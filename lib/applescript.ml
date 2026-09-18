(** Native BBEdit results browsers, without Accessibility/UI scripting. *)
open Types

let escape_applescript s =
  let buf = Buffer.create (String.length s) in
  String.iter (fun c ->
    match c with
    | '\\' -> Buffer.add_string buf {|\\|}
    | '"' -> Buffer.add_string buf {|\"|}
    | c -> Buffer.add_char buf c
  ) s;
  Buffer.contents buf

let result_kind_of_severity = function
  | Error -> "error_kind"
  | Warning -> "warning_kind"
  | BadBox -> "note_kind"

(** Close only our results browsers, including the former title.
    Empty input clears stale errors without opening a new window. *)
let compile_script entries =
  let records = entries |> List.map (fun e ->
    Printf.sprintf
      {|{result_kind:%s, result_file:POSIX file "%s" as alias, result_line:%d, message:"%s"}|}
      (result_kind_of_severity e.se_severity)
      (escape_applescript e.se_file) e.se_line
      (escape_applescript e.se_message)
  ) |> String.concat ", " in
  let show =
    if entries = [] then ""
    else Printf.sprintf
      {|    set rb to make new results browser with properties {name:"LaTeX Results"} with data {%s}
    if savedBounds is not missing value then set bounds of rb to savedBounds
|} records
  in
  {|tell application "BBEdit"
    set savedBounds to missing value
    repeat with w in (every results browser)
        if name of w is "LaTeX Errors" or name of w is "LaTeX Results" then
            set savedBounds to bounds of w
            close w
        end if
    end repeat
|} ^ show ^ "end tell\n"

let write_compile_script entries =
  let path = Filename.temp_file "bbtex_" ".applescript" in
  let oc = open_out path in
  Fun.protect ~finally:(fun () -> close_out oc)
    (fun () -> output_string oc (compile_script entries));
  Some path

(** Save modified TeX inputs in the project directory, plus the explicit root.
    Unsaved untitled documents have no project identity and are not included. *)
let save_project_script config =
  Printf.sprintf
    {|tell application "BBEdit"
    repeat with d in (get text documents)
        set documentPath to ""
        try
            set documentFile to get file of d
            set documentPath to POSIX path of documentFile
        end try
        if documentPath is not "" and modified of d then
            if documentPath is "%s" or documentPath starts with "%s" then
                if documentPath ends with ".tex" or documentPath ends with ".bib" or documentPath ends with ".sty" or documentPath ends with ".cls" then
                    save d
                end if
            end if
        end if
    end repeat
end tell
|} (escape_applescript config.root_file)
    (escape_applescript (config.project_dir ^ "/"))
