#!/bin/bash
# Open or reuse the persistent outline for the front document's project.
set -Eeuo pipefail
trap 'echo "${0##*/}: failed at line $LINENO: $BASH_COMMAND" >&2' ERR
for tool in realpath osascript; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
REAL_SCRIPT="$(realpath "$0")"
REAL_DIR="$(dirname "$REAL_SCRIPT")"
PARENT="$(dirname "$REAL_DIR")"
BBTEX="$PARENT/_build/default/bin/main.exe"
[[ ! -x "$PARENT/Resources/bbtex" ]] || BBTEX="$PARENT/Resources/bbtex"
[[ -x "$BBTEX" ]] || { echo "bbtex executable not found: $BBTEX" >&2; exit 1; }
SOURCE="${BB_DOC_PATH:-${1:-}}"
[[ -n "$SOURCE" ]] || SOURCE=$(osascript -e 'tell application "BBEdit" to get POSIX path of (file of front text document)')
if ! MESSAGE=$("$BBTEX" outline-window "$SOURCE" 2>&1); then
    osascript - "$MESSAGE" <<'APPLESCRIPT'
on run argv
    tell application "BBEdit" to display alert "Project outline unavailable" message (item 1 of argv)
end run
APPLESCRIPT
    exit 1
fi
