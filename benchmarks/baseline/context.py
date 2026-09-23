# H25's context/repair workflow (D948): what an agent is handed and what it takes to
# repair a program with the compiler's own fixes. Neither was in M2 (`context-file` is
# D397, the fixes D432/D444), so the workload and budget are frozen here.
#
#   python benchmarks/baseline/context.py --compiler NEW --root ROOT --host windows|linux \
#       [--runs 3] [--out context.json] [--fixtures DIR]
#       [--pin results/context-<host>.json | --judge results/context-<host>.json]
#
# Context: `context-file --json --symbol S --budget B` for fixed symbols of the
# compiler's own source and of sc500k at budgets of 16 and 64 records. Measured: the
# serialized bytes, the tokens of two model families' tokenizers (tiktoken `cl100k_base`
# and `o200k_base`, counted, not estimated), the records, whether the answer is
# complete, and the latency.
#
# Repair: five defects frozen into the CPU programs of benchmarks/cpu (a misspelt field,
# local and function, a literal of the wrong width, and two defects in one program;
# names of fewer than three characters get no suggestion, so none of these is one).
# The loop is an agent's with no model in it: `check-file --json`, and when a diagnostic
# offers a fix whose precondition (the file's SHA-256) holds, its edits applied, then
# the check again, up to five calls. Measured: the calls, the total time, the
# diagnostics' bytes and tokens. Verified success: the repaired program builds and
# prints what the original prints.
#
# `--pin` writes the budgets: a context answer's tokens not above what they are now,
# its latency and a repair's time within their median plus a quarter, a repair's calls
# not above; `--judge` holds a later revision to them. Exit 1 on a breach or a failed
# repair.
import argparse, hashlib, json, os, platform, shutil, statistics, subprocess, sys, time

parser = argparse.ArgumentParser()
parser.add_argument('--compiler', required=True)
parser.add_argument('--root', required=True)
parser.add_argument('--host', choices=['windows', 'linux'], required=True)
parser.add_argument('--runs', type=int, default=3)
parser.add_argument('--out', default='context.json')
parser.add_argument('--fixtures', default=None)
parser.add_argument('--pin', default=None)
parser.add_argument('--judge', default=None)
# A host without the tokenizer (or its cached encodings) records the raw outputs, and
# `--retokenize REPORT` counts their tokens where it is: the counts are of the bytes.
parser.add_argument('--retokenize', default=None)
args = parser.parse_known_args()[0] if '--retokenize' in sys.argv else parser.parse_args()

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(os.path.dirname(here))
fixtures = os.path.abspath(args.fixtures or os.path.join(repo, 'build', 'baseline-fixtures'))
compiler, root = os.path.abspath(args.compiler), os.path.abspath(args.root)
exe = '.exe' if args.host == 'windows' else ''
MARGIN = 0.25
try:
    import tiktoken
    encoders = {name: tiktoken.get_encoding(name) for name in ('cl100k_base', 'o200k_base')}
except Exception:
    encoders = {}

CONTEXT = [
    ('compiler', repo, 'check.check_expr'), ('compiler', repo, 'nir.emit'), ('compiler', repo, 'em.write_module'),
    ('sc500k', os.path.join(fixtures, 'sc500k'), 'm0250.job17'),
]
# (name, program, [(find, replace)]): each find occurs in the program, and the first
# occurrence is what the defect changes.
REPAIRS = [
    ('field', 'records', [('next.bounces = p.bounces + 1i64', 'next.bounces = p.bouncse + 1i64')]),
    ('local', 'sieve', [('marks[multiple] = 1u8', 'marks[multple] = 1u8')]),
    ('function', 'sort', [('let split = partition(values, low, high)', 'let split = partiton(values, low, high)')]),
    ('literal', 'sieve', [('count += 1u64', 'count += 1usize')]),
    ('two', 'records', [('next.bounces = p.bounces + 1i64', 'next.bounces = p.bouncse + 1i64'),
                        ('next.bounces = next.bounces + 1i64', 'next.bounces = next.bouncs + 1i64')]),
]


def run(command, cwd):
    start = time.perf_counter()
    done = subprocess.run(command, cwd=cwd, capture_output=True, text=True, encoding='utf-8')
    return done, (time.perf_counter() - start) * 1000.0


def tokens(text):
    return {name: len(e.encode(text, disallowed_special=())) for name, e in encoders.items()}


if args.retokenize:
    document = json.load(open(args.retokenize, encoding='utf-8'))
    for cell in document['context']:
        cell['tokens'] = tokens(cell['output'])
    for cell in document['repair']:
        cell['diagnostic_tokens'] = tokens(cell['diagnostics'])
    json.dump(document, open(args.retokenize, 'w', encoding='utf-8'), indent=1)
    print(f'retokenized {args.retokenize}')
    sys.exit(0)


report = {'schema': 'neper-context', 'version': 1, 'host': args.host, 'platform': platform.platform(),
          'runs': args.runs, 'compiler': compiler, 'root': root, 'context': [], 'repair': []}
failures = 0

for workload, cwd, symbol in CONTEXT:
    for budget in (16, 64):
        times, out = [], ''
        for _ in range(args.runs + 1):
            done, ms = run([compiler, 'context-file', 'src/main.e', root, 'x64', args.host, '--json', '--symbol', symbol,
                            '--budget', str(budget)], cwd)
            if done.returncode != 0:
                raise SystemExit(f'context-file {symbol} failed:\n{done.stdout[-800:]}{done.stderr[-800:]}')
            out = done.stdout
            times.append(ms)
        result = json.loads([l for l in out.splitlines() if '"record":"result"' in l][-1])['data']
        cell = {'workload': workload, 'symbol': symbol, 'budget': budget, 'bytes': len(out.encode('utf-8')),
                'tokens': tokens(out), 'records': result.get('records'), 'omitted': result.get('omitted'),
                'complete': result.get('complete'), 'ms_p50': round(statistics.median(times[1:]), 1), 'output': out}
        print(f"context {workload:8s} {symbol:18s} budget {budget:3d}: {cell['records']} records, {cell['bytes']} B, "
              f"{cell['tokens'].get('cl100k_base')} / {cell['tokens'].get('o200k_base')} tokens, complete {cell['complete']}, "
              f"{cell['ms_p50']:.0f} ms")
        report['context'].append(cell)

programs = os.path.join(repo, 'benchmarks', 'cpu')
for name, program, defects in REPAIRS:
    source = open(os.path.join(programs, program, 'src', 'main.e'), encoding='utf-8').read()
    broken = source
    for find, replace in defects:
        assert find in broken, (name, find)
        broken = broken.replace(find, replace, 1)
    scratch = os.path.join(repo, 'build', 'repair-bench', name)
    reference = os.path.join(repo, 'build', 'repair-bench', f'{program}-reference{exe}')
    os.makedirs(os.path.dirname(reference), exist_ok=True)
    done, _ = run([compiler, 'emit-executable', os.path.join(programs, program, 'src', 'main.e'), root, 'x64', args.host,
                   reference, '--release'], os.path.join(programs, program))
    expected = subprocess.run([reference], capture_output=True, text=True).stdout
    samples = []
    for attempt in range(args.runs + 1):
        shutil.rmtree(scratch, ignore_errors=True)
        os.makedirs(os.path.join(scratch, 'src'))
        path = os.path.join(scratch, 'src', 'main.e')
        open(path, 'w', encoding='utf-8', newline='\n').write(broken)
        calls, total_ms, diagnostic_bytes, diagnostic_tokens, fixed = 0, 0.0, 0, {k: 0 for k in encoders}, False
        diagnostics = ''
        while calls < 5:
            done, ms = run([compiler, 'check-file', 'src/main.e', root, 'x64', args.host, '--json'], scratch)
            calls += 1; total_ms += ms
            diagnostic_bytes += len(done.stdout.encode('utf-8'))
            diagnostics += done.stdout
            for k, v in tokens(done.stdout).items(): diagnostic_tokens[k] += v
            if done.returncode == 0:
                fixed = True
                break
            edits = None
            for line in done.stdout.splitlines():
                record = json.loads(line)
                if record.get('record') == 'diagnostic' and record.get('fixes'):
                    fix = record['fixes'][0]
                    current = hashlib.sha256(open(path, 'rb').read()).hexdigest()
                    if all(p['sha256'] == current for p in fix.get('preconditions', [])):
                        edits = fix['edits']
                    break
            if edits is None:
                break
            data = open(path, 'rb').read()
            for edit in sorted(edits, key=lambda e: -e['span']['byte_start']):
                data = data[:edit['span']['byte_start']] + edit['replacement'].encode('utf-8') + data[edit['span']['byte_end']:]
            open(path, 'wb').write(data)
        verified = False
        if fixed:
            image = os.path.join(scratch, f'repaired{exe}')
            built, ms = run([compiler, 'emit-executable', 'src/main.e', root, 'x64', args.host, image, '--release'], scratch)
            total_ms += ms
            verified = built.returncode == 0 and subprocess.run([image], capture_output=True, text=True).stdout == expected
        if attempt:
            samples.append({'calls': calls, 'ms': round(total_ms, 1), 'diagnostic_bytes': diagnostic_bytes,
                            'diagnostic_tokens': diagnostic_tokens, 'diagnostics': diagnostics, 'verified': verified})
    shutil.rmtree(scratch, ignore_errors=True)
    ok = all(s['verified'] for s in samples)
    if not ok: failures += 1
    cell = {'defect': name, 'program': program, 'edits': len(defects), 'calls': samples[-1]['calls'],
            'ms_p50': round(statistics.median(s['ms'] for s in samples), 1), 'diagnostic_bytes': samples[-1]['diagnostic_bytes'],
            'diagnostic_tokens': samples[-1]['diagnostic_tokens'], 'diagnostics': samples[-1]['diagnostics'], 'verified': ok}
    print(f"repair  {name:8s} in {program:7s}: {cell['calls']} calls, {cell['ms_p50']:.0f} ms, diagnostics {cell['diagnostic_bytes']} B / "
          f"{cell['diagnostic_tokens'].get('cl100k_base')} tokens, {'verified' if ok else 'FAILED'}")
    report['repair'].append(cell)

breaches = 0
if args.judge:
    pinned = json.load(open(args.judge, encoding='utf-8'))
    pc = {(c['symbol'], c['budget']): c for c in pinned['context']}
    for c in report['context']:
        p = pc.get((c['symbol'], c['budget']))
        if p is None: continue
        for k in encoders:
            if c['tokens'][k] > p['tokens'][k]: breaches += 1; print(f"  BREACH {c['symbol']} {c['budget']}: {k} {c['tokens'][k]} > {p['tokens'][k]}")
        if c['ms_p50'] > p['ms_budget']: breaches += 1; print(f"  BREACH {c['symbol']} {c['budget']}: {c['ms_p50']} ms > {p['ms_budget']}")
    pr = {c['defect']: c for c in pinned['repair']}
    for c in report['repair']:
        p = pr.get(c['defect'])
        if p is None: continue
        if c['calls'] > p['calls'] or c['ms_p50'] > p['ms_budget']: breaches += 1; print(f"  BREACH repair {c['defect']}: {c['calls']} calls, {c['ms_p50']} ms")
if args.pin:
    pin = {'schema': 'neper-context-budget', 'version': 1, 'host': args.host, 'margin': MARGIN,
           'context': [{'symbol': c['symbol'], 'budget': c['budget'], 'tokens': c['tokens'],
                        'ms_budget': round(c['ms_p50'] * (1.0 + MARGIN), 1)} for c in report['context']],
           'repair': [{'defect': c['defect'], 'calls': c['calls'], 'ms_budget': round(c['ms_p50'] * (1.0 + MARGIN), 1)} for c in report['repair']]}
    json.dump(pin, open(args.pin, 'w', encoding='utf-8'), indent=1)
    print(f'pinned {args.pin}')
report['failures'] = failures
report['breaches'] = breaches
json.dump(report, open(args.out, 'w', encoding='utf-8'), indent=1)
print(f'context/repair: {failures} failed repair(s), {breaches} breach(es); wrote {args.out}')
sys.exit(1 if failures or breaches else 0)
