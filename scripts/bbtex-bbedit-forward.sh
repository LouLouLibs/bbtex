#!/bin/bash
# bbtex-bbedit-forward.sh — BBEdit wrapper for SyncTeX forward search.
#
# Thin wrapper: calls bbtex forward-search, tells Skim to display.

set -euo pipefail

REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
if [[ -x "$PARENT/Resources/bbtex" ]]; then
    BBTEX="$PARENT/Resources/bbtex"
else
    BBTEX="$PARENT/_build/default/bin/main.exe"
fi

[[ -z "${BB_DOC_PATH:-}" ]] && exit 1

OUTPUT=$("$BBTEX" forward-search "$BB_DOC_PATH" "${BB_DOC_SELSTART_LINE:-1}" 2>/dev/null) && true
PDF=""
while IFS= read -r line; do
    case "${line%%: *}" in
        pdf) PDF="${line#*: }" ;;
    esac
done <<< "$OUTPUT"
LINE="${BB_DOC_SELSTART_LINE:-1}"

[[ -z "$PDF" ]] && exit 1

SKIM="/Applications/Skim.app/Contents/SharedSupport/displayline"
if [[ -x "$SKIM" ]]; then
    "$SKIM" -r -b "$LINE" "$PDF" "$BB_DOC_PATH"
else
    open -g -a Skim "$PDF"
fi

# Keep focus on BBEdit
osascript -e 'tell application "BBEdit" to activate' 2>/dev/null &
