#!/bin/bash
# Local CI for Apple Silicon: the checks GitHub Actions used to run, on a clean
# checkout of a commit (never the working folder).
#   scripts/ci.sh [options] [REF]          REF defaults to HEAD
#     --engines        also compile the corpus with pdfLaTeX, XeLaTeX and LuaLaTeX
#     --tectonic       also run the Tectonic tier (network; uses installed Biber)
#     --report         post the result as the commit status "local-ci/macos-arm64"
#     --release TAG    after passing, create or update the draft GitHub release TAG
#                      (REF must be that tag)
#     --keep           keep the checkout and log for inspection
set -Eeuo pipefail
trap 'echo "${0##*/}: failed at line $LINENO: $BASH_COMMAND" >&2' ERR

fail() { echo "${0##*/}: $*" >&2; exit 1; }
ENGINES=false TECTONIC=false REPORT=false KEEP=false RELEASE="" REF=HEAD
while (( $# > 0 )); do
    case "$1" in
        --engines) ENGINES=true ;;
        --tectonic) TECTONIC=true ;;
        --report) REPORT=true ;;
        --keep) KEEP=true ;;
        --release) RELEASE="${2:?--release needs a tag}"; shift ;;
        -*) fail "unknown option $1 (see the header of this script)" ;;
        *) REF="$1" ;;
    esac
    shift
done
[[ "$(uname -sm)" == "Darwin arm64" ]] || fail "runs on Apple Silicon macOS only"
for tool in git dune ocamlc uv node perl shellcheck osacompile otool; do
    command -v "$tool" >/dev/null || fail "$tool not found"
done
if $REPORT || [[ -n "$RELEASE" ]]; then
    command -v gh >/dev/null || fail "gh not found (needed for --report and --release)"
fi
unset VIRTUAL_ENV

REPO="$(git rev-parse --show-toplevel)"
SHA="$(git -C "$REPO" rev-parse --verify "$REF^{commit}")"
SHORT="${SHA:0:9}"
if [[ -n "$RELEASE" ]]; then
    [[ "$(git -C "$REPO" rev-parse --verify "$RELEASE^{commit}" 2>/dev/null)" == "$SHA" ]] ||
        fail "--release $RELEASE: tag missing or not at $REF"
fi
PINNED="$(sed -n "s/^ *OCAML_COMPILER: '\(.*\)'/\1/p" "$REPO/.github/workflows/ci.yml" | head -1)"
if [[ -n "$PINNED" && "$(ocamlc -version)" != "$PINNED" ]]; then
    echo "note: OCaml $(ocamlc -version) here, CI pins $PINNED" >&2
fi

CONTEXT="local-ci/macos-arm64"
$ENGINES && CONTEXT="$CONTEXT+engines"
report() { # state, description
    $REPORT || return 0
    gh api --silent "repos/{owner}/{repo}/statuses/$SHA" -f state="$1" \
        -f context="$CONTEXT" -f description="$2" || echo "warning: could not post status" >&2
}

CHECKOUT="$(mktemp -d "${TMPDIR:-/tmp}/bbtex-ci-$SHORT-XXXXXX")"
LOG="$CHECKOUT.log"
cleanup() {
    if ! $KEEP; then
        git -C "$REPO" worktree remove --force "$CHECKOUT" 2>/dev/null || rm -rf "$CHECKOUT"
    fi
}
trap cleanup EXIT
git -C "$REPO" worktree add --quiet --detach "$CHECKOUT" "$SHA"
cd "$CHECKOUT"
report pending "running on $(hostname -s)"
echo "Local CI for $SHORT ($(git log -1 --format=%s "$SHA")) — log: $LOG"

STARTED=$SECONDS
CURRENT=""
step() { # name, command...
    CURRENT="$1"; shift
    local began=$SECONDS
    printf '  %-28s' "$CURRENT"
    if "$@" >> "$LOG" 2>&1; then
        echo "ok ($((SECONDS - began))s)"
    else
        echo "FAILED — see $LOG"
        echo "  checkout kept at $CHECKOUT (remove: git worktree remove --force \"$CHECKOUT\")"
        report failure "$CURRENT failed"
        KEEP=true
        exit 1
    fi
}

build() { dune build && dune runtest; }
integration() {
    uv run test/integration/check_project_builds.py
    uv run test/integration/check_preview_cancellation.py
    node test/integration/check_snippet_page.mjs
    uv run test/integration/check_draft_release.py
}
lint() {
    shellcheck -s bash scripts/*.sh test/integration/*.sh
    for script in scripts/*.sh test/integration/*.sh; do bash -n "$script"; done
    perl -c scripts/with-preview-lock.pl
    # Whitespace errors in this commit's changes relative to main.
    local base
    base="$(git merge-base "$SHA" origin/main 2>/dev/null || git rev-parse "$SHA~1")"
    git diff --check "$base" "$SHA"
}
package() {
    bash test/integration/check_preview_release.sh
    file _build/default/bin/main.exe | grep -F arm64
    # Packages must not require Homebrew or opam libraries.
    if otool -L _build/default/bin/main.exe | tail -n +2 | awk '{print $1}' |
        grep -Ev '^(/usr/lib/|/System/Library/)'; then
        echo "Unexpected non-system dynamic library dependency"; return 1
    fi
    mkdir -p dist/release
    cp dist/bbtex.bbpackage.zip dist/release/bbtex-macos-arm64.bbpackage.zip
    { echo "Commit: $SHA"; echo "Architecture: arm64"; sw_vers; ocamlc -version
      dune --version; uv --version; } > dist/release/build-info-arm64.txt
    (cd dist/release && shasum -a 256 bbtex-macos-arm64.bbpackage.zip > SHA256SUMS-arm64.txt)
}
engine() { uv run test/integration/check_real_engines.py --engine "$1"; }

step "build and unit tests" build
step "integration checks" integration
step "shellcheck and syntax" lint
step "package and archive checks" package
if $ENGINES; then
    for name in pdflatex xelatex lualatex; do step "real engines: $name" engine "$name"; done
fi
if $TECTONIC; then
    step "real engines: tectonic" uv run test/integration/check_tectonic.py
fi
if [[ -n "$RELEASE" ]]; then
    step "draft release $RELEASE" env RELEASE_TAG="$RELEASE" bash scripts/draft-release.sh dist/release
fi

SUMMARY="passed in $((SECONDS - STARTED))s on $(hostname -s)"
report success "$SUMMARY"
echo "Local CI $SUMMARY"
