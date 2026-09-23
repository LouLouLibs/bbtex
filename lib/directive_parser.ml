(** Parse %!TEX directives from the first 50 lines of a .tex file.

    Directives look like:
      %!TEX root = ../main.tex
      %!TEX program = xelatex

    We search only the first 50 lines — directives buried deeper
    are almost certainly not directives. *)

open Types

let max_lines = 50

(** Try to parse a single line as a %!TEX directive.
    Returns [None] if the line is not a directive. *)
let parse_directive_line line =
  let line = String.trim line in
  (* TeXShop accepts whitespace between the comment marker and !TEX. *)
  let line = if String.starts_with ~prefix:"%" line then
      String.sub line 1 (String.length line - 1) |> String.trim
    else "" in
  if String.length line < 4 then None
  else
    let prefix = String.sub line 0 4 in
    if String.lowercase_ascii prefix <> "!tex" then None
    else
      let rest = String.trim (String.sub line 4 (String.length line - 4)) in
      (* Find the '=' *)
      match String.index_opt rest '=' with
      | None -> None
      | Some eq_pos ->
        let key_str = String.trim (String.sub rest 0 eq_pos) in
        let val_str = String.trim (String.sub rest (eq_pos + 1)
                                     (String.length rest - eq_pos - 1)) in
        if key_str = "" || val_str = "" then None
        else
          Some { key = directive_key_of_string key_str; value = val_str }

(** Read the first [max_lines] lines from a file and collect all
    %!TEX directives found. *)
let parse_file filename =
  let ic = open_in filename in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
    let rec loop n acc =
      if n >= max_lines then List.rev acc
      else
        match input_line ic with
        | line ->
          (* A UTF-8 byte-order mark would hide a directive on the first line. *)
          let line = if n = 0 && String.starts_with ~prefix:"\xef\xbb\xbf" line
            then String.sub line 3 (String.length line - 3) else line in
          let acc' = match parse_directive_line line with
            | Some d -> d :: acc
            | None   -> acc
          in
          loop (n + 1) acc'
        | exception End_of_file -> List.rev acc
    in
    loop 0 [])

(** Convenience: find a specific directive key. *)
let find_directive key directives =
  List.find_opt (fun d -> d.key = key) directives
  |> Option.map (fun d -> d.value)
