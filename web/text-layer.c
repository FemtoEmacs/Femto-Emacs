/* Browsered's on-demand real-text overlay, adapted for Chezweb.
 * After redisplay, describe only the selected window and its visible bytes.
 * The toolbar enables the field for one buffer; switching buffers ends it.
 * Corrections return through compiled/chezweb.scm, never through this reader.
 */
#include <emscripten.h>
#include <stdlib.h>
#include <string.h>
#include "header.h"


static int enabled = 0;                  /* checking, in ... */
static buffer_t *checked = NULL;         /* ... this buffer */

/* (web-text-layer #t): check the selected window's buffer; #f: stop */
EMSCRIPTEN_KEEPALIVE int web_layer_set(int on)
{
	enabled = on && curwp != NULL && curwp->w_bufp != NULL;
	checked = enabled ? curwp->w_bufp : NULL;
	return enabled;
}
EMSCRIPTEN_KEEPALIVE int web_layer_on(void) { return enabled; }

EM_JS(void, web_layer, (const char *json), {
	Module.browsered.textLayer(json ? UTF8ToString(json) : null);
});

static char *out = NULL;
static size_t cap = 0, len = 0;

static void put(const char *s, size_t n)
{
	if (len + n + 1 > cap) {
		size_t c = cap ? cap : 4096;
		while (len + n + 1 > c) c *= 2;
		char *grown = realloc(out, c);
		if (grown == NULL) return;
		out = grown;
		cap = c;
	}
	memcpy(out + len, s, n);
	len += n;
	out[len] = '\0';
}

static void puts_(const char *s) { put(s, strlen(s)); }

static void putnum(const char *name, long v)
{
	char b[48];
	snprintf(b, sizeof b, "\"%s\":%ld,", name, v);
	puts_(b);
}

static void putbyte(unsigned char c)
{
	char b[8];
	if (c == '"' || c == '\\') { b[0] = '\\'; b[1] = (char) c; put(b, 2); }
	else if (c == '\n') put("\\n", 2);
	else if (c == '\t') put("\\t", 2);
	else if (c < 0x20 || c == 0x7f) { snprintf(b, sizeof b, "\\u%04x", c); put(b, 6); }
	else put((const char *) &c, 1);
}

void web_layer_update(void)
{
	window_t *wp = curwp;
	buffer_t *bp;
	point_t from, to, at, i, size;

	if (enabled && (wp == NULL || wp->w_bufp != checked)) web_layer_set(0);   /* another buffer: done */
	if (!enabled || wp == NULL || (bp = wp->w_bufp) == NULL) { web_layer(NULL); return; }

	size = document_size(bp);
	from = wp->w_page < 0 ? 0 : (wp->w_page > size ? size : wp->w_page);
	to = wp->w_epage < from ? from : (wp->w_epage > size ? size : wp->w_epage);
	at = wp->w_point < from ? from : (wp->w_point > to ? to : wp->w_point);
	len = 0;
	puts_("{");
	putnum("top", wp->w_top);
	putnum("rows", wp->w_rows);
	putnum("page", (long) from);
	putnum("point", (long) (at - from));
	puts_("\"buffer\":\"");
	for (i = 0; bp->b_bname[i]; i++) putbyte((unsigned char) bp->b_bname[i]);
	puts_("\",\"text\":\"");
	for (i = from; i < to; i++) putbyte(*ptr(bp, i));
	puts_("\"}");
	web_layer(out);
}

