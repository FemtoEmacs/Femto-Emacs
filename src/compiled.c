/* Native compiled Scheme bridge. Legacy editor objects stay in femtoscheme;
 * compatible Scheme executes in Wasmtime. No shell is used for compilation. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include "llt/llt.h"
#include "flisp.h"
#include "../schemer/native-host.h"
#ifdef __CYGWIN__
#include "process-windows.h"
#endif
#ifdef _WIN32
#include <windows.h>
#include <process.h>
#else
#include <spawn.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>
extern char **environ;
#endif
static unsigned compiled_count, executed_count, callback_count;
typedef struct module {int id;sc_module *wasm;struct module *next;} module;
typedef struct cache {char *request;unsigned char *bytes;size_t size;struct cache *next;} cache;
static module *modules;static cache *cache_head;static int next_id;
static char *readfile(const char *path,size_t *size){FILE *f=fopen(path,"rb");if(!f)return NULL;char *s=NULL;size_t cap=0,n=0;char b[8192];size_t k;while((k=fread(b,1,sizeof b,f))){if(n+k+1>cap){cap=(n+k+1)*2;s=realloc(s,cap);if(!s)abort();}memcpy(s+n,b,k);n+=k;}int bad=ferror(f);fclose(f);if(bad){free(s);return NULL;}if(!s)s=malloc(1);s[n]=0;if(size)*size=n;return s;}
static char *editor_request(const char *text,void *user){(void)user;callback_count++;value_t s=cvalue_static_cstring(text);value_t result=fl_applyn(1,symbol_value(symbol("schemer-editor-request")),s);return strdup(cvalue_data(result));}
static value_t response(int ok,const char *value,const char *output,int id){value_t r=FL_NIL;fl_gc_handle(&r);r=fl_cons(fixnum(id),r);r=fl_cons(string_from_cstr(output?output:""),r);r=fl_cons(string_from_cstr(value?value:""),r);r=fl_cons(ok?FL_T:FL_F,r);fl_free_gc_handles(1);return r;}
static int compile_request(const char *request,unsigned char **bytes,size_t *size,char **error){
 value_t install=symbol_value(symbol("*install-dir*"));char *root=strdup(install==UNBOUND?".":cvalue_data(install));
 char dir[4096],input[4096],output[4096],log[4096],exe[4096];
#ifdef _WIN32
 char temp[MAX_PATH];GetTempPathA(sizeof temp,temp);snprintf(dir,sizeof dir,"%schezemax-compiled-%lu-%u",temp,(unsigned long)GetCurrentProcessId(),++next_id);if(!CreateDirectoryA(dir,NULL)){free(root);*error=strdup("Cannot create private compiler directory");return 0;}
#else
 snprintf(dir,sizeof dir,"/tmp/chezemax-compiled-XXXXXX");if(!mkdtemp(dir)){free(root);*error=strdup("Cannot create private compiler directory");return 0;}
#endif
 snprintf(input,sizeof input,"%s/request.scm",dir);snprintf(output,sizeof output,"%s/module.wasm",dir);snprintf(log,sizeof log,"%s/compiler.log",dir);
 snprintf(exe,sizeof exe,"%s/schemer-compile%s",root,
#ifdef _WIN32
 ".exe"
#else
 ""
#endif
 );
 FILE *f=fopen(input,"wb");int ok=f!=NULL;if(f){ok=fwrite(request,1,strlen(request),f)==strlen(request);if(fclose(f))ok=0;}
 if(ok){
#ifdef __CYGWIN__
  /* Cygwin spawn can map a PID page inside Wasmtime's reserved memory.
   * Start a fresh process through the same native helper as run-program. */
  char *argv[]={exe,input,output,root,NULL};win_process child=NULL;
  const char *why=win_process_start(exe,argv,NULL,NULL,log,log,&child);
  int status=-1;ok=!why && win_process_wait(child,-1,&status)==1 && status==0;
  if(child)win_process_close(child);
  if(why){FILE *f=fopen(log,"wb");if(f){fputs(why,f);fclose(f);}}
#elif defined(_WIN32)
  /* The CRT launcher needs quoted arguments when installation paths contain spaces. */
  char qexe[8192],qin[8192],qout[8192],qroot[8192];snprintf(qexe,sizeof qexe,"\"%s\"",exe);snprintf(qin,sizeof qin,"\"%s\"",input);snprintf(qout,sizeof qout,"\"%s\"",output);snprintf(qroot,sizeof qroot,"\"%s\"",root);const char *argv[]={qexe,qin,qout,qroot,NULL};ok=_spawnv(_P_WAIT,exe,argv)==0;
#else
  posix_spawn_file_actions_t actions;posix_spawn_file_actions_init(&actions);posix_spawn_file_actions_addopen(&actions,1,log,O_WRONLY|O_CREAT|O_TRUNC,0600);posix_spawn_file_actions_adddup2(&actions,1,2);
  char *argv[]={exe,input,output,root,NULL};pid_t pid;int rc=posix_spawn(&pid,exe,&actions,NULL,argv,environ);posix_spawn_file_actions_destroy(&actions);
  int status=0;if(!rc){while(waitpid(pid,&status,0)<0){if(errno!=EINTR){rc=-1;break;}}}ok=!rc&&WIFEXITED(status)&&WEXITSTATUS(status)==0;
#endif
 }
 if(ok){*bytes=(unsigned char*)readfile(output,size);ok=*bytes!=NULL;}
 if(!ok){*error=readfile(log,NULL);if(!*error||!**error){free(*error);*error=strdup("Compiled Scheme compiler failed; build schemer-compile and keep schemer/compiler.wasm beside the editor");}}
 remove(input);remove(output);remove(log);
#ifdef _WIN32
 RemoveDirectoryA(dir);
#else
 rmdir(dir);
#endif
 free(root);return ok;
}
static value_t native_run(value_t *args,uint32_t n){
 argcount("native-schemer-run",n,2);char *request=strdup(tostring(args[0],"native-schemer-run"));int keep=args[1]!=FL_F;
 cache *c;for(c=cache_head;c&&strcmp(c->request,request);c=c->next){}
 char *error=NULL,*value=NULL,*output=NULL;if(!c){c=calloc(1,sizeof *c);c->request=request;if(!compile_request(request,&c->bytes,&c->size,&error)){value_t r=response(0,error,"",0);free(error);free(c->request);free(c);return r;}c->next=cache_head;cache_head=c;compiled_count++;}else free(request);
 sc_module *m=sc_module_open(c->bytes,c->size,editor_request,NULL,&error);int ok=m&&sc_module_run(m,0,&value,&output,&error);int id=0;
 if(ok){executed_count++;if(keep){module *p=calloc(1,sizeof *p);p->id=id=++next_id;p->wasm=m;p->next=modules;modules=p;m=NULL;}}
 value_t r=response(ok,ok?value:error,output,id);sc_module_close(m);free(error);free(value);free(output);return r;
}
static value_t native_invoke(value_t *args,uint32_t n){argcount("native-schemer-invoke",n,1);int id=tofixnum(args[0],"native-schemer-invoke");module *p;for(p=modules;p&&p->id!=id;p=p->next){}if(!p)return response(0,"Compiled procedure is no longer available","",0);char *error=NULL,*value=NULL,*output=NULL;int ok=sc_module_run(p->wasm,1,&value,&output,&error);if(ok)executed_count++;value_t r=response(ok,ok?value:error,output,id);free(error);free(value);free(output);return r;}
static value_t native_status(value_t *args,uint32_t n){(void)args;argcount("native-schemer-status",n,0);char s[256];snprintf(s,sizeof s,"Wasmtime / Schemer WasmGC: %u compilations, %u executions, %u editor callbacks",compiled_count,executed_count,callback_count);return string_from_cstr(s);}
static void cleanup(void){while(modules){module *p=modules;modules=p->next;sc_module_close(p->wasm);free(p);}while(cache_head){cache *p=cache_head;cache_head=p->next;free(p->request);free(p->bytes);free(p);}}
void compiled_init(void){static builtinspec_t api[]={{"native-schemer-run",native_run},{"native-schemer-invoke",native_invoke},{"native-schemer-status",native_status},{NULL,NULL}};assign_global_builtins(api);atexit(cleanup);}
