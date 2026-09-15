# Mutation fuzzing of the compiler's front end and artifact readers (D341, H10/H24):
# arbitrary bytes and mutated fixtures must never crash or hang the compiler; a
# refused input is a diagnostic and an exit code, and nothing else.
#
#   python benchmarks/fuzz/fuzz.py --compiler PATH --repo ROOT [--seed 1] [--iterations 2000]
#       [--what source,artifact] [--timeout 20] [--out build/fuzz]
#
# Sources: every `.e` under tests/selfhost/fixtures and tests/conformance is a seed;
# a mutation flips, deletes, duplicates or inserts bytes, splices a slice of another
# seed, or truncates, and the result is checked with `check-file`. Artifacts: the
# `.em` files a build leaves under `.neper/` of a fixture are mutated the same way
# and read with `validate-em`. A run that exits above 2, is killed by a signal, or
# outruns the timeout is a finding; its input is kept under --out with the command.
import argparse, os, random, shutil, subprocess, sys, time

parser = argparse.ArgumentParser()
parser.add_argument('--compiler', required=True)
parser.add_argument('--repo', required=True)
parser.add_argument('--seed', type=int, default=1)
parser.add_argument('--iterations', type=int, default=2000)
parser.add_argument('--what', default='source,artifact,deep')
parser.add_argument('--timeout', type=float, default=20.0)
parser.add_argument('--out', default=None)
parser.add_argument('--host', default='windows')
args = parser.parse_args()
repo = os.path.abspath(args.repo)
out = os.path.abspath(args.out or os.path.join(repo, 'build', 'fuzz'))
os.makedirs(out, exist_ok=True)
rng = random.Random(args.seed)

def seeds(suffix, roots):
    found = []
    for root in roots:
        for d, _, files in os.walk(root):
            for f in files:
                if f.endswith(suffix):
                    p = os.path.join(d, f)
                    if os.path.getsize(p) < 200_000:
                        found.append(p)
    return found

def mutate(data, others):
    data = bytearray(data)
    for _ in range(rng.randint(1, 6)):
        kind = rng.randint(0, 6)
        if not data:
            data.extend(b'x')
        at = rng.randrange(len(data))
        if kind == 0:
            data[at] = rng.randrange(256)
        elif kind == 1:
            del data[at:at + rng.randint(1, 64)]
        elif kind == 2:
            data[at:at] = data[at:at + rng.randint(1, 64)]
        elif kind == 3:
            data[at:at] = bytes(rng.randrange(256) for _ in range(rng.randint(1, 16)))
        elif kind == 4 and others:
            other = rng.choice(others)
            s = rng.randrange(max(len(other), 1))
            data[at:at] = other[s:s + rng.randint(1, 200)]
        elif kind == 5:
            del data[at:]
        else:
            data[at] = rng.choice(b'{}()[]",\\\n\t\x00\xff.:;')
    return bytes(data)

# The artifact's checksum (CRC-32C over the file with the field at 28 zeroed) is
# recomputed after a mutation, so the readers past the checksum see the mutated bytes;
# one mutation in four leaves it wrong, so the checksum's own rejection is covered too.
CRC_TABLE = []
for entry in range(256):
    crc = entry
    for _ in range(8):
        crc = (crc >> 1) ^ 0x82F63B78 if crc & 1 else crc >> 1
    CRC_TABLE.append(crc)

def crc32c_zeroed(data, zero_at, zero_count):
    crc = 0xFFFFFFFF
    for i, b in enumerate(data):
        if zero_at <= i < zero_at + zero_count: b = 0
        crc = CRC_TABLE[(crc ^ b) & 255] ^ (crc >> 8)
    return crc ^ 0xFFFFFFFF

def fix_checksum(data):
    if len(data) < 32 or rng.random() < 0.25: return data
    crc = crc32c_zeroed(data, 28, 4)
    return data[:28] + crc.to_bytes(4, 'little') + data[32:]

findings = 0
started = time.time()
what = args.what.split(',')
work = os.path.join(out, 'work')
os.makedirs(work, exist_ok=True)
if 'source' in what:
    sources = seeds('.e', [os.path.join(repo, 'tests', 'selfhost', 'fixtures'), os.path.join(repo, 'tests', 'conformance')])
    texts = [open(p, 'rb').read() for p in sources]
    for i in range(args.iterations):
        base = rng.randrange(len(texts))
        data = mutate(texts[base], texts) if rng.random() < 0.97 else bytes(rng.randrange(256) for _ in range(rng.randint(0, 4000)))
        path = os.path.join(work, 'fuzz_source.e')
        with open(path, 'wb') as f:
            f.write(data)
        cmd = [args.compiler, 'check-file', path, repo, 'x64', args.host]
        try:
            p = subprocess.run(cmd, capture_output=True, timeout=args.timeout)
            code = p.returncode
            reason = None if 0 <= code <= 2 else f'exit {code}'
        except subprocess.TimeoutExpired:
            reason = f'timeout {args.timeout}s'
        if reason:
            findings += 1
            keep = os.path.join(out, f'source_{findings:03}.e')
            shutil.copyfile(path, keep)
            with open(keep + '.txt', 'w') as f:
                f.write(f'{reason}\nseed {sources[base]}\n{" ".join(cmd)}\n')
            print(f'FINDING {findings}: {reason} from {os.path.relpath(sources[base], repo)} -> {keep}')
        if (i + 1) % 200 == 0:
            print(f'source {i + 1}/{args.iterations}, {findings} findings, {time.time() - started:.0f} s', flush=True)
if 'artifact' in what:
    # A fixture built once so its artifacts exist; the compiler's own are the largest seeds.
    fixture = os.path.join(repo, 'tests', 'selfhost', 'fixtures', 'link', 'generic_instances')
    exe = os.path.join(work, 'seed.exe' if args.host == 'windows' else 'seed')
    subprocess.run([args.compiler, 'emit-executable', os.path.join(fixture, 'src', 'main.e'), repo, 'x64', args.host, exe, '--incremental'], capture_output=True)
    artifacts = seeds('.em', [os.path.join(fixture, '.neper'), os.path.join(repo, '.neper')])
    if not artifacts:
        print('no artifacts to mutate', file=sys.stderr)
    blobs = [open(p, 'rb').read() for p in artifacts]
    for i in range(args.iterations):
        base = rng.randrange(len(blobs))
        data = mutate(blobs[base], blobs) if rng.random() < 0.97 else bytes(rng.randrange(256) for _ in range(rng.randint(0, 4000)))
        data = fix_checksum(data)
        path = os.path.join(work, 'fuzz_artifact.em')
        with open(path, 'wb') as f:
            f.write(data)
        # Validated, then linked in the place of the artifact it came from, so every
        # reader the link runs sees it: the checksum, the sections, the string table,
        # the functions, the relocations, the rows.
        set_paths = [p for p in artifacts if os.path.dirname(p) == os.path.dirname(artifacts[base])]
        linked = [path if p == artifacts[base] else p for p in sorted(set_paths, key=lambda p: (not p.startswith(os.path.join(os.path.dirname(p), 'main')), p))]
        reason = None
        for cmd in ([args.compiler, 'validate-em', path], [args.compiler, 'link-em', os.path.join(work, 'fuzz_link' + ('.exe' if args.host == 'windows' else '')), *linked]):
            try:
                p = subprocess.run(cmd, capture_output=True, timeout=args.timeout)
                code = p.returncode
                if not (0 <= code <= 2):
                    reason = f'exit {code}'
                    break
            except subprocess.TimeoutExpired:
                reason = f'timeout {args.timeout}s'
                break
        if reason:
            findings += 1
            keep = os.path.join(out, f'artifact_{findings:03}.em')
            shutil.copyfile(path, keep)
            with open(keep + '.txt', 'w') as f:
                f.write(f'{reason}\nseed {artifacts[base]}\n{" ".join(cmd)}\n')
            print(f'FINDING {findings}: {reason} from {os.path.relpath(artifacts[base], repo)} -> {keep}')
        if (i + 1) % 200 == 0:
            print(f'artifact {i + 1}/{args.iterations}, {findings} findings, {time.time() - started:.0f} s', flush=True)
if 'deep' in what:
    # The bounded constructs (D341): twenty thousand levels of each must be refused with
    # a diagnostic, not a stack overflow, in a check and in a full build of both modes.
    n = 20000
    NL = chr(10)
    deep = {
        'parens': 'fn main() -> err {' + NL + '    let x = ' + '(' * n + '1i32' + ')' * n + NL + '    ret ok' + NL + '}' + NL,
        'calls': 'fn f(x: i32) -> i32 { ret x }' + NL + 'fn main() -> err {' + NL + '    let x = ' + 'f(' * n + '1i32' + ')' * n + NL + '    ret ok' + NL + '}' + NL,
        'blocks': 'fn main() -> err {' + NL + ('    if true {' + NL) * n + '    ret ok' + NL + ('    }' + NL) * n + '}' + NL,
        'chain': 'fn main() -> err {' + NL + '    let x = 1i32' + ' + 1i32' * n + NL + '    ret ok' + NL + '}' + NL,
        'prefix': 'fn main() -> err {' + NL + '    let x = ' + '-' * n + '1i32' + NL + '    ret ok' + NL + '}' + NL,
        'pointers': 'type T = ' + '*' * n + 'i32' + NL + 'fn main() -> err {' + NL + '    ret ok' + NL + '}' + NL,
    }
    for name, text in deep.items():
        path = os.path.join(work, f'deep_{name}.e')
        with open(path, 'w', newline='') as f:
            f.write(text)
        for cmd in ([args.compiler, 'check-file', path, repo, 'x64', args.host],
                    [args.compiler, 'emit-executable', path, repo, 'x64', args.host, os.path.join(work, 'deep' + ('.exe' if args.host == 'windows' else ''))],
                    [args.compiler, 'emit-executable', path, repo, 'x64', args.host, os.path.join(work, 'deep' + ('.exe' if args.host == 'windows' else '')), '--release']):
            try:
                p = subprocess.run(cmd, capture_output=True, timeout=args.timeout)
                reason = None if 0 <= p.returncode <= 2 else f'exit {p.returncode}'
            except subprocess.TimeoutExpired:
                reason = f'timeout {args.timeout}s'
            if reason:
                findings += 1
                print(f'FINDING {findings}: {reason} on deep {name}: {" ".join(cmd)}')
                break
    print(f'deep: {len(deep)} constructs, {findings} findings, {time.time() - started:.0f} s')
print(f'done: {findings} findings in {time.time() - started:.0f} s')
sys.exit(1 if findings else 0)
