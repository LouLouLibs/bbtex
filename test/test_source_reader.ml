open Bbtex

(* ── Simple assertion framework ────────────────────────────── *)

let tests_passed = ref 0
let tests_failed = ref 0

let assert_equal ~msg expected actual =
  if expected <> actual then begin
    Printf.eprintf "FAIL: %s\n  expected: %s\n  actual:   %s\n" msg expected actual;
    incr tests_failed
  end else
    incr tests_passed


let assert_int_equal ~msg expected actual =
  assert_equal ~msg (string_of_int expected) (string_of_int actual)

let assert_string_option ~msg expected actual =
  let to_s = function None -> "<none>" | Some s -> Printf.sprintf "Some(%s)" s in
  assert_equal ~msg (to_s expected) (to_s actual)

let run_test name f =
  Printf.printf "  %s ... " name;
  (try
     f ();
     Printf.printf "ok\n"
   with e ->
     Printf.eprintf "EXCEPTION: %s\n" (Printexc.to_string e);
     incr tests_failed)

(* ── Testdata path resolution ───────────────────────────────── *)

(* Dune runs tests from _build/default/test/; find testdata relative to cwd
   or fall back to the source tree. *)
let testdata_dir =
  let cwd = Sys.getcwd () in
  if Sys.file_exists (Filename.concat cwd "testdata") then
    Filename.concat cwd "testdata"
  else
    Filename.concat (Filename.dirname (Filename.dirname (Filename.dirname cwd))) "testdata"

let source_lines_path = Filename.concat testdata_dir "source_lines.tex"

(* ── Tests: read_source_line ────────────────────────────────── *)

let test_read_line1 () =
  let result = Source_reader.read_source_line source_lines_path 1 in
  assert_string_option ~msg:"line 1 content"
    (Some {|\documentclass{article}|}) result

let test_read_line3 () =
  let result = Source_reader.read_source_line source_lines_path 3 in
  assert_string_option ~msg:"line 3 content"
    (Some "This is line three with $math$ and special chars.") result

let test_read_line_past_end () =
  let result = Source_reader.read_source_line source_lines_path 999 in
  assert_string_option ~msg:"past end returns None"
    None result

let test_read_nonexistent_file () =
  let result = Source_reader.read_source_line "/nonexistent/path/file.tex" 1 in
  assert_string_option ~msg:"nonexistent file returns None"
    None result

(* ── Tests: escape_pcre ─────────────────────────────────────── *)

let test_escape_plain_text () =
  let result = Source_reader.escape_pcre "hello world" in
  assert_equal ~msg:"plain text unchanged" "hello world" result

let test_escape_backslash () =
  assert_equal ~msg:"backslash escaped" {|\\|} (Source_reader.escape_pcre {|\|})

let test_escape_dot () =
  assert_equal ~msg:"dot escaped" {|\.|} (Source_reader.escape_pcre ".")

let test_escape_star () =
  assert_equal ~msg:"star escaped" {|\*|} (Source_reader.escape_pcre "*")

let test_escape_plus () =
  assert_equal ~msg:"plus escaped" {|\+|} (Source_reader.escape_pcre "+")

let test_escape_question () =
  assert_equal ~msg:"question escaped" {|\?|} (Source_reader.escape_pcre "?")

let test_escape_paren_open () =
  assert_equal ~msg:"open paren escaped" {|\(|} (Source_reader.escape_pcre "(")

let test_escape_paren_close () =
  assert_equal ~msg:"close paren escaped" {|\)|} (Source_reader.escape_pcre ")")

let test_escape_bracket_open () =
  assert_equal ~msg:"open bracket escaped" {|\[|} (Source_reader.escape_pcre "[")

let test_escape_bracket_close () =
  assert_equal ~msg:"close bracket escaped" {|\]|} (Source_reader.escape_pcre "]")

let test_escape_caret () =
  assert_equal ~msg:"caret escaped" {|\^|} (Source_reader.escape_pcre "^")

let test_escape_dollar () =
  assert_equal ~msg:"dollar escaped" {|\$|} (Source_reader.escape_pcre "$")

let test_escape_pipe () =
  assert_equal ~msg:"pipe escaped" {|\||} (Source_reader.escape_pcre "|")

let test_escape_brace_open () =
  assert_equal ~msg:"open brace escaped" {|\{|} (Source_reader.escape_pcre "{")

let test_escape_brace_close () =
  assert_equal ~msg:"close brace escaped" {|\}|} (Source_reader.escape_pcre "}")

let test_escape_latex_line () =
  (* Line 3 from source_lines.tex *)
  let input = "This is line three with $math$ and special chars." in
  let result = Source_reader.escape_pcre input in
  assert_equal ~msg:"realistic LaTeX line escaped"
    {|This is line three with \$math\$ and special chars\.|} result

(* ── Tests: build_search_entries ────────────────────────────── *)

let make_entry ?(context=[]) severity file line message =
  { Types.severity; file; line; message; context }

let test_build_search_entries_basic () =
  let entry = make_entry Types.Error (Some source_lines_path) (Some 1)
    "Undefined control sequence." in
  let results = Source_reader.build_search_entries ~root_dir:testdata_dir [entry] in
  assert_int_equal ~msg:"one result" 1 (List.length results);
  let r = List.hd results in
  assert_equal ~msg:"se_file" source_lines_path r.Types.se_file;
  assert_int_equal ~msg:"se_line" 1 r.Types.se_line;
  assert_equal ~msg:"se_message" "Undefined control sequence." r.Types.se_message;
  assert_equal ~msg:"se_severity" "error" (Types.string_of_severity r.Types.se_severity)

let test_build_search_entries_dedup () =
  (* Different diagnostics on the same line must survive. Exact repeats collapse. *)
  let e1 = make_entry Types.Error (Some source_lines_path) (Some 3)
    "First error on line 3." in
  let e2 = make_entry Types.Error (Some source_lines_path) (Some 3)
    "Second error on line 3." in
  let results = Source_reader.build_search_entries ~root_dir:testdata_dir [e1; e2; e1] in
  assert_int_equal ~msg:"dedup: preserve different messages, collapse exact repeats"
    2 (List.length results)

let test_build_search_entries_includes_warnings () =
  (* Warnings with valid file+line now become search entries *)
  let entry = make_entry Types.Warning (Some source_lines_path) (Some 1)
    "Some warning on input line 1." in
  let results = Source_reader.build_search_entries ~root_dir:testdata_dir [entry] in
  assert_int_equal ~msg:"warning with file+line is included" 1 (List.length results);
  let r = List.hd results in
  assert_equal ~msg:"se_severity" "warning" (Types.string_of_severity r.Types.se_severity)

let test_build_search_entries_badbox () =
  (* Bad boxes with file+line DO become search entries *)
  let entry = make_entry Types.BadBox (Some source_lines_path) (Some 1)
    "Overfull \\hbox at line 1." in
  let results = Source_reader.build_search_entries ~root_dir:testdata_dir [entry] in
  assert_int_equal ~msg:"badbox with file+line becomes search entry" 1 (List.length results)

let test_build_search_entries_no_line_uses_zero () =
  (* Entry with no line number uses line 0 *)
  let entry = make_entry Types.Warning (Some source_lines_path) None
    "No line number." in
  let results = Source_reader.build_search_entries ~root_dir:testdata_dir [entry] in
  assert_int_equal ~msg:"entry without line is included" 1 (List.length results);
  let r = List.hd results in
  assert_int_equal ~msg:"se_line is 0" 0 r.Types.se_line

let test_build_search_entries_zero_line_uses_zero () =
  (* Entry with line=0 uses line 0 *)
  let entry = make_entry Types.Warning (Some source_lines_path) (Some 0)
    "Line 0 is not valid." in
  let results = Source_reader.build_search_entries ~root_dir:testdata_dir [entry] in
  assert_int_equal ~msg:"entry with line=0 is included" 1 (List.length results);
  let r = List.hd results in
  assert_int_equal ~msg:"se_line is 0" 0 r.Types.se_line

let test_build_search_entries_skips_no_file () =
  let entry = make_entry Types.Warning None (Some 1)
    "No file." in
  let results = Source_reader.build_search_entries ~root_dir:testdata_dir [entry] in
  assert_int_equal ~msg:"entry without file is skipped" 0 (List.length results)

(* ── Runner ────────────────────────────────────────────────── *)

let () =
  Printf.printf "Source_reader tests:\n";
  run_test "read_source_line: line 1" test_read_line1;
  run_test "read_source_line: line 3 (middle)" test_read_line3;
  run_test "read_source_line: past end returns None" test_read_line_past_end;
  run_test "read_source_line: nonexistent file returns None" test_read_nonexistent_file;
  run_test "escape_pcre: plain text unchanged" test_escape_plain_text;
  run_test "escape_pcre: backslash" test_escape_backslash;
  run_test "escape_pcre: dot" test_escape_dot;
  run_test "escape_pcre: star" test_escape_star;
  run_test "escape_pcre: plus" test_escape_plus;
  run_test "escape_pcre: question" test_escape_question;
  run_test "escape_pcre: open paren" test_escape_paren_open;
  run_test "escape_pcre: close paren" test_escape_paren_close;
  run_test "escape_pcre: open bracket" test_escape_bracket_open;
  run_test "escape_pcre: close bracket" test_escape_bracket_close;
  run_test "escape_pcre: caret" test_escape_caret;
  run_test "escape_pcre: dollar" test_escape_dollar;
  run_test "escape_pcre: pipe" test_escape_pipe;
  run_test "escape_pcre: open brace" test_escape_brace_open;
  run_test "escape_pcre: close brace" test_escape_brace_close;
  run_test "escape_pcre: realistic LaTeX line" test_escape_latex_line;
  run_test "build_search_entries: basic one entry" test_build_search_entries_basic;
  run_test "build_search_entries: dedup same file+line" test_build_search_entries_dedup;
  run_test "build_search_entries: includes warnings with file+line" test_build_search_entries_includes_warnings;
  run_test "build_search_entries: badbox with file+line included" test_build_search_entries_badbox;
  run_test "build_search_entries: no line uses line 0" test_build_search_entries_no_line_uses_zero;
  run_test "build_search_entries: line=0 uses line 0" test_build_search_entries_zero_line_uses_zero;
  run_test "build_search_entries: skips entry without file" test_build_search_entries_skips_no_file;
  Printf.printf "\nResults: %d passed, %d failed\n" !tests_passed !tests_failed;
  if !tests_failed > 0 then exit 1
