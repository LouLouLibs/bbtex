open Bbtex
open Live_selection

let () =
  assert (in_math "Text $x");
  assert (not (in_math "Text $x$ and"));
  assert (not (in_math "Cost \\$5 and"));
  assert (not (in_math "% $ in a comment\nText"));
  assert (in_math "\\begin{align*}\n a &= b");
  assert (not (in_math "\\begin{align*} a \\end{align*} after"));
  assert (in_math "\\[ x");
  assert (in_math "\\begin{equation}\\begin{cases} a");
  assert (not (in_math "\\begin{itemize}\\item x"));
  print_endline "Live selection: math context passed"

let () =
  let fragment = function Fragment f -> Some f | _ -> None in
  assert (classify ~prefix:"" ~selected:"  \n" = Empty);
  assert (fragment (classify ~prefix:"Text " ~selected:"$x^2$") = Some (Math "$x^2$"));
  assert (fragment (classify ~prefix:"\\begin{align*}\n" ~selected:"a &= b") = Some (Math "a &= b"));
  assert (fragment (classify ~prefix:"Intro. " ~selected:"Mass is $m$.") = Some (Text "Mass is $m$."));
  let invalid selected = match classify ~prefix:"" ~selected with Invalid _ -> true | _ -> false in
  assert (invalid "\\frac{a}{b");
  assert (invalid "\\begin{align*} a");
  assert (invalid "text $x");
  assert (invalid "\\begin{document}");
  assert (invalid (String.make 20_001 'a'));
  print_endline "Live selection: classification passed"

let () =
  assert (body (Math "$x$") = "$x$");
  assert (body (Math "x^2") = "\\[\nx^2\n\\]");
  assert (body (Math "a &= b \\\\ c &= d") = "\\begin{align*}\na &= b \\\\ c &= d\n\\end{align*}");
  assert (body (Text "Hi.") = "\\begin{minipage}{\\linewidth}\nHi.\n\\end{minipage}");
  print_endline "Live selection: fragment bodies passed"

let () =
  let o = { source = "/p/a b.tex"; window = "7"; offset = 10; length = 4; line = 3 } in
  assert (parse_line "/p/a b.tex\t7\t10\t4\t3" = Some (Seen o));
  assert (parse_line "idle" = Some Idle);
  assert (parse_line "closed" = Some No_preview);
  assert (parse_line "/p/notes.txt\t7\t10\t4\t3" = Some Idle);
  assert (parse_line "garbage" = None);
  print_endline "Live selection: poll lines passed"

(* Rapid A -> B -> C changes render only C once it settles. *)
let drag_renders_once () =
  let obs offset = { source = "/p/a.tex"; window = "1"; offset; length = 5; line = 1 } in
  let s = initial ~now:0. in
  let s = observe s ~now:0.00 (Seen (obs 1)) in
  let s, a1 = decide s ~now:0.10 in
  let s = observe s ~now:0.15 (Seen (obs 2)) in
  let s = observe s ~now:0.30 (Seen (obs 3)) in
  let s, a2 = decide s ~now:0.40 in
  let s, a3 = decide s ~now:0.70 in
  let _, a4 = decide s ~now:1.50 in
  assert (a1 = Wait && a2 = Wait && a3 = Render (obs 3) && a4 = Wait)

let () =
  drag_renders_once ();
  let empty = { source = "/p/a.tex"; window = "1"; offset = 4; length = 0; line = 1 } in
  let s = observe (initial ~now:0.) ~now:0. (Seen empty) in
  assert (snd (decide s ~now:5.) = Wait);
  let s = observe s ~now:1. No_preview in
  assert (snd (decide s ~now:2.) = Wait);
  assert (snd (decide s ~now:3.1) = Stop);
  let s = observe s ~now:3.2 Idle in
  assert (snd (decide s ~now:9.) = Wait);
  assert (snd (decide (initial ~now:0.) ~now:10.5) = Stop);
  print_endline "Live selection: debounce and lifetime passed"
