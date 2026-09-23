(** Bounded version queries. Child tools may initialize their own caches. *)
type result = { outcome : string; output : string }
let run ?(timeout=3.) executable argument =
  let reader, writer = Unix.pipe ~cloexec:true () in
  match (try Unix.fork () with exn -> Unix.close reader; Unix.close writer; raise exn) with
  | 0 ->
    (try
       Unix.close reader;
       ignore (Unix.setsid ());
       let null = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
       Unix.dup2 null Unix.stdin; Unix.close null;
       Unix.dup2 writer Unix.stdout; Unix.dup2 writer Unix.stderr; Unix.close writer;
       Unix.execv executable [|executable; argument|]
     with _ -> Unix._exit 127)
  | pid ->
    Unix.close writer; Unix.set_nonblock reader;
    let output = Buffer.create 1024 and bytes = Bytes.create 4096 in
    let started = Unix.gettimeofday () and status = ref None and eof = ref false in
    let stop = ref None in
    let kill () =
      (try Unix.kill (-pid) Sys.sigkill with Unix.Unix_error _ -> ());
      if !status = None then (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ()) in
    Fun.protect ~finally:(fun () ->
      kill (); Unix.close reader;
      if !status = None then (try ignore (Unix.waitpid [] pid) with Unix.Unix_error _ -> ())) (fun () ->
      while !stop = None && not (!eof && !status <> None) do
        if Unix.gettimeofday () -. started >= timeout then
          stop := Some (Printf.sprintf "timed out after %g seconds" timeout)
        else begin
          if !status = None then begin
            let waited, value = Unix.waitpid [Unix.WNOHANG] pid in
            if waited <> 0 then status := Some value
          end;
          let ready, _, _ = Unix.select (if !eof then [] else [reader]) [] [] 0.02 in
          if ready <> [] then
            try
              let count = Unix.read reader bytes 0 (Bytes.length bytes) in
              if count = 0 then eof := true
              else if Buffer.length output + count > 16384 then stop := Some "output exceeded 16 KiB"
              else Buffer.add_subbytes output bytes 0 count
            with Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> ()
        end
      done;
      let outcome = match !stop, !status with
        | Some message, _ -> message
        | None, Some (Unix.WEXITED 0) -> "ok"
        | None, Some (Unix.WEXITED n) -> Printf.sprintf "exit %d" n
        | _ -> "terminated by signal" in
      { outcome; output = Buffer.contents output })
let summary text =
  text |> String.split_on_char '\n' |> List.map String.trim
  |> List.filter (fun s -> s <> "")
  |> (function [] -> "No version text returned" | first :: _ ->
      let first = String.map (fun c -> if Char.code c < 32 || Char.code c = 127 then ' ' else c) first in
      if String.length first > 240 then String.sub first 0 240 ^ "…" else first)
