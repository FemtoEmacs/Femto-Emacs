#include "../src/header.h"
#include <emscripten.h>
#include <errno.h>
#include <spawn.h>
#include <stdlib.h>
extern int app_main(int,char **);
EM_JS(void,web_ended,(),{Module.browsered.ended();});
EM_JS(char *,web_initial_file,(),{return stringToNewUTF8(Module.chezwebSessionPath);});
EM_JS(int,web_initial_modified,(),{return Module.chezwebInitialModified ? 1 : 0;});
int main(void){char *path=web_initial_file();char *argv[]={"/chezweb",path,NULL};int r=app_main(2,argv);web_ended();return r;}
int posix_spawnp(pid_t *p,const char *f,const posix_spawn_file_actions_t *a,const posix_spawnattr_t *b,char *const v[],char *const e[]){(void)p;(void)f;(void)a;(void)b;(void)v;(void)e;return ENOSYS;}

/* Give the shared C/Scheme prompts access to explicitly granted Chrome
 * folders before their ordinary completion or file-open operation runs.
 * JSPI suspends through the compiled Scheme frames while this awaits. */
#include <string.h>
static int filename_prompt;
EM_ASYNC_JS(int,web_prepare_filename,(const char *path,int partial),{
 return (await ChezwebFiles.prepare(UTF8ToString(path),!!partial))?1:0;
});
extern int __real_getfilename(char *,char *,int);
extern int __real_getfilename_default(char *,char *,int);
extern int __real_line_edit(char *,char *,int,int,int (*)(char *,int,int,int));
extern int __real_call_lisp_event(char *,char *);
int __wrap_getfilename(char *prompt,char *buf,int n){filename_prompt++;int r=__real_getfilename(prompt,buf,n);filename_prompt--;return r;}
int __wrap_getfilename_default(char *prompt,char *buf,int n){filename_prompt++;int r=__real_getfilename_default(prompt,buf,n);filename_prompt--;return r;}
int __wrap_line_edit(char *prompt,char *buf,int n,int flags,int (*complete)(char *,int,int,int)){
 int r=__real_line_edit(prompt,buf,n,flags,complete);
 if(r&&filename_prompt&&!web_prepare_filename(buf,0))return 0;
 return r;
}
int __wrap_call_lisp_event(char *kind,char *arg){
 /* The virtual snapshot may contain native edits not yet saved to disk. */
 if(!strcmp(kind,"startup")&&web_initial_modified())curbp->b_flags|=B_MODIFIED;
 if(filename_prompt&&!strcmp(kind,"complete-file"))web_prepare_filename(arg,1);
 return __real_call_lisp_event(kind,arg);
}

EM_ASYNC_JS(char *,chezweb_shell_run,(const char *command,const char *directory,int *status,char **cwd),{
 var result=await ChezwebShell.run(UTF8ToString(command),UTF8ToString(directory));
 var cwdText=stringToNewUTF8(result.directory),output=stringToNewUTF8(result.output);
 HEAP32[status>>2]=result.status;HEAPU32[cwd>>2]=cwdText;return output;
});
EM_ASYNC_JS(char *,chezweb_web_request,(const char *name,const char *arg),{
 return stringToNewUTF8(await ChezwebShell.request(UTF8ToString(name),UTF8ToString(arg)));
});
