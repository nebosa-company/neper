# The M2 performance gate (D366, H25): a measurement against the baseline's budgets.
#
#   python benchmarks/baseline/gate.py NEW.json [--baseline results/baseline-windows.json]
#
# Every cell of NEW.json is compared with the baseline cell of the same workload and
# mode: cold p50 within +10%, warm p50 within +15%, peak RSS within +10%, the arena
# high-water mark not above, the image within +5% (docs/m2-baseline.md, "The
# budgets"). A cell the baseline lacks is reported and not judged. The report is one
# line per measure per cell -- `ok`, `BREACH` with both numbers and the delta, or
# `missing` -- then a summary; the exit status is 1 when any measure breached, which
# is what a merge gate reads. A breach is not a failure of the measurement: it is
# the number a decision row has to name (D352, D355), and the gate exists so it is
# named rather than drifted past.
import argparse, json, os, sys

here = os.path.dirname(os.path.abspath(__file__))
parser = argparse.ArgumentParser()
parser.add_argument('measurement')
parser.add_argument('--baseline', default=None)
args = parser.parse_args()

with open(args.measurement, encoding='utf-8') as f:
    new = json.load(f)
baseline_path = args.baseline
if baseline_path is None:
    baseline_path = os.path.join(here, 'results', 'baseline-%s.json' % new['host'])
with open(baseline_path, encoding='utf-8') as f:
    base = json.load(f)

BUDGETS = [
    ('cold p50', lambda c: c['cold']['p50'], 0.10),
    ('warm p50', lambda c: c['warm']['p50'], 0.15),
    ('peak RSS', lambda c: c.get('peak_mb'), 0.10),
    ('arena high-water', lambda c: c.get('arena_mb'), 0.0),
    ('image', lambda c: c.get('image_bytes'), 0.05),
]

def fmt(v):
    return ('%d' % v) if float(v).is_integer() else ('%.1f' % v)

def cells(report):
    return {(c['workload'], c['mode']): c for c in report['cells'] if 'failed' not in c}

base_cells = cells(base)
breaches = 0
judged = 0
print('gate: %s (revision %s, %s workers) against %s (revision %s, %s workers)' % (
    os.path.basename(args.measurement), new.get('revision', '?')[:12], new.get('jobs'),
    os.path.basename(baseline_path), base.get('revision', '?')[:12], base.get('jobs')))
if new.get('jobs') != base.get('jobs'):
    print('  note: the worker counts differ, and the budgets were set at the baseline\'s')
for key, cell in cells(new).items():
    if key not in base_cells:
        print('  %s %s: missing from the baseline, not judged' % key)
        continue
    old = base_cells[key]
    for name, read, margin in BUDGETS:
        a, b = read(old), read(cell)
        if a is None or b is None or a == 0:
            print('  %s %s %s: missing, not judged' % (key[0], key[1], name))
            continue
        judged += 1
        delta = (b - a) / a
        limit = a * (1 + margin)
        unit = 'B' if name == 'image' else ('MB' if 'RSS' in name or 'arena' in name else 'ms')
        if b > limit + 0.5:
            breaches += 1
            print('  %s %s %s: BREACH %s -> %s %s (%+.1f%%, budget %+.0f%%)' % (key[0], key[1], name, fmt(a), fmt(b), unit, delta * 100, margin * 100))
        else:
            print('  %s %s %s: ok %s -> %s %s (%+.1f%%)' % (key[0], key[1], name, fmt(a), fmt(b), unit, delta * 100))

print('gate: %d measures judged, %d breached' % (judged, breaches))
sys.exit(1 if breaches else 0)
