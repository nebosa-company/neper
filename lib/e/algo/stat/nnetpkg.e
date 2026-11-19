// R nnet::multinom with case weights and weight decay; se receives the standard errors summary.multinom gives (square roots of the inverse information matrix at the penalised fit, without the penalty term) (the penalty decay * sum of squared coefficients added to the negative log-likelihood; the deviance returned is twice that objective, as multinom reports): the multinomial logit by Newton's method (R runs BFGS on the same likelihood, so the two agree to R's reltol). Class 0 is the reference; the coefficients are the K - 1 rows for classes 1 .. K - 1, p columns each (row-major).
//
// Not here: the hidden-layer networks of nnet, softmax and censored responses.

use e.algo.stat.gparot as gp
use e.math
use e.mem
use e.algo.stat.rbfgs as bf

// returns the deviance, -2 log-likelihood (NaN if the Hessian is singular); iterations in it
fn multinom(a: *mem.Arena, x: []const f64, cls: []const f64, n: usize, p: usize, nk: usize, decay: f64, wts: []const f64, coef: []f64, se: []f64) -> f64 {
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
        // summary.multinom takes the standard errors from the Hessian of the likelihood part alone (nnetHess leaves the decay penalty out)
        let (inv0, ie0) = gp.invert(a, h, q)
        if ie0 == ok {
            var dg = 0usize
            while dg < q {
                se[dg] = math.sqrt[f64](inv0[dg * q + dg])
                dg += 1usize
            }
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

// nnet() with one hidden layer of logistic units and k outputs: mode 0 linear outputs with squared error (linout = TRUE), 1 logistic outputs with squared error, 2 logistic outputs with
// the cross-entropy (entropy = TRUE), 3 softmax outputs with the cross-entropy; optional skip-layer connections, case weights and decay times the squared weights. The fit is optim's BFGS
// (nnet's own vmmin is that algorithm: verified against optim(method = "BFGS") to 1e-12 in R) from weights given by the caller (R draws runif(nwts, -rang, rang)). The weights run unit by unit:
// each hidden unit as bias then the p inputs, then each output unit as bias, the hidden units and (with skip) the p inputs. The hidden activation is clamped at +-15 as nnet's C code does.
type NetCtx = struct { x: []const f64, y: []const f64, w: []const f64, n: usize, p: usize, h: usize, k: usize, mode: usize, decay: f64, skip: bool }

fn net_out_size(c: *NetCtx) -> usize {
    var s = 1usize + c.h
    if c.skip { s += c.p }
    ret s
}

// the k outputs (after the output activation) of observation t into out; hid receives the hidden activations
fn net_forward(c: *NetCtx, wts: []const f64, t: usize, hid: []f64, out: []f64) {
    var j = 0usize
    while j < c.h {
        let base = j * (c.p + 1usize)
        var s = wts[base]
        var q = 0usize
        while q < c.p {
            s += wts[base + 1usize + q] * c.x[t * c.p + q]
            q += 1usize
        }
        var sg = 1.0f64
        if s < -15.0f64 { sg = 0.0f64 } else if s <= 15.0f64 { sg = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - s)) }
        hid[j] = sg
        j += 1usize
    }
    let ob = c.h * (c.p + 1usize)
    let os = net_out_size(c)
    var mx = -1.0e300f64
    var o = 0usize
    while o < c.k {
        let b = ob + o * os
        var v = wts[b]
        j = 0usize
        while j < c.h {
            v += wts[b + 1usize + j] * hid[j]
            j += 1usize
        }
        if c.skip {
            var q = 0usize
            while q < c.p {
                v += wts[b + 1usize + c.h + q] * c.x[t * c.p + q]
                q += 1usize
            }
        }
        out[o] = v
        if v > mx { mx = v }
        o += 1usize
    }
    if c.mode == 3usize {
        var sum = 0.0f64
        o = 0usize
        while o < c.k {
            out[o] = math.exp[f64](out[o] - mx)
            sum += out[o]
            o += 1usize
        }
        o = 0usize
        while o < c.k {
            out[o] = out[o] / sum
            o += 1usize
        }
    } else if c.mode != 0usize {
        o = 0usize
        while o < c.k {
            var sg = 1.0f64
            let v = out[o]
            if v < -15.0f64 { sg = 0.0f64 } else if v <= 15.0f64 { sg = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - v)) }
            out[o] = sg
            o += 1usize
        }
    }
}

// the logarithm nnet uses in its entropy terms: the argument is floored at 1e-80
fn net_log(v: f64) -> f64 {
    if v < 1.0e-80f64 { ret math.log[f64](1.0e-80f64) }
    ret math.log[f64](v)
}

fn net_f(c: *NetCtx, wts: []const f64) -> f64 {
    var hid: [64]f64 = zero
    var out: [16]f64 = zero
    var e = 0.0f64
    var t = 0usize
    while t < c.n {
        net_forward(c, wts, t, hid[0usize..64usize], out[0usize..16usize])
        var o = 0usize
        while o < c.k {
            let tg = c.y[t * c.k + o]
            if c.mode <= 1usize {
                e += c.w[t] * (out[o] - tg) * (out[o] - tg)
            } else if c.mode == 2usize {
                e -= c.w[t] * (tg * net_log(out[o]) + (1.0f64 - tg) * net_log(1.0f64 - out[o]))
            } else {
                e -= c.w[t] * tg * net_log(out[o])
            }
            o += 1usize
        }
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
    var out: [16]f64 = zero
    var dl: [16]f64 = zero
    var i = 0usize
    while i < wts.len {
        g[i] = 2.0f64 * c.decay * wts[i]
        i += 1usize
    }
    let ob = c.h * (c.p + 1usize)
    let os = net_out_size(c)
    var t = 0usize
    while t < c.n {
        net_forward(c, wts, t, hid[0usize..64usize], out[0usize..16usize])
        var o = 0usize
        while o < c.k {
            let tg = c.y[t * c.k + o]
            if c.mode == 0usize {
                dl[o] = 2.0f64 * c.w[t] * (out[o] - tg)
            } else if c.mode == 1usize {
                dl[o] = 2.0f64 * c.w[t] * (out[o] - tg) * out[o] * (1.0f64 - out[o])
            } else {
                dl[o] = c.w[t] * (out[o] - tg)
            }
            o += 1usize
        }
        if c.mode == 3usize {
            var st = 0.0f64
            o = 0usize
            while o < c.k {
                st += c.y[t * c.k + o]
                o += 1usize
            }
            o = 0usize
            while o < c.k {
                dl[o] = c.w[t] * (out[o] * st - c.y[t * c.k + o])
                o += 1usize
            }
        }
        o = 0usize
        while o < c.k {
            let b = ob + o * os
            g[b] += dl[o]
            var j = 0usize
            while j < c.h {
                g[b + 1usize + j] += dl[o] * hid[j]
                j += 1usize
            }
            if c.skip {
                var q = 0usize
                while q < c.p {
                    g[b + 1usize + c.h + q] += dl[o] * c.x[t * c.p + q]
                    q += 1usize
                }
            }
            o += 1usize
        }
        var j = 0usize
        while j < c.h {
            var back = 0.0f64
            o = 0usize
            while o < c.k {
                back += dl[o] * wts[ob + o * os + 1usize + j]
                o += 1usize
            }
            let dh = back * hid[j] * (1.0f64 - hid[j])
            let base = j * (c.p + 1usize)
            g[base] += dh
            var q = 0usize
            while q < c.p {
                g[base + 1usize + q] += dh * c.x[t * c.p + q]
                q += 1usize
            }
            j += 1usize
        }
        t += 1usize
    }
}

// fit: wts holds the start values and receives the solution; the answer is the objective value; fitted (n by k, row-major) receives the outputs
fn nnet_fit(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, n: usize, p: usize, h: usize, k: usize, mode: usize, skip: bool, decay: f64, maxit: usize, reltol: f64, abstol: f64, wts: []f64, fitted: []f64) -> f64 {
    var c = NetCtx { x: x, y: y, w: w, n: n, p: p, h: h, k: k, mode: mode, decay: decay, skip: skip }
    let v = bf.vmmin_abs[NetCtx](a, &c, net_f, net_g, wts, reltol, maxit, abstol)
    var hid: [64]f64 = zero
    var out: [16]f64 = zero
    var t = 0usize
    while t < n {
        net_forward(&c, wts, t, hid[0usize..64usize], out[0usize..16usize])
        var o = 0usize
        while o < k {
            fitted[t * k + o] = out[o]
            o += 1usize
        }
        t += 1usize
    }
    ret v
}
