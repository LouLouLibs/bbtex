open Bbtex
open Latexmkrc

let () =
  (* Assignments: spacing, comments, other variables, comparisons. *)
  assert (assignment "out_dir" "$out_dir = 'build';" = Some "'build'");
  assert (assignment "out_dir" "  $out_dir='build'  # Overleaf" = Some "'build'");
  assert (assignment "out_dir" "# $out_dir = 'build';" = None);
  assert (assignment "out_dir" "$out_dir_extra = 'x';" = None);
  assert (assignment "out_dir" "if ($out_dir == 1) {}" = None);
  assert (assignment "aux_dir" "$aux_dir = \"$out_dir/aux\";" = Some "\"$out_dir/aux\"");
  assert (assignment "pdf_mode" "$pdf_mode = 4; $postscript_mode = 0;" = Some "4");
  (* Literals only: interpolated or computed values are unknown. *)
  assert (literal "'build'" = Some "build");
  assert (literal "\"build\"" = Some "build");
  assert (literal "5" = Some "5");
  assert (literal "\"$out_dir/aux\"" = None);
  assert (literal "catfile('a', 'b')" = None);
  print_endline "latexmkrc: assignment and literal parsing passed"

let config ~root_dir ?(engine=Types.Pdflatex) output_directory =
  let root_file = Filename.concat root_dir "main.tex" in
  { Types.source_file = root_file; root_file; chain = [root_file]; root_source = Types.This_file;
    engine; project_dir = root_dir; output_directory; options = []; profile = None;
    project_options = []; project_output = None; bibtex = None;
    log_file = ""; pdf_file = "" }

let () =
  let root = Filename.temp_file "bbtex-rc-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let home = Filename.concat root "home" and project = Filename.concat root "project" in
  Unix.mkdir home 0o700; Unix.mkdir project 0o700;
  let write path text = Out_channel.with_open_bin path (fun oc -> output_string oc text) in
  let rc = Filename.concat project "latexmkrc" and dotrc = Filename.concat project ".latexmkrc" in
  Fun.protect ~finally:(fun () -> List.iter (fun f -> if Sys.file_exists f then Sys.remove f)
      [rc; dotrc; Filename.concat home ".latexmkrc"];
      Unix.rmdir home; Unix.rmdir project; Unix.rmdir root) (fun () ->
    let inspect ?engine output = inspect ~home ~config_home:(Filename.concat home ".config")
        (config ~root_dir:project ?engine output) in
    assert (inspect project = []);
    (* latexmk reads the first of latexmkrc and .latexmkrc, and a user file. *)
    write dotrc "$out_dir = 'dot';\n";
    write rc "$out_dir = 'build';\n$pdf_mode = 4;\n";
    write (Filename.concat home ".latexmkrc") "# nothing\n";
    assert (files ~home ~config_home:(Filename.concat home ".config") ~root_dir:project =
      [Filename.concat home ".latexmkrc"; rc]);
    let findings = inspect (Filename.concat project "build") ~engine:Types.Lualatex in
    assert (List.for_all (fun f -> not f.overridden) findings);
    assert (build_note findings = None && results findings = []);
    let findings = inspect project in
    assert (List.map (fun f -> f.line, f.overridden) (List.filter (fun f -> f.file = rc) findings) =
      [0, false; 1, true; 2, true]);
    assert (build_note findings = Some "[bbtex] latexmkrc $out_dir, $pdf_mode replaced by bbtex's settings; see LaTeX — Doctor");
    (match results findings with
     | [first; _] -> assert (first.se_file = rc && first.se_line = 1 &&
         String.starts_with ~prefix:"[bbtex] latexmkrc: $out_dir is replaced" first.se_message)
     | _ -> assert false);
    (* Tectonic and RaTeX don't run latexmk: the file is noted, nothing replaced. *)
    let tectonic = inspect project ~engine:Types.Tectonic in
    assert (List.for_all (fun f -> f.line = 0 && not f.overridden) tectonic));
  print_endline "latexmkrc: file discovery, findings, note and results passed"
