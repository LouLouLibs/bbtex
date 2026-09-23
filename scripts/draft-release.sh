#!/bin/bash
# Called only after local CI passes for the tag (scripts/ci.sh --release TAG).
# Never publishes a release; it creates or updates a draft.
set -euo pipefail
ASSETS="${1:?Expected artifact directory}"
TAG="${RELEASE_TAG:?Expected RELEASE_TAG}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] || {
    echo "Expected a version tag such as v0.2.0 or v0.2.0-rc.1" >&2
    exit 1
}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ASSETS"
for arch in arm64; do
    test -s "bbtex-macos-$arch.bbpackage.zip"
    test -s "build-info-$arch.txt"
    shasum -a 256 -c "SHA256SUMS-$arch.txt"
done
if DRAFT=$(gh release view "$TAG" --json isDraft --jq .isDraft 2>/dev/null); then
    [[ "$DRAFT" == true ]] || {
        echo "Refusing to change an already-published release: $TAG" >&2
        exit 1
    }
else
    gh release create "$TAG" --verify-tag --draft --title "bbtex $TAG" \
        --notes-file "$ROOT/docs/release-notes.md"
fi
gh release upload "$TAG" --clobber ./*.bbpackage.zip ./SHA256SUMS-*.txt ./build-info-*.txt
