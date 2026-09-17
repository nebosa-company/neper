"""Every function and type of a source tree renamed (D529, H10, H17).

    python benchmarks/metamorphic/rename_symbols.py COMPILER ROOT SRC_DIR OUT_DIR [OS]

The metamorphic harness's `symbols` transformation (D478) over a whole tree: every
function but `main` and every type declared under SRC_DIR takes a name of the same
length, at its declaration and at every reference the index of any module resolves
to it, qualified or bare, past keywords and every name any module spells. Left as
they are: `main`, externs and `@import`ed functions, whose names are foreign, and a
type with a function spelled `<snake>_<op>` for it together with those functions,
since the lookup is by the spelling (D517). A compiler built from the result must
build the original sources to the stable stage byte for byte: its own names reach
its own image and nothing else.
"""
import json, os, re, shutil, subprocess, sys

compiler, root, src_dir, out_dir = sys.argv[1:5]
host_os = sys.argv[5] if len(sys.argv) > 5 else 'windows'
if os.path.exists(out_dir):
    shutil.rmtree(out_dir)
os.makedirs(out_dir)
KEYWORDS = set('''fn let var ret if else while for in break continue use type error const struct union
enum true false nil ok zero undef extern unreachable shared own try defer switch case match as
and or not import pub mut static comptime test gpu when is do loop target byte'''.split())
PROTOCOL_OPS = ('eq', 'cmp', 'hash', 'format', 'next', 'next_err')


def snake(name):
    out = bytearray()
    for i, ch in enumerate(name):
        upper = 65 <= ch <= 90
        if upper and i > 0 and ((97 <= name[i - 1] <= 122) or (48 <= name[i - 1] <= 57) or (i + 1 < len(name) and 97 <= name[i + 1] <= 122)):
            out.append(95)
        out.append(ch + 32 if upper else ch)
    return bytes(out)


def same_length_name(name, taken):
    for times in range(1, 26):
        out = bytearray()
        for ch in name:
            if 97 <= ch <= 122:
                out.append((ch - 97 + times) % 26 + 97)
            elif 65 <= ch <= 90:
                out.append((ch - 65 + times) % 26 + 65)
            else:
                out.append(ch)
        candidate = bytes(out)
        if candidate != name and candidate.decode() not in KEYWORDS and candidate not in taken:
            taken.add(candidate)
            return candidate
    return name


modules = {}
taken = set()
for name in sorted(os.listdir(src_dir)):
    path = os.path.join(src_dir, name)
    if not (os.path.isfile(path) and name.endswith('.e')):
        continue
    p = subprocess.run([compiler, 'index-file', path, root, 'x64', host_os, '--json'], capture_output=True)
    if p.returncode != 0:
        sys.exit('rename_symbols: index of %s failed' % path)
    records = [json.loads(line) for line in p.stdout.decode('utf-8').splitlines()]
    text = open(path, 'rb').read()
    tokens = subprocess.run([compiler, 'tokens', path, '--json'], capture_output=True).stdout.decode('utf-8').splitlines()
    for line in tokens:
        r = json.loads(line)
        if r.get('record') == 'token' and r['kind'] == 'IDENTIFIER':
            taken.add(text[r['span']['byte_start']:r['span']['byte_end']])
    modules[name] = (path, text, records)

# The declarations that may be renamed: functions and types, by qualified name.
renames = {}
for name, (path, text, records) in modules.items():
    module = [r for r in records if r.get('record') == 'symbol' and r['kind'] == 'module'][0]['name']
    declared = {r['qualified_name']: r for r in records if r.get('record') == 'symbol' and r['kind'] in ('fn', 'type', 'extern') and r['module'] == module and r.get('selection_span')}
    type_prefixes = {q: snake(r['name'].encode()) + b'_' for q, r in declared.items() if r['kind'] == 'type'}
    protocol_bound = set()
    for q, r in declared.items():
        if r['kind'] != 'fn':
            continue
        for tq, prefix in type_prefixes.items():
            n = r['name'].encode()
            if n.startswith(prefix) and n[len(prefix):].decode() in PROTOCOL_OPS:
                protocol_bound.add(q)
                protocol_bound.add(tq)
    for q, r in declared.items():
        if r['kind'] == 'extern' or r['name'] == 'main' or q in protocol_bound or 'import' in r.get('attributes', []) or 'export' in r.get('attributes', []):
            continue
        renames[q] = None
for q in sorted(renames):
    old = q.rsplit('.', 1)[1].encode()
    renames[q] = same_length_name(old, taken)

# Every module rewritten: declarations and references whose target is renamed.
for name, (path, text, records) in modules.items():
    spans = []
    for r in records:
        if r.get('record') == 'symbol' and r['qualified_name'] in renames and r.get('selection_span'):
            s = r['selection_span']
            spans.append((s['byte_start'], s['byte_end'], r['qualified_name']))
        if r.get('record') == 'reference' and r.get('target_qualified_name') in renames:
            s = r['source_span']
            old = r['target_qualified_name'].rsplit('.', 1)[1].encode()
            if text[s['byte_end'] - len(old):s['byte_end']] == old:
                spans.append((s['byte_end'] - len(old), s['byte_end'], r['target_qualified_name']))
    out = bytearray(text)
    for start, end, q in sorted(set(spans), reverse=True):
        out[start:end] = renames[q]
    open(os.path.join(out_dir, name), 'wb').write(bytes(out))
for name in sorted(os.listdir(src_dir)):
    path = os.path.join(src_dir, name)
    if os.path.isfile(path) and not name.endswith('.e'):
        shutil.copy(path, os.path.join(out_dir, name))
print('renamed', len(renames))
