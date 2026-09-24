(** Follow the BBEdit selection: one poller child, one debounce loop, renders
    started as detached children. Superseded renders cancel themselves through
    Snippet_page generations. *)

let read_all path = try In_channel.with_open_bin path In_channel.input_all with Sys_error _ -> ""

let lock_path () = Filename.concat (Build_job.state_dir ()) "live-selection.lock"

(* Never call this from the watcher itself: closing any descriptor of the lock
   file drops the process's lockf lock on it. *)
let with_lock_fd f =
  Build_job.mkdir (Build_job.state_dir ());
  let fd = Unix.openfile (lock_path ()) [Unix.O_CREAT; Unix.O_RDWR; Unix.O_CLOEXEC] 0o600 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () -> f fd)

let running () =
  with_lock_fd (fun fd ->
    try Unix.lockf fd Unix.F_TEST 0; false with Unix.Unix_error _ -> true)

let stop () =
  let flag = Snippet_page.live_flag () in
  (* A watcher that just took its lock writes its PID a moment later. *)
  let rec signal tries =
    match int_of_string_opt (String.trim (read_all flag)) with
    | Some pid -> (try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ())
    | None when tries > 0 && running () -> Unix.sleepf 0.05; signal (tries - 1)
    | None -> () in
  if running () then signal 20 else Build_job.remove flag

let process_start pid =
  let ic = Unix.open_process_args_in "/bin/ps" [| "/bin/ps"; "-o"; "lstart="; "-p"; string_of_int pid |] in
  let line = try String.trim (input_line ic) with End_of_file -> "" in
  ignore (Unix.close_process_in ic); line

(* The same marker the save worker honours (scripts/bbtex-preview-on-save.sh). *)
let build_paused () =
  let marker = Filename.concat (Build_job.state_dir ()) "suppress-save-preview" in
  match List.map String.trim (String.split_on_char '\n' (read_all marker)) with
  | pid :: start :: _ when int_of_string_opt pid <> None && start <> "" ->
    process_start (int_of_string pid) = start
  | pid :: _ -> (match int_of_string_opt pid with
      | Some pid -> (try Unix.kill pid 0; true with Unix.Unix_error _ -> false)
      | None -> false)
  | [] -> false

let spawn renderer (o : Live_selection.observation) =
  let null = Unix.openfile "/dev/null" [Unix.O_RDWR; Unix.O_CLOEXEC] 0 in
  Fun.protect ~finally:(fun () -> Unix.close null) (fun () ->
    ignore (Unix.create_process renderer
      [| renderer; o.source; o.window; string_of_int o.offset;
         string_of_int o.length; string_of_int o.line |] null Unix.stderr Unix.stderr))

let publish_busy (o : Live_selection.observation) =
  let token = Snippet_page.begin_request ~source:o.source ~line:o.line ~mode:"live" in
  ignore (Snippet_page.finish token ~status:"busy" ~png:"" ~log:""
    ~message:"Live preview paused while a full build runs.")

(* Collect finished renders; report whether [child] (the poller) was among them,
   so it is never signalled or waited for after its PID could be reused. *)
let rec reap child exited =
  match Unix.waitpid [Unix.WNOHANG] (-1) with
  | 0, _ -> ()
  | pid, _ -> if pid = child then exited := true; reap child exited
  | exception Unix.Unix_error (Unix.ECHILD, _, _) -> ()
  | exception Unix.Unix_error (Unix.EINTR, _, _) -> reap child exited

(* Split complete lines off [pending], keeping the unterminated tail. *)
let take_lines pending =
  let text = Buffer.contents pending in
  match String.rindex_opt text '\n' with
  | None -> []
  | Some last ->
    Buffer.clear pending;
    Buffer.add_string pending (String.sub text (last + 1) (String.length text - last - 1));
    String.split_on_char '\n' (String.sub text 0 last)

let watch ~poller ~renderer =
  with_lock_fd (fun fd ->
    (try Unix.lockf fd Unix.F_TLOCK 0
     with Unix.Unix_error _ -> raise (Project.Error "Live selection preview is already running."));
    (* Install the handler before publishing the PID, so `stop` always gets a cleanup. *)
    let stopping = ref false in
    Sys.set_signal Sys.sigterm (Sys.Signal_handle (fun _ -> stopping := true));
    let flag = Snippet_page.live_flag () in
    Build_job.write flag (string_of_int (Unix.getpid ()));
    let read_end, write_end = Unix.pipe ~cloexec:true () in
    let child = ref None and exited = ref false and write_open = ref true in
    let close_write () = if !write_open then (write_open := false; Unix.close write_end) in
    Fun.protect ~finally:(fun () ->
      (match !child with
       | Some pid when not !exited ->
         (try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ());
         (try ignore (Unix.waitpid [] pid) with Unix.Unix_error _ -> ())
       | _ -> ());
      close_write ();
      Unix.close read_end;
      Build_job.remove flag;
      Snippet_page.stop_live ~message:"Live selection preview is off.")
    (fun () ->
      let pid = Unix.create_process "/usr/bin/osascript"
        [| "/usr/bin/osascript"; poller; "0.15"; "1.0" |] Unix.stdin Unix.stdout write_end in
      child := Some pid;
      close_write ();
      let pending = Buffer.create 256 and chunk = Bytes.create 4096 in
      (* The build marker is checked a few times a second, not every tick:
         checking it runs ps while a build is active. *)
      let checked = ref neg_infinity in
      let rec loop state =
        reap pid exited;
        if !stopping then () else
        let now = Unix.gettimeofday () in
        let state = if now -. !checked < 0.25 then state else
          (checked := now; Live_selection.building state (build_paused ())) in
        let ready = try let r, _, _ = Unix.select [read_end] [] [] 0.05 in r <> []
          with Unix.Unix_error (Unix.EINTR, _, _) -> false in
        let state, open_ =
          if not ready then state, true else
          match Unix.read read_end chunk 0 (Bytes.length chunk) with
          | 0 -> state, false (* poller exited: BBEdit quit *)
          | n ->
            Buffer.add_subbytes pending chunk 0 n;
            List.fold_left (fun s line -> match Live_selection.parse_line line with
              | Some event -> Live_selection.observe s ~now event
              | None -> s) state (take_lines pending), true
          | exception Unix.Unix_error (Unix.EINTR, _, _) -> state, true in
        if not open_ || !stopping then () else
        match Live_selection.decide state ~now with
        | _, Live_selection.Stop -> ()
        | state, Live_selection.Render o -> spawn renderer o; loop state
        | state, Live_selection.Busy o -> publish_busy o; loop state
        | state, Live_selection.Wait -> loop state
      in loop (Live_selection.initial ~now:(Unix.gettimeofday ()))))
