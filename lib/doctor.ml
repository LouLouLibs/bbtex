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
let present p = try ignore (Unix.lstat p); true with Unix.Unix_error _ -> false
let bounded_read limit p =
  if (Unix.stat p).Unix.st_size > limit then raise (Sys_error "Inspection size limit exceeded");
  In_channel.with_open_bin p In_channel.input_all

let attachment_identity hook =
  let receipt = hook ^ ".bbtex-receipt" in
  if not (present receipt) then "UNVERIFIED", "No bbtex installer receipt; preserve the attachment until inspected."
  else try
    let expected = String.trim (bounded_read 128 receipt) in
    let actual = "bbtex-save-hook-v1:" ^ Digest.to_hex (Digest.string (bounded_read (1024 * 1024) hook)) in
    if expected = actual then "OK", "Matches bbtex installer receipt (content identity, not a security attestation)."
    else "WARN", "Attachment differs from its bbtex receipt; preserve it and review before upgrading."
  with Sys_error _ | Unix.Unix_error _ -> "WARN", "Attachment or receipt is unreadable/oversized; preserve it."

let installation ~base ~add =
  let commands = ["LaTeX — Compile.sh"; "LaTeX — Project Outline.sh";
    "LaTeX — Project Outline Window.sh"; "LaTeX — Insert Citation.sh"; "LaTeX — Doctor.sh"] in
  let found = Hashtbl.create 16 and seen = Hashtbl.create 32 in
  let editing = ref false in
  let remaining = ref 2048 and limited = ref false in
  let rec scan depth dir =
    if depth > 8 || !remaining <= 0 then limited := true
    else if directory dir then try
      let canonical = Unix.realpath dir in
      if not (Hashtbl.mem seen canonical) then begin
        Hashtbl.add seen canonical ();
        Array.iter (fun name ->
          if !remaining <= 0 then limited := true else begin
            decr remaining;
            let p = Filename.concat dir name in
            if name = "environments-lib.scpt" && exists p then editing := true;
            if List.mem name commands then begin
              let previous = Option.value ~default:[] (Hashtbl.find_opt found name) in
              Hashtbl.replace found name (p :: previous);
              if not (exists p) then add "WARN" "Broken command link" p
            end;
            if directory p then scan (depth + 1) p
          end) (Sys.readdir dir)
      end
    with Sys_error _ | Unix.Unix_error _ -> add "UNVERIFIED" "Installation directory" (dir ^ " could not be read")
  in
  List.iter (scan 0) [Filename.concat base "Scripts"; Filename.concat base "Packages"];
  List.iter (fun name -> match Hashtbl.find_opt found name with
    | Some paths ->
      add "OK" "Installed command" (name ^ ": " ^ String.concat ", " (List.rev paths));
      if List.length paths > 1 then add "WARN" "Duplicate command"
        (name ^ " appears in multiple menu locations; keep one workflow installation active.")
    | None -> add "OPTIONAL" "Menu command" (name ^ " not found in inspected Scripts/Packages")) commands;
  if !limited then add "UNVERIFIED" "Installation scan" "Stopped at 2,048 entries or 8 directory levels; inspect remaining folders manually.";
  let attachments = Filename.concat base "Attachment Scripts" in
  (try Array.iter (fun name ->
    let stem = try Filename.chop_extension name with Invalid_argument _ -> name in
    if List.mem stem ["Document"; "BBEdit"; "Document.documentDidSave"] then begin
      let hook = Filename.concat attachments name in
      if name = "Document.documentDidSave.scpt" then
        let status, detail = attachment_identity hook in add status "Save attachment" (hook ^ ": " ^ detail)
      else add "WARN" "Attachment conflict" (hook ^ ": may handle documentDidSave; do not replace without manual integration.")
    end) (Sys.readdir attachments)
   with Sys_error _ -> if present attachments then add "UNVERIFIED" "Attachments" "Attachment directory could not be read.");
  if not (present (Filename.concat attachments "Document.documentDidSave.scpt")) then
    add "OPTIONAL" "Save attachment" "No standard save hook; preview on save is optional.";
  !editing

let inspect ~home ~path ~state ~binary ?source ?support ?(probe=false) () =
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
  let base = Option.value ~default:(Filename.concat home "Library/Application Support/BBEdit") support in
  let packages = Filename.concat base "Packages" in
  add (if directory base then "INFO" else "UNVERIFIED") "BBEdit support directory" base;
  add "INFO" "Running binary" binary;
  add "INFO" "Layout" (if contains binary "/Contents/Resources/" then "Packaged executable"
    else if contains binary "/_build/" then "Development executable" else "Custom executable location");
  let discovered_support = installation ~base ~add in
  let support = discovered_support || directory (Filename.concat packages "bbtex-support.bbpackage") ||
    exists (Filename.concat packages "bbtex.bbpackage/Contents/Resources/environments-lib.scpt") in
  add (if support then "OK" else "OPTIONAL") "Editing support"
    (if support then "Editing support is installed separately or bundled with the workflow package."
     else "Editing support was not found in the standard packages; install it for structural editing and clippings.");
  add (if List.exists directory ["/Applications/Skim.app"; Filename.concat home "Applications/Skim.app"] then "OK" else "OPTIONAL")
    "Skim" "Standard application locations checked; launch and SyncTeX behavior unverified.";
  add "UNVERIFIED" "BBEdit integration" "TexLab configuration, Automation permission, shortcuts and UI behavior require a native smoke check.";
  (if probe then "bbtex doctor — tool launch checks (tools may initialize caches)\n" else "bbtex doctor — read-only inspection\n") ^
  "Home paths redacted; review other paths before sharing.\n\n" ^
  redact home (String.concat "\n" (List.rev !lines)) ^ "\n\nSee docs/setup-troubleshooting.md for next actions.\n"
let run ?(probe=false) ?support source =
  print_string (inspect ~home:(Option.value ~default:"" (Sys.getenv_opt "HOME"))
    ~path:(Option.value ~default:"" (Sys.getenv_opt "PATH")) ~state:(Build_job.state_dir ())
    ~binary:Sys.executable_name ?source ?support ~probe ())
