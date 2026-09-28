#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Verify native result creation and cleanup in BBEdit using disposable files."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "_build/default/bin/main.exe"
with tempfile.TemporaryDirectory(prefix="bbtex-results-") as directory:
    source = Path(directory) / "main.tex"
    source.write_text("% !TEX jobname = draft\n\\documentclass{article}\n\\begin{document}\nx\n\\end{document}\n")
    # v0.2 entries: an error hint (note_kind), an ignored comment and a latexmkrc
    # setting, which points BBEdit at a file that isn't .tex.
    (Path(directory) / "latexmkrc").write_text("$out_dir = 'elsewhere';\n")
    log = source.with_suffix(".log")
    log.write_text("(./main.tex\n! Undefined control sequence.\nl.3 \\oops\n)\n")
    def apply_results():
        result = subprocess.run([str(BINARY), "results", str(source)], capture_output=True,
                                text=True, check=True)
        protocol = dict(line.split(": ", 1) for line in result.stdout.splitlines())
        script = Path(protocol["applescript_file"])
        try:
            text = script.read_text().replace('"LaTeX Results"', '"bbtex Test Results"').replace(
                '"LaTeX Errors"', '"bbtex Test Legacy"')
            if log.read_text():
                for expected in ["result_kind:note_kind", "[bbtex] A command isn't defined",
                                 "[bbtex] % !TEX jobname = draft is ignored", "[bbtex] latexmkrc: $out_dir"]:
                    assert expected in text, (expected, text)
            subprocess.run(["osascript", "-"], input=text, text=True, check=True)
        finally:
            script.unlink()
    def count():
        return subprocess.check_output(["osascript", "-e",
            'tell application "BBEdit" to count (every results browser whose name is "bbtex Test Results")'],
            text=True).strip()
    try:
        apply_results()
        assert count() == "1", "Test results browser was not created"
        log.write_text("")
        source.write_text(source.read_text().split("\n", 1)[1])
        (Path(directory) / "latexmkrc").unlink()
        apply_results()
        assert count() == "0", "Empty results did not clear the old browser"
    finally:
        subprocess.run(["osascript", "-e",
            '''tell application "BBEdit"
                repeat with w in (get every results browser)
                    if name of w is "bbtex Test Results" then close w
                end repeat
            end tell'''],
            check=True)
    print("Native BBEdit results creation and cleanup passed")
