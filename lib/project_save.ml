(** Which open BBEdit documents are inputs of a project, as AppleScript that
    saves them before a build or, for a preview, refuses while any is unsaved.

    A modified document counts when it is the root, a file the saved project
    actually includes (so \input{../shared/macros} counts even outside the
    project folder), or a TeX-related file inside the project folder. BBEdit
    reports resolved paths, as [Unix.realpath] does, so paths compare directly. *)

let tex_extensions = [
  ".tex"; ".bib"; ".sty"; ".cls"; ".clo"; ".cfg"; ".def"; ".fd"; ".ldf"; ".ltx";
  ".dtx"; ".ins"; ".bbx"; ".cbx"; ".lbx"; ".dbx"; ".bst"; ".tikz"; ".pgf"; ".lua" ]

(** Absolute paths of the files the saved project includes, root first. *)
let included_files (config : Types.compilation_config) =
  let listed = try List.map fst (Project_index.build config.root_file).files
    with Project.Error _ | Sys_error _ | Unix.Unix_error _ -> [] in
  List.sort_uniq compare (config.root_file :: listed)

let script ~check (config : Types.compilation_config) =
  let quote path = "\"" ^ Applescript.escape_applescript path ^ "\"" in
  let inputs = "{" ^ String.concat ", " (List.map quote (included_files config)) ^ "}" in
  let extension = String.concat " or " (List.map (fun ext ->
    "documentPath ends with " ^ quote ext) tex_extensions) in
  let action = if check
    then {|error "Save modified project inputs before previewing. Preview does not save your work automatically: " & documentPath|}
    else "save d" in
  Printf.sprintf {|tell application "BBEdit"
    set projectInputs to %s
    repeat with d in (get text documents)
        set documentPath to ""
        try
            set documentFile to get file of d
            set documentPath to POSIX path of documentFile
        end try
        if documentPath is not "" and modified of d then
            if projectInputs contains documentPath or (documentPath starts with %s and (%s)) then
                %s
            end if
        end if
    end repeat
end tell
|} inputs (quote (config.project_dir ^ "/")) extension action
