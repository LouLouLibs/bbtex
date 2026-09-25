# Getting started

bbtex adds a set of **LaTeX —** commands to BBEdit's Scripts menu, all backed
by one small `bbtex` binary. This page gets you from nothing to a compiled PDF
in about ten minutes, most of it spent waiting for MacTeX to download.

> [!TIP]
> **Current release: v0.1.0.** This is the first release, and it's
> [totally vibe coded](about.md#totally-vibe-coded). It works well on my Mac;
> if it doesn't on yours, please
> [open an issue](https://github.com/LouLouLibs/bbtex/issues).

## Requirements

- An Apple Silicon Mac. Packages are built and tested on the macOS version of
  the Mac that ran the release checks; Intel builds are not verified.
- [BBEdit](https://www.barebones.com/products/bbedit/).
- A TeX distribution: [MacTeX](https://tug.org/mactex/) or
  [TinyTeX](https://yihui.org/tinytex/), which provide `latexmk`, `pdflatex`,
  `xelatex` and `lualatex`. With Biber, use version 2.21 or later with a
  matching biblatex.
- [Skim](https://skim-app.sourceforge.io/) for PDF viewing and SyncTeX.

Optional:

- [Tectonic](https://tectonic-typesetting.github.io/), if you prefer it to latexmk.
- Poppler's `pdftoppm` (`brew install poppler`), for equation previews.
- [TexLab](https://github.com/latex-lsp/texlab), for completion and Go to
  Definition in BBEdit.

## Install

### From a release package

1. Download `bbtex-macos-arm64.bbpackage.zip` from the
   [Releases page](https://github.com/LouLouLibs/bbtex/releases) and unzip it.
2. Double-click `bbtex.bbpackage`. BBEdit installs it into
   `~/Library/Application Support/BBEdit/Packages/`.
3. Run **Scripts → LaTeX — Doctor** to check the TeX tools, Skim and the package
   layout.

Preview on Save and the right-click Preview Selection service are optional
installs; see [equation previews](selection-preview.md#release-installation).

### From source

You need [opam](https://opam.ocaml.org/doc/Install.html) with OCaml 4.14 or
later (CI builds with 5.4.1).

```sh
git clone https://github.com/LouLouLibs/bbtex.git
cd bbtex
opam install . --deps-only   # dune, uucp and uunf
scripts/install.sh
```

This builds the binary, links it to `~/.local/bin/bbtex`, and links the scripts
into BBEdit's Scripts folder. Install either the development scripts or the
release package, not both, or the menu shows duplicates.

## Set up BBEdit

### Keyboard shortcuts

Assign shortcuts in **BBEdit → Settings → Menus & Shortcuts**, in the Scripts
section:

| Script | Suggested shortcut |
|---|---|
| LaTeX — Compile | <kbd>⌘</kbd><kbd>K</kbd> |
| LaTeX — Forward Search | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>J</kbd> |
| LaTeX — Compile With… | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>K</kbd> |
| LaTeX — Clean | none |

Remove any existing binding for those keys first. You can also assign keys in
**Window → Palettes → Scripts**.

### Skim inverse search

In **Skim → Settings → Sync**:

| Field | Value |
|---|---|
| Preset | Custom |
| Command | `/usr/local/bin/bbedit` |
| Arguments | `--line %line "%file"` |

Now ⌘-click in Skim jumps back to the source line in BBEdit.

## First build

1. Open a `.tex` file in BBEdit.
2. Press <kbd>⌘</kbd><kbd>K</kbd>. bbtex saves the document and any modified
   project inputs, compiles the root, and opens the PDF in Skim at the cursor.
3. Errors appear in the **LaTeX Results** browser. Click one to reach its line,
   fix it, and press <kbd>⌘</kbd><kbd>K</kbd> again. A successful build closes
   old results without opening a window.
4. Press <kbd>⇧</kbd><kbd>⌘</kbd><kbd>J</kbd> to show the cursor's position in
   the PDF.
5. **LaTeX — Show Build Results** lists warnings and bad boxes without
   rebuilding; **LaTeX — Open Build Log** shows the full compiler output.

A silent notification reports the root, engine, duration and diagnostic counts.

![The compiled demo paper open in Skim](images/skim-sync.png)

![LaTeX Results listing an undefined control sequence in model.tex, line 7](images/results-browser.png)

## Choose the engine and main file

Put TeXShop-style comments near the top of a file (bbtex reads the first 50
lines). Only these two are read; other `% !TEX` lines such as `spellcheck`,
`options` or `% !BIB` are ignored:

```latex
%!TEX program = xelatex
%!TEX root = ../main.tex
```

- `program` is `pdflatex` (the default), `xelatex`, `lualatex` or `tectonic`.
  The first three run through latexmk, which handles passes and
  BibTeX/Biber; Tectonic runs directly.
- `root` points an included chapter or table at the main document, relative to
  the file that contains it.

Rather than typing these, press <kbd>⇧</kbd><kbd>⌘</kbd><kbd>K</kbd> and choose
**Configure Document…**. The same **Compile With…** picker also runs a
one-off build with another engine or a named profile. For settings shared
across a project, such as the output directory, extra options and profiles, add a
[`.bbtex` file](project-builds.md#shared-project-settings).

## Next steps

- [Compiling projects](project-builds.md): `.bbtex` settings, profiles and cancellation.
- [Writing and editing](bbedit-editing.md): environments, clippings and TexLab.
- [Project outline](project-navigation.md) and
  [citations and references](citation-reference-pickers.md).
- [Equation previews](selection-preview.md): manual, on save, or live.
- [Troubleshooting](setup-troubleshooting.md) if Doctor reports a problem.
