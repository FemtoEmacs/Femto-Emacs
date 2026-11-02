# program-files.awk -- the files make compiles into chezemax.wasm: those
# of compiled/PROGRAM, with <ORDER> replaced by compiled/scripts/ORDER (the
# editor's scripts); <USERS> (your own code) is --compile-scripts' alone.
/^#/ || /^[ \t]*$/ { next }
$1 == "<ORDER>" {
    while ((getline line < "compiled/scripts/ORDER") > 0)
        if (line != "" && line !~ /^#/) print line
    close("compiled/scripts/ORDER")
    next
}
$1 == "<USERS>" { next }
{ print $1 }
