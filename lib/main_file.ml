(** Finding the main document of a file that names none, as Overleaf does: a
    [.tex] file next to it, or one folder up, that has \documentclass and
    includes it through literal \input, \include or \subfile (as the project
    index follows them). Only a single match counts; the same table can belong
    to several papers, so bbtex never picks between them. *)

let max_candidates = 64  (* .tex files read per folder *)
let max_inputs = 256     (* files read while following one candidate's inputs *)
let max_size = 4 * 1024 * 1024

let text file =
  match Unix.stat file with
  | { Unix.st_kind = Unix.S_REG; st_size; _ } when st_size <= max_size ->
    (try Some (Tex_lexer.visible (Preview_cache.read file)) with Sys_error _ -> None)
  | _ | exception Unix.Unix_error _ -> None

let has_documentclass text = Tex_lexer.find text 0 "\\documentclass" < String.length text

(** Whether [file] is a main document itself: \documentclass outside comments. *)
let is_document file = match text file with Some text -> has_documentclass text | None -> false

(* The existing files [file] inputs, resolved like the project index: against
   the main document's folder, then the including file's. *)
let inputs ~main file text =
  let n = String.length text in
  let rec scan i acc =
    if i >= n then List.rev acc
    else if text.[i] <> '\\' then scan (i + 1) acc
    else
      let name, next = Tex_lexer.command text i in
      if not (List.mem name ["input"; "include"; "subfile"]) then scan next acc else
      let value, stop = match Tex_lexer.argument text next with
        | Some found -> found
        | None ->
          let a = Tex_lexer.skip text next in
          let b = ref a in
          while !b < n && not (Tex_lexer.space text.[!b]) && text.[!b] <> '}' do incr b done;
          String.sub text a (!b - a), !b in
      let value = String.trim value in
      if value = "" || String.exists (fun c -> List.mem c ['\\'; '#'; '{'; '}'; '$']) value
      then scan stop acc else
      let value = if Filename.extension value = "" then value ^ ".tex" else value in
      let candidates = if Filename.is_relative value
        then [Filename.concat (Filename.dirname main) value; Filename.concat (Filename.dirname file) value]
        else [value] in
      match List.find_opt Sys.file_exists candidates with
      | Some path -> (try scan stop (Unix.realpath path :: acc) with Unix.Unix_error _ -> scan stop acc)
      | None -> scan stop acc
  in scan 0 []

(** Whether [main] includes [target], directly or through other inputs. *)
let includes ~main target =
  let seen = Hashtbl.create 32 in
  let rec visit = function
    | [] -> false
    | file :: rest when Hashtbl.mem seen file -> visit rest
    | _ when Hashtbl.length seen >= max_inputs -> false
    | file :: rest ->
      Hashtbl.add seen file ();
      let found = match text file with Some text -> inputs ~main file text | None -> [] in
      List.mem target found || visit (found @ rest)
  in visit [main]

(* Main documents in [source]'s folder and the one above, each once. *)
let candidates source =
  let dir = Filename.dirname source in
  let folders = if Filename.dirname dir = dir then [dir] else [dir; Filename.dirname dir] in
  List.concat_map (fun folder ->
    match Sys.readdir folder with
    | exception Sys_error _ -> []
    | names ->
      Array.sort compare names;
      Array.to_list names
      |> List.filter (fun name -> Filename.extension name = ".tex" && name.[0] <> '.')
      |> List.filteri (fun i _ -> i < max_candidates)
      |> List.filter_map (fun name ->
          try Some (Unix.realpath (Filename.concat folder name)) with Unix.Unix_error _ -> None))
    folders
  |> List.fold_left (fun acc f -> if List.mem f acc then acc else acc @ [f]) []
  |> List.filter (fun file -> file <> source && is_document file)

type result = Found of string | Several of string list | Unknown

(** [source] must be a canonical path. *)
let find source =
  match List.filter (fun main -> includes ~main source) (candidates source) with
  | [] -> Unknown
  | [main] -> Found main
  | several -> Several several

(** [file] as seen from [source]'s folder: "main.tex" or "../main.tex". *)
let display ~source file =
  let dir = Filename.dirname source in
  if Filename.dirname file = dir then Filename.basename file
  else if Filename.dirname file = Filename.dirname dir then "../" ^ Filename.basename file
  else file
