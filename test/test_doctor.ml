open Bbtex
let () =
  assert (Doctor.redact "/Users/test user" "at /Users/test user/file" = "at ~/file");
  assert (Doctor.redact "" "unchanged" = "unchanged");
  assert (Doctor.log_findings "unrelated error" = []);
  assert (List.length (Doctor.log_findings "extracting arm64 binary with lipo failed") = 1);
  assert (List.length (Doctor.log_findings "Found biblatex control file version 3.8, expected version 3.11") = 1);
  let root = Filename.temp_file "bbtex-doctor-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  Fun.protect ~finally:(fun () -> Unix.rmdir root) (fun () ->
    let state = Filename.concat root "absent/state" in
    let report = Doctor.inspect ~home:root ~path:root ~state ~binary:"/_build/default/bin/main.exe" () in
    assert (Doctor.contains report "[WARN] latexmk");
    assert (Doctor.contains report "[OPTIONAL] biber");
    assert (Doctor.contains report "Development executable");
    assert (Doctor.contains report "[UNVERIFIED] Versions");
    assert (not (Doctor.contains report root));
    assert (Sys.readdir root = [||]));
  print_endline "Doctor read-only checks passed"

let () =
  let root = Filename.temp_file "bbtex-doctor-layout-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let rec remove p =
    if (Unix.lstat p).st_kind = Unix.S_DIR then begin
      Array.iter (fun n -> remove (Filename.concat p n)) (Sys.readdir p); Unix.rmdir p
    end else Sys.remove p in
  Fun.protect ~finally:(fun () -> remove root) (fun () ->
    let rec mkdir p = if not (Sys.file_exists p) then begin mkdir (Filename.dirname p); Unix.mkdir p 0o700 end in
    let write p text = mkdir (Filename.dirname p); let oc = open_out p in output_string oc text; close_out oc in
    let base = Filename.concat root "custom support" in
    let package = Filename.concat base "Packages/Renamed.bbpackage/Contents" in
    let command = "LaTeX — Project Outline Window.sh" in
    write (Filename.concat package ("Scripts/" ^ command)) "fixture";
    write (Filename.concat base ("Scripts/Nested/" ^ command)) "fixture";
    write (Filename.concat package "Resources/environments-lib.scpt") "fixture";
    let hook = Filename.concat base "Attachment Scripts/Document.documentDidSave.scpt" in
    write hook "compiled fixture";
    assert (fst (Doctor.attachment_identity hook) = "UNVERIFIED");
    write (hook ^ ".bbtex-receipt") ("bbtex-save-hook-v1:" ^ Digest.to_hex (Digest.file hook));
    assert (fst (Doctor.attachment_identity hook) = "OK");
    let before = Digest.file hook in
    let report = Doctor.inspect ~home:root ~path:"" ~state:root ~binary:"bbtex" ~support:base () in
    assert (Doctor.contains report "Renamed.bbpackage");
    assert (Doctor.contains report "[WARN] Duplicate command");
    assert (Doctor.contains report "[OK] Editing support");
    assert (Doctor.contains report "[OK] Save attachment");
    assert (Digest.file hook = before);
    write hook "changed";
    assert (fst (Doctor.attachment_identity hook) = "WARN");
    write (Filename.concat base "Attachment Scripts/BBEdit.applescript") "foreign";
    let report = Doctor.inspect ~home:root ~path:"" ~state:root ~binary:"bbtex" ~support:base () in
    assert (Doctor.contains report "[WARN] Attachment conflict"));
  print_endline "Doctor: custom layouts, attachment identity and conflicts passed"

let () =
  let script = Filename.temp_file "bbtex-probe space " ".sh" in
  Fun.protect ~finally:(fun () -> Sys.remove script) (fun () ->
    let write body =
      let oc = open_out script in output_string oc ("#!/bin/sh\n" ^ body); close_out oc;
      Unix.chmod script 0o700 in
    write "printf 'version 1.2\\n' >&2\n";
    let result = Doctor_probe.run script "--version" in
    assert (result.outcome = "ok" && Doctor_probe.summary result.output = "version 1.2");
    write "echo broken >&2; exit 7\n";
    assert ((Doctor_probe.run script "--version").outcome = "exit 7");
    write "while :; do echo flooding-output; done\n";
    assert ((Doctor_probe.run script "--version").outcome = "output exceeded 16 KiB");
    (* The descendant inherits the pipe even after the version-query parent exits. *)
    write "/bin/sleep 30 &\nexit 0\n";
    let start = Unix.gettimeofday () in
    let result = Doctor_probe.run ~timeout:0.15 script "--version" in
    assert (Doctor.contains result.outcome "timed out");
    assert (Unix.gettimeofday () -. start < 2.));
  print_endline "Doctor probes: stderr, failure, flood and descendant timeout passed"
