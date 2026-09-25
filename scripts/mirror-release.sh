#!/bin/bash
# Mirror a release tag to the UMN GitHub Enterprise copy and publish its docs.
#   scripts/mirror-release.sh vX.Y.Z [--dry-run]
# Only tagged releases leave this repository: the mirror gets the tag, its
# main branch moves (fast-forward only) to the tagged commit, and gh-pages is
# rebuilt from that commit. Work in progress is never pushed there.
# Environment:
#   BBTEX_MIRROR_URL   default git@github.umn.edu:loualiche/bbtex.git
#   BBTEX_MIRROR_BASE  docs base path, default /loualiche/bbtex/
#                      (served at https://pages.github.umn.edu/loualiche/bbtex/)
set -Eeuo pipefail
trap 'echo "mirror-release.sh: line $LINENO failed" >&2' ERR

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
URL="${BBTEX_MIRROR_URL:-git@github.umn.edu:loualiche/bbtex.git}"
BASE="${BBTEX_MIRROR_BASE:-/loualiche/bbtex/}"

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[[ $# -ge 1 && $# -le 2 ]] || usage
TAG="$1"
DRY=0
[[ $# -eq 1 || "$2" == --dry-run ]] || usage
[[ $# -eq 1 ]] || DRY=1
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
    echo "mirror-release.sh: '$TAG' is not a release tag (vX.Y.Z)" >&2; exit 2; }
for tool in git npm npx; do
    command -v "$tool" >/dev/null || { echo "mirror-release.sh: $tool is required" >&2; exit 1; }
done
git -C "$ROOT" rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null || {
    echo "mirror-release.sh: tag $TAG does not exist here" >&2; exit 1; }
COMMIT=$(git -C "$ROOT" rev-parse "$TAG^{commit}")

run() { if [[ $DRY -eq 1 ]]; then echo "would run: $*"; else "$@"; fi; }

echo "Mirroring $TAG ($(git -C "$ROOT" rev-parse --short "$COMMIT")) to $URL"
run git -C "$ROOT" push "$URL" "refs/tags/$TAG:refs/tags/$TAG"
# Fast-forward only: a rejected push means the mirror's main moved on its own.
run git -C "$ROOT" push "$URL" "$COMMIT:refs/heads/main"

# Build the docs from the tagged commit, not the working tree.
WORK=$(mktemp -d)
trap 'git -C "$ROOT" worktree remove --force "$WORK/tree" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
git -C "$ROOT" worktree add --quiet --detach "$WORK/tree" "$COMMIT"
if [[ ! -f "$WORK/tree/site/package.json" ]]; then
    echo "mirror-release.sh: $TAG has no docs site; skipping gh-pages"
    exit 0
fi
if [[ $DRY -eq 1 ]]; then
    BBTEX_DOCS_ROOT="$WORK/tree" BBTEX_DOCS_BASE="$BASE" "$ROOT/scripts/docs-site.sh" build
    echo "would deploy $WORK/tree/site/.vitepress/dist to $URL gh-pages"
else
    BBTEX_DOCS_ROOT="$WORK/tree" BBTEX_DOCS_BASE="$BASE" BBTEX_DOCS_REMOTE="$URL" \
        "$ROOT/scripts/docs-site.sh" deploy
fi
echo "Done. Docs: https://pages.github.umn.edu${BASE}"
