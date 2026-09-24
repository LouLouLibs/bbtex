#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Disposable native outline window/navigation proof; run explicitly on macOS."""
import os
import re
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / '_build/default/bin/main.exe'

def apple(body, *args):
    return subprocess.check_output(['osascript', '-', *map(str, args)], input=body,
                                   text=True, timeout=15).strip()

with tempfile.TemporaryDirectory(prefix='bbtex-outline-window-') as tmp:
    folder = Path(tmp)
    source = folder / 'paper é.tex'
    source.write_text('\\documentclass{article}\n\\begin{document}\n\\section{First}\nBody.\n\\section{Second}\n\\end{document}\n')
    session = folder / 'session'
    session.mkdir(mode=0o700)
    process = None
    title = ''
    try:
        apple('on run argv\ntell application "BBEdit" to open (POSIX file (item 1 of argv))\nend run', source)
        process = subprocess.Popen([str(BINARY), 'outline-window-prototype', str(source), str(session)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        page = Path(process.stdout.readline().removeprefix('page: ').strip())
        endpoint = process.stdout.readline().removeprefix('endpoint: ').strip()
        assert page.is_file() and endpoint.startswith('http://127.0.0.1:'), (page, endpoint)
        title = 'Preview: ' + page.name
        def window_count():
            return apple('on run argv\ntell application "BBEdit" to return count of (web_preview_windows whose name is item 1 of argv)\nend run', title)
        deadline = time.monotonic() + 10
        while window_count() != '1':
            assert process.poll() is None
            assert time.monotonic() < deadline, 'Outline window did not appear'
            time.sleep(.1)
        # Reopening should reuse the page/window and leave ownership with the first worker.
        reused = subprocess.run([str(BINARY), 'outline-window-prototype', str(source), str(session)],
                                text=True, capture_output=True, timeout=15)
        assert reused.returncode == 0 and 'status: reused' in reused.stdout, reused
        assert window_count() == '1', 'Duplicate outline windows'
        def request(suffix, method='POST', origin='null'):
            req = urllib.request.Request(endpoint + suffix, method=method,
                                         headers={'Origin': origin}, data=b'' if method == 'POST' else None)
            with urllib.request.urlopen(req, timeout=15) as result:
                assert result.headers.get('Access-Control-Allow-Origin') == origin
                return result.read().decode()
        for suffix, method, origin in [('/jump/0/0', 'GET', 'null'), ('/jump/0/0', 'POST', 'https://example.org'),
                                        ('/jump/0/999', 'POST', 'null')]:
            try:
                request(suffix, method, origin)
                raise AssertionError('Unexpected authorization')
            except urllib.error.HTTPError as error:
                assert error.code == 403
        assert 'Opened saved source' in request('/jump/0/1', origin='x-bbedit-preview://')
        line = apple('tell application "BBEdit" to return startLine of selection')
        assert line == '5', line
        apple('on run argv\ntell application "BBEdit"\nopen (POSIX file (item 1 of argv))\nif (file of front text document as alias) is not (POSIX file (item 1 of argv) as alias) then error "Wrong disposable document"\nset contents of front text document to "Unsaved changes"\nend tell\nend run', source)
        assert 'unsaved edits' in request('/jump/0/0')
        apple('on run argv\ntell application "BBEdit"\nset d to open (POSIX file (item 1 of argv))\nclose d saving no\nend tell\nend run', source)
        source.write_text(source.read_text() + '% changed on disk\n')
        assert 'Source changed' in request('/jump/0/0')
        # Refresh shifts entry numbers and locations; old buttons must never be
        # interpreted against the newly built snapshot.
        source.write_text('\\documentclass{article}\n\\begin{document}\n\\section{New}\n\\section{First}\nBody.\n\\section{Second}\n\\end{document}\n')
        refreshed = request('/refresh', origin='x-bbedit-preview://')
        revision = int(re.search(r'data-revision="(\d+)"', refreshed).group(1))
        assert revision >= 1 and 'New' in refreshed
        try:
            request('/jump/0/1')
            raise AssertionError('Old snapshot navigation was accepted')
        except urllib.error.HTTPError as error:
            assert error.code == 403
        assert 'Opened saved source' in request(f'/jump/{revision}/2')
        assert apple('tell application "BBEdit" to return startLine of selection') == '6'
        # A disk save must reach the live preview without an explicit refresh.
        # Closing this disposable source also avoids an external-change dialog.
        apple('on run argv\ntell application "BBEdit"\nset d to open POSIX file (item 1 of argv)\nclose d saving no\nend tell\nend run', source)
        source.write_text(source.read_text().replace('\\section{Second}', '\\section{Automatically updated}'))
        deadline = time.monotonic() + 12
        while int(request('/ping', method='GET').split()[-1]) <= revision:
            assert time.monotonic() < deadline, 'Saved change was not detected automatically'
            time.sleep(.2)
        # A live HTML page must keep the server alive without test-generated pings.
        time.sleep(12)
        assert process.poll() is None, 'WebKit did not maintain the heartbeat'
        apple('on run argv\ntell application "BBEdit"\nrepeat with w in (get web_preview_windows)\nif name of w is item 1 of argv then close w\nend repeat\nend tell\nend run', title)
        output, errors = process.communicate(timeout=15)
        assert 'page-connected: true' in output, 'WebKit never reached the local endpoint'
        assert 'page-ready: true' in output, 'BBEdit could not read the POST response (CORS handshake failed)'
        assert any(int(n) > revision for n in re.findall(r'snapshot-applied: (\d+)', output)), 'Preview did not apply the automatic update'
        assert process.returncode == 0 and not page.exists(), 'Session did not stop after window close'
        print('Outline window: reuse, native validated jumps, dirty/stale rejection, heartbeat and close passed')
    finally:
        if process and process.poll() is None:
            process.terminate()
            process.communicate(timeout=15)
        apple('on run argv\ntell application "BBEdit"\nrepeat with w in (get web_preview_windows)\nif name of w is item 2 of argv then close w\nend repeat\ntry\nset d to open (POSIX file (item 1 of argv))\nclose d saving no\nend try\nend tell\nend run', source, title)
