(** Read-only setup inspection, with optional bounded tool version queries. *)
let exists p = Sys.file_exists p
let directory p = try Sys.is_directory p with Sys_error _ -> false
let access p modes = try Unix.access p modes; true with Unix.Unix_error _ -> false
let locate path name = String.split_on_char ':' path |> List.filter_map (fun dir ->
  let p = Filename.concat (if dir = "" then "." else dir) name in
  if not (directory p) && access p [Unix.X_OK] then Some p else None)
  |> List.fold_left (fun found p -> if List.mem p found then found else found @ [p]) []
let contains text needle =
  let rec loop i = i + String.length needle <= String.length text &&
    (String.sub text i (String.length needle) = needle || loop (i+1)) in loop 0
let redact home text =
  if home = "" || home = "/" then text else
  let b = Buffer.create (String.length text) in
  let rec loop i = if i < String.length text then
    if i + String.length home <= String.length text && String.sub text i (String.length home) = home
    then (Buffer.add_char b '~'; loop (i + String.length home))
    else (Buffer.add_char b text.[i]; loop (i+1)) in
  loop 0; Buffer.contents b
let rec existing_parent p = if exists p then p else
  let parent = Filename.dirname p in if parent = p then p else existing_parent parent
let log_findings text =
  (if contains text "extracting arm64 binary with lipo failed" then
    ["Biber launcher failed before bibliography processing. Repair/reinstall Biber through your TeX distribution."] else []) @
  (if contains text "control file version" && contains text "expected version" then
    ["Biber/biblatex version mismatch. Match Biber to biblatex in the selected TeX distribution or Tectonic bundle."] else [])
let inspect ~home ~path ~state ~binary ?source ?(probe=false) () =
  let lines = ref [] in
  let add status name detail = lines := Printf.sprintf "[%s] %s: %s" status name detail :: !lines in
  let engine = match source with
    | None -> add "INFO" "Project" "No source supplied; checking default pdfLaTeX setup."; "pdflatex"
    | Some source -> (try
        let config = Compiler.resolve_compilation source in
        add "OK" "Project" config.root_file;
        let log = Filename.concat state ("build-" ^ Digest.to_hex (Digest.string config.root_file) ^ ".log") in
        (try
           if (Unix.stat log).Unix.st_size <= 1024 * 1024 then begin
             let text = In_channel.with_open_bin log In_channel.input_all in
             List.iter (add "WARN" "Previous build evidence") (log_findings text)
           end else add "UNVERIFIED" "Build evidence" "Log exceeds inspection limit (1 MiB)."
         with Sys_error _ | Unix.Unix_error _ -> add "UNVERIFIED" "Build evidence" "No readable build log.");
        Types.string_of_engine config.engine
      with exn -> add "WARN" "Project configuration" (Printexc.to_string exn); "pdflatex") in
  add "INFO" "Selected engine" engine;
  let required = if engine = "tectonic" || engine = "ratex" then [engine] else ["latexmk"; engine] in
  List.iter (fun name -> match locate path name with
    | [] -> add (if List.mem name required then "WARN" else "OPTIONAL") name
        "Not on PATH. See setup troubleshooting for feature-specific installation."
    | first :: rest -> add "OK" name first;
        if probe && name <> "ratex" then begin
          try
            let result = Doctor_probe.run first (if name = "pdftoppm" then "-v" else "--version") in
            add (if result.outcome = "ok" then "OK" else "WARN") (name ^ " launch")
              (result.outcome ^ ": " ^ Doctor_probe.summary result.output);
            List.iter (add "WARN" name) (log_findings result.output)
          with Unix.Unix_error (error, _, _) -> add "WARN" (name ^ " launch") (Unix.error_message error)
        end;
        if rest <> [] then add "INFO" (name ^ " alternatives") (String.concat ", " rest))
    (List.sort_uniq String.compare (required @ ["pdftoppm"; "bibtex"; "biber"; "texlab"]));
  add "UNVERIFIED" "Versions and compatibility"
    (if probe then "Version queries do not establish bibliography compatibility or successful compilation. RaTeX is never probed."
     else "Tools were located, not executed. Use doctor --probe for bounded launch/version checks. RaTeX remains experimental.");
  let parent = existing_parent state in
  add (if directory parent && access parent [Unix.W_OK; Unix.X_OK] then "OK" else "WARN")
    "State access" (parent ^ " (permission inspection; no write attempted)");
  let base = Filename.concat home "Library/Application Support/BBEdit" in
  let scripts = Filename.concat base "Scripts" in
  let packages = Filename.concat base "Packages" in
  add "INFO" "Running binary" binary;
  add "INFO" "Layout" (if contains binary "/Contents/Resources/" then "Packaged executable"
    else if contains binary "/_build/" then "Development executable" else "Custom executable location");
  List.iter (fun name ->
    let loose = Filename.concat scripts name in
    let bundled = Filename.concat (Filename.concat packages "bbtex.bbpackage/Contents/Scripts") name in
    let present p = try ignore (Unix.lstat p); true with Unix.Unix_error _ -> false in
    if present loose && present bundled then add "WARN" "Duplicate command"
      (name ^ " exists in Scripts and bbtex package; keep one installation active.");
    List.iter (fun p -> if present p && not (exists p) then add "WARN" "Broken command link" p) [loose; bundled])
    ["LaTeX — Compile.sh"; "LaTeX — Project Outline.sh"; "LaTeX — Insert Citation.sh"; "LaTeX — Doctor.sh"];
  let support = directory (Filename.concat packages "bbtex-support.bbpackage") ||
    exists (Filename.concat packages "bbtex.bbpackage/Contents/Resources/environments-lib.scpt") in
  add (if support then "OK" else "OPTIONAL") "Editing support"
    (if support then "Editing support is installed separately or bundled with the workflow package."
     else "Editing support was not found in the standard packages; install it for structural editing and clippings.");
  let hook = Filename.concat base "Attachment Scripts/Document.documentDidSave.scpt" in
  add (if exists hook then "UNVERIFIED" else "OPTIONAL") "Save attachment"
    (if exists hook then "Attachment exists; ownership/conflicts need manual inspection. Do not overwrite an unrelated hook."
     else "No attachment; automatic preview on save is optional.");
  add (if List.exists directory ["/Applications/Skim.app"; Filename.concat home "Applications/Skim.app"] then "OK" else "OPTIONAL")
    "Skim" "Standard application locations checked; launch and SyncTeX behavior unverified.";
  add "UNVERIFIED" "BBEdit integration" "TexLab configuration, Automation permission, shortcuts and UI behavior require a native smoke check.";
  (if probe then "bbtex doctor — tool launch checks (tools may initialize caches)\n" else "bbtex doctor — read-only inspection\n") ^
  "Home paths redacted; review other paths before sharing.\n\n" ^
  redact home (String.concat "\n" (List.rev !lines)) ^ "\n\nSee docs/setup-troubleshooting.md for next actions.\n"
let run ?(probe=false) source =
  print_string (inspect ~home:(Option.value ~default:"" (Sys.getenv_opt "HOME"))
    ~path:(Option.value ~default:"" (Sys.getenv_opt "PATH")) ~state:(Build_job.state_dir ())
    ~binary:Sys.executable_name ?source ~probe ())
