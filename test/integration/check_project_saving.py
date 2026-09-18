#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Verify project saving against disposable open BBEdit documents."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "_build/default/bin/main.exe"
with tempfile.TemporaryDirectory(prefix="bbtex-save-") as directory:
    root = Path(directory).resolve()
    project = root / "project"
    project.mkdir()
    main = project / "main.tex"
    chapter = project / "chapter.tex"
    bib = project / "refs.bib"
    other = root / "unrelated.tex"
    for file in (main, chapter, bib, other):
        file.write_text("original\n")
    (project / ".bbtex").write_text("root = main.tex\n")
    script = subprocess.check_output([str(BINARY), "save-project", str(main)], text=True)
    def run(text):
        return subprocess.check_output(["osascript", "-", *map(str, (main, chapter, bib, other))],
                                       input=text, text=True)
    try:
        run('''on run argv
            tell application "BBEdit"
                repeat with p in argv
                    set d to open (POSIX file (contents of p))
                    set text of d to "changed" & linefeed
                end repeat
            end tell
        end run''')
        subprocess.run(["osascript", "-"], input=script, text=True, check=True)
        for file in (main, chapter, bib):
            assert file.read_text() == "changed\n", (file, repr(file.read_text()))
        assert other.read_text() == "original\n", "Unrelated document was saved"
        print("Project saving passed: root, chapter, bibliography saved; unrelated file untouched")
    finally:
        run('''on run argv
            tell application "BBEdit"
                repeat with d in (get text documents)
                    try
                        set documentFile to get file of d
                        if argv contains (POSIX path of documentFile) then close d saving no
                    end try
                end repeat
            end tell
        end run''')
