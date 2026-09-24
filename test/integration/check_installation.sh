#!/bin/bash
# Staged package install/upgrade/uninstall; never changes the real BBEdit setup.
set -Eeuo pipefail
trap 'echo "${0##*/}: failed at line $LINENO: $BASH_COMMAND" >&2' ERR
for tool in ditto osacompile /sbin/md5; do command -v "$tool" >/dev/null; done
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG="${BBTEX_TEST_PACKAGE:-$ROOT/dist/bbtex.bbpackage}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/bbtex-install-check.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
SUPPORT="$STAGE/Custom BBEdit Support"
PACKAGE="$SUPPORT/Packages/Renamed Workflow.bbpackage"
mkdir -p "$SUPPORT/Packages"
ditto "$PKG" "$PACKAGE"
BBTEX="$PACKAGE/Contents/Resources/bbtex"
INSTALLER="$PACKAGE/Contents/Resources/install-preview-save-hook.sh"
HOOK="$SUPPORT/Attachment Scripts/Document.documentDidSave.scpt"
report() { "$BBTEX" doctor --bbedit-support "$SUPPORT"; }
report >"$STAGE/report"
grep -q 'Installed command.*Renamed Workflow.bbpackage' "$STAGE/report"
grep -q '\[OK\] Editing support' "$STAGE/report"
if [[ "${BBTEX_INSTALL_REAL:-0}" == 1 ]]; then
    printf '\\documentclass{article}\n\\begin{document}\nInstallation smoke check.\n\\[E=mc^2\\]\n\\end{document}\n' >"$STAGE/main.tex"
    BBTEX_STATE_DIR="$STAGE/state" "$BBTEX" compile "$STAGE/main.tex" >"$STAGE/compile.log"
    [[ -s "$STAGE/main.pdf" ]]
    echo 'Staged package: real pdfLaTeX compilation passed'
fi
mkdir -p "$SUPPORT/Scripts/Nested"
printf 'duplicate fixture\n' >"$SUPPORT/Scripts/Nested/LaTeX — Project Outline.sh"
ln -s "$STAGE/missing" "$SUPPORT/Scripts/Nested/LaTeX — Doctor.sh"
report >"$STAGE/report"
grep -q '\[WARN\] Duplicate command' "$STAGE/report"
grep -q '\[WARN\] Broken command link' "$STAGE/report"
bash "$INSTALLER" --apply --bbedit-support "$SUPPORT" >"$STAGE/install.log"
report >"$STAGE/report"
grep -q '\[OK\] Save attachment.*Matches bbtex installer receipt' "$STAGE/report"
# An unchanged install upgrades; changed or unrelated attachments do not.
bash "$INSTALLER" --apply --bbedit-support "$SUPPORT" >>"$STAGE/install.log"
# Exact legacy hook content is adopted, without trusting a marker string alone.
rm -f "$HOOK.bbtex-receipt"
bash "$INSTALLER" --apply --bbedit-support "$SUPPORT" >>"$STAGE/install.log"
[[ -f "$HOOK.bbtex-receipt" ]]
/bin/cp "$HOOK" "$STAGE/original.scpt"
printf 'modified\n' >>"$HOOK"
HASH="$(/sbin/md5 -q "$HOOK")"
report >"$STAGE/report"
grep -q '\[WARN\] Save attachment.*differs' "$STAGE/report"
if bash "$INSTALLER" --apply --bbedit-support "$SUPPORT" >>"$STAGE/install.log" 2>&1; then
    echo 'Installer overwrote a changed hook' >&2; exit 1
fi
[[ "$(/sbin/md5 -q "$HOOK")" == "$HASH" ]]
/bin/cp "$STAGE/original.scpt" "$HOOK"
# A foreign script mentioning bbtex must not be mistaken for an owned hook.
rm -f "$HOOK.bbtex-receipt"
printf 'on documentDidSave(myDoc)\nreturn "LaTeX — Toggle Preview on Save.sh"\nend documentDidSave\n' >"$STAGE/foreign.applescript"
osacompile -o "$HOOK" "$STAGE/foreign.applescript"
HASH="$(/sbin/md5 -q "$HOOK")"
if bash "$INSTALLER" --apply --bbedit-support "$SUPPORT" >>"$STAGE/install.log" 2>&1; then
    echo 'Installer adopted a marker-only foreign hook' >&2; exit 1
fi
[[ "$(/sbin/md5 -q "$HOOK")" == "$HASH" ]]
/bin/cp "$STAGE/original.scpt" "$HOOK"
printf 'foreign attachment\n' >"$SUPPORT/Attachment Scripts/Document.scpt"
report >"$STAGE/report"
grep -q '\[WARN\] Attachment conflict' "$STAGE/report"
if bash "$INSTALLER" --apply --bbedit-support "$SUPPORT" >>"$STAGE/install.log" 2>&1; then
    echo 'Installer ignored a conflicting attachment' >&2; exit 1
fi
# Retain an executable outside the staged package to inspect removal.
/bin/cp "$BBTEX" "$STAGE/bbtex"
rm -rf "$PACKAGE" "$SUPPORT/Scripts"
rm -f "$HOOK" "$HOOK.bbtex-receipt"
"$STAGE/bbtex" doctor --bbedit-support "$SUPPORT" >"$STAGE/report"
grep -q '\[OPTIONAL\] Menu command' "$STAGE/report"
grep -q '\[WARN\] Attachment conflict' "$STAGE/report"
[[ -f "$SUPPORT/Attachment Scripts/Document.scpt" ]]
echo 'Staged install: renamed package, nested/duplicate/broken commands, hook receipt, protected upgrade and removal passed'
