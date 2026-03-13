(** bbtex — LaTeX log parser and BBEdit integration tool. *)

open Bbtex

let usage = {|Usage: bbtex <command> [options] <file>

Commands:
  compile <file.tex>         Compile and report results (protocol output)
  clean <file.tex>           Remove all build artifacts (latexmk -C)
  forward-search <f> <line>  SyncTeX forward search
  parse-log <file.log>       Parse a LaTeX log file
  directives <file.tex>      Extract %!TEX directives
  format-results <file.log>  Parse log, output in BBEdit results format

Options:
  --format bbedit|text       Output format (default: text for parse-log,
                             bbedit for format-results)
  --verbose                  Enable verbose logging to stderr
  --help                     Show this help message
|}

let parse_args () =
  let args = Array.to_list Sys.argv |> List.tl in
  let rec go cmd fmt verbose rest = function
    | [] -> (cmd, fmt, verbose, List.rev rest)
    | "--help" :: _ -> print_string usage; exit 0
    | "-h" :: _ -> print_string usage; exit 0
    | "--verbose" :: tail -> go cmd fmt true rest tail
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

let cmd_compile filename =
  try
    let result = Compiler.compile filename in
    let applescript_file =
      Applescript.write_compile_script result.search_results
    in
    let lines = Bbedit_format.format_compile_result result ~applescript_file in
    List.iter print_endline lines;
    match result.status with
    | Types.Success -> exit 0
    | Types.Failure -> exit 1
  with Compiler.Bbtex_error msg ->
    Log.error msg;
    List.iter print_endline (Bbedit_format.format_error_message msg);
    exit 2

let cmd_clean filename =
  try
    let exit_code = Compiler.clean filename in
    if exit_code = 0 then
      Printf.printf "status: success\nsummary: build artifacts removed\n"
    else
      Printf.printf "status: error\nmessage: latexmk -C exited with code %d\n" exit_code;
    exit (if exit_code = 0 then 0 else 2)
  with Compiler.Bbtex_error msg ->
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
  with Compiler.Bbtex_error msg ->
    Log.error msg;
    List.iter print_endline (Bbedit_format.format_error_message msg);
    exit 2

let () =
  let (cmd, fmt, verbose, args) = parse_args () in
  if verbose then Log.set_verbose ();
  match cmd with
  | None ->
    print_string usage;
    exit 1
  | Some "compile" ->
    (match args with
     | [f] -> cmd_compile f
     | _ -> Printf.eprintf "compile requires a filename\n"; exit 1)
  | Some "clean" ->
    (match args with
     | [f] -> cmd_clean f
     | _ -> Printf.eprintf "clean requires a filename\n"; exit 1)
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
