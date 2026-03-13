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

(* ── Tests ─────────────────────────────────────────────────── *)

let test_bbedit_format_basic () =
  let entry = {
    Types.severity = Types.Error;
    file = Some "./main.tex";
    line = Some 42;
    message = "Undefined control sequence.";
    context = [];
  } in
  let result = Bbedit_format.format_bbedit entry in
  assert_equal ~msg:"bbedit format"
    "./main.tex:42: error: Undefined control sequence."
    result

let test_bbedit_format_warning () =
  let entry = {
    Types.severity = Types.Warning;
    file = Some "./chapter1.tex";
    line = Some 55;
    message = "Reference `fig:missing' undefined.";
    context = [];
  } in
  let result = Bbedit_format.format_bbedit entry in
  assert_equal ~msg:"bbedit warning format"
    "./chapter1.tex:55: warning: Reference `fig:missing' undefined."
    result

let test_bbedit_format_badbox () =
  (* BadBox severity maps to "warning" in BBEdit format *)
  let entry = {
    Types.severity = Types.BadBox;
    file = Some "./body.tex";
    line = Some 10;
    message = "Overfull \\hbox (5.0pt too wide)";
    context = [];
  } in
  let result = Bbedit_format.format_bbedit entry in
  assert_equal ~msg:"bbedit badbox format"
    "./body.tex:10: warning: Overfull \\hbox (5.0pt too wide)"
    result

let test_bbedit_format_missing_file () =
  let entry = {
    Types.severity = Types.Error;
    file = None;
    line = Some 10;
    message = "Something went wrong.";
    context = [];
  } in
  let result = Bbedit_format.format_bbedit entry in
  assert_equal ~msg:"missing file uses <unknown>"
    "<unknown>:10: error: Something went wrong."
    result

let test_bbedit_format_missing_line () =
  let entry = {
    Types.severity = Types.Warning;
    file = Some "./main.tex";
    line = None;
    message = "There were undefined references.";
    context = [];
  } in
  let result = Bbedit_format.format_bbedit entry in
  assert_equal ~msg:"missing line uses 0"
    "./main.tex:0: warning: There were undefined references."
    result

let test_bbedit_format_missing_both () =
  let entry = {
    Types.severity = Types.Error;
    file = None;
    line = None;
    message = "Emergency stop.";
    context = [];
  } in
  let result = Bbedit_format.format_bbedit entry in
  assert_equal ~msg:"missing file and line"
    "<unknown>:0: error: Emergency stop."
    result

let test_bbedit_format_all () =
  let entries = [
    { Types.severity = Types.Error; file = Some "a.tex"; line = Some 1;
      message = "err1"; context = [] };
    { Types.severity = Types.Warning; file = Some "b.tex"; line = Some 2;
      message = "warn1"; context = [] };
  ] in
  let results = Bbedit_format.format_bbedit_all entries in
  assert_equal ~msg:"format_all length"
    "2" (string_of_int (List.length results));
  assert_equal ~msg:"first line"
    "a.tex:1: error: err1" (List.nth results 0);
  assert_equal ~msg:"second line"
    "b.tex:2: warning: warn1" (List.nth results 1)

let test_text_format_produces_output () =
  let entry = {
    Types.severity = Types.Error;
    file = Some "./main.tex";
    line = Some 42;
    message = "Undefined control sequence.";
    context = ["\\badcmd"];
  } in
  let result = Bbedit_format.format_text_entry entry in
  assert_true ~msg:"text format is non-empty"
    (String.length result > 0);
  (* Check that it contains the message somewhere *)
  assert_true ~msg:"text format contains message"
    (let sub = "Undefined control sequence." in
     let rec check i =
       if i > String.length result - String.length sub then false
       else if String.sub result i (String.length sub) = sub then true
       else check (i + 1)
     in check 0)

let test_text_format_all () =
  let entries = [
    { Types.severity = Types.Error; file = Some "a.tex"; line = Some 1;
      message = "err1"; context = [] };
    { Types.severity = Types.Warning; file = None; line = None;
      message = "warn1"; context = [] };
  ] in
  let results = Bbedit_format.format_text_all entries in
  assert_equal ~msg:"format_text_all length"
    "2" (string_of_int (List.length results));
  assert_true ~msg:"first entry non-empty"
    (String.length (List.nth results 0) > 0);
  assert_true ~msg:"second entry non-empty"
    (String.length (List.nth results 1) > 0)

let test_directives_text_format () =
  let directives = [
    { Types.key = Types.Root; value = "../main.tex" };
    { Types.key = Types.Program; value = "lualatex" };
  ] in
  let results = Bbedit_format.format_directives_text directives in
  assert_equal ~msg:"two lines" "2" (string_of_int (List.length results));
  assert_equal ~msg:"first" "root = ../main.tex" (List.nth results 0);
  assert_equal ~msg:"second" "program = lualatex" (List.nth results 1)

let test_format_compile_result_success () =
  let result = {
    Types.status = Types.Success;
    summary = "Compilation succeeded";
    log_file = "/tmp/main.log";
    pdf_file = "/tmp/main.pdf";
    search_results = [];
  } in
  let lines = Bbedit_format.format_compile_result result ~applescript_file:None in
  assert_equal ~msg:"four lines when no applescript" "4" (string_of_int (List.length lines));
  assert_equal ~msg:"status is success" "status: success" (List.nth lines 0);
  assert_equal ~msg:"summary line" "summary: Compilation succeeded" (List.nth lines 1);
  assert_equal ~msg:"log line" "log: /tmp/main.log" (List.nth lines 2);
  assert_equal ~msg:"pdf line" "pdf: /tmp/main.pdf" (List.nth lines 3)

let test_format_compile_result_with_applescript () =
  let result = {
    Types.status = Types.Failure;
    summary = "Compilation failed with 2 errors";
    log_file = "/tmp/main.log";
    pdf_file = "/tmp/main.pdf";
    search_results = [];
  } in
  let lines = Bbedit_format.format_compile_result result
    ~applescript_file:(Some "/tmp/results.applescript") in
  assert_equal ~msg:"five lines with applescript" "5" (string_of_int (List.length lines));
  assert_equal ~msg:"status is error" "status: error" (List.nth lines 0);
  assert_equal ~msg:"applescript_file line"
    "applescript_file: /tmp/results.applescript" (List.nth lines 4)

let test_format_compile_error_message () =
  let lines = Bbedit_format.format_error_message "file not found: main.tex" in
  assert_equal ~msg:"two lines" "2" (string_of_int (List.length lines));
  assert_equal ~msg:"status: error" "status: error" (List.nth lines 0);
  assert_equal ~msg:"message line" "message: file not found: main.tex" (List.nth lines 1)

(* ── Runner ────────────────────────────────────────────────── *)

let () =
  Printf.printf "Output format tests:\n";
  run_test "bbedit format basic" test_bbedit_format_basic;
  run_test "bbedit format warning" test_bbedit_format_warning;
  run_test "bbedit format badbox" test_bbedit_format_badbox;
  run_test "bbedit format missing file" test_bbedit_format_missing_file;
  run_test "bbedit format missing line" test_bbedit_format_missing_line;
  run_test "bbedit format missing both" test_bbedit_format_missing_both;
  run_test "bbedit format_all" test_bbedit_format_all;
  run_test "text format produces output" test_text_format_produces_output;
  run_test "text format_all" test_text_format_all;
  run_test "directives text format" test_directives_text_format;
  run_test "format compile result success" test_format_compile_result_success;
  run_test "format compile result with applescript" test_format_compile_result_with_applescript;
  run_test "format compile error message" test_format_compile_error_message;
  Printf.printf "\nResults: %d passed, %d failed\n" !tests_passed !tests_failed;
  if !tests_failed > 0 then exit 1
