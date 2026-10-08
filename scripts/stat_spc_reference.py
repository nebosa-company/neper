"""Write tests/selfhost/fixtures/link/algo_stat_spc_reference/src/main.e (L071, D2255).

  python scripts/stat_spc_reference.py

The statistical estimators behind the SPC, capability and measurement-system charts, checked against
independent numpy and scipy computations on seeded data: individuals/moving-range limits, X-bar/R and
X-bar/S limits (the A2/D3/D4 table against the constants recomputed from d2 and d3, c4 from the gamma
function), normal, batch and lognormal capability with their ppm, the P, nP, C and U attribute limits,
Laney P-prime and U-prime (and the phased form), G chart limits (solved from the piecewise-linear
geometric CDF), T chart limits (the exponential quantiles), the Nelson/Western Electric run-rule flags,
Gage linearity (OLS with scipy's t distribution), and attribute agreement (Clopper-Pearson from the beta
quantile, kappa from the marginals). Every check has its own exit code.
"""
import math
import pathlib

import numpy as np
from scipy import optimize, stats

root = pathlib.Path(__file__).resolve().parent.parent
lines = []
code = [0]
rng = np.random.default_rng(20261008)


def check(condition):
    code[0] += 1
    lines.append('    if %s { os.exit(%d) }' % (condition, code[0]))


def num(v):
    return repr(float(v))


def farr(name, values):
    lines.append('    let %s = [%d]f64{ %s }' % (name, len(values), ', '.join(num(v) + 'f64' for v in values)))


def uarr(name, values):
    lines.append('    let %s = [%d]usize{ %s }' % (name, len(values), ', '.join('%dusize' % v for v in values)))


def barr(name, values):
    lines.append('    let %s = [%d]bool{ %s }' % (name, len(values), ', '.join('true' if v else 'false' for v in values)))


def close(got, want, tol=1e-9):
    return 'close(%s, %s, %s)' % (got, num(want) + 'f64', num(tol) + 'f64')


# ---- individuals / moving range and normal capability ----
x = np.round(10.0 + 0.5 * rng.standard_normal(40) + np.linspace(0, 0.4, 40), 3)
lsl, usl = 8.5, 11.5
farr('imr_x', x)
lines.append('    var moving: [39]f64 = zero')
lines.append('    let (individuals, mr, imr_error) = stat.imr_limits(imr_x[..], moving[..])')
mr_values = np.abs(np.diff(x))
mean = float(np.mean(x))
mr_bar = float(np.mean(mr_values))
check('imr_error != ok || !%s || !%s || !%s' % (close('individuals.center', mean), close('individuals.lower', mean - 3 * mr_bar / 1.128), close('individuals.upper', mean + 3 * mr_bar / 1.128)))
check('!%s || !%s || mr.lower != 0.0f64 || !%s' % (close('mr.center', mr_bar), close('mr.upper', 3.267 * mr_bar), close('moving[38]', float(mr_values[-1]))))
lines.append('    var moving2: [39]f64 = zero')
lines.append('    let (capability, capability_error) = stat.normal_capability_individuals(imr_x[..], %sf64, %sf64, moving2[..])' % (num(lsl), num(usl)))
within = mr_bar / 1.128
overall = float(np.std(x, ddof=1))
cp, pp = (usl - lsl) / (6 * within), (usl - lsl) / (6 * overall)
closest = min(mean - lsl, usl - mean)
check('capability_error != ok || !%s || !%s || !%s' % (close('capability.within_sigma', within), close('capability.overall_sigma', overall), close('capability.mean', mean)))
check('!%s || !%s || !%s || !%s' % (close('capability.cp', cp), close('capability.cpk', closest / (3 * within)), close('capability.pp', pp), close('capability.ppk', closest / (3 * overall))))
lines.append('    let (performance, performance_error) = stat.normal_capability_performance(imr_x[..], %sf64, %sf64, capability)' % (num(lsl), num(usl)))
million = 1e6
below = int(np.sum(x < lsl))
above = int(np.sum(x > usl))
check('performance_error != ok || !%s || !%s' % (close('performance.observed_below_ppm', million * below / len(x)), close('performance.observed_above_ppm', million * above / len(x))))
check('!%s || !%s || !%s || !%s' % (
    close('performance.within_below_ppm', million * stats.norm.cdf((lsl - mean) / within), 1e-7),
    close('performance.within_above_ppm', million * stats.norm.sf((usl - mean) / within), 1e-7),
    close('performance.overall_below_ppm', million * stats.norm.cdf((lsl - mean) / overall), 1e-7),
    close('performance.overall_above_ppm', million * stats.norm.sf((usl - mean) / overall), 1e-7)))

# ---- batch capability ----
batch_size, batches = 5, 8
between = rng.normal(0, 0.35, batches)
batch_values = np.round(np.concatenate([10.2 + b + 0.3 * rng.standard_normal(batch_size) for b in between]), 3)
farr('batch_x', batch_values)
lines.append('    var batch_means: [8]f64 = zero')
lines.append('    var batch_spreads: [8]f64 = zero')
lines.append('    let (batch, batch_error) = stat.batch_capability(batch_x[..], 5usize, 9.0f64, 11.5f64, batch_means[..], batch_spreads[..])')
groups = batch_values.reshape(batches, batch_size)
ms_within = float(np.sum((groups - groups.mean(axis=1, keepdims=True)) ** 2) / (batches * (batch_size - 1)))
grand = float(batch_values.mean())
ms_between = float(batch_size * np.sum((groups.mean(axis=1) - grand) ** 2) / (batches - 1))
between_var = max((ms_between - ms_within) / batch_size, 0.0)
combined = math.sqrt(ms_within + between_var)
overall_b = float(np.std(batch_values, ddof=1))
w = 11.5 - 9.0
c = min(grand - 9.0, 11.5 - grand)
check('batch_error != ok || !%s || !%s || !%s || !%s' % (close('batch.within_sigma', math.sqrt(ms_within)), close('batch.between_sigma', math.sqrt(between_var)), close('batch.between_within_sigma', combined), close('batch.overall_sigma', overall_b)))
check('!%s || !%s || !%s || !%s' % (close('batch.cp', w / (6 * combined)), close('batch.cpk', c / (3 * combined)), close('batch.pp', w / (6 * overall_b)), close('batch.ppk', c / (3 * overall_b))))
check('!%s || !%s || !%s' % (close('batch.observed_ppm', million * float(np.sum((batch_values < 9.0) | (batch_values > 11.5))) / len(batch_values)),
                              close('batch.expected_bw_ppm', million * (stats.norm.cdf((9.0 - grand) / combined) + stats.norm.sf((11.5 - grand) / combined)), 1e-7),
                              close('batch.expected_overall_ppm', million * (stats.norm.cdf((9.0 - grand) / overall_b) + stats.norm.sf((11.5 - grand) / overall_b)), 1e-7)))
check('!%s || !%s' % (close('batch_means[3]', float(groups[3].mean())), close('batch_spreads[3]', float(groups[3].std(ddof=1)))))

# ---- lognormal capability ----
logn = np.round(np.exp(rng.normal(math.log(4.0), 0.25, 30)), 3)
farr('logn_x', logn)
lines.append('    let (lognormal, lognormal_error) = stat.lognormal_capability(logn_x[..], 2.0f64, 9.0f64)')
logs = np.log(logn)
mu, sigma = float(logs.mean()), float(logs.std(ddof=0))
zl, zu = (math.log(2.0) - mu) / sigma, (math.log(9.0) - mu) / sigma
check('lognormal_error != ok || !%s || !%s || !%s' % (close('lognormal.log_mean', mu), close('lognormal.log_sigma', sigma), close('lognormal.median', math.exp(mu))))
check('!%s || !%s || !%s || !%s' % (close('lognormal.pp', (zu - zl) / 6), close('lognormal.ppl', -zl / 3), close('lognormal.ppu', zu / 3), close('lognormal.ppk', min(-zl / 3, zu / 3))))
check('!%s || !%s' % (close('lognormal.expected_below_ppm', million * stats.norm.cdf(zl), 1e-7), close('lognormal.expected_above_ppm', million * stats.norm.sf(zu), 1e-7)))

# ---- X-bar/R and X-bar/S limits ----
d2 = {2: 1.128, 3: 1.693, 4: 2.059, 5: 2.326, 6: 2.534, 7: 2.704, 8: 2.847, 9: 2.970, 10: 3.078}
d3 = {2: 0.853, 3: 0.888, 4: 0.880, 5: 0.864, 6: 0.848, 7: 0.833, 8: 0.820, 9: 0.808, 10: 0.797}
for size in (2, 5, 9):
    sub = np.round(rng.normal(50, 2, 12 * size), 3)
    groups = sub.reshape(12, size)
    farr('xr_%d' % size, sub)
    lines.append('    var xr_means_%d: [12]f64 = zero' % size)
    lines.append('    var xr_ranges_%d: [12]f64 = zero' % size)
    lines.append('    let (xr_mean_%d, xr_range_%d, xr_error_%d) = stat.xbar_r_limits(xr_%d[..], %dusize, xr_means_%d[..], xr_ranges_%d[..])' % (size, size, size, size, size, size, size))
    rbar = float(np.mean(groups.max(axis=1) - groups.min(axis=1)))
    xbb = float(groups.mean())
    a2 = 3.0 / (d2[size] * math.sqrt(size))
    d3f = max(0.0, 1.0 - 3.0 * d3[size] / d2[size])
    d4f = 1.0 + 3.0 * d3[size] / d2[size]
    # The table carries three decimals; the recomputed constants agree to 5e-4 of R-bar.
    check('xr_error_%d != ok || !%s || !%s || !%s' % (size, close('xr_mean_%d.center' % size, xbb), close('xr_mean_%d.upper' % size, xbb + a2 * rbar, 6e-4), close('xr_mean_%d.lower' % size, xbb - a2 * rbar, 6e-4)))
    check('!%s || !%s || !%s' % (close('xr_range_%d.center' % size, rbar), close('xr_range_%d.upper' % size, d4f * rbar, 6e-4), close('xr_range_%d.lower' % size, d3f * rbar, 6e-4)))
    lines.append('    var xs_means_%d: [12]f64 = zero' % size)
    lines.append('    var xs_devs_%d: [12]f64 = zero' % size)
    lines.append('    let (xs_mean_%d, xs_dev_%d, xs_error_%d) = stat.xbar_s_limits(xr_%d[..], %dusize, xs_means_%d[..], xs_devs_%d[..])' % (size, size, size, size, size, size, size))
    sbar = float(np.mean(groups.std(axis=1, ddof=1)))
    n = float(size)
    c4 = math.sqrt(2.0 / (n - 1.0)) * math.exp(math.lgamma(n / 2.0) - math.lgamma((n - 1.0) / 2.0))
    a3 = 3.0 / (c4 * math.sqrt(n))
    b3 = max(0.0, 1.0 - 3.0 * math.sqrt(1.0 - c4 * c4) / c4)
    b4 = 1.0 + 3.0 * math.sqrt(1.0 - c4 * c4) / c4
    check('xs_error_%d != ok || !%s || !%s || !%s' % (size, close('xs_mean_%d.upper' % size, xbb + a3 * sbar), close('xs_mean_%d.lower' % size, xbb - a3 * sbar), close('xs_dev_%d.center' % size, sbar)))
    check('!%s || !%s' % (close('xs_dev_%d.upper' % size, b4 * sbar), close('xs_dev_%d.lower' % size, b3 * sbar)))

# ---- attribute control limits ----
sizes_p = np.array([50, 80, 60, 100, 75, 90, 55, 120, 70, 85, 65, 110])
counts_p = np.array([4, 9, 3, 12, 6, 14, 2, 9, 5, 7, 4, 13])
uarr('p_counts', counts_p)
uarr('p_sizes', sizes_p)
lines.append('    var p_out: [12]stat.AttributeControlPoint = zero')
lines.append('    let p_error = stat.attribute_control(.P, p_counts[..], p_sizes[..], p_out[..])')
pbar = counts_p.sum() / sizes_p.sum()
ok_p = ['p_error != ok']
for i in range(12):
    sd = math.sqrt(pbar * (1 - pbar) / sizes_p[i])
    ok_p.append('!%s' % close('p_out[%d].value' % i, counts_p[i] / sizes_p[i]))
    ok_p.append('!%s' % close('p_out[%d].upper' % i, min(pbar + 3 * sd, 1.0)))
    ok_p.append('!%s' % close('p_out[%d].lower' % i, max(pbar - 3 * sd, 0.0)))
check(' || '.join(ok_p[:19]))
check(' || '.join(ok_p[19:]))
equal = np.full(12, 60)
counts_np = np.array([3, 5, 2, 8, 4, 6, 1, 7, 5, 4, 9, 3])
uarr('np_counts', counts_np)
uarr('np_sizes', equal)
lines.append('    var np_out: [12]stat.AttributeControlPoint = zero')
lines.append('    let np_error = stat.attribute_control(.Np, np_counts[..], np_sizes[..], np_out[..])')
rate = counts_np.sum() / equal.sum()
npbar = 60 * rate
sd = math.sqrt(npbar * (1 - rate))
check('np_error != ok || !%s || !%s || !%s || !%s' % (close('np_out[0].center', npbar), close('np_out[0].upper', min(npbar + 3 * sd, 60.0)), close('np_out[0].lower', max(npbar - 3 * sd, 0.0)), close('np_out[4].value', float(counts_np[4]))))
counts_c = np.array([6, 9, 4, 11, 7, 5, 8, 12, 6, 3])
uarr('c_counts', counts_c)
uarr('c_sizes', np.ones(10, dtype=int))
lines.append('    var c_out: [10]stat.AttributeControlPoint = zero')
lines.append('    let c_error = stat.attribute_control(.C, c_counts[..], c_sizes[..], c_out[..])')
cbar = counts_c.mean()
check('c_error != ok || !%s || !%s || !%s' % (close('c_out[0].center', cbar), close('c_out[0].upper', cbar + 3 * math.sqrt(cbar)), close('c_out[0].lower', max(cbar - 3 * math.sqrt(cbar), 0.0))))
sizes_u = np.array([20, 35, 25, 40, 30, 22, 38, 28])
counts_u = np.array([5, 9, 4, 14, 7, 3, 11, 6])
uarr('u_counts', counts_u)
uarr('u_sizes', sizes_u)
lines.append('    var u_out: [8]stat.AttributeControlPoint = zero')
lines.append('    let u_error = stat.attribute_control(.U, u_counts[..], u_sizes[..], u_out[..])')
ubar = counts_u.sum() / sizes_u.sum()
check('u_error != ok || !%s || !%s || !%s' % (close('u_out[1].center', ubar), close('u_out[1].upper', ubar + 3 * math.sqrt(ubar / sizes_u[1])), close('u_out[1].value', counts_u[1] / sizes_u[1])))


# ---- Laney P-prime and U-prime ----
def laney(kind, counts, sizes):
    counts = np.asarray(counts, dtype=float)
    sizes = np.asarray(sizes, dtype=float)
    center = counts.sum() / sizes.sum()
    values = counts / sizes
    var = center * (1 - center) / sizes if kind == 'P' else center / sizes
    z = (values - center) / np.sqrt(var)
    sigma_z = float(np.mean(np.abs(np.diff(z))) / 1.128)
    spread = 3 * np.sqrt(var) * sigma_z
    lower = np.maximum(center - spread, 0.0)
    upper = center + spread
    if kind == 'P':
        upper = np.minimum(upper, 1.0)
    return sigma_z, lower, upper


for kind, counts, sizes, name in (('P', counts_p, sizes_p, 'p'), ('U', counts_u, sizes_u, 'u')):
    kind_text = '.P' if kind == 'P' else '.U'
    lines.append('    var laney_%s: [%d]stat.AttributeControlPoint = zero' % (name, len(counts)))
    lines.append('    let (sigma_%s, laney_error_%s) = stat.laney_control(%s, %s_counts[..], %s_sizes[..], laney_%s[..])' % (name, name, kind_text, name, name, name))
    sigma_z, lower, upper = laney(kind, counts, sizes)
    parts = ['laney_error_%s != ok' % name, '!%s' % close('sigma_%s' % name, sigma_z)]
    for i in range(len(counts)):
        parts.append('!%s' % close('laney_%s[%d].lower' % (name, i), lower[i]))
        parts.append('!%s' % close('laney_%s[%d].upper' % (name, i), upper[i]))
    check(' || '.join(parts[:12]))
    if len(parts) > 12:
        check(' || '.join(parts[12:]))
# Phased: two phases with their own baseline and sigma-z.
starts = [True] + [False] * 5 + [True] + [False] * 5
barr('phase_starts', starts)
lines.append('    var phased: [12]stat.AttributeControlPoint = zero')
lines.append('    var phased_sigma: [12]f64 = zero')
lines.append('    let phased_error = stat.laney_control_phased(.P, p_counts[..], p_sizes[..], phase_starts[..], phased[..], phased_sigma[..])')
parts = ['phased_error != ok']
for begin, end in ((0, 6), (6, 12)):
    sigma_z, lower, upper = laney('P', counts_p[begin:end], sizes_p[begin:end])
    parts.append('!%s' % close('phased_sigma[%d]' % begin, sigma_z))
    for i in range(begin, end, 2):
        parts.append('!%s' % close('phased[%d].upper' % i, upper[i - begin]))
        parts.append('!%s' % close('phased[%d].lower' % i, lower[i - begin]))
check(' || '.join(parts))

# ---- G and T charts ----
def geometric_gap_percentile(p, f):
    """The gap (non-events between events) at fraction f of the geometric CDF made piecewise linear between integers."""
    def cdf(trials):
        k = math.floor(trials)
        lo = 1.0 - (1.0 - p) ** k
        hi = 1.0 - (1.0 - p) ** (k + 1)
        return lo + (trials - k) * (hi - lo)
    if p == 1.0:
        return 0.0
    solved = optimize.brentq(lambda t: cdf(t) - f, 0.0, 1e6, xtol=1e-14, rtol=1e-14)
    return max(solved - 1.0, 0.0)


gaps = np.array([3, 0, 5, 12, 1, 7, 2, 0, 9, 4, 6, 15])
uarr('gaps', gaps)
lines.append('    let (g_limits, g_error) = stat.g_control_limits(gaps[..])')
p = 1.0 / (gaps.mean() + 1.0)
check('g_error != ok || !%s || !%s || !%s' % (close('g_limits.center', geometric_gap_percentile(p, 0.5), 1e-8), close('g_limits.lower', geometric_gap_percentile(p, 0.00135), 1e-8), close('g_limits.upper', geometric_gap_percentile(p, 0.99865), 1e-8)))
intervals = np.round(rng.exponential(2.5, 15), 3)
farr('intervals', intervals)
lines.append('    let (t_limits, t_error) = stat.t_exponential_control_limits(intervals[..])')
scale = float(intervals.mean())
check('t_error != ok || !%s || !%s || !%s' % (close('t_limits.center', stats.expon.ppf(0.5, scale=scale)), close('t_limits.lower', stats.expon.ppf(0.00135, scale=scale)), close('t_limits.upper', stats.expon.ppf(0.99865, scale=scale))))


# ---- the run rules (Nelson 1-8) ----
def nelson(values, centers, sigmas, starts=None):
    n = len(values)
    z = (values - centers) / sigmas
    flags = {k: np.zeros(n, dtype=bool) for k in ('beyond3', 'same_side9', 'trend6', 'alternating14', 'two_of_three2', 'four_of_five1', 'within1_15', 'outside1_8')}
    begin = 0
    for i in range(n):
        if starts is not None and i > 0 and starts[i]:
            begin = i
        seg = slice(begin, i + 1)
        zs = z[seg]
        vs = values[seg]
        flags['beyond3'][i] = abs(z[i]) > 3
        if len(zs) >= 9:
            last = zs[-9:]
            flags['same_side9'][i] = bool(np.all(last > 0) or np.all(last < 0))
        if len(vs) >= 6:
            d = np.diff(vs[-6:])
            flags['trend6'][i] = bool(np.all(d > 0) or np.all(d < 0))
        if len(vs) >= 14:
            d = np.diff(vs[-14:])
            flags['alternating14'][i] = bool(np.all(d[1:] * d[:-1] < 0) and np.all(d != 0))
        if len(zs) >= 3:
            last = zs[-3:]
            flags['two_of_three2'][i] = bool(np.sum(last > 2) >= 2 or np.sum(last < -2) >= 2)
        if len(zs) >= 5:
            last = zs[-5:]
            flags['four_of_five1'][i] = bool(np.sum(last > 1) >= 4 or np.sum(last < -1) >= 4)
        if len(zs) >= 15:
            flags['within1_15'][i] = bool(np.all(np.abs(zs[-15:]) <= 1))
        if len(zs) >= 8:
            flags['outside1_8'][i] = bool(np.all(np.abs(zs[-8:]) > 1))
    return flags


series = rng.normal(0.0, 1.0, 140)
series[10:19] = np.abs(rng.normal(0.8, 0.2, 9)) + 0.1           # nine on one side
series[30:37] = np.linspace(-0.5, 1.5, 7)                         # a run up
series[50:66] = np.where(np.arange(16) % 2 == 0, 0.6, -0.6)       # an alternating run
series[80] = 3.4                                                  # a point beyond three sigma
series[90:93] = [2.3, 0.2, 2.6]                                   # two of three beyond two sigma
series[100:115] = rng.uniform(-0.9, 0.9, 15)                      # fifteen within one sigma
series[120:128] = np.where(np.arange(8) % 2 == 0, 1.4, -1.6)      # eight beyond one sigma
series = np.round(series, 3)
farr('series', series)
farr('centers', np.zeros(140))
farr('sigmas', np.ones(140))
lines.append('    var signals: [140]stat.ControlSignal = zero')
lines.append('    let signal_error = stat.control_run_rules(series[..], centers[..], sigmas[..], signals[..])')
flags = nelson(series, np.zeros(140), np.ones(140))
check('signal_error != ok')
for key in ('beyond3', 'same_side9', 'trend6', 'alternating14', 'two_of_three2', 'four_of_five1', 'within1_15', 'outside1_8'):
    want = flags[key]
    lines.append('    let want_%s = [140]bool{ %s }' % (key, ', '.join('true' if v else 'false' for v in want)))
    lines.append('    var %s_ok = true' % key)
    lines.append('    var %s_i = 0usize' % key)
    lines.append('    while %s_i < 140usize {' % key)
    lines.append('        if signals[%s_i].%s != want_%s[%s_i] { %s_ok = false }' % (key, key, key, key, key))
    lines.append('        %s_i += 1usize' % key)
    lines.append('    }')
    check('!%s_ok' % key)
    print(key, int(want.sum()))
phase = [False] * 140
phase[0] = True
phase[70] = True
barr('run_starts', phase)
lines.append('    var phased_signals: [140]stat.ControlSignal = zero')
lines.append('    let phased_signal_error = stat.control_run_rules_phased(series[..], centers[..], sigmas[..], run_starts[..], phased_signals[..])')
flags_phased = nelson(series, np.zeros(140), np.ones(140), phase)
check('phased_signal_error != ok')
for key in ('same_side9', 'trend6', 'four_of_five1', 'within1_15'):
    want = flags_phased[key]
    lines.append('    let pwant_%s = [140]bool{ %s }' % (key, ', '.join('true' if v else 'false' for v in want)))
    lines.append('    var p%s_ok = true' % key)
    lines.append('    var p%s_i = 0usize' % key)
    lines.append('    while p%s_i < 140usize {' % key)
    lines.append('        if phased_signals[p%s_i].%s != pwant_%s[p%s_i] { p%s_ok = false }' % (key, key, key, key, key))
    lines.append('        p%s_i += 1usize' % key)
    lines.append('    }')
    check('!p%s_ok' % key)

# ---- Gage linearity ----
references = np.array([2.0, 4.0, 6.0, 8.0, 10.0])
repeats = 3
biases_true = 0.05 + 0.02 * references
measurements = np.concatenate([references[i] + biases_true[i] + 0.04 * rng.standard_normal(repeats) for i in range(5)])
measurements = np.round(measurements, 4)
farr('gl_references', references)
farr('gl_measurements', measurements)
critical = float(stats.t.ppf(0.975, len(measurements) - 2))
lines.append('    var gl_biases: [15]f64 = zero')
lines.append('    var gl_means: [5]f64 = zero')
lines.append('    var gl_fitted: [5]f64 = zero')
lines.append('    var gl_lower: [5]f64 = zero')
lines.append('    var gl_upper: [5]f64 = zero')
lines.append('    let (linearity, linearity_error) = stat.gage_linearity(gl_references[..], gl_measurements[..], 3usize, %sf64, gl_biases[..], gl_means[..], gl_fitted[..], gl_lower[..], gl_upper[..])' % num(critical))
xs = np.repeat(references, repeats)
ys = measurements - xs
res = stats.linregress(xs, ys)
residual_sigma = math.sqrt(np.sum((ys - (res.intercept + res.slope * xs)) ** 2) / (len(xs) - 2))
check('linearity_error != ok || !%s || !%s || !%s' % (close('linearity.slope', res.slope), close('linearity.intercept', res.intercept), close('linearity.average_bias', float(ys.mean()))))
check('!%s || !%s || !%s || !%s' % (close('linearity.residual_sigma', residual_sigma), close('linearity.slope_standard_error', res.stderr), close('linearity.slope_p', res.pvalue, 1e-7), close('linearity.linearity', res.slope * (references[-1] - references[0]))))
mean_x = xs.mean()
sxx = np.sum((xs - mean_x) ** 2)
mse = residual_sigma ** 2
parts = []
for i, ref in enumerate(references):
    fit = res.intercept + res.slope * ref
    se = math.sqrt(mse * (1.0 / len(xs) + (ref - mean_x) ** 2 / sxx))
    parts.append('!%s' % close('gl_fitted[%d]' % i, fit))
    parts.append('!%s' % close('gl_lower[%d]' % i, fit - critical * se))
    parts.append('!%s' % close('gl_upper[%d]' % i, fit + critical * se))
    parts.append('!%s' % close('gl_means[%d]' % i, float(ys[i * repeats:(i + 1) * repeats].mean())))
check(' || '.join(parts))

# ---- Attribute agreement ----
items, appraisers, trials, categories = 12, 3, 3, 3
standard = rng.integers(0, categories, items)
ratings = np.zeros((appraisers, items, trials), dtype=int)
for a in range(appraisers):
    for i in range(items):
        ratings[a, i, :] = standard[i]
        if rng.random() < 0.3:
            ratings[a, i, rng.integers(0, trials)] = rng.integers(0, categories)
        if rng.random() < 0.15:
            ratings[a, i, :] = rng.integers(0, categories)
uarr('aa_standard', standard)
uarr('aa_ratings', ratings.reshape(-1))
lines.append('    var aa_within: [3]stat.AttributeAgreementRate = zero')
lines.append('    var aa_standard_rates: [3]stat.AttributeAgreementRate = zero')
lines.append('    let (agreement, agreement_error) = stat.attribute_agreement(aa_standard[..], aa_ratings[..], 3usize, 3usize, 3usize, 0.95f64, aa_within[..], aa_standard_rates[..])')


def clopper(k, n, conf=0.95):
    alpha = 1.0 - conf
    low = 0.0 if k == 0 else stats.beta.ppf(alpha / 2, k, n - k + 1)
    high = 1.0 if k == n else stats.beta.ppf(1 - alpha / 2, k + 1, n - k)
    return float(low), float(high)


parts = ['agreement_error != ok']
for a in range(appraisers):
    consistent = sum(1 for i in range(items) if len(set(ratings[a, i])) == 1)
    versus = sum(1 for i in range(items) if len(set(ratings[a, i])) == 1 and ratings[a, i, 0] == standard[i])
    lo, hi = clopper(consistent, items)
    slo, shi = clopper(versus, items)
    parts.append('aa_within[%d].matched != %dusize' % (a, consistent))
    parts.append('!%s' % close('aa_within[%d].confidence.low' % a, lo, 1e-7))
    parts.append('!%s' % close('aa_within[%d].confidence.high' % a, hi, 1e-7))
    parts.append('aa_standard_rates[%d].matched != %dusize' % (a, versus))
    parts.append('!%s' % close('aa_standard_rates[%d].confidence.low' % a, slo, 1e-7))
    parts.append('!%s' % close('aa_standard_rates[%d].confidence.high' % a, shi, 1e-7))
between_matched = sum(1 for i in range(items) if len(set(ratings[:, i, :].reshape(-1))) == 1)
all_standard = sum(1 for i in range(items) if len(set(ratings[:, i, :].reshape(-1))) == 1 and ratings[0, i, 0] == standard[i])
pooled = float(np.mean(ratings == standard[None, :, None]))
chance = sum((np.sum(standard == k) / items) * (np.sum(ratings == k) / ratings.size) for k in range(categories))
parts.append('agreement.between_matched != %dusize' % between_matched)
parts.append('agreement.all_vs_standard_matched != %dusize' % all_standard)
parts.append('!%s' % close('agreement.pooled_rating_fraction', pooled))
parts.append('!%s' % close('agreement.pooled_rating_kappa', (pooled - chance) / (1 - chance)))
check(' || '.join(parts[:13]))
check(' || '.join(parts[13:]))

body = '\n'.join(lines)
source = '''// The estimators behind the SPC, capability and measurement-system charts against independent numpy and
// scipy computations on seeded data (L071, D2255; scripts/stat_spc_reference.py writes this file):
// individuals and moving-range limits, X-bar/R and X-bar/S limits, normal, batch and lognormal capability with
// their ppm, P, nP, C and U limits, Laney P-prime and U-prime, G and T chart limits, the Nelson run-rule flags,
// Gage linearity and attribute agreement. Every check has its own exit code.
use e.algo.stat
use e.mem
use e.os

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn close(got: f64, want: f64, tolerance: f64) -> bool {
    ret abs64(got - want) <= tolerance * (1.0f64 + abs64(want))
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    let (written, write_error) = os.write(os.stdout(), "algo stat spc reference ok\\n")
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'algo_stat_spc_reference' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote algo_stat_spc_reference with', code[0], 'checks')
