/*
 * exepath.c -- the path of this executable, and so the folder Chezweb is
 * installed in (chezemax.wasm, compiled/, scheme/languages are found
 * there).  Taken from femtoscheme's llt/dirpath.c, which gave it to the
 * editor until femtoscheme was removed (27 November 2026).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if defined(__EMSCRIPTEN__)
char *get_exename(char *buf, size_t size) { snprintf(buf, size, "/chezweb"); return buf; }
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#include <stdint.h>
char *get_exename(char *buf, size_t size)
{
	uint32_t bufsize = (uint32_t) size;
	if (_NSGetExecutablePath(buf, &bufsize)) return NULL;
	return buf;
}
#elif defined(_WIN32)
#include <windows.h>
char *get_exename(char *buf, size_t size)
{
	if (GetModuleFileNameA(NULL, buf, (DWORD) size) == 0) return NULL;
	return buf;
}
#elif defined(__FreeBSD__)
#include <sys/types.h>
#include <sys/sysctl.h>
char *get_exename(char *buf, size_t size)
{
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, -1 };
	if (sysctl(mib, 4, buf, &size, NULL, 0) != 0) return NULL;
	return buf;
}
#else   /* Linux, Cygwin: the link /proc/self/exe */
char *get_exename(char *buf, size_t size)
{
	ssize_t n = readlink("/proc/self/exe", buf, size);
	if (n < 0 || (size_t) n >= size) return NULL;
	buf[n] = '\0';
	return buf;
}
#endif

/* the folder of this executable into DIR, "." when it cannot be known */
void install_directory(char *dir, size_t size)
{
	char *slash;
	if (get_exename(dir, size) == NULL) { snprintf(dir, size, "."); return; }
	slash = strrchr(dir, '/');
	if (slash == dir) dir[1] = '\0';
	else if (slash) *slash = '\0';
	else snprintf(dir, size, ".");
}
