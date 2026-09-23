# Citation and reference pickers

**Scripts → LaTeX — Insert Citation** searches citation keys, authors, titles,
years, and bibliography filenames. Select several results with Shift/Command
to insert multiple keys. **Insert Reference** searches saved labels together with
their section, equation, figure/table caption, and source location. Existing
native TexLab completion and its shortcut remain the quick path.

Place the cursor inside a key argument or at a normal insertion point:

- Inside `\citet*[see][p. 4]{old}`, choosing `new` produces
  `\citet*[see][p. 4]{old,new}`. Existing keys are kept and duplicates removed.
  Select a whole key to replace it; a partially selected key is rejected.
- Inside `\eqref{old}`, choosing `eq:energy` replaces only the key. `\ref`,
  `\pageref`, `\autoref`, `\nameref`, and `\vref` retain their commands.
  `\cref`/`\Cref` retain existing keys and append the chosen label.
- At an ordinary empty insertion point, the commands insert `\cite{...}` or
  `\ref{...}`. They do not replace selected prose. An unfinished `\cite{` at
  the end of the buffer can be completed, including its closing brace.

Common natbib/biblatex single-argument citation commands are recognized:
cite/citep/citet/citealp/citealt/citeauthor/citeyear/citeyearpar/parencite/textcite/
autocite/footcite/footfullcite/fullcite/smartcite/supercite/nocite, with a star and
up to two optional arguments. Custom commands and multi-command forms such as
`\cites` are outside the supported insertion scope; use native completion for
those commands. The picker does not choose a citation style or change package
configuration. Comments and common verbatim regions are excluded.

Insertion is one undoable editor change. Cancel leaves the document untouched.
An already-dirty source buffer is supported: the picker captures its text and
selection, then refuses to insert if either changes while the dialog is open.
It also rechecks the saved files used to build the results. BBEdit scripting
ranges use UTF-16 units; tests include accented text and emoji before the cursor.

## Saved project data

References reuse the [project outline index](project-navigation.md). Citation
resources come from literal `\bibliography{one,two}` and
`\addbibresource[options]{file.bib}` declarations in that same root/include graph.
Both pickers use saved definitions, including when the insertion buffer is dirty.
Save new labels or resource declarations before searching for them. No source,
bibliography, or unrelated document is saved automatically.

Missing resources, malformed bibliography entries, and incomplete project inputs
produce a partial-index notice. Valid entries elsewhere remain available.
Duplicate citation keys and labels are shown with their locations but cannot be
inserted until made unambiguous. Fix the definitions rather than relying on which
duplicate a compiler might choose.

## Bibliography parser and boundaries

Citation search runs in the bbtex binary (`bbtex citation-picker`). Bibliography
blocks come from [bibtexparser-ml](https://github.com/LouLouLibs/bibtexparser-ml),
vendored in `vendor/bibtexparser-ml`: an OCaml port of the splitter in
[python-bibtexparser](https://github.com/sciunto-org/python-bibtexparser) 2.0.1,
made for bbtex. Its own repository tests it for identical output against
bibtexparser 2.0.1 on edge cases, fuzzed input and real bibliographies.

The splitter handles entry boundaries, fields, nested braces, quoted values,
duplicates, and malformed-block recovery. A bounded value resolver handles
`@string` references and `#` concatenation across the declared files. Search
metadata supports direct `crossref` and comma-separated `xdata` inheritance with
child values taking precedence; missing/ambiguous parents and cycles are reported.
This is metadata fallback for search, not a full implementation of biblatex's
type-specific inheritance rules. TeX markup is retained. Search uses full Unicode
case folding, like Python's `str.casefold`: `σοφία` finds `ΣΟΦΊΑ` and `strasse`
finds `Straße`. Accents still count, so `garcia` does not find `García`. The
folding table is generated from Unicode's `CaseFolding.txt` by
`scripts/gen-casefold.sh`.
UTF-8 (including BOM) bibliography files are supported.

Each bibliography is limited to 32 MiB, inheritance/string expansion to 32 levels,
and a dialog to 300 matches; use a narrower query for larger result sets. The
10,000-entry regression fixture is indexed and searched in about 0.05 seconds
locally, excluding dialog interaction.

## Setup and checks

Development commands are installed by `scripts/install-workflow-commands.sh`.
Release packages include both commands and their helpers. Both searches use the
OCaml binary directly; neither needs Python or uv. Errors are logged to
`~/.local/state/bbtex/picker.log`.

`dune runtest` checks edit planning, the shared index, and citation metadata
(string expansion, inheritance, duplicates, recovery and size limits).
`uv run test/integration/check_pickers.py` tests the command-line output and
compiles the generated dialogs.
Set `BBTEX_TEST_NATIVE=1` to exercise multi-citation insertion, reference replacement,
Undo, cancellation, Unicode ranges, and concurrent buffer/selection changes in
disposable BBEdit documents. The automated test substitutes dialog choices;
the actual menu interactions are checked separately.
