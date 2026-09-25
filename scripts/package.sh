#!/bin/bash
# package.sh — Build a distributable bbtex.bbpackage for BBEdit.
#
# Usage: ./scripts/package.sh [--arch arm64|x86_64]
#
# Produces: dist/bbtex.bbpackage/  (ready to install)
#           dist/bbtex.bbpackage.zip (for GitHub releases)

set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"

# ── Parse args ──────────────────────────────────────────────
ARCH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Build ───────────────────────────────────────────────────
echo "Building bbtex..."
dune build

BINARY="$PROJECT_ROOT/_build/default/bin/main.exe"
[[ -x "$BINARY" ]] || { echo "Build failed: $BINARY not found"; exit 1; }

BUILT_ARCH="$(file "$BINARY" | grep -o 'arm64\|x86_64')"
if [[ -n "$ARCH" && "$BUILT_ARCH" != "$ARCH" ]]; then
    echo "Warning: binary is $BUILT_ARCH but --arch $ARCH was requested"
    echo "Cross-compilation requires the matching OCaml toolchain"
    exit 1
fi

# ── Assemble package ───────────────────────────────────────
PKG="$PROJECT_ROOT/dist/bbtex.bbpackage"
rm -rf "$PKG"
mkdir -p "$PKG/Contents/Resources"
mkdir -p "$PKG/Contents/Scripts"
cp "$PROJECT_ROOT/LICENSE" "$PKG/LICENSE"

# Binary
cp "$BINARY" "$PKG/Contents/Resources/bbtex"
cp "$PROJECT_ROOT/scripts/configure-document.applescript" "$PKG/Contents/Resources/configure-document.applescript"
cp "$PROJECT_ROOT/scripts/project-outline.applescript" "$PKG/Contents/Resources/project-outline.applescript"
cp "$PROJECT_ROOT/scripts/insert-picker.applescript" "$PKG/Contents/Resources/insert-picker.applescript"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-pick.sh" "$PKG/Contents/Resources/bbtex-bbedit-pick.sh"
cp "$PROJECT_ROOT/scripts/snippet-window.applescript" "$PKG/Contents/Resources/snippet-window.applescript"
cp "$PROJECT_ROOT/scripts/bbtex-live-selection.sh" "$PKG/Contents/Scripts/LaTeX — Toggle Live Selection Preview.sh"
cp "$PROJECT_ROOT/scripts/bbtex-live-render.sh" "$PKG/Contents/Resources/bbtex-live-render.sh"
cp "$PROJECT_ROOT/scripts/live-selection-poll.applescript" "$PKG/Contents/Resources/"
cp "$PROJECT_ROOT/scripts/live-selection-capture.applescript" "$PKG/Contents/Resources/"
cp "$PROJECT_ROOT/scripts/preview-save-hook.applescript" "$PKG/Contents/Resources/preview-save-hook.applescript"
cp "$PROJECT_ROOT/scripts/with-preview-lock.pl" "$PKG/Contents/Resources/with-preview-lock.pl"
cp "$PROJECT_ROOT/scripts/install-preview-save-hook.sh" "$PKG/Contents/Resources/install-preview-save-hook.sh"
cp "$PROJECT_ROOT/docs/selection-preview.md" "$PKG/Contents/Resources/selection-preview.md"
cp "$PROJECT_ROOT/docs/project-navigation.md" "$PKG/Contents/Resources/project-navigation.md"
cp "$PROJECT_ROOT/docs/setup-troubleshooting.md" "$PKG/Contents/Resources/setup-troubleshooting.md"
cp "$PROJECT_ROOT/docs/dev/releases.md" "$PKG/Contents/Resources/releases.md"
cp "$PROJECT_ROOT/docs/release-notes.md" "$PKG/Contents/Resources/release-notes.md"
cp "$PROJECT_ROOT/docs/citation-reference-pickers.md" "$PKG/Contents/Resources/citation-reference-pickers.md"
chmod +x "$PKG/Contents/Resources/bbtex"

# Scripts — copy with BBEdit menu names
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-outline.sh" "$PKG/Contents/Scripts/LaTeX — Project Outline.sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-outline-window.sh" "$PKG/Contents/Scripts/LaTeX — Project Outline Window.sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-doctor.sh" "$PKG/Contents/Scripts/LaTeX — Doctor.sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-citation.sh" "$PKG/Contents/Scripts/LaTeX — Insert Citation.sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-reference.sh" "$PKG/Contents/Scripts/LaTeX — Insert Reference.sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-compile-with.sh" "$PKG/Contents/Scripts/LaTeX — Compile With….sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-compile.sh" "$PKG/Contents/Scripts/LaTeX — Compile.sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-forward.sh" "$PKG/Contents/Scripts/LaTeX — Forward Search.sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-clean.sh"   "$PKG/Contents/Scripts/LaTeX — Clean.sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-results.sh" "$PKG/Contents/Scripts/LaTeX — Show Build Results.sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-log.sh" "$PKG/Contents/Scripts/LaTeX — Open Build Log.sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-cancel.sh" "$PKG/Contents/Scripts/LaTeX — Cancel Build.sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-preview.sh" "$PKG/Contents/Scripts/LaTeX — Preview Selection.sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-preview-log.sh" "$PKG/Contents/Scripts/LaTeX — Open Preview Log.sh"
cp "$PROJECT_ROOT/scripts/bbtex-preview-on-save.sh" "$PKG/Contents/Scripts/LaTeX — Toggle Preview on Save.sh"
cp "$PROJECT_ROOT/scripts/bbtex-bbedit-clean-all.sh" "$PKG/Contents/Scripts/LaTeX — Clean All Build Output.sh"
chmod +x "$PKG/Contents/Scripts/"*.sh

# Editing helpers and clippings share the main package in release builds.
"$PROJECT_ROOT/scripts/build-support.sh" "$PKG"

echo "Package assembled: $PKG"
echo "  Binary: $BUILT_ARCH"
echo "  Contents:"
find "$PKG" -type f | sort | while read -r f; do
    echo "    ${f#"$PKG"/}"
done

# ── Zip for distribution ──────────────────────────────────
# Keep executable permissions and Finder's stationery flags, and nothing else.
# Every file also carries Dropbox and macOS provenance attributes (provenance
# cannot be removed), which would put an AppleDouble entry for each file in
# the archive's __MACOSX folder. So archive the package without extended
# attributes, then add back only the stationery templates' metadata.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ZIP="$PROJECT_ROOT/dist/bbtex.bbpackage-new.zip"
rm -f "$ZIP"
ditto -c -k --noextattr --noacl --keepParent "$PKG" "$ZIP"
mkdir -p "$STAGE/meta/bbtex.bbpackage/Contents/Stationery"
for template in "$PKG/Contents/Stationery/"*.tex; do
    [[ -e "$template" ]] || continue
    ditto "$template" "$STAGE/meta/bbtex.bbpackage/Contents/Stationery/${template##*/}"
done
ditto -c -k --sequesterRsrc --keepParent "$STAGE/meta/bbtex.bbpackage" "$STAGE/meta.zip"
/usr/bin/unzip -q "$STAGE/meta.zip" '__MACOSX/bbtex.bbpackage/Contents/Stationery/*' -d "$STAGE/rsrc"
(cd "$STAGE/rsrc" && /usr/bin/zip -q -r -X "$ZIP" __MACOSX)
mv "$ZIP" "$PROJECT_ROOT/dist/bbtex.bbpackage.zip"
echo "Zip created: dist/bbtex.bbpackage.zip"
