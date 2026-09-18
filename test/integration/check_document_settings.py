#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Exercise the setup edit in BBEdit with an external main file."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "_build/default/bin/main.exe"
with tempfile.TemporaryDirectory(prefix="bbtex-settings-") as directory:
    folder = Path(directory).resolve()
    (folder / "tables").mkdir()
    (folder / "paper elsewhere").mkdir()
    source = folder / "tables" / 'table "one".tex'
    main = folder / "paper elsewhere" / "main.tex"
    original = "%!TEX program = pdflatex\nα & β \\\\\n"
    source.write_text(original)
    main.write_text("%!TEX program = xelatex\n\\documentclass{article}\n")
    def run(script):
        return subprocess.check_output(["osascript", "-", str(source), str(BINARY), str(main)],
                                       input=script, text=True)
    try:
        run('''on run argv
            set commandText to quoted form of (item 2 of argv) & " document-settings " & quoted form of (item 1 of argv) & " inherit " & quoted form of (item 3 of argv)
            set editScript to do shell script commandText without altering line endings
            run script editScript
            tell application "BBEdit"
                set d to open (POSIX file (item 1 of argv))
                if not (modified of d) then error "Settings should remain unsaved for review"
                save d
            end tell
        end run''')
        assert source.read_text() == "%!TEX root = ../paper elsewhere/main.tex\n" + original.split("\n", 1)[1]
        paths = subprocess.check_output([str(BINARY), "paths", str(source)], text=True)
        assert f"root: {main}\n" in paths and "engine: xelatex\n" in paths, paths
        print("Native settings edit passed: Unicode and quoted paths preserved; external root and inherited engine resolved")
    finally:
        run('''on run argv
            tell application "BBEdit"
                repeat with d in (get text documents)
                    try
                        set f to get file of d
                        if (POSIX path of f) is item 1 of argv then close d saving no
                    end try
                end repeat
            end tell
        end run''')
