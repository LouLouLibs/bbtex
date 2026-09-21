open Bbtex
let locate before after =
  Structure.locate ~text:(before ^ after) ~cursor:(Picker.characters before (String.length before)+1) ~ending:true
let name before after = (fst (locate before after)).Structure.name
let reject before after =
  try ignore (locate before after); assert false with Project.Error _ -> ()
let () =
  assert (name "\\begin{a}\\begin{a}x" "\\end{a}\\end{a}" = "a");
  assert (name "\\begin{outer}\n% \\begin{fake}\n\\begin{inner}x" "\\end{inner}\\end{outer}" = "inner");
  assert (name "\\begin{outer}\\verb|\\end{outer}|x" "\\end{outer}" = "outer");
  assert (name "\\begin{outer}\\begin{verbatim}\\end{fake}\\end{verbatim}x" "\\end{outer}" = "outer");
  assert (name "\\newcommand{\\foo}{\\begin{fake}}\\begin{real}x" "\\end{real}" = "real");
  assert (name "\\begin{a}\\%x" "\\end{a}" = "a");
  assert (name "\\be" "gin{a}x\\end{a}" = "a");
  assert (name "\\begin{a}x\\end{a" "}" = "a");
  reject "\\begin{a}\\begin{b}x" "\\end{a}\\end{b}";
  reject "\\begin{a}% x" "\n\\end{a}";
  reject "\\begin{a}\\begin{verbatim}x" "\\end{verbatim}\\end{a}";
  reject "\\begin{a}\\beg" "in{verbatim}x\\end{verbatim}\\end{a}";
  reject "\\newcommand{\\foo}{\\begin{a}x" "\\end{a}}";
  reject "\\begin{a}x" "";
  reject "\\begin{\\name}x" "\\end{\\name}";
  assert (Structure.close ~text:"\\begin{a}\\begin{b}" ~cursor:19 = "b");
  let prefix = "\\newcommand{\\fake}{\\begin{wrong}}\\begin{real}" in
  assert (Structure.close ~text:prefix ~cursor:(String.length prefix+1) = "real");
  List.iter (fun prefix -> try
    ignore (Structure.close ~text:prefix ~cursor:(String.length prefix+1)); assert false
    with Project.Error _ -> ()) [""; "\\begin{a}% comment"; "\\begin{verbatim}x";
      "\\begin{a}\\end{b}"; "\\begin{a}\\begin{"];
  let text = "É😀 \\begin{a}x\\end{a}" in
  let cursor = 15 in
  let plan = Structure.change ~text ~cursor "align*" in
  assert (String.starts_with ~prefix:"{5, 17," plan);
  assert (String.ends_with ~suffix:", 20}" plan);
  List.iter (fun name -> try ignore (Structure.change ~text ~cursor name); assert false
    with Project.Error _ -> ()) [""; "a}bad"; "a b"; "\\foo"];
  print_endline "Structural matching: nesting, comments, literals, definitions, malformed input and Unicode passed"
