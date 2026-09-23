#!/bin/bash
# Install on-demand build commands into BBEdit's Scripts menu as symlinks to this
# checkout, without restarting BBEdit. Refuses to replace unrelated files.
set -Eeuo pipefail
trap 'echo "${0##*/}: failed at line $LINENO: $BASH_COMMAND" >&2' ERR

fail() { echo "${0##*/}: $*" >&2; exit 1; }
command -v realpath >/dev/null || fail "realpath not found (macOS 13 or later required)"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$HOME/Library/Application Support/BBEdit/Scripts"
COMMANDS=(
    "LaTeX — Show Build Results.sh|bbtex-bbedit-results.sh"
    "LaTeX — Doctor.sh|bbtex-bbedit-doctor.sh"
    "LaTeX — Project Outline.sh|bbtex-bbedit-outline.sh"
    "LaTeX — Insert Citation.sh|bbtex-bbedit-citation.sh"
    "LaTeX — Insert Reference.sh|bbtex-bbedit-reference.sh"
    "LaTeX — Open Build Log.sh|bbtex-bbedit-log.sh"
    "LaTeX — Cancel Build.sh|bbtex-bbedit-cancel.sh"
    "LaTeX — Clean All Build Output.sh|bbtex-bbedit-clean-all.sh"
    "LaTeX — Preview Selection.sh|bbtex-bbedit-preview.sh"
    "LaTeX — Open Preview Log.sh|bbtex-bbedit-preview-log.sh"
    "LaTeX — Toggle Preview on Save.sh|bbtex-preview-on-save.sh"
)

# Check every target before changing anything.
for command in "${COMMANDS[@]}"; do
    target="$SCRIPTS/${command%%|*}"
    expected="$ROOT/scripts/${command#*|}"
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ -L "$target" && "$(realpath "$target" 2>/dev/null || true)" == "$(realpath "$expected")" ]]; then
            continue
        fi
        fail "Refusing to overwrite an unrelated file: $target"
    fi
done

mkdir -p "$SCRIPTS"
for command in "${COMMANDS[@]}"; do
    name="${command%%|*}"
    target="$SCRIPTS/$name"
    [[ -L "$target" ]] || ln -s "$ROOT/scripts/${command#*|}" "$target"
    [[ -f "$target" ]] || fail "Not a working link: $target"
    echo "Installed: $name"
done
