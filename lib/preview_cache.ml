(** One cached render per root, validated against every recorded input. *)
let digest path = Digest.to_hex (if Sys.is_directory path then
    Digest.string (String.concat "\000" (Array.to_list (Sys.readdir path) |> List.sort String.compare))
  else Digest.file path)
let read path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))
let key text engine options =
  Digest.to_hex (Digest.string (String.concat "\000"
    ("png-1400-v1" :: text :: engine :: options @
     (Array.to_list (Unix.environment ()) |> List.sort String.compare))))

let valid manifest expected =
  try
    let fields = String.split_on_char '\000' (read manifest) in
    let rec check = function
      | [] -> true
      | hash :: path :: rest -> hash = digest path && check rest
      | _ -> false in
    match fields with
    | actual :: (_ :: _ :: _ as entries) -> actual = expected && check entries
    | _ -> false
  with Sys_error _ | Unix.Unix_error _ -> false

let record ~manifest ~key ~cwd ~dir ~root ~engine =
  let fls = Filename.concat dir "selection.fls" in
  try
    let dependencies = read fls |> String.split_on_char '\n'
      |> List.filter_map (fun line ->
        if not (String.starts_with ~prefix:"INPUT " line) then None else
        let path = String.sub line 6 (String.length line - 6) |> String.trim in
        let path = if Filename.is_relative path then Filename.concat cwd path else path in
        let path = Unix.realpath path in
        if String.starts_with ~prefix:(dir ^ "/") path then None else Some path)
      |> fun paths -> cwd :: root :: Build_job.executable engine :: Build_job.executable "pdftoppm" :: paths
      |> List.sort_uniq String.compare in
    let fields = key :: List.concat_map (fun path -> [digest path; path]) dependencies in
    let temporary = manifest ^ ".tmp" in
    let oc = open_out_bin temporary in
    Fun.protect ~finally:(fun () -> close_out oc)
      (fun () -> output_string oc (String.concat "\000" fields));
    Unix.rename temporary manifest
  with Sys_error _ | Unix.Unix_error _ -> Build_job.remove manifest
