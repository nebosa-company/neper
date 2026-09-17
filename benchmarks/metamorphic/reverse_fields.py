"""Every struct of a source tree with its fields reversed (D530, H10).

    python benchmarks/metamorphic/reverse_fields.py COMPILER SRC_DIR OUT_DIR

The metamorphic harness's `fields` transformation (D477) over a whole tree: in each
`.e` file every `struct { ... }` has its fields in reverse order, split at the commas
of depth zero through the token stream, the line breaks around a field left where
they are. The layout of every struct changes, so a compiler built from the result is
another image -- but it must build the original sources to the stable stage byte for
byte: nothing in the compiler reads a struct by its layout.
"""
import json, os, shutil, subprocess, sys

compiler, src_dir, out_dir = sys.argv[1:4]
if os.path.exists(out_dir):
    shutil.rmtree(out_dir)
os.makedirs(out_dir)


def reversed_fields(path):
    text = open(path, 'rb').read()
    # A module with foreign declarations (D551) lays its structs out for the other
    # side -- `os.windows.e`'s OVERLAPPED, `os.linux.e`'s sockaddr -- and reversing
    # them is not a turn but a different program: it goes over as it is. So does
    # `e.mem`: its `Arena` is the runtime's, laid out by the embedded runtime source
    # (D149) before any program is compiled, and a program reading it the other way
    # round finds its arena exhausted at the first allocation.
    foreign = b'\nextern fn' in text or b'\n@import' in text or b'\n@export' in text or text.startswith(b'extern fn') or text.startswith(b'@import')
    if foreign or os.path.basename(path) == 'mem.e':
        return text, 0
    p = subprocess.run([compiler, 'tokens', path, '--json'], capture_output=True)
    if p.returncode != 0:
        sys.exit('reverse_fields: tokens of %s failed' % path)
    toks = []
    for line in p.stdout.decode('utf-8').splitlines():
        record = json.loads(line)
        if record.get('record') == 'token':
            toks.append((record['span']['byte_start'], record['span']['byte_end'], record['kind']))
    edits = []
    i = 0
    while i + 1 < len(toks):
        if toks[i][2] != 'KW_STRUCT' or text[toks[i + 1][0]:toks[i + 1][1]] != b'{':
            i += 1
            continue
        j = i + 2
        depth = 0
        fields, start = [], j
        while j < len(toks):
            sp = text[toks[j][0]:toks[j][1]]
            if sp in (b'{', b'[', b'('):
                depth += 1
            elif sp in (b'}', b']', b')'):
                if depth == 0:
                    break
                depth -= 1
            elif sp == b',' and depth == 0:
                fields.append((start, j))
                start = j + 1
            j += 1
        if start < j:
            fields.append((start, j))
        trimmed = []
        for a, b in fields:
            while a < b and toks[a][2] == 'NEWLINE':
                a += 1
            while b > a and toks[b - 1][2] == 'NEWLINE':
                b -= 1
            if a < b:
                trimmed.append((a, b))
        fields = trimmed
        if len(fields) > 1:
            spans = [(toks[a][0], toks[b - 1][1]) for a, b in fields]
            texts = [text[s:e] for s, e in spans]
            for (s, e), new in zip(spans, reversed(texts)):
                edits.append((s, e, new))
        i = j + 1
    out = bytearray(text)
    for s, e, new in sorted(edits, reverse=True):
        out[s:e] = new
    return bytes(out), len(edits)


total = 0
# Every directory under the tree (D551): the library's modules sit in packages.
for dirpath, dirs, files in os.walk(src_dir):
    rel = os.path.relpath(dirpath, src_dir)
    target_dir = os.path.join(out_dir, rel) if rel != '.' else out_dir
    os.makedirs(target_dir, exist_ok=True)
    for name in sorted(files):
        source = os.path.join(dirpath, name)
        if name.endswith('.e'):
            text, count = reversed_fields(source)
            open(os.path.join(target_dir, name), 'wb').write(text)
            total += count
        else:
            shutil.copy(source, os.path.join(target_dir, name))
print('fields moved', total)
