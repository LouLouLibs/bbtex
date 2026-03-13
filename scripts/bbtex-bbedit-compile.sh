#!/bin/bash
# bbtex-bbedit-compile.sh — BBEdit wrapper for LaTeX compilation.
#
# Thin wrapper: saves document, calls bbtex compile, runs
# the generated AppleScript, opens PDF, shows notification.
# All logic is in the OCaml binary.

set -euo pipefail

REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
# Package layout: Contents/Resources/bbtex — Dev layout: project/_build/default/bin/main.exe
if [[ -x "$PARENT/Resources/bbtex" ]]; then
    BBTEX="$PARENT/Resources/bbtex"
else
    BBTEX="$PARENT/_build/default/bin/main.exe"
fi

[[ -z "${BB_DOC_PATH:-}" ]] && { osascript -e 'display alert "No document open" message "Open a .tex file first." as warning'; exit 1; }

mkdir -p "$HOME/.local/state/bbtex"
osascript -e 'tell application "BBEdit" to save front document' 2>/dev/null || true

# Capture output and exit code — bbtex returns 1 for LaTeX errors, which is normal
OUTPUT=$("$BBTEX" compile "$BB_DOC_PATH" 2>"$HOME/.local/state/bbtex/last-compile.log") && EXIT=0 || EXIT=$?

# Parse key-value output (single pass, no external tools)
STATUS="" SUMMARY="" LOG="" PDF="" APPLESCRIPT_FILE="" MESSAGE=""
while IFS= read -r line; do
    case "${line%%: *}" in
        status)           STATUS="${line#*: }" ;;
        summary)          SUMMARY="${line#*: }" ;;
        log)              LOG="${line#*: }" ;;
        pdf)              PDF="${line#*: }" ;;
        applescript_file) APPLESCRIPT_FILE="${line#*: }" ;;
        message)          MESSAGE="${line#*: }" ;;
    esac
done <<< "$OUTPUT"

# Suppress stdout so BBEdit doesn't show "Unix Script Output".
# Stderr goes to the debug log for troubleshooting (not /dev/null).
exec >/dev/null 2>>"$HOME/.local/state/bbtex/last-compile.log"

if [[ $EXIT -eq 2 ]]; then
    osascript -e "display alert \"bbtex error\" message \"${MESSAGE:-unknown error}\" as warning" &
    exit 1
fi

# Open PDF in background (don't steal focus from BBEdit)
if [[ -n "$PDF" && -f "$PDF" ]]; then
    open -g -a Skim "$PDF" &
fi

# Open .log file only when there are errors (no need on clean success)
if [[ "$STATUS" != "success" && -n "$LOG" && -f "$LOG" ]]; then
    bbedit "$LOG"
fi

# Refocus the .tex document
bbedit "$BB_DOC_PATH"

# Results browser with errors/warnings/badboxes.
# Created last so it appears on top of the editor window.
if [[ -n "$APPLESCRIPT_FILE" && -f "$APPLESCRIPT_FILE" ]]; then
    osascript "$APPLESCRIPT_FILE" || true
fi

# Notification (never steals focus)
if [[ "$STATUS" == "success" ]]; then
    osascript -e "display notification \"$SUMMARY\" with title \"LaTeX: Success\" sound name \"Glass\"" &
else
    osascript -e "display notification \"$SUMMARY\" with title \"LaTeX: Errors\" sound name \"Basso\"" &
fi

exit 0
