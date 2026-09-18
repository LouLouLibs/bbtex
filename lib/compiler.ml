(** Compilation orchestration.

    Resolves %%!TEX directives, runs latexmk or tectonic, parses the
    resulting log file, and assembles a compile_result for the caller. *)

open Types

(** Raised for all bbtex-internal failures: file not found, wrong extension,
    missing external tools, etc. *)
exception Bbtex_error of string

(* ── resolve_compilation ─────────────────────────────────────── *)

(** [resolve_compilation path] validates [path], reads directives, determines
    the root file and engine, and returns a fully-resolved compilation_config.

    Raises [Bbtex_error] if:
    - the file does not exist
    - the file does not end in ".tex" *)
let resolve_compilation ?engine:engine_override path =
  Log.info (Printf.sprintf "resolving compilation for: %s" path);

  (* Validate existence *)
  if not (Sys.file_exists path) then
    raise (Bbtex_error (Printf.sprintf "file not found: %s" path));

  (* Validate extension *)
  if Filename.extension path <> ".tex" then
    raise (Bbtex_error
      (Printf.sprintf "not a .tex file: %s" path));

  (* Resolve to absolute path *)
  let abs_source =
    if Filename.is_relative path then
      Filename.concat (Sys.getcwd ()) path
    else
      path
  in
  Log.info (Printf.sprintf "absolute source: %s" abs_source);

  let source_dir = Filename.dirname abs_source in

  (* Read directives *)
  let directives = Directive_parser.parse_file abs_source in
  Log.info (Printf.sprintf "found %d directive(s)" (List.length directives));

  (* Resolve root file: relative to source_dir *)
  let abs_root =
    match Directive_parser.find_directive Root directives with
    | None ->
      Log.info "no root directive; using source file as root";
      abs_source
    | Some rel_root ->
      let candidate =
        if Filename.is_relative rel_root then
          Filename.concat source_dir rel_root
        else
          rel_root
      in
      Log.info (Printf.sprintf "root directive -> %s" candidate);
      candidate
  in

  if not (Sys.file_exists abs_root) then
    raise (Bbtex_error (Printf.sprintf "root file not found: %s" abs_root));
  let root_directives = Directive_parser.parse_file abs_root in
  (* An explicit choice overrides the source directive, then the root directive. *)
  let program =
    match Directive_parser.find_directive Program directives with
    | Some _ as program -> program
    | None -> Directive_parser.find_directive Program root_directives
  in
  (* Determine engine *)
  let engine =
    match engine_override, program with
    | Some engine, _ -> engine
    | None, None ->
      Log.info "no program directive; defaulting to pdflatex";
      Pdflatex
    | None, Some prog ->
      let e = Types.engine_of_string prog in
      Log.info (Printf.sprintf "engine: %s" (Types.string_of_engine e));
      e
  in

  (* Derive log and pdf paths from root base *)
  let root_base = Filename.remove_extension abs_root in
  let log_file = root_base ^ ".log" in
  let pdf_file = root_base ^ ".pdf" in

  Log.info (Printf.sprintf "log_file: %s" log_file);
  Log.info (Printf.sprintf "pdf_file: %s" pdf_file);

  { source_file = abs_source;
    root_file   = abs_root;
    engine;
    log_file;
    pdf_file }

(* ── run_compilation ─────────────────────────────────────────── *)

(** [run_compilation config] executes latexmk or tectonic and returns the
    exit code.  stdout and stderr from the child process are forwarded to
    Unix.stderr (which the shell wrapper redirects to the log). *)
let run_compilation config =
  let dev_null =
    Unix.openfile "/dev/null" [Unix.O_RDONLY] 0
  in
  let exit_code =
    try
      let (cmd, argv) =
        match config.engine with
        | Tectonic ->
          let cmd = "tectonic" in
          (cmd, [| cmd; "--keep-logs"; "--synctex"; config.root_file |])
        | engine ->
          let cmd = "latexmk" in
          let flag = Types.latexmk_flag engine in
          (cmd, [| cmd;
                   flag;
                   "-interaction=nonstopmode";
                   "-file-line-error";
                   "-synctex=1";
                   "-cd";
                   config.root_file |])
      in
      Log.info (Printf.sprintf "running: %s %s"
                  cmd (String.concat " " (Array.to_list (Array.sub argv 1 (Array.length argv - 1)))));
      let pid =
        Unix.create_process cmd argv dev_null Unix.stderr Unix.stderr
      in
      let (_, status) = Unix.waitpid [] pid in
      (match status with
       | Unix.WEXITED n   -> n
       | Unix.WSIGNALED _ -> 1
       | Unix.WSTOPPED _  -> 1)
    with
    | Unix.Unix_error (Unix.ENOENT, _, _) ->
      let cmd =
        match config.engine with
        | Tectonic -> "tectonic"
        | _        -> "latexmk"
      in
      Unix.close dev_null;
      raise (Bbtex_error (Printf.sprintf "%s not found in PATH" cmd))
  in
  Unix.close dev_null;
  exit_code

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
let clean path =
  let config = resolve_compilation path in
  Log.info (Printf.sprintf "cleaning build artifacts for: %s" config.root_file);
  let cmd = "latexmk" in
  let argv = [| cmd; "-C"; "-cd"; config.root_file |] in
  Log.info (Printf.sprintf "running: %s %s" cmd
    (String.concat " " (Array.to_list (Array.sub argv 1 (Array.length argv - 1)))));
  let dev_null = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
  let exit_code =
    try
      let pid = Unix.create_process cmd argv dev_null Unix.stderr Unix.stderr in
      Unix.close dev_null;
      let (_, status) = Unix.waitpid [] pid in
      (match status with
       | Unix.WEXITED n   -> n
       | Unix.WSIGNALED _ -> 1
       | Unix.WSTOPPED _  -> 1)
    with Unix.Unix_error (Unix.ENOENT, _, _) ->
      Unix.close dev_null;
      raise (Bbtex_error "latexmk not found in PATH")
  in
  Log.info (Printf.sprintf "latexmk -C exited with code %d" exit_code);
  exit_code

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
  if not (Sys.file_exists config.log_file) then
    raise (Bbtex_error "No LaTeX log yet. Compile the document first, or use Open Build Log for compiler output.");
  assemble_result config ~exit_code:0 (Log_parser.parse_file config.log_file)

let compile ?engine path =
  let config = resolve_compilation ?engine path in
  let exit_code = run_compilation config in
  Log.info (Printf.sprintf "compiler exited with code %d" exit_code);
  let entries =
    if Sys.file_exists config.log_file then Log_parser.parse_file config.log_file
    else []
  in
  let result = assemble_result config ~exit_code entries in
  if result.status = Success && not (Sys.file_exists config.pdf_file) then
    raise (Bbtex_error "Compiler finished without producing a PDF. Use Open Build Log for details.");
  result
