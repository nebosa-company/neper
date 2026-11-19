// R bayestestR on a posterior sample: hdi (the shortest window of ceiling(ci n) sorted draws), eti (the equal-tailed type-7 quantiles), p_direction (the share of draws on the
// larger side of zero) and rope (the share of draws inside the range).
//
// Not here: the density-based point estimates and methods, bayes factors, the other indices and model objects.

use e.algo.stat.desctools as dt
use e.math
use e.mem
use e.algo.stat.bwsel as bws
use e.algo.stat.rdensity as rdn

// the HDI limits: part 0 low, 1 high
fn hdi(a: *mem.Arena, x: []const f64, ci: f64, part: usize) -> f64 {
    let (s, e) = dt.sorted_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let n = s.len
    let w = usize(math.ceil[f64](ci * f64(n)))
    let nci = n - w
    var best = 1.0e300f64
    var first = 0usize
    var last = 0usize
    var cnt = 0usize
    var i = 0usize
    while i < nci {
        let width = s[i + w] - s[i]
        if width < best {
            best = width
            first = i
            last = i
            cnt = 1usize
        } else if width == best {
            last = i
            cnt += 1usize
        }
        i += 1usize
    }
    var pick = first
    if cnt > 1usize {
        if last - first + 1usize != cnt { pick = last } else { pick = (first + last) / 2usize }
    }
    if part == 0usize { ret s[pick] }
    ret s[pick + w]
}

// the equal-tailed interval limits
fn eti(a: *mem.Arena, x: []const f64, ci: f64, part: usize) -> f64 {
    let (s, e) = dt.sorted_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if part == 0usize { ret dt.quant7(s, (1.0f64 - ci) / 2.0f64) }
    ret dt.quant7(s, (1.0f64 + ci) / 2.0f64)
}

fn p_direction(x: []const f64) -> f64 {
    var pos = 0.0f64
    var neg = 0.0f64
    var i = 0usize
    while i < x.len {
        if x[i] > 0.0f64 { pos += 1.0f64 }
        if x[i] < 0.0f64 { neg += 1.0f64 }
        i += 1usize
    }
    var m = pos
    if neg > m { m = neg }
    ret m / f64(x.len)
}

fn rope_share(x: []const f64, lo: f64, hi: f64) -> f64 {
    var c = 0.0f64
    var i = 0usize
    while i < x.len {
        if x[i] >= lo && x[i] <= hi { c += 1.0f64 }
        i += 1usize
    }
    ret c / f64(x.len)
}

// rope(x, range, ci, ci_method, complement = TRUE): out receives (ROPE percentage, superiority, inferiority, CI low, CI high) of the sample inside the ci interval (method 0 ETI, 1 HDI);
// equivalence_test's decision is 0 Rejected, 1 Accepted, 2 Undecided on that percentage
fn rope_ci(a: *mem.Arena, x: []const f64, lo: f64, hi: f64, ci: f64, method: usize, out: []f64) {
    var cl = 0.0f64
    var ch = 0.0f64
    if method == 0usize {
        cl = eti(a, x, ci, 0usize)
        ch = eti(a, x, ci, 1usize)
    } else {
        cl = hdi(a, x, ci, 0usize)
        ch = hdi(a, x, ci, 1usize)
    }
    var cnt = 0usize
    var inside = 0usize
    var sup = 0usize
    var inf = 0usize
    var i = 0usize
    while i < x.len {
        if x[i] >= cl && x[i] <= ch {
            cnt += 1usize
            if x[i] >= lo && x[i] <= hi { inside += 1usize }
            if x[i] > hi { sup += 1usize }
            if x[i] < lo { inf += 1usize }
        }
        i += 1usize
    }
    out[0usize] = f64(inside) / f64(cnt)
    out[1usize] = f64(sup) / f64(cnt)
    out[2usize] = f64(inf) / f64(cnt)
    out[3usize] = cl
    out[4usize] = ch
}

fn equivalence_decision(pct: f64, ci: f64) -> usize {
    if ci < 1.0f64 {
        if pct == 0.0f64 { ret 0usize }
        if pct == 1.0f64 { ret 1usize }
        ret 2usize
    }
    if pct < 0.025f64 { ret 0usize }
    if pct > 0.975f64 { ret 1usize }
    ret 2usize
}

// bayestestR::map_estimate(x) (kernel method, precision 2^10): the point of the Sheather-Jones kernel density of x, evaluated on 1024 points over range(x), where it peaks; out[0] the point, out[1] the density
fn map_estimate(a: *mem.Arena, x: []const f64, out: []f64) -> err {
    let nout = 1024usize
    let (dy, e1) = mem.alloc[f64](a, nout)
    let (sc, e2) = mem.alloc[f64](a, 8usize * 1024usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 1usize
    while i < x.len {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    let bw = bws.bw_sj(a, x)
    rdn.density_range(x, bw, nout, lo, hi, dy, sc)
    var best = 0usize
    i = 1usize
    while i < nout {
        if dy[i] > dy[best] { best = i }
        i += 1usize
    }
    out[0usize] = lo + f64(best) * (hi - lo) / f64(nout - 1usize)
    out[1usize] = dy[best]
    ret ok
}

// bayestestR::p_map(x, null): the posterior density at the null value over the density at the MAP, both read from the 1024-point kernel density (Sheather-Jones bandwidth) over the range of x as `map_estimate` does, the density at
// the null by linear interpolation of that grid (zero outside its range)
fn p_map(a: *mem.Arena, x: []const f64, null: f64) -> f64 {
    let nout = 1024usize
    let (dy, e1) = mem.alloc[f64](a, nout)
    let (sc, e2) = mem.alloc[f64](a, 8usize * 1024usize)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 1usize
    while i < x.len {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    let bw = bws.bw_sj(a, x)
    rdn.density_range(x, bw, nout, lo, hi, dy, sc)
    var best = 0usize
    i = 1usize
    while i < nout {
        if dy[i] > dy[best] { best = i }
        i += 1usize
    }
    if null < lo || null > hi { ret 0.0f64 }
    let pos = (null - lo) / (hi - lo) * f64(nout - 1usize)
    var k = usize(math.floor[f64](pos))
    if k >= nout - 1usize { k = nout - 2usize }
    let fr = pos - f64(k)
    let d0 = dy[k] + fr * (dy[k + 1usize] - dy[k])
    ret d0 / dy[best]
}

// bayestestR::p_significance(x, threshold): the share of the posterior outside the interval [-threshold, threshold] on the side of the median's sign, which is the share beyond the threshold in the direction of the effect
fn p_significance(x: []const f64, threshold: f64) -> f64 {
    var n = 0.0f64
    var pos = 0.0f64
    var neg = 0.0f64
    var i = 0usize
    while i < x.len {
        if x[i] > threshold { pos += 1.0f64 }
        if x[i] < 0.0f64 - threshold { neg += 1.0f64 }
        n += 1.0f64
        i += 1usize
    }
    if pos > neg { ret pos / n }
    ret neg / n
}
