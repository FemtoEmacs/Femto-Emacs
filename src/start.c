/*
 * start.c -- Chezweb's scripts at start-up: the compiled program
 *
 * The folder Chezweb is installed in is the executable's (exepath.c);
 * chezemax.wasm there (or yours, compiled-program.c) is loaded, and then
 * the event "init" runs your files (compiled/start.scm).  Without a
 * program that runs the scripts, Chezweb says why and stops: there is
 * nothing else to run them.  Until 27 November 2026 femtoscheme started
 * here and ran old copies of the scripts (scheme/) when the program did
 * not; those copies lacked everything written since the switch.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void install_directory(char *, size_t);
extern void compiled_program_init(const char *);
extern int compiled_scripts_running(void);
extern const char *compiled_program_status(void);
extern int compiled_event(const char *, const char *);

/* the scripts run (the program registered every hook) */
int compiled_scripts = 0;

/* NEED_SCRIPTS 0: a test program (app.c, --test) may register fewer hooks */
int init_scheme(int need_scripts)
{
	char directory[4096];

	install_directory(directory, sizeof directory);
	compiled_program_init(directory);
	compiled_scripts = compiled_scripts_running();
	if (compiled_scripts) {
		compiled_event("init", "");     /* your files (compiled/start.scm) */
		return 1;
	}
	if (need_scripts) {
		fprintf(stderr,
			"Chezweb: the compiled scripts did not start (%s).\n"
			"They are %s/chezemax.wasm: build it with make, or run\n"
			"  chezweb --compile-scripts\n",
			compiled_program_status(), directory);
		exit(1);
	}
	return 0;
}
