#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Metadata/search tests; optionally exercise insertion, Undo, and stale guards in BBEdit."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
BINARY = Path(os.environ.get('BBTEX_TEST_BINARY', ROOT / '_build/default/bin/main.exe'))
RESOURCES = Path(os.environ.get('BBTEX_TEST_RESOURCES', ROOT / 'scripts'))

def run(*args):
    return subprocess.check_output([str(BINARY), *map(str, args)], text=True)

def quote(text):
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'

def apple(script, *args, check=True):
    result = subprocess.run(['osascript', '-', *map(str, args)], input=script,
                            capture_output=True, text=True)
    if check:
        assert result.returncode == 0, result.stderr
    return result

with tempfile.TemporaryDirectory(prefix='bbtex-pickers-') as temporary:
    folder = Path(temporary).resolve()
    main = folder / 'main.tex'
    main.write_text('\\documentclass{article}\n\\addbibresource[location=local]{one.bib}\n'
                    '\\bibliography{two,missing}\n\\begin{document}\n'
                    '\\section{Methods}\\label{sec:methods}\n'
                    '\\begin{equation}x=y\\label{eq:result}\\end{equation}\n\\end{document}\n')
    (folder / 'one.bib').write_text('''@string{prefix = "Collected"}
@book{parent, author={García, Ana}, title={Parent}, year={2026}}
@xdata{shared, year=2025}
@article{child, title=prefix # { {Nested} Papers}, crossref={parent}}
@article{quoted, title="A {Quoted} Title", author={李, 明}, xdata={shared}}
@article{duplicate, title={First duplicate}}
@article{duplicate, title={Second duplicate}}
@article{broken, title={unfinished
@article{valid, title={Valid after broken}}
''')
    (folder / 'two.bib').write_text('''@article{later, title=prefix # " Work", author={Zoë}}
@article{loopA, crossref={loopB}}
@article{loopB, crossref={loopA}}
''')
    def search(query, source=main):
        return json.loads(run('citation-picker', source, query, '--json'))

    assert search('garcía nested 2026')['entries'][0]['key'] == 'child'
    assert search('李 quoted 2025')['entries'][0]['key'] == 'quoted'
    assert search('collected work')['entries'][0]['key'] == 'later'
    assert search('valid after broken')['entries'][0]['key'] == 'valid'
    assert all(e['ambiguous'] for e in search('duplicate')['entries'])
    issues = search('')['issues']
    assert any('missing.bib' in issue for issue in issues)
    assert any('Cyclic' in issue for issue in issues)
    script = run('citation-picker', main, 'title')
    subprocess.run(['osacompile', '-o', str(folder / 'cite.scpt'), '-'], input=script, text=True, check=True)
    subprocess.run(['osacompile', '-o', str(folder / 'helper.scpt'), str(RESOURCES / 'insert-picker.applescript')], check=True)
    reference = run('reference-picker', main, 'equation')
    assert 'eq:result' in reference and 'x=y' in reference
    assert 'sec:methods' not in reference.split('set rows to', 1)[1].split('\n', 1)[0]
    bibliography = folder / 'one.bib'
    run('picker-check', bibliography, hashlib.md5(bibliography.read_bytes()).hexdigest())
    print('Metadata: nested/quoted values, strings/concatenation, inheritance, Unicode, duplicate keys and recovery passed')

    # A large bibliography is indexed, but bounded dialog output requires a query.
    large = folder / 'large.bib'
    large.write_text('\n'.join('@article{key%d,title={Paper number %d},author={Author %d}}' % (i, i, i) for i in range(10000)))
    large_source = folder / 'large.tex'
    large_source.write_text('\\bibliography{large}\n')
    started = time.monotonic()
    assert len(search('', large_source)['entries']) == 10000
    assert len(search('number 9999', large_source)['entries']) == 1
    unbounded = subprocess.run([str(BINARY), 'citation-picker', str(large_source), ''],
                               capture_output=True, text=True)
    assert unbounded.returncode == 2 and 'More than 300' in unbounded.stderr, unbounded
    print(f'10,000-entry bibliography indexed/searched in {time.monotonic() - started:.3f}s')

    if os.environ.get('BBTEX_TEST_NATIVE') == '1':
        helper = (RESOURCES / 'insert-picker.applescript').read_text()
        helper = '\n'.join('            set answer to {text returned:""}' if 'set answer to display dialog' in line
                           else '            set pickerText to ""' if 'set pickerText to do shell script' in line
                           else '        error messageText number errorNumber' if 'then tell application "BBEdit" to display alert' in line
                           else line for line in helper.splitlines())
        units = lambda text: len(text.encode('utf-16-le')) // 2

        def prepare(text):
            apple('tell application "BBEdit"\nset d to open (POSIX file ' + quote(str(main)) + ')\n'
                  'set contents of d to ' + quote(text) + '\n'
                  f'select insertion point after character {units(text)} of d\n'
                  'set index of window of d to 1\nend tell')

        def contents():
            return apple('tell application "BBEdit" to get contents of front text document').stdout.rstrip('\n')

        original = 'É😀 See \\citet*[see][p. 2]{existing}'
        try:
            # Multi-select picker maps the exact chosen rows to keys.
            # A project without index issues, so no partial-index alert opens.
            (folder / 'clean.bib').write_text('@article{quoted, title="A {Quoted} Title"}\n'
                                              '@article{valid, title={Valid}}\n')
            (folder / 'clean.tex').write_text('\\bibliography{clean}\n')
            picker = run('citation-picker', folder / 'clean.tex', '')
            picker = '\n'.join('set chosen to {item 1 of rows, item 2 of rows}'
                               if line.startswith('set chosen to choose') else line for line in picker.splitlines())
            chosen = apple(picker).stdout
            assert 'quoted,valid' in chosen, chosen

            # Start with an already-dirty editor buffer. Only our insertion is undone.
            prepare(original)
            apple('tell application "BBEdit" to select insertion point before character ' + str(units(original)) + ' of front text document')
            result = apple(helper.replace('set choice to run script pickerText', 'set choice to {"newA,newB", ""}'),
                           BINARY, 'cite')
            expected = original[:-1] + ',newA,newB}'
            assert contents() == expected, (contents(), expected, result)
            apple('tell application "BBEdit" to undo')
            assert contents() == original

            # Cancel performs no edit. A case-only edit while the dialog is open is protected.
            cancel = helper.replace('set choice to run script pickerText', 'set choice to false')
            apple(cancel, BINARY, 'cite')
            assert contents() == original
            changed = original.replace('See', 'see')
            mutation = 'tell application "BBEdit" to set contents of front text document to ' + quote(changed) + '\nset choice to {"newA", ""}'
            failure = apple(helper.replace('set choice to run script pickerText', mutation),
                            BINARY, 'cite', check=False)
            assert failure.returncode and 'document changed' in failure.stderr.lower(), failure
            assert contents() == changed

            prepare(original)
            move = 'tell application "BBEdit" to select insertion point before character 1 of front text document\nset choice to {"newA", ""}'
            failure = apple(helper.replace('set choice to run script pickerText', move),
                            BINARY, 'cite', check=False)
            assert failure.returncode and 'selection moved' in failure.stderr.lower(), failure
            assert contents() == original

            prepare('See \\eqref{old}')
            apple('tell application "BBEdit" to select insertion point before character 14 of front text document')
            apple(helper.replace('set choice to run script pickerText', 'set choice to {"eq:result", ""}'),
                  BINARY, 'ref')
            assert contents() == 'See \\eqref{eq:result}'
            print('Native insertion: multi-cite, Unicode, command/options retention, reference replacement, Undo, cancel and dirty-buffer race passed')
        finally:
            apple('tell application "BBEdit"\nrepeat with d in (get text documents)\ntry\n'
                  'set f to file of d\nif POSIX path of f is ' + quote(str(main)) +
                  ' then close d saving no\nend try\nend repeat\nend tell')
