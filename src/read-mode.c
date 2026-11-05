/* Native READ and copy-only Vim navigation. No text mutation is permitted.
 * Movement uses the same visual-row functions as the Emacs C keymap. */
#include "header.h"

void fe_read_mode(int mode)
{
	if (!curbp || mode < 0 || mode > 2) return;
	curbp->b_read_mode = mode;
	curbp->b_read_visual = curbp->b_read_pending = 0;
	curbp->b_read_count = 0;
	if (mode) curbp->b_flags |= B_READONLY;
	else curbp->b_flags &= ~B_READONLY;
}

int fe_read_state(char *name)
{
	for (buffer_t *bp = bheadp; bp; bp = bp->b_next)
		if (!strcmp(name, bp->b_bname))
			return bp->b_read_mode ? bp->b_read_mode + (bp->b_read_visual ? 2 : 0) : 0;
	return 0;
}

static point_t size(void) { return document_size(curbp); }
static int byte(point_t p) { return p >= 0 && p < size() ? *ptr(curbp, p) : -1; }
static point_t line_end(point_t p)
{
	while (p < size() && byte(p) != '\n') ++p;
	return p;
}
static point_t next_char(point_t p)
{
	int n = byte(p);
	if (n < 0) return size();
	point_t end = p + utf8_size((char_t)n);
	return end < size() ? end : size();
}
static point_t prev_char(point_t p)
{
	if (p <= 0) return 0;
	--p;
	while (p > 0 && (byte(p) & 0xc0) == 0x80) --p;
	return p;
}
static int class(point_t p)
{
	int b = byte(p);
	if (b < 0) return -1;
	if (isspace((unsigned char)b)) return 0;
	return b >= 128 || isalnum((unsigned char)b) || b == '_' ? 1 : 2;
}
static void word(int direction, int end)
{
	point_t p = curbp->b_point;
	if (direction < 0) {
		p = prev_char(p);
		while (p > 0 && class(p) == 0) p = prev_char(p);
		int c = class(p);
		while (p > 0 && class(prev_char(p)) == c) p = prev_char(p);
	} else if (end) {
		p = next_char(p);
		while (p < size() && class(p) == 0) p = next_char(p);
		int c = class(p);
		while (next_char(p) < size() && class(next_char(p)) == c) p = next_char(p);
		if (p == size() && p > 0) p = prev_char(p);
	} else {
		int c = class(p);
		while (p < size() && class(p) == c) p = next_char(p);
		while (p < size() && class(p) == 0) p = next_char(p);
	}
	curbp->b_point = p;
}

/* Match nested delimiters directly in the current buffer. */
static void match_bracket(void)
{
 const char *opens = "([{", *closes = ")]}", *q;
 point_t p = curbp->b_point, end = line_end(p);
 while (p < end && !(byte(p) > 0 && strchr("()[]{}", byte(p)))) p = next_char(p);
 if (p >= end) return;
 int b = byte(p), direction, other;
 if ((q = strchr(opens, b))) { direction = 1; other = closes[q-opens]; }
 else { q = strchr(closes, b); direction = -1; other = opens[q-closes]; }
 long depth = 1;
 for (point_t i = p + direction; i >= 0 && i < size(); i += direction) {
  int c = byte(i);
  if (c == b) ++depth;
  else if (c == other && --depth == 0) { curbp->b_point = i; return; }
 }
}

static void reset(void)
{
	curbp->b_read_count = 0;
	curbp->b_read_pending = 0;
}

static void copy_range(point_t start, point_t end)
{
	point_t origin = curbp->b_point;
	if (end > start) {
		curbp->b_mark = start;
		curbp->b_point = end;
		copy();
		/* A single Scheme notification keeps the kill ring and clipboard
		 * interoperable with Emacs paste; navigation never enters Scheme. */
		if (scrap) call_lisp_event("read-copy", (char *)scrap);
	}
	curbp->b_point = origin;
	curbp->b_mark = NOMARK;
	curbp->b_read_visual = 0;
	mark_active = 0;
}

int fe_read_key(char *key)
{
	if (!curbp || !curbp->b_read_mode) return 0;
	/* An explicit exit and the established search/help handlers stay in
	 * Scheme, where help/tag views return to their originating document. */
	if (!strcmp(key, "i") || !strcmp(key, "/") || !strcmp(key, "?") ||
	    !strcmp(key, "n") || !strcmp(key, "N")) { reset(); return 0; }
	if (!strcmp(key, "C-g") || !strcmp(key, "escape") || !strcmp(key, "esc")) {
		reset(); curbp->b_read_visual = 0; curbp->b_mark = NOMARK; mark_active = 0;
		return 1;
	}
	if (key[0] >= '0' && key[0] <= '9' && !key[1] && (key[0] != '0' || curbp->b_read_count)) {
		unsigned digit = key[0] - '0';
		if (curbp->b_read_count <= (1000000u - digit) / 10)
			curbp->b_read_count = curbp->b_read_count * 10 + digit;
		return 1;
	}
	unsigned count = curbp->b_read_count ? curbp->b_read_count : 1;
	if (!strcmp(key, "v")) {
		curbp->b_read_visual = !curbp->b_read_visual;
		curbp->b_mark = curbp->b_read_visual ? curbp->b_point : NOMARK;
		mark_active = curbp->b_read_visual; reset(); return 1;
	}
	if (!strcmp(key, "y")) {
		if (curbp->b_read_visual && curbp->b_mark != NOMARK) {
			point_t p = curbp->b_point, m = curbp->b_mark;
			copy_range(p < m ? p : m, next_char(p > m ? p : m)); reset();
		} else if (curbp->b_read_pending == 'y') {
			point_t start = lnstart(curbp, curbp->b_point), end = start;
			while (count-- && end < size()) {
				end = line_end(end);
				if (end < size()) ++end;
			}
			copy_range(start, end); reset();
		} else curbp->b_read_pending = 'y';
		return 1;
	}
	if (!strcmp(key, "z")) {
		if (curbp->b_read_pending == 'z') { if (curwp) recenter(); reset(); }
		else curbp->b_read_pending = 'z';
		return 1;
	}
	if (!strcmp(key, "g") && curbp->b_read_pending != 'g') {
		curbp->b_read_pending = 'g'; return 1;
	}
	if (!strcmp(key, "G") || (!strcmp(key, "g") && curbp->b_read_pending == 'g')) {
		if (!curbp->b_read_count && key[0] == 'G') curbp->b_point = size();
		else {
			point_t p = 0;
			while (--count && p < size()) { p = line_end(p); if (p < size()) ++p; }
			curbp->b_point = p;
		}
		reset(); return 1;
	}
	/* No deletion, paste, undo, insert/open-line, replace or replay in
	 * either mode. Never let these reach the former Vim editing handler. */
	if (strchr("dxpPuUoOaAIrRJ.:", key[0]) && key[0] && !key[1]) {
		msg("Copy-only mode: i returns to Emacs to edit"); reset(); return 1;
	}
	if (!strcmp(key, "C-y") || !strcmp(key, "C-r") || !strcmp(key, "C-k") ||
	    !strcmp(key, "C-w") || !strcmp(key, "backspace") || !strcmp(key, "delete") || !strcmp(key, "DEL") ||
	    !strcmp(key, "C-_") || !strcmp(key, "esc C-_") || !strcmp(key, "esc _") ||
	    !strcmp(key, "C-x u")) {
		msg("Copy-only mode: i returns to Emacs to edit"); reset(); return 1;
	}
	int motion = 1;
	if (!strcmp(key, "C-d") || !strcmp(key, "C-u")) {
		unsigned rows = curwp && curwp->w_rows > 1 ? curwp->w_rows / 2 : 1;
		count = count > 1000000u / rows ? 1000000u : count * rows;
	}
	while (count--) {
		point_t before = curbp->b_point;
		if (!strcmp(key, "down") || !strcmp(key, "j") || !strcmp(key, "C-n") ||
		    !strcmp(key, "RET") || !strcmp(key, "\r") || !strcmp(key, "\n") ||
		    !strcmp(key, "+") || !strcmp(key, "C-d")) down();
		else if (!strcmp(key, "up") || !strcmp(key, "k") || !strcmp(key, "C-p") ||
		         !strcmp(key, "-") || !strcmp(key, "C-u")) { if (curbp->b_point > 0) up(); }
		else if (!strcmp(key, "left") || !strcmp(key, "h")) curbp->b_point = prev_char(before);
		else if (!strcmp(key, "right") || !strcmp(key, "l") || !strcmp(key, " ")) curbp->b_point = next_char(before);
		else if (!strcmp(key, "%")) match_bracket();
		else if (!strcmp(key, "w")) word(1, 0);
		else if (!strcmp(key, "b")) word(-1, 0);
		else if (!strcmp(key, "e")) word(1, 1);
		else if (!strcmp(key, "0") || !strcmp(key, "home")) curbp->b_point = lnstart(curbp, before);
		else if (!strcmp(key, "$") || !strcmp(key, "end")) curbp->b_point = line_end(before);
		else if (!strcmp(key, "^")) {
			point_t p = lnstart(curbp, before);
			while (byte(p) == ' ' || byte(p) == '\t') ++p;
			curbp->b_point = p;
		} else { motion = 0; break; }
		if (curbp->b_point == before) break;
	}
	reset();
	if (curbp->b_read_visual) mark_active = 1;
	if (motion) return 1;
	/* Other printable keys cannot insert text. Named keys may retain
	 * normal Emacs window, file, help and search bindings. */
	return key[0] && (!key[1] || (unsigned char)key[0] >= 128);
}

int read_mode_event(const char *kind, const char *arg)
{
	if (strcmp(kind, "key") && strcmp(kind, "self-insert")) return 0;
	return fe_read_key((char *)arg);
}
