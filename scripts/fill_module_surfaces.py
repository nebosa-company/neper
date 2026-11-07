"""Add every missing fence line for the modules named in a checker report.

Usage: fill_module_surfaces.py REPORT.txt CHECKER_JSON_INDEX_DIR

For each `FAIL: <module>: `<name>` is declared in source but not in its surface`
this asks the compiler for that module's index, builds the declaration text the
way `docs/module-apis.md` spells it, and appends what is missing. Lines going
the other way (in the fence, not in source) are printed but never removed: a
person has to decide whether the source lost a symbol or the fence kept a dead
one.
"""
import json
import os
import re
import subprocess
import sys

report_path = sys.argv[1]
compiler = sys.argv[2]
arch = sys.argv[3]
target_os = sys.argv[4]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

missing = {}
stale = []
for line in open(report_path, encoding='utf-8'):
    found = re.match(r'^FAIL: ([^:]+): `([^`]+)` is declared in source but not in its surface', line)
    if found:
        missing.setdefault(found.group(1), []).append(found.group(2))
        continue
    other = re.match(r'^FAIL: ([^:]+): `([^`]+)` is in its surface but neither written in source', line)
    if other:
        stale.append((other.group(1), other.group(2)))


def module_path(module):
    return os.path.join('lib', module.replace('.', os.sep) + '.e')


def declarations(module):
    path = module_path(module)
    command = [compiler, 'index-file', path, ROOT, arch, target_os, '--json']
    done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if done.returncode:
        return {}, done.stderr.strip()
    records = {}
    for raw in done.stdout.splitlines():
        if not raw.strip():
            continue
        record = json.loads(raw)
        if record.get('record') == 'symbol':
            records[record['name']] = record
    return records, ''


def fence_line(record, path):
    signature = (record.get('signature') or record['name']).strip()
    span = record.get('span')
    if record['kind'] in ('type', 'const') and span is not None:
        source = open(path, encoding='utf-8').read().splitlines()
        first, last = span['line'] - 1, span['end_line'] - 1
        if first == last:
            return source[first][span['column'] - 1:].strip()
        parts = [source[first][span['column'] - 1:]]
        parts.extend(source[first + 1:last])
        parts.append(source[last][:span['end_column'] - 1])
        return ' '.join(part.strip() for part in parts)
    return signature


catalogue = 'docs/module-apis.md'
lines = open(catalogue, encoding='utf-8').read().splitlines()
total = 0
for module in sorted(missing):
    names = sorted(set(missing[module]))
    records, error = declarations(module)
    if error:
        print('skip %s: %s' % (module, error), file=sys.stderr)
        continue
    generated = []
    for name in names:
        record = records.get(name)
        if record is None:
            print('no index record for %s.%s' % (module, name), file=sys.stderr)
            continue
        generated.append(fence_line(record, os.path.join(ROOT, module_path(module))))
    header = '### `%s`' % module
    if header not in lines:
        print('no catalogue heading for ' + module, file=sys.stderr)
        continue
    start = lines.index(header)
    open_at = start
    while open_at < len(lines) and lines[open_at].strip() != '```neper':
        open_at += 1
    close_at = open_at + 1
    while close_at < len(lines) and lines[close_at].strip() != '```':
        close_at += 1
    body = set(lines[open_at + 1:close_at])
    added = [line for line in generated if line not in body]
    lines[close_at:close_at] = added
    total += len(added)
    print('%-24s +%d' % (module, len(added)))

open(catalogue, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
print('added %d line(s) in total' % total)
if stale:
    print('fence entries with no source declaration (left for a person):')
    for module, name in stale:
        print('  %s.%s' % (module, name))
