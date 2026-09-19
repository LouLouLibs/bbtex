#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Verify draft release gating with real checksums and a mocked GitHub CLI."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="bbtex-release-") as directory:
    root = Path(directory)
    assets = root / "assets"
    commands = root / "bin"
    assets.mkdir()
    commands.mkdir()
    trace = root / "trace"
    gh = commands / "gh"
    gh.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$RELEASE_TEST_TRACE"
if [[ "$2" == view ]]; then
    case "$RELEASE_TEST_STATE" in
        missing) exit 1 ;;
        draft) echo true ;;
        published) echo false ;;
    esac
fi
''')
    gh.chmod(0o755)
    for arch in ("arm64", "x86_64"):
        name = f"bbtex-macos-{arch}.bbpackage.zip"
        data = f"fixture archive for {arch}".encode()
        (assets / name).write_bytes(data)
        (assets / f"SHA256SUMS-{arch}.txt").write_text(f"{hashlib.sha256(data).hexdigest()}  {name}\n")
        (assets / f"build-info-{arch}.txt").write_text(f"Architecture: {arch}\n")
    def run(state, tag="v0.2.0"):
        trace.write_text("")
        result = subprocess.run(["bash", str(ROOT / "scripts/draft-release.sh"), str(assets)],
            env={**os.environ, "PATH": str(commands) + ":" + os.environ["PATH"],
                 "RELEASE_TAG": tag, "RELEASE_TEST_STATE": state, "RELEASE_TEST_TRACE": str(trace)},
            capture_output=True, text=True)
        return result, trace.read_text()
    result, calls = run("missing")
    assert result.returncode == 0, result.stderr
    assert "--verify-tag --draft" in calls and "release upload" in calls, calls
    result, calls = run("draft", "v0.2.0-rc.1")
    assert result.returncode == 0 and "release create" not in calls and "release upload" in calls
    result, calls = run("published")
    assert result.returncode != 0 and "release upload" not in calls
    result, calls = run("missing", "vbad")
    assert result.returncode != 0 and not calls
    (assets / "bbtex-macos-arm64.bbpackage.zip").write_bytes(b"corrupted")
    result, calls = run("missing")
    assert result.returncode != 0 and not calls
    (assets / "bbtex-macos-arm64.bbpackage.zip").write_bytes(b"fixture archive for arm64")
    (assets / "bbtex-macos-x86_64.bbpackage.zip").unlink()
    result, calls = run("draft")
    assert result.returncode != 0 and not calls
    print("Draft creation/update, published-release refusal, version gating, and artifact checks passed")
