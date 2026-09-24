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
STATE="${BBTEX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/bbtex}"
FALLBACK="Could not render the selection. See Open Preview Log."

# Second stage, run while holding preview-on-save.lock: render the captured
# fragment in WORK for request TOKEN.
if [[ "${1:-}" == "--locked" ]]; then
    SOURCE="$2" WORK="$3" TOKEN="$4"
    # Finishing is a no-op once a newer request owns the window; otherwise it
    # clears "Rendering..." (as stale, with its own wording if the source changed).
    cancelled() {
        "$BBTEX" snippet-finish "$TOKEN" stale "" "" "Preview cancelled. Select again to retry." >/dev/null || true
    }
    # While this render waited, a newer selection or a save may have replaced it.
    "$BBTEX" snippet-current "$TOKEN" || { cancelled; exit 0; }
    # A full build that is active wins; the watcher renders again once it ends.
    if "$BBTEX" live-selection build-active; then
        "$BBTEX" snippet-finish "$TOKEN" busy "" "" "Live preview paused while a full build runs." >/dev/null || true
        exit 0
    fi
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
    # A fallback message is only for failure statuses: an empty MESSAGE on a
    # successful render must stay empty, not be replaced by the error fallback.
    case "$RESULT" in
        0) if [[ -f "$PNG" ]]; then
               STATUS=current
               MESSAGE=""
           else
               STATUS=error
               MESSAGE="${MESSAGE:-$FALLBACK}"
           fi
           ;;
        3) # Superseded (then a no-op) or cancelled by a save or a build.
           cancelled
           exit 0
           ;;
        6) # Safety net: the whitespace check below should already have caught
           # this. Finish the snippet instead of leaving it stuck "Rendering...".
           "$BBTEX" snippet-finish "$TOKEN" stale "" "" "Select math or text to preview." >/dev/null || true
           exit 0
           ;;
        5) STATUS=stale
           MESSAGE="${MESSAGE:-$FALLBACK}"
           ;;
        *) STATUS=error
           [[ "$MESSAGE" != *"already building"* ]] || STATUS=busy
           MESSAGE="${MESSAGE:-$FALLBACK}"
           ;;
    esac
    "$BBTEX" snippet-finish "$TOKEN" "$STATUS" "$PNG" "$LOG" "$MESSAGE" >/dev/null || true
    exit 0
fi

SOURCE="$1" WINDOW_ID="$2" OFFSET="$3" LENGTH="$4" LINE="$5"
WORK=$(mktemp -d "$STATE/live.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
# A selection that moved since the poll belongs to a newer request.
osascript "$REAL_DIR/live-selection-capture.applescript" "$WINDOW_ID" "$OFFSET" "$LENGTH" "$WORK" 2>/dev/null || exit 0
# A whitespace-only selection has nothing to render; leave the previous
# preview as it was rather than start a render that preview-fragment will
# reject as empty (case 6 above), which would otherwise leave the window
# stuck on "Rendering...".
[[ -n "$(tr -d '[:space:]' < "$WORK/selected")" ]] || exit 0
# The watcher may have stopped between the poll and this run; a stale renderer
# then does nothing instead of failing loudly.
TOKEN=$("$BBTEX" snippet-begin "$SOURCE" "$LINE" live 2>/dev/null) || exit 0
# Queue on the lock save previews and full builds take (see
# bbtex-preview-on-save.sh and bbtex-bbedit-compile.sh): back-to-back renders
# then never race for the project build lock, and a build waits for a render
# instead of being refused.
/usr/bin/perl "$REAL_DIR/with-preview-lock.pl" "$STATE/preview-on-save.lock" \
    /bin/bash "$REAL_SCRIPT" --locked "$SOURCE" "$WORK" "$TOKEN" || {
    "$BBTEX" snippet-finish "$TOKEN" error "" "" "$FALLBACK" >/dev/null || true
}
