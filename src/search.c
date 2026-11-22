/* Literal incremental search shared by terminal and GUI backends. */
#include "header.h"

void search(void)
{
    int cpos=0,c;
    int direction=(whatKey && (!strcmp(whatKey,"C-r") ||
                   !strcmp(whatKey,"search-backward"))) ? REV_SEARCH : FWD_SEARCH;
    point_t origin=curbp->b_point;
    int origin_shard=shard_current(curbp);  /* shard.c: C-g comes back to it */
    const char *prompt=direction==FWD_SEARCH ? "Search forward: " : "Search backward: ";
    searchtext[0]=0;
    display_prompt_and_response((char *)prompt,searchtext);
    for(;;){
        c=read_key_byte();
        point_t previous=curbp->b_point;
        if(c==0x07){
            if(shard_current(curbp)!=origin_shard)(void)shard_switch(curbp,origin_shard,0);
            curbp->b_point=origin;display(curwp,TRUE);msg("Search cancelled");return;
        }
        if(c==0x0a || c==0x0d){
            msg("Search %s",cpos ? "finished" : "closed");return;
        }
        if(c==0x1b){
            /*
             * Esc alone ends the search.  An arrow, Home, PgUp or a mouse
             * click is Esc [ ... or Esc O ...: the search ends and the key
             * is given back whole, so the arrow moves the cursor, as in
             * Emacs.  Before, "[A" was left to be typed into the text.
             */
            int next=read_key_byte();
            if(next=='[' || next=='O'){
                char seq[2]={0x1b,(char)next};
                unread_key_bytes(seq,2);
            } else {
                char key=(char)next;
                unread_key_bytes(&key,1);
            }
            msg("Search %s",cpos ? "finished" : "closed");return;
        }
        if(c==0x13 || c==0x12){
            direction=c==0x13 ? FWD_SEARCH : REV_SEARCH;
        } else if(c==0x7f || c==0x08){
            if(!cpos)continue;
            /* Remove the whole UTF-8 character, not only its final byte. */
            do { cpos--; } while(cpos>0 && ((unsigned char)searchtext[cpos]&0xc0)==0x80);
            searchtext[cpos]=0;curbp->b_point=origin;
        } else if(c>=32 && cpos<STRBUF_M-1){
            searchtext[cpos++]=(char)c;searchtext[cpos]=0;
            curbp->b_point=origin;
        } else if(c<32){
            /* another control key (C-a, C-n, C-e ...): the search ends
             * and the key does what it always does */
            char key=(char)c;
            unread_key_bytes(&key,1);
            msg("Search %s",cpos ? "finished" : "closed");return;
        } else continue;
        prompt=direction==FWD_SEARCH ? "Search forward: " : "Search backward: ";
        point_t found=direction==FWD_SEARCH ? search_forward(searchtext) : search_backwards(searchtext);
        /* shard.c: C-s again at a failing search looks in the next shards */
        if(found==-1 && c==0x13 && curbp->b_shard && cpos && shard_search_forward(searchtext))
            found=curbp->b_point;
        if(found==-1)curbp->b_point=previous;
        display_search_result(found,direction,(char *)prompt,searchtext);
    }
}

void move_to_search_result(point_t found)
{
	if (found != -1) {
		curbp->b_point = found;
		display(curwp, TRUE);
	}
}

void display_search_result(point_t found, int dir, char *prompt, char *search)
{
    (void)dir;
	if (found != -1 ) {
		curbp->b_point = found;
		msg("%s%s",prompt, search);
		display(curwp, TRUE);
	} else {
		msg("Failing %s%s",prompt, search);
		dispmsg();
		/* A failed search must not unexpectedly jump to a buffer boundary. */
	}
}

/*
 * The text from P on, as far as it runs without the gap and before END:
 * its first byte, and how many bytes (search_forward reads it with
 * memchr, not a byte at a time through ptr())
 */
static const char_t *run_at(buffer_t *bp, point_t p, point_t end, point_t *len)
{
	point_t gap = bp->b_gap - bp->b_buf;
	if (p < gap) {
		*len = (gap < end ? gap : end) - p;
		return bp->b_buf + p;
	}
	*len = end - p;
	return bp->b_egap + (p - gap);
}

/* Does STEXT start at P (before END)?  Byte by byte: it may cross the gap. */
static int matches_at(buffer_t *bp, point_t p, point_t end, const char *stext, point_t *after)
{
	const char *s;
	point_t pp;
	for (s = stext, pp = p; *s != '\0' && pp < end && (unsigned char)*s == *(ptr(bp, pp)); s++, pp++)
		;
	*after = pp;
	return *s == '\0';
}

/*
 * The end of the first STEXT at or after point, or -1.  The text is read
 * with memchr for the first byte of STEXT, a run between the gap and the
 * end at a time: byte by byte through ptr() a search of 50 MB for a
 * pattern found at its end took 1.6 seconds (tests/complexity.sh).
 */
point_t search_forward(char *stext)
{
	point_t end_p = visible_end(curbp);     /* narrow.c: not past the part shown */
	point_t p = curbp->b_point, len, after;
	unsigned char first = (unsigned char) stext[0];

	if (0 == strlen(stext))
		return curbp->b_point;

	while (p < end_p) {
		const char_t *run = run_at(curbp, p, end_p, &len), *hit;
		if (len <= 0) break;
		hit = memchr(run, first, (size_t) len);
		if (hit == NULL) { p += len; continue; }
		p += hit - run;
		if (matches_at(curbp, p, end_p, stext, &after))
			return after;
		p++;
	}

	return -1;
}

point_t search_backwards(char *stext)
{
	point_t p,pp;
	char* s;
	point_t end_p = visible_end(curbp);
	point_t start_p = visible_start(curbp);

	if (0 == strlen(stext))
		return curbp->b_point;

	for (p=curbp->b_point - 1; p >= start_p; p--) {
		for (s=stext, pp=p; *s != '\0' && pp < end_p && (unsigned char)*s == *(ptr(curbp, pp)); s++, pp++)
			;

		if (*s == '\0') {
			return p;
		}
	}
	return -1;
}
