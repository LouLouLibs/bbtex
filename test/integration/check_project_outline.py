#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Check outline data and native script compilation; opt into disposable BBEdit jumps."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BINARY = Path(os.environ.get("BBTEX_TEST_BINARY", ROOT / "_build/default/bin/main.exe"))
NATIVE = os.environ.get("BBTEX_TEST_NATIVE") == "1"

def command(*args, check=True):
    return subprocess.run([str(BINARY), *map(str, args)], capture_output=True, text=True, check=check)

def apple(script):
    return subprocess.run(["osascript", "-"], input=script, capture_output=True, text=True)

with tempfile.TemporaryDirectory(prefix="bbtex-outline-") as temporary:
    folder = Path(temporary).resolve() / "paper with spaces"
    folder.mkdir()
    root = folder / "main.tex"
    child = folder / 'chapter "quoted".tex'
    root.write_text('\\documentclass{article}\n\\begin{document}\n'
                    '\\section{Résumé and \\"quotes\\"}\n\\label{same}\n'
                    '\\input{chapter "quoted".tex}\n\\end{document}\n')
    child.write_text('% !TEX root = main.tex\n\\subsection{Results}\n'
                     '\\begin{equation}\nx=1\\label{same}\n\\end{equation}\n'
                     '\\begin{figure}\\caption{A useful diagram}\\label{fig:result}\\end{figure}\n'
                     '\\begin{table}\\caption{Measurements}\\label{tab:result}\\end{table}\n')
    before = {file: file.read_bytes() for file in (root, child)}
    outline = json.loads(command("outline", child).stdout)
    entries = outline["entries"]
    assert outline["version"] == 1 and outline["savedOnly"] and not outline["issues"]
    assert len([e for e in entries if e["kind"] == "label" and e["title"] == "same"]) == 2
    assert {e["kind"] for e in entries} >= {"section", "subsection", "equation", "figure", "table", "label"}
    assert len(json.loads(command("outline", child, "kind:label same").stdout)["entries"]) == 2
    picker = command("outline-picker", child).stdout
    subprocess.run(["osacompile", "-o", str(folder / "picker.scpt"), "-"], input=picker, text=True, check=True)
    subprocess.run(["osacompile", "-o", str(folder / "helper.scpt"),
                    str(ROOT / "scripts/project-outline.applescript")], check=True)
    print("Saved multi-file outline, duplicate labels, search, and native picker compilation passed")
    try:
        if NATIVE:
            for number, entry in enumerate(entries, 1):
                # Exercise the generated native row-to-target mapping without
                # unattended dialogs. Actual keyboard dialog interaction is manual.
                chosen = "\n".join(
                    f"set chosen to {{item {number} of rows}}" if line.startswith("set chosen to choose") else line
                    for line in picker.splitlines())
                selected = apple(chosen)
                assert selected.returncode == 0, selected.stderr
                assert selected.stdout.strip() == f"{entry['file']}, {entry['fingerprint']}, {entry['line']}"
                jump = command("outline-jump", entry["file"], entry["fingerprint"], entry["line"]).stdout
                result = apple(jump)
                assert result.returncode == 0, result.stderr
                location = apple('''tell application "BBEdit"
                    set f to get file of front text document
                    return {POSIX path of f, startLine of selection}
                end tell''')
                assert location.stdout.strip() == f"{entry['file']}, {entry['line']}", location
            target = next(e for e in entries if e["file"] == str(child))
            jump = command("outline-jump", child, target["fingerprint"], target["line"]).stdout
            dirty = apple('''tell application "BBEdit"
                set contents of front text document to "Unsaved changes" & linefeed
            end tell''')
            assert dirty.returncode == 0, dirty.stderr
            rejected = apple(jump)
            assert rejected.returncode != 0 and "unsaved edits" in rejected.stderr, rejected
            print("Every native row opens its exact source/line; dirty buffers are rejected")
        assert {file: file.read_bytes() for file in (root, child)} == before
        target = next(e for e in entries if e["file"] == str(child))
        child.write_bytes(b"\n" + before[child])
        result = command("outline-jump", child, target["fingerprint"], target["line"], check=False)
        assert result.returncode == 2 and "changed" in result.stderr
        refreshed = json.loads(command("outline", root, "kind:subsection").stdout)["entries"]
        assert refreshed[0]["line"] == target["line"] + 1
        print("Changed disk content rejects old targets; reopening the outline refreshes locations")
    finally:
        if NATIVE:
            paths = [str(file) for file in (root, child)]
            # Quoting via JSON is valid AppleScript here (paths have no controls).
            result = apple('''tell application "BBEdit"
                repeat with d in (get text documents)
                    try
                        set f to get file of d
                        if (POSIX path of f) is in {''' + ", ".join(json.dumps(p) for p in paths) + '''} then close d saving no
                    end try
                end repeat
            end tell''')
            assert result.returncode == 0, result.stderr
