open Bbtex

let () =
  let dir = Filename.temp_file "bbtex-outline-" "" in
  Sys.remove dir; Unix.mkdir dir 0o700;
  let rec remove path = if Sys.is_directory path then begin
    Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path);
    Unix.rmdir path
  end else Sys.remove path in
  Fun.protect ~finally:(fun () -> remove dir) (fun () ->
    let main = Filename.concat dir "main.tex" and child = Filename.concat dir "child.tex" in
    Build_job.write main {|\documentclass{article}
\newcommand{\fake}[1]{\section{Macro section}\label{fake}}
\newenvironment{fakeenv}{\section{Hidden}}{\label{hidden}}
\def\fake#1{\label{hidden-definition}}
\begin{document}
% \section{Commented out}
\section[Short]{First {nested} title}
\label{duplicate}
\verb|\label{verb}| \% \label{escaped-percent}
\begin{verbatim}
\section{Verbatim section}\input{no-such-file}
\end{verbatim}
\begin{minted}{tex}
\label{minted}
\end{minted}
\input{child}
\input{child}
\input{missing}
\input{\generated}
\section*{Last}
\end{document}
\label{after-document}
|};
    Build_job.write child {|% !TEX root = main.tex
\subsection{Child}
\begin{equation}
x = y \label{duplicate}
\end{equation}
\begin{figure}\caption[Short]{A useful caption}\label{fig:test}\end{figure}
\begin{table}\caption{Measurements}\label{tab:test}\end{table}
\[a=b\]
\input{main}
|};
    let index = Project_index.build child in
    let entries = index.entries in
    let named title = List.filter (fun e -> e.Project_index.title = title) entries in
    assert (List.length (named "duplicate") = 2);
    List.iter (fun title -> assert (named title = []))
      ["fake"; "hidden"; "hidden-definition"; "verb"; "minted"; "after-document"; "Commented out"];
    assert (List.length index.issues = 3);
    let first = List.hd entries in
    assert (first.title = "First {nested} title" && first.line = 7 && first.depth = 0);
    let child_section = List.hd (named "Child") in
    assert (child_section.depth = 1 && child_section.context = first.title);
    let duplicate = List.hd (Project_index.search index "kind:label duplicate child.tex") in
    assert (duplicate.line = 4);
    assert (List.length (Project_index.search index "kind:figure useful") = 1);
    assert (List.length (Project_index.search index "kind:table Measurements") = 1);
    assert (List.length (Project_index.search index "kind:equation") = 2);
    let script = Outline.picker index "duplicate" in
    assert (Project_index.find script 0 "1. " < String.length script);
    assert (Project_index.find script 0 "2. " < String.length script);
    ignore (Outline.jump ~binary:"/tmp/bbtex" duplicate.file duplicate.fingerprint duplicate.line);
    Build_job.write child ("\n" ^ Project_index.read child);
    (try ignore (Outline.jump ~binary:"/tmp/bbtex" duplicate.file duplicate.fingerprint duplicate.line);
       assert false with Project.Error _ -> ());
    let refreshed = Project_index.build child in
    assert ((List.hd (Project_index.search refreshed "kind:label duplicate child.tex")).line = 5);
    Build_job.write main "% !TEX root = child.tex\n";
    (try ignore (Project_index.build child); assert false with Project.Error _ -> ());
    (* Legacy CR-only and CRLF hard lines retain locations. *)
    Build_job.write main "\\section{One}\r\n\\section{Two}\r\\label{three}";
    let index = Project_index.build main in
    assert (List.map (fun e -> e.Project_index.line) index.entries = [1; 2; 3]);
    print_endline "Project outline: hierarchy, includes, duplicates, literals, cycles, search and stale targets passed")
