#!/bin/sh
# Native read/copy modes: real terminal keys, long files and edit protection.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-read-mode.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
# Shared runners can be much slower than a local terminal.
traversal_timeout=${CHEZWEB_READ_MODE_TIMEOUT:-180}
# Fast typematic input; keep the existing PTY runner and its output checks.
sed 's/drain(30)/drain(2)/' tests/pty-keys.c > "$work/pty.c"
$cc -O2 "$work/pty.c" -o "$work/pty" -lutil 2>/dev/null || $cc -O2 "$work/pty.c" -o "$work/pty"
awk 'BEGIN {for(i=1;i<=1829;i++) printf "line %04d\n",i}' > "$work/long.md"
cp "$work/long.md" "$work/original"
for mode in read vim; do
 for key in down enter; do
  {
   printf 'wait 1000\n'
   if [ "$mode" = read ]; then printf 'keys ^X^Q\n'; else printf 'keys \\exvim-mode\\r\n'; fi
   printf 'wait 200\n'
   # Acknowledged batches keep a slow runner's terminal input queue bounded.
   # Every checkpoint verifies progress, rather than merely sleeping longer.
   awk -v key="$key" 'BEGIN {
    for(i=1;i<=1900;i++) {
     print (key=="down" ? "keys \\e[B" : "keys \\r")
     if(i%200==0) {
      line=(i+1<1830 ? i+1 : 1830)
      print "keys \\e:"
      printf "keys (list (quote NAV-CHECKPOINT) %d (= (line-number) %d))\\r\n",i,line
      printf "await-screen (NAV-CHECKPOINT %d #t)\n",i
     }
    }
   }'
   printf 'keys \\e:\nwait 100\n'
   printf "keys (list 'NATIVE-END (line-number) (buffer-read-only?))\\\\r\n"
   # A final newline means EOF is logical line 1830, as in Emacs mode.
   printf 'await-screen (NATIVE-END 1830 #t)\n'
   printf 'keys i\nkeys ^X^C\n'
  } > "$work/keys"
  if CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" "$traversal_timeout" "$work/screen" ./chezemax "$work/long.md"; then :
  else
   status=$?
   # Keep failure evidence bounded, even for the long scrolling fixture.
   tail -c 32768 "$work/screen" >&2
   exit "$status"
  fi
  if grep -aq 'Compiled Scheme.*error\|heap out of memory' "$work/screen"; then echo "FAIL $mode $key hook error";exit 1;fi
  cmp "$work/long.md" "$work/original"
  echo "PASS $mode $key traverses 1829 lines without edits or hook errors"
 done
done
# Exercise native copy state, Unicode boundaries and edit refusal in both
# runtimes. These operations do not need a display or external clipboard.
for runtime in compiled femtoscheme; do
 result=$(CHEZEMAX_SCHEME=$runtime CHEZEMAX_NO_INIT=1 ./chezemax --eval '
 (begin
  (insert "αβ🙂\nsecond\nthird") (goto-char 0) (enter-normal-mode (quote vim))
  (vim-key "v") (vim-key "l") (vim-key "l") (vim-key "y")
  (let ((copied (get-clipboard)))
  (vim-key "x") (vim-key "d") (vim-key "d") (vim-key "p")
  (vim-key "u") (vim-key "C-r") (vim-key "o") (vim-key "r")
  (undo) (redo)
  (let ((protected (and (buffer-read-only?) (string=? (buffer-substring 0 (buffer-size)) "αβ🙂\nsecond\nthird"))))
  (goto-char 0) (vim-key "y") (vim-key "y")
  (let ((line-copy (get-clipboard)))
  (leave-normal-mode)
  (list (string=? copied "αβ🙂") (string=? line-copy "αβ🙂\n") protected (begin (insert "X") (and (not (buffer-read-only?)) (string=? (buffer-substring 0 1) "X"))))))))')
 case "$result" in *'(#t #t #t #t)') ;; *) echo "FAIL $runtime native selection/copy/protection: $result";exit 1 ;; esac
 echo "PASS $runtime UTF-8 selection, yy, Vim edit refusal and explicit exit"
done
for runtime in compiled femtoscheme; do
 result=$(CHEZEMAX_SCHEME=$runtime CHEZEMAX_NO_INIT=1 ./chezemax --eval '
 (begin
  (insert "a\nb\nc\n") (goto-char 0) (enter-normal-mode (quote read))
  (vim-key "3") (vim-key "y") (vim-key "y")
  (let ((three (string=? (get-clipboard) "a\nb\nc\n")))
   (vim-key "v") (vim-key "C-g")
   (let ((cancelled (eq? (vim-state) (quote normal))))
    (goto-char 0) (vim-key "9") (vim-key "C-g") (vim-key "l")
    (let ((count-cancelled (= (point) 1)))
     (vim-key "3") (vim-key "G") (vim-key "g") (vim-key "g")
     (let ((top (= (point) 0)))
      (leave-normal-mode)
      (list three cancelled count-cancelled top))))))')
 case "$result" in *'(#t #t #t #t)') ;; *) echo "FAIL $runtime counts/cancellation: $result";exit 1 ;; esac
 echo "PASS $runtime counted yy, cancelled counts/selections and gg"
done
# Cumulative regression: reuse the same process and store across mode switches.
# The original one-pass tests missed retained objects surviving each traversal.
awk 'BEGIN {for(i=1;i<=1829;i++) printf "line %04d: cumulative scrolling keeps these wrapped prose rows in the same editor process for every pass.\n",i}' > "$work/cumulative.md"
cp "$work/cumulative.md" "$work/cumulative.original"
{
 printf 'wait 1000\nkeys \\exvim-mode\\r\nwait 200\n'
 for pass in 1 2 3 4; do
  if [ "$pass" -gt 1 ]; then
   if [ $((pass % 2)) = 0 ]; then printf 'keys ^X^Q\n'; else printf 'keys \\exvim-mode\\r\n'; fi
   printf 'keys gg\n'
  fi
  awk -v pass="$pass" 'BEGIN {
   for(i=1;i<=4000;i++) {
    print "keys \\r"
    if(i%200==0) {
     print "keys \\e:"
     printf "keys (list (quote CUMULATIVE-BATCH) %d %d)\\r\n",pass,i
     printf "await-screen (CUMULATIVE-BATCH %d %d)\n",pass,i
    }
   }
  }'
  printf 'keys \\e:\nwait 100\n'
  printf "keys (list 'CUMULATIVE-%s (= (point) (buffer-size)) (buffer-read-only?))\\\\r\n" "$pass"
  printf 'await-screen (CUMULATIVE-%s #t #t)\n' "$pass"
 done
 printf 'keys i\nkeys ^X^C\n'
} > "$work/keys"
# 16,000 keys at this runner's 2 ms delay take at least 32 seconds,
# plus rendering and per-pass evaluations; retain a generous overall budget.
CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 600 "$work/screen" ./chezemax "$work/cumulative.md"
if grep -aq 'Compiled Scheme.*error\|heap out of memory' "$work/screen"; then echo 'FAIL cumulative scrolling hook error';exit 1;fi
cmp "$work/cumulative.md" "$work/cumulative.original"
echo 'PASS four wrapped-file traversals and Vim/READ switches in one process'
