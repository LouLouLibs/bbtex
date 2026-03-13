(** Output formatters for log entries.

    Two formats:
    - BBEdit results browser: file:line: severity: message
    - Text: human-readable with ANSI colors *)

open Types

(* ── ANSI colors ────────────────────────────────────────────── *)

let red s     = "\027[31m" ^ s ^ "\027[0m"
let yellow s  = "\027[33m" ^ s ^ "\027[0m"
let cyan s    = "\027[36m" ^ s ^ "\027[0m"
let bold s    = "\027[1m" ^ s ^ "\027[0m"
let dim s     = "\027[2m" ^ s ^ "\027[0m"

(* ── BBEdit format ──────────────────────────────────────────── *)

(** Format one entry for BBEdit's results browser.
    Format: file:line: type: message
    If file or line is unknown, use sensible defaults. *)
let format_bbedit entry =
  let file = Option.value ~default:"<unknown>" entry.file in
  let line = Option.value ~default:0 entry.line in
  let sev = match entry.severity with
    | Error   -> "error"
    | Warning -> "warning"
    | BadBox  -> "warning"
  in
  Printf.sprintf "%s:%d: %s: %s" file line sev entry.message

(** Format all entries for BBEdit. *)
let format_bbedit_all entries =
  List.map format_bbedit entries

(* ── Text format (with ANSI colors) ────────────────────────── *)

let format_text_entry entry =
  let buf = Buffer.create 128 in
  let sev_str = match entry.severity with
    | Error   -> red (bold "error")
    | Warning -> yellow (bold "warning")
    | BadBox  -> cyan "badbox"
  in
  Buffer.add_string buf sev_str;
  (match entry.file with
   | Some f ->
     Buffer.add_string buf (dim " in ");
     Buffer.add_string buf (bold f);
   | None -> ());
  (match entry.line with
   | Some n ->
     Buffer.add_string buf (dim (Printf.sprintf ":%d" n))
   | None -> ());
  Buffer.add_char buf '\n';
  Buffer.add_string buf (Printf.sprintf "  %s\n" entry.message);
  List.iter (fun ctx ->
    Buffer.add_string buf (dim (Printf.sprintf "  | %s\n" ctx))
  ) entry.context;
  Buffer.contents buf

let format_text_all entries =
  List.map format_text_entry entries

(* ── Directive output ───────────────────────────────────────── *)

let format_directives_text directives =
  List.map (fun (d : Types.directive) ->
    Printf.sprintf "%s = %s"
      (string_of_directive_key d.key)
      d.value
  ) directives

(* ── Compile result protocol output ────────────────────────── *)

let format_compile_result result ~applescript_file =
  let open Types in
  let status_str = match result.status with
    | Success -> "success"
    | Failure -> "error"
  in
  let lines = [
    Printf.sprintf "status: %s" status_str;
    Printf.sprintf "summary: %s" result.summary;
    Printf.sprintf "log: %s" result.log_file;
    Printf.sprintf "pdf: %s" result.pdf_file;
  ] in
  match applescript_file with
  | Some path -> lines @ [Printf.sprintf "applescript_file: %s" path]
  | None -> lines

let format_error_message msg =
  [ "status: error"; Printf.sprintf "message: %s" msg ]
