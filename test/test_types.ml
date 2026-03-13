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

let run_test name f =
  Printf.printf "  %s ... " name;
  (try
     f ();
     Printf.printf "ok\n"
   with e ->
     Printf.eprintf "EXCEPTION: %s\n" (Printexc.to_string e);
     incr tests_failed)

(* ── Tests ─────────────────────────────────────────────────── *)

let test_engine_of_string_known () =
  assert_equal ~msg:"pdflatex" "pdflatex"
    (Types.string_of_engine (Types.engine_of_string "pdflatex"));
  assert_equal ~msg:"xelatex" "xelatex"
    (Types.string_of_engine (Types.engine_of_string "xelatex"));
  assert_equal ~msg:"lualatex" "lualatex"
    (Types.string_of_engine (Types.engine_of_string "lualatex"));
  assert_equal ~msg:"tectonic" "tectonic"
    (Types.string_of_engine (Types.engine_of_string "tectonic"))

let test_engine_of_string_case_insensitive () =
  assert_equal ~msg:"Pdflatex uppercase" "pdflatex"
    (Types.string_of_engine (Types.engine_of_string "Pdflatex"));
  assert_equal ~msg:"XELATEX all caps" "xelatex"
    (Types.string_of_engine (Types.engine_of_string "XELATEX"));
  assert_equal ~msg:"LuaLatex mixed" "lualatex"
    (Types.string_of_engine (Types.engine_of_string "LuaLatex"));
  assert_equal ~msg:"Tectonic mixed" "tectonic"
    (Types.string_of_engine (Types.engine_of_string "Tectonic"))

let test_engine_of_string_unknown_defaults_to_pdflatex () =
  assert_equal ~msg:"unknown engine defaults to pdflatex" "pdflatex"
    (Types.string_of_engine (Types.engine_of_string "bogusengine"));
  assert_equal ~msg:"empty string defaults to pdflatex" "pdflatex"
    (Types.string_of_engine (Types.engine_of_string ""))

let test_string_of_engine_all_variants () =
  assert_equal ~msg:"Pdflatex -> pdflatex" "pdflatex"
    (Types.string_of_engine Types.Pdflatex);
  assert_equal ~msg:"Xelatex -> xelatex" "xelatex"
    (Types.string_of_engine Types.Xelatex);
  assert_equal ~msg:"Lualatex -> lualatex" "lualatex"
    (Types.string_of_engine Types.Lualatex);
  assert_equal ~msg:"Tectonic -> tectonic" "tectonic"
    (Types.string_of_engine Types.Tectonic)

let test_latexmk_flag () =
  assert_equal ~msg:"pdflatex flag" "-pdflatex"
    (Types.latexmk_flag Types.Pdflatex);
  assert_equal ~msg:"xelatex flag" "-pdfxelatex"
    (Types.latexmk_flag Types.Xelatex);
  assert_equal ~msg:"lualatex flag" "-pdflualatex"
    (Types.latexmk_flag Types.Lualatex)

(* ── Runner ────────────────────────────────────────────────── *)

let () =
  Printf.printf "Types tests:\n";
  run_test "engine_of_string known values" test_engine_of_string_known;
  run_test "engine_of_string case insensitivity" test_engine_of_string_case_insensitive;
  run_test "engine_of_string unknown defaults to pdflatex" test_engine_of_string_unknown_defaults_to_pdflatex;
  run_test "string_of_engine all variants" test_string_of_engine_all_variants;
  run_test "latexmk_flag pdflatex xelatex lualatex" test_latexmk_flag;
  Printf.printf "\nResults: %d passed, %d failed\n" !tests_passed !tests_failed;
  if !tests_failed > 0 then exit 1
