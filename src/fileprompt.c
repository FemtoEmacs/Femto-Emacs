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

#if defined(__CYGWIN__) || defined(CHEZWEB_WINDOWS_PATHS)
/* Use the installer's /c drive convention if Cygwin cannot convert a path. */
int windows_path_to_posix(char *path, size_t size)
{
    size_t input_len = strlen(path);
    if (input_len >= size) return 0;
    if (!input_len) return 1;
    int drive = ((path[0] >= 'A' && path[0] <= 'Z') ||
                 (path[0] >= 'a' && path[0] <= 'z')) && path[1] == ':';
    if (drive || path[0] == '\\') {
#if defined(__CYGWIN__) && !defined(CHEZWEB_WINDOWS_PATHS)
        char converted[PATH_MAX];
        if (cygwin_conv_path(CCP_WIN_A_TO_POSIX, path, converted, sizeof converted) == 0) {
            size_t len = strlen(converted);
            int directory = (path[input_len - 1] == '\\' || path[input_len - 1] == '/') &&
                            len > 0 && converted[len - 1] != '/';
            if (len + directory >= size || len + directory >= sizeof converted) return 0;
            if (directory) converted[len++] = '/';
            converted[len] = '\0';
            memcpy(path, converted, len + 1);
            return 1;
        }
#endif
        if (drive && (input_len == 2 || path[2] == '\\' || path[2] == '/')) {
            path[1] = path[0] >= 'A' && path[0] <= 'Z' ? path[0] + ('a' - 'A') : path[0];
            path[0] = '/';
        } else if (drive || path[1] != '\\') {
            /* These forms depend on the current Windows drive or directory. */
            return 0;
        }
    }
    for (char *p = path; *p; p++)
        if (*p == '\\') *p = '/';
    return 1;
}
#endif
