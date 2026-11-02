/*
 * highlight.h -- the tokenizers behind syntax highlighting (highlight.c),
 * for both runtimes: femtoscheme's builtins and compiled Scheme's
 * (bridge-more.c).  Text and colours are bytes; colours are faces.
 */
#ifndef CHEZEMAX_HIGHLIGHT_H
#define CHEZEMAX_HIGHLIGHT_H

typedef struct { char *s; int n; } hl_bytes;

/* (fe-define-token-language ...): a language defined by tables */
typedef struct {
	hl_bytes word_chars;                    /* more word constituents */
	hl_bytes *line_comments; int n_line;
	hl_bytes *block_open, *block_close; int n_block;
	hl_bytes *strings; int n_strings;
	int escape;                             /* a byte, or -1 */
	hl_bytes char_prefix;                   /* n == 0: none */
	int backslash_commands, case_insensitive;
	hl_bytes *keywords; int n_keywords;
} hl_language_spec;
int highlight_define_language(const hl_language_spec *);   /* the id */
int highlight_tokens_id(int id, const unsigned char *text, int len, unsigned char *colors);  /* 0: no such id */
void highlight_python_text(const unsigned char *text, int len, unsigned char *colors);
void highlight_nim_text(const unsigned char *text, int len, unsigned char *colors);

/* Markdown: the blocks of code, in order (*FOUND, malloc'd), their number */
typedef struct { int start, end, info_start, info_end; } hl_block;
int highlight_markdown_text(const unsigned char *text, int len, unsigned char *colors, hl_block **found);
#endif
