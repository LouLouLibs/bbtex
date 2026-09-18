#!/bin/bash
# Project clean-all command, sharing the normal compilation workflow.
set -euo pipefail
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
if [[ -f "$REAL_DIR/bbtex-bbedit-compile.sh" ]]; then
    exec /bin/bash "$REAL_DIR/bbtex-bbedit-compile.sh" --clean-all
else
    exec /bin/bash "$REAL_DIR/LaTeX — Compile.sh" --clean-all
fi
