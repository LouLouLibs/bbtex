open Bbtex

let contains text part =
  let rec loop i = i + String.length part <= String.length text &&
    (String.sub text i (String.length part) = part || loop (i + 1)) in
  loop 0

let () =
  let dir = Filename.temp_file "bbtex-snippet-test-" "" in
  Sys.remove dir; Unix.mkdir dir 0o700;
  Unix.putenv "BBTEX_STATE_DIR" dir;
  let rec remove path =
    if Sys.is_directory path then (Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path); Unix.rmdir path)
    else Sys.remove path in
  Fun.protect ~finally:(fun () -> remove dir) (fun () ->
    let source = Filename.concat dir "paper.tex" and png = Filename.concat dir "image.png" in
    Build_job.write source "saved source"; Build_job.write png "test image";
    let folder = Snippet_page.directory () in
    let page = Snippet_page.page_path folder in
    Build_job.write page "old template";
    let first = Snippet_page.begin_request ~source ~line:3 ~mode:"manual" in
    assert (contains (Snippet_page.read_file page) "bbtex-snippet-template:2");
    assert (contains (Snippet_page.read_file (Filename.concat folder "image.js")) "location.reload()");
    assert (Option.is_some (Snippet_page.finish first ~status:"current" ~png ~log:"" ~message:""));
    let original = Snippet_page.load folder in
    assert (original.status = "current" && original.image <> "");
    let second = Snippet_page.begin_request ~source ~line:8 ~mode:"manual" in
    let pending = Snippet_page.load folder in
    assert (pending.status = "rendering" && pending.image = original.image && pending.image_line = 3);
    assert (Snippet_page.finish first ~status:"error" ~png:"" ~log:"" ~message:"obsolete" = None);
    assert ((Snippet_page.load folder).revision = pending.revision);
    let log = Filename.concat dir "compiler.log" in
    Build_job.write log "error";
    ignore (Snippet_page.finish second ~status:"error" ~png:"" ~log ~message:"<script>\n\"bad\"");
    assert ((Snippet_page.load folder).image = original.image);
    assert (Snippet_page.log_path () = log);
    assert (not (contains (Snippet_page.payload (Snippet_page.load folder)) "<script>"));
    let third = Snippet_page.begin_request ~source ~line:9 ~mode:"manual" in
    Build_job.write source "changed before publication";
    assert (not (Snippet_page.is_current third));
    ignore (Snippet_page.finish third ~status:"current" ~png ~log:"" ~message:"");
    assert ((Snippet_page.load folder).status = "stale");
    let missing = Snippet_page.begin_request ~source ~line:9 ~mode:"manual" in
    ignore (Snippet_page.finish missing ~status:"current" ~png:"missing-rendered-image.png" ~log:"" ~message:"");
    assert ((Snippet_page.load folder).status = "error");
    (* Disabling tracking invalidates automatic work, but not manual requests. *)
    let flag = Filename.concat dir "preview-on-save-source" in
    Snippet_page.atomic_write flag source;
    let auto = Snippet_page.begin_request ~source ~line:9 ~mode:"auto" in
    assert (Snippet_page.is_current auto);
    Sys.remove flag;
    assert (not (Snippet_page.is_current auto));
    let manual = Snippet_page.begin_request ~source ~line:9 ~mode:"manual" in
    Snippet_page.stop_auto ~matches:(fun _ -> true) ~message:"full build";
    assert (Snippet_page.is_current manual);
    Snippet_page.atomic_write flag source;
    let auto = Snippet_page.begin_request ~source ~line:9 ~mode:"auto" in
    Snippet_page.stop_auto ~matches:(fun _ -> false) ~message:"other project";
    assert (Snippet_page.is_current auto);
    Snippet_page.stop_auto ~matches:(fun _ -> true) ~message:"full build";
    assert (not (Snippet_page.is_current auto));
    (* Dependency saves retain the source anchor and supersede queued work. *)
    let root = Filename.concat dir "main.tex" in
    let macros = Filename.concat dir "macros.tex" in
    Build_job.write root "\\documentclass{article}\n\\begin{document}\n\\end{document}";
    Build_job.write source "% !TEX root = main.tex\n\\[x=1\\]\n";
    Build_job.write macros "macros";
    let render_dir = Preview_inputs.directory root in
    Build_job.mkdir render_dir;
    Build_job.write (Filename.concat render_dir "selection.fls") ("INPUT " ^ macros ^ "\n");
    Preview_inputs.record ~root ~dir:render_dir ~success:true;
    let auto = Snippet_page.begin_request ~source ~line:2 ~mode:"auto" in
    assert (Snippet_page.refresh_dependency png = None);
    assert (Snippet_page.is_current auto);
    let refreshed = Option.get (Snippet_page.refresh_dependency macros) in
    let generation, line, tracked = refreshed in
    assert (line = 2 && tracked = source && Snippet_page.is_current generation);
    assert (not (Snippet_page.is_current auto));
    (* Cache invalidation and a partial failed recorder cannot lose old inputs. *)
    Build_job.write (Filename.concat render_dir "selection.fls") "";
    Preview_inputs.record ~root ~dir:render_dir ~success:false;
    assert (Preview_inputs.relevant ~root macros);
    assert (Option.is_some (Snippet_page.refresh_dependency root));
    Build_job.write source "% !TEX root = main.tex\nchanged equation";
    assert (Snippet_page.refresh_dependency macros = None);
    assert ((Snippet_page.load folder).status = "stale");
    Sys.remove flag;
    assert (Snippet_page.refresh_dependency root = None);
    let other = Filename.concat dir "other.tex" in
    Build_job.write other "other source";
    ignore (Snippet_page.begin_request ~source:other ~line:1 ~mode:"manual");
    assert ((Snippet_page.load folder).image = "");
    Unix.putenv "BBTEX_PREVIEW_TOKEN" "first";
    let key = Preview_cache.key "formula" "pdflatex" [] in
    Unix.putenv "BBTEX_PREVIEW_TOKEN" "second";
    assert (Preview_cache.key "formula" "pdflatex" [] = key);
    (* BBEdit sets selection variables per run; they must not defeat the cache. *)
    Unix.putenv "BB_DOC_SELSTART" "1";
    let key = Preview_cache.key "formula" "pdflatex" [] in
    Unix.putenv "BB_DOC_SELSTART" "99";
    assert (Preview_cache.key "formula" "pdflatex" [] = key);
    (* Variables that change what TeX reads do change the key. *)
    let original = Sys.getenv_opt "TEXINPUTS" in
    Unix.putenv "TEXINPUTS" "/tmp/other-inputs:";
    assert (Preview_cache.key "formula" "pdflatex" [] <> key);
    Unix.putenv "TEXINPUTS" (Option.value ~default:"" original);
    print_endline "Snippet state: migration, generations, stale/error output, ownership, and cache identity passed")

let () =
  let state = Filename.temp_file "bbtex-snippet-live-" "" in
  Sys.remove state; Unix.mkdir state 0o700;
  Unix.putenv "BBTEX_STATE_DIR" state;
  let rec remove path =
    if Sys.is_directory path then (Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path); Unix.rmdir path)
    else Sys.remove path in
  Fun.protect ~finally:(fun () -> remove state) (fun () ->
    let flag = Snippet_page.live_flag () in
    assert (Filename.dirname flag = state);
    Out_channel.with_open_bin flag (fun oc -> output_string oc "123");
    let token = Snippet_page.begin_request ~source:"" ~line:0 ~mode:"live" in
    assert (Snippet_page.is_current token);
    Sys.remove flag;
    assert (not (Snippet_page.is_current token));
    Snippet_page.stop_live ~message:"Live selection preview is off.";
    assert (Snippet_page.finish token ~status:"current" ~png:"" ~log:"" ~message:"" = None));
  print_endline "Snippet: live tracking follows the live flag passed"

let () =
  let state = Filename.temp_file "bbtex-snippet-live-off-" "" in
  Sys.remove state; Unix.mkdir state 0o700;
  Unix.putenv "BBTEX_STATE_DIR" state;
  let rec remove path =
    if Sys.is_directory path then (Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path); Unix.rmdir path)
    else Sys.remove path in
  Fun.protect ~finally:(fun () -> remove state) (fun () ->
    let flag = Snippet_page.live_flag () in
    Snippet_page.stop_live ~message:"Live selection preview is off.";
    ignore (Snippet_page.begin_request ~source:"" ~line:0 ~mode:"manual");
    let folder = Snippet_page.directory () in
    let before = Snippet_page.load folder in
    (match Snippet_page.begin_request ~source:"" ~line:0 ~mode:"live" with
     | _ -> assert false
     | exception Project.Error message -> assert (message = "Live selection preview is off."));
    let after = Snippet_page.load folder in
    assert (after.generation = before.generation && after.message = before.message
            && after.revision = before.revision);
    Out_channel.with_open_bin flag (fun oc -> output_string oc "123");
    let token = Snippet_page.begin_request ~source:"" ~line:0 ~mode:"live" in
    assert ((Snippet_page.load folder).generation = token));
  print_endline "Snippet: live requests refused once live mode stops passed"
