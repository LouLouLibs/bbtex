open Bbtex

let with_project f =
  let root = Filename.temp_file "bbtex-main-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let root = Unix.realpath root in
  let rec remove p =
    if (Unix.lstat p).st_kind = Unix.S_DIR then begin
      Array.iter (fun n -> remove (Filename.concat p n)) (Sys.readdir p); Unix.rmdir p
    end else Sys.remove p in
  let write name text =
    let path = Filename.concat root name in
    if not (Sys.file_exists (Filename.dirname path)) then Unix.mkdir (Filename.dirname path) 0o700;
    Out_channel.with_open_bin path (fun oc -> output_string oc text); path in
  Fun.protect ~finally:(fun () -> remove root) (fun () -> f root write)

let document body = "\\documentclass{article}\n\\begin{document}\n" ^ body ^ "\n\\end{document}\n"

let found = function Main_file.Found main -> Filename.basename main | _ -> "-"

let () =
  (* One main document next to the file, or one folder up, through \input,
     \include (no extension) and nested inputs. *)
  with_project (fun root write ->
    let table = write "tables/t1.tex" "a & b \\\\\n" in
    let intro = write "sections/intro.tex" "\\section{Intro}\n\\input{tables/t1}\n" in
    ignore (write "main.tex" (document "\\include{sections/intro}"));
    ignore (write "notes.tex" "No document class here.\n");
    assert (found (Main_file.find intro) = "main.tex");
    assert (found (Main_file.find table) = "main.tex");
    (* A resolved root is reported relative to the file. *)
    assert (Main_file.display ~source:intro (Filename.concat root "main.tex") = "../main.tex");
    assert (Main_file.display ~source:(Filename.concat root "x.tex") (Filename.concat root "main.tex") = "main.tex"));
  print_endline "Main file: single match, nested and one folder up passed"

let () =
  with_project (fun _ write ->
    let shared = write "shared.tex" "Shared text.\n" in
    ignore (write "paper.tex" (document "\\input{shared}"));
    ignore (write "slides.tex" (document "\\input shared.tex"));
    (match Main_file.find shared with
     | Main_file.Several [a; b] -> assert (Filename.basename a = "paper.tex" && Filename.basename b = "slides.tex")
     | _ -> assert false);
    let orphan = write "orphan.tex" "Nobody includes me.\n" in
    assert (Main_file.find orphan = Main_file.Unknown));
  print_endline "Main file: several matches and none passed"

let () =
  (* Comments don't count, a main document is its own, and input cycles end. *)
  with_project (fun _ write ->
    let part = write "part.tex" "Text.\n" in
    ignore (write "commented.tex" "% \\documentclass{article}\n\\input{part}\n");
    ignore (write "hidden.tex" (document "% \\input{part}"));
    assert (Main_file.find part = Main_file.Unknown);
    assert (Main_file.is_document (write "self.tex" (document "Self.")));
    assert (not (Main_file.is_document part));
    let a = write "a.tex" "\\input{b}\n" in
    ignore (write "b.tex" "\\input{a}\n");
    ignore (write "loop.tex" (document "\\input{b}"));
    assert (found (Main_file.find a) = "loop.tex"));
  print_endline "Main file: comments, main documents and cycles passed"

let () =
  (* Resolution: a found root is built, and reported; a document or an explicit
     root never triggers the search. *)
  with_project (fun root write ->
    let chapter = write "chapters/one.tex" "\\section{One}\n" in
    ignore (write "main.tex" ("%!TEX program = xelatex\n" ^ document "\\input{chapters/one}"));
    let config = Compiler.resolve_compilation chapter in
    assert (config.root_file = Filename.concat root "main.tex");
    assert (config.engine = Types.Xelatex);
    assert (config.root_source = Types.Found_main (Filename.concat root "main.tex"));
    assert (Compiler.root_description config = "found: ../main.tex includes this file");
    assert (Compiler.root_note config = Some "[bbtex] Building ../main.tex, which includes this file");
    let self = Compiler.resolve_compilation (Filename.concat root "main.tex") in
    assert (self.root_source = Types.This_file && Compiler.root_note self = None);
    ignore (write "chapters/two.tex" "%!TEX root = ../main.tex\n");
    let direct = Compiler.resolve_compilation (Filename.concat root "chapters/two.tex") in
    assert (direct.root_source = Types.Root_directive);
    ignore (write "other.tex" (document "\\input{chapters/one}"));
    let ambiguous = Compiler.resolve_compilation chapter in
    assert (ambiguous.root_file = chapter);
    assert (Compiler.root_note ambiguous = Some
      "[bbtex] Several documents include this file (../main.tex, ../other.tex): choose one with Configure Document…"));
  print_endline "Main file: compilation roots passed"
