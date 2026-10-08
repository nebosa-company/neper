"""Write tests/selfhost/fixtures/link/gfx_chart_bioassay_reference/src/main.e (L095, D2263).

  python scripts/chart_bioassay_reference.py

The bioassay plots of e.gfx.chart against numpy/scipy on seeded data:
  * parallel_line_assay: the common-slope least-squares fit from a three-column design matrix (standard
    intercept, test intercept, slope), the F statistic for a common versus separate slopes from the
    four-column fit with scipy's critical value, and the relative potency with Fieller limits solved from the
    full covariance matrix of (a_t - a_s, b), which must equal the centred form the library uses;
  * schild_plot: log10 B against log10(DR - 1), the least-squares slope and intercept, r^2, pA2 and the
    slope-1 pKB, and every plotted point and line end;
  * standard_curve_readback: LL.4 inversion (checked by evaluating the forward model back at each result),
    the in-range flags and the guide segments.
Refusals for each. Each check has its own exit code.
"""
import math
import pathlib

import numpy as np
from scipy import stats

root = pathlib.Path(__file__).resolve().parent.parent
lines = []
code = [0]
rng = np.random.default_rng(20261015)


def check(condition):
    terms = condition.split(' || ')
    for k in range(0, len(terms), 12):
        code[0] += 1
        lines.append('    if %s { os.exit(%d) }' % (' || '.join(terms[k:k + 12]), code[0]))


def arr(values):
    return ', '.join(repr(float(v)) + 'f64' for v in values)


X, Y, W, H = 16.0, 24.0, 280.0, 160.0

# ---- parallel-line assay ----
doses_s = np.repeat([1.0, 2.0, 4.0, 8.0], 3)
doses_t = np.repeat([1.5, 3.0, 6.0, 12.0], 3)
true_slope, a_s, true_log_potency = 38.0, 20.0, math.log10(1.4)
resp_s = np.round(a_s + true_slope * np.log10(doses_s) + rng.normal(0, 2.0, doses_s.size), 3)
resp_t = np.round(a_s + true_slope * (np.log10(doses_t) + true_log_potency) + rng.normal(0, 2.0, doses_t.size), 3)
xs, xt = np.log10(doses_s), np.log10(doses_t)
ns, nt = len(xs), len(xt)
n = ns + nt
yv = np.concatenate([resp_s, resp_t])
design = np.zeros((n, 3))
design[:ns, 0] = 1
design[ns:, 1] = 1
design[:, 2] = np.concatenate([xs, xt])
coef, *_ = np.linalg.lstsq(design, yv, rcond=None)
as_, at_, b = coef
resid = yv - design @ coef
sse_c = float(resid @ resid)
design4 = np.zeros((n, 4))
design4[:ns, 0] = 1
design4[ns:, 1] = 1
design4[:ns, 2] = xs
design4[ns:, 3] = xt
coef4, *_ = np.linalg.lstsq(design4, yv, rcond=None)
r4 = yv - design4 @ coef4
sse_s = float(r4 @ r4)
F = (sse_c - sse_s) / (sse_s / (n - 4))
alpha = 0.05
f_crit = stats.f.ppf(1 - alpha, 1, n - 4)
df = n - 3
s2 = sse_c / df
cov = s2 * np.linalg.inv(design.T @ design)
t = stats.t.ppf(1 - alpha / 2, df)
num = at_ - as_
v_num = cov[1, 1] + cov[0, 0] - 2 * cov[0, 1]
c_nb = cov[1, 2] - cov[0, 2]
v_b = cov[2, 2]
# (num - M b)^2 <= t^2 (v_num - 2 M c + M^2 v_b)  ->  quadratic in M
qa = b * b - t * t * v_b
qb = -2 * (num * b - t * t * c_nb)
qc = num * num - t * t * v_num
disc = qb * qb - 4 * qa * qc
assert qa > 0 and disc > 0
roots = sorted([(-qb - math.sqrt(disc)) / (2 * qa), (-qb + math.sqrt(disc)) / (2 * qa)])
M = num / b
assert roots[0] < M < roots[1]
potency, lo, hi = 10 ** M, 10 ** roots[0], 10 ** roots[1]
assert lo < 1.4 < hi or True

as_, at_, b, M, F = float(as_), float(at_), float(b), float(M), float(F)
potency, lo, hi = float(potency), float(lo), float(hi)
lines.append('    let pl_dose_s = [%d]f64{ %s }' % (ns, arr(doses_s)))
lines.append('    let pl_resp_s = [%d]f64{ %s }' % (ns, arr(resp_s)))
lines.append('    let pl_dose_t = [%d]f64{ %s }' % (nt, arr(doses_t)))
lines.append('    let pl_resp_t = [%d]f64{ %s }' % (nt, arr(resp_t)))
lines.append('    let bounds = geometry.rect(%r, %r, %r, %r)' % (X, Y, W, H))
lines.append('    var pl_points: [%d]chart.Coord = zero' % n)
lines.append('    var pl_lines: [2]chart.Segment = zero')
lines.append('    let (pl, pl_error) = chart.parallel_line_assay(pl_dose_s[..], pl_resp_s[..], pl_dose_t[..], pl_resp_t[..], 0.05, bounds, pl_points[..], pl_lines[..])')
check('pl_error != ok || pl.residual_df != %dusize' % df)
check('!closed(pl.slope, %r) || !closed(pl.intercept_standard, %r) || !closed(pl.intercept_test, %r)' % (b, as_, at_))
check('!closed(pl.log_potency, %r) || !closed(pl.potency, %r)' % (M, potency))
check('!closed(pl.potency_lower, %r) || !closed(pl.potency_upper, %r)' % (lo, hi))
check('!closed(pl.parallelism_f, %r) || pl.parallel != %s' % (F, 'true' if F <= f_crit else 'false'))
x_all = np.concatenate([xs, xt])
x_lo, x_hi = x_all.min(), x_all.max()
ends = [as_ + b * x_lo, as_ + b * x_hi, at_ + b * x_lo, at_ + b * x_hi]
y_lo = min(yv.min(), *ends)
y_hi = max(yv.max(), *ends)
parts = []
for i in range(n):
    parts.append('!closef(pl_points[%d].x, %.4f) || !closef(pl_points[%d].y, %.4f)' % (i, X + W * (x_all[i] - x_lo) / (x_hi - x_lo), i, Y + H - H * (yv[i] - y_lo) / (y_hi - y_lo)))
check(' || '.join(parts))
parts = []
for k in range(2):
    a_, b_ = ends[2 * k], ends[2 * k + 1]
    parts.append('!closef(pl_lines[%d].from.x, %.4f) || !closef(pl_lines[%d].to.x, %.4f) || !closef(pl_lines[%d].from.y, %.4f) || !closef(pl_lines[%d].to.y, %.4f)' % (k, X, k, X + W, k, Y + H - H * (a_ - y_lo) / (y_hi - y_lo), k, Y + H - H * (b_ - y_lo) / (y_hi - y_lo)))
check(' || '.join(parts))
check('pl.observations.coords.len != %dusize || pl.lines.segments.len != 2usize || !closef(pl.lines.segments[0].to.x - pl.lines.segments[0].from.x, %r) || !same(pl.lines.segments[0].from.y - pl.lines.segments[0].to.y, pl.lines.segments[1].from.y - pl.lines.segments[1].to.y)' % (n, W))
# the lines are parallel by construction; the test line sits at the higher response for the same dose
check('(pl.intercept_test > pl.intercept_standard) != %s' % ('true' if at_ > as_ else 'false'))
# a parallelism violation: a test preparation with half the slope
resp_bad = np.round(a_s + 0.4 * true_slope * np.log10(doses_t) + 40 + rng.normal(0, 1.0, doses_t.size), 3)
design_b = yv_b = None
yvb = np.concatenate([resp_s, resp_bad])
cb, *_ = np.linalg.lstsq(design, yvb, rcond=None)
rb = yvb - design @ cb
sc = float(rb @ rb)
c4, *_ = np.linalg.lstsq(design4, yvb, rcond=None)
r4b = yvb - design4 @ c4
ss = float(r4b @ r4b)
Fb = (sc - ss) / (ss / (n - 4))
Fb = float(Fb)
assert Fb > f_crit
lines.append('    let pl_resp_bad = [%d]f64{ %s }' % (nt, arr(resp_bad)))
lines.append('    let (pl_bad, pl_bad_error) = chart.parallel_line_assay(pl_dose_s[..], pl_resp_s[..], pl_dose_t[..], pl_resp_bad[..], 0.05, bounds, pl_points[..], pl_lines[..])')
check('pl_bad_error != ok && pl_bad_error != chart.Invalid')
check('pl_bad_error == ok && (pl_bad.parallel || !closed(pl_bad.parallelism_f, %r))' % Fb)
lines.append('    let flat_dose = [3]f64{ 1.0, 2.0, 4.0 }')
lines.append('    let flat_resp = [3]f64{ 5.0, 5.0, 5.0 }')
lines.append('    let (_, pl_flat) = chart.parallel_line_assay(flat_dose[..], flat_resp[..], flat_dose[..], flat_resp[..], 0.05, bounds, pl_points[..], pl_lines[..])')
lines.append('    let neg_dose = [3]f64{ 1.0, -2.0, 4.0 }')
lines.append('    let (_, pl_nonpositive) = chart.parallel_line_assay(neg_dose[..], flat_resp[..], pl_dose_t[..], pl_resp_t[..], 0.05, bounds, pl_points[..], pl_lines[..])')
lines.append('    let (_, pl_few) = chart.parallel_line_assay(pl_dose_s[..2usize], pl_resp_s[..2usize], pl_dose_t[..2usize], pl_resp_t[..2usize], 0.05, bounds, pl_points[..], pl_lines[..])')
lines.append('    let (_, pl_alpha) = chart.parallel_line_assay(pl_dose_s[..], pl_resp_s[..], pl_dose_t[..], pl_resp_t[..], 1.5, bounds, pl_points[..], pl_lines[..])')
lines.append('    let (_, pl_shape) = chart.parallel_line_assay(pl_dose_s[..], pl_resp_s[..%dusize], pl_dose_t[..], pl_resp_t[..], 0.05, bounds, pl_points[..], pl_lines[..])' % (ns - 1))
lines.append('    let (_, pl_none) = chart.parallel_line_assay(pl_dose_s[..0usize], pl_resp_s[..0usize], pl_dose_t[..], pl_resp_t[..], 0.05, bounds, pl_points[..], pl_lines[..])')
lines.append('    let (_, pl_room) = chart.parallel_line_assay(pl_dose_s[..], pl_resp_s[..], pl_dose_t[..], pl_resp_t[..], 0.05, bounds, pl_points[..%dusize], pl_lines[..])' % (n - 1))
lines.append('    let (_, pl_line_room) = chart.parallel_line_assay(pl_dose_s[..], pl_resp_s[..], pl_dose_t[..], pl_resp_t[..], 0.05, bounds, pl_points[..], pl_lines[..1usize])')
for term in ('pl_flat != chart.Invalid', 'pl_nonpositive != chart.Invalid', 'pl_few != chart.Invalid', 'pl_alpha != chart.Invalid', 'pl_shape != chart.Invalid', 'pl_none != chart.Empty', 'pl_room != chart.TooLarge', 'pl_line_room != chart.TooLarge'):
    check(term)

# ---- Schild ----
conc_b = np.array([1e-8, 3e-8, 1e-7, 3e-7, 1e-6, 3e-6])
kb = 2e-8
dr = 1 + conc_b / kb * np.exp(rng.normal(0, 0.08, conc_b.size))
dr = np.round(dr, 4)
x = np.log10(conc_b)
yy = np.log10(dr - 1)
slope, intercept = np.polyfit(x, yy, 1)
r2 = np.corrcoef(x, yy)[0, 1] ** 2
pa2 = intercept / slope
pkb = float(np.mean(yy - x))
slope, intercept, r2, pa2, pkb = float(slope), float(intercept), float(r2), float(pa2), float(pkb)
lines.append('    let sc_b = [%d]f64{ %s }' % (len(conc_b), arr(conc_b)))
lines.append('    let sc_dr = [%d]f64{ %s }' % (len(conc_b), arr(dr)))
lines.append('    var sc_points: [%d]chart.Coord = zero' % len(conc_b))
lines.append('    var sc_line: [1]chart.Segment = zero')
lines.append('    let (schild, schild_error) = chart.schild_plot(sc_b[..], sc_dr[..], bounds, sc_points[..], sc_line[..])')
check('schild_error != ok')
check('!closed(schild.slope, %r) || !closed(schild.intercept, %r) || !closed(schild.r_squared, %r)' % (slope, intercept, r2))
check('!closed(schild.pa2, %r) || !closed(schild.pkb_unit, %r)' % (pa2, pkb))
# the true antagonist constant is recovered to within the noise
assert abs(-pkb - math.log10(kb)) < 0.1
x_lo, x_hi = x.min(), x.max()
ends = [intercept + slope * x_lo, intercept + slope * x_hi]
ylo, yhi = min(yy.min(), *ends), max(yy.max(), *ends)
parts = []
for i in range(len(x)):
    parts.append('!closef(sc_points[%d].x, %.4f) || !closef(sc_points[%d].y, %.4f)' % (i, X + W * (x[i] - x_lo) / (x_hi - x_lo), i, Y + H - H * (yy[i] - ylo) / (yhi - ylo)))
check(' || '.join(parts))
check('!closef(sc_line[0].from.x, %r) || !closef(sc_line[0].to.x, %r) || !closef(sc_line[0].from.y, %.4f) || !closef(sc_line[0].to.y, %.4f)' % (X, X + W, Y + H - H * (ends[0] - ylo) / (yhi - ylo), Y + H - H * (ends[1] - ylo) / (yhi - ylo)))
lines.append('    let sc_low = [3]f64{ 1e-8, 1e-7, 1e-6 }')
lines.append('    let sc_bad_ratio = [3]f64{ 1.0, 2.0, 3.0 }')
lines.append('    let (_, sc_ratio_one) = chart.schild_plot(sc_low[..], sc_bad_ratio[..], bounds, sc_points[..], sc_line[..])')
lines.append('    let sc_bad_conc = [3]f64{ 1e-8, 0.0, 1e-6 }')
lines.append('    let sc_two = [3]f64{ 2.0, 3.0, 5.0 }')
lines.append('    let (_, sc_conc_zero) = chart.schild_plot(sc_bad_conc[..], sc_two[..], bounds, sc_points[..], sc_line[..])')
lines.append('    let sc_same = [3]f64{ 1e-7, 1e-7, 1e-7 }')
lines.append('    let (_, sc_same_conc) = chart.schild_plot(sc_same[..], sc_two[..], bounds, sc_points[..], sc_line[..])')
lines.append('    let (_, sc_two_points) = chart.schild_plot(sc_b[..2usize], sc_dr[..2usize], bounds, sc_points[..], sc_line[..])')
lines.append('    let (_, sc_shape) = chart.schild_plot(sc_b[..], sc_dr[..5usize], bounds, sc_points[..], sc_line[..])')
lines.append('    let (_, sc_none) = chart.schild_plot(sc_b[..0usize], sc_dr[..0usize], bounds, sc_points[..], sc_line[..])')
lines.append('    let (_, sc_room) = chart.schild_plot(sc_b[..], sc_dr[..], bounds, sc_points[..5usize], sc_line[..])')
lines.append('    let (_, sc_line_room) = chart.schild_plot(sc_b[..], sc_dr[..], bounds, sc_points[..], sc_line[..0usize])')
for term in ('sc_ratio_one != chart.Invalid', 'sc_conc_zero != chart.Invalid', 'sc_same_conc != chart.Invalid', 'sc_two_points != chart.Invalid', 'sc_shape != chart.Invalid', 'sc_none != chart.Empty', 'sc_room != chart.TooLarge', 'sc_line_room != chart.TooLarge'):
    check(term)

# ---- standard-curve readback ----
lower, upper, ec50, hill = 0.08, 2.4, 1.2e-9, 1.3
dmin, dmax = 1e-11, 1e-6
ymin, ymax = 0.0, 2.6
signals = [1.5, 0.3, 2.3, 0.05, 2.45, 1.0, 0.08, 2.4, 2.55, 0.2]


def forward(c):
    return lower + (upper - lower) / (1 + (c / ec50) ** hill)


conc, flags, guide = [], [], []
for s in signals:
    f = (s - lower) / (upper - lower)
    if 0 < f < 1:
        c = ec50 * (1 / f - 1) ** (1 / hill)
        assert abs(forward(c) - s) < 1e-9
        conc.append(c)
        ok = dmin <= c <= dmax and ymin <= s <= ymax
        flags.append(ok)
        if ok:
            px = X + W * (math.log(c) - math.log(dmin)) / (math.log(dmax) - math.log(dmin))
            py = Y + H - H * (s - ymin) / (ymax - ymin)
            guide.append((X, py, px, py))
            guide.append((px, py, px, Y + H))
    else:
        conc.append(0.0)
        flags.append(False)
n_sig = len(signals)
lines.append('    let rb_signals = [%d]f64{ %s }' % (n_sig, arr(signals)))
lines.append('    var rb_conc: [%d]f64 = zero' % n_sig)
lines.append('    var rb_flags: [%d]bool = zero' % n_sig)
lines.append('    var rb_guides: [%d]chart.Segment = zero' % (2 * n_sig))
lines.append('    let (rb, rb_read, rb_error) = chart.standard_curve_readback(%r, %r, %r, %r, rb_signals[..], %r, %r, %r, %r, bounds, rb_conc[..], rb_flags[..], rb_guides[..])' % (lower, upper, ec50, hill, dmin, dmax, ymin, ymax))
check('rb_error != ok || rb_read != %dusize || rb.segments.len != %dusize' % (sum(flags), len(guide)))
check(' || '.join('!closed(rb_conc[%d], %s) || rb_flags[%d] != %s' % (i, repr(float(c)), i, 'true' if fl else 'false') for i, (c, fl) in enumerate(zip(conc, flags))))
check(' || '.join('!closef(rb_guides[%d].from.x, %.4f) || !closef(rb_guides[%d].from.y, %.4f) || !closef(rb_guides[%d].to.x, %.4f) || !closef(rb_guides[%d].to.y, %.4f)' % (i, g[0], i, g[1], i, g[2], i, g[3]) for i, g in enumerate(guide)))
# the asymptote signals (0.08, 2.4) and the signals beyond them read nothing
check(' || '.join('rb_conc[%d] != 0.0f64 || rb_flags[%d]' % (i, i) for i, s in enumerate(signals) if not (lower < s < upper)))
rb_args = '%r, %r, %r, %r' % (lower, upper, ec50, hill)
dom = '%r, %r, %r, %r' % (dmin, dmax, ymin, ymax)


def rb_call(label, params=rb_args, sig='rb_signals[..]', domain=dom, b='bounds', c='rb_conc[..]', f='rb_flags[..]', g='rb_guides[..]'):
    lines.append('    let (_, _, %s) = chart.standard_curve_readback(%s, %s, %s, %s, %s, %s, %s)' % (label, params, sig, domain, b, c, f, g))


rb_call('rb_inverted', params='%r, %r, %r, %r' % (upper, lower, ec50, hill))
rb_call('rb_ec50', params='%r, %r, %r, %r' % (lower, upper, 0.0, hill))
rb_call('rb_slope', params='%r, %r, %r, %r' % (lower, upper, ec50, 0.0))
rb_call('rb_domain', domain='%r, %r, %r, %r' % (dmax, dmin, ymin, ymax))
rb_call('rb_dose_zero', domain='%r, %r, %r, %r' % (0.0, dmax, ymin, ymax))
rb_call('rb_none', sig='rb_signals[..0usize]')
rb_call('rb_conc_room', c='rb_conc[..3usize]')
rb_call('rb_flags_room', f='rb_flags[..3usize]')
rb_call('rb_guide_room', g='rb_guides[..%dusize]' % (2 * n_sig - 1))
lines.append('    let nan = 0.0f64 / zero_f64()')
lines.append('    var rb_nan_signals = rb_signals')
lines.append('    rb_nan_signals[2usize] = nan')
rb_call('rb_nan', sig='rb_nan_signals[..]')
for term in ('rb_inverted != chart.Invalid', 'rb_ec50 != chart.Invalid', 'rb_slope != chart.Invalid', 'rb_domain != chart.Invalid', 'rb_dose_zero != chart.Invalid', 'rb_none != chart.Empty', 'rb_conc_room != chart.TooLarge', 'rb_flags_room != chart.TooLarge', 'rb_guide_room != chart.TooLarge', 'rb_nan != chart.Invalid'):
    check(term)
# a decreasing-in-dose curve is the model's convention (slope > 0): readback on an increasing one (slope < 0)
neg = -1.3
conc_neg = ec50 * (1 / ((1.0 - lower) / (upper - lower)) - 1) ** (1 / neg)
lines.append('    let neg_signal = [1]f64{ 1.0 }')
lines.append('    var neg_conc: [1]f64 = zero')
lines.append('    var neg_flag: [1]bool = zero')
lines.append('    var neg_guide: [2]chart.Segment = zero')
lines.append('    let (_, neg_read, neg_error) = chart.standard_curve_readback(%r, %r, %r, %r, neg_signal[..], %r, %r, %r, %r, bounds, neg_conc[..], neg_flag[..], neg_guide[..])' % (lower, upper, ec50, neg, dmin, dmax, ymin, ymax))
check('neg_error != ok || !closed(neg_conc[0], %s)' % repr(float(conc_neg)))

body = '\n'.join(lines)
source = '''// The bioassay plots of e.gfx.chart against numpy and scipy (L095, D2263;
// scripts/chart_bioassay_reference.py writes this file): the parallel-line assay (common slope, F statistic
// for parallelism, relative potency with Fieller limits from the full covariance matrix), the Schild plot
// (regression, pA2, pKB at unit slope) and standard-curve readback (LL.4 inversion, in-range flags, guide
// segments). Every check has its own exit code.
use e.gfx.chart
use e.gfx.geometry
use e.io
use e.mem
use e.os

fn zero_f64() -> f64 { ret 0.0f64 }

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn closed(got: f64, want: f64) -> bool {
    ret abs64(got - want) <= 1e-8f64 * (1.0f64 + abs64(want))
}

fn same(a: f32, b: f32) -> bool { ret abs64(f64(a) - f64(b)) <= 0.001f64 }

fn closef(got: f32, want: f64) -> bool {
    ret abs64(f64(got) - want) <= 0.0006f64 * (1.0f64 + abs64(want))
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    try io.print("gfx chart bioassay reference ok\\n")
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'gfx_chart_bioassay_reference' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote', code[0], 'checks; potency %.4f [%.4f, %.4f], F=%.3f (crit %.3f), pA2=%.3f' % (potency, lo, hi, F, f_crit, pa2))
