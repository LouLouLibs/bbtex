# Roadmap

**Current:** v0.2.0 · **Next:** after v0.2 · **Updated:** 2026-09-28 {.meta}

What's next for bbtex, roughly in order. v0.2 is about two things: meeting
documents that come from TeXShop, LaTeXTools or Overleaf where they are, and
explaining errors in plain English. Nothing here is promised by a date; it's
vibe coded, so it moves when I have time to try things out.

## Finishing v0.1.0

v0.1.0 is [released](https://github.com/LouLouLibs/bbtex/releases/tag/v0.1.0) (2026-09-25). The repository is public and these docs are at
[louloulibs.github.io/bbtex](https://louloulibs.github.io/bbtex/); a copy is
mirrored to UMN's GitHub (login required). Still to do:

- **Walk through a clean install** on a fresh macOS account, following the
  [clean install walkthrough](install.md) exactly.
- **Sign and notarize the binary.** Until bbtex is signed with an Apple
  Developer ID and notarized, a browser download is quarantined and blocked;
  users have to clear it with `xattr` (the walkthrough and Doctor explain how).

## v0.2

v0.2.0 meets TeXShop, LaTeXTools and Overleaf documents where they are. Tracked in
the [v0.2 milestone](https://github.com/LouLouLibs/bbtex/milestone/1), with
[#34](https://github.com/LouLouLibs/bbtex/issues/34) as the tracking issue.

- **Magic comments bbtex doesn't apply are reported, never dropped silently**
  ([#29](https://github.com/LouLouLibs/bbtex/issues/29)). Doctor lists every
  `% !TEX` and `% !BIB` comment as used, mapped or ignored, and builds name
  the ones that don't fully apply with a `[bbtex]` note.
- **Build settings in comments** ([#30](https://github.com/LouLouLibs/bbtex/issues/30)):
  `options`, `parameter`, `output_directory` and `% !BIB TS-program` map onto
  bbtex's settings; `.bbtex` wins, and shell escape only comes from `.bbtex`.
  See [build settings in comments](project-builds.md#build-settings-in-comments).
- **Plain-English error hints** ([#31](https://github.com/LouLouLibs/bbtex/issues/31)):
  a `[bbtex]` line under the errors bbtex recognises, in LaTeX Results and
  `bbtex parse-log`. TeX's own message is never changed.
- **The main file without a root comment** ([#32](https://github.com/LouLouLibs/bbtex/issues/32)):
  a file that names no main document builds the one document nearby that
  includes it, as in an Overleaf project. See
  [without a root comment](project-builds.md#without-a-root-comment).
- **Project `latexmkrc`** ([#33](https://github.com/LouLouLibs/bbtex/issues/33)):
  read as latexmk always does; bbtex keeps its output folder, auxiliary folder
  and engine, and says so. An rc `$aux_dir` no longer hides build errors. See
  [a project `latexmkrc`](project-builds.md#a-project-latexmkrc).

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
