#!/bin/bash
# Render one settled live selection. Started by `bbtex live-selection watch`.
set -Eeuo pipefail
trap 'echo "bbtex-live-render.sh: line $LINENO failed" >&2' ERR
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
BBTEX="$PARENT/_build/default/bin/main.exe"
[[ ! -x "$REAL_DIR/bbtex" ]] || BBTEX="$REAL_DIR/bbtex"
export PATH="/Library/TeX/texbin:/opt/homebrew/bin:/usr/local/bin:$PATH"
SOURCE="$1" WINDOW_ID="$2" OFFSET="$3" LENGTH="$4" LINE="$5"
STATE="${BBTEX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/bbtex}"
WORK=$(mktemp -d "$STATE/live.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
# A selection that moved since the poll belongs to a newer request.
osascript "$REAL_DIR/live-selection-capture.applescript" "$WINDOW_ID" "$OFFSET" "$LENGTH" "$WORK" 2>/dev/null || exit 0
# The watcher may have stopped between the poll and this run; a stale renderer
# then does nothing instead of failing loudly.
TOKEN=$("$BBTEX" snippet-begin "$SOURCE" "$LINE" live 2>/dev/null) || exit 0
export BBTEX_PREVIEW_TOKEN="$TOKEN"
OUTPUT=$("$BBTEX" preview-fragment "$SOURCE" "$WORK") && RESULT=0 || RESULT=$?
PNG="" LOG="" MESSAGE=""
while IFS= read -r line; do
    case "$line" in
        png:*) PNG="${line#png: }" ;;
        log:*) LOG="${line#log: }" ;;
        message:*) MESSAGE="${line#message: }" ;;
    esac
done <<< "$OUTPUT"
case "$RESULT" in
    0) if [[ -f "$PNG" ]]; then
           STATUS=current
           MESSAGE=""
       else
           STATUS=error
       fi
       ;;
    3|6) exit 0 ;;
    5) STATUS=stale ;;
    *) STATUS=error
       [[ "$MESSAGE" != *"already building"* ]] || STATUS=busy ;;
esac
"$BBTEX" snippet-finish "$TOKEN" "$STATUS" "$PNG" "$LOG" \
    "${MESSAGE:-Could not render the selection. See Open Preview Log.}" >/dev/null || true
