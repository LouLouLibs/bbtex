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
# BBEdit displays this report in its shell output window. No saved report or
# persistent state is created, and no document is required.
SOURCE="${BB_DOC_PATH:-${1:-}}"
if [[ -n "$SOURCE" && -f "$SOURCE" ]]; then
    exec "$BBTEX" doctor "$SOURCE"
fi
exec "$BBTEX" doctor
