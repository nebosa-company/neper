"""Every local and parameter of a source tree renamed (D528, H10, H17).

    python benchmarks/metamorphic/rename_locals.py COMPILER ROOT SRC_DIR OUT_DIR

The metamorphic harness's `renamed` transformation (D477, D484) over a whole tree:
each `.e` file's locals and parameters take a name of the same length through the
index's `local` and `parameter` symbols and the references that target them, so
every column holds, past keywords and the names the module spells. A compiler
built from the result must be the compiler built from the original, byte for
byte; a reference the index missed is a build that fails, which is how the index's
cap of four thousand references was found (D528).
"""
import json, os, shutil, subprocess, sys, itertools
compiler, root, src_dir, out_dir = sys.argv[1:5]
host_os = sys.argv[5] if len(sys.argv) > 5 else 'windows'
if os.path.exists(out_dir): shutil.rmtree(out_dir)
os.makedirs(out_dir)
KEYWORDS = set('''fn let var ret if else while for in break continue use type error const struct union
enum true false nil ok zero undef extern unreachable shared own try defer switch case match as
and or not import pub mut static comptime test gpu when is do loop target byte'''.split())
def same_length_name(name, taken):
    for times in range(1, 26):
        out = bytearray()
        for ch in name:
            if 97 <= ch <= 122: out.append((ch - 97 + times) % 26 + 97)
            elif 65 <= ch <= 90: out.append((ch - 65 + times) % 26 + 65)
            else: out.append(ch)
        c = bytes(out)
        if c != name and c.decode() not in KEYWORDS and c not in taken:
            taken.add(c); return c
    return name
def renamed(path):
    p = subprocess.run([compiler, 'index-file', path, root, 'x64', host_os, '--json'], capture_output=True)
    if p.returncode != 0: sys.exit('index of %s failed: %s' % (path, p.stdout[:300]))
    text = open(path, 'rb').read()
    records = [json.loads(l) for l in p.stdout.decode('utf-8').splitlines()]
    module = [r for r in records if r.get('record') == 'symbol' and r['kind'] == 'module'][0]['name']
    symbols, spans = {}, []
    tokens = subprocess.run([compiler, 'tokens', path, '--json'], capture_output=True).stdout.decode('utf-8').splitlines()
    taken = set()
    for line in tokens:
        r = json.loads(line)
        if r.get('record') == 'token' and r['kind'] == 'IDENTIFIER': taken.add(text[r['span']['byte_start']:r['span']['byte_end']])
    for r in records:
        if r.get('record') == 'symbol' and r['kind'] in ('local', 'parameter') and r['module'] == module and r.get('selection_span'):
            symbols[r['id']] = r['name'].encode()
            s = r['selection_span']; spans.append((s['byte_start'], s['byte_end'], r['id']))
        if r.get('record') == 'reference' and r.get('target_id') in symbols and r['role'] in ('read', 'write', 'call', 'address'):
            s = r['source_span']
            if text[s['byte_start']:s['byte_end']] == symbols[r['target_id']]: spans.append((s['byte_start'], s['byte_end'], r['target_id']))
    new_names = {sid: same_length_name(name, taken) for sid, name in symbols.items()}
    out = bytearray(text)
    for s, e, sid in sorted(set(spans), reverse=True):
        out[s:e] = new_names[sid]
    return bytes(out), len(symbols)
total = 0
# Every directory under the tree (D550): the library's modules sit in packages.
for dirpath, dirs, files in os.walk(src_dir):
    rel = os.path.relpath(dirpath, src_dir)
    target_dir = os.path.join(out_dir, rel) if rel != '.' else out_dir
    os.makedirs(target_dir, exist_ok=True)
    for name in sorted(files):
        source = os.path.join(dirpath, name)
        # Another target's variant, `os.linux.e` on windows (D544), is not this
        # program's module: it cannot be indexed here and goes over as it is.
        parts = name.split('.')
        other_target = len(parts) == 3 and parts[1] not in (host_os, 'x64')
        if name.endswith('.e') and not other_target:
            b, n = renamed(source); open(os.path.join(target_dir, name), 'wb').write(b); total += n
        else: shutil.copy(source, os.path.join(target_dir, name))
print('renamed', total)
