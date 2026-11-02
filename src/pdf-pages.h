/* Native PDF rendering for TTFY. No interpreter or external package required. */
#ifndef CHEZEMAX_PDF_PAGES_H
#define CHEZEMAX_PDF_PAGES_H
#include <stddef.h>
#define TTFY_MAX_PAGES 32
int ttfy_render(const char *pdf, const char *range, const char *directory,
                char images[TTFY_MAX_PAGES][4096], int *first, int *last,
                char *error, size_t error_size);
#endif
