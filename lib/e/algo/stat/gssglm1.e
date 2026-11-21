// R package gss: gssanova (gssanova1) over the sampled basis id.basis for the families binomial, Poisson, Gamma and inverse Gaussian: ngreg1, the performance-oriented
// iteration over sspreg1 (one kernel) or mspreg1 (several) with the working weights sqrt(wt). Models and layouts as in e.algo.stat.gss ssanova over the sampled basis.
//
// Not here: the nbinomial, polr, weibull, lognorm and loglogis families, offsets, case weights, random and partial terms.

use e.math
use e.mem
use e.algo.stat.gss as gss

error NoConverge

type Gs1 = struct { fit: gss.Ss1, eta: []f64, w: []f64, iter: usize }

fn p10(x: f64) -> f64 { ret math.pow[f64](10.0f64, x) }

// eta = s d + sum 10^theta r c
fn lin(f: *const gss.Ss1, s: []const f64, rs: []const f64, nq: usize, n: usize, n0: usize, nxi: usize, eta: []f64) {
    var i = 0usize
    while i < n {
        var sm = 0.0f64
        var j = 0usize
        while j < n0 {
            sm += s[i + j * n] * f.d[j]
            j += 1usize
        }
        var k = 0usize
        while k < nq {
            var rc = 0.0f64
            j = 0usize
            while j < nxi {
                rc += rs[k * n * nxi + i + j * n] * f.c[j]
                j += 1usize
            }
            sm += p10(f.theta[k]) * rc
            k += 1usize
        }
        eta[i] = sm
        i += 1usize
    }
}

// the quadrature-free fit of one pass: nq == 1 through sspreg1w with q = r[id, ], else mspreg1w
fn pass(a: *mem.Arena, s: []const f64, rs: []const f64, id: []const usize, nq: usize, y: []const f64, w: []const f64, n: usize, n0: usize, nxi: usize, method: usize, alpha: f64, varht: f64, skip: bool, out: *gss.Ss1) -> err {
    if nq == 1usize {
        let (q, e) = gss.zeros(a, nxi * nxi)
        if e != ok { ret e }
        var j = 0usize
        while j < nxi {
            var i = 0usize
            while i < nxi {
                q[i + j * nxi] = rs[id[i] + j * n]
                i += 1usize
            }
            j += 1usize
        }
        try gss.sspreg1w(a, s, rs, q, y, w, n, n0, nxi, method, alpha, varht, out)
        ret ok
    }
    try gss.mspreg1w(a, s, rs, id, nq, y, w, n, n0, nxi, method, alpha, varht, skip, out)
    ret ok
}

// fam 1 binomial, 2 Poisson, 3 Gamma, 4 inverse Gaussian; method 1 u, 2 v
fn gssanova1(a: *mem.Arena, fam: usize, s: []const f64, rs: []const f64, id: []const usize, nq: usize, y: []const f64, n: usize, n0: usize, nxi: usize, method: usize, alpha: f64, varht: f64, skip: bool, out: *Gs1) -> err {
    let (eta, e1) = gss.zeros(a, n)
    let (etan, e2) = gss.zeros(a, n)
    let (ywk, e3) = gss.zeros(a, n)
    let (wt, e4) = gss.zeros(a, n)
    let (w, e5) = gss.zeros(a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var none: []const f64 = zero
    var i = 0usize
    if fam >= 3usize {
        // the start: the log response fitted by "v"
        while i < n {
            ywk[i] = math.log[f64](y[i])
            i += 1usize
        }
        var z0: gss.Ss1 = zero
        try pass(a, s, rs, id, nq, ywk, none, n, n0, nxi, 2usize, alpha, varht, skip, &z0)
        lin(&z0, s, rs, nq, n, n0, nxi, eta)
    }
    var iter = 0usize
    var z: gss.Ss1 = zero
    var looping = true
    while looping {
        iter += 1usize
        gss.mkdata(fam, y, eta, n, ywk, wt)
        i = 0usize
        while i < n {
            w[i] = math.sqrt[f64](wt[i])
            i += 1usize
        }
        let lb = mem.mark(a)
        try pass(a, s, rs, id, nq, ywk, w, n, n0, nxi, method, alpha, varht, skip, &z)
        lin(&z, s, rs, nq, n, n0, nxi, etan)
        var num = 0.0f64
        var dn = 0.0f64
        i = 0usize
        while i < n {
            let df = (eta[i] - etan[i]) / (1.0f64 + gss.absf(eta[i]))
            num += wt[i] * df * df
            dn += wt[i]
            i += 1usize
        }
        i = 0usize
        while i < n {
            eta[i] = etan[i]
            i += 1usize
        }
        if num / dn < 0.0000001f64 {
            looping = false
        } else {
            if iter >= 30usize { looping = false }
        }
        if looping { mem.reset(a, lb) }
    }
    out.fit = z
    out.eta = eta
    out.w = wt
    out.iter = iter
    ret ok
}
