# bbtex — LaTeX for BBEdit

Setup checks: `bbtex doctor [file.tex]` or **Scripts → LaTeX — Doctor**.
Add `--probe` for bounded tool-version checks (included in the menu command).
See [setup troubleshooting](docs/setup-troubleshooting.md) for scope and fixes.

Compile LaTeX, see errors in BBEdit's results browser, and jump between
source and PDF. Like LaTeXTools for Sublime, but for BBEdit.

## What you get

- **Cmd+K** saves open project inputs, compiles the resolved root, and shows
  errors in BBEdit's results browser — click any entry to jump to the source line.
  Successful builds update Skim at the source position without taking focus.
- **LaTeX — Show Build Results** shows all errors, warnings, and bad boxes
  from the project's log without recompiling.
- **LaTeX — Open Build Log** opens compiler output for the latest build of
  this source, or the project's LaTeX log when available.
- **Cmd+Shift+J** jumps from the cursor position in BBEdit to the
  corresponding spot in Skim (forward search).
- **Cmd+click in Skim** jumps back to BBEdit at the right line (inverse
  search).
- **Cmd+Shift+K** opens **Compile With…** to choose a one-off engine or project profile.
- **LaTeX — Cancel Build** stops the current project's compiler and its children.
- **LaTeX — Preview Selection** renders selected math using the project's preamble
  in a compact BBEdit image window. See [selection preview](docs/selection-preview.md).
- **LaTeX — Project Outline** searches saved headings, equations, captions, and
  labels across included files. See [navigation](docs/project-navigation.md).
- **LaTeX — Insert Citation / Insert Reference** search bibliography metadata or
  label context and insert keys without changing existing command styles.
  See [picker details](docs/citation-reference-pickers.md).
- **LaTeX — Clean** (menu only) removes build artifacts (`.aux`, `.log`, `.synctex.gz`,
  etc.), preserving the PDF. **Clean All Build Output** also removes the PDF,
  after confirmation.
- A silent macOS notification reports the root, engine, duration, and diagnostic counts.

## Prerequisites

- [BBEdit](https://www.barebones.com/products/bbedit/)
- A TeX distribution: [MacTeX](https://tug.org/mactex/) or
  [TinyTeX](https://yihui.org/tinytex/) (provides `latexmk`, `pdflatex`,
  `xelatex`, `lualatex`)
- [Skim](https://skim-app.sourceforge.io/) for PDF viewing and SyncTeX

Optional: [Tectonic](https://tectonic-typesetting.github.io/) if you
prefer it over latexmk.

Equation previews additionally require Poppler (`pdftoppm`). TexLab is optional
for editor completion/navigation. Run **LaTeX — Doctor** after installation;
see [setup troubleshooting](docs/setup-troubleshooting.md) for the install,
upgrade/rollback and uninstall acceptance checklist.

## Install

### From a package (easiest)

Download `bbtex.bbpackage.zip` from the Releases page, unzip, and
double-click `bbtex.bbpackage`. BBEdit installs it automatically.

### From source

Requires [opam](https://opam.ocaml.org/doc/Install.html) (OCaml 4.14 or later;
CI builds with 5.4.1). Running the integration tests also needs
[uv](https://docs.astral.sh/uv/).

```bash
git clone <repo-url> ~/bbtex-ocaml
cd ~/bbtex-ocaml
opam install . --deps-only   # dune, uucp and uunf
scripts/install.sh
```

This builds the binary, symlinks it to `~/.local/bin/bbtex`, and installs
the scripts into BBEdit's Scripts folder.

## Setup

After installing, two manual steps remain:

### 1. Keyboard shortcuts

BBEdit > Settings > Menus & Shortcuts, scroll to the Scripts section:

| Script                 | Shortcut    |
|------------------------|-------------|
| LaTeX — Compile        | Cmd+K |
| LaTeX — Forward Search | Cmd+Shift+J |
| LaTeX — Compile With…  | Cmd+Shift+K |
| LaTeX — Clean          | None |

Remove the previous Cmd+Shift+K binding from Clean before assigning it to
Compile With…. If Cmd+K is already assigned, remove that conflicting binding too.
Scripts can also be assigned keys in Window > Palettes > Scripts.

### 2. Skim inverse search

Skim > Settings > Sync:

| Field     | Value                              |
|-----------|------------------------------------|
| Preset    | Custom                             |
| Command   | `/usr/local/bin/bbedit`            |
| Arguments | `--line %line "%file"`             |

This lets you Cmd+click in Skim to jump back to the source line in
BBEdit.

## Choosing the LaTeX engine

bbtex reads `%!TEX` directives from the first 50 lines of your `.tex`
file — the same magic comments used by TeXShop, TeXworks, and Sublime
LaTeXTools.

These “magic comments” come from the **TeXShop editor convention**: the editor
reads them as build instructions, while LaTeX ignores them as ordinary comments.
They are not an official LaTeX standard or AUCTeX's Emacs local-variable format.
See [TeXShop](https://pages.uoregon.edu/koch/texshop/) and
[LaTeXTools' documented support](https://latextools.readthedocs.io/en/latest/features/).
bbtex's generated syntax is shown below; editor-specific variations are not
necessarily interchangeable.

### Compile With…

Press **Cmd+Shift+K** to choose Document settings, pdfLaTeX, XeLaTeX,
LuaLaTeX, Tectonic, or a named project profile in a native picker. The choice applies to that build
only; it does not edit your source. Cancel skips compilation.

Choose **Configure Document…** in the same picker for engine guidance and a
main-file chooser. It writes `%!TEX` settings into the current document for
review, including relative root paths for included tables and chapters.

### Engine selection

Add this near the top of your document:

```latex
%!TEX program = xelatex
```

Supported engines: `pdflatex` (default), `xelatex`, `lualatex`,
`tectonic`.

- `pdflatex`, `xelatex`, `lualatex` are compiled via **latexmk**, which
  handles multiple passes, BibTeX/Biber, and convergence automatically.
- `tectonic` is called directly (it has its own multi-pass logic).

Engine precedence is: explicit engine override, selected/default profile engine,
first directive in the source-to-root chain, project engine, then `pdflatex`.

### Multi-file projects

If your project has a main file that `\input`s or `\include`s chapters,
add this to each chapter file:

```latex
%!TEX root = ../main.tex
```

Now compiling from any chapter file will compile `main.tex` instead. The
path is relative to the file containing the directive.

For shared defaults, add a `.bbtex` file in the project directory:

```ini
root = main.tex
engine = pdflatex
output_directory = build

[profile XeLaTeX]
engine = xelatex
```

See [project settings, profiles, and cancellation](docs/project-builds.md) for
the full format and saving behavior. Only one build or cleanup runs per root.

### Example preamble

```latex
%!TEX root = main.tex
%!TEX program = xelatex
\documentclass{article}
\usepackage{fontspec}
...
```

## Workflow

1. Open a `.tex` file in BBEdit.
2. **Cmd+K** — saves the document and modified project inputs, compiles the root, and opens the PDF
   in Skim at the current source position. Errors appear automatically;
   successful builds clear old results without opening a new window.
3. Click an error in the results browser to jump to the source line.
4. Fix the error, **Cmd+K** again.
5. **Cmd+Shift+J** — jump from the cursor in BBEdit to the matching
   position in the PDF (forward search via SyncTeX).
6. **Cmd+click in Skim** — jump from the PDF back to BBEdit (inverse
   search).
7. Use **LaTeX — Show Build Results** to inspect warnings and bad boxes,
   or **LaTeX — Open Build Log** for full compiler output.

## Troubleshooting

**Compilation fails with no useful message**
Check the debug log:

```bash
cat ~/.local/state/bbtex/last-compile.log
```

Or run directly from Terminal for full output:

```bash
bbtex compile --verbose myfile.tex
```

**"No document open" alert**
The script needs BBEdit's `$BB_DOC_PATH`. Make sure you run it from a
document window, not a shell worksheet.

**Forward search does nothing**
Make sure Skim is installed at `/Applications/Skim.app` and that SyncTeX
is enabled (it is by default with latexmk).

**latexmk / pdflatex not found**
Your TeX distribution isn't on the PATH that BBEdit sees. The easiest fix
is to install [MacTeX](https://tug.org/mactex/), which adds itself to the
system PATH. If you use TinyTeX or a custom location, add the TeX binary
directory to `/etc/paths.d/` or to your shell profile.

## Command-line usage

The `bbtex` binary also works standalone from Terminal:

```bash
# Compile a .tex file
bbtex compile myfile.tex

# Override the engine for one build
bbtex compile --engine tectonic myfile.tex

# Use a named project profile
bbtex compile --profile Draft myfile.tex

# Stop this project's active build
bbtex cancel myfile.tex

# Parse a log file (human-readable)
bbtex parse-log build/output.log

# Parse a log file (BBEdit results format)
bbtex parse-log build/output.log --format bbedit

# Extract %!TEX directives
bbtex directives myfile.tex

# Forward search (emit PDF path for SyncTeX)
bbtex forward-search myfile.tex 42
```

## Further reading

- [Architecture and design decisions](docs/architecture.md)
- [LaTeXTools feature comparison](docs/latextools-comparison.md)

## Editing support and development plan

The old Latex.bbpackage's clippings, stationery, and editing helpers are now
maintained in this repository. Its retired build scripts are archived during
migration. See [editing commands and TexLab setup](docs/bbedit-editing.md),
[asset attribution](support/THIRD-PARTY-NOTICES.md), and the
[implementation plan](docs/plans/2026-09-17-bbedit-latex-workflow.md).

Build and install helpers are bash; Python is used only for integration tests,
through `uv run`. See [AGENTS.md](AGENTS.md) for the language policy.

    scripts/build-support.sh
    scripts/install-support.sh                 # preview the install
    scripts/install-support.sh --apply --restart
# Optional preview refresh

**LaTeX — Toggle Preview on Save** enables equation preview updates on ⌘S for
the current file. See [selection preview](docs/selection-preview.md#refresh-on-save)
for supported equation environments and attachment installation.
RaTeX is available as an **experimental placeholder** in the compiler picker;
it is not installed automatically or selected by default.

## CI builds and releases

bbtex supports Apple Silicon Macs. `scripts/ci.sh` runs the full check suite on
a clean checkout, posts the result to GitHub with `--report`, and prepares draft
releases with `--release`. `--engines` adds the
[real-engine corpus](docs/real-engine-regressions.md) (pdfLaTeX/XeLaTeX/LuaLaTeX
with BibTeX/Biber, previews, diagnostics and cancellation). See
[CI and release instructions](docs/releases.md).
