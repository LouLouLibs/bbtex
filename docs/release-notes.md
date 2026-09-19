BBEdit equation previews now use a compact reusable image window, with cached
single-pass rendering for pdfLaTeX, XeLaTeX, and LuaLaTeX. Tectonic is also
supported. Full-document PDFs continue to use Skim.

- Optional preview on save follows the complete display equation at the cursor.
- Rapid saves coalesce; superseded output is discarded and full builds wait for
  active save previews. Switching source tabs does not reopen the old preview.
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
