#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Inspect isolated partial/conflicting installations without writing into them."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BINARY = Path(os.environ.get('BBTEX_TEST_BINARY', ROOT / '_build/default/bin/main.exe')).resolve()
with tempfile.TemporaryDirectory(prefix='bbtex doctor ') as tmp:
    home = Path(tmp)
    tools = home / 'tools'
    tools.mkdir()
    # A located executable must never be invoked by inspection.
    fake = tools / 'pdflatex'
    fake.write_text('#!/bin/sh\nexit 99\n')
    fake.chmod(0o700)
    base = home / 'Library/Application Support/BBEdit'
    scripts = base / 'Scripts'
    packaged = base / 'Packages/bbtex.bbpackage/Contents/Scripts'
    scripts.mkdir(parents=True)
    packaged.mkdir(parents=True)
    for folder in [scripts, packaged]:
        (folder / 'LaTeX — Project Outline.sh').write_text('fixture')
    (scripts / 'LaTeX — Doctor.sh').symlink_to(home / 'missing')
    hook = base / 'Attachment Scripts/Document.documentDidSave.scpt'
    hook.parent.mkdir()
    hook.write_bytes(b'unknown hook')
    def snapshot():
        return {str(p.relative_to(home)): ('link', os.readlink(p)) if p.is_symlink()
                else ('dir',) if p.is_dir() else ('file', p.read_bytes())
                for p in home.rglob('*')}
    before = snapshot()
    result = subprocess.run([BINARY, 'doctor'], capture_output=True, text=True, check=True,
                            env=dict(os.environ, HOME=tmp, PATH=str(tools),
                                     BBTEX_STATE_DIR=str(home / 'absent/state')))
    for expected in ['[OK] pdflatex', '[WARN] latexmk', '[OPTIONAL] biber',
                     '[WARN] Duplicate command', '[WARN] Broken command link',
                     '[UNVERIFIED] Save attachment', '[UNVERIFIED] Versions']:
        assert expected in result.stdout, result.stdout
    assert tmp not in result.stdout
    assert snapshot() == before, 'Doctor changed the inspected installation'
print('Doctor partial/conflicting installation and read-only checks passed')
