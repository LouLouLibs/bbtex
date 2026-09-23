open Bbtex

let raises f = try ignore (f ()); false with Citation.Invalid _ | Project.Error _ -> true

let () =
  let dir = Filename.temp_file "bbtex-citation-" "" in
  Sys.remove dir; Unix.mkdir dir 0o700;
  let rec remove path = if Sys.is_directory path then begin
    Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path);
    Unix.rmdir path
  end else Sys.remove path in
  Fun.protect ~finally:(fun () -> remove dir) (fun () ->
    let path name = Filename.concat dir name in
    Build_job.write (path "main.tex") {|\documentclass{article}
\addbibresource[location=local]{one.bib}
\bibliography{two,missing}
\begin{document}
\end{document}
|};
    Build_job.write (path "one.bib") {|@string{prefix = "Collected"}
@book{parent, author={García, Ana}, title={Parent}, year={2026}}
@xdata{shared, year=2025}
@article{child, title=prefix # { {Nested} Papers}, crossref={parent}}
@article{quoted, title="A {Quoted} Title", author={李, 明}, xdata={shared}}
@article{duplicate, title={First duplicate}}
@article{duplicate, title={Second duplicate}}
@article{broken, title={unfinished
@article{valid, title={Valid after broken}}
|};
    Build_job.write (path "two.bib") ("\xef\xbb\xbf" ^ {|@article{later, title=prefix # " Work", author={ZOË}}
@article{loopA, crossref={loopB}}
@article{loopB, crossref={loopA}}
|});
    let data = Citation.bibliography (Project_index.build (path "main.tex")) in
    let first query = match Citation.search data query with
      | e :: _ -> e.Citation.key | [] -> failwith ("no match: " ^ query) in
    assert (first "garcía nested 2026" = "child");
    assert (first "李 quoted 2025" = "quoted");
    assert (first "collected work zoë" = "later");
    assert (first "valid after broken" = "valid");
    assert (Citation.search data "shared" = []);
    let duplicates = Citation.search data "duplicate" in
    assert (List.length duplicates = 2 && List.for_all (fun e -> e.Citation.ambiguous) duplicates);
    let has text = List.exists (fun issue -> Project_index.find issue 0 text < String.length issue) data.issues in
    assert (has "missing.bib" && has "Cyclic inherited metadata: loopA" && has "one.bib:7: duplicate key duplicate"
            && has "one.bib:8: malformed entry skipped");
    assert (List.length data.proofs = 3);

    (* The value layer: delimiters, concatenation, and bounded expansion. *)
    let cache = Hashtbl.create 8 and strings = Hashtbl.create 8 in
    assert (Citation.resolve ~cache strings {|"a" |} = "a");
    assert (Citation.resolve ~cache strings {|{a {b} c} # "d{"}e"|} = {|a {b} cd{"}e|});
    assert (raises (fun () -> Citation.resolve ~cache strings "{open"));
    assert (raises (fun () -> Citation.resolve ~cache strings "{a} #"));
    assert (raises (fun () -> Citation.resolve ~cache strings "{a} {b}"));
    Hashtbl.replace strings "x0" "{a}";
    for i = 1 to 24 do Hashtbl.replace strings (Printf.sprintf "x%d" i) (Printf.sprintf "x%d # x%d" (i - 1) (i - 1)) done;
    assert (raises (fun () -> Citation.resolve ~cache:(Hashtbl.create 8) strings "x24"));
    Hashtbl.replace strings "loop" "loop";
    assert (raises (fun () -> Citation.resolve ~cache:(Hashtbl.create 8) strings "loop"));

    (* The dialog: bounded rows, duplicate keys refused, sources verified. *)
    let script = Citation.picker ~binary:"/bin/bbtex" data "" in
    let contains text = Project_index.find script 0 text < String.length script in
    assert (contains "Partial bibliography index" && contains "picker-check" && contains "quoted — 李, 明 (2025) · A {Quoted} Title — one.bib:5");
    assert (contains "This citation key is duplicated");
    Build_job.write (path "large.bib") (String.concat "\n" (List.init 10000 (fun i ->
      Printf.sprintf "@article{key%d,title={Paper number %d},author={Author %d}}" i i i)));
    Build_job.write (path "large.tex") {|\bibliography{large}|};
    let started = Unix.gettimeofday () in
    let large = Citation.bibliography (Project_index.build (path "large.tex")) in
    assert (List.length large.entries = 10000 && List.length (Citation.search large "number 9999") = 1);
    assert (raises (fun () -> Citation.picker ~binary:"/bin/bbtex" large ""));
    Printf.printf "Citations: strings/concatenation, inheritance, Unicode folding, duplicates, recovery and bounds passed \
                   (10,000 entries in %.3fs)\n" (Unix.gettimeofday () -. started))
