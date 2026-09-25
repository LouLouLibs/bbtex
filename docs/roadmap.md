# Roadmap

**Current:** v0.1.0 · **Next:** v0.2 · **Updated:** 2026-09-25 {.meta}

What's next for bbtex, roughly in order. v0.2 is about two things: meeting
documents that come from TeXShop, LaTeXTools or Overleaf where they are, and
explaining errors in plain English. Nothing here is promised by a date; it's
vibe coded, so it moves when I have time to try things out.

## Finishing v0.1.0

v0.1.0 is [released](https://github.com/LouLouLibs/bbtex/releases/tag/v0.1.0) (2026-09-25). The repository is public and these docs are at
[louloulibs.github.io/bbtex](https://louloulibs.github.io/bbtex/); a copy is
mirrored to UMN's GitHub (login required). Still to do:

- **Walk through a clean install** on a fresh macOS account using only the
  release instructions: install, compile, preview, upgrade or roll back,
  uninstall ([checklist](setup-troubleshooting.md#fresh-account-or-fresh-mac-acceptance)).

## v0.2

Tracked in the [v0.2 milestone](https://github.com/LouLouLibs/bbtex/milestone/1), with [#34](https://github.com/LouLouLibs/bbtex/issues/34) as the tracking issue.

### Warn about magic comments bbtex ignores

Issue [#29](https://github.com/LouLouLibs/bbtex/issues/29).

Documents written for TeXShop or LaTeXTools often carry `% !TEX` lines that
bbtex doesn't read (see [the comparison](editor-comparison.md#magic-comments)).
Ignoring them silently is the worst option: `% !TEX options = --shell-escape`
that quietly does nothing looks like a bbtex bug.

- **Doctor** lists every `% !TEX` and `% !BIB` line in the file and its root,
  marked as used, mapped (below) or ignored, with what to do instead.
- **Builds** mention ignored lines once, in the build notification or as a
  `[bbtex]` note in LaTeX Results, so you see it without running Doctor.

### Read the comments that change the build

Issue [#30](https://github.com/LouLouLibs/bbtex/issues/30).

Map the build-relevant comments onto settings bbtex already has, so the same
document builds the same way in TeXShop, LaTeXTools and BBEdit:

| Comment | From | Becomes |
|---|---|---|
| `% !TEX options = …` | LaTeXTools | extra compiler options (`options =`) |
| `% !TEX parameter = …` | TeXShop | extra compiler options |
| `% !TEX output_directory = …` | LaTeXTools | `output_directory =` |
| `% !BIB TS-program = bibtex` / `biber` | TeXShop | tell latexmk which one to run |
| `% !TEX jobname = …` | LaTeXTools | maybe, if it survives SyncTeX, results and cleanup end to end |

Open question: when a comment and `.bbtex` disagree, which wins? The likely
answer is the same order bbtex uses for engines: an explicit profile, then the
document, then the project file.

Still out: TeXShop engine scripts (arbitrary shell scripts that bypass bbtex's
log parsing and cancellation), `spellcheck` (BBEdit has its own), and TeXShop's
window settings.

### Plain-English error explanations, always marked `[bbtex]`

Issue [#31](https://github.com/LouLouLibs/bbtex/issues/31).

Overleaf's best trick is telling you what an error usually means. bbtex's log
parser already classifies errors, so it can add a short explanation under the
ones it recognises. The rule: **TeX's own message is never changed**, and every
added line starts with `[bbtex]`, so it's always clear which words came from
TeX and which from bbtex.

```
Error: File model.tex; Line 7:
  Undefined control sequence.
  [bbtex] A command isn't defined: check for a typo, or a missing \usepackage.
```

A first set to cover, each with a test log in the corpus:

- `Undefined control sequence`: a typo or a missing package
- `Missing $ inserted`: math outside math mode, often `_` or `^` in text
- ``File `….sty' not found``: install the package (`tlmgr install …`)
- `Environment … undefined`: a missing package or a misspelled name
- `Missing \begin{document}`: stray text in the preamble
- `Runaway argument` / `File ended while scanning`: an unclosed brace
- `Extra }` / `Too many }'s`: unbalanced braces
- `Misplaced alignment tab character &`: `&` outside a table or `align`
- citations or references undefined after a build: rerun, or check the key
- fontspec or `\setmainfont` under pdfLaTeX: switch to XeLaTeX or LuaLaTeX
- packages that need `--shell-escape` (minted, …): add it to `options`
- Biber/biblatex version mismatch (Doctor already detects this)

The same lines appear in `bbtex results` and `bbtex parse-log`. They stay short,
never guess, and are skipped when the error isn't recognised.

### Find the main file without being told

Issue [#32](https://github.com/LouLouLibs/bbtex/issues/32).

Overleaf just knows which file is the main document; an Overleaf zip or a
fresh clone should build in bbtex without adding `% !TEX root` first. When a
file has no `% !TEX root`, no `.bbtex` and no `\documentclass`, bbtex would
look for `.tex` files next to it (and one level up) that have `\documentclass`
and include this file. If exactly one matches, build that, and say so in the
notification. If there are several, ask through **Configure Document…**, as
today. No guessing when it's ambiguous: the same table can belong to more than
one paper.

### Check and document `latexmkrc`

Issue [#33](https://github.com/LouLouLibs/bbtex/issues/33).

Overleaf projects often ship a `latexmkrc`. bbtex runs latexmk from the main
file's folder, so latexmk should already read it; the one catch is that
bbtex's `-outdir` overrides an `$out_dir` set there. Confirm with a test, and
document what wins.

## After v0.2

Smaller things already on the list:

- **Unsaved buffers.** Previews and the outline read saved files; snapshot
  unsaved dependency edits instead.
- **Outline state** that survives closing and reopening the window.
- **Open the file under `\input`/`\include`** at the cursor.
- **A richer citation picker.**
- **Compile on save** (opt-in), reusing the cancellation and one-build-per-project
  machinery. It has to replace ⌘K builds rather than run alongside them.
- **Word count** via `texcount`.
- **Live selection polish**: measure capturing the text before the selection on
  multi-megabyte documents; clearer wording when a save cancels a render; stop
  renders queued behind a long build when live mode is turned off; ignore a
  literal `\begin{document}` inside a comment when detecting math.
- **Tests**: move the six Python checks that only exercise the binary
  (project builds, preview, preview cancellation, real engines, Tectonic,
  TexLab) to dune cram tests where practical, and make `check_live_preview.py`
  wait on state like `check_live_selection.py` does, since it flakes on timing.

## Not planned

To be upfront about what bbtex won't try to be:

- Overleaf's collaboration features: real-time co-editing, comments, track
  changes. Git and BBEdit cover history.
- A rich-text or visual editor, cloud builds, or built-in AI features.
- Running TeXShop engine scripts, or viewers other than Skim.
- Reimplementing completion that TexLab already provides.

Have an idea, or hit something that isn't here?
[Open an issue](https://github.com/LouLouLibs/bbtex/issues).
