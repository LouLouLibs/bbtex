(** LaTeX log parser — the core value of this tool.

    LaTeX log files are notoriously messy. Key challenges:

    1. **File tracking.** LaTeX prints '(' before entering a file and ')'
       when leaving.  We maintain a file stack to know which file each
       message belongs to.

    2. **Multi-line messages.** An error message starts with '!' and may
       continue across several lines until a blank line or the 'l.<num>'
       line number indicator.

    3. **Warnings.**  LaTeX warnings come in several flavours:
       - "LaTeX Warning:" / "LaTeX Font Warning:"
       - "Package <pkg> Warning:"
       - These can also span multiple lines (continued with spaces).

    4. **Bad boxes.**  "Overfull \hbox ..." / "Underfull \vbox ..." with
       optional "at lines N--M" or "at line N".

    The parser is a single pass over the lines, carrying state via a
    record that tracks the file stack and any in-progress multi-line
    message. *)

open Types

(* ── Helpers ────────────────────────────────────────────────── *)

let starts_with prefix s =
  String.starts_with ~prefix s

let contains_substring ~sub s =
  let ls = String.length s and lsub = String.length sub in
  if lsub > ls then false
  else
    let rec check i =
      if i > ls - lsub then false
      else if String.sub s i lsub = sub then true
      else check (i + 1)
    in
    check 0

(** Extract an int from a string starting at position [i],
    consuming digits.  Returns (the_int, next_position). *)
let scan_int s i =
  let len = String.length s in
  let rec loop j =
    if j < len && s.[j] >= '0' && s.[j] <= '9'
    then loop (j + 1)
    else j
  in
  let j = loop i in
  if j = i then None
  else Some (int_of_string (String.sub s i (j - i)), j)

(* ── File stack management ──────────────────────────────────── *)

(* Extensions of files TeX reads with \input, \usepackage, \documentclass, ... *)
let file_extensions = [
  ".tex"; ".sty"; ".cls"; ".clo"; ".cfg"; ".def"; ".fd"; ".ldf"; ".ltx"; ".dtx";
  ".aux"; ".bbl"; ".toc"; ".lof"; ".lot"; ".out"; ".ind"; ".nav"; ".snm"; ".vrb";
  ".lua"; ".dict"; ".tikz"; ".pgf"; ".mkii"; ".mkiv"; ".bst"; ".cbx"; ".bbx"; ".lbx" ]

let has_file_extension name =
  List.exists (fun ext -> String.ends_with ~suffix:ext (String.lowercase_ascii name)) file_extensions

(** The file name opened by the '(' just before [start], and where it ends.
    TeX prints "(" and the path, unquoted even when it contains spaces
    ("(./my chapter.tex"), or quoted ("(\"./my chapter.tex\""). A name is the
    longest run up to a known extension; failing that, a path starting with
    "/", "./" or "../". Anything else, like "(Fig.2" or "(1.2pt", is text. *)
let file_name_at line start =
  let len = String.length line in
  if start < len && line.[start] = '"' then
    match String.index_from_opt line (start + 1) '"' with
    | Some stop -> Some (String.sub line (start + 1) (stop - start - 1), stop + 1)
    | None -> None
  else begin
    let stop = ref start in
    while !stop < len && line.[!stop] <> ')' && line.[!stop] <> '(' do incr stop done;
    let candidate = String.sub line start (!stop - start) in
    (* Longest prefix ending in an extension, at a word boundary. *)
    let rec longest k best =
      if k > String.length candidate then best
      else
        let boundary = k = String.length candidate || candidate.[k] = ' ' in
        let best = if boundary && has_file_extension (String.sub candidate 0 k)
          then Some k else best in
        longest (k + 1) best in
    match longest 1 None with
    | Some k -> Some (String.sub candidate 0 k, start + k)
    | None ->
      let word = match String.index_opt candidate ' ' with
        | Some k -> String.sub candidate 0 k | None -> candidate in
      if word <> "" && (starts_with "/" word || starts_with "./" word || starts_with "../" word)
      then Some (word, start + String.length word) else None
  end

(** Update the file stack for the '(' and ')' in [line]: '(' plus a file name
    pushes the file, any other '(' pushes a placeholder, ')' pops. Also
    returns the last file closed, if any. *)
let update_file_stack_closing stack line =
  let len = String.length line in
  let stack = ref stack and closed = ref None in
  let i = ref 0 in
  while !i < len do
    (match line.[!i] with
     | '(' ->
       (match file_name_at line (!i + 1) with
        | Some (name, stop) -> stack := name :: !stack; i := stop
        | None -> stack := "" :: !stack; incr i)
     | ')' ->
       (match !stack with
        | top :: rest -> if top <> "" then closed := Some top; stack := rest
        | [] -> ());
       incr i
     | _ -> incr i)
  done;
  !stack, !closed

let update_file_stack stack line = fst (update_file_stack_closing stack line)

(** Return the current file from the stack (topmost non-empty entry). *)
let current_file stack =
  List.find_opt (fun s -> s <> "") stack

(* ── Line classifiers ───────────────────────────────────────── *)

type line_kind =
  | ErrorStart of string          (** '! <message>' *)
  | FileLineError of string * int * string (** 'file:line: message' (-file-line-error format) *)
  | LineIndicator of int * string (** 'l.<N> <context>' *)
  | LatexWarning of string        (** 'LaTeX Warning: ...' etc. *)
  | PackageWarning of string      (** 'Package <pkg> Warning: ...' *)
  | FontWarning of string         (** 'LaTeX Font Warning: ...' *)
  | OverfullBox of string         (** 'Overfull \hbox ...' *)
  | UnderfullBox of string        (** 'Underfull \hbox ...' *)
  | ContinuationLine of string    (** indented line continuing a warning *)
  | PackageContinuation of string (** "(pkg)   text" continuing a package warning *)
  | OtherLine of string           (** anything else *)

(** Try to parse a -file-line-error format line: "file:line: message".
    Returns Some (file, line_num, message) or None. *)
let try_file_line_error line =
  (* Find first colon — must be preceded by a path-like string *)
  let len = String.length line in
  let rec find_colon i =
    if i >= len then None
    else if line.[i] = ':' then
      let path = String.sub line 0 i in
      (* Must look like a file path: contains '.' or '/' *)
      if (contains_substring ~sub:"." path || contains_substring ~sub:"/" path)
         && i + 1 < len then
        (* Next part must be digits followed by ": " *)
        (match scan_int line (i + 1) with
         | Some (n, pos) when pos + 1 < len && line.[pos] = ':' && line.[pos + 1] = ' ' ->
           let msg = String.sub line (pos + 2) (len - pos - 2) in
           Some (path, n, msg)
         | _ -> find_colon (i + 1))
      else find_colon (i + 1)
    else find_colon (i + 1)
  in
  find_colon 0

let classify_line line =
  let trimmed = String.trim line in
  if starts_with "! " line then
    ErrorStart (String.sub line 2 (String.length line - 2))
  else if starts_with "l." line then
    (* Try to parse l.<digits> — TeX always puts this at column 0 *)
    (match scan_int line 2 with
     | Some (n, pos) ->
       let rest = if pos < String.length line
                  then String.sub line pos (String.length line - pos)
                  else "" in
       LineIndicator (n, String.trim rest)
     | None -> OtherLine line)
  else if starts_with "LaTeX Warning:" line then
    LatexWarning (String.trim (String.sub line 14 (String.length line - 14)))
  else if starts_with "LaTeX Font Warning:" line then
    FontWarning (String.trim (String.sub line 19 (String.length line - 19)))
  else if contains_substring ~sub:"Warning:" line
          && contains_substring ~sub:"Package" line then
    (* "Package foo Warning: blah" — extract message after "Warning: " *)
    let warning_tag = "Warning: " in
    let ltag = String.length warning_tag in
    let lline = String.length line in
    let rec find_warning_pos i =
      if i > lline - ltag then None
      else if String.sub line i ltag = warning_tag then
        Some (i + ltag)
      else find_warning_pos (i + 1)
    in
    (match find_warning_pos 0 with
     | Some pos ->
       let after = String.trim (String.sub line pos (lline - pos)) in
       PackageWarning after
     | None -> OtherLine line)
  else if starts_with "Overfull" trimmed then
    OverfullBox trimmed
  else if starts_with "Underfull" trimmed then
    UnderfullBox trimmed
  else if String.length line > 0
          && (line.[0] = ' ' || line.[0] = '\t')
          && String.length trimmed > 0 then
    ContinuationLine trimmed
  else if starts_with "(" line && (match String.index_opt line ')' with
      | Some k -> k > 1 && k + 1 < String.length line && line.[k + 1] = ' '
                  && not (String.contains (String.sub line 1 (k - 1)) ' ')
      | None -> false) then
    let k = String.index line ')' in
    PackageContinuation (String.trim (String.sub line (k + 1) (String.length line - k - 1)))
  else
    (* Try -file-line-error format: "file.tex:69: Undefined control sequence." *)
    match try_file_line_error line with
    | Some (file, n, msg) -> FileLineError (file, n, msg)
    | None -> OtherLine line

(* ── Bad-box line number extraction ─────────────────────────── *)

(** Extract line number from a bad-box message.
    Formats: "... at lines 42--55", "... at line 42" *)
let extract_box_line_number msg =
  (* Search for "at lines N--M" *)
  let try_pattern () =
    let patterns = ["at lines "; "at line "] in
    let rec try_pats = function
      | [] -> None
      | pat :: rest ->
        let lpat = String.length pat in
        let lmsg = String.length msg in
        let rec search i =
          if i > lmsg - lpat then try_pats rest
          else if String.sub msg i lpat = pat then
            scan_int msg (i + lpat) |> Option.map fst
          else search (i + 1)
        in
        search 0
    in
    try_pats patterns
  in
  try_pattern ()

(* ── Extract line number from warning messages ──────────────── *)

(** Warnings sometimes contain "on input line <N>" *)
let extract_warning_line msg =
  let pat = "on input line " in
  let lpat = String.length pat in
  let lmsg = String.length msg in
  let rec search i =
    if i > lmsg - lpat then None
    else if String.sub msg i lpat = pat then
      scan_int msg (i + lpat) |> Option.map fst
    else search (i + 1)
  in
  search 0

(* ── Parser state ───────────────────────────────────────────── *)

type parse_state = {
  file_stack : string list;
  entries : log_entry list;     (** accumulated entries, reversed *)
  (* In-progress multi-line error *)
  in_error : bool;
  error_message : string;
  error_context : string list;
  error_file : string option;
  error_line : int option;      (** line number from -file-line-error format *)
  error_blank_lines : int;      (** consecutive blank lines seen in error *)
  (* In-progress multi-line warning *)
  in_warning : bool;
  warning_severity : severity;
  warning_message : string;
  warning_file : string option;
  in_box : bool;                (** inside the contents printed after a bad box *)
  after_context : bool;         (** the line after "l.<N>" continues the excerpt *)
  last_closed : string option;  (** for messages after every file has closed *)
}

let empty_state = {
  file_stack = [];
  entries = [];
  in_error = false;
  error_message = "";
  error_context = [];
  error_file = None;
  error_line = None;
  error_blank_lines = 0;
  in_warning = false;
  warning_severity = Warning;
  warning_message = "";
  warning_file = None;
  in_box = false;
  after_context = false;
  last_closed = None;
}

(** Finish any in-progress error, returning updated state. *)
let flush_error st =
  if not st.in_error then st
  else
    let entry = {
      severity = Error;
      file = st.error_file;
      line = st.error_line;
      message = st.error_message;
      context = List.rev st.error_context;
    } in
    { st with
      in_error = false;
      error_message = "";
      error_context = [];
      error_file = None;
      error_line = None;
      error_blank_lines = 0;
      entries = entry :: st.entries }

(** Finish any in-progress warning, returning updated state. *)
let flush_warning st =
  if not st.in_warning then st
  else
    let line_num = extract_warning_line st.warning_message in
    let entry = {
      severity = st.warning_severity;
      file = st.warning_file;
      line = line_num;
      message = st.warning_message;
      context = [];
    } in
    { st with
      in_warning = false;
      warning_message = "";
      warning_file = None;
      entries = entry :: st.entries }

(** Process one line, returning the new state. *)
let process_line st line =
  let kind = classify_line line in
  (* Text TeX copies from the document (error excerpts, box contents) can hold
     any parentheses; only the rest of the log opens and closes files. *)
  let copied = st.in_error || st.in_box || st.after_context || (match kind with
      | ErrorStart _ | FileLineError _ | LineIndicator _ | OverfullBox _ | UnderfullBox _ -> true
      | _ -> false) in
  let in_box = (match kind with
      | OverfullBox _ | UnderfullBox _ -> true
      | _ -> st.in_box && String.trim line <> "") in
  let after_context = (match kind with LineIndicator _ -> st.in_error | _ -> false) in
  let file_stack, closed =
    if copied then st.file_stack, None else update_file_stack_closing st.file_stack line in
  let last_closed = if closed = None then st.last_closed else closed in
  let st = { st with file_stack; in_box; after_context; last_closed } in
  (* "File ended while scanning ..." and "Emergency stop" come after TeX has
     closed the file at fault; point them at it rather than at nothing. *)
  let cur_file = match current_file file_stack with
    | Some _ as file -> file | None -> last_closed in
  match kind with
  | ErrorStart msg ->
    (* Flush any previous incomplete error/warning *)
    let st = flush_error st in
    let st = flush_warning st in
    { st with
      in_error = true;
      error_message = msg;
      error_context = [];
      error_file = cur_file;
      error_line = None;
      error_blank_lines = 0 }

  | FileLineError (file, n, msg) ->
    (* -file-line-error format: "file.tex:69: message" — already has file+line.
       Enter error state; the l.<N> line that follows will complete it with
       context text. If no l.<N> comes, flush_error emits with the line we
       already have. *)
    let st = flush_error st in
    let st = flush_warning st in
    { st with
      in_error = true;
      error_message = msg;
      error_context = [];
      error_file = Some file;
      error_line = Some n;
      error_blank_lines = 0 }

  | LineIndicator (n, ctx) when st.in_error ->
    (* This completes the current error with a line number.
       Prefer file-line-error line if available, fall back to l.<N>. *)
    let line_num = match st.error_line with Some l -> l | None -> n in
    let context = if ctx <> ""
                  then List.rev (ctx :: st.error_context)
                  else List.rev st.error_context in
    let entry = {
      severity = Error;
      file = st.error_file;
      line = Some line_num;
      message = st.error_message;
      context;
    } in
    { st with
      in_error = false;
      error_message = "";
      error_context = [];
      error_file = None;
      error_line = None;
      error_blank_lines = 0;
      entries = entry :: st.entries }

  | LineIndicator (_, _) ->
    (* Line indicator outside error context — ignore *)
    st

  | LatexWarning msg | FontWarning msg ->
    let st = flush_error st in
    let st = flush_warning st in
    { st with
      in_warning = true;
      warning_severity = Warning;
      warning_message = msg;
      warning_file = cur_file }

  | PackageWarning msg ->
    let st = flush_error st in
    let st = flush_warning st in
    { st with
      in_warning = true;
      warning_severity = Warning;
      warning_message = msg;
      warning_file = cur_file }

  | OverfullBox msg | UnderfullBox msg ->
    let st = flush_error st in
    let st = flush_warning st in
    let line_num = extract_box_line_number msg in
    let entry = {
      severity = BadBox;
      file = cur_file;
      line = line_num;
      message = msg;
      context = [];
    } in
    { st with entries = entry :: st.entries }

  | PackageContinuation text when st.in_warning ->
    { st with warning_message = st.warning_message ^ " " ^ text }

  | PackageContinuation _ -> st

  | ContinuationLine text ->
    if st.in_error then
      { st with error_context = text :: st.error_context }
    else if st.in_warning then
      (* Append to warning message *)
      { st with warning_message = st.warning_message ^ " " ^ text }
    else
      st

  | OtherLine _ ->
    (* A non-indented, non-special line may terminate a warning *)
    if st.in_warning then flush_warning st
    else if st.in_error then begin
      (* Could be a continuation of the error message body.
         LaTeX errors like "! LaTeX Error: ..." are followed by
         blank lines, help text ("See the LaTeX manual..."),
         and then eventually "l.<N>".  We tolerate up to 3
         consecutive blank lines before giving up. *)
      let trimmed = String.trim line in
      if trimmed = "" then begin
        if st.error_blank_lines >= 2 then flush_error st
        else { st with error_blank_lines = st.error_blank_lines + 1 }
      end else
        { st with
          error_context = trimmed :: st.error_context;
          error_blank_lines = 0 }
    end
    else st

(* ── Line unwrapping ───────────────────────────────────────── *)

(** TeX hard-wraps log output at [max_print_line] characters (79 in TeX Live):
    bytes for pdfTeX, Unicode characters for XeTeX and LuaTeX. A physical line
    that long was likely wrapped; join it with the next one, unless that one
    starts an error. This is the heuristic LaTeXTools and texlab use too. *)
let full_line line =
  String.length line = 79 || (String.length line > 79 && begin
    let chars = ref 0 in
    String.iter (fun c -> if Char.code c land 0xc0 <> 0x80 then incr chars) line;
    !chars = 79
  end)

let unwrap_lines lines =
  let buf = Buffer.create 256 in
  let rec go acc = function
    | [] ->
      if Buffer.length buf > 0 then
        List.rev (Buffer.contents buf :: acc)
      else
        List.rev acc
    | line :: rest ->
      Buffer.add_string buf line;
      let next_is_error = match rest with next :: _ -> starts_with "! " next | [] -> false in
      if full_line line && not next_is_error then
        (* Physical line was wrapped — continue collecting *)
        go acc rest
      else begin
        (* End of logical line *)
        let result = Buffer.contents buf in
        Buffer.clear buf;
        go (result :: acc) rest
      end
  in
  go [] lines

(* ── Public interface ───────────────────────────────────────── *)

(** Parse a list of lines, returning log entries in order. *)
let parse_lines lines =
  let lines = unwrap_lines lines in
  let final_state = List.fold_left process_line empty_state lines in
  let final_state = flush_error final_state in
  let final_state = flush_warning final_state in
  List.rev final_state.entries

(** Parse a log file by filename. *)
let parse_file filename =
  let ic = open_in filename in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
    let rec read_all acc =
      match input_line ic with
      | line -> read_all (line :: acc)
      | exception End_of_file -> List.rev acc
    in
    let lines = read_all [] in
    parse_lines lines)
