(** Unicode text keys for matching, from uucp and uunf.

    [fold] is full case folding, as Python's str.casefold: "ΣΟΦΊΑ" and
    "σοφία" fold alike, and "Straße" folds to "strasse".

    [search_key] also ignores accents: the text is decomposed (NFD) and
    combining marks are dropped before folding, so "garcia" matches "García"
    and "muller" matches "Müller". Letters without a decomposition, such as
    "ø" or "ł", keep their identity. Invalid UTF-8 becomes U+FFFD. *)

let iter_utf_8 f text =
  let rec go i =
    if i < String.length text then begin
      let d = String.get_utf_8_uchar text i in
      f (Uchar.utf_decode_uchar d);
      go (i + Uchar.utf_decode_length d)
    end in
  go 0

let add_folded b u = match Uucp.Case.Fold.fold u with
  | `Self -> Buffer.add_utf_8_uchar b u
  | `Uchars folded -> List.iter (Buffer.add_utf_8_uchar b) folded

let fold text =
  let b = Buffer.create (String.length text) in
  iter_utf_8 (fun u ->
    if Uchar.to_int u < 0x80 then Buffer.add_char b (Char.lowercase_ascii (Uchar.to_char u))
    else add_folded b u) text;
  Buffer.contents b

let search_key text =
  let b = Buffer.create (String.length text) in
  let normalizer = Uunf.create `NFD in
  let rec emit v = match Uunf.add normalizer v with
    | `Uchar u -> if Uucp.Gc.general_category u <> `Mn then add_folded b u; emit `Await
    | `Await | `End -> () in
  iter_utf_8 (fun u -> emit (`Uchar u)) text;
  emit `End;
  Buffer.contents b
