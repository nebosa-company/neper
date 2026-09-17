"""Every comment of a source tree blanked (D526, H10).

    python benchmarks/metamorphic/strip_comments.py COMPILER SRC_DIR OUT_DIR

Each `.e` file under SRC_DIR is copied to OUT_DIR with every comment's bytes -- read
from the lossless token stream's trivia -- replaced by spaces, so every line and
column holds; every other file is copied as it is. A compiler built from the result
must be the compiler built from the original, byte for byte: comments are trivia, and
the line tables and trap records carry lines and columns that the blanks keep.
"""
import json, os, shutil, subprocess, sys

compiler, src_dir, out_dir = sys.argv[1:4]
if os.path.exists(out_dir):
    shutil.rmtree(out_dir)
os.makedirs(out_dir)


def blanked(path):
    p = subprocess.run([compiler, 'tokens', path, '--json'], capture_output=True)
    if p.returncode != 0:
        sys.exit('strip_comments: tokens of %s failed' % path)
    text = bytearray(open(path, 'rb').read())
    for line in p.stdout.decode('utf-8').splitlines():
        record = json.loads(line)
        if record.get('record') != 'token':
            continue
        for trivia in record.get('leading_trivia', []):
            if trivia['kind'] == 'comment':
                start, end = trivia['span']['byte_start'], trivia['span']['byte_end']
                text[start:end] = b' ' * (end - start)
    return bytes(text)


for name in sorted(os.listdir(src_dir)):
    source = os.path.join(src_dir, name)
    if not os.path.isfile(source):
        continue
    if name.endswith('.e'):
        open(os.path.join(out_dir, name), 'wb').write(blanked(source))
    else:
        shutil.copy(source, os.path.join(out_dir, name))
