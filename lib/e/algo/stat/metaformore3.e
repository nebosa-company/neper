// R metafor fsn: the Fisher pooling of Rosenthal's fail-safe N and the "General" (rma-based) fail-safe N, with R's uniroot (extendInt "upX" and "downX", then R_zeroin2) and R's rnorm
// stream (set.seed, then one rnorm(fsnum) per evaluation of .fsn.gen, rescaled by .fsn.scale), the approximate branch and the exact refit of rma, with and without a target.
//
// Not here: the verbose output, fsnum above 5000 refits with a Ws beyond memory (the refit allocates (k + fsnum)^2 doubles per evaluation), type General on a model with user weights.

use e.math
use e.mem
use e.math.dist as dist
use e.math.nmath as nm
use e.algo.rand.r as rr
use e.algo.stat.metaforrma as mr
use e.algo.stat.metaformore as mm
use e.algo.stat.metaformore2 as m2
use e.algo.stat.metaforfit as mf

const X0: usize = 136usize

// kind 0 .fsn.fisher over pi, kind 1 .fsn.gen
type Gen = struct {
    m: *mm.Mod, rng: *rr.Rng, kind: usize, pi: []const f64, vt: f64, est: f64, tau2: f64, hastgt: bool, tgt: f64, alpha: f64, mumiss: f64, maxint: f64, exact: bool,
    last_est: f64, last_tau2: f64, last_pval: f64, failed: bool
}

// a workspace for up to n studies and one coefficient
fn ws_big(a: *mem.Arena, n: usize) -> (mr.Ws, err) {
    var z: mr.Ws = zero
    let pm = mr.PMAX
    let (w, e0) = mem.alloc[f64](a, n)
    let (ymc, e1) = mem.alloc[f64](a, n)
    let (py, e2) = mem.alloc[f64](a, n)
    let (res, e3) = mem.alloc[f64](a, n)
    let (xs, e4) = mem.alloc[f64](a, n * pm)
    let (pmat, e5) = mem.alloc[f64](a, n * n)
    let (s, e6) = mem.alloc[f64](a, pm * pm)
    let (aug, e7) = mem.alloc[f64](a, 2usize * pm * pm)
    let (b, e8) = mem.alloc[f64](a, pm)
    let (tmp, e9) = mem.alloc[f64](a, pm * pm)
    let (wfe, e10) = mem.alloc[f64](a, n)
    let (ya, e11) = mem.alloc[f64](a, n)
    let (xa, e12) = mem.alloc[f64](a, n * pm)
    let (sub, e13) = mem.alloc[f64](a, pm * pm)
    let (sub2, e14) = mem.alloc[f64](a, pm * pm)
    let (o2, e15) = mem.alloc[f64](a, mr.OUTLEN)
    let (big, e16) = mem.alloc[f64](a, 4usize * pm * pm)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (z, e0) }
    if e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok { ret (z, e9) }
    z.w = w
    z.ymc = ymc
    z.py = py
    z.res = res
    z.xs = xs
    z.pm = pmat
    z.s = s
    z.aug = aug
    z.b = b
    z.tmp = tmp
    z.wfe = wfe
    z.ya = ya
    z.xa = xa
    z.sub = sub
    z.sub2 = sub2
    z.o2 = o2
    z.big = big
    z.ar = a
    ret (z, ok)
}

// .fsn.scale(rnorm(n), n) * sd + mu into d (n draws)
fn scaled_draws(rng: *rr.Rng, n: usize, sd: f64, mu: f64, d: []f64) {
    if n == 0usize { ret }
    if n == 1usize {
        d[0usize] = 0.0f64 * sd + mu
        ret
    }
    let nf = f64(n)
    var i = 0usize
    var s = 0.0f64
    while i < n {
        d[i] = rr.norm(rng)
        s += d[i]
        i += 1usize
    }
    var mean = s / nf
    var t = 0.0f64
    i = 0usize
    while i < n {
        t += d[i] - mean
        i += 1usize
    }
    mean += t / nf
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (d[i] - mean) * (d[i] - mean)
        i += 1usize
    }
    let sdev = math.sqrt[f64](ss / (nf - 1.0f64))
    i = 0usize
    while i < n {
        d[i] = ((d[i] - mean) / sdev) * sd + mu
        i += 1usize
    }
}

// .fsn.gen: the difference to zero (pval - alpha, or est - target) and, in g.last_*, the new estimate, tau2 and p-value
fn gen_eval(g: *Gen, x: f64) -> f64 {
    var fs = math.floor[f64](x)
    if fs > g.maxint { fs = g.maxint }
    let n = usize(fs)
    let m = g.m
    let k = m.k
    let kf = f64(k)
    let kn = k + n
    let start = mem.mark(m.a)
    let (yn, e1) = mem.alloc[f64](m.a, kn)
    let (vn, e2) = mem.alloc[f64](m.a, kn)
    if e1 != ok || e2 != ok {
        g.failed = true
        ret mr.nan()
    }
    var i = 0usize
    while i < k {
        yn[i] = m.y[i]
        vn[i] = m.v[i]
        i += 1usize
    }
    scaled_draws(g.rng, n, math.sqrt[f64](g.vt + g.tau2), g.mumiss, yn[k..kn])
    i = 0usize
    while i < n {
        vn[k + i] = g.vt
        i += 1usize
    }
    var est_fsn = 0.0f64
    var tau2_fsn = 0.0f64
    var pval_fsn = 0.0f64
    let nf = fs
    if g.exact && n <= 5000usize {
        let (xcol, e3) = mem.alloc[f64](m.a, kn)
        let (ws0, e4) = ws_big(m.a, kn)
        if e3 != ok || e4 != ok {
            g.failed = true
            mem.reset(m.a, start)
            ret mr.nan()
        }
        var ws = ws0
        i = 0usize
        while i < kn {
            xcol[i] = 1.0f64
            i += 1usize
        }
        var c = m.c
        c.skipr2 = true
        c.aw = m.c.aw[0usize..0usize]
        mf.fit(&ws, yn, vn, xcol, kn, 1usize, &c, m.tmp)
        est_fsn = m.tmp[mr.O_BETA]
        tau2_fsn = m.tmp[mr.O_TAU2]
        pval_fsn = m.tmp[mr.O_P]
        if est_fsn != est_fsn { g.failed = true }
        if g.hastgt == false && g.mumiss != 0.0f64 && m2.sgn(est_fsn) == m2.sgn(g.mumiss) { pval_fsn = 1.0f64 }
    } else {
        if m.c.method == 0usize {
            tau2_fsn = 0.0f64
        } else {
            est_fsn = (kf * g.est + nf * g.mumiss) / (kf + nf)
            if m.c.tau2fix != m.c.tau2fix {
                var extra = 0.0f64
                if nf - 1.0f64 > 0.0f64 { extra = nf - 1.0f64 }
                tau2_fsn = ((kf - 1.0f64) * g.tau2 + extra * g.tau2 + kf * (g.est - est_fsn) * (g.est - est_fsn) + nf * (g.mumiss - est_fsn) * (g.mumiss - est_fsn)) / (kf + nf - 1.0f64)
                if g.hastgt == false && tau2_fsn < 0.0f64 { tau2_fsn = 0.0f64 }
            } else {
                tau2_fsn = g.tau2
            }
        }
        var zval = 0.0f64
        if m.c.weighted {
            var sw = 0.0f64
            var swy = 0.0f64
            i = 0usize
            while i < kn {
                let wi = 1.0f64 / (vn[i] + tau2_fsn)
                sw += wi
                swy += yn[i] * wi
                i += 1usize
            }
            est_fsn = swy / sw
            var sv = 0.0f64
            i = 0usize
            while i < k {
                sv += 1.0f64 / (m.v[i] + tau2_fsn)
                i += 1usize
            }
            zval = est_fsn / math.sqrt[f64](1.0f64 / (sv + nf / (g.vt + tau2_fsn)))
        } else {
            var sy = 0.0f64
            i = 0usize
            while i < kn {
                sy += yn[i]
                i += 1usize
            }
            est_fsn = sy / f64(kn)
            var sv = 0.0f64
            i = 0usize
            while i < k {
                sv += m.v[i] + tau2_fsn
                i += 1usize
            }
            zval = f64(kn) * est_fsn / math.sqrt[f64](sv + nf * (g.vt + tau2_fsn))
        }
        pval_fsn = 2.0f64 * dist.pnorm(math.abs[f64](zval), 0.0f64, 1.0f64, false, false)
        if g.hastgt == false && g.mumiss != 0.0f64 && m2.sgn(est_fsn * g.mumiss) == 1.0f64 { pval_fsn = 1.0f64 }
    }
    mem.reset(m.a, start)
    g.last_est = est_fsn
    g.last_tau2 = tau2_fsn
    g.last_pval = pval_fsn
    if g.hastgt {
        if fs == g.maxint { ret 0.0f64 }
        ret est_fsn - g.tgt
    }
    if fs == g.maxint { ret 0.0f64 }
    ret pval_fsn - g.alpha
}

// .fsn.fisher
fn fisher_eval(g: *Gen, x: f64) -> f64 {
    let k = g.pi.len
    var s = 0.0f64
    var i = 0usize
    while i < k {
        s += math.log[f64](g.pi[i])
        i += 1usize
    }
    let reps = usize(x)
    let lh = math.log[f64](0.5f64)
    i = 0usize
    while i < reps {
        s += lh
        i += 1usize
    }
    ret nm.pchisq(0.0f64 - 2.0f64 * s, 2.0f64 * (f64(k) + x), false, false) - g.alpha
}

fn f_of(g: *Gen, x: f64) -> f64 {
    if g.kind == 0usize { ret fisher_eval(g, x) }
    ret gen_eval(g, x)
}

fn trunc_big(x: f64) -> f64 {
    let big = 1.7976931348623157e308f64
    if x > big { ret big }
    if x < 0.0f64 - big { ret 0.0f64 - big }
    ret x
}

// R_zeroin2 with f(lower) and f(upper) given
fn zeroin2(g: *Gen, lower: f64, upper: f64, flo: f64, fup: f64, tol: f64, maxit: i64) -> f64 {
    let eps = 2.220446049250313e-16f64
    var a = lower
    var b = upper
    var c = a
    var fa = flo
    var fb = fup
    var fc = fa
    if fa == 0.0f64 { ret a }
    if fb == 0.0f64 { ret b }
    var left = maxit + 1i64
    while left > 0i64 {
        left -= 1i64
        let prev = b - a
        if math.abs[f64](fc) < math.abs[f64](fb) {
            a = b
            b = c
            c = a
            fa = fb
            fb = fc
            fc = fa
        }
        let tol_act = 2.0f64 * eps * math.abs[f64](b) + tol / 2.0f64
        var step = (c - b) / 2.0f64
        if math.abs[f64](step) <= tol_act || fb == 0.0f64 { ret b }
        if math.abs[f64](prev) >= tol_act && math.abs[f64](fa) > math.abs[f64](fb) {
            let cb = c - b
            var pp = 0.0f64
            var qq = 0.0f64
            if a == c {
                let t1 = fb / fa
                pp = cb * t1
                qq = 1.0f64 - t1
            } else {
                qq = fa / fc
                let t1 = fb / fc
                let t2 = fb / fa
                pp = t2 * (cb * qq * (qq - t1) - (b - a) * (t1 - 1.0f64))
                qq = (qq - 1.0f64) * (t1 - 1.0f64) * (t2 - 1.0f64)
            }
            if pp > 0.0f64 { qq = 0.0f64 - qq } else { pp = 0.0f64 - pp }
            if pp < (0.75f64 * cb * qq - math.abs[f64](tol_act * qq) / 2.0f64) && pp < math.abs[f64](prev * qq / 2.0f64) { step = pp / qq }
        }
        if math.abs[f64](step) < tol_act {
            if step > 0.0f64 { step = tol_act } else { step = 0.0f64 - tol_act }
        }
        a = b
        fa = fb
        b += step
        fb = f_of(g, b)
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            c = a
            fc = fa
        }
    }
    ret b
}

fn delta_of(u: f64) -> f64 {
    var a = math.abs[f64](u)
    if a < 1.0e-4f64 { a = 1.0e-4f64 }
    ret 0.01f64 * a
}

// uniroot(f, c(lower, upper), extendInt = "upX" (sig 1) or "downX" (sig -1), tol, maxiter)$root, then the f(root) evaluation that uniroot's result list makes; false when R would stop
fn uniroot_ext(g: *Gen, lower0: f64, upper0: f64, sig: f64, tol: f64, maxiter: i64) -> (f64, bool) {
    var lower = lower0
    var upper = upper0
    var flo = f_of(g, lower)
    var fup = f_of(g, upper)
    if flo != flo || fup != fup || g.failed { ret (0.0f64, false) }
    let dox = sig * trunc_big(flo) > 0.0f64 || sig * trunc_big(fup) < 0.0f64
    var it = 0i64
    if dox {
        var delta = delta_of(lower)
        while sig * flo > 0.0f64 {
            it += 1i64
            if it > maxiter { ret (0.0f64, false) }
            lower -= delta
            flo = f_of(g, lower)
            delta = 2.0f64 * delta
        }
        delta = delta_of(upper)
        while sig * fup < 0.0f64 {
            it += 1i64
            if it > maxiter { ret (0.0f64, false) }
            upper += delta
            fup = f_of(g, upper)
            delta = 2.0f64 * delta
        }
    }
    if g.failed { ret (0.0f64, false) }
    if !(m2.sgn(flo) * m2.sgn(fup) <= 0.0f64) { ret (0.0f64, false) }
    let root = zeroin2(g, lower, upper, trunc_big(flo), trunc_big(fup), tol, maxiter)
    let _ = f_of(g, root)
    ret (root, !g.failed)
}

// fsn on the model fitted into m.out; kind 0 Rosenthal (pool 0 Stouffer, 1 Fisher), 4 General, the others as in metaformore2.fsn;
// out[X0 ..]: fsnum, pval, target, est, tau2, est.fsn, tau2.fsn, pval.fsn
fn fsn2(m: *mm.Mod, kind: usize, alpha: f64, tgt0: f64, pool: usize, exact0: bool, mumiss: f64, seed: f64, maxint: f64) {
    let k = m.k
    let kf = f64(k)
    let o = m.out
    var j = 3usize
    if kind != 4usize && !(kind == 0usize && pool == 1usize) {
        m2.fsn(m.y, m.v, k, kind, alpha, tgt0, o)
        while j < 8usize {
            o[X0 + j] = mr.nan()
            j += 1usize
        }
        ret
    }
    var rng: rr.Rng = zero
    rr.seed(&rng, i64(seed))
    var g: Gen = zero
    g.m = m
    g.rng = &rng
    g.alpha = alpha
    g.mumiss = mumiss
    g.maxint = maxint
    g.hastgt = tgt0 == tgt0
    g.tgt = tgt0
    let tol = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    let hi = kf * 50.0f64
    var fsnum = 0.0f64
    var tgt = mr.nan()
    var pval = mr.nan()
    var est = mr.nan()
    var tau2 = mr.nan()
    var estf = mr.nan()
    var tau2f = mr.nan()
    var pvalf = mr.nan()
    if kind == 0usize {
        let (pis, e1) = mem.alloc[f64](m.a, k)
        if e1 != ok { ret }
        var i = 0usize
        while i < k {
            pis[i] = dist.pnorm(math.abs[f64](m.y[i] / math.sqrt[f64](m.v[i])), 0.0f64, 1.0f64, false, false)
            i += 1usize
        }
        g.kind = 0usize
        g.pi = pis
        g.alpha = 0.0f64
        pval = fisher_eval(&g, 0.0f64)
        g.alpha = alpha
        if pval >= alpha {
            fsnum = 0.0f64
        } else {
            let (root, good) = uniroot_ext(&g, 0.0f64, hi, 1.0f64, tol, 1000i64)
            if !good {
                o[X0] = mr.nan()
                o[X0 + 1usize] = pval
                o[X0 + 2usize] = mr.nan()
                while j < 8usize {
                    o[X0 + j] = mr.nan()
                    j += 1usize
                }
                ret
            }
            fsnum = root
        }
        fsnum = m2.rnd_fsn(fsnum)
    } else {
        g.kind = 1usize
        g.exact = exact0 || m.c.test != 0usize
        var mi = 0.0f64
        var i = 0usize
        while i < k {
            mi += 1.0f64 / m.v[i]
            i += 1usize
        }
        g.vt = 1.0f64 / (mi / kf)
        est = o[mr.O_BETA]
        tau2 = o[mr.O_TAU2]
        pval = o[mr.O_P]
        g.est = est
        g.tau2 = tau2
        var go = false
        var sig = 1.0f64
        if g.hastgt {
            tgt = tgt0
            if m2.sgn(tgt) != m2.sgn(est) { tgt = 0.0f64 - tgt }
            g.tgt = tgt
            if tgt == 0.0f64 {
                fsnum = 1.0f64 / 0.0f64
            } else if math.abs[f64](tgt) >= math.abs[f64](est) {
                fsnum = 0.0f64
            } else {
                go = true
                if est > 0.0f64 { sig = 0.0f64 - 1.0f64 }
            }
        } else {
            if pval >= alpha { fsnum = 0.0f64 } else { go = true }
        }
        if go {
            let (root, good) = uniroot_ext(&g, 0.0f64, hi, sig, tol, 1000i64)
            if !good {
                o[X0] = mr.nan()
                o[X0 + 1usize] = pval
                o[X0 + 2usize] = tgt
                o[X0 + 3usize] = est
                o[X0 + 4usize] = tau2
                while j < 8usize {
                    o[X0 + j] = mr.nan()
                    j += 1usize
                }
                ret
            }
            fsnum = root
            if fsnum > maxint { fsnum = maxint }
            fsnum = m2.rnd_fsn(fsnum)
            let _ = gen_eval(&g, fsnum)
            estf = g.last_est
            tau2f = g.last_tau2
            pvalf = g.last_pval
        }
        if fsnum == 0.0f64 {
            estf = est
            tau2f = tau2
            pvalf = pval
        }
    }
    o[X0] = fsnum
    o[X0 + 1usize] = pval
    o[X0 + 2usize] = tgt
    o[X0 + 3usize] = est
    o[X0 + 4usize] = tau2
    o[X0 + 5usize] = estf
    o[X0 + 6usize] = tau2f
    o[X0 + 7usize] = pvalf
}
