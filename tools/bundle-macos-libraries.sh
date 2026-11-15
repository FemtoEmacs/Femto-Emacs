#!/bin/bash
# Copy Homebrew libraries into the app and rewrite their Mach-O references.
set -euo pipefail

executables="$1/Contents/MacOS"
libraries="$1/Contents/Frameworks"
mkdir "$libraries"

binaries=("$executables/chezweb-gui" "$executables/irene-dixe")
originals=("${binaries[@]}")
for ((index = 0; index < ${#binaries[@]}; index++)); do
    binary=${binaries[index]}
    original=${originals[index]}
    listing=$(otool -L "$binary")
    skip=1
    prefix=@loader_path/../Frameworks
    if [[ ${binary%/*} == "$libraries" ]]; then
        skip=2 # The library's own install name follows the file header.
        prefix=@loader_path
    fi

    while IFS= read -r line; do
        if ((skip > 0)); then
            skip=$((skip - 1))
            continue
        fi
        dependency=${line%% (compatibility version*}
        dependency=${dependency#"${dependency%%[![:space:]]*}"}
        name=${dependency##*/}
        case "$dependency" in
            /opt/homebrew/*|/usr/local/*) source=$(realpath "$dependency") ;;
            @rpath/*|@loader_path/*)
                [[ $prefix == @loader_path ]] || continue
                source=$(realpath "${original%/*}/$name")
                ;;
            *) continue ;;
        esac

        target="$libraries/$name"
        if [[ ! -e $target ]]; then
            cp "$source" "$target"
            chmod 755 "$target"
            install_name_tool -id "@rpath/$name" "$target"
            binaries+=("$target")
            originals+=("$source")
        else
            for ((copied = 2; copied < ${#binaries[@]}; copied++)); do
                [[ ${binaries[copied]} == "$target" ]] || continue
                if [[ ${originals[copied]} != "$source" ]]; then
                    printf 'Conflicting libraries named %s\n' "$name" >&2
                    exit 1
                fi
                break
            done
        fi
        install_name_tool -change "$dependency" "$prefix/$name" "$binary"
    done <<< "$listing"
done
