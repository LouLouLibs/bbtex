# Real-engine regression corpus

These original fixtures use the repository's license and contain no user documents
or third-party publisher templates. The article exercises two-column constraints,
BibTeX, root directives, shared external inputs, accented text and references.
The book uses includes, a table of contents, biblatex/Biber and Unicode metadata.
The Beamer deck exercises widescreen geometry and fragile/verbatim content.

The runner copies this tree into an isolated path containing spaces and Unicode,
creates output-directory configuration there, and generates a larger multi-file
variant. Never run automated mutations against `examples/ui-check`.
