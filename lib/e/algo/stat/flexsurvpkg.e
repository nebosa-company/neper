// R flexsurv flexsurvreg for the parametric families weibull, exponential, lognormal, loglogistic and gompertz with covariates on the location parameter (scale, rate, meanlog): the maximum-likelihood estimates on flexsurv's transformed scale (res.t) and the log-likelihood, by Newton's method with central-difference derivatives of the exact log-likelihood and step halving.
//
// Not here: covariates on ancillary parameters, the generalised gamma and F, splines (flexsurvspline), standard errors, hazard and survival predictions, cure models.

use e.algo.stat.gparot as gp
use e.math
use e.math.dist as dist
use e.mem

// model 0 weibull (par: log shape, log scale), 1 exponential (log rate), 2 lognormal (meanlog, log sdlog), 3 loglogistic (log shape, log scale), 4 gompertz (shape, log rate); par then continues with one coefficient per covariate, all on the location parameter
fn loglik(model: usize, t: []const f64, d: []const f64, x: []const f64, n: usize, k: usize, par: []const f64) -> f64 {
    var ll = 0.0f64
    var i = 0usize
    var base = 2usize
    if model == 1usize { base = 1usize }
    while i < n {
        var xb = 0.0f64
        var c = 0usize
        while c < k {
            xb += par[base + c] * x[i * k + c]
            c += 1usize
        }
        let y = t[i]
        let ev = d[i] > 0.5f64
        if model == 0usize {
            let sh = math.exp[f64](par[0usize])
            let sc = math.exp[f64](par[1usize] + xb)
            let z = math.pow[f64](y / sc, sh)
            ll -= z
            if ev { ll += math.log[f64](sh / y) + sh * math.log[f64](y / sc) }
        }
        if model == 1usize {
            let rt = math.exp[f64](par[0usize] + xb)
            ll -= rt * y
            if ev { ll += math.log[f64](rt) }
        }
        if model == 2usize {
            let ml = par[0usize] + xb
            let sd = math.exp[f64](par[1usize])
            let zz = (math.log[f64](y) - ml) / sd
            if ev { ll += dist.dnorm(math.log[f64](y), ml, sd, true) - math.log[f64](y) } else { ll += dist.pnorm(zz, 0.0f64, 1.0f64, false, true) }
        }
        if model == 3usize {
            let sh = math.exp[f64](par[0usize])
            let sc = math.exp[f64](par[1usize] + xb)
            let z = math.pow[f64](y / sc, sh)
            ll -= math.log[f64](1.0f64 + z)
            if ev { ll += math.log[f64](sh / sc) + (sh - 1.0f64) * math.log[f64](y / sc) - math.log[f64](1.0f64 + z) }
        }
        if model == 4usize {
            let a = par[0usize]
            let b = math.exp[f64](par[1usize] + xb)
            var cum = b * y
            if math.abs[f64](a) > 1.0e-12f64 { cum = b / a * (math.exp[f64](a * y) - 1.0f64) }
            ll -= cum
            if ev { ll += math.log[f64](b) + a * y }
        }
        i += 1usize
    }
    ret ll
}

// par receives the estimates (length q); returns the log-likelihood
fn fit(a: *mem.Arena, model: usize, t: []const f64, d: []const f64, x: []const f64, n: usize, k: usize, par: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    var q = 2usize + k
    if model == 1usize { q = 1usize + k }
    let (gr, e1) = mem.alloc[f64](a, q)
    let (h, e2) = mem.alloc[f64](a, q * q)
    let (tr, e3) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    var mt = 0.0f64
    var ml = 0.0f64
    var ne = 0.0f64
    var i = 0usize
    while i < n {
        mt += t[i] / f64(n)
        ml += math.log[f64](t[i]) / f64(n)
        ne += d[i]
        i += 1usize
    }
    i = 0usize
    while i < q {
        par[i] = 0.0f64
        i += 1usize
    }
    if model == 0usize || model == 3usize { par[1usize] = math.log[f64](mt) }
    if model == 1usize { par[0usize] = math.log[f64](ne / (mt * f64(n))) }
    if model == 2usize { par[0usize] = ml }
    if model == 4usize {
        par[0usize] = 0.01f64
        par[1usize] = math.log[f64](ne / (mt * f64(n)))
    }
    var ll = loglik(model, t, d, x, n, k, par)
    var it = 0usize
    while it < 200usize {
        let hs = 1.0e-4f64
        i = 0usize
        while i < q {
            let o = par[i]
            par[i] = o + hs
            let fp = loglik(model, t, d, x, n, k, par)
            par[i] = o - hs
            let fm = loglik(model, t, d, x, n, k, par)
            par[i] = o
            gr[i] = (fp - fm) / (2.0f64 * hs)
            h[i * q + i] = (fp - 2.0f64 * ll + fm) / (hs * hs)
            var j = 0usize
            while j < i {
                let oj = par[j]
                par[i] = o + hs
                par[j] = oj + hs
                let a1 = loglik(model, t, d, x, n, k, par)
                par[j] = oj - hs
                let a2 = loglik(model, t, d, x, n, k, par)
                par[i] = o - hs
                let a4 = loglik(model, t, d, x, n, k, par)
                par[j] = oj + hs
                let a3 = loglik(model, t, d, x, n, k, par)
                par[i] = o
                par[j] = oj
                let v = (a1 - a2 - a3 + a4) / (4.0f64 * hs * hs)
                h[i * q + j] = v
                h[j * q + i] = v
                j += 1usize
            }
            i += 1usize
        }
        let (hi, ie) = gp.invert(a, h, q)
        // an ascent direction: Newton's when its dot product with the gradient is positive, else a scaled gradient
        var newton_ok = false
        if ie == ok {
            var dot = 0.0f64
            i = 0usize
            while i < q {
                var l = 0usize
                while l < q {
                    dot -= gr[i] * hi[i * q + l] * gr[l]
                    l += 1usize
                }
                i += 1usize
            }
            newton_ok = dot > 0.0f64
        }
        var hmax = 1.0f64
        i = 0usize
        while i < q {
            if math.abs[f64](h[i * q + i]) > hmax { hmax = math.abs[f64](h[i * q + i]) }
            i += 1usize
        }
        var scale = 1.0f64
        var moved = false
        var tries = 0usize
        while tries < 40usize {
            i = 0usize
            while i < q {
                var dd = 0.0f64
                if newton_ok {
                    var l = 0usize
                    while l < q {
                        dd += hi[i * q + l] * gr[l]
                        l += 1usize
                    }
                    dd = 0.0f64 - dd
                } else {
                    dd = gr[i] / hmax
                }
                tr[i] = par[i] + scale * dd
                i += 1usize
            }
            let l2 = loglik(model, t, d, x, n, k, tr)
            if l2 == l2 && l2 > ll - 1.0e-13f64 {
                var ch = 0.0f64
                i = 0usize
                while i < q {
                    if math.abs[f64](tr[i] - par[i]) > ch { ch = math.abs[f64](tr[i] - par[i]) }
                    par[i] = tr[i]
                    i += 1usize
                }
                ll = l2
                moved = true
                if ch < 1.0e-10f64 { ret ll }
                break
            }
            scale = scale / 2.0f64
            tries += 1usize
        }
        if !moved { break }
        it += 1usize
    }
    ret ll
}
