(** Plain-English hints for LaTeX messages bbtex recognises.

    A hint explains what a message usually means; it never replaces TeX's own
    words. Every hint starts with "[bbtex]", so it is always clear which text
    came from TeX. Messages that aren't recognised get no hint: better silent
    than wrong. The patterns come from real logs in testdata/logs/hint-*.log. *)

open Types

let prefix = "[bbtex] "

let contains message sub = Log_parser.contains_substring ~sub message

(* The name between TeX's `quotes', as in "File `foo.sty' not found". *)
let quoted message =
  match String.index_opt message '`' with
  | None -> None
  | Some start -> match String.index_from_opt message start '\'' with
    | None -> None
    | Some stop -> Some (String.sub message (start + 1) (stop - start - 1))

let missing_file message =
  match quoted message with
  | Some name when List.mem (Filename.extension name) [".sty"; ".cls"] ->
    Printf.sprintf "%s isn't installed: install the package that provides it \
      (tlmgr search --global --file %s finds it)." name name
  | _ -> "TeX can't find this file: check its name, and that the path is \
      relative to the root file."

let error message =
  let has = contains message in
  if has "Undefined control sequence" then
    Some "A command isn't defined: check for a typo, or a missing \\usepackage."
  else if has "Missing $ inserted" then
    Some "Math outside math mode, often a _ or ^ in text: put it in $...$, or write \\_ or \\^{}."
  else if has "File `" && has "' not found" then Some (missing_file message)
  else if has "LaTeX Error: Environment " && has " undefined" then
    Some "This environment isn't defined: check its spelling, or load the package that provides it."
  else if has "Missing \\begin{document}" then
    Some "Text before \\begin{document}: look for stray text or a typo in the preamble."
  else if has "File ended while scanning" || has "Paragraph ended before" then
    Some "A command's argument never ends: look for a missing } before this point."
  else if has "Too many }'s" || has "Extra }" then
    Some "Braces don't balance: look for a } without a matching {."
  else if has "Misplaced alignment tab character &" then
    Some "& only works in tables and alignments such as align: write \\& for an ampersand."
  else if has "fontspec package requires either XeTeX or" then
    Some "fontspec needs XeLaTeX or LuaLaTeX: choose one with Compile With…, or add % !TEX program = xelatex."
  else if has "shell-escape" || has "shell escape" ||
          (has "minted" && has "unavailable or disabled") then
    Some "This package runs external programs: add options = -shell-escape to .bbtex, \
      for documents you trust."
  else None

let warning message =
  let has = contains message in
  if has "Reference `" && has "undefined" then
    Some "No \\label has this key: check its spelling. A new label needs one more build."
  else if has "Citation `" && has "undefined" then
    Some "No bibliography entry has this key: check it against the .bib file, and that \
      the bibliography is loaded."
  else if has "is wrong format version" then
    Some "Biber and biblatex versions don't match: run LaTeX — Doctor."
  else None

(** The hint for a message, starting with "[bbtex] ", or None. *)
let hint severity message =
  Option.map (( ^ ) prefix) (match severity with
    | Error -> error message
    | Warning -> warning message
    | BadBox -> None)

let for_entry (e : log_entry) = hint e.severity e.message
