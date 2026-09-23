#!/bin/bash
set -euo pipefail
export PATH="/Library/TeX/texbin:/opt/homebrew/bin:/usr/local/bin:$PATH"
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
BBTEX="$PARENT/_build/default/bin/main.exe"
if [[ -x "$PARENT/Resources/bbtex" ]]; then
    BBTEX="$PARENT/Resources/bbtex"
fi
# BBEdit displays this report in its shell output window. Tool version queries
# may initialize their own caches; no document or saved report is required.
SOURCE="${BB_DOC_PATH:-${1:-}}"
if [[ -n "$SOURCE" && -f "$SOURCE" ]]; then
    exec "$BBTEX" doctor --probe "$SOURCE"
fi
exec "$BBTEX" doctor --probe
