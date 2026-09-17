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
    p = subprocess.run([compiler, 'tokens', path, '--json'], capture_output=True)
    if p.returncode != 0:
        sys.exit('reverse_fields: tokens of %s failed' % path)
    text = open(path, 'rb').read()
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
for name in sorted(os.listdir(src_dir)):
    source = os.path.join(src_dir, name)
    if not os.path.isfile(source):
        continue
    if name.endswith('.e'):
        text, count = reversed_fields(source)
        open(os.path.join(out_dir, name), 'wb').write(text)
        total += count
    else:
        shutil.copy(source, os.path.join(out_dir, name))
print('fields moved', total)
