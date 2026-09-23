(** Citation metadata from saved project bibliographies; never rewrites them.
    Blocks come from the vendored bibtexparser-ml, a port of python-bibtexparser's
    splitter. This module resolves the value layer it leaves raw: @string
    macros, [#] concatenation, and crossref/xdata inheritance for search. *)

type entry = { key : string; entry_type : string; file : string; line : int;
               fields : (string * string) list; author : string; title : string;
               year : string; ambiguous : bool }
type t = { entries : entry list; issues : string list; proofs : (string * string) list }

exception Invalid of string

(* ASCII and Latin-1 case folding, enough for names such as "García" or "ZOË". *)
let fold text =
  let b = Bytes.of_string (String.lowercase_ascii text) in
  for i = 0 to Bytes.length b - 2 do
    let c = Bytes.get b (i + 1) in
    if Bytes.get b i = '\xc3' && c >= '\x80' && c <= '\x9e' && c <> '\x97' then
      Bytes.set b (i + 1) (Char.chr (Char.code c + 0x20))
  done;
  Bytes.to_string b

let space = function ' ' | '\t' | '\n' | '\r' | '\011' | '\012' -> true | _ -> false

(* Resolves a raw value such as [{a} # name # "b"] against @string macros. *)
let rec resolve ?(seen = []) ~cache strings value =
  let n = String.length value and pieces = Buffer.create (String.length value) in
  let rec skip i = if i < n && space value.[i] then skip (i + 1) else i in
  let rec piece position =
    let position = skip position in
    if position < n then begin
      let opening = value.[position] in
      let position =
        if opening = '{' || opening = '"' then begin
          let start = position + 1 in
          let rec close i depth =
            if i >= n then raise (Invalid "Unclosed metadata value")
            else match value.[i] with
              | '\\' -> close (i + 2) depth
              | '{' -> close (i + 1) (depth + 1)
              | '}' when opening = '{' && depth = 1 -> i
              | '}' -> close (i + 1) (depth - 1)
              | '"' when opening = '"' && depth = 0 -> i
              | _ -> close (i + 1) depth in
          let stop = close start (if opening = '{' then 1 else 0) in
          Buffer.add_string pieces (String.sub value start (stop - start));
          stop + 1
        end else begin
          let rec token i = if i < n && not (space value.[i]) && value.[i] <> '#' then token (i + 1) else i in
          let stop = token position in
          if stop = position then raise (Invalid "Invalid string concatenation");
          let token = String.sub value position (stop - position) in
          let name = fold token in
          (match Hashtbl.find_opt strings name with
           | Some definition ->
             if List.mem name seen || List.length seen >= 32 then
               raise (Invalid ("Cyclic bibliography string: " ^ token));
             let expanded = match Hashtbl.find_opt cache name with
               | Some expanded -> expanded
               | None ->
                 let expanded = resolve ~seen:(name :: seen) ~cache strings definition in
                 Hashtbl.replace cache name expanded; expanded in
             Buffer.add_string pieces expanded
           | None -> Buffer.add_string pieces token);
          stop
        end in
      if Buffer.length pieces > 1024 * 1024 then raise (Invalid "Expanded metadata exceeds 1 MiB");
      let position = skip position in
      if position < n then begin
        if value.[position] <> '#' then raise (Invalid "Unexpected metadata expression");
        if skip (position + 1) >= n then raise (Invalid "Missing value after string concatenation");
        piece (position + 1)
      end
    end in
  piece 0;
  Buffer.contents pieces

let dedupe items = List.rev (List.fold_left (fun acc x -> if List.mem x acc then acc else x :: acc) [] items)

let bibliography (index : Project_index.t) =
  let issues = ref (List.rev index.issues) and proofs = ref (List.rev index.files) in
  let issue message = issues := message :: !issues in
  let strings = Hashtbl.create 64 and raw_entries = ref [] in
  List.iter (fun file ->
    match
      if (Unix.stat file).st_size > 32 * 1024 * 1024 then Error "Bibliography exceeds 32 MiB" else
      let raw = Project_index.read file in
      proofs := (file, Project_index.hash raw) :: !proofs;
      let bom = "\xef\xbb\xbf" in
      let text = if String.starts_with ~prefix:bom raw then String.sub raw 3 (String.length raw - 3) else raw in
      if String.is_valid_utf_8 text then Ok (Bibtexparser.parse_string text) else Error "not valid UTF-8"
    with
    | exception (Sys_error message) -> issue (file ^ ": " ^ message)
    | exception Unix.Unix_error (error, _, _) -> issue (file ^ ": " ^ Unix.error_message error)
    | Error message -> issue (file ^ ": " ^ message)
    | Ok blocks -> List.iter (function
        | Bibtexparser.String { key; value; _ } -> Hashtbl.replace strings (fold key) value
        | Entry { line; entry_type; key; fields } ->
          (* Later fields win when names differ only in case, as in a Python dict. *)
          let fields = List.fold_left (fun acc (f : Bibtexparser.field) ->
            let name = fold f.name in (name, f.value) :: List.remove_assoc name acc) [] fields in
          raw_entries := (key, entry_type, file, line + 1, List.rev fields) :: !raw_entries
        | Duplicate_key { line; key; ignored = Entry { entry_type; _ } } ->
          raw_entries := (key, entry_type, file, line + 1, []) :: !raw_entries;
          issue (Printf.sprintf "%s:%d: duplicate key %s" file (line + 1) key)
        | Duplicate_key { line; _ } | Duplicate_field { line; _ } | Failed { line; _ } ->
          issue (Printf.sprintf "%s:%d: malformed entry skipped" file (line + 1))
        | Preamble _ | Comment _ -> ()) blocks) index.bibliographies;
  let cache = Hashtbl.create 64 in
  let raw_entries = List.rev !raw_entries |> List.map (fun (key, entry_type, file, line, fields) ->
    let fields = List.map (fun (name, value) ->
      try name, resolve ~cache strings value
      with Invalid message -> issue (key ^ ": " ^ message); name, value) fields in
    (key, entry_type, file, line, fields)) in
  let grouped = Hashtbl.create 256 in
  List.iter (fun ((key, _, _, _, _) as e) -> Hashtbl.add grouped key e) raw_entries;
  let rec inherited seen (key, _, _, _, own) =
    if List.mem key seen || List.length seen >= 32 then (issue ("Cyclic inherited metadata: " ^ key); [])
    else begin
      let field name = Option.value ~default:"" (List.assoc_opt name own) in
      let parents = String.split_on_char ',' (field "xdata") |> List.map String.trim
                    |> List.filter ((<>) "") in
      let parents = if field "crossref" <> "" then parents @ [field "crossref"] else parents in
      let merge acc fields = List.fold_left (fun acc (name, value) ->
        (name, value) :: List.remove_assoc name acc) acc fields in
      let from_parents = List.fold_left (fun acc parent ->
        match Hashtbl.find_all grouped parent with
        | [single] -> merge acc (inherited (key :: seen) single)
        | _ -> issue (Printf.sprintf "%s: missing or ambiguous inherited entry %s" key parent); acc)
        [] parents in
      merge from_parents own
    end in
  let entries = List.map (fun ((key, entry_type, file, line, own) as e) ->
    let fields = inherited [] e in
    let first names = match List.find_map (fun name -> List.assoc_opt name fields) names with
      | Some value -> value | None -> "" in
    let ambiguous = List.length (Hashtbl.find_all grouped key) <> 1 in
    if ambiguous then issue ("Duplicate citation key: " ^ key);
    { key; entry_type; file; line; fields = own; author = first ["author"; "editor"];
      title = first ["title"; "booktitle"]; year = first ["year"; "date"]; ambiguous }) raw_entries in
  { entries; issues = dedupe (List.rev !issues); proofs = List.rev !proofs }

let words text =
  String.split_on_char ' ' (String.map (fun c -> if space c then ' ' else c) text)
  |> List.filter ((<>) "")

let contains haystack needle =
  let n = String.length needle and h = String.length haystack in
  let rec at i = i + n <= h && (String.sub haystack i n = needle || at (i + 1)) in
  at 0

let search data query =
  let tokens = words (fold query) in
  List.filter (fun e ->
    fold e.entry_type <> "xdata" &&
    let haystack = fold (String.concat " " [e.key; e.author; e.title; e.year; e.file]) in
    List.for_all (contains haystack) tokens) data.entries

(* Collapses whitespace and keeps at most 160 characters, never splitting one. *)
let short text =
  let text = String.concat " " (words text) in
  let rec cut i count =
    if i >= String.length text || count = 160 then String.sub text 0 (min i (String.length text))
    else cut (i + Uchar.utf_decode_length (String.get_utf_8_uchar text i)) (count + 1) in
  cut 0 0

let picker ~binary data query =
  let entries = search data query in
  if List.length entries > 300 then raise (Project.Error "More than 300 citations match. Narrow the search.");
  let quote = Outline.quote in
  let warning = if data.issues = [] then [] else
    let rec take k = function x :: rest when k > 0 -> x :: take (k - 1) rest | _ -> [] in
    ["display alert \"Partial bibliography index\" message " ^ quote (String.concat "\n" (take 20 data.issues))] in
  let body = if entries = [] then
      ["display alert \"Insert Citation\" message \"No matching saved bibliography entries.\""; "return false"]
    else
      let rows = List.mapi (fun i e -> Printf.sprintf "%d. %s — %s (%s) · %s — %s:%d" (i + 1) e.key
        (short e.author) e.year (short e.title) (Filename.basename e.file) e.line) entries in
      ["set rows to {" ^ String.concat ", " (List.map quote rows) ^ "}";
       "set chosen to choose from list rows with title \"Insert Citation\" with prompt \
        \"Select one or more citations. Shift/Command selects multiple rows.\" \
        OK button name \"Insert\" with multiple selections allowed";
       "if chosen is false then return false"; "set chosenKeys to \"\""] @
      List.concat (List.mapi (fun i e ->
        [Printf.sprintf "if chosen contains item %d of rows then" (i + 1)] @
        (if e.ambiguous || not (Picker.key_valid e.key) then
           ["error \"This citation key is duplicated or cannot be inserted literally. Fix its definition first.\""]
         else ["if chosenKeys is not \"\" then set chosenKeys to chosenKeys & \",\"";
               "set chosenKeys to chosenKeys & " ^ quote e.key]) @ ["end if"]) entries) @
      ["return {chosenKeys, " ^ quote (Picker.verification ~binary data.proofs) ^ "}"] in
  String.concat "\n" (["tell application \"BBEdit\""] @ warning @ body @ ["end tell"]) ^ "\n"

let json data query =
  let q = Snippet_page.json in
  let entry e = Printf.sprintf
      {|{"key":%s,"type":%s,"file":%s,"line":%d,"author":%s,"title":%s,"year":%s,"ambiguous":%b,"fields":{%s}}|}
      (q e.key) (q e.entry_type) (q e.file) e.line (q e.author) (q e.title) (q e.year) e.ambiguous
      (String.concat "," (List.map (fun (name, value) -> q name ^ ":" ^ q value) e.fields)) in
  Printf.sprintf {|{"entries":[%s],"issues":[%s]}|}
    (String.concat "," (List.map entry (search data query))) (String.concat "," (List.map q data.issues))
