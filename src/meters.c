/*
 * meters.c -- what the editor holds, for the endurance tests
 * (tests/endurance.sh; 22 November 2026)
 *
 * (fe-meter K): one meter, as a number
 *   0  live bytes of the C heap: exact under AddressSanitizer
 *      (make chezemax-sanitized); else the allocator's own count
 *      (mallinfo2 with glibc, the malloc zones on macOS); -1 unknown
 *   1  resident memory of the process (RSS), in bytes; -1 unknown
 *   2  open file descriptors
 *   3  buffers, 4 windows
 *   5  bytes the shells of M-x term have written (terminal.c), 6 the pid
 * (fe-meter-note LABEL): one line "LABEL heap rss fds buffers windows",
 *   appended to the file $CHEZWEB_METERS (nothing without it)
 * With $CHEZWEB_METERS_MS set, the editor also writes a line every so
 *   many milliseconds while it waits for keys or reads a shell (main.c):
 *   "tick MS TERM-BYTES PID heap rss fds buffers windows".
 * (fe-leak-check): under LeakSanitizer, the memory no pointer reaches, now
 *   (not only at exit), reported on standard error; 1 if there is any.
 *   0 without the sanitizer.
 *
 * RSS alone misleads: freed pages stay with the allocator, and the heap of
 * the compiled Scheme program grows and never shrinks.  The live C heap and
 * the descriptors say whether C keeps what it should have let go; RSS is a
 * bound.  The Scheme side counts its own tables (tests/endurance.scm).
 */
#include "header.h"

extern long long term_bytes_read;      /* terminal.c */
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>

#if defined(__has_feature)
#if __has_feature(address_sanitizer)
#define METERS_ASAN 1
#endif
#endif
#if defined(__SANITIZE_ADDRESS__)
#define METERS_ASAN 1
#endif

#ifdef METERS_ASAN
/* the sanitizers' own functions (their headers are not always installed) */
extern size_t __sanitizer_get_current_allocated_bytes(void);
extern int __lsan_do_recoverable_leak_check(void);
#elif defined(__APPLE__)
#include <malloc/malloc.h>
#elif defined(__GLIBC__) && (__GLIBC__ > 2 || (__GLIBC__ == 2 && __GLIBC_MINOR__ >= 33))
#include <malloc.h>
#define METERS_MALLINFO2 1
#endif

#ifdef __APPLE__
#include <mach/mach.h>
#endif

static long heap_bytes(void)
{
#ifdef METERS_ASAN
	return (long) __sanitizer_get_current_allocated_bytes();
#elif defined(__APPLE__)
	malloc_statistics_t s;
	malloc_zone_statistics(NULL, &s);
	return (long) s.size_in_use;
#elif defined(METERS_MALLINFO2)
	struct mallinfo2 m = mallinfo2();
	return (long) (m.uordblks + m.hblkhd);
#else
	return -1;
#endif
}

static long resident_bytes(void)
{
#ifdef __APPLE__
	struct mach_task_basic_info info;
	mach_msg_type_number_t n = MACH_TASK_BASIC_INFO_COUNT;
	if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t) &info, &n) != KERN_SUCCESS)
		return -1;
	return (long) info.resident_size;
#else
	long pages = 0, resident = 0;
	FILE *f = fopen("/proc/self/statm", "r");
	if (f == NULL) return -1;
	if (fscanf(f, "%ld %ld", &pages, &resident) != 2) resident = -1;
	fclose(f);
	return resident < 0 ? -1 : resident * sysconf(_SC_PAGESIZE);
#endif
}

static long open_descriptors(void)
{
	long n = 0, fd, top;
	DIR *d = opendir("/proc/self/fd");
	if (d != NULL) {                        /* Linux: one entry a descriptor */
		struct dirent *e;
		while ((e = readdir(d)) != NULL) if (e->d_name[0] != '.') n++;
		closedir(d);
		return n - 1;                       /* not the one opendir holds */
	}
	top = sysconf(_SC_OPEN_MAX);
	if (top < 0 || top > 65536) top = 65536;
	for (fd = 0; fd < top; fd++) if (fcntl((int) fd, F_GETFD) != -1) n++;
	return n;
}

static long meter_windows(void)
{
	long n = 0;
	window_t *wp;
	for (wp = wheadp; wp != NULL; wp = wp->w_next) n++;
	return n;
}

static long meter_buffers(void)
{
	long n = 0;
	buffer_t *bp;
	for (bp = bheadp; bp != NULL; bp = bp->b_next) n++;
	return n;
}

long fe_meter(long which)
{
	switch (which) {
	case 0: return heap_bytes();
	case 1: return resident_bytes();
	case 2: return open_descriptors();
	case 3: return meter_buffers();
	case 4: return meter_windows();
	case 5: return (long) term_bytes_read;
	case 6: return (long) getpid();
	default: return -1;
	}
}

void fe_meter_note(char *label)
{
	const char *file = getenv("CHEZWEB_METERS");
	FILE *f;
	if (file == NULL || !*file) return;
	if ((f = fopen(file, "a")) == NULL) return;
	fprintf(f, "%s %ld %ld %ld %ld %ld\n", label, heap_bytes(), resident_bytes(),
		open_descriptors(), meter_buffers(), meter_windows());
	fclose(f);
}

#include <sys/time.h>
static long now_ms(void)
{
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return (long) tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

/* main.c, while the editor waits: a line of meters every $CHEZWEB_METERS_MS */
void meters_tick(void)
{
	static long every = -1, start, last;
	char label[96];
	long now;
	if (every == 0) return;
	if (every < 0) {
		const char *ms = getenv("CHEZWEB_METERS_MS");
		every = ms && atol(ms) > 0 ? atol(ms) : 0;
		start = last = now_ms();
		if (every == 0) return;
	}
	now = now_ms();
	if (now - last < every) return;
	last = now;
	snprintf(label, sizeof label, "tick %ld %lld %ld", now - start, term_bytes_read, (long) getpid());
	fe_meter_note(label);
}

long fe_leak_check(void)
{
#ifdef METERS_ASAN
	return __lsan_do_recoverable_leak_check() ? 1 : 0;
#else
	return 0;
#endif
}
