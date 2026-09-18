#!/bin/bash
# Project cancel command, sharing the normal compilation workflow.
set -euo pipefail
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
if [[ -f "$REAL_DIR/bbtex-bbedit-compile.sh" ]]; then
    exec /bin/bash "$REAL_DIR/bbtex-bbedit-compile.sh" --cancel
else
    exec /bin/bash "$REAL_DIR/LaTeX — Compile.sh" --cancel
fi
