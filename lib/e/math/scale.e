// R's axis-scale toolkit, value for value: the labelling algorithms of the labeling package
// (`extended`, `heckbert`, `wilkinson`, `nelder`, `rpretty`), base R's `pretty`, scales'
// `breaks_extended`, `breaks_pretty`, `breaks_log` and `breaks_width`, its transformations
// (`transform_*`, with their inverses and derivatives), and its bounds helpers (`rescale`,
// `rescale_mid`, `rescale_max`, the out-of-bounds rules, `expand_range`, `zero_range`).
//
// A sequence `seq(a, b, by = s)` is R's: n = floor((b - a) / s + 1e-10) steps, a + i s, none past
// b. Powers of ten are the correctly rounded decimal, as R's `^` gives them. NA is NaN.
//
// Not here: date, time and difftime breaks and transforms, `minor_breaks_*`, and the labeling
// package's `matplotlib` labeller.

use e.math
use e.math.special as special
use e.mem
use e.str

error InvalidOption
error NegativeValue

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn is_nan(x: f64) -> bool { ret x != x }

fn infinity() -> f64 { ret mem.bitcast[f64](9218868437227405312u64) }

fn is_finite(x: f64) -> bool { ret x == x && x != infinity() && x != 0.0f64 - infinity() }

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn max_of(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

fn min_of(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}

fn modulo(x: f64, y: f64) -> f64 {
    let q = x / y
    let tmp = x - math.floor[f64](q) * y
    let q2 = math.floor[f64](tmp / y)
    ret tmp - q2 * y
}

fn rint(x: f64) -> f64 {
    let f = math.floor[f64](x)
    let d = x - f
    if d > 0.5f64 { ret f + 1.0f64 }
    if d < 0.5f64 { ret f }
    if f - 2.0f64 * math.floor[f64](f / 2.0f64) == 0.0f64 { ret f }
    ret f + 1.0f64
}

fn machine_eps() -> f64 { ret 0.0000000000000002220446049250313f64 }

// 10^k for a whole k as the correctly rounded double.
fn ten_to(a: *mem.Arena, k: f64) -> f64 {
    if is_nan(k) { ret nan() }
    if k != math.floor[f64](k) || k > 300.0f64 || k < -300.0f64 { ret math.pow[f64](10.0f64, k) }
    let (initial, e) = str.builder(a, 12usize)
    if e != ok { ret nan() }
    var b = initial
    let _ = str.push(&b, "1e")
    let _ = str.push_i64(&b, i64(k))
    let text = str.done(&b)
    let (v, pe) = str.parse_f64(text)
    if pe != ok { ret nan() }
    ret v
}

// R's x^y for a base and a whole power: exact for 10 and 2, pow otherwise.
fn power(a: *mem.Arena, base: f64, k: f64) -> f64 {
    if base == 10.0f64 { ret ten_to(a, k) }
    if k == 2.0f64 { ret base * base }
    ret math.pow[f64](base, k)
}

// log(x, base) as R computes it.
fn log_base(x: f64, base: f64) -> f64 {
    if base == 10.0f64 { ret math.log10[f64](x) }
    if base == 2.0f64 { ret math.log2[f64](x) }
    ret math.log[f64](x) / math.log[f64](base)
}

// seq(from, to, by = by).
fn seq_by(a: *mem.Arena, from: f64, to: f64, by: f64) -> ([]f64, err) {
    let del = to - from
    if del == 0.0f64 && to == 0.0f64 {
        let (one, e) = mem.alloc[f64](a, 1usize)
        if e != ok { ret (one, e) }
        one[0usize] = to
        ret (one, ok)
    }
    var dd = abs_of(del) / max_of(abs_of(to), abs_of(from))
    if dd < 100.0f64 * machine_eps() {
        let (one, e) = mem.alloc[f64](a, 1usize)
        if e != ok { ret (one, e) }
        one[0usize] = from
        ret (one, ok)
    }
    let n = i64(del / by + 0.0000000001f64)
    let (out, e) = mem.alloc[f64](a, usize(n) + 1usize)
    if e != ok { ret (out, e) }
    var i = 0i64
    while i <= n {
        var v = from + f64(i) * by
        if by > 0.0f64 { v = min_of(v, to) } else { v = max_of(v, to) }
        out[usize(i)] = v
        i += 1i64
    }
    ret (out, ok)
}

// seq(from, to, length.out = n) (seq.int).
fn seq_len_out(a: *mem.Arena, from: f64, to: f64, n: usize) -> ([]f64, err) {
    let (out, e) = mem.alloc[f64](a, n)
    if e != ok { ret (out, e) }
    if n == 0usize { ret (out, ok) }
    out[0usize] = from
    if n == 1usize { ret (out, ok) }
    out[n - 1usize] = to
    if n > 2usize {
        let by = (to - from) / f64(n - 1usize)
        var i = 1usize
        while i < n - 1usize {
            out[i] = from + f64(i) * by
            i += 1usize
        }
    }
    ret (out, ok)
}

// --- labeling::heckbert, wilkinson, nelder, extended, rpretty.

fn heckbert_nicenum(a: *mem.Arena, x: f64, round: bool) -> f64 {
    let e = math.floor[f64](math.log10[f64](x))
    let p = ten_to(a, e)
    let f = x / p
    var nf = 10.0f64
    if round {
        if f < 1.5f64 { nf = 1.0f64 } else if f < 3.0f64 { nf = 2.0f64 } else if f < 7.0f64 { nf = 5.0f64 }
    } else {
        if f <= 1.0f64 { nf = 1.0f64 } else if f <= 2.0f64 { nf = 2.0f64 } else if f <= 5.0f64 { nf = 5.0f64 }
    }
    ret nf * p
}

fn heckbert(a: *mem.Arena, dmin: f64, dmax: f64, m: f64) -> ([]f64, err) {
    let range = heckbert_nicenum(a, dmax - dmin, false)
    let lstep = heckbert_nicenum(a, range / (m - 1.0f64), true)
    let lmin = math.floor[f64](dmin / lstep) * lstep
    let lmax = math.ceil[f64](dmax / lstep) * lstep
    let (r, e) = seq_by(a, lmin, lmax, lstep)
    ret (r, e)
}

fn wilkinson_scale(a: *mem.Arena, lo: f64, hi: f64, k: f64, q: []const f64, mincoverage: f64, m: f64, best: []f64) -> bool {
    // best: lmin, lmax, lstep, score
    let n = q.len + 1usize
    let range = hi - lo
    let intervals = k - 1.0f64
    let granularity = 1.0f64 - abs_of(k - m) / m
    let delta = range / intervals
    let dbase = ten_to(a, math.floor[f64](math.log10[f64](delta)))
    var found = false
    var i = 1usize
    while i <= n {
        var qi = 10.0f64
        if i > 1usize { qi = q[i - 2usize] }
        let tdelta = qi * dbase
        let tmin = math.floor[f64](lo / tdelta) * tdelta
        let tmax = tmin + intervals * tdelta
        if tmin <= lo && tmax >= hi {
            var zero_in = 0.0f64
            if tmin <= 0.0f64 && tmax >= 0.0f64 { zero_in = 1.0f64 }
            let roundness = 1.0f64 - (f64(i - 1usize) - zero_in) / f64(n)
            let coverage = (hi - lo) / (tmax - tmin)
            if coverage > mincoverage {
                let tnice = granularity + roundness + coverage
                if !found || tnice > best[3usize] {
                    best[0usize] = tmin
                    best[1usize] = tmax
                    best[2usize] = tdelta
                    best[3usize] = tnice
                    found = true
                }
            }
        }
        i += 1usize
    }
    ret found
}

fn wilkinson(a: *mem.Arena, dmin: f64, dmax: f64, m: f64, q: []const f64, mincoverage: f64) -> ([]f64, err) {
    var best: [4]f64 = zero
    var have = false
    var top: [4]f64 = zero
    var k = max_of(math.floor[f64](m / 2.0f64), 2.0f64)
    let last = math.ceil[f64](6.0f64 * m)
    while k <= last {
        var cand: [4]f64 = zero
        if wilkinson_scale(a, dmin, dmax, k, q, mincoverage, m, cand[0usize..4usize]) {
            if !have || cand[3usize] > top[3usize] {
                top = cand
                have = true
            }
        }
        k = k + 1.0f64
    }
    if !have {
        let (none, e) = seq_by(a, 0.0f64, 0.0f64, 1.0f64)
        ret (none, e)
    }
    best = top
    let (r, e) = seq_by(a, best[0usize], best[1usize], best[2usize])
    ret (r, e)
}

fn nelder(a: *mem.Arena, dmin: f64, dmax: f64, m: f64, q: []const f64) -> ([]f64, err) {
    let bias = 0.0001f64
    let intervals = m - 1.0f64
    var step = (dmax - dmin) / intervals
    var s = step
    while s <= 1.0f64 { s = s * 10.0f64 }
    while s > 10.0f64 { s = s / 10.0f64 }
    let x = s - bias
    var unit = 1usize
    var i = 0usize
    while i < q.len {
        if x < q[i] {
            unit = i + 1usize
            break
        }
        i += 1usize
    }
    step = step * q[unit - 1usize] / s
    let range = step * intervals
    let xx = 0.5f64 * (1.0f64 + (dmin + dmax - range) / step)
    let j = math.floor[f64](xx - bias)
    var valmin = step * j
    if dmin > 0.0f64 && range >= dmax { valmin = 0.0f64 }
    var valmax = valmin + range
    if !(dmax > 0.0f64 || range < 0.0f64 - dmin) {
        valmax = 0.0f64
        valmin = 0.0f64 - range
    }
    let (r, e) = seq_by(a, valmin, valmax, step)
    ret (r, e)
}

fn simplicity(q: f64, qs: []const f64, j: f64, lmin: f64, lmax: f64, lstep: f64) -> f64 {
    let eps = machine_eps() * 100.0f64
    let n = f64(qs.len)
    var i = 1.0f64
    var k = 0usize
    while k < qs.len {
        if qs[k] == q {
            i = f64(k + 1usize)
            break
        }
        k += 1usize
    }
    var v = 0.0f64
    let r = modulo(lmin, lstep)
    if (r < eps || lstep - r < eps) && lmin <= 0.0f64 && lmax >= 0.0f64 { v = 1.0f64 }
    ret 1.0f64 - (i - 1.0f64) / (n - 1.0f64) - j + v
}

fn simplicity_max(q: f64, qs: []const f64, j: f64) -> f64 {
    let n = f64(qs.len)
    var i = 1.0f64
    var k = 0usize
    while k < qs.len {
        if qs[k] == q {
            i = f64(k + 1usize)
            break
        }
        k += 1usize
    }
    ret 1.0f64 - (i - 1.0f64) / (n - 1.0f64) - j + 1.0f64
}

fn cover(dmin: f64, dmax: f64, lmin: f64, lmax: f64) -> f64 {
    let range = dmax - dmin
    let t = 0.1f64 * range
    ret 1.0f64 - 0.5f64 * ((dmax - lmax) * (dmax - lmax) + (dmin - lmin) * (dmin - lmin)) / (t * t)
}

fn coverage_max(dmin: f64, dmax: f64, span: f64) -> f64 {
    let range = dmax - dmin
    if span > range {
        let half = (span - range) / 2.0f64
        let t = 0.1f64 * range
        ret 1.0f64 - 0.5f64 * (half * half + half * half) / (t * t)
    }
    ret 1.0f64
}

fn density(k: f64, m: f64, dmin: f64, dmax: f64, lmin: f64, lmax: f64) -> f64 {
    let r = (k - 1.0f64) / (lmax - lmin)
    let rt = (m - 1.0f64) / (max_of(lmax, dmax) - min_of(dmin, lmin))
    ret 2.0f64 - max_of(r / rt, rt / r)
}

fn density_max(k: f64, m: f64) -> f64 {
    if k >= m { ret 2.0f64 - (k - 1.0f64) / (m - 1.0f64) }
    ret 1.0f64
}

// labeling::extended(dmin, dmax, m, Q, only.loose, w).
fn extended(a: *mem.Arena, dmin0: f64, dmax0: f64, m: f64, q: []const f64, only_loose: bool, w: []const f64) -> ([]f64, err) {
    let eps = machine_eps() * 100.0f64
    var dmin = dmin0
    var dmax = dmax0
    if dmin > dmax {
        dmin = dmax0
        dmax = dmin0
    }
    if dmax - dmin < eps {
        let (r, e) = seq_len_out(a, dmin, dmax, usize(m))
        ret (r, e)
    }
    var best_score = 0.0f64 - 2.0f64
    var b_lmin = 0.0f64
    var b_lmax = 0.0f64
    var b_lstep = 0.0f64
    var j = 1.0f64
    var done = false
    while !done {
        var qi = 0usize
        while qi < q.len && !done {
            let qv = q[qi]
            let sm = simplicity_max(qv, q, j)
            if w[0usize] * sm + w[1usize] + w[2usize] + w[3usize] < best_score {
                done = true
            } else {
                var k = 2.0f64
                var stop_k = false
                while !stop_k {
                    let dm = density_max(k, m)
                    if w[0usize] * sm + w[1usize] + w[2usize] * dm + w[3usize] < best_score {
                        stop_k = true
                    } else {
                        let delta = (dmax - dmin) / (k + 1.0f64) / j / qv
                        var z = math.ceil[f64](math.log10[f64](delta))
                        var stop_z = false
                        while !stop_z {
                            let step = j * qv * ten_to(a, z)
                            let cm = coverage_max(dmin, dmax, step * (k - 1.0f64))
                            if w[0usize] * sm + w[1usize] * cm + w[2usize] * dm + w[3usize] < best_score {
                                stop_z = true
                            } else {
                                let min_start = math.floor[f64](dmax / step) * j - (k - 1.0f64) * j
                                let max_start = math.ceil[f64](dmin / step) * j
                                if min_start <= max_start {
                                    var start = min_start
                                    while start <= max_start {
                                        let lmin = start * (step / j)
                                        let lmax = lmin + step * (k - 1.0f64)
                                        let s = simplicity(qv, q, j, lmin, lmax, step)
                                        let c = cover(dmin, dmax, lmin, lmax)
                                        let g = density(k, m, dmin, dmax, lmin, lmax)
                                        let score = w[0usize] * s + w[1usize] * c + w[2usize] * g + w[3usize] * 1.0f64
                                        if score > best_score && (!only_loose || (lmin <= dmin && lmax >= dmax)) {
                                            best_score = score
                                            b_lmin = lmin
                                            b_lmax = lmax
                                            b_lstep = step
                                        }
                                        start = start + 1.0f64
                                    }
                                }
                                z = z + 1.0f64
                            }
                        }
                        k = k + 1.0f64
                    }
                }
            }
            qi += 1usize
        }
        if !done { j = j + 1.0f64 }
    }
    let (r, e) = seq_by(a, b_lmin, b_lmax, b_lstep)
    ret (r, e)
}

fn default_q() -> [6]f64 {
    var q: [6]f64 = zero
    q[0usize] = 1.0f64
    q[1usize] = 5.0f64
    q[2usize] = 2.0f64
    q[3usize] = 2.5f64
    q[4usize] = 4.0f64
    q[5usize] = 3.0f64
    ret q
}

fn default_w() -> [4]f64 {
    var w: [4]f64 = zero
    w[0usize] = 0.25f64
    w[1usize] = 0.2f64
    w[2usize] = 0.5f64
    w[3usize] = 0.05f64
    ret w
}

// scales::breaks_extended(n)(x).
fn breaks_extended(a: *mem.Arena, x: []const f64, n: f64) -> ([]f64, err) {
    var lo = infinity()
    var hi = 0.0f64 - infinity()
    var any = false
    var i = 0usize
    while i < x.len {
        if is_finite(x[i]) {
            any = true
            if x[i] < lo { lo = x[i] }
            if x[i] > hi { hi = x[i] }
        }
        i += 1usize
    }
    if !any {
        let (none, e) = mem.alloc[f64](a, 0usize)
        ret (none, e)
    }
    let q = default_q()
    let w = default_w()
    let (r, e) = extended(a, lo, hi, n, q[0usize..6usize], false, w[0usize..4usize])
    ret (r, e)
}

// labeling::rpretty(dmin, dmax, m, n, min.n, shrink.sml, high.u.bias, u5.bias).
fn rpretty(a: *mem.Arena, dmin: f64, dmax: f64, m: f64) -> ([]f64, err) {
    var ndiv = math.floor[f64](m) - 1.0f64
    let min_n = math.floor[f64](ndiv / 3.0f64)
    let shrink = 0.75f64
    let h = 1.5f64
    let h5 = 0.5f64 + 1.5f64 * h
    let dx = dmax - dmin
    var cell = 0.0f64
    var i_small = false
    if dx == 0.0f64 && dmax == 0.0f64 {
        cell = 1.0f64
        i_small = true
    } else {
        cell = max_of(abs_of(dmin), abs_of(dmax))
        var u = 1.5f64 / (1.0f64 + h5)
        if h5 >= 1.5f64 * h + 0.5f64 { u = 1.0f64 / (1.0f64 + h) }
        u = 1.0f64 + u
        i_small = dx < cell * u * max_of(1.0f64, ndiv) * 0.0000001f64 * 3.0f64
    }
    if i_small {
        if cell > 10.0f64 { cell = 9.0f64 + cell / 10.0f64 }
        cell = cell * shrink
        if min_n > 1.0f64 { cell = cell / min_n }
    } else {
        cell = dx
        if ndiv > 1.0f64 { cell = cell / ndiv }
    }
    if cell < 20.0f64 * 0.0000001f64 { cell = 20.0f64 * 0.0000001f64 }
    let base = ten_to(a, math.floor[f64](math.log10[f64](cell)))
    var unit = base
    if (2.0f64 * base) - cell < h * (cell - unit) {
        unit = 2.0f64 * base
        if (5.0f64 * base) - cell < h5 * (cell - unit) {
            unit = 5.0f64 * base
            if (10.0f64 * base) - cell < h * (cell - unit) { unit = 10.0f64 * base }
        }
    }
    var ns = math.floor[f64](dmin / unit + 0.0000001f64)
    var nu = math.ceil[f64](dmax / unit - 0.0000001f64)
    while ns * unit > dmin + (0.0000001f64 * unit) { ns = ns - 1.0f64 }
    while nu * unit < dmax - (0.0000001f64 * unit) { nu = nu + 1.0f64 }
    var k = math.floor[f64](0.5f64 + nu - ns)
    if k < min_n {
        k = min_n - k
        if ns >= 0.0f64 {
            nu = nu + k / 2.0f64
            ns = ns - k / 2.0f64 + modulo(k, 2.0f64)
        } else {
            ns = ns - k / 2.0f64
            nu = nu + k / 2.0f64 + modulo(k, 2.0f64)
        }
        ndiv = min_n
    }
    let (r, e) = seq_by(a, ns * unit, nu * unit, unit)
    ret (r, e)
}

// --- base R's pretty(x, n).

fn pretty(a: *mem.Arena, lo0: f64, hi0: f64, n: i64) -> ([]f64, err) {
    var lo = lo0
    var up = hi0
    var ndiv = n
    let min_n = n / 3i64
    let shrink = 0.75f64
    let h = 1.5f64
    let h5 = 0.5f64 + 1.5f64 * h
    let rounding_eps = 0.0000000001f64
    let dx = up - lo
    var cell = 0.0f64
    var i_small = false
    if dx == 0.0f64 && up == 0.0f64 {
        cell = 1.0f64
        i_small = true
    } else {
        cell = max_of(abs_of(lo), abs_of(up))
        var u = 1.5f64 / (1.0f64 + h5)
        if h5 >= 1.5f64 * h + 0.5f64 { u = 1.0f64 / (1.0f64 + h) }
        u = 1.0f64 + u
        var nd = f64(ndiv)
        if nd < 1.0f64 { nd = 1.0f64 }
        u = u * nd * machine_eps()
        i_small = dx < cell * u * 3.0f64
    }
    if i_small {
        if cell > 10.0f64 { cell = 9.0f64 + cell / 10.0f64 }
        cell = cell * shrink
        if min_n > 1i64 { cell = cell / f64(min_n) }
    } else {
        cell = dx
        if ndiv > 1i64 { cell = cell / f64(ndiv) }
    }
    let base = ten_to(a, math.floor[f64](math.log10[f64](cell)))
    var unit = base
    if (2.0f64 * base) - cell < h * (cell - unit) {
        unit = 2.0f64 * base
        if (5.0f64 * base) - cell < h5 * (cell - unit) {
            unit = 5.0f64 * base
            if (10.0f64 * base) - cell < h * (cell - unit) { unit = 10.0f64 * base }
        }
    }
    var ns = math.floor[f64](lo / unit + rounding_eps)
    var nu = math.ceil[f64](up / unit - rounding_eps)
    while ns * unit > lo + rounding_eps * unit { ns = ns - 1.0f64 }
    while nu * unit < up - rounding_eps * unit { nu = nu + 1.0f64 }
    var k = i64(0.5f64 + nu - ns)
    if k < min_n {
        k = min_n - k
        if lo == 0.0f64 && ns == 0.0f64 && up != 0.0f64 {
            nu = nu + f64(k)
        } else if up == 0.0f64 && nu == 0.0f64 && lo != 0.0f64 {
            ns = ns - f64(k)
        } else if ns >= 0.0f64 {
            nu = nu + f64(k / 2i64)
            ns = ns - f64(k / 2i64 + k % 2i64)
        } else {
            ns = ns - f64(k / 2i64)
            nu = nu + f64(k / 2i64 + k % 2i64)
        }
        ndiv = min_n
    } else {
        ndiv = k
    }
    if ns * unit < lo { lo = ns * unit }
    if nu * unit > up { up = nu * unit }
    let (s, e) = seq_len_out(a, lo, up, usize(ndiv) + 1usize)
    if e != ok { ret (s, e) }
    if ndiv > 0i64 {
        let delta = (up - lo) / f64(ndiv)
        var i = 0usize
        while i < s.len {
            if abs_of(s[i]) < 0.00000000000001f64 * delta { s[i] = 0.0f64 }
            i += 1usize
        }
    }
    ret (s, ok)
}

fn zero_range2(lo: f64, hi: f64) -> bool {
    if is_nan(lo) || is_nan(hi) { ret false }
    if lo == hi { ret true }
    if !is_finite(lo) || !is_finite(hi) { ret false }
    let m = min_of(abs_of(lo), abs_of(hi))
    if m == 0.0f64 { ret false }
    ret abs_of((lo - hi) / m) < 1000.0f64 * machine_eps()
}

// scales::breaks_pretty(n)(x).
fn breaks_pretty(a: *mem.Arena, x: []const f64, n: i64) -> ([]f64, err) {
    var lo = infinity()
    var hi = 0.0f64 - infinity()
    var i = 0usize
    while i < x.len {
        if is_finite(x[i]) {
            if x[i] < lo { lo = x[i] }
            if x[i] > hi { hi = x[i] }
        }
        i += 1usize
    }
    if hi < lo {
        let (none, e) = mem.alloc[f64](a, 0usize)
        ret (none, e)
    }
    if zero_range2(lo, hi) {
        let (one, e) = mem.alloc[f64](a, 1usize)
        if e != ok { ret (one, e) }
        one[0usize] = x[0usize]
        ret (one, ok)
    }
    let (r, e) = pretty(a, lo, hi, n)
    ret (r, e)
}

// --- scales::breaks_log(n, base)(x).

fn count_relevant(breaks: []const f64, lo: f64, hi: f64) -> usize {
    var c = 0usize
    var i = 0usize
    while i < breaks.len {
        if lo <= breaks[i] && breaks[i] <= hi { c += 1usize }
        i += 1usize
    }
    ret c
}

fn base_powers(a: *mem.Arena, base: f64, from: f64, to: f64, by: f64) -> ([]f64, err) {
    let (ks, e) = seq_by(a, from, to, by)
    if e != ok { ret (ks, e) }
    var i = 0usize
    while i < ks.len {
        ks[i] = power(a, base, ks[i])
        i += 1usize
    }
    ret (ks, ok)
}

fn sorted_copy(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (out, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < x.len {
        let v = x[i]
        var j = i
        while j > 0usize && out[j - 1usize] > v {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = v
        i += 1usize
    }
    ret (out, ok)
}

fn log_sub_breaks(a: *mem.Arena, lr0: f64, lr1: f64, n: f64, base: f64) -> ([]f64, err) {
    let mn = math.floor[f64](lr0)
    let mx = math.ceil[f64](lr1)
    if base <= 2.0f64 {
        let (r, e) = base_powers(a, base, mn, mx, 1.0f64)
        ret (r, e)
    }
    let nb = usize(base)
    let (steps, se) = mem.alloc[f64](a, nb + 1usize)
    let (cand, ce) = mem.alloc[f64](a, nb + 1usize)
    if se != ok { ret (steps, se) }
    if ce != ok { ret (cand, ce) }
    var nsteps = 1usize
    steps[0usize] = 1.0f64
    var ncand = 0usize
    var c = 2usize
    while c <= nb {
        if f64(c) < base {
            cand[ncand] = f64(c)
            ncand += 1usize
        }
        c += 1usize
    }
    let lo = power(a, base, lr0)
    let hi = power(a, base, lr1)
    let (powers, pe) = base_powers(a, base, mn, mx, 1.0f64)
    if pe != ok { ret (powers, pe) }
    var breaks: []f64 = zero
    var relevant = 0usize
    var enough = false
    while ncand > 0usize && !enough {
        // the candidate that leaves the widest narrowest gap in log space
        var best = 0usize
        var best_delta = 0.0f64 - infinity()
        var ci = 0usize
        while ci < ncand {
            let (pts, ge) = mem.alloc[f64](a, nsteps + 2usize)
            if ge != ok { ret (pts, ge) }
            var t = 0usize
            while t < nsteps {
                pts[t] = steps[t]
                t += 1usize
            }
            pts[nsteps] = cand[ci]
            pts[nsteps + 1usize] = base
            let (sorted, soe) = sorted_copy(a, pts)
            if soe != ok { ret (sorted, soe) }
            var delta = infinity()
            var q = 1usize
            while q < sorted.len {
                let d = log_base(sorted[q], base) - log_base(sorted[q - 1usize], base)
                if d < delta { delta = d }
                q += 1usize
            }
            if delta > best_delta {
                best_delta = delta
                best = ci
            }
            ci += 1usize
        }
        steps[nsteps] = cand[best]
        nsteps += 1usize
        var r = best
        while r + 1usize < ncand {
            cand[r] = cand[r + 1usize]
            r += 1usize
        }
        ncand -= 1usize
        let (bk, be) = mem.alloc[f64](a, powers.len * nsteps)
        if be != ok { ret (bk, be) }
        var s = 0usize
        while s < nsteps {
            var pi = 0usize
            while pi < powers.len {
                bk[s * powers.len + pi] = powers[pi] * steps[s]
                pi += 1usize
            }
            s += 1usize
        }
        breaks = bk
        relevant = count_relevant(breaks, lo, hi)
        if f64(relevant) >= n - 2.0f64 { enough = true }
    }
    if enough {
        let (sorted, soe) = sorted_copy(a, breaks)
        if soe != ok { ret (sorted, soe) }
        var first = 0usize
        while first < sorted.len && !(lo <= sorted[first]) { first += 1usize }
        var last = 0usize
        var i = 0usize
        while i < sorted.len {
            if sorted[i] <= hi { last = i }
            i += 1usize
        }
        var from = 0usize
        if first > 0usize { from = first - 1usize }
        var upto = last + 1usize
        if upto > sorted.len - 1usize { upto = sorted.len - 1usize }
        ret (sorted[from..upto + 1usize], ok)
    }
    let (ends, ee) = mem.alloc[f64](a, 2usize)
    if ee != ok { ret (ends, ee) }
    ends[0usize] = lo
    ends[1usize] = hi
    let (r, e) = breaks_extended(a, ends, n)
    ret (r, e)
}

fn breaks_log(a: *mem.Arena, x: []const f64, n: f64, base: f64) -> ([]f64, err) {
    var lo = infinity()
    var hi = 0.0f64 - infinity()
    var any = false
    var i = 0usize
    while i < x.len {
        if !is_nan(x[i]) {
            any = true
            if x[i] < lo { lo = x[i] }
            if x[i] > hi { hi = x[i] }
        }
        i += 1usize
    }
    if !any || !is_finite(lo) || !is_finite(hi) {
        let (none, e) = mem.alloc[f64](a, 0usize)
        ret (none, e)
    }
    let lr0 = log_base(lo, base)
    let lr1 = log_base(hi, base)
    if !is_finite(lr0) || !is_finite(lr1) {
        let (none, e) = mem.alloc[f64](a, 0usize)
        ret (none, e)
    }
    let mn = math.floor[f64](lr0)
    let mx = math.ceil[f64](lr1)
    if mx == mn {
        let (one, e) = mem.alloc[f64](a, 1usize)
        if e != ok { ret (one, e) }
        one[0usize] = power(a, base, mn)
        ret (one, ok)
    }
    var by = math.floor[f64]((mx - mn) / n) + 1.0f64
    let blo = power(a, base, lr0)
    let bhi = power(a, base, lr1)
    let (breaks, be) = base_powers(a, base, mn, mx, by)
    if be != ok { ret (breaks, be) }
    if f64(count_relevant(breaks, blo, bhi)) >= n - 2.0f64 { ret (breaks, ok) }
    while by > 1.0f64 {
        by = by - 1.0f64
        let (bk, bke) = base_powers(a, base, mn, mx, by)
        if bke != ok { ret (bk, bke) }
        if f64(count_relevant(bk, blo, bhi)) >= n - 2.0f64 { ret (bk, ok) }
    }
    let (r, e) = log_sub_breaks(a, lr0, lr1, n, base)
    ret (r, e)
}

// scales::breaks_width(width, offset)(x) for numbers: fullseq(range(x), width), then each
// offset added.
fn breaks_width(a: *mem.Arena, x: []const f64, width: f64, offsets: []const f64) -> ([]f64, err) {
    var lo = infinity()
    var hi = 0.0f64 - infinity()
    var i = 0usize
    while i < x.len {
        if !is_nan(x[i]) {
            if x[i] < lo { lo = x[i] }
            if x[i] > hi { hi = x[i] }
        }
        i += 1usize
    }
    var out: []f64 = zero
    if zero_range2(lo, hi) {
        let (two, e) = mem.alloc[f64](a, 2usize)
        if e != ok { ret (two, e) }
        two[0usize] = lo - width / 2.0f64
        two[1usize] = hi + width / 2.0f64
        out = two
    } else {
        let (s, e) = seq_by(a, math.floor[f64](lo / width) * width, math.ceil[f64](hi / width) * width, width)
        if e != ok { ret (s, e) }
        out = s
    }
    var k = 0usize
    while k < offsets.len {
        i = 0usize
        while i < out.len {
            out[i] = out[i] + offsets[k]
            i += 1usize
        }
        k += 1usize
    }
    ret (out, ok)
}

// --- Bounds.

fn rescale(x: f64, to_lo: f64, to_hi: f64, from_lo: f64, from_hi: f64) -> f64 {
    if zero_range2(from_lo, from_hi) || zero_range2(to_lo, to_hi) {
        if is_nan(x) { ret x }
        ret (to_lo + to_hi) / 2.0f64
    }
    ret (x - from_lo) / (from_hi - from_lo) * (to_hi - to_lo) + to_lo
}

fn rescale_mid(x: f64, to_lo: f64, to_hi: f64, from_lo: f64, from_hi: f64, mid: f64) -> f64 {
    if zero_range2(from_lo, from_hi) || zero_range2(to_lo, to_hi) {
        if is_nan(x) { ret x }
        ret (to_lo + to_hi) / 2.0f64
    }
    let extent = 2.0f64 * max_of(abs_of(from_lo - mid), abs_of(from_hi - mid))
    ret (x - mid) / extent * (to_hi - to_lo) + (to_lo + to_hi) / 2.0f64
}

fn rescale_max(x: f64, to_hi: f64, from_hi: f64) -> f64 { ret x / from_hi * to_hi }

// Out-of-bounds rules, one value: 0 censor, 1 censor_any, 2 squish, 3 squish_any, 4 squish_infinite,
// 5 keep. A discarded value is NaN here (discard drops it from a vector).
fn oob(x: f64, lo: f64, hi: f64, rule: u8) -> f64 {
    var finite_only = rule == 0u8 || rule == 2u8
    if rule == 4u8 {
        if x == 0.0f64 - infinity() { ret lo }
        if x == infinity() { ret hi }
        ret x
    }
    if rule == 5u8 { ret x }
    if is_nan(x) { ret x }
    if finite_only && !is_finite(x) { ret x }
    if rule == 0u8 || rule == 1u8 {
        if x < lo || x > hi { ret nan() }
        ret x
    }
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

fn expand_range(lo: f64, hi: f64, mul: f64, add: f64, zero_width: f64, out: []f64) {
    var width = hi - lo
    if zero_range2(lo, hi) { width = zero_width }
    out[0usize] = lo - (width * mul + add)
    out[1usize] = hi + (width * mul + add)
}

// --- Transformations.

// kind: 0 asn, 1 atanh, 2 asinh, 3 boxcox(p, offset), 4 modulus(p, offset), 5 yj(p), 6 exp(base),
// 7 identity, 8 log(base), 9 log1p, 10 pseudo_log(sigma, base), 11 logit, 12 probit,
// 13 reciprocal, 14 reverse, 15 sqrt.
type Transform = struct { kind: u8, p: f64, offset: f64, sigma: f64, base: f64 }

// The functions e.math lacks, to a few ulps (Kahan's forms).
fn log1p(x: f64) -> f64 {
    if x == infinity() { ret x }
    let u = 1.0f64 + x
    if u == 1.0f64 { ret x }
    ret math.log[f64](u) * x / (u - 1.0f64)
}

fn expm1(x: f64) -> f64 {
    let u = math.exp[f64](x)
    if u == 1.0f64 { ret x }
    let um1 = u - 1.0f64
    if um1 == -1.0f64 { ret -1.0f64 }
    if u == infinity() { ret u }
    ret um1 * x / math.log[f64](u)
}

fn sinh(x: f64) -> f64 {
    let ax = abs_of(x)
    var r = 0.0f64
    if ax < 1.0f64 {
        let m = expm1(ax)
        r = (m + m / (m + 1.0f64)) / 2.0f64
    } else {
        let e = math.exp[f64](ax)
        r = (e - 1.0f64 / e) / 2.0f64
    }
    if x < 0.0f64 { ret 0.0f64 - r }
    ret r
}

fn cosh(x: f64) -> f64 {
    let e = math.exp[f64](abs_of(x))
    ret (e + 1.0f64 / e) / 2.0f64
}

fn tanh(x: f64) -> f64 {
    let ax = abs_of(x)
    let m = expm1(2.0f64 * ax)
    var r = m / (m + 2.0f64)
    if m == infinity() { r = 1.0f64 }
    if x < 0.0f64 { ret 0.0f64 - r }
    ret r
}

fn asinh(x: f64) -> f64 {
    let ax = abs_of(x)
    let r = log1p(ax + ax * ax / (1.0f64 + math.sqrt[f64](1.0f64 + ax * ax)))
    if x < 0.0f64 { ret 0.0f64 - r }
    ret r
}

fn atanh(x: f64) -> f64 {
    let ax = abs_of(x)
    var r = infinity()
    if ax != 1.0f64 { r = 0.5f64 * log1p(2.0f64 * ax / (1.0f64 - ax)) }
    if x < 0.0f64 { ret 0.0f64 - r }
    ret r
}

fn sign_of(x: f64) -> f64 {
    if x > 0.0f64 { ret 1.0f64 }
    if x < 0.0f64 { ret -1.0f64 }
    ret 0.0f64
}

fn rpow(a: *mem.Arena, x: f64, y: f64) -> f64 {
    if x == 10.0f64 { ret ten_to(a, y) }
    if y == 2.0f64 { ret x * x }
    ret math.pow[f64](x, y)
}

fn dnorm(a: *mem.Arena, x0: f64) -> f64 {
    var x = abs_of(x0)
    if x == infinity() { ret 0.0f64 }
    if x < 5.0f64 { ret 0.398942280401432677939946059934f64 * math.exp[f64](0.0f64 - 0.5f64 * x * x) }
    let x1 = rint(x * 65536.0f64) / 65536.0f64
    let x2 = x - x1
    ret 0.398942280401432677939946059934f64 * (math.exp[f64](0.0f64 - 0.5f64 * x1 * x1) * math.exp[f64]((0.0f64 - 0.5f64 * x2 - x1) * x2))
}

fn dlogis(x0: f64) -> f64 {
    let e = math.exp[f64](0.0f64 - abs_of(x0))
    let f = 1.0f64 + e
    ret e / (f * f)
}

fn yj_pos(a: *mem.Arena, t: *const Transform, x: f64, mode: u8) -> f64 {
    // mode 0 trans, 1 inverse, 2 d_trans, 3 d_inverse
    let p = t.p
    if abs_of(p) < 0.0000001f64 {
        if mode == 0u8 { ret log1p(x) }
        if mode == 1u8 { ret expm1(x) }
        if mode == 2u8 { ret 1.0f64 / (1.0f64 + x) }
        ret math.exp[f64](x)
    }
    if mode == 0u8 { ret (rpow(a, x + 1.0f64, p) - 1.0f64) / p }
    if mode == 1u8 { ret rpow(a, p * x + 1.0f64, 1.0f64 / p) - 1.0f64 }
    if mode == 2u8 { ret rpow(a, x + 1.0f64, p - 1.0f64) }
    ret rpow(a, p * x + 1.0f64, 1.0f64 / p - 1.0f64)
}

fn yj_neg(a: *mem.Arena, t: *const Transform, x: f64, mode: u8) -> f64 {
    let p = t.p
    if abs_of(2.0f64 - p) < 0.0000001f64 {
        if mode == 0u8 { ret 0.0f64 - log1p(0.0f64 - x) }
        if mode == 1u8 { ret 1.0f64 - math.exp[f64](0.0f64 - x) }
        if mode == 2u8 { ret 1.0f64 / (1.0f64 - x) }
        ret math.exp[f64](0.0f64 - x)
    }
    if mode == 0u8 { ret 0.0f64 - (rpow(a, 0.0f64 - x + 1.0f64, 2.0f64 - p) - 1.0f64) / (2.0f64 - p) }
    if mode == 1u8 { ret 1.0f64 - rpow(a, 0.0f64 - (2.0f64 - p) * x + 1.0f64, 1.0f64 / (2.0f64 - p)) }
    if mode == 2u8 { ret rpow(a, 1.0f64 - x, 1.0f64 - p) }
    ret rpow(a, 0.0f64 - (2.0f64 - p) * x + 1.0f64, 1.0f64 / (2.0f64 - p) - 1.0f64)
}

// mode 0 transform, 1 inverse, 2 d_transform, 3 d_inverse.
fn apply(a: *mem.Arena, t: *const Transform, x: f64, mode: u8) -> f64 {
    let k = t.kind
    if is_nan(x) { ret x }
    if k == 0u8 {
        if mode == 0u8 { ret 2.0f64 * math.asin[f64](math.sqrt[f64](x)) }
        if mode == 1u8 {
            let s = math.sin[f64](x / 2.0f64)
            ret s * s
        }
        if mode == 2u8 { ret 1.0f64 / math.sqrt[f64](x - x * x) }
        ret math.sin[f64](x) / 2.0f64
    }
    if k == 1u8 {
        if mode == 0u8 { ret atanh(x) }
        if mode == 1u8 { ret tanh(x) }
        if mode == 2u8 { ret 1.0f64 / (1.0f64 - x * x) }
        let c = cosh(x)
        ret 1.0f64 / (c * c)
    }
    if k == 2u8 {
        if mode == 0u8 { ret asinh(x) }
        if mode == 1u8 { ret sinh(x) }
        if mode == 2u8 { ret 1.0f64 / math.sqrt[f64](x * x + 1.0f64) }
        ret cosh(x)
    }
    if k == 3u8 {
        if abs_of(t.p) < 0.0000001f64 {
            if mode == 0u8 { ret math.log[f64](x + t.offset) }
            if mode == 1u8 { ret math.exp[f64](x) - t.offset }
            if mode == 2u8 { ret 1.0f64 / (x + t.offset) }
            ret math.exp[f64](x)
        }
        if mode == 0u8 { ret (rpow(a, x + t.offset, t.p) - 1.0f64) / t.p }
        if mode == 1u8 { ret rpow(a, x * t.p + 1.0f64, 1.0f64 / t.p) - t.offset }
        if mode == 2u8 { ret rpow(a, x + t.offset, t.p - 1.0f64) }
        ret rpow(a, x * t.p + 1.0f64, 1.0f64 / t.p - 1.0f64)
    }
    if k == 4u8 {
        let s = sign_of(x)
        let ax = abs_of(x)
        if abs_of(t.p) < 0.0000001f64 {
            if mode == 0u8 { ret s * math.log[f64](ax + t.offset) }
            if mode == 1u8 { ret s * (math.exp[f64](ax) - t.offset) }
            if mode == 2u8 { ret 1.0f64 / (ax + t.offset) }
            ret math.exp[f64](ax)
        }
        if mode == 0u8 { ret s * (rpow(a, ax + t.offset, t.p) - 1.0f64) / t.p }
        if mode == 1u8 { ret s * (rpow(a, ax * t.p + 1.0f64, 1.0f64 / t.p) - t.offset) }
        if mode == 2u8 { ret rpow(a, ax + t.offset, t.p - 1.0f64) }
        ret rpow(a, ax * t.p + 1.0f64, 1.0f64 / t.p - 1.0f64)
    }
    if k == 5u8 {
        var at0 = 0.0f64
        if mode >= 2u8 { at0 = 1.0f64 }
        if x == 0.0f64 { ret at0 }
        if x > 0.0f64 { ret yj_pos(a, t, x, mode) }
        ret yj_neg(a, t, x, mode)
    }
    if k == 6u8 {
        if mode == 0u8 { ret rpow(a, t.base, x) }
        if mode == 1u8 { ret log_base(x, t.base) }
        if mode == 2u8 { ret rpow(a, t.base, x) * math.log[f64](t.base) }
        ret 1.0f64 / x / math.log[f64](t.base)
    }
    if k == 7u8 {
        if mode >= 2u8 { ret 1.0f64 }
        ret x
    }
    if k == 8u8 {
        if mode == 0u8 { ret log_base(x, t.base) }
        if mode == 1u8 { ret rpow(a, t.base, x) }
        if mode == 2u8 { ret 1.0f64 / x / math.log[f64](t.base) }
        ret rpow(a, t.base, x) * math.log[f64](t.base)
    }
    if k == 9u8 {
        if mode == 0u8 { ret log1p(x) }
        if mode == 1u8 { ret expm1(x) }
        if mode == 2u8 { ret 1.0f64 / (1.0f64 + x) }
        ret math.exp[f64](x)
    }
    if k == 10u8 {
        let lb = math.log[f64](t.base)
        if mode == 0u8 { ret asinh(x / (2.0f64 * t.sigma)) / lb }
        if mode == 1u8 { ret 2.0f64 * t.sigma * sinh(x * lb) }
        if mode == 2u8 { ret 1.0f64 / (math.sqrt[f64](4.0f64 + x * x / (t.sigma * t.sigma)) * t.sigma * lb) }
        ret 2.0f64 * t.sigma * cosh(x * lb) * lb
    }
    if k == 11u8 {
        if mode == 0u8 { ret math.log[f64](x / (1.0f64 - x)) }
        if mode == 1u8 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - x)) }
        if mode == 2u8 { ret 1.0f64 / dlogis(math.log[f64](x / (1.0f64 - x))) }
        ret dlogis(x)
    }
    if k == 12u8 {
        if mode == 0u8 { ret special.normal_quantile(x) }
        if mode == 1u8 { ret special.normal_cdf(x) }
        if mode == 2u8 { ret 1.0f64 / dnorm(a, special.normal_quantile(x)) }
        ret dnorm(a, x)
    }
    if k == 13u8 {
        if mode == 0u8 || mode == 1u8 { ret 1.0f64 / x }
        ret 0.0f64 - 1.0f64 / (x * x)
    }
    if k == 14u8 {
        if mode <= 1u8 { ret 0.0f64 - x }
        ret -1.0f64
    }
    if mode == 0u8 { ret math.sqrt[f64](x) }
    if mode == 1u8 {
        if x < 0.0f64 { ret nan() }
        ret x * x
    }
    if mode == 2u8 { ret 0.5f64 / math.sqrt[f64](x) }
    ret 2.0f64 * x
}
