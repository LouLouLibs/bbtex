#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Real TeX Live/BibTeX/Biber corpus; preserve diagnostic artifacts on failure."""
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
BINARY = Path(os.environ.get('BBTEX_TEST_BINARY', ROOT / '_build/default/bin/main.exe')).resolve()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--engine', choices=['pdflatex', 'xelatex', 'lualatex'], default='pdflatex')
parser.add_argument('--artifacts', type=Path, default=ROOT / 'dist/real-engines')
args = parser.parse_args()
args.artifacts.mkdir(parents=True, exist_ok=True)
run_dir = Path(tempfile.mkdtemp(prefix=args.engine + '-', dir=args.artifacts.resolve()))
project = run_dir / 'paper with spaces é'
shutil.copytree(ROOT / 'test/corpus', project)
env = dict(os.environ, BBTEX_STATE_DIR=str(run_dir / 'state'))
started = time.monotonic()
report = {'status': 'running', 'engine': args.engine, 'cases': [], 'versions': {}}
print('Artifacts:', run_dir, flush=True)


def command(argv, **kwargs):
    return subprocess.run(list(map(str, argv)), env=env, text=True, capture_output=True,
                          timeout=180, **kwargs)


def bbtex(label, *argv, expected=0, selection=None):
    result = command([BINARY, *argv], input=selection)
    (run_dir / (label + '.stdout')).write_text(result.stdout)
    (run_dir / (label + '.stderr')).write_text(result.stderr)
    fields = dict(line.split(': ', 1) for line in result.stdout.splitlines() if ': ' in line)
    if 'applescript_file' in fields:
        script = Path(fields['applescript_file'])
        if script.exists():
            shutil.copy2(script, run_dir / (label + '.applescript'))
            script.unlink()
    assert result.returncode == expected, (label, result.returncode, result.stdout, result.stderr)
    return fields


def snapshot():
    return {str(path.relative_to(project)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in project.rglob('*') if path.is_file() and
            (path.suffix in ['.tex', '.bib'] or path.name == '.bbtex') and
            'build output' not in path.parts}


def pdf_details(pdf):
    info = command(['pdfinfo', pdf])
    assert info.returncode == 0, info.stderr
    size = re.search(r'Page size:\s+([\d.]+) x ([\d.]+)', info.stdout)
    pages = re.search(r'Pages:\s+(\d+)', info.stdout)
    assert size and pages, info.stdout
    extracted = command(['pdftotext', '-layout', pdf, '-'])
    assert extracted.returncode == 0, extracted.stderr
    return int(pages[1]), float(size[1]), float(size[2]), ' '.join(extracted.stdout.split())


try:
    for tool in [args.engine, 'latexmk', 'bibtex', 'biber', 'pdfinfo', 'pdftotext', 'pdftoppm']:
        assert shutil.which(tool), f'Required tool missing: {tool}'
        version = command([tool, '-v' if tool in ['pdfinfo', 'pdftotext', 'pdftoppm'] else '--version'])
        report['versions'][tool] = (version.stdout + version.stderr).splitlines()[:3]
        assert version.returncode == 0, f'{tool} cannot run: {version.stdout}{version.stderr}'
    for case in ['article', 'book', 'beamer', 'unicode']:
        (project / case / '.bbtex').write_text(f'root = main.tex\nengine = {args.engine}\noutput_directory = build output\n')
    before = snapshot()
    cases = [('article', 'sections/results.tex', ['ArticleEvidence', 'Corpus Bibliography Evidence'], 1, 3),
             ('book', 'chapters/introduction.tex', ['BookEvidence', 'Book Bibliography Evidence'], 4, 8),
             ('beamer', 'main.tex', ['BeamerEvidence', 'Literal text'], 2, 2)]
    if args.engine != 'pdflatex':
        cases.append(('unicode', 'main.tex', ['UnicodeEvidence', 'naïve façade', 'García'], 1, 1))
    for case, entry, markers, minimum, maximum in cases:
        case_started = time.monotonic()
        fields = bbtex(case, 'compile', project / case / entry)
        assert fields['status'] == 'success', fields
        assert fields['engine'] == args.engine, fields
        pdf = Path(fields['pdf'])
        # macOS may canonicalize the Unicode directory spelling to decomposed form.
        assert pdf.samefile(project / case / 'build output/main.pdf'), fields
        pages, width, height, content = pdf_details(pdf)
        assert minimum <= pages <= maximum, (case, pages)
        assert all(marker.casefold() in content.casefold() for marker in markers), (case, content)
        if case == 'beamer':
            assert abs(width / height - 16 / 9) < .02, (width, height)
        else:
            assert 550 < width < 650 and 750 < height < 900, (width, height)
        log = Path(fields['log']).read_text(errors='replace')
        assert not re.search(r'(Citation|Reference) .*undefined|There were undefined|Please \(re\)run Biber', log), log[-3000:]
        assert not (project / case / 'main.pdf').exists()
        for generated in (project / case).rglob('*'):
            if generated.suffix in ['.aux', '.bbl', '.bcf', '.log', '.pdf', '.toc']:
                assert 'build output' in generated.parts, f'Output escaped its directory: {generated}'
        if case in ['article', 'book']:
            assert (pdf.parent / 'main.bbl').is_file(), 'Bibliography was not generated'
            sync = gzip.open(pdf.with_suffix('.synctex.gz'), 'rt', errors='replace').read()
            assert entry in sync, 'Included source missing from SyncTeX'
        outline = command([BINARY, 'outline', project / case / entry])
        assert outline.returncode == 0, outline.stderr
        assert any(e['kind'] == 'label' for e in json.loads(outline.stdout)['entries'])
        report['cases'].append({'name': case, 'seconds': round(time.monotonic()-case_started, 3),
                                'pages': pages, 'width': width, 'height': height})
        print('Passed:', case, report['cases'][-1], flush=True)
    assert snapshot() == before, 'A build changed source files'

    # Exercise larger include graphs without checking generated boilerplate into git.
    large = project / 'larger project'
    large.mkdir()
    (large / '.bbtex').write_text(f'root = main.tex\nengine = {args.engine}\noutput_directory = build output\n')
    inputs = []
    for i in range(40):
        name = f'part-{i:02}.tex'
        (large / name).write_text(f'\\section{{Section {i}}}\\label{{sec:{i}}}\nCorpusPart{i:02}.\n')
        inputs.append('\\input{' + name + '}')
    (large / 'main.tex').write_text('\\documentclass{article}\n\\begin{document}\n' + '\n'.join(inputs) + '\n\\end{document}\n')
    large_fields = bbtex('larger', 'compile', large / 'main.tex')
    assert large_fields['engine'] == args.engine, large_fields
    assert 'CorpusPart39' in pdf_details(Path(large_fields['pdf']))[3]
    large_index = json.loads(command([BINARY, 'outline', large / 'main.tex']).stdout)
    assert len([e for e in large_index['entries'] if e['kind'] == 'label']) == 40
    print('Passed: generated 40-file project', flush=True)

    # Preview shares external preamble inputs, caches them, and stays out of build output.
    entry = project / 'article/sections/results.tex'
    built_pdf = project / 'article/build output/main.pdf'
    original_pdf = built_pdf.read_bytes()
    preview = bbtex('preview-first', 'preview', entry, selection=r'\energyfactor m c^2')
    assert preview['engine'] == args.engine, preview
    preview_pdf = Path(preview['pdf'])
    _, width, height, _ = pdf_details(preview_pdf)
    assert width < 650 and height < 150, (width, height)
    image = Path(preview['png']).read_bytes()
    assert image.startswith(b'\x89PNG')
    cached = bbtex('preview-cached', 'preview', entry, selection=r'\energyfactor m c^2')
    assert cached['cache'] == 'hit', cached
    macros = project / 'shared/macros.tex'
    macros.write_text(macros.read_text().replace('{2}', '{999}'))
    changed = bbtex('preview-changed', 'preview', entry, selection=r'\energyfactor m c^2')
    assert changed['cache'] == 'miss' and Path(changed['png']).read_bytes() != image
    assert built_pdf.read_bytes() == original_pdf
    print('Passed: preview geometry, output isolation, warm cache and external-input invalidation', flush=True)

    original_source = entry.read_text()
    lines = original_source.splitlines()
    lines.insert(2, r'\undefinedCorpusCommand')
    entry.write_text('\n'.join(lines) + '\n')
    failure = bbtex('diagnostic-failure', 'compile', entry, expected=1)
    parsed = command([BINARY, 'parse-log', failure['log']])
    (run_dir / 'diagnostics.txt').write_text(parsed.stdout + parsed.stderr)
    assert 'Undefined control sequence' in parsed.stdout and 'results.tex' in parsed.stdout, parsed.stdout
    plain_diagnostics = re.sub(r'\x1b\[[0-9;]*m', '', parsed.stdout)
    assert re.search(r'results\.tex:3\b', plain_diagnostics), parsed.stdout
    entry.write_text(original_source)
    bbtex('diagnostic-recovery', 'compile', entry)
    print('Passed: included-file diagnostic line mapping and build recovery', flush=True)

    # Close a marker file before looping: TeX's piped console output is buffered.
    cancelled_project = project / 'cancellation'
    cancelled_project.mkdir()
    (cancelled_project / '.bbtex').write_text(f'engine = {args.engine}\n')
    cancellation_source = cancelled_project / 'main.tex'
    cancellation_source.write_text('\\documentclass{article}\n\\begin{document}\n'
                                   '\\newwrite\\readyout\n\\immediate\\openout\\readyout=ready.txt\n'
                                   '\\immediate\\write\\readyout{ready}\n\\immediate\\closeout\\readyout\n'
                                   '\\loop\\iftrue\\repeat\n\\end{document}\n')
    process = subprocess.Popen([str(BINARY), 'compile', str(cancellation_source)], env=env,
                               text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 20
        while True:
            marker = cancelled_project / 'ready.txt'
            if marker.exists() and marker.read_text().strip() == 'ready':
                break
            assert process.poll() is None, 'TeX exited before cancellation readiness'
            assert time.monotonic() < deadline, 'TeX did not reach cancellation readiness'
            time.sleep(.05)
        bbtex('cancel-request', 'cancel', cancellation_source)
        output, errors = process.communicate(timeout=10)
        (run_dir / 'cancel-result.stdout').write_text(output)
        (run_dir / 'cancel-result.stderr').write_text(errors)
        assert process.returncode == 3 and 'status: cancelled' in output, (output, errors)
        assert not list((run_dir / 'state').glob('*.active')), 'Build lock remained active'
    finally:
        if process.poll() is None:
            process.terminate()
            process.communicate(timeout=10)
    cancellation_source.write_text('\\documentclass{article}\n\\begin{document}\nRecovered.\n\\end{document}\n')
    bbtex('cancel-recovery', 'compile', cancellation_source)
    print('Passed: cancellation of a real TeX process and subsequent build', flush=True)
    report['status'] = 'success'
except BaseException as error:
    report['status'] = 'failure'
    report['error'] = repr(error)
    raise
finally:
    report['seconds'] = round(time.monotonic()-started, 3)
    (run_dir / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f"Real-engine corpus {report['status']} in {report['seconds']}s; artifacts: {run_dir}", flush=True)
