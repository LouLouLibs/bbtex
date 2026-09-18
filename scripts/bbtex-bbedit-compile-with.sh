#!/bin/bash
# Native engine picker, sharing the normal compilation workflow.
set -euo pipefail
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
if [[ -f "$REAL_DIR/bbtex-bbedit-compile.sh" ]]; then
    exec /bin/bash "$REAL_DIR/bbtex-bbedit-compile.sh" --choose-engine
else
    exec /bin/bash "$REAL_DIR/LaTeX — Compile.sh" --choose-engine
fi
