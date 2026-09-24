#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Measure large-outline startup/readback and automatic refresh in real BBEdit."""
from pathlib import Path
import os
import select
import subprocess
import tempfile
import time

BINARY = Path(__file__).resolve().parents[2] / '_build/default/bin/main.exe'
def apple(script, *args):
    return subprocess.check_output(['osascript', '-', *map(str, args)], input=script,
                                   text=True, timeout=15).strip()

with tempfile.TemporaryDirectory(prefix='bbtex-outline-large-') as tmp:
    folder = Path(tmp)
    inputs = []
    for i in range(120):
        name = f'chapter-{i}.tex'
        (folder / name).write_text(''.join(f'\\section{{Heading {i}-{j}}}\n\\label{{sec:{i}:{j}}}\nBody.\n' for j in range(40)))
        inputs.append(f'\\input{{{name}}}')
    source = folder / 'main.tex'
    source.write_text('\\documentclass{article}\n\\begin{document}\n' + '\n'.join(inputs) + '\n\\end{document}\n')
    session = folder / 'session'
    session.mkdir(mode=0o700)
    other = folder / 'editing.tex'
    other.write_text('A disposable document to keep focused.\n')
    started = time.monotonic()
    process = subprocess.Popen([str(BINARY), 'outline-window-prototype', str(source), str(session)],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    output = bytearray()
    def wait_for(marker):
        deadline = time.monotonic() + 30
        while marker not in output:
            assert process.poll() is None, 'Outline worker stopped'
            assert time.monotonic() < deadline, f'Timed out: {marker!r}'
            if select.select([process.stdout], [], [], .2)[0]:
                output.extend(os.read(process.stdout.fileno(), 4096))
    try:
        wait_for(b'page-ready: true')
        print(f'BBEdit: 121 files / 9600 entries, startup and script/readback {time.monotonic()-started:.3f}s')
        focused = apple('on run argv\ntell application "BBEdit"\nopen POSIX file (item 1 of argv)\nreturn ID of front window\nend tell\nend run', other)
        started = time.monotonic()
        source.write_text('% saved change\n' + source.read_text())
        wait_for(b'snapshot-applied: 1')
        print(f'BBEdit: automatic refresh applied in {time.monotonic()-started:.3f}s (includes 2s polling interval)')
        assert apple('tell application "BBEdit" to return ID of front window') == focused, 'Automatic refresh changed the front window'
        print('BBEdit: automatic refresh left the editing window in front')
    finally:
        apple('on run argv\ntell application "BBEdit"\nset d to open POSIX file (item 1 of argv)\nclose d saving no\nend tell\nend run', other)
        for page in session.glob('bbtex-outline-*.html'):
            subprocess.run(['osascript', '-', 'Preview: ' + page.name], input='on run argv\ntell application "BBEdit"\nrepeat with w in (get web_preview_windows)\nif name of w is item 1 of argv then close w\nend repeat\nend tell\nend run', text=True, check=True, timeout=15)
        try:
            _, errors = process.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            process.terminate()
            _, errors = process.communicate(timeout=15)
            raise
        assert process.returncode == 0, errors.decode()
