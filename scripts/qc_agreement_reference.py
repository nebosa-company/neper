"""Write tests/selfhost/fixtures/link/gfx_chart_qc_agreement_reference/src/main.e (L097, D2265).

  python scripts/qc_agreement_reference.py

The QC and agreement extensions against numpy/scipy:
  * levey_jennings: the Westgard rules (1-3s, 2-2s, R-4s, 4-1s, 10x) per point against a sliding-window numpy
    formulation, the plotted points, the seven SD lines and the y reach;
  * stat.concordance_cc: Lin's CCC by definition, r * Cb, the bias correction and Lin's Fisher-z interval,
    plus perfect agreement and the concordance_plot geometry;
  * symmetry_plot: the median-centred tail-distance pairs for odd and even n;
  * stat.box_cox_llf against scipy.stats.boxcox_llf at every grid lambda, and box_cox_profile's maximiser,
    interpolated interval (within a grid step of scipy's boxcox CI) and curve, with an unbracketed grid.
Small-sample, constant-data, bad-shape and short-storage refusals. Each check has its own exit code.
"""
import math
import pathlib
import re

import numpy as np
from scipy import stats

root = pathlib.Path(__file__).resolve().parent.parent
lines = []
code = [0]
rng = np.random.default_rng(20261017)


def check(condition):
    terms = condition.split(' || ')
    for k in range(0, len(terms), 12):
        code[0] += 1
        lines.append('    if %s { os.exit(%d) }' % (' || '.join(terms[k:k + 12]), code[0]))


def arr(values):
    return ', '.join(repr(float(v)) + 'f64' for v in values)


X, Y, W, H = 14.0, 22.0, 300.0, 170.0
lines.append('    let bounds = geometry.rect(%r, %r, %r, %r)' % (X, Y, W, H))

# ---- Levey-Jennings ----
mean, sd = 100.0, 2.0
n = 44
z = rng.normal(0, 0.55, n)
z[5] = 4.5            # 1-3s
z[10], z[11] = 2.3, 2.6    # 2-2s
z[15], z[16] = 2.5, -2.4   # R-4s
z[20:24] = [1.3, 1.6, 1.2, 1.9]  # 4-1s completes at 23
z[30:40] = [0.4, 0.6, 0.3, 0.8, 0.5, 0.2, 0.7, 0.9, 0.35, 0.45]  # 10x completes at 39
values = np.round(mean + sd * z, 4)
zz = (values - mean) / sd
flags = np.zeros(n, dtype=int)
flags[np.abs(zz) > 3] |= 1
for i in range(1, n):
    if (zz[i] > 2 and zz[i - 1] > 2) or (zz[i] < -2 and zz[i - 1] < -2):
        flags[i] |= 2
    if (zz[i] > 2 and zz[i - 1] < -2) or (zz[i] < -2 and zz[i - 1] > 2):
        flags[i] |= 4
windows4 = np.lib.stride_tricks.sliding_window_view(zz, 4)
windows10 = np.lib.stride_tricks.sliding_window_view(zz, 10)
for k, w in enumerate(windows4):
    if (w > 1).all() or (w < -1).all():
        flags[k + 3] |= 8
for k, w in enumerate(windows10):
    if (w > 0).all() or (w < 0).all():
        flags[k + 9] |= 16
for bit in (1, 2, 4, 8, 16):
    assert (flags & bit).any(), bit
reach = max(4.0, float(np.abs(zz).max()))
low = mean - reach * sd
span = 2 * reach * sd
flagged = int((flags != 0).sum())
lines.append('    let qc_values = [%d]f64{ %s }' % (n, arr(values)))
lines.append('    var qc_points: [%d]chart.Coord = zero' % n)
lines.append('    var qc_trace: [%d]chart.Segment = zero' % (n - 1))
lines.append('    var qc_limits: [7]chart.Segment = zero')
lines.append('    var qc_signals: [%d]chart.Coord = zero' % n)
lines.append('    var qc_flags: [%d]u8 = zero' % n)
lines.append('    let (qc, qc_error) = chart.levey_jennings(qc_values[..], %r, %r, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])' % (mean, sd))
check('qc_error != ok || qc.flagged != %dusize || qc.signals.coords.len != %dusize || qc.trace.segments.len != %dusize || qc.limits.segments.len != 7usize' % (flagged, flagged, n - 1))
check(' || '.join('qc_flags[%d] != %du8' % (i, flags[i]) for i in range(n)))
check('!closef(qc.y_limit, %r)' % reach)
parts = []
for i in range(n):
    parts.append('!closef(qc_points[%d].x, %.4f) || !closef(qc_points[%d].y, %.4f)' % (i, X + W * i / (n - 1), i, Y + H - H * (values[i] - low) / span))
check(' || '.join(parts))
parts = []
for lvl in range(7):
    yv = Y + H - H * (lvl - 3 + reach) / (2 * reach)
    parts.append('!closef(qc_limits[%d].from.y, %.4f) || !closef(qc_limits[%d].to.y, %.4f) || !closef(qc_limits[%d].from.x, %r) || !closef(qc_limits[%d].to.x, %r)' % (lvl, yv, lvl, yv, lvl, X, lvl, X + W))
check(' || '.join(parts))
# the mean line sits at the plot's vertical middle and the lines are evenly spaced
check('!closef(qc_limits[3].from.y, %r) || !same(qc_limits[1].from.y - qc_limits[0].from.y, qc_limits[6].from.y - qc_limits[5].from.y)' % (Y + H / 2))
sig = [i for i in range(n) if flags[i]]
check(' || '.join('!closef(qc_signals[%d].x, %.4f) || !closef(qc_signals[%d].y, %.4f)' % (k, X + W * i / (n - 1), k, Y + H - H * (values[i] - low) / span) for k, i in enumerate(sig)))
# an in-control series raises nothing
calm = np.round(mean + sd * np.array([0.1, -0.3, 0.2, -0.5, 0.4, -0.1, 0.3, -0.2, 0.0, 0.5, -0.4, 0.2]), 4)
lines.append('    let calm_values = [%d]f64{ %s }' % (len(calm), arr(calm)))
lines.append('    let (calm, calm_error) = chart.levey_jennings(calm_values[..], %r, %r, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])' % (mean, sd))
check('calm_error != ok || calm.flagged != 0usize || calm.signals.coords.len != 0usize || !closef(calm.y_limit, 4.0)')
lines.append('    let nan = 0.0f64 / zero_f64()')
lines.append('    let (_, qc_one) = chart.levey_jennings(qc_values[..1usize], %r, %r, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])' % (mean, sd))
lines.append('    let (_, qc_none) = chart.levey_jennings(qc_values[..0usize], %r, %r, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])' % (mean, sd))
lines.append('    let (_, qc_sd_zero) = chart.levey_jennings(qc_values[..], %r, 0.0, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])' % mean)
lines.append('    let (_, qc_sd_nan) = chart.levey_jennings(qc_values[..], %r, nan, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])' % mean)
lines.append('    var qc_nan_values = qc_values')
lines.append('    qc_nan_values[3usize] = nan')
lines.append('    let (_, qc_value_nan) = chart.levey_jennings(qc_nan_values[..], %r, %r, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])' % (mean, sd))
lines.append('    let (_, qc_points_room) = chart.levey_jennings(qc_values[..], %r, %r, bounds, qc_points[..%dusize], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])' % (mean, sd, n - 1))
lines.append('    let (_, qc_trace_room) = chart.levey_jennings(qc_values[..], %r, %r, bounds, qc_points[..], qc_trace[..%dusize], qc_limits[..], qc_signals[..], qc_flags[..])' % (mean, sd, n - 2))
lines.append('    let (_, qc_limit_room) = chart.levey_jennings(qc_values[..], %r, %r, bounds, qc_points[..], qc_trace[..], qc_limits[..6usize], qc_signals[..], qc_flags[..])' % (mean, sd))
lines.append('    let (_, qc_signal_room) = chart.levey_jennings(qc_values[..], %r, %r, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..%dusize], qc_flags[..])' % (mean, sd, n - 1))
lines.append('    let (_, qc_flag_room) = chart.levey_jennings(qc_values[..], %r, %r, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..%dusize])' % (mean, sd, n - 1))
lines.append('    let (_, qc_bounds) = chart.levey_jennings(qc_values[..], %r, %r, geometry.Rect { x: 0.0, y: 0.0, width: 0.0, height: 5.0 }, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])' % (mean, sd))
check('qc_one != chart.Invalid || qc_none != chart.Empty || qc_sd_zero != chart.Invalid || qc_sd_nan != chart.Invalid || qc_value_nan != chart.Invalid || qc_bounds != chart.Invalid')
check('qc_points_room != chart.TooLarge || qc_trace_room != chart.TooLarge || qc_limit_room != chart.TooLarge || qc_signal_room != chart.TooLarge || qc_flag_room != chart.TooLarge')

# ---- Lin's concordance ----
m = 30
true = rng.uniform(10, 60, m)
x = np.round(true + rng.normal(0, 2.0, m), 3)
y = np.round(1.08 * true + 2.5 + rng.normal(0, 2.5, m), 3)
mx, my = x.mean(), y.mean()
sxx, syy = x.var(), y.var()              # population (1/n)
sxy = float(np.mean((x - mx) * (y - my)))
ccc = 2 * sxy / (sxx + syy + (mx - my) ** 2)
r = float(np.corrcoef(x, y)[0, 1])
v = math.sqrt(sxx / syy)
u = (mx - my) / (sxx ** 0.25 * syy ** 0.25)
cb = 2 / (v + 1 / v + u * u)
assert abs(ccc - r * cb) < 1e-12 and ccc < r
zc = 1.959963984540054
r2 = r * r
den = 1 - ccc ** 2
var_z = ((1 - r2) * ccc ** 2 * (1 - ccc ** 2) / (r2 * den * den) + 4 * ccc ** 3 * (1 - ccc) * u * u / (r * den * den) - 2 * ccc ** 4 * u ** 4 / (r2 * den * den)) / (m - 2)
zeta = math.atanh(ccc)
lo, hi = math.tanh(zeta - zc * math.sqrt(var_z)), math.tanh(zeta + zc * math.sqrt(var_z))
assert lo < ccc < hi
lines.append('    let cc_x = [%d]f64{ %s }' % (m, arr(x)))
lines.append('    let cc_y = [%d]f64{ %s }' % (m, arr(y)))
lines.append('    let (cc, cc_error) = stat.concordance_cc(cc_x[..], cc_y[..], %r)' % zc)
check('cc_error != ok || !closed(cc.ccc, %r) || !closed(cc.pearson, %r) || !closed(cc.bias_correction, %r)' % (float(ccc), r, float(cb)))
check('!closed(cc.lower, %r) || !closed(cc.upper, %r) || !closed(cc.ccc, cc.pearson * cc.bias_correction)' % (float(lo), float(hi)))
# agreement shrinks with a location shift and with a scale shift, never above r
lines.append('    var shifted: [%d]f64 = zero' % m)
lines.append('    var fill = 0usize')
lines.append('    while fill < %d {' % m)
lines.append('        shifted[fill] = cc_x[fill] + 15.0')
lines.append('        fill += 1usize')
lines.append('    }')
mx2 = mx + 15
ccc_s = 2 * float(np.mean((x - mx) * (x - mx))) / (2 * sxx + 15.0 ** 2)
lines.append('    let (shift_cc, shift_error) = stat.concordance_cc(cc_x[..], shifted[..], %r)' % zc)
check('shift_error != ok || !closed(shift_cc.ccc, %r) || !closed(shift_cc.pearson, 1.0) || !closed(shift_cc.bias_correction, %r)' % (ccc_s, ccc_s))
lines.append('    let (same_cc, same_error) = stat.concordance_cc(cc_x[..], cc_x[..], %r)' % zc)
check('same_error != ok || !closed(same_cc.ccc, 1.0) || !closed(same_cc.lower, 1.0) || !closed(same_cc.upper, 1.0) || !closed(same_cc.bias_correction, 1.0)')
lines.append('    var cc_points: [%d]chart.Coord = zero' % m)
lines.append('    var cc_diagonal: [1]chart.Segment = zero')
lines.append('    let (cc_plot, cc_plot_error) = chart.concordance_plot(cc_x[..], cc_y[..], bounds, cc_points[..], cc_diagonal[..])')
lo_d = min(x.min(), y.min())
hi_d = max(x.max(), y.max())
check('cc_plot_error != ok || cc_plot.coords.len != %dusize' % m)
check(' || '.join('!closef(cc_points[%d].x, %.4f) || !closef(cc_points[%d].y, %.4f)' % (i, X + W * (x[i] - lo_d) / (hi_d - lo_d), i, Y + H - H * (y[i] - lo_d) / (hi_d - lo_d)) for i in range(m)))
check('!closef(cc_diagonal[0].from.x, %r) || !closef(cc_diagonal[0].from.y, %r) || !closef(cc_diagonal[0].to.x, %r) || !closef(cc_diagonal[0].to.y, %r)' % (X, Y + H, X + W, Y))
lines.append('    let cc_two = [2]f64{ 1.0, 2.0 }')
lines.append('    let (_, cc_small) = stat.concordance_cc(cc_two[..], cc_two[..], %r)' % zc)
lines.append('    let cc_flat = [4]f64{ 5.0, 5.0, 5.0, 5.0 }')
lines.append('    let cc_four = [4]f64{ 1.0, 2.0, 3.0, 4.0 }')
lines.append('    let (_, cc_constant) = stat.concordance_cc(cc_flat[..], cc_four[..], %r)' % zc)
lines.append('    let cc_down = [4]f64{ 4.0, 3.0, 2.0, 1.0 }')
lines.append('    let (_, cc_negative) = stat.concordance_cc(cc_four[..], cc_down[..], %r)' % zc)
lines.append('    let (_, cc_shape) = stat.concordance_cc(cc_x[..], cc_y[..%dusize], %r)' % (m - 1, zc))
lines.append('    let (_, cc_z_zero) = stat.concordance_cc(cc_x[..], cc_y[..], 0.0)')
lines.append('    let (_, cc_z_nan) = stat.concordance_cc(cc_x[..], cc_y[..], nan)')
lines.append('    var cc_nan_x = cc_x')
lines.append('    cc_nan_x[4usize] = nan')
lines.append('    let (_, cc_nan) = stat.concordance_cc(cc_nan_x[..], cc_y[..], %r)' % zc)
check('cc_small != stat.Invalid || cc_constant != stat.Invalid || cc_negative != stat.Invalid || cc_shape != stat.Invalid || cc_z_zero != stat.Invalid || cc_z_nan != stat.Invalid || cc_nan != stat.Invalid')
lines.append('    let (_, plot_flat) = chart.concordance_plot(cc_flat[..], cc_flat[..], bounds, cc_points[..], cc_diagonal[..])')
lines.append('    let (_, plot_none) = chart.concordance_plot(cc_x[..0usize], cc_y[..0usize], bounds, cc_points[..], cc_diagonal[..])')
lines.append('    let (_, plot_shape) = chart.concordance_plot(cc_x[..], cc_y[..%dusize], bounds, cc_points[..], cc_diagonal[..])' % (m - 1))
lines.append('    let (_, plot_room) = chart.concordance_plot(cc_x[..], cc_y[..], bounds, cc_points[..%dusize], cc_diagonal[..])' % (m - 1))
lines.append('    let (_, plot_line_room) = chart.concordance_plot(cc_x[..], cc_y[..], bounds, cc_points[..], cc_diagonal[..0usize])')
check('plot_flat != chart.Invalid || plot_none != chart.Empty || plot_shape != chart.Invalid || plot_room != chart.TooLarge || plot_line_room != chart.TooLarge')

# ---- symmetry ----
for label, size in (('odd', 21), ('even', 20)):
    data = np.sort(np.round(rng.lognormal(0.0, 0.6, size) * 10, 3))
    med = float(np.median(data))
    pairs = size // 2
    lower = med - data[:pairs]
    upper = data[::-1][:pairs] - med
    reach = float(max(lower.max(), upper.max()))
    lines.append('    let sym_%s = [%d]f64{ %s }' % (label, size, arr(data)))
    lines.append('    var sym_%s_points: [%d]chart.Coord = zero' % (label, pairs))
    lines.append('    var sym_%s_diagonal: [1]chart.Segment = zero' % label)
    lines.append('    let (sym_%s_plot, sym_%s_error) = chart.symmetry_plot(sym_%s[..], bounds, sym_%s_points[..], sym_%s_diagonal[..])' % (label, label, label, label, label))
    check('sym_%s_error != ok || sym_%s_plot.coords.len != %dusize || !closef(sym_%s_plot.x_max, %r)' % (label, label, pairs, label, reach))
    check(' || '.join('!closef(sym_%s_points[%d].x, %.4f) || !closef(sym_%s_points[%d].y, %.4f)' % (label, i, X + W * lower[i] / reach, label, i, Y + H - H * upper[i] / reach) for i in range(pairs)))
    check('!closef(sym_%s_diagonal[0].from.x, %r) || !closef(sym_%s_diagonal[0].from.y, %r) || !closef(sym_%s_diagonal[0].to.x, %r) || !closef(sym_%s_diagonal[0].to.y, %r)' % (label, X, label, Y + H, label, X + W, label, Y))
lines.append('    let sym_flat = [5]f64{ 2.0, 2.0, 2.0, 2.0, 2.0 }')
lines.append('    let (_, sym_constant) = chart.symmetry_plot(sym_flat[..], bounds, sym_odd_points[..], sym_odd_diagonal[..])')
lines.append('    let sym_down = [5]f64{ 5.0, 4.0, 3.0, 2.0, 1.0 }')
lines.append('    let (_, sym_unsorted) = chart.symmetry_plot(sym_down[..], bounds, sym_odd_points[..], sym_odd_diagonal[..])')
lines.append('    let (_, sym_few) = chart.symmetry_plot(sym_odd[..3usize], bounds, sym_odd_points[..], sym_odd_diagonal[..])')
lines.append('    let (_, sym_none) = chart.symmetry_plot(sym_odd[..0usize], bounds, sym_odd_points[..], sym_odd_diagonal[..])')
lines.append('    var sym_nan_data = sym_odd')
lines.append('    sym_nan_data[2usize] = nan')
lines.append('    let (_, sym_nan) = chart.symmetry_plot(sym_nan_data[..], bounds, sym_odd_points[..], sym_odd_diagonal[..])')
lines.append('    let (_, sym_room) = chart.symmetry_plot(sym_odd[..], bounds, sym_odd_points[..9usize], sym_odd_diagonal[..])')
lines.append('    let (_, sym_line_room) = chart.symmetry_plot(sym_odd[..], bounds, sym_odd_points[..], sym_odd_diagonal[..0usize])')
check('sym_constant != chart.Invalid || sym_unsorted != chart.Invalid || sym_few != chart.Invalid || sym_none != chart.Empty || sym_nan != chart.Invalid || sym_room != chart.TooLarge || sym_line_room != chart.TooLarge')

# ---- Box-Cox ----
data = np.round(rng.lognormal(1.2, 0.55, 40), 4)
grid = np.round(np.linspace(-2.0, 2.0, 41), 10)
assert 0.0 in grid
llf = np.array([stats.boxcox_llf(l, data) for l in grid])
best = int(np.argmax(llf))
drop = stats.chi2.ppf(0.95, 1) / 2
level = llf[best] - drop


# literal replay of the library's two scans
def scan_lower():
    i = best
    while i > 0:
        if llf[i - 1] < level:
            return float(grid[i - 1] + (grid[i] - grid[i - 1]) * (level - llf[i - 1]) / (llf[i] - llf[i - 1])), True
        i -= 1
    return float(grid[0]), False


def scan_upper():
    i = best
    while i + 1 < len(grid):
        if llf[i + 1] < level:
            return float(grid[i] + (grid[i + 1] - grid[i]) * (llf[i] - level) / (llf[i] - llf[i + 1])), True
        i += 1
    return float(grid[-1]), False


lower, has_lower = scan_lower()
upper, has_upper = scan_upper()
assert has_lower and has_upper
lmax, ci = stats.boxcox(data, alpha=0.05)[1:]
assert abs(lower - ci[0]) < 0.1 and abs(upper - ci[1]) < 0.1 and abs(grid[best] - lmax) < 0.1 + 1e-9
lines.append('    let bc_values = [%d]f64{ %s }' % (len(data), arr(data)))
lines.append('    let bc_grid = [%d]f64{ %s }' % (len(grid), arr(grid)))
lines.append('    var bc_llf: [%d]f64 = zero' % len(grid))
lines.append('    var bc_points: [%d]chart.Coord = zero' % len(grid))
lines.append('    var bc_segments: [%d]chart.Segment = zero' % (len(grid) - 1))
lines.append('    let (bc, bc_error) = chart.box_cox_profile(bc_values[..], bc_grid[..], %r, bounds, bc_llf[..], bc_points[..], bc_segments[..])' % float(drop))
check('bc_error != ok || !bc.bracketed || !closed(bc.lambda_hat, %r) || !closed(bc.max_llf, %r)' % (float(grid[best]), float(llf[best])))
check(' || '.join('!closed(bc_llf[%d], %r)' % (i, float(llf[i])) for i in range(len(grid))))
check('!closed(bc.lower, %r) || !closed(bc.upper, %r)' % (lower, upper))
check('bc.lower > bc.lambda_hat || bc.upper < bc.lambda_hat')
low_l, high_l = float(llf.min()), float(llf.max())
parts = []
for i in range(len(grid)):
    parts.append('!closef(bc_points[%d].x, %.4f) || !closef(bc_points[%d].y, %.4f)' % (i, X + W * (grid[i] - grid[0]) / (grid[-1] - grid[0]), i, Y + H - H * (llf[i] - low_l) / (high_l - low_l)))
check(' || '.join(parts))
check('bc.curve.segments.len != %dusize || !closef(bc.curve.y_max, %r) || !closef(bc.curve.y_min, %r)' % (len(grid) - 1, high_l, low_l))
# the log transform at lambda 0 is the same curve evaluated through the log branch
lines.append('    let (zero_llf, zero_error) = stat.box_cox_llf(bc_values[..], 0.0)')
check('zero_error != ok || !closed(zero_llf, %r)' % float(stats.boxcox_llf(0.0, data)))
# an unbracketed grid: the profile is within the drop everywhere on a narrow window
narrow = np.round(np.linspace(0.1, 0.3, 5), 10)
llf_n = np.array([stats.boxcox_llf(l, data) for l in narrow])
bn = int(np.argmax(llf_n))
lines.append('    let bc_narrow = [5]f64{ %s }' % arr(narrow))
lines.append('    let (bc_narrow_profile, bc_narrow_error) = chart.box_cox_profile(bc_values[..], bc_narrow[..], %r, bounds, bc_llf[..], bc_points[..], bc_segments[..])' % float(drop))
check('bc_narrow_error != ok || bc_narrow_profile.bracketed || !closed(bc_narrow_profile.lambda_hat, %r) || !closed(bc_narrow_profile.lower, %r) || !closed(bc_narrow_profile.upper, %r)' % (float(narrow[bn]), float(narrow[0]), float(narrow[-1])))
lines.append('    let bc_negative = [4]f64{ 1.0, 2.0, -3.0, 4.0 }')
lines.append('    let (_, bc_non_positive) = chart.box_cox_profile(bc_negative[..], bc_grid[..], %r, bounds, bc_llf[..], bc_points[..], bc_segments[..])' % float(drop))
lines.append('    let bc_flat = [4]f64{ 3.0, 3.0, 3.0, 3.0 }')
lines.append('    let (_, bc_constant) = chart.box_cox_profile(bc_flat[..], bc_grid[..], %r, bounds, bc_llf[..], bc_points[..], bc_segments[..])' % float(drop))
lines.append('    let (_, bc_two) = chart.box_cox_profile(bc_values[..2usize], bc_grid[..], %r, bounds, bc_llf[..], bc_points[..], bc_segments[..])' % float(drop))
lines.append('    let bc_back = [3]f64{ 1.0, 0.5, 0.0 }')
lines.append('    let (_, bc_order) = chart.box_cox_profile(bc_values[..], bc_back[..], %r, bounds, bc_llf[..], bc_points[..], bc_segments[..])' % float(drop))
lines.append('    let (_, bc_two_grid) = chart.box_cox_profile(bc_values[..], bc_grid[..2usize], %r, bounds, bc_llf[..], bc_points[..], bc_segments[..])' % float(drop))
lines.append('    let (_, bc_drop) = chart.box_cox_profile(bc_values[..], bc_grid[..], 0.0, bounds, bc_llf[..], bc_points[..], bc_segments[..])')
lines.append('    let (_, bc_none) = chart.box_cox_profile(bc_values[..0usize], bc_grid[..], %r, bounds, bc_llf[..], bc_points[..], bc_segments[..])' % float(drop))
lines.append('    let (_, bc_llf_room) = chart.box_cox_profile(bc_values[..], bc_grid[..], %r, bounds, bc_llf[..10usize], bc_points[..], bc_segments[..])' % float(drop))
lines.append('    let (_, bc_points_room) = chart.box_cox_profile(bc_values[..], bc_grid[..], %r, bounds, bc_llf[..], bc_points[..10usize], bc_segments[..])' % float(drop))
lines.append('    let (_, bc_segments_room) = chart.box_cox_profile(bc_values[..], bc_grid[..], %r, bounds, bc_llf[..], bc_points[..], bc_segments[..10usize])' % float(drop))
check('bc_non_positive != chart.Invalid || bc_constant != chart.Invalid || bc_two != chart.Invalid || bc_order != chart.Invalid || bc_two_grid != chart.Invalid || bc_drop != chart.Invalid || bc_none != chart.Empty')
check('bc_llf_room != chart.TooLarge || bc_points_room != chart.TooLarge || bc_segments_room != chart.TooLarge')
lines.append('    let (_, llf_two_error) = stat.box_cox_llf(bc_values[..2usize], 0.5)')
lines.append('    let (_, llf_nan_error) = stat.box_cox_llf(bc_values[..], nan)')
check('llf_two_error != stat.Invalid || llf_nan_error != stat.Invalid')

body = re.sub(r'np\.float64\(([^)]*)\)', r'\1', '\n'.join(line for line in lines if line))
source = '''// The QC and agreement extensions against numpy and scipy (L097, D2265;
// scripts/qc_agreement_reference.py writes this file): the Levey-Jennings Westgard rules and lines, Lin's
// concordance correlation (definition, r * Cb, Fisher-z interval) and its agreement plot, the symmetry plot,
// and the Box-Cox profile (scipy's boxcox_llf at every grid lambda, the maximiser, the interpolated interval).
// Every check has its own exit code.
use e.algo.stat
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
    ret abs64(got - want) <= 1e-9f64 * (1.0f64 + abs64(want))
}

fn same(a: f32, b: f32) -> bool { ret abs64(f64(a) - f64(b)) <= 0.001f64 }

fn closef(got: f32, want: f64) -> bool {
    ret abs64(f64(got) - want) <= 0.0006f64 * (1.0f64 + abs64(want))
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    try io.print("gfx chart qc agreement reference ok\\n")
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'gfx_chart_qc_agreement_reference' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote', code[0], 'checks; CCC %.4f [%.4f, %.4f] r=%.4f, lambda_hat %.2f CI [%.3f, %.3f]' % (ccc, lo, hi, r, grid[best], lower, upper))
