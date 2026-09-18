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
  print_endline "Document settings: replacement, inheritance, CRLF, idempotence, and external roots passed"
