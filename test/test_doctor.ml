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
