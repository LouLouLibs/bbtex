(** Just enough TeX lexing to find commands and their arguments in saved
    source: comments and verbatim text are blanked, positions are kept. *)

let starts text pos value = pos + String.length value <= String.length text &&
  String.sub text pos (String.length value) = value
let space = function ' ' | '\t' | '\r' | '\n' -> true | _ -> false
let rec skip text i = if i < String.length text && space text.[i] then skip text (i + 1) else i
let letter = function 'a'..'z' | 'A'..'Z' | '@' -> true | _ -> false
let command text i =
  let j = ref (i + 1) in
  if !j < String.length text && letter text.[!j] then
    while !j < String.length text && letter text.[!j] do incr j done
  else if !j < String.length text then incr j;
  String.sub text (i + 1) (!j - i - 1), !j

let group text pos opening closing =
  let i = skip text pos in
  if i >= String.length text || text.[i] <> opening then None else
  let rec scan j depth =
    if j >= String.length text then None
    else if text.[j] = '\\' then scan (min (String.length text) (j + 2)) depth
    else if text.[j] = closing && depth = 1 then
      Some (String.sub text (i + 1) (j - i - 1), j + 1)
    else scan (j + 1) (depth + (if text.[j] = opening then 1 else if text.[j] = closing then -1 else 0))
  in scan (i + 1) 1
let argument text pos = group text pos '{' '}'
let optional text pos = match group text pos '[' ']' with None -> pos | Some (_, j) -> j
let star text pos = if pos < String.length text && text.[pos] = '*' then pos + 1 else pos
let find text start value =
  let rec loop i = if i + String.length value > String.length text then String.length text
    else if starts text i value then i else loop (i + 1) in loop start

(* Preserve byte positions and newlines while excluding comments and literal text. *)
let visible text =
  let result = Bytes.of_string text in
  let blank a b = for i = a to b - 1 do
    if text.[i] <> '\n' && text.[i] <> '\r' then Bytes.set result i ' ' done in
  let rec scan i = if i < String.length text then
    if text.[i] = '%' then begin
      let j = ref i in
      while !j < String.length text && text.[!j] <> '\n' && text.[!j] <> '\r' do incr j done;
      blank i !j; scan !j
    end else if text.[i] = '\\' then begin
      let name, next = command text i in
      if List.mem name ["verb"; "lstinline"] then begin
        let d = optional text (star text next) |> skip text in
        let stop = if d >= String.length text || space text.[d] then d else
          min (String.length text) (find text (d + 1) (String.make 1 text.[d]) + 1) in
        blank i stop; scan stop
      end else if name = "begin" then match argument text next with
        | Some (env, j) when List.mem env ["verbatim"; "verbatim*"; "Verbatim"; "BVerbatim";
            "lstlisting"; "minted"; "comment"] ->
          let ending = "\\end{" ^ env ^ "}" in
          let stop = min (String.length text) (find text j ending + String.length ending) in
          blank i stop; scan stop
        | _ -> scan next
      else scan next
    end else scan (i + 1)
  in scan 0; Bytes.to_string result
