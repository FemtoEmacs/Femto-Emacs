/*
 * pty-keys.c -- run a program in a terminal of its own and type keys into
 * it, as a person would (tests/run-editor.sh).
 *
 *   pty-keys SCRIPT TIMEOUT-SECONDS SCREEN-FILE PROGRAM ARG ...
 *
 * SCRIPT has one step a line:
 *   wait MS        let MS milliseconds pass (the program draws meanwhile)
 *   keys TEXT      type TEXT; \e is Esc, \r Return, \t Tab, \\ a backslash,
 *                  ^X the control key with X (^X^S is C-x C-s)
 * Everything the program writes goes to SCREEN-FILE.  The exit status is
 * the program's, or 124 when it did not finish in TIMEOUT-SECONDS.
 */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
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
		if (left < 0) left = 0;
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
		} else if (left == 0 || (n < 0 && errno != EINTR)) {
			return;
		}
	}
}

static void type_text(const char *s)
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
	/* one key at a time, as typed */
	for (size_t k = 0; k < n; k++) {
		if (write(master, out + k, 1) != 1) return;
		drain(30);
	}
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

	long start = now_ms();
	char line[4096];
	while (fgets(line, sizeof line, script)) {
		line[strcspn(line, "\n")] = '\0';
		if (strncmp(line, "wait ", 5) == 0) drain(atol(line + 5));
		else if (strncmp(line, "keys ", 5) == 0) type_text(line + 5);
	}
	fclose(script);

	/* the program should end by itself now */
	int status = 0;
	for (;;) {
		pid_t r = waitpid(pid, &status, WNOHANG);
		if (r == pid) break;
		if (now_ms() - start > timeout) {
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
