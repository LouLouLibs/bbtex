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

(* ── Substring helper ───────────────────────────────────────── *)

let contains haystack needle =
  let hlen = String.length haystack in
  let nlen = String.length needle in
  if nlen = 0 then true
  else if nlen > hlen then false
  else begin
    let found = ref false in
    for i = 0 to hlen - nlen do
      if not !found then begin
        let sub = String.sub haystack i nlen in
        if sub = needle then found := true
      end
    done;
    !found
  end

(* ── Tests: escape_applescript ─────────────────────────────── *)

let test_escape_plain_text () =
  assert_equal ~msg:"plain text unchanged" "hello world"
    (Applescript.escape_applescript "hello world")

let test_escape_backslash () =
  assert_equal ~msg:"backslash doubled" {|\\|}
    (Applescript.escape_applescript {|\|})

let test_escape_double_quote () =
  assert_equal ~msg:"double quote escaped" {|\"|}
    (Applescript.escape_applescript "\"")

let test_escape_both () =
  assert_equal ~msg:"backslash and quote both escaped" {|a\\\"b|}
    (Applescript.escape_applescript {|a\"b|})

(* ── Tests: compile_script ──────────────────────────────────── *)

let test_compile_script_both_empty () =
  assert_equal ~msg:"empty lists returns empty string" ""
    (Applescript.compile_script [])

let test_compile_script_single_tell_block () =
  let e = { Types.se_file = "/path/a.tex"; se_line = 1;
            se_message = "An error."; se_severity = Types.Error } in
  let script = Applescript.compile_script [e] in
  (* Should have exactly one tell/end tell pair *)
  let count_tell str =
    let n = ref 0 in
    let len = String.length str in
    for i = 0 to len - 4 do
      if String.sub str i 4 = "tell" && (i = 0 || str.[i-1] = '\n') then incr n
    done;
    !n
  in
  let tells = count_tell script in
  assert_equal ~msg:"exactly one tell block" "1" (string_of_int tells)

let test_compile_script_closes_old_windows () =
  let e = { Types.se_file = "/path/a.tex"; se_line = 1;
            se_message = "An error."; se_severity = Types.Error } in
  let script = Applescript.compile_script [e] in
  assert_true ~msg:"closes LaTeX Errors windows"
    (contains script {|"LaTeX Errors"|})

let test_compile_script_error_entry () =
  let e = { Types.se_file = "/path/doc.tex"; se_line = 69;
            se_message = "Undefined control sequence.";
            se_severity = Types.Error } in
  let script = Applescript.compile_script [e] in
  assert_true ~msg:"contains results browser" (contains script "results browser");
  assert_true ~msg:"contains error_kind" (contains script "error_kind");
  assert_true ~msg:"contains file path" (contains script "/path/doc.tex");
  assert_true ~msg:"contains line number" (contains script "result_line:69");
  assert_true ~msg:"contains message" (contains script "Undefined control sequence.")

let test_compile_script_badbox_entry () =
  let e = { Types.se_file = "/path/doc.tex"; se_line = 42;
            se_message = "Overfull hbox";
            se_severity = Types.BadBox } in
  let script = Applescript.compile_script [e] in
  assert_true ~msg:"badbox uses note_kind" (contains script "note_kind")

let test_compile_script_multiple_entries () =
  let e1 = { Types.se_file = "/path/a.tex"; se_line = 1;
             se_message = "Error one."; se_severity = Types.Error } in
  let e2 = { Types.se_file = "/path/b.tex"; se_line = 2;
             se_message = "Error two."; se_severity = Types.Error } in
  let script = Applescript.compile_script [e1; e2] in
  assert_true ~msg:"contains first message" (contains script "Error one.");
  assert_true ~msg:"contains second message" (contains script "Error two.")

let test_compile_script_escapes_quotes () =
  let entry = { Types.se_file = {|/my "project"/doc.tex|}; se_line = 1;
                se_message = {|say "hello"|}; se_severity = Types.Error } in
  let script = Applescript.compile_script [entry] in
  assert_true ~msg:"path quote escaped" (contains script {|\"project\"|});
  assert_true ~msg:"message quote escaped" (contains script {|\"hello\"|})


(* ── Tests: write_compile_script ──────────────────────────────── *)

let test_write_compile_script_none_when_empty () =
  let result = Applescript.write_compile_script [] in
  assert_true ~msg:"returns None for empty input" (result = None)

let test_write_compile_script_some_when_entries () =
  let e = { Types.se_file = "/path/a.tex"; se_line = 1;
            se_message = "An error."; se_severity = Types.Error } in
  let result = Applescript.write_compile_script [e] in
  assert_true ~msg:"returns Some for non-empty input" (result <> None)

(* ── Runner ────────────────────────────────────────────────── *)

let () =
  Printf.printf "Applescript tests:\n";
  run_test "escape_applescript: plain text unchanged" test_escape_plain_text;
  run_test "escape_applescript: backslash doubled" test_escape_backslash;
  run_test "escape_applescript: double quote escaped" test_escape_double_quote;
  run_test "escape_applescript: both escaped" test_escape_both;
  run_test "compile_script: empty lists returns empty string" test_compile_script_both_empty;
  run_test "compile_script: single tell block" test_compile_script_single_tell_block;
  run_test "compile_script: closes old windows" test_compile_script_closes_old_windows;
  run_test "compile_script: error entry" test_compile_script_error_entry;
  run_test "compile_script: badbox uses note_kind" test_compile_script_badbox_entry;
  run_test "compile_script: multiple entries" test_compile_script_multiple_entries;
  run_test "compile_script: escapes quotes" test_compile_script_escapes_quotes;
  run_test "write_compile_script: None when empty" test_write_compile_script_none_when_empty;
  run_test "write_compile_script: Some when entries" test_write_compile_script_some_when_entries;
  Printf.printf "\nResults: %d passed, %d failed\n" !tests_passed !tests_failed;
  if !tests_failed > 0 then exit 1
