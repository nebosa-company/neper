// R norm's data augmentation: rngseed, the I-step (imputation of the missing cells by draws from the conditional
// normals) with imp.norm, and da.norm's alternating I and P steps (a draw of the normal-inverted-Wishart posterior),
// following the package's Fortran in its own random number generator (the Park-Miller generator in single
// precision, the Box-Muller normals in pairs, Fishman's and Ahrens's gamma deviates) and its single-precision
// rounding, so that the draws agree with R after rngseed to the single-precision functions' rounding.
//
// The data are n rows by p columns row-major with NaN for a missing cell. Parameters are the package's packed
// theta of d = (p + 1)(p + 2) / 2 numbers in the standardised scale (makeparam.norm builds one).
//
// Not here: the other routines of norm (the monotone steps, mda.norm), em.norm (e.algo.stat.normem).

use e.math
use e.mem

type Rn = struct { ix: i64, alt: i64, next: f64 }

fn r32(x: f64) -> f64 { ret f64(f32(x)) }

// rngs(seed): the generator starts at seed and the first draw is consumed
fn rngseed(r: *Rn, seed: i64) {
    r.ix = seed
    r.alt = 0i64
    r.next = 0.0f64
    let _ = rangen(r)
}

// rangen: Schrage's integer recursion of the Park-Miller generator; the deviate is a REAL
fn rangen(r: *Rn) -> f64 {
    let a = 16807i64
    let b15 = 32768i64
    let b16 = 65536i64
    let p = 2147483647i64
    let xhi = r.ix / b16
    let xalo = (r.ix - xhi * b16) * a
    let leftflo = xalo / b16
    let fhi = xhi * a + leftflo
    let k = fhi / b15
    var ix = ((xalo - leftflo * b16) - p) + (fhi - k * b15) * b16 + k
    if ix < 0i64 { ix += p }
    r.ix = ix
    ret r32(r32(f64(ix)) * r32(4.656612875e-10f64))
}

fn gauss(r: *Rn) -> f64 {
    if r.alt != 0i64 && r.alt != 1i64 { r.alt = 0i64 }
    if r.alt == 0i64 {
        let u1 = rangen(r)
        let u2 = rangen(r)
        let pi = r32(3.141593f64)
        let sq = r32(math.sqrt[f64](r32(0.0f64 - 2.0f64 * r32(math.log[f64](u1)))))
        let arg = r32(r32(2.0f64 * pi) * u2)
        let g = r32(sq * r32(math.cos[f64](arg)))
        r.next = r32(sq * r32(math.sin[f64](arg)))
        r.alt = 1i64
        ret g
    }
    r.alt = 0i64
    ret r.next
}

// gamm: Fishman's method for a >= 1, Ahrens's below; a REAL
fn gamm(r: *Rn, a: f64) -> f64 {
    let e = r32(2.718282f64)
    if a >= 1.0f64 {
        while true {
            let u = rangen(r)
            let y = 0.0f64 - r32(math.log[f64](rangen(r)))
            let q = math.pow[f64](y / math.exp[f64](y - 1.0f64), a - 1.0f64)
            if u <= q { ret r32(a * y) }
        }
    }
    while true {
        let u = rangen(r)
        let b = (e + a) / e
        let p = b * u
        if p <= 1.0f64 {
            let x = r32(math.pow[f64](p, 1.0f64 / a))
            let u1 = rangen(r)
            if !(u1 > math.pow[f64](e, 0.0f64 - x)) { ret x }
        } else {
            let x = r32(0.0f64 - math.log[f64]((b - p) / a))
            let u1 = rangen(r)
            if !(u1 > math.pow[f64](x, a - 1.0f64)) { ret x }
        }
    }
    ret 0.0f64
}

// ---- packed storage ----

type Pk = struct { p: usize, d: usize, psi: []usize }

fn ps(k: *const Pk, i: usize, j: usize) -> usize { ret k.psi[i * (k.p + 1usize) + j] }

fn mkpsi(a: *mem.Arena, p: usize) -> (Pk, err) {
    var k: Pk = zero
    let (psi, e) = mem.alloc[usize](a, (p + 1usize) * (p + 1usize))
    if e != ok { ret (k, e) }
    var posn = 0usize
    var j = 0usize
    while j <= p {
        psi[j * (p + 1usize) + j] = posn
        posn += 1usize
        var q = j + 1usize
        while q <= p {
            psi[j * (p + 1usize) + q] = posn
            psi[q * (p + 1usize) + j] = posn
            posn += 1usize
            q += 1usize
        }
        j += 1usize
    }
    k.p = p
    k.d = posn
    k.psi = psi
    ret (k, ok)
}

fn swp(k: *const Pk, th: []f64, pivot: usize, submat: usize, dir: f64) {
    let a = th[ps(k, pivot, pivot)]
    th[ps(k, pivot, pivot)] = 0.0f64 - 1.0f64 / a
    var j = 0usize
    while j <= submat {
        if j != pivot { th[ps(k, j, pivot)] = th[ps(k, j, pivot)] / a * dir }
        j += 1usize
    }
    var i = 0usize
    while i <= submat {
        j = i
        while j <= submat {
            if i != pivot && j != pivot {
                let b = th[ps(k, i, pivot)]
                let c = th[ps(k, j, pivot)]
                th[ps(k, i, j)] = th[ps(k, i, j)] - a * b * c
            }
            j += 1usize
        }
        i += 1usize
    }
}

// r is npatt by p (1 observed, 0 missing), row-major; the sweep to condition on the observed variables of a pattern
fn swpobs(k: *const Pk, th: []f64, r: []const i64, patt: usize) {
    let p = k.p
    var j = 1usize
    while j <= p {
        let s = th[ps(k, j, j)]
        if r[patt * p + j - 1usize] == 1i64 && s > 0.0f64 {
            swp(k, th, j, p, 1.0f64)
        } else if r[patt * p + j - 1usize] == 0i64 && s < 0.0f64 {
            swp(k, th, j, p, 0.0f64 - 1.0f64)
        }
        j += 1usize
    }
}

fn gtcols(p: usize, r: []const i64, patt: usize, want: i64, out: []usize) -> usize {
    var n = 0usize
    var j = 1usize
    while j <= p {
        if r[patt * p + j - 1usize] == want {
            out[n] = j
            n += 1usize
        }
        j += 1usize
    }
    ret n
}

// the upper Cholesky factor of the submatrix of theta on the columns mc, in place
fn chols(k: *const Pk, th: []f64, mc: []const usize, nmc: usize) {
    var i = 0usize
    while i < nmc {
        var tmp = 0.0f64
        var q = 0usize
        while q < i {
            let v = th[ps(k, mc[q], mc[i])]
            tmp += v * v
            q += 1usize
        }
        th[ps(k, mc[i], mc[i])] = math.sqrt[f64](th[ps(k, mc[i], mc[i])] - tmp)
        var j = i + 1usize
        while j < nmc {
            tmp = 0.0f64
            q = 0usize
            while q < i {
                tmp += th[ps(k, mc[q], mc[i])] * th[ps(k, mc[q], mc[j])]
                q += 1usize
            }
            th[ps(k, mc[i], mc[j])] = (th[ps(k, mc[i], mc[j])] - tmp) / th[ps(k, mc[i], mc[i])]
            j += 1usize
        }
        i += 1usize
    }
}

// the sufficient statistics of the observed cells
fn tobsn(k: *const Pk, tobs: []f64, n: usize, x: []const f64, npatt: usize, r: []const i64, mdpst: []const usize, nmdp: []const usize, oc: []usize) {
    let p = k.p
    var i = 0usize
    while i < k.d {
        tobs[i] = 0.0f64
        i += 1usize
    }
    tobs[0usize] = 1.0f64
    var patt = 0usize
    while patt < npatt {
        let noc = gtcols(p, r, patt, 1i64, oc)
        var row = mdpst[patt]
        while row < mdpst[patt] + nmdp[patt] {
            var j = 0usize
            while j < noc {
                tobs[ps(k, 0usize, oc[j])] += x[row * p + oc[j] - 1usize]
                var q = j
                while q < noc {
                    tobs[ps(k, oc[j], oc[q])] += x[row * p + oc[j] - 1usize] * x[row * p + oc[q] - 1usize]
                    q += 1usize
                }
                j += 1usize
            }
            row += 1usize
        }
        patt += 1usize
    }
}

// the I-step: draws the missing cells into x given theta (in sweep(0) condition, left swept), t receives the sufficient statistics of the completed data
fn is1n(rn: *Rn, k: *const Pk, th: []f64, t: []f64, tobs: []const f64, n: usize, x: []f64, npatt: usize, r: []const i64, mdpst: []const usize, nmdp: []const usize, oc: []usize, mc: []usize, z: []f64, c: []f64) {
    let p = k.p
    var junk = gauss(rn)
    junk += 0.0f64
    var i = 0usize
    while i < k.d {
        t[i] = tobs[i]
        i += 1usize
    }
    var patt = npatt
    while patt > 0usize {
        patt -= 1usize
        swpobs(k, th, r, patt)
        let nmc = gtcols(p, r, patt, 0i64, mc)
        let noc = gtcols(p, r, patt, 1i64, oc)
        var j = 0usize
        while j < nmc {
            var q = j
            while q < nmc {
                c[ps(k, mc[j], mc[q])] = th[ps(k, mc[j], mc[q])]
                q += 1usize
            }
            j += 1usize
        }
        chols(k, c, mc, nmc)
        var row = mdpst[patt]
        while row < mdpst[patt] + nmdp[patt] {
            j = 0usize
            while j < nmc {
                let cj = mc[j]
                var v = th[ps(k, 0usize, cj)]
                var q = 0usize
                while q < noc {
                    v += th[ps(k, oc[q], cj)] * x[row * p + oc[q] - 1usize]
                    q += 1usize
                }
                z[cj - 1usize] = gauss(rn)
                q = 0usize
                while q <= j {
                    v += z[mc[q] - 1usize] * c[ps(k, cj, mc[q])]
                    q += 1usize
                }
                x[row * p + cj - 1usize] = v
                t[ps(k, 0usize, cj)] += v
                q = 0usize
                while q < noc {
                    t[ps(k, cj, oc[q])] += v * x[row * p + oc[q] - 1usize]
                    q += 1usize
                }
                q = 0usize
                while q <= j {
                    t[ps(k, cj, mc[q])] += v * x[row * p + mc[q] - 1usize]
                    q += 1usize
                }
                j += 1usize
            }
            row += 1usize
        }
    }
    i = 1usize
    while i < k.d {
        t[i] = t[i] / f64(n)
        i += 1usize
    }
}

fn invtrn(k: *const Pk, t: []f64) {
    let p = k.p
    t[ps(k, 1usize, 1usize)] = 1.0f64 / t[ps(k, 1usize, 1usize)]
    var kk = 2usize
    while kk <= p {
        t[ps(k, kk, kk)] = 1.0f64 / t[ps(k, kk, kk)]
        var j = 1usize
        while j < kk {
            var s = 0.0f64
            var i = j
            while i < kk {
                s += t[ps(k, i, j)] * t[ps(k, i, kk)]
                i += 1usize
            }
            t[ps(k, j, kk)] = 0.0f64 - s * t[ps(k, kk, kk)]
            j += 1usize
        }
        kk += 1usize
    }
}

fn bfac(rn: *Rn, k: *const Pk, b: []f64, m: f64) {
    let p = k.p
    var j = 1usize
    while j <= p {
        b[ps(k, j, j)] = r32(math.sqrt[f64](r32(2.0f64 * gamm(rn, (m - f64(j) + 1.0f64) / 2.0f64))))
        j += 1usize
    }
    j = 1usize
    while j < p {
        var q = j + 1usize
        while q <= p {
            b[ps(k, j, q)] = gauss(rn)
            q += 1usize
        }
        j += 1usize
    }
}

// a draw of the normal-inverted-Wishart posterior with the parameters in pars, overwriting pars
fn ninvwn(rn: *Rn, k: *const Pk, pars: []f64, tau: f64, m: f64, mat: []f64, z: []f64, b: []f64, c: []usize) {
    let p = k.p
    var junk = gauss(rn)
    junk += 0.0f64
    var j = 0usize
    while j < p {
        c[j] = j + 1usize
        j += 1usize
    }
    chols(k, pars, c, p)
    bfac(rn, k, b, m)
    invtrn(k, b)
    var i = 1usize
    while i <= p {
        j = 1usize
        while j <= p {
            var s = 0.0f64
            var q = 1usize
            var lim = i
            if j < lim { lim = j }
            while q <= lim {
                s += b[ps(k, i, q)] * pars[ps(k, q, j)]
                q += 1usize
            }
            mat[(i - 1usize) * p + j - 1usize] = s
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < p {
        z[j] = gauss(rn)
        j += 1usize
    }
    j = 1usize
    while j <= p {
        var s = 0.0f64
        var q = 1usize
        while q <= p {
            s += mat[(q - 1usize) * p + j - 1usize] * z[q - 1usize]
            q += 1usize
        }
        pars[ps(k, 0usize, j)] = pars[ps(k, 0usize, j)] + s / math.sqrt[f64](tau)
        j += 1usize
    }
    i = 1usize
    while i <= p {
        j = i
        while j <= p {
            var s = 0.0f64
            var q = 1usize
            while q <= p {
                s += mat[(q - 1usize) * p + i - 1usize] * mat[(q - 1usize) * p + j - 1usize]
                q += 1usize
            }
            pars[ps(k, i, j)] = s
            j += 1usize
        }
        i += 1usize
    }
    pars[ps(k, 0usize, 0usize)] = 0.0f64 - 1.0f64
}

// the P-step: the posterior given the completed-data statistics t and the prior (tau, m, mu0 and lambda inverse in theta), overwriting theta
fn ps1n(rn: *Rn, k: *const Pk, t: []f64, m0: f64, tau0: f64, th: []f64, n: usize, mat: []f64, z: []f64, b: []f64, c: []usize) {
    let p = k.p
    swp(k, t, 0usize, p, 1.0f64)
    let nf = f64(n)
    var j = 1usize
    while j <= p {
        var q = j
        while q <= p {
            th[ps(k, j, q)] = th[ps(k, j, q)] + nf * t[ps(k, j, q)] + tau0 * nf / (tau0 + nf) * (t[ps(k, 0usize, j)] - th[ps(k, 0usize, j)]) * (t[ps(k, 0usize, q)] - th[ps(k, 0usize, q)])
            q += 1usize
        }
        j += 1usize
    }
    j = 1usize
    while j <= p {
        th[ps(k, 0usize, j)] = nf * t[ps(k, 0usize, j)] / (nf + tau0) + tau0 * th[ps(k, 0usize, j)] / (nf + tau0)
        j += 1usize
    }
    ninvwn(rn, k, th, tau0 + nf, m0 + nf, mat, z, b, c)
}

type Prelim = struct { n: usize, p: usize, x: []f64, xbar: []f64, sdv: []f64, ro: []usize, r: []i64, npatt: usize, mdpst: []usize, nmdp: []usize }

// prelim.norm: rows sorted by missingness pattern, columns centred and scaled, missing cells coded 999, the patterns as the package finds them
fn prelim(a: *mem.Arena, x0: []const f64, n: usize, p: usize) -> (Prelim, err) {
    var s: Prelim = zero
    let (x, e1) = mem.alloc[f64](a, n * p)
    let (xbar, e2) = mem.alloc[f64](a, p)
    let (sdv, e3) = mem.alloc[f64](a, p)
    let (ro, e4) = mem.alloc[usize](a, n)
    let (mdp, e5) = mem.alloc[f64](a, n)
    let (ord, e6) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (s, mem.Full) }
    var i = 0usize
    while i < n {
        var code = 1.0f64
        var j = 0usize
        var w = 1.0f64
        while j < p {
            if x0[i * p + j] != x0[i * p + j] { code += w }
            w *= 2.0f64
            j += 1usize
        }
        mdp[i] = code
        ord[i] = i
        i += 1usize
    }
    // stable order by pattern code
    i = 1usize
    while i < n {
        var j = i
        while j > 0usize && mdp[ord[j - 1usize]] > mdp[ord[j]] {
            let t = ord[j - 1usize]
            ord[j - 1usize] = ord[j]
            ord[j] = t
            j -= 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        ro[ord[i]] = i
        i += 1usize
    }
    var j = 0usize
    while j < p {
        var s1 = 0.0f64
        var s2 = 0.0f64
        var cnt = 0.0f64
        i = 0usize
        while i < n {
            let v = x0[i * p + j]
            if v == v {
                cnt += 1.0f64
                s1 += v
                s2 += v * v
            }
            i += 1usize
        }
        xbar[j] = 0.0f64
        sdv[j] = 1.0f64
        if cnt > 0.0f64 {
            xbar[j] = s1 / cnt
            let sd = math.sqrt[f64]((s2 - (s1 * s1) / cnt) / cnt)
            if sd > 0.0f64 { sdv[j] = sd }
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        j = 0usize
        while j < p {
            let v = x0[ord[i] * p + j]
            if v == v {
                var u = v - xbar[j]
                if sdv[j] > 0.0f64 { u = u / sdv[j] }
                x[i * p + j] = u
            } else {
                x[i * p + j] = 999.0f64
            }
            j += 1usize
        }
        i += 1usize
    }
    // patterns
    let (rall, e7) = mem.alloc[i64](a, n * p)
    let (mdpst, e8) = mem.alloc[usize](a, n)
    let (nmdp, e9) = mem.alloc[usize](a, n)
    if e7 != ok || e8 != ok || e9 != ok { ret (s, mem.Full) }
    var npatt = 0usize
    i = 0usize
    while i < n {
        if i == 0usize || mdp[ord[i]] != mdp[ord[i - 1usize]] {
            mdpst[npatt] = i
            j = 0usize
            while j < p {
                var obs = 1i64
                if x0[ord[i] * p + j] != x0[ord[i] * p + j] { obs = 0i64 }
                rall[npatt * p + j] = obs
                j += 1usize
            }
            npatt += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < npatt {
        var nx = n
        if i + 1usize < npatt { nx = mdpst[i + 1usize] }
        nmdp[i] = nx - mdpst[i]
        i += 1usize
    }
    s.n = n
    s.p = p
    s.x = x
    s.xbar = xbar
    s.sdv = sdv
    s.ro = ro
    s.r = rall
    s.npatt = npatt
    s.mdpst = mdpst
    s.nmdp = nmdp
    ret (s, ok)
}

// imp.norm: one imputation of the missing cells given theta; `out` (n by p, row-major, original row order) receives the data with the missing cells drawn
fn imp_norm(a: *mem.Arena, rn: *Rn, x0: []const f64, n: usize, p: usize, theta: []const f64, out: []f64) -> err {
    let (s, e) = prelim(a, x0, n, p)
    if e != ok { ret e }
    let (k, ek) = mkpsi(a, p)
    if ek != ok { ret ek }
    let (tobs, e1) = mem.alloc[f64](a, k.d)
    let (th, e2) = mem.alloc[f64](a, k.d)
    let (t, e3) = mem.alloc[f64](a, k.d)
    let (c, e4) = mem.alloc[f64](a, k.d)
    let (oc, e5) = mem.alloc[usize](a, p)
    let (mc, e6) = mem.alloc[usize](a, p)
    let (z, e7) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var i = 0usize
    while i < k.d {
        th[i] = theta[i]
        c[i] = theta[i]
        i += 1usize
    }
    tobsn(&k, tobs, n, s.x, s.npatt, s.r, s.mdpst, s.nmdp, oc)
    is1n(rn, &k, th, t, tobs, n, s.x, s.npatt, s.r, s.mdpst, s.nmdp, oc, mc, z, c)
    i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            out[i * p + j] = s.x[s.ro[i] * p + j] * s.sdv[j] + s.xbar[j]
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// da.norm: `steps` I and P steps from `start`, with the prior (tau, m, mu0, lambdainv) or the noninformative one (tau 0, m -1, zeros); the new theta goes to `start`
fn da_norm(a: *mem.Arena, rn: *Rn, x0: []const f64, n: usize, p: usize, start: []f64, steps: usize, tau: f64, m: f64, mu0: []const f64, lambdainv: []const f64) -> err {
    let (s, e) = prelim(a, x0, n, p)
    if e != ok { ret e }
    let (k, ek) = mkpsi(a, p)
    if ek != ok { ret ek }
    let (tobs, e1) = mem.alloc[f64](a, k.d)
    let (th, e2) = mem.alloc[f64](a, k.d)
    let (t, e3) = mem.alloc[f64](a, k.d)
    let (c, e4) = mem.alloc[f64](a, k.d)
    let (pri, e8) = mem.alloc[f64](a, k.d)
    let (b, e9) = mem.alloc[f64](a, k.d)
    let (oc, e5) = mem.alloc[usize](a, p)
    let (mc, e6) = mem.alloc[usize](a, p)
    let (z, e7) = mem.alloc[f64](a, p)
    let (mat, e10) = mem.alloc[f64](a, p * p)
    let (ci, e11) = mem.alloc[usize](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret mem.Full }
    var i = 0usize
    while i < k.d {
        pri[i] = 0.0f64
        i += 1usize
    }
    var j = 1usize
    while j <= p {
        pri[ps(&k, 0usize, j)] = mu0[j - 1usize]
        var q = 1usize
        while q <= p {
            pri[ps(&k, j, q)] = lambdainv[(j - 1usize) * p + q - 1usize]
            q += 1usize
        }
        j += 1usize
    }
    tobsn(&k, tobs, n, s.x, s.npatt, s.r, s.mdpst, s.nmdp, oc)
    var st = 0usize
    while st < steps {
        i = 0usize
        while i < k.d {
            th[i] = start[i]
            c[i] = start[i]
            i += 1usize
        }
        is1n(rn, &k, th, t, tobs, n, s.x, s.npatt, s.r, s.mdpst, s.nmdp, oc, mc, z, c)
        i = 0usize
        while i < k.d {
            start[i] = t[i]
            th[i] = pri[i]
            i += 1usize
        }
        ps1n(rn, &k, start, m, tau, th, n, mat, z, b, ci)
        i = 0usize
        while i < k.d {
            start[i] = th[i]
            i += 1usize
        }
        st += 1usize
    }
    ret ok
}

// ninvwish: a draw of the normal-inverted-Wishart distribution with parameters (tau, m, mu0, lambda inverse); `out` receives the packed theta
fn ninvwish(a: *mem.Arena, rn: *Rn, p: usize, tau: f64, m: f64, mu0: []const f64, lambdainv: []const f64, out: []f64) -> err {
    let (k, ek) = mkpsi(a, p)
    if ek != ok { ret ek }
    let (b, e1) = mem.alloc[f64](a, k.d)
    let (mat, e2) = mem.alloc[f64](a, p * p)
    let (z, e3) = mem.alloc[f64](a, p)
    let (ci, e4) = mem.alloc[usize](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var i = 0usize
    while i < k.d {
        out[i] = 0.0f64
        i += 1usize
    }
    var j = 1usize
    while j <= p {
        out[ps(&k, 0usize, j)] = mu0[j - 1usize]
        var q = 1usize
        while q <= p {
            out[ps(&k, j, q)] = lambdainv[(j - 1usize) * p + q - 1usize]
            q += 1usize
        }
        j += 1usize
    }
    ninvwn(rn, &k, out, tau, m, mat, z, b, ci)
    ret ok
}

// ---- monotone data augmentation (mda.norm) ----

fn max0(a: usize, b: usize) -> usize {
    if a > b { ret a }
    ret b
}

// sj(j): the last pattern for which variable j needs imputing to make the pattern monotone; 1-based values over npatt, zero for none
fn sjn(p: usize, npatt: usize, r: []const i64, sj: []usize) {
    var j = 1usize
    while j <= p {
        var patt = npatt + 1usize
        var go = true
        while go {
            patt -= 1usize
            go = false
            if patt >= 1usize {
                if r[(patt - 1usize) * p + j - 1usize] == 0i64 { go = true }
            }
        }
        sj[j - 1usize] = patt
        j += 1usize
    }
    var tmp = sj[p - 1usize]
    j = p - 1usize
    while j >= 1usize {
        sj[j - 1usize] = max0(sj[j - 1usize], tmp)
        tmp = sj[j - 1usize]
        j -= 1usize
    }
}

fn chol2(k: *const Pk, th: []f64, last: usize) {
    var i = 0usize
    while i <= last {
        var tmp = 0.0f64
        var q = 0usize
        while q < i {
            let v = th[ps(k, q, i)]
            tmp += v * v
            q += 1usize
        }
        th[ps(k, i, i)] = math.sqrt[f64](th[ps(k, i, i)] - tmp)
        var j = i + 1usize
        while j <= last {
            tmp = 0.0f64
            q = 0usize
            while q < i {
                tmp += th[ps(k, q, i)] * th[ps(k, q, j)]
                q += 1usize
            }
            th[ps(k, i, j)] = (th[ps(k, i, j)] - tmp) / th[ps(k, i, i)]
            j += 1usize
        }
        i += 1usize
    }
}

fn ph2thn(k: *const Pk, th: []f64) {
    let p = k.p
    var j = 1usize
    while j < p {
        swp(k, th, j, j, 1.0f64)
        j += 1usize
    }
    j = 1usize
    while j < p {
        swp(k, th, j, p, 0.0f64 - 1.0f64)
        j += 1usize
    }
}

// the columns of a pattern with the given code, up to column last
fn gtcols_to(p: usize, r: []const i64, patt: usize, want: i64, last: usize, out: []usize) -> usize {
    var n = 0usize
    var j = 1usize
    while j <= last {
        if r[patt * p + j - 1usize] == want {
            out[n] = j
            n += 1usize
        }
        j += 1usize
    }
    ret n
}

// mda.norm: steps monotone I and P steps from theta; the new theta goes to theta
fn mda_norm(a: *mem.Arena, rn: *Rn, x0: []const f64, n: usize, p: usize, theta: []f64, steps: usize) -> err {
    let (s, e) = prelim(a, x0, n, p)
    if e != ok { ret e }
    let (k, ek) = mkpsi(a, p)
    if ek != ok { ret ek }
    let d = k.d
    let npatt = s.npatt
    let (sj, e1) = mem.alloc[usize](a, p)
    let (nmon, e2) = mem.alloc[usize](a, p)
    let (last, e3) = mem.alloc[usize](a, npatt)
    let (layer, e4) = mem.alloc[usize](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    sjn(p, npatt, s.r, sj)
    var j = 1usize
    while j <= p {
        var c0 = 0usize
        var q = 0usize
        while q < sj[j - 1usize] {
            c0 += s.nmdp[q]
            q += 1usize
        }
        nmon[j - 1usize] = c0
        j += 1usize
    }
    j = p
    while j >= 1usize {
        var start = 1usize
        if j < p { start = sj[j] + 1usize }
        var q = start
        while q <= sj[j - 1usize] {
            last[q - 1usize] = j
            q += 1usize
        }
        j -= 1usize
    }
    var nlayer = 0usize
    j = p
    while j >= 1usize {
        if j == p {
            if sj[j - 1usize] > 0usize { nlayer += 1usize }
        } else if sj[j - 1usize] > sj[j] {
            nlayer += 1usize
        }
        layer[j - 1usize] = nlayer
        j -= 1usize
    }
    let (tobs, e5) = mem.alloc[f64](a, nlayer * d + 1usize)
    let (t, e6) = mem.alloc[f64](a, d)
    let (c, e7) = mem.alloc[f64](a, d)
    let (th, e8) = mem.alloc[f64](a, d)
    let (nt, e9) = mem.alloc[f64](a, d)
    let (oc, e10) = mem.alloc[usize](a, p)
    let (mc, e11) = mem.alloc[usize](a, p)
    let (z, e12) = mem.alloc[f64](a, p)
    let (v, e13) = mem.alloc[f64](a, p + 1usize)
    if e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret mem.Full }
    var i = 0usize
    while i < nlayer * d {
        tobs[i] = 0.0f64
        i += 1usize
    }
    var lpatt = 0usize
    var l = 1usize
    while l <= nlayer {
        let fpatt = lpatt + 1usize
        var jj = p + 1usize
        var go = true
        while go {
            jj -= 1usize
            if layer[jj - 1usize] == l { go = false }
        }
        lpatt = sj[jj - 1usize]
        var patt = fpatt
        while patt <= lpatt {
            let noc = gtcols_to(p, s.r, patt - 1usize, 1i64, last[patt - 1usize], oc)
            var row = s.mdpst[patt - 1usize]
            while row < s.mdpst[patt - 1usize] + s.nmdp[patt - 1usize] {
                tobs[(l - 1usize) * d + ps(&k, 0usize, 0usize)] += 1.0f64
                var q = 0usize
                while q < noc {
                    tobs[(l - 1usize) * d + ps(&k, 0usize, oc[q])] += s.x[row * p + oc[q] - 1usize]
                    var w = q
                    while w < noc {
                        tobs[(l - 1usize) * d + ps(&k, oc[q], oc[w])] += s.x[row * p + oc[q] - 1usize] * s.x[row * p + oc[w] - 1usize]
                        w += 1usize
                    }
                    q += 1usize
                }
                row += 1usize
            }
            patt += 1usize
        }
        l += 1usize
    }
    var st = 0usize
    while st < steps {
        i = 0usize
        while i < d {
            th[i] = theta[i]
            c[i] = theta[i]
            i += 1usize
        }
        var junk = gauss(rn)
        junk += 0.0f64
        var patt = 1usize
        while patt <= npatt {
            swpobs(&k, th, s.r, patt - 1usize)
            let nmc = gtcols_to(p, s.r, patt - 1usize, 0i64, last[patt - 1usize], mc)
            let noc = gtcols_to(p, s.r, patt - 1usize, 1i64, last[patt - 1usize], oc)
            var q = 0usize
            while q < nmc {
                var w = q
                while w < nmc {
                    c[ps(&k, mc[q], mc[w])] = th[ps(&k, mc[q], mc[w])]
                    w += 1usize
                }
                q += 1usize
            }
            chols(&k, c, mc, nmc)
            var row = s.mdpst[patt - 1usize]
            while row < s.mdpst[patt - 1usize] + s.nmdp[patt - 1usize] {
                var jx = 0usize
                while jx < nmc {
                    let cj = mc[jx]
                    var xv = th[ps(&k, 0usize, cj)]
                    q = 0usize
                    while q < noc {
                        xv += th[ps(&k, oc[q], cj)] * s.x[row * p + oc[q] - 1usize]
                        q += 1usize
                    }
                    z[cj - 1usize] = gauss(rn)
                    q = 0usize
                    while q <= jx {
                        xv += z[mc[q] - 1usize] * c[ps(&k, cj, mc[q])]
                        q += 1usize
                    }
                    s.x[row * p + cj - 1usize] = xv
                    jx += 1usize
                }
                row += 1usize
            }
            patt += 1usize
        }
        i = 0usize
        while i < d {
            t[i] = 0.0f64
            nt[i] = 0.0f64
            i += 1usize
        }
        var lsj = 0usize
        var lay = 0usize
        var jc = p
        while jc >= 1usize {
            if sj[jc - 1usize] > lsj {
                lay += 1usize
                t[ps(&k, 0usize, 0usize)] += tobs[(lay - 1usize) * d + ps(&k, 0usize, 0usize)]
                var kk = 1usize
                while kk <= jc {
                    t[ps(&k, 0usize, kk)] += tobs[(lay - 1usize) * d + ps(&k, 0usize, kk)]
                    var m = kk
                    while m <= jc {
                        t[ps(&k, m, kk)] += tobs[(lay - 1usize) * d + ps(&k, m, kk)]
                        m += 1usize
                    }
                    kk += 1usize
                }
                var pt = lsj + 1usize
                while pt <= sj[jc - 1usize] {
                    let nmc = gtcols_to(p, s.r, pt - 1usize, 0i64, jc, mc)
                    let noc = gtcols_to(p, s.r, pt - 1usize, 1i64, jc, oc)
                    var row = s.mdpst[pt - 1usize]
                    while row < s.mdpst[pt - 1usize] + s.nmdp[pt - 1usize] {
                        var q = 0usize
                        while q < nmc {
                            let xm = s.x[row * p + mc[q] - 1usize]
                            t[ps(&k, 0usize, mc[q])] += xm
                            var w = 0usize
                            while w < noc {
                                t[ps(&k, mc[q], oc[w])] += xm * s.x[row * p + oc[w] - 1usize]
                                w += 1usize
                            }
                            w = 0usize
                            while w <= q {
                                t[ps(&k, mc[q], mc[w])] += xm * s.x[row * p + mc[w] - 1usize]
                                w += 1usize
                            }
                            q += 1usize
                        }
                        row += 1usize
                    }
                    pt += 1usize
                }
                kk = 0usize
                while kk < jc {
                    swp(&k, t, kk, jc, 1.0f64)
                    kk += 1usize
                }
            }
            let df = f64(nmon[jc - 1usize] + 3usize * (p - jc)) - 1.0f64
            nt[ps(&k, jc, jc)] = t[ps(&k, jc, jc)] / r32(2.0f64 * gamm(rn, df / 2.0f64))
            var kk = 0usize
            while kk < jc {
                var m = kk
                while m < jc {
                    c[ps(&k, kk, m)] = 0.0f64 - nt[ps(&k, jc, jc)] * t[ps(&k, kk, m)]
                    m += 1usize
                }
                kk += 1usize
            }
            chol2(&k, c, jc - 1usize)
            kk = 0usize
            while kk < jc {
                v[kk] = gauss(rn)
                nt[ps(&k, kk, jc)] = t[ps(&k, kk, jc)]
                var m = 0usize
                while m <= kk {
                    nt[ps(&k, kk, jc)] += c[ps(&k, m, kk)] * v[m]
                    m += 1usize
                }
                kk += 1usize
            }
            if jc > 1usize {
                if sj[jc - 2usize] > sj[jc - 1usize] {
                    kk = 0usize
                    while kk < jc {
                        swp(&k, t, kk, jc - 1usize, 0.0f64 - 1.0f64)
                        kk += 1usize
                    }
                } else if sj[jc - 2usize] == sj[jc - 1usize] {
                    swp(&k, t, jc - 1usize, jc - 1usize, 0.0f64 - 1.0f64)
                }
            }
            lsj = sj[jc - 1usize]
            jc -= 1usize
        }
        nt[ps(&k, 0usize, 0usize)] = 0.0f64 - 1.0f64
        ph2thn(&k, nt)
        i = 0usize
        while i < d {
            theta[i] = nt[i]
            i += 1usize
        }
        st += 1usize
    }
    ret ok
}

// getparam.norm: mu and sigma (row-major) on the original scale from a theta
fn getparam(k: *const Pk, theta: []const f64, xbar: []const f64, sdv: []const f64, mu: []f64, sigma: []f64) {
    let p = k.p
    var j = 1usize
    while j <= p {
        mu[j - 1usize] = theta[ps(k, 0usize, j)] * sdv[j - 1usize] + xbar[j - 1usize]
        var q = 1usize
        while q <= p {
            sigma[(j - 1usize) * p + q - 1usize] = theta[ps(k, j, q)] * sdv[j - 1usize] * sdv[q - 1usize]
            q += 1usize
        }
        j += 1usize
    }
}

// makeparam.norm for a (mu, sigma) pair: the theta on the standardised scale
fn makeparam(k: *const Pk, mu: []const f64, sigma: []const f64, xbar: []const f64, sdv: []const f64, out: []f64) {
    let p = k.p
    var i = 0usize
    while i < k.d {
        out[i] = 0.0f64
        i += 1usize
    }
    out[0usize] = 0.0f64 - 1.0f64
    var j = 1usize
    while j <= p {
        out[ps(k, 0usize, j)] = (mu[j - 1usize] - xbar[j - 1usize]) / sdv[j - 1usize]
        var q = 1usize
        while q <= p {
            out[ps(k, j, q)] = sigma[(j - 1usize) * p + q - 1usize] / (sdv[j - 1usize] * sdv[q - 1usize])
            q += 1usize
        }
        j += 1usize
    }
}
