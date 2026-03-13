#!/bin/bash
# bbtex-bbedit-clean.sh — BBEdit wrapper for LaTeX clean.
#
# Thin wrapper: calls bbtex clean, shows notification.

set -euo pipefail

REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
if [[ -x "$PARENT/Resources/bbtex" ]]; then
    BBTEX="$PARENT/Resources/bbtex"
else
    BBTEX="$PARENT/_build/default/bin/main.exe"
fi

[[ -z "${BB_DOC_PATH:-}" ]] && { osascript -e 'display alert "No document open" message "Open a .tex file first." as warning'; exit 1; }

OUTPUT=$("$BBTEX" clean "$BB_DOC_PATH" 2>/dev/null) && EXIT=0 || EXIT=$?

if [[ $EXIT -eq 0 ]]; then
    osascript -e 'display notification "Build artifacts removed" with title "LaTeX: Clean" sound name "Glass"' &
else
    MESSAGE=""
    while IFS= read -r line; do
        case "${line%%: *}" in
            message) MESSAGE="${line#*: }" ;;
        esac
    done <<< "$OUTPUT"
    osascript -e "display alert \"LaTeX Clean failed\" message \"${MESSAGE:-unknown error}\" as warning" &
    exit 1
fi

exit 0
