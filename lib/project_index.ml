(** A saved-source outline, not a TeX interpreter. Locations are hard lines. *)
type entry = { kind : string; title : string; file : string; line : int;
               depth : int; context : string; fingerprint : string }
type t = { root : string; entries : entry list; issues : string list }

let read = Preview_cache.read
let hash text = Digest.to_hex (Digest.string text)
let starts text pos value = pos + String.length value <= String.length text &&
  String.sub text pos (String.length value) = value
let space = function ' ' | '\t' | '\r' | '\n' -> true | _ -> false
let rec skip text i = if i < String.length text && space text.[i] then skip text (i + 1) else i
let letter = function 'a'..'z' | 'A'..'Z' | '@' -> true | _ -> false
let command text i =
  let j = ref (i + 1) in
  if !j < String.length text && letter text.[!j] then
    while !j < String.length text && letter text.[!j] do incr j done
  else if !j < String.length text then incr j;
  String.sub text (i + 1) (!j - i - 1), !j

let group text pos opening closing =
  let i = skip text pos in
  if i >= String.length text || text.[i] <> opening then None else
  let rec scan j depth =
    if j >= String.length text then None
    else if text.[j] = '\\' then scan (min (String.length text) (j + 2)) depth
    else if text.[j] = closing && depth = 1 then
      Some (String.sub text (i + 1) (j - i - 1), j + 1)
    else scan (j + 1) (depth + (if text.[j] = opening then 1 else if text.[j] = closing then -1 else 0))
  in scan (i + 1) 1
let argument text pos = group text pos '{' '}'
let optional text pos = match group text pos '[' ']' with None -> pos | Some (_, j) -> j
let star text pos = if pos < String.length text && text.[pos] = '*' then pos + 1 else pos
let find text start value =
  let rec loop i = if i + String.length value > String.length text then String.length text
    else if starts text i value then i else loop (i + 1) in loop start

(* Preserve byte positions and newlines while excluding comments and literal text. *)
let visible text =
  let result = Bytes.of_string text in
  let blank a b = for i = a to b - 1 do
    if text.[i] <> '\n' && text.[i] <> '\r' then Bytes.set result i ' ' done in
  let rec scan i = if i < String.length text then
    if text.[i] = '%' then begin
      let j = ref i in
      while !j < String.length text && text.[!j] <> '\n' && text.[!j] <> '\r' do incr j done;
      blank i !j; scan !j
    end else if text.[i] = '\\' then begin
      let name, next = command text i in
      if List.mem name ["verb"; "lstinline"] then begin
        let d = optional text (star text next) |> skip text in
        let stop = if d >= String.length text || space text.[d] then d else
          min (String.length text) (find text (d + 1) (String.make 1 text.[d]) + 1) in
        blank i stop; scan stop
      end else if name = "begin" then match argument text next with
        | Some (env, j) when List.mem env ["verbatim"; "verbatim*"; "Verbatim"; "BVerbatim";
            "lstlisting"; "minted"; "comment"] ->
          let ending = "\\end{" ^ env ^ "}" in
          let stop = min (String.length text) (find text j ending + String.length ending) in
          blank i stop; scan stop
        | _ -> scan next
      else scan next
    end else scan (i + 1)
  in scan 0; Bytes.to_string result

let words text = String.split_on_char ' ' (String.map (fun c -> if space c then ' ' else c) text)
  |> List.filter (fun s -> s <> "")
let compact text =
  let rec take n = function [] -> [] | _ when n = 0 -> ["…"] | x :: xs -> x :: take (n - 1) xs in
  String.concat " " (take 20 (words text))
let line_at text pos =
  let line = ref 1 in
  for i = 0 to pos - 1 do if text.[i] = '\n' || (text.[i] = '\r' &&
    (i + 1 >= String.length text || text.[i + 1] <> '\n')) then incr line done; !line
let section_level = function
  | "part" -> Some 0 | "chapter" -> Some 1 | "section" -> Some 2
  | "subsection" -> Some 3 | "subsubsection" -> Some 4
  | "paragraph" -> Some 5 | "subparagraph" -> Some 6 | _ -> None
let environment_kind env =
  let env = if String.ends_with ~suffix:"*" env then String.sub env 0 (String.length env - 1) else env in
  if List.mem env ["equation"; "align"; "gather"; "multline"; "flalign"; "displaymath"; "eqnarray"]
  then Some "equation" else if List.mem env ["figure"; "table"] then Some env else None

let build source =
  let root = (Compiler.resolve_compilation source).root_file in
  let entries = ref [] and issues = ref [] and visited = Hashtbl.create 32 in
  let sections = ref [] in
  let issue file line message = issues := Printf.sprintf "%s:%d: %s" file line message :: !issues in
  let rec visit stack file =
    if List.mem file stack then issue file 1 "Input cycle; not followed again."
    else if Hashtbl.mem visited file then ()
    else if Hashtbl.length visited >= 256 || List.length stack >= 64 then
      issue file 1 "Project traversal limit reached."
    else begin
      Hashtbl.add visited file ();
      try
        if (Unix.stat file).Unix.st_size > 4 * 1024 * 1024 then
          raise (Project.Error "File exceeds the 4 MiB outline limit.");
        let raw = read file in
        let fingerprint = hash raw and text = visible raw in
        let n = String.length text in
        let context () = String.concat " › " (List.map snd !sections) in
        let add kind title pos extra =
          entries := {kind; title = compact title; file; line = line_at text pos;
            depth = List.length !sections; context = String.concat " · "
              (List.filter ((<>) "") [context (); extra]); fingerprint} :: !entries in
        let environments = ref [] in
        let rec scan i = if i < n then
          if text.[i] <> '\\' then scan (i + 1) else
          let name, next = command text i in
          let arg = argument text (optional text (star text next)) in
          match section_level name, name, arg with
          | Some level, _, Some (title, stop) ->
            sections := List.filter (fun (l, _) -> l < level) !sections;
            add name title i "";
            sections := !sections @ [level, compact title]; scan stop
          | _, ("input" | "include" | "subfile"), _ ->
            let value, stop = match arg with Some a -> a | None ->
              let a = skip text next in
              let b = ref a in
              while !b < n && not (space text.[!b]) && text.[!b] <> '}' do incr b done;
              String.sub text a (!b - a), !b in
            let value = String.trim value in
            if value = "" || String.exists (fun c -> List.mem c ['\\'; '#'; '{'; '}'; '$']) value then
              issue file (line_at text i) ("Dynamic \\" ^ name ^ " input is unavailable: " ^ value)
            else begin
              let value = if Filename.extension value = "" then value ^ ".tex" else value in
              let candidates = if Filename.is_relative value then
                [Filename.concat (Filename.dirname root) value; Filename.concat (Filename.dirname file) value]
                else [value] in
              match List.find_opt Sys.file_exists candidates with
              | None -> issue file (line_at text i) ("Missing input: " ^ value)
              | Some path -> visit (file :: stack) (Unix.realpath path)
            end; scan stop
          | _, "begin", Some (env, stop) ->
            (match environment_kind env with
             | None -> ()
             | Some kind ->
               let ending = find text stop ("\\end{" ^ env ^ "}") in
               let body = String.sub text stop (ending - stop) in
               let caption_at = find body 0 "\\caption" in
               let title = if caption_at = String.length body then compact body else
                 let _, j = command body caption_at in
                 match argument body (optional body (star body j)) with
                 | Some (caption, _) -> caption | None -> compact body in
               add kind (if title = "" then env else title) i "";
               environments := (env, compact title) :: !environments);
            scan stop
          | _, "end", Some (env, stop) ->
            environments := List.filter (fun (e, _) -> e <> env) !environments;
            if env <> "document" then scan stop
          | _, "[", _ ->
            let stop = find text next "\\]" in
            add "equation" (String.sub text next (stop - next)) i ""; scan next
          | _, "label", Some (label, stop) ->
            add "label" label i (match !environments with (_, title) :: _ -> title | [] -> ""); scan stop
          | _, ("newcommand" | "renewcommand" | "providecommand" | "DeclareRobustCommand"), _ ->
            let after_name = match argument text (star text next) with
              | Some (_, j) -> j | None -> let j = skip text (star text next) in
                if j < n && text.[j] = '\\' then snd (command text j) else j in
            let j = optional text (optional text after_name) in
            scan (match argument text j with Some (_, stop) -> stop | None -> next)
          | _, ("newenvironment" | "renewenvironment"), Some (_, stop) ->
            let j = optional text (optional text stop) in
            let j = match argument text j with Some (_, stop) -> stop | None -> j in
            scan (match argument text j with Some (_, stop) -> stop | None -> j)
          | _, ("def" | "gdef" | "edef" | "xdef"), _ ->
            let j = find text next "{" in
            scan (match argument text j with Some (_, stop) -> stop | None -> next)
          | _, ("includeonly" | "import" | "subimport" | "inputminted"), _ ->
            issue file (line_at text i) ("\\" ^ name ^ " is not expanded by the outline.");
            scan (match arg with Some (_, stop) -> stop | None -> next)
          | _ -> scan next
        in scan 0
      with Sys_error message | Project.Error message -> issue file 1 message
         | Unix.Unix_error (error, _, _) -> issue file 1 (Unix.error_message error)
    end
  in visit [] root; {root; entries = List.rev !entries; issues = List.rev !issues}

let relative root file =
  let prefix = Filename.dirname root ^ "/" in
  if String.starts_with ~prefix file then String.sub file (String.length prefix) (String.length file - String.length prefix)
  else file
let display root e = Printf.sprintf "%s%s: %s — %s:%d%s"
  (String.make (2 * e.depth) ' ') e.kind e.title (relative root e.file) e.line
  (if e.context = "" then "" else " · " ^ e.context)
let search index query =
  let tokens = words (String.lowercase_ascii query) in
  List.filter (fun e -> let text = String.lowercase_ascii (display index.root e) in
    List.for_all (fun token ->
      if String.starts_with ~prefix:"kind:" token then token = "kind:" ^ e.kind
      else find text 0 token < String.length text) tokens) index.entries
let json index entries =
  let q = Snippet_page.json in
  Printf.sprintf {|{"version":1,"root":%s,"savedOnly":true,"issues":[%s],"entries":[%s]}|}
    (q index.root) (String.concat "," (List.map q index.issues))
    (String.concat "," (List.map (fun e -> Printf.sprintf
      {|{"kind":%s,"title":%s,"file":%s,"line":%d,"depth":%d,"context":%s,"fingerprint":%s}|}
      (q e.kind) (q e.title) (q e.file) e.line e.depth (q e.context) (q e.fingerprint)) entries))
