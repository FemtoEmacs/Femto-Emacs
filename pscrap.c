#include <assert.h>
#include <string.h>
#include "header.h"

void ps_push(pscrap_t **pst, char_t *scrap) {
	/* Usage: 
	 *     ps_push(&stack, scrap); 
	 */
	pscrap_t *nst = (pscrap_t*) malloc(sizeof(pscrap_t));
    nst->scrap = scrap;
    nst->next = *pst;
    *pst = nst;
}

void ps_pop(pscrap_t **pst) {
	/* Usage: 
	 *     ps_pop(&stack); 
	 */
	if(*pst != NULL) {
		pscrap_t * aux = (*pst)->next;
		free(*pst);
		*pst = aux;
	} 
}

char_t* ps_top(pscrap_t *st) {
	/* Usage: 
	 *     char_t* xxx = ps_top(stack); 
	 */
	return (st == NULL)? NULL : st->scrap;
}

int ps_size(pscrap_t *st) {
	/* Usage: 
	 *     n = ps_size(stack); 
	 */
	return (st == NULL)? 0 : 1 + ps_size(st->next);
}
