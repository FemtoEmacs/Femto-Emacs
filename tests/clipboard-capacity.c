/* A clipboard allocation must shrink even if realloc refuses to do so. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "screen.h"
static struct { void *p; size_t n; } blocks[32];
static size_t largest;
static int slot(void *p) { for (int i=0;i<32;i++) if(blocks[i].p==p) return i; abort(); }
void *clip_test_malloc(size_t n) {
 if(n>largest) largest=n; void *p=malloc(n); assert(p);
 for(int i=0;i<32;i++) if(!blocks[i].p) { blocks[i].p=p;blocks[i].n=n;return p; }
 abort();
}
void *clip_test_realloc(void *p,size_t n) {
 if(!p) return clip_test_malloc(n);
 if(n>largest) largest=n; int i=slot(p); if(n<=blocks[i].n) return p; /* legal allocator behavior */
 void *q=realloc(p,n);assert(q);blocks[i].p=q;blocks[i].n=n;return q;
}
void clip_test_free(void *p) { if(p) { int i=slot(p);blocks[i].p=NULL;free(p); } }
#ifdef __CYGWIN__
#include "system.h"
/* Exercise the no-fork branch on every host; process launching itself is
 * covered by Windows integration tests. This fake never starts a process. */
static int launches;
const char *sys_run_program(const char *program, char *const *args, int nargs,
 const char *input, size_t input_len, long timeout, const char *directory, sys_run_result *r) {
 (void)input;(void)input_len;(void)timeout;(void)directory;
 assert(!strcmp(program,"/bin/sh") && nargs==2 && !strcmp(args[0],"-c"));
 memset(r,0,sizeof *r);launches++;
 size_t n=0;FILE *f=NULL;
 if(!strstr(args[1],"command -v")) {
  f=fopen(getenv("CLIPBOARD_TEST_TEXT"),"rb");assert(f);
  assert(!fseek(f,0,SEEK_END));n=(size_t)ftell(f);rewind(f);
 }
 r->out=clip_test_malloc(n+1);r->out_len=n;
 if(f) {assert(fread(r->out,1,n,f)==n);fclose(f);}
 r->out[n]=0;r->err=clip_test_malloc(1);r->err[0]=0;
 return NULL;
}
void sys_run_result_free(sys_run_result *r) {clip_test_free(r->out);clip_test_free(r->err);}
#endif
int main(void) {

 size_t n=0;int same=0;
 char *s=screen_get_clipboard_unless(NULL,0,&n,&same);
 assert(s && !same && n==1024*1024+17);
 for(size_t i=0;i<n;i++) assert(s[i]=='x');
 assert(s[n]==0);
 assert(largest <= n+n/8+4096); /* bounded large-buffer growth */
 assert(blocks[slot(s)].n==n+1); /* no retained doubling capacity */
 size_t m=0;char *other=screen_get_clipboard_unless(s,n,&m,&same);
 assert(!other && same);
#ifdef __CYGWIN__
 assert(launches>=3);
#endif
 clip_test_free(s);
 FILE *f=fopen(getenv("CLIPBOARD_TEST_TEXT"),"wb");assert(f);
 const char raw[]={'a','\r','\n','b','\r','c',0,'d'};
 const char expected[]={'a','\n','b','\n','c',0,'d'};
 assert(fwrite(raw,1,sizeof raw,f)==sizeof raw);fclose(f);
 s=screen_get_clipboard_unless(NULL,0,&n,&same);
 assert(s && n==sizeof expected && !memcmp(s,expected,n));
 other=screen_get_clipboard_unless(s,n,&m,&same);
 if(other) {assert(m==n && !memcmp(other,s,n));clip_test_free(other);} else assert(same);clip_test_free(s);
 for(int i=0;i<32;i++) assert(!blocks[i].p);
 puts("PASS clipboard: exact retained capacity with nonshrinking realloc; identical copy not duplicated");
 return 0;
}
