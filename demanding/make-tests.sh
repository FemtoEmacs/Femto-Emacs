#!/bin/sh
# make-tests.sh -- fresh files for the interaction tests of
# demanding/interactions, for trying Chezweb by hand:
#
#   natbrowser-interaction.org  the browser and the native window saving
#                               natbrowser-test.md (and Save As into
#                               natbrowser-copy.md, which step 7 creates)
#   vsplit.md                   C-x 3, on vsplit-test.md and vsplit-test.c
#
#   sh make-tests.sh
#
# Each run puts back the scripts and test files as they are in
# interactions/fresh (the scripts too: their [ ] boxes start empty), and
# removes what a run creates (natbrowser-copy.md, the #...# recovery and
# auto-save files).  The previous run's files go first to
# interactions/bkp/run-DATE, so nothing of a run is lost.  It also copies
# the backdoor's configuration for these tests to
# ~/.chezemax/backdoor-claude.conf, keeping the one there in
# ~/.chezemax/bkp.
set -eu
cd "$(dirname "$0")/interactions"
files="natbrowser-interaction.org natbrowser-test.md vsplit.md vsplit-test.md vsplit-test.c"
made="natbrowser-copy.md #natbrowser-test.md# #natbrowser-copy.md# #vsplit-test.md# #vsplit-test.c# #vsplit.md#"

run=bkp/run-$(date +%Y%m%d-%H%M%S)
mkdir -p "$run"
for f in $files $made; do
	[ -e "$f" ] && cp -p "$f" "$run/"
done
[ -f "$HOME/.chezemax/backdoor.txt" ] && cp -p "$HOME/.chezemax/backdoor.txt" "$run/"
echo "the previous run's files: interactions/$run"

for f in $made; do rm -f "$f"; done
for f in $files; do cp fresh/"$f" "$f"; done
echo "fresh: $files"

mkdir -p "$HOME/.chezemax/bkp"
conf="$HOME/.chezemax/backdoor-claude.conf"
if [ -f "$conf" ] && ! cmp -s "$conf" fresh/backdoor.conf; then
	cp -p "$conf" "$HOME/.chezemax/bkp/backdoor-claude.conf.before-interactions"
	echo "your backdoor configuration kept in ~/.chezemax/bkp/backdoor-claude.conf.before-interactions"
fi
cp fresh/backdoor.conf "$conf"
echo "the backdoor is configured for these tests (~/.chezemax/backdoor-claude.conf)"
echo "start with: cd $(pwd); then open natbrowser-interaction.org or vsplit.md"
