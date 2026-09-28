# Project-aware builds

⌘K saves the active document, then modified `.tex`, `.bib`, `.sty`, and `.cls`
files open under the project directory (and the explicit root), before building.
The project directory is the directory containing `.bbtex`, or the final root
file's directory when no configuration exists. Untitled files are not saved.
Save edits to `.bbtex` itself before compiling.

## Configuration

### Document comments: the TeXShop convention

`%!TEX root = ...` and `%!TEX program = ...` are editor instructions embedded
in ordinary LaTeX comments. The convention comes from TeXShop and is also used
by LaTeXTools. TeX itself ignores these lines; the editor/build wrapper reads
them. This is an editor convention, not an official LaTeX standard. AUCTeX's
`TeX-master` and `TeX-engine` local variables are a different format and are not
currently read by bbtex.

References: [TeXShop](https://pages.uoregon.edu/koch/texshop/) and
[LaTeXTools magic-comment support](https://latextools.readthedocs.io/en/latest/features/).
bbtex reads comments from the first 50 lines. Both `%!TEX` and `% !TEX` are
accepted, case-insensitively, as are `program` and TeXShop's `TS-program` alias.
The supported engine values are `pdflatex`, `xelatex`, `lualatex`, and
`tectonic`. TeXShop's built-in engine names are accepted too: `pdflatexmk`,
`latexmk` and `LaTeX` mean pdflatex, `xelatexmk` means xelatex, and `lualatexmk`
means lualatex. Other TeXShop engine scripts are not supported.
A UTF-8 byte-order mark before the first directive is ignored. The setup helper
normalizes these variants when replacing settings, avoiding duplicate directives.

For guided setup, press ⇧⌘K and choose **Configure Document…**. Choose whether
this file is the main document or select a main `.tex` file anywhere on disk.
The file chooser starts in the current source document's directory.
The engine picker explains the usual use cases; included files can inherit the
main document's engine. The helper saves your current edits, replaces the
root/program comments, and leaves the result unsaved for review. Press ⌘K to
save and compile. Project profile engines still take precedence.

For example, `tables/table1.tex` included by `main.tex` can start with:

```latex
%!TEX root = ../main.tex
```

The helper generates this relative path, including for main files outside the
current folder. A shared `.bbtex` root setting also works for files beneath its
directory.

#### Without a root comment

An Overleaf download or a fresh clone usually has no `% !TEX root`. When a file
names no main document (no `% !TEX root`, no `root =` in `.bbtex`) and has no
`\documentclass` itself, bbtex looks for the document that includes it: a `.tex`
file in the same folder or one folder up that has `\documentclass` and reaches
this file through literal `\input`, `\include` or `\subfile` commands.

- **Exactly one** includes it: bbtex builds that one and says so in the build
  notification ("[bbtex] Building ../main.tex, which includes this file").
- **Several** do: bbtex doesn't pick, since the same table can belong to more
  than one paper. It builds the file alone, as before, and the notification
  points to **Configure Document…** to choose.
- **None** does: the file is built on its own.

The search reads at most 64 `.tex` files per folder and follows at most 256
inputs from each candidate, skipping files over 4 MiB. `bbtex paths` and
Doctor show how the root was chosen (`root_source:`).

#### Build settings in comments

bbtex also reads the comments that change the build, so a document builds the
same way in TeXShop, LaTeXTools and BBEdit:

| Comment | From | Becomes |
|---|---|---|
| `% !TEX options = …` | LaTeXTools | extra compiler options |
| `% !TEX parameter = …` | TeXShop | extra compiler options, like `options` |
| `% !TEX output_directory = …` | LaTeXTools | the output folder, relative to the root file |
| `% !BIB TS-program = …` | TeXShop | checked against what latexmk ran (below) |

- **Order.** Each setting comes from its first comment along the
  source-to-root chain, as `program` does. Options are appended: `.bbtex`
  options, then the document's, then the selected profile's.
- **`.bbtex` wins** for the output folder. A comment naming a different one is
  reported as ignored. LaTeXTools' special folders (`<<temp>>` and the like)
  aren't supported.
- **Shell escape** (`-shell-escape`, `--enable-write18`) is never taken from a
  comment, since a downloaded document could otherwise run programs. The other
  options still apply, and bbtex says how to opt in: put the option in `.bbtex`.
  Options in comments are checked like `.bbtex` options, and a malformed one
  stops the build with the comment's file and line.
- **`% !BIB TS-program`**: latexmk runs BibTeX or Biber, whichever the document
  asks for (biblatex's `backend=` option decides), so `bibtex` and `biber` can't
  force either. After a build, bbtex checks which one ran and warns when it
  differs from the comment. `bibtex8`, `upbibtex` and `pbibtex` become
  latexmk's BibTeX program (not under Tectonic or RaTeX).
- `jobname`, `aux_directory`, `encoding` and `spellcheck` are not applied.

bbtex never ignores a comment silently: **LaTeX — Doctor** lists every
`% !TEX` and `% !BIB` comment in the file and its root, marked used, mapped or
ignored, with what to do instead. A build with a comment that doesn't fully
apply names it in the notification, and in LaTeX Results (with a `[bbtex]`
prefix) when the build fails. Editor settings such as `encoding` and
`spellcheck` appear only in Doctor. The
[comparison](editor-comparison.md#magic-comments) lists them side by side.

### Shared project settings

Put a file named `.bbtex` at the top of the project. This is bbtex's own format,
separate from TeXShop's comments. The format is plain
`key = value` lines, with optional profile sections. `#` and `;` start comment
lines. Path values are written literally, without surrounding quotes.

```ini
root = main.tex
engine = pdflatex
output_directory = build

[profile Draft]
engine = pdflatex
options = -halt-on-error

[profile XeLaTeX]
engine = xelatex

[profile Tectonic]
engine = tectonic
options = --reruns=1
```

`root` is relative to the configuration file. `output_directory` is relative to
the final root `.tex` file; omit it to write beside the root file. All profiles
share this output directory so results, cleanup, and forward search agree.
For nested `\include{chapters/...}` files, bbtex recovers missing auxiliary
subdirectories inside that output directory and retries latexmk. Recovery is
limited to 16 attempts and does not follow symlink parents or paths escaping
the output tree. Other write errors remain build failures.

Optionally add `default_profile = Draft` above the profile sections to use that
profile for ordinary ⌘K builds. Profile names are case-sensitive. Profiles can
override `engine` and append `options`; `root` and `output_directory` are global.

⇧⌘K lists the four engines and each named project profile. A selection applies
only to that build. Neither the source nor configuration is rewritten.

Engine precedence: explicit engine choice, selected/default profile engine,
first `%!TEX program` in the source-to-root chain, project engine, pdfLaTeX.
Options: `.bbtex`, then `% !TEX options` or `parameter`, then the profile.
Output folder: `.bbtex`, then `% !TEX output_directory`, then the root's folder.
A source `%!TEX root` takes precedence over the project's `root` setting.
Root directives can chain through files; a self-root is allowed, cycles and
missing or non-TeX roots produce an error. Symlinks resolve to the same root.

Options are passed as separate arguments, never evaluated by a shell. Use
`--option=value` for options taking values; quote values containing spaces inside
`options`. Engine, output-path, cleanup, and watch-mode flags are managed by
bbtex and cannot be supplied as extra options. Unknown settings and malformed
quotes fail before compilation.

## Running and cancelling

Build notifications show the root and engine, then elapsed time and diagnostics.
Only one build or cleanup may run for a given root. A second request reports
that the project is busy; it does not start another compiler. Different roots
can build independently.

Choose **LaTeX — Cancel Build** from any file resolving to the same root. It
requests cancellation from the running build, which stops the compiler's process
group, including TeX/BibTeX children. A process that ignores the initial stop
signal is forcibly stopped after one second. The project lock is then released.
This cancellation does not use PID files to signal arbitrary processes.

**LaTeX — Open Build Log** opens the current root's compiler log. Logs and
cancellation state live in `~/.local/state/bbtex` by default, keyed by canonical
root path; `BBTEX_STATE_DIR` overrides that location. CLI use also respects
`XDG_STATE_HOME` when `BBTEX_STATE_DIR` is unset.

## Cleanup

**LaTeX — Clean** removes auxiliary output with `latexmk -c`, preserving the PDF.
**LaTeX — Clean All Build Output** uses `latexmk -C` to also remove the PDF; the
BBEdit command asks before doing so. Both use the configured output directory
and refuse to run during an active build. Cleanup requires latexmk, including
for projects compiled with Tectonic.

## Command line

```sh
bbtex profiles chapter.tex
bbtex paths --profile Draft chapter.tex
bbtex compile --profile Draft chapter.tex
bbtex cancel chapter.tex
bbtex clean chapter.tex
bbtex clean-all chapter.tex
```

Compile exit codes: 0 success, 1 compilation errors, 2 setup/busy failure,
3 cancelled. The output protocol includes root, engine, duration, and build_log.

## Checks

```sh
dune runtest
uv run test/integration/check_build_workflow.py
uv run test/integration/check_project_builds.py
uv run test/integration/check_project_saving.py
uv run test/integration/check_live_compile.py
```

The cancellation check needs permission to signal its own compiler process group.
The last two checks create disposable documents and require BBEdit/Skim scripting.
## Experimental RaTeX placeholder

`ratex` is accepted in the compiler picker, Configure Document, `.bbtex`
engine settings, and `% !TEX program = ratex`. It refers to
[leoliu0/ratex](https://github.com/leoliu0/ratex), the full-document compiler.
This is an optional experimental integration; bbtex does not install RaTeX or
change the default engine. Its documented command is invoked directly with
`-pdf -interaction=nonstopmode -output-directory=…`.

Actual RaTeX rendering, package compatibility, diagnostics and SyncTeX remain
unverified. Keep using your established engine for normal work until RaTeX
matures. The placeholder can also render snippets if a compatible `ratex`
executable is installed; its snippet results are not cached.
