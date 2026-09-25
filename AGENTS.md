# Agent guidelines for bbtex

bbtex is an OCaml project: a single `bbtex` binary plus thin bash and
AppleScript glue for BBEdit. Keep it that way.

## Languages

- **Shipped code has no Python.** Anything a user runs (menu commands, pickers,
  previews, installers in the release package) is the OCaml binary, bash, or
  AppleScript. New behavior goes into `bbtex` as a subcommand.
- **Thin glue is bash** (`scripts/*.sh`): copying, linking, calling system
  tools. Anything with real logic (plists, parsing, rollback across several
  steps) is a `bbtex` subcommand in OCaml, not bash and not Python.
- **Bash conventions** (macOS runs `#!/bin/bash` as bash 3.2, so no `mapfile`,
  associative arrays or `${x,,}`): `set -Eeuo pipefail` with an `ERR` trap that
  names the line; check required tools up front; don't read `find` through
  `< <(...)`, where a failure looks like empty output; stage changes and `mv`
  them into place; call tools whose GNU and BSD versions differ by path
  (`/bin/cp`, `/usr/bin/stat`). CI runs shellcheck on every script.
- **Python is only for integration tests** that drive BBEdit through
  AppleScript or compare against a Python reference implementation. Don't add
  Python for anything else, including one-off utilities.
- **When Python is used, run it through `uv run`** with PEP 723 inline metadata
  and explicit dependencies. Never bare `python`, and never install into
  another environment. If `VIRTUAL_ENV` points at a removed interpreter, use
  `env -u VIRTUAL_ENV uv run ...`.

No Python remains outside `test/`. Moving the tests that only exercise the
binary to dune cram tests is tracked in issue #4.

- **Node is for the docs site only.** `site/` holds the VitePress config for
  the site built from `docs/`; `scripts/docs-site.sh build|preview|deploy`
  runs it. Nothing under `site/` ships in the package. User guides live in
  `docs/`, internal notes (plans, status, release process) in `docs/dev/`.

## Build

- OCaml comes from opam: `opam install . --deps-only`, then `dune build` and
  `dune runtest`. CI pins the compiler with `OCAML_COMPILER` in
  `.github/workflows/`.
- `vendor/` holds copies of other repositories (see each `VENDORED.md`). Change
  them upstream and copy them in again; don't edit them here.

## Checks

CI runs locally on Apple Silicon: `scripts/ci.sh --report` before asking for a
merge (`--engines` when build, log or engine code changed). GitHub Actions
workflows are manual-only; don't re-enable push or pull-request triggers.

See `docs/dev/HANDOFF.md` for project history and user preferences.
