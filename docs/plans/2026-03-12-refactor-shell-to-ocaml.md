# bbtex refactor: move shell logic into OCaml — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move compilation orchestration, source-line reading, AppleScript generation, and error handling from shell scripts into OCaml, leaving only thin BBEdit wrappers in shell.

**Architecture:** The OCaml binary gains `compile` and `forward-search` subcommands that do all heavy lifting. They output a simple key-value protocol on stdout and log to stderr. Shell wrappers parse the protocol, run generated AppleScript, and handle BBEdit-specific UI (save, notify, open Skim).

**Tech Stack:** OCaml 5.0+ (stdlib + unix), dune 3.0+, no external packages.

**Spec:** `docs/specs/2026-03-12-refactor-shell-to-ocaml-design.md`

**Test framework:** Custom inline assert framework (no external test lib). Pattern: `open Bbtex`, define `assert_equal`/`assert_true`/`run_test`, runner at bottom calling `run_test` for each case. Exit 1 on failure.

**Build/test commands:**
- Build: `dune build`
- Test: `dune runtest`
- Run specific test: `dune exec test/test_<name>.exe`

---

## Chunk 1: Foundation modules (log.ml, types.ml extensions)

### Task 1: Add `unix` dependency to lib/dune

**Files:**
- Modify: `lib/dune`

- [ ] **Step 1: Update lib/dune to add unix dependency**

Change `lib/dune` from:
```
(library
 (name bbtex))
```
to:
```
(library
 (name bbtex)
 (libraries unix))
```

- [ ] **Step 2: Verify build still passes**

Run: `dune build`
Expected: success, no errors.

- [ ] **Step 3: Verify existing tests still pass**

Run: `dune runtest`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/dune
git commit -m "Add unix library dependency to lib/dune"
```

---

### Task 2: Implement log.ml

**Files:**
- Create: `lib/log.ml`
- Create: `test/test_log_module.ml`
- Modify: `test/dune`

- [ ] **Step 1: Write the test file**

Create `test/test_log_module.ml`:

```ocaml
open Bbtex

let tests_passed = ref 0
let tests_failed = ref 0

let assert_equal ~msg expected actual =
  if expected <> actual then begin
    Printf.eprintf "FAIL: %s\n  expected: %s\n  actual:   %s\n" msg expected actual;
    incr tests_failed
  end else
    incr tests_passed

let assert_true ~msg cond =
  if not cond then begin
    Printf.eprintf "FAIL: %s\n" msg;
    incr tests_failed
  end else
    incr tests_passed

let run_test name f =
  Printf.printf "  %s ... " name;
  (try
     f ();
     Printf.printf "ok\n"
   with e ->
     Printf.eprintf "EXCEPTION: %s\n" (Printexc.to_string e);
     incr tests_failed)

(* Capture stderr output by redirecting to a temp file *)
let capture_stderr f =
  let tmp = Filename.temp_file "bbtex_test" ".stderr" in
  let old_stderr = Unix.dup Unix.stderr in
  let fd = Unix.openfile tmp [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
  Unix.dup2 fd Unix.stderr;
  Unix.close fd;
  Fun.protect ~finally:(fun () ->
    Unix.dup2 old_stderr Unix.stderr;
    Unix.close old_stderr
  ) (fun () -> f ());
  let ic = open_in tmp in
  let content = Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
    let buf = Buffer.create 256 in
    (try while true do Buffer.add_string buf (input_line ic); Buffer.add_char buf '\n' done
     with End_of_file -> ());
    Buffer.contents buf
  ) in
  Sys.remove tmp;
  content

let test_info_prints_to_stderr () =
  let output = capture_stderr (fun () -> Log.info "hello world") in
  assert_true ~msg:"info output contains prefix"
    (String.starts_with ~prefix:"bbtex:" output);
  assert_true ~msg:"info output contains message"
    (let sub = "hello world" in
     let rec check i =
       if i > String.length output - String.length sub then false
       else if String.sub output i (String.length sub) = sub then true
       else check (i + 1)
     in check 0)

let test_error_prints_to_stderr () =
  let output = capture_stderr (fun () -> Log.error "something broke") in
  assert_true ~msg:"error output contains 'error'"
    (let sub = "error:" in
     let rec check i =
       if i > String.length output - String.length sub then false
       else if String.sub output i (String.length sub) = sub then true
       else check (i + 1)
     in check 0);
  assert_true ~msg:"error output contains message"
    (let sub = "something broke" in
     let rec check i =
       if i > String.length output - String.length sub then false
       else if String.sub output i (String.length sub) = sub then true
       else check (i + 1)
     in check 0)

let test_verbose_silent_by_default () =
  let output = capture_stderr (fun () -> Log.verbose "should not appear") in
  assert_equal ~msg:"verbose silent by default" "" output

let test_verbose_prints_after_set () =
  Log.set_verbose ();
  let output = capture_stderr (fun () -> Log.verbose "now visible") in
  assert_true ~msg:"verbose output non-empty after set_verbose"
    (String.length output > 0);
  assert_true ~msg:"verbose output contains message"
    (let sub = "now visible" in
     let rec check i =
       if i > String.length output - String.length sub then false
       else if String.sub output i (String.length sub) = sub then true
       else check (i + 1)
     in check 0);
  (* Reset for other tests — verbose_enabled is a global ref *)
  Log.reset_verbose ()

let () =
  Printf.printf "Log module tests:\n";
  run_test "info prints to stderr" test_info_prints_to_stderr;
  run_test "error prints to stderr" test_error_prints_to_stderr;
  run_test "verbose silent by default" test_verbose_silent_by_default;
  run_test "verbose prints after set_verbose" test_verbose_prints_after_set;
  Printf.printf "\nResults: %d passed, %d failed\n" !tests_passed !tests_failed;
  if !tests_failed > 0 then exit 1
```

- [ ] **Step 2: Add test to dune**

Change `test/dune` from:
```
(tests
 (names test_log_parser test_directive_parser test_format)
 (libraries bbtex))
```
to:
```
(tests
 (names test_log_parser test_directive_parser test_format test_log_module)
 (libraries bbtex unix))
```

Note: `unix` is needed here because the test uses `Unix.dup`/`Unix.dup2` to capture stderr.

- [ ] **Step 3: Run test to verify it fails**

Run: `dune runtest`
Expected: FAIL — `Log` module not found.

- [ ] **Step 4: Implement log.ml**

Create `lib/log.ml`:

```ocaml
(** Structured logging to stderr.

    All log output goes to stderr so it doesn't interfere with
    the stdout protocol. Verbose mode is controlled by a global
    ref, set once at startup from main.ml. *)

let verbose_enabled = ref false

let set_verbose () = verbose_enabled := true

let reset_verbose () = verbose_enabled := false

let info msg =
  Printf.eprintf "bbtex: %s\n%!" msg

let verbose msg =
  if !verbose_enabled then
    Printf.eprintf "bbtex: %s\n%!" msg

let error msg =
  Printf.eprintf "bbtex: error: %s\n%!" msg
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `dune runtest`
Expected: all tests pass (existing + new log module tests).

- [ ] **Step 6: Commit**

```bash
git add lib/log.ml test/test_log_module.ml test/dune
git commit -m "Add log.ml: structured logging to stderr"
```

---

### Task 3: Extend types.ml with new types

**Files:**
- Modify: `lib/types.ml`
- Create: `test/test_types.ml`
- Modify: `test/dune`

- [ ] **Step 1: Write the test file**

Create `test/test_types.ml`:

```ocaml
open Bbtex

let tests_passed = ref 0
let tests_failed = ref 0

let assert_equal ~msg expected actual =
  if expected <> actual then begin
    Printf.eprintf "FAIL: %s\n  expected: %s\n  actual:   %s\n" msg expected actual;
    incr tests_failed
  end else
    incr tests_passed

let run_test name f =
  Printf.printf "  %s ... " name;
  (try
     f ();
     Printf.printf "ok\n"
   with e ->
     Printf.eprintf "EXCEPTION: %s\n" (Printexc.to_string e);
     incr tests_failed)

let test_engine_of_string_known () =
  assert_equal ~msg:"pdflatex"
    "pdflatex" (Types.string_of_engine (Types.engine_of_string "pdflatex"));
  assert_equal ~msg:"xelatex"
    "xelatex" (Types.string_of_engine (Types.engine_of_string "xelatex"));
  assert_equal ~msg:"lualatex"
    "lualatex" (Types.string_of_engine (Types.engine_of_string "lualatex"));
  assert_equal ~msg:"tectonic"
    "tectonic" (Types.string_of_engine (Types.engine_of_string "tectonic"))

let test_engine_of_string_case_insensitive () =
  assert_equal ~msg:"XeLaTeX"
    "xelatex" (Types.string_of_engine (Types.engine_of_string "XeLaTeX"));
  assert_equal ~msg:"PDFLATEX"
    "pdflatex" (Types.string_of_engine (Types.engine_of_string "PDFLATEX"))

let test_engine_of_string_unknown_defaults () =
  (* Unknown values should default to Pdflatex *)
  assert_equal ~msg:"unknown defaults to pdflatex"
    "pdflatex" (Types.string_of_engine (Types.engine_of_string "latexmk"));
  assert_equal ~msg:"empty defaults to pdflatex"
    "pdflatex" (Types.string_of_engine (Types.engine_of_string ""))

let test_string_of_engine () =
  assert_equal ~msg:"Pdflatex" "pdflatex" (Types.string_of_engine Types.Pdflatex);
  assert_equal ~msg:"Xelatex" "xelatex" (Types.string_of_engine Types.Xelatex);
  assert_equal ~msg:"Lualatex" "lualatex" (Types.string_of_engine Types.Lualatex);
  assert_equal ~msg:"Tectonic" "tectonic" (Types.string_of_engine Types.Tectonic)

let test_latexmk_flag () =
  assert_equal ~msg:"pdflatex flag" "-pdflatex" (Types.latexmk_flag Types.Pdflatex);
  assert_equal ~msg:"xelatex flag" "-pdfxelatex" (Types.latexmk_flag Types.Xelatex);
  assert_equal ~msg:"lualatex flag" "-pdflualatex" (Types.latexmk_flag Types.Lualatex)

let () =
  Printf.printf "Types tests:\n";
  run_test "engine_of_string known values" test_engine_of_string_known;
  run_test "engine_of_string case insensitive" test_engine_of_string_case_insensitive;
  run_test "engine_of_string unknown defaults" test_engine_of_string_unknown_defaults;
  run_test "string_of_engine" test_string_of_engine;
  run_test "latexmk_flag" test_latexmk_flag;
  Printf.printf "\nResults: %d passed, %d failed\n" !tests_passed !tests_failed;
  if !tests_failed > 0 then exit 1
```

- [ ] **Step 2: Add test to dune**

Change `test/dune` to add `test_types` to the names list:
```
(tests
 (names test_log_parser test_directive_parser test_format test_log_module test_types)
 (libraries bbtex unix))
```

- [ ] **Step 3: Run test to verify it fails**

Run: `dune runtest`
Expected: FAIL — `Types.engine_of_string` not found.

- [ ] **Step 4: Add new types and functions to types.ml**

Append to the end of `lib/types.ml`:

```ocaml
(* ── Compilation types ─────────────────────────────────────── *)

type engine = Pdflatex | Xelatex | Lualatex | Tectonic

let string_of_engine = function
  | Pdflatex -> "pdflatex"
  | Xelatex  -> "xelatex"
  | Lualatex -> "lualatex"
  | Tectonic -> "tectonic"

let engine_of_string s =
  match String.lowercase_ascii s with
  | "pdflatex" -> Pdflatex
  | "xelatex"  -> Xelatex
  | "lualatex" -> Lualatex
  | "tectonic" -> Tectonic
  | other ->
    if other <> "" then
      Log.info (Printf.sprintf "unknown engine '%s', defaulting to pdflatex" other);
    Pdflatex

(** Map an engine to the latexmk flag. Not used for Tectonic. *)
let latexmk_flag = function
  | Pdflatex -> "-pdflatex"
  | Xelatex  -> "-pdfxelatex"
  | Lualatex -> "-pdflualatex"
  | Tectonic -> "-pdflatex"  (* should not be called for Tectonic *)

type compilation_config = {
  source_file : string;
  root_file : string;
  engine : engine;
  log_file : string;
  pdf_file : string;
}

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

Note: search_entry and loose_warning fields use prefixed names (`se_`, `lw_`) to avoid ambiguity with `log_entry` fields in OCaml's structural record typing.

- [ ] **Step 5: Run tests to verify they pass**

Run: `dune runtest`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/types.ml test/test_types.ml test/dune
git commit -m "Extend types.ml with engine, compilation_config, compile_result"
```

---

## Chunk 2: source_reader.ml and applescript.ml

### Task 4: Implement source_reader.ml

**Files:**
- Create: `lib/source_reader.ml`
- Create: `test/test_source_reader.ml`
- Modify: `test/dune`

- [ ] **Step 1: Create a test fixture file**

Create `testdata/source_lines.tex`:
```latex
\documentclass{article}
\begin{document}
This is line three with $math$ and special chars.
A line with \textbf{bold} formatting.
x^2 + y^2 = z^2
\end{document}
```

- [ ] **Step 2: Write the test file**

Create `test/test_source_reader.ml`:

```ocaml
open Bbtex

let tests_passed = ref 0
let tests_failed = ref 0

let assert_equal ~msg expected actual =
  if expected <> actual then begin
    Printf.eprintf "FAIL: %s\n  expected: %s\n  actual:   %s\n" msg expected actual;
    incr tests_failed
  end else
    incr tests_passed

let assert_true ~msg cond =
  if not cond then begin
    Printf.eprintf "FAIL: %s\n" msg;
    incr tests_failed
  end else
    incr tests_passed

let assert_int_equal ~msg expected actual =
  assert_equal ~msg (string_of_int expected) (string_of_int actual)

let run_test name f =
  Printf.printf "  %s ... " name;
  (try
     f ();
     Printf.printf "ok\n"
   with e ->
     Printf.eprintf "EXCEPTION: %s\n" (Printexc.to_string e);
     incr tests_failed)

(* Path to testdata relative to where dune runs tests *)
let testdata_dir =
  let cwd = Sys.getcwd () in
  if Sys.file_exists (Filename.concat cwd "testdata") then
    Filename.concat cwd "testdata"
  else
    (* dune runs tests from _build/default/test, testdata is at project root *)
    Filename.concat (Filename.dirname (Filename.dirname (Filename.dirname cwd))) "testdata"

let fixture_file = Filename.concat testdata_dir "source_lines.tex"

let test_read_source_line_valid () =
  let line = Source_reader.read_source_line fixture_file 1 in
  assert_equal ~msg:"line 1" (Some "\\documentclass{article}") line

let test_read_source_line_middle () =
  let line = Source_reader.read_source_line fixture_file 3 in
  assert_equal ~msg:"line 3"
    (Some "This is line three with $math$ and special chars.")
    line

let test_read_source_line_past_end () =
  let line = Source_reader.read_source_line fixture_file 999 in
  assert_equal ~msg:"past end returns None" None
    (match line with None -> None | Some _ -> line)

let test_read_source_line_nonexistent_file () =
  let line = Source_reader.read_source_line "/tmp/does-not-exist-bbtex.tex" 1 in
  assert_equal ~msg:"nonexistent file returns None" None
    (match line with None -> None | Some _ -> line)

let test_escape_pcre_plain () =
  assert_equal ~msg:"plain text unchanged"
    "hello world" (Source_reader.escape_pcre "hello world")

let test_escape_pcre_special () =
  assert_equal ~msg:"backslash"
    "\\\\foo" (Source_reader.escape_pcre "\\foo");
  assert_equal ~msg:"dot"
    "file\\.tex" (Source_reader.escape_pcre "file.tex");
  assert_equal ~msg:"dollar"
    "\\$math\\$" (Source_reader.escape_pcre "$math$");
  assert_equal ~msg:"caret"
    "x\\^2" (Source_reader.escape_pcre "x^2");
  assert_equal ~msg:"pipe"
    "a\\|b" (Source_reader.escape_pcre "a|b");
  assert_equal ~msg:"parens"
    "\\(foo\\)" (Source_reader.escape_pcre "(foo)");
  assert_equal ~msg:"brackets"
    "\\[1\\]" (Source_reader.escape_pcre "[1]");
  assert_equal ~msg:"braces"
    "\\{x\\}" (Source_reader.escape_pcre "{x}");
  assert_equal ~msg:"star"
    "a\\*b" (Source_reader.escape_pcre "a*b");
  assert_equal ~msg:"plus"
    "a\\+b" (Source_reader.escape_pcre "a+b");
  assert_equal ~msg:"question"
    "a\\?b" (Source_reader.escape_pcre "a?b")

let test_escape_pcre_latex_line () =
  (* A realistic LaTeX source line *)
  let input = "\\textbf{$x^2 + y^2 = z^2$}" in
  let escaped = Source_reader.escape_pcre input in
  assert_equal ~msg:"latex line"
    "\\\\textbf\\{\\$x\\^2 \\+ y\\^2 = z\\^2\\$\\}" escaped

let test_build_search_entries_basic () =
  let entries = [
    { Types.severity = Types.Error;
      file = Some "./source_lines.tex"; line = Some 3;
      message = "test"; context = [] };
  ] in
  let results = Source_reader.build_search_entries ~root_dir:testdata_dir entries in
  assert_int_equal ~msg:"one search entry" 1 (List.length results);
  let r = List.hd results in
  assert_int_equal ~msg:"line is 3" 3 r.se_line;
  assert_true ~msg:"pattern is escaped"
    (String.length r.se_pattern > 0)

let test_build_search_entries_dedup () =
  let entries = [
    { Types.severity = Types.Error;
      file = Some "./source_lines.tex"; line = Some 3;
      message = "first"; context = [] };
    { Types.severity = Types.Warning;
      file = Some "./source_lines.tex"; line = Some 3;
      message = "second"; context = [] };
  ] in
  let results = Source_reader.build_search_entries ~root_dir:testdata_dir entries in
  assert_int_equal ~msg:"deduped to one entry" 1 (List.length results)

let test_build_search_entries_skips_no_line () =
  let entries = [
    { Types.severity = Types.Warning;
      file = Some "./source_lines.tex"; line = None;
      message = "no line"; context = [] };
  ] in
  let results = Source_reader.build_search_entries ~root_dir:testdata_dir entries in
  assert_int_equal ~msg:"no entries without line" 0 (List.length results)

let test_build_loose_warnings () =
  let entries = [
    { Types.severity = Types.Error;
      file = Some "a.tex"; line = Some 1;
      message = "has line"; context = [] };
    { Types.severity = Types.Warning;
      file = Some "b.tex"; line = None;
      message = "no line"; context = [] };
    { Types.severity = Types.Warning;
      file = None; line = None;
      message = "no file either"; context = [] };
  ] in
  let loose = Source_reader.build_loose_warnings entries in
  assert_int_equal ~msg:"two loose warnings" 2 (List.length loose)

let () =
  Printf.printf "Source reader tests:\n";
  run_test "read_source_line valid" test_read_source_line_valid;
  run_test "read_source_line middle" test_read_source_line_middle;
  run_test "read_source_line past end" test_read_source_line_past_end;
  run_test "read_source_line nonexistent file" test_read_source_line_nonexistent_file;
  run_test "escape_pcre plain" test_escape_pcre_plain;
  run_test "escape_pcre special chars" test_escape_pcre_special;
  run_test "escape_pcre latex line" test_escape_pcre_latex_line;
  run_test "build_search_entries basic" test_build_search_entries_basic;
  run_test "build_search_entries dedup" test_build_search_entries_dedup;
  run_test "build_search_entries skips no line" test_build_search_entries_skips_no_line;
  run_test "build_loose_warnings" test_build_loose_warnings;
  Printf.printf "\nResults: %d passed, %d failed\n" !tests_passed !tests_failed;
  if !tests_failed > 0 then exit 1
```

- [ ] **Step 3: Add test to dune**

Add `test_source_reader` to the test names in `test/dune`.

- [ ] **Step 4: Run test to verify it fails**

Run: `dune runtest`
Expected: FAIL — `Source_reader` module not found.

- [ ] **Step 5: Implement source_reader.ml**

Create `lib/source_reader.ml`:

```ocaml
(** Read source lines from .tex files and build search patterns.

    Given log entries with file+line references, reads the actual
    source lines and escapes them as PCRE patterns for BBEdit's
    multi-file search results browser. *)

open Types

let read_source_line filename line_num =
  if not (Sys.file_exists filename) then None
  else
    try
      let ic = open_in filename in
      Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
        let rec loop n =
          match input_line ic with
          | line ->
            if n = line_num then Some line
            else loop (n + 1)
          | exception End_of_file -> None
        in
        loop 1)
    with Sys_error _ -> None

let escape_pcre s =
  let buf = Buffer.create (String.length s * 2) in
  String.iter (fun c ->
    (match c with
     | '\\' | '.' | '*' | '+' | '?' | '(' | ')' | '[' | ']'
     | '^' | '$' | '|' | '{' | '}' ->
       Buffer.add_char buf '\\'
     | _ -> ());
    Buffer.add_char buf c
  ) s;
  Buffer.contents buf

let resolve_path ~root_dir path =
  if Filename.is_relative path then
    let resolved = Filename.concat root_dir path in
    (* Normalize ./foo to just foo under root_dir *)
    if Sys.file_exists resolved then
      let dir = Filename.dirname resolved in
      let base = Filename.basename resolved in
      let abs_dir = if Filename.is_relative dir then
        Filename.concat (Sys.getcwd ()) dir
      else dir in
      (* Simplify by using realpath-like logic *)
      Filename.concat abs_dir base
    else
      resolved
  else
    path

let build_search_entries ~root_dir entries =
  let seen = Hashtbl.create 16 in
  let results = ref [] in
  List.iter (fun (entry : log_entry) ->
    match entry.file, entry.line with
    | Some file, Some line when line > 0 ->
      let abs_file = resolve_path ~root_dir file in
      let key = (abs_file, line) in
      if not (Hashtbl.mem seen key) then begin
        Hashtbl.add seen key ();
        match read_source_line abs_file line with
        | Some source_line ->
          Log.verbose (Printf.sprintf "read %s:%d" abs_file line);
          let pattern = escape_pcre source_line in
          results := { se_file = abs_file; se_line = line; se_pattern = pattern } :: !results
        | None ->
          Log.verbose (Printf.sprintf "could not read %s:%d" abs_file line)
      end
    | _ -> ()
  ) entries;
  List.rev !results

let build_loose_warnings entries =
  List.filter_map (fun (entry : log_entry) ->
    match entry.line with
    | Some n when n > 0 -> None
    | _ ->
      let file = Option.value ~default:"<unknown>" entry.file in
      Some { lw_file = file; lw_message = entry.message }
  ) entries
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `dune runtest`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/source_reader.ml test/test_source_reader.ml testdata/source_lines.tex test/dune
git commit -m "Add source_reader.ml: read source lines and escape for PCRE"
```

---

### Task 5: Implement applescript.ml

**Files:**
- Create: `lib/applescript.ml`
- Create: `test/test_applescript.ml`
- Modify: `test/dune`

- [ ] **Step 1: Write the test file**

Create `test/test_applescript.ml`:

```ocaml
open Bbtex

let tests_passed = ref 0
let tests_failed = ref 0

let assert_equal ~msg expected actual =
  if expected <> actual then begin
    Printf.eprintf "FAIL: %s\n  expected: %s\n  actual:   %s\n" msg expected actual;
    incr tests_failed
  end else
    incr tests_passed

let assert_true ~msg cond =
  if not cond then begin
    Printf.eprintf "FAIL: %s\n" msg;
    incr tests_failed
  end else
    incr tests_passed

let run_test name f =
  Printf.printf "  %s ... " name;
  (try
     f ();
     Printf.printf "ok\n"
   with e ->
     Printf.eprintf "EXCEPTION: %s\n" (Printexc.to_string e);
     incr tests_failed)

let contains ~sub s =
  let ls = String.length s and lsub = String.length sub in
  if lsub > ls then false
  else
    let rec check i =
      if i > ls - lsub then false
      else if String.sub s i lsub = sub then true
      else check (i + 1)
    in check 0

let test_close_results_windows () =
  let script = Applescript.close_results_windows in
  assert_true ~msg:"mentions BBEdit"
    (contains ~sub:"BBEdit" script);
  assert_true ~msg:"mentions Search Results"
    (contains ~sub:"Search Results" script)

let test_search_results_single () =
  let entries = [
    { Types.se_file = "/path/to/main.tex"; se_line = 42;
      se_pattern = "hello world" };
  ] in
  let script = Applescript.search_results entries in
  assert_true ~msg:"contains find"
    (contains ~sub:"find" script);
  assert_true ~msg:"contains pattern"
    (contains ~sub:"hello world" script);
  assert_true ~msg:"contains file path"
    (contains ~sub:"/path/to/main.tex" script);
  assert_true ~msg:"contains showing results"
    (contains ~sub:"showing results" script)

let test_search_results_multiple () =
  let entries = [
    { Types.se_file = "/path/to/a.tex"; se_line = 1;
      se_pattern = "first" };
    { Types.se_file = "/path/to/b.tex"; se_line = 2;
      se_pattern = "second" };
  ] in
  let script = Applescript.search_results entries in
  (* Patterns should be OR'd *)
  assert_true ~msg:"contains first pattern"
    (contains ~sub:"first" script);
  assert_true ~msg:"contains second pattern"
    (contains ~sub:"second" script);
  assert_true ~msg:"contains pipe separator"
    (contains ~sub:"|" script)

let test_search_results_escapes_quotes () =
  let entries = [
    { Types.se_file = "/path/to/main.tex"; se_line = 1;
      se_pattern = "say \\\"hello\\\"" };
  ] in
  let script = Applescript.search_results entries in
  (* The pattern should have quotes escaped for AppleScript *)
  assert_true ~msg:"script is non-empty"
    (String.length script > 0)

let test_loose_warnings_doc () =
  let warnings = [
    { Types.lw_file = "main.tex"; lw_message = "undefined refs" };
    { Types.lw_file = "ch1.tex"; lw_message = "font missing" };
  ] in
  let script = Applescript.loose_warnings_doc warnings in
  assert_true ~msg:"mentions BBEdit"
    (contains ~sub:"BBEdit" script);
  assert_true ~msg:"contains first warning"
    (contains ~sub:"undefined refs" script)

let test_compile_script_empty () =
  let script = Applescript.compile_script [] [] in
  assert_equal ~msg:"empty inputs produce empty script"
    "" script

let test_compile_script_combined () =
  let search = [
    { Types.se_file = "/path/to/main.tex"; se_line = 1;
      se_pattern = "hello" };
  ] in
  let loose = [
    { Types.lw_file = "main.tex"; lw_message = "warning text" };
  ] in
  let script = Applescript.compile_script search loose in
  assert_true ~msg:"non-empty" (String.length script > 0);
  assert_true ~msg:"contains find"
    (contains ~sub:"find" script)

let () =
  Printf.printf "AppleScript generation tests:\n";
  run_test "close_results_windows" test_close_results_windows;
  run_test "search_results single" test_search_results_single;
  run_test "search_results multiple" test_search_results_multiple;
  run_test "search_results escapes quotes" test_search_results_escapes_quotes;
  run_test "loose_warnings_doc" test_loose_warnings_doc;
  run_test "compile_script empty" test_compile_script_empty;
  run_test "compile_script combined" test_compile_script_combined;
  Printf.printf "\nResults: %d passed, %d failed\n" !tests_passed !tests_failed;
  if !tests_failed > 0 then exit 1
```

- [ ] **Step 2: Add test to dune**

Add `test_applescript` to the test names in `test/dune`.

- [ ] **Step 3: Run test to verify it fails**

Run: `dune runtest`
Expected: FAIL — `Applescript` module not found.

- [ ] **Step 4: Implement applescript.ml**

Create `lib/applescript.ml`:

```ocaml
(** Generate AppleScript for BBEdit integration.

    Produces scripts that populate BBEdit's multi-file search results
    browser and optionally open scratch documents for warnings without
    line numbers. *)

open Types

(** Escape a string for inclusion in an AppleScript double-quoted string.
    Must escape backslashes and double quotes. *)
let escape_applescript s =
  let buf = Buffer.create (String.length s * 2) in
  String.iter (fun c ->
    match c with
    | '\\' -> Buffer.add_string buf "\\\\"
    | '"'  -> Buffer.add_string buf "\\\""
    | _    -> Buffer.add_char buf c
  ) s;
  Buffer.contents buf

let close_results_windows =
  {|tell application "BBEdit"
    repeat with w in (every window whose name starts with "Search Results")
        close w
    end repeat
end tell|}

let search_results entries =
  if entries = [] then ""
  else
    let patterns = List.map (fun e -> escape_applescript e.se_pattern) entries in
    let combined_pattern = String.concat "|" patterns in
    (* Collect unique files *)
    let seen = Hashtbl.create 8 in
    let unique_files = List.filter_map (fun e ->
      if Hashtbl.mem seen e.se_file then None
      else begin
        Hashtbl.add seen e.se_file ();
        Some e.se_file
      end
    ) entries in
    let file_list = String.concat ", "
      (List.map (fun f ->
        Printf.sprintf "POSIX file \"%s\" as alias" (escape_applescript f)
      ) unique_files) in
    Printf.sprintf
      {|tell application "BBEdit"
    find "%s" searching in {%s} options {search mode:grep} with showing results
end tell|}
      combined_pattern file_list

let loose_warnings_doc warnings =
  if warnings = [] then ""
  else
    let lines = List.map (fun w ->
      Printf.sprintf "%s: %s" w.lw_file w.lw_message
    ) warnings in
    let content = escape_applescript (String.concat "\n" lines) in
    Printf.sprintf
      {|tell application "BBEdit"
    set warningDoc to make new text document with properties {name:"LaTeX Warnings", contents:"%s"}
end tell|}
      content

let compile_script search_entries loose_warnings =
  if search_entries = [] && loose_warnings = [] then ""
  else
    let parts = [
      close_results_windows;
      search_results search_entries;
      loose_warnings_doc loose_warnings;
    ] in
    let non_empty = List.filter (fun s -> s <> "") parts in
    String.concat "\n\n" non_empty

(** Write the compile script to a temp file and return the path.
    Returns None if the script is empty (no results to display). *)
let write_compile_script search_entries loose_warnings =
  let script = compile_script search_entries loose_warnings in
  if script = "" then None
  else begin
    let path = Filename.temp_file "bbtex-" ".scpt" in
    let oc = open_out path in
    Fun.protect ~finally:(fun () -> close_out oc) (fun () ->
      output_string oc script);
    Log.verbose (Printf.sprintf "wrote AppleScript to %s" path);
    Some path
  end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `dune runtest`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/applescript.ml test/test_applescript.ml test/dune
git commit -m "Add applescript.ml: generate AppleScript for BBEdit search results"
```

---

## Chunk 3: compiler.ml, bbedit_format.ml extensions, main.ml update

### Task 6: Implement compiler.ml

**Files:**
- Create: `lib/compiler.ml`

Note: compiler.ml calls external processes (latexmk, tectonic, synctex) so
full integration tests require those tools installed. We test the
`resolve_compilation` function which only does file I/O and directive parsing.
The `run_compilation` function is tested manually. `compile` is an integration
function that orchestrates everything.

- [ ] **Step 1: Write test for resolve_compilation**

Create `test/test_compiler.ml`:

```ocaml
open Bbtex

let tests_passed = ref 0
let tests_failed = ref 0

let assert_equal ~msg expected actual =
  if expected <> actual then begin
    Printf.eprintf "FAIL: %s\n  expected: %s\n  actual:   %s\n" msg expected actual;
    incr tests_failed
  end else
    incr tests_passed

let assert_true ~msg cond =
  if not cond then begin
    Printf.eprintf "FAIL: %s\n" msg;
    incr tests_failed
  end else
    incr tests_passed

let run_test name f =
  Printf.printf "  %s ... " name;
  (try
     f ();
     Printf.printf "ok\n"
   with e ->
     Printf.eprintf "EXCEPTION: %s\n" (Printexc.to_string e);
     incr tests_failed)

let testdata_dir =
  let cwd = Sys.getcwd () in
  if Sys.file_exists (Filename.concat cwd "testdata") then
    Filename.concat cwd "testdata"
  else
    Filename.concat (Filename.dirname (Filename.dirname (Filename.dirname cwd))) "testdata"

let test_resolve_compilation_basic () =
  let tex_file = Filename.concat testdata_dir "sample.tex" in
  let config = Compiler.resolve_compilation tex_file in
  (* Default engine should be pdflatex since sample.tex has no %!TEX program *)
  assert_equal ~msg:"engine is pdflatex"
    "pdflatex" (Types.string_of_engine config.engine);
  assert_true ~msg:"root_file ends with sample.tex"
    (Filename.basename config.root_file = "sample.tex");
  assert_true ~msg:"log_file ends with sample.log"
    (Filename.basename config.log_file = "sample.log");
  assert_true ~msg:"pdf_file ends with sample.pdf"
    (Filename.basename config.pdf_file = "sample.pdf");
  assert_true ~msg:"root_file is absolute"
    (Filename.is_implicit config.root_file = false)

let test_resolve_compilation_nonexistent () =
  try
    let _ = Compiler.resolve_compilation "/tmp/bbtex-nonexistent.tex" in
    assert_true ~msg:"should have raised" false
  with Compiler.Bbtex_error msg ->
    assert_true ~msg:"error mentions file"
      (let sub = "not found" in
       let rec check i =
         if i > String.length msg - String.length sub then false
         else if String.sub msg i (String.length sub) = sub then true
         else check (i + 1)
       in check 0)

let test_resolve_compilation_non_tex () =
  try
    let tmp = Filename.temp_file "bbtex" ".txt" in
    Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
      let _ = Compiler.resolve_compilation tmp in
      assert_true ~msg:"should have raised" false)
  with Compiler.Bbtex_error msg ->
    assert_true ~msg:"error mentions .tex"
      (let sub = ".tex" in
       let rec check i =
         if i > String.length msg - String.length sub then false
         else if String.sub msg i (String.length sub) = sub then true
         else check (i + 1)
       in check 0)

let () =
  Printf.printf "Compiler tests:\n";
  run_test "resolve_compilation basic" test_resolve_compilation_basic;
  run_test "resolve_compilation nonexistent" test_resolve_compilation_nonexistent;
  run_test "resolve_compilation non-tex" test_resolve_compilation_non_tex;
  Printf.printf "\nResults: %d passed, %d failed\n" !tests_passed !tests_failed;
  if !tests_failed > 0 then exit 1
```

- [ ] **Step 2: Add test to dune**

Add `test_compiler` to the test names in `test/dune`.

- [ ] **Step 3: Run test to verify it fails**

Run: `dune runtest`
Expected: FAIL — `Compiler` module not found.

- [ ] **Step 4: Implement compiler.ml**

Create `lib/compiler.ml`:

```ocaml
(** Compilation orchestration.

    Resolves %!TEX directives, runs latexmk or tectonic, parses
    the resulting log, reads source lines, and builds a compile_result. *)

open Types

exception Bbtex_error of string

let resolve_compilation source_file =
  (* Validate *)
  if not (Sys.file_exists source_file) then
    raise (Bbtex_error (Printf.sprintf "file not found: %s" source_file));
  if not (Filename.check_suffix source_file ".tex") then
    raise (Bbtex_error (Printf.sprintf "not a .tex file: %s" source_file));

  Log.info (Printf.sprintf "resolving directives for %s" source_file);

  (* Resolve to absolute path *)
  let abs_source =
    if Filename.is_relative source_file then
      Filename.concat (Sys.getcwd ()) source_file
    else source_file
  in
  let source_dir = Filename.dirname abs_source in

  (* Read directives *)
  let directives = Directive_parser.parse_file abs_source in
  List.iter (fun (d : directive) ->
    Log.verbose (Printf.sprintf "directive: %s = %s"
      (string_of_directive_key d.key) d.value)
  ) directives;

  (* Resolve root *)
  let root_file =
    match Directive_parser.find_directive Root directives with
    | Some root_value ->
      let resolved =
        if Filename.is_relative root_value then
          Filename.concat source_dir root_value
        else root_value
      in
      Log.info (Printf.sprintf "root = %s" resolved);
      resolved
    | None ->
      Log.info (Printf.sprintf "root = %s (self)" abs_source);
      abs_source
  in

  (* Resolve engine *)
  let engine =
    match Directive_parser.find_directive Program directives with
    | Some prog ->
      let e = engine_of_string prog in
      Log.info (Printf.sprintf "engine = %s" (string_of_engine e));
      e
    | None ->
      Log.info "engine = pdflatex (default)";
      Pdflatex
  in

  let root_dir = Filename.dirname root_file in
  let root_base = Filename.chop_suffix (Filename.basename root_file) ".tex" in

  {
    source_file = abs_source;
    root_file;
    engine;
    log_file = Filename.concat root_dir (root_base ^ ".log");
    pdf_file = Filename.concat root_dir (root_base ^ ".pdf");
  }

let run_compilation config =
  let cmd, args =
    match config.engine with
    | Tectonic ->
      "tectonic", [| "tectonic"; config.root_file |]
    | engine ->
      let flag = latexmk_flag engine in
      "latexmk", [|
        "latexmk";
        flag;
        "-interaction=nonstopmode";
        "-file-line-error";
        "-synctex=1";
        "-cd";
        config.root_file;
      |]
  in
  Log.info (Printf.sprintf "running: %s" (String.concat " " (Array.to_list args)));
  try
    let devnull = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
    let pid = Unix.create_process cmd args devnull Unix.stderr Unix.stderr in
    Unix.close devnull;
    let _, status = Unix.waitpid [] pid in
    let exit_code = match status with
      | Unix.WEXITED n -> n
      | Unix.WSIGNALED n -> 128 + n
      | Unix.WSTOPPED n -> 128 + n
    in
    Log.info (Printf.sprintf "%s exited with code %d" cmd exit_code);
    exit_code
  with Unix.Unix_error (Unix.ENOENT, _, _) ->
    raise (Bbtex_error (Printf.sprintf "%s not found in PATH" cmd))

let make_summary entries =
  let nerr = List.length (List.filter (fun e -> e.severity = Error) entries) in
  let nwarn = List.length (List.filter (fun e -> e.severity = Warning) entries) in
  let nbox = List.length (List.filter (fun e -> e.severity = BadBox) entries) in
  Printf.sprintf "%d error(s), %d warning(s), %d bad box(es)" nerr nwarn nbox

let compile source_file =
  let config = resolve_compilation source_file in
  let compile_exit = run_compilation config in

  (* Parse the log *)
  let entries =
    if Sys.file_exists config.log_file then begin
      Log.info (Printf.sprintf "parsing %s" config.log_file);
      let entries = Log_parser.parse_file config.log_file in
      Log.info (make_summary entries);
      entries
    end else begin
      Log.info (Printf.sprintf "no log file found at %s" config.log_file);
      []
    end
  in

  (* Build search entries and loose warnings *)
  let root_dir = Filename.dirname config.root_file in
  Log.info (Printf.sprintf "reading source lines for %d entries" (List.length entries));
  let search_results = Source_reader.build_search_entries ~root_dir entries in
  let loose_warnings = Source_reader.build_loose_warnings entries in

  let has_errors = List.exists (fun e -> e.severity = Error) entries in
  let status = if has_errors || compile_exit <> 0 then Failure else Success in

  {
    status;
    summary = make_summary entries;
    log_file = config.log_file;
    pdf_file = config.pdf_file;
    search_results;
    loose_warnings;
  }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `dune runtest`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/compiler.ml test/test_compiler.ml test/dune
git commit -m "Add compiler.ml: compilation orchestration with latexmk/tectonic"
```

---

### Task 7: Extend bbedit_format.ml with protocol formatter

**Files:**
- Modify: `lib/bbedit_format.ml`
- Modify: `test/test_format.ml`

- [ ] **Step 1: Add test for format_compile_result**

Append to the test section of `test/test_format.ml` (before the runner):

```ocaml
let test_format_compile_result_success () =
  let result = {
    Types.status = Types.Success;
    summary = "0 error(s), 1 warning(s), 0 bad box(es)";
    log_file = "/path/to/main.log";
    pdf_file = "/path/to/main.pdf";
    search_results = [];
    loose_warnings = [];
  } in
  let lines = Bbedit_format.format_compile_result result ~applescript_file:None in
  let has key = List.exists (fun l -> String.starts_with ~prefix:key l) lines in
  assert_true ~msg:"has status" (has "status: ");
  assert_true ~msg:"has summary" (has "summary: ");
  assert_true ~msg:"has log" (has "log: ");
  assert_true ~msg:"has pdf" (has "pdf: ");
  assert_true ~msg:"status is success"
    (List.exists (fun l -> l = "status: success") lines)

let test_format_compile_result_with_applescript () =
  let result = {
    Types.status = Types.Failure;
    summary = "1 error(s), 0 warning(s), 0 bad box(es)";
    log_file = "/path/to/main.log";
    pdf_file = "/path/to/main.pdf";
    search_results = [];
    loose_warnings = [];
  } in
  let lines = Bbedit_format.format_compile_result result
    ~applescript_file:(Some "/tmp/bbtex-test.scpt") in
  let has key = List.exists (fun l -> String.starts_with ~prefix:key l) lines in
  assert_true ~msg:"has applescript_file" (has "applescript_file: ");
  assert_true ~msg:"status is error"
    (List.exists (fun l -> l = "status: error") lines)

let test_format_compile_error_message () =
  let lines = Bbedit_format.format_error_message "latexmk not found in PATH" in
  let has key = List.exists (fun l -> String.starts_with ~prefix:key l) lines in
  assert_true ~msg:"has status" (has "status: ");
  assert_true ~msg:"has message" (has "message: ");
  assert_true ~msg:"status is error"
    (List.exists (fun l -> l = "status: error") lines)
```

Add these to the runner:
```ocaml
  run_test "format_compile_result success" test_format_compile_result_success;
  run_test "format_compile_result with applescript" test_format_compile_result_with_applescript;
  run_test "format_error_message" test_format_compile_error_message;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune runtest`
Expected: FAIL — `Bbedit_format.format_compile_result` not found.

- [ ] **Step 3: Add format_compile_result and format_error_message to bbedit_format.ml**

Append to the end of `lib/bbedit_format.ml`:

```ocaml
(* ── Compile result protocol output ────────────────────────── *)

let format_compile_result result ~applescript_file =
  let open Types in
  let status_str = match result.status with
    | Success -> "success"
    | Failure -> "error"
  in
  let lines = [
    Printf.sprintf "status: %s" status_str;
    Printf.sprintf "summary: %s" result.summary;
    Printf.sprintf "log: %s" result.log_file;
    Printf.sprintf "pdf: %s" result.pdf_file;
  ] in
  match applescript_file with
  | Some path -> lines @ [Printf.sprintf "applescript_file: %s" path]
  | None -> lines

let format_error_message msg =
  [ "status: error"; Printf.sprintf "message: %s" msg ]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune runtest`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/bbedit_format.ml test/test_format.ml
git commit -m "Add format_compile_result and format_error_message to bbedit_format.ml"
```

---

### Task 8: Update main.ml with new subcommands

**Files:**
- Modify: `bin/main.ml`

- [ ] **Step 1: Rewrite main.ml**

Replace the contents of `bin/main.ml` with:

```ocaml
(** bbtex — LaTeX log parser and BBEdit integration tool.

    Subcommands:
      compile <file.tex>         Compile, parse log, output protocol
      forward-search <f> <line>  SyncTeX forward search
      parse-log <file.log>       Parse a LaTeX log file
      directives <file.tex>      Extract %!TEX directives
      format-results <file.log>  Parse log, output for BBEdit results browser

    Options:
      --format bbedit|text  Output format (default: text)
      --verbose             Enable verbose logging *)

open Bbtex

let usage = {|Usage: bbtex <command> [options] <file>

Commands:
  compile <file.tex>         Compile and report results (protocol output)
  forward-search <f> <line>  SyncTeX forward search
  parse-log <file.log>       Parse a LaTeX log file
  directives <file.tex>      Extract %!TEX directives
  format-results <file.log>  Parse log, output in BBEdit results format

Options:
  --format bbedit|text       Output format (default: text for parse-log,
                             bbedit for format-results)
  --verbose                  Enable verbose logging to stderr
  --help                     Show this help message
|}

(** Simple argument parser — no external dependencies needed.
    Returns (command, format_opt, verbose, args). *)
let parse_args () =
  let args = Array.to_list Sys.argv |> List.tl in  (* drop argv[0] *)
  let rec go cmd fmt verbose rest = function
    | [] -> (cmd, fmt, verbose, List.rev rest)
    | "--help" :: _ -> print_string usage; exit 0
    | "-h" :: _ -> print_string usage; exit 0
    | "--verbose" :: tail -> go cmd fmt true rest tail
    | "--format" :: f :: tail ->
      (match Types.output_format_of_string f with
       | Some fmt' -> go cmd (Some fmt') verbose rest tail
       | None ->
         Printf.eprintf "Unknown format: %s (expected bbedit or text)\n" f;
         exit 1)
    | arg :: tail ->
      if cmd = None then go (Some arg) fmt verbose rest tail
      else go cmd fmt verbose (arg :: rest) tail
  in
  go None None false [] args

(** Print a summary line to stderr. *)
let print_summary entries =
  let nerr = List.length (List.filter (fun e -> e.Types.severity = Types.Error) entries) in
  let nwarn = List.length (List.filter (fun e -> e.Types.severity = Types.Warning) entries) in
  let nbox = List.length (List.filter (fun e -> e.Types.severity = Types.BadBox) entries) in
  if nerr + nwarn + nbox > 0 then
    Printf.eprintf "%d error(s), %d warning(s), %d bad box(es)\n" nerr nwarn nbox

let cmd_log ~default_format ~show_summary fmt filename =
  let entries = Log_parser.parse_file filename in
  let fmt = Option.value ~default:default_format fmt in
  (match fmt with
   | Types.Bbedit ->
     List.iter print_endline (Bbedit_format.format_bbedit_all entries)
   | Types.Text ->
     List.iter print_string (Bbedit_format.format_text_all entries));
  if show_summary then print_summary entries;
  if List.exists (fun e -> e.Types.severity = Types.Error) entries
  then exit 1
  else exit 0

let cmd_directives filename =
  let directives = Directive_parser.parse_file filename in
  List.iter print_endline (Bbedit_format.format_directives_text directives)

let cmd_compile filename =
  try
    let result = Compiler.compile filename in
    let applescript_file =
      Applescript.write_compile_script result.search_results result.loose_warnings
    in
    let lines = Bbedit_format.format_compile_result result ~applescript_file in
    List.iter print_endline lines;
    match result.status with
    | Types.Success -> exit 0
    | Types.Failure -> exit 1
  with Compiler.Bbtex_error msg ->
    Log.error msg;
    List.iter print_endline (Bbedit_format.format_error_message msg);
    exit 2

let cmd_forward_search filename line_str =
  try
    let line_num =
      try int_of_string line_str
      with Failure _ ->
        raise (Compiler.Bbtex_error
          (Printf.sprintf "line number must be an integer, got: %s" line_str))
    in
    let config = Compiler.resolve_compilation filename in
    let pdf_file = config.pdf_file in
    if not (Sys.file_exists pdf_file) then
      raise (Compiler.Bbtex_error
        (Printf.sprintf "PDF not found: %s — compile the document first" pdf_file));

    (* Run synctex *)
    let synctex_args = [|
      "synctex"; "view";
      "-i"; Printf.sprintf "%d:0:%s" line_num filename;
      "-o"; pdf_file;
    |] in
    Log.info (Printf.sprintf "running: %s" (String.concat " " (Array.to_list synctex_args)));

    let (r_fd, w_fd) = Unix.pipe () in
    let devnull = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
    (try
       let pid = Unix.create_process "synctex" synctex_args devnull w_fd Unix.stderr in
       Unix.close devnull;
       Unix.close w_fd;
       let ic = Unix.in_channel_of_descr r_fd in
       let lines = ref [] in
       (try while true do lines := input_line ic :: !lines done
        with End_of_file -> ());
       let _, status = Unix.waitpid [] pid in
       let _ = status in
       let output = List.rev !lines in

       (* Parse synctex output *)
       let find_val prefix =
         List.find_map (fun l ->
           if String.starts_with ~prefix l then
             Some (String.trim (String.sub l (String.length prefix)
               (String.length l - String.length prefix)))
           else None
         ) output
       in
       let page = Option.value ~default:"1" (find_val "Page:") in
       let x = Option.value ~default:"0" (find_val "x:") in
       let y = Option.value ~default:"0" (find_val "y:") in

       Printf.printf "status: success\n";
       Printf.printf "pdf: %s\n" pdf_file;
       Printf.printf "page: %s\n" page;
       Printf.printf "x: %s\n" x;
       Printf.printf "y: %s\n" y;
       exit 0
     with Unix.Unix_error (Unix.ENOENT, _, _) ->
       Unix.close devnull;
       Unix.close w_fd;
       Unix.close r_fd;
       raise (Compiler.Bbtex_error "synctex not found in PATH"))
  with Compiler.Bbtex_error msg ->
    Log.error msg;
    List.iter print_endline (Bbedit_format.format_error_message msg);
    exit 2

let () =
  let (cmd, fmt, verbose, args) = parse_args () in
  if verbose then Log.set_verbose ();
  match cmd with
  | None ->
    print_string usage;
    exit 1
  | Some "compile" ->
    (match args with
     | [f] -> cmd_compile f
     | _ -> Printf.eprintf "compile requires a filename\n"; exit 1)
  | Some "forward-search" ->
    (match args with
     | [f; line] -> cmd_forward_search f line
     | _ -> Printf.eprintf "forward-search requires <file.tex> <line>\n"; exit 1)
  | Some "parse-log" ->
    (match args with
     | [f] -> cmd_log ~default_format:Types.Text ~show_summary:true fmt f
     | _ -> Printf.eprintf "parse-log requires a filename\n"; exit 1)
  | Some "directives" ->
    (match args with
     | [f] -> cmd_directives f
     | _ -> Printf.eprintf "directives requires a filename\n"; exit 1)
  | Some "format-results" ->
    (match args with
     | [f] -> cmd_log ~default_format:Types.Bbedit ~show_summary:false fmt f
     | _ -> Printf.eprintf "format-results requires a filename\n"; exit 1)
  | Some other ->
    Printf.eprintf "Unknown command: %s\n\n%s" other usage;
    exit 1
```

- [ ] **Step 2: Update bin/dune to add unix dependency**

Change `bin/dune` to:
```
(executable
 (name main)
 (libraries bbtex unix))
```

- [ ] **Step 3: Build and verify**

Run: `dune build`
Expected: success.

Run: `dune runtest`
Expected: all existing tests pass.

- [ ] **Step 4: Smoke test the new subcommands**

Run: `dune exec bin/main.exe -- --help`
Expected: shows updated usage with `compile` and `forward-search`.

Run: `dune exec bin/main.exe -- directives testdata/sample.tex`
Expected: same output as before (backwards compatibility).

Run: `dune exec bin/main.exe -- parse-log testdata/sample.log`
Expected: same output as before.

- [ ] **Step 5: Commit**

```bash
git add bin/main.ml bin/dune
git commit -m "Add compile and forward-search subcommands to main.ml"
```

---

## Chunk 4: Shell wrappers, install.sh, cleanup

### Task 9: Rewrite thin shell wrappers

**Files:**
- Rewrite: `scripts/bbtex-bbedit-compile.sh`
- Rewrite: `scripts/bbtex-bbedit-forward.sh`

- [ ] **Step 1: Rewrite bbtex-bbedit-compile.sh**

Replace contents of `scripts/bbtex-bbedit-compile.sh` with the thin wrapper from the spec (see spec section "Thin shell wrappers > bbtex-bbedit-compile.sh").

- [ ] **Step 2: Rewrite bbtex-bbedit-forward.sh**

Replace contents of `scripts/bbtex-bbedit-forward.sh` with the thin wrapper from the spec (see spec section "Thin shell wrappers > bbtex-bbedit-forward.sh").

- [ ] **Step 3: Verify scripts are executable**

Run: `chmod +x scripts/bbtex-bbedit-compile.sh scripts/bbtex-bbedit-forward.sh`

- [ ] **Step 4: Commit**

```bash
git add scripts/bbtex-bbedit-compile.sh scripts/bbtex-bbedit-forward.sh
git commit -m "Rewrite BBEdit wrapper scripts as thin protocol consumers"
```

---

### Task 10: Remove old scripts, update install.sh

**Files:**
- Delete: `scripts/bbtex-compile.sh`
- Delete: `scripts/bbtex-forward-search.sh`
- Rewrite: `scripts/install.sh`

- [ ] **Step 1: Delete old scripts**

```bash
git rm scripts/bbtex-compile.sh scripts/bbtex-forward-search.sh
```

- [ ] **Step 2: Update install.sh**

Rewrite `scripts/install.sh` to work from `~/Dropbox/projects_claude/bbtex-ocaml/`. The symlink targets and structure remain the same, just the paths update. Key changes:
- `PROJECT_DIR` resolves from the script's location (no change needed if using `$(cd "$(dirname "$0")/.." && pwd)`)
- Create `~/.local/state/bbtex/` directory for debug logs
- Print updated instructions

- [ ] **Step 3: Commit**

```bash
git add -A scripts/
git commit -m "Remove old shell scripts, update install.sh for new project location"
```

---

### Task 11: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README**

Key changes:
- Update project path references to `~/Dropbox/projects_claude/bbtex-ocaml/`
- Add `compile` and `forward-search` to the usage section
- Update architecture diagram to show the new module layout
- Add debugging section mentioning `~/.local/state/bbtex/last-compile.log`
- Remove references to deleted shell scripts

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Update README for refactored architecture"
```

---

### Task 12: Manual integration test

No code changes. Verify end-to-end.

- [ ] **Step 1: Build**

Run: `dune build`

- [ ] **Step 2: Test compile subcommand**

Run: `dune exec bin/main.exe -- compile testdata/sample.tex --verbose 2>&1`
Expected: protocol output on stdout, verbose logging on stderr. If latexmk is installed, it should compile. If not, should show a clear error with exit code 2.

- [ ] **Step 3: Test parse-log backwards compatibility**

Run: `dune exec bin/main.exe -- parse-log testdata/sample.log`
Expected: same output as before refactor.

- [ ] **Step 4: Run install.sh**

Run: `scripts/install.sh`
Expected: symlinks created, instructions printed.

- [ ] **Step 5: Verify symlinks**

Run: `ls -la ~/.local/bin/bbtex`
Run: `ls -la ~/Library/Application\ Support/BBEdit/Scripts/LaTeX*`
Expected: symlinks point to files under `~/Dropbox/projects_claude/bbtex-ocaml/`.
