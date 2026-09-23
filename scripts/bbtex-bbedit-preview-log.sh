#!/bin/bash
set -euo pipefail
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
BBTEX="$PARENT/_build/default/bin/main.exe"
[[ ! -x "$PARENT/Resources/bbtex" ]] || BBTEX="$PARENT/Resources/bbtex"
if LOG=$("$BBTEX" snippet-log 2>&1); then
    PATH="/usr/local/bin:/opt/homebrew/bin:$PATH" bbedit "$LOG"
else
    osascript - "$LOG" <<'APPLESCRIPT'
on run argv
    tell application "BBEdit" to display alert "Preview log unavailable" message (item 1 of argv)
end run
APPLESCRIPT
fi
