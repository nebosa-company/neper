"""Write tests/selfhost/fixtures/link/gfx_chart_spc_multivariate_reference/src/main.e (L071, D2255).

  python scripts/chart_spc_multivariate_reference.py

The multivariate and ANOM charts of e.gfx.chart against independent numpy/scipy computations on seeded
data: the Hotelling T-squared scores, mean, covariance and upper limit in both phases (the limit from
scipy's F quantile for Phase II and the beta quantile for Phase I, with `alpha` the one-sided false-alarm
probability of a point), the generalized-variance chart (determinants of the subgroup covariances, the
pooled covariance, b1, b2, b3 and the moment-normal limits), the MEWMA smoothed vectors and statistics
(finite-time covariance factor), and ANOM's grand mean, pooled standard deviation and decision limits.
Every check has its own exit code.
"""
import math
import pathlib

import numpy as np
from scipy import stats

root = pathlib.Path(__file__).resolve().parent.parent
lines = []
code = [0]
rng = np.random.default_rng(20261009)


def check(condition):
    code[0] += 1
    lines.append('    if %s { os.exit(%d) }' % (condition, code[0]))


def num(v):
    return repr(float(v))


def farr(name, values):
    flat = np.asarray(values, dtype=float).reshape(-1)
    lines.append('    let %s = [%d]f64{ %s }' % (name, len(flat), ', '.join(num(v) + 'f64' for v in flat)))


def close(got, want, tol=1e-9):
    return 'close(%s, %s, %s)' % (got, num(want) + 'f64', num(tol) + 'f64')


def all_close(got, want, tol=1e-9):
    return 'all_close(%s, %s[..], %s)' % (got, want, num(tol) + 'f64')


# ---- Hotelling T-squared, individuals ----
p = 3
sigma = np.array([[1.0, 0.6, 0.3], [0.6, 1.5, 0.4], [0.3, 0.4, 0.8]])
historical = np.round(rng.multivariate_normal([5.0, 10.0, -2.0], sigma, 30), 4)
monitored = np.round(rng.multivariate_normal([5.0, 10.0, -2.0], sigma, 12), 4)
monitored[5] += [2.5, -3.0, 1.5]
monitored[9] += [4.0, 4.0, -4.0]
farr('hot_historical', historical)
farr('hot_monitored', monitored)
lines.append('    let bounds = geometry.rect(10.0, 20.0, 240.0, 120.0)')
lines.append('    var h_means: [3]f64 = zero')
lines.append('    var h_covariance: [9]f64 = zero')
lines.append('    var h_factor: [9]f64 = zero')
lines.append('    var h_residual: [3]f64 = zero')
lines.append('    var h_scores: [12]f64 = zero')
lines.append('    var h_points: [12]chart.Coord = zero')
lines.append('    var h_segments: [11]chart.Segment = zero')
lines.append('    var h_signals: [12]chart.Coord = zero')
lines.append('    var h_upper: [1]chart.Segment = zero')
lines.append('    var h_storage = chart.HotellingStorage { means: h_means[..], covariance: h_covariance[..], factor: h_factor[..], residual: h_residual[..], scores: h_scores[..], points: h_points[..], segments: h_segments[..], signals: h_signals[..], upper: h_upper[..] }')
mean = historical.mean(axis=0)
cov = np.cov(historical.T, ddof=1)
inv = np.linalg.inv(cov)
scores = np.array([float((x - mean) @ inv @ (x - mean)) for x in monitored])
m = historical.shape[0]
farr('want_hot_mean', mean)
farr('want_hot_cov', cov)
farr('want_hot_scores', scores)
for alpha in (0.05, 0.0027):
    ucl2 = p * (m + 1) * (m - 1) / (m * (m - p)) * stats.f.ppf(1 - alpha, p, m - p)
    name = 'two_%d' % round(alpha * 10000)
    lines.append('    let (%s, %s_error) = chart.hotelling_t2_individuals(hot_monitored[..], 3usize, hot_historical[..], %sf64, bounds, &h_storage)' % (name, name, num(alpha)))
    check('%s_error != ok || !%s.phase_two || %s.historical_count != 30usize' % (name, name, name))
    check('!%s || !%s' % (all_close('%s.means' % name, 'want_hot_mean'), all_close('%s.covariance' % name, 'want_hot_cov')))
    check('!%s' % all_close('%s.scores' % name, 'want_hot_scores', 1e-8))
    check('!%s' % close('%s.upper_limit' % name, ucl2, 1e-9))
    flags = int(np.sum(scores > ucl2))
    check('%s.signals.coords.len != %dusize' % (name, flags))
# Phase I: the baseline is the plotted data; the limit is the beta form.
scores1 = np.array([float((x - mean) @ inv @ (x - mean)) for x in historical])
ucl1 = (m - 1) ** 2 / m * stats.beta.ppf(1 - 0.05, p / 2, (m - p - 1) / 2)
lines.append('    var h1_scores: [30]f64 = zero')
lines.append('    var h1_points: [30]chart.Coord = zero')
lines.append('    var h1_segments: [29]chart.Segment = zero')
lines.append('    var h1_signals: [30]chart.Coord = zero')
lines.append('    var h1_storage = chart.HotellingStorage { means: h_means[..], covariance: h_covariance[..], factor: h_factor[..], residual: h_residual[..], scores: h1_scores[..], points: h1_points[..], segments: h1_segments[..], signals: h1_signals[..], upper: h_upper[..] }')
lines.append('    let (one, one_error) = chart.hotelling_t2_individuals(hot_historical[..], 3usize, hot_historical[..0usize], 0.05f64, bounds, &h1_storage)')
farr('want_hot1_scores', scores1)
check('one_error != ok || one.phase_two || one.historical_count != 30usize || !%s || !%s' % (all_close('one.scores', 'want_hot1_scores', 1e-8), close('one.upper_limit', ucl1, 1e-9)))
check('one.signals.coords.len != %dusize' % int(np.sum(scores1 > ucl1)))

# ---- generalized variance ----
n_sub, p_gv = 6, 3
phase_one = np.round(np.concatenate([rng.multivariate_normal([0, 0, 0], sigma, n_sub) for _ in range(12)]), 4)
phase_two = np.round(np.concatenate([rng.multivariate_normal([0, 0, 0], sigma * (1.0 if k != 2 else 6.0), n_sub) for k in range(4)]), 4)
farr('gv_one', phase_one)
farr('gv_two', phase_two)
covs = [np.cov(phase_one[i * n_sub:(i + 1) * n_sub].T, ddof=1) for i in range(12)]
pooled = sum(covs) / 12
dets = [float(np.linalg.det(c)) for c in covs] + [float(np.linalg.det(np.cov(phase_two[i * n_sub:(i + 1) * n_sub].T, ddof=1))) for i in range(4)]
df = n_sub - 1
b1 = math.prod((n_sub - j) for j in range(1, p_gv + 1)) / df ** p_gv
second = math.prod((n_sub - j) * (n_sub - j + 2) for j in range(1, p_gv + 1)) / df ** (2 * p_gv)
b2 = second - b1 * b1
pooled_df = 12 * df
b3 = math.prod((pooled_df - i) / pooled_df for i in range(p_gv))
det_sigma = float(np.linalg.det(pooled)) / b3
lines.append('    var g_covariance: [9]f64 = zero')
lines.append('    var g_pooled: [9]f64 = zero')
lines.append('    var g_factor: [9]f64 = zero')
lines.append('    var g_determinants: [16]f64 = zero')
lines.append('    var g_points: [16]chart.Coord = zero')
lines.append('    var g_segments: [15]chart.Segment = zero')
lines.append('    var g_signals: [16]chart.Coord = zero')
lines.append('    var g_upper: [1]chart.Segment = zero')
lines.append('    var g_lower: [1]chart.Segment = zero')
lines.append('    var g_center: [1]chart.Segment = zero')
lines.append('    var g_storage = chart.GeneralizedVarianceStorage { covariance: g_covariance[..], pooled: g_pooled[..], factor: g_factor[..], determinants: g_determinants[..], points: g_points[..], segments: g_segments[..], signals: g_signals[..], upper: g_upper[..], lower: g_lower[..], center: g_center[..] }')
farr('want_gv_dets', dets)
farr('want_gv_pooled', pooled)
for sided, two in (('one_sided', False), ('two_sided', True)):
    alpha = 0.0027
    tail = alpha / 2 if two else alpha
    z = float(stats.norm.ppf(1 - tail))
    center = b1 * det_sigma
    upper = center + z * math.sqrt(b2) * det_sigma
    lower = max(0.0, center - z * math.sqrt(b2) * det_sigma) if two else 0.0
    lines.append('    let (gv_%s, gv_%s_error) = chart.generalized_variance(gv_one[..], gv_two[..], 6usize, 3usize, %sf64, %s, bounds, &g_storage)' % (sided, sided, num(alpha), 'true' if two else 'false'))
    check('gv_%s_error != ok || gv_%s.phase_one_count != 12usize || gv_%s.phase_two_count != 4usize' % (sided, sided, sided))
    check('!%s || !%s' % (all_close('gv_%s.determinants' % sided, 'want_gv_dets', 1e-8), all_close('gv_%s.pooled_covariance' % sided, 'want_gv_pooled', 1e-9)))
    check('!%s || !%s || !%s' % (close('gv_%s.b1' % sided, b1, 1e-12), close('gv_%s.b2' % sided, b2, 1e-12), close('gv_%s.b3' % sided, b3, 1e-12)))
    check('!%s || !%s || !%s' % (close('gv_%s.center_value' % sided, center, 1e-9), close('gv_%s.upper_limit' % sided, upper, 1e-8), close('gv_%s.lower_limit' % sided, lower, 1e-8)))
    flags = sum(1 for d in dets if d > upper or d < lower)
    check('gv_%s.signals.coords.len != %dusize' % (sided, flags))

# ---- MEWMA ----
lam = 0.2
mw_hist = historical
mw_values = monitored
mean_w = mw_hist.mean(axis=0)
cov_w = np.cov(mw_hist.T, ddof=1)
z = np.zeros(p)
smoothed = []
mscores = []
for i, x in enumerate(mw_values, start=1):
    z = lam * (x - mean_w) + (1 - lam) * z
    smoothed.append(z + mean_w)
    factor = lam / (2 - lam) * (1 - (1 - lam) ** (2 * i))
    mscores.append(float(z @ np.linalg.inv(factor * cov_w) @ z))
mscores = np.array(mscores)
limit = 11.5
farr('want_mw_smoothed', np.array(smoothed))
farr('want_mw_scores', mscores)
lines.append('    var m_means: [3]f64 = zero')
lines.append('    var m_covariance: [9]f64 = zero')
lines.append('    var m_factor: [9]f64 = zero')
lines.append('    var m_state: [3]f64 = zero')
lines.append('    var m_residual: [3]f64 = zero')
lines.append('    var m_smoothed: [36]f64 = zero')
lines.append('    var m_scores: [12]f64 = zero')
lines.append('    var m_points: [12]chart.Coord = zero')
lines.append('    var m_segments: [11]chart.Segment = zero')
lines.append('    var m_signals: [12]chart.Coord = zero')
lines.append('    var m_upper: [1]chart.Segment = zero')
lines.append('    var m_storage = chart.MewmaStorage { means: m_means[..], covariance: m_covariance[..], factor: m_factor[..], state: m_state[..], residual: m_residual[..], smoothed: m_smoothed[..], scores: m_scores[..], points: m_points[..], segments: m_segments[..], signals: m_signals[..], upper: m_upper[..] }')
lines.append('    let (mewma, mewma_error) = chart.mewma(hot_monitored[..], 3usize, hot_historical[..], %sf64, %sf64, bounds, &m_storage)' % (num(lam), num(limit)))
check('mewma_error != ok || !mewma.phase_two || mewma.historical_count != 30usize')
check('!%s || !%s' % (all_close('mewma.smoothed', 'want_mw_smoothed', 1e-9), all_close('mewma.scores', 'want_mw_scores', 1e-8)))
check('mewma.signals.coords.len != %dusize' % int(np.sum(mscores > limit)))

# ---- ANOM ----
sizes = [6, 9, 5, 8]
means_true = [10.0, 10.4, 9.2, 11.0]
values = []
ids = []
for g, (n, mu) in enumerate(zip(sizes, means_true)):
    values += list(np.round(rng.normal(mu, 0.5, n), 3))
    ids += [g] * n
values = np.array(values)
ids = np.array(ids)
farr('anom_values', values)
lines.append('    let anom_ids = [%d]usize{ %s }' % (len(ids), ', '.join('%dusize' % i for i in ids)))
lines.append('    var a_points: [4]chart.Coord = zero')
lines.append('    var a_signals: [4]chart.Coord = zero')
lines.append('    var a_upper: [4]chart.Segment = zero')
lines.append('    var a_lower: [4]chart.Segment = zero')
lines.append('    var a_center: [1]chart.Segment = zero')
lines.append('    var a_means: [4]f64 = zero')
lines.append('    var a_counts: [4]usize = zero')
lines.append('    var a_upper_limits: [4]f64 = zero')
lines.append('    var a_lower_limits: [4]f64 = zero')
lines.append('    var a_storage = chart.AnomStorage { points: a_points[..], signals: a_signals[..], upper: a_upper[..], lower: a_lower[..], center: a_center[..], means: a_means[..], counts: a_counts[..], upper_limits: a_upper_limits[..], lower_limits: a_lower_limits[..] }')
h = 3.0
lines.append('    let (anom, anom_error) = chart.anom(anom_values[..], anom_ids[..], 4usize, %sf64, bounds, &a_storage)' % num(h))
grand = float(values.mean())
group_means = [float(values[ids == g].mean()) for g in range(4)]
sse = float(sum(np.sum((values[ids == g] - group_means[g]) ** 2) for g in range(4)))
pooled_sd = math.sqrt(sse / (len(values) - 4))
upper = [grand + h * pooled_sd * math.sqrt((len(values) - n) / (len(values) * n)) for n in sizes]
lower = [grand - h * pooled_sd * math.sqrt((len(values) - n) / (len(values) * n)) for n in sizes]
check('anom_error != ok || !%s || !%s' % (close('anom.grand_mean', grand), close('anom.pooled_sd', pooled_sd)))
parts = []
for g in range(4):
    parts.append('!%s' % close('anom.means[%d]' % g, group_means[g]))
    parts.append('!%s' % close('anom.upper_limits[%d]' % g, upper[g]))
    parts.append('!%s' % close('anom.lower_limits[%d]' % g, lower[g]))
    parts.append('anom.counts[%d] != %dusize' % (g, sizes[g]))
check(' || '.join(parts))
flagged = sum(1 for g in range(4) if group_means[g] > upper[g] or group_means[g] < lower[g])
check('anom.signals.coords.len != %dusize' % flagged)
print('hotelling signals', int(np.sum(scores > ucl2)), 'gv', [sum(1 for d in dets if d > upper_ or d < lo_) for upper_, lo_ in ((center + 3 * math.sqrt(b2) * det_sigma, 0.0),)], 'mewma', int(np.sum(mscores > limit)), 'anom', flagged)

body = '\n'.join(lines)
source = '''// The multivariate SPC charts and ANOM of e.gfx.chart against independent numpy and scipy computations
// (L071, D2255; scripts/chart_spc_multivariate_reference.py writes this file): Hotelling T-squared in both
// phases with the F and beta limits, the generalized-variance chart with its moment-normal limits, MEWMA with
// the finite-time covariance factor, and ANOM's decision limits. Every check has its own exit code.
use e.gfx.chart
use e.gfx.geometry
use e.mem
use e.os

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn close(got: f64, want: f64, tolerance: f64) -> bool {
    ret abs64(got - want) <= tolerance * (1.0f64 + abs64(want))
}

fn all_close(got: []const f64, want: []const f64, tolerance: f64) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if !close(got[i], want[i], tolerance) { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    let (written, write_error) = os.write(os.stdout(), "gfx chart spc multivariate reference ok\\n")
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'gfx_chart_spc_multivariate_reference' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote gfx_chart_spc_multivariate_reference with', code[0], 'checks')
