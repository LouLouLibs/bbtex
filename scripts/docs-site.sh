#!/bin/bash
# Build, preview or publish the documentation site (VitePress, sources in docs/).
#   scripts/docs-site.sh build     # site/.vitepress/dist, fails on dead links
#   scripts/docs-site.sh preview   # build, then serve at http://localhost:4173/bbtex/
#   scripts/docs-site.sh deploy    # build, then push the result to the gh-pages branch
# Node is used only here; nothing from site/ ships in the bbtex package.
# Optional environment (used by scripts/mirror-release.sh):
#   BBTEX_DOCS_ROOT    checkout to build from (default: this repository)
#   BBTEX_DOCS_REMOTE  git URL to deploy to (default: this repository's origin)
#   BBTEX_DOCS_BASE    site base path (default: /bbtex/)
set -Eeuo pipefail
trap 'echo "docs-site.sh: line $LINENO failed" >&2' ERR

ROOT="${BBTEX_DOCS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SITE="$ROOT/site"
DIST="$SITE/.vitepress/dist"
BRANCH=gh-pages

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[[ $# -eq 1 ]] || usage
for tool in npm npx git; do
    command -v "$tool" >/dev/null || { echo "docs-site.sh: $tool is required" >&2; exit 1; }
done

build() {
    if [[ ! -d "$SITE/node_modules" ]]; then
        (cd "$SITE" && npm ci --no-fund --no-audit)
    fi
    (cd "$SITE" && npx vitepress build)
}

deploy() {
    build
    local remote
    remote="${BBTEX_DOCS_REMOTE:-$(git -C "$ROOT" remote get-url origin)}"
    # Global, so the EXIT trap can still see it after this function returns.
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    # Publish from a throwaway clone of the gh-pages branch, so the working
    # tree and its uncommitted changes are never touched.
    if git ls-remote --exit-code --heads "$remote" "$BRANCH" >/dev/null; then
        git clone --quiet --depth 1 --branch "$BRANCH" "$remote" "$work/site"
    else
        git init --quiet "$work/site"
        git -C "$work/site" checkout --quiet --orphan "$BRANCH"
        git -C "$work/site" remote add origin "$remote"
    fi
    find "$work/site" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
    /bin/cp -R "$DIST/." "$work/site/"
    touch "$work/site/.nojekyll"
    git -C "$work/site" add --all
    if git -C "$work/site" diff --cached --quiet; then
        echo "docs-site.sh: $BRANCH is already up to date"
        return
    fi
    git -C "$work/site" commit --quiet -m "Deploy docs from $(git -C "$ROOT" rev-parse --short HEAD)"
    git -C "$work/site" push --quiet origin "HEAD:$BRANCH"
    echo "docs-site.sh: pushed to $BRANCH"
}

case "$1" in
    build) build ;;
    preview) build && (cd "$SITE" && npx vitepress preview) ;;
    deploy) deploy ;;
    *) usage ;;
esac
