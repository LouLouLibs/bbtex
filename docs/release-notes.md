BBEdit equation previews now use a compact reusable image window, with cached
single-pass rendering for pdfLaTeX, XeLaTeX, and LuaLaTeX. Tectonic is also
supported. Full-document PDFs continue to use Skim.

**LaTeX — Project Outline** adds native search across saved project sections,
equations, figure/table captions, and labels. Duplicate labels retain their source
locations; changed files and unsaved targets require a refreshed outline. The
bounded index follows literal includes and reports unavailable inputs. Existing
TexLab completion and symbol navigation remain available.

**Insert Citation / Insert Reference** search bibliography metadata or label
context and insert keys into the current command. Citation multi-selection,
existing options/keys, Undo, cancellation, and changed-buffer checks are supported.
Citation search uses uv with pinned BibtexParser; reference search uses the shared
OCaml index. Both use saved project definitions and reject ambiguous duplicate keys.

- Optional preview on save follows the complete display equation at the cursor.
- Saving a known macro/preamble input refreshes the tracked equation, including
  background document saves, while preserving editor focus. Changed source
  locations require a fresh equation save. Recorder-less engines have limited
  dependency discovery; unsaved buffers remain outside the preview contract.
- The preview shows rendering/current/stale/error/busy status and source context.
  Previous images are clearly marked out of date; Open Preview Log exposes errors.
- Rapid saves coalesce; superseded previews cancel their own compiler children.
  Full builds interrupt matching automatic previews and wait for their cleanup.
  Switching source tabs does not reopen the old preview.
- A BBEdit-only contextual service provides Preview Selection through Services.
- Bundled installers support optional save attachments and the contextual service.
- RaTeX remains an experimental placeholder, with no installation or default change.

Choose the `arm64` ZIP for Apple Silicon or `x86_64` for Intel. Extract it and
install `bbtex.bbpackage`; use the bundled `Contents/Resources/selection-preview.md`
for optional feature setup. Keep either development scripts or the full package
installed to avoid duplicate menus. Packages are built/tested on macOS 15.

Preview requires a TeX distribution with `preview.sty` and Poppler's `pdftoppm`.
The optional installers require uv. Preview-on-save uses saved preambles and
dependencies, is off by default, and does not capture unsaved dependency edits.
