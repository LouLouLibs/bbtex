# BBEdit LaTeX handoff — updated 2026-09-23

## Issue #1: persistent-outline navigation prototype

After synchronizing Claude's merged changes through `ae6567d`, added an isolated
`outline-window-prototype FILE PRIVATE_TEMP_DIR` capability proof. Existing menu
and source-index contract remain unchanged. OCaml serves a token-scoped loopback
endpoint; HTML form buttons invoke existing `Outline.jump` validation. No request
can choose a file path or executable. Saved snapshot entries are indented, not yet
an expandable/filterable tree. See `docs/outline-window-prototype.md`.

Unit checks cover escaped markup and method/token/entry/Host/Origin restrictions.
Disposable native checks pass for window reuse, exact jumps, dirty/stale rejection
and closing the window stopping the worker. Found that a closed BBEdit preview can
keep its JavaScript alive: heartbeat alone is insufficient, so this prototype also
uses bounded window-list checks every two seconds. Evaluate this tradeoff before
installing a production menu. Real click/Return acceptance has been requested with
the disposable `/tmp/bbtex-outline-demo.vw96At` project; do not claim it until answered.

Remaining issue #1 work: tree/state model, filter/navigation UI, refresh and
project-switching semantics, production lifecycle and packaging. Preserve user's
sample edit and the newer local-CI/opam/no-shipped-Python architecture.

## Tectonic Biber coverage — 2026-09-23

The Tectonic runner now requires a working compatible Biber and exercises the
multi-file biblatex book online and cached, alongside all prior cases. A `--biber`
argument exposes an explicit executable only in the test subprocess PATH; no
installed tool or user shell configuration is changed. Version/path evidence is
recorded, final citations must converge, bibliography text must appear in the
PDF, external Biber invocation and included-chapter SyncTeX are asserted.

Verified pair: Tectonic 0.17.0, tlextras-2022.0r0 (biblatex 3.17), Biber 2.17.
Full local corpus passed in 14.1 seconds. The historical Biber was downloaded
from its official SourceForge release into `/tmp/bbtex-tectonic-tools.gBOms9`;
its arm64 slice was used only for this test. System Biber remains 2.21.
CI provisions the Linux Biber 2.17 archive with SHA-256 verification in runner
temporary storage, separately from the TeX Live matrix. This is a regression
fixture pairing, not a downgrade recommendation for the supported MacTeX setup.

## Biber repaired; old distributions removed — 2026-09-23

Documented baseline for the supported MacTeX setup: **Biber ≥ 2.21**, with a
compatible biblatex version. This does not override Tectonic bundle compatibility.

User completed the manual native-Biber installation. `/Library/TeX/texbin/biber`
is now an arm64 executable reporting 2.21. The full pdfLaTeX corpus, including
the biblatex/Biber book, passes in 13.9 seconds WITHOUT a temporary Biber PATH
override (`dist/real-engines/pdflatex-1c0sj9vp`). Prior XeLaTeX/LuaLaTeX and native
preview verification against MacTeX 2026 also passed (see below).

Verified removal of TeX Live 2024 and the 2022/2024 .texdist and .FactoryDefaults
registrations. TeX Live 2026 remains selected; shared texmf-local is preserved.
Removed the stale 2022 PATH line through chezmoi's
`.chezmoitemplates/zshrc_darwin.tmpl`; `chezmoi diff ~/.zshrc` is empty. The
chezmoi source change is not committed. User instructions: managed dotfiles must
be edited through chezmoi; scratch work belongs in a temporary directory, not HOME.
Biber preparation/original-launcher backup: `/tmp/bbtex-biber-2026.iiWjHc`.

Tectonic cold-cache fix `98d8fdb` passed all engine jobs and both package builds:
https://github.com/LouLouLibs/bbtex/actions/runs/35833006342
https://github.com/LouLouLibs/bbtex/actions/runs/35833006383
Remaining Tectonic work: a compatible Biber/bundle pair for the book fixture;
the repaired system Biber does not resolve the older bundle's version mismatch.

## MacTeX 2026 installation verification — 2026-09-23

User installed MacTeX 2026 and asked to verify it, then circle back together to
remove the old installation. `/Library/TeX/texbin` now selects TeX Live 2026.
Unfortunately its Biber universal launcher STILL fails with the same lipo error.
No installed binary was replaced. Extracted the new binary's arm64 slice to
`dist/biber-2026-check/biber` (Biber 2.21) strictly for isolated verification.
With that temporary PATH override, the full real-engine corpus passes:
pdfLaTeX 13.9 s, XeLaTeX 15.8 s, LuaLaTeX 20.0 s. Four-engine previews pass;
native BBEdit preview reuse/selection/focus passes (1.387 s first, 0.292 s reused).

Keep cleanup pending with the user: `/usr/local/texlive/2024` is 11 GB; 2026 is
9.7 GB. Preserve shared `texmf-local`. A stale 2022 PATH entry is in ~/.zshrc:209.
Neither was changed. User wants verifiable manual Biber repair, not another
opaque administrator prompt. 2024 repair binary is not appropriate for 2026;
use the new installation's own Biber 2.21 if proceeding with native extraction.

CI exposed a cold-cache font miss in the new Tectonic large-project fixture.
It now warms its own dependencies online before the asserted cached rebuild.

## Biber repair investigation and Tectonic expansion — 2026-09-23

Tectonic now passes generated 40-file build/outline checks and real-process
cancellation/recovery locally (full tier 6.2 seconds). Console readiness avoids
Tectonic's deferred virtual-file publication. Biber-book pairing remains open.

Installed Biber's launcher contains `-extract_family`, rejected by this Mac's
`lipo`. Extracting its own arm64 slice with `lipo -thin arm64` produces working
Biber 2.20. Root installation was NOT changed: user canceled the administrator
prompt because provenance was unclear and asked for step-by-step manual guidance.
The user has been given commands to extract/verify their own installed binary
under `~/biber-repair`, with no replacement yet. Do not retry an administrator
prompt; continue guiding their manual repair after verification. The prepared
workspace copy is `dist/biber-repair/biber`. No downloaded replacement was used.

## Doctor launch checks — 2026-09-22

User confirmed the Doctor menu works. Added `doctor --probe`; the installed menu
now uses it through its existing development symlink. Plain `doctor` remains
inspection-only. Direct version queries use the first PATH executable, closed
stdin, three seconds/tool and 16 KiB combined output; cleanup kills the probe
process group. RaTeX is never launched. External tools may initialize caches,
which is stated in the report/guide. Successful launch does not establish
Biber/biblatex compatibility or a successful compile.

Local live checks reproduced Biber's exit 255 / arm64 extraction failure with an
actionable warning; all other probed tools returned versions. Tests cover stderr,
nonzero exit, output flood and descendants holding a pipe open. Remaining Phase 6
work is broader installation/attachment discovery and fresh-machine acceptance.
Ubuntu's older Dune rejected overlapping test stanzas; Doctor now belongs to the
existing tests stanza. Real-engine CI also watches test/dune changes.

## Doctor inspection tier — 2026-09-22

Added `bbtex doctor [file.tex]` and **LaTeX — Doctor** (development shortcut
installed; release packaging includes command and troubleshooting guide).
Inspection is read-only: resolves engine, locates tools in PATH order, checks
state-parent permissions, known installation duplicates/broken links, optional
editing package/Skim and attachment presence. Home paths are redacted. Existing
bounded project build logs identify Biber launcher and control-version failures.
Tool versions/launchability, attachment ownership and native integration are
explicitly unverified; no subprocess probes or repairs are performed.

Unit and isolated partial/conflicting-installation tests pass and verify no
inspection writes. Phase 6 remains in progress: active bounded version probes,
broader installation discovery, and fresh-machine acceptance remain. See
`docs/setup-troubleshooting.md`. Preserve sample edits and experimental RaTeX.

## Tectonic rendering tier — 2026-09-22

`test/integration/check_tectonic.py` covers article/BibTeX, Beamer, Unicode/fontspec,
cached-resource rebuilds, SyncTeX, output isolation and preview macro updates.
The first local run passed in 10.6 seconds. CI adds a separate Tectonic 0.17.0
job with a checksum-verified musl binary and explicit tlextras-2022.0r0 bundle.
Reports explicitly exclude Biber-book, cancellation and 40-file coverage.
Preview checks require fresh rendering, matching the existing no-cache contract.

The book probe found a separate compatibility issue after using the temporary
working Biber: bundle biblatex 3.17 produces control version 3.8, but Biber 2.20
expects 3.11. Tectonic does invoke Biber; the tool/bundle versions must match.
See `docs/real-engine-regressions.md`. Next: doctor/setup diagnostics, including
both Biber launch failure and version mismatch; remaining Tectonic parity work
stays explicit. Preserve user sample edits; RaTeX stays experimental.

Commit `c601917` passed all four engine jobs:
https://github.com/LouLouLibs/bbtex/actions/runs/35779917765
and both macOS package jobs:
https://github.com/LouLouLibs/bbtex/actions/runs/35779917520 .
The explicit dated-bundle local run passed in 7.3 seconds.

## XeLaTeX/LuaLaTeX regression tier — 2026-09-22

The corpus now accepts `--engine pdflatex|xelatex|lualatex`, sets the selected
engine for all generated projects (including cancellation), verifies the reported
build/preview engine, and records it in artifact names and JSON. CI has independent
jobs and artifacts for all three engines, with explicit XeTeX/LuaTeX/font packages.
XeLaTeX and LuaLaTeX also compile a native Unicode/fontspec fixture using TeX font
filenames rather than OS registration. Final local runs: 16.2 s XeLaTeX and 21.1 s
LuaLaTeX, using the previously documented temporary Biber workaround.

Tectonic is the remaining engine tier: explicitly provision its binary/bundle,
verify offline/cache and bibliography behavior, and adapt checks to its retained
outputs. The current preview code intentionally disables Tectonic cache hits.
After coverage, proceed to doctor/setup troubleshooting, including local Biber.
Future UI requests are tracked separately: outline window
https://github.com/LouLouLibs/bbtex/issues/1 and live-selection preview
https://github.com/LouLouLibs/bbtex/issues/2. RaTeX remains experimental.

## Real-engine corpus and CI, first tier — 2026-09-22

Phase 5 adds original article/book/Beamer fixtures plus a generated 40-file case,
isolated from the user-edited sample. The runner checks real bibliography
convergence, PDF content/geometry, output isolation, SyncTeX inputs, outline data,
preview cache invalidation, diagnostic line mapping, and cancellation/recovery.
Local full run: 14.6 seconds, with retained logs and version/timing JSON under
`dist/real-engines`. See `docs/real-engine-regressions.md` for scope and commands.

The corpus exposed missing nested include auxiliary directories with isolated
output and file-line diagnostics. Compiler recovery now creates only safe relative
`.aux` parents inside the output tree and retries latexmk, bounded to 16 attempts.
Containment and symlink rejection have unit coverage. The local universal Biber
launcher failed independently; the passing run used a temporary arm64 extraction
of Biber 2.20. Installed TeX tools were not replaced; record this for doctor work.

The new Ubuntu real-engine workflow uses explicit packages, path-filtered pushes/
PRs, version tags, and manual dispatch; evidence uploads even on failures. It is
separate from macOS packaging and does not gate draft creation automatically.
Phase 5 remains in progress: broader engines and native release walkthroughs
remain. RaTeX is still an experimental placeholder.

## Structural wrapping and placeholders — 2026-09-22

Phase 4 adds **LaTeX Editing → Wrap in Environment** for complete-line selections
and empty insertion on blank lines. It preserves body indentation and selects the
wrapped body, or places an empty cursor one tab into the inserted body. The shared
snapshot guard and single-edit application now serve rename and wrapping.

The clippings/TexLab audit found existing argument templates but name-only local
TexLab completions for frac/equation. New hyperlink/image clippings use native
placeholders; the custom environment clipping validates names and stale snapshots.
Native cancellation tests discovered that returning an empty clipping result can
erase selected text. Insert/Close Environment now abort with cancellation instead;
BBEdit's scripting caller may report -1701 for the absent clipping result.

Unit tests cover wrapping boundaries, indentation, Unicode and line endings.
Native tests cover body/cursor placement, Undo, placeholder expansion/selection,
stale buffers, cancellation and invalid input with selected text. Actual dialog
answers are substituted in the deterministic tests. See the editing guide for
scope. Next roadmap phase: broader regression coverage; no RaTeX adoption work.
Release-package and installed-copy checks pass. The development package was
updated without restarting BBEdit; its full backup is under
`~/Library/Application Support/BBEdit/Backups/bbtex-wrapping-L77928`.

## Structural editing, first slice — 2026-09-21

Phase 4 hardens Change/Toggle/Close Environment with `Structure`, a bounded OCaml
scanner over the unsaved buffer. Comments, common literal regions, and common
definitions are excluded; nesting is matched by a stack. Rename/toggle apply
both tags as one edit, map the UTF-16 cursor, and reject changed buffers/selections.
The editing support package now carries its own `Resources/bbtex` executable.
Menu scripts explicitly supply that resource path to the library: a native test
exposed that a loaded library's `path to me` can refer to the calling menu script.

Unit and native checks pass for nesting, malformed tags, Unicode, one Undo,
renaming, and stale edits. See `docs/bbedit-editing.md` for scanner boundaries.
Packaged and installed native tests pass. The existing development package's
environment scripts and binary were updated without restarting BBEdit; a full
backup is under `~/Library/Application Support/BBEdit/Backups/bbtex-environments-hVDjUX`.
CI exposed read-only Dune executable permissions when rebuilding package resources;
the support builder now stages and atomically replaces the binary instead of
opening the previous copy for writing.
Next: audit the existing clippings/TexLab placeholders, then add safe wrapping and
harden insertion. Phase 4 remains in progress; RaTeX stays experimental.

## Citation/reference pickers — 2026-09-21

Phase 3 implements and installs **LaTeX — Insert Citation** and **LaTeX — Insert
Reference**, also included in release packages. References reuse the saved project
index with label type/context; citations search author/title/year/key across
declared bibliographies. Since 2026-09-23 this runs in the binary through the
vendored bibtexparser-ml port; it previously used pinned BibtexParser through uv. See
`docs/citation-reference-pickers.md` for dependencies, scope, and limitations.

Insertion preserves supported command names/options, merges multiple citation
keys, and guards saved inputs, exact buffer bytes, document identity, and selection.
Native tests pass for Unicode/UTF-16 offsets, citation and reference insertion,
single Undo, cancellation, and buffer/selection changes. Metadata tests cover
malformed-entry recovery, duplicates, strings, inheritance, missing files, bounded
expansion, and 10,000 entries (about 0.15 seconds). Release package checks pass.

The user walkthrough exposed an unquoted inherited PATH in the citation launcher:
Little Snitch's spaced application path caused `env: … No such file or directory`.
Fix `75aadf7` quotes the full PATH assignment and adds a regression executing the
actual launcher shell prefix with that spaced path. Metadata tests and AppleScript
compilation pass. Installed development symlinks already use the fix; packaged
users need a rebuilt package. Post-fix menu acceptance is not yet confirmed.

The optional user walkthrough of the two new menus is pending; do not repeat the
already accepted outline check. Next planned work is Phase 4 structural editing.
Preserve the user's uncommitted edit in `examples/ui-check/sections/equations.tex`.
RaTeX remains an experimental placeholder.

## Project navigation — 2026-09-21

Phase 2 implements **LaTeX — Project Outline**, installed as a development Scripts
symlink and included in release packaging. `project_index.ml` is a saved-file,
bounded scanner that follows literal includes, preserves duplicate labels, shows
section hierarchy and equation/caption context, and reports missing/dynamic/cyclic
inputs. `bbtex outline FILE [QUERY]` exposes versioned JSON for future reference
pickers. Native query/list dialogs use `outline.ml` and `project-outline.applescript`.
`outline-jump` checks the target fingerprint and generated AppleScript rejects
dirty buffers or mismatched lines. No files are silently saved; RaTeX is unchanged.

Capability audit: BBEdit's native functions menu and TexLab symbol search remain
available. Local TexLab tests now cover document/workspace symbols alongside
completion and definition. No supported scripting API to retrieve BBEdit's
internal LSP symbol data was found. See `docs/project-navigation.md` for the
presentation decision, parser boundaries, query syntax, and saved-source contract.

Phase 2 is accepted: the user confirmed search and Return-to-navigate work in the
installed BBEdit command on 2026-09-21. Do not repeat that acceptance question.
Next roadmap item: Phase 3, richer citation/reference selection.

Unit and native integration checks pass for multi-file hierarchy, duplicate labels,
verbatim/comments, include/root cycles, changed disk contents, every fixture
row-to-location mapping, dirty buffers, quoted paths, and Unicode. Computer Use
permission was granted on retry, but reading BBEdit's modal dialogs intermittently
times out or fails screen capture; the user supplied the final keyboard check. The
wrapper now redirects shell output to `outline.log`, like the existing build
commands, and explicitly activates BBEdit for the user-requested search dialog.
Release package/archive checks, including the packaged outline binary, pass.

The previous preview milestone was committed/pushed as `aba5ca9`; CI passed on
both architectures: https://github.com/LouLouLibs/bbtex/actions/runs/35533004418 .

## Dependency-save refresh — 2026-09-20

The next Phase 1 item is implemented. Saving a resolved root or recorded TeX
input refreshes the active automatic equation at its retained source/line.
Unrelated saves are ignored; changed source fingerprints mark the preview stale
and ask for a fresh equation save. Manual preview replaces the automatic anchor.
The save attachment now handles non-front documents and dependency refresh uses
window ID 0 so it cannot open a new preview or move focus.

`Preview_inputs` persists recorder paths in each root's `tracked.inputs`, separate
from `cache.inputs`; failed renders retain prior inputs for recovery. Root refresh
works without a recorder; Tectonic/RaTeX do not promise arbitrary dependency
discovery. No unsaved snapshots or RaTeX adoption work was added.

Unit and worker tests cover routing, source invalidation, unrelated saves and
generation supersession. Four-engine rendering checks and native foreground/
background macro-save checks pass. The installed save attachment is updated;
native checks restored the user's tracking and previous image.
Package/archive, mocked build workflows, cancellation ownership and browser
ordering checks pass. Packaged native preview: 1.478 s first open, 0.336 s reuse;
tab-switch checks establish their focus baseline after closing the old preview.
Phase 1 is locally verified; next roadmap item is project-wide navigation.

## Preview-polish continuation — 2026-09-20

Phase 1 is now partly implemented; see
`docs/plans/2026-09-19-writing-workflow-roadmap.md` for the user's ordered roadmap.
The preview uses generation-aware OCaml state (`snippet-window/state-v2`) and a
short publication lock. `snippet-begin` starts a request, `snippet-finish` rejects
obsolete generations, and `snippet-current` checks tracking/source freshness.
The browser rejects obsolete payloads and delayed image loads. Existing HTML
pages reload into the new status UI through their existing image poller.

Rendering/current/stale/error/busy status includes source and cursor line. Old
images remain only for the same source and are explicitly marked out of date.
**LaTeX — Open Preview Log** is installed. Superseded previews detect invalidation
inside their own Build_job and cancel their own process groups; no generic root
cancellation is used for supersession. Full compile invalidates only matching
automatic preview requests before acquiring the existing preview serialization
lock. Request tokens are excluded from the render cache key.

Tests cover state migration, publication races, browser load ordering, compiler
children, full-build isolation, four real engines, cached reuse, actual BBEdit
saves and error feedback. Native test cleanup now keeps a temporary recovery
backup and restores old previews with a fresh revision, including legacy payloads.
Dependency-save refresh is covered by the newer section above; unsaved snapshots
and richer scanning remain deferred. RaTeX remains an experimental placeholder.

## Continuation results — 2026-09-19

The documentation, save-worker lifecycle, and release-installation work below
has been completed. Existing changes and example documents were preserved;
RaTeX is still an experimental placeholder. The continuation work was committed
as `db810ee`. CI and draft-release packaging are documented in `docs/releases.md`.

- Both historical plans now distinguish accepted/completed work from optional
  future improvements. Do not repeat the already accepted UI walkthroughs.
- Save workers now use `with-preview-lock.pl` and a kernel-owned lock instead
  of PID directories. Each save queues a uniquely identified contender; only
  the newest queued request renders. Switching tracked files, disabling, saves
  during publication/exit, and process death are covered by deterministic tests.
- Full compilation waits for an active save preview before starting its compiler,
  while its live suppression marker prevents new save previews from rendering.
- First-window creation checks the source window and its file, including a tab
  change within the same window. Source restoration never activates BBEdit.
  The contextual service also avoids reopening/reactivating a departed source.
- Hook and service resolve development Scripts first, then the standard
  `Packages/bbtex.bbpackage/Contents/Scripts` path. Release resources include
  standalone optional installers and usage instructions. No full release package
  is installed alongside the current development setup.
- The installed attachment/service were updated; save tracking remains opt-in.
- Verification: dune build/runtest; mocked build workflow including waiting for
  preview; worker concurrency/crash tests; real rendering with all four engines;
  actual BBEdit saves; native window reuse and tab-switch focus checks.
  The arm64 release package and ZIP were rebuilt and checked for archive
  integrity/resource parity. Bundled installers compiled successfully; packaged
  compile/preview and staged Automator service checks passed. Latest native
  preview timings: 1.438 s first open, 0.307 s reuse; service 3.383/2.420 s.
  Release validation is reproducible with
  `BBTEX_TEST_NATIVE=1 bash test/integration/check_preview_release.sh` using the
  uv environment settings below. Native tests require automation permission.

Remaining optional feedback: save-preview ergonomics and contextual-menu
placement. Superseded renders finish before their output is discarded; automatic
cancellation, richer status, and unsaved dependency snapshots remain deferred.
The older sections below provide historical context where not superseded here.

## Start here

Continue work in `/Users/loulou/Dropbox/projects_claude/bbtex-ocaml`.
The user asked for this handoff before starting a fresh session. Do not restart
the implementation or repeat already completed UI questions.

Latest request implemented: opt-in equation preview on file save; RaTeX in the
compiler picker as an experimental placeholder. User explicitly agrees to leave
RaTeX as a placeholder until it matures. Do not install it or change defaults.

## Repository and user preferences

- Last commit: `242093d Add project builds and guided TeXShop document settings`.
  Previous: `2b69a1b Improve BBEdit LaTeX editing and compile workflow`.
- **Substantial work remains uncommitted**, including preview, cache, service,
  save hook, completion binding helper, docs and sample project. Preserve all of
  it. Inspect `git status --short` before acting. No commit made for this handoff.
- Language policy (no Python in shipped code; Python only for integration tests,
  always through **uv** with PEP 723 metadata) is in `AGENTS.md`.
- Reliable command here (inherited VIRTUAL_ENV is broken):
  `env -u VIRTUAL_ENV uv --no-cache run --python /Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13 SCRIPT`
- User authorizes BBEdit scripting and direct installation; use required sandbox
  escalation for Library writes/native automation. Do not repeatedly ask design
  permission. Do not force quit BBEdit or overwrite user documents.
- Native AppleScript works. Computer Use permission is unavailable; user helps
  with visual checks. No need to reinstall TexLab or reassign shortcuts.

## Installed and accepted

- ⌘K compile; ⇧⌘K compiler/profile picker and Configure Document; ⇧⌘C Complete.
  Complete replaced Copy & Append, and **user verified the shortcut works**.
- User verified Configure Document, reference/citation completion, and Go to
  Definition. Main-file picker now starts in the current source directory.
- TeXShop magic comments and aliases documented; `.bbtex` profiles, root chains,
  project save/build/cancel, error results and Skim full-document viewing work.
- Legacy package archived; editing assets in bbtex-support package, TexLab link
  installed. Native helpers reuse old package functionality where useful.
- User accepted the compact BBEdit HTML window displaying PNG equation previews.
  **Skim is no longer the selection-preview surface.** Skim remains for full PDF.
- Right-click service installed as
  `~/Library/Services/LaTeX — Preview Selection.workflow` (BBEdit selected text).
  Registered with pbs; native Automator test passed. User has not explicitly
  confirmed its exact contextual-menu placement. Automator adds ~2–3 s overhead.
- Save hook installed at
  `~/Library/Application Support/BBEdit/Attachment Scripts/Document.documentDidSave.scpt`.
  Menu script **LaTeX — Toggle Preview on Save** is installed as a repo symlink.
  **Off by default**, and test restored the previous flag/image. To use: toggle
  in a saved TeX document, edit with cursor inside a displayed equation, press
  ⌘S. Toggle again in that file to disable; another file switches tracking.
  Closing the preview window does NOT disable this mode.
- Development scripts are symlinks; rebuilding `_build/default/bin/main.exe`
  changes installed behavior. `~/.local/bin/bbtex` points to that binary.

## Implementation map

- `lib/preview.ml`: saved root preamble + selection, standalone `preview.sty`,
  cropped PDF and pdftoppm PNG. Direct single pass for ordinary TeX engines;
  Tectonic/custom options use their own paths. Root cwd preserves relative inputs.
  Root build locks/cancellation shared with full compilation.
- `lib/preview_cache.ml`: one cached selection per root; validates actual `.fls`
  dependencies, root directory listing, configuration/environment and binaries.
  No cache for Tectonic, RaTeX or custom options. Time/random-dependent TeX is a
  known limitation. Outputs under `~/.local/state/bbtex/preview-<root digest>/`.
- `lib/snippet_page.ml`: base64 PNG in atomically published `image.js`, HTML polls
  every 250 ms. One state-specific preview page/window. Error publication clears
  the old image. Existing HTML is only written if absent: account for migration
  if changing the page template.
- `scripts/bbtex-bbedit-preview.sh`: explicit selection preview, refuses modified
  relevant project inputs; does not save documents automatically.
- `scripts/snippet-window.applescript`: reuses native BBEdit web preview window,
  preserves placement, restores source focus on first open after 600 ms delay.
- `lib/equation.ml`: extract complete display block at a saved cursor line.
  Supports `\\[...\\]`, equation/align/gather/multline/flalign and starred forms,
  displaymath. No inline math or `$$`; lightweight scanner, not a TeX parser.
  CLI command: `bbtex equation-at FILE LINE`.
- `scripts/bbtex-preview-on-save.sh`: toggle file tracking; background contenders
  coalesce saves using request tokens and `with-preview-lock.pl`. The kernel lock
  cannot be stranded by a missing PID file. Uses the saved root preamble.
- `scripts/preview-save-hook.applescript`: documentDidSave captures current
  document path/line/window and starts background worker. Compare file paths,
  **not object references**, to identify front document (fixed during testing).
  Logs hook errors through macOS logger; worker log is `preview-on-save.log`.
- Full compile wrapper writes a live PID suppression marker so its own save
  does not start a competing preview. Hook ignores a marker whose PID is dead.
- `scripts/install-preview-save-hook.sh`: compile/install hook; refuses unrelated
  existing Document/BBEdit hooks. `install-workflow-commands.sh` installs menu link.
  `install.sh` wired for both. Release resources now include hook/service
  installers; see `docs/selection-preview.md` for package-only installation.
- RaTeX branches in types/compiler/preview/CLI/configure dialog use documented
  `ratex -pdf -interaction=nonstopmode -output-directory=DIR FILE`.
  Compiler reads captured job log instead of potentially stale TeX .log.
  No RaTeX executable installed or real rendering tested.

## Evidence and verification

- Latest `dune build`, `dune runtest`, shell syntax checks and `git diff --check`
  passed after final changes. Unit preview test includes equation extraction.
- **Latest native test** `test/integration/check_save_preview.py` passed:
  actual BBEdit saves published two distinct PNG equations, with no restart.
  It creates/closes only a disposable source and restores flag/image afterward.
- `test/integration/check_preview.py` was rerun successfully on 2026-09-19 across
  pdflatex/xelatex/lualatex/tectonic, invalid input, external macros, source/PDF
  isolation and cache invalidation. LuaLaTeX required unsandboxed font-cache access.
- `check_live_preview.py` passed window reuse, selection/focus preservation
  and exact image publication. Optional env `BBTEX_TEST_PREVIEW_WRAPPER` checks
  packaged command; `BBTEX_TEST_PREVIEW_SERVICE` tests staged Automator workflow.
- Packaged preview, optional installers, compile wrapper, service, and ZIP were
  verified after the save-hook lifecycle changes; `dist` is current.
- Measured native manual preview: ~1.45 s first open, ~0.31 s cached reuse plus
  up to 250 ms polling; real TeX ~0.22–0.50 s, conversion ~0.06–0.16 s.
- `examples/ui-check/` has main.tex, included sections/equations.tex, bibliography,
  `.bbtex` profiles and custom macro. User may have edited these: preserve changes.

## Original review checklist (resolved as noted above)

1. Review the current uncommitted diff and reconcile documentation. Historical
   plan files still have obsolete pending UI/Skim prototype statements despite
   later acceptance. This handoff records the current state. Update the two plan
   files so completed items and optional future work are clear.
2. Harden save-preview lifecycle/concurrency as needed. Current version coalesces
   saves but **does not cancel an in-flight superseded render**. Review a save
   arriving during publication/worker exit, switching tracked files while a
   worker runs, stale lock without PID, and source focus if user moves elsewhere
   during first render. These are review risks, not established test failures.
   A normal build suppresses its save event, but an already-running preview can
   still make a full build report busy because they share the root lock.
3. Save mode deliberately uses saved dependencies; it does not snapshot unsaved
   preamble/macros, and saves in another dependency file do not trigger a tracked
   source preview. This is documented. Decide whether clearer stale/error/busy
   feedback is needed. Do not silently save unrelated documents. Manual preview
   already checks modified project inputs. Verbatim/custom math environments
   are outside the extractor’s current scope.
4. Review release packaging/install story for the optional save attachment and
   contextual service. Package includes hook source but BBEdit will not install
   an attachment just because it is in Resources. The current installer is
   repository/development-oriented and the hook locates the Scripts-folder worker;
   package-only use needs a reliable worker path. Rebuild and validate release
   after fixing this; avoid duplicate menu entries with dev installation.
5. UI checks worth requesting when useful: user’s save-preview experience and
   right-click service discoverability. Do NOT ask them to repeat completion,
   Configure Document, Go to Definition, or basic manual-preview acceptance.
6. When implementation/release cleanup is done, organize and commit the pending
   work. User has previously requested commits between stages, but did not request
   a new commit in the handoff turn. Never discard unrelated/user modifications.

Deferred, not required now: keystroke-live preview, KaTeX/MathJax alternate renderer,
native popover/inline display (no supported BBEdit API established), richer citation
picker, unsaved dependency snapshots. Save-driven real TeX preview was the user’s
chosen pragmatic next step. RaTeX remains a placeholder, not an adoption project.

## References

- User’s article: https://leoliu0.github.io/blog-ratex.html
- Correct RaTeX: https://github.com/leoliu0/ratex (full TeX compiler; not the
  similarly named erweixin/RaTeX math renderer). Article cached during research at
  `/tmp/bbtex-ratex-article.html` if still present. Fastest advertised timings
  include unchanged builds; do not infer equivalent edited-equation latency.
- BBEdit installed manual extracted to `/tmp/bbedit-manual.txt`; save attachment
  documentation around lines 15600–15700. Installed app scripting dictionary:
  `/Applications/BBEdit.app/Contents/Resources/BBEdit.sdef`.
- `docs/selection-preview.md`, `docs/project-builds.md`, `docs/bbedit-editing.md`.
- Plans: `docs/plans/2026-09-17-bbedit-latex-workflow.md` and
  `docs/plans/2026-09-18-fast-selection-preview.md` (historical/stale sections).
