(** Persistent saved-source outline. The original picker remains available. *)
let html text =
  let b = Buffer.create (String.length text) in
  String.iter (function '&' -> Buffer.add_string b "&amp;" | '<' -> Buffer.add_string b "&lt;"
    | '>' -> Buffer.add_string b "&gt;" | '"' -> Buffer.add_string b "&quot;"
    | c -> Buffer.add_char b c) text; Buffer.contents b

type node = { number : int; entry : Project_index.entry; children : node list }

let tree entries =
  let rec siblings depth = function
    | (number, (entry : Project_index.entry)) :: rest when entry.depth >= depth ->
      let children, rest = siblings (entry.depth + 1) rest in
      let following, rest = siblings depth rest in
      {number; entry; children} :: following, rest
    | rest -> [], rest
  in fst (siblings 0 (List.mapi (fun i e -> i, e) entries))

let stable_keys entries =
  let counts = Hashtbl.create 32 in
  List.map (fun (e : Project_index.entry) ->
    let base = Digest.to_hex (Digest.string (String.concat "\000" [e.file; e.kind; e.title; e.context])) in
    let occurrence = Option.value ~default:0 (Hashtbl.find_opt counts base) in
    Hashtbl.replace counts base (occurrence + 1);
    base ^ "-" ^ string_of_int occurrence) entries

let page ?(revision=0) ~endpoint (index : Project_index.t) =
  let keys = Array.of_list (stable_keys index.entries) in
  let rec row {number; entry=e; children} =
    let button = Printf.sprintf {|<button type="button" data-entry="%d" title="%s">%s</button>|}
      number (html e.context) (html (Project_index.display index.root e)) in
    let content = match children with
      | [] -> button
      | children -> "<details open><summary>" ^ button ^ "</summary><ul>" ^
        String.concat "\n" (List.map row children) ^ "</ul></details>" in
    Printf.sprintf {|<li data-key="%s" data-search="%s">%s</li>|}
      keys.(number) (html (String.concat " " [e.kind; e.title; e.file; e.context])) content
  in
  let rows = List.map row (tree index.entries) in
  "<!doctype html><html><head><meta charset=\"utf-8\"><title>Project Outline</title>" ^
  "<style>body{font:14px system-ui;margin:16px;color:#222;background:#fafafa}button{font:inherit;text-align:left;border:0;background:none;padding:6px;cursor:pointer}button:hover,button:focus{background:#ddeaff}iframe{border:1px solid #bbb;width:100%;height:65px}form{margin:0}header{position:sticky;top:0;background:#fafafa;padding-bottom:10px}small{display:block}</style></head><body>" ^
  "<style>ul{list-style:none;padding-left:20px;margin:0}#outline{padding-left:0}li[hidden]{display:none}summary{cursor:pointer}summary button{max-width:calc(100% - 24px)}button{overflow-wrap:anywhere}input{font:inherit;padding:6px;width:calc(100% - 16px)}button[aria-current=true]{background:#ddeaff}small{overflow-wrap:anywhere}</style>" ^
  "<header><h2>Project Outline</h2><small>" ^ html index.root ^
  "</small><p>Saved sources only. Tab to an entry, then Return to open. Close the window to stop the session.</p><button type=\"button\" id=\"refresh\">Refresh saved outline</button>" ^
  "<label for=\"search\">Search outline</label><input id=\"search\" type=\"search\" placeholder=\"Heading, label, context or file\"><p id=\"matches\" role=\"status\"></p>" ^
  "<p id=\"feedback\" role=\"status\" aria-live=\"polite\">Connecting to outline session…</p></header>" ^
  "<p id=\"issues\">" ^ (if index.issues = [] then "" else "Partial outline: " ^ html (String.concat " · " index.issues)) ^ "</p>" ^
  Printf.sprintf "<ul id=\"outline\" data-revision=\"%d\">" revision ^ String.concat "\n" rows ^ "</ul>" ^
  "<script>const endpoint=" ^ Snippet_page.json endpoint ^ {|;
const feedback=document.getElementById('feedback');
const search=document.getElementById('search');
let items=Array.from(document.querySelectorAll('#outline li'));
let branches=Array.from(document.querySelectorAll('#outline details'));
const key=element=>element.closest('li').dataset.key;
const normalize=text=>text.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
let savedExpansion=null;
function filter(){
  const query=normalize(search.value.trim());
  if(query && savedExpansion===null)savedExpansion=new Set(branches.filter(b=>b.open).map(key));
  const matches=items.filter(item=>!query || normalize(item.dataset.search).includes(query));
  const visible=new Set(matches);
  matches.forEach(item=>{for(let parent=item.parentElement.closest('li');parent;parent=parent.parentElement.closest('li'))visible.add(parent);});
  items.forEach(item=>{item.hidden=!visible.has(item);});
  if(query)branches.forEach(branch=>{branch.open=true;});
  else if(savedExpansion!==null){branches.forEach(branch=>{branch.open=savedExpansion.has(key(branch));});savedExpansion=null;}
  document.getElementById('matches').textContent=query ? matches.length+' matching entries' : items.length+' entries';
}
search.addEventListener('input',filter);
search.addEventListener('keydown',event=>{
  if(event.key==='Escape'){search.value='';filter();}
  if(event.key==='Enter'){
    const match=items.find(item=>!item.hidden && normalize(item.dataset.search).includes(normalize(search.value.trim())));
    if(match){const button=match.querySelector('button[data-entry]');button.focus();button.click();}
  }
});
filter();
fetch(endpoint+'/ping',{method:'POST',mode:'cors',credentials:'omit',cache:'no-store'})
  .then(response=>{if(!response.ok)throw new Error('Session unavailable');return response.text();})
  .then(()=>fetch(endpoint+'/ready',{method:'POST',mode:'cors',credentials:'omit',cache:'no-store'}))
  .then(response=>{if(!response.ok)throw new Error('Session unavailable');feedback.textContent='Connected. Choose a location.';})
  .catch(()=>{feedback.textContent='Connection failed. Reopen the outline session.';});
let navigating=false;
function bindEntries(){document.querySelectorAll('button[data-entry]').forEach(button=>{
  button.addEventListener('click',async(event)=>{
    event.preventDefault();event.stopPropagation();
    if(navigating)return;
    navigating=true;
    feedback.textContent='Opening saved source…';
    try{
      const response=await fetch(endpoint+'/jump/'+document.getElementById('outline').dataset.revision+'/'+button.dataset.entry,
        {method:'POST',mode:'cors',credentials:'omit',cache:'no-store'});
      const message=await response.text();
      feedback.textContent=message;
      if(message==='Opened saved source.'){
        document.querySelectorAll('button[aria-current]').forEach(item=>item.removeAttribute('aria-current'));
        button.setAttribute('aria-current','true');
      }
    }catch(error){
      feedback.textContent='Navigation unavailable. Reopen the outline session.';
    }finally{navigating=false;}
  });
});}
bindEntries();
async function refresh(automatic=false){
  if(navigating)return;
  navigating=true;
  if(!automatic)feedback.textContent='Refreshing saved sources…';
  try{
    const response=await fetch(endpoint+(automatic?'/poll/'+document.getElementById('outline').dataset.revision:'/refresh'),{method:'POST',mode:'cors',credentials:'omit',cache:'no-store'});
    if(response.status===204)return;
    const text=await response.text();
    if(!response.ok)throw new Error(text);
    const updated=new DOMParser().parseFromString(text,'text/html');
    const expansion=savedExpansion || new Set(branches.filter(b=>b.open).map(key));
    const known=new Set(branches.map(key));
    const selected=document.querySelector('button[aria-current]');
    const selectedKey=selected ? key(selected) : null;
    const scroll=window.scrollY;
    document.getElementById('outline').replaceWith(updated.getElementById('outline'));
    document.getElementById('issues').textContent=updated.getElementById('issues').textContent;
    items=Array.from(document.querySelectorAll('#outline li'));
    branches=Array.from(document.querySelectorAll('#outline details'));
    branches.forEach(branch=>{branch.open=!known.has(key(branch)) || expansion.has(key(branch));});
    savedExpansion=null;
    items.forEach(item=>{if(item.dataset.key===selectedKey)item.querySelector('button[data-entry]').setAttribute('aria-current','true');});
    bindEntries();filter();window.scrollTo(0,scroll);
    feedback.textContent=(automatic?'Updated automatically':'Refreshed')+' from saved sources. Unsaved edits are not included.';
    await fetch(endpoint+'/applied/'+document.getElementById('outline').dataset.revision,
      {method:'POST',mode:'cors',credentials:'omit',cache:'no-store'});
  }catch(error){feedback.textContent='Refresh failed: '+error.message;}
  finally{navigating=false;}
}
document.getElementById('refresh').addEventListener('click',()=>refresh());
setInterval(()=>refresh(true),2000);
function pulse(){fetch(endpoint+'/ping',{mode:'no-cors',cache:'no-store'}).catch(()=>{});}
pulse();setInterval(pulse,1000);</script></body></html>|}

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
    else if Doctor.contains result.output "This document has unsaved edits." then
      "Navigation refused: This document has unsaved edits. Save it in BBEdit, then click Refresh saved outline and try again."
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

let field name headers = List.find_map (fun line ->
    match String.index_opt line ':' with
    | Some i when String.lowercase_ascii (String.sub line 0 i) = name ->
      Some (String.trim (String.sub line (i+1) (String.length line-i-1)))
    | _ -> None) headers

let authorized ~host headers =
  field "host" headers = Some host &&
  (match field "origin" headers with
   | None | Some "null" | Some "x-bbedit-preview://" -> true
   | _ -> false)

let route ?(revision=0) ~secret ~count meth target =
  if (meth = "GET" || meth = "POST") && target = "/" ^ secret ^ "/ping" then `Ping else
  if meth = "POST" && target = "/" ^ secret ^ "/ready" then `Ready else
  if meth = "POST" && target = "/" ^ secret ^ "/refresh" then `Refresh else
  if meth = "POST" && target = "/" ^ secret ^ "/applied/" ^ string_of_int revision then `Applied else
  let poll = "/" ^ secret ^ "/poll/" in
  if meth = "POST" && String.starts_with ~prefix:poll target then
    let value = String.sub target (String.length poll) (String.length target - String.length poll) in
    (match int_of_string_opt value with
     | Some n when n >= 0 && string_of_int n = value -> `Poll n
     | _ -> `Reject)
  else
  let prefix = "/" ^ secret ^ "/jump/" ^ string_of_int revision ^ "/" in
  if meth = "POST" && String.starts_with ~prefix target then
    let value = String.sub target (String.length prefix) (String.length target - String.length prefix) in
    match int_of_string_opt value with
    | Some i when i >= 0 && i < count && string_of_int i = value -> `Jump i
    | _ -> `Reject
  else `Reject

let respond ?(origin="null") fd code body =
  let text = Printf.sprintf "HTTP/1.1 %s\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: %s\r\nVary: Origin\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n%s"
      code (String.length body) origin body in
  (* Refreshed outlines can exceed the socket buffer. Bound the whole write so
     slow readers neither truncate normal responses nor hold the worker open. *)
  let deadline = Unix.gettimeofday () +. 2. in
  let rec write pos = if pos < String.length text then
    let remaining = deadline -. Unix.gettimeofday () in
    if remaining <= 0. then failwith "response timeout";
    let _, ready, _ = Unix.select [] [fd] [] remaining in
    if ready = [] then failwith "response timeout";
    try
      let n = Unix.write_substring fd text pos (String.length text - pos) in
      if n = 0 then raise End_of_file else write (pos+n)
    with Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> write pos
  in write 0

let stamps (index : Project_index.t) =
  List.map (fun (path, _) -> path, try
    let s = Unix.stat path in Some (s.st_mtime, s.st_ctime, s.st_size, s.st_ino)
    with Unix.Unix_error _ -> None) index.files

let run ?(launch=true) ?(on_ready=fun () -> ()) source dir =
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
      on_ready ();
      Printf.printf "status: reused\npage: %s\n%!" page_file
    end else begin
      let index = Project_index.build source in
      let current = ref index in
      let watched = ref (stamps index) and last_scan = ref (Unix.gettimeofday ()) in
      let entries = ref (Array.of_list index.entries) and revision = ref 0 in
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
        if launch then begin
          let deadline = Unix.gettimeofday () +. 5. in
          let rec wait () =
            if window_present dir page_file then ()
            else if Unix.gettimeofday () >= deadline then
              raise (Project.Error "Outline preview window did not appear.")
            else begin ignore (Unix.select [] [] [] 0.05); wait () end
          in wait ()
        end;
        on_ready ();
        let stop = ref false and last = ref (Unix.gettimeofday () +. 20.) in
        let connected = ref false in
        let seen_window = ref launch and next_window_check = ref 0. in
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
                      let respond = respond ~origin:(Option.value ~default:"null" (field "origin" headers)) in
                      (match String.split_on_char ' ' first with
                       | [meth; target; "HTTP/1.1"] ->
                         (match route ~revision:!revision ~secret ~count:(Array.length !entries) meth target with
                          | (`Refresh | `Poll _) as action ->
                            (try
                              let before = stamps !current in
                              let now = Unix.gettimeofday () in
                              let unchanged = match action with `Poll _ ->
                                before = !watched && (!current).issues = [] && now -. !last_scan < 30.
                                | _ -> false in
                              let updated = if unchanged then !current else Project_index.build index.root in
                              if not unchanged then begin watched := before; last_scan := now end;
                              if updated.root <> index.root then
                                raise (Project.Error "Project root changed. Open a new outline session.");
                              if action = `Poll !revision && updated = !current then
                                respond fd "204 No Content" ""
                              else begin
                              let next = if updated = !current then !revision else !revision + 1 in
                              let body = page ~revision:next ~endpoint updated in
                              current := updated;
                              entries := Array.of_list updated.entries; revision := next;
                              last := Unix.gettimeofday (); respond fd "200 OK" body
                              end
                            with Project.Error message | Sys_error message ->
                              respond fd "500 Internal Server Error" message)
                          | `Applied ->
                            Printf.printf "snapshot-applied: %d\n%!" !revision;
                            respond fd "200 OK" "applied"
                          | `Ready ->
                            Printf.printf "page-ready: true\n%!";
                            last := Unix.gettimeofday (); respond fd "200 OK" "ready"
                          | `Ping ->
                            if not !connected then Printf.printf "page-connected: true\n%!";
                            connected := true;
                            last := Unix.gettimeofday (); respond fd "200 OK" ("alive " ^ string_of_int !revision)
                          | `Jump i ->
                            let e = (!entries).(i) in
                            let message = try
                              run_script (Outline.jump ~binary:(Unix.realpath Sys.executable_name) e.file e.fingerprint e.line)
                              with Project.Error message -> "Navigation refused: " ^ message in
                            last := Unix.gettimeofday (); respond fd "200 OK" message
                          | `Reject -> respond fd "403 Forbidden" "Unknown request.")
                       | _ -> respond fd "400 Bad Request" "Malformed request.")
                    | _ -> respond fd "403 Forbidden" "Unknown origin."
                  with error -> Printf.eprintf "outline-request-error: %s\n%!" (Printexc.to_string error))
              end
            with Unix.Unix_error (Unix.EINTR, _, _) -> ()
          done))
    end)

(* Sessions are pinned to canonical project roots. Launching another project
   never repurposes an existing window or silently changes its search state. *)
let session_dir root =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
    (Printf.sprintf "bbtex-outline-%d-%s" (Unix.getuid ()) (Digest.to_hex (Digest.string root))) in
  (try Unix.mkdir dir 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let s = Unix.lstat dir in
  if s.st_kind <> Unix.S_DIR || s.st_uid <> Unix.getuid () || s.st_perm land 0o077 <> 0 then
    raise (Project.Error "Outline session directory is not private.");
  dir

let launch source =
  let root = (Compiler.resolve_compilation source).root_file in
  let dir = session_dir root in
  let reader, writer = Unix.pipe ~cloexec:true () in
  match Unix.fork () with
  | 0 ->
    Unix.close reader;
    ignore (Unix.setsid ());
    let log = Unix.openfile (Filename.concat dir "session.log")
      [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_APPEND] 0o600 in
    let input = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
    Unix.dup2 input Unix.stdin; Unix.close input;
    Unix.dup2 log Unix.stdout; Unix.dup2 log Unix.stderr; Unix.close log;
    let reported = ref false in
    let report message = if not !reported then begin
      reported := true;
      let bytes = Bytes.of_string message in
      ignore (Unix.write writer bytes 0 (Bytes.length bytes)); Unix.close writer
    end in
    (try run ~on_ready:(fun () -> report "ready") root dir; exit 0
     with error -> report (Printexc.to_string error); exit 1)
  | pid ->
    Unix.close writer;
    Fun.protect ~finally:(fun () -> Unix.close reader) (fun () ->
      let ready, _, _ = Unix.select [reader] [] [] 20. in
      if ready = [] then begin
        Unix.kill pid Sys.sigterm; ignore (Unix.waitpid [] pid);
        raise (Project.Error "Timed out opening the outline window.")
      end;
      let bytes = Bytes.create 4096 in
      let n = Unix.read reader bytes 0 (Bytes.length bytes) in
      let message = Bytes.sub_string bytes 0 n in
      if message <> "ready" then begin
        ignore (Unix.waitpid [] pid);
        raise (Project.Error ("Could not open outline: " ^ message))
      end;
      ignore (Unix.waitpid [Unix.WNOHANG] pid);
      Printf.printf "Outline opened for %s\nsession: %s\n%!" root dir)
