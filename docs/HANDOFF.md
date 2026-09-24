# BBEdit LaTeX handoff — current 2026-09-24

This is the current status. The [chronological history](archive/handoff-through-2026-09-24.md)
contains superseded plans and evidence; its old “remaining” lists are not current tasks.

## Preserve these constraints

- Preserve user edits, especially `examples/ui-check/sections/equations.tex`.
- Review current repository state before work; the user also works with Claude.
- RaTeX remains an experimental placeholder. Do not install it or change defaults.
- Use temporary directories for scratch work, not the home directory. Edit managed
  dotfiles through chezmoi. Never force-quit BBEdit or modify user documents in tests.
- Follow `AGENTS.md`: OCaml product logic, thin Bash/AppleScript glue, no shipped
  Python. Python native/reference tests run through uv with PEP 723 metadata.
- Builds use opam. Local CI is `opam exec -- scripts/ci.sh --report`; engine changes
  also need `--engines`/`--tectonic`. GitHub Actions remain manual-only.
- Native acceptance already covers completion, Configure Document, Go to Definition,
  manual/save previews and the persistent outline. Do not ask for redundant checks.

## Completed

- Project/profile builds, diagnostics, cancellation, TeXShop aliases and Skim SyncTeX.
- TexLab completion/navigation; OCaml citation/reference pickers; structural editing,
  wrapping, placeholders and Undo checks. Shipped Python removal is complete (#4).
- Compact reusable equation preview, cached rendering, current/stale/error states,
  cancellation ownership, dependency-save refresh and optional contextual service.
- pdfLaTeX/XeLaTeX/LuaLaTeX corpus plus Tectonic online/offline bibliography coverage.
- MacTeX 2026 works with native Biber 2.21. Old distributions were cleaned up.
  Supported MacTeX baseline is **Biber >= 2.21** with matching biblatex. The dated
  Tectonic test bundle uses isolated Biber 2.17; do not downgrade system Biber.
- Persistent outline merged in [PR #26](https://github.com/LouLouLibs/bbtex/pull/26):
  expandable tree, literal search, guarded jumps, saved-source refresh retaining
  state, one window per root, menu/package integration and cleanup on close.
  HTML escaping and nonce CSP protect source-controlled display text.
- Outline startup bursts: larger listener queue and immediate request draining;
  three native passes with 16 concurrent startup requests. Keyboard focus survives
  refresh. 9,600 entries: BBEdit readiness ~1.23 s, update ~1.53 s including polling;
  Chromium search ~255 ms, down from ~3.7 s. See the explicit native/browser tests.
- [Issue #2](https://github.com/LouLouLibs/bbtex/issues/2): opt-in preview that
  follows the selection, implemented on branch `live-selection`. Plan:
  [live selection preview](plans/2026-09-24-live-selection-preview.md). The
  native check `check_live_selection.py` measured 1.23 s cold / 0.76 s warm
  (cached) from selection to Current, including the 0.35 s debounce and the
  poll (2026-09-24, Apple Silicon, BBEdit 15.5.5, pdfLaTeX; local timings, not
  guarantees).

## Setup and diagnostics (merged in PR #27)

Doctor adds `--bbedit-support DIRECTORY`, bounded discovery of renamed packages
and nested menu folders, broken/duplicate commands, and save-hook conflict checks.
The hook installer writes a checksummed receipt; Doctor distinguishes unchanged,
modified and unverified attachments without executing or rewriting them. Receipts
are content identity, not a security attestation. Legacy hooks without receipts
are adopted only if their full decompiled source matches the installer output.

Staged installation tests cover package discovery, nested conflicts, safe hook
upgrade and removal while preserving unrelated attachments. These are isolated
tests on a configured Mac, not proof of first-time setup on a clean machine.
Unit checks and staged install/upgrade/removal passed, as did a real packaged
pdfLaTeX compilation. Native packaged preview passed at 1.587 s first render /
0.316 s cached reuse, preserving source/selection and avoiding first-open focus
theft after a document switch. Issue #1 was updated and closed as completed.
Follow [setup troubleshooting](setup-troubleshooting.md) for the remaining physical
fresh-account/Mac walkthrough and explicit verification boundaries.

## Remaining work

1. Perform the documented fresh-account/Mac acceptance with only the release
   instructions: install, compile, preview, upgrade/rollback and uninstall.
   This needs the user on a clean account; it cannot be automated here.
2. Prepare the first release (no tags or GitHub releases exist yet): release
   notes, full engine checks and a draft via `scripts/ci.sh --engines --report
   --release vX vX`. Publishing remains a separate step.

Housekeeping 2026-09-24: merged local branches were deleted; 18 merged remote
branches (and `origin/python-cleanup`, whose content is already in `main`) still
await deletion by the user. The [editor comparison](editor-comparison.md) now
covers LaTeXTools and AUCTeX against current features.

Optional follow-ups: outline state across closing/reopening, unsaved dependency
snapshots, richer citation UI. No new renderer or RaTeX adoption is required.

## Useful entry points

- `lib/outline_window.ml`, `lib/project_index.ml`: persistent outline and saved index.
- `lib/preview.ml`, `lib/preview_cache.ml`, `lib/snippet_page.ml`: equation rendering.
- `lib/doctor.ml`, `scripts/install-preview-save-hook.sh`: inspection and hook safety.
- `docs/releases.md`: current Apple Silicon/local-CI release policy.
- Native tests: `check_outline_window.py`, `check_outline_launcher.py`,
  `check_outline_large.py`, `check_live_preview.py`, `check_save_preview.py`.
- Browser test: `check_outline_browser.mjs`; see outline notes for temporary
  Playwright setup. Test names containing “live preview” do not implement issue #2.
- If inherited VIRTUAL_ENV is broken, use `env -u VIRTUAL_ENV uv run --no-cache
  --python /Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13 TEST`.
