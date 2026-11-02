#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
extern int file_prompt_start(char *,int);
extern void file_prompt_accept(const char *);
int main(void){
 char old[4096],buf[4096],expected[4096],temp[]="/tmp/chezemax-prompt-XXXXXX";
 assert(getcwd(old,sizeof old));assert(mkdtemp(temp));assert(!chdir(temp));
 assert(getcwd(expected,sizeof expected));assert(!setenv("HOME",expected,1));
 assert(file_prompt_start(buf,sizeof buf));assert(!strcmp(buf,"~/"));
 assert(!mkdir("nested",0700));
 snprintf(expected,sizeof expected,"%s/nested/new.scm",getenv("HOME"));file_prompt_accept(expected);
 assert(file_prompt_start(buf,sizeof buf));assert(!strcmp(buf,"~/nested/"));
 /* Reopening after cancellation has no side effects on the remembered path. */
 assert(file_prompt_start(buf,sizeof buf));assert(!strcmp(buf,"~/nested/"));
 assert(!file_prompt_start(buf,2));
 assert(!chdir("nested"));assert(file_prompt_start(buf,sizeof buf));assert(!strcmp(buf,"~/nested/"));
 file_prompt_accept("relative.scm");assert(file_prompt_start(buf,sizeof buf));assert(!strcmp(buf,"~/nested/"));
 assert(!setenv("HOME","/not-the-home",1));assert(file_prompt_start(buf,sizeof buf));
 assert(buf[0]=='/' && strstr(buf,"/nested/"));
 assert(!chdir(old));snprintf(buf,sizeof buf,"%s/nested",temp);assert(!rmdir(buf));assert(!rmdir(temp));
 puts("PASS filename prompt: cwd, tilde, remembered directory, cancellation, relative paths, changed cwd, capacity");
}
