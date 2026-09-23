# H25's CPU program workflow (D943): the run time of programs the compilers build, not
# the build. The programs in benchmarks/cpu use only the core language and arena
# allocation, so the library code each compiler brings does not decide the comparison.
#
#   python benchmarks/baseline/cpu.py --baseline-compiler OLD --baseline-root ROOT_OLD \
#       --candidate-compiler NEW --candidate-root ROOT_NEW --host windows|linux \
#       [--programs sieve,sort,hash,records] [--runs 7] [--out cpu.json]
#
# Each program is built three ways: the baseline's release (M2's release carried no
# checks), the candidate's release with `--unchecked` -- the same safety contract --
# and the candidate's release as shipped, which keeps its checks (D355). H25 compares
# run time only under equivalent contracts, so the budget judges the unchecked build:
# the median of the paired per-run ratio against the baseline within +10%. The checked
# build's ratio is reported beside it as the intentional difference, not judged. Every
# run's output must be the baseline's (same defined behaviour); the image sizes are
# recorded. The three run in alternation, pair by pair, after a discarded warm-up.
# Exit 1 on a breach or a differing output.
import argparse, json, os, platform, statistics, subprocess, sys, time

parser = argparse.ArgumentParser()
parser.add_argument('--baseline-compiler', required=True)
parser.add_argument('--baseline-root', required=True)
parser.add_argument('--candidate-compiler', required=True)
parser.add_argument('--candidate-root', required=True)
parser.add_argument('--host', choices=['windows', 'linux'], required=True)
parser.add_argument('--programs', default='sieve,sort,hash,records')
parser.add_argument('--runs', type=int, default=7)
parser.add_argument('--out', default='cpu.json')
args = parser.parse_args()

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(os.path.dirname(here))
programs_dir = os.path.join(repo, 'benchmarks', 'cpu')
out_dir = os.path.join(repo, 'build', 'cpu-bench')
os.makedirs(out_dir, exist_ok=True)
BUDGET = 0.10
exe = '.exe' if args.host == 'windows' else ''
builds = {
    'baseline': (args.baseline_compiler, args.baseline_root, ['--release']),
    'unchecked': (args.candidate_compiler, args.candidate_root, ['--release', '--unchecked']),
    'checked': (args.candidate_compiler, args.candidate_root, ['--release']),
}

report = {'schema': 'neper-cpu', 'version': 1, 'host': args.host, 'platform': platform.platform(),
          'runs': args.runs, 'budget': BUDGET,
          'builds': {k: {'compiler': os.path.abspath(v[0]), 'root': os.path.abspath(v[1]), 'flags': v[2]} for k, v in builds.items()},
          'cells': []}
failures = 0
for name in args.programs.split(','):
    source = os.path.join(programs_dir, name, 'src', 'main.e')
    images = {}
    for who, (compiler, root, flags) in builds.items():
        image = os.path.join(out_dir, f'{name}-{who}{exe}')
        done = subprocess.run([os.path.abspath(compiler), 'emit-executable', source, os.path.abspath(root), 'x64', args.host,
                               image] + flags, capture_output=True, text=True, cwd=os.path.join(programs_dir, name))
        if done.returncode != 0:
            raise SystemExit(f'{who} could not build {name}:\n{done.stdout[-1500:]}{done.stderr[-1500:]}')
        images[who] = image
    times = {who: [] for who in builds}
    outputs = {}
    for run in range(args.runs + 1):
        for who, image in images.items():
            start = time.perf_counter()
            ran = subprocess.run([image], capture_output=True, text=True)
            ms = (time.perf_counter() - start) * 1000.0
            if ran.returncode != 0:
                raise SystemExit(f'{name} built by {who} failed:\n{ran.stdout[-500:]}{ran.stderr[-500:]}')
            outputs.setdefault(who, set()).add(ran.stdout)
            if run:
                times[who].append(ms)
    same = all(outputs[who] == outputs['baseline'] and len(outputs[who]) == 1 for who in builds)
    cell = {'program': name, 'output': sorted(outputs['baseline'])[0].strip(), 'same_output': same,
            'image_bytes': {who: os.path.getsize(image) for who, image in images.items()},
            'ms': {who: [round(t, 1) for t in ts] for who, ts in times.items()}}
    for who in ('unchecked', 'checked'):
        ratios = [c / b for b, c in zip(times['baseline'], times[who])]
        cell[who + '_ratio_p50'] = round(statistics.median(ratios), 3)
        cell[who + '_ratio_range'] = [round(min(ratios), 3), round(max(ratios), 3)]
    for who in builds:
        cell[who + '_ms_p50'] = round(statistics.median(times[who]), 1)
    breach = cell['unchecked_ratio_p50'] > 1.0 + BUDGET
    if breach or not same: failures += 1
    print(f"{name:8s} baseline {cell['baseline_ms_p50']:7.0f} ms | unchecked {cell['unchecked_ms_p50']:7.0f} "
          f"(p50 ratio {cell['unchecked_ratio_p50']:.3f} {'BREACH' if breach else 'ok'}) | checked {cell['checked_ms_p50']:7.0f} "
          f"({cell['checked_ratio_p50']:.3f}, reported) | image {cell['image_bytes']['baseline']} / "
          f"{cell['image_bytes']['unchecked']} / {cell['image_bytes']['checked']} B | output {'same' if same else 'DIFFERS'}")
    report['cells'].append(cell)
report['failures'] = failures
json.dump(report, open(args.out, 'w', encoding='utf-8'), indent=1)
print(f'cpu: {failures} breach(es) or differing output(s); wrote {args.out}')
sys.exit(1 if failures else 0)
