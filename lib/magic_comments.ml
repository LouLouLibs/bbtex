(** Every % !TEX and % !BIB comment in a project's source-to-root chain, and
    what bbtex does with it. [root] and [program] are read as they are;
    [options], [parameter], [output_directory] and % !BIB [TS-program] are
    mapped onto bbtex's own settings; the rest is reported as ignored rather
    than dropped silently. *)

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
  | Mapped of { becomes : string; warning : string option }
    (** [warning]: the part bbtex could not apply, e.g. shell escape. *)
  | Ignored of { advice : string; affects_build : bool }
    (** [affects_build] is false for editor settings, which builds never mention. *)

(** What the project decides, against which comments are judged. *)
type context = {
  project_options : string list;  (** from .bbtex, including the profile *)
  project_output : string option; (** .bbtex output_directory, absolute *)
  root_dir : string;
  latexmk : bool;                 (** Tectonic and RaTeX builds don't run latexmk *)
  bib_ran : [ `Bibtex | `Biber ] option;  (** per the last build's .blg *)
}

let no_context = { project_options = []; project_output = None; root_dir = "/";
                   latexmk = true; bib_ran = None }

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

let text c = if c.value = "" then marker c.family ^ " " ^ c.key
  else Printf.sprintf "%s %s = %s" (marker c.family) c.key c.value

let where c = Printf.sprintf "%s:%d" c.file c.line

let relative ~dir file =
  let prefix = if String.ends_with ~suffix:"/" dir then dir else dir ^ "/" in
  if String.starts_with ~prefix file
  then String.sub file (String.length prefix) (String.length file - String.length prefix) else file

(* The setting a comment names, merging aliases. *)
let setting c = match c.family, String.lowercase_ascii c.key with
  | Tex, "ts-program" -> Tex, "program"
  | Tex, "parameter" -> Tex, "options"
  | Bib, "ts-program" -> Bib, "program"
  | family, key -> family, key

(* root and program are read per file, as TeXShop does; the settings bbtex maps
   come from the first comment along the source-to-root chain, like program's
   engine choice. *)
let per_file c = List.mem (setting c) [Tex, "root"; Tex, "program"]
let mapped c = List.mem (setting c) [Tex, "options"; Tex, "output_directory"; Bib, "program"]

let first name comments = List.find_opt (fun c -> c.value <> "" && setting c = name) comments

let is_shell_escape arg =
  let arg = String.lowercase_ascii arg in
  let has sub = Log_parser.contains_substring ~sub arg in
  (has "shell-escape" || has "write18") &&
  not (List.exists (fun prefix -> String.starts_with ~prefix arg) ["-no-"; "--no-"; "-disable"; "--disable"])

let bibtex_programs = ["bibtex8"; "upbibtex"; "pbibtex"]

(** The document's build settings, from the first comment for each. Options
    are validated like .bbtex options; shell escape is never taken from a
    comment. Raises [Project.Error] naming the comment for malformed options. *)
type document = { options : string list; output_directory : string option; bibtex : string option }

let document comments =
  let options = match first (Tex, "options") comments with
    | None -> []
    | Some c ->
      (try Project.options c.value with Project.Error message ->
         raise (Project.Error (Printf.sprintf "%s: %s: %s" (where c) (text c) message)))
      |> List.filter (fun arg -> not (is_shell_escape arg)) in
  let output_directory = match first (Tex, "output_directory") comments with
    | Some c when not (String.starts_with ~prefix:"<<" c.value) -> Some c.value
    | _ -> None in
  let bibtex = match first (Bib, "program") comments with
    | Some c when List.mem (String.lowercase_ascii c.value) bibtex_programs ->
      Some (String.lowercase_ascii c.value)
    | _ -> None in
  { options; output_directory; bibtex }

let ignored ?(affects_build=true) advice = Ignored { advice; affects_build }
let mapped_to ?warning becomes = Mapped { becomes; warning }

let options_status ~context c =
  match Project.options c.value with
  | exception Project.Error message -> ignored message
  | args ->
    let escapes = List.filter is_shell_escape args in
    let rest = List.filter (fun a -> not (is_shell_escape a)) args in
    let becomes = if rest = [] then "no options" else "options " ^ String.concat " " rest in
    if escapes = [] || List.exists is_shell_escape context.project_options then mapped_to becomes
    else mapped_to becomes ~warning:(Printf.sprintf "can't turn on shell escape: a comment \
      in a downloaded file could run programs. If you trust this document, add \
      options = %s to .bbtex" (String.concat " " escapes))

let output_status ~context c =
  if String.starts_with ~prefix:"<<" c.value then
    ignored "LaTeXTools' special folders aren't supported; name a folder instead"
  else
    let dir = Source_reader.resolve_path ~root_dir:context.root_dir c.value in
    match context.project_output with
    | None -> mapped_to ("output directory " ^ c.value)
    | Some project when project = dir -> mapped_to ("output directory " ^ c.value ^ ", as in .bbtex")
    | Some project -> ignored ("output_directory in .bbtex wins (" ^ relative ~dir:context.root_dir project ^ ")")

let bib_status ~context c =
  let value = String.lowercase_ascii c.value in
  let ran_other = match value, context.bib_ran with
    | "biber", Some `Bibtex -> Some "BibTeX" | ("bibtex" | "bibtex8" | "upbibtex" | "pbibtex"), Some `Biber -> Some "Biber"
    | _ -> None in
  let warning = Option.map (fun ran -> Printf.sprintf "says %s, but the last build ran %s: latexmk \
    follows the document, where biblatex's backend= option decides" c.value ran) ran_other in
  match value with
  | "bibtex" | "biber" -> mapped_to ?warning ("latexmk runs " ^ c.value ^ " when the document needs it")
  | _ when List.mem value bibtex_programs ->
    if context.latexmk then mapped_to ?warning ("latexmk's BibTeX program, " ^ value)
    else ignored "only latexmk builds run a different BibTeX program"
  | _ -> ignored ("not a bibliography program bbtex knows: use bibtex, biber, " ^
                  String.concat ", " bibtex_programs)

(** [repeated] means an earlier comment sets the same setting (in the same
    file for root and program, anywhere earlier in the chain otherwise). *)
let classify ?(context=no_context) ?(repeated=false) c =
  match c.family, String.lowercase_ascii c.key with
  | _ when c.value = "" -> ignored ("not read; write it as " ^ marker c.family ^ " " ^ c.key ^ " = …")
  | _ when repeated && per_file c -> ignored "only the first one in a file is read; delete this one"
  | _ when repeated -> ignored "an earlier comment sets this; only the first one is read"
  | Tex, ("root" | "program" | "ts-program") -> Used
  | Tex, "encoding" -> ignored ~affects_build:false
      "BBEdit sets the file's encoding and TeX reads the file as saved"
  | Tex, "spellcheck" -> ignored ~affects_build:false "a TeXShop setting; BBEdit has its own spelling settings"
  | Tex, ("options" | "parameter") -> options_status ~context c
  | Tex, "output_directory" -> output_status ~context c
  | Tex, "aux_directory" -> ignored "auxiliary files go in the output directory; set output_directory"
  | Tex, "jobname" -> ignored "the PDF is named after the root file; rename the root file instead"
  | Bib, ("ts-program" | "program") -> bib_status ~context c
  | _ -> ignored "not a comment bbtex knows"

(** Each comment with its status, in file and line order. *)
let statuses ?(context=no_context) comments =
  let same c other = setting other = setting c && (not (per_file c) || other.file = c.file) in
  List.mapi (fun i c ->
    let repeated = (per_file c || mapped c) && c.value <> "" && List.exists (fun earlier ->
      earlier.value <> "" && same c earlier) (List.filteri (fun j _ -> j < i) comments) in
    c, classify ~context ~repeated c) comments

(** Doctor lines: (status, detail), one per comment. *)
let doctor_lines ~dir statuses = List.map (fun (c, status) ->
  let where = Printf.sprintf "%s:%d %s" (relative ~dir c.file) c.line (text c) in
  match status with
  | Used -> "OK", where ^ " (used)"
  | Mapped { becomes; warning = None } -> "OK", Printf.sprintf "%s (mapped: %s)" where becomes
  | Mapped { becomes; warning = Some warning } ->
    "WARN", Printf.sprintf "%s (mapped: %s; %s)" where becomes warning
  | Ignored { advice; affects_build } ->
    (if affects_build then "WARN" else "INFO"), Printf.sprintf "%s (ignored: %s)" where advice)
  statuses

(* Comments that don't do what they say, with the sentence explaining why. *)
let problems statuses = List.filter_map (function
  | c, Ignored { advice; affects_build = true } -> Some (c, "is ignored: " ^ advice)
  | c, Mapped { warning = Some warning; _ } -> Some (c, warning)
  | _ -> None) statuses

(** One line for the build notification, or None when every comment applies. *)
let build_note statuses =
  match problems statuses with
  | [] -> None
  | found ->
    let names = unique (List.map (fun (c, _) -> marker c.family ^ " " ^ c.key) found) in
    Some (Printf.sprintf "[bbtex] Not fully applied: %s; see LaTeX — Doctor" (String.concat ", " names))

(** LaTeX Results entries pointing at each comment that doesn't fully apply. *)
let results statuses = List.map (fun (c, why) ->
  { se_file = c.file; se_line = c.line; se_severity = Warning;
    se_message = Printf.sprintf "[bbtex] %s %s" (text c) why })
  (problems statuses)

(** Which bibliography tool a build ran, from its .blg log. *)
let bib_ran blg =
  match In_channel.with_open_bin blg (fun ic -> In_channel.really_input_string ic
          (min 4096 (Int64.to_int (In_channel.length ic)))) with
  | exception Sys_error _ -> None
  | None -> None
  | Some head ->
    let has sub = Log_parser.contains_substring ~sub head in
    if has "This is Biber" then Some `Biber else if has "BibTeX" then Some `Bibtex else None
