/*
 * pty-keys.c -- run a program in a terminal of its own and type keys into
 * it, as a person would (tests/run-editor.sh).
 *
 *   pty-keys SCRIPT TIMEOUT-SECONDS SCREEN-FILE PROGRAM ARG ...
 *
 * SCRIPT has one step a line:
 *   wait MS        let MS milliseconds pass (the program draws meanwhile)
 *   await-screen TEXT  wait for literal terminal output, within TIMEOUT
 *   await-file PATH    wait for a nonempty file, within TIMEOUT
 *   keys TEXT      type TEXT; \e is Esc, \r Return, \t Tab, \\ a backslash,
 *                  ^X the control key with X (^X^S is C-x C-s)
 *   paste TEXT     the same keys, but all at once, in one write: a command
 *                  that reads a prompt (M-%, C-s) is then timed by its work,
 *                  not by the 30 ms each typed key waits
 *   send-file PATH the bytes of the file PATH, as they are (NUL bytes,
 *                  escapes, megabytes), written as fast as the program
 *                  reads them, while what it writes is copied
 *   resize ROWS COLS  the terminal takes that size: the program gets
 *                  SIGWINCH, as when a window is resized
 * Everything the program writes goes to SCREEN-FILE.  The exit status is
 * the program's, or 124 when it did not finish in TIMEOUT-SECONDS.
 */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <util.h>
#else
#include <pty.h>
#endif

static FILE *screen;
static int master;
static char observed[65536];
static size_t observed_len;
static long deadline;

static long now_ms(void)
{
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return tv.tv_sec * 1000L + tv.tv_usec / 1000;
}

/* copy what the program wrote, for MS milliseconds */
static void drain(long ms)
{
	long end = now_ms() + ms;
	for (;;) {
		long left = end - now_ms();
		if (left <= 0) return;
		fd_set r;
		FD_ZERO(&r);
		FD_SET(master, &r);
		struct timeval tv = { left / 1000, (left % 1000) * 1000 };
		int n = select(master + 1, &r, NULL, NULL, &tv);
		if (n > 0) {
			char buf[4096];
			ssize_t k = read(master, buf, sizeof buf);
			if (k <= 0) return;
			fwrite(buf, 1, (size_t) k, screen);
			fflush(screen);
			if (observed_len + (size_t) k >= sizeof observed) {
				size_t drop = observed_len + (size_t) k - sizeof observed + 1;
				memmove(observed, observed + drop, observed_len - drop);
				observed_len -= drop;
			}
			memcpy(observed + observed_len, buf, (size_t) k);
			observed_len += (size_t) k;
			observed[observed_len] = 0;
		} else if (n == 0 || errno != EINTR) {
			return;
		}
	}
}

static int type_text(const char *s, int at_once)
{
	char out[4096];
	size_t n = 0;
	for (; *s && n < sizeof out - 1; s++) {
		if (*s == '\\' && s[1]) {
			s++;
			out[n++] = *s == 'e' ? 27 : *s == 'r' ? 13 : *s == 't' ? 9 : *s;
		} else if (*s == '^' && s[1]) {
			s++;
			out[n++] = (char) (*s == '?' ? 127 : (*s & 31));
		} else {
			out[n++] = *s;
		}
	}
	if (at_once) {
		size_t k = 0;
		while (k < n) {
			ssize_t w = write(master, out + k, n - k);
			if (w <= 0) { if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) return 0; if (now_ms() >= deadline) return 0; drain(10); continue; }
			k += (size_t) w;
		}
		drain(30);
		return 1;
	}
	/* one key at a time, as typed */
	for (size_t k = 0; k < n; k++) {
		while (write(master, out + k, 1) != 1) {
			if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)
				return 0;
			if (now_ms() >= deadline) return 0;
			drain(10);
		}
		drain(30);
	}
	return 1;
}

/* the bytes of PATH into the terminal; the program's output is read
 * meanwhile, so that neither side waits for the other forever */
static int send_file(const char *path, long deadline)
{
	FILE *f = fopen(path, "rb");
	char buf[65536];
	size_t have = 0, at = 0;
	int eof = 0, flags, ok = 1;
	if (!f) { perror(path); return 0; }
	flags = fcntl(master, F_GETFL);
	fcntl(master, F_SETFL, flags | O_NONBLOCK);     /* a full terminal must not block us */
	for (;;) {
		if (at == have && !eof) {
			have = fread(buf, 1, sizeof buf, f);
			at = 0;
			if (have == 0) eof = 1;
		}
		if (eof && at == have) break;
		if (now_ms() > deadline) { ok = 0; break; }
		fd_set r, w;
		FD_ZERO(&r); FD_ZERO(&w);
		FD_SET(master, &r); FD_SET(master, &w);
		struct timeval tv = { 1, 0 };
		int n = select(master + 1, &r, &w, NULL, &tv);
		if (n < 0) { if (errno == EINTR) continue; break; }
		if (FD_ISSET(master, &r)) drain(0);
		if (FD_ISSET(master, &w)) {
			ssize_t k = write(master, buf + at, have - at);
			if (k > 0) at += (size_t) k;
			else if (k < 0 && errno != EAGAIN && errno != EINTR) { ok = 0; break; }
		}
	}
	fcntl(master, F_SETFL, flags);
	fclose(f);
	if (ok) drain(30);
	return ok;
}

int main(int argc, char **argv)
{
	if (argc < 5) {
		fprintf(stderr, "usage: pty-keys SCRIPT TIMEOUT SCREEN PROGRAM ARG ...\n");
		return 2;
	}
	FILE *script = fopen(argv[1], "r");
	if (!script) { perror(argv[1]); return 2; }
	long timeout = atol(argv[2]) * 1000L;
	screen = fopen(argv[3], "wb");
	if (!screen) { perror(argv[3]); return 2; }

	struct winsize ws = { 24, 80, 0, 0 };
	pid_t pid = forkpty(&master, NULL, NULL, &ws);
	if (pid < 0) { perror("forkpty"); return 2; }
	if (pid == 0) {
		setenv("TERM", "xterm", 1);
		execv(argv[4], argv + 4);
		perror(argv[4]);
		_exit(127);
	}

	int flags = fcntl(master, F_GETFL);
	if (flags < 0 || fcntl(master, F_SETFL, flags | O_NONBLOCK) < 0) {
		perror("nonblocking PTY master");
		kill(pid, SIGKILL);
		return 2;
	}
	deadline = now_ms() + timeout;
	int trace = getenv("CHEZWEB_PTY_TRACE") != NULL;
	char line[4096];
	while (fgets(line, sizeof line, script)) {
		line[strcspn(line, "\n")] = '\0';
		if (trace) fprintf(stderr, "PTY step: %s\n", line);
		if (strncmp(line, "wait ", 5) == 0) drain(atol(line + 5));
		else if (strncmp(line, "keys ", 5) == 0) {
			if (!type_text(line + 5, 0)) {
				fprintf(stderr, "Could not send keys: %s\n", line + 5);
				kill(pid, SIGKILL);
				waitpid(pid, NULL, 0);
				fclose(script);
				fclose(screen);
				return 124;
			}
		}
		else if (strncmp(line, "paste ", 6) == 0) (void) type_text(line + 6, 1);
		else if (strncmp(line, "send-file ", 10) == 0) {
			if (!send_file(line + 10, deadline)) {
				fprintf(stderr, "Timed out or failed: %s\n", line);
				kill(pid, SIGKILL);
				waitpid(pid, NULL, 0);
				fclose(script);
				return 124;
			}
		}
		else if (strncmp(line, "resize ", 7) == 0) {
			struct winsize size = { 24, 80, 0, 0 };
			if (sscanf(line + 7, "%hu %hu", &size.ws_row, &size.ws_col) == 2)
				ioctl(master, TIOCSWINSZ, &size);   /* the kernel signals the program */
			drain(50);
		}
		else if (strncmp(line, "await-screen ", 13) == 0 ||
		         strncmp(line, "await-file ", 11) == 0) {
			int is_screen = strncmp(line, "await-screen ", 13) == 0;
			const char *target = line + (is_screen ? 13 : 11);
			for (;;) {
				struct stat st;
				if (is_screen ? strstr(observed, target) != NULL :
				    (stat(target, &st) == 0 && st.st_size > 0)) break;
				if (now_ms() >= deadline) {
					fprintf(stderr, "Timed out: %s\n", line);
					kill(pid, SIGKILL);
					waitpid(pid, NULL, 0);
					fclose(script);
					fclose(screen);
					return 124;
				}
				drain(50);
			}
		}
	}
	fclose(script);

	/* the program should end by itself now */
	int status = 0;
	for (;;) {
		pid_t r = waitpid(pid, &status, WNOHANG);
		if (r == pid) break;
		if (now_ms() >= deadline) {
			kill(pid, SIGKILL);
			waitpid(pid, &status, 0);
			drain(100);
			fclose(screen);
			return 124;
		}
		drain(50);
	}
	drain(100);
	fclose(screen);
	if (WIFEXITED(status)) return WEXITSTATUS(status);
	return 128 + (WIFSIGNALED(status) ? WTERMSIG(status) : 0);
}
