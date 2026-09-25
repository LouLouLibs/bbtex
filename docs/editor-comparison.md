# bbtex vs TeXShop, LaTeXTools and AUCTeX

How bbtex in BBEdit compares with the editors people usually mean when they
say "a good LaTeX setup": [TeXShop](https://pages.uoregon.edu/koch/texshop/)
(the Mac's own LaTeX editor, with its built-in PDF viewer),
[LaTeXTools](https://latextools.readthedocs.io/) for Sublime Text, and
[AUCTeX](https://www.gnu.org/software/auctex/) (with RefTeX and preview-latex)
for Emacs. It describes bbtex v0.1.0; see the [handoff](dev/HANDOFF.md) for
open work.

"Yes" means a supported workflow in the stock package; many gaps in the other
tools can be filled with configuration or engine scripts. The bbtex column is
checked against the code and tests. The others come from each project's
documentation, and "Unknown" means I haven't confirmed it. Corrections are
welcome. bbtex relies on TexLab (through BBEdit's language-server support) for
as-you-type completion and adds its own explicit commands on top.

## Magic comments

TeXShop started the `% !TEX` convention; LaTeXTools adopted and extended it.
bbtex reads **only `root` and `program`** (plus TeXShop's `TS-program`
spelling). Everything else a TeXShop or LaTeXTools document might carry is
ignored, and settings like extra options or an output directory go in a
[`.bbtex` file](project-builds.md#shared-project-settings) instead.

| Comment | TeXShop | LaTeXTools | bbtex |
|---------|---------|-----------|-------|
| `% !TEX root = …` | Yes | Yes | Yes, in the first 50 lines, `%!TEX` or `% !TEX` |
| `% !TEX TS-program = …` | Yes | Yes | Yes, as an alias of `program` |
| `% !TEX program = …` | No | Yes | Yes |
| TeXShop engine names (`pdflatexmk`, `xelatexmk`, …) | Yes (engine scripts) | Unknown | Built-in names map to pdfLaTeX, XeLaTeX, LuaLaTeX; custom engine scripts are not run |
| `% !TEX encoding = …` | Yes | No | Parsed but not used |
| `% !TEX spellcheck = …` | Yes | Yes | No |
| `% !TEX parameter = …` | Yes | No | No |
| `% !BIB TS-program = …` | Yes | No | No; latexmk picks BibTeX or Biber |
| `% !TEX options = …` | No | Yes | No; use `options =` in `.bbtex` |
| `% !TEX output_directory = …` | No | Yes | No; use `output_directory =` in `.bbtex` |
| `% !TEX jobname = …` / `aux_directory` | No | Yes | No |
| Emacs `TeX-master` / `TeX-engine` | No | No | No (AUCTeX's own format) |

## Build

| Feature | TeXShop | LaTeXTools | AUCTeX | bbtex |
|---------|---------|-----------|--------|-------|
| One-key build | ⌘T (Typeset) | ⌘B | `C-c C-c` | ⌘K |
| latexmk builds | Via `…mk` engine scripts | Yes (default) | Via add-on or custom command | Yes |
| pdfLaTeX / XeLaTeX / LuaLaTeX | Yes | Yes | Yes (`TeX-engine`) | Yes |
| Tectonic | Custom engine script | No | Custom command | Yes, direct pipeline |
| BibTeX / Biber | Separate command, or latexmk engines | Via latexmk | Via command chain | Via latexmk; tested with MacTeX Biber ≥ 2.21 |
| Named build variants | Engine menu | Builder settings | `TeX-command-list` | `.bbtex` profiles; **Compile With…** (⇧⌘K) |
| Save before build | Current file | Current file | Asks | Saves modified open project inputs |
| Cancel a build | Yes (Abort) | Yes | Yes (`TeX-kill-job`) | Yes, whole process group |
| Clean auxiliary files | Yes (Trash Aux Files) | Yes | Yes (`TeX-clean`) | **Clean** (keeps PDF) / **Clean All Build Output** |
| Custom build logic | Engine shell scripts | Python builders | Emacs Lisp | No; profiles cover engine and options |

## Project settings

| Feature | TeXShop | LaTeXTools | AUCTeX | bbtex |
|---------|---------|-----------|--------|-------|
| Main file for included files | `% !TEX root` | `% !TEX root`, project file | `TeX-master` | `%!TEX root` or `root =` in `.bbtex` |
| Project settings file | No | `.sublime-project` | `.dir-locals.el` | `.bbtex` (root, engine, output, options, profiles) |
| Guided setup | No | No | Asks for master on first build | **Configure Document…** writes root/program comments |
| Global user config | Preferences | JSON settings | Emacs Lisp | No |
| Setup diagnostics | No | System check command | No | **LaTeX — Doctor** |

## Errors and logs

| Feature | TeXShop | LaTeXTools | AUCTeX | bbtex |
|---------|---------|-----------|--------|-------|
| Error list | Console output | Output panel | ``C-c ` `` | BBEdit results browser |
| Jump to the source line | Unknown | Yes | Yes | Yes, click the entry |
| Warnings and bad boxes | In the log | Yes (toggle) | Yes (toggle) | **Show Build Results**, no rebuild |
| Full log | Yes | Yes | Yes | **Open Build Log** |
| 79-column line unwrapping | Unknown | Partial | Yes | Yes |

## PDF viewing and SyncTeX

| Feature | TeXShop | LaTeXTools | AUCTeX | bbtex |
|---------|---------|-----------|--------|-------|
| Viewer | Built-in (external optional) | Skim, Preview, others | Any configured | Skim |
| Forward search | Yes | Yes | Yes (`TeX-source-correlate-mode`) | Yes; updates Skim without taking focus |
| Inverse search | Yes (⌘-click) | Yes | Yes (Emacs server) | Yes (⌘-click), after Skim's sync setting |

## Navigation

| Feature | TeXShop | LaTeXTools | AUCTeX | bbtex |
|---------|---------|-----------|--------|-------|
| Section list | Tags menu (current file) | Yes (project-wide) | RefTeX `C-c =` | **Project Outline Window**, project-wide, refreshes on save |
| Search labels, equations, captions | Unknown | Sections and labels | RefTeX TOC and labels | Yes, across included files, with `kind:` filters |
| Go to label definition | No | Yes | RefTeX | TexLab Go to Definition |
| Jump to an `\input` file | Unknown | Yes | Partial | No dedicated command |
| Stale-target protection | No | No | No | Jumps refuse changed or unsaved targets |

## Citations and references

| Feature | TeXShop | LaTeXTools | AUCTeX | bbtex |
|---------|---------|-----------|--------|-------|
| Citation completion | Unknown (BibDesk integration) | Yes | RefTeX `C-c [` | TexLab completion |
| Citation search picker | Unknown | Quick panel | RefTeX regexp search | **Insert Citation**: key, author, title, year; multiple keys |
| Accent- and case-insensitive search | Unknown | Unknown | Partial | Yes |
| Reference picker with context | Unknown | Quick panel | RefTeX label menu | **Insert Reference**: label plus nearby text |
| Duplicate-key handling | Unknown | Unknown | Warns | Refuses ambiguous keys |

## Editing

| Feature | TeXShop | LaTeXTools | AUCTeX | bbtex |
|---------|---------|-----------|--------|-------|
| Insert environment | Macros, command completion | Snippets | `C-c C-e` | Clippings |
| Change environment | No | Yes | `C-u C-c C-e` | **Change Environment**, one undo, nested-aware |
| Toggle starred environment | No | Yes | Partial | **Toggle Starred Environment** |
| Wrap selection | Macros | Yes | `C-c C-e` on region | **Wrap in Environment**; clippings |
| Command completion | Yes (Esc, completion list) | CWL files | Style files | TexLab and BBEdit clippings |
| Symbol palettes | Yes (LaTeX and Matrix panels) | No | Math menu | No |
| Folding | Unknown | No | `TeX-fold-mode` | No |
| Package documentation | Yes (texdoc) | Yes (texdoc) | Yes (texdoc) | **Package Documentation** (texdoc) |

## Previews

| Feature | TeXShop | LaTeXTools | AUCTeX | bbtex |
|---------|---------|-----------|--------|-------|
| Equation preview | Unknown | Inline phantoms | Inline images (preview-latex) | Separate reusable BBEdit window |
| Uses the document preamble | Unknown | Configurable | Yes | Yes, the main file's saved preamble |
| Follows the cursor or selection | No | Yes (phantoms update) | On demand | Refresh on save or live selection (both opt-in) |
| Refresh when a macro file changes | No | No | No | Yes, for recorded inputs |
| Image preview on hover | No | Yes | No | No |

## Where bbtex is ahead

1. **Your editor stays BBEdit.** TeXShop is a good LaTeX editor, but if you
   already live in BBEdit, bbtex brings builds, SyncTeX and previews to it
   instead of asking you to switch.
2. **Project safety.** Builds save the project's inputs, run one at a time per
   project, and cancel whole process groups. Outline jumps and picker
   insertions refuse stale targets instead of landing on the wrong line.
3. **Project-wide tools.** The outline, pickers and previews follow `\input`
   and `\include` across the whole project.
4. **Tested against real engines.** Builds and log parsing run against
   pdfLaTeX, XeLaTeX, LuaLaTeX and Tectonic corpora with BibTeX and Biber.
5. **Standalone CLI and Doctor.** Every feature is a `bbtex` subcommand, and
   Doctor checks the setup.

## Where bbtex is behind

1. **Magic comments.** Only `root` and `program` are read. TeXShop's
   `spellcheck`, `parameter` and `% !BIB`, and LaTeXTools' `options`,
   `output_directory` and `jobname`, are ignored.
2. **No built-in viewer.** TeXShop has its own PDF window; bbtex needs Skim.
3. **Inline previews.** BBEdit has no API for images in the text view, so
   previews live in a separate window.
4. **As-you-type help.** Completion depends on TexLab and an explicit Complete
   command; there are no symbol palettes, math-mode snippets or folding.
5. **Extensibility.** TeXShop engine scripts, LaTeXTools builders and AUCTeX's
   Emacs Lisp let you script your own builds; bbtex has profiles and options.
6. **Unsaved buffers.** The outline, pickers and previews read saved files.

## Candidate follow-ups

- Read more of the magic comments TeXShop and LaTeXTools users already have
  (`options` and `output_directory` are the likely ones), mapping them onto
  the existing `.bbtex` settings.
- A command to open the file under an `\input`/`\include` at the cursor.
- Unsaved-buffer snapshots for preview dependencies and the outline.

Deliberately out of scope: builder plugin APIs, running TeXShop engine
scripts, viewers other than Skim, and reimplementing completion that TexLab
already provides.
