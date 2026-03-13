(** AppleScript generation for BBEdit integration.

    Produces a single AppleScript that, in one [tell application "BBEdit"]
    block: closes the previous results browser and creates a new one with
    exact file+line+message entries for errors, warnings, and bad boxes. *)

open Types

(** [escape_applescript s] escapes backslashes and double quotes so that [s]
    can be safely embedded inside an AppleScript double-quoted string literal. *)
let escape_applescript s =
  let buf = Buffer.create (String.length s) in
  String.iter (fun c ->
    match c with
    | '\\' ->
      Buffer.add_string buf {|\\|}
    | '"' ->
      Buffer.add_string buf {|\"|}
    | c ->
      Buffer.add_char buf c
  ) s;
  Buffer.contents buf

(** Map severity to BBEdit result_kind. *)
let result_kind_of_severity = function
  | Error   -> "error_kind"
  | Warning -> "warning_kind"
  | BadBox  -> "note_kind"

(** [compile_script entries] generates a single AppleScript that:
    1. Closes any existing "LaTeX Errors" results browser
    2. Creates a new results browser with [entries]

    Returns [""] when [entries] is empty. *)
let compile_script entries =
  if entries = [] then ""
  else begin
    let buf = Buffer.create 512 in
    Buffer.add_string buf {|tell application "BBEdit"|};
    Buffer.add_char buf '\n';

    (* Save position of existing results browser, then close it *)
    Buffer.add_string buf {|    set savedBounds to missing value|};
    Buffer.add_char buf '\n';
    Buffer.add_string buf {|    repeat with w in (every window whose name starts with "LaTeX Errors")|};
    Buffer.add_char buf '\n';
    Buffer.add_string buf {|        set savedBounds to bounds of w|};
    Buffer.add_char buf '\n';
    Buffer.add_string buf {|        close w|};
    Buffer.add_char buf '\n';
    Buffer.add_string buf {|    end repeat|};
    Buffer.add_char buf '\n';

    (* Results browser with all entries *)
    let records =
      entries
      |> List.map (fun e ->
           Printf.sprintf
             {|{result_kind:%s, result_file:POSIX file "%s" as alias, result_line:%d, message:"%s"}|}
             (result_kind_of_severity e.se_severity)
             (escape_applescript e.se_file)
             e.se_line
             (escape_applescript e.se_message))
      |> String.concat ", "
    in
    Buffer.add_string buf
      (Printf.sprintf
         {|    set rb to make new results browser with properties {name:"LaTeX Errors"} with data {%s}|}
         records);
    Buffer.add_char buf '\n';

    (* Restore position *)
    Buffer.add_string buf {|    if savedBounds is not missing value then set bounds of rb to savedBounds|};
    Buffer.add_char buf '\n';

    Buffer.add_string buf {|end tell|};
    Buffer.add_char buf '\n';

    (* Uncheck the "Notes" checkbox via UI scripting so only errors/warnings
       are visible by default; the user can still re-check it manually. *)
    if List.exists (fun e -> e.se_severity = BadBox) entries then begin
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|delay 0.3|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|tell application "System Events"|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|    tell process "BBEdit"|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|        repeat with w in windows|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|            if name of w contains "LaTeX Errors" then|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|                repeat with cb in (every checkbox of w)|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|                    if (title of cb as text) contains "Note" then|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|                        if enabled of cb then click cb|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|                        exit repeat|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|                    end if|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|                end repeat|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|                exit repeat|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|            end if|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|        end repeat|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|    end tell|};
      Buffer.add_char buf '\n';
      Buffer.add_string buf {|end tell|};
      Buffer.add_char buf '\n'
    end;

    Buffer.contents buf
  end

(** [write_compile_script entries] writes the compiled AppleScript to a
    temporary file and returns [Some path].  Returns [None] if the script
    would be empty (no entries). *)
let write_compile_script entries =
  let script = compile_script entries in
  if script = "" then None
  else begin
    let path = Filename.temp_file "bbtex_" ".applescript" in
    Log.verbose (Printf.sprintf "writing AppleScript to %s" path);
    let oc = open_out path in
    output_string oc script;
    close_out oc;
    Some path
  end
