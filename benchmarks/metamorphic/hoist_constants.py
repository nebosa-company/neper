"""Every typed integer literal of a source tree hoisted to a constant (D527, H10).

    python benchmarks/metamorphic/hoist_constants.py COMPILER SRC_DIR OUT_DIR

The metamorphic harness's `constants` transformation (D508) over a whole tree: in
each `.e` file every typed integer literal outside a `const` and a `case` label is
replaced by a module-scope `const` of the same type and value, one per distinct
literal, named to the literal's length so every column holds, the declarations
appended at the end. A compiler built from the result must be the compiler built
from the original, byte for byte: a constant folds into its uses, and the proofs
read a named constant as they read a literal (D527).
"""
import json, os, re, shutil, subprocess, sys

compiler, src_dir, out_dir = sys.argv[1:4]
if os.path.exists(out_dir):
    shutil.rmtree(out_dir)
os.makedirs(out_dir)
LITERAL = re.compile(rb'^([0-9]+)(u8|u16|u32|u64|usize|i8|i16|i32|i64|isize)$')


def hoisted(path):
    p = subprocess.run([compiler, 'tokens', path, '--json'], capture_output=True)
    if p.returncode != 0:
        sys.exit('hoist_constants: tokens of %s failed' % path)
    text = open(path, 'rb').read()
    records = [json.loads(line) for line in p.stdout.decode('utf-8').splitlines()]
    records = [r for r in records if r.get('record') == 'token']
    line_kinds = {}
    for r in records:
        line_kinds.setdefault(r['span']['line'], []).append(r['kind'])
    names = {}
    edits = []
    for r in records:
        if r['kind'] != 'INTEGER':
            continue
        lexeme = text[r['span']['byte_start']:r['span']['byte_end']]
        first = line_kinds[r['span']['line']][0]
        if LITERAL.match(lexeme) and len(lexeme) >= 3 and first not in ('KW_CONST', 'KW_CASE'):
            if lexeme not in names:
                names[lexeme] = b'K' + str(len(names) + 1).encode().rjust(len(lexeme) - 1, b'0')
            edits.append((r['span']['byte_start'], r['span']['byte_end'], names[lexeme]))
    out = bytearray(text)
    for start, end, name in reversed(edits):
        out[start:end] = name
    if out and not out.endswith(b'\n'):
        out += b'\n'
    for lexeme, name in names.items():
        out += b'const ' + name + b': ' + LITERAL.match(lexeme).group(2) + b' = ' + lexeme + b'\n'
    return bytes(out)


for name in sorted(os.listdir(src_dir)):
    source = os.path.join(src_dir, name)
    if not os.path.isfile(source):
        continue
    if name.endswith('.e'):
        open(os.path.join(out_dir, name), 'wb').write(hoisted(source))
    else:
        shutil.copy(source, os.path.join(out_dir, name))
