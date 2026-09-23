#!/bin/bash
# Install the built editing support (dist/bbtex-support.bbpackage) into BBEdit's
# Packages folder for development. The previous copy goes to BBEdit's Backups.
#   install-support.sh [--apply] [--restart]
#     (no options)  show what would change
#     --apply       install; BBEdit must be closed, or use --restart
#     --restart     quit BBEdit normally first and reopen it afterwards
# Release users don't need this: bbtex.bbpackage already contains these assets.
set -Eeuo pipefail
trap 'echo "${0##*/}: failed at line $LINENO: $BASH_COMMAND" >&2' ERR

fail() { echo "${0##*/}: $*" >&2; exit 1; }
for tool in ditto pgrep osascript; do
    command -v "$tool" >/dev/null || fail "$tool not found"
done
APPLY=false RESTART=false
for option in "$@"; do
    case "$option" in
        --apply) APPLY=true ;;
        --restart) RESTART=true ;;
        *) fail "usage: ${0##*/} [--apply] [--restart]" ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/dist/bbtex-support.bbpackage"
SUPPORT="$HOME/Library/Application Support/BBEdit"
DESTINATION="$SUPPORT/Packages/bbtex-support.bbpackage"
LEGACY="$SUPPORT/Packages/Latex.bbpackage"
SERVER_LINK="$SUPPORT/Language Servers/texlab"
TEXLAB="$(command -v texlab || true)"

[[ -f "$SOURCE/Contents/Resources/environments-lib.scpt" &&
   -f "$SOURCE/Contents/Scripts/LaTeX Editing/Package Documentation.scpt" ]] ||
    fail "Build support first: scripts/build-support.sh"
# Migrating the retired Latex.bbpackage (archiving it and carrying over its
# shortcuts) was removed after it ran; see git history of install-support.py.
[[ ! -e "$LEGACY" ]] ||
    fail "Found the retired $LEGACY. Migrate it with the old scripts/install-support.py (git log -- scripts/install-support.py)."

echo "Install $SOURCE → $DESTINATION"
echo "TexLab: ${TEXLAB:-not installed}"
if ! $APPLY; then
    echo "Preview only. Use --apply (and --restart if BBEdit is open) to install."
    exit 0
fi

bbedit_running() { pgrep -x BBEdit >/dev/null; }
if $RESTART && bbedit_running; then
    osascript -e 'tell application "BBEdit" to quit'
fi
# Allow a normal quit to finish; never force quit.
for _ in {1..40}; do
    bbedit_running || break
    sleep 0.25
done
if bbedit_running; then
    fail "Quit BBEdit before installing; no files changed."
fi
if $RESTART; then
    trap 'open -a BBEdit' EXIT
fi

BACKUP="$SUPPORT/Backups/bbtex-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$BACKUP"
# ditto keeps Finder metadata, such as the stationery flags.
ditto "$SOURCE" "$BACKUP/new-support.bbpackage"

moved=false published=false linked=false
rollback() {
    trap - ERR
    echo "${0##*/}: install failed; restoring the previous state" >&2
    if $published && [[ -e "$DESTINATION" ]]; then
        /bin/mv "$DESTINATION" "$BACKUP/failed-install.bbpackage"
    fi
    if $moved; then /bin/mv "$BACKUP/${DESTINATION##*/}" "$DESTINATION"; fi
    if $linked; then /bin/rm -f "$SERVER_LINK"; fi
}
trap rollback ERR
if [[ -e "$DESTINATION" ]]; then
    /bin/mv "$DESTINATION" "$BACKUP/"
    moved=true
fi
/bin/mv "$BACKUP/new-support.bbpackage" "$DESTINATION"
published=true
if [[ -n "$TEXLAB" && ! -e "$SERVER_LINK" && ! -L "$SERVER_LINK" ]]; then
    mkdir -p "$(dirname "$SERVER_LINK")"
    ln -s "$TEXLAB" "$SERVER_LINK"
    linked=true
fi
[[ -f "$DESTINATION/Contents/Resources/environments-lib.scpt" ]]
trap - ERR
echo "Installed. Backup: $BACKUP"
