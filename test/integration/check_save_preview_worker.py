#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Deterministic save-worker races without editor automation or real TeX."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="bbtex-worker-") as directory:
    root = Path(directory)
    scripts = root / "Contents/Scripts"
    resources = root / "Contents/Resources"
    state = root / "state"
    commands = root / "bin"
    for folder in (scripts, resources, state, commands):
        folder.mkdir(parents=True)
    worker = scripts / "LaTeX — Toggle Preview on Save.sh"
    shutil.copy(ROOT / "scripts/bbtex-preview-on-save.sh", worker)
    shutil.copy(ROOT / "scripts/with-preview-lock.pl", resources)
    (commands / "osascript").write_text('#!/bin/bash\nexit 0\n')
    (commands / "osascript").chmod(0o755)
    binary = resources / "bbtex"
    binary.write_text('''#!/bin/bash
set -eu
s="$BBTEX_STATE_DIR"
case "$1" in
equation-at) printf '%s:%s' "${2##*/}" "$3" ;;
preview)
    value=$(cat)
    printf '%s\\n' "$value" >> "$s/started"
    while [[ -f "$s/render-gate" ]]; do sleep 0.02; done
    [[ ! -f "$s/fail" ]] || { echo 'message: test failure'; exit 2; }
    printf '%s' "$value" > "$s/result.png"
    printf 'png: %s/result.png\\n' "$s" ;;
snippet-finish)
    if [[ "$3" == current ]]; then
        touch "$s/publishing"
        while [[ -f "$s/publish-gate" ]]; do sleep 0.02; done
    fi
    output=$("$BBTEX_TEST_BINARY" "$@") || exit $?
    if [[ "$3" == error ]]; then echo failed >> "$s/published";
    elif [[ "$3" == current ]] && "$BBTEX_TEST_BINARY" snippet-current "$2"; then cat "$4" >> "$s/published"; echo >> "$s/published"; fi
    printf '%s\\n' "$output" ;;
snippet-*) exec "$BBTEX_TEST_BINARY" "$@" ;;
esac
''')
    binary.chmod(0o755)
    env = {**os.environ, "BBTEX_STATE_DIR": str(state),
           "BBTEX_TEST_BINARY": str(ROOT / "_build/default/bin/main.exe"),
           "PATH": str(commands) + ":/usr/bin:/bin"}
    source = root / "a.tex"
    other = root / "b.tex"
    source.write_text("one")
    other.write_text("two")
    flag = state / "preview-on-save-source"
    children = []

    def wait_for(predicate):
        deadline = time.monotonic() + 8
        while not predicate():
            assert time.monotonic() < deadline, "Timed out waiting for worker"
            time.sleep(0.02)

    def save(file, line):
        old = (state / "preview-on-save-request").read_text() if (state / "preview-on-save-request").exists() else None
        p = subprocess.Popen(["/bin/bash", str(worker), "--saved", str(file), str(line), "0"], env=env)
        children.append(p)
        wait_for(lambda: (state / "preview-on-save-request").exists() and (state / "preview-on-save-request").read_text() != old)
        return p

    def finish():
        for p in children:
            assert p.wait(timeout=10) == 0
        children.clear()

    def lines(name):
        p = state / name
        return p.read_text().splitlines() if p.exists() else []

    try:
        flag.write_text(str(source))
        # Legacy stale directory (including missing PID) cannot block new workers.
        (state / "preview-on-save-worker").mkdir()
        (state / "render-gate").touch()
        save(source, 1)
        wait_for(lambda: lines("started") == ["a.tex:1"])
        save(source, 2)
        save(source, 3)
        (state / "render-gate").unlink()
        finish()
        assert lines("published") == ["a.tex:3"], lines("published")
        assert lines("started") == ["a.tex:1", "a.tex:3"]
        print("Rapid saves: superseded output dropped; only latest queued save renders")

        (state / "render-gate").touch()
        save(source, 4)
        wait_for(lambda: lines("started")[-1] == "a.tex:4")
        flag.write_text(str(other))
        save(other, 8)
        (state / "render-gate").unlink()
        finish()
        assert lines("published") == ["a.tex:3", "b.tex:8"]
        print("Switching files: new source survives while old render is discarded")

        (state / "publishing").unlink()
        (state / "publish-gate").touch()
        save(other, 9)
        wait_for(lambda: (state / "publishing").exists())
        save(other, 10)
        (state / "publish-gate").unlink()
        finish()
        assert lines("published")[-2:] == ["b.tex:8", "b.tex:10"]
        print("Save during publication: obsolete result rejected at the publication lock")

        (state / "render-gate").touch()
        save(other, 11)
        wait_for(lambda: lines("started")[-1] == "b.tex:11")
        flag.unlink()
        (state / "render-gate").unlink()
        finish()
        assert lines("published")[-1] == "b.tex:10"
        print("Disabling during render prevents publication")

        flag.write_text(str(other))
        (state / "suppress-save-preview").write_text(str(os.getpid()))
        save(other, 12)
        finish()
        assert lines("started")[-1] == "b.tex:11"
        (state / "suppress-save-preview").unlink()
        (state / "fail").touch()
        save(other, 13)
        finish()
        assert lines("published")[-1] == "failed"
        print("Build suppression and infrastructure-error clearing passed")

        # A process crash releases the kernel lock without deleting lock files.
        ready = state / "lock-ready"
        owner = subprocess.Popen(["/usr/bin/perl", str(resources / "with-preview-lock.pl"),
                                  str(state / "preview-on-save.lock"), "/bin/bash", "-c",
                                  'touch "$1"; exec /bin/sleep 20', "bash", str(ready)])
        children.append(owner)
        wait_for(ready.exists)
        (state / "fail").unlink()
        save(other, 14)
        assert lines("started")[-1] == "b.tex:13"
        owner.kill()
        owner.wait(timeout=5)
        children.remove(owner)
        finish()
        assert lines("published")[-1] == "b.tex:14"
        print("Killed lock owner: queued save proceeds without stale-lock cleanup")
    finally:
        for name in ("render-gate", "publish-gate"):
            (state / name).unlink(missing_ok=True)
        for p in children:
            p.wait(timeout=10)
