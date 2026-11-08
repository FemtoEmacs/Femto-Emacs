#!/bin/sh
# chinese-tables.sh -- make Chinese/pinyin.txt and Chinese/lianxiang.txt, the
# tables of M-x chinese-input (compiled/scripts/chinese.scm).  Maintainers
# only: users get the tables made, in Chinese/.  Needs sh, awk and sort.
#
#   sh tools/chinese-tables.sh kTGHZ2013.txt dict.txt
#
# kTGHZ2013.txt: Unihan's kTGHZ2013 field, the 8105 characters of the
#   Tongyong Guifan Hanzi Biao (2013) with their readings, as kept by
#   https://github.com/mozillazg/pinyin-data (MIT; Unihan: Unicode licence).
# dict.txt: jieba's dictionary, words with frequencies,
#   https://github.com/fxsjy/jieba (MIT).
#
# pinyin.txt: "SYLLABLE+TONE CHARACTERS", tones 1-4 and 5 (neutral), u-umlaut
#   written v; the characters of the list read so, most frequent first (the
#   frequency of the character as a word in dict.txt).  Also "SYLLABLE
#   CHARACTERS", without the tone: every tone, most frequent first.
# lianxiang.txt: "CHARACTER FOLLOWERS": for each character of the list, at
#   most 9 characters of the list that follow it in the most frequent
#   two-character words of dict.txt, most frequent first.
set -eu
[ $# = 2 ] || { echo 'usage: sh tools/chinese-tables.sh kTGHZ2013.txt dict.txt' >&2; exit 2; }
cd "$(dirname "$0")/.."
export LC_ALL=C
work=$(mktemp -d "${TMPDIR:-/tmp}/chinese-tables.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

# the characters and their readings, tone marks made numbers: CHAR SYLLABLE
awk '
BEGIN {
  split("ā a 1 á a 2 ǎ a 3 à a 4 ē e 1 é e 2 ě e 3 è e 4 ī i 1 í i 2 ǐ i 3 ì i 4 " \
        "ō o 1 ó o 2 ǒ o 3 ò o 4 ū u 1 ú u 2 ǔ u 3 ù u 4 ǖ v 1 ǘ v 2 ǚ v 3 ǜ v 4 " \
        "ü v 5 ń n 2 ň n 3 ǹ n 4 ḿ m 2", t, " ")
  for (i = 1; i in t; i += 3) { mark[t[i]] = t[i+1]; tone[t[i]] = t[i+2] }
}
/^U\+/ {
  c = $0; sub(/.*# */, "", c); sub(/ .*/, "", c)
  r = $0; sub(/^[^:]*: */, "", r); sub(/ *#.*/, "", r)
  n = split(r, rs, ",")
  for (k = 1; k <= n; k++) {
    s = rs[k]; d = 5
    for (m in mark) if (index(s, m)) { if (tone[m] != 5) d = tone[m]; gsub(m, mark[m], s) }
    if (s ~ /^[a-z]+$/) { print c, s d; print c, s }
  }
}' "$1" > "$work/readings"

# frequencies: single characters and two-character words of the list
awk 'NR == FNR { inlist[$1] = 1; next }
     length($1) == 3 && ($1 in inlist) { print "1", $1, $2 }
     length($1) == 6 && (substr($1,1,3) in inlist) && (substr($1,4,3) in inlist) { print "2", $1, $2 }' \
    "$work/readings" "$2" > "$work/freq"

# pinyin.txt
awk 'NR == FNR { if ($1 == "1") f[$2] = $3; next }
     { print $2, ($1 in f) ? f[$1] : 0, $1 }' "$work/freq" "$work/readings" |
  sort -k1,1 -k2,2nr -k3,3 |
  awk '$1 != s { if (s != "") print s, line; s = $1; line = ""; delete seen }
       !($3 in seen) { line = line $3; seen[$3] = 1 }
       END { print s, line }' > Chinese/pinyin.txt

# lianxiang.txt
awk '$1 == "2" { print substr($2,1,3), $3, substr($2,4,3) }' "$work/freq" |
  sort -k1,1 -k2,2nr |
  awk '$1 != c { if (c != "") print c, line; c = $1; line = ""; n = 0; delete seen }
       n < 9 && !($3 in seen) && $3 != $1 { line = line $3; seen[$3] = 1; n++ }
       END { if (c != "") print c, line }' > Chinese/lianxiang.txt

printf '%s syllables in pinyin.txt, %s characters with followers in lianxiang.txt\n' \
  "$(wc -l < Chinese/pinyin.txt)" "$(wc -l < Chinese/lianxiang.txt)"
