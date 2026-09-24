#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Native per-project outline launcher lifecycle, using disposable documents."""
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / '_build/default/bin/main.exe'

def apple(body, *args):
    return subprocess.check_output(['osascript', '-', *map(str, args)],
                                   input=body, text=True, timeout=15).strip()

def close(page):
    apple('on run argv\ntell application "BBEdit"\nrepeat with w in (get web_preview_windows)\nif name of w is item 1 of argv then close w\nend repeat\nend tell\nend run', 'Preview: ' + page.name)

def wait_for(predicate):
    deadline = time.monotonic() + 15
    while not predicate():
        assert time.monotonic() < deadline, 'Timed out waiting for outline lifecycle'
        time.sleep(.1)

with tempfile.TemporaryDirectory(prefix='bbtex-outline-launcher-') as tmp:
    folder = Path(tmp)
    env = {**os.environ, 'TMPDIR': tmp}
    pages = []
    def launch(source):
        result = subprocess.run([str(BINARY), 'outline-window', str(source)],
                                env=env, capture_output=True, text=True, timeout=25, check=True)
        session = Path(result.stdout.split('session: ', 1)[1].strip())
        page, = session.glob('bbtex-outline-*.html')
        if page not in pages:
            pages.append(page)
        return session, page
    try:
        first = folder / 'first.tex'
        second = folder / 'second.tex'
        child = folder / 'child.tex'
        for source in (first, second):
            source.write_text('\\documentclass{article}\n\\begin{document}\n\\section{Test}\n\\end{document}\n')
        child.write_text('%!TEX root = first.tex\n')
        session, page = launch(first)
        wait_for(lambda: 'page-ready: true' in (session / 'session.log').read_text())
        original = page.read_text()
        assert launch(child) == (session, page), 'Included document did not reuse root project'
        assert page.read_text() == original, 'Reuse rewrote the page and lost UI state'
        count = apple('on run argv\ntell application "BBEdit" to return count of (web_preview_windows whose name is item 1 of argv)\nend run', 'Preview: ' + page.name)
        assert count == '1', 'Duplicate preview on reuse'
        other_session, other = launch(second)
        assert other_session != session, 'Different projects shared a session'
        close(page)
        wait_for(lambda: not page.exists())
        assert other.exists(), 'Closing one project stopped another'
        _, reopened = launch(first)
        assert reopened == page and page.exists(), 'Closed project did not reopen'
        print('Outline launcher: root reuse, two independent projects, close and reopen passed')
    finally:
        for page in pages:
            close(page)
        for page in pages:
            wait_for(lambda: not page.exists())
