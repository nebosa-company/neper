# H20's cap re-evaluation (D1521): the forty-instruction inlining cap (D346) against
# the workloads the hardening plan names for it -- GP-01, the compiler, and the M2
# CPU programs in benchmarks/cpu -- in release as shipped, which keeps its checks.
#
#   python benchmarks/baseline/inline_cap.py --compiler NEPER --root ROOT --host windows|linux \
#       [--caps 0,20,40,80] [--runs 7] [--out cap.json]
#
# Per cap: each CPU program's image size and median run time, its output held to the
# cap-40 build's; and the compiler built under the cap -- its image size, the median
# time it takes for one fixed job (a debug build of the compiler, which inlines
# nothing, so only the capped compiler's own code speed differs), and whether it
# builds itself under the cap to the same bytes.
import argparse, json, os, platform, statistics, subprocess, sys, time

parser = argparse.ArgumentParser()
parser.add_argument('--compiler', required=True)
parser.add_argument('--root', required=True)
parser.add_argument('--host', required=True)
parser.add_argument('--caps', default='0,20,40,80')
parser.add_argument('--runs', type=int, default=7)
parser.add_argument('--programs', default='sieve,sort,hash,records')
parser.add_argument('--out', default='cap.json')
args = parser.parse_args()
exe = '.exe' if args.host == 'windows' else ''
root = os.path.abspath(args.root)
compiler = os.path.abspath(args.compiler)
programs_dir = os.path.join(root, 'benchmarks', 'cpu')
out_dir = os.path.join(root, 'build', 'inline-cap')
os.makedirs(out_dir, exist_ok=True)
caps = [int(c) for c in args.caps.split(',')]


def build(tool, source, image, cap, cwd, release=True):
    flags = (['--release'] if release else []) + ['--inline-cap', str(cap)]
    done = subprocess.run([tool, 'emit-executable', source, root, 'x64', args.host, image] + flags,
                          capture_output=True, text=True, cwd=cwd)
    if done.returncode != 0:
        raise SystemExit(f'cap {cap} could not build {source}:\n{done.stdout[-1500:]}{done.stderr[-1500:]}')


def timed(command, cwd=None):
    start = time.perf_counter()
    ran = subprocess.run(command, capture_output=True, text=True, cwd=cwd)
    ms = (time.perf_counter() - start) * 1000.0
    if ran.returncode != 0:
        raise SystemExit(f'{command[0]} failed:\n{ran.stdout[-500:]}{ran.stderr[-500:]}')
    return ms, ran.stdout


report = {'schema': 'neper-inline-cap', 'version': 1, 'host': args.host, 'platform': platform.platform(),
          'runs': args.runs, 'caps': caps, 'programs': [], 'compiler': []}
for name in args.programs.split(','):
    source = os.path.join(programs_dir, name, 'src', 'main.e')
    images = {}
    for cap in caps:
        image = os.path.join(out_dir, f'{name}-cap{cap}{exe}')
        build(compiler, source, image, cap, os.path.join(programs_dir, name))
        images[cap] = image
    times = {cap: [] for cap in caps}
    outputs = {cap: set() for cap in caps}
    for run in range(args.runs + 1):
        for cap in caps:
            ms, out = timed([images[cap]])
            outputs[cap].add(out)
            if run:
                times[cap].append(ms)
    reference = outputs[40] if 40 in outputs else outputs[caps[0]]
    cell = {'program': name, 'same_output': all(outputs[c] == reference and len(outputs[c]) == 1 for c in caps),
            'image_bytes': {str(c): os.path.getsize(images[c]) for c in caps},
            'ms_p50': {str(c): round(statistics.median(times[c]), 1) for c in caps}}
    report['programs'].append(cell)
    print(f"{name:8s} " + ' | '.join(f"cap {c}: {cell['ms_p50'][str(c)]:7.1f} ms {cell['image_bytes'][str(c)]} B" for c in caps)
          + f" | output {'same' if cell['same_output'] else 'DIFFERS'}")

# GP-01: the compiler built under each cap, then timed building itself under that cap.
main = os.path.join(root, 'src', 'main.e')
for cap in caps:
    image = os.path.join(out_dir, f'neper-cap{cap}{exe}')
    build(compiler, main, image, cap, root)
    again = os.path.join(out_dir, f'neper-cap{cap}-again{exe}')
    timed([image, 'emit-executable', main, root, 'x64', args.host, again, '--release', '--inline-cap', str(cap)], cwd=root)
    fixed = open(image, 'rb').read() == open(again, 'rb').read()
    job = os.path.join(out_dir, f'neper-cap{cap}-job{exe}')
    samples = []
    for run in range(args.runs + 1):
        ms, _ = timed([image, 'emit-executable', main, root, 'x64', args.host, job], cwd=root)
        if run:
            samples.append(ms)
    cell = {'cap': cap, 'image_bytes': os.path.getsize(image), 'debug_build_ms_p50': round(statistics.median(samples), 1),
            'debug_build_ms_range': [round(min(samples), 1), round(max(samples), 1)], 'fixed_point': fixed}
    report['compiler'].append(cell)
    print(f"GP-01 cap {cap:3d}: image {cell['image_bytes']} B, debug build {cell['debug_build_ms_p50']:.0f} ms "
          f"({cell['debug_build_ms_range'][0]:.0f}-{cell['debug_build_ms_range'][1]:.0f}), fixed point {'yes' if fixed else 'NO'}")
json.dump(report, open(args.out, 'w', encoding='utf-8'), indent=1)
print(f'wrote {args.out}')
