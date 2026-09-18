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

(* ── Testdata path resolution ───────────────────────────────── *)

(* Dune runs tests from _build/default/test/; find testdata relative to cwd
   or fall back to the source tree. *)
let testdata_dir =
  let cwd = Sys.getcwd () in
  if Sys.file_exists (Filename.concat cwd "testdata") then
    Filename.concat cwd "testdata"
  else
    Filename.concat (Filename.dirname (Filename.dirname (Filename.dirname cwd))) "testdata"

let sample_tex = Filename.concat testdata_dir "sample.tex"

(* ── Tests: resolve_compilation ────────────────────────────── *)

let test_resolve_sample_engine () =
  let config = Compiler.resolve_compilation sample_tex in
  assert_equal ~msg:"engine is pdflatex"
    "pdflatex" (Types.string_of_engine config.Types.engine)

let test_resolve_sample_root_file () =
  let config = Compiler.resolve_compilation sample_tex in
  (* root_file should end with sample.tex *)
  assert_true ~msg:"root_file ends with sample.tex"
    (let s = config.Types.root_file in
     let suffix = "sample.tex" in
     String.length s >= String.length suffix &&
     String.sub s (String.length s - String.length suffix) (String.length suffix) = suffix)

let test_resolve_sample_log_file () =
  let config = Compiler.resolve_compilation sample_tex in
  assert_true ~msg:"log_file ends with sample.log"
    (let s = config.Types.log_file in
     let suffix = "sample.log" in
     String.length s >= String.length suffix &&
     String.sub s (String.length s - String.length suffix) (String.length suffix) = suffix)

let test_resolve_sample_pdf_file () =
  let config = Compiler.resolve_compilation sample_tex in
  assert_true ~msg:"pdf_file ends with sample.pdf"
    (let s = config.Types.pdf_file in
     let suffix = "sample.pdf" in
     String.length s >= String.length suffix &&
     String.sub s (String.length s - String.length suffix) (String.length suffix) = suffix)

let test_resolve_sample_root_is_absolute () =
  let config = Compiler.resolve_compilation sample_tex in
  assert_true ~msg:"root_file is absolute"
    (not (Filename.is_relative config.Types.root_file))

let test_resolve_nonexistent_raises () =
  let path = "/nonexistent/no/such/file.tex" in
  try
    let _ = Compiler.resolve_compilation path in
    Printf.eprintf "FAIL: resolve_compilation should have raised for nonexistent file\n";
    incr tests_failed
  with
  | Compiler.Bbtex_error msg ->
    assert_true ~msg:"error message contains 'not found'"
      (contains msg "not found");
    incr tests_passed
  | e ->
    Printf.eprintf "FAIL: unexpected exception: %s\n" (Printexc.to_string e);
    incr tests_failed

let test_resolve_non_tex_raises () =
  (* Create a temp .txt file *)
  let tmp = Filename.temp_file "bbtex_test_" ".txt" in
  Fun.protect ~finally:(fun () -> (try Sys.remove tmp with _ -> ())) (fun () ->
    (* Write something to it so it exists *)
    let oc = open_out tmp in
    output_string oc "not a tex file\n";
    close_out oc;
    try
      let _ = Compiler.resolve_compilation tmp in
      Printf.eprintf "FAIL: resolve_compilation should have raised for .txt file\n";
      incr tests_failed
    with
    | Compiler.Bbtex_error msg ->
      assert_true ~msg:"error message contains '.tex'"
        (contains msg ".tex");
      incr tests_passed
    | e ->
      Printf.eprintf "FAIL: unexpected exception: %s\n" (Printexc.to_string e);
      incr tests_failed
  )

(* ── Tests: make_summary ────────────────────────────────────── *)

let make_entry severity =
  { Types.severity; file = None; line = None; message = ""; context = [] }

let test_make_summary_empty () =
  let s = Compiler.make_summary [] in
  assert_equal ~msg:"empty → zero counts"
    "0 error(s), 0 warning(s), 0 bad box(es)" s

let test_make_summary_counts () =
  let entries = [
    make_entry Types.Error;
    make_entry Types.Error;
    make_entry Types.Warning;
    make_entry Types.BadBox;
    make_entry Types.BadBox;
    make_entry Types.BadBox;
  ] in
  let s = Compiler.make_summary entries in
  assert_equal ~msg:"correct counts"
    "2 error(s), 1 warning(s), 3 bad box(es)" s

let test_engine_precedence () =
  let root = Filename.temp_file "bbtex_root_" ".tex" in
  let chapter = Filename.temp_file "bbtex_chapter_" ".tex" in
  let write path text =
    let oc = open_out path in output_string oc text; close_out oc
  in
  Fun.protect ~finally:(fun () -> Sys.remove root; Sys.remove chapter) (fun () ->
    write root "%!TEX program = xelatex\n";
    write chapter ("%!TEX root = " ^ root ^ "\n");
    let engine ?engine () =
      Types.string_of_engine
        (Compiler.resolve_compilation ?engine chapter).Types.engine
    in
    assert_equal ~msg:"chapter inherits root engine" "xelatex" (engine ());
    write chapter ("%!TEX root = " ^ root ^ "\n%!TEX program = lualatex\n");
    assert_equal ~msg:"source overrides root engine" "lualatex" (engine ());
    assert_equal ~msg:"explicit choice overrides directives"
      "tectonic" (engine ~engine:Types.Tectonic ()))

(* ── Runner ────────────────────────────────────────────────── *)

let () =
  Printf.printf "Compiler tests:\n";
  run_test "engine precedence" test_engine_precedence;
  run_test "resolve_compilation: engine is pdflatex" test_resolve_sample_engine;
  run_test "resolve_compilation: root_file ends with sample.tex" test_resolve_sample_root_file;
  run_test "resolve_compilation: log_file ends with sample.log" test_resolve_sample_log_file;
  run_test "resolve_compilation: pdf_file ends with sample.pdf" test_resolve_sample_pdf_file;
  run_test "resolve_compilation: root_file is absolute" test_resolve_sample_root_is_absolute;
  run_test "resolve_compilation: nonexistent file raises Bbtex_error with 'not found'" test_resolve_nonexistent_raises;
  run_test "resolve_compilation: non-.tex file raises Bbtex_error with '.tex'" test_resolve_non_tex_raises;
  run_test "make_summary: empty list" test_make_summary_empty;
  run_test "make_summary: counts errors/warnings/badboxes" test_make_summary_counts;
  Printf.printf "\nResults: %d passed, %d failed\n" !tests_passed !tests_failed;
  if !tests_failed > 0 then exit 1
