#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Exercise real bbtex/wrappers with fake compiler and desktop commands."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "_build/default/bin/main.exe"
WRAPPER = Path(os.environ.get("BBTEX_TEST_WRAPPER", ROOT / "scripts/bbtex-bbedit-compile.sh"))

with tempfile.TemporaryDirectory(prefix="bbtex-workflow-") as directory:
    root = Path(directory)
    commands = root / "bin"
    commands.mkdir()
    trace = root / "trace"
    fixture = root / "fixture.log"
    source = root / 'a "quoted" project.tex'
    source.write_text("\\documentclass{article}\n\\begin{document}\nx\n\\end{document}\n")
    def command(name, body):
        file = commands / name
        file.write_text("#!/bin/bash\nset -eu\n" + body)
        file.chmod(0o755)
        return file
    compiler = command("latexmk", """
printf 'compiler\\n' >> "$BBTEX_TEST_TRACE"
for arg in "$@"; do file="$arg"; done
base="${file%.tex}"
cp "$BBTEX_TEST_FIXTURE" "$base.log"
printf 'compiler output for test\\n' >&2
if [[ "${BBTEX_TEST_EXIT:-0}" == 0 ]]; then
    touch "$base.pdf"
    [[ "${BBTEX_TEST_SYNCTEX:-1}" == 0 ]] || touch "$base.synctex.gz"
fi
exit "${BBTEX_TEST_EXIT:-0}"
""")
    command("osascript", """
printf 'osascript\\n' >> "$BBTEX_TEST_TRACE"
if [[ "$1" == "-e" ]]; then
    [[ "${BBTEX_TEST_SAVE_FAIL:-0}" == 0 ]] || exit 1
    printf '%s\\n' "$2" >> "$BBTEX_TEST_TRACE"
elif [[ "$1" == "-" ]]; then
    printf '%s\\n' "$@" >> "$BBTEX_TEST_TRACE"
    script=$(cat)
    printf '%s\\n' "$script" >> "$BBTEX_TEST_TRACE"
    if [[ "$script" == *"choose from list"* ]]; then printf '%s\\n' "${BBTEX_TEST_CHOICE:-}"; fi
else
    cat "$1" >> "$BBTEX_TEST_TRACE"
fi
""")
    def desktop_command(name, label):
        return command(name, f"printf '{label}\\n' >> \"$BBTEX_TEST_TRACE\"\nprintf '%s\\n' \"$@\" >> \"$BBTEX_TEST_TRACE\"\n")
    desktop_command("open", "open")
    desktop_command("bbedit", "bbedit")
    skim = desktop_command("displayline", "sync")
    env = {**os.environ, "PATH": str(commands) + ":/usr/bin:/bin",
           "BB_DOC_PATH": str(source), "BB_DOC_SELSTART_LINE": "3",
           "BBTEX_STATE_DIR": str(root / "state"),
           "BBTEX_SKIM_DISPLAYLINE": str(skim),
           "BBTEX_TEST_TRACE": str(trace), "BBTEX_TEST_FIXTURE": str(fixture)}
    def run(mode=None, **settings):
        trace.write_text("")
        result = subprocess.run(["/bin/bash", str(WRAPPER)] +
                                ([mode] if mode else []),
                                env={**env, **settings}, capture_output=True, text=True)
        assert not result.stdout, result.stdout
        return result.returncode, trace.read_text()

    fixture.write_text("")
    code, output = run()
    assert code == 0 and "sync\n-r\n-g\n3\n" in output, output
    assert str(source) in output and "make new results browser" not in output
    assert "bbedit\n" not in output and "sound name" not in output
    print("Clean build: quiet, background sync, quoted paths preserved")

    source.with_suffix(".synctex.gz").unlink()
    code, output = run(BBTEX_TEST_SYNCTEX="0")
    assert code == 0 and "open\n-g\n-a\nSkim" in output and "sync\n" not in output
    print("Missing SyncTeX: background PDF fallback")

    fixture.write_text("(./" + source.name + "\nLaTeX Warning: Citation missing on input line 3.\n)\n")
    code, output = run()
    assert code == 0 and "make new results browser" not in output, output
    code, output = run("--show-results")
    assert code == 0 and "warning_kind" in output and "compiler\n" not in output, output
    assert "System Events" not in output
    print("Warnings: hidden automatically, available on demand")

    fixture.write_text("(./" + source.name + "\nLaTeX Warning: A warning on input line 3.\n! Undefined control sequence.\nl.3 \\oops\n)\n")
    code, output = run(BBTEX_TEST_EXIT="1")
    assert code == 0 and "error_kind" in output and "warning_kind" not in output, output
    assert "bbedit\n" not in output and "sync\n" not in output
    print("Errors: automatic browser, no log window or stale PDF")

    fixture.write_text("")
    code, output = run(BBTEX_TEST_EXIT="12")
    assert code == 0 and "Compilation failed (exit 12)" in output, output
    code, output = run("--open-log")
    build_logs = list((root / "state").glob("build-*.log"))
    assert code == 0 and len(build_logs) == 1 and str(build_logs[0]) in output, output
    assert "compiler\n" not in output
    print("Unparsed compiler failure: actionable diagnostic and compiler log")

    code, output = run(BBTEX_TEST_SAVE_FAIL="1")
    assert code == 1 and "compiler\n" not in output, output
    print("Failed save: compilation stopped")

    (root / ".bbtex").write_text("[profile Draft]\nengine = xelatex\n")
    code, output = run("--choose-engine", BBTEX_TEST_CHOICE="Profile: Draft")
    assert code == 0 and "xelatex" in output and "Profile: Draft" in output, output
    code, output = run("--choose-engine", BBTEX_TEST_CHOICE="")
    assert code == 0 and "compiler\n" not in output
    code, output = run("--cancel")
    assert code == 0 and "No build is running" in output and "compiler\n" not in output
    print("Profile picker, picker cancellation, and Cancel Build action verified")

    code, output = run("--choose-engine", BBTEX_TEST_CHOICE="Configure Document…")
    assert code == 0 and "compiler\n" not in output and "Apply Document Settings" in output, output
    print("Document configuration opens without compiling")

    compiler.unlink()
    code, output = run()
    assert code == 1 and "latexmk not found in PATH" in output, output
    assert "sync\n" not in output
    print("Missing compiler: actionable alert")

    state = root / "state"
    assert not list(state.glob("*.applescript"))
