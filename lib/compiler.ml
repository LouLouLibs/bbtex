(** Compilation orchestration.

    Resolves %%!TEX directives, runs latexmk or tectonic, parses the
    resulting log file, and assembles a compile_result for the caller. *)

open Types

(** Raised for all bbtex-internal failures: file not found, wrong extension,
    missing external tools, etc. *)
exception Bbtex_error = Project.Error

(* ── resolve_compilation ─────────────────────────────────────── *)

(** [resolve_compilation path] validates [path], reads directives, determines
    the root file and engine, and returns a fully-resolved compilation_config.

    Raises [Bbtex_error] if:
    - the file does not exist
    - the file does not end in ".tex" *)
let strict_engine name =
  match String.lowercase_ascii name with
  | "pdflatex" | "xelatex" | "lualatex" | "tectonic" | "ratex" -> Types.engine_of_string name
  (* TeXShop's built-in engine names run these compilers (through latexmk). *)
  | "pdflatexmk" | "latexmk" | "latex" -> Types.Pdflatex
  | "xelatexmk" -> Types.Xelatex
  | "lualatexmk" -> Types.Lualatex
  | _ -> raise (Bbtex_error ("Unknown LaTeX engine: " ^ name ^ ". Use pdflatex, xelatex, \
      lualatex or tectonic; TeXShop's pdflatexmk, xelatexmk, lualatexmk, latexmk and LaTeX \
      also work."))

let canonical path =
  if not (Sys.file_exists path) then raise (Bbtex_error ("file not found: " ^ path));
  if Filename.extension path <> ".tex" || Sys.is_directory path then
    raise (Bbtex_error ("not a .tex file: " ^ path));
  Unix.realpath path

let resolve_compilation ?engine:engine_override ?profile path =
  let source_file = canonical path in
  let initial = Project.load (Filename.dirname source_file) in
  let rec follow visited program file =
    if List.mem file visited then raise (Bbtex_error ("Cyclic %!TEX root directives: " ^ file));
    let directives = Directive_parser.parse_file file in
    let program = match program with Some _ -> program | None ->
      Directive_parser.find_directive Program directives in
    let root = match Directive_parser.find_directive Root directives with
      | Some value -> Some (Filename.dirname file, value)
      | None when visited = [] -> Option.map (fun value ->
          Filename.dirname (Option.get initial.file), value) (Project.get "root" initial.defaults)
      | None -> None
    in
    match root with
    | None -> file, program
    | Some (dir, root) ->
      let next = canonical (if Filename.is_relative root then Filename.concat dir root else root) in
      if next = file then file, program (* Conventional self-root directive. *)
      else follow (file :: visited) program next
  in
  let root_file, program = follow [] None source_file in
  let settings = if initial.file = None then Project.load (Filename.dirname root_file) else initial in
  let profile = match profile with Some _ -> profile | None -> Project.get "default_profile" settings.defaults in
  let fields = match profile with
    | None -> []
    | Some name -> (match List.assoc_opt name settings.profiles with
       | Some fields -> fields | None -> raise (Bbtex_error ("Unknown build profile: " ^ name)))
  in
  let engine = match engine_override with
    | Some e -> e
    | None ->
      let name = match Project.get "engine" fields with
        | Some e -> e
        | None -> Option.value ~default:(Option.value ~default:"pdflatex"
            (Project.get "engine" settings.defaults)) program
      in strict_engine name
  in
  let root_dir = Filename.dirname root_file in
  let output_directory = match Project.get "output_directory" settings.defaults with
    | None -> root_dir
    | Some "" -> raise (Bbtex_error "output_directory cannot be empty")
    | Some dir -> Source_reader.resolve_path ~root_dir dir
  in
  let options = Project.options (Option.value ~default:"" (Project.get "options" settings.defaults)) @
    Project.options (Option.value ~default:"" (Project.get "options" fields)) in
  let base = Filename.concat output_directory (Filename.remove_extension (Filename.basename root_file)) in
  let project_dir = match settings.file with None -> root_dir | Some f -> Filename.dirname f in
  { source_file; root_file; engine; project_dir; output_directory; options; profile;
    log_file = base ^ ".log"; pdf_file = base ^ ".pdf" }

let settings_for path =
  let config = resolve_compilation path in
  Project.load config.project_dir

(* Some latexmk versions only recognize this TeX error without file-line-error.
   Recover only missing relative .aux parents, strictly inside the output tree. *)
let prepare_aux_directories ~output_directory ~log_file =
  let created = ref false in
  let prepare line =
    let marker = "I can't write on file `" in
    let rec find i =
      if i + String.length marker > String.length line then None
      else if String.sub line i (String.length marker) = marker then Some (i + String.length marker)
      else find (i + 1) in
    match find 0 with
    | None -> ()
    | Some first ->
      (match String.index_from_opt line first '\'' with
       | None -> ()
       | Some last ->
         let path = String.sub line first (last-first) in
         let parts = String.split_on_char '/' path in
         if Filename.is_relative path && String.ends_with ~suffix:".aux" path &&
            not (List.exists (fun p -> p = ".." || p = "") parts) then begin
           let parents = List.rev (List.tl (List.rev parts)) |> List.filter ((<>) ".") in
           let rec make parent = function
             | [] -> ()
             | part :: rest ->
               let dir = Filename.concat parent part in
               let exists = try Some (Unix.lstat dir).Unix.st_kind
                 with Unix.Unix_error (Unix.ENOENT, _, _) -> None in
               (match exists with
                | Some Unix.S_DIR -> make dir rest
                | Some _ -> () (* Do not follow symlinks or overwrite files. *)
                | None -> Unix.mkdir dir 0o700; created := true; make dir rest)
           in make output_directory parents
         end)
  in
  (try
     if (Unix.stat log_file).Unix.st_size <= 8 * 1024 * 1024 then
       Preview_cache.read log_file |> String.split_on_char '\n' |> List.iter prepare
   with Sys_error _ | Unix.Unix_error _ -> ());
  !created

let run_compilation job config =
  Build_job.mkdir config.output_directory;
  let command, args = match config.engine with
    | Ratex -> "ratex", ["-pdf"; "-interaction=nonstopmode"; "-output-directory=" ^ config.output_directory]
    | Tectonic -> "tectonic", ["--keep-logs"; "--synctex"; "--outdir"; config.output_directory]
    | engine -> "latexmk", [Types.latexmk_flag engine; "-interaction=nonstopmode";
        "-file-line-error"; "-synctex=1"; "-cd"; "-outdir=" ^ config.output_directory]
  in
  let rec run remaining retry =
    let code = Build_job.run job ~cwd:(Filename.dirname config.root_file) command
      (args @ (if retry then ["-g"] else []) @ config.options @ [config.root_file]) in
    if code <> 0 && command = "latexmk" && remaining > 0 &&
       prepare_aux_directories ~output_directory:config.output_directory ~log_file:config.log_file
    then run (remaining-1) true else code
  in run 16 false

(* ── make_summary ────────────────────────────────────────────── *)

(** [make_summary entries] counts errors, warnings, and bad boxes and returns
    a human-readable summary string. *)
let make_summary entries =
  let errors   = ref 0 in
  let warnings = ref 0 in
  let badboxes = ref 0 in
  List.iter (fun e ->
    match e.severity with
    | Error   -> incr errors
    | Warning -> incr warnings
    | BadBox  -> incr badboxes
  ) entries;
  Printf.sprintf "%d error(s), %d warning(s), %d bad box(es)"
    !errors !warnings !badboxes

(* ── clean ───────────────────────────────────────────────────── *)

(** [clean path] resolves directives to find the root file, then runs
    [latexmk -C] to remove all build artifacts (.aux, .log, .pdf, .synctex.gz,
    etc.).  Works regardless of which engine was used to compile. *)
let clean ?(full=false) path =
  let config = resolve_compilation path in
  Build_job.with_job config.root_file (fun job ->
    Build_job.run job ~cwd:(Filename.dirname config.root_file) "latexmk"
      [ (if full then "-C" else "-c"); "-cd"; "-outdir=" ^ config.output_directory; config.root_file ])

let cancel path =
  let config = resolve_compilation path in
  Build_job.cancel config.root_file

(* ── compile ─────────────────────────────────────────────────── *)

(** [compile path] is the full pipeline: resolve → compile → parse log →
    build search entries → build loose warnings → assemble compile_result. *)
let assemble_result config ~exit_code entries =
  let entries =
    if exit_code <> 0 && not (List.exists (fun e -> e.severity = Error) entries) then
      { severity = Error; file = Some config.root_file; line = None;
        message = Printf.sprintf
          "Compilation failed (exit %d). Use LaTeX — Open Build Log for details." exit_code;
        context = [] } :: entries
    else entries
  in
  let root_dir = Filename.dirname config.root_file in
  (* Preserve project-wide diagnostics and unavailable-file diagnostics too. *)
  let located_entries = List.map (fun e ->
    match e.file with
    | Some file when Sys.file_exists (Source_reader.resolve_path ~root_dir file) -> e
    | _ -> { e with file = Some config.root_file; line = None }
  ) entries in
  let search_results = Source_reader.build_search_entries ~root_dir located_entries in

  let summary = make_summary entries in
  Log.info summary;

  let has_errors =
    List.exists (fun e -> e.severity = Error) entries
  in
  let status =
    if has_errors || exit_code <> 0 then Failure else Success
  in

  { status;
    summary;
    log_file       = config.log_file;
    pdf_file       = config.pdf_file;
    search_results }

let inspect_log path =
  let config = resolve_compilation path in
  let config = if config.engine = Ratex then { config with log_file = Build_job.log_path config.root_file } else config in
  if not (Sys.file_exists config.log_file) then
    raise (Bbtex_error "No LaTeX log yet. Compile the document first, or use Open Build Log for compiler output.");
  assemble_result config ~exit_code:0 (Log_parser.parse_file config.log_file)

let compile ?engine ?profile path =
  let config = resolve_compilation ?engine ?profile path in
  Build_job.with_job config.root_file (fun job ->
  let exit_code = run_compilation job config in
  Log.info (Printf.sprintf "compiler exited with code %d" exit_code);
  let entries =
    if config.engine = Ratex then Log_parser.parse_file job.log
    else if Sys.file_exists config.log_file then Log_parser.parse_file config.log_file
    else []
  in
  let result_config = if config.engine = Ratex then { config with log_file = job.log } else config in
  let result = assemble_result result_config ~exit_code entries in
  if result.status = Success && not (Sys.file_exists config.pdf_file) then
    raise (Bbtex_error "Compiler finished without producing a PDF. Use Open Build Log for details.");
  result)
