# The M2 baseline measurement (D338, M2.5 stage A): the compiler's cold and warm build
# time, phase split, peak memory and image size over the fixed CPU workloads, as
# distributions, into a JSON document that the budgets in docs/m2-baseline.md are set
# from and later revisions are compared against.
#
#   python benchmarks/baseline/measure.py --compiler PATH --repo ROOT --host windows|linux \
#       [--out baseline.json] [--runs 5] [--fixtures DIR] [--workloads compiler,sc500k,sc1m,sc2m] [--jobs N]
#
# `compiler` is a self-hosted release build of the revision under measurement (a
# bootstrap-built one runs its workers inline and measures something else). The scale
# fixtures are generated into --fixtures (default build/baseline-fixtures) by
# benchmarks/scale/generate.py with the fixed seed when they are missing, so the
# workloads are the same bytes on every host and every run. Cold means the workload's
# `.neper` directory removed before the build; warm means the same build again with
# nothing changed. Both are with a warm OS file cache: the first run of each cell is
# discarded, and the reported runs follow it. Every command is recorded in the output.
import argparse, json, os, platform, re, shutil, statistics, subprocess, sys, time

parser = argparse.ArgumentParser()
parser.add_argument('--compiler', required=True)
parser.add_argument('--repo', required=True)
parser.add_argument('--host', choices=['windows', 'linux'], required=True)
parser.add_argument('--out', default='baseline.json')
parser.add_argument('--runs', type=int, default=5)
parser.add_argument('--fixtures', default=None)
parser.add_argument('--workloads', default='compiler,sc500k,sc1m,sc2m')
parser.add_argument('--arena', default='14g')
# `--jobs N` caps the workers (D331), for a cell a host cannot hold at eight: recorded.
parser.add_argument('--jobs', type=int, default=0)
args = parser.parse_args()

repo = os.path.abspath(args.repo)
fixtures = os.path.abspath(args.fixtures or os.path.join(repo, 'build', 'baseline-fixtures'))
os.makedirs(fixtures, exist_ok=True)
SCALE = {'sc500k': (500, 500_000), 'sc1m': (1000, 1_000_000), 'sc2m': (2000, 2_000_000)}
exe = '.exe' if args.host == 'windows' else ''

def workload_dir(name):
    if name == 'compiler':
        return repo, os.path.join('src', 'main.e')
    d = os.path.join(fixtures, name)
    if not os.path.exists(os.path.join(d, 'src', 'main.e')):
        modules, lines = SCALE[name]
        subprocess.check_call([sys.executable, os.path.join(repo, 'benchmarks', 'scale', 'generate.py'), d,
                               '--modules', str(modules), '--lines', str(lines), '--seed', '1'])
    return d, os.path.join('src', 'main.e')

def run(cwd, argv):
    start = time.perf_counter()
    p = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, errors='replace')
    return (time.perf_counter() - start) * 1000.0, p

def phases(text):
    out = {}
    for m in re.finditer(r'^time ([a-z ]+): (\d+) ms', text, re.M):
        out[m.group(1)] = int(m.group(2))
    return out

# The arena's high-water mark, the last `arena N MB` of the `--time` lines: what the
# build committed, which on Windows is what the commit charge has to hold (D306).
def arena_mb(text):
    found = re.findall(r', arena (\d+) MB', text)
    return int(found[-1]) if found else None

def stat_row(text, name):
    m = re.search(r'^' + re.escape(name) + r' \| ([\d\']+)', text, re.M)
    return int(m.group(1).replace("'", '')) if m else None

def percentiles(values):
    s = sorted(values)
    def p(q):
        k = (len(s) - 1) * q
        f, c = int(k), min(int(k) + 1, len(s) - 1)
        return s[f] + (s[c] - s[f]) * (k - f)
    return {'p50': round(p(0.5), 1), 'p95': round(p(0.95), 1), 'min': round(s[0], 1), 'max': round(s[-1], 1), 'runs': len(s)}

report = {
    'schema': 'neper-baseline', 'version': 1, 'host': args.host,
    'machine': platform.machine(), 'platform': platform.platform(), 'cpu': platform.processor(),
    'compiler': os.path.abspath(args.compiler), 'runs': args.runs, 'arena': args.arena, 'jobs': args.jobs or 8,
    'revision': subprocess.run(['git', '-C', repo, 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip(),
    'cells': [],
}
for name in args.workloads.split(','):
    cwd, operand = workload_dir(name)
    lines = sum(1 for f in os.listdir(os.path.join(cwd, 'src')) if f.endswith('.e') for _ in open(os.path.join(cwd, 'src', f), encoding='utf-8', errors='replace'))
    for mode in ('debug', 'release'):
        flag = ['--release'] if mode == 'release' else []
        out = os.path.join(cwd, f'baseline-{mode}{exe}')
        base = [args.compiler, 'emit-executable', operand, repo, 'x64', args.host, out, '--arena', args.arena, '--incremental', '--time'] + flag + (['-j', str(args.jobs)] if args.jobs else [])
        cell = {'workload': name, 'lines': lines, 'mode': mode, 'command': ' '.join(base), 'cold_ms': [], 'warm_ms': [], 'cold_phases': [], 'warm_phases': [], 'arena_mb': None, 'retries': 0}
        failed = None
        i = 0
        while i < args.runs + 1:
            shutil.rmtree(os.path.join(cwd, '.neper'), ignore_errors=True)
            ms, p = run(cwd, base)
            text = p.stdout + p.stderr
            if p.returncode == 0:
                ms2, p2 = run(cwd, base)
                text2 = p2.stdout + p2.stderr
            # A build that ran out of memory is the machine's commit charge, not the
            # workload (D306): tried again up to three times, and counted.
            if p.returncode != 0 or p2.returncode != 0:
                failed = (text if p.returncode != 0 else text2)[-400:]
                if 'Exhausted' in failed and cell['retries'] < 3:
                    cell['retries'] += 1
                    failed = None
                    continue
                break
            if i:
                cell['cold_ms'].append(ms); cell['cold_phases'].append(phases(text))
                cell['warm_ms'].append(ms2); cell['warm_phases'].append(phases(text2))
                cell['arena_mb'] = max(cell['arena_mb'] or 0, arena_mb(text) or 0)
            i += 1
        if failed:
            cell['failed'] = failed
            report['cells'].append(cell)
            print(f'{name} {mode}: FAILED {failed.strip()[-120:]}', file=sys.stderr)
            continue
        # One measured cold build with --stats for the peak, the size and the counts.
        text = ''
        for attempt in range(4):
            shutil.rmtree(os.path.join(cwd, '.neper'), ignore_errors=True)
            ms, p = run(cwd, base + ['--stats'])
            text = p.stdout + p.stderr
            if p.returncode == 0: break
            cell['retries'] += 1
        cell['peak_mb'] = stat_row(text, 'compiler peak working set')
        cell['image_bytes'] = stat_row(text, 'executable size')
        cell['functions'] = stat_row(text, 'functions')
        cell['cold'] = percentiles(cell['cold_ms'])
        cell['warm'] = percentiles(cell['warm_ms'])
        cell['cold_phase_p50'] = {k: statistics.median(ph.get(k, 0) for ph in cell['cold_phases']) for k in cell['cold_phases'][0]}
        cell['warm_phase_p50'] = {k: statistics.median(ph.get(k, 0) for ph in cell['warm_phases']) for k in cell['warm_phases'][0]}
        report['cells'].append(cell)
        print(f"{name:9} {mode:8} cold p50 {cell['cold']['p50']:8.0f} p95 {cell['cold']['p95']:8.0f} | warm p50 {cell['warm']['p50']:6.0f} p95 {cell['warm']['p95']:6.0f} | peak {cell['peak_mb']} MB | arena {cell['arena_mb']} MB | image {cell['image_bytes']} B | retries {cell['retries']}")
        try:
            os.remove(out)
        except OSError:
            pass
with open(args.out, 'w', encoding='utf-8') as f:
    json.dump(report, f, indent=1)
print('wrote', args.out)
