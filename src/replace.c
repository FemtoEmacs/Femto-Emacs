/* replace.c, Femto Emacs, Hugh Barney, Public Domain, 2016 */

#include <string.h>
#include "header.h"

/*
 * ! in M-%: every occurrence from START (the start of one) to the end of
 * the text shown is replaced, in one pass.  One occurrence at a time, each
 * moved the gap, could grow it, and told undo twice: 100,000 took 83
 * seconds (tests/complexity.sh).  Here the new text of the stretch from
 * START to the end of the last occurrence is built apart, and replaces the
 * old in the buffer at once: undo is told one deletion and one insertion,
 * and C-/ takes the whole of it back, as it takes back one command.  The
 * occurrences are those the search one by one found: left to right, not
 * overlapping, never inside a replacement.  Returns how many; point is at
 * the start of the last replacement, where the loop left it.
 */
static int replace_rest(point_t start, const char *stext, int slen, const char *rtext, int rlen)
{
	point_t end = visible_end(curbp), p = start, last = start, k;
	char_t *out = NULL, *old = NULL;
	size_t n = 0, cap = 0;
	int count = 0;

	if (slen <= 0) return 0;
	while (p + slen <= end) {
		int i = 0;
		while (i < slen && *ptr(curbp, p + i) == (char_t) stext[i]) i++;
		if (i < slen) { p++; continue; }
		/* the text since the last occurrence, then the replacement */
		if (n + (size_t) (p - last) + (size_t) rlen + 1 > cap) {
			size_t want = (n + (size_t) (p - last) + (size_t) rlen + 1) * 2;
			char_t *grown = realloc(out, want);
			if (grown == NULL) { free(out); msg(m_alloc); return -1; }
			out = grown;
			cap = want;
		}
		for (k = last; k < p; k++) out[n++] = *ptr(curbp, k);
		memcpy(out + n, rtext, (size_t) rlen);
		n += (size_t) rlen;
		p += slen;
		last = p;
		count++;
	}
	if (count == 0) { free(out); return 0; }
	old = malloc((size_t) (last - start) + 1);
	if (old == NULL) { free(out); msg(m_alloc); return -1; }
	for (k = start; k < last; k++) old[k - start] = *ptr(curbp, k);

	/* the old stretch out, the new one in: the gap at START */
	(void) movegap(curbp, start);
	if ((point_t) n >= (curbp->b_egap - curbp->b_gap) + (last - start) &&
	    !growgap(curbp, (point_t) n - (last - start) + 1)) {
		free(out); free(old); return -1;
	}
	curbp->b_egap += last - start;
	record_change(curbp, 'd', start, old, last - start);
	memcpy(curbp->b_gap, out, n);
	curbp->b_gap += n;
	record_change(curbp, 'i', start, out, (long) n);
	add_mode(curbp, B_MODIFIED);
	curbp->b_point = start + (point_t) n - rlen;
	free(out);
	free(old);
	return count;
}

/*search for a string and replace it with another string */
void query_replace(void)
{
	point_t o_point = curbp->b_point;
	point_t l_point = -1;
	point_t found;
	char question[STRBUF_L];
	int slen, rlen;   /* length of search and replace strings */
	int numsub = 0;   /* number of substitutions */
	int ask = TRUE;
	int c;

	if (read_only_refuses()) return;
	searchtext[0] = '\0';
	replace[0] = '\0';

	if (!getinput(m_replace, (char*)searchtext, STRBUF_M, F_CLEAR))
		return;

	if (!getinput(m_with, (char*)replace, STRBUF_M, F_CLEAR))
		return;

	slen = strlen(searchtext);
	rlen = strlen(replace);

	/* build query replace question string */
	sprintf(question, m_qreplace, searchtext, replace);

	/* scan through the file, from point */
	numsub = 0;
	while(TRUE) {
		found = search_forward(searchtext);

		/* if not found set the point to the last point of replacement, or where we started */
		if (found == -1) {
			curbp->b_point = (l_point == -1 ? o_point : l_point);
			break;
		}

		curbp->b_point = found;
		/* search_forward places point at end of search, move to start of search */
		curbp->b_point -= slen;

		if (ask == TRUE) {
			msg(question);
			screen_clrtoeol();

		qprompt:
			display(curwp, TRUE);
			c = read_nonmouse_key_byte();

			switch (c) {
			case 'y': /* yes, substitute */
				break;

			case 'n': /* no, find next */
				curbp->b_point = found; /* set to end of search string */
				continue;

			case '!': /* yes/stop asking, do the lot */
			{
				int done = replace_rest(curbp->b_point, (char *) searchtext, slen, (char *) replace, rlen);
				if (done < 0) return;
				msg("%d substitutions", numsub + done);
				return;
			}

			case 0x1B: /* esc */
				screen_flushinp(); /* discard any escape sequence without writing in buffer */
			case 'q': /* controlled exit */
				return;

			default: /* help me */
				msg(m_rephelp);
				goto qprompt;
			}
		}

		if (rlen > slen) {
			movegap(curbp, found);
			/*check enough space in gap left */
			if (rlen - slen >= curbp->b_egap - curbp->b_gap)
				growgap(curbp, rlen - slen);
			/* shrink gap right by r - s */
			curbp->b_gap = curbp->b_gap + (rlen - slen);
		} else if (slen > rlen) {
			movegap(curbp, found);
			/* stretch gap left by s - r, no need to worry about space */
			curbp->b_gap = curbp->b_gap - (slen - rlen);
		} else {
			/* if rlen = slen, we just overwrite the chars, no need to move gap */
		}

		/* now just overwrite the chars at point in the buffer */
		l_point = curbp->b_point;
		record_change(curbp, 'd', curbp->b_point, (char_t *) searchtext, slen);
		record_change(curbp, 'i', curbp->b_point, (char_t *) replace, rlen);
		memcpy(ptr(curbp, curbp->b_point), replace, rlen * sizeof (char_t));
		add_mode(curbp, B_MODIFIED);
		curbp->b_point = found - (slen - rlen); /* end of replcement */
		numsub++;
	}

	msg("%d substitutions", numsub);
}
