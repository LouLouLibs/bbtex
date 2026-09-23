#!/bin/bash
# Build reusable BBEdit editing assets. No changes to the installed application.
#   scripts/build-support.sh [DESTINATION]   (default: dist/bbtex-support.bbpackage)
set -Eeuo pipefail
trap 'echo "${0##*/}: failed at line $LINENO: $BASH_COMMAND" >&2' ERR

fail() { echo "${0##*/}: $*" >&2; exit 1; }
for tool in osacompile xattr; do
    command -v "$tool" >/dev/null || fail "$tool not found (macOS developer tools required)"
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/support"
DESTINATION="${1:-$ROOT/dist/bbtex-support.bbpackage}"
CONTENTS="$DESTINATION/Contents"
BINARY="$ROOT/_build/default/bin/main.exe"
[[ -f "$BINARY" ]] || fail "Run dune build before building editing support"

# Writes NUL-separated paths from find to FILE, failing if find fails (a failed
# find inside a process substitution would otherwise look like "no files").
list() {
    local file="$1"; shift
    /usr/bin/find "$@" -print0 > "$file" || fail "find $* failed"
}

TEMPORARY="$(mktemp -d)"
trap 'rm -rf "$TEMPORARY"' EXIT

# Merge support/Contents into the destination. macOS cp: -X skips extended
# attributes (GNU cp has no -X); the stationery flag is set explicitly below.
mkdir -p "$CONTENTS"
/bin/cp -R -X "$SOURCE/Contents/." "$CONTENTS/"

# Dune artifacts can be read-only. Replace an existing copy rather than
# opening it for writing, so repeat builds work on clean CI runners too.
RESOURCES="$CONTENTS/Resources"
mkdir -p "$RESOURCES"
STAGING="$(mktemp -d "$RESOURCES/.bbtex-XXXXXX")"
trap 'rm -rf "$TEMPORARY" "$STAGING"' EXIT
/bin/cp -p "$BINARY" "$STAGING/bbtex"
/bin/mv -f "$STAGING/bbtex" "$RESOURCES/bbtex"

/bin/cp "$SOURCE/THIRD-PARTY-NOTICES.md" "$SOURCE/README.md" "$DESTINATION/"

list "$TEMPORARY/scripts" "$SOURCE/AppleScriptSources" -name '*.applescript'
while IFS= read -r -d '' script; do
    relative="${script#"$SOURCE/AppleScriptSources/"}"
    output="$CONTENTS/${relative%.applescript}.scpt"
    mkdir -p "$(dirname "$output")"
    osacompile -o "$output" "$script"
done < "$TEMPORARY/scripts"

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
list "$TEMPORARY/clippings" "$CONTENTS/Clippings" -type f ! -name '*.scpt'
while IFS= read -r -d '' clipping; do
    folder="$(dirname "$clipping")"
    references="$(grep -a -o '#script [^#]*#' "$clipping" || true)"
    [[ -n "$references" ]] || continue
    while IFS= read -r reference; do
        name="${reference#\#script }"
        name="${name%\#}"
        [[ -f "$folder/$name" ]] || fail "Missing clipping script: $clipping -> $name"
    done <<< "$references"
done < "$TEMPORARY/clippings"

echo "Built editing support: $DESTINATION"
