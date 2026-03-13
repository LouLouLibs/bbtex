open Bbtex

(* ── Simple assertion framework ────────────────────────────── *)

let tests_passed = ref 0
let tests_failed = ref 0

let assert_equal ~msg expected actual =
  if expected <> actual then begin
    Printf.eprintf "FAIL: %s\n  expected: %s\n  actual:   %s\n" msg expected actual;
    incr tests_failed
  end else
    incr tests_passed

let assert_true ~msg cond =
  if not cond then begin
    Printf.eprintf "FAIL: %s\n" msg;
    incr tests_failed
  end else
    incr tests_passed

let run_test name f =
  Printf.printf "  %s ... " name;
  (try
     f ();
     Printf.printf "ok\n"
   with e ->
     Printf.eprintf "EXCEPTION: %s\n" (Printexc.to_string e);
     incr tests_failed)

(* ── Stderr capture helpers ─────────────────────────────────── *)

(** Capture everything written to stderr during [f ()].
    Returns the captured string. *)
let capture_stderr f =
  (* Create a pipe: read end and write end *)
  let (pipe_read, pipe_write) = Unix.pipe () in
  (* Save current stderr fd *)
  let saved_stderr = Unix.dup Unix.stderr in
  (* Redirect stderr to pipe write end *)
  Unix.dup2 pipe_write Unix.stderr;
  Unix.close pipe_write;
  (* Run the function *)
  (try f () with _ -> ());
  (* Flush OCaml's stderr buffer *)
  flush stderr;
  (* Restore stderr *)
  Unix.dup2 saved_stderr Unix.stderr;
  Unix.close saved_stderr;
  (* Read everything from the pipe *)
  let buf = Buffer.create 256 in
  let chunk = Bytes.create 256 in
  let rec read_all () =
    let n = Unix.read pipe_read chunk 0 256 in
    if n > 0 then begin
      Buffer.add_subbytes buf chunk 0 n;
      read_all ()
    end
  in
  (* Set pipe_read to non-blocking to avoid hanging when done *)
  Unix.set_nonblock pipe_read;
  (try read_all () with Unix.Unix_error (Unix.EAGAIN, _, _) -> ());
  Unix.close pipe_read;
  Buffer.contents buf

(* ── Tests ─────────────────────────────────────────────────── *)

let test_info_prints_to_stderr () =
  let output = capture_stderr (fun () -> Log.info "hello world") in
  assert_equal ~msg:"info outputs correct format"
    "bbtex: hello world\n" output

let test_error_prints_to_stderr () =
  let output = capture_stderr (fun () -> Log.error "something went wrong") in
  assert_equal ~msg:"error outputs correct format"
    "bbtex: error: something went wrong\n" output

let test_verbose_silent_by_default () =
  Log.reset_verbose ();
  let output = capture_stderr (fun () -> Log.verbose "should not appear") in
  assert_equal ~msg:"verbose is silent when not enabled" "" output

let test_verbose_prints_after_set_verbose () =
  Log.set_verbose ();
  let output = capture_stderr (fun () -> Log.verbose "verbose message") in
  Log.reset_verbose ();
  assert_equal ~msg:"verbose prints after set_verbose"
    "bbtex: verbose message\n" output

let test_verbose_silent_after_reset () =
  Log.set_verbose ();
  Log.reset_verbose ();
  let output = capture_stderr (fun () -> Log.verbose "should not appear") in
  assert_equal ~msg:"verbose is silent again after reset_verbose" "" output

let test_info_with_special_chars () =
  let output = capture_stderr (fun () -> Log.info "file: foo/bar.tex") in
  assert_true ~msg:"info preserves special chars"
    (String.length output > 0);
  assert_equal ~msg:"info with special chars"
    "bbtex: file: foo/bar.tex\n" output

(* ── Runner ────────────────────────────────────────────────── *)

let () =
  Printf.printf "Log module tests:\n";
  run_test "info prints to stderr" test_info_prints_to_stderr;
  run_test "error prints to stderr" test_error_prints_to_stderr;
  run_test "verbose silent by default" test_verbose_silent_by_default;
  run_test "verbose prints after set_verbose" test_verbose_prints_after_set_verbose;
  run_test "verbose silent after reset_verbose" test_verbose_silent_after_reset;
  run_test "info with special chars" test_info_with_special_chars;
  Printf.printf "\nResults: %d passed, %d failed\n" !tests_passed !tests_failed;
  if !tests_failed > 0 then exit 1
