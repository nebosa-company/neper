# The timed half of the performance gate, paired (D930, H25): two compilers -- the
# baseline and a candidate -- build the same fixed workload in alternation, cold then
# warm, run after run, so whatever else the host is doing lands on both. The report is
# each compiler's distribution and the distribution of the per-run ratio
# candidate / baseline; the gate judges the ratio's median against the budgets of
# docs/m2-baseline.md (cold +10%, warm +15%), which a load the two runs shared cannot
# move the way it moves an absolute time.
#
#   python benchmarks/baseline/paired.py --baseline-compiler OLD --baseline-root ROOT_OLD \
#       --candidate-compiler NEW --candidate-root ROOT_NEW --host windows|linux \
#       [--workloads sc500k,sc1m] [--runs 7] [--jobs N] [--out paired.json] [--fixtures DIR]
#
# Each compiler builds against its own toolchain root, the workloads are the scale
# fixtures benchmarks/scale/generate.py makes with the fixed seed (the same bytes on
# every host), and cold means the workload's `.neper` removed first. The first pair of
# every cell is discarded as the warm-up of the OS file cache. Exit 1 when a median
# ratio exceeds its budget: the number a decision row names.
import argparse, json, os, platform, shutil, statistics, subprocess, sys, time

parser = argparse.ArgumentParser()
parser.add_argument('--baseline-compiler', required=True)
parser.add_argument('--baseline-root', required=True)
parser.add_argument('--candidate-compiler', required=True)
parser.add_argument('--candidate-root', required=True)
parser.add_argument('--host', choices=['windows', 'linux'], required=True)
parser.add_argument('--workloads', default='sc500k,sc1m')
parser.add_argument('--runs', type=int, default=7)
parser.add_argument('--jobs', type=int, default=0)
parser.add_argument('--arena', default='14g')
parser.add_argument('--out', default='paired.json')
parser.add_argument('--fixtures', default=None)
args = parser.parse_args()

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(os.path.dirname(here))
fixtures = os.path.abspath(args.fixtures or os.path.join(repo, 'build', 'baseline-fixtures'))
SCALE = {'sc500k': (500, 500_000), 'sc1m': (1000, 1_000_000), 'sc2m': (2000, 2_000_000)}
BUDGETS = {'cold': 0.10, 'warm': 0.15}
exe = '.exe' if args.host == 'windows' else ''


def workload(name):
    d = os.path.join(fixtures, name)
    if not os.path.exists(os.path.join(d, 'src', 'main.e')):
        modules, lines = SCALE[name]
        subprocess.check_call([sys.executable, os.path.join(repo, 'benchmarks', 'scale', 'generate.py'), d,
                               '--modules', str(modules), '--lines', str(lines), '--seed', '1'])
    return d


def timed(cwd, argv):
    start = time.perf_counter()
    p = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, errors='replace')
    return (time.perf_counter() - start) * 1000.0, p.returncode, (p.stdout + p.stderr)[-300:]


def summary(values):
    s = sorted(values)
    def q(f):
        k = (len(s) - 1) * f
        lo, hi = int(k), min(int(k) + 1, len(s) - 1)
        return s[lo] + (s[hi] - s[lo]) * (k - lo)
    return {'p50': round(q(0.5), 3), 'p95': round(q(0.95), 3), 'min': round(s[0], 3), 'max': round(s[-1], 3), 'runs': len(s)}


compilers = [('baseline', os.path.abspath(args.baseline_compiler), os.path.abspath(args.baseline_root)),
             ('candidate', os.path.abspath(args.candidate_compiler), os.path.abspath(args.candidate_root))]
report = {'schema': 'neper-paired', 'version': 1, 'host': args.host, 'platform': platform.platform(),
          'runs': args.runs, 'jobs': args.jobs or 8, 'arena': args.arena, 'budgets': BUDGETS,
          'compilers': {tag: {'path': path, 'root': root} for tag, path, root in compilers}, 'cells': []}
breaches = 0
for name in args.workloads.split(','):
    cwd = workload(name)
    for mode in ('debug', 'release'):
        cell = {'workload': name, 'mode': mode, 'baseline': {'cold': [], 'warm': []}, 'candidate': {'cold': [], 'warm': []}, 'failed': None}
        for run in range(args.runs + 1):
            # Alternate which compiler goes first, so neither always follows the other.
            order = compilers if run % 2 == 0 else compilers[::-1]
            pair = {}
            for tag, path, root in order:
                out = os.path.join(cwd, f'paired-{tag}-{mode}{exe}')
                argv = [path, 'emit-executable', os.path.join('src', 'main.e'), root, 'x64', args.host, out, '--arena', args.arena, '--incremental'] + (['--release'] if mode == 'release' else []) + (['-j', str(args.jobs)] if args.jobs else [])
                shutil.rmtree(os.path.join(cwd, '.neper'), ignore_errors=True)
                cold, cold_status, cold_tail = timed(cwd, argv)
                warm, warm_status, warm_tail = timed(cwd, argv)
                if cold_status != 0 or warm_status != 0:
                    cell['failed'] = f'{tag}: ' + (cold_tail if cold_status != 0 else warm_tail)
                    break
                pair[tag] = (cold, warm)
            if cell['failed']:
                break
            if run == 0:
                continue
            for tag in ('baseline', 'candidate'):
                cell[tag]['cold'].append(pair[tag][0])
                cell[tag]['warm'].append(pair[tag][1])
        shutil.rmtree(os.path.join(cwd, '.neper'), ignore_errors=True)
        if cell['failed']:
            print(f'{name} {mode}: FAILED {cell["failed"].strip()[-160:]}')
            report['cells'].append(cell)
            continue
        verdicts = []
        for phase in ('cold', 'warm'):
            ratios = [c / b for b, c in zip(cell['baseline'][phase], cell['candidate'][phase])]
            cell[phase] = {'baseline': summary(cell['baseline'][phase]), 'candidate': summary(cell['candidate'][phase]), 'ratio': summary(ratios)}
            median = cell[phase]['ratio']['p50']
            ok = median <= 1.0 + BUDGETS[phase]
            if not ok:
                breaches += 1
            verdicts.append(f"{phase} ratio p50 {median:.3f} [{cell[phase]['ratio']['min']:.3f}..{cell[phase]['ratio']['max']:.3f}] {'ok' if ok else 'BREACH'}")
        report['cells'].append(cell)
        print(f"{name:7} {mode:8} baseline cold {cell['cold']['baseline']['p50']:7.0f} ms warm {cell['warm']['baseline']['p50']:5.0f} | candidate cold {cell['cold']['candidate']['p50']:7.0f} warm {cell['warm']['candidate']['p50']:5.0f} | " + '; '.join(verdicts))
report['breaches'] = breaches
with open(args.out, 'w', encoding='utf-8') as f:
    json.dump(report, f, indent=1)
print(f'paired gate: {breaches} breach(es); wrote {args.out}')
sys.exit(1 if breaches else 0)
