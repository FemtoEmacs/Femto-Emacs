/* Run from the checkout root:
 * cc -std=c11 -fsanitize=address,undefined -g -Isrc \
 *   Lean/models/evidence/gap_bp-reconstruction-check.c -o /tmp/gap-check
 * (on macOS add -ffunction-sections -fdata-sections -Wl,-dead_strip)
 * /tmp/gap-check
 * Allocations and all text fixtures are disposable. realloc always relocates. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <setjmp.h>
#include <assert.h>
#include <limits.h>
static int allocation_fails, messages, fatals;
static size_t capacity;
#ifdef GAP_TEST_SIZE_LIMIT
static unsigned long test_limit = ULONG_MAX;
#endif
static jmp_buf fatal_target;
static void *checked_malloc(size_t n) {
    if (allocation_fails) return NULL;
    capacity = n;
    return malloc(n);
}
static void *checked_realloc(void *old, size_t n) {
    if (allocation_fails) return NULL;
    void *fresh = malloc(n);
    assert(fresh != NULL);
    memcpy(fresh, old, capacity < n ? capacity : n);
    free(old);
    capacity = n;
    return fresh;
}
#define malloc checked_malloc
#define realloc checked_realloc
#ifndef GAP_RECONSTRUCTION_SOURCE
#define GAP_RECONSTRUCTION_SOURCE "../src/reconstructed-gap.c"
#endif
#include GAP_RECONSTRUCTION_SOURCE
#undef malloc
#undef realloc
/* Unused framework procedures are discarded by the linker's dead stripping. */
char *f_alloc = "allocation failed", *m_alloc = "allocation failed";
void fatal(char *s) { (void)s; ++fatals; longjmp(fatal_target, 1); }
void msg(char *s, ...) { (void)s; ++messages; }
static unsigned long checks;
static void verify(buffer_t *b, const buffer_t *metadata,
                   const unsigned char *text, size_t n, size_t p, size_t h) {
    assert((size_t)(b->b_gap - b->b_buf) == p);
    assert((size_t)(b->b_egap - b->b_gap) == h);
    assert((size_t)(b->b_ebuf - b->b_buf) == n+h);
    assert(memcmp(b->b_buf,text,p) == 0);
    assert(memcmp(b->b_egap,text+p,n-p) == 0);
    buffer_t copy = *b;
    copy.b_buf=metadata->b_buf;copy.b_gap=metadata->b_gap;
    copy.b_egap=metadata->b_egap;copy.b_ebuf=metadata->b_ebuf;
    assert(memcmp(&copy,metadata,sizeof copy) == 0);
    ++checks;
}
static buffer_t fixture(const unsigned char *text,size_t n,size_t p,size_t h) {
    buffer_t b;
    memset(&b,0,sizeof b);
    capacity=n+h;
    b.b_buf=malloc(capacity ? capacity : 1);
    assert(b.b_buf);
    memset(b.b_buf,0xcc,capacity);
    memcpy(b.b_buf,text,p);memcpy(b.b_buf+p+h,text+p,n-p);
    b.b_gap=b.b_buf+p;b.b_egap=b.b_gap+h;b.b_ebuf=b.b_buf+capacity;
    b.b_point=17;b.b_mark=9;b.b_flags=B_READONLY;b.b_id=123;
    strcpy(b.b_fname,"unchanged");return b;
}
int main(void) {
    unsigned char text[256];
    for(size_t i=0;i<sizeof text;i++) text[i]=(unsigned char)i;
    /* Every small gap layout and target; grow before and after moving. */
    for(size_t n=0;n<=24;n++) for(size_t h=0;h<=12;h++)
    for(size_t p=0;p<=n;p++) for(size_t q=0;q<=n;q++) {
        buffer_t b=fixture(text,n,p,h), original=b;
        assert(movegap(&b,(point_t)q)==(point_t)q);
        verify(&b,&original,text,n,q,h);
        /* A zero-length allocation is initial even when its base is non-NULL.
         * Avoid asking the model to own such a malloc(0)-style allocation. */
        if(n+h != 0) {
            assert(growgap(&b,-7));verify(&b,&original,text,n,q,h+512);
            assert(movegap(&b,(point_t)p)==(point_t)p);
            verify(&b,&original,text,n,p,h+512);
            assert(growgap(&b,513));verify(&b,&original,text,n,p,h+1025);
        }
        free(b.b_buf);
    }
    /* Raw byte coverage and a long deterministic movement/growth schedule. */
    buffer_t b=fixture(text,256,128,1), original=b;
    size_t h=1;
    unsigned state=1;
    for(unsigned i=0;i<10000;i++) {
        state=state*1664525u+1013904223u;size_t p=state%257;
        assert(movegap(&b,(point_t)p)==(point_t)p);
        if(i%100==0) { assert(growgap(&b,1));h+=512; }
        verify(&b,&original,text,256,p,h);
    }
    /* Existing failure paths preserve pointers, fields, and allocation bytes. */
    original=b;unsigned char *saved=malloc(capacity);memcpy(saved,b.b_buf,capacity);
    allocation_fails=1;assert(!growgap(&b,1));allocation_fails=0;
    assert(!memcmp(&b,&original,sizeof b));assert(!memcmp(saved,b.b_buf,capacity));
    assert(!growgap(&b,LONG_MAX));assert(!memcmp(&b,&original,sizeof b));
    assert(!memcmp(saved,b.b_buf,capacity));free(saved);free(b.b_buf);
    /* The three initial paths, including a genuinely unallocated buffer. */
    buffer_t empty={0};assert(movegap(&empty,0)==0);
    if(setjmp(fatal_target)==0) { allocation_fails=1;growgap(&empty,1);abort(); }
    allocation_fails=0;assert(empty.b_buf==NULL);
#ifdef GAP_TEST_SIZE_LIMIT
    test_limit=1;
    if(setjmp(fatal_target)==0) { growgap(&empty,1);abort(); }
    assert(empty.b_buf==NULL);
    test_limit=ULONG_MAX;
#endif
    assert(growgap(&empty,1));assert(empty.b_ebuf-empty.b_buf==512);
    assert(empty.b_gap==empty.b_buf && empty.b_egap==empty.b_ebuf);free(empty.b_buf);
#ifdef GAP_TEST_SIZE_LIMIT
    assert(fatals==2 && messages==2);
#else
    assert(fatals==1 && messages==2);
#endif
    printf("pass: %lu buffer checks; forced realloc relocation; allocation failures; overflow; 10000-step schedule\n",checks);
    return 0;
}
