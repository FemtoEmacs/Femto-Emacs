/* Verify Save As defaults and its real completion callback without disk writes. */
#include "header.h"
extern int getfilename_default(char *,char *,int);
static char initial[PATH_MAX];
static int tab_mode, completions_called, command_mode;
void msg(char *format,...){(void)format;}
int call_lisp_event(char *kind,char *prefix){
 if(command_mode){assert(!strcmp(kind,"complete-command"));assert(!strcmp(prefix,"cat foo"));fe_set_completions("cat foo\\ bar");return 1;}
 assert(!strcmp(kind,"complete-file"));assert(!strcmp(prefix,"~/new-f"));
 completions_called++;fe_set_completions("~/new-file.scm");return 1;
}
int line_edit(char *prompt,char *buf,int size,int flag,int (*complete)(char *,int,int,int)){
 (void)prompt;if(flag==F_CLEAR)buf[0]=0;snprintf(initial,sizeof initial,"%s",buf);
 assert(complete!=NULL);
 if(!tab_mode)return FALSE;
 snprintf(buf,size,"%s",command_mode?"cat foo":"~/new-f");complete(buf,size,(int)strlen(buf),0);return TRUE;
}
int main(void){
 char old[PATH_MAX],temp[]="/tmp/chezemax-saveas-XXXXXX",home[PATH_MAX],buf[PATH_MAX],expected[PATH_MAX];
 assert(getcwd(old,sizeof old));assert(mkdtemp(temp));assert(!chdir(temp));assert(getcwd(home,sizeof home));assert(!setenv("HOME",home,1));
 buf[0]=0;assert(!getfilename_default("Save: ",buf,sizeof buf));assert(!strcmp(initial,"~/"));
 snprintf(buf,sizeof buf,"old.scm");assert(!getfilename_default("Save: ",buf,sizeof buf));assert(!strcmp(initial,"~/old.scm"));
 snprintf(buf,sizeof buf,"%s/old.scm",home);assert(!getfilename_default("Save: ",buf,sizeof buf));assert(!strcmp(initial,"~/old.scm"));
 tab_mode=1;assert(getfilename_default("Save: ",buf,sizeof buf));assert(completions_called==1);
 snprintf(expected,sizeof expected,"%s/new-file.scm",home);assert(!strcmp(buf,expected));assert(access(buf,F_OK)!=0);
 command_mode=1;tab_mode=0;assert(!getcommand(buf,sizeof buf));assert(!strcmp(initial,""));
 tab_mode=1;assert(getcommand(buf,sizeof buf));assert(!strcmp(buf,"cat foo\\ bar"));
 command_mode=0;assert(getfilename_default("Save: ",buf,sizeof buf));
 assert(!chdir(old));assert(!rmdir(temp));
 puts("PASS Save As: editable folder/current filename, tilde, Tab completion, cancellation; no file writes; completing command prompt accepts/cancels and preserves shell escaping");
}
