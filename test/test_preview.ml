open Bbtex
let () =
  let equation = "\\begin{align*}\nx &= 2\\\\\ny &= 3\n\\end{align*}" in
  let source = "% \\[ ignored\ntext\n" ^ equation ^ "\nend" in
  assert (Equation.at_line source 4 = equation);
  assert (Equation.at_line "\\[x\\]\n\\[y\\]" 2 = "\\[y\\]");
  assert (try ignore (Equation.at_line source 2); false with Project.Error _ -> true);
  assert (try ignore (Equation.at_line "\\[unclosed" 1); false with Project.Error _ -> true);
  let prefix = "\\documentclass{article}\n% \\begin{document} ignored\n\\newcommand{\\foo}{x}\n" in
  assert (Preview.preamble (prefix ^ "\\begin{document}body") = prefix);
  assert (Preview.preamble "\\% escaped percent\n\\begin{document}" = "\\% escaped percent\n");
  let raw = Preview.document (prefix ^ "\\begin{document}") "x^2" in
  assert (String.ends_with ~suffix:"\\[\nx^2\n\\]\n\\end{preview}\n\\end{document}\n" raw);
  let delimited = Preview.document (prefix ^ "\\begin{document}") "\\begin{align}x&=1\\end{align}" in
  assert (String.ends_with ~suffix:"\\begin{align}x&=1\\end{align}\n\\end{preview}\n\\end{document}\n" delimited);
  List.iter (fun (root, selection) ->
    assert (try ignore (Preview.document root selection); false with Project.Error _ -> true))
    [("\\begin{document}", "  "); ("missing document", "x")];
  print_endline "Preview: comments, preamble, raw/delimited math, and invalid input passed"

let () =
  let root = "\\documentclass{article}\n\\begin{document}" in
  assert (Preview.document root "x" = Preview.wrap root (Preview.manual_body "x"));
  let prose = Preview.wrap root (Live_selection.body (Live_selection.Text "Hi $x$.")) in
  assert (String.ends_with ~suffix:"\\begin{preview}\n\\begin{minipage}{\\linewidth}\nHi $x$.\n\\end{minipage}\n\\end{preview}\n\\end{document}\n" prose);
  print_endline "Preview: fragment bodies wrap into the document passed"
