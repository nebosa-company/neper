// R fpc: unimodal.ind, dipp.tantrum and diptest.multi (which, as fpc codes it, always answers the dipp.tantrum p value with M = 100 draws, whatever pvalue says).
// Matrices are row-major.

use e.algo.rand.r as rg
use e.algo.stat.dip as dp
use e.algo.stat.fpc as fp
use e.algo.stat.rdensity as rd
use e.mem

error Malformed

// unimodal.ind(y): FALSE when y rises, falls, and rises again
fn unimodal_ind(y: []const f64) -> bool {
    let ly = y.len
    var k = 0usize
    if y[1usize] >= y[0usize] {
        var found = false
        var i = 1usize
        while i + 1usize < ly && !found {
            if y[i + 1usize] < y[i] {
                k = i
                found = true
            }
            i += 1usize
        }
        if !found { ret true }
    } else {
        k = 1usize
    }
    var j = k + 1usize
    while j < ly {
        if y[j] > y[j - 1usize] { ret false }
        j += 1usize
    }
    ret true
}

fn sort_copy(a: *mem.Arena, v: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < v.len {
        s[i] = v[i]
        i += 1usize
    }
    var j = 1usize
    while j < v.len {
        let t = s[j]
        var q = j
        while q > 0usize && s[q - 1usize] > t {
            s[q] = s[q - 1usize]
            q -= 1usize
        }
        s[q] = t
        j += 1usize
    }
    ret (s, ok)
}

// dipp.tantrum(xdata, d, M): the p value (1 + #(dv >= d)) / (1 + M) and the bandwidth bw
fn dipp_tantrum(a: *mem.Arena, g: *rg.Rng, xdata: []const f64, d: f64, mm: usize) -> (f64, f64, err) {
    let n = xdata.len
    let (xs, e1) = sort_copy(a, xdata)
    let (y, e2) = mem.alloc[f64](a, 512usize)
    let (scr, e3) = mem.alloc[f64](a, 5usize * 1024usize)
    let (xn, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0.0f64, 0.0f64, Malformed) }
    let bw = rd.bw_nrd0(xdata, xs)
    var bwnew = bw
    let inc = bw / 10.0f64
    rd.density_gauss(xdata, xs, bwnew, 512usize, y, scr)
    while !unimodal_ind(y) {
        bwnew = bwnew + inc
        rd.density_gauss(xdata, xs, bwnew, 512usize, y, scr)
    }
    var cnt = 0usize
    var i = 0usize
    while i < mm {
        let mark = mem.mark(a)
        let (sm, e5) = rg.sample_int(a, g, i64(n), i64(n), true)
        if e5 != ok { ret (0.0f64, 0.0f64, e5) }
        var j = 0usize
        while j < n {
            xn[j] = rg.rnorm(g, xdata[usize(sm[j]) - 1usize], bwnew)
            j += 1usize
        }
        let (so, e6) = sort_copy(a, xn)
        if e6 != ok { ret (0.0f64, 0.0f64, e6) }
        let (dr, e7) = dp.dip(a, so, false)
        if e7 != ok { ret (0.0f64, 0.0f64, e7) }
        if dr.dip >= d { cnt += 1usize }
        mem.reset(a, mark)
        i += 1usize
    }
    ret (f64(1usize + cnt) / f64(1usize + mm), bwnew, ok)
}

// the dip statistic of the sorted sample xs
fn dipof(a: *mem.Arena, xs: []const f64) -> (f64, err) {
    let (dr, e) = dp.dip(a, xs, false)
    ret (dr.dip, e)
}

// diptest.multi(xdata, class, M): x is m by p, lab the labels (any integers); the first discriminant coordinate when p > 1
fn diptest_multi(a: *mem.Arena, g: *rg.Rng, x: []const f64, m: usize, p: usize, lab: []const usize, mm: usize) -> (f64, err) {
    let (xu, e1) = mem.alloc[f64](a, m)
    if e1 != ok { ret (0.0f64, e1) }
    var i = 0usize
    if p == 1usize {
        while i < m {
            xu[i] = x[i]
            i += 1usize
        }
    } else {
        let (rl, e2) = mem.alloc[usize](a, m)
        let (ev, e3) = mem.alloc[f64](a, p)
        let (un, e4) = mem.alloc[f64](a, p * p)
        let (pj, e5) = mem.alloc[f64](a, m * p)
        let (wo, e6) = mem.alloc[f64](a, p * p)
        if e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (0.0f64, Malformed) }
        // the labels become 1..K in increasing order, as factor(clvec) numbers its levels
        var kn = 0usize
        var prev = 0usize
        var have = false
        while true {
            var nx = 0usize
            var f = false
            i = 0usize
            while i < m {
                if (!have || lab[i] > prev) && (!f || lab[i] < nx) {
                    nx = lab[i]
                    f = true
                }
                i += 1usize
            }
            if !f { break }
            kn += 1usize
            i = 0usize
            while i < m {
                if lab[i] == nx { rl[i] = kn }
                i += 1usize
            }
            prev = nx
            have = true
        }
        let e7 = fp.discrcoord(a, x, m, p, rl, kn, 0usize, ev, un, pj, wo)
        if e7 != ok { ret (0.0f64, e7) }
        i = 0usize
        while i < m {
            xu[i] = pj[i * p]
            i += 1usize
        }
    }
    let (xs, e8) = sort_copy(a, xu)
    if e8 != ok { ret (0.0f64, e8) }
    let (dr, e9) = dp.dip(a, xs, false)
    if e9 != ok { ret (0.0f64, e9) }
    let (pv, bw, e10) = dipp_tantrum(a, g, xu, dr.dip, mm)
    ret (pv, e10)
}
