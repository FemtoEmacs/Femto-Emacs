/* Editable filename-prompt defaults, shared by terminal and GUI. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <unistd.h>
#include <ctype.h>
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

/*
 * A filename in Windows' form, as people type or paste it on Windows
 * (C:\Users\pedro\doc.md, D:\, \\server\share\x, notes\a.md), in
 * the form the editor's files take there, Cygwin's: /c/Users/pedro/doc.md,
 * /d/, //server/share/x, notes/a.md.  Pedro could open only what he could
 * name in that form (16 November 2026).  Returns 1 when BUF changed.
 * Elsewhere a backslash is a character of a filename: nothing changes,
 * unless a test asks (CHEZWEB_WINDOWS_PATHS).
 */
int file_path_posix(char *buf, int size)
{
#if defined(__CYGWIN__) || defined(CHEZWEB_WINDOWS_PATHS)
    char out[PATH_MAX];
    size_t n = strlen(buf), k = 0, i = 0;
    int drive = n >= 2 && isalpha((unsigned char)buf[0]) && buf[1] == ':' &&
                (n == 2 || buf[2] == '\\' || buf[2] == '/');
    int unc = n >= 2 && buf[0] == '\\' && buf[1] == '\\';
    if (!drive && !unc && !strchr(buf, '\\')) return 0;
#ifdef __CYGWIN__
    /* Cygwin knows its own mounts (the drives' prefix, network folders) */
    if (cygwin_conv_path(CCP_WIN_A_TO_POSIX | CCP_RELATIVE, buf, out, sizeof out) == 0) {
        size_t m = strlen(out);
        int sep = buf[n - 1] == '\\' || buf[n - 1] == '/';
        if (sep && m && out[m - 1] != '/' && m + 1 < sizeof out) { out[m++] = '/'; out[m] = 0; }
        if (m < (size_t)size) { memcpy(buf, out, m + 1); return 1; }
        return 0;
    }
#endif
    /* the same by hand, with Cygwin's names for drives: C: is /c */
    if (drive) {
        out[k++] = '/';
        out[k++] = (char)tolower((unsigned char)buf[0]);
        i = 2;
    }
    for (; i < n && k + 1 < sizeof out; i++)
        out[k++] = buf[i] == '\\' ? '/' : buf[i];
    out[k] = 0;
    if (k >= (size_t)size) return 0;
    memcpy(buf, out, k + 1);
    return 1;
#else
    (void) buf; (void) size;
    return 0;
#endif
}
