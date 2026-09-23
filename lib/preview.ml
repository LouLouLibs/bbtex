(** Selection previews reuse the root preamble without rewriting project inputs. *)
let read_file path = In_channel.with_open_bin path In_channel.input_all

let preamble text =
  let marker = "\\begin{document}" in
  let length = String.length text in
  let rec scan i comment =
    if i >= length then raise (Project.Error
      "Preview needs a literal \\begin{document} in the main file. Compile the full document for generated preambles.")
    else if comment then scan (i + 1) (text.[i] <> '\n' && text.[i] <> '\r')
    else if text.[i] = '%' then scan (i + 1) true
    else if i + String.length marker <= length &&
      String.sub text i (String.length marker) = marker then String.sub text 0 i
    else if text.[i] = '\\' then scan (min length (i + 2)) false
    else scan (i + 1) false
  in scan 0 false

let document root_text selection =
  let selection = String.trim selection in
  if selection = "" then raise (Project.Error "Select an equation or a complete math environment first.");
  let delimited = List.exists (fun prefix -> String.starts_with ~prefix selection)
    ["$"; "\\["; "\\("; "\\begin{"] in
  let body = if delimited then selection else "\\[\n" ^ selection ^ "\n\\]" in
  "\\PassOptionsToPackage{active,tightpage}{preview}\n" ^ preamble root_text ^
  "\n\\usepackage{preview}\n\\setlength\\PreviewBorder{4pt}\n" ^
  "\\begin{document}\n\\begin{preview}\n" ^ body ^
  "\n\\end{preview}\n\\end{document}\n"

let compile ?(current = fun () -> true) source selection =
  if not (current ()) then raise Build_job.Cancelled;
  let started = Unix.gettimeofday () in
  let config = Compiler.resolve_compilation source in
  let text = document (read_file config.root_file) selection in
  Build_job.with_job ~superseded:(fun () -> not (current ())) config.root_file (fun job ->
    let dir = Filename.concat (Build_job.state_dir ())
      ("preview-" ^ Digest.to_hex (Digest.string config.root_file)) in
    Build_job.mkdir dir;
    let dir = Unix.realpath dir in
    let tex = Filename.concat dir "selection.tex" in
    let pdf = Filename.concat dir "selection.pdf" in
    let log = Filename.concat dir "compiler.log" in
    let png = Filename.concat dir "selection.png" in
    let manifest = Filename.concat dir "cache.inputs" in
    Printf.printf "log: %s\n%!" log;
    let engine = Types.string_of_engine config.engine in
    let key = Preview_cache.key text engine config.options in
    let cacheable = config.engine <> Types.Tectonic && config.engine <> Types.Ratex && config.options = [] in
    if cacheable && Sys.file_exists png && Sys.file_exists pdf && Preview_cache.valid manifest key then begin
      Preview_inputs.record ~root:config.root_file ~dir ~success:true;
      Printf.printf "status: success\npdf: %s\npng: %s\nlog: %s\nengine: %s\ncache: hit\nrender_duration: %.3f\nconversion_duration: 0.000\n"
        pdf png log engine (Unix.gettimeofday () -. started);
      0
    end else begin
    Build_job.remove manifest;
    Build_job.write tex text;
    Build_job.remove pdf;
    Build_job.remove (Filename.concat dir "selection.fls");
    let job = { job with Build_job.log = log } in
    let command, args = match config.engine with
      | Types.Ratex -> "ratex", ["-pdf"; "-interaction=nonstopmode"; "-output-directory=" ^ dir]
      | Types.Tectonic -> "tectonic", ["--keep-logs"; "--outdir"; dir;
          "-Z"; "search-path=" ^ Filename.dirname config.root_file]
      | engine when config.options = [] -> Types.string_of_engine engine,
          ["-interaction=nonstopmode"; "-halt-on-error"; "-file-line-error";
           "-recorder"; "-output-directory=" ^ dir]
      | engine -> "latexmk", [Types.latexmk_flag engine; "-interaction=nonstopmode";
          "-halt-on-error"; "-file-line-error"; "-recorder"; "-outdir=" ^ dir]
    in
    (* Keep relative preamble inputs anchored at the real main document. *)
    let exit_code = Build_job.run job ~cwd:(Filename.dirname config.root_file)
      command (args @ config.options @ [tex]) in
    let success = exit_code = 0 && Sys.file_exists pdf in
    Preview_inputs.record ~root:config.root_file ~dir ~success;
    if success then begin
      let png_started = Unix.gettimeofday () in
      let convert_job = { job with Build_job.log = Filename.concat dir "conversion.log" } in
      let converted = Build_job.run convert_job ~cwd:dir "pdftoppm"
        ["-f"; "1"; "-singlefile"; "-scale-to"; "1400"; "-png"; pdf; Filename.concat dir "selection"] in
      if converted <> 0 then begin
        Printf.printf "log: %s\n%!" convert_job.log;
        raise (Project.Error ("PNG conversion failed: " ^ convert_job.log))
      end;
      if cacheable then Preview_cache.record ~manifest ~key
        ~cwd:(Filename.dirname config.root_file) ~dir ~root:config.root_file ~engine;
      Printf.printf "png: %s\nrender_duration: %.3f\nconversion_duration: %.3f\n"
        (Filename.concat dir "selection.png") (png_started -. started)
        (Unix.gettimeofday () -. png_started)
    end;
    Printf.printf "status: %s\npdf: %s\nlog: %s\nengine: %s\ncache: miss\n"
      (if success then "success" else "error") pdf log (Types.string_of_engine config.engine);
    if not success then print_endline "message: Preview failed. Inspect the preview log; select a complete equation and check that its macros are defined in the root preamble.";
    if success then 0 else 1 end)
