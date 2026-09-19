(** bbtex — LaTeX log parser and BBEdit integration tool. *)

open Bbtex

let usage = {|Usage: bbtex <command> [options] <file>

Commands:
  compile <file.tex>         Compile and report results (protocol output)
  results <file.tex>         Show all diagnostics from the current project log
  paths <file.tex>           Resolve project log and PDF paths without compiling
  clean <file.tex>           Remove auxiliary files, keep PDF
  clean-all <file.tex>       Remove all build output including PDF
  cancel <file.tex>          Cancel the running build for this project
  profiles <file.tex>        List named profiles from .bbtex
  preview <file.tex>         Preview selected math read from stdin
  save-project <file.tex>    Emit AppleScript to save open project files
  document-settings <file> <engine|inherit> <root|->
                            Emit AppleScript to update document directives
  forward-search <f> <line>  SyncTeX forward search
  parse-log <file.log>       Parse a LaTeX log file
  directives <file.tex>      Extract %!TEX directives
  format-results <file.log>  Parse log, output in BBEdit results format

Options:
  --format bbedit|text       Output format (default: text for parse-log,
                             bbedit for format-results)
  --engine <name>            Compile once with pdflatex, xelatex, lualatex,
                             tectonic, or ratex (overrides document directives)
  --profile <name>           Use a named project build profile
  --verbose                  Enable verbose logging to stderr
  --help                     Show this help message
|}

let parse_args () =
  let args = Array.to_list Sys.argv |> List.tl in
  let engine = ref None and profile = ref None in
  let rec go cmd fmt verbose rest = function
    | [] -> (cmd, fmt, verbose, !engine, !profile, List.rev rest)
    | "--help" :: _ -> print_string usage; exit 0
    | "-h" :: _ -> print_string usage; exit 0
    | "--verbose" :: tail -> go cmd fmt true rest tail
    | "--profile" :: name :: tail -> profile := Some name; go cmd fmt verbose rest tail
    | ["--profile"] -> Printf.eprintf "--profile requires a name\n"; exit 2
    | "--engine" :: name :: tail ->
      (match String.lowercase_ascii name with
       | "pdflatex" | "xelatex" | "lualatex" | "tectonic" | "ratex" ->
         engine := Some (Types.engine_of_string name);
         go cmd fmt verbose rest tail
       | _ -> Printf.eprintf "Unknown engine: %s\n" name; exit 2)
    | ["--engine"] -> Printf.eprintf "--engine requires a name\n"; exit 2
    | "--format" :: f :: tail ->
      (match Types.output_format_of_string f with
       | Some fmt' -> go cmd (Some fmt') verbose rest tail
       | None ->
         Printf.eprintf "Unknown format: %s (expected bbedit or text)\n" f;
         exit 1)
    | arg :: tail ->
      if cmd = None then go (Some arg) fmt verbose rest tail
      else go cmd fmt verbose (arg :: rest) tail
  in
  go None None false [] args

let print_summary entries =
  let nerr = List.length (List.filter (fun e -> e.Types.severity = Types.Error) entries) in
  let nwarn = List.length (List.filter (fun e -> e.Types.severity = Types.Warning) entries) in
  let nbox = List.length (List.filter (fun e -> e.Types.severity = Types.BadBox) entries) in
  if nerr + nwarn + nbox > 0 then
    Printf.eprintf "%d error(s), %d warning(s), %d bad box(es)\n" nerr nwarn nbox

let cmd_log ~default_format ~show_summary fmt filename =
  let entries = Log_parser.parse_file filename in
  let fmt = Option.value ~default:default_format fmt in
  (match fmt with
   | Types.Bbedit ->
     List.iter print_endline (Bbedit_format.format_bbedit_all entries)
   | Types.Text ->
     List.iter print_string (Bbedit_format.format_text_all entries));
  if show_summary then print_summary entries;
  if List.exists (fun e -> e.Types.severity = Types.Error) entries
  then exit 1
  else exit 0

let cmd_directives filename =
  let directives = Directive_parser.parse_file filename in
  List.iter print_endline (Bbedit_format.format_directives_text directives)

let cmd_compile ?engine ?profile filename =
  let started = Unix.gettimeofday () in
  try
    let config = Compiler.resolve_compilation ?engine ?profile filename in
    let result = Compiler.compile ?engine ?profile filename in
    Printf.printf "root: %s\nengine: %s\nduration: %.1f\nbuild_log: %s\n"
      config.root_file (Types.string_of_engine config.engine)
      (Unix.gettimeofday () -. started) (Build_job.log_path config.root_file);
    let applescript_file =
      (* Successful builds do not open a results window. Full diagnostics remain
         available through the explicit results command. *)
      Applescript.write_compile_script
        (List.filter (fun e -> e.Types.se_severity = Types.Error) result.search_results)
    in
    let lines = Bbedit_format.format_compile_result result ~applescript_file in
    List.iter print_endline lines;
    match result.status with
    | Types.Success -> exit 0
    | Types.Failure -> exit 1
  with
  | Build_job.Cancelled ->
    print_endline "status: cancelled";
    print_endline "summary: Build cancelled";
    exit 3
  | Compiler.Bbtex_error msg ->
    Log.error msg;
    List.iter print_endline (Bbedit_format.format_error_message msg);
    exit 2

let cmd_results filename =
  try
    let result = Compiler.inspect_log filename in
    let applescript_file = Applescript.write_compile_script result.search_results in
    List.iter print_endline (Bbedit_format.format_compile_result result ~applescript_file)
  with Compiler.Bbtex_error msg ->
    List.iter print_endline (Bbedit_format.format_error_message msg);
    exit 2

let cmd_paths ?engine ?profile filename =
  try
    let config = Compiler.resolve_compilation ?engine ?profile filename in
    Printf.printf "status: success\nlog: %s\npdf: %s\nroot: %s\nengine: %s\nproject: %s\nbuild_log: %s\n"
      config.log_file config.pdf_file config.root_file (Types.string_of_engine config.engine)
      config.project_dir (Build_job.log_path config.root_file)
  with Compiler.Bbtex_error msg ->
    List.iter print_endline (Bbedit_format.format_error_message msg);
    exit 2

let cmd_clean ?(full=false) filename =
  try
    let exit_code = Compiler.clean ~full filename in
    if exit_code = 0 then
      Printf.printf "status: success\nsummary: %s\n"
        (if full then "All build output removed" else "Auxiliary files removed; PDF preserved")
    else
      Printf.printf "status: error\nmessage: Cleanup exited with code %d\n" exit_code;
    exit (if exit_code = 0 then 0 else 2)
  with
  | Build_job.Cancelled ->
    print_endline "status: cancelled";
    print_endline "summary: Build cancelled";
    exit 3
  | Compiler.Bbtex_error msg ->
    Log.error msg;
    List.iter print_endline (Bbedit_format.format_error_message msg);
    exit 2

let cmd_forward_search filename line_str =
  try
    let line_num =
      try int_of_string line_str
      with Failure _ ->
        raise (Compiler.Bbtex_error
          (Printf.sprintf "line number must be an integer, got: %s" line_str))
    in
    let config = Compiler.resolve_compilation filename in
    let pdf_file = config.pdf_file in
    if not (Sys.file_exists pdf_file) then
      raise (Compiler.Bbtex_error
        (Printf.sprintf "PDF not found: %s — compile the document first" pdf_file));

    let synctex_args = [|
      "synctex"; "view";
      "-i"; Printf.sprintf "%d:0:%s" line_num filename;
      "-o"; pdf_file;
    |] in
    Log.info (Printf.sprintf "running: %s"
      (String.concat " " (Array.to_list synctex_args)));

    let (r_fd, w_fd) = Unix.pipe () in
    let devnull = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
    (try
       let pid = Unix.create_process "synctex" synctex_args devnull w_fd Unix.stderr in
       Unix.close devnull;
       Unix.close w_fd;
       let ic = Unix.in_channel_of_descr r_fd in
       let lines = ref [] in
       (try while true do lines := input_line ic :: !lines done
        with End_of_file -> ());
       let _ = Unix.waitpid [] pid in
       let output = List.rev !lines in

       let find_val prefix =
         List.find_map (fun l ->
           if String.starts_with ~prefix l then
             Some (String.trim (String.sub l (String.length prefix)
               (String.length l - String.length prefix)))
           else None
         ) output
       in
       let page = Option.value ~default:"1" (find_val "Page:") in
       let x = Option.value ~default:"0" (find_val "x:") in
       let y = Option.value ~default:"0" (find_val "y:") in

       Printf.printf "status: success\n";
       Printf.printf "pdf: %s\n" pdf_file;
       Printf.printf "page: %s\n" page;
       Printf.printf "x: %s\n" x;
       Printf.printf "y: %s\n" y;
       exit 0
     with Unix.Unix_error (Unix.ENOENT, _, _) ->
       Unix.close r_fd;
       raise (Compiler.Bbtex_error "synctex not found in PATH"))
  with
  | Build_job.Cancelled ->
    print_endline "status: cancelled";
    print_endline "summary: Build cancelled";
    exit 3
  | Compiler.Bbtex_error msg ->
    Log.error msg;
    List.iter print_endline (Bbedit_format.format_error_message msg);
    exit 2

let () =
  let (cmd, fmt, verbose, engine, profile, args) = parse_args () in
  if (engine <> None || profile <> None) && cmd <> Some "compile" && cmd <> Some "paths" then begin
    Printf.eprintf "--engine/--profile are only supported by compile and paths\n"; exit 2
  end;
  if verbose then Log.set_verbose ();
  match cmd with
  | None ->
    print_string usage;
    exit 1
  | Some "compile" ->
    (match args with
     | [f] -> cmd_compile ?engine ?profile f
     | _ -> Printf.eprintf "compile requires a filename\n"; exit 1)
  | Some "preview" ->
    (match args with
     | [f] -> (try
         let selection = Buffer.create 256 in
         (try while true do Buffer.add_string selection (input_line stdin); Buffer.add_char selection '\n' done
          with End_of_file -> ());
         exit (Preview.compile f (Buffer.contents selection))
       with
       | Project.Error message -> Printf.printf "status: error\nmessage: %s\n" message; exit 2
       | Build_job.Cancelled -> print_endline "status: cancelled"; exit 3)
     | _ -> Printf.eprintf "preview requires a filename and selection on stdin\n"; exit 2)
  | Some "snippet-page" ->
    (match args with
     | [png] -> print_endline (Snippet_page.publish png)
     | _ -> Printf.eprintf "snippet-page requires a PNG filename\n"; exit 2)
  | Some "equation-at" ->
    (match args with
     | [file; line] -> (try print_endline (Equation.at_line (Preview.read_file file) (int_of_string line))
       with Project.Error message -> Printf.eprintf "%s\n" message; exit 2)
     | _ -> Printf.eprintf "equation-at requires a filename and line\n"; exit 2)
  | Some "clean" ->
    (match args with
     | [f] -> cmd_clean f
     | _ -> Printf.eprintf "clean requires a filename\n"; exit 1)
  | Some "clean-all" ->
    (match args with
     | [f] -> cmd_clean ~full:true f
     | _ -> Printf.eprintf "clean-all requires a filename\n"; exit 1)
  | Some "cancel" ->
    (match args with
     | [f] -> (try
         let cancelled = Compiler.cancel f in
         Printf.printf "status: success\nsummary: %s\n"
           (if cancelled then "Cancellation requested" else "No build is running for this project")
       with Compiler.Bbtex_error msg ->
         List.iter print_endline (Bbedit_format.format_error_message msg); exit 2)
     | _ -> Printf.eprintf "cancel requires a filename\n"; exit 1)
  | Some "profiles" ->
    (match args with
     | [f] -> (try
         List.iter (fun (name, _) -> Printf.printf "profile: %s\n" name)
           (Compiler.settings_for f).Project.profiles
       with Compiler.Bbtex_error msg ->
         List.iter print_endline (Bbedit_format.format_error_message msg); exit 2)
     | _ -> Printf.eprintf "profiles requires a filename\n"; exit 1)
  | Some "save-project" ->
    (match args with
     | [f] -> (try print_string (Applescript.save_project_script (Compiler.resolve_compilation f))
       with Compiler.Bbtex_error msg -> Printf.eprintf "%s\n" msg; exit 2)
     | _ -> Printf.eprintf "save-project requires a filename\n"; exit 1)
  | Some "document-settings" ->
    (match args with
     | [f; engine; root] -> (try print_string (Document_settings.script f engine root)
       with Project.Error msg -> Printf.eprintf "%s\n" msg; exit 2)
     | _ -> Printf.eprintf "document-settings requires file, engine, and root (or -)\n"; exit 2)
  | Some "results" ->
    (match args with
     | [f] -> cmd_results f
     | _ -> Printf.eprintf "results requires a filename\n"; exit 1)
  | Some "paths" ->
    (match args with
     | [f] -> cmd_paths ?engine ?profile f
     | _ -> Printf.eprintf "paths requires a filename\n"; exit 1)
  | Some "forward-search" ->
    (match args with
     | [f; line] -> cmd_forward_search f line
     | _ -> Printf.eprintf "forward-search requires <file.tex> <line>\n"; exit 1)
  | Some "parse-log" ->
    (match args with
     | [f] -> cmd_log ~default_format:Types.Text ~show_summary:true fmt f
     | _ -> Printf.eprintf "parse-log requires a filename\n"; exit 1)
  | Some "directives" ->
    (match args with
     | [f] -> cmd_directives f
     | _ -> Printf.eprintf "directives requires a filename\n"; exit 1)
  | Some "format-results" ->
    (match args with
     | [f] -> cmd_log ~default_format:Types.Bbedit ~show_summary:false fmt f
     | _ -> Printf.eprintf "format-results requires a filename\n"; exit 1)
  | Some other ->
    Printf.eprintf "Unknown command: %s\n\n%s" other usage;
    exit 1
