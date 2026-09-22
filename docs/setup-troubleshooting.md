# Setup and troubleshooting

Run `bbtex doctor` or **Scripts → LaTeX — Doctor** in BBEdit. Supply a saved
source with `bbtex doctor path/to/main.tex` to resolve its engine and inspect its
latest bbtex build log. The menu uses `BB_DOC_PATH` when BBEdit supplies it; without
that value it checks the default setup. The report appears as shell output.

This first diagnostic tier is strictly read-only: no tool execution, compilation,
settings changes, directory creation or installation. `OK` means the stated
inspection passed, not that the feature has been exercised. `WARN` needs attention;
`OPTIONAL` is not a broken installation. `UNVERIFIED` requires a manual check.
Exit status is zero when a report is produced, including reports containing warnings.

## Interpreting the report

- Missing selected TeX engine or latexmk: install/repair your TeX distribution and
  make its executable directory available on PATH. The BBEdit launcher includes
  `/Library/TeX/texbin`, `/opt/homebrew/bin` and `/usr/local/bin` before inherited PATH.
  The terminal command inspects the terminal's PATH, which may differ.
- Missing `pdftoppm`: install Poppler if you want equation previews.
- Missing `uv`: install uv for the citation picker and Python-based installers.
- Missing `texlab`: check the TexLab installation and BBEdit language-server
  configuration; executable discovery alone does not verify that BBEdit uses it.
- Missing BibTeX/Biber: install the backend required by your bibliography. A
  Tectonic BibTeX project uses its embedded backend; external BibTeX is optional.
- Biber universal launcher failure: the known local error is `extracting arm64
  binary with lipo failed`. Repair/reinstall through your TeX distribution. This
  occurs before bibliography processing; changing citation keys will not fix it.
- Biber control-file version mismatch: use a compatible Biber/biblatex pair.
  Tectonic's selected bundle supplies biblatex independently of the system TeX
  installation. The observed bundle biblatex 3.17 and Biber 2.20 are incompatible.
  Doctor recognizes this only if the evidence remains in the latest build log;
  it does not run Biber or infer compatibility from its executable path.
- Duplicate commands: inspect both BBEdit's Scripts folder and the `bbtex.bbpackage`
  package. Keep one active workflow installation. `bbtex-support.bbpackage` is a
  separate editing package and is expected alongside the workflow commands.
- Save attachment present: ownership is unverified. Do not overwrite an existing
  attachment from another workflow. Follow the preview installation instructions.
- State access: the nearest existing parent must be writable/searchable. The
  inspection does not prove that an actual write will succeed (quota/ACL changes
  and other runtime failures remain possible).

RaTeX remains an experimental placeholder. No installation is recommended by doctor.
Tool versions, launchability, arbitrary custom package names, compiled attachment
ownership, and native integration are deliberately unverified in this first tier.

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
