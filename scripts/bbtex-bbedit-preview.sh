#!/bin/bash
# Preview without saving documents. Modified project inputs need an explicit save.
set -euo pipefail
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
BBTEX="$PARENT/_build/default/bin/main.exe"
[[ ! -x "$PARENT/Resources/bbtex" ]] || BBTEX="$PARENT/Resources/bbtex"
alert() {
    osascript - "$1" <<'APPLESCRIPT'
on run argv
    tell application "BBEdit" to display alert "LaTeX Selection Preview" message (item 1 of argv)
end run
APPLESCRIPT
}
[[ -n "${BB_DOC_PATH:-}" ]] || { alert "Open a saved TeX document first."; exit 1; }
PROJECT_OUTPUT=$("$BBTEX" paths "$BB_DOC_PATH") || { alert "$PROJECT_OUTPUT"; exit 1; }
# Refuse while any project input has unsaved changes (the build's own rule:
# bbtex save-project --check), then read the selection, in one AppleScript run.
CHECK_SCRIPT=$("$BBTEX" save-project --check "$BB_DOC_PATH") || { alert "$CHECK_SCRIPT"; exit 1; }
CAPTURE_ERROR="$(mktemp)"
trap 'rm -f "$CAPTURE_ERROR"' EXIT
if ! CAPTURE=$(osascript -e "$CHECK_SCRIPT" -e 'tell application "BBEdit"
    return (ID of front window as text) & linefeed & (startLine of selection as text) & linefeed & (contents of selection as text)
end tell' 2>"$CAPTURE_ERROR"); then
    MESSAGE="$(cat "$CAPTURE_ERROR")"
    MESSAGE="${MESSAGE#*execution error: }"
    MESSAGE="${MESSAGE% \(-*}"
    [[ "$MESSAGE" == "Save modified project inputs"* ]] ||
        MESSAGE="Could not read the selection in the front BBEdit window: $MESSAGE"
    alert "$MESSAGE"
    exit 1
fi
SOURCE_ID="${CAPTURE%%$'\n'*}"
SELECTION="${CAPTURE#*$'\n'}"
SOURCE_LINE="${SELECTION%%$'\n'*}"
SELECTION="${SELECTION#*$'\n'}"
[[ -n "${SELECTION//[[:space:]]/}" ]] || { alert "Select an equation or a complete math environment first."; exit 0; }
TOKEN=$("$BBTEX" snippet-begin "$BB_DOC_PATH" "$SOURCE_LINE" manual)
export BBTEX_PREVIEW_TOKEN="$TOKEN"
OUTPUT=$(printf '%s\n' "$SELECTION" | "$BBTEX" preview "$BB_DOC_PATH") && EXIT=0 || EXIT=$?
STATUS="" PNG="" LOG="" MESSAGE=""
while IFS= read -r line; do
    case "$line" in
        status:*) STATUS="${line#status: }" ;;
        png:*) PNG="${line#png: }" ;;
        log:*) LOG="${line#log: }" ;;
        message:*) MESSAGE="${line#message: }" ;;
    esac
done <<< "$OUTPUT"
if [[ $EXIT -eq 0 && "$STATUS" == "success" && -f "$PNG" ]]; then
    PAGE=$("$BBTEX" snippet-finish "$TOKEN" current "$PNG" "$LOG" "") || exit 0
    WINDOW_SCRIPT="$REAL_DIR/snippet-window.applescript"
    [[ -f "$WINDOW_SCRIPT" ]] || WINDOW_SCRIPT="$PARENT/Resources/snippet-window.applescript"
    osascript "$WINDOW_SCRIPT" "$PAGE" "$SOURCE_ID" "${PAGE##*/}" "$BB_DOC_PATH"
else
    DISPLAY_STATUS=error
    [[ "$MESSAGE" != *"already building"* ]] || DISPLAY_STATUS=busy
    [[ "$STATUS" != cancelled ]] || { DISPLAY_STATUS=stale; MESSAGE="Preview cancelled. Select an equation to retry."; }
    "$BBTEX" snippet-finish "$TOKEN" "$DISPLAY_STATUS" "" "$LOG" "${MESSAGE:-Could not create the preview.}" >/dev/null || exit 0
    [[ "$STATUS" != cancelled ]] || exit 0
    [[ ! -f "$LOG" ]] || bbedit "$LOG"
    alert "${MESSAGE:-Could not create the preview.}"
    exit 1
fi
