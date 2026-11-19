// R mcmc::metrop: the random-walk Metropolis sampler, batch means of the states taken every nspac proposals (blen per batch), proposals current + scale * rnorm, an uphill move accepted without drawing a uniform and a downhill one by `u < exp(delta)` with u drawn only then, as the package's C code does. The log unnormalised density is one of a fixed set (no user functions here).
//
// Not here: user-supplied densities and output functions, morph, temper, initseq and the other samplers of the package.

use e.algo.rand.r as rng
use e.math
use e.mem

// target 0 standard normal, 1 -x^2/2 - x^4/10 per sum, 2 Laplace
fn lud(id: usize, x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        if id == 0usize { s += 0.0f64 - 0.5f64 * x[i] * x[i] }
        if id == 1usize { s += 0.0f64 - 0.5f64 * x[i] * x[i] - 0.1f64 * x[i] * x[i] * x[i] * x[i] }
        if id == 2usize { s += 0.0f64 - math.abs[f64](x[i]) }
        i += 1usize
    }
    ret s
}

// metrop(lud, initial, nbatch, blen, nspac, scale): batch (nbatch by d, row-major), the acceptance rate of each batch and the final state
fn metrop(a: *mem.Arena, g: *rng.Rng, id: usize, initial: []const f64, nbatch: usize, blen: usize, nspac: usize, scale: []const f64, batch: []f64, accb: []f64, fin: []f64) -> err {
    let d = initial.len
    let (cur, e1) = mem.alloc[f64](a, d)
    let (prop, e2) = mem.alloc[f64](a, d)
    let (sum, e3) = mem.alloc[f64](a, d)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < d {
        cur[i] = initial[i]
        i += 1usize
    }
    var lc = lud(id, cur)
    var ib = 0usize
    while ib < nbatch {
        i = 0usize
        while i < d {
            sum[i] = 0.0f64
            i += 1usize
        }
        var nacc = 0usize
        var jb = 0usize
        while jb < blen {
            var is = 0usize
            while is < nspac {
                i = 0usize
                while i < d {
                    prop[i] = cur[i] + scale[i] * rng.rnorm(g, 0.0f64, 1.0f64)
                    i += 1usize
                }
                let lp = lud(id, prop)
                var accept = false
                if lp >= lc { accept = true } else {
                    let u = rng.unif(g)
                    if u < math.exp[f64](lp - lc) { accept = true }
                }
                if accept {
                    i = 0usize
                    while i < d {
                        cur[i] = prop[i]
                        i += 1usize
                    }
                    lc = lp
                    nacc += 1usize
                }
                is += 1usize
            }
            i = 0usize
            while i < d {
                sum[i] += cur[i]
                i += 1usize
            }
            jb += 1usize
        }
        i = 0usize
        while i < d {
            batch[ib * d + i] = sum[i] / f64(blen)
            i += 1usize
        }
        accb[ib] = f64(nacc) / f64(blen * nspac)
        ib += 1usize
    }
    i = 0usize
    while i < d {
        fin[i] = cur[i]
        i += 1usize
    }
    ret ok
}

// mcmc::initseq(x) (Geyer's initial sequence estimators) for a scalar chain: gamma0, the pairs Gamma_k = gamma_(2k) + gamma_(2k+1) of the centred chain up to the first negative one (set to zero and kept),
// the running minimum (dec), the greatest convex minorant of that (con), and the three asymptotic variance estimates -gamma0 + 2 sum Gamma. out: [0] gamma0, [1] length of the sequences, [2] var.pos,
// [3] var.dec, [4] var.con, then Gamma.pos, Gamma.dec, Gamma.con each of the length in [1]
fn initseq(a: *mem.Arena, x: []const f64, out: []f64) -> err {
    let n = x.len
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / f64(n)
    let (xc, e1) = mem.alloc[f64](a, n)
    let (gam, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    i = 0usize
    while i < n {
        xc[i] = x[i] - mean
        i += 1usize
    }
    var k = 0usize
    while k < n {
        var sm = 0.0f64
        i = 0usize
        while i + k < n {
            sm += xc[i] * xc[i + k]
            i += 1usize
        }
        gam[k] = sm / f64(n)
        k += 1usize
    }
    let npair = n / 2usize
    let (pos, e3) = mem.alloc[f64](a, npair + 1usize)
    let (dec, e4) = mem.alloc[f64](a, npair + 1usize)
    let (con, e5) = mem.alloc[f64](a, npair + 1usize)
    if e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var m = 0usize
    var stop = false
    k = 0usize
    while k < npair && !stop {
        let g = gam[2usize * k] + gam[2usize * k + 1usize]
        if g < 0.0f64 {
            pos[m] = 0.0f64
            m += 1usize
            stop = true
        } else {
            pos[m] = g
            m += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < m {
        dec[i] = pos[i]
        if i > 0usize && dec[i - 1usize] < dec[i] { dec[i] = dec[i - 1usize] }
        i += 1usize
    }
    // greatest convex minorant of the points (i, dec_i): the lower convex hull, then linear interpolation between hull vertices
    let (hull, e6) = mem.alloc[usize](a, m + 1usize)
    if e6 != ok { ret mem.Full }
    var h = 0usize
    i = 0usize
    while i < m {
        while h >= 2usize {
            let i0 = hull[h - 2usize]
            let i1 = hull[h - 1usize]
            // remove i1 when it lies on or above the segment from i0 to i
            let cross = (dec[i1] - dec[i0]) * f64(i - i0) - (dec[i] - dec[i0]) * f64(i1 - i0)
            if cross >= 0.0f64 { h -= 1usize } else { break }
        }
        hull[h] = i
        h += 1usize
        i += 1usize
    }
    var seg = 0usize
    i = 0usize
    while i < m {
        while seg + 1usize < h && hull[seg + 1usize] < i { seg += 1usize }
        if seg + 1usize >= h {
            con[i] = dec[hull[h - 1usize]]
        } else {
            let i0 = hull[seg]
            let i1 = hull[seg + 1usize]
            con[i] = dec[i0] + (dec[i1] - dec[i0]) * f64(i - i0) / f64(i1 - i0)
        }
        i += 1usize
    }
    var s1 = 0.0f64
    var s2 = 0.0f64
    var s3 = 0.0f64
    i = 0usize
    while i < m {
        s1 += pos[i]
        s2 += dec[i]
        s3 += con[i]
        i += 1usize
    }
    out[0usize] = gam[0usize]
    out[1usize] = f64(m)
    out[2usize] = 0.0f64 - gam[0usize] + 2.0f64 * s1
    out[3usize] = 0.0f64 - gam[0usize] + 2.0f64 * s2
    out[4usize] = 0.0f64 - gam[0usize] + 2.0f64 * s3
    i = 0usize
    while i < m {
        out[5usize + i] = pos[i]
        out[5usize + m + i] = dec[i]
        out[5usize + 2usize * m + i] = con[i]
        i += 1usize
    }
    ret ok
}

// mcmc::olbm(x, batch.length) for a scalar chain: the overlapping batch means estimate of the variance of the sample mean
fn olbm(x: []const f64, blen: usize) -> f64 {
    let n = x.len
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / f64(n)
    let nb = n - blen + 1usize
    var bm = 0.0f64
    var j = 0usize
    while j < blen {
        bm += x[j]
        j += 1usize
    }
    bm = bm / f64(blen)
    var ss = (bm - mean) * (bm - mean)
    var b = 1usize
    while b < nb {
        bm = bm + (x[b + blen - 1usize] - x[b - 1usize]) / f64(blen)
        ss += (bm - mean) * (bm - mean)
        b += 1usize
    }
    ret ss * f64(blen) / (f64(nb) * f64(n))
}

// mcmc::morph: the isotropic transformation of the state space made of the exponential (r, p = 3) and the subexponential (b) maps, applied to the distance from `center`. use_b and use_expo choose the parts (both: expo after subexpo)
type Morph = struct { use_b: bool, b: f64, use_expo: bool, r: f64, center: []const f64 }

fn sub_finv(x: f64, b: f64) -> f64 {
    let e = 2.718281828459045f64
    if x > 1.0f64 / b { ret math.exp[f64](b * x) - e / 3.0f64 }
    ret (x * b) * (x * b) * (x * b) * e / 6.0f64 + x * b * e / 2.0f64
}

fn sub_dfinv(x: f64, b: f64) -> f64 {
    let e = 2.718281828459045f64
    if x > 1.0f64 / b { ret b * math.exp[f64](b * x) }
    ret b * (x * b) * (x * b) * e / 2.0f64 + b * e / 2.0f64
}

fn sub_f(x: f64, b: f64) -> f64 {
    let e = 2.718281828459045f64
    if x > 2.0f64 * e / 3.0f64 { ret math.log[f64](x + e / 3.0f64) / b }
    let b6 = math.pow[f64](b, 6.0f64)
    let pinv = math.exp[f64](1.0f64 / 3.0f64) * math.pow[f64](math.sqrt[f64](b6 * b6 * (9.0f64 * x * x + e * e)) - 3.0f64 * b6 * x, 0.0f64 - 1.0f64 / 3.0f64)
    ret pinv * b - 1.0f64 / (pinv * b * b * b)
}

fn exp_finv(x: f64, r: f64) -> f64 {
    if x <= r { ret x }
    ret x + (x - r) * (x - r) * (x - r)
}

fn exp_dfinv(x: f64, r: f64) -> f64 {
    if x <= r { ret 1.0f64 }
    ret 1.0f64 + 3.0f64 * (x - r) * (x - r)
}

fn exp_f(x: f64, r: f64) -> f64 {
    if x < r { ret x }
    let n = math.sqrt[f64]((27.0f64 * r - 27.0f64 * x) * (27.0f64 * r - 27.0f64 * x) + 108.0f64) + 27.0f64 * (r - x)
    ret r + math.pow[f64](2.0f64 / n, 1.0f64 / 3.0f64) - math.pow[f64](n / 2.0f64, 1.0f64 / 3.0f64) / 3.0f64
}

fn morph_finv(m: *const Morph, x: f64) -> f64 {
    var v = x
    if m.use_expo { v = exp_finv(v, m.r) }
    if m.use_b { v = sub_finv(v, m.b) }
    ret v
}

fn morph_dfinv(m: *const Morph, x: f64) -> f64 {
    var d = 1.0f64
    var v = x
    if m.use_expo {
        d = exp_dfinv(v, m.r)
        v = exp_finv(v, m.r)
    }
    if m.use_b { d = d * sub_dfinv(v, m.b) }
    ret d
}

fn morph_f(m: *const Morph, x: f64) -> f64 {
    var v = x
    if m.use_b { v = sub_f(v, m.b) }
    if m.use_expo { v = exp_f(v, m.r) }
    ret v
}

fn norm2(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i] * x[i]
        i += 1usize
    }
    ret math.sqrt[f64](s)
}

// the state in the original coordinates: f.inv applied to the distance, plus the centre
fn morph_inverse(m: *const Morph, st: []const f64, out: []f64) {
    let nr = norm2(st)
    var i = 0usize
    while i < st.len {
        if nr == 0.0f64 { out[i] = m.center[i] } else { out[i] = morph_finv(m, nr) * st[i] / nr + m.center[i] }
        i += 1usize
    }
}

fn morph_transform(m: *const Morph, x: []const f64, out: []f64) {
    var dd: [8]f64 = zero
    var i = 0usize
    while i < x.len {
        dd[i] = x[i] - m.center[i]
        i += 1usize
    }
    let nr = norm2(dd[0usize..x.len])
    i = 0usize
    while i < x.len {
        if nr == 0.0f64 { out[i] = 0.0f64 } else { out[i] = morph_f(m, nr) * dd[i] / nr }
        i += 1usize
    }
}

// the log unnormalised density of the morphed chain: lud(inverse(state)) plus the log Jacobian
fn morph_lud(id: usize, m: *const Morph, st: []const f64) -> f64 {
    var xo: [8]f64 = zero
    morph_inverse(m, st, xo[0usize..st.len])
    var foo = lud(id, xo[0usize..st.len])
    if foo == 0.0f64 - 1.0f64 / 0.0f64 { ret foo }
    let nr = norm2(st)
    let k = f64(st.len)
    if nr == 0.0f64 {
        foo += k * math.log[f64](morph_dfinv(m, 0.0f64))
    } else {
        foo += math.log[f64](morph_dfinv(m, nr)) + (k - 1.0f64) * (math.log[f64](morph_finv(m, nr)) - math.log[f64](nr))
    }
    ret foo
}

// mcmc::morph.metrop(lud, initial, nbatch, blen, nspac, scale, morph = morph(...)) under set.seed (the package's morph.metrop does not pass nspac on to metrop, so the chain always uses nspac = 1 and nspac is ignored here too): metrop on the morphed density from the transformed initial state; the batch means are of the states mapped
// back to the original coordinates, the acceptance rates are the chain's, and fin is the final state in the original coordinates
fn morph_metrop(a: *mem.Arena, g: *rng.Rng, id: usize, m: *const Morph, initial: []const f64, nbatch: usize, blen: usize, nspac: usize, scale: []const f64, batch: []f64, accb: []f64, fin: []f64) -> err {
    let d = initial.len
    let (cur, e1) = mem.alloc[f64](a, d)
    let (prop, e2) = mem.alloc[f64](a, d)
    let (sum, e3) = mem.alloc[f64](a, d)
    let (orig, e4) = mem.alloc[f64](a, d)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    morph_transform(m, initial, cur)
    var lc = morph_lud(id, m, cur)
    var i = 0usize
    var ib = 0usize
    while ib < nbatch {
        i = 0usize
        while i < d {
            sum[i] = 0.0f64
            i += 1usize
        }
        var nacc = 0usize
        var jb = 0usize
        while jb < blen {
            var is = 0usize
            while is < 1usize {
                i = 0usize
                while i < d {
                    prop[i] = cur[i] + scale[i] * rng.rnorm(g, 0.0f64, 1.0f64)
                    i += 1usize
                }
                let lp = morph_lud(id, m, prop)
                var accept = false
                if lp >= lc { accept = true } else {
                    let u = rng.unif(g)
                    if u < math.exp[f64](lp - lc) { accept = true }
                }
                if accept {
                    i = 0usize
                    while i < d {
                        cur[i] = prop[i]
                        i += 1usize
                    }
                    lc = lp
                    nacc += 1usize
                }
                is += 1usize
            }
            morph_inverse(m, cur, orig)
            i = 0usize
            while i < d {
                sum[i] += orig[i]
                i += 1usize
            }
            jb += 1usize
        }
        i = 0usize
        while i < d {
            batch[ib * d + i] = sum[i] / f64(blen)
            i += 1usize
        }
        accb[ib] = f64(nacc) / f64(blen)
        ib += 1usize
    }
    morph_inverse(m, cur, fin)
    ret ok
}
