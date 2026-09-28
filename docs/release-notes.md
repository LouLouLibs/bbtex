**bbtex v0.2.0** meets documents from TeXShop, LaTeXTools and Overleaf where
they are, and explains common LaTeX errors in plain English. Like everything
here, it is totally vibe coded; see
[About bbtex](https://louloulibs.github.io/bbtex/about#totally-vibe-coded).

**Plain-English error hints.** Under the errors it recognises, bbtex adds one
short line starting with `[bbtex]`, for example "A command isn't defined:
check for a typo, or a missing \usepackage." TeX's own message is never
changed, and unrecognised errors get nothing. The first set covers undefined
commands and environments, missing `$`, missing packages (with the
`tlmgr search` command that finds them), runaway arguments, unbalanced braces,
misplaced `&`, undefined references and citations, fontspec under pdfLaTeX,
packages that need shell escape, and Biber/biblatex mismatches. Hints appear
in LaTeX Results and `bbtex parse-log`.

**Build settings in comments.** LaTeXTools' `% !TEX options` and
`output_directory`, TeXShop's `% !TEX parameter` and `% !BIB TS-program` now
apply to builds. `.bbtex` wins where both set the output folder; options add
up (`.bbtex`, the document, then the profile). Shell escape is never taken
from a comment: a downloaded document could otherwise run programs, so it
has to come from `.bbtex`. latexmk still picks BibTeX or Biber from the
document, and bbtex warns when the comment disagrees with what ran. See
[build settings in comments](https://louloulibs.github.io/bbtex/project-builds#build-settings-in-comments).

**No silently ignored comments.** Doctor lists every `% !TEX` and `% !BIB`
comment in a file and its root as used, mapped or ignored, with what to do
instead. Builds with a comment that doesn't fully apply say so in the
notification, and in LaTeX Results when they fail.

**The main file without a root comment.** A file that names no main document
and has no `\documentclass` of its own builds the one document nearby (same
folder or one up) that includes it, as in an Overleaf project, and the
notification says which. When several documents include it, bbtex doesn't
guess and points to **Configure Document…**. `bbtex paths` reports how the
root was chosen. See
[without a root comment](https://louloulibs.github.io/bbtex/project-builds#without-a-root-comment).

**Project `latexmkrc`.** A project or user `latexmkrc` is read as latexmk
always does (`TEXINPUTS` paths and custom compiler commands apply); bbtex
keeps its own output folder, auxiliary folder and engine, and Doctor and the
build notification say when it replaces an rc setting. See
[a project latexmkrc](https://louloulibs.github.io/bbtex/project-builds#a-project-latexmkrc).

Fixed:

- A `latexmkrc` that set `$aux_dir` moved the LaTeX log away from the output
  folder, so builds reported no errors (or stale ones) and Show Build Results
  failed. bbtex now keeps auxiliary files with the output.

Current releases support Apple Silicon (`arm64`). Extract the ZIP and install
`bbtex.bbpackage`, replacing v0.1.0; see the
[install guide](https://louloulibs.github.io/bbtex/install). Packages are built
and tested on the macOS version of the Mac that ran the release checks; older
versions are unverified.
