# Fast selection preview in BBEdit

Status updated 2026-09-19. The compact BBEdit HTML window was accepted by the
user and replaced the original PDF-in-Skim selection prototype. Skim remains
the viewer for full documents. No additional prototype approval is pending.

## Completed

- Explicit Preview Selection captures complete selected math and uses the saved
  root preamble, engine, and relative macro inputs without saving documents.
- AUCTeX's standalone `preview.sty` crops the output; Poppler converts it to PNG.
  pdfLaTeX, XeLaTeX, LuaLaTeX, and Tectonic passed real rendering checks.
- One BBEdit HTML window refreshes through atomic image publication every 250 ms.
  Native checks cover reuse, selection preservation, and focus restoration.
  Placement persists after first creation. First creation skips opening when
  the user has moved to another document during rendering. Restoring the source
  window does not activate BBEdit over another app.
- Direct TeX engines use one pass and one cached selection per root. Cache
  validation covers recorded input digests, directory entries, configuration,
  environment, and executable contents. Macro edits invalidate cached output.
- The selected-text contextual service and opt-in save attachment are implemented.
  Native save tests published two distinct equations without restarting BBEdit.
- Save workers serialize with a kernel lock, coalesce queued saves, discard
  superseded render results, and preserve requests arriving during publication.
  Changing the tracked file or disabling tracking invalidates the old result.
  Full builds suppress their save events and wait for an active save preview.
- Release resources include standalone installers for the optional attachment
  and service. Both support the standard package path without development links.

Measured native latency on the original simple fixture: 1.45 s first open,
0.31 s cached window reuse, plus up to 250 ms polling. Real rendering took
0.22–0.50 s and PNG conversion 0.06–0.16 s. Automator adds roughly 2–3 s.
These are measurements, not guarantees or sub-200-ms claims.

## Current constraints

Manual preview requires explicitly saving modified project inputs. Save preview
uses saved dependencies; changing a different dependency does not trigger the
tracked source. It never silently saves unrelated documents. Inline math,
`$$`, verbatim-aware scanning, and custom display environments are outside the
save extractor's scope. Saves outside a recognized equation do nothing.

An in-flight render finishes before its superseded result is discarded; it is
not automatically cancelled. A save arriving during atomic publication can
briefly show the preceding image before its own queued update. Cancellation is
available through Cancel Build. The preview shares the root lock with other
build operations. Tectonic, custom options, and experimental RaTeX are uncached;
time/random-dependent macros can require explicit cache removal.

## Optional future work

- User feedback on save-preview ergonomics and contextual-menu discoverability.
- Cancellation of superseded renders and richer busy/rendering status.
- Unsaved dependency snapshots and dependency-save triggers.
- Keystroke-live preview, alternative web renderers, or richer citation UI.
- Native inline/popover display only if a supported BBEdit API is established.

RaTeX stays an experimental placeholder; do not install it or change defaults.
See [selection preview](../selection-preview.md) for usage and verification.
