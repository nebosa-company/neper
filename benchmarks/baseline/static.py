# The deterministic half of the performance gate (D506, H25): the image and the
# workers' arena high-water of a build of the fixed sc500k workload, in both modes,
# as a measurement document `gate.py` judges against `results/static-<host>.json`.
#
#   python benchmarks/baseline/static.py --compiler PATH --repo ROOT --host windows|linux \
#       --out static.json [--fixtures DIR] [--jobs 8]
#
# Unlike measure.py's times, these two numbers are the same on every run of the same
# compiler over the same bytes -- sc500k is generated from the fixed seed, and the
# image and the arenas are functions of the program and the worker count (D331), not
# of the machine's load -- so the suites can hold a revision to them exactly, with no
# distribution to sample. `worker_arenas_reached_mb` and `executable_size_bytes` are
# read from the `--stats --json` record (D476). A breach is what a decision row names.
import argparse, json, os, subprocess, sys

parser = argparse.ArgumentParser()
parser.add_argument('--compiler', required=True)
parser.add_argument('--repo', required=True)
parser.add_argument('--host', choices=['windows', 'linux'], required=True)
parser.add_argument('--out', required=True)
parser.add_argument('--fixtures', default=None)
parser.add_argument('--jobs', type=int, default=8)
args = parser.parse_args()

repo = os.path.abspath(args.repo)
fixtures = os.path.abspath(args.fixtures or os.path.join(repo, 'build', 'baseline-fixtures'))
os.makedirs(fixtures, exist_ok=True)
workload = os.path.join(fixtures, 'sc500k')
if not os.path.exists(os.path.join(workload, 'src', 'main.e')):
    subprocess.check_call([sys.executable, os.path.join(repo, 'benchmarks', 'scale', 'generate.py'), workload,
                           '--modules', '500', '--lines', '500000', '--seed', '1'], stdout=subprocess.DEVNULL)
try:
    revision = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=repo, capture_output=True, text=True).stdout.strip()
except OSError:
    revision = '?'

cells = []
for mode in ('debug', 'release'):
    out = os.path.join(workload, 'static-%s%s' % (mode, '.exe' if args.host == 'windows' else ''))
    argv = [os.path.abspath(args.compiler), 'emit-executable', os.path.join(workload, 'src', 'main.e'), repo, 'x64', args.host, out,
            '-j', str(args.jobs), '--stats', '--json']
    if mode == 'release':
        argv.insert(7, '--release')
    p = subprocess.run(argv, cwd=workload, capture_output=True, text=True, errors='replace')
    stats = None
    for line in p.stdout.splitlines():
        if line.startswith('{"record":"stats"'):
            stats = json.loads(line)
    if p.returncode != 0 or stats is None:
        print('static: the %s build of sc500k failed (exit %d)' % (mode, p.returncode))
        print(p.stdout[-2000:])
        print(p.stderr[-2000:])
        sys.exit(2)
    cells.append({'workload': 'sc500k', 'mode': mode, 'command': ' '.join(argv),
                  'arena_mb': stats['worker_arenas_reached_mb'], 'image_bytes': stats['executable_size_bytes']})
    print('static: sc500k %-7s arena %d MB image %d B' % (mode, stats['worker_arenas_reached_mb'], stats['executable_size_bytes']))

doc = {'schema': 'neper-baseline', 'version': 1, 'static': True, 'host': args.host, 'jobs': args.jobs,
       'compiler': args.compiler, 'revision': revision, 'cells': cells}
with open(args.out, 'w', encoding='utf-8') as f:
    json.dump(doc, f, indent=1)
    f.write('\n')
