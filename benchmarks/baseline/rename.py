# H25's rename workflow (D941): a feature M2 did not have (`plan-rename-file`, D376), so
# its workload and budget are frozen here before any candidate is tuned against them.
#
#   python benchmarks/baseline/rename.py --compiler NEW --root ROOT --host windows|linux \
#       [--workloads sc500k,sc1m] [--runs 7] [--out rename.json] [--fixtures DIR]
#       [--pin results/rename-<host>.json | --judge results/rename-<host>.json]
#
# The workload: the scale fixtures (the same bytes on every host), and in each the most
# used function of the middle module renamed to `renamed_<name>` from inside the
# project, operand `src/main.e`. One run, timed step by step, on a fresh copy of the
# sources: the query (`uses-file`), the plan (`plan-rename-file`), the apply
# (`apply-plan`) and the check (a build of the renamed copy). Then the guards, every
# run:
#
#   H17 completeness  the new name has as many uses as the old had, the old has none,
#                     and the renamed program prints what the original does
#   unrelated diff    only the files the plan names changed, and putting the old name
#                     back where the new one stands gives the original bytes exactly
#
# `--pin` writes the budgets: each step's p50 plus a quarter, per workload and host,
# which later revisions are judged against with `--judge` (a p50 above its budget is a
# breach); the p95 is reported, not pinned, since one outlier run in seven is its value. Exit 1 on a breach or a failed guard.
import argparse, json, os, platform, re, shutil, statistics, subprocess, sys, time

parser = argparse.ArgumentParser()
parser.add_argument('--compiler', required=True)
parser.add_argument('--root', required=True)
parser.add_argument('--host', choices=['windows', 'linux'], required=True)
parser.add_argument('--workloads', default='sc500k,sc1m')
parser.add_argument('--runs', type=int, default=7)
parser.add_argument('--out', default='rename.json')
parser.add_argument('--fixtures', default=None)
parser.add_argument('--pin', default=None)
parser.add_argument('--judge', default=None)
args = parser.parse_args()

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(os.path.dirname(here))
fixtures = os.path.abspath(args.fixtures or os.path.join(repo, 'build', 'baseline-fixtures'))
SCALE = {'sc500k': (500, 500_000), 'sc1m': (1000, 1_000_000)}
MARGIN = 0.25
compiler, root = os.path.abspath(args.compiler), os.path.abspath(args.root)
exe = '.exe' if args.host == 'windows' else ''
STEPS = ('query', 'plan', 'apply', 'check')


def workload(name):
    d = os.path.join(fixtures, name)
    if not os.path.exists(os.path.join(d, 'src', 'main.e')):
        modules, lines = SCALE[name]
        subprocess.check_call([sys.executable, os.path.join(repo, 'benchmarks', 'scale', 'generate.py'), d,
                               '--modules', str(modules), '--lines', str(lines), '--seed', '1'])
    return d


def run(command, cwd):
    start = time.perf_counter()
    done = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    return done, (time.perf_counter() - start) * 1000.0


def uses(cwd, symbol):
    done, ms = run([compiler, 'uses-file', 'src/main.e', root, 'x64', args.host, '--json', '--symbol', symbol], cwd)
    count = sum(1 for line in done.stdout.splitlines() if '"record":"use"' in line)
    return done.returncode, count, ms


def target_symbol(d, modules):
    module = f'm{modules // 2:04d}'
    counts = {}
    for f in os.listdir(os.path.join(d, 'src')):
        for m in re.finditer(module + r'\.(job\d+)\b', open(os.path.join(d, 'src', f), encoding='utf-8').read()):
            counts[m.group(1)] = counts.get(m.group(1), 0) + 1
    name = max(sorted(counts), key=lambda k: counts[k])
    return module, name


report = {'schema': 'neper-rename', 'version': 1, 'host': args.host, 'platform': platform.platform(),
          'runs': args.runs, 'compiler': compiler, 'root': root, 'cells': []}
failures = 0
for name in args.workloads.split(','):
    d = workload(name)
    module, function = target_symbol(d, SCALE[name][0])
    old, new = f'{module}.{function}', f'renamed_{function}'
    expected = open(os.path.join(d, 'expected.txt'), encoding='utf-8').read().strip() if os.path.exists(os.path.join(d, 'expected.txt')) else None
    originals = {f: open(os.path.join(d, 'src', f), 'rb').read() for f in os.listdir(os.path.join(d, 'src'))}
    scratch = os.path.join(d + '-rename')
    cell = {'workload': name, 'symbol': old, 'to': new, 'runs': []}
    for n in range(args.runs + 1):
        shutil.rmtree(scratch, ignore_errors=True)
        shutil.copytree(os.path.join(d, 'src'), os.path.join(scratch, 'src'))
        record = {}
        code, old_uses, record['query'] = uses(scratch, old)
        plan_path = os.path.join(scratch, 'plan.jsonl')
        done, record['plan'] = run([compiler, 'plan-rename-file', 'src/main.e', root, 'x64', args.host, '--json',
                                    '--symbol', old, '--to', new], scratch)
        open(plan_path, 'w', encoding='utf-8').write(done.stdout)
        planned = sorted(set(re.findall(r'"path":"([^"]+)"', done.stdout)))
        applied, record['apply'] = run([compiler, 'apply-plan', plan_path, '--root', os.path.join(scratch, 'src')], scratch)
        output = os.path.join(scratch, f'renamed{exe}')
        built, record['check'] = run([compiler, 'emit-executable', 'src/main.e', root, 'x64', args.host, output], scratch)
        guards = {'query': code == 0 and old_uses > 0, 'plan': done.returncode == 0, 'apply': applied.returncode == 0,
                  'check': built.returncode == 0}
        # H17 completeness: the uses moved whole to the new name, and the program is the same.
        _, new_uses, _ = uses(scratch, f'{module}.{new}')
        _, left_uses, _ = uses(scratch, old)
        guards['complete'] = new_uses == old_uses and left_uses == 0
        if built.returncode == 0 and expected is not None:
            ran = subprocess.run([output], capture_output=True, text=True)
            guards['same_output'] = ran.stdout.strip() == expected
        # The unrelated diff: only planned files changed, and the old name put back is the original.
        changed = []
        for f, before in originals.items():
            after = open(os.path.join(scratch, 'src', f), 'rb').read()
            if after != before:
                changed.append(f)
                if after.replace(new.encode(), function.encode()) != before: guards['unrelated'] = False
        guards.setdefault('unrelated', True)
        guards['only_planned'] = all(any(p.endswith(f) for p in planned) for f in changed)
        record['uses'] = old_uses
        record['files_changed'] = len(changed)
        record['guards'] = guards
        if n:
            cell['runs'].append(record)
        if not all(guards.values()):
            failures += 1
            print(f'{name} run {n}: guard failed {guards}\n{done.stdout[-800:]}\n{applied.stdout[-400:]}{applied.stderr[-400:]}\n{built.stdout[-400:]}{built.stderr[-400:]}')
    shutil.rmtree(scratch, ignore_errors=True)
    for step in STEPS:
        times = sorted(r[step] for r in cell['runs'])
        cell[step + '_ms_p50'] = round(statistics.median(times), 1)
        cell[step + '_ms_p95'] = round(times[min(len(times) - 1, int(round(0.95 * (len(times) - 1))))], 1)
    last = cell['runs'][-1]
    print(f"{name:7s} {old} -> {new}: {last['uses']} uses in {last['files_changed']} files; " +
          ', '.join(f"{s} p50 {cell[s + '_ms_p50']:.0f} ms" for s in STEPS))
    report['cells'].append(cell)

breaches = 0
if args.judge:
    pinned = {c['workload']: c for c in json.load(open(args.judge, encoding='utf-8'))['cells']}
    for cell in report['cells']:
        budget = pinned.get(cell['workload'])
        if budget is None:
            print(f"{cell['workload']}: not pinned, not judged"); continue
        for step in STEPS:
            limit = budget[step + '_budget_ms']
            verdict = 'ok' if cell[step + '_ms_p50'] <= limit else 'BREACH'
            if verdict != 'ok': breaches += 1
            print(f"  {cell['workload']} {step}: {verdict} p50 {cell[step + '_ms_p50']:.0f} ms, budget {limit:.0f}")
if args.pin:
    pin = {'schema': 'neper-rename-budget', 'version': 1, 'host': args.host, 'margin': MARGIN, 'cells': [
        dict({'workload': c['workload'], 'symbol': c['symbol']},
             **{s + '_budget_ms': round(c[s + '_ms_p50'] * (1.0 + MARGIN), 1) for s in STEPS}) for c in report['cells']]}
    json.dump(pin, open(args.pin, 'w', encoding='utf-8'), indent=1)
    print(f'pinned {args.pin}')
report['guard_failures'] = failures
report['breaches'] = breaches
json.dump(report, open(args.out, 'w', encoding='utf-8'), indent=1)
print(f'rename: {failures} guard failure(s), {breaches} breach(es); wrote {args.out}')
sys.exit(1 if failures or breaches else 0)
