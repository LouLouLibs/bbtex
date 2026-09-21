#!/bin/bash
# Build and verify release preview resources; opt into disposable native UI tests.
set -euo pipefail
cd "$(dirname "$0")/../.."
bash scripts/package.sh
PKG="$PWD/dist/bbtex.bbpackage"
for resource in with-preview-lock.pl preview-save-hook.applescript snippet-window.applescript project-outline.applescript install-preview-save-hook.py install-preview-service.py; do
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
if [[ "${BBTEX_TEST_NATIVE:-0}" == 1 ]]; then
    BBTEX_TEST_PREVIEW_WRAPPER="$PKG/Contents/Scripts/LaTeX — Preview Selection.sh" uv run test/integration/check_live_preview.py
    uv run scripts/install-preview-service.py
    BBTEX_TEST_PREVIEW_SERVICE="$PWD/dist/LaTeX — Preview Selection.workflow" uv run test/integration/check_live_preview.py
fi
echo "Release preview checks passed."
