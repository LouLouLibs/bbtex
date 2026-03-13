(** Core types for LaTeX log parsing.

    Uses OCaml's algebraic types to precisely model the domain:
    every error category, box kind, and severity level is
    a distinct variant — no stringly-typed nonsense. *)

type severity =
  | Error
  | Warning
  | BadBox

type box_kind =
  | Overfull
  | Underfull

type box_type =
  | Hbox
  | Vbox

type log_entry = {
  severity : severity;
  file : string option;
  line : int option;
  message : string;
  context : string list;  (** additional lines of context from the log *)
}

type directive_key =
  | Root
  | Program
  | Encoding
  | Other of string

type directive = {
  key : directive_key;
  value : string;
}

type output_format =
  | Bbedit
  | Text

(* ── Pretty-printing helpers ────────────────────────────────── *)

let string_of_severity = function
  | Error   -> "error"
  | Warning -> "warning"
  | BadBox  -> "badbox"


let string_of_directive_key = function
  | Root       -> "root"
  | Program    -> "program"
  | Encoding   -> "encoding"
  | Other s    -> s

let directive_key_of_string s =
  match String.lowercase_ascii s with
  | "root"     -> Root
  | "program"  -> Program
  | "encoding" -> Encoding
  | other      -> Other other

let output_format_of_string s =
  match String.lowercase_ascii s with
  | "bbedit" -> Some Bbedit
  | "text"   -> Some Text
  | _        -> None

(* ── Compilation types ─────────────────────────────────────── *)

type engine = Pdflatex | Xelatex | Lualatex | Tectonic

let string_of_engine = function
  | Pdflatex -> "pdflatex"
  | Xelatex  -> "xelatex"
  | Lualatex -> "lualatex"
  | Tectonic -> "tectonic"

let engine_of_string s =
  match String.lowercase_ascii s with
  | "pdflatex" -> Pdflatex
  | "xelatex"  -> Xelatex
  | "lualatex" -> Lualatex
  | "tectonic" -> Tectonic
  | other ->
    if other <> "" then
      Log.info (Printf.sprintf "unknown engine '%s', defaulting to pdflatex" other);
    Pdflatex

let latexmk_flag = function
  | Pdflatex -> "-pdflatex"
  | Xelatex  -> "-pdfxelatex"
  | Lualatex -> "-pdflualatex"
  | Tectonic -> "-pdflatex"

type compilation_config = {
  source_file : string;
  root_file : string;
  engine : engine;
  log_file : string;
  pdf_file : string;
}

type compile_status = Success | Failure

type search_entry = {
  se_file : string;
  se_line : int;
  se_message : string;
  se_severity : severity;
}

type compile_result = {
  status : compile_status;
  summary : string;
  log_file : string;
  pdf_file : string;
  search_results : search_entry list;
}
