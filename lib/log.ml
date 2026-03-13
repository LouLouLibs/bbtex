(** Structured logging to stderr.

    All log output goes to stderr so it doesn't interfere with
    the stdout protocol. Verbose mode is controlled by a global
    ref, set once at startup from main.ml. *)

let verbose_enabled = ref false

let set_verbose () = verbose_enabled := true

let reset_verbose () = verbose_enabled := false

let info msg =
  Printf.eprintf "bbtex: %s\n%!" msg

let verbose msg =
  if !verbose_enabled then
    Printf.eprintf "bbtex: %s\n%!" msg

let error msg =
  Printf.eprintf "bbtex: error: %s\n%!" msg
