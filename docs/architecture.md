# bbtex Architecture

## Overview

```
OCaml binary (bbtex)              Shell scripts
┌──────────────────────────┐      ┌─────────────────────────────┐
│ types.ml                 │      │ bbtex-bbedit-compile.sh     │
│   algebraic types for    │      │   thin wrapper: saves doc,  │
│   errors, warnings,      │      │   calls bbtex compile,      │
│   bad boxes, directives, │      │   runs AppleScript, opens   │
│   compile results        │      │   PDF, shows notification   │
│                          │      │                             │
│ log_parser.ml            │      │ bbtex-bbedit-forward.sh     │
│   single-pass parser     │◄─────│   thin wrapper: calls bbtex │
│   with file stack        │      │   forward-search, tells     │
│                          │      │   Skim to jump to line      │
│ directive_parser.ml      │      └─────────────────────────────┘
│   %!TEX root/program     │
│                          │
│ source_reader.ml         │
│   reads source lines for │
│   AppleScript generation │
│                          │
│ compiler.ml              │
│   runs latexmk/tectonic, │
│   parses log, produces   │
│   structured result      │
│                          │
│ applescript.ml           │
│   generates AppleScript  │
│   for BBEdit results     │
│   browser                │
│                          │
│ log.ml                   │
│   logging helpers        │
│                          │
│ bbedit_format.ml         │
│   output formatting and  │
│   compile result protocol│
└──────────────────────────┘
```

**OCaml handles all logic.** Shell scripts are thin wrappers that invoke
the binary, parse its key:value output, and call AppleScript/Skim/bbedit.
This split puts the hard problems — parsing LaTeX's messy log format,
orchestrating compilation, generating AppleScript — in a language with
strong types and pattern matching, while keeping the glue code minimal.

## Design decisions

### Why OCaml for the parser

LaTeX log parsing is fundamentally a parsing problem: you maintain a file
stack, classify lines by pattern, track multi-line state, and produce
structured output. OCaml's algebraic types (`severity`, `line_kind`,
`box_kind`) map directly to the problem domain. Pattern matching makes the
line classifier exhaustive — the compiler tells you if you miss a case.

### Why shell scripts for orchestration

The BBEdit wrappers are thin glue: resolve paths, call the binary, parse
key:value output lines, invoke AppleScript/Skim. Shell is the natural home
for this. It's transparent (you can read exactly what commands run), easy
to modify (no recompilation), and avoids pulling system-level concerns
into the OCaml code.

### Why latexmk instead of custom multi-pass logic

latexmk already handles the hard parts of LaTeX compilation: detecting
when to re-run, when to invoke bibtex/biber, file dependency tracking,
convergence detection. Reimplementing this would be a significant effort
with subtle bugs. We use latexmk for pdflatex/xelatex/lualatex and call
tectonic directly (tectonic handles its own multi-pass logic).

### No external OCaml dependencies

The tool uses only the OCaml standard library. No opam packages. This
keeps the build simple (`dune build` with no dependency resolution) and
makes the code easier to audit and understand.

### No JSON output format

We considered and rejected JSON output. The two formats we need are:

- **bbedit**: `file:line: severity: message` — consumed by BBEdit's
  results browser.
- **text**: ANSI-colored human-readable output — for terminal use and
  debugging.

If structured machine-readable output becomes necessary (e.g., for editor
plugins or CI integration), **JSON Lines (JSONL)** would be the right
choice — one JSON object per log entry, one per line. JSONL is simpler to
produce and consume than a single JSON document, works naturally with
streaming and line-oriented tools (`grep`, `head`, `wc -l`), and doesn't
require holding the full output in memory. We'd add this as a third
`--format jsonl` option when there's a concrete use case.

### Exit codes

- `0` — compilation succeeded (possibly with warnings/bad boxes)
- `1` — compilation had errors
- `2` — bbtex internal error (bad arguments, file not found, etc.)

This lets you use bbtex in shell conditionals and CI scripts.

## Log parser details

LaTeX logs are notoriously messy. The parser handles:

- **File tracking:** LaTeX prints `(filename` when entering a file and
  `)` when leaving. The parser maintains a stack to attribute each
  message to the correct source file. Filenames are identified by the
  heuristic "contains `.` or `/`" to distinguish from grouping parens.

- **Multi-line errors:** Error messages start with `!` and may span
  several lines, terminated by a `l.<N>` line indicator. The parser
  tolerates blank lines and help text between the `!` line and the
  `l.<N>` line.

- **Warnings:** `LaTeX Warning:`, `Package <pkg> Warning:`, `LaTeX Font
  Warning:` — these can span multiple continuation lines (detected by
  leading whitespace).

- **Bad boxes:** `Overfull \hbox` / `Underfull \vbox` with line number
  extraction from `at lines N--M` or `at line N`.

- **Warning line numbers:** Extracted from `on input line N` when present
  in the warning text.

## Type reference

```ocaml
type severity = Error | Warning | BadBox
type box_kind = Overfull | Underfull
type box_type = Hbox | Vbox

type log_entry = {
  severity : severity;
  file : string option;
  line : int option;
  message : string;
  context : string list;
}

type directive_key = Root | Program | Encoding | Other of string
type directive = { key : directive_key; value : string }
type output_format = Bbedit | Text

type compile_status = Success | Failure

type search_entry = {
  se_file : string;
  se_line : int;
  se_pattern : string;
}

type loose_warning = {
  lw_file : string;
  lw_message : string;
}

type compile_result = {
  status : compile_status;
  summary : string;
  log_file : string;
  pdf_file : string;
  search_results : search_entry list;
  loose_warnings : loose_warning list;
}
```
