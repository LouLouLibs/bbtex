(** Persist recorder inputs independently of the disposable render cache. *)
let canonical path = try Unix.realpath path with Unix.Unix_error _ -> path
let directory root = Filename.concat (Build_job.state_dir ())
  ("preview-" ^ Digest.to_hex (Digest.string (canonical root)))

let path root = Filename.concat (directory root) "tracked.inputs"
let read root =
  try String.split_on_char '\000' (Preview_cache.read (path root))
  with Sys_error _ -> []

let relevant ~root saved =
  List.mem (canonical saved) (List.map canonical (root :: read root))

let record ~root ~dir ~success =
  try
    let inputs = Preview_cache.inputs ~cwd:(Filename.dirname root) ~dir in
    let inputs = root :: inputs @ (if success then [] else read root)
      |> List.sort_uniq String.compare in
    let target = path root in
    let temporary = Filename.temp_file ~temp_dir:dir "inputs-" ".tmp" in
    Fun.protect ~finally:(fun () -> Build_job.remove temporary) (fun () ->
      Build_job.write temporary (String.concat "\000" inputs);
      Unix.rename temporary target)
  with Sys_error _ | Unix.Unix_error _ -> ()
