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

let wrapped text cursor length name expected =
  let edit = Structure.wrap ~text ~cursor ~length name in
  let first = Structure.byte_offset text (edit.start-1) in
  let last = Structure.byte_offset text (edit.start-1+edit.count) in
  let actual = String.sub text 0 first ^ edit.replacement ^ String.sub text last (String.length text-last) in
  if actual <> expected then failwith (Printf.sprintf "Wrap %S <> %S" actual expected);
  edit
let () =
  ignore (wrapped "  one\n    two\nnext" 3 11 "quote" "  \\begin{quote}\n  one\n    two\n  \\end{quote}\nnext");
  ignore (wrapped "  one\n    two\nnext" 1 14 "quote" "  \\begin{quote}\n  one\n    two\n  \\end{quote}\nnext");
  let edit = wrapped "  " 3 0 "equation*" "  \\begin{equation*}\n  \t\n  \\end{equation*}" in
  assert (edit.selection_count = 0 && edit.selection_start = 24);
  ignore (wrapped "a\r\nb\r\n" 1 6 "quote" "\\begin{quote}\r\na\r\nb\r\n\\end{quote}\r\n");
  ignore (wrapped "\tÉ😀\n" 1 5 "quote" "\t\\begin{quote}\n\tÉ😀\n\t\\end{quote}\n");
  ignore (wrapped "\\begin{a}\nx\n\\end{a}" 11 1 "b" "\\begin{a}\n\\begin{b}\nx\n\\end{b}\n\\end{a}");
  List.iter (fun (text,cursor,length) ->
    try ignore (Structure.wrap ~text ~cursor ~length "quote"); assert false with Project.Error _ -> ())
    ["some text", 3, 3; "some text", 1, 4; "\\begin{a}\nx\n\\end{a}", 1, 12;
     "\\begin{verbatim}\nx\n\\end{verbatim}", 18, 1;
     "\\newcommand{\\foo}{\nx\n}", 20, 1; "a\r\n", 1, 2];
  print_endline "Wrapping: indentation, body selection, blank insertion, CRLF, Unicode and unsafe boundaries passed"
