#!/bin/bash
set -euo pipefail
STATE_DIR="${BBTEX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/bbtex}"
mkdir -p "$STATE_DIR"
exec >/dev/null 2>>"$STATE_DIR/picker.log"
MODE="${1:-ref}"
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
BBTEX="$PARENT/_build/default/bin/main.exe"
RESOURCE_DIR="$REAL_DIR"
if [[ -x "$PARENT/Resources/bbtex" ]]; then
    BBTEX="$PARENT/Resources/bbtex"
    RESOURCE_DIR="$PARENT/Resources"
fi
exec osascript "$RESOURCE_DIR/insert-picker.applescript" "$BBTEX" "$MODE"
