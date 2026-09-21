#!/bin/bash
set -euo pipefail
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
WORKER="$REAL_DIR/bbtex-bbedit-pick.sh"
[[ -f "$WORKER" ]] || WORKER="$(dirname "$REAL_DIR")/Resources/bbtex-bbedit-pick.sh"
exec /bin/bash "$WORKER" cite
