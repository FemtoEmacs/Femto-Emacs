#!/bin/sh
# Download the exact sources referenced by each installed package version.
# A separate setup.exe transaction may select a different source-package version.
set -eu
manifest=$1
cache=$2
mirror=https://cygwin.mirror.constant.com
mkdir -p "$cache"
curl --fail --location --retry 3 "$mirror/x86_64/setup.xz" -o "$cache/setup.xz"
xz -dc "$cache/setup.xz" > "$cache/setup.ini"
awk '
 NR==FNR {if(NF==2 && $2 ~ /^[0-9]/) needed[$1]=$2; next}
 /^@ / {package=$2; version=""; next}
 /^version: / {version=$2; next}
 /^source: / {if(package in needed && version==needed[package]) {
   found[package]=1; archives[$2]=$3 " " $4
 }}
 END {
   failed=0
   for(package in needed) if(!found[package]) {
     print "Missing source for " package " " needed[package] > "/dev/stderr"; failed=1
   }
   if(failed) exit 1
   for(path in archives) print path " " archives[path]
 }' "$manifest" "$cache/setup.ini" > "$cache/sources.list.tmp"
sort "$cache/sources.list.tmp" > "$cache/sources.list"
rm "$cache/sources.list.tmp"
[ -s "$cache/sources.list" ]
: > "$cache/SHA512SUMS"
while read -r path bytes digest; do
 mkdir -p "$cache/$(dirname "$path")"
 echo "Source: $path"
 curl --fail --location --retry 3 "$mirror/$path" -o "$cache/$path"
 [ "$(wc -c < "$cache/$path" | tr -d ' ')" = "$bytes" ]
 printf '%s  %s\n' "$digest" "$path" >> "$cache/SHA512SUMS"
done < "$cache/sources.list"
(cd "$cache" && sha512sum -c SHA512SUMS)
cp "$manifest" "$cache/installed-packages.txt"
echo 'PASS exact installed component sources and SHA-512 checksums'
