open Bbtex
open Magic_comments

let comment ?(family=Tex) key value = { file = "/p/main.tex"; line = 1; family; key; value }

let ignored ?(affects_build=true) c = match classify c with
  | Ignored i -> i.affects_build = affects_build
  | Used -> false

let () =
  (* Parsing: both spellings, any case, % !BIB, and a directive missing its "=". *)
  assert (parse_line "%!TEX root = main.tex" = Some (Tex, "root", "main.tex"));
  assert (parse_line "  %\t!TeX TS-program = xelatex " = Some (Tex, "TS-program", "xelatex"));
  assert (parse_line "% !BIB TS-program = biber" = Some (Bib, "TS-program", "biber"));
  assert (parse_line "%!TEX root ../main.tex" = Some (Tex, "root ../main.tex", ""));
  assert (parse_line "%!TEXT is not a directive" = None);
  assert (parse_line "% a comment mentioning !TEX" = None);
  assert (parse_line "\\section{!TEX}" = None);
  print_endline "Magic comments: parsing passed"

let () =
  assert (classify (comment "root" "main.tex") = Used);
  assert (classify (comment "program" "xelatex") = Used);
  assert (classify (comment "TS-program" "lualatex") = Used);
  assert (ignored ~affects_build:false (comment "encoding" "UTF-8 Unicode"));
  assert (ignored ~affects_build:false (comment "spellcheck" "en_US"));
  assert (ignored ~affects_build:false (comment ~family:Bib "TS-program" "biber"));
  List.iter (fun key -> assert (ignored (comment key "x")))
    ["parameter"; "options"; "output_directory"; "aux_directory"; "jobname"; "progam"];
  assert (ignored (comment ~family:Bib "engine" "x"));
  assert (ignored (comment "root ../main.tex" ""));
  (match classify (comment "options" "--shell-escape") with
   | Ignored { advice; _ } -> assert (advice = "put it in .bbtex as options = --shell-escape")
   | Used -> assert false);
  (match classify (comment "output_directory" "build") with
   | Ignored { advice; _ } -> assert (advice = "put it in .bbtex as output_directory = build")
   | Used -> assert false);
  print_endline "Magic comments: classification passed"

let () =
  (* Only the first root or program in a file is read; TS-program is program. *)
  let at line key value = { (comment key value) with line } in
  let statuses = statuses [at 1 "program" "xelatex"; at 2 "TS-program" "lualatex";
    at 3 "root" "a.tex"; { (at 4 "root" "b.tex") with file = "/p/other.tex" }] in
  (match List.map snd statuses with
   | [Used; Ignored { affects_build = true; _ }; Used; Used] -> ()
   | _ -> assert false);
  (* No note when a document only uses root and program. *)
  assert (build_note [at 1 "root" "main.tex"; at 2 "program" "xelatex"; at 3 "encoding" "UTF-8"] = None);
  assert (results [at 1 "root" "main.tex"; at 2 "encoding" "UTF-8"] = []);
  let noted = [at 1 "options" "--shell-escape"; at 2 "options" "-8bit"; at 3 "jobname" "x"] in
  assert (build_note noted = Some "[bbtex] Ignored % !TEX options, % !TEX jobname; see LaTeX — Doctor");
  (match results noted with
   | [first; _; _] ->
     assert (first.Types.se_line = 1 && first.se_severity = Types.Warning);
     assert (first.se_message =
       "[bbtex] % !TEX options = --shell-escape is ignored: put it in .bbtex as options = --shell-escape")
   | _ -> assert false);
  assert (doctor_lines ~dir:"/p" [at 3 "options" "-8bit"] =
    ["WARN", "main.tex:3 % !TEX options = -8bit (ignored: put it in .bbtex as options = -8bit)"]);
  assert (doctor_lines ~dir:"/p/" [at 1 "root" "main.tex"] = ["OK", "main.tex:1 % !TEX root = main.tex (used)"]);
  print_endline "Magic comments: statuses, build note and results passed"

let () =
  (* Files: the first 50 lines, a byte-order mark, each file once, unreadable files skipped. *)
  let file = Filename.temp_file "bbtex-magic-" ".tex" in
  Fun.protect ~finally:(fun () -> Sys.remove file) (fun () ->
    Out_channel.with_open_bin file (fun oc ->
      output_string oc "\xef\xbb\xbf% !TEX options = -8bit\n";
      for _ = 2 to 50 do output_string oc "text\n" done;
      output_string oc "% !TEX jobname = late\n");
    match scan [file; file; "/nonexistent/absent.tex"] with
    | [c] -> assert (c.key = "options" && c.line = 1)
    | _ -> assert false);
  print_endline "Magic comments: file scanning passed"
