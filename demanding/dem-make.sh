#!/bin/sh
# dem-make.sh -- makes the demanding files of this folder, dem-*, for
# trying Chezweb by hand (each has its guidelines in dem-*.gls).
#
#   sh dem-make.sh          all the files but the huge one (about 175 MB)
#   sh dem-make.sh huge     also dem-huge.txt, 1.28 GB, that C-x C-f opens
#                           in shards by itself
#   sh dem-make.sh clean    removes the files it made (not the .gls)
#
# Only sh, awk and printf: it runs on macOS and Linux.  The files are made
# again each time, so a test that saved over one can start fresh.
set -eu
cd "$(dirname "$0")"
LC_ALL=C; export LC_ALL

made() { printf '  %-28s %s bytes\n' "$1" "$(wc -c < "$1" | tr -d ' ')"; }

if [ "${1:-}" = clean ]; then
	rm -f dem-open-parens.scm dem-open-parens-lines.scm dem-deep-sexp.scm dem-balanced.scm \
	      dem-long-list.scm dem-minified.json dem-wide-line.txt dem-search.txt \
	      dem-replace.txt dem-replace-line.txt dem-paragraph.txt dem-list.md \
	      dem-list.org dem-headings.org dem-malformed.txt dem-unicode.txt \
	      dem-clipboard.txt dem-huge.txt dem-backup.txt dem-backup-link.txt \
	      dem-hard.txt dem-hard-twin.txt dem-autosave.txt dem-autosave-big.txt
	echo "removed"
	exit 0
fi

echo "making the demanding files:"

# 10 MB of ( on one line, never closed
awk 'BEGIN { s = "(((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((("
             for (i = 0; i < 14; i++) s = s s
             for (i = 0; i < 10; i++) printf "%s", s; printf "\n" }' > dem-open-parens.scm
made dem-open-parens.scm

# 100,000 lines of 100 ( each, never closed
awk 'BEGIN { s = "(((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((("
             for (i = 0; i < 100000; i++) print s }' > dem-open-parens-lines.scm
made dem-open-parens-lines.scm

# 8 MB of good Scheme, demanding: a quoted list 1,000,000 deep on one line,
# closed, with a string at the bottom; nested #| |# with parens; a table of
# 80,000 rows with ) and ( in strings, characters (#\( #\)), |symbols| and
# comments; a short definition after.  Chez Scheme loads it.
awk 'BEGIN {
	print ";;;; dem-balanced.scm -- demanding, and good Scheme: every paren is closed"
	print ""
	print "(define deep"
	printf "  \047"
	for (i = 0; i < 1000000; i++) printf "("
	printf "\"the bottom, with ) and ( in a string\""
	for (i = 0; i < 1000000; i++) printf ")"
	print ")"
	print ""
	print "#| A block comment with ( and ) in it,"
	print "   #| a comment nested in it, with a ) |#"
	print "   and still a ( in the outer one. |#"
	print ""
	print "(define table"
	print "  (quote ("
	for (i = 1; i <= 80000; i++)
		printf "    (row %06d \"a ) in a string\" #\\( #\\) |a (symbol| 3.14) ; a ( in a comment\n", i
	print "  )))"
	print ""
	print "(define (after-all) (vector-length (list->vector table)))"
}' > dem-balanced.scm
made dem-balanced.scm

# one s-expression nested 20,000 levels deep, closed on its last line
awk 'BEGIN { print "(define deep"
             for (i = 1; i <= 20000; i++) printf "(level-%05d \"ção\" %d\n", i, i
             for (i = 0; i < 20000; i++) printf ")"; printf ")\n"
             print "(define after-deep 42)" }' > dem-deep-sexp.scm
made dem-deep-sexp.scm

# one list of 100,000 lines, 5 MB, well closed, between two small definitions
awk 'BEGIN { print "(define before-list 1)"
             print "(define big-list"
             print "  (quote ("
             # lines 50003-50005: a sublist indented wrong, for C-M-\
             # (dem-long-list.gls, step 8)
             for (i = 1; i <= 100000; i++)
               if (i == 50000) printf "    (sublist %06d\n", i
               else if (i == 50001) printf "(item %06d \"ção € 😀\" #\\x 3.14 (nested (deeper %d)))\n", i, i
               else if (i == 50002) printf "                 (item %06d \"ção € 😀\" #\\x 3.14 (nested (deeper %d))))\n", i, i
               else printf "    (item %06d \"ção € 😀\" #\\x 3.14 (nested (deeper %d)))\n", i, i
             print "  )))"
             print "(define after-list 2)" }' > dem-long-list.scm
made dem-long-list.scm

# one line of 5 MB of minified JSON, with accents and CJK
awk 'BEGIN { printf "{"
             for (i = 0; i < 125000; i++) printf "\"k%d\":[1,2.5,\"café 中文\",{\"x\":null}],", i
             printf "\"end\":true}\n" }' > dem-minified.json
made dem-minified.json

# 400,000 short lines, one line of 35 MB of wide characters, 1,000 lines
awk 'BEGIN { for (i = 0; i < 400000; i++) printf "ç line %06d of the first shard, ends 😀\n", i
             s = "ção€😀ñ中"; for (i = 0; i < 12; i++) s = s s
             for (i = 0; i < 500; i++) printf "%s", s; printf "\n"
             for (i = 0; i < 1000; i++) printf "ç tail %04d 😀\n", i }' > dem-wide-line.txt
made dem-wide-line.txt

# 52 MB of text without the letters q and z, ending at line 880000
awk 'BEGIN { for (i = 0; i < 880000; i++) printf "line %06d of fifty megabytes of plain text, all the same.\n", i }' > dem-search.txt
made dem-search.txt

# 100,000 lines with one foo each; one line of 100,000 foo
awk 'BEGIN { for (i = 0; i < 100000; i++) printf "%06d: a foo on the line\n", i }' > dem-replace.txt
made dem-replace.txt
awk 'BEGIN { for (i = 0; i < 100000; i++) printf "%06d foo ", i; printf "\n" }' > dem-replace-line.txt
made dem-replace-line.txt

# one paragraph of 50,000 words on one line
awk 'BEGIN { for (i = 0; i < 50000; i++) printf "%s%s", (i ? " " : ""), "word" (i % 97); printf "\n" }' > dem-paragraph.txt
made dem-paragraph.txt

# nested lists of 12,000 items, eight levels deep
for kind in md org; do
	awk -v kind=$kind 'BEGIN {
		if (kind == "org") print "* A heading over the list\n"
		for (i = 0; i < 12000; i++) {
			d = i % 8; pad = ""; for (j = 0; j < d; j++) pad = pad "  "
			printf "%s- item %d, at depth %d, with a line long enough to be refilled by M-q into two or three lines of the list\n", pad, i, d
		}
	}' > dem-list.$kind
	made dem-list.$kind
done

# 30,000 Org headings on three levels, each with a paragraph
awk 'BEGIN { for (i = 1; i <= 10000; i++) {
               printf "* Chapter %05d\nThe text of chapter %d, with ção and 中文.\n", i, i
               printf "** Section %05d.1\nA paragraph under the section, long enough to wrap once on a window of eighty columns, more or less.\n", i
               printf "*** Note %05d.1.1\nA note, with a list:\n- one\n- two\n", i } }' > dem-headings.org
made dem-headings.org

# 1 MB of text that is not text: NUL, surrogates, bytes no UTF-8 has
printf 'abc\000def \355\240\200 \355\260\200 \377\376 \300\200 \200 \303\247\303\243o \342\202\n' > dem-malformed.txt
while [ "$(wc -c < dem-malformed.txt | tr -d ' ')" -lt 1000000 ]; do
	cat dem-malformed.txt dem-malformed.txt > dem-malformed.2; mv dem-malformed.2 dem-malformed.txt
done
made dem-malformed.txt

# characters that are hard to draw: combining accents, emoji sequences,
# flags, CJK, Korean, tabs, at every column
awk 'BEGIN { split("e\314\201 a\314\200\314\202 \341\274\200\315\205 \360\237\221\250\342\200\215\360\237\221\251\342\200\215\360\237\221\247 \360\237\207\247\360\237\207\267 \344\270\255\346\226\207 \355\225\234\352\270\200 \342\235\244\357\270\217 \t", t, " ")
             for (i = 0; i < 2000; i++) {
               line = sprintf("%04d ", i)
               for (j = 0; j < 12; j++) line = line t[(i + j) % 9 + 1] "x"
               print line } }' > dem-unicode.txt
made dem-unicode.txt

# 21 MB to put on the system clipboard (pbcopy < dem-clipboard.txt)
awk 'BEGIN { for (i = 0; i < 400000; i++) printf "row %06d that another program copied, ção 中文 😀..\n", i }' > dem-clipboard.txt
made dem-clipboard.txt

# files for the safe save, the backups and auto-save (dem-backup.gls,
# dem-autosave.gls): small texts, a symbolic link, two names of one file
# (a hard link), and 11 MB, above the 10 MB that auto-save takes
rm -f dem-backup-link.txt dem-hard-twin.txt
printf 'version 1 of dem-backup.txt\n' > dem-backup.txt
chmod 640 dem-backup.txt
ln -s dem-backup.txt dem-backup-link.txt
printf 'version 1 of dem-hard.txt, also named dem-hard-twin.txt\n' > dem-hard.txt
ln dem-hard.txt dem-hard-twin.txt 2>/dev/null || echo "  (no hard links on this disk: step 7 of dem-backup.gls cannot be tried)"
printf 'version 1 of dem-autosave.txt: type below, do not save\n' > dem-autosave.txt
made dem-backup.txt
made dem-hard.txt
made dem-autosave.txt
awk 'BEGIN { for (i = 0; i < 180000; i++) printf "line %06d of eleven megabytes, too large to be auto-saved..\n", i }' > dem-autosave-big.txt
made dem-autosave-big.txt

if [ "${1:-}" = huge ]; then
	echo "  dem-huge.txt (1.28 GB): a minute or two"
	awk 'BEGIN { for (i = 0; i < 18000000; i++) printf "huge %08d: ção € 😀 a line of a file of more than a gigabyte\n", i }' > dem-huge.txt
	made dem-huge.txt
fi
echo "done; the guidelines are the dem-*.gls files (start with dem-read-me.gls)"
