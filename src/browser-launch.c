/* C-c d keeps this native editor alive. The browser receives a snapshot;
 * explicit browser saves return through a private temporary file. Changes
 * made concurrently in the native buffer are preserved as a conflict. */
#include "header.h"
#include "system.h"
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>
#include <spawn.h>
#include <errno.h>
#include <time.h>
extern void fe_message(char *);
extern char **environ;
#ifdef __EMSCRIPTEN__
const char *chezweb_launch(void){return "The browser editor is already open. Ask AI in the terminal or SDL window.";}
void chezweb_poll(void){}
#else
extern const char *bridge_install_dir(void);
extern long fe_copy_text(long,long,char *);
extern void fe_delete_region(long,long);
extern void fe_insert_bytes(long,char *,long);
static char session[4096],url[4096],*baseline;
static size_t baseline_len;
static buffer_t *source;
static pid_t server_pid;
static char *snapshot(buffer_t *bp,size_t *n){buffer_t *save=curbp;curbp=bp;*n=(size_t)document_size(bp);char *s=malloc(*n+1);if(s){fe_copy_text(0,(long)*n,s);s[*n]=0;}curbp=save;return s;}
static void cleanup(void){if(server_pid>0){kill(server_pid,SIGTERM);waitpid(server_pid,NULL,0);}if(*session){const char *names[]={"initial","name","pending","pending.new","incoming","ready",NULL};char p[8192];for(int i=0;names[i];i++){snprintf(p,sizeof p,"%s/%s",session,names[i]);unlink(p);}rmdir(session);}free(baseline);baseline=NULL;server_pid=0;*session=0;*url=0;}
static const char *open_chrome(void){
 const char *browser=getenv("CHEZWEB_BROWSER");if(browser&&*browser){char *args[]={url};return sys_spawn_program(browser,args,1);}
#ifdef __APPLE__
 char *args[]={"-a","Google Chrome",url};return sys_spawn_program("/usr/bin/open",args,3);
#else
 char *args[]={url};return sys_spawn_program("google-chrome",args,1);
#endif
}
const char *chezweb_launch(void){
 if(server_pid>0&&waitpid(server_pid,NULL,WNOHANG)==0){const char *e=open_chrome();return e?e:"Browser session reopened; the terminal/SDL window stays active.";}
 cleanup();
 static int registered;if(!registered){atexit(cleanup);registered=1;}
 const char *root=bridge_install_dir();char exe[8192],html[8192];snprintf(exe,sizeof exe,"%s/chezweb-server",root);snprintf(html,sizeof html,"%s/Chezweb.html",root);
 if(access(exe,X_OK)||access(html,R_OK))return "Build the browser editor first: make browser (Emscripten required to build).";
 snprintf(session,sizeof session,"/tmp/chezweb-session-XXXXXX");if(!mkdtemp(session))return "Cannot create a private browser session.";
 source=curbp;baseline=snapshot(source,&baseline_len);char path[8192];snprintf(path,sizeof path,"%s/initial",session);FILE *f=fopen(path,"wb");if(!f||!baseline)return "Cannot write the browser snapshot.";size_t written=fwrite(baseline,1,baseline_len,f);int closed=fclose(f);if(written!=baseline_len||closed)return "Cannot finish the browser snapshot.";
 snprintf(path,sizeof path,"%s/name",session);f=fopen(path,"w");if(f){const char *name=strrchr(source->b_fname,'/');name=name?name+1:source->b_fname;fputs(*name?name:"browser.txt",f);fclose(f);}
 unsigned char random[24];FILE *rng=fopen("/dev/urandom","rb");if(!rng)return "Cannot create browser session token.";size_t got=fread(random,1,sizeof random,rng);fclose(rng);if(got!=sizeof random)return "Cannot create browser session token.";char token[49];for(size_t i=0;i<sizeof random;i++)snprintf(token+i*2,3,"%02x",random[i]);
 char *args[]={exe,(char *)root,session,token,NULL};int rc=posix_spawn(&server_pid,exe,NULL,NULL,args,environ);if(rc){server_pid=0;return "Cannot start the Chezweb loopback server.";}
 snprintf(path,sizeof path,"%s/ready",session);for(int i=0;i<100;i++){FILE *r=fopen(path,"r");if(r){if(fgets(url,sizeof url,r))url[strcspn(url,"\r\n")]=0;fclose(r);break;}struct timespec delay={0,20000000};nanosleep(&delay,NULL);}
 if(!*url)return "The browser server did not become ready.";
 const char *e=open_chrome();return e?e:"Browser editor opened in Chrome. This native window remains available for AI.";
}
void chezweb_poll(void){
 if(!*session)return;char path[8192];snprintf(path,sizeof path,"%s/pending",session);char incoming[8192];snprintf(incoming,sizeof incoming,"%s/incoming",session);if(rename(path,incoming))return;FILE *f=fopen(incoming,"rb");if(!f)return;fseek(f,0,SEEK_END);long n=ftell(f);rewind(f);if(n<0||n>16*1024*1024){fclose(f);return;}char *text=malloc((size_t)n+1);if(!text){fclose(f);return;}size_t got=fread(text,1,(size_t)n,f);fclose(f);if(got!=(size_t)n){free(text);return;}text[n]=0;
 int exists=0;for(buffer_t *b=bheadp;b;b=b->b_next)if(b==source)exists=1;
 size_t current_len=0;char *current=exists?snapshot(source,&current_len):NULL;
 int conflict=!current||current_len!=baseline_len||memcmp(current,baseline,baseline_len)|| (source->b_flags&B_READONLY);
 buffer_t *old=curbp;curbp=source;
 if(conflict){/* A new conflict buffer, never overwrite an earlier one. */char name[64];static unsigned serial;snprintf(name,sizeof name,"*browser-conflict-%u*",++serial);curbp=find_buffer(name,TRUE);}
 fe_delete_region(0,document_size(curbp));fe_insert_bytes(0,text,n);curbp->b_flags|=B_MODIFIED;curbp->b_point=0;
 if(conflict){associate_b2w(curbp,curwp);fe_message("Browser changes kept in a conflict buffer; native edits were preserved.");}else{curbp=old;fe_message("Browser changes imported. C-x C-s saves the file from this native window.");free(baseline);baseline=text;baseline_len=(size_t)n;text=NULL;}
 free(current);free(text);unlink(incoming);
}
#endif
