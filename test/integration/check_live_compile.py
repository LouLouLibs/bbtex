#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Compile a disposable document through the actual BBEdit/Skim wrapper."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="bbtex-live-") as directory:
    root = Path(directory).resolve()
    source = root / "main.tex"
    pdf = root / "build output/main.pdf"
    (root / ".bbtex").write_text("root = main.tex\noutput_directory = build output\n")
    original = "%!TEX program = pdflatex\n\\documentclass{article}\n\\begin{document}\nA live bbtex compilation check.\n\\end{document}\n"
    source.write_text(original)
    def applescript(text):
        return subprocess.check_output(["osascript", "-", str(source), str(pdf)],
                                       input=text, text=True).strip()
    try:
        applescript("""
on run argv
    tell application "BBEdit"
        set d to open (POSIX file (item 1 of argv))
        select insertion point before character 83 of d
    end tell
end run
""")
        env = {**os.environ, "BB_DOC_PATH": str(source), "BB_DOC_SELSTART_LINE": "4",
               "BBTEX_STATE_DIR": str(root / "state")}
        result = subprocess.run(["/bin/bash", str(ROOT / "scripts/bbtex-bbedit-compile.sh")],
                                env=env, capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, (result.stderr, (root / "state/last-compile.log").read_text())
        assert result.stdout == ""
        assert pdf.is_file() and pdf.stat().st_size > 0
        assert (root / "build output/main.synctex.gz").is_file()
        assert source.read_text() == original
        # Inspect only the PDF created by this test, without UI scripting.
        page = applescript("""
on run argv
    tell application "Skim"
        repeat with d in documents
            if path of d is item 2 of argv then return index of current page of d
        end repeat
    end tell
    error "Test PDF was not opened in Skim"
end run
""")
        assert page == "1", page
        print("Live compile passed: configured output directory, PDF and SyncTeX produced; Skim opened page 1; source unchanged")
    finally:
        applescript("""
on run argv
    tell application "Skim"
        repeat with d in (get documents)
            if path of d is item 2 of argv then close d saving no
        end repeat
    end tell
    tell application "BBEdit"
        repeat with d in (get text documents)
            try
                set documentFile to get file of d
                if POSIX path of documentFile is item 1 of argv then close d saving no
            end try
        end repeat
    end tell
end run
""")
