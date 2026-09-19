#!/bin/bash
set -euo pipefail
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
BBTEX="$PARENT/_build/default/bin/main.exe"
[[ ! -x "$PARENT/Resources/bbtex" ]] || BBTEX="$PARENT/Resources/bbtex"
export PATH="/Library/TeX/texbin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export BBTEX_STATE_DIR="${BBTEX_STATE_DIR:-$HOME/.local/state/bbtex}"
mkdir -p "$BBTEX_STATE_DIR"
FLAG="$BBTEX_STATE_DIR/preview-on-save-source"
SOURCE="${2:-${BB_DOC_PATH:-}}"
[[ -n "$SOURCE" ]] || exit 0
if [[ "${1:-}" != "--saved" && "${1:-}" != "--locked" ]]; then
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
[[ -f "$FLAG" && "$(cat "$FLAG")" == "$SOURCE" ]] || exit 0
LINE="${3:-1}"
SOURCE_ID="${4:-0}"
REQUEST="$BBTEX_STATE_DIR/preview-on-save-request"
if [[ "${1:-}" == "--saved" ]]; then
    TEMP=$(mktemp "$BBTEX_STATE_DIR/request.XXXXXX")
    TOKEN="${TEMP##*/}"
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
       -f "$REQUEST" && "$(cat "$REQUEST")" == "$TOKEN" ]] &&
        ! kill -0 "$(cat "$BBTEX_STATE_DIR/suppress-save-preview" 2>/dev/null)" 2>/dev/null
}
# Every save queues a contender; only the newest renders. A save during
# publication/exit still has its own contender, so no wakeup can be lost.
if current; then
    BEFORE="$(cksum "$SOURCE")"
    SELECTION=$("$BBTEX" equation-at "$SOURCE" "$LINE") || exit 0
    OUTPUT=$(printf '%s\n' "$SELECTION" | "$BBTEX" preview "$SOURCE") && RESULT=0 || RESULT=$?
    [[ "$BEFORE" == "$(cksum "$SOURCE")" ]] && current || exit 0
    PNG=""
    while IFS= read -r line; do
        [[ "$line" != png:* ]] || PNG="${line#png: }"
    done <<< "$OUTPUT"
    if [[ $RESULT -eq 0 && -f "$PNG" ]]; then
        PAGE=$("$BBTEX" snippet-page "$PNG")
        WINDOW_SCRIPT="$REAL_DIR/snippet-window.applescript"
        [[ -f "$WINDOW_SCRIPT" ]] || WINDOW_SCRIPT="$PARENT/Resources/snippet-window.applescript"
        osascript "$WINDOW_SCRIPT" "$PAGE" "$SOURCE_ID" "${PAGE##*/}" "$SOURCE"
    else
        printf '%s\n' "$OUTPUT" >&2
        "$BBTEX" snippet-page - >/dev/null
    fi
    exit 0
fi
