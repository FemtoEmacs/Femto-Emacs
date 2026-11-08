/*
 * backdoor.c -- M-x backdoor-claude and M-x backdoor-codex
 *
 * A window into the editor for an assistant that cannot see your screen.
 * While it is open (the mode line shows B/D), the editor writes one line
 * per key -- the key, point, the window's first character, the cursor's
 * row and column, the text's size -- plus notes from the C core (the
 * display's guard, a reframe) and from scripts ((fe-backdoor-note TEXT)).
 * The lines go to the buffer *backdoor*, refreshed only while a window
 * shows it, and to ~/.chezemax/backdoor.txt, at most once a second, where
 * the assistant reads them.
 *
 * Only the last BACKDOOR_LINES lines are kept (about two pages), each cut
 * at BACKDOOR_WIDTH bytes: a fixed 15 KB, whatever happens.  Closed again
 * (the same command), the memory and the buffer are freed and every hook
 * is one test of an int that is 0: the backdoor no longer exists.
 */
#include <stdarg.h>
#include <time.h>
#include <sys/stat.h>
#include "header.h"

#define BACKDOOR_LINES 120
#define BACKDOOR_WIDTH 128
#define BACKDOOR_BUFFER "*backdoor*"

int backdoor_on;                                /* all a closed backdoor is */

static char (*ring)[BACKDOOR_WIDTH];            /* the last lines, a circle */
static int ring_next, ring_count;
static unsigned long keys_seen;
static int dirty_buffer, dirty_file;
static time_t written;
static char who[8];
static char pending_key[48];                    /* the key being processed */

/* ~/.chezemax/backdoor.txt, the folder made if it is not there yet */
static void file_path(char *path, size_t n)
{
	const char *home = getenv("HOME");
	snprintf(path, n, "%s/.chezemax", home && *home ? home : ".");
	mkdir(path, 0755);
	snprintf(path, n, "%s/.chezemax/backdoor.txt", home && *home ? home : ".");
}

/* One line, cut to the ring's width; never a newline inside it */
static void add_line(const char *text)
{
	char *line = ring[ring_next];
	size_t i;

	for (i = 0; text[i] != '\0' && i < BACKDOOR_WIDTH - 1; i++)
		line[i] = (text[i] == '\n' || text[i] == '\r') ? ' ' : text[i];
	line[i] = '\0';
	ring_next = (ring_next + 1) % BACKDOOR_LINES;
	if (ring_count < BACKDOOR_LINES) ring_count++;
	dirty_buffer = dirty_file = 1;
}

/* The kept lines, oldest first, into TEXT (a caller's buffer large enough) */
static size_t ring_text(char *text)
{
	size_t len = 0;
	int k, start = (ring_next - ring_count + BACKDOOR_LINES) % BACKDOOR_LINES;

	for (k = 0; k < ring_count; k++) {
		const char *line = ring[(start + k) % BACKDOOR_LINES];
		size_t n = strlen(line);
		memcpy(text + len, line, n);
		len += n;
		text[len++] = '\n';
	}
	text[len] = '\0';
	return len;
}

static void write_file(void)
{
	char text[BACKDOOR_LINES * BACKDOOR_WIDTH + 1];
	char path[4096], temp[4200];
	size_t len = ring_text(text);
	FILE *f;

	file_path(path, sizeof path);
	snprintf(temp, sizeof temp, "%s.new", path);
	if ((f = fopen(temp, "w")) == NULL) return;
	int complete = fwrite(text, 1, len, f) == len;
	if (fclose(f) != 0) complete = 0;
	if (complete && rename(temp, path) == 0) dirty_file = 0;
	else remove(temp);
	written = time(NULL);
}

/* The note of a C function, a script or a test, formatted as printf does */
void backdoor_note(const char *format, ...)
{
	char text[BACKDOOR_WIDTH];
	va_list ap;

	if (!backdoor_on) return;
	va_start(ap, format);
	vsnprintf(text, sizeof text, format, ap);
	va_end(ap);
	add_line(text);
}

/* (fe-backdoor-note TEXT): a script's note; nothing at all when closed */
void fe_backdoor_note(char *text)
{
	if (backdoor_on) backdoor_note("note: %s", text);
}

/* The key just read (main.c): its name, or the text it typed */
void backdoor_key(char_t *input, keymap_t *key)
{
	size_t i = 0;
	const char_t *p;

	if (key != NULL) {
		snprintf(pending_key, sizeof pending_key, "%s", key->key_name);
		return;
	}
	for (p = input; p != NULL && *p != '\0' && i < sizeof pending_key - 5; p++) {
		if (*p < 32 || *p == 127) i += (size_t) snprintf(pending_key + i, 5, "\\x%02x", *p);
		else pending_key[i++] = (char) *p;
	}
	pending_key[i] = '\0';
}

/* After each redisplay (main.c): the state the key left */
void backdoor_shown(void)
{
	if (pending_key[0] != '\0') {
		backdoor_note("#%lu %s pt=%ld page=%ld cur=%d,%d size=%ld %s",
			      ++keys_seen, pending_key, (long) curbp->b_point,
			      (long) curbp->b_page, curbp->b_row, curbp->b_col,
			      (long) document_size(curbp), curbp->b_bname);
		pending_key[0] = '\0';
	}
	if (dirty_file && time(NULL) != written) write_file();
}

/* Before each redisplay (main.c): *backdoor* shows the lines, if shown */
void backdoor_refresh(void)
{
	char text[BACKDOOR_LINES * BACKDOOR_WIDTH + 1];
	buffer_t *bp;
	size_t len;

	if (!dirty_buffer) return;
	bp = find_buffer(BACKDOOR_BUFFER, FALSE);
	if (bp == NULL || bp->b_cnt == 0) return;      /* not on screen: later */
	dirty_buffer = 0;
	len = ring_text(text);
	zero_buffer(bp);
	if ((point_t) len > bp->b_egap - bp->b_gap && !growgap(bp, (point_t) len)) return;
	memcpy(bp->b_gap, text, len);
	bp->b_gap += len;
	bp->b_point = pos(bp, bp->b_egap);
	bp->b_flags |= B_SPECIAL;
	bp->b_flags &= ~B_MODIFIED;
	b2w_all_windows(bp);
}

static void open_backdoor(const char *name)
{
	ring = calloc(BACKDOOR_LINES, sizeof *ring);
	if (ring == NULL) { msg(m_alloc); return; }
	ring_next = ring_count = 0;
	keys_seen = 0;
	pending_key[0] = '\0';
	snprintf(who, sizeof who, "%s", name);
	backdoor_on = 1;
	backdoor_note("backdoor opened for %s: one line a key, the last %d kept", who, BACKDOOR_LINES);
	(void) find_buffer(BACKDOOR_BUFFER, TRUE);
	write_file();
	msg("Backdoor open (B/D) for %s: C-x b *backdoor*; ~/.chezemax/backdoor.txt", who);
}

static void close_backdoor(void)
{
	buffer_t *bp = find_buffer(BACKDOOR_BUFFER, FALSE);

	backdoor_note("backdoor closed");
	write_file();                   /* the file stays for the assistant */
	backdoor_on = 0;
	free(ring);
	ring = NULL;
	ring_count = ring_next = 0;
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
