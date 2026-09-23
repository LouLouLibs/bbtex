#!/bin/bash
# Build reusable BBEdit editing assets. No changes to the installed application.
#   scripts/build-support.sh [DESTINATION]   (default: dist/bbtex-support.bbpackage)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/support"
DESTINATION="${1:-$ROOT/dist/bbtex-support.bbpackage}"
CONTENTS="$DESTINATION/Contents"
BINARY="$ROOT/_build/default/bin/main.exe"

if [[ ! -f "$BINARY" ]]; then
    echo "Run dune build before building editing support" >&2
    exit 1
fi

# Merge support/Contents into the destination. macOS cp: -X skips extended
# attributes (GNU cp has no -X); the stationery flag is set explicitly below.
mkdir -p "$CONTENTS"
/bin/cp -R -X "$SOURCE/Contents/." "$CONTENTS/"

# Dune artifacts can be read-only. Replace an existing copy rather than
# opening it for writing, so repeat builds work on clean CI runners too.
RESOURCES="$CONTENTS/Resources"
mkdir -p "$RESOURCES"
STAGING="$(mktemp -d "$RESOURCES/.bbtex-XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
cp -p "$BINARY" "$STAGING/bbtex"
mv -f "$STAGING/bbtex" "$RESOURCES/bbtex"

cp "$SOURCE/THIRD-PARTY-NOTICES.md" "$SOURCE/README.md" "$DESTINATION/"

while IFS= read -r -d '' script; do
    relative="${script#"$SOURCE/AppleScriptSources/"}"
    output="$CONTENTS/${relative%.applescript}.scpt"
    mkdir -p "$(dirname "$output")"
    osacompile -o "$output" "$script"
done < <(find "$SOURCE/AppleScriptSources" -name '*.applescript' -print0 | sort -z)

# Git does not retain Finder metadata. Restore the stationery flag on build:
# byte 8 of FinderInfo, bit 0x08.
for template in "$CONTENTS/Stationery/"*.tex; do
    [[ -e "$template" ]] || continue
    info="$(xattr -px com.apple.FinderInfo "$template" 2>/dev/null | tr -d ' \n' || true)"
    [[ -n "$info" ]] || info="$(printf '%064d' 0)"
    flags=$(( 16#${info:16:2} | 0x08 ))
    info="${info:0:16}$(printf '%02X' "$flags")${info:18}"
    xattr -wx com.apple.FinderInfo "$info" "$template"
done

# Clipping scripts are looked up relative to their clipping set.
while IFS= read -r -d '' clipping; do
    folder="$(dirname "$clipping")"
    while IFS= read -r reference; do
        name="${reference#\#script }"
        name="${name%\#}"
        if [[ ! -f "$folder/$name" ]]; then
            echo "Missing clipping script: $clipping -> $name" >&2
            exit 1
        fi
    done < <(grep -a -o '#script [^#]*#' "$clipping" || true)
done < <(find "$CONTENTS/Clippings" -type f ! -name '*.scpt' -print0)

echo "Built editing support: $DESTINATION"
