/* Atomic installation of the current buffer. Naming, prompts and overwrite
 * confirmation belong to Scheme; no source-buffer state is changed here. */
#include "header.h"
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

char *fe_install_script(char *name, int overwrite)
{
#ifdef __EMSCRIPTEN__
 (void)name; (void)overwrite;
 return "Use script-installer in the terminal or GUI window";
#else
 const char *home = getenv("HOME");
 char config[4096], users[4096], target[4096], temp[4096];
 size_t n = strlen(name);
 int fd, error = 0;
 FILE *out;
 struct stat st;
 if (!home || !*home) return "HOME is not set";
 if (n <= 4 || n > 255 || name[0] == '.' || strchr(name, '/') || strchr(name, '\\') || strcmp(name+n-4, ".scm"))
  return "Use a visible .scm filename without folder separators";
 if (snprintf(config,sizeof config,"%s/.chezemax",home) >= sizeof config ||
     snprintf(users,sizeof users,"%s/users",config) >= sizeof users ||
     snprintf(target,sizeof target,"%s/%s",users,name) >= sizeof target ||
     snprintf(temp,sizeof temp,"%s/.script-install-XXXXXX",users) >= sizeof temp)
  return "Script installation path is too long";
 if (mkdir(config,0700) && errno != EEXIST) return strerror(errno);
 if (mkdir(users,0700) && errno != EEXIST) return strerror(errno);
 if (!lstat(target,&st)) {
  if (!overwrite) return "A script with that name already exists";
  if (S_ISDIR(st.st_mode)) return "The destination is a directory";
 } else if (errno != ENOENT) return strerror(errno);
 fd = mkstemp(temp);
 if (fd < 0) return strerror(errno);
 out = fdopen(fd,"wb");
 if (!out) { error=errno; close(fd); unlink(temp); return strerror(error); }
 size_t before = curbp->b_buf ? (size_t)(curbp->b_gap-curbp->b_buf) : 0;
 size_t after = curbp->b_egap ? (size_t)(curbp->b_ebuf-curbp->b_egap) : 0;
 if ((before && fwrite(curbp->b_buf,1,before,out) != before) ||
     (after && fwrite(curbp->b_egap,1,after,out) != after))
  error = errno ? errno : EIO;
 if (fclose(out) && !error) error = errno ? errno : EIO;
 /* link refuses a concurrently created destination unless replacement was
  * explicitly approved. The temporary file is on the same filesystem. */
 if (!error && (overwrite ? rename(temp,target) : link(temp,target))) error=errno;
 unlink(temp);
 return error ? strerror(error) : "";
#endif
}
