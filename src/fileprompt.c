/* Editable filename-prompt defaults, shared by terminal and GUI. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <unistd.h>
#ifdef __CYGWIN__
#include <sys/cygwin.h>
#endif
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif
static char remembered[PATH_MAX], last_cwd[PATH_MAX];
int file_prompt_start(char *buf, int size)
{
    char cwd[PATH_MAX], directory[PATH_MAX];
    const char *home=getenv("HOME");
    if (size<=0 || !getcwd(cwd,sizeof cwd)) return 0;
    if (strcmp(cwd,last_cwd)) {
        snprintf(last_cwd,sizeof last_cwd,"%s",cwd);
        remembered[0]=0;
    }
    if (remembered[0]) snprintf(directory,sizeof directory,"%s",remembered);
    else {
        size_t n=strlen(cwd);
        if(n+2>sizeof directory) return 0;
        memcpy(directory,cwd,n);
        if(!n || directory[n-1]!='/') directory[n++]='/';
        directory[n]=0;
    }
    const char *tail=directory;
    int abbreviate=home && *home && strcmp(home,"/") &&
        !strncmp(directory,home,strlen(home)) && directory[strlen(home)]=='/';
    if(abbreviate) tail=directory+strlen(home);
    size_t needed=strlen(tail)+(abbreviate?1:0);
    if(needed>=(size_t)size) return 0;
    if(abbreviate){buf[0]='~';memcpy(buf+1,tail,strlen(tail)+1);}
    else memcpy(buf,tail,strlen(tail)+1);
    return 1;
}
void file_prompt_accept(const char *path)
{
    char absolute[PATH_MAX], cwd[PATH_MAX];
    if(!path || !*path || !getcwd(cwd,sizeof cwd)) return;
    int n=path[0]=='/'?snprintf(absolute,sizeof absolute,"%s",path):
        snprintf(absolute,sizeof absolute,"%s/%s",cwd,path);
    if(n<0 || (size_t)n>=sizeof absolute) return;
    char *slash=strrchr(absolute,'/');
    if(!slash) return;
    slash[1]=0;
    snprintf(remembered,sizeof remembered,"%s",absolute);
    snprintf(last_cwd,sizeof last_cwd,"%s",cwd);
}

#ifdef __CYGWIN__
/* Keep relative paths and ~/ editable. Let Cygwin map drives and UNC roots. */
int windows_path_to_posix(char *path, size_t size)
{
    if (!*path) return 1;
    int drive = ((path[0] >= 'A' && path[0] <= 'Z') ||
                 (path[0] >= 'a' && path[0] <= 'z')) && path[1] == ':';
    if (drive || path[0] == '\\') {
        char converted[PATH_MAX];
        size_t input_len = strlen(path);
        if (cygwin_conv_path(CCP_WIN_A_TO_POSIX, path, converted, sizeof converted) < 0)
            return 0;

        size_t len = strlen(converted);
        int directory = (path[input_len - 1] == '\\' || path[input_len - 1] == '/') &&
                        len > 0 && converted[len - 1] != '/';
        if (len + directory >= size) return 0;
        if (directory) converted[len++] = '/';
        converted[len] = '\0';
        memcpy(path, converted, len + 1);
    } else {
        for (char *p = path; *p; p++)
            if (*p == '\\') *p = '/';
    }
    return 1;
}
#endif
