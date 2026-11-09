/* Regression tests for real search.c with an isolated gap buffer and test_keys. */
#include "../src/header.h"
#include <stdarg.h>
buffer_t storage,*curbp=&storage;
window_t *curwp=NULL;
char searchtext[STRBUF_M],*whatKey="C-s";
static const unsigned char *test_keys;
static char bytes[128];
static int renders;
static unsigned char unread[16];
static int unread_count;
void unread_key_bytes(const char *s,int n){assert(n>=0 && n<=16);memcpy(unread,s,n);unread_count=n;}
char_t *ptr(buffer_t *b,point_t p) {
    point_t gap=b->b_gap-b->b_buf;
    return b->b_buf+p+(p>=gap ? b->b_egap-b->b_gap : 0);
}
point_t pos(buffer_t *b,char_t *p) {
    return p-b->b_buf-(p>=b->b_egap ? b->b_egap-b->b_gap : 0);
}
void display(window_t *w,int full){(void)w;(void)full;renders++;}
/* narrow.c: this buffer is never narrowed */
point_t visible_start(buffer_t *b){(void)b;return 0;}
point_t visible_end(buffer_t *b){return pos(b,b->b_ebuf);}
void dispmsg(void){}
void msg(char *format,...){(void)format;}
void display_prompt_and_response(char *p,char *s){(void)p;(void)s;}
int read_key_byte(void){if(unread_count){int k=unread[0];memmove(unread,unread+1,--unread_count);return k;}assert(*test_keys);return *test_keys++;}
static void setup(point_t point){
    unread_count=0;
    /* Logical text "alpha beta alpha", with a gap crossing the first match. */
    memset(&storage,0,sizeof(storage));memset(bytes,0,sizeof(bytes));
    memcpy(bytes,"al",2);memcpy(bytes+10,"pha beta alpha",14);
    storage.b_buf=(char_t *)bytes;storage.b_gap=(char_t *)bytes+2;
    storage.b_egap=(char_t *)bytes+10;storage.b_ebuf=(char_t *)bytes+24;
    storage.b_point=point;
}
int main(void){
    setup(0);assert(search_forward("alpha")==5);
    storage.b_point=5;assert(search_forward("alpha")==16);
    storage.b_point=16;assert(search_forward("alpha")==-1);
    assert(search_forward("alpha-too-long")==-1);
    assert(search_backwards("alpha")==11);
    storage.b_point=11;assert(search_backwards("alpha")==0);
    storage.b_point=0;assert(search_backwards("alpha")==-1);
    setup(0);test_keys=(const unsigned char *)"alpha\r";search();assert(storage.b_point==5);
    setup(0);test_keys=(const unsigned char *)"alpha\x13\r";search();assert(storage.b_point==16);
    setup(16);whatKey="C-r";test_keys=(const unsigned char *)"alpha\r";search();assert(storage.b_point==11);
    setup(16);test_keys=(const unsigned char *)"alpha\x12\r";search();assert(storage.b_point==0);
    setup(0);whatKey="C-s";test_keys=(const unsigned char *)"alphaX\r";search();assert(storage.b_point==5);
    setup(2);test_keys=(const unsigned char *)"alpha\x07";search();assert(storage.b_point==2);
    setup(0);memcpy(bytes,"\xc3\xa9",2);assert(search_forward("\xc3\xa9")==2);
    storage.b_point=2;assert(search_backwards("\xc3\xa9")==0);
    setup(0);test_keys=(const unsigned char *)"alpha\x1b[A";search();
    assert(read_key_byte()==0x1b);assert(read_key_byte()=='[');assert(read_key_byte()=='A');
    setup(0);test_keys=(const unsigned char *)"alpha\x01";search();assert(read_key_byte()==0x01);
    assert(renders>0);puts("PASS: incremental search, repeat, reverse, Enter, cancel, gap and bounds");
    return 0;
}
