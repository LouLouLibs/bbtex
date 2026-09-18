(** Small dependency-free project configuration: .bbtex with [profile Name] sections. *)
exception Error of string

type settings = {
  file : string option;
  defaults : (string * string) list;
  profiles : (string * (string * string) list) list;
}

let empty = { file = None; defaults = []; profiles = [] }
let get key fields = List.assoc_opt key fields

let rec find_file dir =
  let candidate = Filename.concat dir ".bbtex" in
  if Sys.file_exists candidate then Some candidate
  else let parent = Filename.dirname dir in
    if parent = dir then None else find_file parent

let load dir =
  match find_file dir with
  | None -> empty
  | Some file ->
    let ic = open_in file in
    Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
      let defaults = ref [] and profiles = ref [] and section = ref None in
      let fail line message = raise (Error (Printf.sprintf "%s:%d: %s" file line message)) in
      let rec read line =
        match input_line ic with
        | exception End_of_file -> { file = Some file; defaults = List.rev !defaults;
                                     profiles = List.rev !profiles }
        | text ->
          let text = String.trim text in
          if text = "" || text.[0] = '#' || text.[0] = ';' then read (line + 1)
          else if text.[0] = '[' then begin
            if not (String.starts_with ~prefix:"[profile " text && String.ends_with ~suffix:"]" text)
            then fail line "Expected [profile Name]";
            let name = String.sub text 9 (String.length text - 10) |> String.trim in
            if name = "" || List.mem_assoc name !profiles then fail line "Empty or duplicate profile name";
            profiles := (name, []) :: !profiles;
            section := Some name;
            read (line + 1)
          end else begin
            let key, value = match String.index_opt text '=' with
              | None -> fail line "Expected key = value"
              | Some pos -> String.sub text 0 pos |> String.trim,
                  String.sub text (pos + 1) (String.length text - pos - 1) |> String.trim
            in
            let allowed = match !section with
              | None -> ["root"; "engine"; "default_profile"; "output_directory"; "options"]
              | Some _ -> ["engine"; "options"]
            in
            if not (List.mem key allowed) then fail line ("Unknown or misplaced setting: " ^ key);
            let add fields =
              if List.mem_assoc key fields then fail line ("Duplicate setting: " ^ key);
              (key, value) :: fields
            in
            (match !section with
             | None -> defaults := add !defaults
             | Some name -> profiles := List.map (fun (n, fields) ->
                 if n = name then n, add fields else n, fields) !profiles);
            read (line + 1)
          end
      in read 1)

(** Shell-like quoting for argv, with no expansion or shell execution. *)
let split_options text =
  let buffer = Buffer.create 32 in
  let output = ref [] and quote = ref None and escaped = ref false in
  let flush () = if Buffer.length buffer > 0 then begin
    output := Buffer.contents buffer :: !output; Buffer.clear buffer
  end in
  String.iter (fun c ->
    if !escaped then (Buffer.add_char buffer c; escaped := false)
    else match !quote, c with
    | Some '\'', '\'' -> quote := None
    | Some '\'', c -> Buffer.add_char buffer c
    | _, '\\' -> escaped := true
    | Some '"', '"' -> quote := None
    | Some _, c -> Buffer.add_char buffer c
    | None, ('\'' | '"') -> quote := Some c
    | None, (' ' | '\t') -> flush ()
    | None, c -> Buffer.add_char buffer c
  ) text;
  if !escaped || !quote <> None then raise (Error "Unclosed quote or escape in project options");
  flush ();
  List.rev !output

let options text =
  let args = split_options text in
  List.iter (fun arg ->
    let lower = String.lowercase_ascii arg in
    let reserved = ["-out"; "--out"; "-aux"; "--aux"; "-jobname"; "--jobname";
      "-cd"; "-pdf"; "-dvi"; "-ps"; "-xelatex"; "-lualatex"; "-synctex"; "--synctex";
      "-c"; "-gg"; "-pvc"; "-view"; "--keep-logs"] in
    if not (String.starts_with ~prefix:"-" arg) || arg = "--" ||
       List.exists (fun prefix -> String.starts_with ~prefix lower) reserved then
      raise (Error ("Option is positional or managed by bbtex: " ^ arg ^
                    ". Use project settings for engine and output directory; use --option=value for option values."))
  ) args;
  args
