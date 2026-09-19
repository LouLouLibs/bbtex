(** Locate a complete display-math block at a saved source line. *)
let at_line text requested =
  let n = String.length text in
  let pairs = ["\\[", "\\]"] @ List.map (fun name ->
    "\\begin{" ^ name ^ "}", "\\end{" ^ name ^ "}")
    ["equation"; "equation*"; "align"; "align*"; "gather"; "gather*";
     "multline"; "multline*"; "displaymath"; "flalign"; "flalign*"] in
  let matches i token = i + String.length token <= n &&
    String.sub text i (String.length token) = token in
  let rec scan i line comment active =
    if i >= n then raise (Project.Error "No complete display equation at the cursor. Use equation/align environments or \\[...\\].")
    else if text.[i] = '\n' then scan (i+1) (line+1) false active
    else if comment then scan (i+1) line true active
    else if text.[i] = '%' then scan (i+1) line true active
    else match active with
    | Some (start, first_line, ending) when matches i ending ->
      let finish = i + String.length ending in
      if first_line <= requested && requested <= line then String.sub text start (finish-start)
      else scan finish line false None
    | _ ->
      match active, List.find_opt (fun (opening, _) -> matches i opening) pairs with
      | None, Some (opening, ending) -> scan (i + String.length opening) line false (Some (i, line, ending))
      | _ -> scan (i + if text.[i] = '\\' && i+1 < n then 2 else 1) line false active
  in scan 0 1 false None
