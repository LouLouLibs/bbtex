#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Native acceptance check for live selection preview (issue #2).

Opens a disposable document and a preview window in BBEdit: run it once, and
ask before repeating it. Build first with `opam exec -- dune build`.

Every step waits on published state (`state-v2`), never on fixed sleeps.
Budgets are measured from the moment the selection is in place to the
published `current` state, so they include the 0.35 s debounce and the 0.15 s
poll: cold <= 3.0 s, warm <= 1.0 s.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
BBTEX = ROOT / "_build/default/bin/main.exe"
TOGGLE = ROOT / "scripts/bbtex-live-selection.sh"
COLD_BUDGET = 3.0
WARM_BUDGET = 1.0
OSA_TIMEOUT = 15.0
STATUS_TIMEOUT = 5.0
FINAL = ("current", "stale", "error", "busy")
FIELDS = ["generation", "revision", "status", "source", "line", "image",
          "image_line", "message", "log", "fingerprint", "mode"]

PREAMBLE = "\\documentclass{article}\n\\usepackage{amsmath}\n\\begin{document}\n"
BODY = ("Intro text.\n\\begin{align*}\na &= b \\\\\nc &= d\n\\end{align*}\n"
        "Mass is $m$.\n")
TEXT = PREAMBLE + BODY + "\\end{document}\n"


class Failure(Exception):
    pass


def check(condition: bool, message: str) -> None:
    if not condition:
        raise Failure(message)


def call(command: list[str], timeout: float, **options) -> subprocess.CompletedProcess:
    """subprocess.run with a deadline. A hang (for example BBEdit not answering
    AppleScript) becomes a Failure, so it cannot outlast any wait_for deadline
    and still reaches cleanup."""
    try:
        return subprocess.run(command, capture_output=True, timeout=timeout, **options)
    except subprocess.TimeoutExpired:
        raise Failure(f"{Path(command[0]).name} did not finish within {timeout:.0f}s") from None


def osa(script: str, *args: str) -> str:
    result = call(["osascript", "-", *args], OSA_TIMEOUT, input=script, text=True)
    if result.returncode != 0:
        raise Failure(f"AppleScript failed: {result.stderr.strip()}")
    return result.stdout.strip()


def line_of(index: int) -> int:
    return TEXT[:index].count("\n") + 1


class Check:
    def __init__(self, folder: Path) -> None:
        self.folder = folder
        self.state_dir = folder / "state"
        self.env = {**os.environ, "BBTEX_STATE_DIR": str(self.state_dir)}
        self.source = folder / "main.tex"
        # Snippet_page.page_path hashes the realpath of the snippet-window dir.
        self.window_dir = self.state_dir / "snippet-window"
        self.page_name = ("bbtex-snippet-"
                          + hashlib.md5(str(self.window_dir).encode()).hexdigest()[:8]
                          + ".html")
        self.preview_name = "Preview: " + self.page_name
        self.window_id = ""
        self.error_log = ""  # compiler log of the last render that reported error

    # -- state -------------------------------------------------------------

    def state(self) -> dict:
        try:
            raw = (self.window_dir / "state-v2").read_bytes().decode()
        except FileNotFoundError:
            return {}
        values = raw.split("\0")
        if len(values) != len(FIELDS):
            return {}
        s = dict(zip(FIELDS, values))
        s["revision"] = int(s["revision"])
        s["line"] = int(s["line"])
        s["image_line"] = int(s["image_line"])
        return s

    def revision(self) -> int:
        return self.state().get("revision", 0)

    def watcher_running(self) -> bool:
        code = call([str(BBTEX), "live-selection", "status"], STATUS_TIMEOUT,
                   env=self.env).returncode
        check(code in (0, 1), f"bbtex live-selection status exited {code}")
        return code == 0

    def wait_for(self, predicate, what: str, timeout: float) -> float:
        start = time.monotonic()
        while True:
            if predicate():
                return time.monotonic() - start
            if time.monotonic() - start >= timeout:
                raise Failure(f"timed out after {timeout:.1f}s waiting for {what}; "
                              f"state: {self.describe()}")
            time.sleep(0.02)

    def settled(self, after: int, line: int, what: str, timeout: float = 10.0,
                started: float | None = None) -> tuple[float, dict]:
        """Wait for a final status at LINE newer than revision AFTER."""
        start = time.monotonic() if started is None else started
        found = {}

        def ready() -> bool:
            s = self.state()
            if s and s["revision"] > after and s["line"] == line and s["status"] in FINAL:
                found.update(s)
                if s["status"] == "error":
                    self.error_log = s["log"]
                return True
            return False
        self.wait_for(ready, what, timeout - (time.monotonic() - start))
        return time.monotonic() - start, found

    def describe(self) -> str:
        s = self.state()
        if not s:
            return "(no state-v2)"
        return (f"revision={s['revision']} status={s['status']} line={s['line']} "
                f"image={'yes' if s['image'] else 'no'} message={s['message']!r}")

    # -- BBEdit ------------------------------------------------------------

    def select(self, *ranges: tuple[int, int]) -> None:
        """Bring BBEdit and the test window to the front, then make each
        selection in turn within one AppleScript run (so several are rapid)."""
        selects = "\n".join(f"select characters {offset} thru {offset + length - 1} of d"
                            for offset, length in ranges)
        osa(f'''on run argv
            tell application "BBEdit"
                activate
                set w to text window id ((item 1 of argv) as integer)
                set d to document of w
                set index of window id ((item 1 of argv) as integer) to 1
                {selects}
            end tell
        end run''', self.window_id)

    def preview_windows(self) -> int:
        return int(osa('''on run argv
            set n to 0
            tell application "BBEdit"
                repeat with p in (get web_preview_windows)
                    if name of p is item 1 of argv then set n to n + 1
                end repeat
            end tell
            return n
        end run''', self.preview_name))

    def close_preview(self) -> None:
        """Close only this check's preview window, by its exact name."""
        osa('''on run argv
            tell application "BBEdit"
                repeat with p in (get web_preview_windows)
                    if name of p is item 1 of argv then close p
                end repeat
            end tell
        end run''', self.preview_name)

    # -- scenarios ---------------------------------------------------------

    def preflight(self) -> None:
        check(BBTEX.exists(), f"{BBTEX} is missing: run `opam exec -- dune build` first")
        leftovers = call(["pgrep", "-fl", "live-selection-poll"], STATUS_TIMEOUT,
                        text=True).stdout.strip()
        check(not leftovers, "a live selection poller is already running; turn live "
              f"selection preview off before this check:\n{leftovers}")
        # The poller treats any snippet preview as open, so another one would
        # keep this watcher alive after its own window closes.
        others = osa('''tell application "BBEdit"
            set n to 0
            repeat with p in (get web_preview_windows)
                if name of p starts with "Preview: bbtex-snippet-" then set n to n + 1
            end repeat
            return n
        end tell''')
        check(others == "0", "close the open LaTeX Snippet preview window before this check")

    def start(self) -> None:
        self.source.write_text(TEXT)
        self.window_id = osa('''on run argv
            tell application "BBEdit"
                activate
                set d to open (POSIX file (item 1 of argv))
                select insertion point before character 1 of d
                set index of window of d to 1
                return ID of front window as text
            end tell
        end run''', str(self.source))
        result = call([str(TOGGLE)], 60, env={**self.env, "BB_DOC_PATH": str(self.source)},
                     text=True)
        check(result.returncode == 0,
              f"toggle script failed ({result.returncode}): {result.stderr.strip()}")
        check(self.watcher_running(), "watcher is not running after the toggle script")
        self.wait_for(lambda: self.preview_windows() == 1,
                      f"the preview window {self.preview_name!r}", timeout=5)

    def run(self) -> str:
        self.preflight()
        self.start()
        align = TEXT.index("a &= b")
        align_range = (align + 1, len("a &= b \\\\\nc &= d"))
        align_line = line_of(align)

        # 1. Math inside align*: current within the cold budget.
        before = self.revision()
        self.select(align_range)
        cold, s = self.settled(before, align_line, "cold render of the align* selection")
        check(s["status"] == "current", f"cold render not current: {self.describe()}")
        check(s["source"] == str(self.source), f"wrong source published: {s['source']!r}")
        check(s["image"].startswith("data:image/png;base64,"), "cold render published no image")
        check(cold <= COLD_BUDGET, f"cold render took {cold:.2f}s (budget {COLD_BUDGET:.1f}s)")
        image = s["image"]

        # 2. Invalid fragment: stale with a message, previous image kept.
        #    "\begin{a" has an unclosed brace; it also leaves the render cache alone.
        begin = TEXT.index("\\begin{align*}")
        before = self.revision()
        self.select((begin + 1, 8))
        _, s = self.settled(before, line_of(begin), "the invalid-selection message")
        check(s["status"] == "stale", f"invalid selection not stale: {self.describe()}")
        check("unbalanced braces" in s["message"], f"unexpected message: {s['message']!r}")
        check(s["image"] == image, "invalid selection dropped the previous image")
        check(s["image_line"] == align_line, f"image line changed to {s['image_line']}")

        # 3. Reselect the align* range: a cache hit within the warm budget.
        #    (Reselecting the last rendered range with nothing in between would
        #    not render at all; the invalid selection above sits in between, and
        #    any other selection or cursor move would do too.)
        before = self.revision()
        self.select(align_range)
        warm, s = self.settled(before, align_line, "warm render of the align* selection")
        check(s["status"] == "current", f"warm render not current: {self.describe()}")
        check(warm <= WARM_BUDGET, f"warm render took {warm:.2f}s (budget {WARM_BUDGET:.1f}s)")

        # 4. Rapid A -> B -> C: only C publishes.
        prose = TEXT.index("Mass is")
        prose_line = line_of(prose)
        before = self.revision()
        self.select((align + 1, 7), (1, 7), (prose + 1, 7))
        seen = set()

        def on_c() -> bool:
            s = self.state()
            if s and s["revision"] > before:
                seen.add(s["line"])
            return bool(s) and s["revision"] > before and s["line"] == prose_line \
                and s["status"] in ("current", "stale")
        self.wait_for(on_c, "the final render of selection C", timeout=10)
        s = self.state()
        check(s["status"] == "current", f"selection C not current: {self.describe()}")
        hold = time.monotonic()
        while time.monotonic() - hold < 1.0:
            s = self.state()
            seen.add(s.get("line"))
            check(s.get("line") == prose_line, f"selection moved off C after it published: {self.describe()}")
            time.sleep(0.02)
        check(seen == {prose_line}, f"superseded selections published lines {sorted(seen - {prose_line})}")

        # 5. Source focus and selection preserved.
        front, selected = osa('''on run argv
            tell application "BBEdit"
                set w to text window id ((item 1 of argv) as integer)
                return (ID of front window as text) & linefeed & (contents of selection of w as text)
            end tell
        end run''', self.window_id).split("\n", 1)
        check(front == self.window_id, "the preview took focus from the source window")
        check(selected == "Mass is", f"source selection changed to {selected!r}")

        # 6. Closing the preview stops the watcher and its poller.
        self.close_preview()
        self.wait_for(lambda: not self.watcher_running(), "the watcher to exit after the preview closed",
                      timeout=5)
        self.wait_for(lambda: call(["pgrep", "-f", "live-selection-poll"],
                                  STATUS_TIMEOUT).returncode == 1,
                      "the poller to exit", timeout=1)
        return f"live selection: cold {cold:.2f}s, warm {warm:.2f}s"

    def diagnostics(self) -> None:
        print(f"state: {self.describe()}", file=sys.stderr)
        try:
            lines = (self.state_dir / "live-selection.log").read_text(errors="replace").splitlines()
            print("live-selection.log (last 30 lines):", *lines[-30:], sep="\n  ", file=sys.stderr)
        except FileNotFoundError:
            print("live-selection.log: missing", file=sys.stderr)
        # The compiler log lives in the temp state dir, which cleanup deletes.
        s = self.state()
        log = s["log"] if s and s["status"] == "error" and s["log"] else self.error_log
        if log:
            try:
                lines = Path(log).read_text(errors="replace").splitlines()
            except OSError as error:
                print(f"compiler log {log}: {error}", file=sys.stderr)
            else:
                errors = [line for line in lines if line.startswith("!")]
                shown = errors[-20:] if errors else lines[-20:]
                title = "errors" if errors else "last 20 lines"
                print(f"compiler log {log} ({title}):", *shown, sep="\n  ", file=sys.stderr)

    def cleanup(self) -> list[str]:
        problems = []

        def attempt(what, action):
            try:
                action()
            except Exception as error:  # keep cleaning up after any one failure
                problems.append(f"{what}: {error}")
        attempt("stop watcher", lambda: call(
            [str(BBTEX), "live-selection", "stop"], 10, env=self.env))
        attempt("wait for watcher", lambda: self.wait_for(
            lambda: not self.watcher_running(), "the watcher to stop", timeout=5))
        attempt("close preview", self.close_preview)
        attempt("close document", lambda: osa('''on run argv
            tell application "BBEdit"
                repeat with d in (get text documents)
                    try
                        set f to get file of d
                        if POSIX path of f is item 1 of argv then close d saving no
                    end try
                end repeat
            end tell
        end run''', str(self.source)))
        shutil.rmtree(self.folder, ignore_errors=True)
        return problems


def main() -> int:
    folder = Path(tempfile.mkdtemp(prefix="bbtex-live-selection-")).resolve()
    test = Check(folder)
    summary = None
    try:
        summary = test.run()
    except Exception as error:
        print(f"live selection check FAILED: {error}", file=sys.stderr)
        test.diagnostics()
    finally:
        problems = test.cleanup()
    for problem in problems:
        print(f"cleanup problem: {problem}", file=sys.stderr)
    if summary is not None:
        print(summary)
    return 0 if summary is not None and not problems else 1


if __name__ == "__main__":
    sys.exit(main())
