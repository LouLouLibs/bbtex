#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Check native snippet-window reuse, preserved selection, and image publication."""
import os
from pathlib import Path
import subprocess
import tempfile
import hashlib
import time
import base64
import plistlib
import shlex
import shutil
import json

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="bbtex-live-preview-") as directory:
    folder = Path(directory).resolve()
    source = folder / "main.tex"
    original = "\\documentclass{article}\n\\begin{document}\nx^2 + y^2 = z^2\n\\end{document}\n"
    source.write_text(original)
    window_dir = folder / "state/snippet-window"
    page_name = "bbtex-snippet-" + hashlib.md5(str(window_dir).encode()).hexdigest()[:8] + ".html"
    def apple(script):
        return subprocess.check_output(["osascript", "-", str(source), "Preview: " + page_name, str(folder / "other.tex")],
                                       input=script, text=True).strip()
    try:
        apple('''on run argv
            tell application "BBEdit"
                activate
                delay 0.3
                set d to open (POSIX file (item 1 of argv))
                select characters 42 thru 56 of d
                set index of window of d to 1
            end tell
        end run''')
        # Query the actual selection so off-by-one mistakes cannot silently pass.
        selected = apple('tell application "BBEdit" to get contents of selection')
        assert selected == "x^2 + y^2 = z^2", repr(selected)
        wrapper = os.environ.get("BBTEX_TEST_PREVIEW_WRAPPER", str(ROOT / "scripts/bbtex-bbedit-preview.sh"))
        command = ["/bin/bash", wrapper]
        if service := os.environ.get("BBTEX_TEST_PREVIEW_SERVICE"):
            staged = folder / "preview.workflow"
            shutil.copytree(service, staged)
            workflow = staged / "Contents/document.wflow"
            data = plistlib.loads(workflow.read_bytes())
            parameters = data["actions"][0]["action"]["ActionParameters"]
            parameters["COMMAND_STRING"] = "export BBTEX_STATE_DIR=" + shlex.quote(str(folder / "state")) + "\n" + parameters["COMMAND_STRING"]
            workflow.write_bytes(plistlib.dumps(data))
            command = ["/usr/bin/automator", "-i", selected, str(staged)]
        window_ids = []
        for iteration in range(2):
            started = time.perf_counter()
            result = subprocess.run(command,
                env={**os.environ, "BB_DOC_PATH": str(source), "BBTEX_STATE_DIR": str(folder / "state")},
                capture_output=True, text=True, timeout=60)
            assert result.returncode == 0, (result.stdout, result.stderr)
            print(f"Native preview {iteration + 1}: {time.perf_counter()-started:.3f}s")
            window_ids.append(apple('''on run argv
                tell application "BBEdit"
                    if (contents of selection as text) is not "x^2 + y^2 = z^2" then error "Source focus/selection changed"
                    set matches to {}
                    repeat with w in (get web_preview_windows)
                        if name of w is item 2 of argv then set end of matches to ID of w
                    end repeat
                    if count of matches is not 1 then error "Expected one snippet window"
                    return item 1 of matches
                end tell
            end run'''))
        assert window_ids[0] == window_ids[1]
        assert source.read_text() == original
        pdfs = list((folder / "state").glob("preview-*/selection.pdf"))
        assert len(pdfs) == 1
        published = json.loads((window_dir / "image.js").read_text().split("window.bbtexSnippet(", 1)[1].split(");}else", 1)[0])
        assert published["status"] == "current" and published["source"] == str(source)
        encoded = published["image"].split(",", 1)[1]
        assert base64.b64decode(encoded) == next((folder / "state").glob("preview-*/selection.png")).read_bytes()
        if proof := os.environ.get("BBTEX_PREVIEW_PROOF"):
            subprocess.run(["pdftoppm", "-singlefile", "-scale-to", "1200", "-png", str(pdfs[0]), proof], check=True)
        print("Live preview passed: one BBEdit window reused; PNG published; source and selection preserved")
        # Simulate a completed render after the user has switched documents.
        source_id = apple('tell application "BBEdit" to get ID of front window')
        other = folder / "other.tex"
        other.write_text("Disposable focus check\n")
        subprocess.run(["osascript", "-", str(other)], input='''on run argv
            tell application "BBEdit" to open (POSIX file (item 1 of argv))
        end run''', text=True, check=True)
        other_id = apple('tell application "BBEdit" to get ID of front window')
        apple('''on run argv
            tell application "BBEdit"
                repeat with w in (get web_preview_windows)
                    if name of w is item 2 of argv then close w
                end repeat
            end tell
        end run''')
        helper = Path(wrapper).resolve().parent / "snippet-window.applescript"
        if not helper.exists():
            helper = Path(wrapper).resolve().parents[1] / "Resources/snippet-window.applescript"
        subprocess.run(["osascript", str(helper),
                        str(window_dir / page_name), source_id, page_name, str(source)], check=True)
        assert apple('tell application "BBEdit" to get ID of front window') == other_id
        assert apple('''on run argv
            tell application "BBEdit"
                repeat with w in (get web_preview_windows)
                    if name of w is item 2 of argv then error "Preview stole focus after switching documents"
                end repeat
            end tell
        end run''') == ""
        print("First-window creation skipped after switching documents")
    finally:
        apple('''on run argv
            tell application "BBEdit"
                repeat with w in (get web_preview_windows)
                    if name of w is item 2 of argv then close w
                end repeat
                repeat with d in (get text documents)
                    try
                        set f to get file of d
                        if POSIX path of f is item 1 of argv or POSIX path of f is item 3 of argv then close d saving no
                    end try
                end repeat
            end tell
        end run''')
