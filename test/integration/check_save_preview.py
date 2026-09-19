#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Exercise the installed BBEdit save attachment with a disposable document."""
from pathlib import Path
import subprocess
import tempfile
import time

state = Path.home() / ".local/state/bbtex"
flag = state / "preview-on-save-source"
image = state / "snippet-window/image.js"
backups = {p: p.read_bytes() if p.exists() else None for p in (flag, image)}
with tempfile.TemporaryDirectory(prefix="bbtex-save-preview-") as directory:
    source = Path(directory).resolve() / "main.tex"
    source.write_text("\\documentclass{article}\n\\begin{document}\n\\[x=1\\]\n\\end{document}\n")
    def apple(script):
        return subprocess.check_output(["osascript", "-", str(source)], input=script, text=True)
    try:
        flag.write_text(str(source))
        previous = None
        for expression in ("x=2", "x=345"):
            before = image.stat().st_mtime_ns if image.exists() else 0
            apple('''on run argv
                tell application "BBEdit"
                    set d to open (POSIX file (item 1 of argv))
                    set contents of line 3 of d to "\\\\[''' + expression + '''\\\\]" & linefeed
                    select insertion point before character 44 of d
                    save d
                end tell
            end run''')
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                if image.exists() and image.stat().st_mtime_ns > before:
                    break
                time.sleep(0.1)
            else:
                log = state / "preview-on-save.log"
                raise AssertionError("Save did not publish preview: " + (log.read_text() if log.exists() else "hook did not launch worker"))
            current = image.read_bytes()
            assert current.startswith(b'showSnippet("data:image/png;base64,')
            assert current != previous
            previous = current
            time.sleep(1)
        print("Actual BBEdit saves published two different equation previews.")
    finally:
        flag.unlink(missing_ok=True)
        apple('''on run argv
            tell application "BBEdit"
                repeat with d in (get text documents)
                    try
                        set f to get file of d
                        if POSIX path of f is item 1 of argv then close d saving no
                    end try
                end repeat
            end tell
        end run''')
        for path, data in backups.items():
            if data is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(data)
