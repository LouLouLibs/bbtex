#!/bin/bash
# Build and verify release preview resources; opt into disposable native UI tests.
set -euo pipefail
cd "$(dirname "$0")/../.."
bash scripts/package.sh
PKG="$PWD/dist/bbtex.bbpackage"
for resource in with-preview-lock.pl preview-save-hook.applescript snippet-window.applescript project-outline.applescript insert-picker.applescript citation-picker.py bbtex-bbedit-pick.sh install-preview-save-hook.py install-preview-service.py; do
    cmp "scripts/$resource" "$PKG/Contents/Resources/$resource"
    unzip -p dist/bbtex.bbpackage.zip "bbtex.bbpackage/Contents/Resources/$resource" | cmp - "scripts/$resource"
done
unzip -tq dist/bbtex.bbpackage.zip
uv run test/integration/check_package_archive.py
uv run "$PKG/Contents/Resources/install-preview-save-hook.py"
uv run "$PKG/Contents/Resources/install-preview-service.py"
BBTEX_TEST_WRAPPER="$PKG/Contents/Scripts/LaTeX — Compile.sh" uv run test/integration/check_build_workflow.py
uv run test/integration/check_save_preview_worker.py
BBTEX_TEST_BINARY="$PKG/Contents/Resources/bbtex" uv run test/integration/check_project_outline.py
BBTEX_TEST_BINARY="$PKG/Contents/Resources/bbtex" BBTEX_TEST_RESOURCES="$PKG/Contents/Resources" uv run test/integration/check_pickers.py
if [[ "${BBTEX_TEST_NATIVE:-0}" == 1 ]]; then
    osascript test/integration/check_editing.applescript "$PKG/Contents/Scripts/LaTeX Editing/Toggle Starred Environment.scpt" "$PKG/Contents/Resources"
    osascript test/integration/check_wrapping.applescript "$PKG/Contents/Resources" "$PKG/Contents/Clippings/Latex.tex"
    BBTEX_TEST_RESOURCES="$PKG/Contents/Resources" uv run test/integration/check_structure_dialogs.py
    BBTEX_TEST_PREVIEW_WRAPPER="$PKG/Contents/Scripts/LaTeX — Preview Selection.sh" uv run test/integration/check_live_preview.py
    uv run scripts/install-preview-service.py
    BBTEX_TEST_PREVIEW_SERVICE="$PWD/dist/LaTeX — Preview Selection.workflow" uv run test/integration/check_live_preview.py
fi
echo "Release preview checks passed."
