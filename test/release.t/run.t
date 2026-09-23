Draft release gating: real checksums, a fake gh that records its calls.

  $ release=../../scripts/draft-release.sh
  $ mkdir assets bin
  $ cat > bin/gh <<'FAKE'
  > #!/bin/bash
  > printf '%s\n' "$*" >> "$TRACE"
  > if [[ "$2" == view ]]; then
  >   case "$STATE" in missing) exit 1;; draft) echo true;; published) echo false;; esac
  > fi
  > FAKE
  $ chmod +x bin/gh && export PATH="$PWD/bin:$PATH" TRACE="$PWD/trace"
  $ (cd assets && printf 'fixture archive' > bbtex-macos-arm64.bbpackage.zip &&
  >   shasum -a 256 bbtex-macos-arm64.bbpackage.zip > SHA256SUMS-arm64.txt &&
  >   echo 'Architecture: arm64' > build-info-arm64.txt)
  $ run() { : > "$TRACE"; STATE="$1" RELEASE_TAG="$2" bash "$release" assets > /dev/null 2>&1; echo "exit $?"; cut -d' ' -f1-2 "$TRACE"; }

A missing release is created as a draft, then uploaded; a draft is updated:

  $ run missing v0.2.0
  exit 0
  release view
  release create
  release upload
  $ run draft v0.2.0-rc.1
  exit 0
  release view
  release upload

A published release, a bad tag, a corrupted archive and a missing build-info
file are all refused before gh changes anything:

  $ run published v0.2.0
  exit 1
  release view
  $ run missing vbad
  exit 1
  $ printf 'corrupted' > assets/bbtex-macos-arm64.bbpackage.zip; run missing v0.2.0
  exit 1
  $ printf 'fixture archive' > assets/bbtex-macos-arm64.bbpackage.zip; rm assets/build-info-arm64.txt; run draft v0.2.0
  exit 1
