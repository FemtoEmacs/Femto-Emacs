/*
 * screen.h, SBEmacs
 *
 * The screen layer.  The editor core never talks to ncurses or SDL
 * directly: it draws into an abstract grid of character cells through
 * these functions and reads keys with screen_getch().  Two back ends
 * implement them:
 *
 *   term.c  ncurses, for terminals          -> libsbemacs-term
 *   gui.c   SDL2 + SDL2_ttf, a window       -> libsbemacs-gui
 *
 * Both libraries contain the same editor core and export the same fe_*
 * functions, so the Lisp side can load either.
 *
 * Keys are delivered as the bytes a terminal would send (C-x is 0x18, the
 * up arrow is ESC [ A, ...), so the key tables in key.c serve both.
 */

#ifndef SBEMACS_SCREEN_H
#define SBEMACS_SCREEN_H

/* attribute bits, combined with a face in screen_set_face() */
#define SCR_BOLD      1
#define SCR_UNDERLINE 2
#define SCR_REVERSE   4
#define SCR_DIM       8
#define SCR_ITALIC   16

/* OR-ed into a character given to screen_addch(): draw it in reverse video */
#define SCR_REVERSE_CHAR 0x10000

/*
 * Colours: -1 is the default colour, 0-255 the xterm palette, and
 * SCR_RGB(r,g,b) a 24-bit colour (the terminal back end approximates it).
 */
#define SCR_RGB_FLAG 0x1000000L
#define SCR_RGB(r, g, b) (SCR_RGB_FLAG | ((long)(r) << 16) | ((long)(g) << 8) | (long)(b))
#define SCR_IS_RGB(c) ((c) >= SCR_RGB_FLAG)

/* the byte a back end returns from screen_getch() when the screen resized */
#define SCR_KEY_RESIZE 0x9A

/* life cycle */
extern int  screen_probe(void);            /* 1 if screen_init can work here */
extern int  screen_init(int mouse);        /* returns 0 on failure */
extern void screen_end(void);
extern int  screen_active(void);
extern const char *screen_backend(void);   /* "terminal" or "gui" */

/* geometry */
extern int  screen_rows(void);
extern int  screen_cols(void);

/* drawing; text is UTF-8, each character takes one cell */
extern void screen_move(int row, int col);
extern void screen_addch(int c);           /* one byte, or c | SCR_REVERSE_CHAR */
extern void screen_addstr(const char *s);
extern void screen_mvaddstr(int row, int col, const char *s);
extern void screen_clrtoeol(void);
extern void screen_clear(void);
extern void screen_refresh(void);
extern const char *screen_unctrl(int c);   /* printable form of a control char */

/* faces: ids are the ID_COLOR_* values in header.h */
extern void screen_face(int id);
extern void screen_set_face(int id, long fg, long bg, int attrs);
extern int  screen_colors(void);           /* 8, 256, or 16777216 for 24-bit */

/* wait MS milliseconds (a clicked button stays lit that long) */
extern void screen_pause(int ms);

/* input */
extern int  screen_getch(void);            /* blocks; returns one byte */
extern void screen_flushinp(void);        /* discard pending input */

/*
 * The system clipboard.  In the window, through SDL; in a terminal,
 * through pbcopy/pbpaste (macOS), wl-copy/wl-paste (Wayland) or xclip/xsel
 * (X11), and otherwise an OSC 52 escape, which only writes.
 * screen_get_clipboard returns malloc'd text (LF line ends), or NULL.
 */
extern void screen_set_clipboard(const char *text);
extern char *screen_get_clipboard(void);

/* GUI settings, no-ops in a terminal */
extern void screen_set_font(const char *path, int points);
extern void screen_set_default_colors(long fg, long bg, long cursor);
extern void screen_set_title(const char *title);
extern void screen_set_option(const char *name, int value);

#endif
