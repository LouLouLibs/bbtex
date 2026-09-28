open Bbtex

(* Each sample log is a real TeX Live 2026 pdfLaTeX run, with -file-line-error
   as bbtex compiles. [expect] is the first message carrying a hint and a
   phrase of that hint. *)
let cases = [
  "undefined-control-sequence", "Undefined control sequence.", "A command isn't defined";
  "missing-dollar", "Missing $ inserted.", "Math outside math mode";
  "missing-package", "LaTeX Error: File `bbtexnosuchpackage.sty' not found.",
    "bbtexnosuchpackage.sty isn't installed";
  "undefined-environment", "LaTeX Error: Environment theorem undefined.", "environment isn't defined";
  "missing-begin-document", "LaTeX Error: Missing \\begin{document}.", "Text before \\begin{document}";
  "file-ended", "File ended while scanning use of \\textbf .", "argument never ends";
  "paragraph-ended", "Paragraph ended before \\@sect was complete.", "argument never ends";
  "too-many-braces", "Too many }'s.", "Braces don't balance";
  "extra-brace", "Extra }, or forgotten $.", "Braces don't balance";
  "misplaced-alignment", "Misplaced alignment tab character &.", "write \\& for an ampersand";
  "undefined-references", "Reference `sec:none' on page 1 undefined on input line 3.", "No \\label has this key";
  "fontspec-pdflatex", "Fatal Package fontspec Error: The fontspec package requires either XeTeX or",
    "XeLaTeX or LuaLaTeX";
  "minted-shell-escape", "Package minted Error: Missing definition for highlighting style \"default\" \
    (minted executable is unavailable or disabled); attempting to substitute fallback style.",
    "options = -shell-escape";
  "biblatex-version", "File 'biblatex-version.bbl' is wrong format version - expected 3.3.",
    "Biber and biblatex versions don't match";
]

let contains = Log_parser.contains_substring

let () =
  List.iter (fun (name, message, phrase) ->
    let entries = Log_parser.parse_file (Printf.sprintf "../testdata/logs/hint-%s.log" name) in
    match List.find_opt (fun e -> Error_hints.for_entry e <> None) entries with
    | None -> failwith (name ^ ": no hint")
    | Some e ->
      let hint = Option.get (Error_hints.for_entry e) in
      if e.message <> message || not (contains ~sub:phrase hint) then
        failwith (Printf.sprintf "%s: %S got %S" name e.message hint);
      assert (String.starts_with ~prefix:"[bbtex] " hint)) cases;
  print_endline "Error hints: every sample log gets its hint"

let () =
  let hint = Error_hints.hint in
  (* Citations, and files that aren't packages. *)
  assert (contains ~sub:"against the .bib file"
    (Option.get (hint Types.Warning "Citation `nokey' on page 1 undefined on input line 3.")));
  assert (contains ~sub:"relative to the root file"
    (Option.get (hint Types.Error "LaTeX Error: File `chapters/intro.tex' not found.")));
  (* Unrecognised messages, follow-on errors, summaries and bad boxes get nothing. *)
  List.iter (fun (severity, message) -> assert (hint severity message = None)) [
    Types.Error, "Emergency stop.";
    Types.Error, " ==> Fatal error occurred, no output PDF file produced!";
    Types.Error, "LaTeX Error: Something new and unusual.";
    Types.Warning, "There were undefined references.";
    Types.Warning, "Please rerun LaTeX.";
    Types.Warning, "Shell escape disabled on input line 73.";
    Types.BadBox, "Undefined control sequence.";
    Types.BadBox, "Overfull \\hbox (1.0pt too wide) in paragraph at lines 3--4";
  ];
  print_endline "Error hints: unrecognised messages get no hint"

let () =
  (* TeX's message is kept verbatim; the hint follows it in every format. *)
  let entry = { Types.severity = Types.Error; file = Some "main.tex"; line = Some 7;
                message = "Undefined control sequence."; context = ["l.7 \\foo"] } in
  assert (Bbedit_format.format_bbedit_all [entry] = [
    "main.tex:7: error: Undefined control sequence.";
    "main.tex:7: note: [bbtex] A command isn't defined: check for a typo, or a missing \\usepackage."]);
  let text = Bbedit_format.format_text_entry entry in
  assert (contains ~sub:"  Undefined control sequence.\n" text);
  assert (contains ~sub:"  [bbtex] A command isn't defined: check for a typo, or a missing \\usepackage.\n" text);
  let plain = { entry with message = "Emergency stop." } in
  assert (List.length (Bbedit_format.format_bbedit_all [plain]) = 1);
  assert (not (contains ~sub:"[bbtex]" (Bbedit_format.format_text_entry plain)));
  let search = { Types.se_file = "/tmp/main.tex"; se_line = 7; se_severity = Types.Error;
                 se_message = "Undefined control sequence." } in
  let script = Applescript.compile_script [search] in
  assert (contains ~sub:{|message:"Undefined control sequence."|} script);
  assert (contains ~sub:{|{result_kind:note_kind, result_file:POSIX file "/tmp/main.tex" as alias, result_line:7, message:"[bbtex] A command isn't defined|} script);
  print_endline "Error hints: text, BBEdit and results-browser output passed"
