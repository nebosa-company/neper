"""Differential execution against an independent oracle (D449, H10).

    python benchmarks/differential/differential.py COMPILER ROOT ARCH OS OUTDIR [--cases N] [--seed S]

Builds `tests/selfhost/fixtures/link/differential`, feeds it N random inputs --
printable ASCII, empty to a few kilobytes, the block boundaries of SHA-256 and
SHA-3 among them -- and checks every answer line against Python's `hashlib` and
`base64`, which share no code with the library. Exit 1 on the first difference,
naming the case.
"""
import base64, hashlib, os, random, subprocess, sys

args = sys.argv[1:]
compiler, root, arch, host_os, outdir = args[:5]
cases, seed = 200, 1
rest = args[5:]
while rest:
    flag = rest.pop(0)
    if flag == '--cases':
        cases = int(rest.pop(0))
    elif flag == '--seed':
        seed = int(rest.pop(0))
    else:
        sys.exit('differential: unknown flag %s' % flag)
os.makedirs(outdir, exist_ok=True)
main = os.path.join(root, 'tests', 'selfhost', 'fixtures', 'link', 'differential', 'src', 'main.e')
image = os.path.join(outdir, 'differential' + ('.exe' if host_os == 'windows' else ''))
built = subprocess.run([compiler, 'emit-executable', main, root, arch, host_os, image], capture_output=True, text=True)
if built.returncode != 0:
    sys.exit('differential: the fixture did not build: %s' % (built.stdout + built.stderr))
if host_os != 'windows':
    os.chmod(image, 0o755)

rng = random.Random(seed)
alphabet = ''.join(chr(c) for c in range(32, 127))
inputs = ['', 'a', 'abc', 'x' * 55, 'y' * 56, 'z' * 64, 'w' * 135, 'v' * 136, 'u' * 200]
while len(inputs) < cases:
    inputs.append(''.join(rng.choice(alphabet) for _ in range(rng.randint(0, 3000))))
inputs = [i for i in inputs if i != '']  # an empty line is no case: the program skips it
path = os.path.join(outdir, 'inputs-%d.txt' % seed)
with open(path, 'w', encoding='ascii', newline='\n') as f:
    f.write('\n'.join(inputs) + '\n')
ran = subprocess.run([image, path], capture_output=True, text=True, cwd=outdir)
if ran.returncode != 0:
    sys.exit('differential: the program exited %d: %s' % (ran.returncode, ran.stderr))
lines = ran.stdout.splitlines()
if len(lines) != len(inputs):
    sys.exit('differential: %d answers for %d inputs' % (len(lines), len(inputs)))
for index, (text, line) in enumerate(zip(inputs, lines)):
    data = text.encode('ascii')
    expected = 'sha256:%s sha3:%s b64:%s' % (hashlib.sha256(data).hexdigest(), hashlib.sha3_256(data).hexdigest(), base64.b64encode(data).decode('ascii'))
    if line != expected:
        sys.exit('differential: case %d (%d bytes) differs\n  program: %s\n  oracle:  %s' % (index, len(data), line, expected))
print('differential: %d cases agree with hashlib and base64 (seed %d)' % (len(inputs), seed))
