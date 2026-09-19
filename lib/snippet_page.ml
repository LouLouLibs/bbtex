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

let publish png =
  let dir = Filename.concat (Build_job.state_dir ()) "snippet-window" in
  Build_job.mkdir dir;
  let dir = Unix.realpath dir in
  let page = Filename.concat dir ("bbtex-snippet-" ^ String.sub (Digest.to_hex (Digest.string dir)) 0 8 ^ ".html") in
  if not (Sys.file_exists page) then Build_job.write page {|<!doctype html>
<html><head><meta charset="utf-8"><title>LaTeX Snippet</title>
<style>body{margin:0;padding:16px;background:#f5f5f7;color:#25252a;font:13px -apple-system,sans-serif}
header{margin-bottom:12px}figure{margin:0;padding:10px;background:white;border-radius:8px}
img{display:block;width:100%;height:auto}small{color:#686872;float:right}</style></head>
<body><header><strong>LaTeX Snippet</strong><small id="status">Selection preview</small></header>
<figure><img id="formula" alt="Rendered mathematics"></figure>
<script>let current="";window.showSnippet=function(data){if(data===current)return;
const image=new Image();image.onload=function(){document.getElementById("formula").src=data;document.getElementById("status").textContent="Selection preview";current=data};image.src=data};
window.snippetFailed=function(){current="";const img=document.getElementById("formula");img.removeAttribute("src");img.alt="Preview failed — see the compiler log";document.getElementById("status").textContent="Could not render"};
function refresh(){const s=document.createElement("script");s.src="image.js?t="+Date.now();
s.onload=s.onerror=()=>s.remove();document.body.appendChild(s)}refresh();setInterval(refresh,250);
</script></body></html>|};
  let script = if png = "-" then "snippetFailed();" else
    "showSnippet(\"data:image/png;base64," ^ base64 (Preview.read_file png) ^ "\");" in
  let temporary = Filename.temp_file ~temp_dir:dir "image-" ".js" in
  Build_job.write temporary script;
  Unix.rename temporary (Filename.concat dir "image.js");
  page
