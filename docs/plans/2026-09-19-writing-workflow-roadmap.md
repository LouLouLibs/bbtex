# BBEdit LaTeX writing-workflow roadmap

Status: Phases 1 and 2 complete; Phase 3 implemented and locally tested;
Phase 4 environment matching/renaming implemented,
updated 2026-09-21.

Completed in the first implementation slice: rendering/current/stale/error/busy
status, source/line context, old-image labeling, HTML migration, serialized
generation-aware publication, delayed-image guards, Open Preview Log, and
ownership-aware supersession/full-build interruption. Unit, worker, browser,
process-cancellation, four-engine rendering/cache, and native BBEdit checks cover
this slice. Native timing: 1.506 s first open, 0.321 s cached reuse on the fixture.
Dependency-save refresh is implemented: resolved roots and recorder inputs route
foreground/background saves to the retained equation anchor. Changed source
contents require a fresh equation save; unrelated saves are ignored. Recorder
inputs persist separately from the cache, including after failed renders.
Deterministic routing and native macro-save/focus checks pass. Unsaved snapshots
remain deferred; engines without recorder output guarantee only root refresh.
Latest packaged native timings: 1.478 s first open, 0.336 s cached reuse.
Phase 2 now supplies **LaTeX — Project Outline**, a native saved-file search and
picker backed by a bounded shared OCaml index. It follows literal inputs, shows
hierarchy/equation/caption context, preserves duplicate labels, reports incomplete
inputs, and refuses stale or dirty jump targets. The capability audit and data
contract are in `docs/project-navigation.md`. Unit tests, native script compilation,
all fixture row-to-location mappings, and dirty/stale target checks pass. The user
confirmed that the installed command searches and opens a result with Return on
2026-09-21.

Phase 3 now provides installed and packaged citation/reference menus. Citation
search supports metadata and multiple keys; references show type and context from
the shared index. Pinned BibtexParser handles bibliography blocks, with bounded
string expansion and metadata inheritance. Native insertion checks cover command
and option retention, UTF-16 offsets, one Undo, cancellation, and changed buffers
or selections. Metadata and release-package checks pass, including a 10,000-entry
fixture. The new-menu user walkthrough is pending; next planned phase is
structural editing. See `docs/citation-reference-pickers.md` for scope and limits.

The user's priority order is **3 → 4 → 1 → 2 → 5 → 6** from the feature
comparison: preview polish, project navigation, citation/reference selection,
structural editing, broader regression coverage, then setup/troubleshooting.
The phases below follow that order. Each phase should leave a usable release;
finish its acceptance checks before proceeding to the next.

## Starting point and constraints

Project builds, profiles, diagnostics, cancellation, Skim synchronization,
native TexLab completion/definition, compact equation previews, opt-in preview
on save, and two-architecture CI packaging are already implemented. Preserve
these workflows and the user's shortcuts, documents, and settings. RaTeX stays
an experimental placeholder; no installation or default-engine change.

Use supported BBEdit features and TexLab first. Inspect what the editor actually
exposes before adding another UI or index. Do not assume access to BBEdit's
internal language-server connection. Inline previews and arbitrary popovers
are not established capabilities; the accepted compact HTML window remains the
preview surface. Skim remains the full-document viewer.

Never silently save unrelated documents. Keep automatic preview opt-in. Native
verification uses disposable documents and restores affected tracking state.
Python helpers use uv with PEP 723 metadata and explicit dependencies. Product
logic belongs in OCaml where practical; wrappers handle editor integration.

## Phase 1 — Preview polish (original priority 3)

**Outcome:** the preview clearly communicates whether it is current, responds
to relevant saves, and does not delay editing with obsolete work.

1. Add explicit rendering, current, stale, error, and busy states. Associate
   each state/image with its source, equation location, and request generation.
   An old image may remain visible while rendering only if marked stale.
   Show a concise error and a supported way to inspect the relevant log.
   Version/migrate existing HTML pages so installed previews receive updates.
2. Cancel superseded automatic renders and give explicit full builds priority.
   Track preview ownership with a unique job identifier; cancellation must never
   target an unrelated full build merely because it shares the same root.
   Serialize the final freshness check and publication so an old completion
   cannot overwrite a newer state. Preserve manual cancellation and crash recovery.
3. Refresh when a saved, known dependency affects the tracked equation. Use
   resolved roots and recorded inputs; ignore unrelated saves. Retain the last
   tracked equation location instead of using the dependency file's cursor.
   Detect when source edits invalidate that location and request reselection
   rather than silently previewing a different equation. Support saves of
   relevant non-front documents without stealing focus.
4. Document the saved-input contract and benchmark cold render, warm render,
   cancellation, and cached display against the existing fixture. Keep custom
   engines/options supported without claiming dependency tracking when their
   inputs cannot be discovered reliably.

**Acceptance:** deterministic tests cover save bursts, dependency saves,
switching/disabling tracking, cancellation ownership, build priority, and saves
during publication. The final state always identifies the newest request; stale
output never appears current. A native test verifies window reuse, tab-switch
focus preservation, and useful error feedback. Record latency and investigate
regressions rather than asserting an unmeasured universal target.

**Boundary:** unsaved dependency snapshots are a separate follow-up, not a gate
for Phase 2. Before implementing them, resolve relative input paths, dirty-buffer
capture, and source-location mapping. Continuous keystroke preview is deferred.

Likely touchpoints: `preview.ml`, `build_job.ml`, `snippet_page.ml`, save worker,
save attachment, native window helper, preview integration tests.

## Phase 2 — Project-wide navigation (original priority 4)

**Outcome:** navigate a multi-file paper from one searchable outline.

1. Audit BBEdit's existing symbol/outline commands and TexLab-backed navigation
   using the sample project. Record which needs are already met and which
   operations are accessible through supported integration points.
2. Deliver a keyboard-friendly project outline for sections, equations, figures,
   tables, and labels. Show hierarchy, source file, and nearby text where useful.
   Preserve duplicate labels as distinct entries with their locations.
3. Reuse available symbol data. Where necessary, add a small shared project
   index with a defined parsing scope: include/root resolution, cycle detection,
   comments, common verbatim environments, and stable source locations.
   Do not attempt general TeX expansion. Mark unavailable/dynamic inputs clearly.
4. Refresh on relevant changes without rebuilding the PDF. Decide explicitly
   whether an entry reflects an open buffer or saved content. Revalidate its
   location before jumping after edits; do not silently use stale line numbers.

**Acceptance:** a multi-file fixture can be searched and navigated entirely by
keyboard; every selected entry opens the correct source location. Tests cover
duplicate labels, missing inputs, root cycles, commented commands, and edits
after indexing. Existing Go to Definition and completion continue to work.

**Decision point:** choose the simplest supported BBEdit presentation after a
small capability prototype. A persistent custom outline is justified only if
native navigation cannot meet these acceptance criteria. Record the decision.

Deliverable: navigation command(s), documented index/data contract, and fixtures
that the citation/reference picker can reuse in Phase 3.

## Phase 3 — Citation and reference selection (original priority 1)

**Outcome:** choose a citation or label by meaning, with enough context to avoid
opening several files just to identify it.

1. Add citation search over author, title, year, and key, with multi-selection.
   Preserve the citation command already being edited and existing keys; support
   common BibTeX and biblatex/natbib usage without rewriting citation style.
2. Add reference selection with label type, source location, and nearby section,
   caption, or equation text. Reuse Phase 2's project data. A rendered equation
   thumbnail is optional after text context works reliably.
3. Reuse TexLab's information wherever accessible. If a bibliography reader is
   needed, evaluate a maintained parser before writing one. Define support for
   nested braces, quoted values, strings, multiple files, and inherited metadata;
   malformed entries must not prevent selecting valid entries elsewhere.
4. Preserve native completion as the quick path. Pickers are explicit commands;
   do not automatically replace the accepted completion shortcut.

**Acceptance:** search finds entries by title/author rather than just key;
multiple citations insert correctly; selecting a reference inserts the intended
label. Cancellation changes nothing, insertion is undoable, and dirty-buffer
changes while the picker is open cannot cause insertion at an obsolete position.
Exercise duplicate keys, Unicode names, large bibliographies, and missing files.

Deliverable: richer pickers sharing project data with navigation, with a native
walkthrough limited to the new interactions.

## Phase 4 — Structural editing (original priority 2)

First slice: Change/Toggle/Close Environment share a bounded OCaml matcher over
the unsaved buffer. Rename/toggle use one edit with UTF-16 cursor mapping and
buffer/selection guards. Unit and native checks cover nesting, comments/literals,
definitions, malformed tags, Undo, and stale edits. Wrap-selection and insertion/
placeholder audit remain next; this phase is not complete.

**Outcome:** common LaTeX edits are predictable in nested, real-world documents.

1. Harden Change Environment, Toggle Starred Environment, and insert/close
   helpers against nesting, comments, escaped delimiters, and verbatim regions.
   Share the bounded scanner from earlier phases where it fits.
2. Add wrap-selection operations that preserve indentation and paired names.
   Define behavior on malformed or ambiguous input; prefer an explanatory
   no-op over changing an uncertain region.
3. Improve command/environment insertion with argument placeholders using
   BBEdit's supported clipping/completion facilities. Audit existing clippings
   and TexLab completion first, and add only missing behavior.

**Acceptance:** each operation is a single undoable edit, preserves unrelated
text and unsaved work, and leaves a useful selection/cursor position. Tests cover
nested identical environments, starred forms, comments, verbatim, empty
selections, and incomplete input. Native checks verify Undo and cursor placement.

Deliverable: hardened editing helpers and a small, documented command set.

## Phase 5 — Broader regression coverage (original priority 5)

**Outcome:** confidence extends beyond the development machine and simple paper.

Each preceding phase includes its own tests immediately. This phase expands the
cross-feature corpus and real-tool coverage rather than postponing correctness.

1. Add redistributable fixtures for article/book/Beamer layouts, representative
   journal-style constraints, BibTeX and biblatex/Biber, custom macros, Unicode
   and spaced paths, external includes, and a larger multi-file project. Keep
   user-edited `examples/ui-check` files separate from automated fixtures.
2. Add a real-engine CI tier with the needed TeX packages and Poppler. Start on
   one architecture with pdfLaTeX; extend to XeLaTeX/LuaLaTeX and Tectonic with
   explicit package/download handling. Retain the fast two-architecture checks.
3. Test diagnostics, bibliography convergence, output isolation, preview cache
   invalidation, cancellation, and source mapping together. Compare structure,
   PDF geometry, and required content; avoid brittle cross-platform pixel equality.
4. Keep native BBEdit/Skim acceptance as a documented local release check.
   Record dependency versions and diagnostic artifacts for failed CI jobs.

**Acceptance:** the documented corpus passes; failures produce actionable logs;
CI distinguishes ordinary build checks from real rendering and native editor
verification. Record runtime before deciding which broader jobs run on every
push versus release preparation or scheduled runs.

## Phase 6 — Setup and troubleshooting (original priority 6)

**Outcome:** a new installation can explain what works and how to fix what does not.

1. Add a read-only `bbtex doctor` command and BBEdit menu entry. Check required
   build/preview tools, resolved paths, TexLab discovery, Skim integration,
   package versus development layout, duplicate commands, attachment conflicts,
   and state-directory access. Distinguish required, optional, and unverified items.
2. Show concise next actions; avoid reporting every absent optional tool as an
   error. RaTeX's absence is normal. Do not change settings or install tools as
   part of diagnosis. Separate any repair action from inspection.
3. Simplify release installation, optional feature enablement, upgrades, and
   rollback documentation. Provide an explicit smoke check using a disposable
   document and a diagnostic report with personal paths redacted for sharing.

**Acceptance:** test clean, partial, development, packaged, and conflicting
installations using isolated fixtures. Diagnosis leaves files/settings unchanged
and identifies the correct remedy. A fresh-machine walkthrough can install,
compile, preview, and uninstall using only the instructions.

## Delivery and first implementation slice

Make small commits within each phase, run checks appropriate to each change,
and keep both CI architectures passing. Update this plan with completed work,
evidence, and deferred items. Tagging produces a draft release; publication is
a separate action. Do not re-request acceptance of already verified workflows.

Start with **Phase 1's status/publication model and HTML migration**, then add
ownership-aware cancellation, then dependency-save refresh. That establishes a
reliable preview foundation before introducing the navigation UI. No date or
effort estimate is committed until the editor capability checks are complete.
