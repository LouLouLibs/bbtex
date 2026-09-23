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

let assert_true ~msg cond =
  if not cond then begin
    Printf.eprintf "FAIL: %s\n" msg;
    incr tests_failed
  end else
    incr tests_passed

let assert_option_equal ~msg to_string expected actual =
  let s x = match x with None -> "<none>" | Some v -> to_string v in
  assert_equal ~msg (s expected) (s actual)

let assert_option_int ~msg = assert_option_equal ~msg string_of_int

let assert_severity ~msg expected actual =
  assert_equal ~msg
    (Types.string_of_severity expected)
    (Types.string_of_severity actual)

let run_test name f =
  Printf.printf "  %s ... " name;
  (try
     f ();
     Printf.printf "ok\n"
   with e ->
     Printf.eprintf "EXCEPTION: %s\n" (Printexc.to_string e);
     incr tests_failed)

(* ── Tests ─────────────────────────────────────────────────── *)

let test_empty_input () =
  let entries = Log_parser.parse_lines [] in
  assert_int_equal ~msg:"empty input produces no entries"
    0 (List.length entries)

let test_clean_log () =
  let lines = [
    "This is pdfTeX, Version 3.141592653 (TeX Live 2024)";
    " restricted \\write18 enabled.";
    "entering extended mode";
    "(./main.tex";
    "LaTeX2e <2024-06-01> patch level 2";
    "(/usr/local/texlive/2024/texmf-dist/tex/latex/base/article.cls";
    "Document Class: article 2024/02/08 v1.4n Standard LaTeX document class";
    ")";
    "(./main.aux)";
    "[1{/usr/local/texlive/2024/texmf-var/fonts/map/pdftex/updmap/pdftex.map}]";
    "(./main.aux) )";
    "Output written on main.pdf (1 page, 12345 bytes).";
    "Transcript written on main.log.";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"clean log produces no entries"
    0 (List.length entries)

let test_undefined_control_sequence () =
  let lines = [
    "(./test.tex";
    "! Undefined control sequence.";
    "l.42 \\badcommand";
    "               ";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"one error entry" 1 (List.length entries);
  let e = List.hd entries in
  assert_severity ~msg:"severity is Error" Types.Error e.severity;
  assert_equal ~msg:"message" "Undefined control sequence." e.message;
  assert_option_int ~msg:"line is 42" (Some 42) e.line;
  assert_option_equal ~msg:"file is test.tex" Fun.id (Some "./test.tex") e.file

let test_missing_dollar () =
  let lines = [
    "(./math.tex";
    "! Missing $ inserted.";
    "<inserted text> ";
    "                $";
    "l.17 some math x^2";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"one error entry" 1 (List.length entries);
  let e = List.hd entries in
  assert_severity ~msg:"severity is Error" Types.Error e.severity;
  assert_equal ~msg:"message" "Missing $ inserted." e.message;
  assert_option_int ~msg:"line is 17" (Some 17) e.line

let test_multiline_error () =
  (* LaTeX errors with help text spanning multiple lines before l.<N> *)
  let lines = [
    "(./doc.tex";
    "! LaTeX Error: Environment itemize undefined.";
    "";
    "See the LaTeX manual or LaTeX Companion for explanation.";
    "Type  H <return>  for immediate help.";
    " ...                                              ";
    "";
    "l.25 \\begin{itemize}";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"one error entry" 1 (List.length entries);
  let e = List.hd entries in
  assert_severity ~msg:"severity is Error" Types.Error e.severity;
  assert_equal ~msg:"message"
    "LaTeX Error: Environment itemize undefined." e.message;
  assert_option_int ~msg:"line is 25" (Some 25) e.line;
  (* The context should contain the help text lines *)
  assert_true ~msg:"context is non-empty" (List.length e.context > 0)

let test_latex_warning () =
  let lines = [
    "(./chapter1.tex";
    "LaTeX Warning: Reference `fig:missing' on page 3 undefined on input line 55.";
    "";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"one warning entry" 1 (List.length entries);
  let e = List.hd entries in
  assert_severity ~msg:"severity is Warning" Types.Warning e.severity;
  assert_option_int ~msg:"line is 55" (Some 55) e.line;
  assert_option_equal ~msg:"file is chapter1.tex" Fun.id
    (Some "./chapter1.tex") e.file

let test_package_warning_message () =
  (* Key test: verify the message comes from AFTER "Warning: " not after
     the first colon. This was a bug where "Package foo Warning: msg" would
     extract "foo Warning: msg" instead of just "msg". *)
  let lines = [
    "(./main.tex";
    "Package hyperref Warning: Token not allowed in a PDF string (Unicode):";
    "                          removing `\\mathbb' on input line 88.";
    "";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"one warning entry" 1 (List.length entries);
  let e = List.hd entries in
  assert_severity ~msg:"severity is Warning" Types.Warning e.severity;
  (* The message should start with "Token", NOT "hyperref Warning: Token" *)
  assert_true ~msg:"message starts with 'Token'"
    (String.starts_with ~prefix:"Token" e.message);
  assert_true ~msg:"message does NOT start with 'hyperref'"
    (not (String.starts_with ~prefix:"hyperref" e.message))

let test_font_warning () =
  let lines = [
    "(./main.tex";
    "LaTeX Font Warning: Font shape `OT1/cmr/bx/sc' undefined";
    "                    (Font) using `OT1/cmr/bx/n' instead on input line 12.";
    "";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"one warning entry" 1 (List.length entries);
  let e = List.hd entries in
  assert_severity ~msg:"severity is Warning" Types.Warning e.severity;
  let contains ~sub s =
    let ls = String.length s and lsub = String.length sub in
    if lsub > ls then false
    else
      let rec check i =
        if i > ls - lsub then false
        else if String.sub s i lsub = sub then true
        else check (i + 1)
      in check 0
  in
  assert_true ~msg:"message mentions font shape"
    (contains ~sub:"Font shape" e.message)

let test_warning_with_line_number () =
  let lines = [
    "(./intro.tex";
    "LaTeX Warning: Unused global option(s): [draft] on input line 1.";
    "";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"one warning entry" 1 (List.length entries);
  let e = List.hd entries in
  assert_option_int ~msg:"line is 1" (Some 1) e.line

let test_warning_without_line_number () =
  let lines = [
    "(./main.tex";
    "LaTeX Warning: There were undefined references.";
    "";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"one warning entry" 1 (List.length entries);
  let e = List.hd entries in
  assert_option_int ~msg:"no line number" None e.line

let test_overfull_hbox () =
  let lines = [
    "(./body.tex";
    "Overfull \\hbox (15.2pt too wide) in paragraph at lines 42--55";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"one badbox entry" 1 (List.length entries);
  let e = List.hd entries in
  assert_severity ~msg:"severity is BadBox" Types.BadBox e.severity;
  assert_option_int ~msg:"line is 42" (Some 42) e.line;
  assert_option_equal ~msg:"file is body.tex" Fun.id
    (Some "./body.tex") e.file

let test_underfull_vbox () =
  let lines = [
    "(./page.tex";
    "Underfull \\vbox (badness 10000) at line 99";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"one badbox entry" 1 (List.length entries);
  let e = List.hd entries in
  assert_severity ~msg:"severity is BadBox" Types.BadBox e.severity;
  assert_option_int ~msg:"line is 99" (Some 99) e.line

let test_file_stack_tracking () =
  (* Errors should be attributed to the correct file based on the
     parenthesis-based file stack *)
  let lines = [
    "(./main.tex";
    "(./chapter1.tex";
    "! Undefined control sequence.";
    "l.10 \\foo";
    ")";
    "(./chapter2.tex";
    "! Missing $ inserted.";
    "l.20 x^2";
    ")";
    ")";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"two errors" 2 (List.length entries);
  let e1 = List.nth entries 0 in
  let e2 = List.nth entries 1 in
  assert_option_equal ~msg:"first error in chapter1.tex" Fun.id
    (Some "./chapter1.tex") e1.file;
  assert_option_equal ~msg:"second error in chapter2.tex" Fun.id
    (Some "./chapter2.tex") e2.file

let test_multi_file_project () =
  (* A more realistic multi-file scenario *)
  let lines = [
    "(./thesis.tex";
    "(/usr/local/texlive/2024/texmf-dist/tex/latex/base/article.cls)";
    "(./preamble.tex)";
    "(./intro.tex";
    "LaTeX Warning: Citation `jones2020' on page 1 undefined on input line 5.";
    ")";
    "(./methods.tex";
    "Overfull \\hbox (3.5pt too wide) in paragraph at lines 12--18";
    ")";
    ")";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"two entries" 2 (List.length entries);
  let e1 = List.nth entries 0 in
  let e2 = List.nth entries 1 in
  assert_option_equal ~msg:"warning in intro.tex" Fun.id
    (Some "./intro.tex") e1.file;
  assert_option_equal ~msg:"badbox in methods.tex" Fun.id
    (Some "./methods.tex") e2.file

let test_line_indicator_column_zero () =
  (* l.<N> should only match at column 0, not when indented.
     An indented "l.123" line is a continuation, not a line indicator. *)
  let lines = [
    "(./test.tex";
    "! Undefined control sequence.";
    "  l.99 this is indented and should NOT be a line indicator";
    "l.42 \\badcmd";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"one error entry" 1 (List.length entries);
  let e = List.hd entries in
  (* The actual l. indicator is at line 42, not 99 *)
  assert_option_int ~msg:"line is 42 (not 99)" (Some 42) e.line

let test_clean_realistic_log () =
  (* A realistic clean log with file opens/closes and info messages but
     no errors, warnings, or bad boxes *)
  let lines = [
    "This is pdfTeX, Version 3.141592653-2.6-1.40.26 (TeX Live 2024) (preloaded format=pdflatex)";
    " restricted \\write18 enabled.";
    "entering extended mode";
    "(./main.tex";
    "LaTeX2e <2024-06-01> patch level 2";
    "L3 programming layer <2024-05-27>";
    "(/usr/local/texlive/2024/texmf-dist/tex/latex/base/article.cls";
    "Document Class: article 2024/02/08 v1.4n Standard LaTeX document class";
    "(/usr/local/texlive/2024/texmf-dist/tex/latex/base/size10.clo))";
    "(/usr/local/texlive/2024/texmf-dist/tex/latex/amsmath/amsmath.sty";
    "For additional information on amsmath, use the `?' option.";
    "(/usr/local/texlive/2024/texmf-dist/tex/latex/amsmath/amstext.sty";
    "(/usr/local/texlive/2024/texmf-dist/tex/latex/amsmath/amsgen.sty)))";
    "(/usr/local/texlive/2024/texmf-dist/tex/latex/graphics/graphicx.sty";
    "(/usr/local/texlive/2024/texmf-dist/tex/latex/graphics/graphics.sty";
    "(/usr/local/texlive/2024/texmf-dist/tex/latex/graphics/trig.sty)";
    "(/usr/local/texlive/2024/texmf-dist/tex/latex/graphics-def/pdftex.def)))";
    "(./main.aux)";
    "\\openout1 = `main.aux'.";
    "";
    "[1{/usr/local/texlive/2024/texmf-var/fonts/map/pdftex/updmap/pdftex.map}]";
    "[2] [3]";
    "(./main.aux) )";
    "Here is how much of TeX's memory you used:";
    " 2741 strings out of 476025";
    " 37977 string characters out of 5790017";
    " 1935474 words of memory out of 5000000";
    " 24153 multiletter control sequences out of 15000+600000";
    " 564121 words of font info for 63 fonts, out of 8000000 for 9000";
    " 1141 hyphenation exceptions out of 8191";
    " 75i,6n,76p,200b,107s stack positions out of 10000i,1000n,20000p,200000b,200000s";
    "</usr/local/texlive/2024/texmf-dist/fonts/type1/public/amsfonts/cm/cmr10.pfb>";
    "Output written on main.pdf (3 pages, 45678 bytes).";
    "Transcript written on main.log.";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"clean realistic log produces no entries"
    0 (List.length entries)

let test_line_wrapping_79_chars () =
  (* TeX hard-wraps log output at 79 characters.  unwrap_lines joins physical
     lines of exactly 79 chars with the next line, so wrapped filenames are
     reconstructed correctly. *)
  let prefix = "(/usr/local/texlive/2024/texmf-dist/tex/latex/pgf/compatibility/pgflibrarysnake" in
  assert_int_equal ~msg:"setup: prefix is 79 chars" 79 (String.length prefix);
  let continuation = "s.code.tex" in
  let full_path = "/usr/local/texlive/2024/texmf-dist/tex/latex/pgf/compatibility/pgflibrarysnakes.code.tex" in
  let lines = [
    "(./main.tex";
    prefix;           (* exactly 79 chars → wrapped *)
    continuation;     (* continuation of filename; file stays on stack *)
    "! Undefined control sequence.";
    "l.5 \\broken";
    ")";              (* close the inner file *)
    ")";              (* close main.tex *)
  ] in
  let entries = Log_parser.parse_lines lines in
  let errors = List.filter
    (fun e -> e.Types.severity = Types.Error) entries in
  assert_int_equal ~msg:"one error found" 1 (List.length errors);
  let e = List.hd errors in
  assert_option_int ~msg:"error at line 5" (Some 5) e.line;
  (* After unwrapping, the error should be attributed to the full path *)
  assert_option_equal ~msg:"error file is the full unwrapped path" Fun.id
    (Some full_path) e.file

let test_multiple_errors_same_file () =
  let lines = [
    "(./messy.tex";
    "! Undefined control sequence.";
    "l.10 \\foo";
    "! Missing $ inserted.";
    "l.20 x^2";
    "! Extra alignment tab has been changed to \\cr.";
    "l.30 &";
    ")";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"three errors" 3 (List.length entries);
  assert_option_int ~msg:"first at line 10" (Some 10) (List.nth entries 0).line;
  assert_option_int ~msg:"second at line 20" (Some 20) (List.nth entries 1).line;
  assert_option_int ~msg:"third at line 30" (Some 30) (List.nth entries 2).line

let test_error_without_line_indicator () =
  (* An error that is flushed without ever seeing l.<N> *)
  let lines = [
    "(./broken.tex";
    "! Emergency stop.";
    "";
    "";
    "";
    "Some other text";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"one error entry" 1 (List.length entries);
  let e = List.hd entries in
  assert_option_int ~msg:"no line number" None e.line;
  assert_equal ~msg:"message" "Emergency stop." e.message

let test_mixed_errors_warnings_badboxes () =
  let lines = [
    "(./mixed.tex";
    "! Undefined control sequence.";
    "l.5 \\badcmd";
    "LaTeX Warning: Reference `fig:x' on page 1 undefined on input line 10.";
    "";
    "Overfull \\hbox (8.0pt too wide) in paragraph at lines 15--20";
    ")";
  ] in
  let entries = Log_parser.parse_lines lines in
  assert_int_equal ~msg:"three entries" 3 (List.length entries);
  assert_severity ~msg:"first is Error" Types.Error (List.nth entries 0).severity;
  assert_severity ~msg:"second is Warning" Types.Warning (List.nth entries 1).severity;
  assert_severity ~msg:"third is BadBox" Types.BadBox (List.nth entries 2).severity

(* ── Runner ────────────────────────────────────────────────── *)

(* ── Real logs (testdata/logs, made with TeX Live 2026) ─────── *)

(* "severity file:line message" for each entry, the message cut at 40 bytes. *)
(* "severity file:line message" for each entry. *)
let describe entries =
  List.map (fun (e : Types.log_entry) ->
    Printf.sprintf "%s %s:%s %s"
      (match e.severity with Types.Error -> "error" | Warning -> "warning" | BadBox -> "badbox")
      (Option.value ~default:"?" e.file)
      (Option.fold ~none:"?" ~some:string_of_int e.line) e.message) entries

let check_log name expected =
  let actual = describe (Log_parser.parse_file ("../testdata/logs/" ^ name)) in
  if actual <> expected then begin
    Printf.eprintf "FAIL: %s\n  expected:\n    %s\n  actual:\n    %s\n" name
      (String.concat "\n    " expected) (String.concat "\n    " actual);
    incr tests_failed
  end else incr tests_passed

let test_real_logs () =
  (* pdflatex without -file-line-error, as Tectonic runs: a file name with a
     space, and box contents with "(Fig.2" and an unmatched ")". *)
  check_log "parens-and-spaces.log" [
    "error ./chapter one.tex:2 Undefined control sequence.";
    "badbox ./chap3.tex:1 Overfull \\hbox (146.26979pt too wide) detected at line 1";
    "error ./chap3.tex:3 Undefined control sequence.";
    "badbox ./chap4.tex:1 Overfull \\hbox (144.74202pt too wide) detected at line 1";
    "error ./chap4.tex:3 Undefined control sequence.";
    "error ./main.tex:7 Undefined control sequence."];
  (* Package warnings continued on "(hyperref)" and "(rerunfilecheck)" lines. *)
  check_log "hyperref-multiline.log" [
    "warning ./main.tex:4 Token not allowed in a PDF string (Unicode): removing `\\\\' on input line 4.";
    "warning ./main.tex:? File `main.out' has changed. Rerun to get outlines right or use package `bookmark'."];
  (* XeTeX wraps at 79 characters, not bytes: a warning, and an error whose
     file:line: line is wrapped mid-message. *)
  let accents n = String.concat "" (List.init n (fun _ -> "\xc3\xa9")) in
  check_log "xelatex-wrap.log" [
    "warning ./main.tex:3 Reference `sec:" ^ accents 40 ^ "' on page 1 undefined on input line 3.";
    "warning ./main.tex:? There were undefined references."];
  check_log "xelatex-wrapped-error.log" [
    "error ./chapitre-" ^ accents 45 ^ ".tex:2 Undefined control sequence.";
    "error ./main.tex:5 Undefined control sequence."]

let () =
  Printf.printf "Log parser tests:\n";
  run_test "real logs: files, boxes, package and wrapped warnings" test_real_logs;
  run_test "empty input" test_empty_input;
  run_test "clean log" test_clean_log;
  run_test "undefined control sequence" test_undefined_control_sequence;
  run_test "missing dollar" test_missing_dollar;
  run_test "multi-line error with help text" test_multiline_error;
  run_test "LaTeX warning" test_latex_warning;
  run_test "package warning message extraction" test_package_warning_message;
  run_test "font warning" test_font_warning;
  run_test "warning with line number" test_warning_with_line_number;
  run_test "warning without line number" test_warning_without_line_number;
  run_test "overfull hbox" test_overfull_hbox;
  run_test "underfull vbox" test_underfull_vbox;
  run_test "file stack tracking" test_file_stack_tracking;
  run_test "multi-file project" test_multi_file_project;
  run_test "l. indicator only at column 0" test_line_indicator_column_zero;
  run_test "clean realistic log (no errors)" test_clean_realistic_log;
  run_test "79-char line wrapping" test_line_wrapping_79_chars;
  run_test "multiple errors same file" test_multiple_errors_same_file;
  run_test "error without line indicator" test_error_without_line_indicator;
  run_test "mixed errors, warnings, badboxes" test_mixed_errors_warnings_badboxes;
  Printf.printf "\nResults: %d passed, %d failed\n" !tests_passed !tests_failed;
  if !tests_failed > 0 then exit 1
