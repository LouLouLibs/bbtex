#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["bibtexparser==2.0.1"]
# ///
"""Read saved project bibliography metadata; never rewrite bibliography files."""
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys

import bibtexparser
from bibtexparser.model import Entry, String, DuplicateBlockKeyBlock


def quote(text):
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'


def valid_key(key):
    return bool(key) and not any(c.isspace() or c in '\\{},%#$' for c in key)


def resolve_value(value, strings, seen=(), cache=None):
    """Resolve the value-expression layer left opaque by BibtexParser (not entries)."""
    pieces = []
    if cache is None:
        cache = {}
    total = 0
    position = 0
    while position < len(value):
        while position < len(value) and value[position].isspace():
            position += 1
        if position == len(value):
            break
        opening = value[position]
        if opening in '{"':
            start = position + 1
            position = start
            depth = 1 if opening == '{' else 0
            while position < len(value):
                char = value[position]
                if char == '\\':
                    position += 2
                    continue
                if char == '{':
                    depth += 1
                elif char == '}':
                    depth -= 1
                    if opening == '{' and depth == 0:
                        break
                elif char == '"' and opening == '"' and depth == 0:
                    break
                position += 1
            if position >= len(value):
                raise ValueError("Unclosed metadata value")
            pieces.append(value[start:position])
            position += 1
        else:
            match = re.match(r'[^\s#]+', value[position:])
            if not match:
                raise ValueError("Invalid string concatenation")
            token = match.group()
            position += len(token)
            name = token.casefold()
            if name in strings:
                if name in seen or len(seen) >= 32:
                    raise ValueError("Cyclic bibliography string: " + token)
                if name not in cache:
                    cache[name] = resolve_value(strings[name], strings, (*seen, name), cache)
                pieces.append(cache[name])
            else:
                pieces.append(token)
        total += len(pieces[-1])
        if total > 1024 * 1024:
            raise ValueError("Expanded metadata exceeds 1 MiB")
        while position < len(value) and value[position].isspace():
            position += 1
        if position < len(value):
            if value[position] != '#':
                raise ValueError("Unexpected metadata expression")
            position += 1
            if not value[position:].strip():
                raise ValueError("Missing value after string concatenation")
    return ''.join(pieces)


def bibliography(index):
    issues = list(index['issues'])
    proofs = list(index['files'])
    entries = []
    strings = {}
    for filename in index['bibliographies']:
        path = Path(filename)
        try:
            if path.stat().st_size > 32 * 1024 * 1024:
                raise ValueError("Bibliography exceeds 32 MiB")
            raw = path.read_bytes()
            proofs.append(dict(file=filename, fingerprint=hashlib.md5(raw).hexdigest()))
            library = bibtexparser.parse_string(raw.decode('utf-8-sig'), parse_stack=[])
        except (OSError, UnicodeError, ValueError) as error:
            issues.append(f'{filename}: {error}')
            continue
        for block in library.blocks:
            if isinstance(block, String):
                strings[block.key.casefold()] = block.value
            elif isinstance(block, Entry):
                entries.append(dict(key=block.key, type=block.entry_type, file=filename,
                                    line=(block.start_line or 0) + 1,
                                    fields={f.key.casefold(): f.value for f in block.fields}))
            elif isinstance(block, DuplicateBlockKeyBlock) and isinstance(block.ignore_error_block, Entry):
                entry = block.ignore_error_block
                entries.append(dict(key=entry.key, type=entry.entry_type, file=filename,
                                    line=(block.start_line or 0) + 1, fields={}))
                issues.append(f'{filename}:{(block.start_line or 0) + 1}: duplicate key {entry.key}')
            elif block in library.failed_blocks:
                issues.append(f'{filename}:{(block.start_line or 0) + 1}: malformed entry skipped')
    string_cache = {}
    for entry in entries:
        for name, value in list(entry['fields'].items()):
            try:
                entry['fields'][name] = resolve_value(value, strings, cache=string_cache)
            except ValueError as error:
                issues.append(f"{entry['key']}: {error}")
    grouped = {}
    for entry in entries:
        grouped.setdefault(entry['key'], []).append(entry)

    def inherited(entry, seen=()):
        if entry['key'] in seen or len(seen) >= 32:
            issues.append('Cyclic inherited metadata: ' + entry['key'])
            return {}
        own = entry['fields']
        result = {}
        parents = [p.strip() for p in own.get('xdata', '').split(',') if p.strip()]
        if own.get('crossref'):
            parents.append(own['crossref'])
        for parent in parents:
            if len(grouped.get(parent, [])) == 1:
                result.update(inherited(grouped[parent][0], (*seen, entry['key'])))
            else:
                issues.append(f"{entry['key']}: missing or ambiguous inherited entry {parent}")
        result.update(own)
        return result

    for entry in entries:
        fields = inherited(entry)
        entry['author'] = fields.get('author', fields.get('editor', ''))
        entry['title'] = fields.get('title', fields.get('booktitle', ''))
        entry['year'] = fields.get('year', fields.get('date', ''))
        entry['ambiguous'] = len(grouped[entry['key']]) != 1
        if entry['ambiguous']:
            issues.append('Duplicate citation key: ' + entry['key'])
    return dict(entries=entries, issues=list(dict.fromkeys(issues)), proofs=proofs)


def search(data, query):
    tokens = query.casefold().split()
    return [entry for entry in data['entries'] if entry['type'].casefold() != 'xdata'
            and all(token in ' '.join(str(entry.get(k, '')) for k in
                                     ('key', 'author', 'title', 'year', 'file')).casefold()
                    for token in tokens)]


def picker(binary, data, query):
    entries = search(data, query)
    if len(entries) > 300:
        raise ValueError('More than 300 citations match. Narrow the search.')
    script = ['tell application "BBEdit"']
    if data['issues']:
        script.append('display alert "Partial bibliography index" message ' + quote('\n'.join(data['issues'][:20])))
    if not entries:
        script.extend(['display alert "Insert Citation" message "No matching saved bibliography entries."',
                       'return false', 'end tell'])
        return '\n'.join(script)
    def short(text):
        return ' '.join(text.split())[:160]
    rows = [f"{i}. {e['key']} — {short(e['author'])} ({e['year']}) · {short(e['title'])}"
            f" — {Path(e['file']).name}:{e['line']}" for i, e in enumerate(entries, 1)]
    script += ['set rows to {' + ', '.join(quote(row) for row in rows) + '}',
               'set chosen to choose from list rows with title "Insert Citation" with prompt '
               '"Select one or more citations. Shift/Command selects multiple rows." '
               'OK button name "Insert" with multiple selections allowed',
               'if chosen is false then return false', 'set chosenKeys to ""']
    for i, entry in enumerate(entries, 1):
        script.append(f'if chosen contains item {i} of rows then')
        if entry['ambiguous'] or not valid_key(entry['key']):
            script.append('error "This citation key is duplicated or cannot be inserted literally. Fix its definition first."')
        else:
            script += ['if chosenKeys is not "" then set chosenKeys to chosenKeys & ","',
                       'set chosenKeys to chosenKeys & ' + quote(entry['key'])]
        script.append('end if')
    verification = '\n'.join('do shell script ' + quote(shlex.join(
        [binary, 'picker-check', proof['file'], proof['fingerprint']])) for proof in data['proofs'])
    script += ['return {chosenKeys, ' + quote(verification) + '}', 'end tell']
    return '\n'.join(script)


def main():
    binary, source, query = sys.argv[1:4]
    index = json.loads(subprocess.check_output([binary, 'outline', source], text=True))
    data = bibliography(index)
    if '--json' in sys.argv[4:]:
        print(json.dumps(dict(entries=search(data, query), issues=data['issues']), ensure_ascii=False))
    else:
        print(picker(binary, data, query))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
