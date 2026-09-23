#!/bin/bash
set -euo pipefail
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
BBTEX="$PARENT/_build/default/bin/main.exe"
[[ ! -x "$PARENT/Resources/bbtex" ]] || BBTEX="$PARENT/Resources/bbtex"
export PATH="/Library/TeX/texbin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export BBTEX_STATE_DIR="${BBTEX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/bbtex}"
mkdir -p "$BBTEX_STATE_DIR"
FLAG="$BBTEX_STATE_DIR/preview-on-save-source"
SOURCE="${2:-${BB_DOC_PATH:-}}"
[[ -n "$SOURCE" ]] || exit 0
if [[ "${1:-}" != "--saved" && "${1:-}" != "--locked" ]]; then
    "$BBTEX" snippet-stop - "Preview tracking changed. Save an equation to refresh."
    rm -f "$BBTEX_STATE_DIR/preview-on-save-request"
    if [[ -f "$FLAG" && "$(cat "$FLAG")" == "$SOURCE" ]]; then
        rm "$FLAG"
        osascript -e 'display notification "Preview on save disabled" with title "LaTeX"'
        exit 0
    fi
    TEMP=$(mktemp "$BBTEX_STATE_DIR/tracking.XXXXXX")
    printf '%s' "$SOURCE" > "$TEMP"
    mv "$TEMP" "$FLAG"
    osascript -e 'display notification "Enabled for this file. Save with the cursor inside an equation to refresh its preview." with title "LaTeX"'
    exit 0
fi
[[ -f "$FLAG" ]] || exit 0
LINE="${3:-1}"
SOURCE_ID="${4:-0}"
REQUEST="$BBTEX_STATE_DIR/preview-on-save-request"
if [[ "${1:-}" == "--saved" ]]; then
    TRACKED=$(cat "$FLAG")
    if [[ "$SOURCE" != "$TRACKED" || "$LINE" == 0 ]]; then
        ROUTE=$("$BBTEX" snippet-refresh "$SOURCE") || exit 0
        TOKEN="${ROUTE%%$'\n'*}"
        ROUTE="${ROUTE#*$'\n'}"
        LINE="${ROUTE%%$'\n'*}"
        SOURCE="${ROUTE#*$'\n'}"
        SOURCE_ID=0
    else
        TOKEN=$("$BBTEX" snippet-begin "$SOURCE" "$LINE" auto)
    fi
    TEMP=$(mktemp "$BBTEX_STATE_DIR/request.XXXXXX")
    printf '%s' "$TOKEN" > "$TEMP"
    mv "$TEMP" "$REQUEST"
    LOCK_SCRIPT="$REAL_DIR/with-preview-lock.pl"
    [[ -f "$LOCK_SCRIPT" ]] || LOCK_SCRIPT="$PARENT/Resources/with-preview-lock.pl"
    exec /usr/bin/perl "$LOCK_SCRIPT" "$BBTEX_STATE_DIR/preview-on-save.lock" \
        /bin/bash "$REAL_SCRIPT" --locked "$SOURCE" "$LINE" "$SOURCE_ID" "$TOKEN"
fi
TOKEN="$5"
current() {
    [[ -f "$FLAG" && "$(cat "$FLAG")" == "$SOURCE" &&
       -n "$TOKEN" ]] &&
        ! kill -0 "$(cat "$BBTEX_STATE_DIR/suppress-save-preview" 2>/dev/null)" 2>/dev/null &&
        "$BBTEX" snippet-current "$TOKEN"
}
# Every save queues a contender; only the newest renders. A save during
# publication/exit still has its own contender, so no wakeup can be lost.
if current; then
    SELECTION=$("$BBTEX" equation-at "$SOURCE" "$LINE" 2>&1) || {
        "$BBTEX" snippet-finish "$TOKEN" stale "" "" "$SELECTION" >/dev/null || true
        exit 0
    }
    export BBTEX_PREVIEW_TOKEN="$TOKEN"
    OUTPUT=$(printf '%s\n' "$SELECTION" | "$BBTEX" preview "$SOURCE") && RESULT=0 || RESULT=$?
    PNG="" LOG="" MESSAGE=""
    while IFS= read -r line; do
        case "$line" in
            png:*) PNG="${line#png: }" ;;
            log:*) LOG="${line#log: }" ;;
            message:*) MESSAGE="${line#message: }" ;;
        esac
    done <<< "$OUTPUT"
    if [[ $RESULT -eq 0 && -f "$PNG" ]]; then
        STATUS=current
        MESSAGE=""
    else
        printf '%s\n' "$OUTPUT" >&2
        STATUS=error
        [[ "$MESSAGE" != *"already building"* ]] || STATUS=busy
        [[ $RESULT -ne 3 ]] || { STATUS=stale; MESSAGE="Preview cancelled. Save an equation to retry."; }
        MESSAGE="${MESSAGE:-Could not render the equation. See the preview log.}"
    fi
    PAGE=$("$BBTEX" snippet-finish "$TOKEN" "$STATUS" "$PNG" "$LOG" "$MESSAGE") || exit 0
    WINDOW_SCRIPT="$REAL_DIR/snippet-window.applescript"
    [[ -f "$WINDOW_SCRIPT" ]] || WINDOW_SCRIPT="$PARENT/Resources/snippet-window.applescript"
    osascript "$WINDOW_SCRIPT" "$PAGE" "$SOURCE_ID" "${PAGE##*/}" "$SOURCE"
    exit 0
else
    "$BBTEX" snippet-finish "$TOKEN" busy "" "" "Automatic preview paused while a full build is active. Save again to refresh." >/dev/null || true
fi
