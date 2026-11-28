/* Replay the PTY output, rather than counting old frames in its raw log.
 * A moved strike span must exist once on the final visible screen. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "vterm.h"

int main(int argc, char **argv)
{
    if (argc != 2 && argc != 3) return 2;
    int wanted = argc == 3 ? atoi(argv[2]) : 1;
    FILE *file = fopen(argv[1], "rb");
    if (!file) return 2;
    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    if (size < 0) return 2;
    rewind(file);
    char *bytes = calloc((size_t)size + 1, 1);
    if (!bytes || fread(bytes, 1, (size_t)size, file) != (size_t)size) return 2;
    fclose(file);
    /* Stop before quitting curses restores the outer terminal screen. */
    char *end = strstr(bytes, "\033[?1049l");
    size_t len = end ? (size_t)(end - bytes) : (size_t)size;
    VTerm *vt = vterm_new(24, 80);
    vterm_set_utf8(vt, 1);
    VTermScreen *screen = vterm_obtain_screen(vt);
    vterm_screen_enable_altscreen(screen, 1);
    vterm_screen_reset(screen, 1);
    vterm_input_write(vt, bytes, len);
    vterm_screen_flush_damage(screen);
    char rows[22][81];
    int copies = 0, decorated = 0;
    for (int y = 0; y < 22; y++) {
        for (int x = 0; x < 80; x++) {
            VTermScreenCell cell;
            vterm_screen_get_cell(screen, (VTermPos){y, x}, &cell);
            rows[y][x] = cell.chars[0] && cell.chars[0] < 128 ? (char)cell.chars[0] : ' ';
        }
        rows[y][80] = 0;
        for (char *p = rows[y]; (p = strstr(p, "STRIKEWORD")); p++) {
            copies++;
            int all_struck = 1;
            for (int j = 0; j < 10; j++) {
                VTermScreenCell cell;
                vterm_screen_get_cell(screen, (VTermPos){y, (int)(p - rows[y]) + j}, &cell);
                if (!cell.attrs.strike) all_struck = 0;
            }
            decorated += all_struck;
        }
    }
    vterm_free(vt);
    free(bytes);
    if (copies != 1 || decorated != wanted) {
        for (int y = 0; y < 22; y++) puts(rows[y]);
        fprintf(stderr, "FAIL strike redraw: %d visible copies, %d decorated (expected 1 and %d)\n", copies, decorated, wanted);
        return 1;
    }
    puts(wanted ? "PASS newline redraw leaves exactly one struck phrase on the visible terminal screen" : "PASS removing the tildes removes the strike without leaving ghost words");
    return 0;
}
