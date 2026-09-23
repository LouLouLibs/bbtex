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
import time

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
    command("open", """
printf 'open\\n' >> "$BBTEX_TEST_TRACE"
printf '%s\\n' "$@" >> "$BBTEX_TEST_TRACE"
# Without Skim installed, "open -a Skim" fails.
[[ "${BBTEX_TEST_NO_SKIM:-0}" == 0 || " $* " != *" -a Skim "* ]]
""")
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

    code, output = run(BBTEX_TEST_NO_SKIM="1", BBTEX_SKIM_DISPLAYLINE=str(root / "no-skim/displayline"))
    assert code == 0, output
    assert "open\n-g\n-a\nSkim\n" in output, output
    assert output.count("open\n-g\n") == 2, "falls back to the default PDF viewer"
    assert "LaTeX: Compiled" in output, "notification still shown without Skim"
    print("Without Skim: PDF opens in the default viewer and the notification still appears")

    trace.write_text("")
    ready = root / "preview-ready"
    gate = root / "preview-gate"
    gate.touch()
    preview = subprocess.Popen(["/usr/bin/perl", str(ROOT / "scripts/with-preview-lock.pl"),
        str(root / "state/preview-on-save.lock"), "/bin/bash", "-c",
        'touch "$1"; while [[ -f "$2" ]]; do sleep 0.02; done', "bash", str(ready), str(gate)])
    build = None
    try:
        deadline = time.monotonic() + 5
        while not ready.exists():
            assert time.monotonic() < deadline
            time.sleep(0.02)
        build = subprocess.Popen(["/bin/bash", str(WRAPPER)], env=env)
        deadline = time.monotonic() + 5
        while "LaTeX: Building" not in trace.read_text():
            assert time.monotonic() < deadline
            time.sleep(0.02)
        time.sleep(0.1)
        assert build.poll() is None and "compiler\n" not in trace.read_text()
    finally:
        gate.unlink(missing_ok=True)
        preview.wait(timeout=5)
        if build is not None:
            assert build.wait(timeout=10) == 0
    assert "compiler\n" in trace.read_text()
    print("Full build waits for active save preview before starting compiler")

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
