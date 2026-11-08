/* Real display.c navigation with UTF-8 characters crossing every possible gap. */
#include "header.h"
static int columns = 80;
buffer_t *curbp;
int screen_cols(void) { return columns; }
const char *screen_unctrl(int c) { (void)c; return "^?"; }
point_t document_size(buffer_t *b) {
    return (b->b_ebuf-b->b_buf)-(b->b_egap-b->b_gap);
}
char_t *ptr(buffer_t *b,point_t p) {
    if(p<0)return b->b_buf;
    return b->b_buf+p+(p>=b->b_gap-b->b_buf?b->b_egap-b->b_gap:0);
}
point_t pos(buffer_t *b,char_t *p) {
    return p-b->b_buf-(p>=b->b_egap?b->b_egap-b->b_gap:0);
}
int main(void) {
    const unsigned char text[]="A\xc3\xa3\xc3\xa9\xf0\x9f\x99\x82" "B\nxy\n";
    /* A ã é 🙂 B: 🙂 (U+1F642, an emoji) takes two columns (width.c), so
     * column 4, inside it, lands after it, as Emacs's move-to-column does */
    const point_t expected[]={0,1,3,5,9,9,10};
    unsigned char bytes[64];buffer_t b;
    size_t n=sizeof text-1;unsigned checks=0;
    for(size_t at=0;at<=n;at++) {
        memset(&b,0,sizeof b);memset(bytes,0xcc,sizeof bytes);
        memcpy(bytes,text,at);memcpy(bytes+at+7,text+at,n-at);
        b.b_buf=bytes;b.b_gap=bytes+at;b.b_egap=b.b_gap+7;b.b_ebuf=bytes+n+7;
        columns=80;
        for(int c=0;c<7;c++) {assert(lncolumn(&b,0,c)==expected[c]);checks++;}
        columns=3;
        assert(segnext(&b,0,0)==5);checks++;
        assert(segstart(&b,0,9)==5);checks++;
        /* the row 🙂B fills the three columns: the newline starts the next */
        assert(segnext(&b,0,5)==10);checks++;
        assert(upup(&b,9)==0);checks++;
        assert(dndn(&b,0)==5);checks++;
        /* Mouse placement starts from the same visual-row calculation. */
        window_t window={0};window.w_rows=4;window.w_bufp=&b;
        curbp=&b;b.b_page=segstart(&b,0,9);
        assert(window_position(&window,0,0) && b.b_point==5);checks++;
        /* columns 0 and 1 are 🙂, column 2 is B */
        assert(window_position(&window,0,1) && b.b_point==5);checks++;
        assert(window_position(&window,0,2) && b.b_point==9);checks++;
        b.b_page=0;
        assert(window_position(&window,1,0) && b.b_point==5);checks++;
    }
    printf("PASS %u unwrapped UTF-8 arrow/mouse column/row checks across all gap positions\n",checks);
    return 0;
}
