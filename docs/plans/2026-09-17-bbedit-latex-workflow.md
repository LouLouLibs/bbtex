# BBEdit LaTeX workflow implementation plan

Preserve ⌘K (Compile) and ⇧⌘K (Compile With…). Use native BBEdit completion,
navigation, clippings, results browsers, and Skim. Keep bbtex responsible for builds.

## 1. Consolidation — implemented and installed

- Import the old package’s clippings, stationery, environment helpers, and license.
- Build AppleScript from source; preserve clipping-to-library dependencies.
- Retain change environment, star/unstar, and math operator tools.
- Replace documentation lookup’s dependency on the old typesetting library.
- Ship editing assets in the main release package; use a companion support package
  for development so the existing script symlinks and shortcuts remain valid.
- Archive the original installed package outside BBEdit’s Packages folder.
- Verify imported asset counts, compiled scripts, dependency paths, and shortcuts.

Installed bbtex-support.bbpackage and archived the complete original under
BBEdit/Backups/bbtex-20260917-173713-582962/. A live BBEdit regression check
verified that toggling an equation environment twice restores its original text.
Clipping script dependencies are checked during the build; stationery Finder
metadata is restored explicitly. Build and migration helpers use uv with PEP 723.

## 2. TexLab integration — server behavior and BBEdit activation verified

- Check BBEdit’s actual server configuration and logs, not just PATH.
- Make the existing TexLab executable discoverable using a dedicated symlink.
- Verify reference/citation completion and definition requests with a sample project.
- Document BBEdit completion, go-to-definition, references, and issue navigation.
- Avoid adding a second build-on-save system alongside bbtex.
- Distinguish server-level tests from live editor verification.

TexLab 5.26.0 passed label completion, citation completion, and definition requests
in test/integration/check_texlab.py. Installed a direct BBEdit Language Servers
symlink to the existing executable. Historical BBEdit logs showed discovery
failures. check_bbedit_texlab.py now confirms BBEdit launches TexLab for a saved
TeX document. The user subsequently verified completion and Go to Definition. Native completion
and navigation instructions are in docs/bbedit-editing.md.

## 3. Compile–fix–preview loop — implemented and installed

- Keep successful builds quiet; show errors automatically, warnings on request.
- Add Show Build Results and Open Build Log commands.
- Eliminate fragile System Events checkbox clicking.
- Sync Skim to the captured source line after successful compilation.
- Preserve editing focus and avoid opening both the raw log and results window.
- Give failures without parsed log errors an actionable fallback message.
- Test clean, warning-only, failed, missing-tool, and missing-SyncTeX cases.

Verified with mocked compiler/desktop commands across all listed cases, plus
failed saves and quoted paths. Native BBEdit results creation/cleanup passed.
A real pdfLaTeX build through the wrapper produced PDF and SyncTeX output,
opened the PDF in Skim, and left source content unchanged. Both on-demand
diagnostic commands are installed; the existing compile symlink uses the new
workflow. Diagnostic deduplication now preserves different messages/severities
on the same line. No System Events scripting is required for results.

## 4. Project-aware builds — implemented and installed

- Resolve and validate root chains, including cycles and missing files.
- Save modified files belonging to the current project before compiling.
- Serialize builds per root and provide cancellation without orphaned compilers.
- Show root, engine, duration, and build status.
- Add project settings for defaults, named profiles, output directory, and options.
- Ensure clean, diagnostics, and SyncTeX use the same resolved output paths.
- Make ordinary Clean preserve PDFs; offer a separate full cleanup action.
- Test multi-file projects, overlapping builds, cancellation, and engine switches.

Implemented `.bbtex` configuration and named profiles in Compile With…,
canonical root resolution, per-root locks and logs, and process-group cancellation.
Overlapping requests report a busy project. Ordinary Clean preserves PDFs;
the separate full-clean command asks for confirmation. Both commands are installed.
Native checks verified saving the root, chapter, and bibliography while leaving
an unrelated document unsaved, then compiling a real project into an output
directory containing spaces with PDF and SyncTeX available in Skim.
Process tests cover overlapping builds/cleanup and cancellation of both normal
and signal-resistant compiler children. See docs/project-builds.md for settings.

## 5. Guided document setup — implemented and user verified

Compile With… now includes Configure Document… with engine guidance and a
main-file chooser. It writes TeXShop-style root/program comments for review,
including relative paths to external main files. Unit and native editor-edit
checks cover content preservation and inherited engines. The user verified the
interactive Configure Document workflow; the chooser starts in the source directory.

## Remaining verification and release work

- Setup, compilation, cancellation, completion, and navigation checks are complete.
- TeXShop `% !TEX` spacing and `TS-program` aliases are implemented and tested.
- Release package assembled with the new setup resource; packaged wrapper checked.
- User verified Configure Document, completion on ⇧⌘C, and Go to Definition.
  These checks no longer require follow-up. Direct Computer Use remains unavailable.

## 6. Selected-equation preview — implemented and installed

Preview Selection reuses the resolved root preamble and engine, with AUCTeX's
standalone preview.sty package for cropped PDF converted to PNG in a reusable
BBEdit HTML preview window. Skim remains the full-document viewer. Output/logs stay
in a separate per-root state directory. Project locks and cancellation are shared
with full builds. Tests cover all four engines, external preamble macros, output
isolation, invalid input, and failure logs. See docs/selection-preview.md.
The user accepted the compact HTML surface. Native checks cover selection/focus,
window reuse, and image publication. Direct-engine caching and opt-in preview on
save are implemented; actual BBEdit saves published distinct equations in tests.
The contextual service is installed; its exact right-click placement and the
user's save-preview experience remain optional feedback, not acceptance blockers.
See [Fast selection preview](2026-09-18-fast-selection-preview.md) for measured
latency, current constraints, and deferred work. RaTeX remains experimental.

## Optional later features

Richer citation picker if native completion is insufficient.
Do not rebuild editor features until the native integration has been exercised.

## Verification and rollback

Run dune build/runtest and shell syntax checks for changed build logic.
Compile imported AppleScripts and check package dependencies before installation.
Use timestamped backups for installed packages/settings. Never overwrite user
documents or force quit BBEdit. Report any live UI checks still outstanding.
