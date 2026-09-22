#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Exercise real menu/clipping code with deterministic dialog answers in BBEdit."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = Path(os.environ.get('BBTEX_TEST_RESOURCES', ROOT / 'dist/bbtex-support.bbpackage/Contents/Resources'))

def apple(source, *args):
    result = subprocess.run(['osascript', '-', *map(str, args)], input=source, text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
    return result.stdout

with tempfile.TemporaryDirectory(prefix='bbtex-structure-dialogs-') as temporary:
    contents = Path(temporary) / 'test.bbpackage/Contents'
    resources = contents / 'Resources'
    resources.mkdir(parents=True)
    for name in ['bbtex', 'environments-lib.scpt']:
        shutil.copy2(RESOURCES / name, resources / name)
    for kind in ['menu', 'clipping', 'close']:
        source_path = ROOT / 'support/AppleScriptSources' / (
            'Scripts/LaTeX Editing/Wrap in Environment.applescript' if kind == 'menu'
            else 'Clippings/Latex.tex/close-environment.applescript' if kind == 'close'
            else 'Clippings/Latex.tex/environment.applescript')
        for answer in (['bad}name'] if kind == 'close' else ['cancel', 'quote', 'bad}name']):
            source = source_path.read_text()
            lines = []
            for line in source.splitlines():
                if 'set answer to display dialog' in line or 'set dialogResult to display dialog' in line:
                    variable = 'answer' if kind == 'menu' else 'dialogResult'
                    line = 'error number -128' if answer == 'cancel' else f'set {variable} to {{text returned:"{answer}"}}'
                # Expected invalid input must not show a modal alert during tests.
                if 'then tell application "BBEdit" to display alert' in line or 'then display alert' in line:
                    line = ('return "ERROR: " & messageText' if answer == 'quote'
                            else 'if errorNumber is not -128 then log messageText')
                if 'display dialog eStr' in line:
                    line = '-- Error dialog suppressed for deterministic invalid-input test'
                lines.append(line)
            compiled = contents / f'{kind}-{answer.replace("}", "")}.scpt'
            subprocess.run(['osacompile', '-o', str(compiled), '-'], input='\n'.join(lines), text=True, check=True)
            clipping = contents / 'test-clipping'
            clipping.write_text(f'#script {compiled.name}#\n')
            script = '''on run argv
                tell application "BBEdit"
                    set d to make new text document with properties {contents:"body", source language:"TeX"}
                    select characters 1 thru 4 of d
                end tell
                try
                    if item 2 of argv is "menu" then
                        run script POSIX file (item 1 of argv)
                    else
                        try
                            tell application "BBEdit" to insert clipping POSIX file (item 1 of argv)
                        on error messageText number errorNumber
                            -- BBEdit reports a cancelled clipping's absent result as -1701.
                            if item 3 of argv is "quote" or (errorNumber is not -128 and errorNumber is not -1701) then error messageText number errorNumber
                        end try
                    end if
                    tell application "BBEdit"
                        set actual to text of d as text
                        if item 3 of argv is "quote" then
                            if actual does not contain "\\\\begin{quote}" or actual does not contain "body" or actual does not contain "\\\\end{quote}" then error "Valid insertion failed: " & actual
                            undo
                            if (text of d as text) is not "body" then error "Insertion was not one Undo"
                        else
                            if actual is not "body" then error "Cancel/invalid input changed selected text: " & actual
                            if (contents of selection of window of d as text) is not "body" then error "Cancel/invalid input changed selection"
                        end if
                        close d saving no
                    end tell
                on error messageText number errorNumber
                    tell application "BBEdit" to close d saving no
                    error messageText number errorNumber
                end try
            end run'''
            apple(script, compiled if kind == 'menu' else clipping, kind, answer)
            print(f'{kind}: {answer} passed')
