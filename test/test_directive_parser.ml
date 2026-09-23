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

let run_test name f =
  Printf.printf "  %s ... " name;
  (try
     f ();
     Printf.printf "ok\n"
   with e ->
     Printf.eprintf "EXCEPTION: %s\n" (Printexc.to_string e);
     incr tests_failed)

(* ── Helper: parse directives from a string list ───────────── *)

(** Since Directive_parser.parse_file reads from a file, and we want
    to test with inline strings, we use the exported parse_directive_line
    function directly, simulating the first-50-lines behavior. *)
let parse_lines_as_directives lines =
  let max_lines = 50 in
  let rec loop n acc = function
    | [] -> List.rev acc
    | _ when n >= max_lines -> List.rev acc
    | line :: rest ->
      let acc' = match Directive_parser.parse_directive_line line with
        | Some d -> d :: acc
        | None   -> acc
      in
      loop (n + 1) acc' rest
  in
  loop 0 [] lines

(* ── Tests ─────────────────────────────────────────────────── *)

let test_basic_root () =
  let lines = ["%!TEX root = ../main.tex"] in
  let ds = parse_lines_as_directives lines in
  assert_int_equal ~msg:"one directive" 1 (List.length ds);
  let d = List.hd ds in
  assert_equal ~msg:"key is Root"
    "root" (Types.string_of_directive_key d.key);
  assert_equal ~msg:"value" "../main.tex" d.value

let test_basic_program () =
  let lines = ["%!TEX program = xelatex"] in
  let ds = parse_lines_as_directives lines in
  assert_int_equal ~msg:"one directive" 1 (List.length ds);
  let d = List.hd ds in
  assert_equal ~msg:"key is Program"
    "program" (Types.string_of_directive_key d.key);
  assert_equal ~msg:"value" "xelatex" d.value

let test_case_insensitivity () =
  (* The %!TEX prefix should be case-insensitive *)
  let variants = [
    "%!tex root = ./main.tex";
    "%!TEX root = ./main.tex";
    "%!Tex root = ./main.tex";
    "%!tEX root = ./main.tex";
  ] in
  List.iter (fun line ->
    let ds = parse_lines_as_directives [line] in
    assert_int_equal
      ~msg:(Printf.sprintf "directive found for '%s'" line)
      1 (List.length ds);
    assert_equal
      ~msg:(Printf.sprintf "value for '%s'" line)
      "./main.tex" (List.hd ds).value
  ) variants

let test_missing_equals () =
  let lines = ["%!TEX root ../main.tex"] in
  let ds = parse_lines_as_directives lines in
  assert_int_equal ~msg:"no directive without '='" 0 (List.length ds)

let test_empty_value () =
  let lines = ["%!TEX root = "] in
  let ds = parse_lines_as_directives lines in
  assert_int_equal ~msg:"no directive with empty value" 0 (List.length ds)

let test_multiple_directives () =
  let lines = [
    "%!TEX root = ../main.tex";
    "%!TEX program = lualatex";
    "%!TEX encoding = UTF-8";
  ] in
  let ds = parse_lines_as_directives lines in
  assert_int_equal ~msg:"three directives" 3 (List.length ds);
  assert_equal ~msg:"first key" "root"
    (Types.string_of_directive_key (List.nth ds 0).key);
  assert_equal ~msg:"second key" "program"
    (Types.string_of_directive_key (List.nth ds 1).key);
  assert_equal ~msg:"third key" "encoding"
    (Types.string_of_directive_key (List.nth ds 2).key);
  assert_equal ~msg:"first value" "../main.tex" (List.nth ds 0).value;
  assert_equal ~msg:"second value" "lualatex" (List.nth ds 1).value;
  assert_equal ~msg:"third value" "UTF-8" (List.nth ds 2).value

let test_non_directive_lines_ignored () =
  let lines = [
    "\\documentclass{article}";
    "% This is a comment";
    "%!TEX root = ../main.tex";
    "\\begin{document}";
    "Hello world";
  ] in
  let ds = parse_lines_as_directives lines in
  assert_int_equal ~msg:"only one directive" 1 (List.length ds);
  assert_equal ~msg:"value" "../main.tex" (List.hd ds).value

let test_only_first_50_lines () =
  (* Create 60 lines: a directive at line 1, non-directive filler,
     and a directive at line 55 (which should be ignored) *)
  let lines =
    ["%!TEX root = ../first.tex"] @
    List.init 53 (fun i -> Printf.sprintf "Line %d of filler" (i + 2)) @
    ["%!TEX program = xelatex"]
  in
  assert_true ~msg:"test has 55 lines" (List.length lines = 55);
  let ds = parse_lines_as_directives lines in
  assert_int_equal ~msg:"only first directive found" 1 (List.length ds);
  assert_equal ~msg:"value is first.tex" "../first.tex" (List.hd ds).value

let test_whitespace_handling () =
  (* Extra whitespace around key and value *)
  let lines = ["%!TEX   root   =   ../main.tex  "] in
  let ds = parse_lines_as_directives lines in
  assert_int_equal ~msg:"one directive" 1 (List.length ds);
  assert_equal ~msg:"value trimmed" "../main.tex" (List.hd ds).value

let test_directive_key_unknown () =
  let lines = ["%!TEX foobar = something"] in
  let ds = parse_lines_as_directives lines in
  assert_int_equal ~msg:"one directive" 1 (List.length ds);
  let d = List.hd ds in
  assert_equal ~msg:"key is Other foobar"
    "foobar" (Types.string_of_directive_key d.key)

let test_find_directive () =
  let directives = [
    { Types.key = Types.Root; value = "../main.tex" };
    { Types.key = Types.Program; value = "xelatex" };
  ] in
  let root = Directive_parser.find_directive Types.Root directives in
  assert_equal ~msg:"found root" "../main.tex"
    (Option.value ~default:"<none>" root);
  let prog = Directive_parser.find_directive Types.Program directives in
  assert_equal ~msg:"found program" "xelatex"
    (Option.value ~default:"<none>" prog);
  let enc = Directive_parser.find_directive Types.Encoding directives in
  assert_true ~msg:"encoding not found" (enc = None)

(* ── Runner ────────────────────────────────────────────────── *)

let () =
  Printf.printf "Directive parser tests:\n";
  run_test "basic root directive" test_basic_root;
  run_test "byte-order mark before the first directive" (fun () ->
    let file = Filename.temp_file "bbtex_bom_" ".tex" in
    Fun.protect ~finally:(fun () -> Sys.remove file) (fun () ->
      let oc = open_out_bin file in
      output_string oc "\xef\xbb\xbf%!TEX root = main.tex\n%!TEX program = xelatex\n";
      close_out oc;
      let directives = Directive_parser.parse_file file in
      assert_equal ~msg:"root after BOM" "main.tex"
        (Option.value ~default:"(none)" (Directive_parser.find_directive Types.Root directives));
      assert_equal ~msg:"program on the next line" "xelatex"
        (Option.value ~default:"(none)" (Directive_parser.find_directive Types.Program directives))));
  run_test "TeXShop spacing and engine alias" (fun () ->
    List.iter (fun line ->
      match Directive_parser.parse_directive_line line with
      | Some d -> assert_true ~msg:"program alias" (d.key = Types.Program);
          assert_equal ~msg:"engine" "xelatex" d.value
      | None -> assert_true ~msg:"directive recognized" false)
      ["% !TEX TS-program = xelatex"; "%\t!TeX program = xelatex"; "%!tex ts-program = xelatex"]);
  run_test "basic program directive" test_basic_program;
  run_test "case insensitivity" test_case_insensitivity;
  run_test "missing equals sign" test_missing_equals;
  run_test "empty value" test_empty_value;
  run_test "multiple directives" test_multiple_directives;
  run_test "non-directive lines ignored" test_non_directive_lines_ignored;
  run_test "only first 50 lines searched" test_only_first_50_lines;
  run_test "whitespace handling" test_whitespace_handling;
  run_test "unknown directive key" test_directive_key_unknown;
  run_test "find_directive helper" test_find_directive;
  Printf.printf "\nResults: %d passed, %d failed\n" !tests_passed !tests_failed;
  if !tests_failed > 0 then exit 1
