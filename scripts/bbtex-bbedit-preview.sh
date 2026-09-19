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
PROJECT="" ROOT=""
while IFS= read -r line; do
    case "$line" in
        project:*) PROJECT="${line#project: }" ;;
        root:*) ROOT="${line#root: }" ;;
    esac
done <<< "$PROJECT_OUTPUT"
CAPTURE=$(osascript - "$PROJECT/" "$ROOT" "$BB_DOC_PATH" <<'APPLESCRIPT'
on run argv
    tell application "BBEdit"
        repeat with d in (get text documents)
            set p to ""
            try
                set f to get file of d
                set p to POSIX path of f
            end try
            if p is not "" and modified of d then
                if p starts with item 1 of argv or p is item 2 of argv or p is item 3 of argv then
                    error "Save modified project inputs before previewing. Preview does not save your work automatically."
                end if
            end if
        end repeat
        return (ID of front window as text) & linefeed & (contents of selection as text)
    end tell
end run
APPLESCRIPT
) || { alert "Save modified project inputs before previewing, then select the snippet again."; exit 1; }
SOURCE_ID="${CAPTURE%%$'\n'*}"
SELECTION="${CAPTURE#*$'\n'}"
[[ -n "${SELECTION//[[:space:]]/}" ]] || { alert "Select an equation or a complete math environment first."; exit 0; }
OUTPUT=$(printf '%s\n' "$SELECTION" | "$BBTEX" preview "$BB_DOC_PATH") && EXIT=0 || EXIT=$?
STATUS="" PDF="" PNG="" LOG="" MESSAGE=""
while IFS= read -r line; do
    case "$line" in
        status:*) STATUS="${line#status: }" ;;
        pdf:*) PDF="${line#pdf: }" ;;
        png:*) PNG="${line#png: }" ;;
        log:*) LOG="${line#log: }" ;;
        message:*) MESSAGE="${line#message: }" ;;
    esac
done <<< "$OUTPUT"
[[ "$STATUS" != "cancelled" ]] || exit 0
if [[ $EXIT -eq 0 && "$STATUS" == "success" && -f "$PNG" ]]; then
    PAGE=$("$BBTEX" snippet-page "$PNG")
    WINDOW_SCRIPT="$REAL_DIR/snippet-window.applescript"
    [[ -f "$WINDOW_SCRIPT" ]] || WINDOW_SCRIPT="$PARENT/Resources/snippet-window.applescript"
    osascript "$WINDOW_SCRIPT" "$PAGE" "$SOURCE_ID" "${PAGE##*/}" "$BB_DOC_PATH"
else
    "$BBTEX" snippet-page - >/dev/null
    [[ ! -f "$LOG" ]] || bbedit "$LOG"
    alert "${MESSAGE:-Could not create the preview.}"
    exit 1
fi
