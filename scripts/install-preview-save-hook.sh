#!/bin/bash
# Build BBEdit's optional save attachment (Document.documentDidSave.scpt), and
# with --apply install it without replacing anyone else's Document/BBEdit hooks.
#   install-preview-save-hook.sh [--apply]
set -Eeuo pipefail
trap 'echo "${0##*/}: failed at line $LINENO: $BASH_COMMAND" >&2' ERR

fail() { echo "${0##*/}: $*" >&2; exit 1; }
for tool in osacompile osadecompile /sbin/md5 /usr/bin/cmp; do
    command -v "$tool" >/dev/null || fail "$tool not found"
done
APPLY=false
SUPPORT_DIR="$HOME/Library/Application Support/BBEdit"
while (( $# > 0 )); do
    case "$1" in
        --apply) APPLY=true; shift ;;
        --bbedit-support) SUPPORT_DIR="${2:?--bbedit-support requires a directory}"; shift 2 ;;
        *) fail "usage: ${0##*/} [--apply] [--bbedit-support DIRECTORY]" ;;
    esac
done

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

FOLDER="$SUPPORT_DIR/Attachment Scripts"
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
    if [[ "$existing" == "$TARGET" && -f "$existing" ]]; then
        RECEIPT="$TARGET.bbtex-receipt"
        if [[ -f "$RECEIPT" ]] &&
            [[ "$(cat "$RECEIPT")" == "bbtex-save-hook-v1:$(/sbin/md5 -q "$TARGET")" ]]; then
            continue
        fi
        # A legacy hook without a receipt is only adopted when its full
        # decompiled source matches the current installer output.
        if [[ ! -e "$RECEIPT" ]] &&
            osadecompile "$existing" >"$BUILD/existing-hook.applescript" 2>/dev/null &&
            osadecompile "$OUTPUT" >"$BUILD/current-hook.applescript" 2>/dev/null &&
            /usr/bin/cmp -s "$BUILD/existing-hook.applescript" "$BUILD/current-hook.applescript"; then
            continue
        fi
    fi
    fail "Existing attachment needs manual integration: $existing"
done
/bin/cp "$OUTPUT" "$TARGET.tmp"
/bin/mv -f "$TARGET.tmp" "$TARGET"
printf 'bbtex-save-hook-v1:%s\n' "$(/sbin/md5 -q "$TARGET")" >"$TARGET.bbtex-receipt.tmp"
/bin/mv -f "$TARGET.bbtex-receipt.tmp" "$TARGET.bbtex-receipt"
echo "Installed: $TARGET"
