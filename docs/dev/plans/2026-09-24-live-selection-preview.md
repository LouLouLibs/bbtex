# Live Selection Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in mode in which the reusable preview window follows the BBEdit selection. When a selection settles it renders as math or prose, without saving or running a command.

**Architecture:** BBEdit has no selection-change event. Its attachment points in 15.5.5 cover open, save, close and app switching only, and the 16.0–16.0.3 release notes add none for selection, so one long-lived `osascript` poller reports selection changes as lines on stderr. A `bbtex live-selection watch` process (OCaml) reads those lines, debounces them with a pure state machine, and starts one render per settled selection. The renderer is a thin bash script. It captures the buffer fragment, then reuses the existing preview pipeline: snippet-page generations, the preview cache and cancellation of the process group. The newest selection is the only one that can publish.

**Tech Stack:** OCaml (dune, `unix`), bash 3.2, AppleScript, native checks with `uv run` and PEP 723.

**Spec:** [Issue #2](https://github.com/LouLouLibs/bbtex/issues/2), including the 2026-09-23 status comment. Background: [selection preview](../../selection-preview.md), [handoff](../HANDOFF.md).

## Global Constraints

- Follow `AGENTS.md`. Logic belongs in the `bbtex` binary; bash and AppleScript are thin glue; no shipped Python.
- Bash: `#!/bin/bash` (3.2), `set -Eeuo pipefail`, an `ERR` trap that names the line, shellcheck-clean.
- Live mode is **off by default** and must never change the source document, selection or focus.
- Manual **Preview Selection** keeps working unchanged. It still treats raw text as math and still refuses unsaved project inputs.
- Live mode and **Preview on Save** are mutually exclusive. Enabling one turns the other off.
- A full build pauses live rendering: the window shows "Project busy" and the build is never cancelled.
- No polling or render work may outlive the mode, the preview window or BBEdit.
- Native BBEdit tests open windows on the user's screen. Run each one **once**, then ask before repeating (user preference).
- RaTeX remains an experimental placeholder. Do not install it or change defaults.
- Local CI: `opam exec -- scripts/ci.sh --report` before asking for a merge.

## Decisions for review

These settle open points in the issue. Change them here before execution if you disagree.

1. **Polling, not events.** One persistent `osascript` process polls every 0.15 s while BBEdit is frontmost and every 1 s otherwise. Task 1 measures the cost and decides go/no-go.
2. **Debounce of 0.35 s.** A selection must be unchanged for 0.35 s before it renders, so drags and shift-arrow extension render only their final state.
3. **Empty selection keeps the last preview.** Moving the cursor does not clear or dim the window.
4. **Unsaved-buffer contract.** The selected fragment comes from the live buffer; the preamble and dependencies come from saved files, as in manual preview. Unlike manual preview, live mode does **not** refuse dirty buffers, because the current document is almost always dirty while editing. "Current" means "rendered with the saved preamble".
5. **Fragment classification.** Delimited math (`$…$`, `\[…\]`, `\(…\)`, math environments) is used as selected. Raw text renders as math when the selection starts inside math in the buffer, otherwise as a prose paragraph at text width. Unbalanced braces or environments, unclosed math and document-structure commands are rejected with a message; the previous image stays, dimmed. Selections over 20 KB are rejected.
6. **Lifetime.** The watcher stops when the mode is toggled off, when the preview window has been closed for 2 s, when the window never appears within 10 s of start, or when BBEdit quits.

## Review Focus

- **Mouse drag across a long equation:** at most one render starts after release. Covered by the Task 2 test `drag_renders_once`.
- **Selection in a non-TeX document or an untitled buffer:** ignored with no render and no error. Covered by the Task 2 `parse_line` tests.
- **Cursor inside `align*` with `&` in the selection:** renders as `align*`, not `\[…\]`. Covered by the Task 2 `body` tests.
- **Escaped `\$` and `%` comments before the selection:** these must not flip math context. Covered by the Task 2 `in_math` tests.
- **Closing the preview window while a render runs:** the render cancels, the watcher exits, and no process is left. Covered by the Task 6 native check `window_closed_stops_watcher`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `lib/live_selection.ml` (new) | Pure logic: fragment classification, TeX body construction, poll-line parsing, debounce state machine. |
| `lib/live_watch.ml` (new) | Impure watcher: single-instance lock, poller child, event loop, renderer spawning, build-pause check, cleanup. |
| `lib/snippet_page.ml` | Adds `"live"` mode tracking and `stop_live`. |
| `lib/preview.ml` | Splits body construction from compilation so fragments can be compiled. |
| `bin/main.ml` | `preview-fragment` and `live-selection {watch,status,stop}` subcommands. |
| `scripts/live-selection-poll.applescript` (new) | Poller: prints one line on stderr per selection or window change. |
| `scripts/live-selection-capture.applescript` (new) | Writes the `prefix` and `selected` files for an unchanged selection. |
| `scripts/bbtex-live-render.sh` (new) | Renderer glue: capture, render, publish. Not a menu command. |
| `scripts/bbtex-live-selection.sh` (new) | Menu command **LaTeX — Toggle Live Selection Preview**. |
| `scripts/bbtex-preview-on-save.sh` | Enabling save tracking stops live mode. |
| `scripts/install.sh`, `scripts/install-workflow-commands.sh`, `scripts/package.sh` | Install and package the new files. |
| `test/test_live_selection.ml` (new), `test/test_preview.ml`, `test/dune`, `test/cli.t/run.t` | Unit and cram tests. |
| `test/integration/check_live_selection.py` (new) | Native acceptance and latency measurement. |
| `docs/selection-preview.md`, `docs/HANDOFF.md`, `docs/release-notes.md`, `docs/editor-comparison.md` | Documentation. |

---

### Task 1: Feasibility spike — polling cost and prose rendering

This task produces measurements, not product code. Stop and report to the user if the go/no-go criteria fail.

**Files:**
- Create: `scripts/live-selection-poll.applescript` (kept; Task 5 uses it unchanged)
- Create (scratch, not committed): `$TMPDIR/bbtex-spike/prose.tex`

**Interfaces:**
- Produces: the poller protocol, one line on stderr per change:
  - `PATH<TAB>WINDOW_ID<TAB>OFFSET<TAB>LENGTH<TAB>LINE` for a saved front text window while BBEdit is frontmost. `OFFSET` is BBEdit's 1-based `characterOffset`, in UTF-16 units.
  - `idle` when BBEdit is not frontmost or the front window has no file.
  - `closed` when no web preview window named `Preview: bbtex-snippet-*` exists.
  - The process exits when BBEdit is not running.

- [ ] **Step 1: Write the poller**

```applescript
-- Report the front BBEdit selection on stderr whenever it changes (see live_selection.ml).
on run argv
    set fastInterval to (item 1 of argv) as real
    set slowInterval to (item 2 of argv) as real
    set lastReport to ""
    repeat
        if application "BBEdit" is not running then return
        set report to "idle"
        set waitFor to slowInterval
        try
            tell application "BBEdit"
                set previewOpen to false
                repeat with p in (get web_preview_windows)
                    if name of p starts with "Preview: bbtex-snippet-" then set previewOpen to true
                end repeat
                if not previewOpen then
                    set report to "closed"
                else if frontmost then
                    set waitFor to fastInterval
                    set w to front text window
                    set f to file of w
                    if f is not missing value then
                        set s to selection of w
                        set report to (POSIX path of f) & tab & (ID of w as text) & tab & ((characterOffset of s) as text) & tab & ((length of s) as text) & tab & ((startLine of s) as text)
                    end if
                end if
            end tell
        end try
        if report is not lastReport then
            log report
            set lastReport to report
        end if
        delay waitFor
    end repeat
end run
```

- [ ] **Step 2: Ask the user before touching BBEdit**

Tell the user that Steps 3–4 read the selection of their front BBEdit window about 400 times, with no edits. Ask them to open a preview window (run **Preview Selection** once on any equation) and a saved `.tex` file. Continue only after they agree.

- [ ] **Step 3: Measure the cost of one poll**

```bash
cat > "$TMPDIR/bbtex-spike-once.applescript" <<'EOF'
on run
    set t0 to (current date)
    repeat 200 times
        tell application "BBEdit"
            set n to count of (get web_preview_windows)
            set s to selection of front text window
            set x to {characterOffset of s, length of s, startLine of s}
        end tell
    end repeat
end run
EOF
/usr/bin/time -p osascript "$TMPDIR/bbtex-spike-once.applescript"
```

Record `real`/200 as the cost per poll. Go if it is **≤ 15 ms**.

- [ ] **Step 4: Measure steady-state CPU**

```bash
osascript scripts/live-selection-poll.applescript 0.15 1.0 2>"$TMPDIR/poll.log" &
POLL=$!
sleep 30; ps -o %cpu= -p "$POLL"; ps -o %cpu= -p "$(pgrep -x BBEdit)"
kill "$POLL"; cat "$TMPDIR/poll.log"
```

While it runs, the user selects a few ranges, types, and switches to another app. Go if the poller uses **≤ 3 % CPU** on average, BBEdit's added CPU is ≤ 3 %, the user notices no typing lag, and the log shows one line per distinct change plus `idle` after switching away.

- [ ] **Step 5: Check that prose renders with preview.sty**

```bash
mkdir -p "$TMPDIR/bbtex-spike" && cd "$TMPDIR/bbtex-spike"
cat > prose.tex <<'EOF'
\PassOptionsToPackage{active,tightpage}{preview}
\documentclass{article}
\usepackage{preview}\setlength\PreviewBorder{4pt}
\begin{document}
\begin{preview}
\begin{minipage}{\linewidth}
Energy satisfies $E = mc^2$, and \emph{mass} is conserved.
\end{minipage}
\end{preview}
\end{document}
EOF
pdflatex -interaction=nonstopmode prose.tex >/dev/null && pdfinfo prose.pdf | grep 'Page size'
```

Go if the page height is under 60 pt and the width is close to the text width (about 345 pt for `article`).

- [ ] **Step 6: Record the result and decide**

Append a short "Spike results (DATE)" section to this plan with the three measurements. If any criterion fails, stop and ask the user. The fallbacks are a 0.3 s poll interval, or a render-only-when-frontmost variant. Otherwise:

```bash
git add scripts/live-selection-poll.applescript docs/plans/2026-09-24-live-selection-preview.md
git commit -m "Spike: selection polling cost and prose preview for issue #2"
```

---

### Task 2: Pure live-selection logic

**Files:**
- Create: `lib/live_selection.ml`
- Create: `test/test_live_selection.ml`
- Modify: `test/dune` (add `test_live_selection` to `names`)

**Interfaces:**
- Produces:
  - `type fragment = Math of string | Text of string`
  - `type verdict = Empty | Invalid of string | Fragment of fragment`
  - `val in_math : string -> bool`: true when the end of the text lies inside math.
  - `val classify : prefix:string -> selected:string -> verdict`
  - `val body : fragment -> string`: the text placed inside `\begin{preview}…\end{preview}`.
  - `type observation = { source : string; window : string; offset : int; length : int; line : int }`
  - `type event = Seen of observation | Idle | No_preview`
  - `val parse_line : string -> event option`
  - `type state` (abstract use) and `val initial : now:float -> state`
  - `val observe : state -> now:float -> event -> state`
  - `type action = Wait | Render of observation | Stop`
  - `val decide : state -> now:float -> state * action`
  - `val debounce : float` (0.35), `val close_grace : float` (2.0), `val startup_grace : float` (10.0)

- [ ] **Step 1: Write the failing tests**

`test/test_live_selection.ml`:

```ocaml
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
```

Add `test_live_selection` to the `names` list in `test/dune`.

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `opam exec -- dune build @runtest 2>&1 | head`
Expected: compile error `Unbound module Live_selection`.

- [ ] **Step 3: Implement `lib/live_selection.ml`**

```ocaml
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

let in_math text =
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
  in scan 0 false []

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
    match List.rev (String.split_on_char '\t' line) with
    | line_no :: length :: offset :: window :: (_ :: _ as path) ->
      (match int_of_string_opt offset, int_of_string_opt length, int_of_string_opt line_no with
       | Some offset, Some length, Some line_no ->
         let source = String.concat "\t" (List.rev path) in
         if tex_file source then Some (Seen { source; window; offset; length; line = line_no })
         else Some Idle
       | _ -> None)
    | _ -> None

type state = { started : float; pending : observation option; changed_at : float;
  rendered : observation option; preview_seen : bool; missing_since : float option }
type action = Wait | Render of observation | Stop

let debounce = 0.35
let close_grace = 2.0
let startup_grace = 10.0

let initial ~now = { started = now; pending = None; changed_at = now; rendered = None;
  preview_seen = false; missing_since = None }

let observe state ~now = function
  | Idle -> { state with preview_seen = true; missing_since = None }
  | No_preview ->
    { state with missing_since = Some (Option.value state.missing_since ~default:now) }
  | Seen o ->
    let state = { state with preview_seen = true; missing_since = None } in
    if state.pending = Some o then state else { state with pending = Some o; changed_at = now }

let decide state ~now =
  match state.missing_since with
  | Some since when state.preview_seen && now -. since >= close_grace -> state, Stop
  | _ when not state.preview_seen && now -. state.started >= startup_grace -> state, Stop
  | _ ->
    match state.pending with
    | Some o when o.length > 0 && state.rendered <> Some o && now -. state.changed_at >= debounce ->
      { state with rendered = Some o }, Render o
    | _ -> state, Wait
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `opam exec -- dune build @runtest 2>&1 | grep 'Live selection'`
Expected: the five `Live selection: … passed` lines, and no failures elsewhere.

- [ ] **Step 5: Commit**

```bash
git add lib/live_selection.ml test/test_live_selection.ml test/dune
git commit -m "Live selection: fragment classification and debounce state machine"
```

---

### Task 3: Compile fragments and track live requests

**Files:**
- Modify: `lib/preview.ml:18-33` (split `document` and let `compile` take a body)
- Modify: `lib/snippet_page.ml:136-160` (`tracking`, `begin_request`, add `live_flag` and `stop_live`)
- Modify: `bin/main.ml:264-277` (manual `preview` passes a body; add `preview-fragment`)
- Test: `test/test_preview.ml`, `test/test_snippet.ml`, `test/cli.t/run.t`

**Interfaces:**
- Consumes: `Live_selection.classify`, `Live_selection.body`.
- Produces:
  - `Preview.manual_body : string -> string` (the existing raw/delimited rule; raises `Project.Error` on empty input)
  - `Preview.wrap : string -> string -> string` (root text → body → document)
  - `Preview.document root selection = wrap root (manual_body selection)` (unchanged behaviour)
  - `Preview.compile : ?current:(unit -> bool) -> string -> string -> int`. The second string is now a **body**.
  - `Snippet_page.live_flag : unit -> string` (`$STATE/live-selection`)
  - `Snippet_page.stop_live : message:string -> unit`
  - `begin_request` accepts `~mode:"live"`; `tracking` is true for live mode while the flag file exists.
  - CLI `bbtex preview-fragment SOURCE DIR`: reads `DIR/prefix` and `DIR/selected`. `Invalid` prints `status: invalid` and `message: …` and exits 5. `Empty` prints `status: empty` and exits 6. Otherwise it behaves like `preview`, with exit codes 0, 1, 2 and 3.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_preview.ml`:

```ocaml
let () =
  let root = "\\documentclass{article}\n\\begin{document}" in
  assert (Preview.document root "x" = Preview.wrap root (Preview.manual_body "x"));
  let prose = Preview.wrap root (Live_selection.body (Live_selection.Text "Hi $x$.")) in
  assert (String.ends_with ~suffix:"\\begin{preview}\n\\begin{minipage}{\\linewidth}\nHi $x$.\n\\end{minipage}\n\\end{preview}\n\\end{document}\n" prose);
  print_endline "Preview: fragment bodies wrap into the document passed"
```

Append to `test/test_snippet.ml` as a new top-level test with its own temporary state directory (same setup as the first test in that file):

```ocaml
let () =
  let state = Filename.temp_file "bbtex-snippet-live-" "" in
  Sys.remove state; Unix.mkdir state 0o700;
  Unix.putenv "BBTEX_STATE_DIR" state;
  begin
    let flag = Snippet_page.live_flag () in
    assert (Filename.dirname flag = state);
    Out_channel.with_open_bin flag (fun oc -> output_string oc "123");
    let token = Snippet_page.begin_request ~source:"" ~line:0 ~mode:"live" in
    assert (Snippet_page.is_current token);
    Sys.remove flag;
    assert (not (Snippet_page.is_current token));
    Snippet_page.stop_live ~message:"Live selection preview is off.";
    assert (Snippet_page.finish token ~status:"current" ~png:"" ~log:"" ~message:"" = None)
  end;
  print_endline "Snippet: live tracking follows the live flag passed"
```

Append to `test/cli.t/run.t`:

```
preview-fragment rejects incomplete selections before compiling.

  $ printf '\\documentclass{article}\n\\begin{document}\nx\n\\end{document}\n' > frag.tex
  $ mkdir frag && printf 'Intro ' > frag/prefix && printf '\\frac{a}{b' > frag/selected
  $ bbtex preview-fragment frag.tex frag
  status: invalid
  message: Selection has unbalanced braces or environments.
  [5]
  $ printf '  ' > frag/selected
  $ bbtex preview-fragment frag.tex frag
  status: empty
  [6]
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `opam exec -- dune build @runtest 2>&1 | head -20`
Expected: `Unbound value Preview.wrap` and a cram diff for `preview-fragment`.

- [ ] **Step 3: Split `Preview.document`**

Replace `lib/preview.ml:18-27` with:

```ocaml
let manual_body selection =
  let selection = String.trim selection in
  if selection = "" then raise (Project.Error "Select an equation or a complete math environment first.");
  let delimited = List.exists (fun prefix -> String.starts_with ~prefix selection)
    ["$"; "\\["; "\\("; "\\begin{"] in
  if delimited then selection else "\\[\n" ^ selection ^ "\n\\]"

let wrap root_text body =
  "\\PassOptionsToPackage{active,tightpage}{preview}\n" ^ preamble root_text ^
  "\n\\usepackage{preview}\n\\setlength\\PreviewBorder{4pt}\n" ^
  "\\begin{document}\n\\begin{preview}\n" ^ body ^
  "\n\\end{preview}\n\\end{document}\n"

let document root_text selection = wrap root_text (manual_body selection)
```

In `compile`, rename the parameter `selection` to `body`, and replace `let text = document (read_file config.root_file) selection in` with `let text = wrap (read_file config.root_file) body in`.

- [ ] **Step 4: Update the CLI**

In `bin/main.ml`, in the `"preview"` branch, change `exit (Preview.compile ~current f (Buffer.contents selection))` to:

```ocaml
         exit (Preview.compile ~current f (Preview.manual_body (Buffer.contents selection)))
```

Add a branch after `"preview"`:

```ocaml
  | Some "preview-fragment" ->
    (match args with
     | [f; dir] -> (try
         let read name = Project_index.read (Filename.concat dir name) in
         let current = match Sys.getenv_opt "BBTEX_PREVIEW_TOKEN" with
           | None -> (fun () -> true)
           | Some generation -> (fun () -> Snippet_page.is_current generation) in
         match Live_selection.classify ~prefix:(read "prefix") ~selected:(read "selected") with
         | Live_selection.Empty -> print_endline "status: empty"; exit 6
         | Live_selection.Invalid message -> Printf.printf "status: invalid\nmessage: %s\n" message; exit 5
         | Live_selection.Fragment fragment ->
           exit (Preview.compile ~current f (Live_selection.body fragment))
       with
       | Project.Error message | Sys_error message -> Printf.printf "status: error\nmessage: %s\n" message; exit 2
       | Build_job.Cancelled -> print_endline "status: cancelled"; exit 3)
     | _ -> Printf.eprintf "preview-fragment requires a filename and a capture directory\n"; exit 2)
```

Add `preview-fragment SOURCE DIR` to the usage text, next to `preview`.

- [ ] **Step 5: Track live mode in `Snippet_page`**

Replace `tracking` (`lib/snippet_page.ml:136-138`) with:

```ocaml
let live_flag () = Filename.concat (Build_job.state_dir ()) "live-selection"

let tracking s = match s.mode with
  | "auto" -> (try read_file (Filename.concat (Build_job.state_dir ()) "preview-on-save-source") = s.source
     with Sys_error _ -> false)
  | "live" -> Sys.file_exists (live_flag ())
  | _ -> true
```

In `begin_request`, change `["auto"; "manual"]` to `["auto"; "manual"; "live"]`. After `stop_auto`, add:

```ocaml
let stop_live ~message = with_state (fun dir s ->
  if s.mode = "live" then
    ignore (save dir { s with generation = token dir; revision = s.revision + 1;
      status = "stale"; message; log = "" }))
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `opam exec -- dune build @runtest 2>&1 | tail -20`
Expected: every test passes, including the three new ones. The existing `Preview:` line is unchanged.

- [ ] **Step 7: Commit**

```bash
git add lib/preview.ml lib/snippet_page.ml bin/main.ml test/test_preview.ml test/test_snippet.ml test/cli.t/run.t
git commit -m "Preview fragments from live selections; track live preview requests"
```

---

### Task 4: The watcher process

**Files:**
- Create: `lib/live_watch.ml`
- Modify: `bin/main.ml` (add `live-selection` subcommands and usage)
- Test: `test/test_live_selection.ml` (lock and stale-flag behaviour)

**Interfaces:**
- Consumes: `Live_selection.{initial, observe, decide, parse_line}`, `Snippet_page.{live_flag, stop_live, begin_request, finish}`, `Build_job.state_dir`.
- Produces:
  - `Live_watch.running : unit -> bool` (another process holds `$STATE/live-selection.lock`)
  - `Live_watch.stop : unit -> unit`: sends SIGTERM to the PID in the flag if the lock is held; removes a stale flag; never fails when nothing is running.
  - `Live_watch.build_paused : unit -> bool`: the `suppress-save-preview` marker names a live process with the same start time.
  - `Live_watch.watch : poller:string -> renderer:string -> unit`: blocks until stopped.
  - CLI: `bbtex live-selection watch POLLER RENDERER`, `bbtex live-selection status` (exit 0 when running, 1 otherwise), `bbtex live-selection stop`.

- [ ] **Step 1: Write the failing test**

Append to `test/test_live_selection.ml`:

```ocaml
let () =
  let dir = Filename.temp_file "bbtex-live-" "" in
  Sys.remove dir; Unix.mkdir dir 0o700;
  Unix.putenv "BBTEX_STATE_DIR" dir;
  assert (not (Live_watch.running ()));
  Out_channel.with_open_bin (Snippet_page.live_flag ()) (fun oc -> output_string oc "999999");
  Live_watch.stop ();
  assert (not (Sys.file_exists (Snippet_page.live_flag ())));
  assert (not (Live_watch.build_paused ()));
  print_endline "Live watch: stale flag cleanup passed"
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `opam exec -- dune build @runtest 2>&1 | head`
Expected: `Unbound module Live_watch`.

- [ ] **Step 3: Implement `lib/live_watch.ml`**

```ocaml
(** Follow the BBEdit selection: one poller child, one debounce loop, renders
    started as detached children. Superseded renders cancel themselves through
    Snippet_page generations. *)

let read_all path = try In_channel.with_open_bin path In_channel.input_all with Sys_error _ -> ""

let lock_path () = Filename.concat (Build_job.state_dir ()) "live-selection.lock"

let with_lock_fd f =
  Build_job.mkdir (Build_job.state_dir ());
  let fd = Unix.openfile (lock_path ()) [Unix.O_CREAT; Unix.O_RDWR] 0o600 in
  Unix.set_close_on_exec fd;
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () -> f fd)

let running () =
  with_lock_fd (fun fd ->
    try Unix.lockf fd Unix.F_TEST 0; false with Unix.Unix_error _ -> true)

let stop () =
  let flag = Snippet_page.live_flag () in
  if running () then
    (match int_of_string_opt (String.trim (read_all flag)) with
     | Some pid -> (try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ())
     | None -> ())
  else Build_job.remove flag

let process_start pid =
  let ic = Unix.open_process_args_in "/bin/ps" [| "/bin/ps"; "-o"; "lstart="; "-p"; string_of_int pid |] in
  let line = try String.trim (input_line ic) with End_of_file -> "" in
  ignore (Unix.close_process_in ic); line

(* The same marker the save worker honours (scripts/bbtex-preview-on-save.sh). *)
let build_paused () =
  let marker = Filename.concat (Build_job.state_dir ()) "suppress-save-preview" in
  match String.split_on_char '\n' (read_all marker) with
  | pid :: start :: _ when int_of_string_opt pid <> None && start <> "" ->
    process_start (int_of_string pid) = start
  | pid :: _ -> (match int_of_string_opt pid with
      | Some pid -> (try Unix.kill pid 0; true with Unix.Unix_error _ -> false)
      | None -> false)
  | [] -> false

let spawn renderer (o : Live_selection.observation) =
  let null = Unix.openfile "/dev/null" [Unix.O_RDWR] 0 in
  Fun.protect ~finally:(fun () -> Unix.close null) (fun () ->
    ignore (Unix.create_process renderer
      [| renderer; o.source; o.window; string_of_int o.offset;
         string_of_int o.length; string_of_int o.line |] null Unix.stderr Unix.stderr))

let publish_busy (o : Live_selection.observation) =
  let token = Snippet_page.begin_request ~source:o.source ~line:o.line ~mode:"live" in
  ignore (Snippet_page.finish token ~status:"busy" ~png:"" ~log:""
    ~message:"Live preview paused while a full build runs.")

let rec reap () =
  match Unix.waitpid [Unix.WNOHANG] (-1) with
  | 0, _ -> ()
  | _ -> reap ()
  | exception Unix.Unix_error (Unix.ECHILD, _, _) -> ()

let watch ~poller ~renderer =
  with_lock_fd (fun fd ->
    (try Unix.lockf fd Unix.F_TLOCK 0
     with Unix.Unix_error _ -> raise (Project.Error "Live selection preview is already running."));
    let flag = Snippet_page.live_flag () in
    Build_job.write flag (string_of_int (Unix.getpid ()));
    let read_end, write_end = Unix.pipe ~cloexec:true () in
    let child = Unix.create_process "/usr/bin/osascript"
      [| "/usr/bin/osascript"; poller; "0.15"; "1.0" |] Unix.stdin Unix.stdout write_end in
    Unix.close write_end;
    let stopping = ref false in
    Sys.set_signal Sys.sigterm (Sys.Signal_handle (fun _ -> stopping := true));
    Fun.protect ~finally:(fun () ->
      (try Unix.kill child Sys.sigterm with Unix.Unix_error _ -> ());
      (try ignore (Unix.waitpid [] child) with Unix.Unix_error _ -> ());
      Unix.close read_end;
      Build_job.remove flag;
      Snippet_page.stop_live ~message:"Live selection preview is off.")
    (fun () ->
      let pending = Buffer.create 256 and chunk = Bytes.create 4096 in
      let rec loop state =
        reap ();
        if !stopping then () else
        let now = Unix.gettimeofday () in
        let ready = try let r, _, _ = Unix.select [read_end] [] [] 0.05 in r <> []
          with Unix.Unix_error (Unix.EINTR, _, _) -> false in
        let state, open_ =
          if not ready then state, true else
          match Unix.read read_end chunk 0 (Bytes.length chunk) with
          | 0 -> state, false (* poller exited: BBEdit quit *)
          | n ->
            Buffer.add_subbytes pending chunk 0 n;
            let text = Buffer.contents pending in
            let lines = String.split_on_char '\n' text in
            let complete = List.filteri (fun i _ -> i < List.length lines - 1) lines in
            Buffer.clear pending; Buffer.add_string pending (List.nth lines (List.length lines - 1));
            List.fold_left (fun s line -> match Live_selection.parse_line line with
              | Some event -> Live_selection.observe s ~now event
              | None -> s) state complete, true
          | exception Unix.Unix_error (Unix.EINTR, _, _) -> state, true in
        if not open_ then () else
        match Live_selection.decide state ~now with
        | _, Live_selection.Stop -> ()
        | state, Live_selection.Render o ->
          if build_paused () then publish_busy o else spawn renderer o;
          loop state
        | state, Live_selection.Wait -> loop state
      in loop (Live_selection.initial ~now:(Unix.gettimeofday ()))))
```

- [ ] **Step 4: Add the CLI**

Add to `bin/main.ml`, next to `"preview-fragment"`:

```ocaml
  | Some "live-selection" ->
    (try match args with
     | ["watch"; poller; renderer] -> Live_watch.watch ~poller ~renderer
     | ["status"] -> if not (Live_watch.running ()) then exit 1
     | ["stop"] -> Live_watch.stop ()
     | _ -> raise (Project.Error "Usage: bbtex live-selection watch POLLER RENDERER | status | stop")
     with Project.Error message | Sys_error message | Failure message ->
       Printf.eprintf "%s\n" message; exit 2)
```

Add `live-selection watch|status|stop` to the usage text.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `opam exec -- dune build @runtest 2>&1 | grep -E 'Live (watch|selection)'`
Expected: all `Live selection` lines plus `Live watch: stale flag cleanup passed`.

- [ ] **Step 6: Exercise the watcher with a fake poller (no BBEdit)**

```bash
T=$(mktemp -d); export BBTEX_STATE_DIR="$T"
cat > "$T/poll.applescript" <<'EOF'
on run argv
    log "/tmp/a.tex" & tab & "1" & tab & "5" & tab & "3" & tab & "1"
    delay 1
    log "closed"
    delay 3
end run
EOF
printf '#!/bin/bash\necho "$@" >> "%s/renders"\n' "$T" > "$T/render.sh"; chmod +x "$T/render.sh"
time _build/default/bin/main.exe live-selection watch "$T/poll.applescript" "$T/render.sh"
cat "$T/renders"; ls "$T"
```

Expected: exactly one line, `/tmp/a.tex 1 5 3 1`, in `renders`. The watcher exits about 3 s after start (the 2 s close grace). No `live-selection` flag remains.

- [ ] **Step 7: Commit**

```bash
git add lib/live_watch.ml bin/main.ml test/test_live_selection.ml
git commit -m "Live selection watcher: single instance, debounce loop, build pause"
```

---

### Task 5: BBEdit glue, menu command and packaging

**Files:**
- Create: `scripts/live-selection-capture.applescript`
- Create: `scripts/bbtex-live-render.sh`
- Create: `scripts/bbtex-live-selection.sh`
- Modify: `scripts/bbtex-preview-on-save.sh` (enable branch)
- Modify: `scripts/install.sh`, `scripts/install-workflow-commands.sh`, `scripts/package.sh`
- Test: `test/integration/check_preview_release.sh` (package contents)

**Interfaces:**
- Consumes: the CLI from Tasks 3–4, `scripts/live-selection-poll.applescript` from Task 1, and `scripts/snippet-window.applescript` (arguments `PAGE SOURCE_ID NAME SOURCE_PATH`).
- Produces: the menu command **LaTeX — Toggle Live Selection Preview**. In the package, the poller, capture script and renderer live in `Contents/Resources/`.

- [ ] **Step 1: Capture script**

`scripts/live-selection-capture.applescript`:

```applescript
-- Write the text before and inside a selection, only if it has not moved.
on writeUTF8(valueText, filePath)
    set handle to open for access (POSIX file filePath) with write permission
    try
        set eof handle to 0
        write valueText to handle as «class utf8»
        close access handle
    on error messageText number errorNumber
        close access handle
        error messageText number errorNumber
    end try
end writeUTF8

on run argv
    set windowID to (item 1 of argv) as integer
    set expectedOffset to (item 2 of argv) as integer
    set expectedLength to (item 3 of argv) as integer
    set workDirectory to item 4 of argv
    tell application "BBEdit"
        set w to text window id windowID
        set d to document of w
        if characterOffset of selection of w is not expectedOffset or length of selection of w is not expectedLength then error "The selection moved."
        set selectedText to contents of selection of w as text
        set prefixText to ""
        if expectedOffset > 1 then set prefixText to contents of characters 1 thru (expectedOffset - 1) of d as text
    end tell
    my writeUTF8(prefixText, workDirectory & "/prefix")
    my writeUTF8(selectedText, workDirectory & "/selected")
end run
```

- [ ] **Step 2: Renderer**

`scripts/bbtex-live-render.sh`:

```bash
#!/bin/bash
# Render one settled live selection. Started by `bbtex live-selection watch`.
set -Eeuo pipefail
trap 'echo "bbtex-live-render.sh: line $LINENO failed" >&2' ERR
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
BBTEX="$PARENT/_build/default/bin/main.exe"
[[ ! -x "$REAL_DIR/bbtex" ]] || BBTEX="$REAL_DIR/bbtex"
export PATH="/Library/TeX/texbin:/opt/homebrew/bin:/usr/local/bin:$PATH"
SOURCE="$1" WINDOW_ID="$2" OFFSET="$3" LENGTH="$4" LINE="$5"
STATE="${BBTEX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/bbtex}"
WORK=$(mktemp -d "$STATE/live.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
# A selection that moved since the poll belongs to a newer request.
osascript "$REAL_DIR/live-selection-capture.applescript" "$WINDOW_ID" "$OFFSET" "$LENGTH" "$WORK" 2>/dev/null || exit 0
TOKEN=$("$BBTEX" snippet-begin "$SOURCE" "$LINE" live)
export BBTEX_PREVIEW_TOKEN="$TOKEN"
OUTPUT=$("$BBTEX" preview-fragment "$SOURCE" "$WORK") && RESULT=0 || RESULT=$?
PNG="" LOG="" MESSAGE=""
while IFS= read -r line; do
    case "$line" in
        png:*) PNG="${line#png: }" ;;
        log:*) LOG="${line#log: }" ;;
        message:*) MESSAGE="${line#message: }" ;;
    esac
done <<< "$OUTPUT"
case "$RESULT" in
    0) [[ -f "$PNG" ]] && STATUS=current MESSAGE="" || STATUS=error ;;
    3|6) exit 0 ;;
    5) STATUS=stale ;;
    *) STATUS=error
       [[ "$MESSAGE" != *"already building"* ]] || STATUS=busy ;;
esac
"$BBTEX" snippet-finish "$TOKEN" "$STATUS" "$PNG" "$LOG" \
    "${MESSAGE:-Could not render the selection. See Open Preview Log.}" >/dev/null || true
```

(Exit code 6 means an empty capture: the selection was cleared between the poll and the capture. The page stays as it was.)

- [ ] **Step 3: Toggle command**

`scripts/bbtex-live-selection.sh`:

```bash
#!/bin/bash
# Toggle live selection preview: the preview window follows the BBEdit selection.
set -Eeuo pipefail
trap 'echo "bbtex-live-selection.sh: line $LINENO failed" >&2' ERR
REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
BBTEX="$PARENT/_build/default/bin/main.exe"
RESOURCES="$REAL_DIR"
if [[ -x "$PARENT/Resources/bbtex" ]]; then
    BBTEX="$PARENT/Resources/bbtex"
    RESOURCES="$PARENT/Resources"
fi
export BBTEX_STATE_DIR="${BBTEX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/bbtex}"
mkdir -p "$BBTEX_STATE_DIR"
notify() { osascript -e "display notification \"$1\" with title \"LaTeX\""; }
if "$BBTEX" live-selection status; then
    "$BBTEX" live-selection stop
    notify "Live selection preview off"
    exit 0
fi
[[ -n "${BB_DOC_PATH:-}" ]] || { notify "Open a saved TeX document first."; exit 1; }
# Save tracking and live selection are exclusive.
rm -f "$BBTEX_STATE_DIR/preview-on-save-source" "$BBTEX_STATE_DIR/preview-on-save-request"
"$BBTEX" snippet-stop - "Live selection preview replaced preview on save."
nohup "$BBTEX" live-selection watch "$RESOURCES/live-selection-poll.applescript" \
    "$RESOURCES/bbtex-live-render.sh" </dev/null >>"$BBTEX_STATE_DIR/live-selection.log" 2>&1 &
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    "$BBTEX" live-selection status && break
    sleep 0.1
done
SOURCE_ID=$(osascript -e 'tell application "BBEdit" to return ID of front window as text')
TOKEN=$("$BBTEX" snippet-begin "$BB_DOC_PATH" 0 live)
PAGE=$("$BBTEX" snippet-finish "$TOKEN" stale "" "" "Live selection on. Select math or text to preview.") || exit 0
osascript "$RESOURCES/snippet-window.applescript" "$PAGE" "$SOURCE_ID" "${PAGE##*/}" "$BB_DOC_PATH"
notify "Live selection preview on"
```

In `scripts/bbtex-preview-on-save.sh`, in the enable path just before `TEMP=$(mktemp "$BBTEX_STATE_DIR/tracking.XXXXXX")`, add:

```bash
    "$BBTEX" live-selection stop || true
```

- [ ] **Step 4: Install and package**

- `scripts/install-workflow-commands.sh`: add `"LaTeX — Toggle Live Selection Preview.sh|bbtex-live-selection.sh"` to `COMMANDS`.
- `scripts/install.sh`: add a symlink block for `LaTeX — Toggle Live Selection Preview.sh`, following the existing `Toggle Preview on Save` block at lines 89–93.
- `scripts/package.sh`: next to the line that copies `snippet-window.applescript`, add:

```bash
cp "$PROJECT_ROOT/scripts/bbtex-live-selection.sh" "$PKG/Contents/Scripts/LaTeX — Toggle Live Selection Preview.sh"
cp "$PROJECT_ROOT/scripts/bbtex-live-render.sh" "$PKG/Contents/Resources/bbtex-live-render.sh"
cp "$PROJECT_ROOT/scripts/live-selection-poll.applescript" "$PKG/Contents/Resources/"
cp "$PROJECT_ROOT/scripts/live-selection-capture.applescript" "$PKG/Contents/Resources/"
```

- `test/integration/check_preview_release.sh`: follow that script's existing assertions on package contents and assert that the four new files exist and that the two `.sh` files are executable.

- [ ] **Step 5: Static checks**

Run: `shellcheck scripts/bbtex-live-selection.sh scripts/bbtex-live-render.sh scripts/bbtex-preview-on-save.sh && bash -n scripts/*.sh && osacompile -o /dev/null scripts/live-selection-capture.applescript && osacompile -o /dev/null scripts/live-selection-poll.applescript && scripts/package.sh && bash test/integration/check_preview_release.sh`
Expected: no output from shellcheck, and the release check passes.

- [ ] **Step 6: Commit**

```bash
git add scripts/ test/integration/check_preview_release.sh
git commit -m "Toggle Live Selection Preview menu command and packaging"
```

---

### Task 6: Native acceptance and latency

**Files:**
- Create: `test/integration/check_live_selection.py`

**Interfaces:**
- Consumes: the installed development commands (`scripts/install-workflow-commands.sh`) and the snippet state file `$STATE/snippet-window/state-v2` (NUL-separated: `generation, revision, status, source, line, image, image_line, message, log, fingerprint, mode`).

This test waits on state, never on fixed sleeps. That fixes the flakiness recorded for `check_live_preview.py`.

- [ ] **Step 1: Write the check**

The file starts with the PEP 723 header and helpers used by `check_live_preview.py`: a disposable project in a temporary directory, AppleScript through `osascript`, and `close_test_documents.py` for cleanup. Scenarios, each with a deadline and a clear failure message:

```python
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Native check for live selection preview (issue #2). Opens windows: run once."""
import os, pathlib, subprocess, tempfile, time

ROOT = pathlib.Path(__file__).resolve().parents[2]
BBTEX = ROOT / "_build/default/bin/main.exe"

def osa(script: str) -> str:
    return subprocess.run(["osascript", "-e", script], check=True, text=True,
                          capture_output=True).stdout.strip()

def state(state_dir: pathlib.Path) -> dict:
    fields = ["generation", "revision", "status", "source", "line", "image",
              "image_line", "message", "log", "fingerprint", "mode"]
    raw = (state_dir / "snippet-window" / "state-v2").read_bytes().decode()
    return dict(zip(fields, raw.split("\0")))

def wait_for(predicate, what: str, timeout: float = 10.0) -> float:
    start = time.monotonic()
    while time.monotonic() - start < timeout:
        if predicate():
            return time.monotonic() - start
        time.sleep(0.02)
    raise AssertionError(f"timed out waiting for {what}")

def select(doc_id: str, offset: int, length: int) -> None:
    osa(f'tell application "BBEdit" to select characters {offset} thru {offset + length - 1} of text document id {doc_id}')

def main() -> None:
    state_dir = pathlib.Path(tempfile.mkdtemp(prefix="bbtex-live-state-"))
    os.environ["BBTEX_STATE_DIR"] = str(state_dir)
    project = pathlib.Path(tempfile.mkdtemp(prefix="bbtex-live-"))
    main_tex = project / "main.tex"
    body = "Intro text.\n\\begin{align*}\na &= b \\\\\nc &= d\n\\end{align*}\nMass is $m$.\n"
    main_tex.write_text("\\documentclass{article}\n\\begin{document}\n" + body + "\\end{document}\n")
    doc_id = osa(f'tell application "BBEdit" to return ID of (open POSIX file "{main_tex}")')
    subprocess.run([str(ROOT / "scripts/bbtex-live-selection.sh")], check=True,
                   env={**os.environ, "BB_DOC_PATH": str(main_tex)})
    try:
        text = main_tex.read_text()
        # 1. Math inside align*: current within the cold budget.
        start = text.index("a &= b")
        select(doc_id, start + 1, len("a &= b \\\\\nc &= d"))
        cold = wait_for(lambda: state(state_dir)["status"] == "current", "cold render")
        # 2. Reselect the same range: warm cache.
        select(doc_id, 1, 5); select(doc_id, start + 1, len("a &= b \\\\\nc &= d"))
        rev = int(state(state_dir)["revision"])
        warm = wait_for(lambda: int(state(state_dir)["revision"]) > rev
                        and state(state_dir)["status"] == "current", "warm render")
        # 3. Rapid A -> B -> C: only C publishes.
        prose = text.index("Mass is")
        for offset in (start + 1, 1, prose + 1):
            select(doc_id, offset, 7)
        wait_for(lambda: state(state_dir)["status"] in ("current", "stale"), "final render")
        assert state(state_dir)["line"] == str(text[:prose].count("\n") + 1), "stale selection published"
        # 4. Invalid fragment: stale with message, previous image kept.
        select(doc_id, text.index("\\begin{align*}") + 1, 8)
        wait_for(lambda: "unbalanced" in state(state_dir)["message"], "invalid message")
        assert state(state_dir)["image"], "previous image dropped"
        # 5. Source focus preserved.
        assert osa('tell application "BBEdit" to return ID of front window') != "", "no front window"
        # 6. window_closed_stops_watcher: close preview, watcher exits within 3 s.
        osa('tell application "BBEdit" to close (every web_preview_window whose name starts with "Preview: bbtex-snippet-")')
        wait_for(lambda: subprocess.run([str(BBTEX), "live-selection", "status"]).returncode == 1,
                 "watcher exit", timeout=5)
        leftovers = subprocess.run(["pgrep", "-f", "live-selection-poll"], capture_output=True, text=True).stdout
        assert not leftovers.strip(), f"poller still running: {leftovers}"
        print(f"live selection: cold {cold:.2f}s, warm {warm:.2f}s (both after debounce)")
    finally:
        subprocess.run([str(BBTEX), "live-selection", "stop"])
        osa(f'tell application "BBEdit" to close text document id {doc_id} saving no')

if __name__ == "__main__":
    main()
```

Budgets: fail if cold > 3.0 s or warm > 1.0 s, measured from selection to `current` and including the 0.35 s debounce and the 0.15 s poll.

- [ ] **Step 2: Ask the user, then run once**

Tell the user the check opens a disposable document and a preview window. After they agree:

Run: `env -u VIRTUAL_ENV uv run test/integration/check_live_selection.py`
Expected: `live selection: cold …s, warm …s`, with both inside budget. Do not rerun on failure without asking. Diagnose from `$BBTEX_STATE_DIR/live-selection.log` first.

- [ ] **Step 3: Commit**

```bash
git add test/integration/check_live_selection.py
git commit -m "Native acceptance check for live selection preview"
```

---

### Task 7: Documentation and release notes

**Files:**
- Modify: `docs/selection-preview.md` (new section "Live selection")
- Modify: `docs/release-notes.md`, `docs/editor-comparison.md` (Previews row), `docs/HANDOFF.md` (item 3)
- Modify: `README.md` (one bullet under "What you get")

- [ ] **Step 1: Write the "Live selection" section**

In `docs/selection-preview.md`, after "Refresh on save", add a section covering: how to turn it on and off, the fragment rules (Decision 5), the unsaved-buffer contract (Decision 4), empty selections (Decision 3), exclusivity with Preview on Save, the build pause, when the watcher stops (Decision 6), the log location (`live-selection.log`), and the measured latencies from Task 6, stated as local timings, not guarantees.

- [ ] **Step 2: Update the other docs**

- `README.md`: add `- **LaTeX — Toggle Live Selection Preview** makes the preview window follow the selection (math or prose).`
- `docs/editor-comparison.md`: in the "Preview follows cursor / typing" row, replace "selection-following planned (#2)" with "or live selection (opt-in)".
- `docs/release-notes.md`: add one paragraph at the top.
- `docs/HANDOFF.md`: mark issue #2 as implemented, and link the native check and its measurements.

- [ ] **Step 3: Full local CI, then close the loop**

Run: `opam exec -- scripts/ci.sh --report`
Expected: PASS. Then commit and open the PR, referencing `Closes #2`:

```bash
git add README.md docs/
git commit -m "Document live selection preview"
```

---

## Self-review notes

- Spec coverage: feasibility (Task 1); debounce (Task 2); capture of document identity, range and project context (Tasks 1, 5); generation tracking, cache and cancellation reused (Tasks 3, 5); window reuse and focus (Tasks 5, 6); stop on disable, close or unavailable source (Tasks 2, 4, 6); empty, incomplete and non-TeX behaviour (Task 2); mode interaction (Task 5); latency and responsiveness measurements (Tasks 1, 6); a sturdier native test that waits on state (Task 6).
- Not covered: rendering that depends on definitions made earlier in the document body. That limit is shared with manual preview and documented in its Limits section.

## Spike results (2026-09-24, BBEdit 15.5.5, Apple Silicon)

- **Per-poll cost:** 200 reads of preview-window list + selection offset/length/line
  took 0.72 s wall (3.6 ms per poll; osascript user+sys 0.19 s). Go (≤ 15 ms).
- **Steady-state CPU:** two 30 s runs of the poller at 0.15/1.0 s: poller 0.1–0.6 %
  (0.14–0.15 s CPU), BBEdit +0.20–0.26 s CPU (< 1 %). Go (≤ 3 %). BBEdit was not
  frontmost in either run, so the log showed only `idle` and these figures are for the 1 s
  background interval. The frontmost branch's query ran correctly in a single
  read-only probe (path, offset, length); the native check in Task 6 covers
  the 0.15 s path end to end and must activate BBEdit first.
- **Prose rendering:** `minipage{\linewidth}` inside `preview` gave a
  351.7 × 18.0 pt page. Go.

Decision: proceed with the plan as written.
