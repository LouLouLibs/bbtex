(** Per-root advisory locks and cooperative cancellation of a compiler process group. *)
exception Cancelled

let rec mkdir path =
  if not (Sys.file_exists path) then begin
    let parent = Filename.dirname path in
    if parent <> path then mkdir parent;
    try Unix.mkdir path 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let state_dir () =
  match Sys.getenv_opt "BBTEX_STATE_DIR" with
  | Some path -> path
  | None -> Filename.concat
      (Option.value ~default:(Filename.concat (Sys.getenv "HOME") ".local/state")
         (Sys.getenv_opt "XDG_STATE_HOME")) "bbtex"

let prefix root = Filename.concat (state_dir ()) ("build-" ^ Digest.to_hex (Digest.string root))
let log_path root = prefix root ^ ".log"
let active_path root = prefix root ^ ".active"
let read path =
  let ic = open_in path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () -> input_line ic)
let write path value =
  let oc = open_out path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc (value ^ "\n"))
let remove path = try Sys.remove path with Sys_error _ -> ()

type job = { control : string; log : string; cancelled : bool ref; superseded : unit -> bool }

let with_job ?(superseded = fun () -> false) root f =
  mkdir (state_dir ());
  let lock = Unix.openfile (prefix root ^ ".lock") [Unix.O_RDWR; Unix.O_CREAT] 0o600 in
  Unix.set_close_on_exec lock;
  Fun.protect ~finally:(fun () -> Unix.close lock) (fun () ->
    (try Unix.lockf lock Unix.F_TLOCK 0 with
     | Unix.Unix_error ((Unix.EACCES | Unix.EAGAIN), _, _) ->
       raise (Project.Error "This project is already building. Wait or use LaTeX — Cancel Build."));
    let control = Filename.temp_file ~temp_dir:(state_dir ()) "cancel-" ".request" in
    let active = active_path root in
    let cancelled = ref false in
    let old_signals = List.map (fun signal ->
      signal, Sys.signal signal (Sys.Signal_handle (fun _ -> cancelled := true))
    ) [Sys.sigint; Sys.sigterm; Sys.sighup] in
    Fun.protect ~finally:(fun () ->
      remove active; remove control;
      List.iter (fun (signal, handler) -> Sys.set_signal signal handler) old_signals
    ) (fun () ->
      write control "running";
      write active (Filename.basename control);
      f { control; log = log_path root; cancelled; superseded }))

let request_cancel root =
  let active = active_path root in
  if not (Sys.file_exists active) then false
  else
    try
      let name = read active in
      if Filename.basename name <> name || not (String.starts_with ~prefix:"cancel-" name)
      then false
      else
        let path = Filename.concat (state_dir ()) name in
        (* Do not recreate an old control file after the owning build exits. *)
        let fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_TRUNC] 0 in
        Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
          ignore (Unix.write_substring fd "cancel\n" 0 7));
        true
    with Sys_error _ | Unix.Unix_error (Unix.ENOENT, _, _) -> false

let cancel root =
  try
    let lock = Unix.openfile (prefix root ^ ".lock") [Unix.O_RDWR] 0 in
    Fun.protect ~finally:(fun () -> Unix.close lock) (fun () ->
      (* Test the lock without taking it, so a build starting right now does not
         see this check as another build. *)
      try Unix.lockf lock Unix.F_TEST 0; false with
      | Unix.Unix_error ((Unix.EACCES | Unix.EAGAIN), _, _) -> request_cancel root)
  with Unix.Unix_error (Unix.ENOENT, _, _) -> false

let executable command =
  let paths = String.split_on_char ':' (Option.value ~default:"/usr/bin:/bin" (Sys.getenv_opt "PATH")) in
  match List.find_opt (fun dir ->
    try Unix.access (Filename.concat dir command) [Unix.X_OK]; true with Unix.Unix_error _ -> false
  ) paths with
  | Some dir -> Unix.realpath (Filename.concat dir command)
  | None -> raise (Project.Error (command ^ " not found in PATH"))

let run job ~cwd command args =
  if job.superseded () then raise Cancelled;
  let executable = try executable command with Project.Error message as error ->
    write job.log message; raise error in
  let log = Unix.openfile job.log [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o600 in
  let heading = Printf.sprintf "Directory: %s\nCommand: %s\n\n" cwd
    (String.concat " " (command :: List.map Filename.quote args)) in
  ignore (Unix.write_substring log heading 0 (String.length heading));
  let pid = match Unix.fork () with
    | 0 ->
      (try
         ignore (Unix.setsid ());
         Unix.chdir cwd;
         let input = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
         Unix.dup2 input Unix.stdin; Unix.close input;
         Unix.dup2 log Unix.stdout; Unix.dup2 log Unix.stderr; Unix.close log;
         Unix.execv executable (Array.of_list (command :: args))
       with _ -> Unix._exit 127)
    | pid -> pid
  in
  Unix.close log;
  let signal_group signal =
    Log.info (Printf.sprintf "cancelling compiler process group %d (signal %d)" pid signal);
    try Unix.kill (-pid) signal with Unix.Unix_error (Unix.ESRCH, _, _) -> () in
  let pause () = try ignore (Unix.select [] [] [] 0.05) with Unix.Unix_error (Unix.EINTR, _, _) -> () in
  let wait flags =
    let rec go () = try Unix.waitpid flags pid with Unix.Unix_error (Unix.EINTR, _, _) -> go () in go ()
  in
  let rec poll () =
    let requested = !(job.cancelled) || job.superseded () ||
      (try read job.control = "cancel" with _ -> false) in
    if requested then begin
      (* The session leader owns the whole latexmk/TeX/BibTeX process group. *)
      signal_group Sys.sigterm;
      let deadline = Unix.gettimeofday () +. 1.0 in
      (* Stop waiting once no process in the group is alive (ESRCH, or EPERM
         when only the unreaped leader is left). *)
      let group_alive () =
        try Unix.kill (-pid) 0; true
        with Unix.Unix_error ((Unix.ESRCH | Unix.EPERM), _, _) -> false in
      let rec drain () =
        if Unix.gettimeofday () < deadline && group_alive () then (pause (); drain ())
      in
      (* Keep the session leader unreaped until after the final group signal,
         preventing its PID from being reused in the meantime. *)
      drain ();
      let reaped =
        try signal_group Sys.sigkill; false with
        | Unix.Unix_error (Unix.EPERM, _, _) as error ->
          (* Darwin can reject SIGKILL when only the dead session leader
             remains. Accept that case only if waitpid confirms it exited. *)
          if fst (wait [Unix.WNOHANG]) = pid then true else raise error
      in
      if not reaped then ignore (wait []);
      raise Cancelled
    end;
    match wait [Unix.WNOHANG] with
    | 0, _ -> pause (); poll ()
    | _, Unix.WEXITED code -> code
    | _ -> 1
  in
  poll ()
