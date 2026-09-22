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

**Real TeX engines** runs a three-job Ubuntu 24.04 matrix for pdfLaTeX, XeLaTeX,
and LuaLaTeX. Every job exercises BibTeX/Biber and the full shared corpus; the
two Unicode engines also run the fontspec fixture. Generated large-project and
cancellation fixtures explicitly select the requested engine. Each job uploads
its own `real-engines-ENGINE` artifact, and one failure does not cancel the other
jobs. TeX packages and Latin Modern fonts are explicit APT dependencies.
Ubuntu supplies [Dune 3.14](https://packages.ubuntu.com/noble/ocaml/ocaml-dune),
which meets this repository's Dune requirement. The workflow pins uv to 0.11.2;
APT package versions follow the Ubuntu repositories and runtime versions are
recorded in each report.

The job runs on relevant source/corpus/workflow changes, version tags, and manual
workflow dispatch. It uploads evidence on success or failure for 14 days. The
existing two-architecture macOS package workflow stays separate and fast. Draft
release creation currently waits for those package jobs; verify this real-engine
workflow for the same commit before publishing a release.

An additional Tectonic job runs `uv run test/integration/check_tectonic.py --bundle
https://data1.fullyjustified.net/tlextras-2022.0r0.tar`. It downloads the official
0.17.0 Linux musl binary and verifies its release SHA-256. The dated bundle is
selected explicitly; resources are downloaded on demand on the fresh CI runner,
then each fixture is rebuilt with `--only-cached`. This checks Tectonic's cached
resource mode, not a network firewall. The bundle server remains a dependency;
the archive itself is not vendored or independently checksum-pinned here.

This narrower tier covers the BibTeX article, Beamer and Unicode/fontspec, PDF
text/geometry, article SyncTeX, source/output isolation, and preview macro updates.
Tectonic intentionally renders previews afresh (no recorder manifest), and the
test asserts cache misses. It does not require `.bbl` persistence: Tectonic removes
intermediates by default; the bibliography is checked in the rendered PDF.
Reports explicitly list omitted Biber-book, cancellation and large-project cases.
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
it is not claimed by the Tectonic job. No installed TeX tools were changed.
