// R nnet::multinom with case weights and weight decay (the penalty decay * sum of squared coefficients added to the negative log-likelihood; the deviance returned is twice that objective, as multinom reports): the multinomial logit by Newton's method (R runs BFGS on the same likelihood, so the two agree to R's reltol). Class 0 is the reference; the coefficients are the K - 1 rows for classes 1 .. K - 1, p columns each (row-major).
//
// Not here: the hidden-layer networks of nnet, softmax and censored responses.

use e.algo.stat.gparot as gp
use e.math
use e.mem
use e.algo.stat.rbfgs as bf

// returns the deviance, -2 log-likelihood (NaN if the Hessian is singular); iterations in it
fn multinom(a: *mem.Arena, x: []const f64, cls: []const f64, n: usize, p: usize, nk: usize, decay: f64, wts: []const f64, coef: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let q = (nk - 1usize) * p
    let (gr, e1) = mem.alloc[f64](a, q)
    let (h, e2) = mem.alloc[f64](a, q * q)
    let (pr, e3) = mem.alloc[f64](a, nk)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    var i = 0usize
    while i < q {
        coef[i] = 0.0f64
        i += 1usize
    }
    var dev = 0.0f64
    var it = 0usize
    while it < 100usize {
        let start = mem.mark(a)
        i = 0usize
        while i < q {
            gr[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < q * q {
            h[i] = 0.0f64
            i += 1usize
        }
        dev = 0.0f64
        var t = 0usize
        while t < n {
            var mx = 0.0f64
            var k = 1usize
            while k < nk {
                var eta = 0.0f64
                var c = 0usize
                while c < p {
                    eta += coef[(k - 1usize) * p + c] * x[t * p + c]
                    c += 1usize
                }
                pr[k] = eta
                if eta > mx { mx = eta }
                k += 1usize
            }
            pr[0usize] = 0.0f64
            var s = 0.0f64
            k = 0usize
            while k < nk {
                pr[k] = math.exp[f64](pr[k] - mx)
                s += pr[k]
                k += 1usize
            }
            k = 0usize
            while k < nk {
                pr[k] = pr[k] / s
                k += 1usize
            }
            let yc = usize(cls[t])
            dev -= 2.0f64 * wts[t] * math.log[f64](pr[yc])
            k = 1usize
            while k < nk {
                var d = 0.0f64
                if yc == k { d = 1.0f64 }
                var c = 0usize
                while c < p {
                    gr[(k - 1usize) * p + c] += wts[t] * (d - pr[k]) * x[t * p + c]
                    var l = 1usize
                    while l < nk {
                        var dl = 0.0f64
                        if l == k { dl = 1.0f64 }
                        var c2 = 0usize
                        while c2 < p {
                            h[((k - 1usize) * p + c) * q + (l - 1usize) * p + c2] += wts[t] * pr[k] * (dl - pr[l]) * x[t * p + c] * x[t * p + c2]
                            c2 += 1usize
                        }
                        l += 1usize
                    }
                    c += 1usize
                }
                k += 1usize
            }
            t += 1usize
        }
        i = 0usize
        while i < q {
            gr[i] -= 2.0f64 * decay * coef[i]
            h[i * q + i] += 2.0f64 * decay
            i += 1usize
        }
        let (inv, ie) = gp.invert(a, h, q)
        if ie != ok { ret nan }
        var step = 0.0f64
        i = 0usize
        while i < q {
            var d = 0.0f64
            var j = 0usize
            while j < q {
                d += inv[i * q + j] * gr[j]
                j += 1usize
            }
            coef[i] += d
            if math.abs[f64](d) > step { step = math.abs[f64](d) }
            i += 1usize
        }
        mem.reset(a, start)
        it += 1usize
        if step < 1.0e-12f64 { break }
    }
    // deviance at the final coefficients
    var t = 0usize
    dev = 0.0f64
    while t < n {
        var mx = 0.0f64
        var k = 1usize
        while k < nk {
            var eta = 0.0f64
            var c = 0usize
            while c < p {
                eta += coef[(k - 1usize) * p + c] * x[t * p + c]
                c += 1usize
            }
            pr[k] = eta
            if eta > mx { mx = eta }
            k += 1usize
        }
        pr[0usize] = 0.0f64
        var s = 0.0f64
        k = 0usize
        while k < nk {
            pr[k] = math.exp[f64](pr[k] - mx)
            s += pr[k]
            k += 1usize
        }
        dev -= 2.0f64 * wts[t] * math.log[f64](pr[usize(cls[t])] / s)
        t += 1usize
    }
    var pen = 0.0f64
    i = 0usize
    while i < q {
        pen += coef[i] * coef[i]
        i += 1usize
    }
    ret dev + 2.0f64 * decay * pen
}

// nnet() for a single linear response with one hidden layer of logistic units (linout = TRUE, no skip-layer): sum of squares plus decay times the squared weights, fitted by optim's BFGS
// (nnet's own vmmin is that algorithm: verified against optim(method = "BFGS") to 1e-12 in R) from weights given by the caller (R draws runif(nwts, -rang, rang)). The weights run unit by unit,
// each hidden unit as bias then the p inputs, then the output as bias, the hidden units and (with skip) the p inputs; the hidden activation is clamped at +-15 as nnet's C code does.
type NetCtx = struct { x: []const f64, y: []const f64, w: []const f64, n: usize, p: usize, h: usize, decay: f64, skip: bool }

fn net_hidden(c: *NetCtx, wts: []const f64, t: usize, hid: []f64) -> f64 {
    var j = 0usize
    while j < c.h {
        let base = j * (c.p + 1usize)
        var s = wts[base]
        var k = 0usize
        while k < c.p {
            s += wts[base + 1usize + k] * c.x[t * c.p + k]
            k += 1usize
        }
        var sg = 1.0f64
        if s < -15.0f64 { sg = 0.0f64 } else if s <= 15.0f64 { sg = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - s)) }
        hid[j] = sg
        j += 1usize
    }
    let ob = c.h * (c.p + 1usize)
    var o = wts[ob]
    let hoff = ob + 1usize
    j = 0usize
    while j < c.h {
        o += wts[hoff + j] * hid[j]
        j += 1usize
    }
    if c.skip {
        var k = 0usize
        while k < c.p {
            o += wts[hoff + c.h + k] * c.x[t * c.p + k]
            k += 1usize
        }
    }
    ret o
}

fn net_f(c: *NetCtx, wts: []const f64) -> f64 {
    var hid: [64]f64 = zero
    var e = 0.0f64
    var t = 0usize
    while t < c.n {
        let o = net_hidden(c, wts, t, hid[0usize..64usize])
        e += c.w[t] * (o - c.y[t]) * (o - c.y[t])
        t += 1usize
    }
    var pen = 0.0f64
    var i = 0usize
    while i < wts.len {
        pen += wts[i] * wts[i]
        i += 1usize
    }
    ret e + c.decay * pen
}

fn net_g(c: *NetCtx, wts: []const f64, g: []f64) {
    var hid: [64]f64 = zero
    var i = 0usize
    while i < wts.len {
        g[i] = 2.0f64 * c.decay * wts[i]
        i += 1usize
    }
    let ob = c.h * (c.p + 1usize)
    let hoff = ob + 1usize
    var t = 0usize
    while t < c.n {
        let o = net_hidden(c, wts, t, hid[0usize..64usize])
        let d = 2.0f64 * c.w[t] * (o - c.y[t])
        g[ob] += d
        if c.skip {
            var k = 0usize
            while k < c.p {
                g[hoff + c.h + k] += d * c.x[t * c.p + k]
                k += 1usize
            }
        }
        var j = 0usize
        while j < c.h {
            g[hoff + j] += d * hid[j]
            let dh = d * wts[hoff + j] * hid[j] * (1.0f64 - hid[j])
            let base = j * (c.p + 1usize)
            g[base] += dh
            var k = 0usize
            while k < c.p {
                g[base + 1usize + k] += dh * c.x[t * c.p + k]
                k += 1usize
            }
            j += 1usize
        }
        t += 1usize
    }
}

// fit: wts holds the start values and receives the solution; the answer is the objective value; fitted receives the outputs
fn nnet_fit(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, n: usize, p: usize, h: usize, skip: bool, decay: f64, maxit: usize, reltol: f64, abstol: f64, wts: []f64, fitted: []f64) -> f64 {
    var c = NetCtx { x: x, y: y, w: w, n: n, p: p, h: h, decay: decay, skip: skip }
    let v = bf.vmmin_abs[NetCtx](a, &c, net_f, net_g, wts, reltol, maxit, abstol)
    var hid: [64]f64 = zero
    var t = 0usize
    while t < n {
        fitted[t] = net_hidden(&c, wts, t, hid[0usize..64usize])
        t += 1usize
    }
    ret v
}
