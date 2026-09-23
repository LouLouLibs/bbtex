#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Verify project saving and the preview's unsaved-input check against disposable
open BBEdit documents."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "_build/default/bin/main.exe"
with tempfile.TemporaryDirectory(prefix="bbtex-save-") as directory:
    root = Path(directory).resolve()
    project = root / "project"
    shared = root / "shared"
    project.mkdir()
    shared.mkdir()
    main = project / "main.tex"
    chapter = project / "chapter.tex"
    bib = project / "refs.bib"
    definitions = project / "style.def"
    macros = shared / "macros.tex"          # outside the project, but included
    notes = project / "notes.txt"           # inside, but not a TeX input
    other = root / "unrelated.tex"          # neither inside nor included
    for file in (chapter, bib, definitions, macros, notes, other):
        file.write_text("original\n")
    main.write_text("\\input{chapter}\n\\input{../shared/macros}\n")
    (project / ".bbtex").write_text("root = main.tex\n")
    documents = (main, chapter, bib, definitions, macros, notes, other)
    save = subprocess.check_output([str(BINARY), "save-project", str(main)], text=True)
    check = subprocess.check_output([str(BINARY), "save-project", "--check", str(main)], text=True)

    def run(text, *args):
        return subprocess.run(["osascript", "-", *map(str, args)], input=text, text=True,
                              capture_output=True)
    try:
        opened = run('''on run argv
            tell application "BBEdit"
                repeat with p in argv
                    set d to open (POSIX file (contents of p))
                    set text of d to "changed" & linefeed
                end repeat
            end tell
        end run''', *documents)
        assert opened.returncode == 0, opened.stderr
        refused = run(check)
        assert refused.returncode != 0 and "Save modified project inputs" in refused.stderr, refused
        saved = run(save)
        assert saved.returncode == 0, saved.stderr
        for file in (main, chapter, bib, definitions, macros):
            assert file.read_text() == "changed\n", (file, repr(file.read_text()))
        for file in (notes, other):
            assert file.read_text() == "original\n", f"{file.name} should not have been saved"
        allowed = run(check)
        assert allowed.returncode == 0, ("unrelated unsaved documents must not block", allowed.stderr)
        print("Project saving passed: root, chapter, bibliography, .def and an included file outside "
              "the project saved; notes.txt and an unrelated file untouched; --check refuses, then allows")
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
        end run''', *documents)
