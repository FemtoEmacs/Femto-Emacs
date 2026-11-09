/*
 * backdoor.c -- M-x backdoor-claude and M-x backdoor-codex
 *
 * A window into the editor for an assistant that cannot see your screen.
 * While it is open (the mode line shows B/D), the editor writes one line
 * per key -- the key, point, the window's first character (page), the
 * cursor's row and column, the text's size -- and, under it, indented,
 * what the key changed that the assistant asked to watch.  Notes come from
 * the C core (the display's guard, a reframe, how the display framed the
 * page) and from scripts ((fe-backdoor-note TEXT)).  The lines go to the
 * buffer *backdoor*, refreshed only while a window shows it, and to
 * ~/.chezemax/backdoor.txt, at most once a second, where the assistant
 * reads them.
 *
 * The assistant configures it, before you open it, in
 * ~/.chezemax/backdoor-claude.conf (or -codex.conf), else
 * ~/.chezemax/backdoor.conf: one option a line, # a comment.
 *
 *   lines N            lines kept, 20-5000 (120)
 *   mouse off|clicks|all   mouse events recorded: none; presses, releases,
 *                      drags and the wheel (the default); also bare motion
 *   repeats collapse|keep  identical consecutive key lines as one,
 *                      "#A..B ... (N times)" (collapse, the default)
 *   watch page point mark  what is followed (page): every change of it is
 *                      said, with who made it -- the command (and which C
 *                      function a script called), or the display, and why
 *   text N             the first N bytes a key inserted, escaped (0)
 *   time [MS]          milliseconds of the command and of the display, on
 *                      the key's line; with MS, only for keys at least that
 *                      slow (collapsed keys: the slowest)
 *   alloc              the process's minor page faults, on the key's line;
 *                      under it, when they change, the buffer's capacity
 *                      and the process's maximum resident size
 *   watch none         nothing followed
 *
 * The first lines say what was in effect: the file read, the options, the
 * front end, the screen and the window; an option not understood is said
 * there too.
 *
 * Closed (the same command), the memory and the buffer are freed and every
 * hook -- in main.c, bridge.c (each C function a script calls: a pointer
 * that is NULL) and display.c -- is one test of an int that is 0: the
 * backdoor no longer exists.  The configuration is read only when it opens.
 */
#include <stdarg.h>
#include <ctype.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/resource.h>
#include "header.h"
#include "screen.h"

#define BACKDOOR_WIDTH 160
#define BACKDOOR_DETAILS 24             /* lines under one key, at most */
#define BACKDOOR_BUFFER "*backdoor*"
#ifdef __APPLE__
#define MAXRSS_UNIT "bytes"             /* getrusage's ru_maxrss */
#else
#define MAXRSS_UNIT "KB"
#endif

int backdoor_on;                        /* all a closed backdoor is */
int backdoor_watch;                     /* BACKDOOR_PAGE ... (header.h) */

/* the options, read when it opens */
static int opt_lines = 120, opt_mouse = 1, opt_collapse = 1, opt_text;
static int opt_time = -1, opt_alloc;    /* time: -1 off, else the threshold */

typedef struct {
	char text[BACKDOOR_WIDTH];
	unsigned long first, last;      /* key numbers; 0: a note */
	unsigned long count;            /* the keys it stands for */
	double slowest;                 /* time: its slowest key, ms */
	double command, display;        /*   and that key's two parts */
	long faults;                    /* alloc: minor page faults, all */
	int timed;                      /* time printed on this line */
} line_t;

static line_t *ring;                    /* the last lines, a circle */
static int ring_size, ring_next, ring_count;
#define HEADER_LINES 6
static char header[HEADER_LINES][BACKDOOR_WIDTH]; /* what was in effect: kept */
static int nheader, opening;
static char *scratch;                   /* the file's text, made at writing */
static unsigned long keys_seen;
static int dirty_buffer, dirty_file;
static time_t written;
static char who[8];

/* the key being processed and what it found */
typedef struct {
	buffer_t *bp;
	point_t page, point, mark, size, capacity;
	double ms;
	long maxrss, minflt;
} state_t;
static int pending;                     /* a key is being processed */
static int pending_skip;                /* a mouse event not to record */
static char pending_key[64], pending_desc[40];
static state_t before, commanded, last;
static char details[BACKDOOR_DETAILS][BACKDOOR_WIDTH];
static int ndetails;

/* ~/.chezemax/NAME, the folder made if it is not there yet */
static void file_path(char *path, size_t n, const char *name)
{
	const char *home = getenv("HOME");
	snprintf(path, n, "%s/.chezemax", home && *home ? home : ".");
	mkdir(path, 0755);
	snprintf(path, n, "%s/.chezemax/%s", home && *home ? home : ".", name);
}

/* One line, cut to the ring's width; never a newline inside it */
static void copy_line(char *line, const char *text)
{
	size_t i;

	for (i = 0; text[i] != '\0' && i < BACKDOOR_WIDTH - 1; i++)
		line[i] = (text[i] == '\n' || text[i] == '\r') ? ' ' : text[i];
	line[i] = '\0';
}

static void add_line(const char *text, unsigned long key)
{
	line_t *line = &ring[ring_next];

	copy_line(line->text, text);
	line->first = line->last = key;
	line->count = 1;
	line->timed = 0;
	line->faults = -1;
	ring_next = (ring_next + 1) % ring_size;
	if (ring_count < ring_size) ring_count++;
	dirty_buffer = dirty_file = 1;
}

/* The kept lines, oldest first, into scratch */
static size_t ring_text(void)
{
	size_t len = 0;
	int k, start = (ring_next - ring_count + ring_size) % ring_size;

	for (k = 0; k < nheader; k++)
		len += (size_t) sprintf(scratch + len, "%s\n", header[k]);
	for (k = 0; k < ring_count; k++) {
		const line_t *line = &ring[(start + k) % ring_size];
		if (line->first == 0)
			len += (size_t) sprintf(scratch + len, "%s", line->text);
		else if (line->first == line->last)
			len += (size_t) sprintf(scratch + len, "#%lu %s", line->first, line->text);
		else
			len += (size_t) sprintf(scratch + len, "#%lu..%lu %s (%lu times)",
						line->first, line->last, line->text, line->count);
		if (line->timed)
			len += (size_t) sprintf(scratch + len, " | %s%.1f ms: command %.1f, display %.1f",
						line->count > 1 ? "slowest " : "", line->slowest,
						line->command, line->display);
		if (line->faults >= 0)
			len += (size_t) sprintf(scratch + len, " | faults %ld", line->faults);
		scratch[len++] = '\n';
	}
	scratch[len] = '\0';
	return len;
}

static void write_file(void)
{
	char path[4096], temp[4200];
	size_t len = ring_text();
	FILE *f;

	file_path(path, sizeof path, "backdoor.txt");
	snprintf(temp, sizeof temp, "%s.new", path);
	if ((f = fopen(temp, "w")) == NULL) return;
	int complete = fwrite(scratch, 1, len, f) == len;
	if (fclose(f) != 0) complete = 0;
	if (complete && rename(temp, path) == 0) dirty_file = 0;
	else remove(temp);
	written = time(NULL);
}

static void detail(const char *format, ...)
{
	char text[BACKDOOR_WIDTH];
	va_list ap;

	va_start(ap, format);
	vsnprintf(text, sizeof text, format, ap);
	va_end(ap);
	if (opening) { if (nheader < HEADER_LINES) copy_line(header[nheader++], text); return; }
	if (!pending) { add_line(text, 0); return; }
	if (ndetails < BACKDOOR_DETAILS) copy_line(details[ndetails++], text);
	else if (ndetails == BACKDOOR_DETAILS)
		copy_line(details[BACKDOOR_DETAILS - 1], "  (more lines for this key were dropped)");
}

/* The note of a C function, a script or a test, formatted as printf does;
 * while a key is processed, it goes under that key's line */
void backdoor_note(const char *format, ...)
{
	char text[BACKDOOR_WIDTH];
	va_list ap;

	if (!backdoor_on) return;
	va_start(ap, format);
	vsnprintf(text, sizeof text, format, ap);
	va_end(ap);
	detail("%s", text);
}

/* (fe-backdoor-note TEXT): a script's note; nothing at all when closed */
void fe_backdoor_note(char *text)
{
	if (backdoor_on) backdoor_note("note: %s", text);
}

/* ------------------------------------------------------------------ */
/* the state a key found and left                                     */
/* ------------------------------------------------------------------ */

static double now_ms(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

static void take(state_t *s)
{
	buffer_t *bp = curbp;

	s->bp = bp;
	s->page = bp ? bp->b_page : 0;
	s->point = bp ? bp->b_point : 0;
	s->mark = bp ? bp->b_mark : 0;
	s->size = bp ? document_size(bp) : 0;
	s->capacity = bp ? (point_t) (bp->b_ebuf - bp->b_buf) : 0;
	if (opt_time >= 0) s->ms = now_ms();
	if (opt_alloc) {
		struct rusage u;
		if (getrusage(RUSAGE_SELF, &u) == 0) { s->maxrss = u.ru_maxrss; s->minflt = u.ru_minflt; }
	}
}

/* The last line said for each watched field, so that a run of changes by
 * the same hand (the display scanning up a line at a time) is one line:
 * "page 261 -> 81 by ... (24 changes)" */
static struct { int index, count; long from; char who[100]; } said[3];
static int phase;                       /* 0 the command, 1 the display */

static void change(int field, const char *name, long from, long to, const char *who_did)
{
	int i = said[field].index;

	if (pending && i >= 0 && i < ndetails && i >= ndetails - 3 && !strcmp(said[field].who, who_did)) {
		said[field].count++;
		snprintf(details[i], BACKDOOR_WIDTH, "  %s %ld -> %ld %s (%d changes)",
			 name, said[field].from, to, who_did, said[field].count);
		return;
	}
	detail("  %s %ld -> %ld %s", name, from, to, who_did);
	said[field].index = pending ? ndetails - 1 : -1;
	said[field].count = 1;
	said[field].from = from;
	snprintf(said[field].who, sizeof said[field].who, "%s", who_did);
}

/* what changed between A and B that is watched, said as done by WHO */
static void changes(const state_t *a, const state_t *b, const char *who_did)
{
	if (a->bp != b->bp) {
		if (backdoor_watch)
			detail("  buffer %s -> %s %s", a->bp ? a->bp->b_bname : "-",
			       b->bp ? b->bp->b_bname : "-", who_did);
		said[0].index = said[1].index = said[2].index = -1;
		return;
	}
	if ((backdoor_watch & BACKDOOR_PAGE) && a->page != b->page)
		change(0, "page", (long) a->page, (long) b->page, who_did);
	if ((backdoor_watch & BACKDOOR_POINT) && a->point != b->point)
		change(1, "point", (long) a->point, (long) b->point, who_did);
	if ((backdoor_watch & BACKDOOR_MARK) && a->mark != b->mark)
		change(2, "mark", (long) a->mark, (long) b->mark, who_did);
}

/* the watched fields of the current buffer, cheaply: no clock, no rusage */
static void glance(state_t *s)
{
	s->bp = curbp;
	s->page = curbp ? curbp->b_page : 0;
	s->point = curbp ? curbp->b_point : 0;
	s->mark = curbp ? curbp->b_mark : 0;
}

/* Around each C function a script calls (bridge.c): what changed before
 * it, done by the C core, and what changed in it */
static void backdoor_ccall(const char *name, int after)
{
	state_t now;
	char by[120];

	if (!pending) return;
	glance(&now);
	if (now.bp == last.bp && now.page == last.page && now.point == last.point && now.mark == last.mark)
		return;
	if (after)
		snprintf(by, sizeof by, "in %s (a C function a script called) during the %s",
			 name, phase ? "display" : "command");
	else
		snprintf(by, sizeof by, "by the C core during the %s, before a script called %s",
			 phase ? "display" : "command", name);
	changes(&last, &now, by);
	last.bp = now.bp; last.page = now.page; last.point = now.point; last.mark = now.mark;
}

/* ------------------------------------------------------------------ */
/* the key                                                            */
/* ------------------------------------------------------------------ */

/* A mouse event, named: "mouse press 1 at 13,4", "mouse wheel up", ...;
 * 0 if it is not to be recorded (the mouse option) */
static int name_mouse(char *s, size_t n)
{
	int b = mouse_button, motion = (b & 32) != 0, wheel = (b & 64) != 0;
	int button = b & 3;

	if (opt_mouse == 0) return 0;
	if (wheel)
		snprintf(s, n, "mouse wheel %s at %d,%d", button == 0 ? "up" : button == 1 ? "down" : "side",
			 mouse_row, mouse_col);
	else if (motion && button == 3) {
		if (opt_mouse < 2) return 0;
		snprintf(s, n, "mouse move at %d,%d", mouse_row, mouse_col);
	} else if (motion)
		snprintf(s, n, "mouse drag %d at %d,%d", button + 1, mouse_row, mouse_col);
	else if (mouse_release)
		snprintf(s, n, "mouse release at %d,%d", mouse_row, mouse_col);
	else
		snprintf(s, n, "mouse press %d at %d,%d", button + 1, mouse_row, mouse_col);
	return 1;
}

/* The key just read (main.c): its name, or the text it typed */
void backdoor_key(char_t *input, keymap_t *key)
{
	size_t i = 0;
	const char_t *p;

	pending = 1;
	pending_skip = 0;
	ndetails = 0;
	pending_desc[0] = '\0';
	if (key != NULL) {
		if (key->func == editor_mouse_event)
			pending_skip = !name_mouse(pending_key, sizeof pending_key);
		else {
			snprintf(pending_key, sizeof pending_key, "%s", key->key_name);
			if (key->key_desc) snprintf(pending_desc, sizeof pending_desc, "%s", key->key_desc);
		}
	} else {
		for (p = input; p != NULL && *p != '\0' && i < sizeof pending_key - 5; p++) {
			if (*p < 32 || *p == 127) i += (size_t) snprintf(pending_key + i, 5, "\\x%02x", *p);
			else pending_key[i++] = (char) *p;
		}
		pending_key[i] = '\0';
	}
	take(&before);
	last = before;
	phase = 0;
	said[0].index = said[1].index = said[2].index = -1;
}

/* The command has run (main.c), the display not yet */
void backdoor_commanded(void)
{
	char by[80];

	if (!pending) return;
	take(&commanded);
	snprintf(by, sizeof by, "by the command%s%s%s", *pending_desc ? " (" : "",
		 pending_desc, *pending_desc ? ")" : "");
	changes(&last, &commanded, by);
	last = commanded;
	phase = 1;
}

/* The bytes [FROM, FROM+N) of the current buffer, escaped, at most LIMIT */
static void inserted_text(char *s, size_t size, point_t from, point_t n, int limit)
{
	size_t k = 0;
	point_t i;

	for (i = 0; i < n && i < limit && k + 6 < size; i++) {
		unsigned char c = *ptr(curbp, from + i);
		if (c == '\n') { s[k++] = '\\'; s[k++] = 'n'; }
		else if (c == '\r') { s[k++] = '\\'; s[k++] = 'r'; }
		else if (c == '\t') { s[k++] = '\\'; s[k++] = 't'; }
		else if (c == '"' || c == '\\') { s[k++] = '\\'; s[k++] = (char) c; }
		else if (c < 32 || c == 127) k += (size_t) snprintf(s + k, 5, "\\x%02x", c);
		else s[k++] = (char) c;
	}
	/* never end inside a character */
	while (k > 0 && ((unsigned char) s[k - 1] & 0xC0) == 0x80) k--;
	if (k > 0 && ((unsigned char) s[k - 1] & 0x80)) k--;
	s[k] = '\0';
	if (i < n) snprintf(s + k, size - k, "...");
}

/* After each redisplay (main.c): the key's line and what it changed.
 * Times and page faults go on the key's own line, so that keys that only
 * differ in them still collapse (the slowest is kept); what a key changed
 * goes under it, and a key that changed something never collapses. */
void backdoor_shown(void)
{
	state_t shown;
	char line[BACKDOOR_WIDTH], text_of_line[BACKDOOR_WIDTH];
	double command = 0, display = 0;
	int k, timed = 0;

	if (pending) {
		take(&shown);
		changes(&last, &shown, "by the display");
		keys_seen++;
		if (opt_text > 0 && commanded.bp == before.bp && commanded.size != before.size) {
			point_t d = commanded.size - before.size;
			char text[BACKDOOR_WIDTH];
			if (d > 0 && commanded.point - d >= 0 && commanded.point <= shown.size && shown.bp == commanded.bp) {
				inserted_text(text, sizeof text - 40, commanded.point - d, d, opt_text);
				detail("  text +%ld at %ld \"%s\"", (long) d, (long) (commanded.point - d), text);
			} else
				detail("  text %+ld", (long) d);
		}
		if (opt_time >= 0) {
			command = commanded.ms - before.ms;
			display = shown.ms - commanded.ms;
			timed = command + display >= opt_time;
		}
		if (opt_alloc && (shown.capacity != before.capacity || shown.maxrss != before.maxrss))
			detail("  alloc buffer %+ld bytes (capacity %ld), max resident size %+ld (%s)",
			       (long) (shown.capacity - before.capacity), (long) shown.capacity,
			       shown.maxrss - before.maxrss, MAXRSS_UNIT);
		pending = 0;
		if (!pending_skip || ndetails > 0) {
			line_t *prev = ring_count ? &ring[(ring_next - 1 + ring_size) % ring_size] : NULL;
			snprintf(line, sizeof line, "%s pt=%ld page=%ld cur=%d,%d size=%ld %s",
				 pending_skip ? "mouse move" : pending_key, (long) curbp->b_point,
				 (long) curbp->b_page, curbp->b_row, curbp->b_col,
				 (long) document_size(curbp), curbp->b_bname);
			copy_line(text_of_line, line);
			if (opt_collapse && ndetails == 0 && prev && prev->first != 0 &&
			    !strcmp(prev->text, text_of_line)) {
				prev->last = keys_seen;
				prev->count++;
			} else {
				add_line(line, keys_seen);
				prev = &ring[(ring_next - 1 + ring_size) % ring_size];
				for (k = 0; k < ndetails; k++) add_line(details[k], 0);
			}
			if (timed && (!prev->timed || command + display > prev->slowest)) {
				prev->timed = 1;
				prev->slowest = command + display;
				prev->command = command;
				prev->display = display;
			}
			if (opt_alloc) prev->faults = (prev->faults < 0 ? 0 : prev->faults) + (shown.minflt - before.minflt);
			dirty_buffer = dirty_file = 1;
		}
		ndetails = 0;
	}
	if (dirty_file && time(NULL) != written) write_file();
}

/* Before each redisplay (main.c): *backdoor* shows the lines, if shown */
void backdoor_refresh(void)
{
	buffer_t *bp;
	size_t len;

	if (!dirty_buffer) return;
	bp = find_buffer(BACKDOOR_BUFFER, FALSE);
	if (bp == NULL || bp->b_cnt == 0) return;      /* not on screen: later */
	dirty_buffer = 0;
	len = ring_text();
	zero_buffer(bp);
	if ((point_t) len > bp->b_egap - bp->b_gap && !growgap(bp, (point_t) len)) return;
	memcpy(bp->b_gap, scratch, len);
	bp->b_gap += len;
	bp->b_point = pos(bp, bp->b_egap);
	bp->b_flags |= B_SPECIAL;
	bp->b_flags &= ~B_MODIFIED;
	b2w_all_windows(bp);
}

/* ------------------------------------------------------------------ */
/* the configuration                                                  */
/* ------------------------------------------------------------------ */

static void defaults(void)
{
	opt_lines = 120; opt_mouse = 1; opt_collapse = 1; opt_text = 0;
	opt_time = -1; opt_alloc = 0; backdoor_watch = BACKDOOR_PAGE;
}

/* ~/.chezemax/backdoor-WHO.conf, else backdoor.conf: the options; the
 * problems found, for the header, in PROBLEMS */
static void configure(const char *name, char *used, size_t usize, char *problems, size_t psize)
{
	char path[4096], lower[16], line[256];
	FILE *f;
	int n = 0, i;

	defaults();
	problems[0] = '\0';
	for (i = 0; name[i] && i < (int) sizeof lower - 1; i++) lower[i] = (char) tolower((unsigned char) name[i]);
	lower[i] = '\0';
	snprintf(line, sizeof line, "backdoor-%s.conf", lower);
	file_path(path, sizeof path, line);
	if ((f = fopen(path, "r")) == NULL) {
		file_path(path, sizeof path, "backdoor.conf");
		f = fopen(path, "r");
	}
	if (f == NULL) { snprintf(used, usize, "no backdoor.conf: the defaults"); return; }
	snprintf(used, usize, "%s", strrchr(path, '/') + 1);
	while (fgets(line, sizeof line, f)) {
		char *word, *rest = line, *hash = strchr(line, '#');
		n++;
		if (hash) *hash = '\0';
		if ((word = strtok(rest, " \t\r\n")) == NULL) continue;
		char *arg = strtok(NULL, " \t\r\n");
		size_t k = strlen(problems);
		if (!strcmp(word, "lines") && arg && atoi(arg) >= 20 && atoi(arg) <= 5000)
			opt_lines = atoi(arg);
		else if (!strcmp(word, "mouse") && arg && !strcmp(arg, "off")) opt_mouse = 0;
		else if (!strcmp(word, "mouse") && arg && !strcmp(arg, "clicks")) opt_mouse = 1;
		else if (!strcmp(word, "mouse") && arg && !strcmp(arg, "all")) opt_mouse = 2;
		else if (!strcmp(word, "repeats") && arg && !strcmp(arg, "collapse")) opt_collapse = 1;
		else if (!strcmp(word, "repeats") && arg && !strcmp(arg, "keep")) opt_collapse = 0;
		else if (!strcmp(word, "text") && arg && atoi(arg) >= 0) opt_text = atoi(arg) > 120 ? 120 : atoi(arg);
		else if (!strcmp(word, "time")) opt_time = arg ? (atoi(arg) > 0 ? atoi(arg) : 0) : 0;
		else if (!strcmp(word, "alloc") && !arg) opt_alloc = 1;
		else if (!strcmp(word, "watch") && arg) {
			int w = 0, bad = 0;
			for (; arg; arg = strtok(NULL, " \t\r\n")) {
				if (!strcmp(arg, "page")) w |= BACKDOOR_PAGE;
				else if (!strcmp(arg, "point")) w |= BACKDOOR_POINT;
				else if (!strcmp(arg, "mark")) w |= BACKDOOR_MARK;
				else if (strcmp(arg, "none")) bad = 1;
			}
			if (bad) snprintf(problems + k, psize - k, " line %d: watch page, point, mark or none;", n);
			else backdoor_watch = w;
		} else
			snprintf(problems + k, psize - k, " line %d: \"%s\" not understood;", n, word);
	}
	fclose(f);
}

static void open_backdoor(const char *name)
{
	char used[80], problems[400], text[BACKDOOR_WIDTH], watch[40];
	time_t t = time(NULL);
	struct tm *tm = localtime(&t);

	configure(name, used, sizeof used, problems, sizeof problems);
	snprintf(who, sizeof who, "%s", name);
	/* the header, first in the file whatever else is dropped */
	nheader = 0;
	pending = ndetails = 0;
	backdoor_on = opening = 1;
	strftime(text, sizeof text, "%Y-%m-%d %H:%M:%S", tm);
	backdoor_note("backdoor opened for %s, %s: one line a key, at most %d lines", who, text, opt_lines);
	snprintf(watch, sizeof watch, "%s%s%s%s", backdoor_watch & BACKDOOR_PAGE ? " page" : "",
		 backdoor_watch & BACKDOOR_POINT ? " point" : "", backdoor_watch & BACKDOOR_MARK ? " mark" : "",
		 backdoor_watch ? "" : " none");
	backdoor_note("options (%s): mouse %s, repeats %s, watch%s, text %d, time %s%s, alloc %s",
		      used, opt_mouse == 0 ? "off" : opt_mouse == 1 ? "clicks" : "all",
		      opt_collapse ? "collapse" : "keep", watch, opt_text,
		      opt_time < 0 ? "off" : "on", opt_time > 0 ? " (slow keys)" : "", opt_alloc ? "on" : "off");
	if (problems[0]) backdoor_note("not understood in %s:%s", used, problems);
	backdoor_note("front end %s, screen %d rows x %d columns, window %d rows from row %d, buffer %s (%s)",
		      screen_backend(), screen_rows(), screen_cols(), curwp ? curwp->w_rows : 0,
		      curwp ? curwp->w_top : 0, curbp->b_bname, curbp->b_fname[0] ? curbp->b_fname : "no file");
	opening = 0;
	ring_size = opt_lines - nheader;
	ring = calloc((size_t) ring_size, sizeof *ring);
	scratch = malloc((size_t) opt_lines * (BACKDOOR_WIDTH + 64) + 1);
	if (ring == NULL || scratch == NULL) {
		free(ring); free(scratch); ring = NULL; scratch = NULL;
		backdoor_on = 0; backdoor_watch = 0; msg(m_alloc); return;
	}
	ring_next = ring_count = 0;
	keys_seen = 0;
	if (backdoor_watch) bridge_around_call = backdoor_ccall;
	(void) find_buffer(BACKDOOR_BUFFER, TRUE);
	write_file();
	msg("Backdoor open (B/D) for %s: C-x b *backdoor*; ~/.chezemax/backdoor.txt", who);
}

static void close_backdoor(void)
{
	buffer_t *bp = find_buffer(BACKDOOR_BUFFER, FALSE);

	pending = 0;
	backdoor_note("backdoor closed");
	write_file();                   /* the file stays for the assistant */
	backdoor_on = 0;
	backdoor_watch = 0;
	bridge_around_call = NULL;
	free(ring);
	free(scratch);
	ring = NULL;
	scratch = NULL;
	ring_count = ring_next = ring_size = nheader = 0;
	dirty_buffer = dirty_file = 0;
	if (bp != NULL && bp->b_cnt == 0) delete_buffer(bp);
	msg("Backdoor closed; its last lines are in ~/.chezemax/backdoor.txt");
}

static void toggle(const char *name)
{
	if (backdoor_on) close_backdoor();
	else open_backdoor(name);
}

void backdoor_claude(void) { toggle("Claude"); }
void backdoor_codex(void) { toggle("Codex"); }
