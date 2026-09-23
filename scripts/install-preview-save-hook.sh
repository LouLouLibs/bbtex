#!/bin/bash
# Build BBEdit's optional save attachment (Document.documentDidSave.scpt), and
# with --apply install it without replacing anyone else's Document/BBEdit hooks.
#   install-preview-save-hook.sh [--apply]
set -Eeuo pipefail
trap 'echo "${0##*/}: failed at line $LINENO: $BASH_COMMAND" >&2' ERR

fail() { echo "${0##*/}: $*" >&2; exit 1; }
for tool in osacompile osadecompile; do
    command -v "$tool" >/dev/null || fail "$tool not found"
done
APPLY=false
case "${1:-}" in
    "") ;;
    --apply) APPLY=true ;;
    *) fail "usage: ${0##*/} [--apply]" ;;
esac

HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HERE/preview-save-hook.applescript"
[[ -f "$SOURCE" ]] || fail "missing $SOURCE"
# Inside a release package (Contents/Resources) build into a temporary folder;
# in a checkout, into dist/ so the result can be inspected.
if [[ "${HERE##*/}" == Resources ]]; then
    BUILD="$(mktemp -d "${TMPDIR:-/tmp}/bbtex-hook-XXXXXX")"
    trap 'rm -rf "$BUILD"' EXIT
else
    BUILD="$(dirname "$HERE")/dist"
    mkdir -p "$BUILD"
fi
OUTPUT="$BUILD/Document.documentDidSave.scpt"
osacompile -o "$OUTPUT" "$SOURCE"
echo "Built: $OUTPUT"
$APPLY || exit 0

FOLDER="$HOME/Library/Application Support/BBEdit/Attachment Scripts"
TARGET="$FOLDER/${OUTPUT##*/}"
mkdir -p "$FOLDER"
for existing in "$FOLDER"/*; do
    [[ -e "$existing" || -L "$existing" ]] || continue
    name="${existing##*/}"
    case "${name%.*}" in
        Document | BBEdit | Document.documentDidSave) ;;
        *) continue ;;
    esac
    # Our own earlier install is replaced; anything else needs a human.
    if [[ "$existing" == "$TARGET" ]] &&
        osadecompile "$existing" 2>/dev/null | grep -q 'LaTeX — Toggle Preview on Save.sh'; then
        continue
    fi
    fail "Existing attachment needs manual integration: $existing"
done
/bin/cp "$OUTPUT" "$TARGET.tmp"
/bin/mv -f "$TARGET.tmp" "$TARGET"
echo "Installed: $TARGET"
