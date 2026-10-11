"""Independent oracle for e.test.bench (L129): the statistics, the comparison and the
report text, from Python's `statistics` module and a numerically integrated Student t.

Sample sets are multiples of 0.25 so every sum is exact in binary and the means agree
to the last bit. For each set the script computes: quartiles (R-7, `statistics.quantiles`
inclusive), the Tukey classification at fence 1.5 (mild) and 3.0 (severe), the values kept
inside the mild fence, mean, sample standard deviation, median, MAD, standard error and
the 95% t interval, and renders the JSON and text reports exactly as the module documents
them. The t table in `lib/e/test/bench.e` is checked against a Simpson integration of the
t density. `--emit` prints the fixture's vector lines; otherwise the script only checks.

Lines: `set~<comma separated samples>~<json>~<text>` with `\\n` for newlines, and
`cmp~<set index a>~<set index b>~<threshold>~<line>` for comparisons.
"""
import math
import random
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = (ROOT / 'lib' / 'e' / 'test' / 'bench.e').read_text(encoding='utf-8')


def t_pdf(x, df):
    c = math.exp(math.lgamma((df + 1) / 2) - math.lgamma(df / 2)) / math.sqrt(df * math.pi)
    return c * (1 + x * x / df) ** (-(df + 1) / 2)


def t_quantile_975(df):
    """Upper 2.5% point of Student's t by Simpson integration and bisection."""
    def cdf_tail_mass(x):  # P(0 < T < x)
        n = 4000
        h = x / n
        total = t_pdf(0, df) + t_pdf(x, df)
        for i in range(1, n):
            total += (4 if i % 2 else 2) * t_pdf(i * h, df)
        return total * h / 3
    lo, hi = 0.0, 200.0
    for _ in range(80):
        mid = (lo + hi) / 2
        if cdf_tail_mass(mid) < 0.475:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def check_t_table():
    table = re.search(r'fn t_table\(\) -> str \{\s*ret "([^"]*)"', SOURCE).group(1).split(',')
    assert len(table) == 30, len(table)
    for df, text in enumerate(table, start=1):
        exact = t_quantile_975(df)
        assert abs(float(text) - exact) < 0.0006, (df, text, exact)


def fmt(v):
    return '%.3f' % v


def analyse(samples, fence=1.5):
    xs = sorted(samples)
    q1, _, q3 = statistics.quantiles(xs, n=4, method='inclusive')
    iqr = q3 - q1
    ml, mh = q1 - fence * iqr, q3 + fence * iqr
    sl, sh = q1 - 2 * fence * iqr, q3 + 2 * fence * iqr
    lo_s = sum(1 for v in xs if v < sl)
    lo_m = sum(1 for v in xs if sl <= v < ml)
    hi_m = sum(1 for v in xs if mh < v <= sh)
    hi_s = sum(1 for v in xs if v > sh)
    kept = [v for v in xs if ml <= v <= mh]
    mean = sum(kept) / len(kept)
    sd = statistics.stdev(kept) if len(kept) > 1 else 0.0
    med = statistics.median(kept)
    mad = statistics.median([abs(v - med) for v in kept])
    se = sd / math.sqrt(len(kept))
    table = [float(t) for t in re.search(r'fn t_table\(\) -> str \{\s*ret "([^"]*)"', SOURCE).group(1).split(',')]
    df = len(kept) - 1
    crit = 0.0 if df == 0 else (table[df - 1] if df <= 30 else 1.96)
    return dict(count=len(xs), kept=len(kept), mean=mean, median=med, stddev=sd, min=kept[0], max=kept[-1],
                q1=q1, q3=q3, mad=mad, se=se, ci_low=mean - crit * se, ci_high=mean + crit * se,
                lo_s=lo_s, lo_m=lo_m, hi_m=hi_m, hi_s=hi_s)


def render_json(name, iters, s):
    return ('{"name": "%s", "iters": %d, "samples": %d, "kept": %d, "mean": %s, "median": %s, "stddev": %s, '
            '"min": %s, "max": %s, "q1": %s, "q3": %s, "mad": %s, "ci_low": %s, "ci_high": %s, '
            '"outliers": {"low_severe": %d, "low_mild": %d, "high_mild": %d, "high_severe": %d}}'
            % (name, iters, s['count'], s['kept'], fmt(s['mean']), fmt(s['median']), fmt(s['stddev']),
               fmt(s['min']), fmt(s['max']), fmt(s['q1']), fmt(s['q3']), fmt(s['mad']), fmt(s['ci_low']),
               fmt(s['ci_high']), s['lo_s'], s['lo_m'], s['hi_m'], s['hi_s']))


def render_text(name, iters, s):
    outliers = s['lo_s'] + s['lo_m'] + s['hi_m'] + s['hi_s']
    return ('%s\n  time:   [%s ns %s ns %s ns]\n  median: %s ns (mad %s)\n  stddev: %s ns over %d of %d samples, '
            '%d iterations each\n  outliers: %d (%d low severe, %d low mild, %d high mild, %d high severe)\n'
            % (name, fmt(s['ci_low']), fmt(s['mean']), fmt(s['ci_high']), fmt(s['median']), fmt(s['mad']),
               fmt(s['stddev']), s['kept'], s['count'], iters, outliers, s['lo_s'], s['lo_m'], s['hi_m'], s['hi_s']))


def compare(base, cur, threshold):
    if base['mean'] == 0:
        return 0.0, 0.0, 'no change'
    change = (cur['mean'] - base['mean']) / base['mean'] * 100
    var = base['se'] ** 2 + cur['se'] ** 2
    t = (cur['mean'] - base['mean']) / math.sqrt(var) if var > 0 else 0.0
    df = base['kept'] + cur['kept'] - 2
    table = [float(x) for x in re.search(r'fn t_table\(\) -> str \{\s*ret "([^"]*)"', SOURCE).group(1).split(',')]
    crit = 0.0 if df == 0 else (table[df - 1] if df <= 30 else 1.96)
    significant = abs(t) > crit
    verdict = 'no change'
    if significant and abs(change) > threshold:
        verdict = 'improved' if change < 0 else 'regressed'
    return change, t, verdict


def sample_sets():
    rng = random.Random(129)

    def quarter(v):
        return round(v * 4) / 4

    sets = []
    sets.append([100.0, 100.0])
    sets.append([100.0, 110.5, 120.25])
    sets.append([5.0] * 12)
    for n, mu, sd in [(8, 1000, 40), (20, 1000, 35), (30, 250, 12), (31, 250, 12), (60, 5000, 300), (45, 90, 4)]:
        sets.append([quarter(rng.gauss(mu, sd)) for _ in range(n)])
    # With outliers on both sides.
    base = [quarter(rng.gauss(1000, 20)) for _ in range(40)]
    sets.append(base + [2000.0, 2500.25, 3.0])
    sets.append([quarter(rng.gauss(500, 10)) for _ in range(25)] + [1500.0, 40.0])
    # A faster and a slower version of the same body.
    sets.append([quarter(rng.gauss(1000, 30)) for _ in range(30)])
    sets.append([quarter(rng.gauss(1100, 30)) for _ in range(30)])
    sets.append([quarter(rng.gauss(1003, 30)) for _ in range(30)])
    return sets


def emit():
    sets = sample_sets()
    stats = [analyse(s) for s in sets]
    for i, (s, st) in enumerate(zip(sets, stats)):
        name = 'bench_%d' % i
        iters = 1 + 37 * i
        csv = ','.join(('%g' % v) for v in s)
        out_text = render_text(name, iters, st).replace('\n', '@N@')
        print('set~%s~%s~%s' % (csv, render_json(name, iters, st), out_text))
    last = len(sets) - 1
    for a, b, thr in [(last - 2, last - 1, 1.0), (last - 1, last - 2, 1.0), (last - 2, last, 1.0), (last - 2, last - 1, 20.0),
                      (3, 4, 5.0), (0, 1, 0.0), (2, 2, 0.0), (6, 7, 0.0)]:
        change, t, verdict = compare(stats[a], stats[b], thr)
        print('cmp~%d~%d~%s~bench_%d: %s (%.2f%%, t = %.2f)' % (a, b, ('%g' % thr), b, verdict, change, t))


if __name__ == '__main__':
    check_t_table()
    if '--emit' in sys.argv:
        emit()
    else:
        sets = sample_sets()
        print('bench_vectors: t table matches the integrated density; %d sample sets analysed' % len(sets))
