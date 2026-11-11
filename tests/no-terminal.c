/* The tests that link a few of the editor's C files, without terminal.c:
 * no buffer is ever a terminal (M-x term) */
#include "header.h"
int term_poll(void) { return 0; }
int term_takes_keys(buffer_t *bp) { (void) bp; return 0; }
void term_take_key(void) {}
int term_faces(buffer_t *bp, point_t start, char_t *faces, long len) { (void) bp; (void) start; (void) faces; (void) len; return 0; }
void term_buffer_gone(buffer_t *bp) { (void) bp; }
int term_running(void) { return 0; }
int term_state(buffer_t *bp) { (void) bp; return 0; }
int term_owns_cursor(buffer_t *bp) { (void) bp; return 0; }
int term_poll_ms(void) { return 100; }
