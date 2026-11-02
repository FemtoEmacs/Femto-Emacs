/* lineedit.c, Chezemax: editing the answer to a prompt */

#include "header.h"

/*
 * The prompts of the C core (C-x C-w, C-x C-f, C-x C-s for a new buffer,
 * M-g g, query-replace ...) and Scheme's PROMPT read their answer here.
 * The answer can be edited anywhere in it, as in Emacs's minibuffer:
 *
 *   left, right, C-b, C-f        a character back or forward
 *   C-left, C-right, M-b, M-f    a word back or forward
 *   home, end, C-a, C-e          the start or the end of the answer
 *   backspace                    delete the character before the cursor
 *   delete, C-d                  delete the character at the cursor
 *   C-k                          delete from the cursor to the end
 *   C-u                          delete the whole answer
 *   RET accepts, C-g cancels; TAB completes, when the prompt can
 *
 * Typed text goes in at the cursor.  The text is UTF-8: the cursor moves
 * by characters, never into the middle of one.  Mouse reports and keys
 * without a meaning here are read whole and ignored, so they never turn
 * into text.
 */

static int is_continuation(int b) { return (b & 0xC0) == 0x80; }

/* the characters in the first N bytes of S */
static int columns(const char *s, int n)
{
	int i, c = 0;

	for (i = 0; i < n && s[i]; i++)
		if (!is_continuation((unsigned char) s[i])) c++;
	return c;
}

static int char_before(const char *buf, int pos)
{
	if (pos <= 0) return 0;
	pos--;
	while (pos > 0 && is_continuation((unsigned char) buf[pos])) pos--;
	return pos;
}

static int char_after(const char *buf, int len, int pos)
{
	if (pos >= len) return len;
	pos++;
	while (pos < len && is_continuation((unsigned char) buf[pos])) pos++;
	return pos;
}

static int is_word_byte(int b) { return isalnum(b) || b >= 0x80; }

static int word_before(const char *buf, int pos)
{
	while (pos > 0 && !is_word_byte((unsigned char) buf[char_before(buf, pos)]))
		pos = char_before(buf, pos);
	while (pos > 0 && is_word_byte((unsigned char) buf[char_before(buf, pos)]))
		pos = char_before(buf, pos);
	return pos;
}

static int word_after(const char *buf, int len, int pos)
{
	while (pos < len && !is_word_byte((unsigned char) buf[pos])) pos = char_after(buf, len, pos);
	while (pos < len && is_word_byte((unsigned char) buf[pos])) pos = char_after(buf, len, pos);
	return pos;
}

/* delete the bytes FROM to TO of BUF (of LEN bytes); the new length */
static int delete_bytes(char *buf, int len, int from, int to)
{
	memmove(buf + from, buf + to, (size_t) (len - to + 1));
	return len - (to - from);
}

/* the prompt and the answer, scrolled so that the cursor is visible */
static void show(const char *prompt, const char *buf, int len, int pos)
{
	int width = screen_cols() - 1;
	int pcols = columns(prompt, (int) strlen(prompt));
	int room = width - pcols;
	int first = 0, shown, end;
	char *piece;

	if (room < 8) room = 8;
	/* scroll: the cursor stays within the room after the prompt */
	while (columns(buf + first, pos - first) >= room)
		first = char_after(buf, len, first);
	end = first;
	shown = 0;
	while (end < len && shown < room) {
		end = char_after(buf, len, end);
		shown++;
	}
	screen_mvaddstr(MSGLINE, 0, prompt);
	piece = malloc((size_t) (end - first + 1));
	if (piece != NULL) {
		memcpy(piece, buf + first, (size_t) (end - first));
		piece[end - first] = '\0';
		screen_addstr(piece);
		free(piece);
	}
	screen_clrtoeol();
	screen_move(MSGLINE, pcols + columns(buf + first, pos - first));
	screen_refresh();
}

/*
 * After ESC: read the rest of an escape sequence.  Its meaning here, or
 * 0: one of 'L' 'R' (character), 'l' 'r' (word), 'H' 'E' (start, end),
 * 'D' (delete at the cursor).
 */
static int read_escape(void)
{
	int c = read_key_byte(), param = 0, modifier = 0, final;

	if (c == 'b' || c == 'B') return 'l';
	if (c == 'f' || c == 'F') return 'r';
	if (c != '[' && c != 'O') return 0;
	final = read_key_byte();
	if (c == '[' && final == 'M') {          /* X10 mouse report: three more bytes */
		(void) read_key_byte();
		(void) read_key_byte();
		(void) read_key_byte();
		return 0;
	}
	while (final >= 0x20 && final <= 0x3F) { /* parameters: digits ; < ? */
		if (final >= '0' && final <= '9') {
			param = param * 10 + (final - '0');
		} else if (final == ';') {
			modifier = param;
			param = 0;
		}
		final = read_key_byte();
	}
	/* "1;5D" is C-left: the first number is 1, the second the modifier */
	switch (final) {
	case 'D': return (modifier == 1 && param >= 2) ? 'l' : 'L';
	case 'C': return (modifier == 1 && param >= 2) ? 'r' : 'R';
	case 'H': return 'H';
	case 'F': return 'E';
	case '~':
		if (param == 1 || param == 7) return 'H';
		if (param == 4 || param == 8) return 'E';
		if (param == 3) return 'D';
		return 0;
	default: return 0;
	}
}

/*
 * Edit the answer to PROMPT in BUF (NBUF bytes).  F_CLEAR starts from an
 * empty answer, F_NONE from what BUF holds.  COMPLETE, when not NULL, is
 * called for TAB with the answer, its length and whether the key before
 * was TAB too; it returns the new length.  TRUE when RET accepted a
 * non-empty answer.
 */
int line_edit(char *prompt, char *buf, int nbuf, int flag,
	      int (*complete)(char *buf, int nbuf, int len, int again))
{
	int len, pos, c, last_tab = 0;

	if (flag == F_CLEAR) buf[0] = '\0';
	len = (int) strlen(buf);
	if (len > nbuf - 1) {
		len = nbuf - 1;
		buf[len] = '\0';
	}
	pos = len;

	for (;;) {
		int tab = 0;

		show(prompt, buf, len, pos);
		c = read_key_byte();
		switch (c) {
		case 0x0a:
		case 0x0d:
			return len > 0 ? TRUE : FALSE;
		case 0x07:                      /* C-g */
			return FALSE;
		case 0x01: pos = 0; break;      /* C-a */
		case 0x05: pos = len; break;    /* C-e */
		case 0x02: pos = char_before(buf, pos); break;
		case 0x06: pos = char_after(buf, len, pos); break;
		case 0x04:                      /* C-d */
			if (pos < len) len = delete_bytes(buf, len, pos, char_after(buf, len, pos));
			break;
		case 0x0b:                      /* C-k */
			buf[pos] = '\0';
			len = pos;
			break;
		case 0x15:                      /* C-u */
			buf[0] = '\0';
			len = pos = 0;
			break;
		case 0x08:
		case 0x7f: {                    /* backspace */
			int from = char_before(buf, pos);
			if (pos > 0) {
				len = delete_bytes(buf, len, from, pos);
				pos = from;
			}
			break;
		}
		case 0x09:                      /* TAB */
			tab = 1;
			if (complete != NULL) {
				len = complete(buf, nbuf, len, last_tab);
				pos = len;
			}
			break;
		case 0x1b:
			switch (read_escape()) {
			case 'L': pos = char_before(buf, pos); break;
			case 'R': pos = char_after(buf, len, pos); break;
			case 'l': pos = word_before(buf, pos); break;
			case 'r': pos = word_after(buf, len, pos); break;
			case 'H': pos = 0; break;
			case 'E': pos = len; break;
			case 'D':
				if (pos < len) len = delete_bytes(buf, len, pos, char_after(buf, len, pos));
				break;
			default: break;
			}
			break;
		default: {
			char ch[4];
			int n = 1, i;

			if (c < 0x20 || c == SCR_KEY_RESIZE) break;  /* other control keys */
			ch[0] = (char) c;
			if (c >= 0xC0) {        /* the rest of a UTF-8 character */
				n = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : 2;
				for (i = 1; i < n; i++) ch[i] = (char) read_key_byte();
			} else if (c >= 0x80) {
				break;          /* a stray continuation byte */
			}
			if (len + n <= nbuf - 1) {
				memmove(buf + pos + n, buf + pos, (size_t) (len - pos + 1));
				memcpy(buf + pos, ch, (size_t) n);
				len += n;
				pos += n;
			}
			break;
		}
		}
		last_tab = tab;
	}
}
