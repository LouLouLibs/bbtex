#!/bin/bash
# Build and verify release preview resources; opt into disposable native UI tests.
set -euo pipefail
cd "$(dirname "$0")/../.."
bash scripts/package.sh
PKG="$PWD/dist/bbtex.bbpackage"
for resource in with-preview-lock.pl preview-save-hook.applescript snippet-window.applescript project-outline.applescript insert-picker.applescript bbtex-bbedit-pick.sh install-preview-save-hook.sh; do
    cmp "scripts/$resource" "$PKG/Contents/Resources/$resource"
    unzip -p dist/bbtex.bbpackage.zip "bbtex.bbpackage/Contents/Resources/$resource" | cmp - "scripts/$resource"
done
unzip -tq dist/bbtex.bbpackage.zip
# The archive keeps the license, executable bits and stationery flags.
ARCHIVE="$(mktemp -d)"
ditto -x -k dist/bbtex.bbpackage.zip "$ARCHIVE"
CONTENTS="$ARCHIVE/bbtex.bbpackage/Contents"
cmp LICENSE "$ARCHIVE/bbtex.bbpackage/LICENSE"
test -x "$CONTENTS/Resources/bbtex"
for script in "$CONTENTS"/Scripts/*.sh; do test -x "$script"; done
templates=0
for template in "$CONTENTS"/Stationery/*.tex; do
    info="$(xattr -px com.apple.FinderInfo "$template" | tr -d ' \n')"
    (( 16#${info:16:2} & 0x08 )) || { echo "Stationery flag missing: $template" >&2; exit 1; }
    templates=$((templates + 1))
done
(( templates > 0 ))
rm -rf "$ARCHIVE"
echo "Release archive preserves the license, executable bits and stationery flags"
BBTEX_TEST_BINARY="$PKG/Contents/Resources/bbtex" uv run test/integration/check_doctor.py
"$PKG/Contents/Scripts/LaTeX — Doctor.sh" | grep -q 'bbtex doctor'
bash "$PKG/Contents/Resources/install-preview-save-hook.sh"
SERVICE_BUILD="$(mktemp -d)"
"$PKG/Contents/Resources/bbtex" preview-service build "$SERVICE_BUILD"
plutil -lint "$SERVICE_BUILD/LaTeX — Preview Selection.workflow/Contents/"*
rm -rf "$SERVICE_BUILD"
BBTEX_TEST_WRAPPER="$PKG/Contents/Scripts/LaTeX — Compile.sh" uv run test/integration/check_build_workflow.py
uv run test/integration/check_save_preview_worker.py
BBTEX_TEST_BINARY="$PKG/Contents/Resources/bbtex" uv run test/integration/check_project_outline.py
BBTEX_TEST_BINARY="$PKG/Contents/Resources/bbtex" BBTEX_TEST_RESOURCES="$PKG/Contents/Resources" uv run test/integration/check_pickers.py
if [[ "${BBTEX_TEST_NATIVE:-0}" == 1 ]]; then
    osascript test/integration/check_editing.applescript "$PKG/Contents/Scripts/LaTeX Editing/Toggle Starred Environment.scpt" "$PKG/Contents/Resources"
    osascript test/integration/check_wrapping.applescript "$PKG/Contents/Resources" "$PKG/Contents/Clippings/Latex.tex"
    BBTEX_TEST_RESOURCES="$PKG/Contents/Resources" uv run test/integration/check_structure_dialogs.py
    BBTEX_TEST_PREVIEW_WRAPPER="$PKG/Contents/Scripts/LaTeX — Preview Selection.sh" uv run test/integration/check_live_preview.py
    _build/default/bin/main.exe preview-service build dist
    BBTEX_TEST_PREVIEW_SERVICE="$PWD/dist/LaTeX — Preview Selection.workflow" uv run test/integration/check_live_preview.py
fi
echo "Release preview checks passed."
