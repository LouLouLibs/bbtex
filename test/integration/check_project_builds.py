#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Project resolution, output paths, profiles, locking, cancellation, and cleanup."""
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "_build/default/bin/main.exe"
with tempfile.TemporaryDirectory(prefix="bbtex-project-") as directory:
    root = Path(directory).resolve()
    commands = root / "bin"
    commands.mkdir()
    main = root / "main.tex"
    middle = root / "middle.tex"
    chapter = root / "chapter.tex"
    main.write_text("%!TEX root = main.tex\n%!TEX program = lualatex\n")
    middle.write_text("%!TEX root = main.tex\n")
    chapter.write_text("%!TEX root = middle.tex\n")
    env = {**os.environ, "BBTEX_STATE_DIR": str(root / "state"),
           "PATH": str(commands) + ":/usr/bin:/bin", "BBTEX_TEST_ROOT": str(root)}
    def run(*args, expected=0, **extra):
        p = subprocess.run([str(BINARY), *map(str, args)], env={**env, **extra},
                           text=True, capture_output=True, timeout=10)
        assert p.returncode == expected, (args, p.returncode, p.stdout, p.stderr)
        output = dict(line.split(": ", 1) for line in p.stdout.splitlines() if ": " in line)
        if "applescript_file" in output:
            Path(output["applescript_file"]).unlink()
        return output
    result = run("paths", chapter)
    assert result["root"] == str(main) and result["engine"] == "lualatex"
    middle.write_text("%!TEX root = chapter.tex\n")
    assert "Cyclic" in run("paths", chapter, expected=2)["message"]
    middle.write_text("%!TEX root = absent.tex\n")
    assert "not found" in run("paths", chapter, expected=2)["message"]
    middle.write_text("%!TEX root = main.tex\n")
    print("Root chains, self-root, missing roots, and cycles verified")

    settings = root / ".bbtex"
    settings.write_text("root = main.tex\noutput_directory = build output\n\n[profile Draft]\nengine = xelatex\noptions = -halt-on-error\n\n[profile Tectonic]\nengine = tectonic\noptions = --reruns=1\n")
    expected_pdf = root / "build output/main.pdf"
    result = run("paths", "--profile", "Draft", chapter)
    assert result["engine"] == "xelatex" and result["pdf"] == str(expected_pdf)
    assert run("paths", "--profile", "Draft", "--engine", "pdflatex", chapter)["engine"] == "pdflatex"
    assert "Unknown build profile" in run("paths", "--profile", "Nope", chapter, expected=2)["message"]
    print("Named profiles, explicit engine override, shared output paths verified")

    fake = '''#!/bin/bash
set -eu
printf '%s\\n' "$0" "$@" > "$BBTEX_TEST_ROOT/args"
if [[ "${BBTEX_TEST_SLOW:-0}" == 1 ]]; then
    [[ "${BBTEX_TEST_STUBBORN:-0}" == 0 ]] || trap '' TERM
    sleep 30 &
    printf '%s\\n' "$!" > "$BBTEX_TEST_ROOT/child.pid"
    wait
fi
out=""; next_out=0; clean=""
for arg in "$@"; do
    if [[ "$next_out" == 1 ]]; then out="$arg"; next_out=0; fi
    case "$arg" in
        -outdir=*) out="${arg#-outdir=}" ;;
        --outdir) next_out=1 ;;
        -c|-C) clean="$arg" ;;
    esac
    file="$arg"
done
base="$out/$(basename "${file%.tex}")"
if [[ -n "$clean" ]]; then
    rm -f "$base.log" "$base.aux"
    [[ "$clean" != "-C" ]] || rm -f "$base.pdf"
else
    mkdir -p "$out"
    touch "$base.pdf" "$base.log" "$base.aux" "$base.synctex.gz"
fi
'''
    for engine in ("latexmk", "tectonic"):
        file = commands / engine
        file.write_text(fake)
        file.chmod(0o755)
    result = run("compile", "--profile", "Draft", chapter)
    assert result["status"] == "success" and expected_pdf.is_file()
    args = (root / "args").read_text()
    assert "-pdfxelatex" in args and "-halt-on-error" in args
    assert "duration" in result and Path(result["build_log"]).exists()
    run("compile", "--profile", "Tectonic", chapter)
    assert "--outdir" in (root / "args").read_text()
    assert run("paths", chapter)["pdf"] == str(expected_pdf)
    run("clean", chapter)
    assert expected_pdf.is_file() and not expected_pdf.with_suffix(".aux").exists()
    run("clean-all", chapter)
    assert not expected_pdf.exists()
    print("Engine switching, per-project logs, and PDF-preserving/full cleanup verified")

    process = subprocess.Popen([str(BINARY), "compile", str(chapter)],
                               env={**env, "BBTEX_TEST_SLOW": "1"},
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    child = None
    try:
        deadline = time.monotonic() + 5
        while not (root / "child.pid").exists():
            assert time.monotonic() < deadline, "Compiler did not launch"
            time.sleep(.05)
        child = int((root / "child.pid").read_text())
        blocked = run("compile", main, expected=2)
        assert "already building" in blocked["message"], blocked
        assert "already building" in run("clean", main, expected=2)["message"]
        assert run("cancel", main)["summary"] == "Cancellation requested"
        output, error = process.communicate(timeout=5)
        assert process.returncode == 3 and "status: cancelled" in output, (output, error)
        deadline = time.monotonic() + 3
        while True:
            state = subprocess.run(["ps", "-o", "stat=", "-p", str(child)], capture_output=True, text=True)
            if state.returncode != 0 or not state.stdout.strip() or state.stdout.strip().startswith("Z"):
                break
            assert time.monotonic() < deadline, "Compiler child survived cancellation"
            time.sleep(.05)
        assert not list((root / "state").glob("*.active"))
        assert run("cancel", main)["summary"] == "No build is running for this project"
        run("compile", main)
        print("Overlapping builds/cleanup blocked; cancellation stopped compiler children; lock reusable")
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
        if child:
            try: os.kill(child, 15)
            except ProcessLookupError: pass

    (root / "child.pid").unlink()
    stubborn = subprocess.Popen([str(BINARY), "compile", str(main)],
        env={**env, "BBTEX_TEST_SLOW": "1", "BBTEX_TEST_STUBBORN": "1"},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        deadline = time.monotonic() + 5
        while not (root / "child.pid").exists():
            assert time.monotonic() < deadline
            time.sleep(.05)
        stubborn_child = int((root / "child.pid").read_text())
        run("cancel", chapter)
        output, error = stubborn.communicate(timeout=5)
        assert stubborn.returncode == 3, (output, error)
        state = subprocess.run(["ps", "-o", "stat=", "-p", str(stubborn_child)], capture_output=True, text=True)
        assert not state.stdout.strip() or state.stdout.strip().startswith("Z"), state.stdout
        print("Cancellation also stops a compiler and child that ignore SIGTERM")
    finally:
        if stubborn.poll() is None:
            stubborn.terminate()
            stubborn.wait(timeout=5)
