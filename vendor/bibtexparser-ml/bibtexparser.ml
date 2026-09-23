(* Port of python-bibtexparser 2.0.1's splitter.py (MIT, Copyright (c) 2021
   Michael Weiss). The structure follows the original closely so upstream
   changes can be carried over; names in comments refer to its methods. *)

type field = { name : string; value : string }
type block =
  | Entry of { line : int; entry_type : string; key : string; fields : field list }
  | String of { line : int; key : string; value : string }
  | Preamble of { line : int; value : string }
  | Comment of { line : int }
  | Duplicate_key of { line : int; key : string; ignored : block }
  | Duplicate_field of { line : int; key : string; names : string list; ignored : block }
  | Failed of { line : int; reason : string }

exception Abort of string

(* A mark is a delimiter character, or a block start: "@type" plus optional
   blanks, ending just before its opening "{" or "(". *)
type mark = { start : int; stop : int; char : char (* '@' for a block start *) }

type state = {
  text : string;
  mutable cursor : int;           (* where the next mark search begins *)
  mutable paren : bool;           (* ")" is a mark inside "(" blocks *)
  mutable pending : mark option;  (* _unaccepted_mark *)
  mutable last : int;             (* _current_char_index *)
  mutable line : int;             (* _current_line *)
  mutable closing : char;         (* _closing_delimiter *)
}

(* Python's \w, approximated: any non-ASCII byte counts as a word character. *)
let is_word = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
  | c -> Char.code c >= 0x80

let is_space = function
  | ' ' | '\t' | '\n' | '\r' | '\011' | '\012' | '\028' .. '\031' -> true
  | _ -> false

(* Python's str.strip(): ASCII whitespace plus the common Unicode spaces. *)
let strip s =
  let n = String.length s in
  let space_at i =
    if i < n && is_space s.[i] then 1
    else if i + 1 < n && s.[i] = '\xc2' && (s.[i + 1] = '\x85' || s.[i + 1] = '\xa0') then 2
    else if i + 2 < n && s.[i] = '\xe2' && s.[i + 1] = '\x80'
            && (Char.code s.[i + 2] <= 0x8a || s.[i + 2] = '\xa8' || s.[i + 2] = '\xa9'
                || s.[i + 2] = '\xaf') then 3
    else if i + 2 < n && s.[i] = '\xe2' && s.[i + 1] = '\x81' && s.[i + 2] = '\x9f' then 3
    else if i + 2 < n && s.[i] = '\xe3' && s.[i + 1] = '\x80' && s.[i + 2] = '\x80' then 3
    else if i + 2 < n && s.[i] = '\xe1' && s.[i + 1] = '\x9a' && s.[i + 2] = '\x80' then 3
    else 0 in
  let space_before j =
    let rec width k =
      if k > 3 then 0 else if j - k >= 0 && space_at (j - k) = k then k else width (k + 1) in
    width 1 in
  let rec left i = match space_at i with 0 -> i | k -> left (i + k) in
  let rec right j lo = if j <= lo then j else match space_before j with 0 -> j | k -> right (j - k) lo in
  let i = left 0 in
  let j = right n i in
  String.sub s i (j - i)

let sub st first stop = String.sub st.text first (stop - first)

(* _MARK_PATTERN and _PAREN_BLOCK_MARK_PATTERN. *)
let find_mark st =
  let s = st.text and n = String.length st.text in
  let unescaped i = i = 0 || s.[i - 1] <> '\\' in
  let rec go i =
    if i >= n then None
    else match s.[i] with
      | ('{' | '}' | '"' | ',' | '=' | '\n') as c when unescaped i ->
        Some { start = i; stop = i + 1; char = c }
      | ')' when st.paren && unescaped i -> Some { start = i; stop = i + 1; char = ')' }
      | '@' ->
        let j = ref (i + 1) in
        while !j < n && is_word s.[!j] do incr j done;
        while !j < n && (s.[!j] = ' ' || s.[!j] = '\t') do incr j done;
        if !j < n && (s.[!j] = '{' || s.[!j] = '(') then Some { start = i; stop = !j; char = '@' }
        else go (i + 1)
      | _ -> go (i + 1) in
  go st.cursor

(* _next_mark: newlines are counted, never returned. *)
let rec next_mark st ~eof_ok =
  match st.pending with
  | Some m -> st.pending <- None; st.last <- m.start; Some m
  | None ->
    match find_mark st with
    | None ->
      st.last <- String.length st.text;
      if eof_ok then None else raise (Abort "Unexpectedly reached end of file.")
    | Some m ->
      st.cursor <- m.stop; st.last <- m.start;
      if m.char = '\n' then (st.line <- st.line + 1; next_mark st ~eof_ok) else Some m

let next st = Option.get (next_mark st ~eof_ok:false)

(* Puts [m] back and aborts the block. *)
let abort st m reason = st.pending <- Some m; raise (Abort reason)

(* _is_at_line_start *)
let at_line_start st pos =
  let rec back i = i < 0 || st.text.[i] = '\n' || (is_space st.text.[i] && back (i - 1)) in
  back (pos - 1)

let open_block st m =
  if st.text.[m.stop] = '(' then begin
    st.closing <- ')'; st.paren <- true; st.cursor <- m.stop + 1
  end else begin
    st.closing <- '}'; ignore (next st)
  end

let close_block st =
  if st.closing = ')' then begin
    st.cursor <- (match st.pending with Some m -> m.stop | None -> st.last + 1);
    st.paren <- false; st.closing <- '}'
  end

(* _move_to_closing_delimiter: the index of the block's closing delimiter. *)
let to_closing st ~track_quotes =
  let track_quotes = track_quotes && st.closing = ')' in
  let rec go curls quoted =
    let m = next st in
    if m.char = '{' then go (curls + 1) quoted
    else if m.char = '}' && curls > 0 then go (curls - 1) quoted
    else if curls = 0 && m.char = '"' && track_quotes then go curls (not quoted)
    else if curls = 0 && m.char = st.closing && not quoted then m.start
    else if m.char = '@' && at_line_start st m.start then
      abort st m "Unexpected block start. Was still looking for closing bracket"
    else go curls quoted in
  go 0 false

(* _move_to_comma_or_closing_delimiter: the index where a field value ends. *)
let to_value_end st =
  let s = st.text in
  let rec go quoted curls =
    let m = next st in
    if m.char = '"' && curls = 0 then
      (* A brace-wrapped quote is a literal quote inside a quoted value. *)
      if quoted && m.start > 0 && m.start + 2 < String.length s
         && s.[m.start - 1] = '{' && s.[m.start + 1] = '}' then go quoted curls
      else go (not quoted) curls
    else if m.char = '{' && not quoted then go quoted (curls + 1)
    else if m.char = '}' && not quoted && curls > 0 then go quoted (curls - 1)
    else if (m.char = ',' || m.char = st.closing) && not quoted && curls = 0 then
      (st.pending <- Some m; m.start)
    else if m.char = '@' && at_line_start st m.start then
      abort st m "Unexpected block start. Was still looking for field-value closing"
    else go quoted curls in
  go false 0

(* _move_to_end_of_entry: the fields, and the sorted repeated field names. *)
let fields st first_key =
  let seen = Hashtbl.create 16 and repeated = ref [] in
  let rec go key_start acc =
    let m = next st in
    if m.char = st.closing then begin
      if strip (sub st key_start m.start) <> "" then
        raise (Abort "Expected a `=` after entry key, but found the end of the entry.");
      List.rev acc
    end
    else if m.char <> '=' then abort st m "Expected a `=` after entry key."
    else begin
      let value_end = to_value_end st in
      let name = strip (sub st key_start m.start) in
      let value = strip (sub st m.stop value_end) in
      if Hashtbl.mem seen name && not (List.mem name !repeated) then repeated := name :: !repeated;
      Hashtbl.replace seen name ();
      let acc = { name; value } :: acc in
      let after = next st in
      if after.char = ',' then go after.stop acc
      else if after.char = st.closing then (st.pending <- Some after; go after.start acc)
      else abort st after "Expected either a `,` or the closing delimiter after a field value."
    end in
  let fields = go first_key [] in
  fields, List.sort compare !repeated

(* _handle_entry *)
let entry st m entry_type line =
  let comma = next st in
  let key () = strip (sub st (m.stop + 1) comma.start) in
  if comma.char = st.closing then Entry { line; entry_type; key = key (); fields = [] }
  else if comma.char <> ',' then abort st comma "Expected comma after entry key."
  else
    let key = key () in
    match fields st comma.stop with
    | fields, [] -> Entry { line; entry_type; key; fields }
    | fields, names ->
      Duplicate_field { line; key; names; ignored = Entry { line; entry_type; key; fields } }

(* _handle_string *)
let string_block st m line =
  let eq = next st in
  if eq.char <> '=' then abort st eq "Expected equals sign after field key.";
  let key = strip (sub st (m.stop + 1) eq.start) in
  let value_end = to_closing st ~track_quotes:true in
  String { line; key; value = strip (sub st eq.stop value_end) }

let parse_string text =
  (* A leading newline lets a block start on the first line, as upstream. *)
  let st = { text = "\n" ^ text; cursor = 0; paren = false; pending = None;
             last = 0; line = -1; closing = '}' } in
  let entries = Hashtbl.create 256 and strings = Hashtbl.create 64 in
  (* Library._add_to_dicts *)
  let dedupe = function
    | Entry { line; key; _ } as b when Hashtbl.mem entries key -> Duplicate_key { line; key; ignored = b }
    | Entry { key; _ } as b -> Hashtbl.replace entries key (); b
    | String { line; key; _ } as b when Hashtbl.mem strings key -> Duplicate_key { line; key; ignored = b }
    | String { key; _ } as b -> Hashtbl.replace strings key (); b
    | b -> b in
  let rec loop acc =
    match next_mark st ~eof_ok:true with
    | None -> List.rev acc
    | Some m when m.char <> '@' -> loop acc
    | Some m ->
      let start = String.lowercase_ascii (sub st m.start m.stop) in
      let is kind = String.starts_with ~prefix:kind start in
      let line = st.line in
      let block =
        try
          open_block st m;
          if is "@comment" then (ignore (to_closing st ~track_quotes:false); Comment { line })
          else if is "@preamble" then
            let value_end = to_closing st ~track_quotes:true in
            Preamble { line; value = sub st (m.stop + 1) value_end }
          else if is "@string" then string_block st m line
          else entry st m (strip (String.sub start 1 (String.length start - 1))) line
        with Abort reason -> Failed { line; reason } in
      close_block st;
      loop (dedupe block :: acc) in
  loop []

let parse_file path =
  let ic = open_in_bin path in
  let raw = Fun.protect ~finally:(fun () -> close_in ic)
      (fun () -> really_input_string ic (in_channel_length ic)) in
  let bom = "\xef\xbb\xbf" in
  let text =
    if String.starts_with ~prefix:bom raw then String.sub raw 3 (String.length raw - 3) else raw in
  if String.is_valid_utf_8 text then Ok (parse_string text) else Error (path ^ ": not valid UTF-8")

let line = function
  | Entry { line; _ } | String { line; _ } | Preamble { line; _ } | Comment { line }
  | Duplicate_key { line; _ } | Duplicate_field { line; _ } | Failed { line; _ } -> line
