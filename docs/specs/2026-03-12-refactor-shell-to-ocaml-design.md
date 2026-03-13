# bbtex refactor: move shell logic into OCaml

## Goal

Move compilation orchestration, error handling, and BBEdit integration logic
from shell scripts into the OCaml binary. The shell wrappers shrink to thin
glue that calls `bbtex` and runs the AppleScript it generates. The project
moves from `~/.config/bbedit/bbtex-ocaml/` to `~/projects_claude/bbtex-ocaml/`;
only compiled artifacts and thin wrapper scripts get linked into BBEdit's
config.

## Project structure

```
~/projects_claude/bbtex-ocaml/
  bin/main.ml
  lib/
    types.ml              existing, extended with new types
    log_parser.ml          existing, unchanged
    directive_parser.ml    existing, unchanged
    bbedit_format.ml       existing, extended with new formatters
    compiler.ml            NEW — resolves directives, runs latexmk/tectonic
    source_reader.ml       NEW — reads source lines, escapes for PCRE
    applescript.ml         NEW — generates AppleScript for BBEdit integration
    log.ml                 NEW — structured logging to stderr
  scripts/
    bbtex-bbedit-compile.sh    thin wrapper (~20 lines)
    bbtex-bbedit-forward.sh    thin wrapper (~10 lines, mostly unchanged)
    install.sh                 updated for new location
  test/
  testdata/
  docs/
```

Scripts that go away (absorbed into OCaml):
- `bbtex-compile.sh`
- `bbtex-forward-search.sh`

`install.sh` creates these symlinks:
- `_build/default/bin/main.exe` -> `~/.local/bin/bbtex`
- `scripts/bbtex-bbedit-compile.sh` -> `~/Library/Application Support/BBEdit/Scripts/LaTeX — Compile.sh`
- `scripts/bbtex-bbedit-forward.sh` -> `~/Library/Application Support/BBEdit/Scripts/LaTeX — Forward Search.sh`

## Subcommands

### `bbtex compile <file.tex> [--verbose]`

Full compilation pipeline:

1. Validate the file exists and ends in `.tex`
2. Resolve `%!TEX` directives (root, engine)
3. Log each step to stderr
4. Run latexmk or tectonic via `Unix.create_process`
4. Parse the resulting log file
5. For entries with file+line, read the source line and escape for PCRE
6. Generate AppleScript for BBEdit's search results browser
7. Output structured results to stdout

Exit codes:
- `0` — compilation succeeded (possibly with warnings)
- `1` — compilation had LaTeX errors
- `2` — bbtex itself failed (missing tools, bad arguments, unreadable files)

### `bbtex forward-search <file.tex> <line> [--verbose]`

1. Validate the file exists and ends in `.tex`
2. Resolve `%!TEX root` directive
3. Find PDF and synctex data
4. Run `synctex view` via `Unix.create_process`
5. Output key-value protocol to stdout (same format as `compile`)

Output protocol:
```
status: success
pdf: /absolute/path/to/main.pdf
page: 3
x: 150.0
y: 400.0
```

On failure (PDF not found, synctex not installed, synctex returned no results):
```
status: error
message: PDF not found: /path/to/main.pdf — compile the document first
```

Exit codes: same as `compile` (0 success, 2 bbtex failure). Exit 1 is not
used since forward-search has no LaTeX error concept.

### `bbtex parse-log <file.log> [--format bbedit|text]`

Unchanged. Standalone log parsing for terminal use.

### `bbtex directives <file.tex>`

Unchanged. Standalone directive extraction.

## Output protocol

`bbtex compile` writes structured key-value lines to stdout:

```
status: success
summary: 0 error(s), 2 warning(s), 1 bad box(es)
log: /absolute/path/to/main.log
pdf: /absolute/path/to/main.pdf
applescript_file: /tmp/bbtex-abc123.scpt
```

Fields:
- `status` — `success` or `error`
- `summary` — human-readable count of errors/warnings/bad boxes
- `log` — absolute path to the log file
- `pdf` — absolute path to the PDF
- `applescript_file` — path to a temp file containing the complete AppleScript
  that populates BBEdit's search results browser and optionally opens a scratch
  document for warnings without line numbers. Written by OCaml because
  AppleScript is multi-line and cannot be transported in a single-line protocol
  value. The wrapper runs it with `osascript <path>`. Omitted if there are no
  results to display.

On exit code 2 (bbtex internal failure):
```
status: error
message: latexmk not found in PATH
```

## New OCaml modules

### `types.ml` — extended types

New types added to the existing module:

```ocaml
type engine = Pdflatex | Xelatex | Lualatex | Tectonic

(** Map a %!TEX program directive value to an engine.
    Unknown values log a warning and default to Pdflatex. *)
val engine_of_string : string -> engine

type compilation_config = {
  source_file : string;   (* the file the user asked to compile *)
  root_file : string;     (* resolved %!TEX root, absolute path *)
  engine : engine;
  log_file : string;      (* absolute path *)
  pdf_file : string;      (* absolute path *)
}

type compile_status = Success | Failure

type search_entry = {
  file : string;
  line : int;
  pattern : string;
}

type loose_warning = {
  file : string;
  message : string;
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

### `compiler.ml` — compilation orchestration

- `resolve_compilation : string -> compilation_config` — reads directives,
  resolves root file to absolute path, determines engine via
  `engine_of_string`. Logs each step.
- `run_compilation : compilation_config -> int` — executes latexmk or tectonic
  via `Unix.create_process`, returns exit code. Logs the exact command. Passes
  `-cd` to latexmk so it changes to the source file's directory (needed for
  `\input` with relative paths). Tectonic handles this itself. If the
  executable is not found, catches `Unix.Unix_error(ENOENT, ...)` and returns
  a meaningful error rather than crashing.
- `compile : string -> compile_result` — full pipeline: resolve, run, parse
  log, read source lines, build result.

Requires `(libraries unix)` in `lib/dune`.

### `source_reader.ml` — source line reading and PCRE escaping

- `read_source_line : string -> int -> string option` — reads line N from a
  file. Returns `None` if file or line doesn't exist.
- `escape_pcre : string -> string` — escapes a string for use in a PCRE regex.
  Replaces: `\ . * + ? ( ) [ ] ^ $ | { }` with backslash-escaped versions.
- `build_search_entries : root_dir:string -> log_entry list -> search_entry list`
  — takes parsed log entries, resolves relative file paths against `root_dir`
  (the directory of the root .tex file), reads each source line, escapes,
  deduplicates. Two entries are duplicates if they have the same absolute file
  path and line number. Logs each file read.
- `build_loose_warnings : log_entry list -> loose_warning list` — collects
  entries without a valid file+line number.

### `applescript.ml` — AppleScript generation

- `close_results_windows : string` — generates script to close previous
  "Search Results" windows.
- `search_results : search_entry list -> string` — generates the `find`
  command with OR'd PCRE patterns and file list, with `showing results`.
- `loose_warnings_doc : loose_warning list -> string` — generates script to
  open a scratch "LaTeX Warnings" document.
- `compile_script : search_entry list -> loose_warning list -> string` —
  combines into one complete AppleScript. Returns empty string if no entries.

All generated AppleScript is properly escaped (backslashes and double quotes
in file paths and patterns).

### `bbedit_format.ml` — existing, extended

Keeps existing functions:
- `format_bbedit_all`
- `format_text_all`
- `format_directives_text`

Adds:
- `format_compile_result : compile_result -> applescript_file:string option -> string list`
  — generates the output protocol lines.

### `log.ml` — structured logging

- `info : string -> unit` — prints `bbtex: <msg>` to stderr. Always active.
- `verbose : string -> unit` — prints `bbtex: <msg>` to stderr only when
  `--verbose` flag is set.
- `error : string -> unit` — prints `bbtex: error: <msg>` to stderr.
- `set_verbose : unit -> unit` — enables verbose mode (sets a global ref).

Verbose mode is a deliberate global ref. `main.ml` calls `Log.set_verbose ()`
at argument-parsing time. All other modules (`compiler.ml`, `source_reader.ml`,
`applescript.ml`) call `Log.info` and `Log.verbose` directly without threading
a verbosity parameter.

Logging output (always, to stderr):
```
bbtex: resolving directives for /path/to/file.tex
bbtex: root = /path/to/main.tex
bbtex: engine = pdflatex (via latexmk)
bbtex: running: latexmk -pdflatex -interaction=nonstopmode -file-line-error -synctex=1 -cd /path/to/main.tex
bbtex: latexmk exited with code 0
bbtex: parsing /path/to/main.log
bbtex: found 2 errors, 1 warning, 3 bad boxes
bbtex: reading source lines for 5 entries
```

With `--verbose`, additionally: each directive found, each file stack push/pop
during log parsing, each source line read, the full escaped pattern, the
generated AppleScript.

## Thin shell wrappers

### `bbtex-bbedit-compile.sh`

```bash
#!/bin/bash
set -euo pipefail

REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
BBTEX="$(dirname "$REAL_DIR")/_build/default/bin/main.exe"

[[ -z "${BB_DOC_PATH:-}" ]] && { osascript -e 'display alert "No document open" message "Open a .tex file first." as warning'; exit 1; }

mkdir -p "$HOME/.local/state/bbtex"
osascript -e 'tell application "BBEdit" to save front document' 2>/dev/null || true

OUTPUT=$("$BBTEX" compile "$BB_DOC_PATH" 2>"$HOME/.local/state/bbtex/last-compile.log")
EXIT=$?

STATUS=$(echo "$OUTPUT" | grep "^status: " | cut -d' ' -f2-)
SUMMARY=$(echo "$OUTPUT" | grep "^summary: " | cut -d' ' -f2-)
LOG=$(echo "$OUTPUT" | grep "^log: " | cut -d' ' -f2-)
PDF=$(echo "$OUTPUT" | grep "^pdf: " | cut -d' ' -f2-)
APPLESCRIPT_FILE=$(echo "$OUTPUT" | grep "^applescript_file: " | cut -d' ' -f2-)
MESSAGE=$(echo "$OUTPUT" | grep "^message: " | cut -d' ' -f2-)

if [[ $EXIT -eq 2 ]]; then
    osascript -e "display alert \"bbtex error\" message \"${MESSAGE:-unknown error}\" as warning" &
    exit 1
fi

[[ -n "$APPLESCRIPT_FILE" && -f "$APPLESCRIPT_FILE" ]] && osascript "$APPLESCRIPT_FILE" 2>/dev/null &
[[ -n "$LOG" ]] && bbedit --tail "$LOG" 2>/dev/null &
[[ -n "$PDF" && -f "$PDF" ]] && open -a Skim "$PDF" 2>/dev/null &

if [[ "$STATUS" == "success" ]]; then
    osascript -e "display notification \"$SUMMARY\" with title \"LaTeX: Success\" sound name \"Glass\"" &
else
    osascript -e "display notification \"$SUMMARY\" with title \"LaTeX: Errors\" sound name \"Basso\"" &
fi

exit 0
```

### `bbtex-bbedit-forward.sh`

```bash
#!/bin/bash
set -euo pipefail

REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
BBTEX="$(dirname "$REAL_DIR")/_build/default/bin/main.exe"

[[ -z "${BB_DOC_PATH:-}" ]] && exit 1

OUTPUT=$("$BBTEX" forward-search "$BB_DOC_PATH" "${BB_DOC_SELSTART_LINE:-1}" 2>/dev/null)
PDF=$(echo "$OUTPUT" | grep "^pdf: " | cut -d' ' -f2-)
PAGE=$(echo "$OUTPUT" | grep "^page: " | cut -d' ' -f2-)
LINE="${BB_DOC_SELSTART_LINE:-1}"

SKIM="/Applications/Skim.app/Contents/SharedSupport/displayline"
if [[ -x "$SKIM" ]]; then
    "$SKIM" -r "$LINE" "$PDF" "$BB_DOC_PATH"
else
    open -a Skim "$PDF"
fi
```

## Error handling

### OCaml side

- Functions that can fail return `result` types or raise well-defined
  exceptions caught at the top level in `main.ml`.
- No silent swallowing. Every failure is logged to stderr and reflected in the
  output protocol.
- Exit codes: 0 (success), 1 (LaTeX errors), 2 (bbtex internal failure).
- On exit 2, stdout includes `status: error` and `message:` explaining the
  problem.

### Shell side

- Stderr from `bbtex` always goes to `~/.local/state/bbtex/last-compile.log`.
- Exit code 2 triggers a macOS alert showing the `message:` line.
- No `|| true` on the main `bbtex compile` call.

### Debugging workflow

- Check `~/.local/state/bbtex/last-compile.log` for the full trace.
- Run `tail -f ~/.local/state/bbtex/last-compile.log` in a terminal, then
  compile from BBEdit for live output.
- Run `bbtex compile file.tex --verbose` from the command line for maximum
  detail.

## Migration

1. Move project to `~/projects_claude/bbtex-ocaml/` (done)
2. Initialize git repo (done)
3. Add `(libraries unix)` to `lib/dune`
4. Implement `log.ml`
5. Extend `types.ml` with new types
6. Implement `source_reader.ml`
7. Implement `applescript.ml`
8. Implement `compiler.ml`
9. Extend `bbedit_format.ml` with protocol formatter
10. Update `main.ml` with new subcommands (`compile`, `forward-search`)
11. Rewrite thin wrapper scripts
12. Remove `bbtex-compile.sh` and `bbtex-forward-search.sh`
13. Update `install.sh` for new paths
14. Update tests
15. Update README
16. Run `install.sh` to re-link
17. Remove old `~/.config/bbedit/bbtex-ocaml/` directory
