#!/bin/bash
set -euo pipefail
# As with the build commands, keep BBEdit's shell-output window out of the
# interactive AppleScript dialog workflow.
STATE_DIR="${BBTEX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/bbtex}"
mkdir -p "$STATE_DIR"
exec >/dev/null 2>>"$STATE_DIR/outline.log"
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
BBTEX="$PARENT/_build/default/bin/main.exe"
HELPER="$REAL_DIR/project-outline.applescript"
if [[ -x "$PARENT/Resources/bbtex" ]]; then
    BBTEX="$PARENT/Resources/bbtex"
    HELPER="$PARENT/Resources/project-outline.applescript"
fi
SOURCE="${BB_DOC_PATH:-${1:-}}"
[[ -n "$SOURCE" ]] || SOURCE=$(osascript -e 'tell application "BBEdit"' -e 'set f to get file of front text document' -e 'return POSIX path of f' -e 'end tell')
exec osascript "$HELPER" "$BBTEX" "$SOURCE"
