// R GeneralizedHyperbolic gigFit by Nelder-Mead on (log chi, log psi, lambda), with the package's start values: user specified, "LM" (linear models on the kernel
// density of the data and of its inverse) and "GammaIG" (MASS::fitdistr gamma fits to the data and its inverse). The package's "MoM" start stops with an error in R
// and is not here, nor is nlm.

use e.algo.stat.classint as ci
use e.algo.stat.ghypfit as gf
use e.algo.stat.rdensity as rd
use e.math
use e.mem

// the linear-model start of one tail: log(density at the mid points) on the grid index and its log, over the cells at or above the mode with log density above -9;
// returns the two slope coefficients and whether at least two cells were kept
fn lm_tail(a: *mem.Arena, x: []const f64, b1: *f64, b2: *f64) -> bool {
    var mids: []f64 = zero
    var dd: []f64 = zero
    let nb = gf.fit_hist(a, x, &mids, &dd)
    if nb == 0usize { ret false }
    let (srt, se) = ci.sorted_copy(a, x)
    if se != ok { ret false }
    let bw = rd.bw_nrd0(x, srt)
    let nout = 512usize
    let (y, e1) = mem.alloc[f64](a, nout)
    let (scr, e2) = mem.alloc[f64](a, 5usize * rd.grid_for(nout))
    if e1 != ok || e2 != ok { ret false }
    rd.density_gauss(x, srt, bw, nout, y, scr)
    let from = srt[0usize] - 3.0f64 * bw
    let to = srt[srt.len - 1usize] + 3.0f64 * bw
    let by = (to - from) / f64(nout - 1usize)
    let (ex, e3) = mem.alloc[usize](a, nb)
    let (ey, e4) = mem.alloc[f64](a, nb)
    if e3 != ok || e4 != ok { ret false }
    var j = 0usize
    while j < nb {
        var best = 0usize
        var bd = 1.0e300f64
        var i = 0usize
        while i < nout {
            var gx = from + f64(i) * by
            if i == nout - 1usize { gx = to }
            let d = math.abs[f64](gx - mids[j])
            if d < bd {
                bd = d
                best = i
            }
            i += 1usize
        }
        ex[j] = best + 1usize
        ey[j] = y[best]
        j += 1usize
    }
    var nmax = 0usize
    j = 1usize
    while j < nb {
        if ey[j] > ey[nmax] { nmax = j }
        j += 1usize
    }
    // aboveMode[1:(nMax - 1)] <- FALSE: with nMax = 1 that is c(1, 0), which clears the first cell
    var clear_to = nmax
    if nmax == 0usize { clear_to = 1usize }
    var kept = 0usize
    var s1 = 0.0f64
    var s2 = 0.0f64
    var sy = 0.0f64
    j = 0usize
    while j < nb {
        if j >= clear_to && math.log[f64](ey[j]) > 0.0f64 - 9.0f64 {
            kept += 1usize
            s1 += f64(ex[j])
            s2 += math.log[f64](f64(ex[j]))
            sy += math.log[f64](ey[j])
        }
        j += 1usize
    }
    if kept < 2usize { ret false }
    let m1 = s1 / f64(kept)
    let m2 = s2 / f64(kept)
    let my = sy / f64(kept)
    var a11 = 0.0f64
    var a12 = 0.0f64
    var a22 = 0.0f64
    var r1 = 0.0f64
    var r2 = 0.0f64
    j = 0usize
    while j < nb {
        if j >= clear_to && math.log[f64](ey[j]) > 0.0f64 - 9.0f64 {
            let d1 = f64(ex[j]) - m1
            let d2 = math.log[f64](f64(ex[j])) - m2
            let dy = math.log[f64](ey[j]) - my
            a11 += d1 * d1
            a12 += d1 * d2
            a22 += d2 * d2
            r1 += d1 * dy
            r2 += d2 * dy
        }
        j += 1usize
    }
    let det = a11 * a22 - a12 * a12
    *b1 = (r1 * a22 - r2 * a12) / det
    *b2 = (a11 * r2 - a12 * r1) / det
    ret true
}

fn gig_start_lm(a: *mem.Arena, x: []const f64, out: []f64) {
    var psi = 0.0f64 / 0.0f64
    var chi = 0.0f64 / 0.0f64
    var l1 = 0.0f64 / 0.0f64
    var l2 = 0.0f64 / 0.0f64
    var b1 = 0.0f64
    var b2 = 0.0f64
    if lm_tail(a, x, &b1, &b2) {
        psi = 0.0f64 - 2.0f64 * b1
        l1 = b2 + 1.0f64
    }
    let (inv, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret }
    var i = 0usize
    while i < x.len {
        inv[i] = 1.0f64 / x[i]
        i += 1usize
    }
    if lm_tail(a, inv, &b1, &b2) {
        chi = 0.0f64 - 2.0f64 * b1
        l2 = 0.0f64 - b2 - 1.0f64
    }
    var lam = (l1 + l2) / 2.0f64
    if l1 != l1 { lam = l2 }
    if l2 != l2 { lam = l1 }
    if l1 != l1 && l2 != l2 { lam = 1.0f64 }
    if chi != chi { chi = 1.0f64 }
    if psi != psi { psi = 1.0f64 }
    if chi < 0.000000014901161193847656f64 { chi = 0.01f64 }
    if psi < 0.000000014901161193847656f64 { psi = 0.01f64 }
    out[0usize] = chi
    out[1usize] = psi
    out[2usize] = lam
}

// MASS::fitdistr(x, "gamma"): BFGS on (shape, rate / rate0) from the moment start, parscale c(1, rate0); false when optim does not converge
fn fitdistr_gamma(a: *mem.Arena, x: []const f64, est: []f64, ll: *f64) -> bool {
    var c: gf.FitC = zero
    c.a = a
    c.x = x
    c.mode = 4usize
    let m = gf.smean(x)
    let v = gf.svar(x)
    let rate0 = m / v
    c.ps2 = rate0
    var p0: [2]f64 = zero
    p0[0usize] = m * m / v
    p0[1usize] = 1.0f64
    let (bp, e) = mem.alloc[f64](a, 2usize)
    if e != ok { ret false }
    var lo: [2]f64 = zero
    let (fv, cnt, fl) = gf.fit_optim(a, &c, p0[0usize..2usize], 1usize, 100usize, lo[0usize..2usize], bp)
    if fl != 0i64 || fv != fv { ret false }
    est[0usize] = bp[0usize]
    est[1usize] = bp[1usize] * rate0
    *ll = 0.0f64 - fv
    ret true
}

fn gig_start_gamma_ig(a: *mem.Arena, x: []const f64, out: []f64) -> bool {
    let (inv, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret false }
    var i = 0usize
    while i < x.len {
        inv[i] = 1.0f64 / x[i]
        i += 1usize
    }
    var g1: [2]f64 = zero
    var g2: [2]f64 = zero
    var lg = 0.0f64
    var lig = 0.0f64
    let ok1 = fitdistr_gamma(a, x, g1[0usize..2usize], &lg)
    let ok2 = fitdistr_gamma(a, inv, g2[0usize..2usize], &lig)
    if !ok1 && !ok2 { ret false }
    if !ok1 {
        out[0usize] = 2.0f64 * g2[0usize]
        out[1usize] = 0.1f64
        out[2usize] = 0.0f64 - 1.0f64 / g2[1usize]
        ret true
    }
    if !ok2 || lg > lig {
        out[0usize] = 0.1f64
        out[1usize] = 2.0f64 * g1[0usize]
        out[2usize] = g1[1usize]
        ret true
    }
    if lg < lig {
        out[0usize] = 2.0f64 * g2[0usize]
        out[1usize] = 0.1f64
        out[2usize] = 0.0f64 - 1.0f64 / g2[1usize]
        ret true
    }
    ret false
}

// gigFit: kind 0 LM, 1 GammaIG, 2 US; out[0..3] chi, psi, lambda; out[3] the maximised log-likelihood; out[4] convergence; out[5] the function count; out[6..9] the
// start on the log scale (log chi, log psi, lambda)
fn gig_fit(a: *mem.Arena, x0: []const f64, kind: usize, us: []const f64, stand: bool, out: []f64) -> bool {
    var sx = 1.0f64
    if stand { sx = math.sqrt[f64](gf.svar(x0)) }
    let (x, e) = mem.alloc[f64](a, x0.len)
    if e != ok { ret false }
    var i = 0usize
    while i < x0.len {
        x[i] = x0[i] / sx
        i += 1usize
    }
    var st: [3]f64 = zero
    if kind == 0usize { gig_start_lm(a, x, st[0usize..3usize]) }
    if kind == 1usize {
        if !gig_start_gamma_ig(a, x, st[0usize..3usize]) { ret false }
    }
    if kind == 2usize {
        st[0usize] = us[0usize]
        st[1usize] = us[1usize]
        st[2usize] = us[2usize]
    }
    var c: gf.FitC = zero
    c.a = a
    c.x = x
    c.mode = 5usize
    var p0: [3]f64 = zero
    p0[0usize] = math.log[f64](st[0usize])
    p0[1usize] = math.log[f64](st[1usize])
    p0[2usize] = st[2usize]
    let (bp, e2) = mem.alloc[f64](a, 3usize)
    if e2 != ok { ret false }
    var lo: [3]f64 = zero
    let (fv, cnt, fl) = gf.fit_optim(a, &c, p0[0usize..3usize], 0usize, 1000usize, lo[0usize..3usize], bp)
    if stand {
        out[0usize] = sx * math.exp[f64](bp[0usize])
        out[1usize] = math.exp[f64](bp[1usize]) / sx
    } else {
        out[0usize] = math.exp[f64](bp[0usize])
        out[1usize] = math.exp[f64](bp[1usize])
    }
    out[2usize] = bp[2usize]
    out[3usize] = 0.0f64 - fv
    out[4usize] = f64(fl)
    out[5usize] = f64(cnt)
    out[6usize] = p0[0usize]
    out[7usize] = p0[1usize]
    out[8usize] = p0[2usize]
    ret true
}
