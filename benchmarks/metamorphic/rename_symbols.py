"""Every function and type of a source tree renamed (D529, H10, H17).

    python benchmarks/metamorphic/rename_symbols.py COMPILER ROOT SRC_DIR OUT_DIR [OS] [EXTRA_DIR EXTRA_OUT]...

The metamorphic harness's `symbols` transformation (D478) over a whole tree: every
function but `main` and every type declared under the input trees takes a name of the same
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
extra = sys.argv[6:]
if len(extra) % 2:
    sys.exit('rename_symbols: extra trees must be IN_DIR OUT_DIR pairs')
trees = [(src_dir, out_dir)] + list(zip(extra[0::2], extra[1::2]))
for _, output in trees:
    if os.path.exists(output):
        shutil.rmtree(output)
    os.makedirs(output)
KEYWORDS = set('''fn let var ret if else while for in break continue use type error const struct union
enum true false nil ok zero undef extern unreachable shared own try defer switch case match as
and or not import pub mut static comptime test gpu when is do loop target byte'''.split())
PROTOCOL_OPS = ('eq', 'cmp', 'hash', 'format', 'next', 'next_err')
# These source declarations are named by signatures the compiler seeds rather than
# by source references. Renaming one would change the language/runtime contract,
# not merely the program (D560).
SEEDED_NAMES = {
    'e.mem.Arena', 'e.mem.Stats',
    'e.os.File', 'e.os.Proc', 'e.os.Clock', 'e.os.DirEntry', 'e.os.OpenFlags',
    'e.os.Stdio', 'e.os.SeekWhence', 'e.os.Thread',
    'e.str.Builder', 'e.atomic.Atomic', 'e.simd.Vec', 'e.simd.Mask',
    # Source wrappers whose spelling is part of the fixed ownership/runtime surface.
    'e.os.stdin', 'e.os.stdout', 'e.os.stderr', 'e.os.close', 'e.os.wait',
    'e.os.wait_usage', 'e.os.thread_create', 'e.os.thread_join',
    'e.os.thread_detach', 'e.thread.join',
}


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
for input_root, output_root in trees:
    for dirpath, dirs, files in os.walk(input_root):
        dirs.sort()
        rel_dir = os.path.relpath(dirpath, input_root)
        target_dir = output_root if rel_dir == '.' else os.path.join(output_root, rel_dir)
        os.makedirs(target_dir, exist_ok=True)
        for name in sorted(files):
            path = os.path.join(dirpath, name)
            target_path = os.path.join(target_dir, name)
            parts = name.split('.')
            other_target = len(parts) == 3 and parts[1] not in (host_os, 'x64')
            if not name.endswith('.e') or other_target:
                shutil.copy(path, target_path)
                continue
            p = subprocess.run([compiler, 'index-file', path, root, 'x64', host_os, '--json'], capture_output=True)
            if p.returncode != 0:
                sys.exit('rename_symbols: index of %s failed: %s' % (path, p.stdout[:300]))
            records = [json.loads(line) for line in p.stdout.decode('utf-8').splitlines()]
            text = open(path, 'rb').read()
            tokens = subprocess.run([compiler, 'tokens', path, '--json'], capture_output=True).stdout.decode('utf-8').splitlines()
            for line in tokens:
                r = json.loads(line)
                if r.get('record') == 'token' and r['kind'] == 'IDENTIFIER':
                    taken.add(text[r['span']['byte_start']:r['span']['byte_end']])
            modules[path] = (target_path, text, records)

# The declarations that may be renamed: functions and types, by qualified name.
renames = {}
for path, (target_path, text, records) in modules.items():
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
        if r['kind'] == 'extern' or r['name'] == 'main' or q in SEEDED_NAMES or q in protocol_bound or 'import' in r.get('attributes', []) or 'export' in r.get('attributes', []):
            continue
        renames[q] = None
for q in sorted(renames):
    old = q.rsplit('.', 1)[1].encode()
    renames[q] = same_length_name(old, taken)

# Every module rewritten: declarations and references whose target is renamed.
for path, (target_path, text, records) in modules.items():
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
    open(target_path, 'wb').write(bytes(out))
print('renamed', len(renames))
