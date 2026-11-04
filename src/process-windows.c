/* Native process creation for a Cygwin editor hosting Wasmtime. Cygwin's
 * fork/spawn PID mappings can collide with the JIT's address reservations.
 * Child processes start afresh; handles, redirection and quoting stay here. */
#ifdef __CYGWIN__
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <sys/cygwin.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wchar.h>
#include "process-windows.h"

struct win_child { HANDLE handle; };
static const char *win_error(DWORD code) {
 static char message[2048];wchar_t wide[1024];
 DWORD n=FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM|FORMAT_MESSAGE_IGNORE_INSERTS,
  NULL,code,0,wide,1024,NULL);
 if(n){int k=WideCharToMultiByte(CP_UTF8,0,wide,(int)n,message,sizeof message-1,NULL,NULL);
  if(k>0){while(k && (message[k-1]=='\r'||message[k-1]=='\n'))k--;message[k]=0;return message;}}
 snprintf(message,sizeof message,"Windows process error %lu",(unsigned long)code);return message;
}
static wchar_t *utf16(const char *text) {
 int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text,-1,NULL,0);
 if(!n)return NULL;wchar_t *r=malloc((size_t)n*sizeof *r);
 if(r&&!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text,-1,r,n)){free(r);r=NULL;}return r;
}
static char *utf8(const wchar_t *text) {
 int n=WideCharToMultiByte(CP_UTF8,0,text,-1,NULL,0,NULL,NULL);
 if(!n)return NULL;char *r=malloc((size_t)n);
 if(r&&!WideCharToMultiByte(CP_UTF8,0,text,-1,r,n,NULL,NULL)){free(r);r=NULL;}return r;
}
static wchar_t *native_path(const char *path) {
 if((path[0]&&path[1]==':')||(path[0]=='\\'&&path[1]=='\\'))return utf16(path);
 return cygwin_create_path(CCP_POSIX_TO_WIN_W,path);
}
/* Resolve through the POSIX PATH, adding .exe only when needed. Preserve
 * the POSIX name for #! scripts; CreateProcess itself needs the native name. */
static char *candidate(const char *name) {
 wchar_t *p=native_path(name);if(!p)return NULL;
 DWORD a=GetFileAttributesW(p);free(p);
 if(a!=INVALID_FILE_ATTRIBUTES && !(a&FILE_ATTRIBUTE_DIRECTORY))return strdup(name);
 size_t n=strlen(name);char *r=malloc(n+5);if(!r)return NULL;
 memcpy(r,name,n);memcpy(r+n,".exe",5);p=native_path(r);
 a=p?GetFileAttributesW(p):INVALID_FILE_ATTRIBUTES;free(p);
 if(a==INVALID_FILE_ATTRIBUTES||(a&FILE_ATTRIBUTE_DIRECTORY)){free(r);return NULL;}return r;
}
static char *resolve(const char *program) {
 if(strchr(program,'/')||strchr(program,'\\')||strchr(program,':'))return candidate(program);
 const char *path=getenv("PATH");char *paths=strdup(path?path:"");if(!paths)return NULL;
 char *p=paths,*r=NULL;
 do {char *end=strchr(p,':');if(end)*end=0;
  size_t n=strlen(p)+strlen(program)+3;char *name=malloc(n);
  if(name){snprintf(name,n,"%s/%s",*p?p:".",program);r=candidate(name);free(name);}
  if(r||!end)break;p=end+1;
 } while(1);
 free(paths);return r;
}
static HANDLE redirect(const char *path,int writing,SECURITY_ATTRIBUTES *sa) {
 wchar_t *name=path?native_path(path):utf16("NUL");if(!name)return INVALID_HANDLE_VALUE;
 HANDLE h=CreateFileW(name,writing?GENERIC_WRITE:GENERIC_READ,
  FILE_SHARE_READ|FILE_SHARE_WRITE,sa,writing?CREATE_ALWAYS:OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
 free(name);return h;
}
/* Microsoft's argv quoting: double backslashes only before quotes and
 * the closing quote. There is no cmd.exe interpolation. */
static char *quote(char *out,const char *arg) {
 *out++='"';size_t slashes=0;
 for(const char *p=arg;;p++){
  if(*p=='\\'){slashes++;continue;}
  size_t count=slashes*((*p=='"'||!*p)?2:1);
  while(count--)*out++='\\';slashes=0;
  if(!*p)break;if(*p=='"')*out++='\\';*out++=*p;
 }
 *out++='"';return out;
}
const char *win_process_start(const char *program,char *const argv[],const char *dir,
 const char *input,const char *output,const char *error,win_process *result) {
 *result=NULL;char *exe=resolve(program);if(!exe)return "Program was not found";
 char header[2048]={0};FILE *f=fopen(exe,"rb");if(f){fgets(header,sizeof header,f);fclose(f);}
 char *args[SYS_MAX_ARGS+6];int count=0;char *interpreter=NULL;
 if(header[0]=='#'&&header[1]=='!'){
  char *p=header+2;while(*p==' '||*p=='\t')p++;char *end=p;
  while(*end&&*end!=' '&&*end!='\t'&&*end!='\r'&&*end!='\n')end++;
  char *rest=end;if(*end)*end++=0;rest=end;while(*rest==' '||*rest=='\t')rest++;
  rest[strcspn(rest,"\r\n")]=0;
  interpreter=resolve(p);if(!interpreter){free(exe);return "The script interpreter was not found";}
  args[count++]=interpreter;if(*rest)args[count++]=rest;args[count++]=exe;
 }else args[count++]=exe;
 for(int i=1;argv&&argv[i];i++){
  if(count>=SYS_MAX_ARGS+4){free(interpreter);free(exe);return "Too many process arguments";}
  args[count++]=argv[i];
 }
 args[count]=NULL;
 wchar_t *application=native_path(interpreter?interpreter:exe);
 char *first=application?utf8(application):NULL;
 if(!application||!first){free(application);free(first);free(interpreter);free(exe);return "Cannot convert the executable path";}
 size_t bytes=strlen(first)*2+4;
 for(int i=1;i<count;i++)bytes+=strlen(args[i])*2+4;
 char *line=malloc(bytes),*at=line;
 if(!line){free(application);free(first);free(interpreter);free(exe);return "Out of memory starting process";}
 at=quote(at,first);for(int i=1;i<count;i++){*at++=' ';at=quote(at,args[i]);}*at=0;
 wchar_t *command=utf16(line);free(line);free(first);
 char *cwd=dir?strdup(dir):getcwd(NULL,0);wchar_t *directory=cwd?native_path(cwd):NULL;free(cwd);
 if(!command||!directory){free(command);free(directory);free(application);free(interpreter);free(exe);return "Cannot convert process arguments or directory";}
 SECURITY_ATTRIBUTES sa={sizeof sa,NULL,TRUE};
 HANDLE handles[3];handles[0]=redirect(input,0,&sa);handles[1]=redirect(output,1,&sa);
 handles[2]=((!output&&!error)||(output&&error&&!strcmp(output,error)))?handles[1]:redirect(error,1,&sa);
 DWORD failure=0;
 if(handles[0]==INVALID_HANDLE_VALUE||handles[1]==INVALID_HANDLE_VALUE||handles[2]==INVALID_HANDLE_VALUE)failure=GetLastError()?GetLastError():ERROR_OPEN_FAILED;
 STARTUPINFOEXW start={0};start.StartupInfo.cb=sizeof start;
 start.StartupInfo.dwFlags=STARTF_USESTDHANDLES;
 start.StartupInfo.hStdInput=handles[0];start.StartupInfo.hStdOutput=handles[1];start.StartupInfo.hStdError=handles[2];
 SIZE_T size=0;InitializeProcThreadAttributeList(NULL,1,0,&size);
 start.lpAttributeList=malloc(size);int attributes=0;
 if(!failure){if(!start.lpAttributeList)failure=ERROR_NOT_ENOUGH_MEMORY;else if(!InitializeProcThreadAttributeList(start.lpAttributeList,1,0,&size))failure=GetLastError();else attributes=1;}
 HANDLE inherited[3]={handles[0],handles[1],handles[2]};size_t inherited_count=handles[2]==handles[1]?2:3;
 if(!failure&&!UpdateProcThreadAttribute(start.lpAttributeList,0,PROC_THREAD_ATTRIBUTE_HANDLE_LIST,inherited,inherited_count*sizeof(HANDLE),NULL,NULL))failure=GetLastError();
 struct win_child *child=calloc(1,sizeof *child);PROCESS_INFORMATION process={0};
 if(!child&&!failure)failure=ERROR_NOT_ENOUGH_MEMORY;
 if(!failure){
  cygwin_internal(CW_SYNC_WINENV);
  if(!CreateProcessW(application,command,NULL,NULL,TRUE,
   EXTENDED_STARTUPINFO_PRESENT|CREATE_NO_WINDOW|CREATE_NEW_PROCESS_GROUP,
   NULL,directory,&start.StartupInfo,&process))failure=GetLastError();
 }
 if(attributes)DeleteProcThreadAttributeList(start.lpAttributeList);free(start.lpAttributeList);
 for(int i=0;i<3;i++)if(handles[i]!=INVALID_HANDLE_VALUE && (i!=2||handles[2]!=handles[1]))CloseHandle(handles[i]);
 free(command);free(directory);free(application);free(interpreter);free(exe);
 if(failure){free(child);return win_error(failure);}
 CloseHandle(process.hThread);child->handle=process.hProcess;*result=child;return NULL;
}
int win_process_wait(win_process child,long milliseconds,int *status) {
 DWORD ms=milliseconds<0?INFINITE:((uint64_t)milliseconds>=INFINITE?INFINITE-1:(DWORD)milliseconds);
 DWORD result=WaitForSingleObject(child->handle,ms);
 if(result==WAIT_TIMEOUT)return 0;if(result!=WAIT_OBJECT_0){*status=-1;return -1;}
 DWORD code;if(!GetExitCodeProcess(child->handle,&code)){*status=-1;return -1;}*status=(int)code;return 1;
}
void win_process_kill(win_process child){if(child)TerminateProcess(child->handle,1);}
void win_process_close(win_process child){if(child){CloseHandle(child->handle);free(child);}}
const char *win_run_program(const char *program,char *const *arguments,int nargs,
 const char *input,size_t input_len,long timeout,const char *directory,sys_run_result *r) {
 memset(r,0,sizeof *r);if(nargs>SYS_MAX_ARGS)return "run-program: too many arguments";
 char temp[]="/tmp/chezemax-run-XXXXXX";if(!mkdtemp(temp))return "Cannot create a process temporary folder";
 char in[512],out[512],err[512];snprintf(in,sizeof in,"%s/in",temp);snprintf(out,sizeof out,"%s/out",temp);snprintf(err,sizeof err,"%s/err",temp);
 FILE *f=fopen(in,"wb");if(!f){rmdir(temp);return "Cannot write process input";}
 if(input&&input_len)fwrite(input,1,input_len,f);fclose(f);
 char *argv[SYS_MAX_ARGS+2];argv[0]=(char *)program;
 for(int i=0;i<nargs;i++)argv[i+1]=arguments[i];argv[nargs+1]=NULL;
 win_process child=NULL;const char *problem=win_process_start(program,argv,directory,in,out,err,&child);
 char *message=problem?strdup(problem):NULL;int status=-1;
 if(!problem){int done=win_process_wait(child,timeout<0?0:timeout*1000,&status);
  if(done!=1){char text[128];snprintf(text,sizeof text,done==0?"no answer after %ld seconds":"cannot wait for process (%ld)",timeout);message=strdup(text);win_process_kill(child);int ignored;win_process_wait(child,1000,&ignored);status=-1;}
  win_process_close(child);
 }
 r->out=sys_read_file(out,&r->out_len);if(!r->out)r->out=strdup("");
 r->err=message?message:sys_read_file(err,&r->err_len);if(!r->err)r->err=strdup("");
 if(message)r->err_len=strlen(message);r->status=status;
 unlink(in);unlink(out);unlink(err);rmdir(temp);return NULL;
}
#endif
