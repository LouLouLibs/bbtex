#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Exercise real preview jobs with slow fake engines and scoped supersession."""
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "_build/default/bin/main.exe"
with tempfile.TemporaryDirectory(prefix="bbtex-preview-cancel-") as directory:
    root = Path(directory).resolve()
    commands = root / "bin"
    state = root / "state"
    commands.mkdir()
    state.mkdir()
    source = root / "main.tex"
    other = root / "other.tex"
    for path in (source, other):
        path.write_text("\\documentclass{article}\n\\begin{document}\nx\n\\end{document}\n")
    for name in ("pdflatex", "latexmk"):
        engine = commands / name
        engine.write_text('''#!/bin/bash
echo $$ > "$BBTEX_TEST_DIR/engine.pid"
sleep 40 &
echo $! > "$BBTEX_TEST_DIR/child.pid"
wait
''')
        engine.chmod(0o755)
    env = {**os.environ, "PATH": str(commands) + ":/usr/bin:/bin",
           "BBTEX_TEST_DIR": str(root), "BBTEX_STATE_DIR": str(state)}
    (state / "preview-on-save-source").write_text(str(source))
    processes = []

    def run(*args):
        return subprocess.check_output([str(BINARY), *map(str, args)], env=env, text=True).strip()

    def start(command, token=None):
        for name in ("engine.pid", "child.pid"):
            (root / name).unlink(missing_ok=True)
        p = subprocess.Popen([str(BINARY), command, str(source)],
            env={**env, **({"BBTEX_PREVIEW_TOKEN": token} if token else {})},
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        processes.append(p)
        p.stdin.write("x")
        p.stdin.close()
        p.stdin = None
        deadline = time.monotonic() + 5
        while not (root / "child.pid").exists():
            assert p.poll() is None, p.communicate()
            assert time.monotonic() < deadline
            time.sleep(0.02)
        return p

    def cancelled(p):
        output, error = p.communicate(timeout=5)
        assert p.returncode == 3 and "status: cancelled" in output, (output, error)
        for name in ("engine.pid", "child.pid"):
            pid = (root / name).read_text().strip()
            status = subprocess.run(["ps", "-o", "stat=", "-p", pid], capture_output=True, text=True)
            assert status.returncode != 0 or status.stdout.strip().startswith("Z"), status.stdout

    try:
        token = run("snippet-begin", source, 3, "auto")
        p = start("preview", token)
        newer = run("snippet-begin", source, 3, "manual")
        cancelled(p)
        run("snippet-current", newer)
        print("A newer request cancels the obsolete preview and its compiler children")

        token = run("snippet-begin", source, 3, "auto")
        p = start("preview", token)
        run("snippet-stop", other, "Unrelated full build")
        time.sleep(0.15)
        assert p.poll() is None
        run("snippet-stop", source, "Full build takes priority")
        cancelled(p)
        print("Full-build interruption applies only to the matching automatic preview")

        p = start("compile")
        token = run("snippet-begin", source, 3, "auto")
        busy = subprocess.run([str(BINARY), "preview", str(source)], input="x", text=True,
            capture_output=True, env={**env, "BBTEX_PREVIEW_TOKEN": token})
        assert busy.returncode == 2 and "already building" in busy.stdout
        run("snippet-stop", source, "Stop only automatic preview")
        time.sleep(0.15)
        assert p.poll() is None, "A full build was incorrectly cancelled"
        run("cancel", source)
        output, error = p.communicate(timeout=5)
        assert "status: cancelled" in output, (output, error)
        print("Preview supersession does not cancel an independently running full build")
    finally:
        for p in processes:
            if p.poll() is None:
                run("cancel", source)
                p.communicate(timeout=5)
