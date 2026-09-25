# bbtex vs LaTeXTools and AUCTeX

This compares bbtex in BBEdit with the two editor integrations it is most often
measured against: [LaTeXTools](https://latextools.readthedocs.io/) for Sublime
Text and [AUCTeX](https://www.gnu.org/software/auctex/) (with RefTeX and
preview-latex) for Emacs. It describes what bbtex ships on `main` as of
2026-09-24; see the [handoff](dev/HANDOFF.md) for open work.

"Yes" means a supported, tested workflow. For LaTeXTools and AUCTeX it means
the stock package; many gaps there can be filled with user configuration.
bbtex relies on TexLab (through BBEdit's language-server support) for
as-you-type completion, and adds its own explicit commands on top.

## Build

| Feature | LaTeXTools | AUCTeX | bbtex |
|---------|-----------|--------|-------|
| latexmk builds | Yes (default) | Via add-on or custom command | Yes |
| pdfLaTeX / XeLaTeX / LuaLaTeX | Yes | Yes (`TeX-engine`) | Yes |
| Tectonic | No | Custom command | Yes, direct pipeline |
| BibTeX / Biber | Via latexmk | Via command chain | Via latexmk; tested with MacTeX Biber ≥ 2.21 |
| Named build variants | Builder settings | `TeX-command-list` | `.bbtex` profiles; **Compile With…** (⇧⌘K) |
| Extra compiler options | `%!TEX options` | `TeX-command-extra-options` | `options =` in `.bbtex` (global or per profile) |
| Output directory | `%!TEX output_directory` | `TeX-output-dir` | `output_directory =` in `.bbtex` |
| Jobname / aux directory | Yes | No | No |
| Save project files before build | Current file | Asks | Saves modified open project inputs |
| Cancel a build | Yes | Yes (`TeX-kill-job`) | Yes, whole process group |
| One build per project | No | Per buffer | Yes; builds, cleanup and previews serialize |
| Clean auxiliary files | Yes | Yes (`TeX-clean`) | **Clean** (keeps PDF) / **Clean All Build Output** |
| Build notification | Status bar | Mode line | Silent macOS notification with counts and duration |
| Custom builder plugins | Yes (Python API) | Yes (Emacs Lisp) | No; profiles cover engine and options |

## Project and document settings

| Feature | LaTeXTools | AUCTeX | bbtex |
|---------|-----------|--------|-------|
| `%!TEX root` | Yes | No | Yes, first 50 lines, `%!TEX` or `% !TEX` |
| `%!TEX program` / `TS-program` | Yes | No | Yes, including TeXShop engine names |
| Emacs `TeX-master` / `TeX-engine` | No | Yes | No |
| Project settings file | `.sublime-project` | `.dir-locals.el` | `.bbtex` (root, engine, output, options, profiles) |
| Guided setup | No | Asks for master on first build | **Configure Document…** writes root/program comments |
| Global user config | JSON settings | Emacs Lisp | No |
| Setup diagnostics | System check command | No | **LaTeX — Doctor** (tools, package layout, save hooks) |

## Errors and logs

| Feature | LaTeXTools | AUCTeX | bbtex |
|---------|-----------|--------|-------|
| Parse the TeX log | Regex-based | Regex-based | Single-pass OCaml parser with a file stack |
| 79-column line unwrapping | Partial | Yes | Yes |
| Jump to source | Output panel | ``C-c ` `` | BBEdit results browser |
| Warnings and bad boxes | Yes (toggle) | Yes (toggle) | **Show Build Results**, no rebuild |
| Full log | Yes | Yes | **Open Build Log** |
| Engine-tested diagnostics | Unknown | Unknown | pdfLaTeX, XeLaTeX, LuaLaTeX, Tectonic corpora |

## PDF viewing and SyncTeX

| Feature | LaTeXTools | AUCTeX | bbtex |
|---------|-----------|--------|-------|
| Forward search | Yes | Yes (`TeX-source-correlate-mode`) | Yes; updates Skim without taking focus |
| Inverse search | Yes | Yes (Emacs server) | Yes, after Skim's sync preference is set |
| Viewers | Skim, Preview, others | Any configured | Skim only |

## Navigation

| Feature | LaTeXTools | AUCTeX | bbtex |
|---------|-----------|--------|-------|
| Table of contents | Yes (`C-r`, project-wide) | RefTeX `C-c =` | **Project Outline Window**: persistent searchable tree, refreshes on save |
| Search sections, labels, equations, captions | Sections and labels | RefTeX TOC and labels | Yes, across included files, with `kind:` filters |
| Go to label definition | Yes | RefTeX | TexLab Go to Definition |
| Find references | Unknown | RefTeX | TexLab Find References |
| Jump to `\input` file | Yes | Partial | No dedicated command |
| Create missing included file | Yes | No | No |
| Stale-target protection | No | No | Jumps refuse changed or unsaved targets |

## Citations and references

| Feature | LaTeXTools | AUCTeX | bbtex |
|---------|-----------|--------|-------|
| Citation completion | Yes | RefTeX `C-c [` | TexLab completion (Edit → Complete) |
| Citation search picker | Quick panel | RefTeX regexp search | **Insert Citation**: key, author, title, year search; multiple keys |
| Accent- and case-insensitive search | Unknown | Partial | Yes |
| Reference completion | Yes | RefTeX `C-c )` | TexLab completion |
| Reference picker with context | Quick panel | RefTeX label menu | **Insert Reference**: label plus nearby text |
| Duplicate-key handling | Unknown | Warns | Refuses ambiguous keys |
| Fill-all / auto-trigger helpers | Yes | Partial | No; completion is invoked explicitly |

## Editing

| Feature | LaTeXTools | AUCTeX | bbtex |
|---------|-----------|--------|-------|
| Insert environment | Snippets | `C-c C-e` | Clippings |
| Change environment | Yes | `C-u C-c C-e` | **Change Environment**, one Undo, nested-aware |
| Toggle starred environment | Yes | Partial | **Toggle Starred Environment** |
| Close open environment | Yes | `C-c ]` | Close Environment clipping |
| Wrap selection | Yes | `C-c C-e` on region | **Wrap in Environment**; font/command clippings |
| Macro/package completion | CWL files | Style files | TexLab and BBEdit clippings |
| Math-mode-aware snippets | Yes | `LaTeX-math-mode` | No |
| Folding / prettified display | No | `TeX-fold-mode`, prettify | No |
| Package documentation | Yes (texdoc) | Yes (texdoc) | **Package Documentation** (texdoc) |

## Previews

| Feature | LaTeXTools | AUCTeX | bbtex |
|---------|-----------|--------|-------|
| Equation preview | Inline phantoms | Inline images (preview-latex) | Separate reusable BBEdit window |
| Preview uses document preamble | Configurable | Yes | Yes, main file's saved preamble |
| Preview follows cursor / typing | Yes (phantoms update) | On demand | Refresh on save (opt-in), or live selection (opt-in) |
| Cached rendering | Yes | Yes | Yes, keyed on inputs and `.fls` dependencies |
| Refresh when a macro file changes | No | No | Yes, for recorded inputs |
| Image preview on hover | Yes | No | No |
| Preview from the context menu | No | No | macOS Services action |

## Where bbtex is ahead

1. **Project safety.** Builds save the project's inputs, serialize per project,
   and cancel whole process groups. Outline jumps and picker insertions refuse
   stale targets instead of landing on the wrong line.
2. **Tectonic and TeXShop compatibility.** Tectonic has its own pipeline, and
   TeXShop's `TS-program` and engine names are accepted.
3. **Tested against real engines.** Log parsing and builds run against
   pdfLaTeX, XeLaTeX, LuaLaTeX and Tectonic corpora with BibTeX and Biber.
4. **Setup diagnostics.** Doctor checks tools, custom package layouts and
   save-hook integrity.
5. **Standalone CLI.** Every feature is a `bbtex` subcommand usable outside
   BBEdit.

## Where bbtex is behind

1. **Inline previews.** BBEdit has no API for images in the text view, so
   previews live in a separate window. Live selection mode (opt-in) can
   follow the selection in that window; there is still no inline rendering
   in the text view itself.
2. **As-you-type assistance.** Completion depends on TexLab and an explicit
   Complete command; there is no math-mode detection, fill-all helper or folding.
3. **Configuration breadth.** There is no global config file, no jobname or aux
   directory setting, and Skim is the only viewer.
4. **Extensibility.** LaTeXTools (Python) and AUCTeX (Emacs Lisp) let users
   write builders and commands; bbtex offers profiles and options only.
5. **Unsaved buffers.** The outline, pickers and previews read saved files. AUCTeX
   and LaTeXTools work from buffer contents.

## Candidate follow-ups

These gaps look worth closing; none is scheduled beyond the handoff list.

- A command to open the file under an `\input`/`\include` at the cursor.
- Unsaved-buffer snapshots for preview dependencies and the outline.
- `jobname` in `.bbtex`, if a real project needs it.

Deliberately out of scope: builder plugin APIs, viewers other than Skim, and
reimplementing completion that TexLab already provides.
