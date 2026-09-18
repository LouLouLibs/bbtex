# Writing LaTeX in BBEdit

## Compile and view

- ⌘K: compile using document settings and sync Skim in the background.
- ⇧⌘K: choose an engine or named project profile for this build.
- LaTeX — Cancel Build stops the project's active compiler and its children.
- LaTeX — Clean preserves the PDF; Clean All Build Output removes it after confirmation.
- Use LaTeX — Forward Search to locate the source position in Skim.
  Existing personal key assignments are preserved.
- Cmd-click in Skim returns to BBEdit when Skim inverse search is configured.
- Errors appear automatically in LaTeX Results. Warnings and bad boxes are
  available through LaTeX — Show Build Results without rebuilding.
- LaTeX — Open Build Log opens the current root's compiler output, or
  its project's LaTeX log. If no project log exists, it shows the latest global
  compiler output (which may belong to another document).
- Successful builds do not open a results window or play a sound. If SyncTeX
  is unavailable, the PDF still opens in Skim without taking focus.

Compilation saves modified `.tex`, `.bib`, `.sty`, and `.cls` documents open
under the project directory, plus the explicit root. Configure roots, output
directories, and profiles in [a project `.bbtex` file](project-builds.md).

## Native completion and navigation

TexLab supplies the editor's LaTeX intelligence; bbtex runs explicit builds.
The installed TexLab was verified with label completion, citation completion,
and reference-to-label definition requests using a disposable test project.
BBEdit was also verified to start TexLab when opening a saved TeX file.
This does not test every completion-popup interaction in the editor.

In a TeX document:

- Use BBEdit's completion command inside \ref{...} and \cite{...}.
- Command-double-click a reference, or use Go > Go to Definition.
- Use Search > Find References to Selected Symbol for references.
- Use Search > Find Symbol in Workspace to navigate project symbols.
- Use View > Text Display > Show Issues for source diagnostics.

If completion is missing, inspect Settings > Languages > TeX > Server.
BBEdit's TeX module is preconfigured for texlab; a direct executable symlink
in Language Servers avoids shell PATH differences. Open the actual project
folder so the server can discover the bibliography and included files.

Do not enable a second automatic compilation workflow while using bbtex's
explicit builds. Server completion/navigation do not require build-on-save.

Reference: https://hosting.barebones.com/support/bbedit/lsp-notes.html

## Imported editing tools

Scripts > LaTeX Editing contains:

- Change Environment
- Toggle Starred Environment
- Declare Math Operator
- Package Documentation

The former LaTeX clippings and stationery remain available. Scripted clippings
for inserting and closing environments keep their shared environment library.

The environment helpers operate through text searches, so commented commands
and verbatim environments can confuse them. Further parser hardening is planned.
Use Undo to reverse an unwanted editing operation.

## Rollback

Migration saves the complete previous package and shortcut file in
~/Library/Application Support/BBEdit/Backups/bbtex-TIMESTAMP/.
Quit BBEdit, move bbtex-support.bbpackage out of Packages, restore Latex.bbpackage
from the backup, then reopen BBEdit. Restore the shortcut backup too if you want
the original editing-command assignments.

## Development checks

Python utilities must run with uv and PEP 723 script metadata:

    uv run scripts/build-support.py
    uv run test/integration/check_texlab.py
    uv run test/integration/check_build_workflow.py
    uv run test/integration/check_project_builds.py
    uv run test/integration/check_project_saving.py
    uv run test/integration/check_bbedit_texlab.py
    uv run test/integration/check_results_browser.py
    uv run test/integration/check_live_compile.py
    uv run scripts/install-support.py

The last command previews migration. Add --apply --restart to install.

The native integration checks use disposable BBEdit documents/PDFs and require
macOS application scripting access. The workflow check uses fake compilers and
desktop commands to exercise failure paths without touching the editor.
