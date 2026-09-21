let quote value = "\"" ^ Applescript.escape_applescript value ^ "\""

let picker_body index query =
  let entries = Project_index.search index query in
  if List.length entries > 300 then raise (Project.Error
    "More than 300 outline matches. Run Project Outline again with a narrower search.");
  let warning = if index.Project_index.issues = [] then "" else
    "display alert \"Partial project outline\" message " ^
    quote (String.concat "\n" index.issues) ^ "\n" in
  if entries = [] then warning ^
    "display alert \"Project Outline\" message \"No matching saved-source entries. Try a shorter search.\"\nreturn false\n"
  else
    let rows = List.mapi (fun i e -> Printf.sprintf "%d. %s" (i + 1)
      (Project_index.display index.root e)) entries in
    let choices = String.concat ", " (List.map quote rows) in
    warning ^ "set rows to {" ^ choices ^ "}\n" ^
    "set chosen to choose from list rows with title \"LaTeX Project Outline\" with prompt " ^
    quote (Filename.basename index.root ^ " — saved files. Choose a location; Return opens it.") ^
    " OK button name \"Go\"\nif chosen is false then return false\n" ^
    String.concat "\n" (List.mapi (fun i e -> Printf.sprintf
      "if item 1 of chosen is item %d of rows then return {%s, %s, %s}"
      (i + 1) (quote e.Project_index.file) (quote e.fingerprint) (quote (string_of_int e.line))) entries)

let picker index query = "tell application \"BBEdit\"\n" ^ picker_body index query ^ "\nend tell\n"

let jump ~binary file fingerprint line =
  let raw = Project_index.read file in
  if Project_index.hash raw <> fingerprint then raise (Project.Error
    "Source changed since the outline was opened. Run Project Outline again.");
  (* CRLF counts as one hard line, as do legacy CR-only files. *)
  let normalized = Buffer.create (String.length raw) in
  String.iteri (fun i c -> if c = '\r' then begin
    if i + 1 = String.length raw || raw.[i + 1] <> '\n' then Buffer.add_char normalized '\n'
  end else Buffer.add_char normalized c) raw;
  let lines = String.split_on_char '\n' (Buffer.contents normalized) in
  if line < 1 || line > List.length lines then raise (Project.Error "Invalid outline location.");
  let expected = List.nth lines (line - 1) in
  let check = String.concat " " (List.map Filename.quote
    [binary; "outline-check"; file; fingerprint]) in
  Printf.sprintf {|tell application "BBEdit"
    set d to open (POSIX file %s)
    if modified of d then error "This document has unsaved edits. Save it and run Project Outline again."
    do shell script %s
    set actualLine to contents of line %d of d as text
    if actualLine ends with linefeed then set actualLine to text 1 thru -2 of actualLine
    if actualLine ends with return then set actualLine to text 1 thru -2 of actualLine
    if actualLine is not %s then error "The editor buffer differs from the indexed source. Refresh the document and run Project Outline again."
    select insertion point before character 1 of line %d of d
    set index of window of d to 1
end tell
|} (quote file) (quote check) line (quote expected) line
