# bbtex — LaTeX for BBEdit

Compile LaTeX, see errors in BBEdit's results browser, and jump between
source and PDF. Like LaTeXTools for Sublime, but for BBEdit.

## What you get

- **Cmd+Shift+B** compiles the current `.tex` file and shows
  errors/warnings in BBEdit's results browser — click any entry to jump
  to the source line.
- **Cmd+Shift+J** jumps from the cursor position in BBEdit to the
  corresponding spot in Skim (forward search).
- **Cmd+click in Skim** jumps back to BBEdit at the right line (inverse
  search).
- **Cmd+Shift+K** removes build artifacts (`.aux`, `.log`, `.synctex.gz`,
  etc.).
- A macOS notification tells you whether compilation succeeded or failed.

## Prerequisites

- [BBEdit](https://www.barebones.com/products/bbedit/)
- A TeX distribution: [MacTeX](https://tug.org/mactex/) or
  [TinyTeX](https://yihui.org/tinytex/) (provides `latexmk`, `pdflatex`,
  `xelatex`, `lualatex`)
- [Skim](https://skim-app.sourceforge.io/) for PDF viewing and SyncTeX

Optional: [Tectonic](https://tectonic-typesetting.github.io/) if you
prefer it over latexmk.

## Install

### From a package (easiest)

Download `bbtex.bbpackage.zip` from the Releases page, unzip, and
double-click `bbtex.bbpackage`. BBEdit installs it automatically.

### From source

Requires OCaml 5.0+ and dune 3.0+.

```bash
git clone <repo-url> ~/bbtex-ocaml
cd ~/bbtex-ocaml
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
| LaTeX — Compile        | Cmd+Shift+B |
| LaTeX — Forward Search | Cmd+Shift+J |
| LaTeX — Clean          | Cmd+Shift+K |

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

If no `%!TEX program` directive is found, bbtex defaults to `pdflatex`.

### Multi-file projects

If your project has a main file that `\input`s or `\include`s chapters,
add this to each chapter file:

```latex
%!TEX root = ../main.tex
```

Now compiling from any chapter file will compile `main.tex` instead. The
path is relative to the file containing the directive.

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
2. **Cmd+Shift+B** — saves the document, compiles it, and opens the PDF
   in Skim. Errors and warnings appear in BBEdit's results browser.
3. Click an error in the results browser to jump to the source line.
4. Fix the error, **Cmd+Shift+B** again.
5. **Cmd+Shift+J** — jump from the cursor in BBEdit to the matching
   position in the PDF (forward search via SyncTeX).
6. **Cmd+click in Skim** — jump from the PDF back to BBEdit (inverse
   search).

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
