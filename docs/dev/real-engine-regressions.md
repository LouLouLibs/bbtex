# Real-engine regression checks

Run `dune build`, then `uv run test/integration/check_real_engines.py` for pdfLaTeX.
Use `--engine xelatex` or `--engine lualatex` to run the same corpus with those
engines. The selected engine, latexmk, BibTeX, Biber, and Poppler (`pdfinfo`,
`pdftotext`, `pdftoppm`) must be on PATH. Python runs through uv with explicit
script metadata. Required tools
must start successfully; the runner fails rather than silently skipping them.

The original, MIT-licensed fixtures live in `test/corpus`. Every run copies them
into a fresh directory containing spaces and Unicode. It never mutates
`examples/ui-check` or other user projects. Cases cover:

- A two-column article with shared external macros, accented text, BibTeX,
  references, root directives, and a separate output directory.
- A multi-file book with nested include paths, contents, biblatex/Biber, and
  Unicode bibliography metadata.
- A widescreen Beamer deck with fragile/verbatim content.
- Native Unicode/fontspec text under XeLaTeX and LuaLaTeX, using TeX-distributed
  Latin Modern font files without depending on OS font registration.
- A generated 40-file article, including outline/index coverage.
- Cropped preview geometry, PNG output, warm-cache reuse, external macro
  invalidation, and preservation of the compiled full-document PDF.
- Included-file diagnostics with exact line mapping and a successful rebuild.
- Cancellation of an actual looping TeX process and a subsequent successful build.

Checks compare required PDF text, page counts, geometry ranges, resolved references,
SyncTeX input records, and source/output isolation. They avoid cross-platform pixel
comparisons. PNG differences are used only within one run to establish that a
changed macro caused a new render.

Results remain under `dist/real-engines/ENGINE-*`, including copied source, build
outputs, command stdout/stderr, diagnostic scripts, and `report.json` with tool
versions, the selected engine, case timings and failure details. `--artifacts DIR` changes the parent
directory; each run creates a new child directory. The first passing local run
on 2026-09-22 took 14.6 seconds, excluding dependency installation.
The expanded Unicode-inclusive corpus took 16.2 seconds with XeLaTeX and
21.1 seconds with LuaLaTeX locally on the same date.

## CI tier

Locally, `scripts/ci.sh --engines` runs this corpus with the installed TeX Live
for pdfLaTeX, XeLaTeX and LuaLaTeX, and `--tectonic` adds the Tectonic tier with
a cached Biber 2.17, which the pinned bundle's biblatex requires; see
[CI and releases](releases.md). The GitHub workflow below is kept for manual
runs only.

**Real TeX engines** runs a three-job Ubuntu 24.04 matrix for pdfLaTeX, XeLaTeX,
and LuaLaTeX. Every job exercises BibTeX/Biber and the full shared corpus; the
two Unicode engines also run the fontspec fixture. Generated large-project and
cancellation fixtures explicitly select the requested engine. Each job uploads
its own `real-engines-ENGINE` artifact, and one failure does not cancel the other
jobs. TeX packages and Latin Modern fonts are explicit APT dependencies.
OCaml and dune come from opam with the same pinned compiler as the package
workflow. The workflow pins uv to 0.11.2;
APT package versions follow the Ubuntu repositories and runtime versions are
recorded in each report.

The workflow runs only when dispatched by hand. It uploads evidence on success or
failure for 14 days.

An additional Tectonic job runs `uv run test/integration/check_tectonic.py --bundle
https://data1.fullyjustified.net/tlextras-2022.0r0.tar --biber /path/to/compatible/biber`.
It downloads the official
0.17.0 Linux musl binary and verifies its release SHA-256. The dated bundle is
selected explicitly; resources are downloaded on demand on the fresh CI runner,
then each fixture is rebuilt with `--only-cached`. This checks Tectonic's cached
resource mode, not a network firewall. The bundle server remains a dependency;
the archive itself is not vendored or independently checksum-pinned here.

This tier covers the BibTeX article, biblatex/Biber book, Beamer and Unicode/fontspec,
PDF text/geometry, article/book SyncTeX, source/output isolation, and preview macro updates.
Tectonic intentionally renders previews afresh (no recorder manifest), and the
test asserts cache misses. It does not require `.bbl` persistence: Tectonic removes
intermediates by default; the bibliography is checked in the rendered PDF.
The tier also builds/indexes a generated 40-file project and cancels a real
Tectonic process after console evidence confirms TeX reached its infinite loop.
It verifies cancellation status, released ownership and a successful recovery build.
Readiness uses flushed console messages because Tectonic buffers virtual files
until processing finishes. The book checks rendered bibliography text, resolved
citations and actual external Biber invocation on both online and cached runs.

The pinned 2022 bundle contains biblatex 3.17 and is tested with Biber 2.17.
CI downloads the [official Biber 2.17 Linux release](https://sourceforge.net/projects/biblatex-biber/files/biblatex-biber/2.17/binaries/Linux/)
into runner temporary storage and checks SHA-256
`129d2e0332a57e985ffa253e5e9fbd28ef99af5a068d1b141145211969aa8999`.
The runner's `--biber` option creates a private executable link and changes PATH
only for its own subprocesses. Without it, the runner uses Biber from PATH and
fails if that version cannot launch or compile with the selected bundle.
This historical test dependency is separate from the supported MacTeX baseline
of Biber ≥ 2.21; do not replace system Biber with this older test tool.
The official macOS universal archive used locally has SHA-256
`182e1efa074d8a2a23a8893f2a22440d4e463cce55e4ed02076ac4c0ee0614b2`;
its arm64 slice in temporary storage passed the full tier in 14.1 seconds.
The existing local four-engine preview test remains available. Native BBEdit/Skim,
focus/selection, save attachments, and editing acceptance remain local checks;
Linux rendering success does not establish native macOS behavior.

## Findings from the first corpus run

Nested `\include{chapters/...}` failed with an isolated output directory on
latexmk 4.85: file-line diagnostics prevented its missing auxiliary-directory
recovery. bbtex now recognizes the specific missing `.aux` parent error, creates
only relative directories inside the configured output tree, and retries latexmk
with a forced build. It rejects traversal and symlink parents, and limits recovery
to 16 retries. Other compiler failures remain errors.

The local TeX Live 2024 universal Biber launcher also failed during its arm64
extraction before processing any bibliography. The local passing run used a
temporary arm64 extraction of the same Biber 2.20 executable, without replacing
the installed TeX tools. The Ubuntu job uses its native packaged Biber. This is a
local tool-launch issue to include in the planned doctor/troubleshooting work.

Tectonic's local book probe exposed a second, distinct Biber problem: the current
cached bundle supplies biblatex 3.17 / control-file version 3.8, while the working
temporary Biber 2.20 expects version 3.11. Tectonic does launch Biber automatically,
but that pair fails. Biber-book coverage needs a compatible pinned tool/bundle pair;
the Tectonic job now uses the isolated compatible pair described above. No
installed TeX tools were changed for this coverage work.
