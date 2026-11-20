#!/bin/sh
# Reject missing/invalid measurements rather than treating them as zero.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-speed-report.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
report() { awk -F '\t' -v fx=test -v big=8388608 -f tests/speed-report.awk "$work/input" > "$work/output"; }
printf 'local\tcommand\tkeys\t1.0\t2.0\n' > "$work/input"
report
grep -q '^ok' "$work/output"
for values in 'empty' 'short' 'nonnumeric'; do
  case "$values" in
    empty) printf 'local\tcommand\tkeys\t\t\n' ;;
    short) printf 'local\tcommand\tkeys\t1.0\n' ;;
    nonnumeric) printf 'local\tcommand\tkeys\t1.0\tmissing\n' ;;
  esac > "$work/input"
  if report; then echo "FAIL accepted $values timings"; exit 1; fi
  grep -q '^MISSING' "$work/output"
done
printf 'local\tcommand\tkeys\t1.0\t1000.0\n' > "$work/input"
report
# Use portable sed branches, as the benchmark does, on macOS and Linux.
sed -n -e '/^SLOW/p' -e '/^MISSING/p' "$work/output" | grep -q '^SLOW'
echo 'PASS speed report rejects missing and malformed times and shows slow rows'
