#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["bibtexparser==2.0.1"]
# ///
"""Metadata/search tests; optionally exercise insertion, Undo, and stale guards in BBEdit."""
import importlib.util
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import time
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
BINARY = Path(os.environ.get('BBTEX_TEST_BINARY', ROOT / '_build/default/bin/main.exe'))
RESOURCES = Path(os.environ.get('BBTEX_TEST_RESOURCES', ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('citations', RESOURCES / 'citation-picker.py')
citations = importlib.util.module_from_spec(spec)
spec.loader.exec_module(citations)

# Exercise the actual AppleScript shell prefix, including inherited PATH entries
# with spaces. The native insertion tests stub out the interactive picker launch.
helper_source = (RESOURCES / 'insert-picker.applescript').read_text()
launch_literal = re.search(r'set pickerText to do shell script ("(?:\\.|[^"\\])*")', helper_source)
launch = json.loads(launch_literal.group(1))
inherited_path = '/Applications/Little Snitch.app/Contents/Components:/usr/bin:/bin'
shell_prefix = launch.split(' uv run ', 1)[0]
path_result = subprocess.check_output(
    ['/bin/sh', '-c', shell_prefix + ' /usr/bin/printenv PATH'],
    env=dict(os.environ, PATH=inherited_path, VIRTUAL_ENV='/tmp/unused environment'), text=True)
assert path_result.strip() == '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:' + inherited_path
print('Citation launcher preserves inherited PATH entries containing spaces')

def run(*args):
    return subprocess.check_output([str(BINARY), *map(str, args)], text=True)

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
    index = json.loads(run('outline', main))
    data = citations.bibliography(index)
    assert citations.search(data, 'garcía nested 2026')[0]['key'] == 'child'
    assert citations.search(data, '李 quoted 2025')[0]['key'] == 'quoted'
    assert citations.search(data, 'collected work')[0]['key'] == 'later'
    assert citations.search(data, 'valid after broken')[0]['key'] == 'valid'
    assert all(e['ambiguous'] for e in citations.search(data, 'duplicate'))
    assert any('missing.bib' in issue for issue in data['issues'])
    assert any('Cyclic' in issue for issue in data['issues'])
    assert citations.resolve_value('"a" ', {}) == 'a'
    expanding = {'x0': '{a}'}
    for i in range(1, 25):
        expanding[f'x{i}'] = f'x{i - 1} # x{i - 1}'
    try:
        citations.resolve_value('x24', expanding)
        raise AssertionError('Unbounded string expansion')
    except ValueError:
        pass
    script = citations.picker(str(BINARY), data, 'title')
    subprocess.run(['osacompile', '-o', str(folder / 'cite.scpt'), '-'], input=script, text=True, check=True)
    subprocess.run(['osacompile', '-o', str(folder / 'helper.scpt'), str(RESOURCES / 'insert-picker.applescript')], check=True)
    reference = run('reference-picker', main, 'equation')
    assert 'eq:result' in reference and 'x=y' in reference
    assert 'sec:methods' not in reference.split('set rows to', 1)[1].split('\n', 1)[0]
    proof = data['proofs'][0]
    run('picker-check', proof['file'], proof['fingerprint'])
    print('Metadata: nested/quoted values, strings/concatenation, inheritance, Unicode, duplicate keys and recovery passed')

    # A large bibliography is indexed, but bounded dialog output requires a query.
    large = folder / 'large.bib'
    large.write_text('\n'.join('@article{key%d,title={Paper number %d},author={Author %d}}' % (i, i, i) for i in range(10000)))
    started = time.monotonic()
    big = citations.bibliography(dict(issues=[], files=[], bibliographies=[str(large)]))
    assert len(big['entries']) == 10000
    assert len(citations.search(big, 'number 9999')) == 1
    try:
        citations.picker(str(BINARY), big, '')
        raise AssertionError('Unbounded dialog')
    except ValueError:
        pass
    print(f'10,000-entry bibliography indexed/searched in {time.monotonic() - started:.3f}s')

    if os.environ.get('BBTEX_TEST_NATIVE') == '1':
        helper = (RESOURCES / 'insert-picker.applescript').read_text()
        helper = '\n'.join('            set answer to {text returned:""}' if 'set answer to display dialog' in line
                           else '            set pickerText to ""' if 'set pickerText to do shell script' in line
                           else '        error messageText number errorNumber' if 'then tell application "BBEdit" to display alert' in line
                           else line for line in helper.splitlines())
        quote = citations.quote
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
            clean = dict(data, issues=[], entries=[e for e in data['entries'] if e['key'] in ('quoted', 'valid')])
            picker = citations.picker(str(BINARY), clean, '')
            picker = '\n'.join('set chosen to {item 1 of rows, item 2 of rows}'
                               if line.startswith('set chosen to choose') else line for line in picker.splitlines())
            chosen = apple(picker).stdout
            assert 'quoted,valid' in chosen, chosen

            # Start with an already-dirty editor buffer. Only our insertion is undone.
            prepare(original)
            apple('tell application "BBEdit" to select insertion point before character ' + str(units(original)) + ' of front text document')
            result = apple(helper.replace('set choice to run script pickerText', 'set choice to {"newA,newB", ""}'),
                           BINARY, 'cite', RESOURCES / 'citation-picker.py')
            expected = original[:-1] + ',newA,newB}'
            assert contents() == expected, (contents(), expected, result)
            apple('tell application "BBEdit" to undo')
            assert contents() == original

            # Cancel performs no edit. A case-only edit while the dialog is open is protected.
            cancel = helper.replace('set choice to run script pickerText', 'set choice to false')
            apple(cancel, BINARY, 'cite', RESOURCES / 'citation-picker.py')
            assert contents() == original
            changed = original.replace('See', 'see')
            mutation = 'tell application "BBEdit" to set contents of front text document to ' + quote(changed) + '\nset choice to {"newA", ""}'
            failure = apple(helper.replace('set choice to run script pickerText', mutation),
                            BINARY, 'cite', RESOURCES / 'citation-picker.py', check=False)
            assert failure.returncode and 'document changed' in failure.stderr.lower(), failure
            assert contents() == changed

            prepare(original)
            move = 'tell application "BBEdit" to select insertion point before character 1 of front text document\nset choice to {"newA", ""}'
            failure = apple(helper.replace('set choice to run script pickerText', move),
                            BINARY, 'cite', RESOURCES / 'citation-picker.py', check=False)
            assert failure.returncode and 'selection moved' in failure.stderr.lower(), failure
            assert contents() == original

            prepare('See \\eqref{old}')
            apple('tell application "BBEdit" to select insertion point before character 14 of front text document')
            apple(helper.replace('set choice to run script pickerText', 'set choice to {"eq:result", ""}'),
                  BINARY, 'ref', RESOURCES / 'citation-picker.py')
            assert contents() == 'See \\eqref{eq:result}'
            print('Native insertion: multi-cite, Unicode, command/options retention, reference replacement, Undo, cancel and dirty-buffer race passed')
        finally:
            apple('tell application "BBEdit"\nrepeat with d in (get text documents)\ntry\n'
                  'set f to file of d\nif POSIX path of f is ' + quote(str(main)) +
                  ' then close d saving no\nend try\nend repeat\nend tell')
