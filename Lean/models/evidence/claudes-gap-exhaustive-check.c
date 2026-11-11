/* claudes-gap-exhaustive-check.c -- growgap and movegap of
 * src/claudes-reconstructed-gap.c against the rules of gap_bp-calculator.lean:
 * every text of 0..8 bytes (NUL and non-ASCII included), every gap position
 * and size 0..4, every valid target and every second target (composition),
 * growth by -5, 0, 1, 511, 512, 513, 2000 with an ordinary realloc and with
 * one that always moves the block, repeated growth and movement, both
 * existing-buffer failures (buffer unchanged, FALSE, m_alloc), the all-NULL
 * buffer, both initial failures (fatal, each in a child process) and a
 * request too large for point_t.  Build, from a folder holding the editor's
 * src/*.h and a test copy of the reconstruction:
 *   sed 's/MAX_SIZE_T/test_size_max/g' claudes-reconstructed-gap.c > test-gap.c
 *   cc -std=gnu11 -g -fsanitize=address,undefined -I. claudes-gap-exhaustive-check.c
 * Expected: "18302 checks, 0 failures". */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#include <unistd.h>
#include <sys/wait.h>
static unsigned long test_size_max = ~0UL;
static int fail_alloc, moving_realloc; static size_t old_size;
/* the sizes of the blocks handed out, so a moving realloc copies them whole */
static struct { void *p; size_t n; } blocks[4096];
static void note(void *p,size_t n){for(int i=0;i<4096;i++)if(!blocks[i].p||blocks[i].p==p){blocks[i].p=p;blocks[i].n=n;return;}}
static size_t size_of(void *p){for(int i=0;i<4096;i++)if(blocks[i].p==p)return blocks[i].n;return old_size;}
static void forget(void *p){for(int i=0;i<4096;i++)if(blocks[i].p==p)blocks[i].p=NULL;}
static void release(void *p){forget(p);free(p);}
static void *t_malloc(size_t n){void *q=fail_alloc?NULL:malloc(n);if(q)note(q,n);return q;}
static void *t_realloc(void *p,size_t n){if(fail_alloc)return NULL;
 if(moving_realloc){size_t old=size_of(p);unsigned char *q=malloc(n);if(!q)return NULL;memset(q,0xee,n);memcpy(q,p,old<n?old:n);memset(p,0xdd,old);free(p);forget(p);note(q,n);return q;}
 void *q=realloc(p,n);if(q){forget(p);note(q,n);}return q;}
#define malloc t_malloc
#define realloc t_realloc
#include "test-gap.c"
#undef malloc
#undef realloc
buffer_t *curbp; window_t *curwp;
char *f_alloc="f_alloc",*m_alloc="m_alloc",*m_toobig,*m_badname,*m_open,*m_write,*m_close,*m_stat,*m_saved,*m_loaded;
static const char *message; static jmp_buf fatal_jump;
void msg(char *f,...){message=f;}
void fatal(char *u){(void)u;longjmp(fatal_jump,1);}
int screen_save_file(const char *p){(void)p;return 1;}
const char *screen_backend(void){return "terminal";}
void screen_mvaddstr(int r,int c,const char *s){(void)r;(void)c;(void)s;}
void screen_addstr(const char *s){(void)s;} void screen_clrtoeol(void){}
int screen_rows(void){return 24;}
int yesno(int f){(void)f;return 0;} void delete_mode(buffer_t *b,buffer_flags_t m){b->b_flags&=~m;}
point_t document_size(buffer_t *b){return (b->b_ebuf-b->b_buf)-(b->b_egap-b->b_gap);}
void record_change(buffer_t *b,int k,point_t p,const char_t *t,long n){(void)b;(void)k;(void)p;(void)t;(void)n;}
void zero_buffer(buffer_t *b){(void)b;} void beginning_of_buffer(void){}
static long checks; static int failures;
static void fail(const char *what,int len,int at,int gap,long arg){if(failures++<20)printf("FAIL %s len=%d gap-at=%d gap=%d arg=%ld\n",what,len,at,gap,arg);}
/* a buffer whose text is bytes 1..len (0 included at the middle), the gap at AT of size GAP */
static void make(buffer_t *b,const unsigned char *text,int len,int at,int gap){
 memset(b,0x5a,sizeof *b);size_t cap=len+gap;b->b_buf=malloc(cap?cap:1);memset(b->b_buf,0xcc,cap?cap:1);
 memcpy(b->b_buf,text,at);memcpy(b->b_buf+at+gap,text+at,len-at);
 b->b_gap=b->b_buf+at;b->b_egap=b->b_gap+gap;b->b_ebuf=b->b_buf+cap;}
static int text_is(buffer_t *b,const unsigned char *text,int len){
 int l=b->b_gap-b->b_buf,r=b->b_ebuf-b->b_egap;if(l+r!=len)return 0;
 return !memcmp(b->b_buf,text,l)&&!memcmp(b->b_egap,text+l,r);}
/* every field other than the four pointers is unchanged */
static int others_same(buffer_t *a,buffer_t *b){buffer_t x=*a,y=*b;x.b_buf=x.b_gap=x.b_egap=x.b_ebuf=y.b_buf=y.b_gap=y.b_egap=y.b_ebuf=NULL;return !memcmp(&x,&y,sizeof x);}
int main(void){
 unsigned char text[8]={'a',0,0xc3,0xa9,'\n',0xff,'z','Q'};
 long ns[]={-5,0,1,511,512,513,2000};
 for(int len=0;len<=8;len++)for(int at=0;at<=len;at++)for(int gap=0;gap<=4;gap++){
  /* movegap: every valid target */
  for(int p=0;p<=len;p++){buffer_t b,before;make(&b,text,len,at,gap);before=b;
   point_t r=movegap(&b,p);checks++;
   if(r!=p)fail("move result",len,at,gap,p);
   if(b.b_buf!=before.b_buf||b.b_ebuf!=before.b_ebuf)fail("move allocation",len,at,gap,p);
   if(b.b_gap-b.b_buf!=p||b.b_egap-b.b_gap!=gap)fail("move boundaries",len,at,gap,p);
   if(!text_is(&b,text,len))fail("move text",len,at,gap,p);
   if(!others_same(&b,&before))fail("move other fields",len,at,gap,p);
   /* composition: moving again, then to q, equals moving to q */
   for(int q=0;q<=len;q++){buffer_t c=b;size_t cap=b.b_ebuf-b.b_buf;c.b_buf=malloc(cap?cap:1);memcpy(c.b_buf,b.b_buf,cap);c.b_gap=c.b_buf+(b.b_gap-b.b_buf);c.b_egap=c.b_buf+(b.b_egap-b.b_buf);c.b_ebuf=c.b_buf+cap;movegap(&c,q);checks++;if(c.b_gap-c.b_buf!=q||c.b_egap-c.b_gap!=gap||!text_is(&c,text,len))fail("move compose",len,at,gap,q);release(c.b_buf);}
   release(b.b_buf);}
  /* growgap: every n, ordinary and moving realloc */
  for(int mv=0;mv<=1;mv++)for(unsigned i=0;i<sizeof ns/sizeof *ns;i++){
   buffer_t b,before;make(&b,text,len,at,gap);before=b;moving_realloc=mv;old_size=len+gap;
   long amount=ns[i]<512?512:ns[i];message="";int stopped=setjmp(fatal_jump),r=0;
   if(!stopped)r=growgap(&b,ns[i]);checks++;
   int initial=(len+gap==0);
   if(initial){ /* allocation length zero: malloc, the old 1-byte block is the test's */
    if(stopped||r!=TRUE)fail("grow initial",len,at,gap,ns[i]);}
   else if(stopped||r!=TRUE)fail("grow result",len,at,gap,ns[i]);
   if(b.b_gap-b.b_buf!=at||b.b_egap-b.b_gap!=gap+amount||b.b_ebuf-b.b_buf!=len+gap+amount)fail("grow boundaries",len,at,gap,ns[i]);
   if(!text_is(&b,text,len))fail("grow text",len,at,gap,ns[i]);
   if(!others_same(&b,&before))fail("grow other fields",len,at,gap,ns[i]);
   if(initial)release(before.b_buf);
   /* repeated growth and movement */
   if(!stopped){growgap(&b,1);movegap(&b,len/2);growgap(&b,3);movegap(&b,len);checks++;
    if(!text_is(&b,text,len)||b.b_gap-b.b_buf!=len){fail("grow/move repeated",len,at,gap,ns[i]);if(failures<3)printf("  mv=%d gapat=%ld egap=%ld ebuf=%ld byte0=%d\n",mv,(long)(b.b_gap-b.b_buf),(long)(b.b_egap-b.b_buf),(long)(b.b_ebuf-b.b_buf),b.b_buf[0]);}}
   release(b.b_buf);moving_realloc=0;}
  /* existing buffer, failures: FALSE, m_alloc, buffer exactly as it was */
  if(len+gap>0)for(int why=0;why<2;why++){buffer_t b,before;make(&b,text,len,at,gap);before=b;
   unsigned char saved[16];memcpy(saved,b.b_buf,len+gap);
   if(why==0)test_size_max=len+gap+511;else fail_alloc=1;message="";
   int stopped=setjmp(fatal_jump),r=-1;if(!stopped)r=growgap(&b,1);checks++;
   if(stopped||r!=FALSE||strcmp(message,"m_alloc"))fail(why?"realloc NULL":"existing size rejected",len,at,gap,why);
   if(memcmp(&b,&before,sizeof b)||memcmp(b.b_buf,saved,len+gap))fail("rejected changed the buffer",len,at,gap,why);
   test_size_max=~0UL;fail_alloc=0;release(b.b_buf);}}
 /* the all-NULL buffer */
 {buffer_t b;memset(&b,0,sizeof b);checks++;if(movegap(&b,0)!=0||b.b_buf)fail("NULL move",0,0,0,0);
  if(growgap(&b,-3)!=TRUE||b.b_egap-b.b_gap!=512||b.b_gap!=b.b_buf||b.b_ebuf-b.b_buf!=512)fail("NULL grow",0,0,0,0);release(b.b_buf);}
 /* initial failures are fatal: each in a child process, as the plan asks */
 for(int why=0;why<2;why++){pid_t pid=fork();if(pid==0){buffer_t b;memset(&b,0,sizeof b);
   if(why==0)test_size_max=100;else fail_alloc=1;
   if(setjmp(fatal_jump)){_exit(b.b_buf==NULL?42:1);}growgap(&b,1);_exit(0);}
  int st;waitpid(pid,&st,0);checks++;if(!WIFEXITED(st)||WEXITSTATUS(st)!=42)fail(why?"initial malloc NULL not fatal":"initial size rejected not fatal",0,0,0,why);}
 /* overflow: a request point_t cannot hold is refused, not wrapped */
 {buffer_t b,before;make(&b,text,3,1,1);before=b;message="";int stopped=setjmp(fatal_jump),r=-1;if(!stopped)r=growgap(&b,LONG_MAX);checks++;
  if(stopped||r!=FALSE||memcmp(&b,&before,sizeof b))fail("overflow refused",3,1,1,0);release(b.b_buf);}
 printf("%ld checks, %d failures\n",checks,failures);return failures!=0;}
