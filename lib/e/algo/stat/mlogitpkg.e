// R mlogit: the conditional (multinomial) logit of discrete choice with alternative-specific covariates sharing one coefficient each and optional alternative-specific constants (the first alternative is the reference), fitted by Newton's method on the exact Hessian; coefficients, standard errors and the log-likelihood.
//
// Not here: individual-specific covariates with alternative-specific coefficients, nested and mixed logit, probit, rank-ordered data, heteroskedastic and generalised extreme value models.

use e.algo.stat.gparot as gp
use e.math
use e.mem

// x is n choosers by j alternatives by k covariates (row-major in that order); ch[i] is the chosen alternative (0-based); out = coefficients (q), standard errors (q), log-likelihood, q = (asc ? j - 1 : 0) + k
fn clogit(a: *mem.Arena, x: []const f64, ch: []const f64, n: usize, j: usize, k: usize, asc: bool, out: []f64) -> err {
    var na = 0usize
    if asc { na = j - 1usize }
    let q = na + k
    let (b, e1) = mem.alloc[f64](a, q)
    let (gr, e2) = mem.alloc[f64](a, q)
    let (h, e3) = mem.alloc[f64](a, q * q)
    let (z, e4) = mem.alloc[f64](a, j * q)
    let (pr, e5) = mem.alloc[f64](a, j)
    let (zb, e6) = mem.alloc[f64](a, q)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    var i = 0usize
    while i < q {
        b[i] = 0.0f64
        i += 1usize
    }
    var ll = 0.0f64
    var it = 0usize
    while it < 100usize {
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
        ll = 0.0f64
        var c = 0usize
        while c < n {
            var mx = 0.0f64 - 1.0e300f64
            var a2 = 0usize
            while a2 < j {
                var q2 = 0usize
                while q2 < q {
                    var zv = 0.0f64
                    if q2 < na {
                        if a2 > 0usize && q2 == a2 - 1usize { zv = 1.0f64 }
                    } else {
                        zv = x[(c * j + a2) * k + q2 - na]
                    }
                    z[a2 * q + q2] = zv
                    q2 += 1usize
                }
                var v = 0.0f64
                q2 = 0usize
                while q2 < q {
                    v += b[q2] * z[a2 * q + q2]
                    q2 += 1usize
                }
                pr[a2] = v
                if v > mx { mx = v }
                a2 += 1usize
            }
            var s = 0.0f64
            a2 = 0usize
            while a2 < j {
                pr[a2] = math.exp[f64](pr[a2] - mx)
                s += pr[a2]
                a2 += 1usize
            }
            a2 = 0usize
            while a2 < j {
                pr[a2] = pr[a2] / s
                a2 += 1usize
            }
            let yi = usize(ch[c])
            ll += math.log[f64](pr[yi])
            var q2 = 0usize
            while q2 < q {
                var m = 0.0f64
                a2 = 0usize
                while a2 < j {
                    m += pr[a2] * z[a2 * q + q2]
                    a2 += 1usize
                }
                zb[q2] = m
                gr[q2] += z[yi * q + q2] - m
                q2 += 1usize
            }
            a2 = 0usize
            while a2 < j {
                q2 = 0usize
                while q2 < q {
                    var q3 = 0usize
                    while q3 < q {
                        h[q2 * q + q3] += pr[a2] * (z[a2 * q + q2] - zb[q2]) * (z[a2 * q + q3] - zb[q3])
                        q3 += 1usize
                    }
                    q2 += 1usize
                }
                a2 += 1usize
            }
            c += 1usize
        }
        let (hi, ie) = gp.invert(a, h, q)
        if ie != ok { ret ie }
        var step = 0.0f64
        i = 0usize
        while i < q {
            var d = 0.0f64
            var l = 0usize
            while l < q {
                d += hi[i * q + l] * gr[l]
                l += 1usize
            }
            b[i] += d
            if math.abs[f64](d) > step { step = math.abs[f64](d) }
            i += 1usize
        }
        it += 1usize
        if step < 1.0e-13f64 { break }
    }
    // standard errors and the log-likelihood at the final coefficients: refresh them with one more pass
    ll = 0.0f64
    i = 0usize
    while i < q * q {
        h[i] = 0.0f64
        i += 1usize
    }
    var c = 0usize
    while c < n {
        var mx = 0.0f64 - 1.0e300f64
        var a2 = 0usize
        while a2 < j {
            var q2 = 0usize
            while q2 < q {
                var zv = 0.0f64
                if q2 < na {
                    if a2 > 0usize && q2 == a2 - 1usize { zv = 1.0f64 }
                } else {
                    zv = x[(c * j + a2) * k + q2 - na]
                }
                z[a2 * q + q2] = zv
                q2 += 1usize
            }
            var v = 0.0f64
            q2 = 0usize
            while q2 < q {
                v += b[q2] * z[a2 * q + q2]
                q2 += 1usize
            }
            pr[a2] = v
            if v > mx { mx = v }
            a2 += 1usize
        }
        var s = 0.0f64
        a2 = 0usize
        while a2 < j {
            pr[a2] = math.exp[f64](pr[a2] - mx)
            s += pr[a2]
            a2 += 1usize
        }
        a2 = 0usize
        while a2 < j {
            pr[a2] = pr[a2] / s
            a2 += 1usize
        }
        ll += math.log[f64](pr[usize(ch[c])])
        var q2 = 0usize
        while q2 < q {
            var m = 0.0f64
            a2 = 0usize
            while a2 < j {
                m += pr[a2] * z[a2 * q + q2]
                a2 += 1usize
            }
            zb[q2] = m
            q2 += 1usize
        }
        a2 = 0usize
        while a2 < j {
            q2 = 0usize
            while q2 < q {
                var q3 = 0usize
                while q3 < q {
                    h[q2 * q + q3] += pr[a2] * (z[a2 * q + q2] - zb[q2]) * (z[a2 * q + q3] - zb[q3])
                    q3 += 1usize
                }
                q2 += 1usize
            }
            a2 += 1usize
        }
        c += 1usize
    }
    let (hf, fe) = gp.invert(a, h, q)
    if fe != ok { ret fe }
    i = 0usize
    while i < q {
        out[i] = b[i]
        out[q + i] = math.sqrt[f64](hf[i * q + i])
        i += 1usize
    }
    out[2usize * q] = ll
    ret ok
}
