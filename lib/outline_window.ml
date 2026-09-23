(** Experimental HTML-to-native navigation proof. Sessions live in a caller-owned
    temporary directory; the existing outline menu is deliberately unchanged. *)
let html text =
  let b = Buffer.create (String.length text) in
  String.iter (function '&' -> Buffer.add_string b "&amp;" | '<' -> Buffer.add_string b "&lt;"
    | '>' -> Buffer.add_string b "&gt;" | '"' -> Buffer.add_string b "&quot;"
    | c -> Buffer.add_char b c) text; Buffer.contents b

let page ~endpoint (index : Project_index.t) =
  let rows = List.mapi (fun i (e : Project_index.entry) ->
    Printf.sprintf {|<form method="post" action="%s/jump/%d" target="feedback"><button style="margin-left:%dem" title="%s">%s</button></form>|}
      endpoint i e.depth (html e.context) (html (Project_index.display index.root e))) index.entries in
  "<!doctype html><html><head><meta charset=\"utf-8\"><title>Project Outline — prototype</title>" ^
  "<style>body{font:14px system-ui;margin:16px;color:#222;background:#fafafa}button{font:inherit;text-align:left;border:0;background:none;padding:6px;cursor:pointer}button:hover,button:focus{background:#ddeaff}iframe{border:1px solid #bbb;width:100%;height:65px}form{margin:0}header{position:sticky;top:0;background:#fafafa;padding-bottom:10px}small{display:block}</style></head><body>" ^
  "<header><h2>Project Outline · prototype</h2><small>" ^ html index.root ^
  "</small><p>Saved snapshot. Tab to an entry, then Return to open. Close the window to stop the session.</p>" ^
  "<iframe name=\"feedback\" title=\"Navigation result\" srcdoc=\"Choose a location.\"></iframe></header>" ^
  (if index.issues = [] then "" else "<p>Partial outline: " ^ html (String.concat " · " index.issues) ^ "</p>") ^
  String.concat "\n" rows ^
  "<script>const endpoint=" ^ Snippet_page.json endpoint ^ ";function pulse(){fetch(endpoint+'/ping',{mode:'no-cors',cache:'no-store'}).catch(()=>{});}pulse();setInterval(pulse,1000);</script></body></html>"

let token () =
  let ic = open_in_bin "/dev/urandom" in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
    let bytes = really_input_string ic 24 in
    String.concat "" (List.init 24 (fun i -> Printf.sprintf "%02x" (Char.code bytes.[i]))))

let run_script script =
  let file = Filename.temp_file "bbtex-outline-jump-" ".applescript" in
  Fun.protect ~finally:(fun () -> Build_job.remove file) (fun () ->
    Snippet_page.atomic_write file script;
    (* Reuse bounded process-group cleanup; osascript receives a filename, never
       source text or shell commands from an HTTP request. *)
    let result = Doctor_probe.run ~timeout:10. "/usr/bin/osascript" file in
    if result.outcome = "ok" then "Opened saved source."
    else "Navigation refused: " ^ String.trim result.output)

let open_page file =
  let executable = Build_job.executable "bbedit" in
  let pid = Unix.create_process executable [|executable; "--background"; "--preview"; file|]
      Unix.stdin Unix.stdout Unix.stderr in
  match snd (Unix.waitpid [] pid) with
  | Unix.WEXITED 0 -> () | _ -> raise (Project.Error "Could not open the outline preview.")

let window_present dir file =
  let script = Filename.concat dir "window-check.applescript" in
  Snippet_page.atomic_write script ("if application \"BBEdit\" is not running then return false\n" ^
    "tell application \"BBEdit\"\nrepeat with w in (get web_preview_windows)\nif name of w is " ^
    Outline.quote ("Preview: " ^ Filename.basename file) ^
    " then return true\nend repeat\nend tell\nreturn false\n");
  let result = Doctor_probe.run ~timeout:2. "/usr/bin/osascript" script in
  if result.outcome <> "ok" then raise (Project.Error "Could not inspect outline window lifetime.");
  String.trim result.output = "true"

let read_request fd =
  Unix.set_nonblock fd;
  let buf = Buffer.create 512 and bytes = Bytes.create 1024 in
  let deadline = Unix.gettimeofday () +. 1. in
  let rec loop () =
    if Buffer.length buf > 8192 then raise (Failure "request too large");
    if Doctor.contains (Buffer.contents buf) "\r\n\r\n" then Buffer.contents buf else
    let remaining = deadline -. Unix.gettimeofday () in
    if remaining <= 0. then raise (Failure "request timeout");
    let ready, _, _ = Unix.select [fd] [] [] remaining in
    if ready = [] then raise (Failure "request timeout");
    let n = Unix.read fd bytes 0 (Bytes.length bytes) in
    if n = 0 then raise End_of_file;
    Buffer.add_subbytes buf bytes 0 n; loop ()
  in loop ()

let authorized ~host headers =
  let field name = List.find_map (fun line ->
    match String.index_opt line ':' with
    | Some i when String.lowercase_ascii (String.sub line 0 i) = name ->
      Some (String.trim (String.sub line (i+1) (String.length line-i-1)))
    | _ -> None) headers in
  field "host" = Some host &&
  (match field "origin" with None | Some "null" -> true | _ -> false)

let route ~secret ~count meth target =
  if meth = "GET" && target = "/" ^ secret ^ "/ping" then `Ping else
  let prefix = "/" ^ secret ^ "/jump/" in
  if meth = "POST" && String.starts_with ~prefix target then
    let value = String.sub target (String.length prefix) (String.length target - String.length prefix) in
    match int_of_string_opt value with
    | Some i when i >= 0 && i < count && string_of_int i = value -> `Jump i
    | _ -> `Reject
  else `Reject

let respond fd code body =
  let text = Printf.sprintf "HTTP/1.1 %s\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: %d\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n%s"
      code (String.length body) body in
  (* Responses are small and the socket stays nonblocking: a stalled peer never
     holds the session open. *)
  let rec write pos = if pos < String.length text then
    let n = Unix.write_substring fd text pos (String.length text - pos) in
    if n > 0 then write (pos+n) in write 0

let run ?(launch=true) source dir =
  let dir = Unix.realpath dir in
  let stat = Unix.stat dir in
  if stat.Unix.st_kind <> Unix.S_DIR || stat.st_uid <> Unix.getuid () || stat.st_perm land 0o077 <> 0
  then raise (Project.Error "Use a private temporary session directory (mktemp -d).");
  let page_file = Filename.concat dir
    ("bbtex-outline-" ^ String.sub (Digest.to_hex (Digest.string dir)) 0 8 ^ ".html") in
  let lock = Unix.openfile (Filename.concat dir "session.lock") [Unix.O_RDWR; Unix.O_CREAT] 0o600 in
  Unix.set_close_on_exec lock;
  Fun.protect ~finally:(fun () -> Unix.close lock) (fun () ->
    let owner = try Unix.lockf lock Unix.F_TLOCK 0; true with
      Unix.Unix_error ((Unix.EACCES | Unix.EAGAIN), _, _) -> false in
    if not owner then begin
      let root = (Compiler.resolve_compilation source).root_file in
      if Build_job.read (Filename.concat dir "root") <> root then
        raise (Project.Error "This session belongs to a different project. Use a new temporary directory.");
      if launch then open_page page_file;
      Printf.printf "status: reused\npage: %s\n%!" page_file
    end else begin
      let index = Project_index.build source in
      let entries = Array.of_list index.entries in
      let sock = Unix.socket ~cloexec:true Unix.PF_INET Unix.SOCK_STREAM 0 in
      Fun.protect ~finally:(fun () -> Unix.close sock; Build_job.remove page_file;
        Build_job.remove (Filename.concat dir "root");
        Build_job.remove (Filename.concat dir "window-check.applescript")) (fun () ->
        Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, 0)); Unix.listen sock 4;
        let port = match Unix.getsockname sock with Unix.ADDR_INET (_, p) -> p | _ -> assert false in
        let secret = token () in
        let host = Printf.sprintf "127.0.0.1:%d" port in
        let endpoint = "http://" ^ host ^ "/" ^ secret in
        Build_job.write (Filename.concat dir "root") index.root;
        Snippet_page.atomic_write page_file (page ~endpoint index);
        Printf.printf "page: %s\nendpoint: %s\n%!" page_file endpoint;
        if launch then open_page page_file;
        let stop = ref false and last = ref (Unix.gettimeofday () +. 20.) in
        let connected = ref false in
        let seen_window = ref false and next_window_check = ref 0. in
        let old = List.map (fun signal -> signal, Sys.signal signal (Sys.Signal_handle (fun _ -> stop := true)))
          [Sys.sigterm; Sys.sigint] in
        let old_pipe = Sys.signal Sys.sigpipe Sys.Signal_ignore in
        Fun.protect ~finally:(fun () -> Sys.set_signal Sys.sigpipe old_pipe;
          List.iter (fun (s,h) -> Sys.set_signal s h) old) (fun () ->
          while not !stop && Unix.gettimeofday () -. !last < 10. do
            try
              if launch && Unix.gettimeofday () >= !next_window_check then begin
                next_window_check := Unix.gettimeofday () +. 2.;
                if window_present dir page_file then begin
                  seen_window := true; last := Unix.gettimeofday ()
                end else if !seen_window then stop := true
              end;
              let ready, _, _ = Unix.select [sock] [] [] 0.25 in
              if ready <> [] then begin
                let fd, _ = Unix.accept ~cloexec:true sock in
                Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
                  try
                    let lines = String.split_on_char '\n' (read_request fd) |> List.map String.trim in
                    match lines with
                    | first :: headers when authorized ~host headers ->
                      (match String.split_on_char ' ' first with
                       | [meth; target; "HTTP/1.1"] ->
                         (match route ~secret ~count:(Array.length entries) meth target with
                          | `Ping ->
                            if not !connected then Printf.printf "page-connected: true\n%!";
                            connected := true;
                            last := Unix.gettimeofday (); respond fd "200 OK" "alive"
                          | `Jump i ->
                            let e = entries.(i) in
                            let message = try
                              run_script (Outline.jump ~binary:(Unix.realpath Sys.executable_name) e.file e.fingerprint e.line)
                              with Project.Error message -> "Navigation refused: " ^ message in
                            last := Unix.gettimeofday (); respond fd "200 OK" message
                          | `Reject -> respond fd "403 Forbidden" "Unknown request.")
                       | _ -> respond fd "400 Bad Request" "Malformed request.")
                    | _ -> respond fd "403 Forbidden" "Unknown origin."
                  with _ -> ())
              end
            with Unix.Unix_error (Unix.EINTR, _, _) -> ()
          done))
    end)
