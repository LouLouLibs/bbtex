(** Conservative environment matching over one unsaved editor snapshot. *)
open Project_index

type tag = { name : string; first : int; last : int; name_first : int }
let fail message = raise (Project.Error message)
let valid_name name = name <> "" && name <> "*" && String.for_all (function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '*' | '@' | '-' -> true | _ -> false) name
let units text pos = Picker.characters text pos
let byte_offset text offset =
  let rec loop i count =
    if count = offset then i else if i >= String.length text || count > offset then
      fail "Invalid editor character offset." else
    let c = Char.code text.[i] in
    let width = if c < 128 then 1 else if c land 0xe0 = 0xc0 then 2
      else if c land 0xf0 = 0xe0 then 3 else 4 in
    loop (i + width) (count + if width = 4 then 2 else 1)
  in loop 0 0

let locate ~text ~cursor ~ending =
  if String.length text > 4 * 1024 * 1024 then fail "Document exceeds the 4 MiB editing limit.";
  let at = byte_offset text (cursor - 1) in
  let masked = visible text in
  if at < String.length text && not (space text.[at]) && masked.[at] <> text.[at] then
    fail "The cursor is in a comment or verbatim region.";
  let probe = String.sub text 0 at ^ "X" ^ String.sub text at (String.length text - at) in
  if (visible probe).[at] <> 'X' then fail "The cursor is in a comment or verbatim region.";
  let clean = visible (if ending then text else String.sub text 0 at) in
  let stack = ref [] and pairs = ref [] in
  let rec scan i = if i < String.length clean then
    if clean.[i] <> '\\' then scan (i + 1) else
    let command_name, next = command clean i in
    if List.mem command_name ["def"; "gdef"; "edef"; "xdef"; "newcommand";
      "renewcommand"; "providecommand"; "DeclareRobustCommand"; "newenvironment"; "renewenvironment"] then begin
      let start = if List.mem command_name ["def"; "gdef"; "edef"; "xdef"] then find clean next "{" else
        let j = star clean next |> skip clean in
        let j = match argument clean j with Some (_, stop) -> stop | None ->
          if j < String.length clean && clean.[j] = '\\' then snd (command clean j) else j in
        optional clean (optional clean j) in
      let stop = match argument clean start with Some (_, stop) -> stop
        | None -> fail "An incomplete macro definition prevents reliable environment matching." in
      let stop = if List.mem command_name ["newenvironment"; "renewenvironment"] then
        match argument clean stop with Some (_, stop) -> stop | None -> fail "Incomplete environment definition."
        else stop in
      if at >= i && at < stop then fail "Environment editing inside a macro definition is unsupported.";
      scan stop
    end else if command_name = "begin" || command_name = "end" then begin
      let name, stop = match argument clean next with Some result -> result
        | None -> fail "An incomplete environment tag prevents reliable matching." in
      if not (valid_name name) then fail "Dynamic or invalid environment names cannot be edited safely.";
      let tag = {name; first=i; last=stop; name_first=skip clean next + 1} in
      if command_name = "begin" then stack := tag :: !stack
      else (match !stack with
        | opening :: rest when opening.name = name ->
          stack := rest; pairs := (opening, tag) :: !pairs
        | _ -> fail ("Mismatched \\end{" ^ name ^ "}; repair the environment nesting first."));
      scan stop
    end else scan next
  in
  scan 0;
  if ending then
    match List.filter (fun (a,b) -> a.first <= at && at < b.last) !pairs
      |> List.sort (fun (a,_) (b,_) -> compare b.first a.first) with
    | (a,b) :: _ ->
      if List.exists (fun tag -> tag.first > a.first && tag.first <= at) !stack then
        fail "The innermost environment is incomplete.";
      a, Some b
    | [] -> fail "No complete environment contains the cursor."
  else match !stack with
    | a :: _ -> a, None
    | [] -> fail "No open environment before the cursor."

let close ~text ~cursor =
  (fst (locate ~text ~cursor ~ending:false)).name

let describe ~text ~cursor ~ending =
  if not ending then Printf.sprintf "{%s, 0, missing value, %d}" (Outline.quote (close ~text ~cursor)) cursor
  else let a,b = locate ~text ~cursor ~ending:true in
    let b = Option.get b in
    Printf.sprintf "{%s, %d, %d, %d}" (Outline.quote a.name)
      (units text a.first + 1) (units text b.last) cursor

let change ~text ~cursor name =
  if not (valid_name name) then fail "Use a literal environment name (letters, digits, *, @ or hyphen).";
  let a,b = locate ~text ~cursor ~ending:true in
  let b = Option.get b in
  let replace tag tail = String.sub text tag.first (tag.name_first-tag.first) ^ name ^
    String.sub text (tag.name_first + String.length tag.name) (tail-tag.name_first-String.length tag.name) in
  let replacement = replace a b.first ^ replace b b.last in
  let delta = String.length name - String.length a.name in
  let original_at = byte_offset text (cursor - 1) in
  let mapped = List.fold_left (fun pos tag ->
    let start = units text tag.name_first in
    if original_at >= tag.name_first + String.length tag.name then pos + delta
    else if original_at >= tag.name_first then pos + min (String.length name) (cursor - 1 - start) - (cursor - 1 - start)
    else pos) (cursor - 1) [a;b] in
  Printf.sprintf "{%d, %d, %s, %d}" (units text a.first + 1)
    (units text b.last - units text a.first) (Outline.quote replacement) (mapped + 1)
