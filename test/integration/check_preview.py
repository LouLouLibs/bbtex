#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Compile real cropped previews, checking isolation and failure behavior."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "_build/default/bin/main.exe"
with tempfile.TemporaryDirectory(prefix="bbtex-preview-") as directory:
    folder = Path(directory).resolve()
    project = folder / "paper with spaces"
    project.mkdir()
    main = project / "main.tex"
    chapter = project / "chapter.tex"
    chapter.write_text("% !TEX root = main.tex\n")
    (project / "macros.tex").write_text("\\newcommand{\\myformula}{\\frac{1}{2}}\n")
    (project / "main.pdf").write_bytes(b"existing document PDF")
    env = {**os.environ, "BBTEX_STATE_DIR": str(folder / "state")}
    def run(selection):
        result = subprocess.run([str(BINARY), "preview", str(chapter)], input=selection,
                                text=True, capture_output=True, env=env, timeout=90)
        fields = dict(line.split(": ", 1) for line in result.stdout.splitlines() if ": " in line)
        return result, fields
    for engine in ("pdflatex", "xelatex", "lualatex", "tectonic"):
        main.write_text(f"%!TEX program = {engine}\n" +
                       "\\documentclass{article}\n\\usepackage{amsmath}\n"
                       "\\input{macros.tex}\n% \\begin{document} in a comment\n"
                       "\\begin{document}\nFull body must not be compiled.\n\\end{document}\n")
        before = {p.name: p.read_bytes() for p in project.iterdir()}
        result, fields = run(r"\myformula + x^2")
        assert result.returncode == 0, (result.stdout, result.stderr, Path(fields["log"]).read_text() if "log" in fields else "")
        pdf = Path(fields["pdf"])
        assert Path(fields["png"]).read_bytes().startswith(b"\x89PNG")
        if engine != "tectonic":
            tracked = (Path(fields["png"]).parent / "tracked.inputs").read_text().split("\0")
            assert str(project / "macros.tex") in tracked
            assert str(main) in tracked
        print(f"{engine} render {fields['render_duration']}s; PNG {fields['conversion_duration']}s")
        assert pdf.read_bytes().startswith(b"%PDF")
        info = subprocess.check_output(["pdfinfo", str(pdf)], text=True)
        page = next(line for line in info.splitlines() if line.startswith("Page size:"))
        dimensions = page.split(":", 1)[1].split()
        # Display math retains the document's text width, but crops page height.
        assert float(dimensions[0]) < 400 and float(dimensions[2]) < 150, page
        assert {p.name: p.read_bytes() for p in project.iterdir()} == before
        result, cached = run(r"\myformula + x^2")
        assert result.returncode == 0, result.stdout
        if engine != "tectonic":
            assert cached["cache"] == "hit", cached
            print(f"{engine} cached render {cached['render_duration']}s")
            old_png = Path(cached["png"]).read_bytes()
            macros = project / "macros.tex"
            macros.write_text("\\newcommand{\\myformula}{\\frac{999}{777}}\n")
            result, changed = run(r"\myformula + x^2")
            assert result.returncode == 0 and changed["cache"] == "miss", changed
            assert Path(changed["png"]).read_bytes() != old_png
            macros.write_bytes(before["macros.tex"])
        result, fields = run(r"\begin{align*}a&=b+c\\d&=e\end{align*}")
        assert result.returncode == 0, result.stdout
        print(f"{engine}: cropped raw math and align preview; root macros loaded; project untouched")
    result, fields = run(r"\undefinedPreviewMacro")
    assert result.returncode == 1 and not Path(fields["pdf"]).exists(), result.stdout
    assert "Undefined control sequence" in Path(fields["log"]).read_text().replace("\n", ""), Path(fields["log"]).read_text()
    result, fields = run("  ")
    assert result.returncode == 2 and "Select an equation" in fields["message"]
    print("Failures: readable preview log, no stale PDF, empty selection rejected")
