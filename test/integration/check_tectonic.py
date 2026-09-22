#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Tectonic rendering/cache tier; Biber compatibility is tested separately."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--bundle', help='Explicit Tectonic bundle URL or local path')
parser.add_argument('--artifacts', type=Path, default=ROOT / 'dist/real-engines')
args = parser.parse_args()
args.artifacts.mkdir(parents=True, exist_ok=True)
run = Path(tempfile.mkdtemp(prefix='tectonic-', dir=args.artifacts.resolve()))
project = run / 'paper with spaces é'
shutil.copytree(ROOT / 'test/corpus', project)
binary = Path(os.environ.get('BBTEX_TEST_BINARY', ROOT / '_build/default/bin/main.exe')).resolve()
env = dict(os.environ, BBTEX_STATE_DIR=str(run / 'state'))
report = {'status': 'running', 'engine': 'tectonic', 'bundle': args.bundle or 'installed default',
          'versions': {}, 'cases': [], 'not_covered': ['Biber book', 'cancellation', '40-file project']}
started = time.monotonic()
print('Artifacts:', run, flush=True)


def command(argv, **kwargs):
    return subprocess.run(list(map(str, argv)), env=env, capture_output=True, text=True,
                          timeout=180, **kwargs)


def invoke(label, action, source, selection=None, expected=0):
    result = command([binary, action, source], input=selection)
    (run / (label + '.stdout')).write_text(result.stdout)
    (run / (label + '.stderr')).write_text(result.stderr)
    fields = dict(line.split(': ', 1) for line in result.stdout.splitlines() if ': ' in line)
    if 'applescript_file' in fields:
        script = Path(fields['applescript_file'])
        if script.exists():
            shutil.copy2(script, run / (label + '.applescript'))
            script.unlink()
    assert result.returncode == expected, (label, result.stdout, result.stderr)
    assert fields['engine'] == 'tectonic', fields
    return fields


def configure(case, offline=False):
    # Project.options accepts shell-style quoted arguments.
    import shlex
    options = ['--only-cached'] if offline else []
    if args.bundle:
        options += ['--bundle=' + args.bundle]
    (project / case / '.bbtex').write_text('engine = tectonic\noutput_directory = build output\n'
                                          + 'options = ' + shlex.join(options) + '\n')


def pdf_details(path):
    info = command(['pdfinfo', path])
    text = command(['pdftotext', '-layout', path, '-'])
    assert info.returncode == text.returncode == 0, (info.stderr, text.stderr)
    size = re.search(r'Page size:\s+([\d.]+) x ([\d.]+)', info.stdout)
    pages = re.search(r'Pages:\s+(\d+)', info.stdout)
    assert size and pages, info.stdout
    return int(pages[1]), float(size[1]), float(size[2]), ' '.join(text.stdout.split())


try:
    for tool in ['tectonic', 'pdfinfo', 'pdftotext', 'pdftoppm']:
        version = command([tool, '--version' if tool == 'tectonic' else '-v'])
        assert version.returncode == 0, version.stderr
        report['versions'][tool] = (version.stdout + version.stderr).splitlines()[:3]
    sources = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in project.rglob('*')
               if p.suffix in ['.tex', '.bib']}
    for case, marker, minimum, maximum in [('article', 'Corpus Bibliography Evidence', 1, 3),
                                          ('beamer', 'Literal text', 2, 2),
                                          ('unicode', 'naïve façade', 1, 1)]:
        for offline in [False, True]:
            configure(case, offline)
            label = case + ('-offline' if offline else '-online')
            result = invoke(label, 'compile', project / case / 'main.tex')
            pdf = Path(result['pdf'])
            assert pdf.samefile(project / case / 'build output/main.pdf')
            pages, width, height, text = pdf_details(pdf)
            assert minimum <= pages <= maximum and marker.casefold() in text.casefold(), text
            if case == 'beamer':
                assert abs(width / height - 16 / 9) < .02, (width, height)
            else:
                assert 550 < width < 650 and 750 < height < 900, (width, height)
            log = Path(result['log']).read_text(errors='replace')
            assert not re.search(r'(Citation|Reference) .*undefined|There were undefined', log), log[-3000:]
            if case == 'article':
                sync = gzip.open(pdf.with_suffix('.synctex.gz'), 'rt', errors='replace').read()
                assert 'sections/results.tex' in sync
            report['cases'].append(label)
            print('Passed:', label, flush=True)
    assert all(hashlib.sha256(p.read_bytes()).hexdigest() == value for p, value in sources.items())
    for p in project.rglob('*'):
        if p.suffix in ['.pdf', '.log', '.aux', '.bbl', '.toc']:
            assert 'build output' in p.parts, p
    entry = project / 'article/sections/results.tex'
    pdf = project / 'article/build output/main.pdf'
    original_pdf = pdf.read_bytes()
    # Warm online once to fetch preview-only packages; then force cached resources.
    configure('article')
    first = invoke('preview-online', 'preview', entry, r'\energyfactor m c^2')
    configure('article', True)
    second = invoke('preview-offline', 'preview', entry, r'\energyfactor m c^2')
    assert first['cache'] == second['cache'] == 'miss'
    _, width, height, _ = pdf_details(second['pdf'])
    assert width < 650 and height < 150
    image = Path(second['png']).read_bytes()
    assert image.startswith(b'\x89PNG')
    macros = project / 'shared/macros.tex'
    macros.write_text(macros.read_text().replace('{2}', '{999}'))
    changed = invoke('preview-changed', 'preview', entry, r'\energyfactor m c^2')
    assert changed['cache'] == 'miss' and Path(changed['png']).read_bytes() != image
    assert pdf.read_bytes() == original_pdf
    report['cases'].append('preview offline, fresh render, changed external macro, output isolation')
    report['status'] = 'success'
except BaseException as error:
    report['status'] = 'failure'
    report['error'] = repr(error)
    raise
finally:
    report['seconds'] = round(time.monotonic() - started, 3)
    (run / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f"Tectonic tier {report['status']} in {report['seconds']}s; artifacts: {run}", flush=True)
