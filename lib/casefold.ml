(** Unicode full case folding, as Python's str.casefold: "ΣΟΦΊΑ" and "σοφία"
    fold alike, and "Straße" folds to "strasse". Invalid UTF-8 bytes are kept. *)

(* Binary search in the sorted keys; returns the index of [code], if any. *)
let find code =
  let keys = Casefold_data.keys in
  let rec search low high =
    if low > high then None else
    let middle = (low + high) / 2 in
    let key = keys.(middle) in
    if key = code then Some middle
    else if key < code then search (middle + 1) high else search low (middle - 1) in
  search 0 (Array.length keys - 1)

let fold text =
  let b = Buffer.create (String.length text) in
  let rec go i =
    if i < String.length text then
      let c = text.[i] in
      if Char.code c < 0x80 then (Buffer.add_char b (Char.lowercase_ascii c); go (i + 1))
      else
        let d = String.get_utf_8_uchar text i in
        let width = Uchar.utf_decode_length d in
        if not (Uchar.utf_decode_is_valid d) then Buffer.add_string b (String.sub text i width)
        else (match find (Uchar.to_int (Uchar.utf_decode_uchar d)) with
          | Some k ->
            for j = Casefold_data.starts.(k) to Casefold_data.starts.(k + 1) - 1 do
              Buffer.add_utf_8_uchar b (Uchar.of_int Casefold_data.folds.(j))
            done
          | None -> Buffer.add_string b (String.sub text i width));
        go (i + width) in
  go 0;
  Buffer.contents b
