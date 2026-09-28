open Bbtex
open Magic_comments

let comment ?(family=Tex) ?(file="/p/main.tex") ?(line=1) key value = { file; line; family; key; value }

let ignored ?(affects_build=true) status = match status with
  | Ignored i -> i.affects_build = affects_build
  | Used | Mapped _ -> false

let mapped ?warning status = match status with
  | Mapped m -> (match warning with
      | None -> m.warning = None
      | Some sub -> (match m.warning with Some w -> Log_parser.contains_substring ~sub w | None -> false))
  | Used | Ignored _ -> false

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
  assert (ignored ~affects_build:false (classify (comment "encoding" "UTF-8 Unicode")));
  assert (ignored ~affects_build:false (classify (comment "spellcheck" "en_US")));
  List.iter (fun key -> assert (ignored (classify (comment key "x"))))
    ["aux_directory"; "jobname"; "progam"];
  assert (ignored (classify (comment ~family:Bib "engine" "x")));
  assert (ignored (classify (comment "root ../main.tex" "")));
  print_endline "Magic comments: used and ignored comments passed"

let () =
  (* options and TeXShop's parameter become compiler options; shell escape
     needs .bbtex, and malformed options are reported, not applied. *)
  assert (classify (comment "options" "-8bit") = Mapped { becomes = "options -8bit"; warning = None });
  assert (mapped (classify (comment "parameter" "--interaction=batchmode")));
  assert (mapped ~warning:"add options = -shell-escape to .bbtex"
    (classify (comment "options" "-shell-escape -8bit")));
  assert (mapped ~warning:"add options = --enable-write18 to .bbtex" (classify (comment "parameter" "--enable-write18")));
  let trusted = { no_context with project_options = ["-shell-escape"] } in
  assert (mapped (classify ~context:trusted (comment "options" "-shell-escape")));
  assert (mapped (classify (comment "options" "-no-shell-escape")));
  assert (ignored (classify (comment "options" "-outdir=elsewhere")));
  assert (ignored (classify (comment "options" "main.tex")));
  (* output_directory: used unless .bbtex sets a different one. *)
  let context = { no_context with root_dir = "/p" } in
  assert (mapped (classify ~context (comment "output_directory" "build")));
  assert (mapped (classify ~context:{ context with project_output = Some "/p/build" }
    (comment "output_directory" "build")));
  assert (ignored (classify ~context:{ context with project_output = Some "/p/out" }
    (comment "output_directory" "build")));
  assert (ignored (classify ~context (comment "output_directory" "<<temp>>")));
  (* % !BIB: checked against what the last build ran. *)
  assert (mapped (classify (comment ~family:Bib "TS-program" "biber")));
  assert (mapped (classify ~context:{ no_context with bib_ran = Some `Biber } (comment ~family:Bib "TS-program" "biber")));
  assert (mapped ~warning:"the last build ran BibTeX"
    (classify ~context:{ no_context with bib_ran = Some `Bibtex } (comment ~family:Bib "TS-program" "biber")));
  assert (mapped ~warning:"the last build ran Biber"
    (classify ~context:{ no_context with bib_ran = Some `Biber } (comment ~family:Bib "program" "bibtex")));
  assert (mapped (classify (comment ~family:Bib "TS-program" "bibtex8")));
  assert (ignored (classify ~context:{ no_context with latexmk = false } (comment ~family:Bib "TS-program" "bibtex8")));
  assert (ignored (classify (comment ~family:Bib "TS-program" "makeindex")));
  print_endline "Magic comments: mapped comments passed"

let () =
  (* The document's build settings come from the first comment for each. *)
  let chapter = comment ~file:"/p/chapter.tex" in
  let doc = document [chapter "parameter" "-8bit -shell-escape"; comment "options" "-draftmode";
    chapter "output_directory" "<<temp>>"; comment "output_directory" "later";
    comment ~family:Bib "TS-program" "upBibTeX"] in
  assert (doc.options = ["-8bit"]);
  assert (doc.output_directory = None);
  assert (doc.bibtex = Some "upbibtex");
  assert (document [comment ~family:Bib "TS-program" "biber"] = { options = []; output_directory = None; bibtex = None });
  (match document [comment ~line:4 "options" "-outdir=x"] with
   | exception Project.Error message ->
     assert (String.starts_with ~prefix:"/p/main.tex:4: % !TEX options = -outdir=x: " message)
   | _ -> assert false);
  print_endline "Magic comments: document settings passed"

let () =
  (* Only the first root or program in a file is read; mapped settings read
     the first along the whole chain. *)
  let at line key value = comment ~line key value in
  let statuses = statuses [at 1 "program" "xelatex"; at 2 "TS-program" "lualatex";
    at 3 "root" "a.tex"; { (at 4 "root" "b.tex") with file = "/p/other.tex" };
    at 5 "options" "-8bit"; { (at 1 "parameter" "-draftmode") with file = "/p/other.tex" }] in
  (match List.map snd statuses with
   | [Used; Ignored { affects_build = true; _ }; Used; Used; Mapped _; Ignored { affects_build = true; _ }] -> ()
   | _ -> assert false);
  (* No note when every comment applies. *)
  let fine = Magic_comments.statuses [at 1 "root" "main.tex"; at 2 "program" "xelatex";
    at 3 "encoding" "UTF-8"; at 4 "options" "-8bit"] in
  assert (build_note fine = None && results fine = []);
  let noted = Magic_comments.statuses [at 1 "options" "-shell-escape"; at 3 "jobname" "x"] in
  assert (build_note noted = Some "[bbtex] Not fully applied: % !TEX options, % !TEX jobname; see LaTeX — Doctor");
  (match results noted with
   | [first; second] ->
     assert (first.Types.se_line = 1 && first.se_severity = Types.Warning);
     assert (String.starts_with ~prefix:"[bbtex] % !TEX options = -shell-escape can't turn on shell escape" first.se_message);
     assert (second.se_message = "[bbtex] % !TEX jobname = x is ignored: the PDF is named after the root file; \
       rename the root file instead")
   | _ -> assert false);
  assert (doctor_lines ~dir:"/p" (Magic_comments.statuses [at 3 "options" "-8bit"]) =
    ["OK", "main.tex:3 % !TEX options = -8bit (mapped: options -8bit)"]);
  assert (doctor_lines ~dir:"/p/" (Magic_comments.statuses [at 1 "jobname" "x"]) =
    ["WARN", "main.tex:1 % !TEX jobname = x (ignored: the PDF is named after the root file; rename the root file instead)"]);
  print_endline "Magic comments: statuses, build note and results passed"

let () =
  (* Files: the first 50 lines, a byte-order mark, each file once, unreadable
     files skipped; and which bibliography tool a .blg says ran. *)
  let file = Filename.temp_file "bbtex-magic-" ".tex" in
  Fun.protect ~finally:(fun () -> Sys.remove file) (fun () ->
    Out_channel.with_open_bin file (fun oc ->
      output_string oc "\xef\xbb\xbf% !TEX options = -8bit\n";
      for _ = 2 to 50 do output_string oc "text\n" done;
      output_string oc "% !TEX jobname = late\n");
    (match scan [file; file; "/nonexistent/absent.tex"] with
     | [c] -> assert (c.key = "options" && c.line = 1)
     | _ -> assert false);
    Out_channel.with_open_bin file (fun oc -> output_string oc "This is BibTeX, Version 0.99e (TeX Live 2026)\n");
    assert (bib_ran file = Some `Bibtex);
    Out_channel.with_open_bin file (fun oc -> output_string oc "[0] Config.pm:328> INFO - This is Biber 2.21\n");
    assert (bib_ran file = Some `Biber);
    Out_channel.with_open_bin file (fun oc -> output_string oc "");
    assert (bib_ran file = None);
    assert (bib_ran "/nonexistent/absent.blg" = None));
  print_endline "Magic comments: file scanning passed"
