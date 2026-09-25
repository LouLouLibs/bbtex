<div align="center">

<img src="docs/public/logo.svg" width="96" alt="bbtex logo">

# bbtex
### LaTeX for BBEdit: one-key builds, Skim sync, equation previews

[![Vibecoded](https://img.shields.io/badge/vibecoded-%E2%9C%A8-blueviolet)](https://claude.ai)
[![OCaml](https://img.shields.io/badge/OCaml-5.4-EC6813?logo=ocaml&logoColor=white)](bbtex.opam)
[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-000000?logo=apple&logoColor=white)](#requirements)
[![Docs](https://img.shields.io/badge/docs-louloulibs.github.io%2Fbbtex-1f5f8b)](https://louloulibs.github.io/bbtex/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Install](#install)
- [Setup](#setup)
- [Everyday use](#everyday-use)
- [Choosing the engine and main file](#choosing-the-engine-and-main-file)
- [Command line](#command-line)
- [Documentation](#documentation)
- [Development](#development)
- [License](#license)

## Features

- **One-key builds**: <kbd>⌘K</kbd> saves the project's open inputs, compiles the
  root with latexmk (pdfLaTeX, XeLaTeX, LuaLaTeX) or Tectonic, and lists errors
  in BBEdit's results browser. Click an entry to reach the source line.
- **Skim in both directions**: builds update Skim at the cursor without taking
  focus; ⌘-click in the PDF returns to BBEdit.
- **Equation previews**: render selected math with the document's own preamble
  in a small reusable window, refreshed manually, on save, or live as the
  selection changes.
- **Project outline**: a persistent, searchable tree of sections, equations,
  captions and labels across every included file.
- **Citation and reference pickers**: search the bibliography or label context
  and insert keys into the command at the cursor.
- **Structural editing**: change, toggle or wrap environments in one undoable
  edit; TexLab supplies completion and Go to Definition.
- **Project settings**: TeXShop-style `%!TEX` comments, plus an optional
  `.bbtex` file for roots, output directories, options and named profiles.
- **Doctor**: one command checks the TeX tools, Skim, the package and save hooks.

## Requirements

- An Apple Silicon Mac with [BBEdit](https://www.barebones.com/products/bbedit/).
- [MacTeX](https://tug.org/mactex/) or [TinyTeX](https://yihui.org/tinytex/);
  with Biber, version 2.21 or later.
- [Skim](https://skim-app.sourceforge.io/) for PDFs and SyncTeX.
- Optional: [Tectonic](https://tectonic-typesetting.github.io/), Poppler's
  `pdftoppm` for previews (`brew install poppler`), and
  [TexLab](https://github.com/latex-lsp/texlab) for completion.

## Install

**From a release:** download `bbtex.bbpackage.zip` from
[Releases](https://github.com/LouLouLibs/bbtex/releases), unzip it, and
double-click `bbtex.bbpackage`. Then run **Scripts → LaTeX — Doctor**.

**From source**, with [opam](https://opam.ocaml.org/doc/Install.html):

```sh
git clone https://github.com/LouLouLibs/bbtex.git
cd bbtex
opam install . --deps-only
scripts/install.sh      # builds bbtex, links it to ~/.local/bin, installs the menu scripts
```

Use either the release package or the development scripts, not both.

## Setup

Assign shortcuts in **BBEdit → Settings → Menus & Shortcuts → Scripts**:

| Script | Shortcut |
|---|---|
| LaTeX — Compile | <kbd>⌘K</kbd> |
| LaTeX — Forward Search | <kbd>⇧⌘J</kbd> |
| LaTeX — Compile With… | <kbd>⇧⌘K</kbd> |

For inverse search, set **Skim → Settings → Sync** to *Custom*, command
`/usr/local/bin/bbedit`, arguments `--line %line "%file"`.

## Everyday use

1. Press <kbd>⌘K</kbd>. The PDF opens in Skim at the cursor; errors appear in
   **LaTeX Results**.
2. Click an error, fix it, and press <kbd>⌘K</kbd> again.
3. Press <kbd>⇧⌘J</kbd> to show the cursor's position in the PDF, or ⌘-click in
   Skim to go back.

Other commands in **Scripts → LaTeX —**:

| Command | Purpose |
|---|---|
| Compile With… | One-off engine or profile; **Configure Document…** writes `%!TEX` settings |
| Show Build Results / Open Build Log | Warnings and bad boxes, or the full compiler output |
| Cancel Build | Stop the project's compiler and its children |
| Preview Selection | Render the selected math in the preview window |
| Toggle Preview on Save / Toggle Live Selection Preview | Keep the preview current automatically |
| Project Outline / Project Outline Window | Search and jump across the project |
| Insert Citation / Insert Reference | Pick keys by metadata or label context |
| Clean / Clean All Build Output | Remove auxiliary files (and optionally the PDF) |
| Doctor | Check the setup |

## Choosing the engine and main file

```latex
%!TEX program = xelatex     % pdflatex (default), xelatex, lualatex, tectonic
%!TEX root = ../main.tex    % in an included file: build the main document
```

For shared settings, add a `.bbtex` file at the project root:

```ini
root = main.tex
engine = pdflatex
output_directory = build

[profile Draft]
options = -halt-on-error
```

See [compiling projects](docs/project-builds.md) for the full format.

## Command line

The menu commands wrap one binary that also works in Terminal and CI:

```sh
bbtex compile paper.tex                    # build the resolved root
bbtex compile --engine tectonic paper.tex  # one-off engine
bbtex results paper.tex                    # diagnostics from the last log
bbtex doctor --probe                       # setup checks with tool versions
```

See the [command-line reference](docs/cli.md).

## Documentation

The full guide is at **[louloulibs.github.io/bbtex](https://louloulibs.github.io/bbtex/)**
and in [`docs/`](docs/):

- [Getting started](docs/getting-started.md)
- [Compiling projects](docs/project-builds.md) · [Writing and editing](docs/bbedit-editing.md)
- [Project outline](docs/project-navigation.md) · [Citations and references](docs/citation-reference-pickers.md)
- [Equation previews](docs/selection-preview.md) · [Troubleshooting](docs/setup-troubleshooting.md)
- [Comparison with LaTeXTools and AUCTeX](docs/editor-comparison.md) · [Release notes](docs/release-notes.md)

## Development

```sh
opam exec -- dune build && opam exec -- dune runtest   # unit and cram tests
scripts/ci.sh                                         # full local CI on a clean checkout
scripts/docs-site.sh preview                          # build and serve the docs site
```

bbtex is an OCaml binary with thin bash and AppleScript glue; shipped code has
no Python. See [AGENTS.md](AGENTS.md) for the rules,
[architecture](docs/dev/architecture.md), [CI and releases](docs/dev/releases.md)
and the [project status](docs/dev/HANDOFF.md). Editing assets from the former
Latex.bbpackage are credited in
[support/THIRD-PARTY-NOTICES.md](support/THIRD-PARTY-NOTICES.md).

## License

MIT
