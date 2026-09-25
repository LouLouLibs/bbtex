# Clean install walkthrough

This takes a Mac with nothing LaTeX-related on it to a working bbtex: a compiled
PDF, SyncTeX in both directions and an equation preview. It's also the check I
want every release to pass on a fresh macOS account before I call it done. It
takes about half an hour, most of it waiting for MacTeX to download.

**You need:** an Apple Silicon Mac, an admin password for the installers, and
about 6 GB of free disk space for MacTeX. {.meta}

## Install the tools

1. **BBEdit.** Download it from [barebones.com](https://www.barebones.com/products/bbedit/)
   and move it to `/Applications`. The free mode is enough.
2. **MacTeX.** Download `MacTeX.pkg` from [tug.org/mactex](https://tug.org/mactex/)
   and run the installer. It provides pdfLaTeX, XeLaTeX, LuaLaTeX, latexmk,
   BibTeX, Biber and `preview.sty`. Open a **new** Terminal window afterwards
   and check:

   ```sh
   latexmk -v | head -1
   biber --version      # 2.21 or later
   ```

3. **Skim.** Download it from [skim-app.sourceforge.io](https://skim-app.sourceforge.io/)
   and move it to `/Applications`.
4. **Optional, for equation previews and completion:** with
   [Homebrew](https://brew.sh) installed,

   ```sh
   brew install poppler texlab
   ```

   `poppler` provides `pdftoppm`, which turns previews into images. `texlab` gives
   BBEdit LaTeX completion and Go to Definition.

## Install bbtex

1. Download `bbtex-macos-arm64.bbpackage.zip` from the
   [latest release](https://github.com/LouLouLibs/bbtex/releases/latest) and
   double-click it to unzip. If you want to check the download, compare
   `shasum -a 256 bbtex-macos-arm64.bbpackage.zip` with `SHA256SUMS-arm64.txt`
   from the same release.
2. Move `bbtex.bbpackage` into BBEdit's packages folder:

   ```sh
   mkdir -p ~/Library/Application\ Support/BBEdit/Packages
   mv ~/Downloads/bbtex.bbpackage ~/Library/Application\ Support/BBEdit/Packages/
   ```

3. **Clear the download quarantine.** bbtex isn't signed with an Apple
   Developer ID yet, so macOS blocks a copy downloaded with a web browser and
   shows *"Apple could not verify “bbtex” is free of malware…"*. With BBEdit
   quit, run:

   ```sh
   xattr -dr com.apple.quarantine ~/Library/Application\ Support/BBEdit/Packages/bbtex.bbpackage
   ```

   Only do this for a package you downloaded from the release page above.
4. Open BBEdit. The **Scripts** menu now has a set of **LaTeX —** commands and a
   **LaTeX Editing** submenu.
5. Run **Scripts → LaTeX — Doctor**. It checks the TeX tools, Skim, the package
   and BBEdit's setup, without changing anything. Items marked `OPTIONAL` are
   fine to skip; fix anything marked `WARN`. If it prints a `[bbtex]` quarantine
   message instead, repeat step 3.

## Set up BBEdit and Skim

1. **Shortcuts.** In **BBEdit → Settings → Menus & Shortcuts**, scroll to
   **Scripts** and assign:

   | Script | Shortcut |
   |---|---|
   | LaTeX — Compile | <kbd>⌘K</kbd> |
   | LaTeX — Forward Search | <kbd>⇧⌘J</kbd> |
   | LaTeX — Compile With… | <kbd>⇧⌘K</kbd> |

   Remove any existing command that already uses one of those keys.
2. **Inverse search.** In **Skim → Settings → Sync**, choose the *Custom* preset,
   command `/usr/local/bin/bbedit`, arguments `--line %line "%file"`. If
   `/usr/local/bin/bbedit` doesn't exist, install BBEdit's command-line tools
   from **BBEdit → Install Command Line Tools…**.
3. **TexLab (optional).** If you installed `texlab`, open
   **BBEdit → Settings → Languages**, select **TeX**, and check that the
   language server is enabled and finds `texlab`.

## First build

1. Make a test folder with one file, `test.tex`:

   ```latex
   \documentclass{article}
   \usepackage{amsmath}
   \begin{document}
   \section{Hello}\label{sec:hello}
   Energy is
   \begin{equation}\label{eq:energy}
     E = mc^2
   \end{equation}
   See Section~\ref{sec:hello}.
   \end{document}
   ```

2. Open it in BBEdit and press <kbd>⌘K</kbd>. The first time, macOS may ask
   whether BBEdit may control Skim; allow it. Skim opens the PDF at the cursor
   without taking focus, and a notification reports the build.
3. **Errors.** Change `\section` to `\sectoin` and press <kbd>⌘K</kbd>. **LaTeX
   Results** opens with an error on line 4; click it to jump there. Fix it and
   build again: the error is gone.
4. **SyncTeX.** Put the cursor on the equation and press <kbd>⇧⌘J</kbd>; Skim
   highlights it. ⌘-click a word in Skim to jump back to BBEdit.
5. **Preview (needs Poppler).** Select `E = mc^2` and run
   **Scripts → LaTeX — Preview Selection**. A small window shows the rendered
   equation, and your selection stays in place.
6. **Outline.** Run **Scripts → LaTeX — Project Outline Window**, search for
   `energy`, and press Return to jump to the equation.

If each step works, the install is good.

## Optional extras

- **Preview on save.** Install the save attachment, then turn it on per file
  with **LaTeX — Toggle Preview on Save**:

  ```sh
  "$HOME/Library/Application Support/BBEdit/Packages/bbtex.bbpackage/Contents/Resources/install-preview-save-hook.sh" --apply
  ```

  It refuses to replace another tool's save attachment.
- **Right-click preview.** Add **LaTeX — Preview Selection** to BBEdit's
  Services menu:

  ```sh
  "$HOME/Library/Application Support/BBEdit/Packages/bbtex.bbpackage/Contents/Resources/bbtex" preview-service install
  ```

- **Live selection preview** needs nothing extra: run
  **LaTeX — Toggle Live Selection Preview**.

See [equation previews](selection-preview.md) for details.

## Upgrade or roll back

1. Quit BBEdit.
2. Move the installed `bbtex.bbpackage` somewhere safe (it's your rollback copy).
3. Install the new release as above, including the quarantine step.
4. Open BBEdit and run **LaTeX — Doctor** and one build.

To roll back, quit BBEdit, put the old package back in `Packages`, and reopen
BBEdit.

## Uninstall

1. Turn off **Preview on Save** and **Live Selection Preview** if you use them,
   close any bbtex preview windows, and quit BBEdit.
2. Remove the package:

   ```sh
   rm -rf ~/Library/Application\ Support/BBEdit/Packages/bbtex.bbpackage
   ```

3. If you installed the save attachment, remove
   `~/Library/Application Support/BBEdit/Attachment Scripts/Document.documentDidSave.scpt`
   and `Document.documentDidSave.scpt.bbtex-receipt`, but only if Doctor still identifies it as bbtex's
   unchanged hook. If another tool shares it, leave it for manual review.
4. If you installed the right-click service, remove
   `~/Library/Services/LaTeX — Preview Selection.workflow`.
5. Optionally delete bbtex's cache and state, `~/.local/state/bbtex`.

Your documents, PDFs and TeX installation are never touched.

## If something goes wrong

Start with [troubleshooting](setup-troubleshooting.md). If a step here doesn't
match what you see, that's a bug in these instructions:
[open an issue](https://github.com/LouLouLibs/bbtex/issues) and include the
Doctor report, plus your macOS, BBEdit and MacTeX versions.
