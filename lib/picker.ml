let key_valid key = key <> "" && not (String.exists (fun c ->
  Project_index.space c || List.mem c ['\\'; '{'; '}'; ','; '%'; '#'; '$']) key)
let keys text = String.split_on_char ',' text |> List.map String.trim |> List.filter ((<>) "")
let unique values = List.fold_left (fun acc x -> if List.mem x acc then acc else acc @ [x]) [] values
let check_keys values = if values = [] || not (List.for_all key_valid values) then
  raise (Project.Error "Choose literal citation or reference keys without TeX markup.")
let characters text stop =
  let count = ref 0 in
  (* BBEdit's scripting ranges count UTF-16 code units, including two units
     for supplementary characters such as emoji. Source scanning uses UTF-8. *)
  for i = 0 to stop - 1 do
    let byte = Char.code text.[i] in
    if byte land 0xc0 <> 0x80 then count := !count + (if byte >= 0xf0 then 2 else 1)
  done; !count

type edit = { start : int; count : int; replacement : string }
let plan ~mode ~text ~prefix ~selected chosen =
  let values = unique (keys chosen) in check_keys values;
  if mode <> "cite" && mode <> "ref" then raise (Project.Error "Unknown picker mode.");
  if mode = "ref" && List.length values <> 1 then raise (Project.Error "Choose one reference.");
  let first = String.length prefix and last = String.length prefix + String.length selected in
  if not (String.starts_with ~prefix text) || last > String.length text ||
     String.sub text first (last - first) <> selected then raise (Project.Error "Selection changed. Run the picker again.");
  let probe = prefix ^ "X" ^ String.sub text first (String.length text - first) in
  if (Project_index.visible probe).[first] <> 'X' then
    raise (Project.Error "Place the cursor outside comments and verbatim text.");
  let visible = Project_index.visible text in
  let cite_commands = ["cite"; "citep"; "citet"; "citealp"; "citealt"; "citeauthor"; "citeyear";
    "citeyearpar"; "parencite"; "textcite"; "autocite"; "footcite"; "footfullcite"; "fullcite";
    "smartcite"; "supercite"; "nocite"] in
  let ref_commands = ["ref"; "eqref"; "pageref"; "autoref"; "nameref"; "vref"; "cref"; "Cref"] in
  let commands = if mode = "cite" then cite_commands else ref_commands in
  let found = ref None in
  let rec scan i = if i < String.length visible then
    if visible.[i] <> '\\' then scan (i + 1) else
    let name, next = Project_index.command visible i in
    let normalized = String.lowercase_ascii name in
    if i < first && first < next then raise (Project.Error "Place the cursor inside the command's key argument.");
    if List.mem normalized (cite_commands @ ref_commands) then begin
      let j = Project_index.star visible next in
      let j = Project_index.optional visible (Project_index.optional visible j) |> Project_index.skip visible in
      if j < String.length visible && visible.[j] = '{' then begin
        match Project_index.argument visible j with
        | Some (_, ending) when first >= j + 1 && last <= ending - 1 ->
          if not (List.mem normalized commands) then raise (Project.Error "Use the picker matching this citation/reference command.");
          found := Some (name, j + 1, ending - 1, false)
        | None when first >= j + 1 && last = String.length text ->
          if not (List.mem normalized commands) then raise (Project.Error "Use the picker matching this citation/reference command.");
          found := Some (name, j + 1, last, true)
        | _ -> ()
      end;
      scan next
    end else begin
      if Project_index.find normalized 0 "cite" < String.length normalized ||
         Project_index.find normalized 0 "ref" < String.length normalized then begin
        let rec arguments j =
          let j = Project_index.optional visible (Project_index.optional visible j) |> Project_index.skip visible in
          match Project_index.argument visible j with
          | Some (_, ending) ->
            if first > j && last < ending then
              raise (Project.Error "Use native completion for this custom or multi-argument citation/reference command.");
            arguments ending
          | None -> () in
        arguments (Project_index.star visible next)
      end;
      scan next
    end
  in scan 0;
  let start_byte, stop_byte, replacement = match !found with
    | Some (name, a, b, close) ->
      let original = String.sub text a (b - a) in
      let multi = mode = "cite" || List.mem name ["cref"; "Cref"] in
      let existing = if not multi then [] else begin
        if selected <> "" then begin
          let left = String.sub text a (first - a) |> String.trim in
          let right = String.sub text last (b - last) |> String.trim in
          if (left <> "" && not (String.ends_with ~suffix:"," left)) ||
             (right <> "" && not (String.starts_with ~prefix:"," right)) then
            raise (Project.Error "Select a whole key to replace it, or leave the cursor anywhere in the key list.")
        end;
        let remaining = if selected = "" then original else
          String.sub text a (first - a) ^ String.sub text last (b - last) in
        let existing = keys remaining in
        if existing <> [] then check_keys existing; existing
      end in
      a, b, String.concat "," (unique (existing @ values)) ^ (if close then "}" else "")
    | None ->
      if selected <> "" then raise (Project.Error "Place the cursor in a key argument or at an empty insertion point.");
      first, last, "\\" ^ (if mode = "cite" then "cite" else "ref") ^ "{" ^ String.concat "," values ^ "}"
  in
  {start = characters text start_byte + 1;
   count = characters text stop_byte - characters text start_byte; replacement}

let script edit = Printf.sprintf "return {%d, %d, %s}\n" edit.start edit.count (Outline.quote edit.replacement)

let verification ~binary files = String.concat "\n" (List.map (fun (file, fingerprint) ->
  "do shell script " ^ Outline.quote (String.concat " " (List.map Filename.quote
    [binary; "picker-check"; file; fingerprint]))) files)

let reference_picker ~binary source query =
  let index = Project_index.build source in
  let all_labels = List.filter (fun e -> e.Project_index.kind = "label") index.entries in
  let labels = Project_index.search index query |> List.filter (fun e -> e.Project_index.kind = "label") in
  if List.length labels > 300 then raise (Project.Error "More than 300 references. Narrow the search.");
  let warning = if index.issues = [] then "" else "display alert \"Partial project index\" message " ^
    Outline.quote (String.concat "\n" index.issues) ^ "\n" in
  let body = if labels = [] then "display alert \"Reference picker\" message \"No matching saved labels.\"\nreturn false" else
    let rows = List.mapi (fun i e -> Printf.sprintf "%d. %s" (i + 1) (Project_index.display index.root e)) labels in
    "set rows to {" ^ String.concat ", " (List.map Outline.quote rows) ^ "}\n" ^
    "set chosen to choose from list rows with title \"Insert Reference\" with prompt \"Choose a label by its source and context.\" OK button name \"Insert\"\n" ^
    "if chosen is false then return false\n" ^
    String.concat "\n" (List.mapi (fun i e ->
      let ambiguous = List.length (List.filter (fun x -> x.Project_index.title = e.Project_index.title) all_labels) > 1 in
      Printf.sprintf "if item 1 of chosen is item %d of rows then %s" (i + 1)
        (if ambiguous then "error \"This label is defined more than once. Rename the duplicates before inserting a reference.\""
         else if not (key_valid e.title) then "error \"This label is not a literal key. Use native completion for dynamic labels.\""
         else ("return {" ^ Outline.quote e.title ^ ", " ^
           Outline.quote (verification ~binary index.files) ^ "}"))) labels) in
  "tell application \"BBEdit\"\n" ^ warning ^ body ^ "\nend tell\n"
