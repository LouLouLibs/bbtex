#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Tectonic rendering/cache tier, including a compatible external Biber."""
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
parser.add_argument('--biber', type=Path, help='Compatible Biber executable, exposed only to this test run')
parser.add_argument('--artifacts', type=Path, default=ROOT / 'dist/real-engines')
args = parser.parse_args()
args.artifacts.mkdir(parents=True, exist_ok=True)
run = Path(tempfile.mkdtemp(prefix='tectonic-', dir=args.artifacts.resolve()))
project = run / 'paper with spaces é'
shutil.copytree(ROOT / 'test/corpus', project)
binary = Path(os.environ.get('BBTEX_TEST_BINARY', ROOT / '_build/default/bin/main.exe')).resolve()
env = dict(os.environ, BBTEX_STATE_DIR=str(run / 'state'))
tool_override = None
if args.biber:
    tool_override = tempfile.TemporaryDirectory(prefix='bbtex-tectonic-tools-')
    tools = Path(tool_override.name)
    (tools / 'biber').symlink_to(args.biber.resolve(strict=True))
    env['PATH'] = str(tools) + os.pathsep + env.get('PATH', '')
report = {'status': 'running', 'engine': 'tectonic', 'bundle': args.bundle or 'installed default',
          'biber': str(args.biber.resolve()) if args.biber else shutil.which('biber'),
          'versions': {}, 'cases': []}
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
    for tool in ['tectonic', 'biber', 'pdfinfo', 'pdftotext', 'pdftoppm']:
        version = command([tool, '--version' if tool in ['tectonic', 'biber'] else '-v'])
        assert version.returncode == 0, version.stderr
        report['versions'][tool] = (version.stdout + version.stderr).splitlines()[:3]
    sources = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in project.rglob('*')
               if p.suffix in ['.tex', '.bib']}
    for case, marker, minimum, maximum in [('article', 'Corpus Bibliography Evidence', 1, 3),
                                          ('book', 'Book Bibliography Evidence', 4, 8),
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
            assert not re.search(r'(Citation|Reference) .*undefined|There were undefined|Please \(re\)run Biber', log), log[-3000:]
            if case in ['article', 'book']:
                sync = gzip.open(pdf.with_suffix('.synctex.gz'), 'rt', errors='replace').read()
                assert ('sections/results.tex' if case == 'article' else 'chapters/results.tex') in sync
            if case == 'book':
                build_log = Path(result['build_log']).read_text(errors='replace')
                assert 'Running external tool biber' in build_log, 'Biber was not invoked'
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

    large = project / 'larger project'
    large.mkdir()
    configure('larger project')
    inputs = []
    for i in range(40):
        name = f'part-{i:02}.tex'
        (large / name).write_text(f'\\section{{Section {i}}}\\label{{sec:{i}}}\nCorpusPart{i:02}.\n')
        inputs.append('\\input{' + name + '}')
    (large / 'main.tex').write_text('\\documentclass{article}\n\\begin{document}\n' + '\n'.join(inputs) + '\n\\end{document}\n')
    invoke('larger-online', 'compile', large / 'main.tex')
    configure('larger project', True)
    result = invoke('larger-offline', 'compile', large / 'main.tex')
    assert 'CorpusPart39' in pdf_details(result['pdf'])[3]
    index = command([binary, 'outline', large / 'main.tex'])
    assert index.returncode == 0, index.stderr
    assert len([e for e in json.loads(index.stdout)['entries'] if e['kind'] == 'label']) == 40
    report['cases'].append('40-file project and outline')
    print('Passed: 40-file project and outline', flush=True)

    cancelled = project / 'cancellation'
    cancelled.mkdir()
    configure('cancellation', True)
    config = cancelled / '.bbtex'
    config.write_text(config.read_text().replace('options = ', 'options = --print '))
    source = cancelled / 'main.tex'
    # Tectonic's virtual filesystem publishes files only after processing. Print
    # enough readiness messages to flush its console pipe before the infinite loop.
    source.write_text('\\documentclass{article}\n\\begin{document}\n'
                      + '\\immediate\\write16{BBTEX-CANCELLATION-READY}\n' * 1000
                      + '\\loop\\iftrue\\repeat\n\\end{document}\n')
    process = subprocess.Popen([str(binary), 'compile', str(source)], env=env,
                               text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 20
        while True:
            logs = list((run / 'state').glob('build-*.log'))
            if any('BBTEX-CANCELLATION-READY' in log.read_text(errors='replace') for log in logs):
                break
            assert process.poll() is None, 'Tectonic exited before cancellation readiness'
            assert time.monotonic() < deadline, 'Tectonic did not reach cancellation readiness'
            time.sleep(.05)
        request = command([binary, 'cancel', source])
        assert request.returncode == 0, request.stderr
        output, errors = process.communicate(timeout=10)
        (run / 'cancel-result.stdout').write_text(output)
        (run / 'cancel-result.stderr').write_text(errors)
        assert process.returncode == 3 and 'status: cancelled' in output, (output, errors)
        assert not list((run / 'state').glob('*.active'))
    finally:
        if process.poll() is None:
            command([binary, 'cancel', source])
            process.communicate(timeout=10)
    source.write_text('\\documentclass{article}\n\\begin{document}Recovered.\\end{document}\n')
    recovery = invoke('cancel-recovery', 'compile', source)
    assert 'Recovered.' in pdf_details(recovery['pdf'])[3]
    report['cases'].append('real Tectonic cancellation and recovery')
    print('Passed: real Tectonic cancellation and recovery', flush=True)
    report['status'] = 'success'
except BaseException as error:
    report['status'] = 'failure'
    report['error'] = repr(error)
    raise
finally:
    if tool_override:
        tool_override.cleanup()
    report['seconds'] = round(time.monotonic() - started, 3)
    (run / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f"Tectonic tier {report['status']} in {report['seconds']}s; artifacts: {run}", flush=True)
