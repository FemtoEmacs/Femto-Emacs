/* Real key.c and command.c: a Unicode character is one input/insert event. */
#include "header.h"
static const unsigned char *keys;
static unsigned reads, changes;
static long last_bytes;
buffer_t *curbp;
window_t *curwp;
char_t *input;
char *f_alloc="alloc", *m_alloc="alloc";
int screen_getch(void) { assert(*keys);reads++;return *keys++; }
void msg(char *s,...) { (void)s; }
void fatal(char *s) { (void)s;abort(); }
void input_test_undefined(void) {}
void input_test_mouse(void) {}
void record_change(buffer_t *b,int kind,point_t p,const char_t *text,long n) {
    (void)b;(void)p;(void)text;assert(kind=='i'||kind=='d');changes++;last_bytes=n;
}
int main(void) {
    keymap_t map[]={{NULL,NULL,NULL,NULL}},*binding;
    buffer_t b={0};curbp=&b;assert(growgap(&b,1));
    const char *chars[]={"a","\xc3\xa3","\xc3\xa7","\xc3\xa9","\xf0\x9f\x99\x82","\xc3\x9a"};
    unsigned expected=0;
    for(unsigned i=0;i<sizeof chars/sizeof *chars;i++) {
        keys=(const unsigned char *)chars[i];reads=0;
        input=get_key(map,&binding);
        assert(binding==NULL && !strcmp((char *)input,chars[i]));
        assert(reads==strlen(chars[i]));
        unsigned before=changes;insert();expected+=(unsigned)strlen(chars[i]);
        assert(changes==before+1 && last_bytes==(long)strlen(chars[i]));
        assert(b.b_point==expected && document_size(&b)==expected);
    }
    /* No continuation byte is left over to replay as a second key. */
    keys=(const unsigned char *)"z";input=get_key(map,&binding);
    assert(!strcmp((char *)input,"z"));insert();expected++;
    assert(document_size(&b)==expected);
    /* A non-continuation is given back, rather than swallowed. */
    keys=(const unsigned char *)"\xc3x";input=get_key(map,&binding);
    assert(input[0]==0xc3 && input[1]==0);
    input=get_key(map,&binding);assert(!strcmp((char *)input,"x"));
    /* Replace a two-byte character by four bytes, then by one byte. */
    b.b_point=1;b.b_flags|=B_OVERWRITE;
    input=(char_t *)"\xf0\x9f\x99\x82";insert();expected+=2;
    assert(b.b_point==5 && document_size(&b)==expected);
    b.b_point=1;input=(char_t *)"X";insert();expected-=3;
    assert(b.b_point==2 && document_size(&b)==expected);
    free(b.b_buf);
    puts("PASS atomic UTF-8 input, single-change insertion, resize-byte text, malformed lookahead and overwrite");
    return 0;
}
