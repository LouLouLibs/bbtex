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
import json

state = Path.home() / ".local/state/bbtex"
flag = state / "preview-on-save-source"
image = state / "snippet-window/image.js"
backups = {p: p.read_bytes() if p.exists() else None for p in (flag, image, state / "snippet-window/state-v2")}
# Retain a recovery copy even if a native assertion or cleanup step fails.
recovery = Path(tempfile.mkdtemp(prefix="bbtex-preview-backup-"))
for path, data in backups.items():
    if data is not None:
        (recovery / path.name).write_bytes(data)
with tempfile.TemporaryDirectory(prefix="bbtex-save-preview-") as directory:
    source = Path(directory).resolve() / "main.tex"
    source.write_text("\\documentclass{article}\n\\begin{document}\n\\[x=1\\]\n\\end{document}\n")
    def apple(script):
        return subprocess.check_output(["osascript", "-", str(source)], input=script, text=True)
    try:
        flag.write_text(str(source))
        previous = None
        for expression, expected_status in (("x=2", "current"), ("x=345", "current"), (r"\undefinedBbtexPreviewCommand", "error")):
            expression = expression.replace("\\", "\\\\").replace('"', '\\"')
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
                    published = json.loads(image.read_text().split("window.bbtexSnippet(", 1)[1].split(");}else", 1)[0])
                    if published["status"] == expected_status:
                        break
                time.sleep(0.1)
            else:
                log = state / "preview-on-save.log"
                raise AssertionError("Save did not publish preview: " + (log.read_text() if log.exists() else "hook did not launch worker"))
            current = image.read_bytes()
            assert published["source"] == str(source) and published["line"] == 3
            assert published["image"].startswith("data:image/png;base64,")
            if expected_status == "current":
                assert published["image"] != previous
                previous = published["image"]
            else:
                assert published["image"] == previous
                assert Path(published["log"]).is_file()
            time.sleep(1)
        print("Actual BBEdit saves published distinct previews, then marked the old image stale on a rendering error with its log.")
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
        if backups[flag] is None:
            flag.unlink(missing_ok=True)
        else:
            flag.write_bytes(backups[flag])
        # Restore the prior display with a newer revision: an open modern page
        # correctly ignores payloads whose revision moves backwards.
        saved_state = state / "snippet-window/state-v2"
        latest = int(saved_state.read_text().split("\0")[1]) if saved_state.exists() else 0
        previous = backups[saved_state]
        if previous:
            fields = previous.decode().split("\0")
        else:
            old_image = ""
            if backups[image] and backups[image].startswith(b"showSnippet("):
                old_image, _ = json.JSONDecoder().raw_decode(backups[image].decode()[len("showSnippet("):])
            fields = ["", "0", "stale", "", "0", old_image, "0",
                      "Previous preview restored. Select or save an equation to refresh.", "", "", "manual"]
        fields[0] = "restored-" + str(time.time_ns())
        fields[1] = str(max(latest, int(fields[1])) + 1)
        saved_state.write_text("\0".join(fields))
        restored = dict(generation=fields[0], revision=int(fields[1]), status=fields[2],
                        source=fields[3], line=int(fields[4]), image=fields[5], imageLine=int(fields[6]),
                        message=fields[7], log=fields[8])
        image.write_text("if(window.bbtexSnippet){window.bbtexSnippet(" + json.dumps(restored) +
                         ");}else{location.reload();}")
