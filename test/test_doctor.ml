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
