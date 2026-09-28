(** Every % !TEX and % !BIB comment in a project's source-to-root chain, and
    whether bbtex acts on it. Documents from TeXShop or LaTeXTools carry
    comments bbtex does not read; saying so beats ignoring them silently. *)

open Types

type family = Tex | Bib

type comment = {
  file : string;
  line : int;
  family : family;
  key : string;    (** as written, e.g. "TS-program" *)
  value : string;  (** "" when the line has no "key = value" *)
}

type status =
  | Used
  | Ignored of { advice : string; affects_build : bool }
    (** [affects_build] is false for editor settings, which builds never mention. *)

let marker = function Tex -> "% !TEX" | Bib -> "% !BIB"

(* Same leniency as Directive_parser: any case, optional space after %. *)
let parse_line line =
  let line = String.trim line in
  if not (String.starts_with ~prefix:"%" line) then None else
  let line = String.trim (String.sub line 1 (String.length line - 1)) in
  let family = if String.length line < 4 then None else
    match String.lowercase_ascii (String.sub line 0 4) with
    | "!tex" -> Some Tex | "!bib" -> Some Bib | _ -> None in
  match family with
  | None -> None
  | Some family ->
    let rest = String.sub line 4 (String.length line - 4) in
    match String.index_opt rest '=' with
    | Some eq ->
      let key = String.trim (String.sub rest 0 eq) in
      if key = "" then None else
      Some (family, key, String.trim (String.sub rest (eq + 1) (String.length rest - eq - 1)))
    (* "% !TEX root ../main.tex": a directive with the "=" missing. *)
    | None when rest <> "" && (rest.[0] = ' ' || rest.[0] = '\t') ->
      Some (family, String.trim rest, "")
    | None -> None

(** Unreadable files yield no comments: this never blocks a build. *)
let scan_file file =
  match Directive_parser.read_lines file with
  | exception Sys_error _ -> []
  | lines -> List.concat (List.mapi (fun i text -> match parse_line text with
      | Some (family, key, value) -> [{ file; line = i + 1; family; key; value }]
      | None -> []) lines)

let unique items = List.fold_left (fun acc x -> if List.mem x acc then acc else acc @ [x]) [] items

(** Comments in [files] (a source-to-root chain), each file once. *)
let scan files = List.concat_map scan_file (unique files)

let is_read c = c.family = Tex &&
  List.mem (String.lowercase_ascii c.key) ["root"; "program"; "ts-program"]

(** [repeated] means an earlier comment in the same file set the same setting;
    bbtex reads only the first. *)
let classify ?(repeated=false) c =
  let ignored ?(affects_build=true) advice = Ignored { advice; affects_build } in
  match c.family, String.lowercase_ascii c.key with
  | _ when c.value = "" -> ignored ("not read; write it as " ^ marker c.family ^ " " ^ c.key ^ " = …")
  | Tex, ("root" | "program" | "ts-program") when repeated ->
    ignored "only the first one in a file is read; delete this one"
  | Tex, ("root" | "program" | "ts-program") -> Used
  | Tex, "encoding" -> ignored ~affects_build:false
      "BBEdit sets the file's encoding and TeX reads the file as saved"
  | Tex, "spellcheck" -> ignored ~affects_build:false "a TeXShop setting; BBEdit has its own spelling settings"
  | Tex, ("options" | "parameter") -> ignored ("put it in .bbtex as options = " ^ c.value)
  | Tex, "output_directory" -> ignored ("put it in .bbtex as output_directory = " ^ c.value)
  | Tex, "aux_directory" -> ignored "auxiliary files go in the output directory; set output_directory = in .bbtex"
  | Tex, "jobname" -> ignored "the PDF is named after the root file; rename the root file instead"
  | Bib, ("ts-program" | "program") -> ignored ~affects_build:false
      "latexmk runs BibTeX or Biber, whichever the document needs"
  | _ -> ignored "not a comment bbtex knows; it reads % !TEX root and % !TEX program"

(** Each comment with its status, in file and line order. *)
let statuses comments =
  let key c = c.file, (match String.lowercase_ascii c.key with "ts-program" -> "program" | k -> k) in
  List.mapi (fun i c ->
    let repeated = is_read c && c.value <> "" && List.exists (fun earlier ->
      is_read earlier && earlier.value <> "" && key earlier = key c)
      (List.filteri (fun j _ -> j < i) comments) in
    c, classify ~repeated c) comments

let text c = if c.value = "" then marker c.family ^ " " ^ c.key
  else Printf.sprintf "%s %s = %s" (marker c.family) c.key c.value

let relative ~dir file =
  let prefix = if String.ends_with ~suffix:"/" dir then dir else dir ^ "/" in
  if String.starts_with ~prefix file
  then String.sub file (String.length prefix) (String.length file - String.length prefix) else file

(** Doctor lines: (status, detail), one per comment. *)
let doctor_lines ~dir comments = List.map (fun (c, status) ->
  let where = Printf.sprintf "%s:%d %s" (relative ~dir c.file) c.line (text c) in
  match status with
  | Used -> "OK", where ^ " (used)"
  | Ignored { advice; affects_build } ->
    (if affects_build then "WARN" else "INFO"), Printf.sprintf "%s (ignored: %s)" where advice)
  (statuses comments)

let build_relevant comments = List.filter_map (function
  | c, Ignored { advice; affects_build = true } -> Some (c, advice)
  | _ -> None) (statuses comments)

(** One line for the build notification, or None when nothing is ignored. *)
let build_note comments =
  match build_relevant comments with
  | [] -> None
  | ignored ->
    let names = unique (List.map (fun (c, _) -> marker c.family ^ " " ^ c.key) ignored) in
    Some (Printf.sprintf "[bbtex] Ignored %s; see LaTeX — Doctor" (String.concat ", " names))

(** LaTeX Results entries pointing at each ignored comment that affects builds. *)
let results comments = List.map (fun (c, advice) ->
  { se_file = c.file; se_line = c.line; se_severity = Warning;
    se_message = Printf.sprintf "[bbtex] %s is ignored: %s" (text c) advice })
  (build_relevant comments)
