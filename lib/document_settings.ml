(** Prepare a guarded editor edit; never write the source behind BBEdit's back. *)
let relative_path ~source target =
  let parts = String.split_on_char '/' in
  let rec drop a b = match a, b with
    | x :: xs, y :: ys when x = y -> drop xs ys
    | a, b -> List.map (fun _ -> "..") a @ b
  in
  String.concat "/" (drop (parts (Filename.dirname source)) (parts target))

let update text ~engine ~root =
  let newline = if String.contains text '\r' then "\r\n" else "\n" in
  let lines = String.split_on_char '\n' text in
  let kept = List.mapi (fun i line ->
    let remove = i < Directive_parser.max_lines &&
      match Directive_parser.parse_directive_line line with
      | Some { key = Types.Program; _ } -> true
      | Some { key = Types.Root; _ } -> root <> None
      | _ -> false
    in if remove then None else Some line) lines |> List.filter_map Fun.id in
  let header = (match root with None -> [] | Some p -> ["%!TEX root = " ^ p]) @
    (if engine = "inherit" then [] else ["%!TEX program = " ^ engine]) in
  String.concat "" (List.map (fun line -> line ^ newline) header) ^ String.concat "\n" kept

let script source engine root =
  let source = Compiler.canonical source in
  if engine <> "inherit" then ignore (Compiler.strict_engine engine);
  let root = if root = "-" then None else begin
    let target = Compiler.canonical root in
    if target <> source && (Compiler.resolve_compilation target).root_file = source then
      raise (Project.Error "That main file points back to this document.");
    Some (relative_path ~source target)
  end in
  let ic = open_in_bin source in
  let original = Fun.protect ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic)) in
  let updated = update original ~engine ~root in
  let esc = Applescript.escape_applescript in
  Printf.sprintf {|tell application "BBEdit"
    set d to open (POSIX file "%s")
    if (text of d as text) is not "%s" then error "Document changed during setup. Please try again."
    set text of d to "%s"
    activate
end tell
|} (esc source) (esc original) (esc updated)
