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
# A package downloaded with a browser keeps macOS's quarantine flag, and
# Gatekeeper then kills the unsigned bbtex binary before it can say why. This
# script is plain bash, so it can still explain the fix.
if /usr/bin/xattr -p com.apple.quarantine "$BBTEX" >/dev/null 2>&1; then
    PACKAGE="$(dirname "$PARENT")"
    cat <<EOF
[bbtex] macOS has quarantined the bbtex program, so every LaTeX command fails.

This happens when the package is downloaded with a web browser: bbtex is not
signed with an Apple Developer ID, so Gatekeeper blocks it ("Apple could not
verify bbtex is free of malware").

To allow it, quit BBEdit, then run this in Terminal:

    xattr -dr com.apple.quarantine "$PACKAGE"

Reopen BBEdit and run LaTeX — Doctor again.
EOF
    exit 1
fi
# BBEdit displays this report in its shell output window. Tool version queries
# may initialize their own caches; no document or saved report is required.
SOURCE="${BB_DOC_PATH:-${1:-}}"
if [[ -n "$SOURCE" && -f "$SOURCE" ]]; then
    exec "$BBTEX" doctor --probe "$SOURCE"
fi
exec "$BBTEX" doctor --probe
