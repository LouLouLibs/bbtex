(** Live selection preview: classify a buffer fragment and debounce polled
    selections. Pure logic; Live_watch runs the loop and the BBEdit glue. *)

type fragment = Math of string | Text of string
type verdict = Empty | Invalid of string | Fragment of fragment

let max_bytes = 20_000
let math_environments = ["equation"; "equation*"; "align"; "align*"; "gather"; "gather*";
  "multline"; "multline*"; "displaymath"; "flalign"; "flalign*"; "math"]

let contains text needle =
  let n = String.length text and m = String.length needle in
  let rec at i = i + m <= n && (String.sub text i m = needle || at (i + 1)) in at 0

let matches text i token = i + String.length token <= String.length text &&
  String.sub text i (String.length token) = token

(* The environment name after [keyword] at [i], and the index after its brace. *)
let name_after text i keyword =
  if not (matches text i keyword) then None else
  let start = i + String.length keyword in
  match String.index_from_opt text start '}' with
  | Some stop -> Some (String.sub text start (stop - start), stop + 1)
  | None -> None

(* Index of the last [needle] in [text]. *)
let last_index text needle =
  let m = String.length needle in
  let rec back i = if i < 0 then None else if text.[i] = needle.[0] && matches text i needle then Some i else back (i - 1) in
  back (String.length text - m)

(* Only the body counts: a preamble macro such as \newcommand\be{\begin{equation}}
   must not turn all prose into math. *)
let in_math text =
  let start = match last_index text "\\begin{document}" with
    | Some i -> i + String.length "\\begin{document}" | None -> 0 in
  let n = String.length text in
  let toggle d = function top :: rest when top = d -> rest | stack -> d :: stack in
  let pop d = function top :: rest when top = d -> rest | stack -> stack in
  let rec scan i comment stack =
    if i >= n then stack <> []
    else if text.[i] = '\n' || text.[i] = '\r' then scan (i + 1) false stack
    else if comment then scan (i + 1) true stack
    else if text.[i] = '%' then scan (i + 1) true stack
    else if matches text i "$$" then scan (i + 2) false (toggle "$$" stack)
    else if text.[i] = '$' then scan (i + 1) false (toggle "$" stack)
    else if matches text i "\\[" then scan (i + 2) false ("\\]" :: stack)
    else if matches text i "\\(" then scan (i + 2) false ("\\)" :: stack)
    else if matches text i "\\]" || matches text i "\\)" then
      scan (i + 2) false (pop (String.sub text i 2) stack)
    else match name_after text i "\\begin{", name_after text i "\\end{" with
      | Some (name, next), _ when List.mem name math_environments ->
        scan next false (("\\end{" ^ name ^ "}") :: stack)
      | _, Some (name, next) -> scan next false (pop ("\\end{" ^ name ^ "}") stack)
      | _ -> scan (i + if text.[i] = '\\' && i + 1 < n then 2 else 1) false stack
  in scan start false []

(* Braces and \begin/\end pairs nest correctly outside comments. *)
let balanced text =
  let n = String.length text in
  let rec scan i comment depth envs =
    if i >= n then depth = 0 && envs = [] else
    match text.[i] with
    | '\n' | '\r' -> scan (i + 1) false depth envs
    | _ when comment -> scan (i + 1) true depth envs
    | '%' -> scan (i + 1) true depth envs
    | '{' -> scan (i + 1) false (depth + 1) envs
    | '}' -> depth > 0 && scan (i + 1) false (depth - 1) envs
    | '\\' ->
      (match name_after text i "\\begin{", name_after text i "\\end{" with
       | Some (name, next), _ -> scan next false depth (name :: envs)
       | _, Some (name, next) ->
         (match envs with top :: rest when top = name -> scan next false depth rest | _ -> false)
       | _ -> scan (min n (i + 2)) false depth envs)
    | _ -> scan (i + 1) false depth envs
  in scan 0 false 0 []

let delimited s =
  List.exists (fun prefix -> String.starts_with ~prefix s) ["$"; "\\["; "\\("] ||
  List.exists (fun env -> String.starts_with ~prefix:("\\begin{" ^ env ^ "}") s) math_environments

let classify ~prefix ~selected =
  let s = String.trim selected in
  if s = "" then Empty
  else if String.length s > max_bytes then
    Invalid "Selection is larger than 20 KB. Use Preview Selection or a full build."
  else if List.exists (contains s) ["\\documentclass"; "\\begin{document}"; "\\end{document}"] then
    Invalid "Select a fragment, not the document structure."
  else if not (balanced s) then Invalid "Selection has unbalanced braces or environments."
  else if in_math s then Invalid "Selection has an unclosed math delimiter."
  else if delimited s || in_math prefix then Fragment (Math s)
  else Fragment (Text s)

let body = function
  | Math s when delimited s -> s
  | Math s when String.contains s '&' || contains s "\\\\" -> "\\begin{align*}\n" ^ s ^ "\n\\end{align*}"
  | Math s -> "\\[\n" ^ s ^ "\n\\]"
  | Text s -> "\\begin{minipage}{\\linewidth}\n" ^ s ^ "\n\\end{minipage}"

type observation = { source : string; window : string; offset : int; length : int; line : int }
type event = Seen of observation | Idle | No_preview

let tex_file path = List.exists (Filename.check_suffix path) [".tex"; ".ltx"; ".latex"]

let parse_line line =
  match line with
  | "idle" -> Some Idle
  | "closed" -> Some No_preview
  | _ ->
    (* Split from the right: a path may contain tabs. *)
    (match List.rev (String.split_on_char '\t' line) with
    | line_no :: length :: offset :: window :: (_ :: _ as path) ->
      (match int_of_string_opt offset, int_of_string_opt length, int_of_string_opt line_no with
       | Some offset, Some length, Some line_no ->
         let source = String.concat "\t" (List.rev path) in
         if tex_file source then Some (Seen { source; window; offset; length; line = line_no })
         else Some Idle
       | _ -> None)
    | _ -> None)

type state = { started : float; pending : observation option; changed_at : float;
  rendered : observation option; preview_seen : bool; missing_since : float option;
  building : bool }
type action = Wait | Render of observation | Busy of observation | Stop

let debounce = 0.35
let close_grace = 2.0
let startup_grace = 10.0

let initial ~now = { started = now; pending = None; changed_at = now; rendered = None;
  preview_seen = false; missing_since = None; building = false }

let observe state ~now = function
  | Idle -> { state with preview_seen = true; missing_since = None }
  | No_preview ->
    { state with missing_since = Some (Option.value state.missing_since ~default:now) }
  | Seen o ->
    let state = { state with preview_seen = true; missing_since = None } in
    (* A new observation forgets the last render: the same range reselected
       later may hold edited text. The render cache keeps true repeats cheap. *)
    if state.pending = Some o then state
    else { state with pending = Some o; changed_at = now; rendered = None }

(* A full build started or ended. Its end forgets the last render, so a
   selection reported busy (or yielded by its renderer) renders once. *)
let building state active =
  if state.building && not active then { state with building = false; rendered = None }
  else { state with building = active }

let decide state ~now =
  match state.missing_since with
  | Some since when state.preview_seen && now -. since >= close_grace -> state, Stop
  | _ when not state.preview_seen && now -. state.started >= startup_grace -> state, Stop
  | _ ->
    match state.pending with
    | Some o when o.length > 0 && state.rendered <> Some o && now -. state.changed_at >= debounce ->
      { state with rendered = Some o }, if state.building then Busy o else Render o
    | _ -> state, Wait
