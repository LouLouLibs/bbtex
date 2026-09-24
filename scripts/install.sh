#!/bin/bash
# install.sh — Install bbtex into BBEdit.
#
# What this does:
#   1. Builds the bbtex binary (dune build)
#   2. Symlinks it to ~/.local/bin/bbtex
#   3. Symlinks the BBEdit wrapper scripts into BBEdit's Scripts folder
#
# After running this, you still need to:
#   - Set up keyboard shortcuts in BBEdit (see instructions printed below)
#   - Configure Skim for inverse search (see instructions printed below)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BBEDIT_SCRIPTS="$HOME/Library/Application Support/BBEdit/Scripts"
LOCAL_BIN="$HOME/.local/bin"

# ── Build ────────────────────────────────────────────────────

echo "Building bbtex..."
cd "$PROJECT_DIR"
dune build

if [[ ! -f "$PROJECT_DIR/_build/default/bin/main.exe" ]]; then
    echo "Error: build failed — _build/default/bin/main.exe not found" >&2
    exit 1
fi

echo "  Built: $PROJECT_DIR/_build/default/bin/main.exe"

# ── Install binary ───────────────────────────────────────────

mkdir -p "$LOCAL_BIN"

# Remove old symlink if it exists
if [[ -L "$LOCAL_BIN/bbtex" ]]; then
    rm "$LOCAL_BIN/bbtex"
fi

ln -s "$PROJECT_DIR/_build/default/bin/main.exe" "$LOCAL_BIN/bbtex"
echo "  Symlinked: $LOCAL_BIN/bbtex"

# Verify it works
if "$LOCAL_BIN/bbtex" --help >/dev/null 2>&1; then
    echo "  Verified: bbtex --help works"
else
    echo "  Warning: bbtex --help failed. Check your PATH includes $LOCAL_BIN" >&2
fi

# ── Create state directory ───────────────────────────────────

mkdir -p "$HOME/.local/state/bbtex"
echo "  Created: $HOME/.local/state/bbtex"

# ── Install BBEdit scripts ───────────────────────────────────

mkdir -p "$BBEDIT_SCRIPTS"

# Remove old symlinks if they exist
for name in "LaTeX — Compile.sh" "LaTeX — Compile With….sh" "LaTeX — Forward Search.sh" "LaTeX — Clean.sh" "LaTeX — Show Build Results.sh" "LaTeX — Open Build Log.sh" "LaTeX — Cancel Build.sh" "LaTeX — Clean All Build Output.sh"; do
    if [[ -L "$BBEDIT_SCRIPTS/$name" ]]; then
        rm "$BBEDIT_SCRIPTS/$name"
    fi
done

ln -s "$PROJECT_DIR/scripts/bbtex-bbedit-compile.sh" \
      "$BBEDIT_SCRIPTS/LaTeX — Compile.sh"
ln -s "$PROJECT_DIR/scripts/bbtex-bbedit-compile-with.sh" \
      "$BBEDIT_SCRIPTS/LaTeX — Compile With….sh"
ln -s "$PROJECT_DIR/scripts/bbtex-bbedit-forward.sh" \
      "$BBEDIT_SCRIPTS/LaTeX — Forward Search.sh"
ln -s "$PROJECT_DIR/scripts/bbtex-bbedit-clean.sh" \
      "$BBEDIT_SCRIPTS/LaTeX — Clean.sh"
ln -s "$PROJECT_DIR/scripts/bbtex-bbedit-results.sh" \
      "$BBEDIT_SCRIPTS/LaTeX — Show Build Results.sh"
ln -s "$PROJECT_DIR/scripts/bbtex-bbedit-log.sh" \
      "$BBEDIT_SCRIPTS/LaTeX — Open Build Log.sh"
ln -s "$PROJECT_DIR/scripts/bbtex-bbedit-cancel.sh" \
      "$BBEDIT_SCRIPTS/LaTeX — Cancel Build.sh"
ln -s "$PROJECT_DIR/scripts/bbtex-bbedit-clean-all.sh" \
      "$BBEDIT_SCRIPTS/LaTeX — Clean All Build Output.sh"

if [[ -L "$BBEDIT_SCRIPTS/LaTeX — Preview Selection.sh" ]]; then
    rm "$BBEDIT_SCRIPTS/LaTeX — Preview Selection.sh"
fi
ln -s "$PROJECT_DIR/scripts/bbtex-bbedit-preview.sh" \
      "$BBEDIT_SCRIPTS/LaTeX — Preview Selection.sh"
if [[ -L "$BBEDIT_SCRIPTS/LaTeX — Toggle Preview on Save.sh" ]]; then
    rm "$BBEDIT_SCRIPTS/LaTeX — Toggle Preview on Save.sh"
fi
ln -s "$PROJECT_DIR/scripts/bbtex-preview-on-save.sh" \
      "$BBEDIT_SCRIPTS/LaTeX — Toggle Preview on Save.sh"
if [[ -L "$BBEDIT_SCRIPTS/LaTeX — Toggle Live Selection Preview.sh" ]]; then
    rm "$BBEDIT_SCRIPTS/LaTeX — Toggle Live Selection Preview.sh"
fi
ln -s "$PROJECT_DIR/scripts/bbtex-live-selection.sh" \
      "$BBEDIT_SCRIPTS/LaTeX — Toggle Live Selection Preview.sh"
"$PROJECT_DIR/scripts/install-preview-save-hook.sh" --apply
"$PROJECT_DIR/scripts/install-workflow-commands.sh"

echo "  Symlinked: $BBEDIT_SCRIPTS/LaTeX — Compile.sh"
echo "  Symlinked: $BBEDIT_SCRIPTS/LaTeX — Forward Search.sh"
echo "  Symlinked: $BBEDIT_SCRIPTS/LaTeX — Clean.sh"

# Build editing support locally. Installation is explicit because it migrates
# the older Latex.bbpackage and requires BBEdit to be closed.
"$PROJECT_DIR/scripts/build-support.sh"
echo "  Editing assets built. Install with:"
echo "    scripts/install-support.sh --apply --restart"

# ── Done ─────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  bbtex installed successfully."
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Manual setup remaining:"
echo ""
echo "1. SET KEYBOARD SHORTCUTS IN BBEDIT"
echo "   BBEdit > Settings > Menus & Shortcuts"
echo "   Scroll to the Scripts section, find:"
echo "     • LaTeX — Compile     → assign Cmd+K"
echo "     • LaTeX — Compile With… → assign Shift+Cmd+K"
echo "     • LaTeX — Clean → remove its old Shift+Cmd+K shortcut"
echo "     • LaTeX — Forward Search → assign Shift+Cmd+J"
echo ""
echo "2. CONFIGURE SKIM FOR INVERSE SEARCH (PDF → source)"
echo "   Skim > Settings > Sync"
echo "     Preset: Custom"
echo "     Command: /usr/local/bin/bbedit"
echo "     Arguments: --line %line \"%file\""
echo ""
echo "3. TEST IT"
echo "   Open a .tex file in BBEdit, then:"
echo "     • Cmd+K to compile"
echo "     • Click errors in the results to jump to source"
echo "     • Shift+Cmd+J to jump from source to PDF in Skim"
echo "     • Cmd+click in Skim to jump back to source in BBEdit"
echo ""
echo "4. DEBUGGING"
echo "   If compilation fails unexpectedly, check the debug log:"
echo "     cat ~/.local/state/bbtex/last-compile.log"
echo "   Or run with verbose output:"
echo "     bbtex compile --verbose myfile.tex"
echo ""
