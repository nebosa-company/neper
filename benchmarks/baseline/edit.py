# H25's local edit/revert workflow (D939), paired like the timed gate (D930): the
# baseline and the candidate compiler each take a warm build of a fixed workload, then
# a fixed edit to one module and the build after it, then the revert and the build
# after that, cycle after cycle, in alternation, so host load lands on both.
#
#   python benchmarks/baseline/edit.py --baseline-compiler OLD --baseline-root ROOT_OLD \
#       --candidate-compiler NEW --candidate-root ROOT_NEW --host windows|linux \
#       [--workloads sc500k,sc1m] [--cycles 7] [--jobs 8] [--out edit.json] [--fixtures DIR]
#
# The edits are frozen here, before any candidate is tuned against them (H25):
#
#   body      one statement of one function body in the middle module changes value
#   comment   the middle module's header comment changes: the canonical text does not
#   interface a function is added at the middle module's end: its interface changes
#
# Measured per build: the wall time; the artifacts rewritten and their bytes (from the
# artifact directory, the same way for both compilers); and, where the compiler reports
# them (the manifest's `work` and `incremental` sections -- the baseline has
# neither), declarations and bodies checked, modules and functions lowered and each
# module's decision. The H14 reuse oracle: after an edit the image is byte for byte a
# cold build's of the edited source, after the revert a cold build's of the original.
# The budget is the warm build's (docs/m2-baseline.md): the median per-cycle ratio of
# the candidate over the baseline within +15%; exit 1 on a breach or an oracle failure.
import argparse, hashlib, json, os, platform, shutil, statistics, subprocess, sys, time

parser = argparse.ArgumentParser()
parser.add_argument('--baseline-compiler', required=True)
parser.add_argument('--baseline-root', required=True)
parser.add_argument('--candidate-compiler', required=True)
parser.add_argument('--candidate-root', required=True)
parser.add_argument('--host', choices=['windows', 'linux'], required=True)
parser.add_argument('--workloads', default='sc500k,sc1m')
parser.add_argument('--cycles', type=int, default=7)
parser.add_argument('--jobs', type=int, default=8)
parser.add_argument('--arena', default='14g')
parser.add_argument('--out', default='edit.json')
parser.add_argument('--fixtures', default=None)
args = parser.parse_args()

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(os.path.dirname(here))
fixtures = os.path.abspath(args.fixtures or os.path.join(repo, 'build', 'baseline-fixtures'))
SCALE = {'sc500k': (500, 500_000), 'sc1m': (1000, 1_000_000)}
BUDGET = 0.15
exe = '.exe' if args.host == 'windows' else ''
compilers = {'baseline': (os.path.abspath(args.baseline_compiler), os.path.abspath(args.baseline_root)),
             'candidate': (os.path.abspath(args.candidate_compiler), os.path.abspath(args.candidate_root))}


def workload(name):
    d = os.path.join(fixtures, name)
    if not os.path.exists(os.path.join(d, 'src', 'main.e')):
        modules, lines = SCALE[name]
        subprocess.check_call([sys.executable, os.path.join(repo, 'benchmarks', 'scale', 'generate.py'), d,
                               '--modules', str(modules), '--lines', str(lines), '--seed', '1'])
    return d


def edited(text, kind):
    if kind == 'body':
        at = text.index('acc = acc + r.a')
        return text[:at] + 'acc = acc + r.a + 1i64' + text[at + len('acc = acc + r.a'):]
    if kind == 'comment':
        end = text.index('\n')
        return text[:end] + ' (edited)' + text[end:]
    if kind == 'interface':
        return text + '\nfn edited_extra() -> i64 {\n    ret 0i64\n}\n'
    raise ValueError(kind)


def artifacts(d):
    found = {}
    for root, _, files in os.walk(os.path.join(d, '.neper')):
        for f in files:
            if f.endswith('.em'):
                p = os.path.join(root, f)
                st = os.stat(p)
                found[p] = (st.st_mtime_ns, st.st_size)
    return found


def build(who, d, output, stats):
    compiler, root = compilers[who]
    command = [compiler, 'emit-executable', os.path.join(d, 'src', 'main.e'), root, 'x64', args.host, output,
               '--arena', args.arena, '--incremental', '-j', str(args.jobs)]
    # The baseline commits its arenas up front on Windows and can find the commit
    # charge full (docs/m2-baseline.md); such a build is retried, as measure.py does,
    # and the retries are recorded.
    retries = 0
    while True:
        before = artifacts(d)
        start = time.perf_counter()
        done = subprocess.run(command, cwd=d, capture_output=True, text=True)
        ms = (time.perf_counter() - start) * 1000.0
        if done.returncode == 0:
            break
        if 'Exhausted' not in done.stdout + done.stderr or retries == 3:
            raise SystemExit(f'{who} build failed in {d}:\n{done.stdout[-2000:]}\n{done.stderr[-2000:]}')
        retries += 1
    after = artifacts(d)
    rewritten = [p for p, v in after.items() if before.get(p) != v]
    record = {'ms': round(ms, 1), 'retries': retries, 'artifacts_rewritten': len(rewritten),
              'artifact_bytes_written': sum(after[p][1] for p in rewritten)}
    manifest = os.path.join(d, '.neper', 'debug', 'build-manifest.json')
    if stats and os.path.exists(manifest):
        document = json.load(open(manifest, encoding='utf-8'))
        # The manifest's `work` section: what `--stats` reports, without the source
        # statistics `--stats` computes over every module, which would be timed.
        for key, value in (document.get('work') or {}).items():
            record[key] = value
        inc = document.get('incremental')
        if inc is not None:
            counts = {}
            for m in inc:
                key = m['decision'] + ':' + m['reason']
                counts[key] = counts.get(key, 0) + 1
            record['decisions'] = counts
    return record


def digest(path):
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()


report = {'schema': 'neper-edit', 'version': 1, 'host': args.host, 'platform': platform.platform(),
          'cycles': args.cycles, 'jobs': args.jobs, 'arena': args.arena, 'budget': BUDGET,
          'compilers': {k: {'path': v[0], 'root': v[1]} for k, v in compilers.items()}, 'cells': []}
breaches = 0
for name in args.workloads.split(','):
    d = workload(name)
    modules = SCALE[name][0]
    target = os.path.join(d, 'src', f'm{modules // 2:04d}.e')
    original = open(target, encoding='utf-8', newline='').read()
    for kind in ('body', 'comment', 'interface'):
        changed = edited(original, kind)
        cell = {'workload': name, 'edit': kind, 'module': os.path.basename(target), 'runs': {}}
        oracle = {}
        try:
            for who in compilers:
                # The oracle's references: cold builds of the edited and the original source.
                shutil.rmtree(os.path.join(d, '.neper'), ignore_errors=True)
                open(target, 'w', encoding='utf-8', newline='').write(changed)
                build(who, d, os.path.join(d, f'edit-cold-edited-{who}{exe}'), False)
                shutil.rmtree(os.path.join(d, '.neper'), ignore_errors=True)
                open(target, 'w', encoding='utf-8', newline='').write(original)
                build(who, d, os.path.join(d, f'edit-cold-original-{who}{exe}'), False)
                oracle[who] = {'edited': digest(os.path.join(d, f'edit-cold-edited-{who}{exe}')),
                               'original': digest(os.path.join(d, f'edit-cold-original-{who}{exe}')), 'held': True}
                cell['runs'][who] = []
            for cycle in range(args.cycles + 1):
                for who in compilers:
                    out = os.path.join(d, f'edit-{who}{exe}')
                    open(target, 'w', encoding='utf-8', newline='').write(original)
                    build(who, d, out, False)
                    open(target, 'w', encoding='utf-8', newline='').write(changed)
                    edit_record = build(who, d, out, True)
                    if digest(out) != oracle[who]['edited']: oracle[who]['held'] = False
                    open(target, 'w', encoding='utf-8', newline='').write(original)
                    revert_record = build(who, d, out, True)
                    if digest(out) != oracle[who]['original']: oracle[who]['held'] = False
                    # The first cycle warms the OS cache and is not reported.
                    if cycle:
                        cell['runs'][who].append({'edit': edit_record, 'revert': revert_record})
        finally:
            open(target, 'w', encoding='utf-8', newline='').write(original)
        cell['oracle'] = oracle
        for step in ('edit', 'revert'):
            ratios = [c[step]['ms'] / b[step]['ms'] for b, c in zip(cell['runs']['baseline'], cell['runs']['candidate'])]
            median = statistics.median(ratios)
            cell[step + '_ratio_p50'] = round(median, 3)
            cell[step + '_ratio_range'] = [round(min(ratios), 3), round(max(ratios), 3)]
            for who in compilers:
                times = [r[step]['ms'] for r in cell['runs'][who]]
                cell[f'{who}_{step}_ms_p50'] = round(statistics.median(times), 1)
            if median > 1.0 + BUDGET: breaches += 1
        held = all(o['held'] for o in oracle.values())
        if not held: breaches += 1
        last = cell['runs']['candidate'][-1]
        print(f"{name:7s} {kind:9s} edit {cell['baseline_edit_ms_p50']:7.0f} -> {cell['candidate_edit_ms_p50']:7.0f} ms "
              f"(p50 ratio {cell['edit_ratio_p50']:.3f}), revert {cell['baseline_revert_ms_p50']:7.0f} -> "
              f"{cell['candidate_revert_ms_p50']:7.0f} ms ({cell['revert_ratio_p50']:.3f}); candidate rewrote "
              f"{last['edit']['artifacts_rewritten']} artifacts ({last['edit']['artifact_bytes_written']} B), checked "
              f"{last['edit'].get('bodies_checked')} bodies, lowered {last['edit'].get('functions_lowered')} functions; "
              f"oracle {'held' if held else 'FAILED'}")
        report['cells'].append(cell)
report['breaches'] = breaches
json.dump(report, open(args.out, 'w', encoding='utf-8'), indent=1)
print(f'edit gate: {breaches} breach(es); wrote {args.out}')
sys.exit(1 if breaches else 0)
