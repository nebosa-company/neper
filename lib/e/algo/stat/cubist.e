// R package Cubist 2.07 GPL (Quinlan's rule-based regression models, as the package C code runs them): the model tree (FormTree with its regression
// at every node, the continuous and discrete split search, Prune with Pregibon-style smoothing), the rules cut from the tree paths (FormRules, with the
// pruning of conditions, the duplicate test and optional unbiasing), committees, and the exact data preparation (single-precision values, the precision
// of the data, means replacing missing values).
//
// C `float` values are kept in f64 slots and rounded with r32 at every point the C code stores or computes in single precision; `double`
// values are not rounded. Attribute numbers are Cubist's: 1 is the outcome, 2.. are the predictors in the order given. A discrete value is
// stored as its Cubist number: 0 missing, 1 not applicable, 2.. the levels in order (so a factor with k levels has MaxAttVal k + 1).
//
// The nearest-neighbor stage (K-D index, close distance, averaging), the model as the package reads it back (every number printed with its own
// precision and parsed again), predict at 0 to 9 neighbors, the attribute usage and the evaluation on the training data are below.
// The random stream is the package one (the seed is taken from the clock by the C code; with sample > 0 the value used is the init in the model header).
// Not here: case weights, implicit (defined) attributes, date and time predictors, N/A values, cross-validation, the printed report text.

use e.math
use e.mem
use e.str
use e.math.nmath as nm

error Fail

const BR_DISCR: usize = 1usize
const BR_THRESH: usize = 2usize
const BR_SUBSET: usize = 3usize
const MINSPLIT: i64 = 3i64
fn epsilon() -> f64 { ret 0.0001f64 }

// the whole environment: data, attribute facts, globals, the regression scratch (GEnv), the tree pool and the rule sets
type Cb = struct {
    n: usize, na: usize, w: usize, mw: usize, ncap: usize,
    dat: []f64, cls: []f64, ord: []usize, saved: []usize, resid: []f64, pcnt: []i64, cpred: []f64,
    disc: []bool, ordr: []bool, skip: []bool, maxv: []usize, modal: []usize,
    amean: []f64, asd: []f64, amax: []f64, amin: []f64, apref: []f64, aunit: []f64, aprec: []i64,
    gmean: f64, gsd: f64, ceil: f64, flo: f64, extrap: f64, minitems: i64, maxrules: i64, members: usize, unbiased: bool, nn: usize, maxd: f64,
    sv: []f64, st: []f64,
    // GEnv
    localmodel: []f64, valfreq: []f64, valsum: []f64, valsumsq: []f64, brfreq: [4]f64, brsum: [4]f64, brsumsq: [4]f64,
    donotuse: []bool, gain: []f64, bar: []f64, left: []bool, gsub: []bool, modelatt: []usize, nmodelatt: i64,
    xtx: []f64, xty: []f64, amat: []f64, bmat: []f64, bestmodel: []f64, gresid: []f64, presid: []f64,
    gmeanv: []f64, gvar: []f64, avdev: []f64, zerocoeff: []bool, savezero: []bool, filt: []usize,
    // tree pool
    nt_count: usize, nt_type: []usize, nt_cases: []i64, nt_mean: []f64, nt_sd: []f64, nt_model: []f64, nt_mcopy: []f64, nt_tested: []usize,
    nt_forks: []usize, nt_cut: []f64, nt_sub: []bool, nt_br: []i64, nt_params: []f64, nt_coeffs: []f64, nt_treeerr: []f64, nt_leaferr: []f64, nt_util: []f64,
    // pruning globals
    totalerr: f64, extraerr: f64, totalparams: f64, extraparams: f64, adjerrlim: f64, newadjerr: f64, weakest: i64,
    nt_parent: []i64, prec: i64, bad: bool,
    // rules: the committee, and the rule list being built
    cttee: []RSet, rb: []Rule, nrb: usize,
    // instances: the K-D index, the tabulated rule predictions, the neighbors found
    inst: []usize, drf1: []f64, drf2: []f64, rspred: []f64, ref0: []f64, ref1: []f64,
    ix_tested: []usize, ix_cut: []f64, ix_min0: []f64, ix_max0: []f64, ix_min1: []f64, ix_max1: []f64,
    ix_fp: []i64, ix_lp: []i64, ix_sub: []i64, ixw: usize, ix_n: usize, ix_tst: []bool, ix_vf: []i64,
    bestd: [20]f64, besti: [20]i64, attmind: []f64, worst: usize, minn: i64, nnk: i64, kdroot: i64, useinst: bool, nrule_cap: usize
}

type Cond = struct { ty: usize, att: usize, cut: f64, tv: i64, sub: []bool }
type Rule = struct { size: usize, cover: i64, mean: f64, lo: f64, hi: f64, lolim: f64, hilim: f64, esterr: f64, lhs: []Cond, rhs: []f64 }
type RSet = struct { nr: usize, rules: []Rule }

fn r32(x: f64) -> f64 { ret f64(f32(x)) }

fn cb_zf(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (v, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i <= n {
        v[i] = 0.0f64
        i += 1usize
    }
    ret (v[0usize..n], ok)
}

fn cb_zu(a: *mem.Arena, n: usize) -> ([]usize, err) {
    let (v, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i <= n {
        v[i] = 0usize
        i += 1usize
    }
    ret (v[0usize..n], ok)
}

fn cb_zi(a: *mem.Arena, n: usize) -> ([]i64, err) {
    let (v, e) = mem.alloc[i64](a, n + 1usize)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i <= n {
        v[i] = 0i64
        i += 1usize
    }
    ret (v[0usize..n], ok)
}

fn cb_zb(a: *mem.Arena, n: usize) -> ([]bool, err) {
    let (v, e) = mem.alloc[bool](a, n + 1usize)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i <= n {
        v[i] = false
        i += 1usize
    }
    ret (v[0usize..n], ok)
}

fn ux(i: i64) -> usize { ret usize(i) }

// CVal(Case[i], att)
fn cv(c: *Cb, i: i64, att: usize) -> f64 { ret c.dat[c.ord[ux(i)] * c.w + att] }

// Class(Case[i])
fn clsv(c: *Cb, i: i64) -> f64 { ret c.cls[c.ord[ux(i)]] }

fn cb_swap(c: *Cb, a: i64, b: i64) {
    let t = c.ord[ux(a)]
    c.ord[ux(a)] = c.ord[ux(b)]
    c.ord[ux(b)] = t
}

fn cb_rint(x: f64) -> f64 { ret nm.rint(x) }

fn cb_fabs(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn cb_min(x: f64, y: f64) -> f64 {
    if x < y { ret x }
    ret y
}

fn cb_max(x: f64, y: f64) -> f64 {
    if x > y { ret x }
    ret y
}

// ---- the random number generator of utility.c (Knuth's subtractive generator), used for sampling and for the close distance

type Kr = struct { urd: [55]f64, fp: i64, sp: i64 }

fn kr_modify(k: *Kr, f: usize, s: usize) {
    k.urd[f] = k.urd[f] - k.urd[s]
    if k.urd[f] < 0.0f64 { k.urd[f] = k.urd[f] + 1.0f64 }
}

fn kr_random(k: *Kr) -> f64 {
    if k.fp == k.sp {
        k.fp = 0i64
        k.sp = 31i64
        var v1 = 1.0f64
        var v2 = 0.314159285f64
        var i = 1i64
        while i <= 55i64 {
            let j = ux((i * 21i64) % 55i64)
            k.urd[j] = v1
            v1 = v2 - v1
            if v1 < 0.0f64 { v1 = v1 + 1.0f64 }
            v2 = k.urd[j]
            i += 1i64
        }
        var jj = 0i64
        while jj <= 5i64 {
            i = 0i64
            while i <= 54i64 {
                kr_modify(k, ux(i), ux((i + 30i64) % 55i64))
                i += 1i64
            }
            jj += 1i64
        }
    }
    k.fp = (k.fp + 1i64) % 55i64
    k.sp = (k.sp + 1i64) % 55i64
    kr_modify(k, ux(k.fp), ux(k.sp))
    ret k.urd[ux(k.fp)]
}

fn kr_reset(k: *Kr, init: i64) {
    k.fp = 0i64
    k.sp = 0i64
    var left = init + 1000i64
    while left > 0i64 {
        let _ = kr_random(k)
        left -= 1i64
    }
}

// ---- precision of a value (utility.c Denominator, FracBase)

fn cb_denominator(val: f64) -> i64 {
    var resid = cb_fabs(val)
    if resid == 0.0f64 { ret 1i64 }
    var mult = 1i64
    var maxmult = 1000000i64
    while resid < 0.1f64 {
        resid = resid * 10.0f64
        mult = mult * 10i64
    }
    var ip = math.floor[f64](resid)
    resid = resid - ip
    while ip >= 1.0f64 && maxmult >= 10i64 {
        ip = ip / 10.0f64
        maxmult = maxmult / 10i64
    }
    while mult < maxmult {
        if resid < 0.005f64 || resid > 0.995f64 { ret mult }
        let t = resid * 10.0f64
        let f = math.floor[f64](t)
        resid = t - f
        mult = mult * 10i64
    }
    ret maxmult
}

// ---- data: the columns as the package writes them. kind 0 numeric (NaN missing), 1 factor, 2 ordered factor (codes 1..nlev, 0 or NaN missing).
// `rows` lists the training rows used (the sample); the attribute facts of GetData are computed over them.

type Data = struct { n: usize, p: usize, kind: []usize, nlev: []usize, x: []f64, y: []f64 }

fn cb_alloc_all(a: *mem.Arena, c: *Cb, n: usize, na: usize) -> err {
    c.n = n
    c.na = na
    c.w = na + 1usize
    let w = c.w
    var e: err = ok
    let (d1, e1) = cb_zf(a, n * w)
    let (d2, e2) = cb_zf(a, n)
    let (d3, e3) = cb_zu(a, n)
    let (d4, e4) = cb_zu(a, n)
    let (d5, e5) = cb_zf(a, n)
    let (d6, e6) = cb_zi(a, n)
    let (d7, e7) = cb_zf(a, n)
    c.dat = d1
    c.cls = d2
    c.ord = d3
    c.saved = d4
    c.resid = d5
    c.pcnt = d6
    c.cpred = d7
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { e = mem.Exhausted }
    let (b1, f1) = cb_zb(a, w)
    let (b2, f2) = cb_zb(a, w)
    let (b3, f3) = cb_zb(a, w)
    let (u1, f4) = cb_zu(a, w)
    let (u2, f5) = cb_zu(a, w)
    c.disc = b1
    c.ordr = b2
    c.skip = b3
    c.maxv = u1
    c.modal = u2
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok { e = mem.Exhausted }
    let (m1, g1) = cb_zf(a, w)
    let (m2, g2) = cb_zf(a, w)
    let (m3, g3) = cb_zf(a, w)
    let (m4, g4) = cb_zf(a, w)
    let (m5, g5) = cb_zf(a, w)
    let (m6, g6) = cb_zf(a, w)
    let (m7, g7) = cb_zi(a, w)
    c.amean = m1
    c.asd = m2
    c.amax = m3
    c.amin = m4
    c.apref = m5
    c.aunit = m6
    c.aprec = m7
    if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok || g7 != ok { e = mem.Exhausted }
    ret e
}

// GetData for the training cases: values to single precision, then the means, standard deviations, limits, modal values and precision, then the
// replacement of the unknown values. `rows` are the data rows kept for training.
fn cb_get_data(a: *mem.Arena, c: *Cb, d: *const Data, rows: []const usize, extrap: f64) -> err {
    let n = rows.len
    let p = d.p
    let na = p + 1usize
    let e0 = cb_alloc_all(a, c, n, na)
    if e0 != ok { ret e0 }
    c.extrap = extrap
    let w = c.w
    var i = 0usize
    var maxdisc = 3usize
    // attribute 1 is the outcome
    c.disc[1usize] = false
    var j = 0usize
    while j < p {
        let at = j + 2usize
        if d.kind[j] != 0usize {
            c.disc[at] = true
            c.maxv[at] = d.nlev[j] + 1usize
            if d.kind[j] == 2usize { c.ordr[at] = true }
            if c.maxv[at] + 1usize > maxdisc { maxdisc = c.maxv[at] + 1usize }
        }
        j += 1usize
    }
    c.mw = maxdisc + 2usize
    i = 0usize
    while i < n {
        let r = rows[i]
        c.ord[i] = i
        let yv = r32(d.y[r])
        c.cls[i] = yv
        c.dat[i * w + 1usize] = yv
        j = 0usize
        while j < p {
            let at = j + 2usize
            let xv = d.x[j * d.n + r]
            if c.disc[at] {
                var code = 0.0f64
                if xv == xv && xv >= 1.0f64 { code = xv + 1.0f64 }
                c.dat[i * w + at] = code
            } else {
                c.dat[i * w + at] = r32(xv)
            }
            j += 1usize
        }
        i += 1usize
    }
    // means, limits, precision. A missing continuous value is NaN here.
    var at = 1usize
    while at <= na {
        if !c.disc[at] {
            var sum = 0.0f64
            var sumsq = 0.0f64
            var count = 0i64
            i = 0usize
            while i < n {
                let v = c.dat[i * w + at]
                if v == v {
                    sum += v
                    sumsq += r32(v * v)
                    count += 1i64
                }
                i += 1usize
            }
            if count > 1i64 {
                // FracBase
                var denom = 0i64
                i = 0usize
                while i < n {
                    let v = c.dat[i * w + at]
                    if v == v {
                        let td = cb_denominator(v)
                        if td > denom {
                            denom = td
                            if denom == 1000000i64 { break }
                        }
                    }
                    i += 1usize
                }
                c.aprec[at] = 10i64 * denom
                let ap = f64(c.aprec[at])
                c.amean[at] = r32(math.floor[f64]((sum / f64(count)) * ap + 0.1f64) / ap)
                c.asd[at] = r32(math.sqrt[f64]((sumsq - sum * sum / f64(count)) / f64(count - 1i64)) + 0.000001f64)
            } else {
                c.aprec[at] = 0i64
                c.amean[at] = 0.0f64
                c.asd[at] = 1.0f64
                c.skip[at] = true
            }
            var mx = -1.0e38f64
            var mn = 1.0e38f64
            i = 0usize
            while i < n {
                let v = c.dat[i * w + at]
                if v == v {
                    if v > mx { mx = v }
                    if v < mn { mn = v }
                }
                i += 1usize
            }
            c.amax[at] = r32(mx)
            c.amin[at] = r32(mn)
        } else {
            let (fr, ef) = cb_zi(a, c.maxv[at] + 1usize)
            if ef != ok { ret ef }
            i = 0usize
            while i < n {
                let v = usize(c.dat[i * w + at])
                if v != 0usize { fr[v] += 1i64 }
                i += 1usize
            }
            var m = 0usize
            var v = 2usize
            while v <= c.maxv[at] {
                if fr[v] > fr[m] { m = v }
                v += 1usize
            }
            c.modal[at] = m
            if m == 0usize { c.skip[at] = true }
        }
        at += 1usize
    }
    // the unknown values become the mean or the modal value
    i = 0usize
    while i < n {
        at = 1usize
        while at <= na {
            if !c.skip[at] && at != 1usize {
                if c.disc[at] {
                    if c.dat[i * w + at] == 0.0f64 { c.dat[i * w + at] = f64(c.modal[at]) }
                } else {
                    let v = c.dat[i * w + at]
                    if v != v { c.dat[i * w + at] = c.amean[at] }
                }
            }
            at += 1usize
        }
        i += 1usize
    }
    // an attribute that was skipped keeps NaN out of the arithmetic
    i = 0usize
    while i < n {
        at = 1usize
        while at <= na {
            let v = c.dat[i * w + at]
            if v != v { c.dat[i * w + at] = 0.0f64 }
            at += 1usize
        }
        i += 1usize
    }
    // ceiling and floor of the predictions
    let range = r32(c.amax[1usize] - c.amin[1usize])
    c.ceil = r32(c.amax[1usize] + r32(c.extrap * range))
    if c.amax[1usize] <= 0.0f64 && c.ceil > 0.0f64 { c.ceil = 0.0f64 }
    c.flo = r32(c.amin[1usize] - r32(c.extrap * range))
    if c.amin[1usize] >= 0.0f64 && c.flo < 0.0f64 { c.flo = 0.0f64 }
    c.prec = i64(math.log[f64](f64(c.aprec[1usize]) / 10.0f64) / math.log[f64](10.0f64) + 0.5f64)
    ret ok
}

// ---- statistics (stats.c)

fn cb_sd(c: *Cb, nn: f64, sum: f64, sumsq: f64) -> f64 {
    if nn < 2.0f64 { ret c.gsd }
    ret math.sqrt[f64]((sumsq - sum * sum / nn + 0.001f64) / (nn - 1.0f64))
}

fn cb_compute_gain(c: *Cb, node: usize) -> f64 {
    var resid = 0.0f64
    var cases = 0.0f64
    var v = 1usize
    while v <= 3usize {
        cases += c.brfreq[v]
        resid += c.brfreq[v] * cb_sd(c, c.brfreq[v], c.brsum[v], c.brsumsq[v])
        v += 1usize
    }
    ret c.nt_sd[node] - resid / cases
}

fn cb_estimate_err(val: f64, ndata: f64, nparam: f64) -> f64 {
    var np = r32(nparam)
    if np >= ndata { np = r32(ndata - 1.0f64) }
    ret val * (ndata + np) / (ndata - np)
}

// ---- linear models (predict.c)

fn cb_find_model_atts(c: *Cb, model: []const f64) {
    c.nmodelatt = 0i64
    var at = 1usize
    while at <= c.na {
        if model[at] != 0.0f64 {
            c.nmodelatt += 1i64
            c.modelatt[ux(c.nmodelatt)] = at
        }
        at += 1usize
    }
}

fn cb_raw_lin(c: *Cb, model: []const f64, row: usize) -> f64 {
    var sum = model[0usize]
    var q = 1i64
    while q <= c.nmodelatt {
        let at = c.modelatt[ux(q)]
        sum += model[at] * c.dat[row * c.w + at]
        q += 1i64
    }
    ret r32(sum)
}

fn cb_lin(c: *Cb, model: []const f64, row: usize) -> f64 {
    let raw = cb_raw_lin(c, model, row)
    if raw < c.flo { ret c.flo }
    if raw > c.ceil { ret c.ceil }
    ret raw
}

// ---- sort.c

fn cb_swapsr(c: *Cb, x: i64, y: i64) {
    let ax = ux(x)
    let ay = ux(y)
    let tv = c.sv[ax]
    c.sv[ax] = c.sv[ay]
    c.sv[ay] = tv
    let tt = c.st[ax]
    c.st[ax] = c.st[ay]
    c.st[ay] = tt
}

fn cb_cachesort(c: *Cb, f0: i64, lp: i64) {
    var fp = f0
    while fp < lp {
        let thresh = c.sv[ux((fp + lp) / 2i64)]
        var middle = fp
        while c.sv[ux(middle)] < thresh { middle += 1i64 }
        var high = lp
        while c.sv[ux(high)] > thresh { high -= 1i64 }
        var i = middle
        while i <= high {
            let val = c.sv[ux(i)]
            if val < thresh {
                cb_swapsr(c, middle, i)
                middle += 1i64
                i += 1i64
            } else if val > thresh {
                cb_swapsr(c, high, i)
                high -= 1i64
            } else {
                i += 1i64
            }
        }
        cb_cachesort(c, fp, middle - 1i64)
        fp = high + 1i64
    }
}

// ---- regress.c

fn cb_find_active(c: *Cb) {
    c.nmodelatt = 0i64
    var at = 0usize
    while at <= c.na {
        if !c.zerocoeff[at] {
            c.modelatt[ux(c.nmodelatt)] = at
            c.nmodelatt += 1i64
        }
        at += 1usize
    }
    c.nmodelatt -= 1i64
}

fn cb_add_row(c: *Cb, from: usize, to: usize, factor: f64) {
    let w = c.w
    var col = 0i64
    while col <= c.nmodelatt {
        let q = ux(col)
        c.amat[to * w + q] += factor * c.amat[from * w + q]
        col += 1i64
    }
    c.bmat[to] += factor * c.bmat[from]
}

fn cb_exchange_row(c: *Cb, from: usize, to: usize) {
    let w = c.w
    var col = 0i64
    while col <= c.nmodelatt {
        let q = ux(col)
        let h = c.amat[from * w + q]
        c.amat[from * w + q] = c.amat[to * w + q]
        c.amat[to * w + q] = h
        col += 1i64
    }
    let hb = c.bmat[from]
    c.bmat[from] = c.bmat[to]
    c.bmat[to] = hb
}

fn cb_solve(c: *Cb, model: []f64) {
    let w = c.w
    if c.nmodelatt == 0i64 {
        model[0usize] = c.xty[0usize] / c.xtx[0usize]
        var j = 1usize
        while j <= c.na {
            model[j] = 0.0f64
            j += 1usize
        }
        ret
    }
    var singular = false
    var j = 0i64
    while j <= c.nmodelatt {
        let uj = ux(j)
        let ja = c.modelatt[uj]
        var k = 0i64
        while k <= j {
            let v = c.xtx[ja * w + c.modelatt[ux(k)]]
            c.amat[uj * w + ux(k)] = v
            c.amat[ux(k) * w + uj] = v
            k += 1i64
        }
        c.bmat[uj] = c.xty[ja]
        j += 1i64
    }
    j = 0i64
    while j <= c.nmodelatt {
        let uj = ux(j)
        let jj = c.modelatt[uj]
        var maxelt = 0.0f64
        var k = 0i64
        while k <= j {
            let t = cb_fabs(c.xtx[c.modelatt[ux(k)] * w + jj])
            if t > maxelt { maxelt = t }
            k += 1i64
        }
        let minpivot = f64(c.nmodelatt + 1i64) * maxelt * 1.0e-12f64
        var mx = j
        var pivot = cb_fabs(c.amat[uj * w + uj])
        k = j + 1i64
        while k <= c.nmodelatt {
            let t = cb_fabs(c.amat[ux(k) * w + uj])
            if t > pivot {
                mx = k
                pivot = t
            }
            k += 1i64
        }
        if pivot < minpivot {
            c.zerocoeff[jj] = true
            singular = true
        } else {
            if mx != j { cb_exchange_row(c, ux(mx), uj) }
            pivot = c.amat[uj * w + uj]
            k = j
            while k <= c.nmodelatt {
                c.amat[uj * w + ux(k)] /= pivot
                k += 1i64
            }
            c.bmat[uj] /= pivot
            k = j + 1i64
            while k <= c.nmodelatt {
                cb_add_row(c, uj, ux(k), 0.0f64 - c.amat[ux(k) * w + uj])
                k += 1i64
            }
        }
        j += 1i64
    }
    if singular {
        cb_find_active(c)
        cb_solve(c, model)
        ret
    }
    j = c.nmodelatt - 1i64
    while j >= 0i64 {
        var k = j + 1i64
        while k <= c.nmodelatt {
            c.bmat[ux(j)] -= c.amat[ux(j) * w + ux(k)] * c.bmat[ux(k)]
            k += 1i64
        }
        j -= 1i64
    }
    var q = 1usize
    while q <= c.na {
        model[q] = 0.0f64
        q += 1usize
    }
    j = 0i64
    while j <= c.nmodelatt {
        model[c.modelatt[ux(j)]] = c.bmat[ux(j)]
        j += 1i64
    }
}

fn cb_row_of(c: *Cb, usef: bool, i: i64) -> usize {
    if usef { ret c.filt[ux(i)] }
    ret c.ord[ux(i)]
}

fn cb_average_err(c: *Cb, usef: bool, fp: i64, lp: i64, model: []f64) -> f64 {
    cb_find_model_atts(c, model)
    var sum = 0.0f64
    var sumwt = 0.0f64
    var i = fp
    while i <= lp {
        let r = cb_row_of(c, usef, i)
        sum += cb_fabs(r32(c.cls[r] - cb_lin(c, model, r)))
        sumwt += 1.0f64
        i += 1i64
    }
    ret sum / sumwt
}

fn cb_simplify_model(c: *Cb, usef: bool, fp: i64, lp: i64, model: []f64) {
    var bestadj = 1.0e10f64
    var cases = 0.0f64
    var i = fp
    while i <= lp {
        cases += 1.0f64
        i += 1i64
    }
    var q = 0usize
    while q <= c.na {
        c.savezero[q] = c.zerocoeff[q]
        q += 1usize
    }
    var drop = 1usize
    var leastc = 0.0f64
    while drop != 0usize {
        var stable = true
        drop = 0usize
        var a = 1i64
        while a <= c.nmodelatt {
            let at = c.modelatt[ux(a)]
            let contrib = cb_fabs(model[at] * c.avdev[at])
            if drop == 0usize || contrib < leastc {
                drop = at
                leastc = contrib
            }
            if contrib > 1000.0f64 * c.avdev[0usize] { stable = false }
            a += 1i64
        }
        if stable && cases >= 2.0f64 * f64(c.nmodelatt) {
            let moderr = cb_average_err(c, usef, fp, lp, model)
            let adj = cb_estimate_err(moderr, cases, f64(c.nmodelatt))
            if adj <= bestadj {
                bestadj = adj
                q = 0usize
                while q <= c.na {
                    c.bestmodel[q] = model[q]
                    q += 1usize
                }
            }
        }
        if drop != 0usize {
            model[drop] = 0.0f64
            c.zerocoeff[drop] = true
            cb_find_active(c)
            cb_solve(c, model)
        }
    }
    q = 0usize
    while q <= c.na {
        model[q] = c.bestmodel[q]
        c.zerocoeff[q] = c.savezero[q]
        q += 1usize
    }
}

fn cb_build_tables(c: *Cb, fp: i64, lp: i64) {
    let w = c.w
    cb_find_active(c)
    var jj = 0i64
    while jj <= c.nmodelatt {
        let j = c.modelatt[ux(jj)]
        c.xty[j] = 0.0f64
        var kk = 0i64
        while kk <= jj {
            c.xtx[j * w + c.modelatt[ux(kk)]] = 0.0f64
            kk += 1i64
        }
        jj += 1i64
    }
    c.xtx[0usize] = 0.0f64
    var i = fp
    while i <= lp {
        let r = c.ord[ux(i)]
        c.xtx[0usize] += 1.0f64
        let classval = c.cls[r]
        c.xty[0usize] += classval
        jj = 1i64
        while jj <= c.nmodelatt {
            let j = c.modelatt[ux(jj)]
            let jval = c.dat[r * w + j]
            c.xty[j] += jval * classval
            c.xtx[j * w] += jval
            var kk = 1i64
            while kk <= jj {
                let k = c.modelatt[ux(kk)]
                c.xtx[j * w + k] += jval * c.dat[r * w + k]
                kk += 1i64
            }
            jj += 1i64
        }
        i += 1i64
    }
}

fn cb_regress(c: *Cb, fp: i64, lp: i64, model: []f64) {
    let w = c.w
    c.nmodelatt = 0i64
    c.modelatt[0usize] = 0usize
    c.gmeanv[0usize] = 0.0f64
    c.gvar[0usize] = 0.0f64
    model[0usize] = 0.0f64
    c.avdev[0usize] = 0.0f64
    c.zerocoeff[0usize] = false
    var at = 1usize
    while at <= c.na {
        if !c.disc[at] && at != 1usize && !c.skip[at] && !c.donotuse[at] {
            c.nmodelatt += 1i64
            c.modelatt[ux(c.nmodelatt)] = at
            c.gmeanv[at] = 0.0f64
            c.gvar[at] = 0.0f64
            model[at] = 0.0f64
            c.avdev[at] = 0.0f64
            c.zerocoeff[at] = false
        } else {
            c.zerocoeff[at] = true
        }
        at += 1usize
    }
    var cases = 0.0f64
    var i = fp
    while i <= lp {
        let r = c.ord[ux(i)]
        cases += 1.0f64
        var a = 0i64
        while a <= c.nmodelatt {
            let att = c.modelatt[ux(a)]
            var val = 0.0f64
            if att == 0usize { val = c.cls[r] } else { val = c.dat[r * w + att] }
            c.gmeanv[att] += val
            c.gvar[att] += val * val
            a += 1i64
        }
        i += 1i64
    }
    c.gmeanv[0usize] /= cases
    var a = 1i64
    while a <= c.nmodelatt {
        let att = c.modelatt[ux(a)]
        c.gmeanv[att] /= cases
        c.gvar[att] = (c.gvar[att] - cases * c.gmeanv[att] * c.gmeanv[att]) / (cases - 1.0f64)
        if c.gvar[att] < 1.0e-6f64 {
            c.zerocoeff[att] = true
            c.modelatt[ux(a)] = c.modelatt[ux(c.nmodelatt)]
            c.nmodelatt -= 1i64
            a -= 1i64
        }
        a += 1i64
    }
    i = fp
    while i <= lp {
        let r = c.ord[ux(i)]
        a = 0i64
        while a <= c.nmodelatt {
            let att = c.modelatt[ux(a)]
            var val = 0.0f64
            if att == 0usize { val = c.cls[r] } else { val = c.dat[r * w + att] }
            c.avdev[att] += cb_fabs(val - c.gmeanv[att])
            a += 1i64
        }
        i += 1i64
    }
    a = 0i64
    while a <= c.nmodelatt {
        let att = c.modelatt[ux(a)]
        c.avdev[att] /= cases
        a += 1i64
    }
    if c.nmodelatt < 1i64 || cases < 2.0f64 * f64(c.nmodelatt) {
        model[0usize] = c.gmeanv[0usize]
        at = 1usize
        while at <= c.na {
            model[at] = 0.0f64
            at += 1usize
        }
        ret
    }
    cb_build_tables(c, fp, lp)
    cb_solve(c, model)
    cb_simplify_model(c, false, fp, lp, model)
    cb_find_model_atts(c, model)
    if c.nmodelatt == 0i64 { ret }
    var sumr = 0.0f64
    var bias = 0.0f64
    i = fp
    while i <= lp {
        let r = c.ord[ux(i)]
        c.gresid[ux(i)] = r32(c.cls[r] - cb_lin(c, model, r))
        sumr += cb_fabs(c.gresid[ux(i)])
        bias += c.gresid[ux(i)]
        i += 1i64
    }
    let avresid = sumr / cases
    model[0usize] += bias / cases
    var kp = fp - 1i64
    var first = true
    i = fp
    while i <= lp {
        let r = c.ord[ux(i)]
        if cb_fabs(c.gresid[ux(i)]) > 5.0f64 * avresid {
            if first {
                cb_find_active(c)
                first = false
            }
            c.xtx[0usize] -= 1.0f64
            let classval = c.cls[r]
            c.xty[0usize] -= classval
            var jj = 1i64
            while jj <= c.nmodelatt {
                let j = c.modelatt[ux(jj)]
                let jval = c.dat[r * w + j]
                c.xty[j] -= jval * classval
                c.xtx[j * w] -= jval
                var kk = 1i64
                while kk <= jj {
                    let k = c.modelatt[ux(kk)]
                    c.xtx[j * w + k] -= jval * c.dat[r * w + k]
                    kk += 1i64
                }
                jj += 1i64
            }
        } else {
            kp += 1i64
            c.filt[ux(kp)] = r
        }
        i += 1i64
    }
    if kp < lp {
        cb_solve(c, model)
        cb_simplify_model(c, true, fp, kp, model)
    }
}

// ---- trees (trees.c, formtree.c, contin.c, discr.c)

fn cb_leaf(c: *Cb, cases: i64, mean: f64, sd: f64) -> usize {
    let k = c.nt_count
    c.nt_count += 1usize
    c.nt_type[k] = 0usize
    c.nt_cases[k] = cases
    c.nt_mean[k] = mean
    c.nt_sd[k] = sd
    var q = 0usize
    while q <= c.na {
        c.nt_model[k * c.w + q] = 0.0f64
        c.nt_mcopy[k * c.w + q] = 0.0f64
        q += 1usize
    }
    c.nt_model[k * c.w] = mean
    c.nt_tested[k] = 0usize
    c.nt_parent[k] = -1i64
    c.nt_forks[k] = 0usize
    c.nt_cut[k] = 0.0f64
    q = 0usize
    while q < 4usize {
        c.nt_br[k * 4usize + q] = -1i64
        q += 1usize
    }
    q = 0usize
    while q < 4usize * c.mw {
        c.nt_sub[k * 4usize * c.mw + q] = false
        q += 1usize
    }
    c.nt_params[k] = 0.0f64
    c.nt_coeffs[k] = 0.0f64
    c.nt_treeerr[k] = 0.0f64
    c.nt_leaferr[k] = 0.0f64
    c.nt_util[k] = 0.0f64
    ret k
}

fn cb_tree_size(c: *Cb, t: usize) -> i64 {
    if c.nt_type[t] != 0usize {
        var s = 1i64
        var v = 1usize
        while v <= c.nt_forks[t] {
            s += cb_tree_size(c, usize(c.nt_br[t * 4usize + v]))
            v += 1usize
        }
        ret s
    }
    ret 1i64
}

fn cb_tree_leaves(c: *Cb, t: usize) -> i64 {
    if c.nt_cases[t] < 1i64 { ret 0i64 }
    if c.nt_type[t] != 0usize {
        var s = 0i64
        var v = 1usize
        while v <= c.nt_forks[t] {
            s += cb_tree_leaves(c, usize(c.nt_br[t * 4usize + v]))
            v += 1usize
        }
        ret s
    }
    ret 1i64
}

fn cb_find_global(a: *mem.Arena, c: *Cb) -> err {
    let n = c.n
    let (cnt, e1) = cb_zi(a, c.na + 1usize)
    let (same, e2) = cb_zi(a, c.na + 1usize)
    if e1 != ok || e2 != ok { ret mem.Exhausted }
    var sum = 0.0f64
    var sumsq = 0.0f64
    var i = 0usize
    while i < n {
        let val = c.cls[c.ord[i]]
        sum += val
        sumsq += val * val
        let above = val > c.amean[1usize]
        var at = 1usize
        while at <= c.na {
            if !c.skip[at] && !c.disc[at] && at != 1usize {
                let v = c.dat[c.ord[i] * c.w + at]
                if v != c.amean[at] {
                    cnt[at] += 1i64
                    var gt = false
                    if v > c.amean[at] { gt = true }
                    if gt == above { same[at] += 1i64 }
                }
            }
            at += 1usize
        }
        i += 1usize
    }
    c.gmean = r32(sum / f64(n))
    c.gsd = r32(cb_sd(c, f64(n), sum, sumsq))
    c.aunit[0usize] = 1.0f64 / f64(c.aprec[1usize])
    var at = 1usize
    while at <= c.na {
        if c.skip[at] || c.disc[at] || at == 1usize || cnt[at] == 0i64 {
            c.apref[at] = 0.0f64
        } else {
            var mxs = same[at]
            if cnt[at] - same[at] > mxs { mxs = cnt[at] - same[at] }
            c.apref[at] = r32(f64(2i64 * mxs - cnt[at]) / f64(n))
            c.aunit[at] = 1.0f64
            let mincoeff = 0.01f64 * c.gsd / c.asd[at]
            if mincoeff > 0.0f64 {
                while c.aunit[at] > mincoeff { c.aunit[at] = c.aunit[at] / 10.0f64 }
            }
        }
        at += 1usize
    }
    ret ok
}

// ---- allocation of the tree environment (InitialiseEnvData) and the node pool

fn az(a: *mem.Arena, c: *Cb, n: usize) -> []f64 {
    let (v, e) = cb_zf(a, n)
    if e != ok { c.bad = true }
    ret v
}

fn azu(a: *mem.Arena, c: *Cb, n: usize) -> []usize {
    let (v, e) = cb_zu(a, n)
    if e != ok { c.bad = true }
    ret v
}

fn azi(a: *mem.Arena, c: *Cb, n: usize) -> []i64 {
    let (v, e) = cb_zi(a, n)
    if e != ok { c.bad = true }
    ret v
}

fn azb(a: *mem.Arena, c: *Cb, n: usize) -> []bool {
    let (v, e) = cb_zb(a, n)
    if e != ok { c.bad = true }
    ret v
}

fn cb_alloc_env(a: *mem.Arena, c: *Cb) {
    let n = c.n
    let w = c.w
    let mw = c.mw
    c.sv = az(a, c, n + 2usize)
    c.st = az(a, c, n + 2usize)
    c.localmodel = az(a, c, w)
    c.valfreq = az(a, c, mw + 1usize)
    c.valsum = az(a, c, mw + 1usize)
    c.valsumsq = az(a, c, mw + 1usize)
    c.donotuse = azb(a, c, w)
    c.gain = az(a, c, w)
    c.bar = az(a, c, w)
    c.left = azb(a, c, mw + 1usize)
    c.gsub = azb(a, c, w * 4usize * mw)
    c.modelatt = azu(a, c, w + 1usize)
    c.xtx = az(a, c, w * w)
    c.xty = az(a, c, w)
    c.amat = az(a, c, w * w)
    c.bmat = az(a, c, w)
    c.bestmodel = az(a, c, w)
    c.gresid = az(a, c, n + 1usize)
    c.presid = az(a, c, n + 1usize)
    c.gmeanv = az(a, c, w)
    c.gvar = az(a, c, w)
    c.avdev = az(a, c, w)
    c.zerocoeff = azb(a, c, w)
    c.savezero = azb(a, c, w)
    c.filt = azu(a, c, n + 1usize)
    let cap = 3usize * n + 8usize
    c.ncap = cap
    c.nt_count = 0usize
    c.nt_type = azu(a, c, cap)
    c.nt_cases = azi(a, c, cap)
    c.nt_mean = az(a, c, cap)
    c.nt_sd = az(a, c, cap)
    c.nt_model = az(a, c, cap * w)
    c.nt_mcopy = az(a, c, cap * w)
    c.nt_tested = azu(a, c, cap)
    c.nt_forks = azu(a, c, cap)
    c.nt_cut = az(a, c, cap)
    c.nt_sub = azb(a, c, cap * 4usize * mw)
    c.nt_br = azi(a, c, cap * 4usize)
    c.nt_params = az(a, c, cap)
    c.nt_coeffs = az(a, c, cap)
    c.nt_treeerr = az(a, c, cap)
    c.nt_leaferr = az(a, c, cap)
    c.nt_util = az(a, c, cap)
    c.nt_parent = azi(a, c, cap)
}

// ---- the split search (contin.c, discr.c)

fn cb_clear_br(c: *Cb) {
    var v = 0usize
    while v < 4usize {
        c.brfreq[v] = 0.0f64
        c.brsum[v] = 0.0f64
        c.brsumsq[v] = 0.0f64
        v += 1usize
    }
}

fn cb_eval_continuous(c: *Cb, node: usize, att: usize, fp: i64, lp: i64) {
    let cases = lp - fp + 1i64
    if cases < 2i64 * MINSPLIT { ret }
    cb_clear_br(c)
    var xp = lp + 1i64
    var hisx = 0.0f64
    var hisxx = 0.0f64
    var hisy = 0.0f64
    var hisyy = 0.0f64
    var hisxy = 0.0f64
    var i = lp
    while i >= fp {
        let r = c.ord[ux(i)]
        let val = c.resid[r]
        let x = c.dat[r * c.w + att]
        xp -= 1i64
        c.sv[ux(xp)] = x
        c.st[ux(xp)] = val
        hisx += x
        hisxx += x * x
        hisy += val
        hisyy += val * val
        hisxy += x * val
        c.brfreq[3usize] += 1.0f64
        i -= 1i64
    }
    cb_cachesort(c, xp, lp)
    var edge = MINSPLIT
    if cases >= 3i64 * c.minitems { edge = c.minitems }
    var bestgain = 0.0f64
    var besti = 0i64
    var losx = 0.0f64
    var losxx = 0.0f64
    var losy = 0.0f64
    var losyy = 0.0f64
    var losxy = 0.0f64
    i = xp
    while i <= lp - edge {
        let x = c.sv[ux(i)]
        let val = c.st[ux(i)]
        c.brfreq[2usize] += 1.0f64
        c.brfreq[3usize] -= 1.0f64
        losx += x
        losxx += x * x
        losy += val
        losyy += val * val
        losxy += x * val
        hisx -= x
        hisxx -= x * x
        hisy -= val
        hisyy -= val * val
        hisxy -= x * val
        if c.sv[ux(i + 1i64)] > c.sv[ux(i)] && i >= xp + edge - 1i64 {
            let lok = i - xp + 1i64
            let lon = c.brfreq[2usize]
            let lomx = losx / lon
            let lovx = losxx / lon - lomx * lomx
            let lomy = losy / lon
            let lovy = losyy / lon - lomy * lomy
            var lor = (losxy - losx * losy / lon) / (lon * math.sqrt[f64](lovx * lovy + 1.0e-10f64))
            var e2z = 1.0e38f64
            if lok >= 6i64 { e2z = math.exp[f64](2.0f64 * 1.96f64 * math.sqrt[f64](1.0f64 / f64(lok - 3i64))) }
            if cb_fabs(lor) < (e2z - 1.0f64) / (e2z + 1.0f64) { lor = 0.0f64 }
            let hik = lp - i
            let hin = c.brfreq[3usize]
            let himx = hisx / hin
            let hivx = hisxx / hin - himx * himx
            let himy = hisy / hin
            let hivy = hisyy / hin - himy * himy
            var hir = (hisxy - hisx * hisy / hin) / (hin * math.sqrt[f64](hivx * hivy + 1.0e-10f64))
            e2z = 1.0e38f64
            if hik >= 6i64 { e2z = math.exp[f64](2.0f64 * 1.96f64 * math.sqrt[f64](1.0f64 / f64(hik - 3i64))) }
            if cb_fabs(hir) < (e2z - 1.0f64) / (e2z + 1.0f64) { hir = 0.0f64 }
            c.brsumsq[2usize] = (1.0f64 - lor * lor) * lon * lovy
            c.brsumsq[3usize] = (1.0f64 - hir * hir) * hin * hivy
            let thisgain = cb_compute_gain(c, node)
            if thisgain > bestgain {
                bestgain = thisgain
                besti = i
            }
        }
        i += 1i64
    }
    if bestgain > 0.0f64 {
        c.gain[att] = r32(bestgain)
        let lowv = c.sv[ux(besti)]
        let highv = c.sv[ux(besti + 1i64)]
        var bar = r32(0.5f64 * r32(lowv + highv))
        if bar >= highv { bar = lowv }
        c.bar[att] = bar
    } else {
        c.gain[att] = -1.0f64
    }
}

fn cb_reasonable(c: *Cb) -> bool {
    var k = 0i64
    var v = 1usize
    while v <= 3usize {
        if c.brfreq[v] >= f64(MINSPLIT) { k += 1i64 }
        v += 1usize
    }
    ret k >= 2i64
}

fn cb_eval_binary(c: *Cb, node: usize, att: usize, fp: i64, lp: i64) {
    cb_clear_br(c)
    var i = fp
    while i <= lp {
        let r = c.ord[ux(i)]
        let v = usize(c.dat[r * c.w + att])
        let cvv = c.resid[r]
        c.brfreq[v] += 1.0f64
        c.brsum[v] += cvv
        c.brsumsq[v] += cvv * cvv
        i += 1i64
    }
    if cb_reasonable(c) {
        c.gain[att] = r32(cb_compute_gain(c, node))
    } else {
        c.gain[att] = -1.0f64
    }
}

fn cb_eval_subset(c: *Cb, node: usize, att: usize, fp: i64, lp: i64) {
    let mw = c.mw
    let mv = c.maxv[att]
    var v = 1usize
    while v <= mv {
        c.valfreq[v] = 0.0f64
        c.valsum[v] = 0.0f64
        c.valsumsq[v] = 0.0f64
        v += 1usize
    }
    var i = fp
    while i <= lp {
        let r = c.ord[ux(i)]
        let vv = usize(c.dat[r * c.w + att])
        let cvv = c.resid[r]
        c.valfreq[vv] += 1.0f64
        c.valsum[vv] += cvv
        c.valsumsq[vv] += cvv * cvv
        i += 1i64
    }
    c.brfreq[1usize] = c.valfreq[1usize]
    c.brsum[1usize] = c.valsum[1usize]
    c.brsumsq[1usize] = c.valsumsq[1usize]
    let b1 = (att * 4usize + 1usize) * mw
    let b2 = (att * 4usize + 2usize) * mw
    let b3 = (att * 4usize + 3usize) * mw
    var k = 0usize
    while k < mw {
        c.gsub[b1 + k] = false
        k += 1usize
    }
    c.gsub[b1 + 1usize] = true
    v = 2usize
    while v <= 3usize {
        c.brfreq[v] = 0.0f64
        c.brsum[v] = 0.0f64
        c.brsumsq[v] = 0.0f64
        v += 1usize
    }
    v = 2usize
    while v <= mv {
        c.brfreq[2usize] += c.valfreq[v]
        c.brsum[2usize] += c.valsum[v]
        c.brsumsq[2usize] += c.valsumsq[v]
        v += 1usize
    }
    v = 2usize
    while v <= mv {
        c.left[v] = c.valfreq[v] > 0.0f64
        v += 1usize
    }
    var cycle = 2usize
    while cycle <= mv {
        var sv = 0usize
        if c.ordr[att] {
            sv = mv
            while sv > 1usize && !c.left[sv] { sv -= 1usize }
        } else {
            sv = 0usize
            v = 2usize
            while v <= mv {
                if c.left[v] && (sv == 0usize || c.valsum[v] / c.valfreq[v] > c.valsum[sv] / c.valfreq[sv]) { sv = v }
                v += 1usize
            }
        }
        if sv < 2usize { break }
        c.left[sv] = false
        c.brfreq[2usize] -= c.valfreq[sv]
        c.brsum[2usize] -= c.valsum[sv]
        c.brsumsq[2usize] -= c.valsumsq[sv]
        c.brfreq[3usize] += c.valfreq[sv]
        c.brsum[3usize] += c.valsum[sv]
        c.brsumsq[3usize] += c.valsumsq[sv]
        var thisgain = -1.0f64
        if cb_reasonable(c) { thisgain = cb_compute_gain(c, node) }
        if thisgain > c.gain[att] {
            c.gain[att] = r32(thisgain)
            k = 0usize
            while k < mw {
                c.gsub[b2 + k] = false
                c.gsub[b3 + k] = false
                k += 1usize
            }
            v = 2usize
            while v <= mv {
                if c.valfreq[v] > 0.0f64 {
                    if c.left[v] { c.gsub[b2 + v] = true } else { c.gsub[b3 + v] = true }
                }
                v += 1usize
            }
        }
        cycle += 1usize
    }
}

fn cb_eval_discrete(c: *Cb, node: usize, att: usize, fp: i64, lp: i64) {
    if c.maxv[att] == 3usize {
        cb_eval_binary(c, node, att, fp, lp)
    } else {
        cb_eval_subset(c, node, att, fp, lp)
    }
}

fn cb_discrete_test(c: *Cb, node: usize, att: usize) {
    c.nt_forks[node] = 3usize
    c.nt_tested[node] = att
    if c.maxv[att] == 3usize {
        c.nt_type[node] = BR_DISCR
    } else {
        c.nt_type[node] = BR_SUBSET
        let mw = c.mw
        var s = 1usize
        while s <= 3usize {
            var k = 0usize
            while k < mw {
                c.nt_sub[(node * 4usize + s) * mw + k] = c.gsub[(att * 4usize + s) * mw + k]
                k += 1usize
            }
            s += 1usize
        }
    }
}

fn cb_contin_test(c: *Cb, node: usize, att: usize, cut: f64) {
    c.nt_forks[node] = 3usize
    c.nt_type[node] = BR_THRESH
    c.nt_tested[node] = att
    c.nt_cut[node] = cut
}

// ---- the model tree (FormTree, Group, AddModels)

fn cb_group(c: *Cb, v: usize, fp0: i64, lp: i64, node: usize) -> i64 {
    var fp = fp0
    let att = c.nt_tested[node]
    let ty = c.nt_type[node]
    let mw = c.mw
    var i = fp
    while i <= lp {
        var yes = false
        let x = cv(c, i, att)
        if ty == BR_DISCR {
            yes = x == f64(v)
        } else if ty == BR_THRESH {
            if v != 1usize { yes = (x <= c.nt_cut[node]) == (v == 2usize) }
        } else {
            yes = c.nt_sub[(node * 4usize + v) * mw + usize(x)]
        }
        if yes {
            cb_swap(c, fp, i)
            fp += 1i64
        }
        i += 1i64
    }
    ret fp - 1i64
}

fn cb_form_tree(c: *Cb, fp: i64, lp: i64, level: i64, parent: i64) -> usize {
    let w = c.w
    let root = lp - fp >= i64(c.n) - 1i64
    var at = 1usize
    if !root {
        while at <= c.na {
            c.donotuse[at] = true
            at += 1usize
        }
        var p = parent
        while p >= 0i64 {
            c.donotuse[c.nt_tested[ux(p)]] = false
            p = c.nt_parent[ux(p)]
        }
        cb_regress(c, fp, lp, c.localmodel)
        cb_find_model_atts(c, c.localmodel)
    } else {
        at = 0usize
        while at <= c.na {
            c.localmodel[at] = 0.0f64
            at += 1usize
        }
        c.nmodelatt = 0i64
    }
    var maxresid = 0.0f64
    var cases = 0.0f64
    var rawsum = 0.0f64
    var sum = 0.0f64
    var sumsq = 0.0f64
    var i = fp
    while i <= lp {
        let r = c.ord[ux(i)]
        var val = c.cls[r]
        if !root { val = r32(c.cls[r] - cb_lin(c, c.localmodel, r)) }
        c.resid[r] = val
        cases += 1.0f64
        rawsum += c.cls[r]
        sum += val
        sumsq += val * val
        let av = cb_fabs(val)
        if av > maxresid { maxresid = av }
        i += 1i64
    }
    let node = cb_leaf(c, lp - fp + 1i64, rawsum / cases, cb_sd(c, cases, sum, sumsq))
    if root {
        c.nt_model[node * w] = c.nt_mean[node]
    } else {
        at = 0usize
        while at <= c.na {
            c.nt_model[node * w + at] = c.localmodel[at]
            at += 1usize
        }
    }
    if maxresid < 0.5f64 * c.aunit[0usize] { ret node }
    var bestval = r32(0.0f64 - epsilon())
    var bestatt = 0usize
    var hasbest = false
    at = 1usize
    while at <= c.na {
        c.gain[at] = -1.0f64
        if c.skip[at] || at == 1usize {
            at += 1usize
            continue
        }
        if c.disc[at] {
            if root || c.maxv[at] > 3usize || c.donotuse[at] { cb_eval_discrete(c, node, at, fp, lp) }
        } else {
            cb_eval_continuous(c, node, at, fp, lp)
        }
        let val = c.gain[at]
        if val > 0.0f64 - epsilon() {
            if val > bestval || (hasbest && val > 0.999f64 * bestval && c.apref[at] > c.apref[bestatt]) {
                bestatt = at
                bestval = val
                hasbest = true
            }
        }
        at += 1usize
    }
    if hasbest {
        if c.disc[bestatt] {
            cb_discrete_test(c, node, bestatt)
        } else {
            cb_contin_test(c, node, bestatt, c.bar[bestatt])
        }
        c.nt_parent[node] = parent
        var v = 1usize
        var f = fp
        while v <= 3usize {
            let ep = cb_group(c, v, f, lp, node)
            if f <= ep {
                let ch = cb_form_tree(c, f, ep, level + 1i64, i64(node))
                c.nt_br[node * 4usize + v] = i64(ch)
                f = ep + 1i64
            } else {
                let ch = cb_leaf(c, 0i64, c.nt_mean[node], c.nt_sd[node])
                c.nt_br[node * 4usize + v] = i64(ch)
            }
            v += 1usize
        }
    }
    ret node
}

fn cb_add_split_atts(c: *Cb, t: usize) {
    if c.nt_type[t] != 0usize {
        if !c.disc[c.nt_tested[t]] { c.donotuse[c.nt_tested[t]] = false }
        var v = 1usize
        while v <= c.nt_forks[t] {
            cb_add_split_atts(c, usize(c.nt_br[t * 4usize + v]))
            v += 1usize
        }
    }
}

fn cb_add_models(c: *Cb, fp: i64, lp: i64, t: usize, parent: i64) {
    if c.nt_cases[t] == 0i64 { ret }
    let w = c.w
    if c.nt_type[t] != 0usize {
        var bp = fp
        var v = 1usize
        while v <= c.nt_forks[t] {
            let b = usize(c.nt_br[t * 4usize + v])
            if c.nt_cases[b] > 0i64 {
                let ep = bp + c.nt_cases[b] - 1i64
                cb_add_models(c, bp, ep, b, i64(t))
                bp = ep + 1i64
            }
            v += 1usize
        }
    }
    var at = 1usize
    while at <= c.na {
        c.donotuse[at] = true
        at += 1usize
    }
    var p = parent
    while p >= 0i64 {
        let pa = c.nt_tested[ux(p)]
        if !c.disc[pa] { c.donotuse[pa] = false }
        p = c.nt_parent[ux(p)]
    }
    cb_add_split_atts(c, t)
    cb_regress(c, fp, lp, c.nt_model[t * w..(t + 1usize) * w])
}

// ---- pruning and smoothing (prunetree.c)

fn cb_count_coeffs(c: *Cb, model: []const f64) -> i64 {
    var k = 1i64
    var at = 1usize
    while at <= c.na {
        if cb_fabs(model[at]) > 0.0f64 { k += 1i64 }
        at += 1usize
    }
    ret k
}

fn cb_unsprout(c: *Cb, t: usize) {
    c.nt_type[t] = 0usize
}

fn cb_set_props(c: *Cb, t: usize, parent: i64) {
    let w = c.w
    if c.nt_type[t] != 0usize {
        let b2 = usize(c.nt_br[t * 4usize + 2usize])
        let b3 = usize(c.nt_br[t * 4usize + 3usize])
        if c.nt_cases[b2] < c.minitems || c.nt_cases[b3] < c.minitems { cb_unsprout(c, t) }
    }
    let nc = f64(cb_count_coeffs(c, c.nt_model[t * w..(t + 1usize) * w]))
    if c.nt_coeffs[t] != 0.0f64 {
        c.nt_coeffs[t] = r32(0.5f64 * (c.nt_coeffs[t] + nc))
    } else {
        c.nt_coeffs[t] = r32(nc)
    }
    if c.nt_type[t] != 0usize {
        c.nt_parent[t] = parent
        var q = 0usize
        while q <= c.na {
            c.nt_mcopy[t * w + q] = c.nt_model[t * w + q]
            q += 1usize
        }
        if c.disc[c.nt_tested[t]] {
            if c.nt_type[t] == BR_SUBSET { c.nt_params[t] = 4.0f64 } else { c.nt_params[t] = 3.0f64 }
        } else {
            c.nt_params[t] = 4.0f64
        }
        var v = 1usize
        while v <= c.nt_forks[t] {
            let b = usize(c.nt_br[t * 4usize + v])
            if c.nt_cases[b] > 0i64 {
                cb_set_props(c, b, i64(t))
                c.nt_params[t] = r32(c.nt_params[t] + c.nt_params[b])
            }
            v += 1usize
        }
    } else {
        c.nt_params[t] = c.nt_coeffs[t]
    }
}

fn cb_err_var(c: *Cb, model: []const f64, fp: i64, lp: i64, eo: []f64) -> f64 {
    cb_find_model_atts(c, model)
    var sumwt = 0.0f64
    var sum = 0.0f64
    var sumsq = 0.0f64
    var i = fp
    while i <= lp {
        let r = c.ord[ux(i)]
        let v = r32(c.cls[r] - cb_lin(c, model, r))
        eo[ux(i)] = v
        sumwt += 1.0f64
        sum += v
        sumsq += v * v
        i += 1i64
    }
    if sumwt <= 1.0f64 { ret 1.0e-38f64 }
    let vr = (sumsq - sum * sum / sumwt) / (sumwt - 1.0f64)
    if vr > 1.0e-38f64 { ret vr }
    ret 1.0e-38f64
}

fn cb_median_resid(c: *Cb, fp0: i64, lp0: i64, want0: f64) -> f64 {
    var fp = fp0
    var lp = lp0
    var want = want0
    while fp < lp {
        let thresh = c.gresid[ux((fp + lp) / 2i64)]
        var lowwt = 0.0f64
        var midwt = 0.0f64
        var middle = fp
        while c.gresid[ux(middle)] < thresh {
            lowwt += c.presid[ux(middle)]
            middle += 1i64
        }
        var high = lp
        while c.gresid[ux(high)] > thresh { high -= 1i64 }
        var i = middle
        while i <= high {
            let val = c.gresid[ux(i)]
            if val < thresh {
                lowwt += c.presid[ux(i)]
                let h1 = c.gresid[ux(i)]
                c.gresid[ux(i)] = c.gresid[ux(middle)]
                c.gresid[ux(middle)] = h1
                let h2 = c.presid[ux(i)]
                c.presid[ux(i)] = c.presid[ux(middle)]
                c.presid[ux(middle)] = h2
                middle += 1i64
                i += 1i64
            } else if val > thresh {
                let h1 = c.gresid[ux(i)]
                c.gresid[ux(i)] = c.gresid[ux(high)]
                c.gresid[ux(high)] = h1
                let h2 = c.presid[ux(i)]
                c.presid[ux(i)] = c.presid[ux(high)]
                c.presid[ux(high)] = h2
                high -= 1i64
            } else {
                midwt += c.presid[ux(i)]
                i += 1i64
            }
        }
        if want <= lowwt {
            lp = middle - 1i64
        } else if want > lowwt + midwt {
            want -= lowwt + midwt
            fp = high + 1i64
        } else {
            ret thresh
        }
    }
    ret c.gresid[ux(fp)]
}

fn cb_smooth(c: *Cb, t: usize, parent: i64, fp: i64, lp: i64) {
    let w = c.w
    if c.nt_type[t] != 0usize {
        var bp = fp
        var v = 1usize
        while v <= c.nt_forks[t] {
            let b = usize(c.nt_br[t * 4usize + v])
            let cs = c.nt_cases[b]
            if cs > 0i64 {
                cb_smooth(c, b, i64(t), bp, bp + cs - 1i64)
                bp += cs
            }
            v += 1usize
        }
    }
    let sumwt = f64(lp - fp + 1i64)
    let model = c.nt_model[t * w..(t + 1usize) * w]
    var currvar = cb_err_var(c, model, fp, lp, c.gresid)
    if sumwt > 2.0f64 && currvar > 1.0e-10f64 {
        var p = parent
        while p >= 0i64 {
            let pm = c.nt_mcopy[ux(p) * w..(ux(p) + 1usize) * w]
            let parentvar = cb_err_var(c, pm, fp, lp, c.presid)
            var sumx = 0.0f64
            var sumy = 0.0f64
            var sumxy = 0.0f64
            var i = fp
            while i <= lp {
                sumx += c.gresid[ux(i)]
                sumy += c.presid[ux(i)]
                sumxy += c.gresid[ux(i)] * c.presid[ux(i)]
                i += 1i64
            }
            let cov = (sumxy - sumx * sumy / sumwt) / (sumwt - 1.0f64)
            var pcurr = 1.0f64
            if !(currvar + parentvar - 2.0f64 * cov <= 1.0e-12f64) {
                pcurr = (parentvar - cov) / (currvar + parentvar - 2.0f64 * cov)
            }
            if pcurr > 0.0f64 && pcurr < 1.0f64 {
                var q = 0usize
                while q <= c.na {
                    model[q] = model[q] * pcurr + pm[q] * (1.0f64 - pcurr)
                    q += 1usize
                }
                currvar = cb_err_var(c, model, fp, lp, c.gresid)
            }
            p = c.nt_parent[ux(p)]
        }
    }
    var at = 1usize
    while at <= c.na {
        if model[at] != 0.0f64 {
            let mincoeff = 0.01f64 * c.gsd / c.asd[at]
            if cb_fabs(model[at]) < mincoeff {
                model[at] = 0.0f64
            } else {
                model[at] = cb_rint(model[at] / c.aunit[at]) * c.aunit[at]
            }
        }
        at += 1usize
    }
    cb_find_model_atts(c, model)
    var i = fp
    while i <= lp {
        let r = c.ord[ux(i)]
        c.gresid[ux(i)] = r32(cb_raw_lin(c, model, r) - c.cls[r])
        c.presid[ux(i)] = 1.0f64
        i += 1i64
    }
    model[0usize] -= cb_median_resid(c, fp, lp, sumwt / 2.0f64)
    model[0usize] = cb_rint(model[0usize] / c.aunit[0usize]) * c.aunit[0usize]
}

fn cb_find_errors(c: *Cb, t: usize, fp: i64, lp: i64) {
    let w = c.w
    let model = c.nt_model[t * w..(t + 1usize) * w]
    cb_find_model_atts(c, model)
    var esum = 0.0f64
    var i = fp
    while i <= lp {
        let r = c.ord[ux(i)]
        esum += cb_fabs(r32(c.cls[r] - cb_raw_lin(c, model, r)))
        i += 1i64
    }
    c.nt_leaferr[t] = r32(esum)
    c.nt_treeerr[t] = r32(esum)
    c.nt_util[t] = r32(1.0e38f64)
    if c.nt_type[t] == 0usize { ret }
    c.nt_treeerr[t] = 0.0f64
    var minextra = 1.0e38f64
    var bp = fp
    var v = 1usize
    while v <= c.nt_forks[t] {
        let b = usize(c.nt_br[t * 4usize + v])
        let cs = c.nt_cases[b]
        if cs > 0i64 {
            cb_find_errors(c, b, bp, bp + cs - 1i64)
            c.nt_treeerr[t] = r32(c.nt_treeerr[t] + c.nt_treeerr[b])
            if c.nt_type[b] != 0usize && c.nt_util[b] < minextra { minextra = c.nt_util[b] }
            bp += cs
        }
        v += 1usize
    }
    c.nt_util[t] = r32(cb_min(minextra, r32(c.nt_leaferr[t] - c.nt_treeerr[t])))
}

fn cb_find_weakest(c: *Cb, t: usize) -> bool {
    if c.nt_type[t] == 0usize { ret false }
    var found = false
    let nf = f64(c.n)
    let thisextra = r32(c.nt_leaferr[t] - c.nt_treeerr[t])
    let thisxp = r32(c.nt_coeffs[t] - c.nt_params[t])
    let thisadj = nf * cb_estimate_err((thisextra + c.totalerr) / nf, nf, thisxp + c.totalparams)
    if thisadj <= c.adjerrlim && thisextra < c.extraerr {
        c.weakest = i64(t)
        c.extraerr = thisextra
        c.extraparams = thisxp
        c.newadjerr = thisadj
        found = true
    }
    var v = 1usize
    while v <= c.nt_forks[t] {
        let b = usize(c.nt_br[t * 4usize + v])
        if c.nt_util[b] <= c.extraerr {
            if cb_find_weakest(c, b) { found = true }
        }
        v += 1usize
    }
    ret found
}

fn cb_unsprout_update(c: *Cb, pruned: usize, extraerr: f64, extraparams: f64) {
    var minextra = 1.0e38f64
    c.nt_util[pruned] = r32(1.0e38f64)
    var t = i64(pruned)
    while t >= 0i64 {
        let u = ux(t)
        c.nt_treeerr[u] = r32(c.nt_treeerr[u] + extraerr)
        c.nt_params[u] = r32(c.nt_params[u] + extraparams)
        if u != pruned {
            var v = 1usize
            while v <= c.nt_forks[u] {
                let b = usize(c.nt_br[u * 4usize + v])
                if c.nt_util[b] < minextra { minextra = c.nt_util[b] }
                v += 1usize
            }
            c.nt_util[u] = r32(cb_min(minextra, r32(c.nt_leaferr[u] - c.nt_treeerr[u])))
        }
        t = c.nt_parent[u]
    }
    cb_unsprout(c, pruned)
}

fn cb_prune(c: *Cb, t: usize) {
    cb_set_props(c, t, -1i64)
    cb_smooth(c, t, -1i64, 0i64, i64(c.n) - 1i64)
    cb_find_errors(c, t, 0i64, i64(c.n) - 1i64)
    var leaves = cb_tree_leaves(c, t)
    var stage = 1i64
    let nf = f64(c.n)
    while true {
        c.totalparams = c.nt_params[t]
        c.totalerr = c.nt_treeerr[t]
        let adj = nf * cb_estimate_err(c.totalerr / nf, nf, c.totalparams)
        if stage == 1i64 { c.adjerrlim = adj }
        c.extraerr = 1.0e38f64
        let found = cb_find_weakest(c, t)
        if found && (c.newadjerr <= adj || stage > 1i64) {
            leaves -= cb_tree_leaves(c, usize(c.weakest)) - 1i64
            cb_unsprout_update(c, usize(c.weakest), c.extraerr, c.extraparams)
        } else if stage == 1i64 {
            stage = 2i64
            c.adjerrlim = adj * 1.005f64
        } else {
            stage = 3i64
            c.adjerrlim = 1.0e38f64
        }
        if stage == 3i64 && leaves <= c.maxrules { break }
    }
}

// ---- thresholds that appear in the data (AdjustAllThresholds)

fn cb_uses_thr(c: *Cb, t: usize, at: usize) -> bool {
    if c.nt_type[t] == BR_THRESH && c.nt_tested[t] == at { ret true }
    if c.nt_type[t] != 0usize {
        var v = 1usize
        while v <= c.nt_forks[t] {
            if cb_uses_thr(c, usize(c.nt_br[t * 4usize + v]), at) { ret true }
            v += 1usize
        }
    }
    ret false
}

fn cb_greatest_below(c: *Cb, th: f64) -> f64 {
    var low = 0i64
    var high = i64(c.n) - 1i64
    while low < high {
        let mid = (low + high + 1i64) / 2i64
        if c.sv[ux(mid)] > th {
            high = mid - 1i64
        } else {
            low = mid
        }
    }
    ret c.sv[ux(low)]
}

fn cb_adjust_rec(c: *Cb, t: usize, at: usize) {
    if c.nt_type[t] == BR_THRESH && c.nt_tested[t] == at {
        c.nt_cut[t] = cb_greatest_below(c, c.nt_cut[t])
    }
    if c.nt_type[t] != 0usize {
        var v = 1usize
        while v <= c.nt_forks[t] {
            cb_adjust_rec(c, usize(c.nt_br[t * 4usize + v]), at)
            v += 1usize
        }
    }
}

fn cb_adjust_all(c: *Cb, t: usize) {
    var at = 1usize
    while at <= c.na {
        if !c.disc[at] && cb_uses_thr(c, t, at) {
            var i = 0i64
            while i < i64(c.n) {
                c.sv[ux(i)] = cv(c, i, at)
                i += 1i64
            }
            cb_cachesort(c, 0i64, i64(c.n) - 1i64)
            cb_adjust_rec(c, t, at)
        }
        at += 1usize
    }
}

// ---- rules: satisfying a condition, predicting from a rule set (rules.c, predict.c)

fn cb_rule_matches(c: *Cb, r: *const Rule, buf: []const f64, off: usize) -> bool {
    var d = 0usize
    while d < r.size {
        let cd = &r.lhs[d]
        let x = buf[off + cd.att]
        if cd.ty == BR_DISCR {
            if x != f64(cd.tv) { ret false }
        } else if cd.ty == BR_THRESH {
            var o = 3i64
            if x <= cd.cut { o = 2i64 }
            if o != cd.tv { ret false }
        } else {
            let v = usize(x)
            if !(v < cd.sub.len && v <= c.maxv[cd.att] && cd.sub[v]) { ret false }
        }
        d += 1usize
    }
    ret true
}

fn cb_ruleset_pred(c: *Cb, rs: *const RSet, buf: []const f64, off: usize) -> f64 {
    var sum = 0.0f64
    var weight = 0.0f64
    var k = 0usize
    while k < rs.nr {
        let r = &rs.rules[k]
        if cb_rule_matches(c, r, buf, off) {
            var val = r.rhs[0usize]
            var at = 1usize
            while at <= c.na {
                val += buf[off + at] * r.rhs[at]
                at += 1usize
            }
            if val < r.lolim {
                sum += r.lolim
            } else if val > r.hilim {
                sum += r.hilim
            } else {
                sum += val
            }
            weight += 1.0f64
        }
        k += 1usize
    }
    if weight != 0.0f64 { ret r32(sum / weight) }
    ret c.gmean
}

fn cb_predict_value(c: *Cb, buf: []const f64, off: usize) -> f64 {
    var sum = 0.0f64
    var m = 0usize
    while m < c.members {
        sum += cb_ruleset_pred(c, &c.cttee[m], buf, off)
        m += 1usize
    }
    ret r32(sum / f64(c.members))
}

// ---- forming rules from the pruned tree (formrules.c)

type FR = struct {
    t: usize, ncond: i64, bestd: i64,
    total: []f64, prederr: []f64, deleted: []bool,
    st_ty: []usize, st_att: []usize, st_cut: []f64, st_tv: []i64, st_sub: []bool,
    cfb: []bool, nfail: []i64, lfail: []i64, succ: []i64,
    fail0: i64, fail1: i64, failmany: i64
}

fn cb_tree_depth(c: *Cb, t: usize, d: usize) -> usize {
    if c.nt_type[t] == 0usize { ret d }
    var m = d
    var v = 1usize
    while v <= c.nt_forks[t] {
        let k = cb_tree_depth(c, usize(c.nt_br[t * 4usize + v]), d + 1usize)
        if k > m { m = k }
        v += 1usize
    }
    ret m
}

// the value a tree predicts for a case (TreeValue)
fn cb_tree_value(c: *Cb, t: usize, row: usize) -> f64 {
    let w = c.w
    let ty = c.nt_type[t]
    let att = c.nt_tested[t]
    let x = c.dat[row * w + att]
    if ty == BR_DISCR {
        let v = usize(x)
        if v != 0usize && v <= c.nt_forks[t] {
            let b = usize(c.nt_br[t * 4usize + v])
            if c.nt_cases[b] >= 1i64 { ret cb_tree_value(c, b, row) }
        }
    } else if ty == BR_THRESH {
        var v = 3usize
        if x <= c.nt_cut[t] { v = 2usize }
        ret cb_tree_value(c, usize(c.nt_br[t * 4usize + v]), row)
    } else if ty == BR_SUBSET {
        let v = usize(x)
        var f = 3usize
        if v == 1usize {
            f = 1usize
        } else if c.nt_sub[(t * 4usize + 2usize) * c.mw + v] {
            f = 2usize
        }
        ret cb_tree_value(c, usize(c.nt_br[t * 4usize + f]), row)
    }
    var val = c.nt_model[t * w]
    var at = 1usize
    while at <= c.na {
        val += c.dat[row * w + at] * c.nt_model[t * w + at]
        at += 1usize
    }
    if val < c.flo { ret r32(c.flo) }
    if val > c.ceil { ret r32(c.ceil) }
    ret r32(val)
}

fn cb_satisfies_st(c: *Cb, f: *FR, d: usize, row: usize) -> bool {
    let x = c.dat[row * c.w + f.st_att[d]]
    let ty = f.st_ty[d]
    if ty == BR_DISCR { ret x == f64(f.st_tv[d]) }
    if ty == BR_THRESH {
        var o = 3i64
        if x <= f.st_cut[d] { o = 2i64 }
        ret o == f.st_tv[d]
    }
    ret f.st_sub[d * c.mw + usize(x)]
}

fn cb_push_cond(c: *Cb, f: *FR) {
    let d = ux(f.ncond)
    let n = c.n
    var i = 0usize
    while i < n {
        let failed = !cb_satisfies_st(c, f, d, c.ord[i])
        f.cfb[d * n + i] = failed
        if failed { f.nfail[i] += 1i64 }
        i += 1usize
    }
}

fn cb_pop_cond(c: *Cb, f: *FR) {
    let d = ux(f.ncond)
    let n = c.n
    var i = 0usize
    while i < n {
        if f.cfb[d * n + i] { f.nfail[i] -= 1i64 }
        i += 1usize
    }
}

fn cb_update_count(c: *Cb, f: *FR, d: usize, i: usize, model: []const f64) {
    let row = c.ord[i]
    let val = c.cls[row]
    f.total[d] += 1.0f64
    let raw = cb_raw_lin(c, model, row)
    c.cpred[i] = raw
    var mv = raw
    if mv < c.flo {
        mv = c.flo
    } else if mv > c.ceil {
        mv = c.ceil
    }
    if d != 0usize {
        let oldp = r32(c.resid[row] / f64(c.pcnt[row]))
        let newp = r32(r32(c.resid[row] + mv) / f64(c.pcnt[row] + 1i64))
        f.prederr[d] += cb_fabs(r32(val - oldp)) - cb_fabs(r32(val - newp))
    } else {
        f.prederr[0usize] += cb_fabs(r32(val - mv))
    }
}

fn cb_single_fail(c: *Cb, f: *FR, i: usize) -> usize {
    var d = 1usize
    while d <= ux(f.ncond) {
        if !f.deleted[d] && f.cfb[d * c.n + i] { ret d }
        d += 1usize
    }
    ret 0usize
}

fn cb_process_lists(c: *Cb, f: *FR, model: []const f64) {
    let n = c.n
    if f.bestd == 0i64 {
        f.fail0 = -1i64
        f.fail1 = -1i64
        f.failmany = -1i64
        var d = 0usize
        while d <= ux(f.ncond) {
            f.total[d] = 0.0f64
            f.prederr[d] = 0.0f64
            d += 1usize
        }
        var i = 0usize
        while i < n {
            if f.lfail[i] == 0i64 {
                cb_update_count(c, f, 0usize, i, model)
                f.succ[i] = f.fail0
                f.fail0 = i64(i)
            } else if f.lfail[i] == 1i64 {
                let dd = cb_single_fail(c, f, i)
                cb_update_count(c, f, dd, i, model)
                f.succ[i] = f.fail1
                f.fail1 = i64(i)
            } else {
                f.succ[i] = f.failmany
                f.failmany = i64(i)
            }
            i += 1usize
        }
    } else {
        let bd = ux(f.bestd)
        var prev = -1i64
        var i = f.fail1
        while i >= 0i64 {
            let ui = ux(i)
            let inext = f.succ[ui]
            if f.cfb[bd * n + ui] {
                f.lfail[ui] = 0i64
                cb_update_count(c, f, 0usize, ui, model)
                if prev < 0i64 { f.fail1 = f.succ[ui] } else { f.succ[ux(prev)] = f.succ[ui] }
                f.succ[ui] = f.fail0
                f.fail0 = i
            } else {
                prev = i
            }
            i = inext
        }
        prev = -1i64
        i = f.failmany
        while i >= 0i64 {
            let ui = ux(i)
            let inext = f.succ[ui]
            var hit = false
            if f.cfb[bd * n + ui] {
                f.lfail[ui] -= 1i64
                if f.lfail[ui] == 1i64 { hit = true }
            }
            if hit {
                let dd = cb_single_fail(c, f, ui)
                cb_update_count(c, f, dd, ui, model)
                if prev < 0i64 { f.failmany = f.succ[ui] } else { f.succ[ux(prev)] = f.succ[ui] }
                f.succ[ui] = f.fail1
                f.fail1 = i
            } else {
                prev = i
            }
            i = inext
        }
    }
}

fn cb_same_rule(c: *Cb, r: *const Rule, f: *FR, lhs: []const Cond, size: usize) -> bool {
    if r.size != size { ret false }
    var d = 0usize
    while d < size {
        let x = &r.lhs[d]
        let y = &lhs[d]
        if x.ty != y.ty || x.att != y.att { ret false }
        if x.ty == BR_DISCR {
            if x.tv != y.tv { ret false }
        } else if x.ty == BR_THRESH {
            if x.tv != y.tv || x.cut != y.cut { ret false }
        } else {
            var k = 0usize
            while k < c.mw {
                if x.sub[k] != y.sub[k] { ret false }
                k += 1usize
            }
        }
        d += 1usize
    }
    ret true
}

fn cb_remove_bias(c: *Cb, f: *FR, r: *Rule, coeffs: i64) {
    var toterr = 0.0f64
    var totwt = 0.0f64
    var totabs = -1.0f64
    var i = f.fail0
    while i >= 0i64 {
        totwt += 1.0f64
        let ui = ux(i)
        var nw = c.cpred[ui]
        if nw < r.lolim {
            nw = r.lolim
        } else if nw > r.hilim {
            nw = r.hilim
        }
        toterr += nw - c.cls[c.ord[ui]]
        i = f.succ[ui]
    }
    var bias = toterr / totwt
    while cb_fabs(bias) >= 0.5f64 * c.aunit[0usize] {
        let lastbias = bias
        r.rhs[0usize] -= bias
        toterr = 0.0f64
        totabs = 0.0f64
        i = f.fail0
        while i >= 0i64 {
            let ui = ux(i)
            c.cpred[ui] = r32(c.cpred[ui] - bias)
            var nw = c.cpred[ui]
            if nw < r.lolim {
                nw = r.lolim
            } else if nw > r.hilim {
                nw = r.hilim
            }
            toterr += nw - c.cls[c.ord[ui]]
            totabs += cb_fabs(nw - c.cls[c.ord[ui]])
            i = f.succ[ui]
        }
        bias = toterr / totwt
        if cb_fabs(bias) >= cb_fabs(lastbias) { break }
    }
    if totabs >= 0.0f64 {
        r.rhs[0usize] = cb_rint(r.rhs[0usize] / c.aunit[0usize]) * c.aunit[0usize]
        r.esterr = r32(cb_estimate_err(totabs / totwt, f64(r.cover), f64(coeffs)))
    }
}

fn cb_prune_rule(a: *mem.Arena, c: *Cb, f: *FR, t: usize) {
    let w = c.w
    let mw = c.mw
    let model = c.nt_model[t * w..(t + 1usize) * w]
    cb_find_model_atts(c, model)
    f.bestd = 0i64
    var remaining = f.ncond
    var d = 0usize
    while d <= ux(f.ncond) {
        f.deleted[d] = false
        d += 1usize
    }
    while true {
        cb_process_lists(c, f, model)
        if remaining == 1i64 { break }
        f.bestd = 0i64
        d = 0usize
        while d <= ux(f.ncond) {
            if !f.deleted[d] && d > 0usize {
                if f.prederr[d] >= 0.0f64 && (f.bestd == 0i64 || f.prederr[d] > f.prederr[ux(f.bestd)]) { f.bestd = i64(d) }
            }
            d += 1usize
        }
        if f.bestd == 0i64 { break }
        f.deleted[ux(f.bestd)] = true
        remaining -= 1i64
    }
    var cover = 0i64
    var lov = r32(1.0e38f64)
    var hiv = r32(-1.0e38f64)
    var sum = 0.0f64
    var sumwt = 0.0f64
    var i = f.fail0
    while i >= 0i64 {
        let ui = ux(i)
        cover += 1i64
        sumwt += 1.0f64
        let val = c.cls[c.ord[ui]]
        sum += val
        if val < lov { lov = val }
        if val > hiv { hiv = val }
        i = f.succ[ui]
    }
    let initcoeffs = c.nt_coeffs[t]
    f.prederr[0usize] = cb_estimate_err(f.prederr[0usize] / f.total[0usize], f64(cover), initcoeffs)
    let mean = r32(sum / sumwt)
    let esterr = r32(f.prederr[0usize])
    // NewRule: keep the conditions not deleted, most used first
    var size = 0usize
    d = 1usize
    while d <= ux(f.ncond) {
        if !f.deleted[d] { size += 1usize }
        d += 1usize
    }
    let (lhs, e1) = mem.alloc[Cond](a, size + 1usize)
    if e1 != ok {
        c.bad = true
        ret
    }
    var k = 0usize
    while k < size {
        var dd = 0usize
        var id = 1usize
        while id <= ux(f.ncond) {
            if !f.deleted[id] && (dd == 0usize || f.total[id] > f.total[dd]) { dd = id }
            id += 1usize
        }
        let (sb, e2) = cb_zb(a, mw)
        if e2 != ok {
            c.bad = true
            ret
        }
        if f.st_ty[dd] == BR_SUBSET {
            var q = 0usize
            while q < mw {
                sb[q] = f.st_sub[dd * mw + q]
                q += 1usize
            }
        }
        lhs[k] = Cond { ty: f.st_ty[dd], att: f.st_att[dd], cut: f.st_cut[dd], tv: f.st_tv[dd], sub: sb }
        f.deleted[dd] = true
        k += 1usize
    }
    var dup = false
    var rr = 0usize
    while !dup && rr < c.nrb {
        if cb_same_rule(c, &c.rb[rr], f, lhs[0usize..size], size) {
            dup = true
            if esterr < c.rb[rr].esterr {
                var q = 0usize
                while q <= c.na {
                    c.rb[rr].rhs[q] = model[q]
                    q += 1usize
                }
                c.rb[rr].esterr = esterr
            }
        }
        rr += 1usize
    }
    if dup { ret }
    let range = r32(hiv - lov)
    var lolim = r32(lov - r32(c.extrap * range))
    if lolim < 0.0f64 && lov >= 0.0f64 { lolim = 0.0f64 }
    var hilim = r32(hiv + r32(c.extrap * range))
    if hilim > 0.0f64 && hiv <= 0.0f64 { hilim = 0.0f64 }
    let rhs = az(a, c, w)
    if c.bad { ret }
    var q = 0usize
    while q <= c.na {
        rhs[q] = model[q]
        q += 1usize
    }
    c.rb[c.nrb] = Rule { size: size, cover: cover, mean: mean, lo: lov, hi: hiv, lolim: lolim, hilim: hilim, esterr: esterr, lhs: lhs[0usize..size], rhs: rhs }
    c.nrb += 1usize
    i = f.fail0
    while i >= 0i64 {
        let ui = ux(i)
        if f.nfail[ui] != 0i64 {
            let row = c.ord[ui]
            var cp = c.cpred[ui]
            if cp < lov {
                cp = lov
            } else if cp > hiv {
                cp = hiv
            }
            c.resid[row] = r32(c.resid[row] + cp)
            c.pcnt[row] += 1i64
        }
        i = f.succ[ui]
    }
    if c.unbiased { cb_remove_bias(c, f, &c.rb[c.nrb - 1usize], i64(initcoeffs)) }
}

fn cb_scan(a: *mem.Arena, c: *Cb, f: *FR, t: usize) {
    let mw = c.mw
    if c.nt_type[t] != 0usize {
        f.ncond += 1i64
        let d = ux(f.ncond)
        f.st_ty[d] = c.nt_type[t]
        f.st_att[d] = c.nt_tested[t]
        f.st_cut[d] = c.nt_cut[t]
        var v = 1usize
        while v <= c.nt_forks[t] {
            f.st_tv[d] = i64(v)
            if c.nt_type[t] == BR_SUBSET {
                var k = 0usize
                while k < mw {
                    f.st_sub[d * mw + k] = c.nt_sub[(t * 4usize + v) * mw + k]
                    k += 1usize
                }
            }
            cb_push_cond(c, f)
            cb_scan(a, c, f, usize(c.nt_br[t * 4usize + v]))
            cb_pop_cond(c, f)
            v += 1usize
        }
        f.ncond -= 1i64
    } else if c.nt_cases[t] >= 1i64 {
        var i = 0usize
        while i < c.n {
            f.lfail[i] = f.nfail[i]
            i += 1usize
        }
        f.t = t
        cb_prune_rule(a, c, f, t)
    }
}

fn cb_form_rules(a: *mem.Arena, c: *Cb, t: usize) -> RSet {
    let n = c.n
    let mw = c.mw
    var i = 0usize
    while i < n {
        let row = c.ord[i]
        c.resid[row] = cb_tree_value(c, t, row)
        c.pcnt[row] = 1i64
        i += 1usize
    }
    let depth = cb_tree_depth(c, t, 0usize)
    let dd = depth + 2usize
    var f: FR = zero
    f.total = az(a, c, dd)
    f.prederr = az(a, c, dd)
    f.deleted = azb(a, c, dd)
    f.st_ty = azu(a, c, dd)
    f.st_att = azu(a, c, dd)
    f.st_cut = az(a, c, dd)
    f.st_tv = azi(a, c, dd)
    f.st_sub = azb(a, c, dd * mw)
    f.cfb = azb(a, c, dd * n)
    f.nfail = azi(a, c, n)
    f.lfail = azi(a, c, n)
    f.succ = azi(a, c, n)
    let (rb, e1) = mem.alloc[Rule](a, n + 2usize)
    if e1 != ok { c.bad = true }
    var rs: RSet = zero
    if c.bad { ret rs }
    c.rb = rb
    c.nrb = 0usize
    f.ncond = 0i64
    cb_scan(a, c, &f, t)
    // order the rules by mean value
    var r = 0usize
    while r < c.nrb {
        var next = r
        var nr = r + 1usize
        while nr < c.nrb {
            if c.rb[nr].mean < c.rb[next].mean { next = nr }
            nr += 1usize
        }
        if next != r {
            let hold = c.rb[r]
            c.rb[r] = c.rb[next]
            c.rb[next] = hold
        }
        r += 1usize
    }
    rs.nr = c.nrb
    rs.rules = c.rb[0usize..c.nrb]
    ret rs
}

// ---- instance-based correction (instance.c). N/A values never occur here: the package marks every unknown value as missing.

fn cb_cvdiff(c: *Cb, x: f64, y: f64, at: usize) -> f64 {
    ret cb_fabs(r32(x - y)) / r32(5.0f64 * c.asd[at])
}

// Distance(): Manhattan distance, stopping once it passes thresh
fn cb_dist(c: *Cb, ba: []const f64, oa: usize, bb: []const f64, ob: usize, thresh: f64) -> f64 {
    var dtot = 0.0f64
    var at = 1usize
    while dtot < r32(thresh) && at <= c.na {
        if c.skip[at] || at == 1usize {
            at += 1usize
            continue
        }
        if !c.disc[at] {
            let diff = cb_cvdiff(c, bb[ob + at], ba[oa + at], at)
            if 1.0f64 < diff { dtot += 1.0f64 } else { dtot += diff }
        } else if c.ordr[at] {
            var dv = i64(bb[ob + at]) - i64(ba[oa + at])
            if dv < 0i64 { dv = 0i64 - dv }
            dtot += f64(dv / (i64(c.maxv[at]) - 1i64))
        } else if bb[ob + at] != ba[oa + at] {
            dtot += 2.0f64 / f64(i64(c.maxv[at]) - 1i64)
        }
        at += 1usize
    }
    ret r32(dtot)
}

fn ix_swap(c: *Cb, x: i64, y: i64) {
    let t = c.inst[ux(x)]
    c.inst[ux(x)] = c.inst[ux(y)]
    c.inst[ux(y)] = t
}

fn ix_build(c: *Cb, fp0: i64, lp: i64) -> i64 {
    var fp = fp0
    if lp < fp { ret -1i64 }
    let w = c.w
    let node = c.ix_n
    c.ix_n += 1usize
    c.ix_tested[node] = 0usize
    c.ix_fp[node] = 0i64
    c.ix_lp[node] = 0i64
    var bestatt = 0usize
    var bestexp = 0.0f64
    var bestmean = 0.0f64
    if lp > fp {
        let r0 = c.inst[ux(fp)]
        var min0 = c.drf1[r0]
        var max0 = min0
        var min1 = c.drf2[r0]
        var max1 = min1
        var i = fp + 1i64
        while i <= lp {
            let r = c.inst[ux(i)]
            let d1 = c.drf1[r]
            if d1 < min0 {
                min0 = d1
            } else if d1 > max0 {
                max0 = d1
            }
            let d2 = c.drf2[r]
            if d2 < min1 {
                min1 = d2
            } else if d2 > max1 {
                max1 = d2
            }
            i += 1i64
        }
        c.ix_min0[node] = min0
        c.ix_max0[node] = max0
        c.ix_min1[node] = min1
        c.ix_max1[node] = max1
        let cases = lp - fp + 1i64
        var at = 1usize
        while at <= c.na {
            if c.skip[at] || at == 1usize || (c.ix_tst[at] && c.disc[at]) {
                at += 1usize
                continue
            }
            var mean = 0.0f64
            var expd = 0.0f64
            if !c.disc[at] {
                i = fp
                while i <= lp {
                    mean += c.dat[c.inst[ux(i)] * w + at]
                    i += 1i64
                }
                mean = mean / f64(cases)
                i = fp
                while i <= lp {
                    expd += cb_fabs(c.dat[c.inst[ux(i)] * w + at] - mean) / r32(5.0f64 * c.asd[at])
                    i += 1i64
                }
                expd = expd / f64(cases)
            } else {
                var v = 2usize
                while v <= c.maxv[at] {
                    c.ix_vf[v] = 0i64
                    v += 1usize
                }
                i = fp
                while i <= lp {
                    c.ix_vf[usize(c.dat[c.inst[ux(i)] * w + at])] += 1i64
                    i += 1i64
                }
                if c.ordr[at] {
                    v = 2usize
                    while v <= c.maxv[at] {
                        var vv = 2usize
                        while vv <= c.maxv[at] {
                            var dd = i64(vv) - i64(v)
                            if dd < 0i64 { dd = 0i64 - dd }
                            expd += f64(c.ix_vf[v] * c.ix_vf[vv] * dd)
                            vv += 1usize
                        }
                        v += 1usize
                    }
                } else {
                    v = 2usize
                    while v <= c.maxv[at] {
                        expd += f64(c.ix_vf[v] * (cases - c.ix_vf[v])) * 2.0f64
                        v += 1usize
                    }
                }
                expd = expd / f64((i64(c.maxv[at]) - 1i64) * cases * cases)
            }
            if expd > bestexp {
                bestexp = expd
                bestatt = at
                bestmean = mean
            }
            at += 1usize
        }
    }
    if bestatt == 0usize {
        c.ix_tested[node] = 0usize
        c.ix_fp[node] = fp
        c.ix_lp[node] = lp
    } else if c.disc[bestatt] {
        c.ix_tested[node] = bestatt
        c.ix_tst[bestatt] = true
        var kp = fp
        var v = 1usize
        while v <= c.maxv[bestatt] {
            var xp = kp
            while xp <= lp {
                if usize(c.dat[c.inst[ux(xp)] * w + bestatt]) == v {
                    ix_swap(c, xp, kp)
                    kp += 1i64
                }
                xp += 1i64
            }
            let sb = ix_build(c, fp, kp - 1i64)
            c.ix_sub[node * c.ixw + v] = sb
            fp = kp
            v += 1usize
        }
        c.ix_tst[bestatt] = false
    } else {
        c.ix_tested[node] = bestatt
        c.ix_cut[node] = r32(bestmean)
        let xp = fp
        var kp = xp
        var i = xp
        while i <= lp {
            if c.dat[c.inst[ux(i)] * w + bestatt] <= bestmean {
                ix_swap(c, i, kp)
                kp += 1i64
            }
            i += 1i64
        }
        if xp == lp + 1i64 || (xp == fp && kp == lp + 1i64) || kp == fp {
            c.ix_tested[node] = 0usize
            c.ix_fp[node] = fp
            c.ix_lp[node] = lp
        } else {
            let s1 = ix_build(c, fp, xp - 1i64)
            c.ix_sub[node * c.ixw + 1usize] = s1
            let s2 = ix_build(c, xp, kp - 1i64)
            c.ix_sub[node * c.ixw + 2usize] = s2
            let s3 = ix_build(c, kp, lp)
            c.ix_sub[node * c.ixw + 3usize] = s3
        }
    }
    ret i64(node)
}

fn cb_check_dist(c: *Cb, qb: []const f64, qo: usize, saved: usize, selfrow: i64) {
    if i64(c.inst[saved]) == selfrow { ret }
    let thr = r32(c.bestd[c.worst] + 0.55f64 / 16.0f64)
    let dd = cb_dist(c, qb, qo, c.dat, c.inst[saved] * c.w, thr)
    let dist = r32(cb_rint(16.0f64 * dd) / 16.0f64)
    if dist <= c.bestd[c.worst] {
        var d = 0usize
        while d < 20usize && c.bestd[d] < dist { d += 1usize }
        if d < 20usize {
            var dd2 = 19usize
            while dd2 > d {
                c.bestd[dd2] = c.bestd[dd2 - 1usize]
                c.besti[dd2] = c.besti[dd2 - 1usize]
                dd2 -= 1usize
            }
            c.bestd[d] = dist
            c.besti[d] = i64(saved)
        }
    }
}

fn ix_scan(c: *Cb, qb: []const f64, qo: usize, qd1: f64, qd2: f64, selfrow: i64, node: i64, mind: f64) {
    if node < 0i64 { ret }
    let nd = ux(node)
    let at = c.ix_tested[nd]
    if at == 0usize {
        var xp = c.ix_fp[nd]
        while xp <= c.ix_lp[nd] {
            cb_check_dist(c, qb, qo, ux(xp), selfrow)
            xp += 1i64
        }
        ret
    }
    let lim = c.bestd[c.worst] + 0.5f64 / 16.0f64
    let m1 = cb_max(r32(c.ix_min0[nd] - qd1), r32(qd1 - c.ix_max0[nd]))
    let m2 = cb_max(r32(c.ix_min1[nd] - qd2), r32(qd2 - c.ix_max1[nd]))
    if m1 <= lim && m2 <= lim {
        var first = 0usize
        var forks = 0usize
        let x = qb[qo + at]
        if c.disc[at] {
            first = usize(x)
            forks = c.maxv[at]
        } else {
            first = 3usize
            if x <= c.ix_cut[nd] { first = 2usize }
            forks = 3usize
        }
        if first >= 1usize && first <= forks { ix_scan(c, qb, qo, qd1, qd2, selfrow, c.ix_sub[nd * c.ixw + first], mind) }
        let save = c.attmind[at]
        var v = 1usize
        while v <= forks {
            if v == first || c.ix_sub[nd * c.ixw + v] < 0i64 {
                v += 1usize
                continue
            }
            var amd = 0.0f64
            if v == 1usize || first == 1usize {
                amd = 1.0f64
            } else if !c.disc[at] {
                amd = cb_cvdiff(c, x, c.ix_cut[nd], at)
            } else if c.ordr[at] {
                var dv = i64(v) - i64(first)
                if dv < 0i64 { dv = 0i64 - dv }
                amd = f64(dv / (i64(c.maxv[at]) - 1i64))
            } else {
                amd = 2.0f64 / f64(i64(c.maxv[at]) - 1i64)
            }
            c.attmind[at] = r32(amd)
            let newmind = r32(r32(mind + c.attmind[at]) - save)
            if newmind <= c.bestd[c.worst] + 0.5f64 / 16.0f64 {
                ix_scan(c, qb, qo, qd1, qd2, selfrow, c.ix_sub[nd * c.ixw + v], newmind)
            }
            v += 1usize
        }
        c.attmind[at] = save
    }
}

fn cb_find_nn(c: *Cb, qb: []const f64, qo: usize, selfrow: i64) {
    var d = 0usize
    while d < 20usize {
        c.bestd[d] = c.maxd
        c.besti[d] = -1i64
        d += 1usize
    }
    var at = 0usize
    while at <= c.na {
        c.attmind[at] = 0.0f64
        at += 1usize
    }
    let qd1 = cb_dist(c, qb, qo, c.ref0, 0usize, 1.0e38f64)
    let qd2 = cb_dist(c, qb, qo, c.ref1, 0usize, 1.0e38f64)
    ix_scan(c, qb, qo, qd1, qd2, selfrow, c.kdroot, 0.0f64)
}

fn cb_avg_neighbors(c: *Cb, qb: []const f64, qo: usize) -> f64 {
    let base = cb_predict_value(c, qb, qo)
    var last = 19i64
    while last >= 0i64 && c.besti[ux(last)] < 0i64 { last -= 1i64 }
    if last + 1i64 < c.minn { ret base }
    var d = 0i64
    var count = 0i64
    var totsum = 0.0f64
    var totwt = 0.0f64
    while d <= last && count < c.nnk && count < i64(c.n) - 1i64 {
        var samesum = 0.0f64
        var samewt = 0.0f64
        var same = 0i64
        let wt = 1.0f64 / (c.bestd[ux(d)] + 0.5f64)
        var more = true
        while more {
            let ii = ux(c.besti[ux(d)])
            var est = c.cls[c.inst[ii]] + base - c.rspred[ii]
            if est > c.ceil {
                est = c.ceil
            } else if est < c.flo {
                est = c.flo
            }
            samesum += wt * est
            samewt += wt
            same += 1i64
            d += 1i64
            more = d <= last && c.bestd[ux(d)] == c.bestd[ux(d - 1i64)]
        }
        if count + same > c.nnk {
            let wt2 = r32(f64(c.nnk - count) / f64(same))
            totsum += wt2 * samesum
            totwt += wt2 * samewt
            count = c.nnk
        } else {
            totsum += samesum
            totwt += samewt
            count += same
        }
    }
    let est = totsum / totwt
    if est < c.flo { ret c.flo }
    if est > c.ceil { ret c.ceil }
    ret r32(est)
}

fn cb_nn_estimate(c: *Cb, qb: []const f64, qo: usize, selfrow: i64) -> f64 {
    cb_find_nn(c, qb, qo, selfrow)
    ret cb_avg_neighbors(c, qb, qo)
}

// SetParameters(): MAXD is the average distance between random pairs of instances
fn cb_set_maxd(c: *Cb, kr: *Kr, tr: usize, useall: bool) -> f64 {
    var sum = 0.0f64
    let n = c.n
    var t = 0usize
    while t < tr {
        var i = t
        if !useall { i = usize(f64(n) * ((2.0f64 * f64(t) + 1.0f64) / (2.0f64 * f64(tr)))) }
        var j = usize(kr_random(kr) * f64(n))
        while j == i { j = usize(kr_random(kr) * f64(n)) }
        sum += cb_dist(c, c.dat, c.inst[j] * c.w, c.dat, c.inst[i] * c.w, 1.0e10f64)
        t += 1usize
    }
    ret r32(cb_rint(16.0f64 * sum / f64(tr)) / 16.0f64)
}

// InitialiseInstances(): the cases of c are the instances; maxd_in < 0 asks for MAXD to be set from the random stream
fn cb_init_instances(a: *mem.Arena, c: *Cb, kr: *Kr, maxd_in: f64) {
    let n = c.n
    let w = c.w
    c.inst = azu(a, c, n)
    c.drf1 = az(a, c, n)
    c.drf2 = az(a, c, n)
    c.ref0 = az(a, c, w)
    c.ref1 = az(a, c, w)
    c.attmind = az(a, c, w)
    c.rspred = az(a, c, n)
    let cap = (2usize * n + 4usize) * (c.na + 1usize)
    c.ixw = c.mw
    if c.ixw < 4usize { c.ixw = 4usize }
    c.ix_tested = azu(a, c, cap)
    c.ix_cut = az(a, c, cap)
    c.ix_min0 = az(a, c, cap)
    c.ix_max0 = az(a, c, cap)
    c.ix_min1 = az(a, c, cap)
    c.ix_max1 = az(a, c, cap)
    c.ix_fp = azi(a, c, cap)
    c.ix_lp = azi(a, c, cap)
    c.ix_sub = azi(a, c, cap * c.ixw)
    c.ix_tst = azb(a, c, w)
    c.ix_vf = azi(a, c, c.mw + 1usize)
    if c.bad { ret }
    var q = 0usize
    while q < cap * c.ixw {
        c.ix_sub[q] = -1i64
        q += 1usize
    }
    c.ix_n = 0usize
    var i = 0usize
    while i < n {
        c.inst[i] = i
        i += 1usize
    }
    var at = 1usize
    while at <= c.na {
        if !c.disc[at] {
            c.ref0[at] = r32(c.amean[at] - 2.5f64 * c.asd[at])
        } else {
            c.ref0[at] = 2.0f64
        }
        at += 1usize
    }
    var far = 0usize
    i = 0usize
    while i < n {
        let dist = cb_dist(c, c.dat, c.inst[i] * w, c.ref0, 0usize, 1.0e38f64)
        c.drf1[c.inst[i]] = dist
        if dist > c.drf1[c.inst[far]] { far = i }
        i += 1usize
    }
    at = 0usize
    while at < w {
        c.ref1[at] = c.dat[c.inst[far] * w + at]
        at += 1usize
    }
    i = 0usize
    while i < n {
        c.drf2[c.inst[i]] = cb_dist(c, c.dat, c.inst[i] * w, c.ref1, 0usize, 1.0e38f64)
        i += 1usize
    }
    c.kdroot = ix_build(c, 0i64, i64(n) - 1i64)
    i = 0usize
    while i < n {
        c.rspred[i] = cb_predict_value(c, c.dat, c.inst[i] * w)
        i += 1usize
    }
    var tr = n
    if tr > 1000usize { tr = 1000usize }
    if maxd_in < 0.0f64 {
        c.maxd = cb_set_maxd(c, kr, tr, tr == n)
    } else {
        c.maxd = r32(maxd_in)
    }
    c.minn = (c.nnk + 1i64) / 2i64
    c.worst = ux(c.nnk - 1i64)
    c.useinst = true
}

// ---- the evaluation on the training data and the attribute usage (construct.c)

fn cb_evaluate(c: *Cb, out: []f64) {
    let n = c.n
    var abserr = 0.0f64
    var baseabs = 0.0f64
    var sx = 0.0f64
    var sy = 0.0f64
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var i = 0usize
    while i < n {
        let real = c.cls[i]
        let pv = cb_nn_estimate(c, c.dat, i * c.w, i64(i))
        abserr += cb_fabs(r32(real - pv))
        baseabs += cb_fabs(r32(real - c.gmean))
        sx += real
        sxx += real * real
        sy += pv
        syy += r32(pv * pv)
        sxy += real * pv
        i += 1usize
    }
    let tests = f64(n)
    let prodvar = (sxx - sx * sx / tests) * (syy - sy * sy / tests)
    var cor = 0.0f64
    if prodvar > 0.0f64 { cor = (sxy - sx * sy / tests) / math.sqrt[f64](prodvar) }
    out[0usize] = abserr / tests
    if baseabs != 0.0f64 { out[1usize] = abserr / baseabs } else { out[1usize] = 1.0f64 }
    if cor > 0.0f64 { out[2usize] = cor } else { out[2usize] = 0.0f64 }
}

// the integer percentages of the "Attribute usage" table: conditions in out[at], models in out[w + at]
fn cb_usage(a: *mem.Arena, c: *Cb, out: []f64) {
    let w = c.w
    var cond = az(a, c, w)
    var modl = az(a, c, w)
    var used = azb(a, c, w)
    var sumcases = 0.0f64
    var m = 0usize
    while m < c.members {
        let rs = &c.cttee[m]
        var k = 0usize
        while k < rs.nr {
            let r = &rs.rules[k]
            sumcases += f64(r.cover)
            var q = 0usize
            while q < w {
                used[q] = false
                q += 1usize
            }
            var d = 0usize
            while d < r.size {
                used[r.lhs[d].att] = true
                d += 1usize
            }
            q = 1usize
            while q <= c.na {
                if used[q] { cond[q] += f64(r.cover) }
                used[q] = false
                q += 1usize
            }
            q = 1usize
            while q <= c.na {
                if r.rhs[q] != 0.0f64 { modl[q] += f64(r.cover) }
                q += 1usize
            }
            k += 1usize
        }
        m += 1usize
    }
    var at = 0usize
    while at < 2usize * w {
        out[at] = 0.0f64
        at += 1usize
    }
    at = 1usize
    while at <= c.na {
        var mx = cond[at]
        if modl[at] > mx { mx = modl[at] }
        if mx >= 0.01f64 * sumcases {
            if cond[at] >= 0.01f64 * sumcases { out[at] = cb_rint(100.0f64 * cond[at] / sumcases) }
            if modl[at] >= 0.01f64 * sumcases { out[w + at] = cb_rint(100.0f64 * modl[at] / sumcases) }
        }
        at += 1usize
    }
}

// ---- the whole construction (ConstructCttee)

type Cfg = struct { committees: usize, unbiased: bool, maxrules: i64, extrap: f64, sample: f64, seed: i64, maxd: f64, nn: i64 }

fn cb_construct(a: *mem.Arena, c: *Cb, kr: *Kr, cfg: *const Cfg) -> err {
    let n = c.n
    let w = c.w
    let saved = azu(a, c, n)
    if c.bad { ret mem.Exhausted }
    var i = 0usize
    while i < n {
        saved[i] = c.ord[i]
        i += 1usize
    }
    let e0 = cb_find_global(a, c)
    if e0 != ok { ret e0 }
    c.minitems = 0i64
    let nf = f64(n)
    var mi = cb_rint(nf / 100.0f64)
    if mi > 20.0f64 { mi = 20.0f64 }
    c.minitems = i64(mi)
    if f64(c.minitems) > nf / f64(c.maxrules) { c.minitems = i64(nf / f64(c.maxrules)) }
    if c.minitems < MINSPLIT { c.minitems = MINSPLIT }
    let (cs, e1) = mem.alloc[RSet](a, cfg.committees)
    if e1 != ok { ret e1 }
    c.cttee = cs
    var m = 0usize
    while m < cfg.committees {
        c.nt_count = 0usize
        let t = cb_form_tree(c, 0i64, i64(n) - 1i64, 0i64, -1i64)
        cb_add_models(c, 0i64, i64(n) - 1i64, t, -1i64)
        cb_prune(c, t)
        cb_adjust_all(c, t)
        i = 0usize
        while i < n {
            c.cls[i] = c.dat[i * w + 1usize]
            i += 1usize
        }
        let rs = cb_form_rules(a, c, t)
        if c.bad { ret mem.Exhausted }
        c.cttee[m] = rs
        i = 0usize
        while i < n {
            c.ord[i] = saved[i]
            i += 1usize
        }
        if m + 1usize < cfg.committees {
            i = 0usize
            while i < n {
                let row = c.ord[i]
                let pv = cb_ruleset_pred(c, &c.cttee[m], c.dat, row * w)
                c.resid[row] = pv
                c.cls[row] = r32(2.0f64 * c.dat[row * w + 1usize] - pv)
                i += 1usize
            }
        }
        m += 1usize
    }
    // the model is used as a composite with the nearest neighbors
    c.nnk = cfg.nn
    cb_init_instances(a, c, kr, cfg.maxd)
    if c.bad { ret mem.Exhausted }
    ret ok
}

// ---- the model file: every number the package writes is printed with limited digits and read back, so predictions are made from the read values

// x rounded to nd significant digits, as printf("%.{nd}g") would write it (the digits, not the exponent form)
fn cb_sig_text(a: *mem.Arena, x: f64, nd: i64) -> str {
    let ax = cb_fabs(x)
    var e = i64(math.floor[f64](math.log10[f64](ax)))
    if math.pow[f64](10.0f64, f64(e)) > ax { e -= 1i64 }
    if math.pow[f64](10.0f64, f64(e + 1i64)) <= ax { e += 1i64 }
    var pr = nd - 1i64 - e
    if pr < 0i64 { pr = 0i64 }
    if pr > 99i64 { pr = 99i64 }
    let (b, be) = str.builder(a, 128usize)
    var bb = b
    if be != ok { ret "0" }
    let pe = str.push_f64_fixed(&bb, x, u8(pr))
    if pe != ok { ret "0" }
    ret str.done(&bb)
}

fn cb_fix_text(a: *mem.Arena, x: f64, d: i64) -> str {
    var dd = d
    if dd < 0i64 { dd = 0i64 }
    if dd > 99i64 { dd = 99i64 }
    let (b, be) = str.builder(a, 128usize)
    var bb = b
    if be != ok { ret "0" }
    let pe = str.push_f64_fixed(&bb, x, u8(dd))
    if pe != ok { ret "0" }
    ret str.done(&bb)
}

// read back as a double (sscanf "%lf")
fn cb_rt_sig(a: *mem.Arena, x: f64, nd: i64) -> f64 {
    if x == 0.0f64 || x != x { ret x }
    let m = mem.mark(a)
    let t = cb_sig_text(a, x, nd)
    let (v, pe) = str.parse_f64(t)
    mem.reset(a, m)
    if pe != ok { ret x }
    ret v
}

// read back as a float (sscanf "%f")
fn cb_rt_sig32(a: *mem.Arena, x: f64, nd: i64) -> f64 {
    if x == 0.0f64 || x != x { ret x }
    let m = mem.mark(a)
    let t = cb_sig_text(a, x, nd)
    let (v, pe) = str.parse_f32(t)
    mem.reset(a, m)
    if pe != ok { ret x }
    ret f64(v)
}

fn cb_rt_fix(a: *mem.Arena, x: f64, d: i64) -> f64 {
    let m = mem.mark(a)
    let t = cb_fix_text(a, x, d)
    let (v, pe) = str.parse_f64(t)
    mem.reset(a, m)
    if pe != ok { ret x }
    ret v
}

fn cb_rt_fix32(a: *mem.Arena, x: f64, d: i64) -> f64 {
    let m = mem.mark(a)
    let t = cb_fix_text(a, x, d)
    let (v, pe) = str.parse_f32(t)
    mem.reset(a, m)
    if pe != ok { ret x }
    ret f64(v)
}

// the model as the package reads it back from the .model text: p is filled from the trained c
fn cb_read_model(a: *mem.Arena, c: *Cb, p: *Cb) -> err {
    let w = c.w
    p.na = c.na
    p.w = w
    p.mw = c.mw
    p.members = c.members
    p.prec = c.prec
    p.disc = c.disc
    p.ordr = c.ordr
    p.maxv = c.maxv
    p.skip = azb(a, p, w)
    p.modal = azu(a, p, w)
    p.amean = az(a, p, w)
    p.asd = az(a, p, w)
    p.amax = az(a, p, w)
    p.amin = az(a, p, w)
    if p.bad { ret mem.Exhausted }
    var at = 1usize
    while at <= c.na {
        if c.disc[at] {
            p.modal[at] = c.modal[at]
            if p.modal[at] < 1usize { p.modal[at] = 1usize }
            p.skip[at] = p.modal[at] == 1usize
        } else {
            p.amean[at] = r32(cb_rt_sig(a, c.amean[at], 7i64))
            p.asd[at] = r32(cb_rt_sig(a, c.asd[at], 7i64))
            p.amax[at] = r32(cb_rt_sig(a, c.amax[at], 6i64))
            p.amin[at] = r32(cb_rt_sig(a, c.amin[at], 6i64))
        }
        at += 1usize
    }
    p.gmean = cb_rt_sig32(a, c.gmean, 7i64)
    p.extrap = cb_rt_sig32(a, c.extrap, 6i64)
    p.ceil = r32(cb_rt_sig(a, c.ceil, 7i64))
    p.flo = r32(cb_rt_sig(a, c.flo, 7i64))
    p.maxd = cb_rt_fix32(a, c.maxd, 1i64)
    let (cs, e1) = mem.alloc[RSet](a, c.members)
    if e1 != ok { ret e1 }
    p.cttee = cs
    var m = 0usize
    while m < c.members {
        let rs = &c.cttee[m]
        let (rl, e2) = mem.alloc[Rule](a, rs.nr + 1usize)
        if e2 != ok { ret e2 }
        var k = 0usize
        while k < rs.nr {
            let r = &rs.rules[k]
            let (lh, e3) = mem.alloc[Cond](a, r.size + 1usize)
            if e3 != ok { ret e3 }
            let rh = az(a, p, w)
            if p.bad { ret mem.Exhausted }
            var d = 0usize
            while d < r.size {
                let cd = &r.lhs[d]
                var tv = cd.tv
                if cd.ty == BR_SUBSET { tv = 1i64 }
                lh[d] = Cond { ty: cd.ty, att: cd.att, cut: r32(cb_rt_sig(a, cd.cut, 8i64)), tv: tv, sub: cd.sub }
                d += 1usize
            }
            rh[0usize] = cb_rt_sig(a, r.rhs[0usize], 14i64)
            var q = 1usize
            while q <= c.na {
                if cb_fabs(r.rhs[q]) > 0.0f64 { rh[q] = cb_rt_sig(a, r.rhs[q], 14i64) }
                q += 1usize
            }
            let mean = cb_rt_fix32(a, r.mean, c.prec + 1i64)
            let lo = cb_rt_sig32(a, r.lo, 6i64)
            let hi = cb_rt_sig32(a, r.hi, 6i64)
            let est = cb_rt_fix32(a, r.esterr, c.prec + 1i64)
            let range = r32(hi - lo)
            var lolim = r32(lo - r32(p.extrap * range))
            if lolim < 0.0f64 && lo >= 0.0f64 { lolim = 0.0f64 }
            var hilim = r32(hi + r32(p.extrap * range))
            if hilim > 0.0f64 && hi <= 0.0f64 { hilim = 0.0f64 }
            rl[k] = Rule { size: r.size, cover: r.cover, mean: mean, lo: lo, hi: hi, lolim: lolim, hilim: hilim, esterr: est, lhs: lh[0usize..r.size], rhs: rh }
            k += 1usize
        }
        p.cttee[m] = RSet { nr: rs.nr, rules: rl[0usize..rs.nr] }
        m += 1usize
    }
    ret ok
}

// the checksums of the read model that the oracle compares (see scripts/r_oracle/groups/cubist.R)
fn cb_model_sums(a: *mem.Arena, p: *Cb, out: []f64) {
    var q = 0usize
    while q < 8usize {
        out[q] = 0.0f64
        q += 1usize
    }
    var g = 0usize
    var j = 0usize
    var m = 0usize
    while m < p.members {
        let rs = &p.cttee[m]
        var k = 0usize
        while k < rs.nr {
            let r = &rs.rules[k]
            g += 1usize
            let fg = f64(g)
            out[0usize] += 1.0f64
            out[1usize] += fg * f64(r.cover)
            out[2usize] += fg * cb_rt_fix(a, r.mean, p.prec + 1i64)
            out[3usize] += fg * (cb_rt_sig(a, r.lo, 6i64) + 2.0f64 * cb_rt_sig(a, r.hi, 6i64))
            out[4usize] += fg * cb_rt_fix(a, r.esterr, p.prec + 1i64)
            var d = 0usize
            while d < r.size {
                let cd = &r.lhs[d]
                j += 1usize
                var sel = 0.0f64
                if cd.ty == BR_THRESH {
                    sel = f64(cd.tv)
                    out[6usize] += f64(j) * cb_rt_sig(a, cd.cut, 8i64)
                } else if cd.ty == BR_DISCR {
                    sel = f64(cd.tv - 1i64)
                } else {
                    var v = 2usize
                    while v < cd.sub.len && v <= p.maxv[cd.att] {
                        if cd.sub[v] { sel += math.pow[f64](2.0f64, f64(v - 2usize)) }
                        v += 1usize
                    }
                }
                out[5usize] += f64(j) * (f64(cd.ty) * 10000.0f64 + f64(cd.att - 1usize) * 100.0f64 + sel)
                d += 1usize
            }
            var at = 0usize
            while at <= p.na {
                var cf = 0.0f64
                if at == 0usize {
                    cf = r.rhs[0usize]
                } else if at >= 2usize {
                    cf = r.rhs[at]
                }
                if at == 0usize || at >= 2usize {
                    var pos = 0usize
                    if at >= 2usize { pos = at - 1usize }
                    out[7usize] += cf * (fg * 17.0f64 + f64(pos) + 1.0f64)
                }
                at += 1usize
            }
            k += 1usize
        }
        m += 1usize
    }
}

// ---- cases as the package writes them (GetData for instances and for the cases to predict)

// one row of d into dst[off..]: unknown values become the means or modal values of the model; the class is the instance's
fn cb_load_row(p: *Cb, d: *const Data, r: usize, dst: []f64, off: usize, withclass: bool) {
    dst[off] = 0.0f64
    dst[off + 1usize] = 0.0f64
    if withclass { dst[off + 1usize] = r32(d.y[r]) }
    var j = 0usize
    while j < d.p {
        let at = j + 2usize
        let xv = d.x[j * d.n + r]
        if p.disc[at] {
            var code = 0.0f64
            if xv == xv && xv >= 1.0f64 { code = xv + 1.0f64 }
            if code == 0.0f64 && !p.skip[at] { code = f64(p.modal[at]) }
            dst[off + at] = code
        } else {
            if xv == xv {
                dst[off + at] = r32(xv)
            } else if !p.skip[at] {
                dst[off + at] = p.amean[at]
            } else {
                dst[off + at] = 0.0f64
            }
        }
        j += 1usize
    }
}

// predictions for the rows of q at the given number of neighbors; train supplies the instances
fn cb_predict(a: *mem.Arena, p: *Cb, train: *const Data, q: *const Data, neighbors: i64, kr: *Kr, out: []f64) -> err {
    let w = p.w
    let mark = mem.mark(a)
    var i = 0usize
    if neighbors > 0i64 {
        let n = train.n
        p.n = n
        p.dat = az(a, p, n * w)
        p.cls = az(a, p, n)
        if p.bad { ret mem.Exhausted }
        i = 0usize
        while i < n {
            cb_load_row(p, train, i, p.dat, i * w, true)
            p.cls[i] = p.dat[i * w + 1usize]
            i += 1usize
        }
        let range = r32(p.amax[1usize] - p.amin[1usize])
        p.ceil = r32(p.amax[1usize] + r32(p.extrap * range))
        if p.amax[1usize] <= 0.0f64 && p.ceil > 0.0f64 { p.ceil = 0.0f64 }
        p.flo = r32(p.amin[1usize] - r32(p.extrap * range))
        if p.amin[1usize] >= 0.0f64 && p.flo < 0.0f64 { p.flo = 0.0f64 }
        p.nnk = neighbors
        cb_init_instances(a, p, kr, p.maxd)
        if p.bad { ret mem.Exhausted }
    }
    let qb = az(a, p, w)
    if p.bad { ret mem.Exhausted }
    i = 0usize
    while i < q.n {
        cb_load_row(p, q, i, qb, 0usize, false)
        if neighbors > 0i64 {
            out[i] = cb_nn_estimate(p, qb, 0usize, -1i64)
        } else {
            out[i] = cb_predict_value(p, qb, 0usize)
        }
        i += 1usize
    }
    mem.reset(a, mark)
    ret ok
}

// ---- fitting

fn cb_fit(a: *mem.Arena, c: *Cb, d: *const Data, cfg: *const Cfg, kr: *Kr) -> err {
    let n0 = d.n
    let (rows0, e0) = mem.alloc[usize](a, n0 + 1usize)
    if e0 != ok { ret e0 }
    var nr = 0usize
    let sample = r32(cfg.sample)
    if sample > 0.0f64 {
        kr_reset(kr, cfg.seed)
        var want = i64(r32(f64(n0) * sample) + 0.5f64)
        var left = i64(n0)
        var r = 0usize
        while r < n0 {
            let thr = r32(f64(want) / f64(left))
            left -= 1i64
            if kr_random(kr) < thr {
                want -= 1i64
                rows0[nr] = r
                nr += 1usize
            }
            r += 1usize
        }
    } else {
        var r = 0usize
        while r < n0 {
            rows0[r] = r
            r += 1usize
        }
        nr = n0
    }
    let e1 = cb_get_data(a, c, d, rows0[0usize..nr], r32(cfg.extrap))
    if e1 != ok { ret e1 }
    c.members = cfg.committees
    c.unbiased = cfg.unbiased
    c.maxrules = cfg.maxrules
    cb_alloc_env(a, c)
    if c.bad { ret mem.Exhausted }
    let e2 = cb_construct(a, c, kr, cfg)
    if e2 != ok { ret e2 }
    if sample > 0.0f64 {
        kr_reset(kr, cfg.seed)
        var r = 0usize
        while r < n0 {
            let _ = kr_random(kr)
            r += 1usize
        }
    }
    ret ok
}
