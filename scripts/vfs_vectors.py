"""Generate tests/selfhost/fixtures/link/fs_vfs/src/main.e (L119, D2522).

The oracle is the real filesystem: random sequences of write, mkdir, remove, read, stat
and list over a small name universe (with path spellings such as `a//b`, `./a` and
`x/../a`) are applied to a temporary directory by Python's `os`, and each step's outcome
(success or failure, the bytes read, the kind and size, the sorted names) is recorded.
The fixture replays every trace on Mem, on Sub over Mem, on Overlay over an empty lower,
and on Host over a real directory through e.fs, and requires the recorded outcome.  Path
cleaning is checked against `posixpath.normpath`.
"""
import os
import posixpath
import random
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests/selfhost/fixtures/link/fs_vfs/src/main.e'


def esc(data):
    if isinstance(data, str):
        data = data.encode('latin-1')
    out = []
    for b in data:
        if 48 <= b <= 57 or 65 <= b <= 90 or 97 <= b <= 122 or b in b'/._-':
            out.append(chr(b))
        else:
            out.append('\\x%02x' % b)
    return '"' + ''.join(out) + '"'


NAMES = ['a', 'b', 'c', 'dd', 'e.txt']


def universe():
    paths = ['/']
    for n1 in NAMES:
        paths.append('/' + n1)
        for n2 in NAMES:
            paths.append('/%s/%s' % (n1, n2))
            for n3 in ('f', 'g'):
                paths.append('/%s/%s/%s' % (n1, n2, n3))
    return paths


def spell(rng, path):
    """A lexically equivalent spelling of an absolute path."""
    if path == '/':
        return rng.choice(['/', '', '.', '//', '/./', 'x/..', '/a/..'])
    parts = path.strip('/').split('/')
    kind = rng.randrange(8)
    if kind == 0:
        return '/'.join(parts)
    if kind == 1:
        return '/' + '//'.join(parts)
    if kind == 2:
        return '/./' + '/./'.join(parts) + '/'
    if kind == 3:
        return '/zz/../' + '/'.join(parts)
    if kind == 4:
        return '/' + '/'.join(parts[:-1] + ['tmp', '..', parts[-1]])
    return '/' + '/'.join(parts)


class Real:
    def __init__(self):
        self.root = tempfile.mkdtemp(prefix='vfs_oracle_')

    def real(self, path):
        path = posixpath.normpath(path)
        return os.path.join(self.root, path.lstrip('/')) if path != '/' else self.root

    def apply(self, op, path, data):
        real = self.real(path)
        try:
            if op == 0:
                with open(real, 'wb') as f:
                    f.write(data)
                return True, ''
            if op == 1:
                os.mkdir(real)
                return True, ''
            if op == 2:
                if os.path.isdir(real):
                    os.rmdir(real)
                else:
                    os.remove(real)
                return True, ''
            if op == 3:
                with open(real, 'rb') as f:
                    return True, f.read()
            if op == 4:
                if os.path.isdir(real):
                    return True, ('D', 0)
                return True, ('F', os.path.getsize(real))
            if op == 5:
                names = []
                for name in sorted(os.listdir(real)):
                    names.append(name + (':D' if os.path.isdir(os.path.join(real, name)) else ':F'))
                return True, ','.join(names)
        except OSError:
            return False, ''
        raise AssertionError(op)

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)


def trace(seed, steps, number):
    rng = random.Random(seed)
    paths = universe()
    real = Real()
    lines = []
    ok_count = fail_count = 0
    for index in range(steps):
        op = rng.choices([0, 1, 2, 3, 4, 5], weights=[30, 22, 12, 12, 12, 12])[0]
        path = rng.choice(paths)
        if rng.random() < 0.8:
            # aim at a place whose parent exists, so most steps do something
            dirs = ['/']
            for base, names, _ in os.walk(real.root):
                for name in names:
                    dirs.append('/' + os.path.relpath(os.path.join(base, name), real.root).replace(os.sep, '/'))
            parent = rng.choice(dirs)
            leaf = rng.choice(NAMES + ['f', 'g'])
            path = (parent.rstrip('/') + '/' + leaf)
            if rng.random() < 0.35:
                files = []
                for base, _, fnames in os.walk(real.root):
                    for name in fnames:
                        files.append('/' + os.path.relpath(os.path.join(base, name), real.root).replace(os.sep, '/'))
                if files:
                    path = rng.choice(files)
        if op == 2 and path == '/':
            path = '/a'
        data = bytes(rng.choice(b'abcdefghij XYZ\n\x00\xff') for _ in range(rng.choice([0, 1, 5, 17, 40]))) if op == 0 else b''
        succeeded, result = real.apply(op, path, data)
        if succeeded:
            ok_count += 1
        else:
            fail_count += 1
        spelled = spell(rng, path)
        want = ''
        size = 0
        if succeeded and op == 3:
            want = result
        elif succeeded and op == 4:
            want = result[0]
            size = result[1]
        elif succeeded and op == 5:
            want = result
        lines.append('    if !step(a, v, %du8, %s, %s, %s, %s, %dusize) { ret %di32 }' % (
            op, esc(spelled), esc(data), 'true' if succeeded else 'false', esc(want), size, index + 1))
    real.close()
    return ('fn trace_%d(a: *mem.Arena, v: *vfs.Vfs) -> i32 {\n' % number + '\n'.join(lines) + '\n    ret 0i32\n}\n',
            ok_count, fail_count)


functions = []
for number, seed in enumerate((11, 22, 33, 44), 1):
    code, ok_count, fail_count = trace(seed, 450, number)
    functions.append(code)
    print('trace', number, 'ok', ok_count, 'failed', fail_count)

# --- path cleaning against posixpath.normpath (and the escapes it would clamp)
clean_lines = []
rng = random.Random(7)
samples = ['', '/', '.', '..', '/..', 'a', '/a', 'a/', '//a///b//', '/a/./b/.', '/a/b/../c', 'a/b/../../c', 'a/../..',
           '/a/b/c/../../..', '/a/b/c/../../../..', './././', '/..a/b', '/a/..b/c', '/a/b..', 'a\\b', '/.hidden/./x']
for _ in range(60):
    parts = [rng.choice(['a', 'b', '.', '..', '', 'cc', '...']) for _ in range(rng.randrange(1, 8))]
    samples.append(rng.choice(['', '/']) + '/'.join(parts))
for sample in samples:
    depth = 0
    escaped = False
    for seg in sample.split('/'):
        if seg in ('', '.'):
            continue
        if seg == '..':
            if depth == 0:
                escaped = True
                break
            depth -= 1
        else:
            depth += 1
    if escaped:
        clean_lines.append('    if !clean_invalid(a, %s) { ret %di32 }' % (esc(sample), len(clean_lines) + 1))
    else:
        norm = posixpath.normpath('/' + sample.lstrip('/'))  # normpath keeps a leading '//'
        clean_lines.append('    if !clean_is(a, %s, %s) { ret %di32 }' % (esc(sample), esc(norm), len(clean_lines) + 1))
functions.append('fn clean_cases(a: *mem.Arena) -> i32 {\n' + '\n'.join(clean_lines) + '\n    ret 0i32\n}\n')

template = (ROOT / 'scripts' / 'vfs_fixture_head.e').read_text(encoding='utf-8')
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(template.replace('@@TRACES@@', '\n'.join(functions)), encoding='utf-8', newline='\n')
print('wrote', OUT, 'clean cases', len(clean_lines))
