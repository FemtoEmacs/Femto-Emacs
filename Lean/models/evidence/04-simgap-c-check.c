/* Compare the unchanged gap.c with 04-simgap.lean.
 * Build with -DSIMGAP_SOURCE='"/path/to/test-instrumented-gap.c"'.
 * All filesystem work stays in the disposable directory supplied as argv[1].
 * Test copies replace MAX_SIZE_T with test_size_max to reach its guard branches.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <limits.h>
#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>
#include <setjmp.h>
static unsigned long test_size_max = ULONG_MAX;
static void *test_malloc(size_t);
static void *test_realloc(void *, size_t);
static FILE *test_fopen(const char *, const char *);
static size_t test_fread(void *, size_t, size_t, FILE *);
static size_t test_fwrite(const void *, size_t, size_t, FILE *);
static int test_fclose(FILE *);
static int test_stat(const char *, struct stat *);
static int test_mkdir(const char *, mode_t);
#define malloc test_malloc
#define realloc test_realloc
#define fopen test_fopen
#define fread test_fread
#define fwrite test_fwrite
#define fclose test_fclose
#define stat(path, out) test_stat(path, out)
#define mkdir(path, mode) test_mkdir(path, mode)
#ifndef SIMGAP_SOURCE
#error Supply SIMGAP_SOURCE as the path to the test copy of gap.c.
#endif
#include SIMGAP_SOURCE
#undef malloc
#undef realloc
#undef fopen
#undef fread
#undef fwrite
#undef fclose
#undef stat
#undef mkdir

buffer_t buffers[2], *curbp = &buffers[0];
window_t window, *curwp = &window;
char *f_alloc="f_alloc", *m_alloc="m_alloc", *m_toobig="m_toobig";
char *m_badname="m_badname", *m_open="m_open", *m_write="m_write";
char *m_close="m_close", *m_stat="m_stat", *m_saved="m_saved", *m_loaded="m_loaded";
static int fail_alloc, fail_close, browser, external_ok, answer_yes, callbacks, switch_hook;
static int deny_read, deny_write, advertised_size;
static const char *deny_mkdir;
static size_t read_limit, write_limit;
static FILE *handles[16]; static int alive[16], handle_count;
static const char *message;
static size_t raw_fixture_length;
static jmp_buf fatal_jump;

static void *test_malloc(size_t n) { return fail_alloc ? NULL : malloc(n); }
static void *test_realloc(void *p,size_t n) { return fail_alloc ? NULL : realloc(p,n); }
static FILE *test_fopen(const char *p,const char *mode) {
 if ((!strcmp(mode,"rb") && deny_read) || (!strcmp(mode,"wb") && deny_write)) { errno=EACCES;return NULL; }
 FILE *f=fopen(p,mode);if(f){handles[handle_count]=f;alive[handle_count++]=1;}return f;
}
static size_t test_fread(void *p,size_t size,size_t count,FILE *f) { return fread(p,size,count<read_limit?count:read_limit,f); }
static size_t test_fwrite(const void *p,size_t size,size_t count,FILE *f) { return fwrite(p,size,count<write_limit?count:write_limit,f); }
static int test_fclose(FILE *f) {
 for(int i=0;i<handle_count;i++)if(handles[i]==f && alive[i]){alive[i]=0;break;}
 int result=fclose(f);return fail_close ? EOF : result;
}
static int test_stat(const char *p,struct stat *s) {
 int r=stat(p,s);if(!r && advertised_size>=0 && !strcmp(p,"source"))s->st_size=advertised_size;return r;
}
static int test_mkdir(const char *p,mode_t mode) { if(deny_mkdir && !strcmp(p,deny_mkdir)){errno=EACCES;return -1;}return mkdir(p,mode); }
void msg(char *format,...) {
 if(!strcmp(format,"(No changes need to be saved)"))message="no-changes";
 else if(!strcmp(format,"Save failed; changes are still unsaved. See the browser notice."))message="external-save-failed";
 else if(!strcmp(format,"File saved. See the destination above."))message="browser-saved";
 else message=format;
}
void fatal(char *unused) { (void)unused;longjmp(fatal_jump,1); }
int screen_save_file(const char *p) { (void)p;return !browser || external_ok; }
const char *screen_backend(void) { return browser ? "browser" : "terminal"; }
int screen_rows(void) { return 24; }
void screen_mvaddstr(int r,int c,const char *s) { (void)r;(void)c;(void)s; }
void screen_addstr(const char *s) { (void)s; }
void screen_clrtoeol(void) {}
int yesno(int flag) { (void)flag;return answer_yes; }
void delete_mode(buffer_t *b,buffer_flags_t mode) { b->b_flags &= ~mode; }
point_t document_size(buffer_t *b) { return (b->b_ebuf-b->b_buf)-(b->b_egap-b->b_gap); }
void record_change(buffer_t *b,int kind,point_t p,const char_t *text,long n) {
 (void)b;(void)p;(void)text;
 if((kind=='i' || kind=='d') && n<=0)return;
 callbacks++;if(switch_hook){curbp=&buffers[1];switch_hook=0;}
}
void zero_buffer(buffer_t *b) { b->b_gap=b->b_buf;b->b_egap=b->b_ebuf;b->b_point=0;b->b_mark=-1;record_change(b,'r',0,NULL,0); }
void beginning_of_buffer(void) { curbp->b_point=0;curwp->w_point=0; }
static void make_buffer(buffer_t *b,const char *text,long point,size_t at,size_t room,int flags,int id) {
 size_t n=(id==1 && raw_fixture_length)?raw_fixture_length:strlen(text);if(at>n)at=n;memset(b,0,sizeof *b);
 size_t cap=n+room;b->b_buf=malloc(cap?cap:1);memset(b->b_buf,0xcc,cap);
 memcpy(b->b_buf,text,at);memcpy(b->b_buf+at+room,text+at,n-at);
 b->b_gap=b->b_buf+at;b->b_egap=b->b_gap+room;b->b_ebuf=b->b_buf+cap;
 b->b_point=point;b->b_mark=-1;b->b_flags=flags;b->b_id=id;strcpy(b->b_fname,"doc");
}
static void start(const char *name,const char *text,long point,size_t gap,size_t room,int flags) {
 if(mkdir(name,0700) || chdir(name)){perror(name);exit(2);}
 fail_alloc=fail_close=browser=answer_yes=callbacks=switch_hook=deny_read=deny_write=0;
 external_ok=1;deny_mkdir=NULL;advertised_size=-1;read_limit=write_limit=(size_t)-1;
 test_size_max=ULONG_MAX;message="";handle_count=0;memset(&window,0,sizeof window);
 make_buffer(&buffers[0],text,point,gap,room,flags,1);
 make_buffer(&buffers[1],"q",1,1,3,23,2);curbp=&buffers[0];window.w_bufp=curbp;
}
static void file(const char *name,const char *data) { FILE *f=fopen(name,"wb");if(!f)exit(2);fwrite(data,1,strlen(data),f);fclose(f); }
static void print_bytes(const unsigned char *p,size_t n) { putchar('(');for(size_t i=0;i<n;i++)printf("%s%u",i?" ":"",(unsigned)p[i]);putchar(')'); }
static void report(const char *name,long value,int fatal_result) {
 buffer_t *b=&buffers[0];int live=0;for(int i=0;i<handle_count;i++)live+=alive[i];
 printf("(case \"%s\" (result ",name);if(fatal_result)printf("(fatal \"f_alloc\")");else printf("%ld",value);puts(")");
 printf("  (point %ld) (gap %ld %ld) (capacity %ld) (flags %u)\n",b->b_point,b->b_gap-b->b_buf,b->b_egap-b->b_buf,b->b_ebuf-b->b_buf,(unsigned)b->b_flags);
 printf("  (selected %ld) (current-flags %u) (window-point %ld)\n",(long)(curbp-buffers),(unsigned)curbp->b_flags,window.w_point);
 printf("  (undo %ld %ld %ld %u)\n",b->b_ubuf.u_point,b->b_ubuf.u_gap,b->b_ubuf.u_egap,(unsigned)(unsigned char)b->b_ubuf.u_flags);
 printf("  (text (");for(long i=0;i<document_size(b);i++)printf("%s%u",i?" ":"",(unsigned)*ptr(b,i));printf(")) (live-streams %d)\n",live);
 printf("  (message \"%s\") (callbacks %d)\n  (files",message,callbacks);
 const char *files[]={"bad name","doc","one/doc","one/two/doc","source",NULL};int file_count=0;
 /* Close only for the report flush; keep alive[] for the resource observation. */
 for(int i=0;i<handle_count;i++)if(alive[i])fflush(handles[i]);
 for(int i=0;files[i];i++){struct stat st;if(stat(files[i],&st)||!S_ISREG(st.st_mode))continue;
  unsigned char data[128];FILE *f=fopen(files[i],"rb");size_t n=fread(data,1,sizeof data,f);fclose(f);
  file_count++;printf(" (file \"%s\" ",files[i]);print_bytes(data,n);putchar(')');}
 if(!file_count)putchar(' ');printf(")\n  (directories");const char *dirs[]={".","/","one","one/two",NULL};
 for(int i=0;dirs[i];i++){struct stat st;if(!stat(dirs[i],&st)&&S_ISDIR(st.st_mode))printf(" \"%s\"",dirs[i]);}
 puts("))");
 for(int i=0;i<handle_count;i++)if(alive[i])fclose(handles[i]);
 free(buffers[0].b_buf);free(buffers[1].b_buf);if(chdir(".."))exit(2);
}
#define BASE(name) start(name,"ab\ncd",1,2,3,1)
#define RUN(name,expression) do { long value=0;int stopped=setjmp(fatal_jump);if(!stopped)value=(expression);report(name,value,stopped); } while(0)
int main(int argc,char **argv) {
 if(argc!=2 || chdir(argv[1]))return 2;
 BASE("move-left");RUN("move-left",movegap(curbp,0));
 BASE("move-right");RUN("move-right",movegap(curbp,5));
 BASE("grow");RUN("grow",growgap(curbp,1));
 BASE("initial-allocation-fails");free(curbp->b_buf);memset(curbp,0,sizeof *curbp);curbp->b_buf=malloc(1);curbp->b_gap=curbp->b_egap=curbp->b_ebuf=curbp->b_buf;fail_alloc=1;RUN("initial-allocation-fails",growgap(curbp,1));
 BASE("reallocation-fails");fail_alloc=1;RUN("reallocation-fails",growgap(curbp,1));
 BASE("save");file("doc","old");RUN("save",save_buffer(curbp,"doc"));
 start("save-clean","ab\ncd",1,2,3,0);file("doc","old");RUN("save-clean",save_buffer(curbp,"doc"));
 BASE("save-short-write");file("doc","old");write_limit=2;RUN("save-short-write",save_buffer(curbp,"doc"));
 BASE("save-close-fails");file("doc","old");fail_close=1;RUN("save-close-fails",save_buffer(curbp,"doc"));
 BASE("browser-save-fails");file("doc","old");browser=1;external_ok=0;RUN("browser-save-fails",save_buffer(curbp,"doc"));
 BASE("create-parent");answer_yes=1;RUN("create-parent",save_buffer(curbp,"one/two/doc"));
 BASE("decline-parent");RUN("decline-parent",save_buffer(curbp,"one/doc"));
 start("insert-mask","ab\ncd",1,2,3,22);file("source","XY");RUN("insert-mask",insert_file("source",1));
 BASE("insert-short-read");file("source","XYZ");read_limit=1;RUN("insert-short-read",insert_file("source",0));
 BASE("load-missing");RUN("load-missing",load_file("missing"));
 BASE("load");file("source","XYZ");RUN("load",load_file("source"));
 start("line-two","a\nb\n",1,2,3,1);RUN("line-two",line_to_point(2));
 start("line-three","a\nb\n",1,2,3,1);RUN("line-three",line_to_point(3));
 start("stats","a\nb\n",4,2,3,1);int cur,last;get_line_stats(&cur,&last);report("stats",cur,0);
 /* Deliberately do not run the undefined uninitialized-empty case in C. */
 start("stats-empty-initialized","",0,0,3,1);last=0;get_line_stats(&cur,&last);report("stats-empty-initialized",cur,0);
 BASE("ptr-negative");RUN("ptr-negative",ptr(curbp,-2)-curbp->b_buf);
 BASE("ptr-at-gap");RUN("ptr-at-gap",ptr(curbp,2)-curbp->b_buf);
 BASE("pos-in-gap");RUN("pos-in-gap",pos(curbp,curbp->b_buf+3));
 start("move-empty-gap","ab\ncd",1,2,0,1);RUN("move-empty-gap",movegap(curbp,5));
 BASE("bad-name");RUN("bad-name",save_buffer(curbp,"bad name"));
 BASE("empty-name");RUN("empty-name",save_buffer(curbp,""));
 start("clean-bad-name","ab\ncd",1,2,3,0);strcpy(curbp->b_fname,"bad name");file("bad name","old");RUN("clean-bad-name",save_buffer(curbp,"bad name"));
 BASE("open-write-fails");deny_write=1;RUN("open-write-fails",save_buffer(curbp,"doc"));
 start("open-read-fails-after-growth","ab\ncd",1,2,0,1);file("source","XYZ");deny_read=1;RUN("open-read-fails-after-growth",insert_file("source",1));
 BASE("mkdir-fails");answer_yes=1;deny_mkdir="one";RUN("mkdir-fails",save_buffer(curbp,"one/doc"));
 BASE("insert-too-big");file("source","XYZ");test_size_max=2;RUN("insert-too-big",insert_file("source",1));
 start("insert-close-fails","ab\ncd",1,2,3,22);file("source","XY");fail_close=1;RUN("insert-close-fails",insert_file("source",1));
 BASE("insert-empty");file("source","");RUN("insert-empty",insert_file("source",1));
 BASE("load-close-fails");file("source","XYZ");fail_close=1;RUN("load-close-fails",load_file("source"));
 start("stats-aliased","a\nb\n",0,2,3,1);get_line_stats(&cur,&cur);report("stats-aliased",cur,0);
 start("stats-empty-aliased","",0,0,3,1);get_line_stats(&cur,&cur);report("stats-empty-aliased",cur,0);
 BASE("name-policy");RUN("name-policy",posix_file("a-b/c.txt")&&!posix_file("_hidden")&&!posix_file("bad name")&&!posix_file("C:\\a")&&posix_file("a\0 "));
 start("callback-switch-on-insert","ab\ncd",1,2,3,22);file("source","XY");switch_hook=1;RUN("callback-switch-on-insert",insert_file("source",1));
 start("callback-switch-on-clear","ab\ncd",1,2,3,22);switch_hook=1;clear_buffer();report("callback-switch-on-clear",1,0);
 BASE("mkdir-partial-fails");answer_yes=1;deny_mkdir="one/two";RUN("mkdir-partial-fails",save_buffer(curbp,"one/two/doc"));
 BASE("insert-raced-short");file("source","XYZ");advertised_size=6;RUN("insert-raced-short",insert_file("source",1));
 const char binary[]={'A',0,(char)195,(char)169,(char)240,(char)159,(char)153,(char)130};
 raw_fixture_length=sizeof binary;start("binary-save",binary,1,3,3,1);raw_fixture_length=0;
 file("doc","old");RUN("binary-save",save_buffer(curbp,"doc"));
 BASE("binary-insert");unsigned char raw[]={88,0,89,255};FILE *raw_file=fopen("source","wb");fwrite(raw,1,sizeof raw,raw_file);fclose(raw_file);
 RUN("binary-insert",insert_file("source",1));
 return 0;
}
