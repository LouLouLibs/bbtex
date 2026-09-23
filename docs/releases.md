# CI and releases

bbtex supports Apple Silicon Macs. Checks run locally on an Apple Silicon Mac
with `scripts/ci.sh`; the GitHub Actions workflows are kept but run only when
started by hand (Actions → workflow → Run workflow), because Actions minutes
are limited on this private repository.

## Local CI

```sh
scripts/ci.sh                   # check HEAD
scripts/ci.sh --report          # ... and post the result on GitHub
scripts/ci.sh --engines REF     # also compile the corpus with real TeX engines
```

The script checks out the commit into a temporary git worktree, so uncommitted
changes in your working folder never affect the result, then runs:

1. `dune build` and `dune runtest` (unit and cram tests).
2. Integration checks that need no editor session: project builds, preview
   cancellation, the snippet page, and draft-release gating.
3. shellcheck and `bash -n` on every script, `perl -c` on the preview lock, and
   `git diff --check` on the commit's changes relative to `main`.
4. The release package: `test/integration/check_preview_release.sh`, an arm64
   architecture check, and a check that the binary links only system libraries.
   The package ZIP, its SHA-256 checksum and build information (commit, macOS,
   OCaml, dune and uv versions) are written to `dist/release/`.
5. With `--engines`: the article/book/Beamer corpus with pdfLaTeX, XeLaTeX and
   LuaLaTeX, including BibTeX/Biber and Poppler. With `--tectonic`: the Tectonic
   tier, which downloads bundle resources and uses the installed Biber; see
   [real-engine coverage](real-engine-regressions.md).

`--report` posts the commit status `local-ci/macos-arm64` (or
`local-ci/macos-arm64+engines`) through `gh`, so pull requests show the local
result. Statuses use no Actions minutes. The output of every step goes to a log
next to the temporary checkout; a failing run keeps both for inspection
(`--keep` keeps them after a pass too). The script notes when the local OCaml
differs from the version CI pins (`OCAML_COMPILER` in `.github/workflows/ci.yml`).

Skim, save attachments, and native focus/selection checks remain separate local
integration tests (`BBTEX_TEST_NATIVE=1`). Packages are built and tested on the
macOS version of the Mac running the checks; older versions are unverified.

## Prepare a release

1. Update [release notes](release-notes.md), complete the native checks, and
   merge the intended changes into `main`.
2. Choose the next version, then create and push an annotated tag:

   ```sh
   git tag -a v0.2.0 -m 'bbtex v0.2.0'
   git push origin v0.2.0
   ```

3. Run `scripts/ci.sh --engines --report --release v0.2.0 v0.2.0`. After every
   check passes, it creates or updates a **draft** GitHub release with the arm64
   package ZIP, checksum and build information. It refuses to change a release
   that is already published. Publishing the draft is manual.
