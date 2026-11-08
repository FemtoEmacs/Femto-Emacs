/* Decoder boundaries, bounded rejection and literal control bytes. */
#include "header.h"
static const unsigned char *next;
static size_t remaining;
static unsigned calls;
static char result[128];
static long count;
buffer_t *curbp;
char *m_alloc="allocation failed";
int read_key_byte(void) { if (!remaining) return -1; --remaining; return *next++; }
void msg(char *fmt, ...) { (void)fmt; }
void fe_insert_bytes(long p,char *s,long n) {
 assert(p==0 && n<(long)sizeof result); memcpy(result,s,n);count=n;++calls;
}
static void run(const char *s,size_t n,const char *expected,size_t expected_n) {
 next=(const unsigned char *)s;remaining=n;calls=0;count=0;
 paste_bracketed();assert(remaining==0);
 if(calls!=(expected_n!=0)) fprintf(stderr,"case bytes=%zu expected=%zu calls=%u\n",n,expected_n,calls);
 assert(calls==(expected_n!=0));assert(count==(long)expected_n);
 assert(!expected_n || !memcmp(result,expected,expected_n));
}
int main(void) {
 buffer_t b={0};curbp=&b;
 run("a\r\nb\rc\n\033[201~",13,"a\nb\nc\n",6);
 const char controls[]="\030\003\000\033[20X\033[201~";
 run(controls,sizeof controls-1,controls,8);
 run("\033[201~",6,"",0);
 run("unfinished",10,"",0);
 run("1234567890123456789012345678901\033[201~",37,
     "1234567890123456789012345678901",31);
 run("123456789012345678901234567890123\033[201~",39,"",0);
 b.b_flags=B_READONLY;run("text\033[201~",10,"",0);
 b.b_flags=B_OVERWRITE;run("text\033[201~",10,"",0);
 puts("PASS bounded paste decoder, line ends, controls, incomplete and rejected frames");
 return 0;
}
