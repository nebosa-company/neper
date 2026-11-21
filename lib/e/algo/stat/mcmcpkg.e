// R mcmc 0.9-8: metrop (random-walk Metropolis, batch means), morph and morph.metrop, temper (parallel and serial tempering), initseq and olbm, each equal to the package under set.seed. The log unnormalised
// density is one of a fixed set (no user functions here): metrop and morph.metrop take lud, temper takes tlogh.
//
// Not here: debug output, a user-supplied R function as density or outfun (outfun is one of the index forms or the fixed function c(x, x^2)), initseq of a matrix.

use e.algo.rand.r as rng
use e.math
use e.mem

fn neg_inf() -> f64 {
    ret 0.0f64 - 1.0f64 / 0.0f64
}

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

// R's x^y: y == 2 is x * x, anything else pow
fn rpow(x: f64, y: f64) -> f64 {
    if y == 2.0f64 { ret x * x }
    ret math.pow[f64](x, y)
}

// the output function of a chain, encoded as out = [kind, ...]: empty (identity), [1, indices...] a numeric index, [2, flags...] a logical index, [3] the function c(x, x^2). With rsub false the index forms
// are the C code's (a mask: positive indices pick, negative drop, in increasing order); with rsub true they are R's `[` (positive indices in the order given, negative drop)
fn out_pick(out: []const f64, i: usize, d: usize) -> bool {
    let kind = usize(out[0usize])
    if kind == 2usize { ret out[1usize + i] > 0.5f64 }
    var any = false
    var k = 1usize
    while k < out.len {
        if out[k] == f64(i + 1usize) { any = true }
        if out[k] == 0.0f64 - f64(i + 1usize) { any = true }
        k += 1usize
    }
    if out[1usize] < 0.0f64 { ret !any }
    ret any
}

fn out_dim(out: []const f64, d: usize, rsub: bool) -> usize {
    if out.len == 0usize { ret d }
    let kind = usize(out[0usize])
    if kind == 3usize { ret 2usize * d }
    if kind == 1usize && rsub {
        if out[1usize] > 0.0f64 { ret out.len - 1usize }
        ret d - (out.len - 1usize)
    }
    var n = 0usize
    var i = 0usize
    while i < d {
        if out_pick(out, i, d) { n += 1usize }
        i += 1usize
    }
    ret n
}

fn out_eval(out: []const f64, x: []const f64, buf: []f64, rsub: bool) {
    let d = x.len
    var i = 0usize
    if out.len == 0usize {
        while i < d {
            buf[i] = x[i]
            i += 1usize
        }
        ret
    }
    let kind = usize(out[0usize])
    if kind == 3usize {
        while i < d {
            buf[i] = x[i]
            buf[d + i] = x[i] * x[i]
            i += 1usize
        }
        ret
    }
    if kind == 1usize && rsub && out[1usize] > 0.0f64 {
        while i + 1usize < out.len {
            buf[i] = x[usize(out[i + 1usize]) - 1usize]
            i += 1usize
        }
        ret
    }
    var k = 0usize
    while i < d {
        if kind == 1usize && rsub {
            // negative indices: keep what is not named
            var named = false
            var q = 1usize
            while q < out.len {
                if out[q] == 0.0f64 - f64(i + 1usize) { named = true }
                q += 1usize
            }
            if !named {
                buf[k] = x[i]
                k += 1usize
            }
        } else {
            if out_pick(out, i, d) {
                buf[k] = x[i]
                k += 1usize
            }
        }
        i += 1usize
    }
}

// proposal = state + scale * z with scale a scalar (length 1), a vector (length d) or a d by d matrix (column-major, applied as scale %*% z); z are d standard normals drawn first
fn propose(g: *rng.Rng, st: []const f64, prop: []f64, scale: []const f64, z: []f64) {
    let d = st.len
    var j = 0usize
    while j < d {
        z[j] = rng.rnorm(g, 0.0f64, 1.0f64)
        j += 1usize
    }
    if scale.len == 1usize {
        j = 0usize
        while j < d {
            prop[j] = st[j] + scale[0usize] * z[j]
            j += 1usize
        }
        ret
    }
    if scale.len == d {
        j = 0usize
        while j < d {
            prop[j] = st[j] + scale[j] * z[j]
            j += 1usize
        }
        ret
    }
    j = 0usize
    while j < d {
        prop[j] = st[j]
        j += 1usize
    }
    var m = 0usize
    j = 0usize
    while j < d {
        let u = z[j]
        var k = 0usize
        while k < d {
            prop[k] += scale[m] * u
            m += 1usize
            k += 1usize
        }
        j += 1usize
    }
}

// metrop(lud, initial, nbatch, blen, nspac, scale, outfun): batch (nbatch by nout, row-major), the acceptance rate of each batch, the overall rate in accall[0] and the final state. A proposal of -Inf is rejected
// without a uniform, a higher one accepted without one, anything else (equal included) draws one
fn metrop(a: *mem.Arena, g: *rng.Rng, id: usize, initial: []const f64, nbatch: usize, blen: usize, nspac: usize, scale: []const f64, out: []const f64, batch: []f64, accb: []f64, accall: []f64, fin: []f64) -> err {
    let d = initial.len
    let nout = out_dim(out, d, false)
    let (w, e1) = mem.alloc[f64](a, 4usize * d + 2usize * nout)
    if e1 != ok { ret e1 }
    let cur = w[0usize..d]
    let prop = w[d..2usize * d]
    let z = w[2usize * d..3usize * d]
    let ob = w[3usize * d..3usize * d + nout]
    let sum = w[3usize * d + nout..3usize * d + 2usize * nout]
    var i = 0usize
    while i < d {
        cur[i] = initial[i]
        i += 1usize
    }
    var lc = lud(id, cur)
    var tries = 0.0f64
    var acc = 0.0f64
    var ib = 0usize
    while ib < nbatch {
        i = 0usize
        while i < nout {
            sum[i] = 0.0f64
            i += 1usize
        }
        var nacc = 0.0f64
        var ntry = 0.0f64
        var jb = 0usize
        while jb < blen {
            var is = 0usize
            while is < nspac {
                propose(g, cur, prop, scale, z)
                let lp = lud(id, prop)
                var accept = false
                if lp != neg_inf() {
                    if lp > lc { accept = true } else {
                        let u = rng.unif(g)
                        if u < math.exp[f64](lp - lc) { accept = true }
                    }
                }
                if accept {
                    i = 0usize
                    while i < d {
                        cur[i] = prop[i]
                        i += 1usize
                    }
                    lc = lp
                    acc += 1.0f64
                    nacc += 1.0f64
                }
                tries += 1.0f64
                ntry += 1.0f64
                is += 1usize
            }
            out_eval(out, cur, ob, false)
            i = 0usize
            while i < nout {
                sum[i] += ob[i]
                i += 1usize
            }
            jb += 1usize
        }
        i = 0usize
        while i < nout {
            batch[ib * nout + i] = sum[i] / f64(blen)
            i += 1usize
        }
        accb[ib] = nacc / ntry
        ib += 1usize
    }
    accall[0usize] = acc / tries
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

// mcmc::olbm(x, batch.length, demean) for an n by p chain x (column-major): the overlapping batch means estimate of the variance of the sample mean, a p by p matrix in out (column-major). The mean is R's
// two-pass mean when demean; otherwise (R passes no.calc.mean = FALSE, so the C code takes the mean itself) the plain sum over n. Either way the chain is centred
fn olbm(a: *mem.Arena, x: []const f64, n: usize, p: usize, blen: usize, demean: bool, out: []f64) -> err {
    let (w, e1) = mem.alloc[f64](a, 2usize * p)
    if e1 != ok { ret e1 }
    let mean = w[0usize..p]
    let work = w[p..2usize * p]
    let len = f64(blen)
    let nbatch = f64(n - blen + 1usize)
    var i = 0usize
    var k = 0usize
    while i < p {
        var s = 0.0f64
        k = 0usize
        while k < n {
            s += x[k + n * i]
            k += 1usize
        }
        s = s / f64(n)
        mean[i] = s
        if demean {
            var t = 0.0f64
            k = 0usize
            while k < n {
                t += x[k + n * i] - s
                k += 1usize
            }
            mean[i] = s + t / f64(n)
        }
        mean[i] = mean[i] * len
        i += 1usize
    }
    i = 0usize
    while i < p {
        work[i] = 0.0f64
        k = 0usize
        while k < blen {
            work[i] += x[k + n * i]
            k += 1usize
        }
        var j = i + 1usize
        while j > 0usize {
            j -= 1usize
            out[i + p * j] = (work[i] - mean[i]) * (work[j] - mean[j])
        }
        i += 1usize
    }
    k = 0usize
    var l = blen
    while l < n {
        i = 0usize
        while i < p {
            work[i] -= x[k + n * i]
            work[i] += x[l + n * i]
            var j = i + 1usize
            while j > 0usize {
                j -= 1usize
                out[i + p * j] += (work[i] - mean[i]) * (work[j] - mean[j])
            }
            i += 1usize
        }
        k += 1usize
        l += 1usize
    }
    i = 0usize
    while i < p {
        var j = 0usize
        while j <= i {
            out[i + p * j] = out[i + p * j] / (nbatch * f64(n) * len)
            if j < i { out[j + p * i] = out[i + p * j] }
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// mcmc::morph: the isotropic transformation of the state space made of the exponential (r, p; p = 3 has a closed form, any other p is solved by Newton-Raphson) and the subexponential (b) maps, applied to the distance
// from `center`. use_b and use_expo choose the parts (both: expo after subexpo); neither is the identity shifted by center
type Morph = struct { use_b: bool, b: f64, use_expo: bool, r: f64, p: f64, center: []const f64 }

fn sub_finv(x: f64, b: f64) -> f64 {
    let e = 2.718281828459045f64
    if x > 1.0f64 / b { ret math.exp[f64](b * x) - e / 3.0f64 }
    ret rpow(x * b, 3.0f64) * e / 6.0f64 + x * b * e / 2.0f64
}

fn sub_dfinv(x: f64, b: f64) -> f64 {
    let e = 2.718281828459045f64
    if x > 1.0f64 / b { ret b * math.exp[f64](b * x) }
    ret b * rpow(x * b, 2.0f64) * e / 2.0f64 + b * e / 2.0f64
}

fn sub_f(x: f64, b: f64) -> f64 {
    let e = 2.718281828459045f64
    if x > 2.0f64 * e / 3.0f64 { ret math.log[f64](x + e / 3.0f64) / b }
    let b6 = rpow(b, 6.0f64)
    let pinv = math.exp[f64](1.0f64 / 3.0f64) * rpow(math.sqrt[f64](rpow(b, 12.0f64) * (9.0f64 * x * x + math.exp[f64](2.0f64))) - 3.0f64 * b6 * x, 0.0f64 - 1.0f64 / 3.0f64)
    ret pinv * b - 1.0f64 / (pinv * rpow(b, 3.0f64))
}

fn exp_finv(x: f64, r: f64, p: f64) -> f64 {
    if x <= r { ret x }
    ret x + rpow(x - r, p)
}

fn exp_dfinv(x: f64, r: f64, p: f64) -> f64 {
    if x <= r { ret 1.0f64 }
    ret 1.0f64 + p * rpow(x - r, p - 1.0f64)
}

// R's newton.raphson from x0 = r + x^(1/p): iterate while the error is >= sqrt(eps) (2^-26), then one more step
fn exp_newton(x: f64, r: f64, p: f64) -> f64 {
    var x0 = r + rpow(x, 1.0f64 / p)
    var er = exp_finv(x0, r, p) - x
    var it = 0usize
    while er >= 1.0f64 / 67108864.0f64 && it < 100000usize {
        x0 = x0 - er / exp_dfinv(x0, r, p)
        er = exp_finv(x0, r, p) - x
        it += 1usize
    }
    ret x0 - er / exp_dfinv(x0, r, p)
}

fn exp_f(x: f64, r: f64, p: f64) -> f64 {
    if x < r { ret x }
    if p != 3.0f64 { ret exp_newton(x, r, p) }
    let n = math.sqrt[f64](rpow(27.0f64 * r - 27.0f64 * x, 2.0f64) + 108.0f64) + 27.0f64 * (r - x)
    ret r + rpow(2.0f64 / n, 1.0f64 / 3.0f64) - rpow(n / 2.0f64, 1.0f64 / 3.0f64) / 3.0f64
}

fn morph_finv(m: *const Morph, x: f64) -> f64 {
    var v = x
    if m.use_expo { v = exp_finv(v, m.r, m.p) }
    if m.use_b { v = sub_finv(v, m.b) }
    ret v
}

fn morph_dfinv(m: *const Morph, x: f64) -> f64 {
    var d = 1.0f64
    var v = x
    if m.use_expo {
        d = exp_dfinv(v, m.r, m.p)
        v = exp_finv(v, m.r, m.p)
    }
    if m.use_b { d = d * sub_dfinv(v, m.b) }
    ret d
}

fn morph_f(m: *const Morph, x: f64) -> f64 {
    var v = x
    if m.use_b { v = sub_f(v, m.b) }
    if m.use_expo { v = exp_f(v, m.r, m.p) }
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
        if !m.use_b && !m.use_expo { out[i] = st[i] + m.center[i] } else {
            if nr == 0.0f64 { out[i] = m.center[i] } else { out[i] = morph_finv(m, nr) * st[i] / nr + m.center[i] }
        }
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
        if !m.use_b && !m.use_expo { out[i] = dd[i] } else {
            if nr == 0.0f64 { out[i] = 0.0f64 } else { out[i] = morph_f(m, nr) * dd[i] / nr }
        }
        i += 1usize
    }
}

// morph$log.jacobian at a transformed state
fn morph_logjac(m: *const Morph, st: []const f64) -> f64 {
    if !m.use_b && !m.use_expo { ret 0.0f64 }
    let nr = norm2(st)
    let k = f64(st.len)
    if nr == 0.0f64 { ret k * math.log[f64](morph_dfinv(m, 0.0f64)) }
    ret math.log[f64](morph_dfinv(m, nr)) + (k - 1.0f64) * (math.log[f64](morph_finv(m, nr)) - math.log[f64](nr))
}

// the log unnormalised density of the morphed chain: lud(inverse(state)) plus the log Jacobian
fn morph_lud(id: usize, m: *const Morph, st: []const f64) -> f64 {
    var xo: [8]f64 = zero
    morph_inverse(m, st, xo[0usize..st.len])
    let foo = lud(id, xo[0usize..st.len])
    if foo == neg_inf() { ret foo }
    ret foo + morph_logjac(m, st)
}

// mcmc::morph.metrop(lud, initial, nbatch, blen, nspac, scale, outfun, morph = morph(...)) under set.seed (the package does not pass nspac on to metrop, so the chain always uses nspac = 1 and nspac is ignored here too):
// metrop on the morphed density from the transformed initial state, or, with cont, from `initial` taken as already transformed (a continuation of an earlier run, whose finm it is). The batch means are of
// outfun (R's `[` forms or c(x, x^2)) of the states mapped back to the original coordinates, the acceptance rates are the chain's, fin is the final state in the original coordinates and finm in the morphed ones
fn morph_metrop(a: *mem.Arena, g: *rng.Rng, id: usize, m: *const Morph, initial: []const f64, cont: bool, nbatch: usize, blen: usize, nspac: usize, scale: []const f64, out: []const f64, batch: []f64, accb: []f64, accall: []f64, fin: []f64, finm: []f64) -> err {
    let d = initial.len
    let nout = out_dim(out, d, true)
    let (w, e1) = mem.alloc[f64](a, 5usize * d + 2usize * nout)
    if e1 != ok { ret e1 }
    let cur = w[0usize..d]
    let prop = w[d..2usize * d]
    let z = w[2usize * d..3usize * d]
    let orig = w[3usize * d..4usize * d]
    let ob = w[4usize * d..4usize * d + nout]
    let sum = w[4usize * d + nout..4usize * d + 2usize * nout]
    var i = 0usize
    if cont {
        while i < d {
            cur[i] = initial[i]
            i += 1usize
        }
    } else {
        morph_transform(m, initial, cur)
    }
    var lc = morph_lud(id, m, cur)
    var tries = 0.0f64
    var acc = 0.0f64
    var ib = 0usize
    while ib < nbatch {
        i = 0usize
        while i < nout {
            sum[i] = 0.0f64
            i += 1usize
        }
        var nacc = 0.0f64
        var ntry = 0.0f64
        var jb = 0usize
        while jb < blen {
            propose(g, cur, prop, scale, z)
            let lp = morph_lud(id, m, prop)
            var accept = false
            if lp != neg_inf() {
                if lp > lc { accept = true } else {
                    let u = rng.unif(g)
                    if u < math.exp[f64](lp - lc) { accept = true }
                }
            }
            if accept {
                i = 0usize
                while i < d {
                    cur[i] = prop[i]
                    i += 1usize
                }
                lc = lp
                acc += 1.0f64
                nacc += 1.0f64
            }
            tries += 1.0f64
            ntry += 1.0f64
            morph_inverse(m, cur, orig)
            out_eval(out, orig, ob, true)
            i = 0usize
            while i < nout {
                sum[i] += ob[i]
                i += 1usize
            }
            jb += 1usize
        }
        i = 0usize
        while i < nout {
            batch[ib * nout + i] = sum[i] / f64(blen)
            i += 1usize
        }
        accb[ib] = nacc / ntry
        ib += 1usize
    }
    accall[0usize] = acc / tries
    morph_inverse(m, cur, fin)
    i = 0usize
    while i < d {
        finm[i] = cur[i]
        i += 1usize
    }
    ret ok
}

// mcmc::temper tempering target: component i (the first element of the state, 1-based) with inverse temperature beta[i] and pseudo-prior cc[i], on the rest x of the state.
// id 0: -beta s2 / 2 + cc, 1: -beta (s2 / 2 + s4 / 10) + cc, 2: -beta sum |x| + cc (s2 = sum x^2, s4 = sum x^4 as (x^2)^2)
fn tlogh(id: usize, beta: []const f64, cc: []const f64, st: []const f64) -> f64 {
    let i = usize(st[0usize]) - 1usize
    var s2 = 0.0f64
    var s4 = 0.0f64
    var sa = 0.0f64
    var j = 1usize
    while j < st.len {
        let y = st[j] * st[j]
        s2 += y
        s4 += y * y
        sa += math.abs[f64](st[j])
        j += 1usize
    }
    if id == 0usize { ret 0.0f64 - 0.5f64 * beta[i] * s2 + cc[i] }
    if id == 1usize { ret 0.0f64 - beta[i] * (0.5f64 * s2 + 0.1f64 * s4) + cc[i] }
    ret 0.0f64 - beta[i] * sa + cc[i]
}

// the shape of a temper run. neigh is the ncomp by ncomp logical neighbour matrix (column-major, 1 for a neighbour); scale holds length-prefixed blocks [len, values...], one block, or ncomp of them when
// scale_list (a block of length 1 is a scalar, nx a vector, nx * nx a column-major matrix); outid 0 is the state itself, 1 the fixed function serial c(x^2, component), parallel rowSums(state^2)
type Temper = struct { id: usize, ncomp: usize, nx: usize, parallel: bool, beta: []const f64, cc: []const f64, neigh: []const f64, scale: []const f64, scale_list: bool, outid: usize, nbatch: usize, blen: usize, nspac: usize }

// the results as R returns them (column-major): batch nbatch by nout, ibatch (serial) nbatch by ncomp, acceptx (ncomp), accepti (ncomp by ncomp, NaN where not neighbours) and the final state
type TemperOut = struct { batch: []f64, ibatch: []f64, acceptx: []f64, accepti: []f64, fin: []f64 }

fn temper_scale(t: *const Temper, comp: usize) -> []const f64 {
    if !t.scale_list { ret t.scale[1usize..1usize + usize(t.scale[0usize])] }
    var pos = 0usize
    var k = 1usize
    while k < comp {
        pos += 1usize + usize(t.scale[pos])
        k += 1usize
    }
    ret t.scale[pos + 1usize..pos + 1usize + usize(t.scale[pos])]
}

fn temper_nout(t: *const Temper) -> usize {
    if t.outid == 1usize {
        if t.parallel { ret t.ncomp }
        ret t.nx + 1usize
    }
    if t.parallel { ret t.ncomp * t.nx }
    ret t.nx
}

// the state (serial: [component, x...]; parallel: ncomp by nx column-major) to the batch-mean summand
fn temper_out(t: *const Temper, st: []const f64, buf: []f64) {
    let nx = t.nx
    var i = 0usize
    if t.outid == 0usize {
        let n = temper_nout(t)
        while i < n {
            if t.parallel { buf[i] = st[i] } else { buf[i] = st[i + 1usize] }
            i += 1usize
        }
        ret
    }
    if t.parallel {
        while i < t.ncomp {
            var s = 0.0f64
            var j = 0usize
            while j < nx {
                s += st[i + t.ncomp * j] * st[i + t.ncomp * j]
                j += 1usize
            }
            buf[i] = s
            i += 1usize
        }
        ret
    }
    while i < nx {
        buf[i] = st[i + 1usize] * st[i + 1usize]
        i += 1usize
    }
    buf[nx] = st[0usize]
}

// mcmc::temper(lud, initial, neighbors, nbatch, blen, nspac, scale, outfun, parallel = TRUE/FALSE). A within-component move or a swap/jump is chosen by a uniform < 1/2; the draw order is the package's C code's
fn temper(a: *mem.Arena, g: *rng.Rng, t: *const Temper, initial: []const f64, res: *TemperOut) -> err {
    let nc = t.ncomp
    let nx = t.nx
    let nst = initial.len
    let nout = temper_nout(t)
    let (w, e1) = mem.alloc[f64](a, nst + 2usize * (nx + 1usize) + nx + 6usize * nc + 4usize * nc * nc + 2usize * nout)
    if e1 != ok { ret e1 }
    var q = 0usize
    let state = w[q..q + nst]
    q += nst
    let prop = w[q..q + nx + 1usize]
    q += nx + 1usize
    let cop = w[q..q + nx + 1usize]
    q += nx + 1usize
    let z = w[q..q + nx]
    q += nx
    let cld = w[q..q + nc]
    q += nc
    let acn = w[q..q + nc]
    q += nc
    let acd = w[q..q + nc]
    q += nc
    let ain = w[q..q + nc * nc]
    q += nc * nc
    let aid = w[q..q + nc * nc]
    q += nc * nc
    let nn = w[q..q + nc]
    q += nc
    let thn = w[q..q + nc * nc]
    q += nc * nc
    let bb = w[q..q + nout]
    q += nout
    let ob = w[q..q + nout]
    q += nout
    let ib = w[q..q + nc]
    var i = 0usize
    while i < nst {
        state[i] = initial[i]
        i += 1usize
    }
    i = 0usize
    while i < nc {
        cld[i] = 0.0f64 / 0.0f64
        acn[i] = 0.0f64
        acd[i] = 0.0f64
        nn[i] = 0.0f64
        var j = 0usize
        while j < nc {
            ain[i * nc + j] = 0.0f64
            aid[i * nc + j] = 0.0f64
            if t.neigh[i + nc * j] > 0.5f64 {
                thn[i * nc + usize(nn[i])] = f64(j)
                nn[i] += 1.0f64
            }
            j += 1usize
        }
        i += 1usize
    }
    if t.parallel {
        i = 0usize
        while i < nc {
            cop[0usize] = f64(i + 1usize)
            var j = 0usize
            while j < nx {
                cop[j + 1usize] = initial[i + nc * j]
                j += 1usize
            }
            cld[i] = tlogh(t.id, t.beta, t.cc, cop)
            i += 1usize
        }
    } else {
        cld[usize(initial[0usize]) - 1usize] = tlogh(t.id, t.beta, t.cc, initial)
    }
    var kb = 0usize
    while kb < t.nbatch {
        i = 0usize
        while i < nout {
            bb[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < nc {
            ib[i] = 0.0f64
            i += 1usize
        }
        var jb = 0usize
        while jb < t.blen {
            var is = 0usize
            while is < t.nspac {
                let uw = rng.unif(g)
                if uw < 0.5f64 {
                    if t.parallel {
                        let uc = rng.unif(g)
                        var mi = usize(f64(nc) * uc) + 1usize
                        if mi > nc { mi -= 1usize }
                        cop[0usize] = f64(mi)
                        var j = 0usize
                        while j < nx {
                            cop[j + 1usize] = state[(mi - 1usize) + nc * j]
                            j += 1usize
                        }
                        temper_propose(g, cop, prop, temper_scale(t, mi), z)
                        let nl = tlogh(t.id, t.beta, t.cc, prop)
                        let lh = nl - cld[mi - 1usize]
                        var accept = true
                        if lh < 0.0f64 {
                            let uh = rng.unif(g)
                            accept = uh < math.exp[f64](lh)
                        }
                        if accept {
                            j = 0usize
                            while j < nx {
                                state[(mi - 1usize) + nc * j] = prop[j + 1usize]
                                j += 1usize
                            }
                            cld[mi - 1usize] = nl
                            acn[mi - 1usize] += 1.0f64
                        }
                        acd[mi - 1usize] += 1.0f64
                    } else {
                        let mi = usize(state[0usize])
                        temper_propose(g, state, prop, temper_scale(t, mi), z)
                        let nl = tlogh(t.id, t.beta, t.cc, prop)
                        let lh = nl - cld[mi - 1usize]
                        var accept = true
                        if lh < 0.0f64 {
                            let uh = rng.unif(g)
                            accept = uh < math.exp[f64](lh)
                        }
                        if accept {
                            var j = 0usize
                            while j <= nx {
                                state[j] = prop[j]
                                j += 1usize
                            }
                            cld[mi - 1usize] = nl
                            acn[mi - 1usize] += 1.0f64
                        }
                        acd[mi - 1usize] += 1.0f64
                    }
                } else {
                    if t.parallel {
                        let u1 = rng.unif(g)
                        let u2 = rng.unif(g)
                        var mi = usize(f64(nc) * u1) + 1usize
                        if mi > nc { mi -= 1usize }
                        cop[0usize] = f64(mi)
                        var j = 0usize
                        while j < nx {
                            cop[j + 1usize] = state[(mi - 1usize) + nc * j]
                            j += 1usize
                        }
                        let ni = usize(nn[mi - 1usize])
                        var foo = usize(f64(ni) * u2) + 1usize
                        if foo > ni { foo -= 1usize }
                        let mj = usize(thn[(mi - 1usize) * nc + foo - 1usize]) + 1usize
                        prop[0usize] = f64(mj)
                        j = 0usize
                        while j < nx {
                            prop[j + 1usize] = state[(mj - 1usize) + nc * j]
                            j += 1usize
                        }
                        let cl_i = cld[mi - 1usize]
                        let cl_j = cld[mj - 1usize]
                        prop[0usize] = f64(mi)
                        cop[0usize] = f64(mj)
                        let swc = tlogh(t.id, t.beta, t.cc, cop)
                        let swp = tlogh(t.id, t.beta, t.cc, prop)
                        let lh = swp + swc - cl_j - cl_i
                        var accept = true
                        if lh < 0.0f64 {
                            let uh = rng.unif(g)
                            accept = uh < math.exp[f64](lh)
                        }
                        if accept {
                            j = 0usize
                            while j < nx {
                                state[(mj - 1usize) + nc * j] = cop[j + 1usize]
                                j += 1usize
                            }
                            j = 0usize
                            while j < nx {
                                state[(mi - 1usize) + nc * j] = prop[j + 1usize]
                                j += 1usize
                            }
                            cld[mi - 1usize] = swp
                            cld[mj - 1usize] = swc
                            ain[(mi - 1usize) * nc + mj - 1usize] += 1.0f64
                        }
                        aid[(mi - 1usize) * nc + mj - 1usize] += 1.0f64
                    } else {
                        let mi = usize(state[0usize])
                        let ni = usize(nn[mi - 1usize])
                        let uc = rng.unif(g)
                        var foo = usize(f64(ni) * uc) + 1usize
                        if foo > ni { foo -= 1usize }
                        let mj = usize(thn[(mi - 1usize) * nc + foo - 1usize]) + 1usize
                        let nj = usize(nn[mj - 1usize])
                        prop[0usize] = f64(mj)
                        var j = 0usize
                        while j < nx {
                            prop[j + 1usize] = state[j + 1usize]
                            j += 1usize
                        }
                        let nl = tlogh(t.id, t.beta, t.cc, prop)
                        let lh = nl - cld[mi - 1usize] + math.log[f64](f64(ni)) - math.log[f64](f64(nj))
                        var accept = true
                        if lh < 0.0f64 {
                            let uh = rng.unif(g)
                            accept = uh < math.exp[f64](lh)
                        }
                        if accept {
                            j = 0usize
                            while j <= nx {
                                state[j] = prop[j]
                                j += 1usize
                            }
                            cld[mj - 1usize] = nl
                            ain[(mi - 1usize) * nc + mj - 1usize] += 1.0f64
                        }
                        aid[(mi - 1usize) * nc + mj - 1usize] += 1.0f64
                    }
                }
                is += 1usize
            }
            temper_out(t, state, ob)
            i = 0usize
            while i < nout {
                bb[i] += ob[i]
                i += 1usize
            }
            if !t.parallel { ib[usize(state[0usize]) - 1usize] += 1.0f64 }
            jb += 1usize
        }
        i = 0usize
        while i < nout {
            res.batch[kb + t.nbatch * i] = bb[i] / f64(t.blen)
            i += 1usize
        }
        if !t.parallel {
            i = 0usize
            while i < nc {
                res.ibatch[kb + t.nbatch * i] = ib[i] / f64(t.blen)
                i += 1usize
            }
        }
        kb += 1usize
    }
    i = 0usize
    while i < nc {
        res.acceptx[i] = acn[i] / acd[i]
        var j = 0usize
        while j < nc {
            if t.neigh[i + nc * j] > 0.5f64 {
                res.accepti[i + nc * j] = ain[i * nc + j] / aid[i * nc + j]
            } else {
                res.accepti[i + nc * j] = 0.0f64 / 0.0f64
            }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nst {
        res.fin[i] = state[i]
        i += 1usize
    }
    ret ok
}

// temper's proposal: nx standard normals first, then the same scale forms as metrop's (the state is [component, x...])
fn temper_propose(g: *rng.Rng, cop: []const f64, prop: []f64, scale: []const f64, z: []f64) {
    let nx = cop.len - 1usize
    var j = 0usize
    while j < nx {
        z[j] = rng.rnorm(g, 0.0f64, 1.0f64)
        j += 1usize
    }
    prop[0usize] = cop[0usize]
    if scale.len == 1usize {
        j = 0usize
        while j < nx {
            prop[j + 1usize] = cop[j + 1usize] + scale[0usize] * z[j]
            j += 1usize
        }
        ret
    }
    if scale.len == nx {
        j = 0usize
        while j < nx {
            prop[j + 1usize] = cop[j + 1usize] + scale[j] * z[j]
            j += 1usize
        }
        ret
    }
    j = 0usize
    while j < nx {
        prop[j + 1usize] = cop[j + 1usize]
        j += 1usize
    }
    var m = 0usize
    j = 0usize
    while j < nx {
        let u = z[j]
        var k = 0usize
        while k < nx {
            prop[k + 1usize] += scale[m] * u
            m += 1usize
            k += 1usize
        }
        j += 1usize
    }
}
