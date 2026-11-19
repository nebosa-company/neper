// R bandwidth selectors with every argument: stats::bw.ucv, bw.bcv and bw.SJ (nb, lower, upper, tol, method "ste" / "dpi", the binned
// pair counts of R for n > nb / 2) and MASS::ucv, bcv and width.SJ (nb, lower, upper, the h / 4 scaling, "ste" / "dpi").
//
// NaN stands for a missing argument: lower, upper and tol then take R's default expressions. A failure (no sign change in the bracket,
// a sparse sample) answers NaN where R stops with an error.

use e.algo.stat.bwsel as bs
use e.algo.stat.classint as ci
use e.algo.stat.fdrtool as fd
use e.algo.stat.mass as ms
use e.algo.stat.pwr as pw
use e.math
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn sd_of(x: []const f64) -> f64 {
    let nf = f64(x.len)
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / nf
    var v = 0.0f64
    i = 0usize
    while i < x.len {
        v += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret math.sqrt[f64](v / (nf - 1.0f64))
}

// stats:::bw_pair_cnts: the pair counts by bin distance, d[i] = i * dd; binned (n > nb / 2) is R's tabulate-then-convolve version
fn pair_counts(a: *mem.Arena, x: []const f64, nb: usize, binned: bool, d: []f64, cnt: []f64) -> err {
    var xmin = x[0usize]
    var xmax = x[0usize]
    var i = 0usize
    while i < x.len {
        if x[i] < xmin { xmin = x[i] }
        if x[i] > xmax { xmax = x[i] }
        i += 1usize
    }
    if !binned {
        bs.bin_pairs(x, xmin, xmax, d, cnt)
        ret ok
    }
    let dd = (xmax - xmin) * 1.01f64 / f64(nb)
    let (xx, e1) = mem.alloc[f64](a, x.len)
    let (tab, e2) = mem.alloc[f64](a, nb)
    if e1 != ok || e2 != ok { ret mem.Full }
    var lo = 0.0f64
    i = 0usize
    while i < x.len {
        var t = math.floor[f64](math.abs[f64](x[i]) / dd)
        if x[i] < 0.0f64 { t = 0.0f64 - t }
        if x[i] == 0.0f64 { t = 0.0f64 }
        xx[i] = t
        if i == 0usize || t < lo { lo = t }
        i += 1usize
    }
    i = 0usize
    while i < nb {
        tab[i] = 0.0f64
        d[i] = f64(i) * dd
        cnt[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < x.len {
        let k = xx[i] - lo
        if k < f64(nb) { tab[usize(k)] += 1.0f64 }
        i += 1usize
    }
    var ii = 0usize
    while ii < nb {
        let w = tab[ii]
        cnt[0usize] += w * (w - 1.0f64)
        var jj = 0usize
        while jj < ii {
            cnt[ii - jj] += w * tab[jj]
            jj += 1usize
        }
        ii += 1usize
    }
    cnt[0usize] = cnt[0usize] * 0.5f64
    ret ok
}

// stats::bw.ucv (kind 0) and bw.bcv (kind 1)
fn bw_cv_gen(a: *mem.Arena, x: []const f64, kind: u8, nb: usize, lower_in: f64, upper_in: f64, tol_in: f64) -> f64 {
    let n = x.len
    let (d, e1) = mem.alloc[f64](a, nb)
    let (cnt, e2) = mem.alloc[f64](a, nb)
    if e1 != ok || e2 != ok { ret nan() }
    let hmax = 1.144f64 * sd_of(x) * math.pow[f64](f64(n), 0.0f64 - 0.2f64)
    var lower = lower_in
    var upper = upper_in
    if lower != lower { lower = 0.1f64 * hmax }
    if upper != upper { upper = hmax }
    var tol = tol_in
    if tol != tol { tol = 0.1f64 * lower }
    if pair_counts(a, x, nb, f64(n) > f64(nb) / 2.0f64, d, cnt) != ok { ret nan() }
    var c = bs.BwCtx{ n: n, nb: nb, d: d, cnt: cnt, kind: kind }
    ret fd.brent_min_tol[bs.BwCtx](&c, bs.bw_obj, lower, upper, tol)
}

// stats::bw.SJ: dpi false "ste", true "dpi"
fn bw_sj_gen(a: *mem.Arena, x: []const f64, nb: usize, lower_in: f64, upper_in: f64, tol_in: f64, dpi: bool) -> f64 {
    let n = x.len
    let (d, e1) = mem.alloc[f64](a, nb)
    let (cnt, e2) = mem.alloc[f64](a, nb)
    let (s, e3) = ci.sorted_copy(a, x)
    if e1 != ok || e2 != ok || e3 != ok { ret nan() }
    let nf = f64(n)
    if pair_counts(a, x, nb, nf > f64(nb) / 2.0f64, d, cnt) != ok { ret nan() }
    var scale = sd_of(x)
    let iqr = (ms.quant7(s, 0.75f64) - ms.quant7(s, 0.25f64)) / 1.349f64
    if iqr < scale { scale = iqr }
    let a1 = 1.24f64 * scale * math.pow[f64](nf, 0.0f64 - 1.0f64 / 7.0f64)
    let b1 = 1.23f64 * scale * math.pow[f64](nf, 0.0f64 - 1.0f64 / 9.0f64)
    let c1 = 1.0f64 / (2.0f64 * 1.7724538509055159f64 * nf)
    var c = bs.SjCtx{ n: n, nb: nb, d: d, cnt: cnt, a2: 0.0f64, c1: c1 }
    let td = 0.0f64 - bs.sj_phi(&c, b1, true)
    if !(td > 0.0f64) || td - td != 0.0f64 { ret nan() }
    if dpi {
        let h = math.pow[f64](2.394f64 / (nf * td), 1.0f64 / 7.0f64)
        ret math.pow[f64](c1 / bs.sj_phi(&c, h, false), 0.2f64)
    }
    c.a2 = 1.357f64 * math.pow[f64](bs.sj_phi(&c, a1, false) / td, 1.0f64 / 7.0f64)
    if c.a2 - c.a2 != 0.0f64 { ret nan() }
    let hmax = 1.144f64 * scale * math.pow[f64](nf, 0.0f64 - 0.2f64)
    let miss = lower_in != lower_in || upper_in != upper_in
    var lower = lower_in
    var upper = upper_in
    if lower != lower { lower = 0.1f64 * hmax }
    if upper != upper { upper = hmax }
    var itry = 1usize
    while bs.sj_f(&c, lower) * bs.sj_f(&c, upper) > 0.0f64 {
        if itry > 99usize || !miss { ret nan() }
        if itry % 2usize == 1usize { upper = upper * 1.2f64 } else { lower = lower / 1.2f64 }
        itry += 1usize
    }
    var tol = tol_in
    if tol != tol { tol = 0.1f64 * lower }
    ret pw.zeroin[bs.SjCtx](&c, bs.sj_f, lower, upper, tol, 1000i64)
}

// MASS::ucv (kind 0), MASS::bcv (kind 1), MASS::width.SJ ste (kind 2) and dpi (kind 3): the pair counts are never binned and the answer is on the
// scale of four times R's bandwidth
fn bw_mass(a: *mem.Arena, x: []const f64, kind: usize, nb: usize, lower_in: f64, upper_in: f64) -> f64 {
    let n = x.len
    let (d, e1) = mem.alloc[f64](a, nb)
    let (cnt, e2) = mem.alloc[f64](a, nb)
    if e1 != ok || e2 != ok { ret nan() }
    let nf = f64(n)
    if pair_counts(a, x, nb, false, d, cnt) != ok { ret nan() }
    var hmax = 1.144f64 * sd_of(x) * math.pow[f64](nf, 0.0f64 - 0.2f64)
    if kind < 2usize {
        hmax = hmax * 4.0f64
        var lower = lower_in
        var upper = upper_in
        if lower != lower { lower = 0.1f64 * hmax }
        if upper != upper { upper = hmax }
        var c = bs.BwCtx{ n: n, nb: nb, d: d, cnt: cnt, kind: u8(kind) }
        var mc = MassCtx{ c: c }
        ret fd.brent_min_tol[MassCtx](&mc, mass_obj, lower, upper, 0.1f64 * lower)
    }
    let (s, e3) = ci.sorted_copy(a, x)
    if e3 != ok { ret nan() }
    var scale = sd_of(x)
    let iqr = (ms.quant7(s, 0.75f64) - ms.quant7(s, 0.25f64)) / 1.349f64
    if iqr < scale { scale = iqr }
    let a1 = 1.24f64 * scale * math.pow[f64](nf, 0.0f64 - 1.0f64 / 7.0f64)
    let b1 = 1.23f64 * scale * math.pow[f64](nf, 0.0f64 - 1.0f64 / 9.0f64)
    let c1 = 1.0f64 / (2.0f64 * 1.7724538509055159f64 * nf)
    var c = bs.SjCtx{ n: n, nb: nb, d: d, cnt: cnt, a2: 0.0f64, c1: c1 }
    let td = 0.0f64 - bs.sj_phi(&c, b1, true)
    if kind == 3usize {
        let h = math.pow[f64](2.394f64 / (nf * td), 1.0f64 / 7.0f64)
        ret 4.0f64 * math.pow[f64](c1 / bs.sj_phi(&c, h, false), 0.2f64)
    }
    c.a2 = 1.357f64 * math.pow[f64](bs.sj_phi(&c, a1, false) / td, 1.0f64 / 7.0f64)
    var lower = lower_in
    var upper = upper_in
    if lower != lower { lower = 0.1f64 * hmax }
    if upper != upper { upper = hmax }
    if bs.sj_f(&c, lower) * bs.sj_f(&c, upper) > 0.0f64 { ret nan() }
    ret 4.0f64 * pw.zeroin[bs.SjCtx](&c, bs.sj_f, lower, upper, 0.1f64 * lower, 1000i64)
}

type MassCtx = struct { c: bs.BwCtx }

// the criterion at h / 4, the unit of MASS's h
fn mass_obj(m: *MassCtx, h: f64) -> f64 { ret bs.bw_obj(&m.c, h / 4.0f64) }
