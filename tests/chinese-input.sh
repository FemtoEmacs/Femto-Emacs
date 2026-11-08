#!/bin/sh
# M-x chinese-input: Chinese typed in tonal pinyin, through a terminal, then
# saved.  zhong 1 1: 中; 1: 国, its first 联想 follower; ni3 1 你; hao3 SPC
# 好; , ，; wo SPC 我 (the first before a tone); abc RET: abc as typed;
# zhonx DEL g 1 2: 钟, the second of zhong1; ma C-g: nothing; off: ok.  The
# tables are not read before the input is turned on, nor kept after it is
# turned off.  Disposable home, file and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-chinese.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
: > "$work/zh.txt"
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \e:
wait 300
keys (if *chinese-pinyin* 'tables-before 'none-before)\r
wait 2500
keys \exchinese-input\r
wait 1500
keys zhong11
keys 1
keys ni31hao3 ,
keys wo 
keys abc\r
keys zhonx^?g12
keys ma^G
keys \exchinese-input\r
wait 500
keys ok
keys \e:
wait 300
keys (if *chinese-pinyin* 'tables-after 'none-after)\r
wait 2500
keys ^X^S
wait 300
keys ^X^C
KEYS
(cd "$work"; HOME="$work/home" LC_ALL=C.UTF-8 CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" zh.txt)
printf '中国你好，我abc钟ok' > "$work/expected"
cmp -s "$work/zh.txt" "$work/expected" || { echo 'FAIL the pinyin did not give the expected text'; echo " got: $(cat "$work/zh.txt")"; exit 1; }
grep -q 'none-before' "$work/screen" && grep -q 'none-after' "$work/screen" ||
 { echo 'FAIL the tables were there before M-x chinese-input, or after it was turned off'; exit 1; }
grep -q '中\[' "$work/screen" || grep -q ' 中' "$work/screen" || { echo 'FAIL the mode line did not show 中'; exit 1; }
echo 'PASS tonal pinyin types Chinese, with 联想 followers; no tables before or after'
