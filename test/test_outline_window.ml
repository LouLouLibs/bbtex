open Bbtex
let benchmark () =
  let dir = Filename.temp_file "bbtex-outline-bench-" "" in
  Sys.remove dir; Unix.mkdir dir 0o700;
  let files = ref [] in
  let write name body =
    let path = Filename.concat dir name in files := path :: !files;
    let oc = open_out path in output_string oc body; close_out oc; path in
  Fun.protect ~finally:(fun () -> List.iter Sys.remove !files; Unix.rmdir dir) (fun () ->
    let inputs = List.init 120 (fun i ->
      let name = Printf.sprintf "chapter-%03d.tex" i in
      ignore (write name (String.concat "\n" (List.init 40 (fun j ->
        Printf.sprintf "\\section{Chapter %d heading %d}\n\\label{sec:%d:%d}\nSome saved source text.\n" i j i j))));
      "\\input{" ^ name ^ "}") in
    let source = write "main.tex" ("\\documentclass{article}\n\\begin{document}\n" ^
      String.concat "\n" inputs ^ "\n\\end{document}\n") in
    let start = Unix.gettimeofday () in
    let index = Project_index.build source in
    let built = Unix.gettimeofday () in
    let page = Outline_window.page ~endpoint:"http://127.0.0.1:1/test" index in
    Printf.printf "Outline benchmark: %d files, %d entries, index %.3fs, HTML %.3fs, %d bytes\n%!"
      (List.length index.files) (List.length index.entries) (built -. start)
      (Unix.gettimeofday () -. built) (String.length page);
    let start = Unix.gettimeofday () in
    for _ = 1 to 100 do ignore (Outline_window.stamps index) done;
    Printf.printf "Idle metadata check: %.3f ms average\n%!" ((Unix.gettimeofday () -. start) *. 10.))

let () =
  if Sys.getenv_opt "BBTEX_OUTLINE_BENCH" = Some "1" then benchmark ();
  let entry depth title : Project_index.entry =
    {kind="section"; title; file="/tmp/paper.tex"; line=1; depth; context=""; fingerprint="test"} in
  let entries = [entry 0 "First"; entry 1 "Child"; entry 2 "Label";
                 entry 1 "Sibling"; entry 0 "Second"; entry 3 "Skipped level"] in
  (match Outline_window.tree entries with
   | [{number=0; children=[{number=1; children=[{number=2; children=[]; _}]; _};
                          {number=3; children=[]; _}]; _};
      {number=4; children=[{number=5; children=[]; _}]; _}] -> ()
   | _ -> failwith "Outline hierarchy lost a sibling or parent");
  assert (Outline_window.tree [] = []);
  let original = entry 0 "Stable" in
  assert (Outline_window.stable_keys [original] =
          Outline_window.stable_keys [{original with line=80; fingerprint="changed"}]);
  (match Outline_window.stable_keys [original; original] with
   | [first; second] -> assert (first <> second)
   | _ -> assert false);
  assert (Outline_window.route ~revision:1 ~secret:"token" ~count:2 "POST" "/token/jump/0/1" = `Reject);
  assert (Outline_window.route ~revision:1 ~secret:"token" ~count:2 "POST" "/token/jump/1/1" = `Jump 1);
  assert (Outline_window.route ~secret:"token" ~count:2 "POST" "/token/refresh" = `Refresh);
  assert (Outline_window.route ~secret:"token" ~count:2 "GET" "/token/refresh" = `Reject);
  assert (Outline_window.route ~secret:"token" ~count:2 "POST" "/token/poll/2" = `Poll 2);
  assert (Outline_window.route ~secret:"token" ~count:2 "GET" "/token/poll/2" = `Reject);
  assert (Outline_window.route ~secret:"token" ~count:2 "POST" "/token/poll/-1" = `Reject);
  assert (Outline_window.html "<script>\"&" = "&lt;script&gt;&quot;&amp;");
  (* Exercise every source-controlled HTML sink, including refresh's rendering
     path. Quotes must not escape attributes; tags must remain visible text. *)
  let attacks = ["</script><script>alert(1)</script>";
    "\"><img src=x onerror=alert(1)>"; "</button><svg onload=alert(1)>";
    "&lt;script&gt;alert(1)&lt;/script&gt;";
    "\" autofocus onfocus=alert(1) x=\""] in
  List.iter (fun attack ->
    let malicious = {original with title=attack; context=attack; file="/tmp/" ^ attack} in
    let index : Project_index.t = {root="/tmp/" ^ attack; entries=[malicious];
      issues=[attack]; files=[]; bibliographies=[]} in
    List.iter (fun revision ->
      let rendered = Outline_window.page ~revision ~endpoint:"http://127.0.0.1:123/token" index in
      assert (not (Doctor.contains rendered attack));
      assert (Doctor.contains rendered (Outline_window.html attack));
      assert (Doctor.contains rendered "Content-Security-Policy");
      assert (not (Doctor.contains rendered "<script>"));
      assert (not (Doctor.contains rendered "<img"));
      assert (not (Doctor.contains rendered "<svg"))) [0; 1]) attacks;
  assert (Outline_window.route ~secret:"token" ~count:2 "POST" "/token/jump/0/1" = `Jump 1);
  List.iter (fun (meth, path) -> assert (Outline_window.route ~secret:"token" ~count:2 meth path = `Reject))
    ["GET", "/token/jump/0/1"; "POST", "/wrong/jump/0/1"; "POST", "/token/jump/0/2";
     "POST", "/token/jump/0/-1"; "POST", "/token/jump/0/01"; "POST", "/token/jump/0/0/../../etc/passwd"];
  assert (Outline_window.authorized ~host:"127.0.0.1:123" ["Host: 127.0.0.1:123"; "Origin: null"]);
  assert (Outline_window.authorized ~host:"127.0.0.1:123" ["Host: 127.0.0.1:123"; "Origin: x-bbedit-preview://"]);
  assert (not (Outline_window.authorized ~host:"127.0.0.1:123" ["Host: 127.0.0.1:123"; "Origin: x-bbedit-preview://evil.test"]));
  assert (not (Outline_window.authorized ~host:"127.0.0.1:123" ["Host: evil.test"; "Origin: null"]));
  assert (not (Outline_window.authorized ~host:"127.0.0.1:123" ["Host: 127.0.0.1:123"; "Origin: https://evil.test"]));
  let token = Outline_window.token () in
  assert (String.length token = 48 && token <> Outline_window.token ());
  print_endline "Outline prototype: escaped markup and restricted navigation requests passed"
