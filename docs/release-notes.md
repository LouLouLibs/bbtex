**bbtex v0.1.0** is the first release: LaTeX builds, Skim sync, equation
previews, a project outline and citation pickers for BBEdit on Apple Silicon.
Like everything here, it is totally vibe coded; see
[About bbtex](https://louloulibs.github.io/bbtex/about#totally-vibe-coded).

**LaTeX — Toggle Live Selection Preview** makes the reusable preview window
follow the BBEdit selection instead of waiting for a save. Delimited math
renders as selected; raw text renders as math inside a math selection and as
a prose paragraph otherwise. The fragment comes from the live buffer, while
the preamble and dependencies still come from saved files. Enabling it turns
off Preview on Save, and a full build pauses rendering ("Project busy")
without cancelling it. See [live selection](https://louloulibs.github.io/bbtex/selection-preview#live-selection).

The persistent **Project Outline Window** adds an expandable searchable tree,
automatic saved-source refresh and one window per project. Source jumps retain
dirty/stale checks; HTML escaping and a nonce CSP protect displayed TeX text.
Doctor now discovers custom package layouts and reports save-hook receipt changes
and attachment conflicts. See setup troubleshooting for fresh-machine acceptance.

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
Both run in the bbtex binary with no Python dependency: citation search uses the
bundled bibtexparser-ml splitter, and reference search uses the shared project
index. Both use saved project definitions and reject ambiguous duplicate keys.

- Optional preview on save follows the complete display equation at the cursor.
- Change/Toggle/Close Environment now match nested tags while skipping comments
  and common literal regions. Rename/toggle are single undoable edits, preserve
  cursor position, and refuse stale buffers or malformed nesting.
- Wrap in Environment preserves selected lines and indentation, or inserts a paired
  environment on a blank line. New hyperlink/image clippings provide native argument
  placeholders. Cancelled or invalid environment clippings preserve selected text.
- Builds recover missing nested include auxiliary directories inside isolated
  output folders. A new real pdfLaTeX/BibTeX/Biber CI corpus covers article, book,
  Beamer, previews, diagnostic mapping, and cancellation.
- Real-engine CI now also runs the full corpus under XeLaTeX and LuaLaTeX,
  including a native Unicode/fontspec fixture and separate diagnostic artifacts.
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

Current releases support Apple Silicon (`arm64`); Intel artifacts are not currently
verified. Extract the ZIP and
install `bbtex.bbpackage`; use the bundled `Contents/Resources/selection-preview.md`
for optional feature setup. Keep either development scripts or the full package
installed to avoid duplicate menus. Packages are built and tested on the macOS
version of the Mac that ran the release checks; older versions are unverified.

Preview requires a TeX distribution with `preview.sty` and Poppler's `pdftoppm`.
The optional installers are bash and the bbtex binary; they need no Python or
uv. Preview-on-save uses saved preambles and
dependencies, is off by default, and does not capture unsaved dependency edits.
