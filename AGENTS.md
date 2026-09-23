# Agent guidelines for bbtex

bbtex is an OCaml project: a single `bbtex` binary plus thin bash and
AppleScript glue for BBEdit. Keep it that way.

## Languages

- **Shipped code has no Python.** Anything a user runs (menu commands, pickers,
  previews, installers in the release package) is the OCaml binary, bash, or
  AppleScript. New behavior goes into `bbtex` as a subcommand.
- **Build and install helpers are bash** (`scripts/*.sh`). They run on macOS;
  call system tools by path where GNU and BSD versions differ (e.g. `/bin/cp`).
- **Python is only for integration tests** that drive BBEdit through
  AppleScript or compare against a Python reference implementation. Don't add
  Python for anything else, including one-off utilities.
- **When Python is used, run it through `uv run`** with PEP 723 inline metadata
  and explicit dependencies. Never bare `python`, and never install into
  another environment. If `VIRTUAL_ENV` points at a removed interpreter, use
  `env -u VIRTUAL_ENV uv run ...`.

The Python that remains outside tests is being removed under issue #4. Don't
extend it; prefer porting what you touch.

## Build

- OCaml comes from opam: `opam install . --deps-only`, then `dune build` and
  `dune runtest`. CI pins the compiler with `OCAML_COMPILER` in
  `.github/workflows/`.
- `vendor/` holds copies of other repositories (see each `VENDORED.md`). Change
  them upstream and copy them in again; don't edit them here.

See `docs/HANDOFF.md` for project history and user preferences.
