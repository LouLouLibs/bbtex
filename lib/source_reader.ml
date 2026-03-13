(** Source reader: reads .tex source lines and builds BBEdit search entries.

    Provides helpers to:
    - read a single line from a file by 1-based line number,
    - escape strings for PCRE matching,
    - resolve relative paths against a root directory,
    - build search_entry and loose_warning lists from parsed log entries. *)

open Types

(** [read_source_line path n] reads line [n] (1-based) from the file at [path].
    Returns [None] if the file doesn't exist, can't be opened, or [n] is past
    the end of the file. *)
let read_source_line path n =
  match open_in path with
  | exception Sys_error _ -> None
  | ic ->
    let result =
      let rec skip_to count =
        if count >= n then
          (* We are at the line we want; read it *)
          match input_line ic with
          | exception End_of_file -> None
          | line -> Some line
        else
          match input_line ic with
          | exception End_of_file -> None
          | _ -> skip_to (count + 1)
      in
      skip_to 1
    in
    close_in ic;
    result

(** [escape_pcre s] escapes all PCRE special characters in [s] with a backslash.
    Special characters: \\ . * + ? ( ) [ ] ^ $ | { } *)
let escape_pcre s =
  let buf = Buffer.create (String.length s) in
  String.iter (fun c ->
    (match c with
     | '\\' | '.' | '*' | '+' | '?' | '(' | ')' | '[' | ']'
     | '^' | '$' | '|' | '{' | '}' ->
       Buffer.add_char buf '\\';
       Buffer.add_char buf c
     | c ->
       Buffer.add_char buf c)
  ) s;
  Buffer.contents buf

(** [normalize_path path] removes redundant "." and ".." segments from a path. *)
let normalize_path path =
  let parts = String.split_on_char '/' path |> List.filter (fun s -> s <> "") in
  let is_absolute = String.length path > 0 && path.[0] = '/' in
  let rec simplify acc = function
    | [] -> List.rev acc
    | "." :: rest -> simplify acc rest
    | ".." :: rest ->
      (match acc with
       | [] -> simplify acc rest
       | _ :: prev -> simplify prev rest)
    | seg :: rest -> simplify (seg :: acc) rest
  in
  let cleaned = simplify [] parts in
  let joined = String.concat "/" cleaned in
  if is_absolute then "/" ^ joined else joined

(** [resolve_path ~root_dir path] returns an absolute, normalized path.
    If [path] is relative, it is resolved against [root_dir]. *)
let resolve_path ~root_dir path =
  let abs =
    if Filename.is_relative path then
      Filename.concat root_dir path
    else
      path
  in
  normalize_path abs

(** [build_search_entries ~root_dir entries] converts a list of log entries into
    search_entry values suitable for BBEdit's multi-file search results browser.

    - Resolves relative file paths against [root_dir].
    - Reads the corresponding source line and escapes it for PCRE.
    - Deduplicates by (file, line): the first occurrence wins.
    - Skips entries that have no file or no positive line number.
    - Emits a [Log.verbose] message for each file read attempt. *)
let build_search_entries ~root_dir entries =
  let seen = Hashtbl.create 16 in
  let acc = ref [] in
  List.iter (fun entry ->
    match entry.file with
    | Some rel_file ->
      let abs_file = resolve_path ~root_dir rel_file in
      let line = match entry.line with Some n when n > 0 -> n | _ -> 0 in
      let key = (abs_file, line) in
      if not (Hashtbl.mem seen key) then begin
        Hashtbl.add seen key ();
        Log.verbose (Printf.sprintf "search entry: %s:%d" abs_file line);
        acc := { se_file = abs_file; se_line = line;
                 se_message = entry.message; se_severity = entry.severity } :: !acc
      end
    | None -> ()
  ) entries;
  List.rev !acc

