// R afex aov_car / aov_ez, Type III, for any number of between factors (unequal cells allowed, sum-to-zero coding as afex) and within factors: the car::Anova multivariate-linear-model tests with Greenhouse-Geisser and Huynh-Feldt corrections, Mauchly's sphericity test and generalized eta squared. Pure between-subject designs are the case of no within factor.
//
// Not here: covariates, Type II tests, observed-variable eta squared, emmeans follow-ups.

use e.math
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

error Singular

fn bit_of(m: usize, f: usize) -> bool {
    var x = m
    var i = 0usize
    while i < f {
        x = x / 2usize
        i += 1usize
    }
    ret x % 2usize == 1usize
}

// Gauss-Jordan inverse of the n x n matrix m, in place; w is n * 2n scratch. false when singular.
fn invert(m: []f64, n: usize, w: []f64) -> bool {
    let n2 = 2usize * n
    var r = 0usize
    while r < n {
        var c = 0usize
        while c < n {
            w[r * n2 + c] = m[r * n + c]
            var v = 0.0f64
            if r == c { v = 1.0f64 }
            w[r * n2 + n + c] = v
            c += 1usize
        }
        r += 1usize
    }
    var col = 0usize
    while col < n {
        var piv = col
        r = col + 1usize
        while r < n {
            if math.abs[f64](w[r * n2 + col]) > math.abs[f64](w[piv * n2 + col]) { piv = r }
            r += 1usize
        }
        if w[piv * n2 + col] == 0.0f64 { ret false }
        if piv != col {
            var c = 0usize
            while c < n2 {
                let t = w[col * n2 + c]
                w[col * n2 + c] = w[piv * n2 + c]
                w[piv * n2 + c] = t
                c += 1usize
            }
        }
        let d = w[col * n2 + col]
        var c = 0usize
        while c < n2 {
            w[col * n2 + c] = w[col * n2 + c] / d
            c += 1usize
        }
        r = 0usize
        while r < n {
            if r != col {
                let f = w[r * n2 + col]
                c = 0usize
                while c < n2 {
                    w[r * n2 + c] -= f * w[col * n2 + c]
                    c += 1usize
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    r = 0usize
    while r < n {
        var c = 0usize
        while c < n {
            m[r * n + c] = w[r * n2 + n + c]
            c += 1usize
        }
        r += 1usize
    }
    ret true
}

fn helmert(lev: usize, c: usize) -> f64 {
    let nrm = math.sqrt[f64](f64((c + 1usize) * (c + 2usize)))
    if lev <= c { ret 1.0f64 / nrm }
    if lev == c + 1usize { ret 0.0f64 - f64(c + 1usize) / nrm }
    ret 0.0f64
}

// A row of data is: the 0-based level of each between factor, then prod(wl) responses with the first within factor varying fastest. Effects are indexed by the bit mask of their between factors s and within factors t: slot (s * 2^nwf + t) * 12 holds F, num df, den df, p, generalized eta squared, GG eps, HF eps (uncapped), GG p, HF p, Mauchly W, Mauchly p, effect SS. Undefined slots are NaN: the intercept (0, 0), and the sphericity slots of within terms with one degree of freedom.
fn anova(a: *mem.Arena, data: []const f64, nsub: usize, nbf: usize, bl: []const usize, nwf: usize, wl: []const usize, out: []f64) -> err {
    let nan = 0.0f64 / 0.0f64
    var ks = 1usize
    var f = 0usize
    while f < nwf {
        ks *= wl[f]
        f += 1usize
    }
    var ns = 1usize
    f = 0usize
    while f < nbf {
        ns *= 2usize
        f += 1usize
    }
    var nt = 1usize
    f = 0usize
    while f < nwf {
        nt *= 2usize
        f += 1usize
    }
    let rowlen = nbf + ks
    let (cnt, ec) = mem.alloc[usize](a, ns)
    let (off, eo) = mem.alloc[usize](a, ns)
    if ec != ok { ret ec }
    if eo != ok { ret eo }
    var p = 0usize
    var s = 0usize
    while s < ns {
        var cs = 1usize
        f = 0usize
        while f < nbf {
            if bit_of(s, f) { cs *= bl[f] - 1usize }
            f += 1usize
        }
        cnt[s] = cs
        off[s] = p
        p += cs
        s += 1usize
    }
    let total = nsub * p + 3usize * p * p + 2usize * p * p + 2usize * p * ks + nsub * ks + 4usize * ks * ks + ns * p * p + p * ks
    let (buf, e0) = mem.alloc[f64](a, total + 16usize)
    if e0 != ok { ret e0 }
    var o = 0usize
    let x = buf[o..o + nsub * p]
    o += nsub * p
    let xtxi = buf[o..o + p * p]
    o += p * p
    let w2 = buf[o..o + 2usize * p * p]
    o += 2usize * p * p
    let xty = buf[o..o + p * ks]
    o += p * ks
    let bm = buf[o..o + p * ks]
    o += p * ks
    let res = buf[o..o + nsub * ks]
    o += nsub * ks
    let em = buf[o..o + ks * ks]
    o += ks * ks
    let pm = buf[o..o + ks * ks]
    o += ks * ks
    let tm = buf[o..o + ks * ks]
    o += ks * ks
    let ee = buf[o..o + ks * ks]
    o += ks * ks
    let mi = buf[o..o + ns * p * p]
    o += ns * p * p
    let hp = buf[o..o + p * ks]
    o += p * ks
    let mt = buf[o..o + p * p]
    var i = 0usize
    while i < out.len {
        out[i] = nan
        i += 1usize
    }
    // between design matrix
    i = 0usize
    while i < nsub {
        s = 0usize
        while s < ns {
            var m = 0usize
            while m < cnt[s] {
                var rem = m
                var val = 1.0f64
                f = 0usize
                while f < nbf {
                    if bit_of(s, f) {
                        let l = bl[f]
                        let c = rem % (l - 1usize)
                        rem = rem / (l - 1usize)
                        let lev = usize(data[i * rowlen + f])
                        var code = 0.0f64
                        if lev == c { code = 1.0f64 }
                        if lev == l - 1usize { code = -1.0f64 }
                        val *= code
                    }
                    f += 1usize
                }
                x[i * p + off[s] + m] = val
                m += 1usize
            }
            s += 1usize
        }
        i += 1usize
    }
    var r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var v = 0.0f64
            i = 0usize
            while i < nsub {
                v += x[i * p + r] * x[i * p + c]
                i += 1usize
            }
            xtxi[r * p + c] = v
            c += 1usize
        }
        var j = 0usize
        while j < ks {
            var v = 0.0f64
            i = 0usize
            while i < nsub {
                v += x[i * p + r] * data[i * rowlen + nbf + j]
                i += 1usize
            }
            xty[r * ks + j] = v
            j += 1usize
        }
        r += 1usize
    }
    if !invert(xtxi, p, w2) { ret Singular }
    r = 0usize
    while r < p {
        var j = 0usize
        while j < ks {
            var v = 0.0f64
            var l = 0usize
            while l < p {
                v += xtxi[r * p + l] * xty[l * ks + j]
                l += 1usize
            }
            bm[r * ks + j] = v
            j += 1usize
        }
        r += 1usize
    }
    i = 0usize
    while i < nsub {
        var j = 0usize
        while j < ks {
            var v = data[i * rowlen + nbf + j]
            var l = 0usize
            while l < p {
                v -= x[i * p + l] * bm[l * ks + j]
                l += 1usize
            }
            res[i * ks + j] = v
            j += 1usize
        }
        i += 1usize
    }
    var tre = 0.0f64
    r = 0usize
    while r < ks {
        var c = 0usize
        while c < ks {
            var v = 0.0f64
            i = 0usize
            while i < nsub {
                v += res[i * ks + r] * res[i * ks + c]
                i += 1usize
            }
            em[r * ks + c] = v
            c += 1usize
        }
        tre += em[r * ks + r]
        r += 1usize
    }
    // inverse of each term's block of (X'X)^-1
    s = 0usize
    while s < ns {
        let cs = cnt[s]
        r = 0usize
        while r < cs {
            var c = 0usize
            while c < cs {
                mt[r * cs + c] = xtxi[(off[s] + r) * p + off[s] + c]
                c += 1usize
            }
            r += 1usize
        }
        if !invert(mt[0usize..cs * cs], cs, w2) { ret Singular }
        r = 0usize
        while r < cs * cs {
            mi[s * p * p + r] = mt[r]
            r += 1usize
        }
        s += 1usize
    }
    let dfe = f64(nsub - p)
    var t = 0usize
    while t < nt {
        var q = 1usize
        f = 0usize
        while f < nwf {
            if bit_of(t, f) { q *= wl[f] - 1usize }
            f += 1usize
        }
        // orthonormal basis of the within term
        var m = 0usize
        while m < q {
            var j = 0usize
            while j < ks {
                var v = 1.0f64
                var rem = m
                var jr = j
                f = 0usize
                while f < nwf {
                    let l = wl[f]
                    let lev = jr % l
                    jr = jr / l
                    if bit_of(t, f) {
                        let c = rem % (l - 1usize)
                        rem = rem / (l - 1usize)
                        v *= helmert(lev, c)
                    } else {
                        v *= 1.0f64 / math.sqrt[f64](f64(l))
                    }
                    f += 1usize
                }
                pm[j * q + m] = v
                j += 1usize
            }
            m += 1usize
        }
        r = 0usize
        while r < ks {
            var c = 0usize
            while c < q {
                var v = 0.0f64
                var l = 0usize
                while l < ks {
                    v += em[r * ks + l] * pm[l * q + c]
                    l += 1usize
                }
                tm[r * q + c] = v
                c += 1usize
            }
            r += 1usize
        }
        r = 0usize
        while r < q {
            var c = 0usize
            while c < q {
                var v = 0.0f64
                var l = 0usize
                while l < ks {
                    v += pm[l * q + r] * tm[l * q + c]
                    l += 1usize
                }
                ee[r * q + c] = v
                c += 1usize
            }
            r += 1usize
        }
        var tr = 0.0f64
        var tr2 = 0.0f64
        r = 0usize
        while r < q {
            tr += ee[r * q + r]
            var c = 0usize
            while c < q {
                tr2 += ee[r * q + c] * ee[c * q + r]
                c += 1usize
            }
            r += 1usize
        }
        let qf = f64(q)
        var gg = nan
        var hfu = nan
        var hf = nan
        var wm = nan
        var pw = nan
        if q >= 2usize {
            gg = tr * tr / (qf * tr2)
            hfu = (dfe + 1.0f64) * qf * gg - 2.0f64
            hfu = hfu / (qf * (dfe - qf * gg))
            hf = hfu
            if hf > 1.0f64 { hf = 1.0f64 }
            var det = 1.0f64
            r = 0usize
            while r < q {
                var piv = r
                var c = r + 1usize
                while c < q {
                    if math.abs[f64](ee[c * q + r]) > math.abs[f64](ee[piv * q + r]) { piv = c }
                    c += 1usize
                }
                if piv != r {
                    var l = 0usize
                    while l < q {
                        let sw = ee[r * q + l]
                        ee[r * q + l] = ee[piv * q + l]
                        ee[piv * q + l] = sw
                        l += 1usize
                    }
                    det = 0.0f64 - det
                }
                det *= ee[r * q + r]
                c = r + 1usize
                while c < q {
                    let fc = ee[c * q + r] / ee[r * q + r]
                    var l = r
                    while l < q {
                        ee[c * q + l] -= fc * ee[r * q + l]
                        l += 1usize
                    }
                    c += 1usize
                }
                r += 1usize
            }
            wm = det / math.pow[f64](tr / qf, qf)
            let rho = 1.0f64 - (2.0f64 * qf * qf + qf + 2.0f64) / (6.0f64 * qf * dfe)
            let z = 0.0f64 - dfe * rho * math.log[f64](wm)
            let df = qf * (qf + 1.0f64) / 2.0f64 - 1.0f64
            let om = (qf + 2.0f64) * (qf - 1.0f64) * (qf - 2.0f64) * (2.0f64 * qf * qf * qf + 6.0f64 * qf * qf + 3.0f64 * f64(ks) + 2.0f64) / (288.0f64 * (dfe * qf * rho) * (dfe * qf * rho))
            pw = (1.0f64 - om) * nm.pchisq(z, df, false, false) + om * nm.pchisq(z, df + 4.0f64, false, false)
        }
        s = 0usize
        while s < ns {
            if s != 0usize || t != 0usize {
                let cs = cnt[s]
                r = 0usize
                while r < cs {
                    var c = 0usize
                    while c < q {
                        var v = 0.0f64
                        var l = 0usize
                        while l < ks {
                            v += bm[(off[s] + r) * ks + l] * pm[l * q + c]
                            l += 1usize
                        }
                        hp[r * q + c] = v
                        c += 1usize
                    }
                    r += 1usize
                }
                var ssn = 0.0f64
                var c = 0usize
                while c < q {
                    r = 0usize
                    while r < cs {
                        var l = 0usize
                        while l < cs {
                            ssn += hp[r * q + c] * mi[s * p * p + r * cs + l] * hp[l * q + c]
                            l += 1usize
                        }
                        r += 1usize
                    }
                    c += 1usize
                }
                let dfn = f64(cs) * qf
                let dfd = dfe * qf
                let fv = (ssn / dfn) / (tr / dfd)
                let at = (s * nt + t) * 12usize
                out[at] = fv
                out[at + 1usize] = dfn
                out[at + 2usize] = dfd
                out[at + 3usize] = nb.pf(fv, dfn, dfd, false, false)
                out[at + 4usize] = ssn / (ssn + tre)
                out[at + 5usize] = gg
                out[at + 6usize] = hfu
                if q >= 2usize {
                    out[at + 7usize] = nb.pf(fv, gg * dfn, gg * dfd, false, false)
                    out[at + 8usize] = nb.pf(fv, hf * dfn, hf * dfd, false, false)
                }
                out[at + 9usize] = wm
                out[at + 10usize] = pw
                out[at + 11usize] = ssn
            }
            s += 1usize
        }
        t += 1usize
    }
    ret ok
}
