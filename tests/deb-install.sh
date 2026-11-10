#!/bin/sh
# The Debian package on a clean system (.github/workflows/linux-deb.yml
# runs it, as root, in ubuntu:22.04, ubuntu:24.04 and debian:12 containers):
#   sh tests/deb-install.sh chezweb_VERSION_ARCH.deb
# apt installs the package and the libraries it needs; postinst makes the
# machine code; chezweb starts from any folder, runs its compiled program,
# and in a terminal types, uses M-x korean-input and saves; apt remove
# leaves nothing in /opt/chezweb and /usr/bin.
set -eu
deb=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
here=$(cd "$(dirname "$0")" && pwd)
fail() { echo "FAIL $1"; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -q "$deb" > /tmp/deb-install.log 2>&1 || { tail -30 /tmp/deb-install.log; fail 'apt could not install the package'; }
grep -q 'making the machine code' /tmp/deb-install.log || fail 'postinst did not run'
[ -s /opt/chezweb/chezemax.cwasm ] && [ -s /opt/chezweb/schemer/compiler.cwasm ] || fail 'postinst made no machine code'
cd /tmp
chezweb --version | grep -q '^Chezweb ' || fail 'chezweb --version'
[ "$(CHEZEMAX_NO_INIT=1 chezweb --eval '(fe-install-dir)')" = '"/opt/chezweb"' ] || fail 'the editor did not find /opt/chezweb'
[ "$(CHEZEMAX_NO_INIT=1 chezweb --eval '(+ 1 2)')" = 3 ] || fail 'the compiled program did not run'
echo 'PASS apt installs the package with its libraries; postinst makes the machine code; chezweb runs from any folder'

# a terminal session (a compiler only now, for the test's PTY driver)
apt-get install -y -q gcc libc6-dev > /dev/null 2>&1
work=$(mktemp -d)
cc -O2 "$here/pty-keys.c" -o "$work/pty" -lutil
mkdir -p "$work/home"
: > "$work/t.txt"
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys Hello from the package\r
keys \exkorean-input\r
wait 300
keys gksrmf\r
keys \exkorean-input\r
wait 300
keys ^X^S
wait 300
keys ^X^C
KEYS
(cd "$work"; HOME="$work/home" LC_ALL=C.UTF-8 TERM=xterm CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" /usr/bin/chezweb t.txt) || true
printf 'Hello from the package\n한글\n' | cmp -s - "$work/t.txt" || { cat "$work/t.txt"; fail 'the terminal session did not type and save'; }
echo 'PASS the installed editor types, uses M-x korean-input and saves, in a terminal'

apt-get remove -y -q chezweb > /dev/null 2>&1
[ ! -e /opt/chezweb ] && [ ! -e /usr/bin/chezweb ] && [ ! -e /usr/bin/chezweb-gui ] || fail 'apt remove left files behind'
echo 'PASS apt remove leaves nothing behind'
