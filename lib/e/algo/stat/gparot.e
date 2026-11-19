// The gradient projection rotations of R's GPArotation (2026.8, the Barzilai-Borwein step with a
// nonmonotone window): `gpf_orth` (GPForth) and `gpf_obl` (GPFoblq) over the criteria oblimin, quartimin,
// quartimax, Crawford-Ferguson, Bentler, infomax, geomin, entropy, oblimax, varimax, varimin, target, pst,
// tandem I and tandem II, with Kaiser normalization. Matrices are row-major; NA in a target is NaN.
//
// Not here: the "legacy" and "cayley" algorithms, the Cureton-Mulaik normalization, simplimax,
// bifactor, lp and McCammon rotations. Also stats varimax and promax.

use e.algo.linalg.decomp as decomp
use e.math
use e.mem

error Singular

const FLAT: usize = 0usize

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn eps() -> f64 { ret 2.220446049250313e-16f64 }

// c = a (m x n) * b (n x q)
fn matmul(a: *mem.Arena, x: []const f64, y: []const f64, m: usize, n: usize, q: usize) -> ([]f64, err) {
    let (c, e) = mem.alloc[f64](a, m * q)
    if e != ok { ret (c, e) }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < q {
            var s = 0.0f64
            var k = 0usize
            while k < n {
                s += x[i * n + k] * y[k * q + j]
                k += 1usize
            }
            c[i * q + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret (c, ok)
}

// the transpose of x (m x n)
fn transpose(a: *mem.Arena, x: []const f64, m: usize, n: usize) -> ([]f64, err) {
    let (t, e) = mem.alloc[f64](a, m * n)
    if e != ok { ret (t, e) }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            t[j * m + i] = x[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    ret (t, ok)
}

// the inverse of a k x k matrix by Gauss-Jordan with partial pivoting
fn invert(a: *mem.Arena, x: []const f64, k: usize) -> ([]f64, err) {
    let (w, e1) = mem.alloc[f64](a, k * k)
    if e1 != ok { ret (w, e1) }
    let (inv, e2) = mem.alloc[f64](a, k * k)
    if e2 != ok { ret (inv, e2) }
    var i = 0usize
    while i < k * k {
        w[i] = x[i]
        inv[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        inv[i * k + i] = 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < k {
        var pv = c
        var best = math.abs[f64](w[c * k + c])
        var r = c + 1usize
        while r < k {
            if math.abs[f64](w[r * k + c]) > best {
                best = math.abs[f64](w[r * k + c])
                pv = r
            }
            r += 1usize
        }
        if best == 0.0f64 { ret (inv, Singular) }
        if pv != c {
            var j = 0usize
            while j < k {
                let t = w[c * k + j]
                w[c * k + j] = w[pv * k + j]
                w[pv * k + j] = t
                let t2 = inv[c * k + j]
                inv[c * k + j] = inv[pv * k + j]
                inv[pv * k + j] = t2
                j += 1usize
            }
        }
        let d = w[c * k + c]
        var j = 0usize
        while j < k {
            w[c * k + j] = w[c * k + j] / d
            inv[c * k + j] = inv[c * k + j] / d
            j += 1usize
        }
        r = 0usize
        while r < k {
            if r != c {
                let f = w[r * k + c]
                j = 0usize
                while j < k {
                    w[r * k + j] -= f * w[c * k + j]
                    inv[r * k + j] -= f * inv[c * k + j]
                    j += 1usize
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    ret (inv, ok)
}

fn log_det_spd(x: []const f64, k: usize) -> f64 {
    // log determinant by Gaussian elimination without pivoting on a copy (M is crossprod of squares)
    var s = 0.0f64
    var buf: [64]f64 = zero
    var i = 0usize
    while i < k * k {
        buf[i] = x[i]
        i += 1usize
    }
    var c = 0usize
    while c < k {
        let d = buf[c * k + c]
        s += math.log[f64](math.abs[f64](d))
        var r = c + 1usize
        while r < k {
            let f = buf[r * k + c] / d
            var j = c
            while j < k {
                buf[r * k + j] -= f * buf[c * k + j]
                j += 1usize
            }
            r += 1usize
        }
        c += 1usize
    }
    ret s
}

fn sum_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    ret s
}

// the criterion: Gq (p x k) and f. id 0 oblimin(par[0] = gam), 1 quartimin, 2 quartimax, 3 cf(par[0] = kappa),
// 4 bentler, 5 infomax, 6 geomin(par[0] = delta), 7 entropy, 8 oblimax, 9 varimax, 10 varimin,
// 11 target(par = Target p*k), 12 pst(par = W p*k, then Target p*k), 13 tandem I, 14 tandem II
fn vgq(a: *mem.Arena, id: u8, l: []const f64, p: usize, k: usize, par: []const f64) -> ([]f64, f64, err) {
    if id >= 15u8 {
        let (g0, f0, e0) = vgq_group(a, id, l, p, k, par)
        ret (g0, f0, e0)
    }
    let (gq, ge) = mem.alloc[f64](a, p * k)
    let (l2, le) = mem.alloc[f64](a, p * k)
    if ge != ok { ret (gq, 0.0f64, ge) }
    if le != ok { ret (gq, 0.0f64, le) }
    var i = 0usize
    while i < p * k {
        l2[i] = l[i] * l[i]
        i += 1usize
    }
    var f = 0.0f64
    if id == 0u8 || id == 1u8 {
        var gam = 0.0f64
        if id == 0u8 { gam = par[0usize] }
        let (x, xe) = mem.alloc[f64](a, p * k)
        if xe != ok { ret (gq, 0.0f64, xe) }
        i = 0usize
        while i < p {
            var rs = 0.0f64
            var j = 0usize
            while j < k {
                rs += l2[i * k + j]
                j += 1usize
            }
            j = 0usize
            while j < k {
                x[i * k + j] = rs - l2[i * k + j]
                j += 1usize
            }
            i += 1usize
        }
        if gam != 0.0f64 {
            var j = 0usize
            while j < k {
                var cs = 0.0f64
                i = 0usize
                while i < p {
                    cs += x[i * k + j]
                    i += 1usize
                }
                i = 0usize
                while i < p {
                    x[i * k + j] -= (gam / f64(p)) * cs
                    i += 1usize
                }
                j += 1usize
            }
        }
        i = 0usize
        while i < p * k {
            gq[i] = l[i] * x[i]
            f += l2[i] * x[i]
            i += 1usize
        }
        ret (gq, f / 4.0f64, ok)
    }
    if id == 2u8 {
        i = 0usize
        while i < p * k {
            gq[i] = 0.0f64 - l[i] * l[i] * l[i]
            f += l2[i] * l2[i]
            i += 1usize
        }
        ret (gq, 0.0f64 - f / 4.0f64, ok)
    }
    if id == 3u8 {
        let kappa = par[0usize]
        let (cs, ce) = mem.alloc[f64](a, k)
        if ce != ok { ret (gq, 0.0f64, ce) }
        var j = 0usize
        while j < k {
            cs[j] = 0.0f64
            i = 0usize
            while i < p {
                cs[j] += l2[i * k + j]
                i += 1usize
            }
            j += 1usize
        }
        var f1 = 0.0f64
        var f2 = 0.0f64
        i = 0usize
        while i < p {
            var rs = 0.0f64
            j = 0usize
            while j < k {
                rs += l2[i * k + j]
                j += 1usize
            }
            j = 0usize
            while j < k {
                let l2n = rs - l2[i * k + j]
                let ml2 = cs[j] - l2[i * k + j]
                f1 += l2[i * k + j] * l2n
                f2 += l2[i * k + j] * ml2
                gq[i * k + j] = (1.0f64 - kappa) * l[i * k + j] * l2n + kappa * l[i * k + j] * ml2
                j += 1usize
            }
            i += 1usize
        }
        ret (gq, (1.0f64 - kappa) * f1 / 4.0f64 + kappa * f2 / 4.0f64, ok)
    }
    if id == 4u8 {
        let (lt, lte) = transpose(a, l2, p, k)
        if lte != ok { ret (gq, 0.0f64, lte) }
        let (m, me) = matmul(a, lt, l2, k, p, k)
        if me != ok { ret (gq, 0.0f64, me) }
        var logdd = 0.0f64
        let (dm, de) = mem.alloc[f64](a, k)
        if de != ok { ret (gq, 0.0f64, de) }
        var j = 0usize
        while j < k {
            dm[j] = m[j * k + j]
            logdd += math.log[f64](dm[j])
            j += 1usize
        }
        let (minv, ie) = invert(a, m, k)
        if ie != ok { ret (gq, 0.0f64, ie) }
        i = 0usize
        while i < k {
            minv[i * k + i] -= 1.0f64 / dm[i]
            i += 1usize
        }
        let (prod, pe) = matmul(a, l2, minv, p, k, k)
        if pe != ok { ret (gq, 0.0f64, pe) }
        i = 0usize
        while i < p * k {
            gq[i] = 0.0f64 - l[i] * prod[i]
            i += 1usize
        }
        ret (gq, 0.0f64 - (log_det_spd(m, k) - logdd) / 4.0f64, ok)
    }
    if id == 5u8 {
        var s = 0.0f64
        i = 0usize
        while i < p * k {
            s += l2[i]
            i += 1usize
        }
        let (e1, e1e) = mem.alloc[f64](a, p)
        let (e2, e2e) = mem.alloc[f64](a, k)
        if e1e != ok { ret (gq, 0.0f64, e1e) }
        if e2e != ok { ret (gq, 0.0f64, e2e) }
        i = 0usize
        while i < p {
            e1[i] = 0.0f64
            i += 1usize
        }
        var j = 0usize
        while j < k {
            e2[j] = 0.0f64
            j += 1usize
        }
        i = 0usize
        while i < p {
            j = 0usize
            while j < k {
                e1[i] += l2[i * k + j]
                e2[j] += l2[i * k + j]
                j += 1usize
            }
            i += 1usize
        }
        var q0 = 0.0f64
        var q1 = 0.0f64
        var q2 = 0.0f64
        var sh = 0.0f64
        var sh1 = 0.0f64
        var sh2 = 0.0f64
        let (h, he) = mem.alloc[f64](a, p * k)
        if he != ok { ret (gq, 0.0f64, he) }
        i = 0usize
        while i < p {
            e1[i] = e1[i] / s
            i += 1usize
        }
        j = 0usize
        while j < k {
            e2[j] = e2[j] / s
            j += 1usize
        }
        i = 0usize
        while i < p {
            j = 0usize
            while j < k {
                let e = l2[i * k + j] / s
                q0 -= e * math.log[f64](e + eps())
                h[i * k + j] = 0.0f64 - (math.log[f64](e + eps()) + 1.0f64)
                sh += l2[i * k + j] * h[i * k + j]
                j += 1usize
            }
            i += 1usize
        }
        let (h1, h1e) = mem.alloc[f64](a, p)
        let (h2, h2e) = mem.alloc[f64](a, k)
        if h1e != ok { ret (gq, 0.0f64, h1e) }
        if h2e != ok { ret (gq, 0.0f64, h2e) }
        i = 0usize
        while i < p {
            q1 -= e1[i] * math.log[f64](e1[i] + eps())
            h1[i] = 0.0f64 - (math.log[f64](e1[i] + eps()) + 1.0f64)
            sh1 += e1[i] * s * h1[i]
            i += 1usize
        }
        j = 0usize
        while j < k {
            q2 -= e2[j] * math.log[f64](e2[j] + eps())
            h2[j] = 0.0f64 - (math.log[f64](e2[j] + eps()) + 1.0f64)
            sh2 += e2[j] * s * h2[j]
            j += 1usize
        }
        i = 0usize
        while i < p {
            j = 0usize
            while j < k {
                let g0 = (h[i * k + j] - sh / s) / s
                let g1 = (h1[i] - sh1 / s) / s
                let g2 = (h2[j] - sh2 / s) / s
                gq[i * k + j] = 2.0f64 * l[i * k + j] * (g0 - g1 - g2)
                j += 1usize
            }
            i += 1usize
        }
        ret (gq, math.log[f64](f64(k)) + q0 - q1 - q2, ok)
    }
    if id == 6u8 {
        let delta = par[0usize]
        i = 0usize
        while i < p {
            var lm = 0.0f64
            var j = 0usize
            while j < k {
                lm += math.log[f64](l2[i * k + j] + delta)
                j += 1usize
            }
            let pro = math.exp[f64](lm / f64(k))
            f += pro
            j = 0usize
            while j < k {
                gq[i * k + j] = (2.0f64 / f64(k)) * (l[i * k + j] / (l2[i * k + j] + delta)) * pro
                j += 1usize
            }
            i += 1usize
        }
        ret (gq, f, ok)
    }
    if id == 7u8 {
        i = 0usize
        while i < p * k {
            let lg = math.log[f64](l2[i] + eps())
            gq[i] = 0.0f64 - (l[i] * lg + l[i])
            f -= l2[i] * lg
            i += 1usize
        }
        ret (gq, f / 2.0f64, ok)
    }
    if id == 8u8 {
        var s2 = 0.0f64
        var s4 = 0.0f64
        i = 0usize
        while i < p * k {
            s2 += l2[i]
            s4 += l2[i] * l2[i]
            i += 1usize
        }
        i = 0usize
        while i < p * k {
            gq[i] = 0.0f64 - (4.0f64 * l[i] * l[i] * l[i] / s4 - 4.0f64 * l[i] / s2)
            i += 1usize
        }
        ret (gq, 0.0f64 - (math.log[f64](s4) - 2.0f64 * math.log[f64](s2)), ok)
    }
    if id == 9u8 || id == 10u8 {
        let (ql, qe) = mem.alloc[f64](a, p * k)
        if qe != ok { ret (gq, 0.0f64, qe) }
        var j = 0usize
        while j < k {
            var cm = 0.0f64
            i = 0usize
            while i < p {
                cm += l2[i * k + j]
                i += 1usize
            }
            cm = cm / f64(p)
            i = 0usize
            while i < p {
                ql[i * k + j] = l2[i * k + j] - cm
                i += 1usize
            }
            j += 1usize
        }
        i = 0usize
        while i < p * k {
            f += ql[i] * ql[i]
            if id == 9u8 { gq[i] = 0.0f64 - l[i] * ql[i] } else { gq[i] = l[i] * ql[i] }
            i += 1usize
        }
        if id == 9u8 { ret (gq, 0.0f64 - f / 4.0f64, ok) }
        ret (gq, f / 4.0f64, ok)
    }
    if id == 11u8 {
        i = 0usize
        while i < p * k {
            let t = par[i]
            if t == t {
                gq[i] = 2.0f64 * (l[i] - t)
                f += (l[i] - t) * (l[i] - t)
            } else {
                gq[i] = 0.0f64
            }
            i += 1usize
        }
        ret (gq, f, ok)
    }
    if id == 12u8 {
        i = 0usize
        while i < p * k {
            let w = par[i]
            let bt = w * par[p * k + i]
            gq[i] = 2.0f64 * (w * l[i] - bt)
            f += (w * l[i] - bt) * (w * l[i] - bt)
            i += 1usize
        }
        ret (gq, f, ok)
    }
    // tandem I and II
    let (lt, lte) = transpose(a, l, p, k)
    if lte != ok { ret (gq, 0.0f64, lte) }
    let (ll, lle) = matmul(a, l, lt, p, k, p)
    if lle != ok { ret (gq, 0.0f64, lle) }
    let (ll2, ll2e) = mem.alloc[f64](a, p * p)
    if ll2e != ok { ret (gq, 0.0f64, ll2e) }
    i = 0usize
    while i < p * p {
        ll2[i] = ll[i] * ll[i]
        if id == 14u8 { ll2[i] = 1.0f64 - ll2[i] }
        i += 1usize
    }
    let (mp, mpe) = matmul(a, ll2, l2, p, p, k)
    if mpe != ok { ret (gq, 0.0f64, mpe) }
    let (l2t, l2te) = transpose(a, l2, p, k)
    if l2te != ok { ret (gq, 0.0f64, l2te) }
    let (t2, t2e) = matmul(a, l2, l2t, p, k, p)
    if t2e != ok { ret (gq, 0.0f64, t2e) }
    i = 0usize
    while i < p * p {
        t2[i] = 4.0f64 * ll[i] * t2[i]
        i += 1usize
    }
    let (g2, g2e) = matmul(a, t2, l, p, p, k)
    if g2e != ok { ret (gq, 0.0f64, g2e) }
    i = 0usize
    while i < p * k {
        f += l2[i] * mp[i]
        let g1 = 4.0f64 * l[i] * mp[i]
        if id == 13u8 { gq[i] = 0.0f64 - (g1 + g2[i]) } else { gq[i] = g1 - g2[i] }
        i += 1usize
    }
    if id == 13u8 { f = 0.0f64 - f }
    ret (gq, f, ok)
}

// the criteria of GPArotation 2026.8 that act on a group of columns: 15 simplimax(par[0] = number of near-zero loadings), 16 bifactor,
// 17 bi-geomin(par[0] = delta); the first column is the general factor, outside the criterion
fn vgq_group(a: *mem.Arena, id: u8, l: []const f64, p: usize, k: usize, par: []const f64) -> ([]f64, f64, err) {
    let (gq, ge) = mem.alloc[f64](a, p * k)
    if ge != ok { ret (gq, 0.0f64, ge) }
    var i = 0usize
    while i < p * k {
        gq[i] = 0.0f64
        i += 1usize
    }
    if id == 15u8 {
        let kk = usize(par[0usize])
        let (used, ue) = mem.alloc[bool](a, p * k)
        if ue != ok { ret (gq, 0.0f64, ue) }
        i = 0usize
        while i < p * k {
            used[i] = false
            i += 1usize
        }
        var f = 0.0f64
        var t = 0usize
        while t < kk {
            // the t-th smallest squared loading, ties by position in R's column-major order
            var bi = p * k
            var bv = 0.0f64
            var c = 0usize
            while c < k {
                var r = 0usize
                while r < p {
                    let ix = r * k + c
                    if !used[ix] && (bi == p * k || l[ix] * l[ix] < bv) {
                        bi = ix
                        bv = l[ix] * l[ix]
                    }
                    r += 1usize
                }
                c += 1usize
            }
            used[bi] = true
            gq[bi] = 2.0f64 * l[bi]
            f += bv
            t += 1usize
        }
        ret (gq, f, ok)
    }
    let kg = k - 1usize
    let (sub, se) = mem.alloc[f64](a, p * kg)
    if se != ok { ret (gq, 0.0f64, se) }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < kg {
            sub[i * kg + j] = l[i * k + j + 1usize]
            j += 1usize
        }
        i += 1usize
    }
    if id == 16u8 {
        var f = 0.0f64
        var s4 = 0.0f64
        i = 0usize
        while i < p {
            var rs = 0.0f64
            var j = 0usize
            while j < kg {
                rs += sub[i * kg + j] * sub[i * kg + j]
                j += 1usize
            }
            f += rs * rs
            j = 0usize
            while j < kg {
                let q = sub[i * kg + j] * sub[i * kg + j]
                s4 += q * q
                gq[i * k + j + 1usize] = 4.0f64 * sub[i * kg + j] * (rs - q)
                j += 1usize
            }
            i += 1usize
        }
        ret (gq, f - s4, ok)
    }
    let (g2, f2, ge2) = vgq(a, 6u8, sub, p, kg, par)
    if ge2 != ok { ret (gq, 0.0f64, ge2) }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < kg {
            gq[i * k + j + 1usize] = g2[i * kg + j]
            j += 1usize
        }
        i += 1usize
    }
    ret (gq, f2, ok)
}

// the weights of NormalizingWeight: Kaiser (the row length) or Cureton-Mulaik (that over the weights built from the angle of the
// row to the first unrotated factor)
fn norm_weights(a: *mem.Arena, x: []const f64, p: usize, k: usize, nmode: u8) -> ([]f64, err) {
    let (w, e) = kaiser(a, x, p, k)
    if e != ok || nmode != 2u8 { ret (w, e) }
    let m = f64(k)
    let acosi = math.acos[f64](math.pow[f64](m, 0.0f64 - 0.5f64))
    var i = 0usize
    while i < p {
        let h = w[i]
        var fp = x[i * k] / h
        if fp < 0.0f64 - 1.0f64 { fp = 0.0f64 - 1.0f64 }
        if fp > 1.0f64 { fp = 1.0f64 }
        let alpha = math.acos[f64](math.abs[f64](fp))
        var dem = acosi
        if math.abs[f64](fp) < math.pow[f64](m, 0.0f64 - 0.5f64) { dem = acosi - 3.141592653589793f64 / 2.0f64 }
        let num = acosi - alpha
        let c = math.cos[f64]((num / dem) * (3.141592653589793f64 / 2.0f64))
        w[i] = h / (c * c + 0.001f64)
        i += 1usize
    }
    ret (w, ok)
}

// Kaiser weights: the row length, at least machine epsilon
fn kaiser(a: *mem.Arena, x: []const f64, p: usize, k: usize) -> ([]f64, err) {
    let (w, e) = mem.alloc[f64](a, p)
    if e != ok { ret (w, e) }
    var i = 0usize
    while i < p {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            s += x[i * k + j] * x[i * k + j]
            j += 1usize
        }
        w[i] = math.sqrt[f64](s)
        if w[i] < eps() { w[i] = eps() }
        i += 1usize
    }
    ret (w, ok)
}

type Rotation = struct { loadings: []f64, th: []f64, f: f64, iterations: usize, converged: bool }

fn window_max(table: []const f64, iter: usize, fwindow: usize) -> f64 {
    var lo = 0usize
    if iter + 1usize > fwindow { lo = iter + 1usize - fwindow }
    var m = table[lo]
    var i = lo
    while i <= iter {
        if table[i] > m { m = table[i] }
        i += 1usize
    }
    ret m
}

// GPForth (orthogonal rotation), algorithm "bb" with fwindow 10. Answers the rotated loadings, the
// rotation matrix and the final criterion value.
fn gpf_orth(a: *mem.Arena, x: []const f64, p: usize, k: usize, id: u8, par: []const f64, normalize: bool, tol: f64, maxit: usize) -> (Rotation, err) {
    var nm = 0u8
    if normalize { nm = 1u8 }
    let (r0, e0) = gpf_orth_n(a, x, p, k, id, par, nm, tol, maxit)
    ret (r0, e0)
}

// nmode 0 no normalization, 1 Kaiser, 2 Cureton-Mulaik
fn gpf_orth_n(a: *mem.Arena, x: []const f64, p: usize, k: usize, id: u8, par: []const f64, nmode: u8, tol: f64, maxit: usize) -> (Rotation, err) {
    let (r0, e0) = gpf_orth_alg(a, x, p, k, id, par, nmode, 0u8, 10usize, tol, maxit)
    ret (r0, e0)
}

// algo 0 the Barzilai-Borwein step, 1 legacy (the step doubled every iteration, window 1), 2 Cayley (orthogonal only); fw the window of the
// nonmonotone test
fn gpf_orth_alg(a: *mem.Arena, x: []const f64, p: usize, k: usize, id: u8, par: []const f64, nmode: u8, algo: u8, fw: usize, tol: f64, maxit: usize) -> (Rotation, err) {
    var none: Rotation = zero
    var w: []f64 = zero
    var am = x
    if nmode > 0u8 {
        let (wv, we) = norm_weights(a, x, p, k, nmode)
        if we != ok { ret (none, we) }
        w = wv
        let (an, ae) = mem.alloc[f64](a, p * k)
        if ae != ok { ret (none, ae) }
        var i = 0usize
        while i < p {
            var j = 0usize
            while j < k {
                an[i * k + j] = x[i * k + j] / w[i]
                j += 1usize
            }
            i += 1usize
        }
        am = an
    }
    let (th, te) = mem.alloc[f64](a, k * k)
    let (thp, tpe) = mem.alloc[f64](a, k * k)
    let (g, gge) = mem.alloc[f64](a, p * k)
    let (gpp, gpe) = mem.alloc[f64](a, p * k)
    let (tab, tbe) = mem.alloc[f64](a, maxit + 1usize)
    if te != ok { ret (none, te) }
    if tpe != ok { ret (none, tpe) }
    if gge != ok { ret (none, gge) }
    if gpe != ok { ret (none, gpe) }
    if tbe != ok { ret (none, tbe) }
    var i = 0usize
    while i < k * k {
        th[i] = 0.0f64
        thp[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        th[i * k + i] = 1.0f64
        i += 1usize
    }
    let (l0, l0e) = matmul(a, am, th, p, k, k)
    if l0e != ok { ret (none, l0e) }
    let (gq0, f0, ve) = vgq(a, id, l0, p, k, par)
    if ve != ok { ret (none, ve) }
    var f = f0
    let (at, ate) = transpose(a, am, p, k)
    if ate != ok { ret (none, ate) }
    let (g0, g0e) = matmul(a, at, gq0, k, p, k)
    if g0e != ok { ret (none, g0e) }
    // G = crossprod(A, Gq) is p x k times... A' Gq is k x k, but R's G is A' Gq with A p x k: k x k
    var gk: []f64 = zero
    let (gkv, gke) = mem.alloc[f64](a, k * k)
    if gke != ok { ret (none, gke) }
    gk = gkv
    i = 0usize
    while i < k * k {
        gk[i] = g0[i]
        i += 1usize
    }
    var alpha = 1.0f64
    var havep = false
    var iter = 0usize
    var s = 0.0f64
    let (lbuf, lbe) = mem.alloc[f64](a, p * k)
    if lbe != ok { ret (none, lbe) }
    i = 0usize
    while i < p * k {
        lbuf[i] = l0[i]
        i += 1usize
    }
    var done = false
    while iter <= maxit && !done {
        let mark = mem.mark(a)
        // M = Th' G, S = (M + M') / 2, Gp = G - Th S
        let (tht, tte) = transpose(a, th, k, k)
        if tte != ok { ret (none, tte) }
        let (m, me) = matmul(a, tht, gk, k, k, k)
        if me != ok { ret (none, me) }
        let (sm, sme) = mem.alloc[f64](a, k * k)
        if sme != ok { ret (none, sme) }
        i = 0usize
        while i < k {
            var j = 0usize
            while j < k {
                sm[i * k + j] = (m[i * k + j] + m[j * k + i]) / 2.0f64
                j += 1usize
            }
            i += 1usize
        }
        let (ts, tse) = matmul(a, th, sm, k, k, k)
        if tse != ok { ret (none, tse) }
        let (gp, gpe2) = mem.alloc[f64](a, k * k)
        if gpe2 != ok { ret (none, gpe2) }
        s = 0.0f64
        i = 0usize
        while i < k * k {
            gp[i] = gk[i] - ts[i]
            s += gp[i] * gp[i]
            i += 1usize
        }
        s = math.sqrt[f64](s)
        tab[iter] = f
        if s < tol {
            done = true
        } else {
            if havep && algo != 1u8 {
                var ddt = 0.0f64
                var ddg = 0.0f64
                var dtg = 0.0f64
                i = 0usize
                while i < k * k {
                    let dt = th[i] - thp[i]
                    let dg = gp[i] - gpp[i]
                    ddt += dt * dt
                    ddg += dg * dg
                    dtg += dt * dg
                    i += 1usize
                }
                if ddg > 0.0f64 {
                    alpha = ddt / math.abs[f64](dtg)
                    if alpha > 20.0f64 { alpha = 20.0f64 }
                    if alpha < 1.0e-10f64 { alpha = 1.0e-10f64 }
                }
            } else {
                alpha = 2.0f64 * alpha
            }
            let tgt = window_max(tab, iter, fw)
            var tmatt: []f64 = zero
            var lt: []f64 = zero
            var gqt: []f64 = zero
            var ft = 0.0f64
            var trial = 0usize
            var accepted = false
            while trial <= 10usize && !accepted {
                let (xm, xe) = mem.alloc[f64](a, k * k)
                if xe != ok { ret (none, xe) }
                i = 0usize
                while i < k * k {
                    xm[i] = th[i] - alpha * gp[i]
                    i += 1usize
                }
                var tm: []f64 = zero
                if algo == 2u8 {
                    // Cayley: W = Gp Th' - Th Gp', Th_new = (I + a / 2 W)^-1 (I - a / 2 W) Th
                    let (gpt, gte) = transpose(a, gp, k, k)
                    if gte != ok { ret (none, gte) }
                    let (g1, g1e) = matmul(a, gp, tht, k, k, k)
                    if g1e != ok { ret (none, g1e) }
                    let (g2, g2e) = matmul(a, th, gpt, k, k, k)
                    if g2e != ok { ret (none, g2e) }
                    let (plus, pe2) = mem.alloc[f64](a, k * k)
                    let (minus, me2) = mem.alloc[f64](a, k * k)
                    if pe2 != ok { ret (none, pe2) }
                    if me2 != ok { ret (none, me2) }
                    i = 0usize
                    while i < k * k {
                        let wv = g1[i] - g2[i]
                        var idm = 0.0f64
                        if i / k == i % k { idm = 1.0f64 }
                        plus[i] = idm + alpha / 2.0f64 * wv
                        minus[i] = idm - alpha / 2.0f64 * wv
                        i += 1usize
                    }
                    let (xinv, xie) = invert(a, plus, k)
                    if xie != ok { ret (none, xie) }
                    let (m1, m1e) = matmul(a, xinv, minus, k, k, k)
                    if m1e != ok { ret (none, m1e) }
                    let (m2, m2e) = matmul(a, m1, th, k, k, k)
                    if m2e != ok { ret (none, m2e) }
                    tm = m2
                } else {
                    let (sv, svee) = decomp.svd(a, xm, k, k)
                    if svee != ok { ret (none, svee) }
                    // decomp reads and writes column-major: it saw t(X), so the polar factor of X is t(Vr) Ur
                    let (vt, vte) = transpose(a, sv.v, k, k)
                    if vte != ok { ret (none, vte) }
                    let (tm0, tme) = matmul(a, vt, sv.u, k, k, k)
                    if tme != ok { ret (none, tme) }
                    tm = tm0
                }
                tmatt = tm
                let (lm, lme) = matmul(a, am, tm, p, k, k)
                if lme != ok { ret (none, lme) }
                lt = lm
                let (gqv, fv, vee) = vgq(a, id, lm, p, k, par)
                if vee != ok { ret (none, vee) }
                gqt = gqv
                ft = fv
                if tgt - ft > 0.5f64 * s * s * alpha {
                    accepted = true
                } else {
                    alpha = alpha / 2.0f64
                    trial += 1usize
                }
            }
            // keep the accepted step (R keeps the last trial even when none passed)
            i = 0usize
            while i < k * k {
                thp[i] = th[i]
                th[i] = tmatt[i]
                i += 1usize
            }
            i = 0usize
            while i < p * k {
                gpp[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < k * k {
                gpp[i] = gp[i]
                i += 1usize
            }
            havep = true
            f = ft
            let (at2, at2e) = transpose(a, am, p, k)
            if at2e != ok { ret (none, at2e) }
            let (gn, gne) = matmul(a, at2, gqt, k, p, k)
            if gne != ok { ret (none, gne) }
            i = 0usize
            while i < k * k {
                gk[i] = gn[i]
                i += 1usize
            }
            i = 0usize
            while i < p * k {
                lbuf[i] = lt[i]
                i += 1usize
            }
            iter += 1usize
        }
        mem.reset(a, mark)
    }
    let (out, oe) = mem.alloc[f64](a, p * k)
    if oe != ok { ret (none, oe) }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < k {
            out[i * k + j] = lbuf[i * k + j]
            if nmode > 0u8 { out[i * k + j] = lbuf[i * k + j] * w[i] }
            j += 1usize
        }
        i += 1usize
    }
    ret (Rotation { loadings: out, th: th, f: f, iterations: iter, converged: s < tol }, ok)
}

// G = -t(t(L) %*% Gq %*% Tinv) for the oblique rotation: k x k
fn obl_gradient(a: *mem.Arena, l: []const f64, gq: []const f64, tinv: []const f64, p: usize, k: usize) -> ([]f64, err) {
    let (lt, lte) = transpose(a, l, p, k)
    if lte != ok {
        var none: []f64 = zero
        ret (none, lte)
    }
    let (m1, m1e) = matmul(a, lt, gq, k, p, k)
    if m1e != ok { ret (m1, m1e) }
    let (m2, m2e) = matmul(a, m1, tinv, k, k, k)
    if m2e != ok { ret (m2, m2e) }
    let (g, ge) = transpose(a, m2, k, k)
    if ge != ok { ret (g, ge) }
    var i = 0usize
    while i < k * k {
        g[i] = 0.0f64 - g[i]
        i += 1usize
    }
    ret (g, ok)
}

// the loadings A t(Tinv) of a rotation matrix with unit columns
fn obl_loadings(a: *mem.Arena, am: []const f64, tinv: []const f64, p: usize, k: usize) -> ([]f64, err) {
    let (tit, te) = transpose(a, tinv, k, k)
    if te != ok { ret (tit, te) }
    let (l, le) = matmul(a, am, tit, p, k, k)
    ret (l, le)
}

// GPFoblq (oblique rotation), algorithm bb with fwindow 10. th of the answer is the rotation matrix
// whose columns have unit length; the factor correlations are t(th) th.
fn gpf_obl(a: *mem.Arena, x: []const f64, p: usize, k: usize, id: u8, par: []const f64, normalize: bool, tol: f64, maxit: usize) -> (Rotation, err) {
    var nm = 0u8
    if normalize { nm = 1u8 }
    let (r0, e0) = gpf_obl_n(a, x, p, k, id, par, nm, tol, maxit)
    ret (r0, e0)
}

fn gpf_obl_n(a: *mem.Arena, x: []const f64, p: usize, k: usize, id: u8, par: []const f64, nmode: u8, tol: f64, maxit: usize) -> (Rotation, err) {
    let (r0, e0) = gpf_obl_alg(a, x, p, k, id, par, nmode, 0u8, 10usize, tol, maxit)
    ret (r0, e0)
}

fn gpf_obl_alg(a: *mem.Arena, x: []const f64, p: usize, k: usize, id: u8, par: []const f64, nmode: u8, algo: u8, fw: usize, tol: f64, maxit: usize) -> (Rotation, err) {
    var none: Rotation = zero
    var w: []f64 = zero
    var am = x
    if nmode > 0u8 {
        let (wv, we) = norm_weights(a, x, p, k, nmode)
        if we != ok { ret (none, we) }
        w = wv
        let (an, ae) = mem.alloc[f64](a, p * k)
        if ae != ok { ret (none, ae) }
        var i = 0usize
        while i < p {
            var j = 0usize
            while j < k {
                an[i * k + j] = x[i * k + j] / w[i]
                j += 1usize
            }
            i += 1usize
        }
        am = an
    }
    let (th, te) = mem.alloc[f64](a, k * k)
    let (thp, tpe) = mem.alloc[f64](a, k * k)
    let (gk, gke) = mem.alloc[f64](a, k * k)
    let (gpp, gpe) = mem.alloc[f64](a, k * k)
    let (tab, tbe) = mem.alloc[f64](a, maxit + 1usize)
    let (lbuf, lbe) = mem.alloc[f64](a, p * k)
    if te != ok { ret (none, te) }
    if tpe != ok { ret (none, tpe) }
    if gke != ok { ret (none, gke) }
    if gpe != ok { ret (none, gpe) }
    if tbe != ok { ret (none, tbe) }
    if lbe != ok { ret (none, lbe) }
    var i = 0usize
    while i < k * k {
        th[i] = 0.0f64
        thp[i] = 0.0f64
        gpp[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        th[i * k + i] = 1.0f64
        i += 1usize
    }
    let (tinv0, ie0) = safe_inverse(a, th, k)
    if ie0 != ok { ret (none, ie0) }
    let (l0, l0e) = obl_loadings(a, am, tinv0, p, k)
    if l0e != ok { ret (none, l0e) }
    let (gq0, f0, ve) = vgq(a, id, l0, p, k, par)
    if ve != ok { ret (none, ve) }
    var f = f0
    let (g0, g0e) = obl_gradient(a, l0, gq0, tinv0, p, k)
    if g0e != ok { ret (none, g0e) }
    i = 0usize
    while i < k * k {
        gk[i] = g0[i]
        i += 1usize
    }
    i = 0usize
    while i < p * k {
        lbuf[i] = l0[i]
        i += 1usize
    }
    var alpha = 1.0f64
    var havep = false
    var iter = 0usize
    var s = 0.0f64
    var done = false
    while iter <= maxit && !done {
        let mark = mem.mark(a)
        let (gp, gpe2) = mem.alloc[f64](a, k * k)
        if gpe2 != ok { ret (none, gpe2) }
        var j = 0usize
        while j < k {
            var cs = 0.0f64
            i = 0usize
            while i < k {
                cs += th[i * k + j] * gk[i * k + j]
                i += 1usize
            }
            i = 0usize
            while i < k {
                gp[i * k + j] = gk[i * k + j] - th[i * k + j] * cs
                i += 1usize
            }
            j += 1usize
        }
        s = 0.0f64
        i = 0usize
        while i < k * k {
            s += gp[i] * gp[i]
            i += 1usize
        }
        s = math.sqrt[f64](s)
        tab[iter] = f
        if s < tol {
            done = true
        } else {
            if havep && algo != 1u8 {
                var ddt = 0.0f64
                var ddg = 0.0f64
                var dtg = 0.0f64
                i = 0usize
                while i < k * k {
                    let dt = th[i] - thp[i]
                    let dg = gp[i] - gpp[i]
                    ddt += dt * dt
                    ddg += dg * dg
                    dtg += dt * dg
                    i += 1usize
                }
                if ddg > 0.0f64 {
                    alpha = ddt / math.abs[f64](dtg)
                    if alpha > 20.0f64 { alpha = 20.0f64 }
                    if alpha < 1.0e-10f64 { alpha = 1.0e-10f64 }
                }
            } else {
                alpha = 2.0f64 * alpha
            }
            let tgt = window_max(tab, iter, fw)
            var tmatt: []f64 = zero
            var tinvt: []f64 = zero
            var lt: []f64 = zero
            var gqt: []f64 = zero
            var ft = 0.0f64
            var trial = 0usize
            var accepted = false
            while trial <= 10usize && !accepted {
                let (xm, xe) = mem.alloc[f64](a, k * k)
                if xe != ok { ret (none, xe) }
                j = 0usize
                while j < k {
                    var cn = 0.0f64
                    i = 0usize
                    while i < k {
                        xm[i * k + j] = th[i * k + j] - alpha * gp[i * k + j]
                        cn += xm[i * k + j] * xm[i * k + j]
                        i += 1usize
                    }
                    let v = 1.0f64 / math.sqrt[f64](cn)
                    i = 0usize
                    while i < k {
                        xm[i * k + j] = xm[i * k + j] * v
                        i += 1usize
                    }
                    j += 1usize
                }
                tmatt = xm
                let (ti, tie) = safe_inverse(a, xm, k)
                if tie != ok { ret (none, tie) }
                tinvt = ti
                let (lm, lme) = obl_loadings(a, am, ti, p, k)
                if lme != ok { ret (none, lme) }
                lt = lm
                let (gqv, fv, vee) = vgq(a, id, lm, p, k, par)
                if vee != ok { ret (none, vee) }
                gqt = gqv
                ft = fv
                if tgt - ft > 0.5f64 * s * s * alpha {
                    accepted = true
                } else {
                    alpha = alpha / 2.0f64
                    trial += 1usize
                }
            }
            i = 0usize
            while i < k * k {
                thp[i] = th[i]
                th[i] = tmatt[i]
                gpp[i] = gp[i]
                i += 1usize
            }
            havep = true
            f = ft
            let (gn, gne) = obl_gradient(a, lt, gqt, tinvt, p, k)
            if gne != ok { ret (none, gne) }
            i = 0usize
            while i < k * k {
                gk[i] = gn[i]
                i += 1usize
            }
            i = 0usize
            while i < p * k {
                lbuf[i] = lt[i]
                i += 1usize
            }
            iter += 1usize
        }
        mem.reset(a, mark)
    }
    let (out, oe) = mem.alloc[f64](a, p * k)
    if oe != ok { ret (none, oe) }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < k {
            out[i * k + j] = lbuf[i * k + j]
            if nmode > 0u8 { out[i * k + j] = lbuf[i * k + j] * w[i] }
            j += 1usize
        }
        i += 1usize
    }
    ret (Rotation { loadings: out, th: th, f: f, iterations: iter, converged: s < tol }, ok)
}

fn norm1(x: []const f64, k: usize) -> f64 {
    var m = 0.0f64
    var j = 0usize
    while j < k {
        var s = 0.0f64
        var i = 0usize
        while i < k {
            s += math.abs[f64](x[i * k + j])
            i += 1usize
        }
        if s > m { m = s }
        j += 1usize
    }
    ret m
}

// R's solve() when the matrix is not computationally singular (reciprocal condition at least eps),
// else the pseudo-inverse with tolerance sqrt(eps), as GPFoblq's safe_inverse does.
fn safe_inverse(a: *mem.Arena, x: []const f64, k: usize) -> ([]f64, err) {
    let (inv, e) = invert(a, x, k)
    if e == ok {
        let rc = 1.0f64 / (norm1(x, k) * norm1(inv, k))
        if rc >= eps() { ret (inv, ok) }
    }
    let (sv, se) = decomp.svd(a, x, k, k)
    if se != ok { ret (inv, se) }
    let (out, oe) = mem.alloc[f64](a, k * k)
    if oe != ok { ret (out, oe) }
    var dmax = 0.0f64
    var t = 0usize
    while t < k {
        if sv.d[t] > dmax { dmax = sv.d[t] }
        t += 1usize
    }
    let tol = math.sqrt[f64](eps())
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            var s = 0.0f64
            t = 0usize
            while t < k {
                if sv.d[t] > tol { s += sv.u[t * k + i] * (1.0f64 / sv.d[t]) * sv.v[t * k + j] }
                t += 1usize
            }
            out[i * k + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

// the polar factor U V' of a k x k row-major matrix (the orthogonal matrix closest to it), through decomp.svd
fn polar(a: *mem.Arena, x: []const f64, k: usize) -> ([]f64, err) {
    let (sv, e) = decomp.svd(a, x, k, k)
    if e != ok {
        var none: []f64 = zero
        ret (none, e)
    }
    let (vt, vte) = transpose(a, sv.v, k, k)
    if vte != ok {
        var none: []f64 = zero
        ret (none, vte)
    }
    let (pf, pfe) = matmul(a, vt, sv.u, k, k, k)
    ret (pf, pfe)
}

// stats::varimax(x, normalize = TRUE, eps = 1e-5) of p x k row-major loadings: the rotated loadings and the rotation matrix
fn varimax_stats(a: *mem.Arena, x0: []const f64, p: usize, k: usize, normalize: bool, tolv: f64) -> ([]f64, []f64, err) {
    var none: []f64 = zero
    let (x, e1) = mem.alloc[f64](a, p * k)
    let (sc, e2) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok { ret (none, none, e1) }
    var i = 0usize
    while i < p {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            s += x0[i * k + j] * x0[i * k + j]
            j += 1usize
        }
        sc[i] = math.sqrt[f64](s)
        j = 0usize
        while j < k {
            if normalize { x[i * k + j] = x0[i * k + j] / sc[i] } else { x[i * k + j] = x0[i * k + j] }
            j += 1usize
        }
        i += 1usize
    }
    var tt: []f64 = zero
    let (t0, e3) = mem.alloc[f64](a, k * k)
    if e3 != ok { ret (none, none, e3) }
    i = 0usize
    while i < k * k {
        t0[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        t0[i * k + i] = 1.0f64
        i += 1usize
    }
    tt = t0
    var d = 0.0f64
    var iter = 0usize
    while iter < 1000usize {
        let (z, ze) = matmul(a, x, tt, p, k, k)
        if ze != ok { ret (none, none, ze) }
        let (w, we) = mem.alloc[f64](a, p * k)
        if we != ok { ret (none, none, we) }
        var j = 0usize
        while j < k {
            var c = 0.0f64
            i = 0usize
            while i < p {
                c += z[i * k + j] * z[i * k + j]
                i += 1usize
            }
            i = 0usize
            while i < p {
                w[i * k + j] = z[i * k + j] * z[i * k + j] * z[i * k + j] - z[i * k + j] * c / f64(p)
                i += 1usize
            }
            j += 1usize
        }
        let (xt, xe) = transpose(a, x, p, k)
        if xe != ok { ret (none, none, xe) }
        let (b, be) = matmul(a, xt, w, k, p, k)
        if be != ok { ret (none, none, be) }
        let (u, ue) = polar(a, b, k)
        if ue != ok { ret (none, none, ue) }
        tt = u
        let dpast = d
        d = 0.0f64
        i = 0usize
        while i < k * k {
            d += u[i] * b[i]
            i += 1usize
        }
        if d < dpast * (1.0f64 + tolv) { break }
        iter += 1usize
    }
    let (z, ze) = matmul(a, x, tt, p, k, k)
    if ze != ok { ret (none, none, ze) }
    if normalize {
        i = 0usize
        while i < p {
            var j = 0usize
            while j < k {
                z[i * k + j] = z[i * k + j] * sc[i]
                j += 1usize
            }
            i += 1usize
        }
    }
    ret (z, tt, ok)
}

// stats::promax(x, m): varimax, then the least-squares fit of the power target, columns rescaled to unit variance
// the promax step shared by stats::promax and psych::Promax: x the varimax-rotated loadings (p by k row-major) and rot the rotation that produced them; returns the promax loadings and the rotation rot U
fn promax_tail(a: *mem.Arena, x: []const f64, rot: []const f64, p: usize, k: usize, m: f64) -> ([]f64, []f64, err) {
    var none: []f64 = zero
    let (q, qe) = mem.alloc[f64](a, p * k)
    if qe != ok { ret (none, none, qe) }
    var i = 0usize
    while i < p * k {
        q[i] = x[i] * math.pow[f64](math.abs[f64](x[i]), m - 1.0f64)
        i += 1usize
    }
    let (xt, xte) = transpose(a, x, p, k)
    if xte != ok { ret (none, none, xte) }
    let (xtx, e1) = matmul(a, xt, x, k, p, k)
    if e1 != ok { ret (none, none, e1) }
    let (xtq, e2) = matmul(a, xt, q, k, p, k)
    if e2 != ok { ret (none, none, e2) }
    let (inv, e3) = invert(a, xtx, k)
    if e3 != ok { ret (none, none, e3) }
    let (u, e4) = matmul(a, inv, xtq, k, k, k)
    if e4 != ok { ret (none, none, e4) }
    let (ut, e5) = transpose(a, u, k, k)
    if e5 != ok { ret (none, none, e5) }
    let (utu, e6) = matmul(a, ut, u, k, k, k)
    if e6 != ok { ret (none, none, e6) }
    let (iu, e7) = invert(a, utu, k)
    if e7 != ok { ret (none, none, e7) }
    i = 0usize
    while i < k {
        let dd = math.sqrt[f64](iu[i * k + i])
        var r = 0usize
        while r < k {
            u[r * k + i] = u[r * k + i] * dd
            r += 1usize
        }
        i += 1usize
    }
    let (z, e8) = matmul(a, x, u, p, k, k)
    if e8 != ok { ret (none, none, e8) }
    let (um, e9) = matmul(a, rot, u, k, k, k)
    if e9 != ok { ret (none, none, e9) }
    ret (z, um, ok)
}

fn promax_stats(a: *mem.Arena, x0: []const f64, p: usize, k: usize, m: f64) -> ([]f64, []f64, err) {
    var none: []f64 = zero
    let (x, rot, ve) = varimax_stats(a, x0, p, k, true, 1.0e-5f64)
    if ve != ok { ret (none, none, ve) }
    let (zt, ut, et) = promax_tail(a, x, rot, p, k, m)
    ret (zt, ut, et)
}

// psych::Promax(x, m): the same promax step after GPArotation::Varimax (no Kaiser normalisation, eps 1e-5, 1000 iterations) of x (p by k row-major) instead of stats::varimax, as psych::fa(rotate = "promax") uses; returns the
// loadings and the rotation matrix
fn promax_gpa(a: *mem.Arena, x0: []const f64, p: usize, k: usize, m: f64) -> ([]f64, []f64, err) {
    var none: []f64 = zero
    var par0: [1]f64 = zero
    let (r, ve) = gpf_orth(a, x0, p, k, 9u8, par0[0usize..1usize], false, 1.0e-5f64, 1000usize)
    if ve != ok { ret (none, none, ve) }
    let (zg, ug, eg) = promax_tail(a, r.loadings, r.th, p, k, m)
    ret (zg, ug, eg)
}
