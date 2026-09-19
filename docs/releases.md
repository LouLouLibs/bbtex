# CI and releases

The **Build and package** GitHub Actions workflow tests and packages every push
to `main`, pull request, version tag, and manual workflow run. It builds separate
Apple Silicon (`arm64`, `macos-15`) and Intel (`x86_64`, `macos-15-intel`) packages.
Runner labels follow [GitHub's hosted-runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

Each job installs OCaml, dune, uv, and BBEdit's scripting dictionary. It runs
unit tests, mocked project/build/cancellation and save-worker tests, compiles
the editing assets and optional hook, and validates the package ZIP, including
Finder stationery flags and executable permissions after extraction. The
package binary must link only system libraries. Tool versions and the source
commit are recorded beside the ZIP, along with SHA-256 checksums. Actions are
pinned to commit IDs; Homebrew tools use the runner's available formula versions.

No TeX distribution or interactive editor session is needed for CI. Real TeX
rendering, Skim, save attachments, and native focus/selection checks remain
local integration tests; passing CI does not replace those checks. The current
packages are built and tested on macOS 15; older macOS versions are unverified.

## Download a build

Open the successful workflow run under the repository's **Actions** tab and
download `bbtex-macos-arm64` or `bbtex-macos-x86_64`. Each artifact contains its
package ZIP, checksum, and build information. Extract the package ZIP and install
`bbtex.bbpackage`. Artifacts are retained for 14 days. Optional attachment/service
installation is described in [selection preview](selection-preview.md#release-installation).

## Prepare a release

1. Update [release notes](release-notes.md), complete local native checks, and
   commit/push the intended changes to `main`. Wait for CI to pass.
2. Choose the next version, then create and push an annotated tag, for example:

   ```sh
   git tag -a v0.2.0 -m 'bbtex v0.2.0'
   git push origin v0.2.0
   ```

3. The tag workflow rebuilds both architectures. Only after both pass does it
   create a **draft** GitHub release containing both package ZIPs, checksums,
   and build information. Inspect the draft and publish it manually when ready.

A normal push or manual workflow run produces artifacts only. The workflow
does not choose a version, create a tag, or publish a release. Rerunning a tag
build can refresh its draft's assets but refuses to modify a published release.
Release creation uses the built-in `GITHUB_TOKEN` with write permission limited
to the release job; no personal access token is required.
