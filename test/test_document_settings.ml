open Bbtex
let () =
  assert (Document_settings.update "% !TeX TS-program = pdflatex\n% !TEX root = old.tex\nbody\n" ~engine:"xelatex" ~root:(Some "main.tex") = "%!TEX root = main.tex\n%!TEX program = xelatex\nbody\n");
  let original = "%!TEX program = pdflatex\r\n%!TEX root = old.tex\r\n%!TEX encoding = UTF-8\r\n\\input{table1}\r\n" in
  let updated = Document_settings.update original ~engine:"xelatex" ~root:(Some "../main.tex") in
  assert (updated = "%!TEX root = ../main.tex\r\n%!TEX program = xelatex\r\n%!TEX encoding = UTF-8\r\n\\input{table1}\r\n");
  assert (Document_settings.update updated ~engine:"xelatex" ~root:(Some "../main.tex") = updated);
  assert (Document_settings.update "body without newline" ~engine:"inherit" ~root:None = "body without newline");
  assert (Document_settings.update "%!TEX program = xelatex\n%!TEX root = ../main.tex\nbody\n" ~engine:"inherit" ~root:None = "%!TEX root = ../main.tex\nbody\n");
  assert (Document_settings.relative_path ~source:"/project/tables/table1.tex" "/elsewhere/main.tex" = "../../elsewhere/main.tex");
  (* BBEdit compares and edits in LF, so a CRLF file's script must too. *)
  let file = Filename.temp_file "bbtex-crlf-" ".tex" in
  Out_channel.with_open_bin file (fun oc ->
    output_string oc "%!TEX program = pdflatex\r\n\\documentclass{article}\r\nHi\r\n");
  let script = Document_settings.script file "xelatex" "-" in
  Sys.remove file;
  assert (not (String.contains script '\r'));
  let contains part = Project_index.find script 0 part < String.length script in
  assert (contains "is not \"%!TEX program = pdflatex\n\\\\documentclass{article}\nHi\n\"");
  assert (contains "set text of d to \"%!TEX program = xelatex\n\\\\documentclass{article}\nHi\n\"");
  print_endline "Document settings: replacement, inheritance, CRLF, idempotence, and external roots passed"
