let base64 text =
  let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" in
  let b = Buffer.create ((String.length text + 2) / 3 * 4) in
  let n = String.length text in
  let byte i = if i < n then Char.code text.[i] else 0 in
  let rec loop i = if i < n then begin
    let v = (byte i lsl 16) lor (byte (i+1) lsl 8) lor byte (i+2) in
    Buffer.add_char b alphabet.[(v lsr 18) land 63];
    Buffer.add_char b alphabet.[(v lsr 12) land 63];
    Buffer.add_char b (if i+1 < n then alphabet.[(v lsr 6) land 63] else '=');
    Buffer.add_char b (if i+2 < n then alphabet.[v land 63] else '=');
    loop (i+3)
  end in loop 0; Buffer.contents b

type state = {
  generation : string; revision : int; status : string; source : string;
  line : int; image : string; image_line : int; message : string; log : string;
  fingerprint : string; mode : string;
}

let empty = { generation = ""; revision = 0; status = "stale"; source = "";
  line = 0; image = ""; image_line = 0; message = "Select an equation to preview.";
  log = ""; fingerprint = ""; mode = "manual" }

let read_file path = In_channel.with_open_bin path In_channel.input_all

let directory () =
  let dir = Filename.concat (Build_job.state_dir ()) "snippet-window" in
  Build_job.mkdir dir;
  Unix.realpath dir

let page_path dir = Filename.concat dir
  ("bbtex-snippet-" ^ String.sub (Digest.to_hex (Digest.string dir)) 0 8 ^ ".html")

let atomic_write path value =
  let temporary = Filename.temp_file ~temp_dir:(Filename.dirname path) "publish-" ".tmp" in
  Fun.protect ~finally:(fun () -> Build_job.remove temporary) (fun () ->
    let oc = open_out_bin temporary in
    Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc value);
    Unix.rename temporary path)

let load dir =
  try match String.split_on_char '\000' (read_file (Filename.concat dir "state-v2")) with
    | [generation; revision; status; source; line; image; image_line; message; log; fingerprint; mode] ->
      { generation; revision = int_of_string revision; status; source; line = int_of_string line;
        image; image_line = int_of_string image_line; message; log; fingerprint; mode }
    | _ -> empty
  with Sys_error _ | Failure _ -> empty

let json text =
  let b = Buffer.create (String.length text + 2) in
  Buffer.add_char b '"';
  String.iter (function
    | '"' -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | c when Char.code c < 32 || c = '<' || c = '>' || c = '&' ->
        Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
    | c -> Buffer.add_char b c) text;
  Buffer.add_char b '"'; Buffer.contents b

let payload s = Printf.sprintf
  {|{"generation":%s,"revision":%d,"status":%s,"source":%s,"line":%d,"image":%s,"imageLine":%d,"message":%s,"log":%s}|}
  (json s.generation) s.revision (json s.status) (json s.source) s.line
  (json s.image) s.image_line (json s.message) (json s.log)

let template = {|<!doctype html>
<!-- bbtex-snippet-template:2 -->
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>LaTeX Snippet</title>
<style>body{margin:0;padding:16px;background:#f5f5f7;color:#25252a;font:13px -apple-system,sans-serif}
header{display:flex;justify-content:space-between;gap:12px;margin-bottom:8px}
#source,#message,#log{overflow-wrap:anywhere}#source{color:#686872;margin:0 0 12px}
figure{margin:0;padding:10px;background:white;border-radius:8px}img{display:block;width:100%;height:auto}
figcaption{margin-top:8px;color:#686872}body:not([data-status="current"]) img{opacity:.5}
#log{font-size:11px;color:#686872} [hidden]{display:none!important}
body[data-status="error"] #status{color:#b42318}</style></head>
<body data-status="stale"><header><strong>LaTeX Snippet</strong><span id="status" role="status">Waiting</span></header>
<p id="source"></p><figure hidden><img id="formula" alt="Rendered mathematics"><figcaption id="caption"></figcaption></figure>
<p id="message">Select an equation to preview.</p><p id="log" hidden></p>
<script>
window.bbtexSnippetVersion=3;
let revision=-1;const names={rendering:"Rendering…",current:"Current",stale:"Out of date",error:"Preview failed",busy:"Project busy"};
window.bbtexSnippet=function(s){if(s.revision<=revision)return;revision=s.revision;
const requestedRevision=revision;document.body.dataset.status=s.status;
document.getElementById("status").textContent=names[s.status]||s.status;
document.getElementById("source").textContent=s.source?(s.source.split("/").pop()+(s.line?" · line "+s.line:"")):"";
document.getElementById("source").title=s.source;
document.getElementById("message").textContent=s.message;
const log=document.getElementById("log");log.hidden=!s.log||s.status==="current";
log.textContent=s.log?"Scripts → LaTeX — Open Preview Log\n"+s.log:"";
const figure=document.querySelector("figure"),formula=document.getElementById("formula");
document.getElementById("caption").textContent=s.status==="current"?"Saved source preview":"Previous preview — out of date"+(s.imageLine?" (line "+s.imageLine+")":"");
if(!s.image){figure.hidden=true;formula.removeAttribute("src");return}
if(formula.getAttribute("src")!==s.image)figure.hidden=true;
const img=new Image();img.onload=function(){if(revision!==requestedRevision)return;formula.src=s.image;figure.hidden=false};
img.onerror=function(){if(revision!==requestedRevision)return;figure.hidden=true;document.getElementById("status").textContent="Image unavailable"};img.src=s.image};
let polling=false,fetching=false,shown="";
function add(name,done){const s=document.createElement("script");s.src=name+"?t="+Date.now();
s.onload=()=>{s.remove();done(true)};s.onerror=()=>{s.remove();done(false)};document.body.appendChild(s)}
window.bbtexRevision=function(r){if(r===shown||fetching)return;fetching=true;add("image.js",ok=>{fetching=false;if(ok)shown=r})};
function refresh(){if(polling)return;polling=true;add("revision.js",()=>{polling=false})}refresh();setInterval(refresh,250);
</script></body></html>|}

let save dir s =
  let page = page_path dir in
  if (try read_file page <> template with Sys_error _ -> true) then atomic_write page template;
  atomic_write (Filename.concat dir "state-v2") (String.concat "\000"
    [s.generation; string_of_int s.revision; s.status; s.source; string_of_int s.line;
     s.image; string_of_int s.image_line; s.message; s.log; s.fingerprint; s.mode]);
  (* The page polls the small revision.js and loads image.js, which carries the
     whole image, only when the revision changes. Pages from an older template
     still poll image.js and reload themselves into this one. *)
  let payload = payload s in
  atomic_write (Filename.concat dir "image.js")
    ("if(window.bbtexSnippetVersion===3&&window.bbtexSnippet){window.bbtexSnippet(" ^ payload ^ ");}else{location.reload();}");
  atomic_write (Filename.concat dir "revision.js")
    (Printf.sprintf "window.bbtexRevision&&window.bbtexRevision(%S);"
       (Digest.to_hex (Digest.string payload)));
  page

let with_state f =
  let dir = directory () in
  let fd = Unix.openfile (Filename.concat dir "publication.lock") [Unix.O_CREAT; Unix.O_RDWR] 0o600 in
  Unix.set_close_on_exec fd;
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
    Unix.lockf fd Unix.F_LOCK 0;
    f dir (load dir))

let fingerprint source = if source = "" then "" else
  try Digest.to_hex (Digest.file source) with Sys_error _ -> "missing"

let token dir =
  let path = Filename.temp_file ~temp_dir:dir "request-" "" in
  Build_job.remove path; Filename.basename path

let live_flag () = Filename.concat (Build_job.state_dir ()) "live-selection"

let tracking s = match s.mode with
  | "auto" -> (try read_file (Filename.concat (Build_job.state_dir ()) "preview-on-save-source") = s.source
     with Sys_error _ -> false)
  | "live" -> Sys.file_exists (live_flag ())
  | _ -> true

let is_current generation =
  try
  let s = load (directory ()) in
  generation = s.generation && tracking s && s.fingerprint = fingerprint s.source
  with Sys_error _ | Unix.Unix_error _ -> false

let begin_locked dir previous ~source ~line ~mode =
    let generation = token dir in
    let s = { generation; revision = previous.revision + 1;
      source; line; mode; status = "rendering"; fingerprint = fingerprint source;
      image = (if source = previous.source then previous.image else "");
      image_line = (if source = previous.source then previous.image_line else 0);
      message = "Rendering saved source…"; log = "" } in
    ignore (save dir s); generation

let begin_request ~source ~line ~mode =
  if not (List.mem mode ["auto"; "manual"; "live"]) || line < 0 then
    raise (Project.Error "Invalid preview request.");
  with_state (fun dir previous -> begin_locked dir previous ~source ~line ~mode)

(* A dependency's cursor must never replace the equation's saved anchor. Check
   and start under the publication lock so a concurrent source save wins cleanly. *)
let refresh_dependency saved = with_state (fun dir s ->
  if s.mode <> "auto" || not (tracking s) || s.line < 1 then None else
  let root = (Compiler.resolve_compilation s.source).root_file in
  if Preview_inputs.canonical saved <> Preview_inputs.canonical s.source &&
     not (Preview_inputs.relevant ~root saved) then None else
  if s.fingerprint <> fingerprint s.source then begin
    ignore (save dir { s with generation = token dir; revision = s.revision + 1;
      status = "stale"; message = "Equation source changed. Save with the cursor inside the equation to resume." });
    None
  end else
    let generation = begin_locked dir s ~source:s.source ~line:s.line ~mode:"auto" in
    Some (generation, s.line, s.source))

let finish generation ~status ~png ~log ~message =
  if not (List.mem status ["current"; "stale"; "error"; "busy"]) then
    raise (Project.Error "Invalid preview status.");
  with_state (fun dir s ->
    if generation <> s.generation then None else
    let changed = not (tracking s) || s.fingerprint <> fingerprint s.source in
    let status, message = if changed then "stale", "Source or tracking changed. Save an equation to refresh."
      else status, message in
    let status, message, image = if status <> "current" then status, message, s.image else
      try status, message, "data:image/png;base64," ^ base64 (read_file png)
      with Sys_error error -> "error", "Could not read rendered image: " ^ error, s.image in
    let s = { s with revision = s.revision + 1; status; message; image; log;
      image_line = (if status = "current" then s.line else s.image_line) } in
    Some (save dir s))

let stop_auto ~matches ~message = with_state (fun dir s ->
  if s.mode = "auto" && matches s.source then
    ignore (save dir { s with generation = token dir; revision = s.revision + 1;
      status = "stale"; message; log = "" }))

let stop_live ~message = with_state (fun dir s ->
  if s.mode = "live" then
    ignore (save dir { s with generation = token dir; revision = s.revision + 1;
      status = "stale"; message; log = "" }))

let log_path () = (load (directory ())).log

(* Kept for callers that publish an image without a tracked source. *)
let publish png =
  let generation = begin_request ~source:"" ~line:0 ~mode:"manual" in
  Option.value ~default:(page_path (directory ()))
    (finish generation ~status:(if png = "-" then "error" else "current") ~png ~log:""
       ~message:(if png = "-" then "Could not render the selection." else ""))
