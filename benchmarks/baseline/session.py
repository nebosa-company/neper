# H25's persistent-session workflow (D947): `query-batch` (D409, H16) loads, resolves and
# checks one program and answers a stream of queries from that snapshot. A feature M2
# did not have, so the workload and budget are frozen here.
#
#   python benchmarks/baseline/session.py --compiler NEW --root ROOT --host windows|linux \
#       [--workloads sc500k,sc1m] [--runs 5] [--out session.json] [--fixtures DIR]
#       [--pin results/session-<host>.json | --judge results/session-<host>.json]
#
# The session: fifty symbols spread over the modules (`mNNNN.job0`, which every module
# has), each asked `context SYMBOL 64` and `uses SYMBOL`, with a `memory` query after
# every ten -- 100 queries and 11 memory samples. Measured, run after run in alternation
# with a session of `memory` alone (the load, resolve and check it has to do first):
#
#   per-query latency  (full session - load-only session) / 100, p50 over the runs
#   memory slope       the arena's use against queries answered, least squares, from the
#                      memory samples: what a session retains per request
#   request peak       the most one request held before its storage was released
#   no stale results   five of the answers, byte for byte, against the same query asked of
#                      a fresh process (`context-file`, `uses-file`)
#
# Cache eviction and cancellation are reported as not applicable: a session holds one
# snapshot and answers in order, with nothing to evict and nothing to cancel.
# `--pin` writes the budgets (per-query p50 plus a quarter; a slope of zero); `--judge`
# holds a later revision to them. Exit 1 on a breach, a nonzero slope or a stale answer.
import argparse, json, os, platform, shutil, statistics, subprocess, sys, time

parser = argparse.ArgumentParser()
parser.add_argument('--compiler', required=True)
parser.add_argument('--root', required=True)
parser.add_argument('--host', choices=['windows', 'linux'], required=True)
parser.add_argument('--workloads', default='sc500k,sc1m')
parser.add_argument('--runs', type=int, default=5)
parser.add_argument('--out', default='session.json')
parser.add_argument('--fixtures', default=None)
parser.add_argument('--pin', default=None)
parser.add_argument('--judge', default=None)
args = parser.parse_args()

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(os.path.dirname(here))
fixtures = os.path.abspath(args.fixtures or os.path.join(repo, 'build', 'baseline-fixtures'))
SCALE = {'sc500k': (500, 500_000), 'sc1m': (1000, 1_000_000)}
MARGIN = 0.25
SYMBOLS = 50
compiler, root = os.path.abspath(args.compiler), os.path.abspath(args.root)


def workload(name):
    d = os.path.join(fixtures, name)
    if not os.path.exists(os.path.join(d, 'src', 'main.e')):
        modules, lines = SCALE[name]
        subprocess.check_call([sys.executable, os.path.join(repo, 'benchmarks', 'scale', 'generate.py'), d,
                               '--modules', str(modules), '--lines', str(lines), '--seed', '1'])
    return d


def batch(d, lines):
    path = os.path.join(d, 'session-batch.txt')
    open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
    start = time.perf_counter()
    done = subprocess.run([compiler, 'query-batch', 'src/main.e', root, 'x64', args.host, '--json', '--batch', path],
                          cwd=d, capture_output=True, text=True, encoding='utf-8')
    ms = (time.perf_counter() - start) * 1000.0
    if done.returncode != 0:
        raise SystemExit(f'query-batch failed in {d}:\n{done.stdout[-1500:]}{done.stderr[-1500:]}')
    return done.stdout, ms


def streams(output):
    # One stream per line, each from its header on.
    parts, current = [], []
    for line in output.splitlines(keepends=True):
        if line.startswith('{"schema":"neper-stream"') and current:
            parts.append(''.join(current)); current = []
        current.append(line)
    if current: parts.append(''.join(current))
    return parts


report = {'schema': 'neper-session', 'version': 1, 'host': args.host, 'platform': platform.platform(),
          'runs': args.runs, 'compiler': compiler, 'root': root, 'cells': []}
failures = 0
for name in args.workloads.split(','):
    d = workload(name)
    modules = SCALE[name][0]
    symbols = [f'm{k:04d}.job0' for k in range(0, modules, modules // SYMBOLS)][:SYMBOLS]
    queries, lines = [], ['memory']
    for s in symbols:
        for q in (f'context {s} 64', f'uses {s}'):
            queries.append(q); lines.append(q)
            if len(queries) % 10 == 0: lines.append('memory')
    load_ms, full_ms, output = [], [], ''
    for run in range(args.runs + 1):
        _, ms_load = batch(d, ['memory'])
        output, ms_full = batch(d, lines)
        if run:
            load_ms.append(ms_load); full_ms.append(ms_full)
    parts = streams(output)
    memory = []
    for line, part in zip(lines, parts):
        if line == 'memory':
            data = json.loads([l for l in part.splitlines() if '"record":"result"' in l][0])['data']
            memory.append((data['queries_completed'], data['arena_used'], data['request_peak']))
    n = len(memory)
    mx = sum(q for q, _, _ in memory) / n; my = sum(u for _, u, _ in memory) / n
    slope = sum((q - mx) * (u - my) for q, u, _ in memory) / max(1e-9, sum((q - mx) ** 2 for q, _, _ in memory))
    # No stale results: five answers against a fresh process each.
    stale = []
    for index in (0, 1, len(queries) // 2, len(queries) // 2 + 1, len(queries) - 1):
        query = queries[index]
        words = query.split()
        if words[0] == 'context':
            command = [compiler, 'context-file', 'src/main.e', root, 'x64', args.host, '--json', '--symbol', words[1], '--budget', words[2]]
        else:
            command = [compiler, 'uses-file', 'src/main.e', root, 'x64', args.host, '--json', '--symbol', words[1]]
        fresh = subprocess.run(command, cwd=d, capture_output=True, text=True, encoding='utf-8').stdout
        answered = parts[lines.index(query)]
        if fresh != answered: stale.append(query)
    per_query = [(f - l) / len(queries) for f, l in zip(full_ms, load_ms)]
    cell = {'workload': name, 'queries': len(queries), 'memory_samples': n,
            'load_ms_p50': round(statistics.median(load_ms), 1), 'session_ms_p50': round(statistics.median(full_ms), 1),
            'per_query_ms_p50': round(statistics.median(per_query), 2), 'per_query_ms': [round(x, 2) for x in per_query],
            'memory_slope_bytes_per_query': round(slope, 1), 'arena_used': memory[-1][1], 'request_peak': max(p for _, _, p in memory),
            'stale': stale, 'eviction': 'not applicable: one snapshot per session', 'cancellation': 'not applicable: answered in order'}
    if stale or slope != 0.0: failures += 1
    print(f"{name:7s} load {cell['load_ms_p50']:.0f} ms, session of {len(queries)} queries {cell['session_ms_p50']:.0f} ms: "
          f"{cell['per_query_ms_p50']:.1f} ms a query; retained {cell['memory_slope_bytes_per_query']:.0f} B a query, "
          f"request peak {cell['request_peak'] >> 20} MB, arena {cell['arena_used'] >> 20} MB; stale {stale or 'none'}")
    report['cells'].append(cell)
    os.remove(os.path.join(d, 'session-batch.txt'))

breaches = 0
if args.judge:
    pinned = {c['workload']: c for c in json.load(open(args.judge, encoding='utf-8'))['cells']}
    for cell in report['cells']:
        budget = pinned.get(cell['workload'])
        if budget is None:
            print(f"{cell['workload']}: not pinned, not judged"); continue
        verdict = 'ok' if cell['per_query_ms_p50'] <= budget['per_query_budget_ms'] else 'BREACH'
        if verdict != 'ok': breaches += 1
        print(f"  {cell['workload']} per query: {verdict} p50 {cell['per_query_ms_p50']:.1f} ms, budget {budget['per_query_budget_ms']:.1f}")
if args.pin:
    pin = {'schema': 'neper-session-budget', 'version': 1, 'host': args.host, 'margin': MARGIN, 'cells': [
        {'workload': c['workload'], 'per_query_budget_ms': round(c['per_query_ms_p50'] * (1.0 + MARGIN), 2),
         'memory_slope_budget': 0.0} for c in report['cells']]}
    json.dump(pin, open(args.pin, 'w', encoding='utf-8'), indent=1)
    print(f'pinned {args.pin}')
report['failures'] = failures
report['breaches'] = breaches
json.dump(report, open(args.out, 'w', encoding='utf-8'), indent=1)
print(f'session: {failures} failure(s), {breaches} breach(es); wrote {args.out}')
sys.exit(1 if failures or breaches else 0)
