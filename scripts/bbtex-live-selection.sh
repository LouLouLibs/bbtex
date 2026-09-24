#!/bin/bash
# Toggle live selection preview: the preview window follows the BBEdit selection.
set -Eeuo pipefail
trap 'echo "bbtex-live-selection.sh: line $LINENO failed" >&2' ERR
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
BBTEX="$PARENT/_build/default/bin/main.exe"
RESOURCES="$REAL_DIR"
if [[ -x "$PARENT/Resources/bbtex" ]]; then
    BBTEX="$PARENT/Resources/bbtex"
    RESOURCES="$PARENT/Resources"
fi
export BBTEX_STATE_DIR="${BBTEX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/bbtex}"
mkdir -p "$BBTEX_STATE_DIR"
notify() { osascript -e "display notification \"$1\" with title \"LaTeX\""; }
if "$BBTEX" live-selection status; then
    "$BBTEX" live-selection stop
    notify "Live selection preview off"
    exit 0
fi
[[ -n "${BB_DOC_PATH:-}" ]] || { notify "Open a saved TeX document first."; exit 1; }
# Save tracking and live selection are exclusive.
rm -f "$BBTEX_STATE_DIR/preview-on-save-source" "$BBTEX_STATE_DIR/preview-on-save-request"
"$BBTEX" snippet-stop - "Live selection preview replaced preview on save."
nohup "$BBTEX" live-selection watch "$RESOURCES/live-selection-poll.applescript" \
    "$RESOURCES/bbtex-live-render.sh" </dev/null >>"$BBTEX_STATE_DIR/live-selection.log" 2>&1 &
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    "$BBTEX" live-selection status && break
    sleep 0.1
done
SOURCE_ID=$(osascript -e 'tell application "BBEdit" to return ID of front window as text')
TOKEN=$("$BBTEX" snippet-begin "$BB_DOC_PATH" 0 live)
PAGE=$("$BBTEX" snippet-finish "$TOKEN" stale "" "" "Live selection on. Select math or text to preview.") || exit 0
osascript "$RESOURCES/snippet-window.applescript" "$PAGE" "$SOURCE_ID" "${PAGE##*/}" "$BB_DOC_PATH"
notify "Live selection preview on"
