(** Split BibTeX text into blocks.

    A port of the splitter in python-bibtexparser 2.0.1 (splitter.py and the
    duplicate-key handling of [Library.add]). Results match bibtexparser's
    [parse_string bibtex_str ~parse_stack:[]] block for block, except that
    implicit (free-text) comments are not returned.

    Field values are raw: delimiters ([{...}], ["..."]) and [#]
    concatenations are kept, and [@string] macros are not expanded. *)

type field = { name : string; value : string }

(** Every [line] is the 0-based line of the block's [@]. *)
type block =
  | Entry of { line : int; entry_type : string; key : string; fields : field list }
      (** [entry_type] is lowercased. *)
  | String of { line : int; key : string; value : string }
  | Preamble of { line : int; value : string }
  | Comment of { line : int }  (** an explicit [@comment] block *)
  | Duplicate_key of { line : int; key : string; ignored : block }
      (** A second [Entry] or [String] whose key was already used by the same
          kind of block; it is kept as [ignored]. The first one is returned
          normally. *)
  | Duplicate_field of { line : int; key : string; names : string list; ignored : block }
      (** An entry that repeats field names; [names] are the repeated ones,
          sorted, and the entry is kept as [ignored]. *)
  | Failed of { line : int; reason : string }
      (** A block that could not be parsed. Parsing resumes after it. *)

val parse_string : string -> block list
(** Splits BibTeX text. Never raises; malformed input gives [Failed] blocks. *)

val parse_file : string -> (block list, string) result
(** Reads a file as UTF-8 with an optional byte-order mark, as
    [bytes.decode("utf-8-sig")] does. Returns [Error] when the file is not
    valid UTF-8. Raises [Sys_error] when it cannot be read. *)

val line : block -> int
