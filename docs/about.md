# About bbtex

## Why this exists

I write my papers in BBEdit. It's a great editor, but for LaTeX I kept
missing what other editors have: LaTeXTools in Sublime, AUCTeX in Emacs. One
key to build, errors you can click, a PDF that follows the cursor, equations
you can check without recompiling forty pages.

bbtex brings those things to BBEdit while staying out of the way. It uses
BBEdit's own Scripts menu, results browser and preview windows, so it should
feel like part of the editor rather than a plugin bolted on.

## Totally vibe coded

bbtex is **vibe coded, top to bottom**. I didn't write the code. An AI coding
agent ([Claude Code](https://claude.com/claude-code)) wrote all of it: the
OCaml, the bash and AppleScript glue, the tests, and the docs you're reading.
My part was deciding what it should do, trying it in BBEdit, and pushing back
when something felt wrong.

To keep that honest, the project leans on process:

- **House rules for the agent.** [AGENTS.md](../AGENTS.md) says what goes where:
  logic in the OCaml binary, only thin glue in bash, no shipped Python, and how
  to test.
- **Lots of tests.** Unit and cram tests, a local CI script, real-engine runs
  with pdfLaTeX, XeLaTeX, LuaLaTeX and Tectonic (with BibTeX and Biber), and
  native tests that drive a real BBEdit window.
- **Reviews.** Bigger features go through a written plan, a review of each
  step, and a final review of the whole branch before they're merged.

That still doesn't make it bulletproof. Keep your papers in version control,
and if bbtex does something surprising, please
[open an issue](https://github.com/LouLouLibs/bbtex/issues).

## Where things stand: v0.1.0

This is the first release. What I'd call solid:

- builds with latexmk and Tectonic, with errors in the results browser
- SyncTeX with Skim in both directions
- equation previews, including refresh on save and live selection
- the project outline, and the citation and reference pickers
- environment editing, the clippings, and Doctor

What to know before you try it:

- It's tested on Apple Silicon only, on the macOS version I run. Intel builds
  aren't checked.
- A clean install on a brand-new Mac account hasn't been walked through yet.
  If you're the first, [the checklist](setup-troubleshooting.md#fresh-account-or-fresh-mac-acceptance)
  is there, and I'd love to hear how it went.
- Previews read your **saved** preamble; unsaved edits in other files aren't
  picked up yet.
- The RaTeX engine option is an experimental placeholder. Stick with pdfLaTeX,
  XeLaTeX, LuaLaTeX or Tectonic.

The [release notes](changelog.md) have the details, and
[how it compares](editor-comparison.md) lists what LaTeXTools and AUCTeX still
do better.

## Thanks

bbtex stands on other people's work:

- The editing clippings and stationery come from the old **Latex.bbpackage**
  ([notices](https://github.com/LouLouLibs/bbtex/blob/main/support/THIRD-PARTY-NOTICES.md)).
- [TexLab](https://github.com/latex-lsp/texlab) provides completion and
  navigation through BBEdit's language-server support.
- Equation previews crop with AUCTeX's `preview.sty` and convert with Poppler.
- Citation search uses [bibtexparser-ml](https://github.com/LouLouLibs/bibtexparser-ml),
  an OCaml port of python-bibtexparser's splitter (vibe coded too).
- [Skim](https://skim-app.sourceforge.io/) makes SyncTeX on the Mac pleasant.

bbtex is part of [LouLouLibs](https://github.com/LouLouLibs) and is MIT
licensed.
