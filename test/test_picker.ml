open Bbtex

let check mode before selected after chosen expected =
  let text = before ^ selected ^ after in
  let edit = Picker.plan ~mode ~text ~prefix:before ~selected chosen in
  (* ASCII fixture offsets map directly to bytes. *)
  let result = String.sub text 0 (edit.start - 1) ^ edit.replacement ^
    String.sub text (edit.start - 1 + edit.count) (String.length text - edit.start + 1 - edit.count) in
  if result <> expected then failwith (result ^ " <> " ^ expected)
let rejected mode before selected after =
  try ignore (Picker.plan ~mode ~text:(before ^ selected ^ after) ~prefix:before ~selected "new");
    assert false with Project.Error _ -> ()
let () =
  check "cite" "See " "" "." "a,b" "See \\cite{a,b}.";
  check "cite" "\\citet*[see][p. 4]{" "" "old}" "new,old,third" "\\citet*[see][p. 4]{old,new,third}";
  check "cite" "\\parencite{old," "par" "}" "new" "\\parencite{old,new}";
  check "cite" "\\cite{old" "" "}" "new" "\\cite{old,new}";
  check "cite" "\\cite{" "" "" "new" "\\cite{new}";
  check "ref" "Equation \\eqref{" "old" "}." "eq:new" "Equation \\eqref{eq:new}.";
  check "ref" "\\autoref{ol" "" "d}" "sec:new" "\\autoref{sec:new}";
  check "ref" "\\cref{old" "" "}" "new" "\\cref{old,new}";
  check "ref" "See " "" "." "fig:new" "See \\ref{fig:new}.";
  rejected "cite" "\\cite{old,par" "t" "ial}";
  rejected "cite" "Text " "selected prose" ".";
  rejected "cite" "% comment " "" "";
  rejected "cite" "\\begin{verbatim}\n " "" "\n\\end{verbatim}";
  rejected "cite" "\\ci" "" "te{}";
  rejected "ref" "\\cite{" "" "old}";
  rejected "cite" "\\cites{old}{" "" "second}";
  check "cite" "\\Citep{" "" "old}" "new" "\\Citep{old,new}";
  let edit = Picker.plan ~mode:"cite" ~text:"É😀 " ~prefix:"É😀 " ~selected:"" "new" in
  assert (edit.start = 5 && edit.count = 0);
  print_endline "Pickers: command/options preservation, key merging/replacement, contexts and Unicode offsets passed"
