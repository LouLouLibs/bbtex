#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Open a disposable saved TeX file and check that BBEdit starts TexLab."""
from pathlib import Path
import subprocess
import tempfile
import time

with tempfile.TemporaryDirectory(prefix="bbtex-editor-lsp-") as directory:
    file = Path(directory) / "main.tex"
    file.write_text("\\documentclass{article}\n\\begin{document}\n\\section{Test}\\label{sec:test}\nSee \\ref{sec:test}.\n\\end{document}\n")
    def script(text):
        return subprocess.check_output(["osascript", "-", str(file)], input=text, text=True)
    try:
        print(script("""
on run argv
    tell application "BBEdit"
        set d to open (POSIX file (item 1 of argv))
        return source language of d
    end tell
end run
""").strip())
        for _ in range(20):
            processes = subprocess.run(["pgrep", "-x", "texlab"], capture_output=True, text=True)
            if processes.returncode == 0:
                print("TexLab running while saved TeX document is open:", processes.stdout.strip())
                break
            time.sleep(.5)
        else:
            raise SystemExit("BBEdit did not start TexLab for the saved TeX document.")
    finally:
        script("""
on run argv
    tell application "BBEdit"
        repeat with d in text documents
            try
                set documentFile to get file of d
                if POSIX path of documentFile is item 1 of argv then close d saving no
            end try
        end repeat
    end tell
end run
""")
