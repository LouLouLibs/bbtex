(** The latexmkrc files latexmk reads for a build, and the settings in them
    that bbtex's own choices override.

    bbtex runs latexmk from the root file's folder, so a project latexmkrc is
    read like in Overleaf: TEXINPUTS, custom $pdflatex commands and the like
    all apply. Three settings don't, because bbtex passes them on the command
    line: the output folder ($out_dir), the auxiliary folder ($aux_dir, kept
    with the output so results and SyncTeX find the log) and the engine
    ($pdf_mode and friends). A latexmkrc is Perl; bbtex only recognises
    literal values and says so when it can't tell. *)

type finding = {
  file : string;
  line : int;          (** 0 for the file as a whole *)
  level : string;      (** Doctor's OK, INFO or WARN *)
  message : string;
  overridden : bool;   (** bbtex's setting replaces the rc's: builds say so *)
}

let first_existing paths = List.find_opt (fun p -> try Sys.is_regular_file p with Sys_error _ -> false) paths

(** The rc files latexmk reads, per its documentation: the first user file
    found, then the first of latexmkrc and .latexmkrc in the build folder. *)
let files ~home ~config_home ~root_dir =
  List.filter_map Fun.id [
    first_existing [Filename.concat config_home "latexmk/latexmkrc"; Filename.concat home ".latexmkrc"];
    first_existing [Filename.concat root_dir "latexmkrc"; Filename.concat root_dir ".latexmkrc"] ]

(* A line without its Perl comment; '#' inside strings is rare enough in rc files. *)
let code line = match String.index_opt line '#' with Some i -> String.sub line 0 i | None -> line

(** The right-hand side of "$name = value;" on [line], if it assigns [name]. *)
let assignment name line =
  let line = code line in
  let target = "$" ^ name in
  let len = String.length line and n = String.length target in
  let rec find i =
    if i + n > len then None
    else if String.sub line i n = target &&
            (i + n = len || not (match line.[i + n] with 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> true | _ -> false))
    then
      let j = ref (i + n) in
      while !j < len && (line.[!j] = ' ' || line.[!j] = '\t') do incr j done;
      if !j < len && line.[!j] = '=' && (!j + 1 >= len || line.[!j + 1] <> '=') then
        let rest = String.sub line (!j + 1) (len - !j - 1) in
        let rest = match String.index_opt rest ';' with Some k -> String.sub rest 0 k | None -> rest in
        Some (String.trim rest)
      else find (i + 1)
    else find (i + 1)
  in find 0

(** A literal Perl string or number, unquoted; None for anything computed. *)
let literal value =
  let len = String.length value in
  if len >= 2 && (value.[0] = '\'' || value.[0] = '"') && value.[len - 1] = value.[0]
     && not (String.contains (String.sub value 1 (len - 2)) '$')
  then Some (String.sub value 1 (len - 2))
  else if len > 0 && String.for_all (fun c -> c >= '0' && c <= '9') value then Some value
  else None

let engine_of_pdf_mode = function
  | "1" -> Some Types.Pdflatex | "4" -> Some Types.Lualatex | "5" -> Some Types.Xelatex | _ -> None

(** What bbtex makes of the rc files for [config]. [home] and [config_home]
    locate the user's own latexmkrc. *)
let inspect ~home ~config_home (config : Types.compilation_config) =
  let root_dir = Filename.dirname config.root_file in
  let files = files ~home ~config_home ~root_dir in
  let latexmk = match config.engine with Types.Tectonic | Types.Ratex -> false | _ -> true in
  let output = config.output_directory in
  let shown dir = if dir = root_dir then "next to the root file" else Magic_comments.relative ~dir:root_dir dir in
  List.concat_map (fun file ->
    let whole level message = { file; line = 0; level; message; overridden = false } in
    if not latexmk then [whole "INFO" ("not read: " ^ Types.string_of_engine config.engine ^ " builds don't run latexmk")]
    else
      let lines = try In_channel.with_open_bin file In_channel.input_lines with Sys_error _ -> [] in
      let found = List.concat (List.mapi (fun i text ->
        let at level message overridden = { file; line = i + 1; level; message; overridden } in
        let folder name what =
          match assignment name text with
          | None -> []
          | Some value ->
            let same = match literal value with
              | Some dir -> Source_reader.resolve_path ~root_dir dir = output
              | None -> false in
            if same then [at "OK" (Printf.sprintf "$%s matches bbtex's output folder" name) false]
            else [at "WARN" (Printf.sprintf "$%s is replaced by bbtex's output folder (%s)%s" name (shown output) what) true]
        in
        folder "out_dir" "; set output_directory in .bbtex instead" @
        folder "aux_dir" ": auxiliary files stay with the output so results and SyncTeX find the log" @
        (match assignment "pdf_mode" text with
         | None -> []
         | Some value -> match Option.bind (literal value) engine_of_pdf_mode with
           | Some engine when engine = config.engine -> [at "OK" "$pdf_mode matches bbtex's engine" false]
           | _ -> [at "WARN" (Printf.sprintf "$pdf_mode is replaced by bbtex's engine (%s); choose it with \
                %% !TEX program or engine = in .bbtex" (Types.string_of_engine config.engine)) true]) @
        (if Log_parser.contains_substring ~sub:"shell-escape" (code text)
         then [at "INFO" "turns on shell escape for this project's builds" false] else []))
        lines) in
      whole "INFO" "read by latexmk" :: found)
    files

(** Doctor lines: (level, detail). *)
let doctor_lines findings = List.map (fun f ->
  f.level, if f.line = 0 then Printf.sprintf "%s: %s" f.file f.message
    else Printf.sprintf "%s:%d: %s" f.file f.line f.message) findings

let overridden findings = List.filter (fun f -> f.overridden) findings

(** One line for the build notification, or None. *)
let build_note findings =
  match overridden findings with
  | [] -> None
  | found ->
    (* Every overridden message starts with the rc variable's name. *)
    let names = List.map (fun f -> List.hd (String.split_on_char ' ' f.message)) found
      |> List.fold_left (fun acc n -> if List.mem n acc then acc else acc @ [n]) [] in
    Some (Printf.sprintf "[bbtex] latexmkrc %s replaced by bbtex's settings; see LaTeX — Doctor"
      (String.concat ", " names))

(** LaTeX Results entries at each overridden setting. *)
let results findings = List.map (fun f ->
  { Types.se_file = f.file; se_line = f.line; se_severity = Types.Warning;
    se_message = "[bbtex] latexmkrc: " ^ f.message }) (overridden findings)
