// R forecast::bats and forecast::tbats for a series without missing values: the BATS state space model (Box-Cox, ARMA errors, trend,
// damped trend, several seasonal periods as m-term cycles) and the TBATS one (trigonometric seasonality), each fitted as forecast does:
// the starting parameters, the regression start of the states (lm of the one-step errors on the propagated w matrix, with the seasonal
// cut and seeds of adjustSeasonalSeeds.R), optim's Nelder-Mead (or BFGS for a single parameter) from rnm.e and rbfgs.e on the likelihood
// n log(sum e^2) - 2 (lambda - 1) sum(log y) with checkAdmissibility, the ARMA error step through auto.arima(errors, d = 0), the search over
// Box-Cox / trend / damping (bats) and over the number of harmonics per period (tbats), and forecast.bats / forecast.tbats point forecasts
// and prediction limits (including forecast.tbats's g matrix, which passes object$beta.v and so loses the trend row of g).
//
// The C++ updates of F, g and w are rebuilt from the parameters at every evaluation (the same entries); calcBATSFaster is the dense
// recursion (the same values up to rounding). The stale gamma-bold block that updateGMatrix leaves for the second and later seasonal
// periods of a BATS model with ARMA errors is reproduced.
//
// Not here: use.parallel (same answer, serial), a constant series, missing values, refitting a given model, simulate and bootstrap intervals, a
// non-default `...` of auto.arima, seasonal periods not given explicitly (the caller passes the resolved periods and the ts frequency).

use e.math
use e.mem
use e.math.dist as dist
use e.algo.stat.rnm as rn
use e.algo.stat.rbfgs as rb
use e.algo.stat.fcast as fcast
use e.algo.stat.autoarima as aa
use e.algo.stat.ade4 as ad
use e.algo.linalg.decomp as decomp
use e.algo.linalg.lapack_base as lb

type BSpec = struct { tb: bool, bc: bool, beta: bool, damp: bool, per: []f64, kv: []usize, p: usize, q: usize, lo: f64, hi: f64 }

type BPars = struct { lam: f64, alpha: f64, phi: f64, beta: f64, gam: []const f64, arc: []const f64, mac: []const f64 }

type BatsFit = struct {
    good: bool, sp: BSpec, aic: f64, loglik: f64, code: usize, variance: f64, n: usize, d: usize, biasadj: bool,
    lam: f64, alpha: f64, beta: f64, phi: f64, gam: []f64, arc: []f64, mac: []f64, npar: usize,
    seed: []f64, fitted: []f64, errors: []f64, x: []f64
}

type BCtx = struct {
    ar: *mem.Arena, sp: BSpec, n: usize, d: usize, ng: usize, ssz: usize, np: usize, nst: usize,
    y: []const f64, ty: []f64, ly: f64, x0u: []f64, x0: []f64, parscale: []f64, full: []f64, gsc: []f64,
    w: []f64, g: []f64, fm: []f64, dm: []f64, gbs: []f64, gbf: []f64, st: []f64, er: []f64, yh: []f64,
    eh: []f64, ez: []f64, esc: []f64, etau: []f64, ewr: []f64, ewi: []f64, ework: []f64, stale: bool, bad: bool
}

fn bf_nan() -> f64 { ret mem.bitcast[f64](9221120237041090560u64) }
fn bf_inf() -> f64 { ret 1.0e308f64 * 10.0f64 }
fn bf_pi() -> f64 { ret 3.141592653589793f64 }

// R's sum() accumulates in long double; a compensated sum rounded to double agrees with it
fn bf_lsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var cc = 0.0f64
    var i = 0usize
    while i < v.len {
        let t = s + v[i]
        if math.abs[f64](s) >= math.abs[f64](v[i]) { cc += (s - t) + v[i] } else { cc += (v[i] - t) + s }
        s = t
        i += 1usize
    }
    ret s + cc
}

fn bf_ssq(v: []const f64) -> f64 {
    var s = 0.0f64
    var cc = 0.0f64
    var i = 0usize
    while i < v.len {
        let q = v[i] * v[i]
        let t = s + q
        if math.abs[f64](s) >= math.abs[f64](q) { cc += (s - t) + q } else { cc += (q - t) + s }
        s = t
        i += 1usize
    }
    ret s + cc
}

fn bf_alloc(ar: *mem.Arena, n: usize) -> []f64 {
    let (v, e) = mem.alloc[f64](ar, n + 1usize)
    var i = 0usize
    while i < n + 1usize {
        v[i] = 0.0f64
        i += 1usize
    }
    ret v[0usize..n]
}

fn bf_bc(x: f64, lam: f64) -> f64 {
    if lam < 0.0f64 && x < 0.0f64 { ret bf_nan() }
    ret fcast.box_cox(x, lam)
}

fn bf_ibc(x: f64, lam: f64) -> f64 {
    if lam < 0.0f64 && x > 0.0f64 - 1.0f64 / lam { ret bf_nan() }
    ret fcast.inv_box_cox(x, lam)
}

fn bf_ibc_adj(x: f64, lam: f64, adj: bool, fv: f64) -> f64 {
    let o = bf_ibc(x, lam)
    if !adj { ret o }
    ret o * (1.0f64 + 0.5f64 * fv * (1.0f64 - lam) / math.pow[f64](o, 2.0f64 * lam))
}

fn bf_sumper(sp: *const BSpec) -> usize {
    var s = 0usize
    var i = 0usize
    while i < sp.per.len {
        if sp.tb { s += 2usize * sp.kv[i] } else { s += usize(sp.per[i]) }
        i += 1usize
    }
    ret s
}

fn bf_ng(sp: *const BSpec) -> usize {
    if sp.per.len == 0usize { ret 0usize }
    if sp.tb { ret 2usize * sp.per.len }
    ret sp.per.len
}

fn bf_np(sp: *const BSpec) -> usize {
    var k = 1usize + bf_ng(sp) + sp.p + sp.q
    if sp.bc { k += 1usize }
    if sp.beta { k += 1usize }
    if sp.damp { k += 1usize }
    ret k
}

fn bf_dim(sp: *const BSpec) -> usize {
    var k = 1usize + bf_sumper(sp) + sp.p + sp.q
    if sp.beta { k += 1usize }
    ret k
}

fn bf_unpack(sp: *const BSpec, v: []const f64, pr: *BPars) {
    var i = 0usize
    pr.lam = 1.0f64
    if sp.bc {
        pr.lam = v[0usize]
        i = 1usize
    }
    pr.alpha = v[i]
    i += 1usize
    pr.phi = 1.0f64
    pr.beta = 0.0f64
    if sp.beta {
        if sp.damp {
            pr.phi = v[i]
            pr.beta = v[i + 1usize]
            i += 2usize
        } else {
            pr.beta = v[i]
            i += 1usize
        }
    }
    let ng = bf_ng(sp)
    pr.gam = v[i..i + ng]
    i += ng
    pr.arc = v[i..i + sp.p]
    i += sp.p
    pr.mac = v[i..i + sp.q]
}

// the gamma-bold row of the seasonal states: gamma at the start of each BATS period, gamma one then gamma two over each TBATS harmonic pair
fn bf_gbold(sp: *const BSpec, pr: *const BPars, out: []f64) {
    var i = 0usize
    while i < out.len {
        out[i] = 0.0f64
        i += 1usize
    }
    let ns = sp.per.len
    var off = 0usize
    i = 0usize
    while i < ns {
        if sp.tb {
            let k = sp.kv[i]
            var j = 0usize
            while j < k {
                out[off + j] = pr.gam[i]
                out[off + k + j] = pr.gam[ns + i]
                j += 1usize
            }
            off += 2usize * k
        } else {
            out[off] = pr.gam[i]
            off += usize(sp.per[i])
        }
        i += 1usize
    }
}

// w, g and F (and the fresh gamma-bold row) from the parameters; stale uses the BATS gamma-bold block the C++ update leaves for F
fn bf_build(c: *BCtx, pr: *const BPars, stale: bool) {
    let sp = c.sp
    let d = c.d
    var i = 0usize
    while i < d {
        c.w[i] = 0.0f64
        c.g[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < d * d {
        c.fm[i] = 0.0f64
        i += 1usize
    }
    var adj = 0usize
    if sp.beta { adj = 1usize }
    let stot = c.ssz
    let ns = sp.per.len
    c.w[0usize] = 1.0f64
    if sp.beta { c.w[1usize] = pr.phi }
    var pos = adj
    i = 0usize
    while i < ns {
        if sp.tb {
            var j = 1usize
            while j <= sp.kv[i] {
                c.w[pos + j] = 1.0f64
                j += 1usize
            }
            pos += 2usize * sp.kv[i]
        } else {
            pos += usize(sp.per[i])
            c.w[pos] = 1.0f64
        }
        i += 1usize
    }
    var j = 0usize
    while j < sp.p {
        c.w[adj + stot + j + 1usize] = pr.arc[j]
        j += 1usize
    }
    j = 0usize
    while j < sp.q {
        c.w[adj + stot + sp.p + j + 1usize] = pr.mac[j]
        j += 1usize
    }
    c.g[0usize] = pr.alpha
    if sp.beta { c.g[1usize] = pr.beta }
    bf_gbold(&sp, pr, c.gbf)
    var r = 0usize
    while r < stot {
        c.g[adj + 1usize + r] = c.gbf[r]
        r += 1usize
    }
    if sp.p > 0usize { c.g[adj + stot + 1usize] = 1.0f64 }
    if sp.q > 0usize { c.g[adj + stot + sp.p + 1usize] = 1.0f64 }
    // F
    c.fm[0usize] = 1.0f64
    if sp.beta { c.fm[1usize] = pr.phi }
    let cbase = 1usize + adj + stot
    j = 0usize
    while j < sp.p {
        c.fm[cbase + j] = pr.alpha * pr.arc[j]
        j += 1usize
    }
    j = 0usize
    while j < sp.q {
        c.fm[cbase + sp.p + j] = pr.alpha * pr.mac[j]
        j += 1usize
    }
    if sp.beta {
        c.fm[d + 1usize] = pr.phi
        j = 0usize
        while j < sp.p {
            c.fm[d + cbase + j] = pr.beta * pr.arc[j]
            j += 1usize
        }
        j = 0usize
        while j < sp.q {
            c.fm[d + cbase + sp.p + j] = pr.beta * pr.mac[j]
            j += 1usize
        }
    }
    let srow0 = 1usize + adj
    var off = 0usize
    i = 0usize
    while i < ns {
        if sp.tb {
            let k = sp.kv[i]
            let m = sp.per[i]
            var jj = 1usize
            while jj <= k {
                var cc = 0.0f64
                if m != 2.0f64 { cc = math.cos[f64](2.0f64 * bf_pi() * f64(jj) / m) }
                let ss = math.sin[f64](2.0f64 * bf_pi() * f64(jj) / m)
                let ra = srow0 + off + jj - 1usize
                let rb2 = srow0 + off + k + jj - 1usize
                c.fm[ra * d + ra] = cc
                c.fm[ra * d + srow0 + off + k + jj - 1usize] = ss
                c.fm[rb2 * d + ra] = 0.0f64 - ss
                c.fm[rb2 * d + rb2] = cc
                jj += 1usize
            }
            off += 2usize * k
        } else {
            let s = usize(sp.per[i])
            c.fm[(srow0 + off) * d + srow0 + off + s - 1usize] = 1.0f64
            var rr = 1usize
            while rr < s {
                c.fm[(srow0 + off + rr) * d + srow0 + off + rr - 1usize] = 1.0f64
                rr += 1usize
            }
            off += s
        }
        i += 1usize
    }
    r = 0usize
    while r < stot {
        var gv = c.gbf[r]
        if stale { gv = c.gbs[r] }
        j = 0usize
        while j < sp.p {
            c.fm[(srow0 + r) * d + cbase + j] = gv * pr.arc[j]
            j += 1usize
        }
        j = 0usize
        while j < sp.q {
            c.fm[(srow0 + r) * d + cbase + sp.p + j] = gv * pr.mac[j]
            j += 1usize
        }
        r += 1usize
    }
    if sp.p > 0usize {
        j = 0usize
        while j < sp.p {
            c.fm[cbase * d + cbase + j] = pr.arc[j]
            j += 1usize
        }
        j = 0usize
        while j < sp.q {
            c.fm[cbase * d + cbase + sp.p + j] = pr.mac[j]
            j += 1usize
        }
        var ii = 1usize
        while ii < sp.p {
            c.fm[(cbase + ii) * d + cbase + ii - 1usize] = 1.0f64
            ii += 1usize
        }
    }
    if sp.q > 0usize {
        let mrow0 = cbase + sp.p
        var ii = 1usize
        while ii < sp.q {
            c.fm[(mrow0 + ii) * d + cbase + sp.p + ii - 1usize] = 1.0f64
            ii += 1usize
        }
    }
}

fn bf_dmat(c: *BCtx) {
    let d = c.d
    var i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            c.dm[i * d + j] = c.fm[i * d + j] - c.g[i] * c.w[j]
            j += 1usize
        }
        i += 1usize
    }
}

// F x + g e into out
fn bf_step(c: *BCtx, x: []const f64, ev: f64, out: []f64) {
    let d = c.d
    var i = 0usize
    while i < d {
        var acc = 0.0f64
        var j = 0usize
        while j < d {
            let fv = c.fm[i * d + j]
            if fv != 0.0f64 { acc += fv * x[j] }
            j += 1usize
        }
        out[i] = acc + c.g[i] * ev
        i += 1usize
    }
}

// calcModel / calcBATSFaster: fitted values, errors and states (time-major, d per step) of y from the states x0
fn bf_run(c: *BCtx, yv: []const f64, x0: []const f64) {
    let d = c.d
    var t = 0usize
    while t < c.n {
        var acc = 0.0f64
        var j = 0usize
        if t == 0usize {
            while j < d {
                if c.w[j] != 0.0f64 { acc += c.w[j] * x0[j] }
                j += 1usize
            }
        } else {
            while j < d {
                if c.w[j] != 0.0f64 { acc += c.w[j] * c.st[(t - 1usize) * d + j] }
                j += 1usize
            }
        }
        c.yh[t] = acc
        c.er[t] = yv[t] - acc
        if t == 0usize {
            bf_step(c, x0, c.er[t], c.st[0usize..d])
        } else {
            bf_step(c, c.st[(t - 1usize) * d..t * d], c.er[t], c.st[t * d..(t + 1usize) * d])
        }
        t += 1usize
    }
}

// all |eigenvalue| of D below 1 + 1e-2 (dgeev, values only: dgebal, dgehd2 and dlahqr from ade4)
fn bf_eig_ok(c: *BCtx) -> bool {
    let n = c.d
    let nn = i64(n)
    var r = 0usize
    while r < n {
        var cc = 0usize
        while cc < n {
            c.eh[r + cc * n] = c.dm[r * n + cc]
            c.ez[r + cc * n] = 0.0f64
            cc += 1usize
        }
        c.ez[r + r * n] = 1.0f64
        c.esc[r] = 0.0f64
        c.etau[r] = 0.0f64
        c.ewr[r] = 0.0f64
        c.ewi[r] = 0.0f64
        r += 1usize
    }
    let (ilo, ihi) = ad.g_balance(nn, c.eh, c.esc)
    var i = ilo
    while i <= ihi - 1i64 {
        var alpha = c.eh[ad.gx(i + 1i64, i, nn)]
        var t = 0.0f64
        lb.dlarfg(ihi - i, &alpha, c.eh[ad.gx(lb.i_min(i + 2i64, nn), i, nn)..], 1i64, &t)
        c.eh[ad.gx(i + 1i64, i, nn)] = alpha
        c.etau[usize(i - 1i64)] = t
        lb.dlarf1f("Right", ihi, ihi - i, c.eh[ad.gx(i + 1i64, i, nn)..], 1i64, t, c.eh[ad.gx(1i64, i + 1i64, nn)..], nn, c.ework)
        lb.dlarf1f("Left", ihi - i, nn - i, c.eh[ad.gx(i + 1i64, i, nn)..], 1i64, t, c.eh[ad.gx(i + 1i64, i + 1i64, nn)..], nn, c.ework)
        i = i + 1i64
    }
    i = 1i64
    while i < ilo {
        c.ewr[usize(i - 1i64)] = c.eh[ad.gx(i, i, nn)]
        c.ewi[usize(i - 1i64)] = 0.0f64
        i = i + 1i64
    }
    i = ihi + 1i64
    while i <= nn {
        c.ewr[usize(i - 1i64)] = c.eh[ad.gx(i, i, nn)]
        c.ewi[usize(i - 1i64)] = 0.0f64
        i = i + 1i64
    }
    if ilo == ihi {
        c.ewr[usize(ilo - 1i64)] = c.eh[ad.gx(ilo, ilo, nn)]
        c.ewi[usize(ilo - 1i64)] = 0.0f64
    } else {
        let info = ad.g_lahqr(nn, ilo, ihi, c.eh, c.ewr, c.ewi, c.ez)
        if info != 0i64 { ret false }
    }
    var k = 0usize
    while k < n {
        let md = math.sqrt[f64](c.ewr[k] * c.ewr[k] + c.ewi[k] * c.ewi[k])
        if !(md < 1.0f64 + 1.0e-2f64) { ret false }
        k += 1usize
    }
    ret true
}

// checkAdmissibility
fn bf_adm(c: *BCtx, pr: *const BPars) -> bool {
    let sp = c.sp
    if sp.bc {
        if pr.lam <= sp.lo || pr.lam >= sp.hi { ret false }
    }
    if sp.beta {
        if pr.phi < 0.8f64 || pr.phi > 1.0f64 { ret false }
    }
    if sp.p > 0usize {
        let (mr, good) = aa.min_modulus_ok(c.ar, pr.arc, true, 1.0e30f64)
        if good && mr < 1.0f64 + 1.0e-2f64 { ret false }
    }
    if sp.q > 0usize {
        let (mr, good) = aa.min_modulus_ok(c.ar, pr.mac, false, 1.0e30f64)
        if good && mr < 1.0f64 + 1.0e-2f64 { ret false }
    }
    bf_dmat(c)
    ret bf_eig_ok(c)
}

// calcLikelihood / calcLikelihoodNOTransformed (and the TBATS pair) at the scaled parameters sc
fn bf_obj(c: *BCtx, sc: []const f64) -> f64 {
    let sp = c.sp
    var i = 0usize
    while i < c.np {
        c.full[i] = sc[i] * c.parscale[i]
        i += 1usize
    }
    var pr: BPars = zero
    bf_unpack(&sp, c.full, &pr)
    if !sp.tb && sp.per.len > 0usize { c.gbs[0usize] = pr.gam[0usize] }
    var yv: []const f64 = c.y
    if sp.bc {
        i = 0usize
        while i < c.nst {
            c.x0[i] = bf_bc(c.x0u[i], pr.lam)
            i += 1usize
        }
        i = 0usize
        while i < c.n {
            c.ty[i] = bf_bc(c.y[i], pr.lam)
            i += 1usize
        }
        yv = c.ty
    }
    bf_build(c, &pr, !sp.tb)
    bf_run(c, yv, c.x0)
    let sse = bf_ssq(c.er)
    var ll = f64(c.n) * math.log[f64](sse)
    if sp.bc { ll = ll - 2.0f64 * (pr.lam - 1.0f64) * c.ly }
    if sp.tb {
        if ll != ll { ret bf_inf() }
    }
    if bf_adm(c, &pr) { ret ll }
    if sp.tb { ret bf_inf() }
    ret 1.0e20f64
}

fn bf_grad(c: *BCtx, b: []const f64, g: []f64) {
    let eps = 0.001f64
    var i = 0usize
    while i < c.np {
        c.gsc[i] = b[i]
        i += 1usize
    }
    i = 0usize
    while i < c.np {
        c.gsc[i] = b[i] + eps
        let v1 = bf_obj(c, c.gsc)
        c.gsc[i] = b[i] - eps
        let v2 = bf_obj(c, c.gsc)
        g[i] = (v1 - v2) / (2.0f64 * eps)
        if !(g[i] - g[i] == 0.0f64) { c.bad = true }
        c.gsc[i] = b[i]
        i += 1usize
    }
}

fn bf_gcd(larger: usize, smaller: usize) -> usize {
    var a = larger
    var b = smaller
    while true {
        let r = a % b
        if r == 0usize { ret b }
        a = b
        b = r
    }
    ret b
}

// removes the current columns lo..hi (1-based, inclusive) of the column index list; answers the new length
fn bf_rm(cols: []usize, cur: usize, lo: i64, hi: i64) -> usize {
    var out = 0usize
    var k = 0usize
    while k < cur {
        let pos = i64(k) + 1i64
        if pos < lo || pos > hi {
            cols[out] = cols[k]
            out += 1usize
        }
        k += 1usize
    }
    ret out
}

fn bf_finite(v: f64) -> bool { ret v - v == 0.0f64 }

// fitSpecificBATS / fitSpecificTBATS: ok false when optim would stop on a non-finite start (R's try-error)
fn bf_fit(ar: *mem.Arena, y: []const f64, sp0: BSpec, lam0: f64, biasadj: bool) -> BatsFit {
    var out: BatsFit = zero
    out.good = false
    out.aic = bf_inf()
    var sp = sp0
    if !sp.beta { sp.damp = false }
    let n = y.len
    let ns = sp.per.len
    let np = bf_np(&sp)
    let d = bf_dim(&sp)
    let ng = bf_ng(&sp)
    let ssz = bf_sumper(&sp)
    var sumper = 0.0f64
    var i = 0usize
    while i < ns {
        sumper += sp.per[i]
        i += 1usize
    }
    var c: BCtx = zero
    c.ar = ar
    c.sp = sp
    c.n = n
    c.d = d
    c.ng = ng
    c.ssz = ssz
    c.np = np
    c.nst = d
    c.y = y
    c.ty = bf_alloc(ar, n)
    c.x0u = bf_alloc(ar, d)
    c.x0 = bf_alloc(ar, d)
    c.parscale = bf_alloc(ar, np)
    c.full = bf_alloc(ar, np)
    c.gsc = bf_alloc(ar, np)
    c.w = bf_alloc(ar, d)
    c.g = bf_alloc(ar, d)
    c.fm = bf_alloc(ar, d * d)
    c.dm = bf_alloc(ar, d * d)
    c.gbs = bf_alloc(ar, ssz + 1usize)
    c.gbf = bf_alloc(ar, ssz + 1usize)
    c.st = bf_alloc(ar, d * n)
    c.er = bf_alloc(ar, n)
    c.yh = bf_alloc(ar, n)
    c.eh = bf_alloc(ar, d * d)
    c.ez = bf_alloc(ar, d * d)
    c.esc = bf_alloc(ar, d)
    c.etau = bf_alloc(ar, d)
    c.ewr = bf_alloc(ar, d)
    c.ewi = bf_alloc(ar, d)
    c.ework = bf_alloc(ar, d * 64usize + 64usize)
    let lgy = bf_alloc(ar, n)
    i = 0usize
    while i < n {
        lgy[i] = math.log[f64](y[i])
        i += 1usize
    }
    c.ly = bf_lsum(lgy)
    // starting parameters
    var alpha0 = 0.09f64
    var beta0 = 0.05f64
    var phi0 = 1.0f64
    if !sp.tb && sumper > 16.0f64 {
        alpha0 = 1.0e-6f64
        beta0 = 5.0e-7f64
    }
    if sp.damp { phi0 = 0.999f64 }
    let v0 = bf_alloc(ar, np)
    var k = 0usize
    if sp.bc {
        v0[0usize] = lam0
        k = 1usize
    }
    v0[k] = alpha0
    k += 1usize
    if sp.beta {
        if sp.damp {
            v0[k] = phi0
            v0[k + 1usize] = beta0
            k += 2usize
        } else {
            v0[k] = beta0
            k += 1usize
        }
    }
    i = 0usize
    while i < ng {
        if !sp.tb { v0[k + i] = 0.001f64 }
        i += 1usize
    }
    // parscale
    var ps = 0usize
    if sp.bc {
        c.parscale[0usize] = 0.001f64
        ps = 1usize
    }
    if sp.tb { c.parscale[ps] = 0.01f64 } else { c.parscale[ps] = 0.1f64 }
    ps += 1usize
    if sp.beta {
        c.parscale[ps] = 0.01f64
        ps += 1usize
        if sp.damp {
            c.parscale[ps] = 0.01f64
            ps += 1usize
        }
    }
    i = 0usize
    while i < ng {
        if sp.tb { c.parscale[ps + i] = 1.0e-5f64 } else { c.parscale[ps + i] = 0.01f64 }
        i += 1usize
    }
    ps += ng
    i = 0usize
    while i < sp.p + sp.q {
        c.parscale[ps + i] = 0.1f64
        i += 1usize
    }
    // BATS stale gamma-bold block: 0.001 at the period starts
    if !sp.tb {
        var off = 0usize
        i = 0usize
        while i < ns {
            c.gbs[off] = 0.001f64
            off += usize(sp.per[i])
            i += 1usize
        }
    }
    var pr: BPars = zero
    bf_unpack(&sp, v0, &pr)
    // y tilde: errors of the starting model from zero states
    var yv: []const f64 = y
    if sp.bc {
        i = 0usize
        while i < n {
            c.ty[i] = bf_bc(y[i], pr.lam)
            i += 1usize
        }
        yv = c.ty
    }
    bf_build(&c, &pr, false)
    bf_dmat(&c)
    bf_run(&c, yv, c.x0)
    let ytil = bf_alloc(ar, n)
    i = 0usize
    while i < n {
        ytil[i] = c.er[i]
        i += 1usize
    }
    // w tilde rows: w, w D, w D D, ...
    let wt = bf_alloc(ar, n * d)
    i = 0usize
    while i < d {
        wt[i] = c.w[i]
        i += 1usize
    }
    var t = 1usize
    while t < n {
        var j = 0usize
        while j < d {
            var acc = 0.0f64
            var ii = 0usize
            while ii < d {
                acc += wt[(t - 1usize) * d + ii] * c.dm[ii * d + j]
                ii += 1usize
            }
            wt[t * d + j] = acc
            j += 1usize
        }
        t += 1usize
    }
    // the columns kept for the regression
    let cols = alloc_usize(ar, d)
    i = 0usize
    while i < d {
        cols[i] = i
        i += 1usize
    }
    var cur = d
    let mask = bf_alloc(ar, ns + 1usize)
    if !sp.tb && ns > 0usize {
        var ii = ns
        while ii > 1usize {
            var j = 1usize
            while j <= ii - 1usize {
                if usize(sp.per[ii - 1usize]) % usize(sp.per[j - 1usize]) == 0usize { mask[j - 1usize] = 1.0f64 }
                j += 1usize
            }
            ii -= 1usize
        }
        if ns > 1usize {
            var s = ns
            while s >= 2usize {
                var j = s - 1usize
                while j >= 1usize {
                    let hcf = bf_gcd(usize(sp.per[s - 1usize]), usize(sp.per[j - 1usize]))
                    if hcf != 1usize && mask[s - 1usize] != 1.0f64 && mask[j - 1usize] != 1.0f64 { mask[s - 1usize] = 0.0f64 - f64(hcf) }
                    j -= 1usize
                }
                s -= 1usize
            }
        }
        var wpos = 1i64
        if sp.beta { wpos = 2i64 }
        var si = 0usize
        while si < ns {
            let s = i64(usize(sp.per[si]))
            let m = i64(mask[si])
            if m == 1i64 {
                cur = bf_rm(cols, cur, wpos + 1i64, wpos + s)
            } else if m < 0i64 {
                wpos = wpos + s
                cur = bf_rm(cols, cur, wpos + m + 1i64, wpos)
                wpos = wpos + m
            } else {
                wpos = wpos + s
                cur = bf_rm(cols, cur, wpos, wpos)
                wpos = wpos - 1i64
            }
            si += 1usize
        }
    }
    if sp.p + sp.q > 0usize {
        let e1 = i64(cur)
        cur = bf_rm(cols, cur, e1 - i64(sp.p + sp.q) + 1i64, e1)
    }
    let xm = bf_alloc(ar, n * cur)
    var cc = 0usize
    while cc < cur {
        t = 0usize
        while t < n {
            xm[cc * n + t] = wt[t * d + cols[cc]]
            t += 1usize
        }
        cc += 1usize
    }
    let (lf, le) = decomp.lm_fit(ar, xm, n, cur, ytil, 1.0e-7f64)
    if le != ok { ret out }
    let coefs = lf.coef
    let x0 = bf_alloc(ar, d)
    if !sp.tb && ns > 0usize {
        var pos = 0usize
        var xpos = 1i64
        x0[pos] = coefs[0usize]
        pos += 1usize
        if sp.beta {
            xpos = 2i64
            x0[pos] = coefs[1usize]
            pos += 1usize
        }
        var si = 0usize
        while si < ns {
            let s = i64(usize(sp.per[si]))
            let m = i64(mask[si])
            if m == 1i64 {
                var z = 0i64
                while z < s {
                    x0[pos] = 0.0f64
                    pos += 1usize
                    z = z + 1i64
                }
            } else if m < 0i64 {
                let cnt = s + m
                let kv2 = bf_alloc(ar, usize(cnt))
                var z = 0i64
                while z < cnt {
                    kv2[usize(z)] = coefs[usize(xpos + 1i64 + z - 1i64)]
                    z = z + 1i64
                }
                let kk = bf_lsum(kv2)
                z = 0i64
                while z < cnt {
                    x0[pos] = coefs[usize(xpos + 1i64 + z - 1i64)] - kk / f64(s)
                    pos += 1usize
                    z = z + 1i64
                }
                z = 0i64
                while z < 0i64 - m {
                    x0[pos] = 0.0f64 - kk / f64(s)
                    pos += 1usize
                    z = z + 1i64
                }
                xpos = xpos + cnt
            } else {
                let cnt = s - 1i64
                let kv2 = bf_alloc(ar, usize(cnt))
                var z = 0i64
                while z < cnt {
                    kv2[usize(z)] = coefs[usize(xpos + 1i64 + z - 1i64)]
                    z = z + 1i64
                }
                let kk = bf_lsum(kv2)
                z = 0i64
                while z < cnt {
                    x0[pos] = coefs[usize(xpos + 1i64 + z - 1i64)] - kk / f64(s)
                    pos += 1usize
                    z = z + 1i64
                }
                x0[pos] = 0.0f64 - kk / f64(s)
                pos += 1usize
                xpos = xpos + cnt
            }
            si += 1usize
        }
    } else {
        i = 0usize
        while i < cur {
            x0[i] = coefs[i]
            i += 1usize
        }
    }
    // optimisation
    i = 0usize
    while i < d {
        c.x0[i] = x0[i]
        i += 1usize
    }
    if sp.bc {
        i = 0usize
        while i < d {
            c.x0u[i] = bf_ibc(x0[i], pr.lam)
            i += 1usize
        }
    }
    let start = bf_alloc(ar, np)
    i = 0usize
    while i < np {
        start[i] = v0[i] / c.parscale[i]
        i += 1usize
    }
    let f0 = bf_obj(&c, start)
    if !bf_finite(f0) { ret out }
    let best = bf_alloc(ar, np)
    var fmin = 0.0f64
    var code = 0usize
    if np > 1usize {
        let st1 = mem.mark(ar)
        let (fm, cnt, fail) = rn.nmmin[BCtx](ar, &c, bf_obj, start, 0.0f64 - bf_inf(), 1.4901161193847656e-8f64, 1.0f64, 0.5f64, 2.0f64, 100usize * np * np, 1.0f64, best)
        mem.reset(ar, st1)
        fmin = fm
        code = fail
    } else {
        i = 0usize
        while i < np {
            best[i] = start[i]
            i += 1usize
        }
        let st1 = mem.mark(ar)
        fmin = rb.vmmin[BCtx](ar, &c, bf_obj, bf_grad, best, 1.4901161193847656e-8f64, 100usize)
        mem.reset(ar, st1)
        if c.bad { ret out }
    }
    i = 0usize
    while i < np {
        c.full[i] = best[i] * c.parscale[i]
        i += 1usize
    }
    let par = bf_alloc(ar, np)
    i = 0usize
    while i < np {
        par[i] = c.full[i]
        i += 1usize
    }
    bf_unpack(&sp, par, &pr)
    var xf = bf_alloc(ar, d)
    if sp.bc {
        i = 0usize
        while i < d {
            xf[i] = bf_bc(c.x0u[i], pr.lam)
            i += 1usize
        }
        i = 0usize
        while i < n {
            c.ty[i] = bf_bc(y[i], pr.lam)
            i += 1usize
        }
        yv = c.ty
    } else {
        i = 0usize
        while i < d {
            xf[i] = x0[i]
            i += 1usize
        }
        yv = y
    }
    bf_build(&c, &pr, false)
    bf_run(&c, yv, xf)
    let sse = bf_ssq(c.er)
    let variance = sse / f64(n)
    out.fitted = bf_alloc(ar, n)
    out.errors = bf_alloc(ar, n)
    out.x = bf_alloc(ar, d * n)
    i = 0usize
    while i < n {
        out.errors[i] = c.er[i]
        if sp.bc { out.fitted[i] = bf_ibc_adj(c.yh[i], pr.lam, biasadj, variance) } else { out.fitted[i] = c.yh[i] }
        i += 1usize
    }
    i = 0usize
    while i < d * n {
        out.x[i] = c.st[i]
        i += 1usize
    }
    out.good = true
    out.sp = sp
    out.loglik = fmin
    out.code = code
    out.variance = variance
    out.n = n
    out.d = d
    out.biasadj = biasadj
    out.lam = pr.lam
    out.alpha = pr.alpha
    out.beta = pr.beta
    out.phi = pr.phi
    out.gam = bf_alloc(ar, ng)
    i = 0usize
    while i < ng {
        out.gam[i] = pr.gam[i]
        i += 1usize
    }
    out.arc = bf_alloc(ar, sp.p)
    i = 0usize
    while i < sp.p {
        out.arc[i] = pr.arc[i]
        i += 1usize
    }
    out.mac = bf_alloc(ar, sp.q)
    i = 0usize
    while i < sp.q {
        out.mac[i] = pr.mac[i]
        i += 1usize
    }
    out.npar = np
    out.seed = xf
    out.aic = fmin + 2.0f64 * f64(np + d)
    ret out
}

fn alloc_usize(ar: *mem.Arena, n: usize) -> []usize {
    let (v, e) = mem.alloc[usize](ar, n + 1usize)
    var i = 0usize
    while i < n + 1usize {
        v[i] = 0usize
        i += 1usize
    }
    ret v[0usize..n]
}

fn bf_spec(tb: bool, bcf: bool, tr: bool, dp: bool, per: []f64, kv: []usize, p: usize, q: usize, lo: f64, hi: f64) -> BSpec {
    var sp: BSpec = zero
    sp.tb = tb
    sp.bc = bcf
    sp.beta = tr
    sp.damp = dp && tr
    sp.per = per
    sp.kv = kv
    sp.p = p
    sp.q = q
    sp.lo = lo
    sp.hi = hi
    ret sp
}

// auto.arima(errors, d = 0)$arma[1:2]; false when it cannot be fitted
fn bf_arma_orders(ar: *mem.Arena, errors: []const f64) -> (usize, usize, bool) {
    let (res, e) = aa.auto_arima_d(ar, errors, 1usize, true, 0usize, 0usize, 0usize, true)
    if e != ok { ret (0usize, 0usize, false) }
    ret (res.p, res.q, true)
}

// the tri-state options of bats and tbats: 0 NULL (both), 1 FALSE, 2 TRUE
fn bf_has(mode: usize, v: bool) -> bool {
    if mode == 0usize { ret true }
    if v { ret mode == 2usize }
    ret mode == 1usize
}

// filterSpecifics of bats.R
fn bf_filter_bats(ar: *mem.Arena, y: []const f64, bcf: bool, tr: bool, dp: bool, per: []f64, arma: bool, lo: f64, hi: f64, lam0: f64, biasadj: bool) -> BatsFit {
    var none: BatsFit = zero
    none.good = false
    none.aic = bf_inf()
    if !tr && dp { ret none }
    var kv0: []usize = alloc_usize(ar, 0usize)
    var perc = per
    var first = bf_fit(ar, y, bf_spec(false, bcf, tr, dp, perc, kv0, 0usize, 0usize, lo, hi), lam0, biasadj)
    if !first.good { ret none }
    if per.len > 0usize {
        let e0 = bf_alloc(ar, 0usize)
        let non = bf_fit(ar, y, bf_spec(false, bcf, tr, dp, e0, kv0, 0usize, 0usize, lo, hi), lam0, biasadj)
        if !non.good { ret none }
        if first.aic > non.aic {
            perc = e0
            first = non
        }
    }
    if arma {
        let (p, q, good) = bf_arma_orders(ar, first.errors)
        if !good { ret none }
        if p != 0usize || q != 0usize {
            let second = bf_fit(ar, y, bf_spec(false, bcf, tr, dp, perc, kv0, p, q, lo, hi), lam0, biasadj)
            if !second.good { ret none }
            if second.aic < first.aic { ret second }
        }
    }
    ret first
}

fn bf_pmax_unique(ar: *mem.Arena, per_in: []const f64) -> []f64 {
    let tmp = bf_alloc(ar, per_in.len)
    var cnt = 0usize
    var i = 0usize
    while i < per_in.len {
        var v = per_in[i]
        if v < 1.0f64 { v = 1.0f64 }
        var dup = false
        var j = 0usize
        while j < cnt {
            if tmp[j] == v { dup = true }
            j += 1usize
        }
        if !dup {
            tmp[cnt] = v
            cnt += 1usize
        }
        i += 1usize
    }
    var allone = true
    i = 0usize
    while i < cnt {
        if tmp[i] != 1.0f64 { allone = false }
        i += 1usize
    }
    if allone { cnt = 0usize }
    ret tmp[0usize..cnt]
}

// bats(y, ...): per the resolved seasonal periods (the periods are truncated to integers as fitSpecificBATS does), freq the frequency of the ts
// (for the Guerrero lambda); bcm, trm, dpm the tri-state use.box.cox, use.trend, use.damped.trend (0 NULL, 1 FALSE, 2 TRUE)
fn bats_fit(ar: *mem.Arena, y: []const f64, freq: usize, per_in: []const f64, bcm0: usize, trm: usize, dpm: usize, arma: bool, lo: f64, hi: f64, biasadj: bool) -> BatsFit {
    var none: BatsFit = zero
    none.good = false
    none.aic = bf_inf()
    let per0 = bf_pmax_unique(ar, per_in)
    let per = bf_alloc(ar, per0.len)
    var i = 0usize
    while i < per0.len {
        per[i] = math.floor[f64](per0[i])
        i += 1usize
    }
    // sort ascending
    i = 0usize
    while i < per.len {
        var j = i + 1usize
        while j < per.len {
            if per[j] < per[i] {
                let tmp = per[i]
                per[i] = per[j]
                per[j] = tmp
            }
            j += 1usize
        }
        i += 1usize
    }
    var bcm = bcm0
    i = 0usize
    while i < y.len {
        if y[i] <= 0.0f64 { bcm = 1usize }
        i += 1usize
    }
    var lam0 = 1.0f64
    if bcm != 1usize {
        let work = bf_alloc(ar, y.len + 8usize)
        lam0 = fcast.guerrero(y, freq, lo, hi, work)
    }
    var dpm2 = dpm
    if trm == 1usize { dpm2 = 1usize }
    var best: BatsFit = none
    var bi = 0usize
    while bi < 2usize {
        let bcv = bi == 1usize
        if bf_has(bcm, bcv) {
            var ti = 0usize
            while ti < 2usize {
                let trv = ti == 1usize
                if bf_has(trm, trv) {
                    var di = 0usize
                    while di < 2usize {
                        let dpv = di == 1usize
                        if bf_has(dpm2, dpv) {
                            let cm = bf_filter_bats(ar, y, bcv, trv, dpv, per, arma, lo, hi, lam0, biasadj)
                            if cm.good && cm.aic < best.aic { best = cm }
                        }
                        di += 1usize
                    }
                }
                ti += 1usize
            }
        }
        bi += 1usize
    }
    ret best
}

fn bt_fit(ar: *mem.Arena, y: []const f64, per: []f64, kv: []const usize, bcf: bool, tr: bool, dp: bool, p: usize, q: usize, lam0: f64, lo: f64, hi: f64, biasadj: bool) -> BatsFit {
    let kc = alloc_usize(ar, kv.len)
    var i = 0usize
    while i < kv.len {
        kc[i] = kv[i]
        i += 1usize
    }
    ret bf_fit(ar, y, bf_spec(true, bcf, tr, dp, per, kc, p, q, lo, hi), lam0, biasadj)
}

fn bt_failed() -> BatsFit {
    var none: BatsFit = zero
    none.good = false
    none.aic = bf_inf()
    ret none
}

// R's x %% y for doubles
fn bf_rmod(x: f64, y: f64) -> f64 {
    let q = x / y
    let tmp = x - math.floor[f64](q) * y
    ret tmp - math.floor[f64](tmp / y) * y
}

// filterTBATSSpecifics
fn bt_filter(ar: *mem.Arena, y: []const f64, per: []f64, kv: []const usize, bcf: bool, tr: bool, dp: bool, arma: bool, have_aux: bool, aux: BatsFit, lam0: f64, lo: f64, hi: f64, biasadj: bool) -> BatsFit {
    var first = aux
    if !have_aux { first = bt_fit(ar, y, per, kv, bcf, tr, dp, 0usize, 0usize, lam0, lo, hi, biasadj) }
    if arma && first.good {
        let (p, q, good) = bf_arma_orders(ar, first.errors)
        if good {
            if p != 0usize || q != 0usize {
                let second = bt_fit(ar, y, per, kv, bcf, tr, dp, p, q, lam0, lo, hi, biasadj)
                if second.aic < first.aic { ret second }
            }
        }
    }
    ret first
}

// tbats(y, ...) as bats_fit takes its arguments; the answer is the bats model when no period remains or when it has the lower AIC
fn tbats_fit(ar: *mem.Arena, y: []const f64, freq: usize, per_in: []const f64, bcm0: usize, trm: usize, dpm: usize, arma: bool, lo: f64, hi: f64, biasadj: bool) -> BatsFit {
    let per = bf_pmax_unique(ar, per_in)
    var bcm = bcm0
    var i = 0usize
    while i < y.len {
        if y[i] <= 0.0f64 { bcm = 1usize }
        i += 1usize
    }
    let e0 = bf_alloc(ar, 0usize)
    let nonseas = bats_fit(ar, y, 1usize, e0, bcm, trm, dpm, arma, lo, hi, biasadj)
    if per.len == 0usize { ret nonseas }
    var lam0 = 1.0f64
    if bcm != 1usize {
        let work = bf_alloc(ar, y.len + 8usize)
        lam0 = fcast.guerrero(y, freq, lo, hi, work)
    }
    var dpm2 = dpm
    if trm == 1usize { dpm2 = 1usize }
    let mp_bc = bcm != 1usize
    let mp_tr = trm != 1usize
    let mp_dp = bf_has(dpm2, true)
    let ns = per.len
    let kv = alloc_usize(ar, ns)
    i = 0usize
    while i < ns {
        kv[i] = 1usize
        i += 1usize
    }
    var best = bt_fit(ar, y, per, kv, mp_bc, mp_tr, mp_dp, 0usize, 0usize, lam0, lo, hi, biasadj)
    var ii = 0usize
    while ii < ns {
        if per[ii] == 2.0f64 {
            ii += 1usize
            continue
        }
        var maxk = i64(math.floor[f64]((per[ii] - 1.0f64) / 2.0f64))
        if ii != 0usize {
            var curk = 2i64
            while curk <= maxk {
                if bf_rmod(per[ii], f64(curk)) != 0.0f64 {
                    curk = curk + 1i64
                    continue
                }
                let latter = per[ii] / f64(curk)
                var anyd = false
                var j = 0usize
                while j < ii {
                    if bf_rmod(per[j], latter) == 0.0f64 { anyd = true }
                    j += 1usize
                }
                if anyd {
                    maxk = curk - 1i64
                    break
                } else {
                    curk = curk + 1i64
                }
            }
        }
        if maxk == 1i64 {
            ii += 1usize
            continue
        }
        if maxk <= 6i64 {
            kv[ii] = usize(maxk)
            best.aic = bf_inf()
            while true {
                let nm = bt_fit(ar, y, per, kv, mp_bc, mp_tr, mp_dp, 0usize, 0usize, lam0, lo, hi, biasadj)
                if nm.aic > best.aic {
                    kv[ii] = kv[ii] + 1usize
                    break
                } else {
                    if kv[ii] == 1usize { break }
                    kv[ii] = kv[ii] - 1usize
                    best = nm
                }
            }
            ii += 1usize
            continue
        }
        let ku = alloc_usize(ar, ns)
        let kd = alloc_usize(ar, ns)
        var jj = 0usize
        while jj < ns {
            ku[jj] = kv[jj]
            kd[jj] = kv[jj]
            jj += 1usize
        }
        ku[ii] = 7usize
        kd[ii] = 5usize
        kv[ii] = 6usize
        let upm = bt_fit(ar, y, per, ku, mp_bc, mp_tr, mp_dp, 0usize, 0usize, lam0, lo, hi, biasadj)
        let lvm = bt_fit(ar, y, per, kv, mp_bc, mp_tr, mp_dp, 0usize, 0usize, lam0, lo, hi, biasadj)
        let dnm = bt_fit(ar, y, per, kd, mp_bc, mp_tr, mp_dp, 0usize, 0usize, lam0, lo, hi, biasadj)
        var mn = upm.aic
        if lvm.aic < mn { mn = lvm.aic }
        if dnm.aic < mn { mn = dnm.aic }
        if mn == dnm.aic {
            best = dnm
            kv[ii] = 5usize
            while true {
                kv[ii] = kv[ii] - 1usize
                let dn2 = bt_fit(ar, y, per, kv, mp_bc, mp_tr, mp_dp, 0usize, 0usize, lam0, lo, hi, biasadj)
                if dn2.aic > best.aic {
                    kv[ii] = kv[ii] + 1usize
                    break
                } else {
                    best = dn2
                }
                if kv[ii] == 1usize { break }
            }
        } else if mn == lvm.aic {
            best = lvm
        } else {
            best = upm
            kv[ii] = 7usize
            while true {
                kv[ii] = kv[ii] + 1usize
                let up2 = bt_fit(ar, y, per, kv, mp_bc, mp_tr, mp_dp, 0usize, 0usize, lam0, lo, hi, biasadj)
                if up2.aic > best.aic {
                    kv[ii] = kv[ii] - 1usize
                    break
                } else {
                    best = up2
                }
                if i64(kv[ii]) == maxk { break }
            }
        }
        ii += 1usize
    }
    let aux = best
    if nonseas.aic < best.aic { best = nonseas }
    var newm = bt_failed()
    var bi = 0usize
    while bi < 2usize {
        let bcv = bi == 1usize
        if bf_has(bcm, bcv) {
            var ti = 0usize
            while ti < 2usize {
                let trv = ti == 1usize
                if bf_has(trm, trv) {
                    var di = 0usize
                    while di < 2usize {
                        let dpv = di == 1usize
                        if bf_has(dpm2, dpv) {
                            if bcv == mp_bc && trv == mp_tr && dpv == mp_dp {
                                newm = bt_filter(ar, y, per, kv, bcv, trv, dpv, arma, true, aux, lam0, lo, hi, biasadj)
                            } else if trv || !dpv {
                                newm = bt_filter(ar, y, per, kv, bcv, trv, dpv, arma, false, aux, lam0, lo, hi, biasadj)
                            }
                            if newm.aic < best.aic { best = newm }
                        }
                        di += 1usize
                    }
                }
                ti += 1usize
            }
        }
        bi += 1usize
    }
    ret best
}

// forecast.bats / forecast.tbats at h steps and one level (percent): the point forecasts and the limits, back-transformed
fn bats_forecast(ar: *mem.Arena, f: *const BatsFit, h: usize, level: f64, mean: []f64, lower: []f64, upper: []f64) {
    let sp = f.sp
    let d = f.d
    let n = f.n
    var c: BCtx = zero
    c.ar = ar
    c.sp = sp
    c.n = n
    c.d = d
    c.ssz = bf_sumper(&sp)
    c.w = bf_alloc(ar, d)
    c.g = bf_alloc(ar, d)
    c.fm = bf_alloc(ar, d * d)
    c.gbs = bf_alloc(ar, c.ssz + 1usize)
    c.gbf = bf_alloc(ar, c.ssz + 1usize)
    var pr: BPars = zero
    pr.lam = f.lam
    pr.alpha = f.alpha
    pr.phi = f.phi
    pr.beta = f.beta
    pr.gam = f.gam
    pr.arc = f.arc
    pr.mac = f.mac
    bf_build(&c, &pr, false)
    if sp.tb {
        // forecast.tbats passes object$beta.v (NULL): g loses its trend entry and the gamma block starts one row early
        var adj = 0usize
        if sp.beta { adj = 1usize }
        var i = 0usize
        while i < d {
            c.g[i] = 0.0f64
            i += 1usize
        }
        c.g[0usize] = pr.alpha
        i = 0usize
        while i < c.ssz {
            c.g[1usize + i] = c.gbf[i]
            i += 1usize
        }
        if sp.p > 0usize { c.g[adj + c.ssz + 1usize] = 1.0f64 }
        if sp.q > 0usize { c.g[adj + c.ssz + sp.p + 1usize] = 1.0f64 }
    }
    let xs = bf_alloc(ar, d * h)
    let yf = bf_alloc(ar, h)
    let xl = f.x[(n - 1usize) * d..n * d]
    var acc = 0.0f64
    var j = 0usize
    while j < d {
        if c.w[j] != 0.0f64 { acc += c.w[j] * xl[j] }
        j += 1usize
    }
    yf[0usize] = acc
    bf_step(&c, xl, 0.0f64, xs[0usize..d])
    var t = 1usize
    while t < h {
        bf_step(&c, xs[(t - 1usize) * d..t * d], 0.0f64, xs[t * d..(t + 1usize) * d])
        acc = 0.0f64
        j = 0usize
        while j < d {
            if c.w[j] != 0.0f64 { acc += c.w[j] * xs[(t - 1usize) * d + j] }
            j += 1usize
        }
        yf[t] = acc
        t += 1usize
    }
    let vm = bf_alloc(ar, h)
    vm[0usize] = 1.0f64
    let run = bf_alloc(ar, d * d)
    let tmp = bf_alloc(ar, d * d)
    var jj = 1usize
    while jj < h {
        if jj == 1usize {
            var a = 0usize
            while a < d * d {
                run[a] = 0.0f64
                a += 1usize
            }
            a = 0usize
            while a < d {
                run[a * d + a] = 1.0f64
                a += 1usize
            }
        } else {
            var a = 0usize
            while a < d {
                var b = 0usize
                while b < d {
                    var s = 0.0f64
                    var k = 0usize
                    while k < d {
                        s += run[a * d + k] * c.fm[k * d + b]
                        k += 1usize
                    }
                    tmp[a * d + b] = s
                    b += 1usize
                }
                a += 1usize
            }
            a = 0usize
            while a < d * d {
                run[a] = tmp[a]
                a += 1usize
            }
        }
        // c.j = w running g
        var cj = 0.0f64
        var b = 0usize
        while b < d {
            var s = 0.0f64
            var a = 0usize
            while a < d {
                s += c.w[a] * run[a * d + b]
                a += 1usize
            }
            cj += s * c.g[b]
            b += 1usize
        }
        vm[jj] = vm[jj - 1usize] + cj * cj
        jj += 1usize
    }
    var zq = dist.qnorm((100.0f64 - level) / 200.0f64, 0.0f64, 1.0f64, true, false)
    zq = math.abs[f64](zq)
    t = 0usize
    while t < h {
        let vr = f.variance * vm[t]
        let sd = math.sqrt[f64](vr)
        var lw = yf[t] - zq * sd
        var up = yf[t] + zq * sd
        var mn = yf[t]
        if sp.bc {
            mn = bf_ibc_adj(yf[t], f.lam, f.biasadj, vr)
            lw = bf_ibc(lw, f.lam)
            if f.lam < 1.0f64 {
                if lw < 0.0f64 { lw = 0.0f64 }
            }
            up = bf_ibc(up, f.lam)
        }
        mean[t] = mn
        lower[t] = lw
        upper[t] = up
        t += 1usize
    }
}
