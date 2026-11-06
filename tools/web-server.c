/* Loopback static server, one temporary buffer hand-off, and your settings
 * and compiled scripts (the .scm files of ~/.chezemax and its chezemax.wasm,
 * read-only).  No shell, directory traversal, arbitrary
 * filesystem API, assistant or credentials. */
#define _POSIX_C_SOURCE 200809L
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/time.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <strings.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <time.h>
#define LIMIT (16*1024*1024)
static int sendall(int fd,const void *p,size_t n){while(n){ssize_t k=send(fd,p,n,0);if(k<0&&errno==EINTR)continue;if(k<=0)return 0;p=(const char*)p+k;n-=k;}return 1;}
static void reply(int fd,int status,const char *type,const void *data,size_t len){char h[1024];int n=snprintf(h,sizeof h,"HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %zu\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n",status,status==200?"OK":"Rejected",type,len);sendall(fd,h,(size_t)n);sendall(fd,data,len);}
static void file(int fd,const char *p,const char *type){FILE *f=fopen(p,"rb");if(!f){reply(fd,404,"text/plain","Not found",9);return;}fseek(f,0,SEEK_END);long n=ftell(f);rewind(f);if(n<0||n>64*1024*1024){fclose(f);reply(fd,413,"text/plain","Too large",9);return;}char *b=malloc((size_t)n+1);if(!b){fclose(f);return;}size_t got=fread(b,1,(size_t)n,f);fclose(f);reply(fd,200,type,b,got);free(b);}
static char *header(char *h,const char *name){size_t n=strlen(name);for(char *p=strstr(h,"\r\n");p;p=strstr(p+2,"\r\n")){p+=2;if(!strncasecmp(p,name,n)&&p[n]==':'){p+=n+1;while(*p==' ')p++;return p; }p-=2;}return NULL;}
static int equalheader(char *p,const char *v){return p&&!strncmp(p,v,strlen(v))&&p[strlen(v)]=='\r';}

/* Your settings, read-only: the .scm files of ~/.chezemax/languages and
 * ~/.chezemax/extensions, and ~/.chezemax/init.scm, the files the
 * native editor loads at start-up (compiled/start.scm).  Read again at each
 * request, so C-x C-r in the browser sees what you saved in either window.
 * Nothing else under your home folder is read, and nothing is written.
 * The bundle: "CHEZWEB-SETTINGS 1\n", then for each file its name relative
 * to ~/.chezemax, a newline, its length in bytes, a newline, its bytes. */
typedef struct { char *data; size_t len, cap; } growing;
static int add(growing *g,const void *p,size_t n){if(g->len+n>8*1024*1024)return 0;if(g->len+n>g->cap){size_t c=g->cap?g->cap:65536;while(c<g->len+n)c*=2;char *d=realloc(g->data,c);if(!d)return 0;g->data=d;g->cap=c;}memcpy(g->data+g->len,p,n);g->len+=n;return 1;}
static int scheme_name(const char *n){size_t k=strlen(n);return n[0]!='.'&&k>4&&!strcmp(n+k-4,".scm")&&!strchr(n,'\n');}
static int by_name(const void *a,const void *b){return strcmp(*(char *const*)a,*(char *const*)b);}
static void add_file(growing *g,const char *base,const char *rel){
 char p[8192];snprintf(p,sizeof p,"%s/%s",base,rel);struct stat st;
 if(stat(p,&st)||!S_ISREG(st.st_mode)||st.st_size>1024*1024)return;
 FILE *f=fopen(p,"rb");if(!f)return;char *b=malloc((size_t)st.st_size+1);size_t n=b?fread(b,1,(size_t)st.st_size,f):0;fclose(f);
 if(b&&n==(size_t)st.st_size){char h[8300];int k=snprintf(h,sizeof h,"%s\n%zu\n",rel,n);if(add(g,h,(size_t)k))add(g,b,n);}free(b);}
static void add_folder(growing *g,const char *base,const char *folder){
 char p[8192];snprintf(p,sizeof p,"%s/%s",base,folder);DIR *d=opendir(p);if(!d)return;
 char *names[512];int count=0;struct dirent *e;
 while((e=readdir(d))&&count<512){if(scheme_name(e->d_name))names[count++]=strdup(e->d_name);}
 closedir(d);
 qsort(names,(size_t)count,sizeof *names,by_name);
 for(int i=0;i<count;i++){char rel[8192];snprintf(rel,sizeof rel,"%s/%s",folder,names[i]);add_file(g,base,rel);free(names[i]);}}
static void settings(int fd){
 const char *home=getenv("HOME");char base[4096];growing g={0};
 add(&g,"CHEZWEB-SETTINGS 1\n",19);
 if(home&&*home){snprintf(base,sizeof base,"%s/.chezemax",home);add_folder(&g,base,"languages");add_folder(&g,base,"extensions");add_file(&g,base,"init.scm");}
 reply(fd,200,"application/octet-stream",g.data?g.data:"",g.len);free(g.data);}

/* Your compiled scripts (chezemax --compile-scripts), read-only: the
 * program in ~/.chezemax/chezemax.wasm, with X-Chezweb-Program: current
 * when it is not older than Chezweb's own (ROOT/chezemax.wasm), older
 * otherwise (then without its bytes).  The page puts it in the browser's
 * ~/.chezemax, where the editor's start-up (compiled-program.c) chooses
 * between the two exactly as in the terminal. */
static void program(int fd,const char *root){
 const char *home=getenv("HOME");char yours[4096],installed[4096];struct stat a,b;
 if(!home||!*home){reply(fd,404,"text/plain","Not found",9);return;}
 snprintf(yours,sizeof yours,"%s/.chezemax/chezemax.wasm",home);snprintf(installed,sizeof installed,"%s/chezemax.wasm",root);
 if(stat(yours,&a)||!S_ISREG(a.st_mode)||a.st_size>64*1024*1024){reply(fd,404,"text/plain","Not found",9);return;}
 int older=stat(installed,&b)==0&&a.st_mtime<b.st_mtime;
 FILE *f=older?NULL:fopen(yours,"rb");char *data=NULL;size_t n=0;
 if(!older){if(!f){reply(fd,404,"text/plain","Not found",9);return;}data=malloc((size_t)a.st_size+1);n=data?fread(data,1,(size_t)a.st_size,f):0;fclose(f);if(!data||n!=(size_t)a.st_size){free(data);reply(fd,500,"text/plain","Read failed",11);return;}}
 char h[512];int k=snprintf(h,sizeof h,"HTTP/1.1 200 OK\r\nContent-Type: application/wasm\r\nX-Chezweb-Program: %s\r\nContent-Length: %zu\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n",older?"older":"current",n);
 sendall(fd,h,(size_t)k);if(n)sendall(fd,data,n);free(data);}
/* A native save receipt, unlike PUT session, confirms the real disk write. */
static void save_response(int fd,int status,unsigned long long revision,const char *message){
 char h[512];size_t len=strlen(message);int n=snprintf(h,sizeof h,"HTTP/1.1 %d %s\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: %zu\r\nX-Chezweb-Revision: %llu\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n",status,status==200?"OK":"Rejected",len,revision);
 sendall(fd,h,(size_t)n);sendall(fd,message,len);
}
static void snapshot_response(int fd,const char *dir){
 char path[8192],head[64];snprintf(path,sizeof path,"%s/snapshot",dir);FILE *f=fopen(path,"rb");
 if(!f){reply(fd,404,"text/plain","Not found",9);return;}
 unsigned long long revision;char tail;
 if(!fgets(head,sizeof head,f)||sscanf(head,"%llu %c",&revision,&tail)!=1){fclose(f);reply(fd,500,"text/plain","Invalid snapshot",16);return;}
 long offset=ftell(f);fseek(f,0,SEEK_END);long len=ftell(f)-offset;fseek(f,offset,SEEK_SET);
 char *text=len>=0&&len<=LIMIT?malloc((size_t)len+1):NULL;
 int ok=text&&fread(text,1,(size_t)len,f)==(size_t)len;fclose(f);
 if(!ok){free(text);reply(fd,500,"text/plain","Snapshot read failed",20);return;}
 char h[512];int n=snprintf(h,sizeof h,"HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: %ld\r\nX-Chezweb-Revision: %llu\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",len,revision);sendall(fd,h,(size_t)n);sendall(fd,text,(size_t)len);free(text);
}
static void commit_request(int fd,const char *dir,const char *body,size_t len,unsigned long long revision){
 static unsigned long long sequence;unsigned long long id=++sequence;
 char temp[8192],path[8192];snprintf(temp,sizeof temp,"%s/save.pending.new",dir);snprintf(path,sizeof path,"%s/save.pending",dir);
 FILE *f=fopen(temp,"wb");int ok=f&&fprintf(f,"%llu\n%llu\n",id,revision)>0&&fwrite(body,1,len,f)==len;
 if(f&&fclose(f))ok=0;if(ok)ok=!rename(temp,path);
 if(!ok){unlink(temp);reply(fd,500,"text/plain","Save request failed",19);return;}
 snprintf(temp,sizeof temp,"%s/save.result",dir);
 for(int i=0;i<500;i++){
  f=fopen(temp,"rb");if(f){unsigned long long got,version;int status;char message[4608];
   if(fscanf(f,"%llu\n%d\n%llu\n",&got,&status,&version)==3&&got==id){size_t n=fread(message,1,sizeof message-1,f);message[n]=0;fclose(f);unlink(temp);
    if(status!=200&&status!=409&&status!=413&&status!=422&&status!=500)status=500;
    save_response(fd,status,version,message);return;
   }fclose(f);
  }
  struct timespec pause={0,20000000};nanosleep(&pause,NULL);
 }
 const char *message="Save not confirmed. Close any native prompt and retry; your browser changes remain unsaved.";
 unlink(path);reply(fd,503,"text/plain",message,strlen(message));
}

int main(int argc,char **argv){
 if(argc!=4)return 2;const char *root=argv[1],*dir=argv[2],*token=argv[3];signal(SIGPIPE,SIG_IGN);
 int s=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in a={0};a.sin_family=AF_INET;inet_pton(AF_INET,"127.0.0.1",&a.sin_addr);
 if(s<0||bind(s,(void*)&a,sizeof a)||listen(s,8))return 2;socklen_t alen=sizeof a;getsockname(s,(void*)&a,&alen);
 char origin[128],host[128],prefix[128],path[8192];snprintf(host,sizeof host,"127.0.0.1:%u",ntohs(a.sin_port));snprintf(origin,sizeof origin,"http://%s",host);snprintf(prefix,sizeof prefix,"/%s/",token);
 snprintf(path,sizeof path,"%s/ready",dir);FILE *ready=fopen(path,"w");if(!ready)return 2;fprintf(ready,"%s%s\n",origin,prefix);fclose(ready);
 for(;;){int c=accept(s,NULL,NULL);if(c<0){if(errno==EINTR)continue;break;}struct timeval timeout={5,0};setsockopt(c,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof timeout);setsockopt(c,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof timeout);
 char h[16385];size_t used=0;char *end=NULL;while(used<sizeof(h)-1){ssize_t n=recv(c,h+used,sizeof(h)-1-used,0);if(n<=0)break;used+=(size_t)n;h[used]=0;if((end=strstr(h,"\r\n\r\n")))break;}
 char method[16],url[4096];if(!end||sscanf(h,"%15s %4095s",method,url)!=2){close(c);continue;}
 char *o=header(h,"Origin");if(!equalheader(header(h,"Host"),host)||(o&&!equalheader(o,origin))||strncmp(url,prefix,strlen(prefix))){reply(c,403,"text/plain","Forbidden",9);close(c);continue;}
 const char *name=url+strlen(prefix);
 if(!strcmp(method,"GET")){
  if(!strcmp(name,"snapshot")){snapshot_response(c,dir);}
  else if(!strcmp(name,"target")){snprintf(path,sizeof path,"%s/target",dir);file(c,path,"text/plain; charset=utf-8");}
  else if(!strcmp(name,"name")){snprintf(path,sizeof path,"%s/name",dir);file(c,path,"text/plain; charset=utf-8");}
  else if(!strcmp(name,"session")){snprintf(path,sizeof path,"%s/initial",dir);file(c,path,"text/plain; charset=utf-8");}
  else if(!strcmp(name,"settings"))settings(c);
  else if(!strcmp(name,"program"))program(c,root);
  else if(!*name||!strcmp(name,"Chezweb.html")){snprintf(path,sizeof path,"%s/Chezweb.html",root);file(c,path,"text/html; charset=utf-8");}
  else if(!strcmp(name,"build/chezweb.js")||!strcmp(name,"build/chezweb.wasm")){snprintf(path,sizeof path,"%s/%s",root,name);file(c,path,strstr(name,".wasm")?"application/wasm":"text/javascript");}
  else reply(c,404,"text/plain","Not found",9);
 }else if(!strcmp(method,"POST")&&!strcmp(name,"refresh")&&o&&equalheader(header(h,"Content-Type"),"application/x-chezweb-refresh")){
  snprintf(path,sizeof path,"%s/refresh",dir);FILE *f=fopen(path,"wb");int ok=f!=NULL;if(f&&fclose(f))ok=0;reply(c,ok?200:500,"text/plain",ok?"Refresh requested":"Refresh failed",ok?17:14);
 }else if(!strcmp(method,"PUT")&&(!strcmp(name,"session")||!strcmp(name,"save"))&&equalheader(header(h,"Content-Type"),"application/x-chezweb-text")&&o){
  char *length=header(h,"Content-Length"),*stop=NULL;long n=length?strtol(length,&stop,10):-1;
  if(n<0||n>LIMIT||!stop||*stop!='\r'||header(h,"Transfer-Encoding")){reply(c,400,"text/plain","Invalid length",14);close(c);continue;}
  char *body=malloc((size_t)n+1);if(!body){reply(c,500,"text/plain","Out of memory",13);close(c);continue;}size_t got=used-(size_t)(end+4-h);if(got>(size_t)n)got=(size_t)n;memcpy(body,end+4,got);
  while(got<(size_t)n){ssize_t k=recv(c,body+got,(size_t)n-got,0);if(k<=0)break;got+=(size_t)k;}
  if(!strcmp(name,"save")){
   char *v=header(h,"X-Chezweb-Revision"),*last=NULL;errno=0;unsigned long long revision=v?strtoull(v,&last,10):0;
   if(got!=(size_t)n||!v||*v<'0'||*v>'9'||errno||!last||*last!='\r')reply(c,400,"text/plain","Missing document revision",25);
   else commit_request(c,dir,body,got,revision);
   free(body);close(c);continue;
  }
  int ok=got==(size_t)n;snprintf(path,sizeof path,"%s/pending.new",dir);FILE *f=ok?fopen(path,"wb"):NULL;if(f){ok=fwrite(body,1,got,f)==got;if(fclose(f))ok=0;}else ok=0;
  if(ok){char dest[8192];snprintf(dest,sizeof dest,"%s/pending",dir);ok=rename(path,dest)==0;if(ok){snprintf(dest,sizeof dest,"%s/initial",dir);FILE *initial=fopen(dest,"wb");if(initial){fwrite(body,1,got,initial);fclose(initial);}}}free(body);reply(c,ok?200:500,"text/plain",ok?"Imported on next native key":"Save failed",ok?27:11);
 }else reply(c,405,"text/plain","Unsupported",11);
 close(c);
 }
 close(s);return 0;
}
