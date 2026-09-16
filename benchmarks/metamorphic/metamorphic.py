"""Metamorphic tests of the compiler (D438, H10).

    python benchmarks/metamorphic/metamorphic.py COMPILER ROOT ARCH OS OUTDIR FIXTURE_MAIN...

Two transformations that must not change what a program does, applied to each
fixture's root module and checked against the untouched build:

- `comments`: every comment is removed through the lossless token stream, the
  lines and columns kept, so the image -- debug and release, whose line tables
  name the lines -- must be byte-identical to the original's.
- `reorder`: the top-level declarations after the `use` lines are put in reverse
  order; spec section 14 makes module scope order-independent, so the image may
  differ (functions are laid out in declaration order) but the program must exit
  with the same code and write the same bytes to stdout.

Exit 1 on the first fixture whose transformed build differs, with what differed.
"""
import json, os, shutil, subprocess, sys

compiler, root, arch, host_os, outdir = sys.argv[1:6]
fixtures = sys.argv[6:]
os.makedirs(outdir, exist_ok=True)
exe = '.exe' if host_os == 'windows' else ''


def run(argv, cwd=None):
    return subprocess.run(argv, cwd=cwd, capture_output=True)


def build(main, image, release):
    argv = [compiler, 'emit-executable', main, root, arch, host_os, image]
    if release:
        argv.append('--release')
    p = run(argv)
    if p.returncode != 0:
        sys.exit('metamorphic: build of %s failed: %s' % (main, p.stderr.decode('utf-8', 'replace')))
    if host_os != 'windows':
        os.chmod(image, 0o755)
    return open(image, 'rb').read()


def without_comments(main):
    p = run([compiler, 'tokens', main, '--json'])
    if p.returncode != 0:
        sys.exit('metamorphic: tokens of %s failed' % main)
    text = open(main, 'rb').read()
    cuts = []
    for line in p.stdout.decode('utf-8').splitlines():
        record = json.loads(line)
        if record.get('record') != 'token':
            continue
        for trivia in record['leading_trivia']:
            if trivia['kind'] == 'comment':
                cuts.append((trivia['span']['byte_start'], trivia['span']['byte_end']))
    out = bytearray(text)
    for start, end in sorted(cuts, reverse=True):
        del out[start:end]
    return bytes(out)


def reordered(main):
    lines = open(main, 'rb').read().split(b'\n')
    # The `use` lines and what precedes them stay; the rest is split at every line
    # that starts a declaration (column 1, not a comment or blank) and reversed.
    head = 0
    while head < len(lines) and (lines[head].startswith(b'use ') or lines[head].startswith(b'//') or lines[head].strip() == b''):
        head += 1
    blocks, current = [], []
    for line in lines[head:]:
        starts = line[:1] not in (b'', b' ', b'\t', b'}', b'/') and not line.startswith(b'//')
        if starts and current:
            blocks.append(current)
            current = []
        current.append(line)
    if current:
        blocks.append(current)
    blocks.reverse()
    return b'\n'.join(lines[:head] + [l for b in blocks for l in b])


def variant_dir(fixture_dir, name):
    d = os.path.join(outdir, name)
    if os.path.exists(d):
        shutil.rmtree(d)
    shutil.copytree(fixture_dir, d)
    return d


for main in fixtures:
    fixture_dir = os.path.dirname(os.path.dirname(os.path.abspath(main)))
    name = os.path.basename(fixture_dir)
    original = variant_dir(fixture_dir, name + '-original')
    original_main = os.path.join(original, 'src', 'main.e')
    images = {}
    for release in (False, True):
        images[release] = build(original_main, os.path.join(outdir, '%s-original-%d%s' % (name, release, exe)), release)
    # comments: byte-identical images.
    stripped = variant_dir(fixture_dir, name + '-comments')
    stripped_main = os.path.join(stripped, 'src', 'main.e')
    open(stripped_main, 'wb').write(without_comments(original_main))
    for release in (False, True):
        image = build(stripped_main, os.path.join(outdir, '%s-comments-%d%s' % (name, release, exe)), release)
        if image != images[release]:
            sys.exit('metamorphic: %s without comments builds a different %s image' % (name, 'release' if release else 'debug'))
    # reorder: the same behaviour.
    shuffled = variant_dir(fixture_dir, name + '-reorder')
    shuffled_main = os.path.join(shuffled, 'src', 'main.e')
    open(shuffled_main, 'wb').write(reordered(original_main))
    for release in (False, True):
        a = os.path.join(outdir, '%s-original-%d%s' % (name, release, exe))
        b = os.path.join(outdir, '%s-reorder-%d%s' % (name, release, exe))
        build(shuffled_main, b, release)
        ran_a, ran_b = run([a], cwd=outdir), run([b], cwd=outdir)
        if (ran_a.returncode, ran_a.stdout) != (ran_b.returncode, ran_b.stdout):
            sys.exit('metamorphic: %s reordered behaves differently (%d vs %d)' % (name, ran_a.returncode, ran_b.returncode))
    print('metamorphic: %s holds under comments and reorder' % name)
