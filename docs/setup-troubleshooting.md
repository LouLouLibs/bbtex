# Setup and troubleshooting

For the supported MacTeX setup, use **Biber ≥ 2.21**, paired with a compatible
biblatex version. The verified installation is MacTeX 2026 with Biber 2.21.
Check with `biber --version`; the version alone does not prove the launcher works
or that it matches a Tectonic bundle. Tectonic's older bundle requires separate
Biber/biblatex compatibility validation.

Run `bbtex doctor` for inspection only, or `bbtex doctor --probe` for tool launch
and version checks. **Scripts → LaTeX — Doctor** includes the launch checks. Supply a saved
source with `bbtex doctor path/to/main.tex` to resolve its engine and inspect its
latest bbtex build log. The menu uses `BB_DOC_PATH` when BBEdit supplies it; without
that value it checks the default setup. The report appears as shell output.

For a relocated or staged BBEdit support folder, pass
`bbtex doctor --bbedit-support "/path/to/BBEdit Support"`. Doctor scans Scripts
and Packages below that directory, including renamed packages and nested menu
folders. It follows directory links without revisiting the same location and
reports incomplete inspection at 2,048 entries or eight levels. It does not search
the whole disk. Renamed individual commands and external unselected support
folders still require manual inspection.

Without `--probe`, inspection is strictly read-only: no tool execution,
compilation, settings changes, directory creation or installation. With `--probe`,
Doctor directly executes the first discovered tool with its version flag, without
a shell, with disconnected stdin, a three-second limit per tool, and a 16 KiB
combined stdout/stderr limit. Timeout/output-limit cleanup kills the probe process
group. Probes run sequentially (up to seven tools, roughly 21 seconds of timeouts).
External tools may initialize caches; no document is compiled and Doctor does not
install or repair anything. RaTeX is never probed. `OK` means the stated
inspection passed, not that the feature has been exercised. `WARN` needs attention;
`OPTIONAL` is not a broken installation. `UNVERIFIED` requires a manual check.
Exit status is zero when a report is produced, including reports containing warnings.

## Interpreting the report

- Missing selected TeX engine or latexmk: install/repair your TeX distribution and
  make its executable directory available on PATH. The BBEdit launcher includes
  `/Library/TeX/texbin`, `/opt/homebrew/bin` and `/usr/local/bin` before inherited PATH.
  The terminal command inspects the terminal's PATH, which may differ.
- Missing `pdftoppm`: install Poppler if you want equation previews.
- Missing `texlab`: check the TexLab installation and BBEdit language-server
  configuration; executable discovery alone does not verify that BBEdit uses it.
- Missing BibTeX/Biber: install the backend required by your bibliography. A
  Tectonic BibTeX project uses its embedded backend; external BibTeX is optional.
- Biber universal launcher failure: the known local error is `extracting arm64
  binary with lipo failed`. Repair/reinstall through your TeX distribution. This
  occurs before bibliography processing; changing citation keys will not fix it.
- Biber control-file version mismatch: use a compatible Biber/biblatex pair.
  Tectonic's selected bundle supplies biblatex independently of the system TeX
  installation. The verified older bundle biblatex 3.17 requires isolated Biber 2.17;
  the supported MacTeX Biber 2.21 must not be substituted for that fixture.
  Doctor recognizes this if evidence remains in the latest build log. A successful
  Biber version query does not prove compatibility with a project's biblatex.
- Duplicate commands: inspect both BBEdit's Scripts folder and the `bbtex.bbpackage`
  package. Keep one active workflow installation. `bbtex-support.bbpackage` is a
  separate editing package and is expected alongside the workflow commands.
- Save attachment: new installations include a `.bbtex-receipt` checksum beside
  the compiled hook. `OK` means its contents match that receipt, not a security
  attestation. Modified/unreadable hooks are warnings; older hooks without receipts
  remain unverified. `Document` and `BBEdit` attachments are reported as possible
  conflicts. The installer refuses changed/conflicting hooks; a receipt-less legacy
  hook is adopted only if its full decompiled source matches the current hook.
  Follow the preview installation instructions; never delete unrelated attachments.
- State access: the nearest existing parent must be writable/searchable. The
  inspection does not prove that an actual write will succeed (quota/ACL changes
  and other runtime failures remain possible).

RaTeX remains an experimental placeholder. No installation is recommended by doctor.
Tool versions and launchability require `--probe`. Bibliography compatibility,
renamed individual commands and native integration still require their own checks.
Version output is bounded and reduced to its first nonempty
line; failure signatures are examined separately.

## Disposable smoke check and sharing

Create a new temporary folder and save `main.tex` containing:

```tex
\documentclass{article}
\begin{document}
Hello.
\[ E = mc^2 \]
\end{document}
```

Run Doctor, compile from BBEdit, then select `E = mc^2` and preview it. Confirm
that the full PDF opens in Skim, the equation preview appears, and editor focus
returns as documented. Use a disposable document for structural insertion/Undo
checks. Do not use an existing paper as a test fixture.

The diagnostic report replaces the current home directory with `~`. Other paths
may remain, including project paths outside your home; review before sharing.
It does not include raw logs or document contents. See [releases](releases.md)
for installation/upgrade instructions and [selection preview](selection-preview.md)
for optional service/save-hook setup. Preserve a backup before changing an existing
package; restore that backup to roll back an upgrade.

## Fresh-account or fresh-Mac acceptance

This remains a manual acceptance gate. Staged tests on an already configured Mac
do not establish that the dependency/setup instructions suffice on a fresh machine.
Use a disposable macOS account or a spare Mac; do not remove a working installation
to simulate one. Record macOS/BBEdit/TeX versions and the package checksum.

1. Install the documented prerequisites and the Apple Silicon release package from
   [README](https://github.com/LouLouLibs/bbtex#prerequisites). Run **LaTeX — Doctor**, keeping the report and noting
   missing optional tools separately from required ones. Confirm there is only one
   active workflow installation and no unexplained attachment conflicts.
2. In a temporary folder, create the document above. Compile from BBEdit, open the
   PDF in Skim, and check forward/inverse search. Select `E = mc^2` and invoke
   **Preview Selection**; confirm a cropped equation and preserved editing focus.
3. Open **Project Outline Window**, navigate and save a heading change. Try a
   structural insertion followed by Undo. Enable optional preview-on-save only if
   desired; verify the installer leaves any unrelated attachment alone.
4. Back up the installed package and any bbtex-owned save hook **with its receipt**.
   Upgrade the package once and verify the same smoke checks. Restore that backup
   to test rollback; do not overwrite an attachment modified since the backup.
5. Close bbtex preview windows and disable preview-on-save. Quit BBEdit normally,
   then remove only the package installed for this test. Remove the optional
   `Document.documentDidSave.scpt` and its receipt only if still identified as the
   unchanged bbtex hook; retain shared or modified attachments for manual review.
   Remove the optional `LaTeX — Preview Selection.workflow` from Services only if
   installed in this walkthrough. Restart BBEdit and verify the removed commands
   are absent and unrelated tools still work. Project sources/PDFs and TeX itself
   are never uninstall targets. Retaining bbtex's cache/state is harmless.

For automated staging, `bash test/integration/check_installation.sh` copies the
built package into a temporary custom support folder, verifies discovery, upgrade
refusal and removal, and preserves a foreign attachment. It never repurposes HOME
or writes into the real BBEdit support folder. The hook installer's
`--bbedit-support DIRECTORY` option selects its destination for this staging test;
it does not configure BBEdit or change the hook's standard worker lookup paths.
