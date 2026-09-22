# Writing LaTeX in BBEdit

## Compile and view

- ⌘K: compile using document settings and sync Skim in the background.
- ⇧⌘K: choose an engine or named project profile for this build.
- LaTeX — Cancel Build stops the project's active compiler and its children.
- LaTeX — Preview Selection renders selected math in a compact BBEdit window using the main-file
  preamble. Select a complete equation or raw math first; see [preview details](selection-preview.md).
- LaTeX — Open Preview Log opens the current preview request's log. Status in the
  preview window distinguishes current output from rendering, stale, or failed output.
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

- Choose **Edit → Complete** inside \ref{...} and \cite{...}. This installation
  uses **⇧⌘C**, reassigned from Copy & Append (which remains available in the
  Edit menu). BBEdit's factory shortcut is F5, possibly Fn-F5. For example, type
  `\ref{eq:` and invoke Complete. The current shortcut is shown in the Edit menu
  and can be changed in Settings → Menus & Shortcuts.
- Command-double-click a reference, or use Go > Go to Definition.
- Use Search > Find References to Selected Symbol for references.
- Use Search > Find Symbol in Workspace to navigate project symbols.
- Use **Scripts → LaTeX — Project Outline** for a searchable saved-file outline
  of sections, equations, figures, tables, and labels across included files.
  Duplicate labels retain their locations; stale targets require a fresh search.
  See [project navigation](project-navigation.md) for scope and keyboard usage.
- Use View > Text Display > Show Issues for source diagnostics.
- **Scripts → LaTeX — Insert Citation / Insert Reference** provide explicit
  metadata/context search and safe key insertion alongside native completion.
  [Picker usage and supported commands](citation-reference-pickers.md).

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
- Wrap in Environment
- Declare Math Operator
- Package Documentation

The former LaTeX clippings and stationery remain available. Scripted clippings
for inserting and closing environments keep their shared environment library.

Place an empty cursor inside an environment (including either tag) to change its
name or toggle its star. The innermost matched pair changes in one undoable edit;
body text, indentation, and surrounding tags stay intact. The cursor follows the
same position through the name changes, including Unicode before the cursor.
Cancel leaves text and selection unchanged. Edits made while the rename dialog
is open cause an explanatory refusal rather than applying an obsolete edit.

Matching uses the current unsaved buffer and skips comments, common verbatim
environments, inline literal commands, and common macro/environment definitions.
Nested identical names are supported. Malformed or crossed tags, dynamic names,
selected text, and a cursor inside a comment, literal region, or definition are
rejected. Names may contain letters, digits, `*`, `@`, and hyphens. Buffers are
limited to 4 MiB; TeX macro expansion, custom literal syntax, and conditionals
are outside this bounded scanner's scope.

**Wrap in Environment** wraps selected complete lines, preserving their existing
indentation and leaving the body selected. A selection may start after leading
whitespace and end before the last line ending; the helper includes that line's
indentation and trailing whitespace. It rejects partial prose lines and selections
that cross environment boundaries. On a blank line, an empty selection inserts
a paired environment and places the cursor in its body, one tab beyond the line's
indentation. LF, CRLF, and CR line endings are retained by the planner (BBEdit
normalizes its scripting text). Wrapping is one Undo and uses the same buffer and
selection guards as renaming.

The Close Environment clipping uses the same scanner on text before the cursor
and proposes the innermost still-open name; it does not inspect future closing
tags. Failed matching aborts insertion and explains why. The custom begin/end
clipping validates the environment name and the same whole-line/context boundaries,
then rechecks the buffer/selection after its dialog. It retains its original
indented body template; use Wrap in Environment to keep body indentation exactly.
Cancellation and invalid input preserve selected text: scripted
clippings abort instead of returning an empty replacement.

The existing fraction, matrix, minipage, and command clippings remain the route
for argument placeholders. A local TexLab audit with snippet support enabled
returned name completions for `\frac` and `\begin{equation}`, without argument
placeholders. Two missing templates are now under **links and images**:

- **hyperlink (hyperref)** wraps selected text in `\href` and selects the URL
  placeholder; the document must load `hyperref`.
- **image (graphicx)** inserts `\includegraphics` with width and filename
  placeholders, selecting width first; the document must load `graphicx`.

These use BBEdit's native clipping placeholders and each insertion is one Undo.
They do not add package declarations or alter TexLab's completion shortcut.

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

After `dune build` and building support, verify environment edits with:

    osascript test/integration/check_editing.applescript "$PWD/dist/bbtex-support.bbpackage/Contents/Scripts/LaTeX Editing/Toggle Starred Environment.scpt" "$PWD/dist/bbtex-support.bbpackage/Contents/Resources"

This checks nested toggling, Unicode cursor positions, renaming, single Undo,
and rejection of changed buffers/selections. `dune runtest` covers scanner edge
cases. Release checks run the native test when `BBTEX_TEST_NATIVE=1` is set.

`check_wrapping.applescript` takes the package Resources and `Clippings/Latex.tex`
paths and verifies wrapping, empty insertion, selected bodies, native placeholders,
and Undo. `uv run test/integration/check_structure_dialogs.py` tests the actual
menu/clipping scripts with deterministic dialog answers, including cancellation
and invalid input over selected text. Both are included in native release checks.
