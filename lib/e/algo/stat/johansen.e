// R urca::ca.jo, the Johansen procedure: the eigenvalues, the trace or maximal-eigenvalue statistics with the package's
// critical values, and the normalised eigenvectors V, the loadings W, PI and GAMMA, for the specifications longrun and
// transitory, the ecdet none, const and trend, and seasonal dummies.
//
// Not here: the exogenous dummy variables (`dumvar`), missing values, the tests of restrictions (alrtest, blrtest, ...).

use e.algo.linalg.decomp as decomp
use e.algo.stat.urca2 as u2
use e.math
use e.mem

error Singular

type Johansen = struct { lambda: []f64, teststat: []f64, v: []f64, w: []f64, pi: []f64, gamma: []f64, kdim: usize, p: usize }

// c = x (m x n) * y (n x q), row-major
fn mm(a: *mem.Arena, x: []const f64, y: []const f64, m: usize, n: usize, q: usize) -> []f64 {
    let (c, e) = mem.alloc[f64](a, m * q + 1usize)
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
    ret c[0usize..m * q]
}

fn tr(a: *mem.Arena, x: []const f64, m: usize, n: usize) -> []f64 {
    let (c, e) = mem.alloc[f64](a, m * n + 1usize)
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            c[j * m + i] = x[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    ret c[0usize..m * n]
}

fn sub(x: []const f64, y: []const f64, out: []f64) {
    var i = 0usize
    while i < out.len {
        out[i] = x[i] - y[i]
        i += 1usize
    }
}

fn inverse(a: *mem.Arena, x: []const f64, k: usize) -> ([]f64, bool) {
    let (o, e) = mem.alloc[f64](a, k * k + 1usize)
    let good = u2.inv_small(a, x, k, o)
    ret (o[0usize..k * k], good)
}

// x is n by p column-major; type 0 eigen, 1 trace; ecdet 0 none, 1 const, 2 trend; spec 0 longrun, 1 transitory; season 0 for none
fn ca_jo(a: *mem.Arena, x: []const f64, n: usize, p0: usize, qtype: u8, ecdet: u8, k: usize, spec: u8, season: usize) -> (Johansen, err) {
    var out: Johansen = zero
    // Z0 and Z1: embed(diff(x), K) over the rows t = 1 .. n - K
    let nn = n - k
    var pk = p0
    if ecdet >= 1u8 { pk += 1usize }
    // Z1: the lagged differences (and the constant for ecdet none or trend, the seasonal dummies)
    var n1 = p0 * (k - 1usize)
    if ecdet != 1u8 { n1 += 1usize }
    if season > 0usize { n1 += season - 1usize }
    let (z0, e0) = mem.alloc[f64](a, nn * p0)
    let (z1, e1) = mem.alloc[f64](a, nn * n1)
    let (zk, e2) = mem.alloc[f64](a, nn * pk)
    if e0 != ok || e1 != ok || e2 != ok { ret (out, e0) }
    var t = 0usize
    while t < nn {
        // 0-based row t: Z0 = diff at observation t + K, i.e. x[t + k] - x[t + k - 1]
        var j = 0usize
        while j < p0 {
            z0[t * p0 + j] = x[j * n + t + k] - x[j * n + t + k - 1usize]
            j += 1usize
        }
        var c = 0usize
        if ecdet != 1u8 {
            z1[t * n1] = 1.0f64
            c = 1usize
        }
        if season > 0usize {
            var q = 0usize
            while q + 1usize < season {
                // the seasonal dummies of observation index t + K (0-based): (indicator - 1 / season) in column q
                let ob = (t + k) % season
                var v = 0.0f64 - 1.0f64 / f64(season)
                if ob == q { v = 1.0f64 - 1.0f64 / f64(season) }
                z1[t * n1 + c] = v
                c += 1usize
                q += 1usize
            }
        }
        var lag = 1usize
        while lag < k {
            j = 0usize
            while j < p0 {
                z1[t * n1 + c] = x[j * n + t + k - lag] - x[j * n + t + k - lag - 1usize]
                c += 1usize
                j += 1usize
            }
            lag += 1usize
        }
        // ZK: the level at lag K (longrun) or 1 (transitory)
        var base = t
        if spec == 1u8 { base = t + k - 1usize }
        j = 0usize
        while j < p0 {
            zk[t * pk + j] = x[j * n + base]
            j += 1usize
        }
        if ecdet == 1u8 { zk[t * pk + p0] = 1.0f64 }
        if ecdet == 2u8 { zk[t * pk + p0] = f64(base + 1usize) }
        t += 1usize
    }
    let nf = f64(nn)
    let z0t = tr(a, z0, nn, p0)
    let z1t = tr(a, z1, nn, n1)
    let zkt = tr(a, zk, nn, pk)
    let m00 = mm(a, z0t, z0, p0, nn, p0)
    let m11 = mm(a, z1t, z1, n1, nn, n1)
    let mkk = mm(a, zkt, zk, pk, nn, pk)
    let m01 = mm(a, z0t, z1, p0, nn, n1)
    let m0k = mm(a, z0t, zk, p0, nn, pk)
    let mk1 = mm(a, zkt, z1, pk, nn, n1)
    var i = 0usize
    while i < p0 * p0 { m00[i] = m00[i] / nf
        i += 1usize }
    i = 0usize
    while i < n1 * n1 { m11[i] = m11[i] / nf
        i += 1usize }
    i = 0usize
    while i < pk * pk { mkk[i] = mkk[i] / nf
        i += 1usize }
    i = 0usize
    while i < p0 * n1 { m01[i] = m01[i] / nf
        i += 1usize }
    i = 0usize
    while i < p0 * pk { m0k[i] = m0k[i] / nf
        i += 1usize }
    i = 0usize
    while i < pk * n1 { mk1[i] = mk1[i] / nf
        i += 1usize }
    let m10 = tr(a, m01, p0, n1)
    let m1k = tr(a, mk1, pk, n1)
    let mk0 = tr(a, m0k, p0, pk)
    let (m11i, g1) = inverse(a, m11, n1)
    if !g1 { ret (out, Singular) }
    let m01i = mm(a, m01, m11i, p0, n1, n1)
    let mk1i = mm(a, mk1, m11i, pk, n1, n1)
    let s00 = mm(a, m01i, m10, p0, n1, p0)
    let s0k = mm(a, m01i, m1k, p0, n1, pk)
    let sk0 = mm(a, mk1i, m10, pk, n1, p0)
    let skk = mm(a, mk1i, m1k, pk, n1, pk)
    sub(m00, s00, s00)
    sub(m0k, s0k, s0k)
    sub(mk0, sk0, sk0)
    sub(mkk, skk, skk)
    // the Cholesky factor C (lower) of SKK
    let (c, ce) = mem.alloc[f64](a, pk * pk)
    if ce != ok { ret (out, ce) }
    i = 0usize
    while i < pk * pk {
        c[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < pk {
        var j = 0usize
        while j <= i {
            var s = skk[i * pk + j]
            var q = 0usize
            while q < j {
                s -= c[i * pk + q] * c[j * pk + q]
                q += 1usize
            }
            if i == j {
                if s <= 0.0f64 { ret (out, Singular) }
                c[i * pk + i] = math.sqrt[f64](s)
            } else {
                c[i * pk + j] = s / c[j * pk + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    let (ci, g2) = inverse(a, c, pk)
    let (s00i, g3) = inverse(a, s00, p0)
    if !g2 || !g3 { ret (out, Singular) }
    let cit = tr(a, ci, pk, pk)
    // A = Cinv SK0 S00inv S0K t(Cinv), symmetrised against rounding
    let am0 = mm(a, mm(a, mm(a, ci, sk0, pk, pk, p0), s00i, pk, p0, p0), s0k, pk, p0, pk)
    let am = mm(a, am0, cit, pk, pk, pk)
    i = 0usize
    while i < pk {
        var j = 0usize
        while j < i {
            let av = (am[i * pk + j] + am[j * pk + i]) / 2.0f64
            am[i * pk + j] = av
            am[j * pk + i] = av
            j += 1usize
        }
        i += 1usize
    }
    let (eg, ee) = decomp.eigen(a, am, pk)
    if ee != ok { ret (out, ee) }
    let (lam, le) = mem.alloc[f64](a, pk)
    if le != ok { ret (out, le) }
    // the eigenvectors, the columns of vre (column-major)
    let (ev, eve) = mem.alloc[f64](a, pk * pk)
    if eve != ok { ret (out, eve) }
    // the order of R's eigen: eigenvalues decreasing, the vectors carried along
    let (ord, oe2) = mem.alloc[usize](a, pk)
    if oe2 != ok { ret (out, oe2) }
    i = 0usize
    while i < pk {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < pk {
        let key = ord[i]
        var j = i
        while j > 0usize && eg.re[ord[j - 1usize]] < eg.re[key] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = key
        i += 1usize
    }
    i = 0usize
    while i < pk {
        lam[i] = eg.re[ord[i]]
        var j = 0usize
        while j < pk {
            ev[j * pk + i] = eg.vre[ord[i] * pk + j]
            j += 1usize
        }
        i += 1usize
    }
    let v0 = mm(a, cit, ev, pk, pk, pk)
    // V[, x] / V[1, x]
    let (vv, ve2) = mem.alloc[f64](a, pk * pk)
    if ve2 != ok { ret (out, ve2) }
    i = 0usize
    while i < pk {
        var j = 0usize
        while j < pk {
            vv[i * pk + j] = v0[i * pk + j] / v0[j]
            j += 1usize
        }
        i += 1usize
    }
    let vt = tr(a, vv, pk, pk)
    let vskkv = mm(a, mm(a, vt, skk, pk, pk, pk), vv, pk, pk, pk)
    let (vsi, g4) = inverse(a, vskkv, pk)
    if !g4 { ret (out, Singular) }
    let w = mm(a, mm(a, s0k, vv, p0, pk, pk), vsi, p0, pk, pk)
    let (skki, g5) = inverse(a, skk, pk)
    if !g5 { ret (out, Singular) }
    let pim = mm(a, s0k, skki, p0, pk, pk)
    // GAMMA = M01 M11inv - PI MK1 M11inv
    let pmk = mm(a, pim, mk1i, p0, pk, n1)
    let (gam, gme) = mem.alloc[f64](a, p0 * n1)
    if gme != ok { ret (out, gme) }
    i = 0usize
    while i < p0 * n1 {
        gam[i] = m01i[i] - pmk[i]
        i += 1usize
    }
    // the statistics: reversed over idx = 0 .. P - 1 (the original number of variables)
    let (ts, tse) = mem.alloc[f64](a, p0)
    if tse != ok { ret (out, tse) }
    var xx = 0usize
    while xx < p0 {
        var val = 0.0f64
        if qtype == 1u8 {
            var q = xx
            while q < pk {
                val += math.log[f64](1.0f64 - lam[q])
                q += 1usize
            }
            val = 0.0f64 - nf * val
        } else {
            val = 0.0f64 - nf * math.log[f64](1.0f64 - lam[xx])
        }
        // rev(): the last index first
        ts[p0 - 1usize - xx] = val
        xx += 1usize
    }
    out.lambda = lam
    out.teststat = ts
    out.v = vv
    out.w = w
    out.pi = pim
    out.gamma = gam
    out.kdim = pk
    out.p = p0
    ret (out, ok)
}

// the critical values of ca.jo: row r (1 .. arrsel) and level (0 10%, 1 5%, 2 1%)
fn jo_cval(a: *mem.Arena, qtype: u8, ecdet: u8, row: usize, level: usize) -> f64 {
    var text = "6.5 12.91 18.9 24.78 30.84 36.25 42.06 48.43 54.01 59.0 65.07 8.18 14.90 21.07 27.14 33.32 39.43 44.91 51.07 57.00 62.42 68.27 11.65 19.19 25.75 32.14 38.78 44.59 51.30 57.07 63.37 68.61 74.36 6.50 15.66 28.71 45.23 66.49 85.18 118.99 151.38 186.54 226.34 269.53 8.18 17.95 31.52 48.28 70.6 90.39 124.25 157.11 192.84 232.49 277.39 11.65 23.52 37.22 55.43 78.87 104.20 136.06 168.92 204.79 246.27 292.65"
    if ecdet == 1u8 { text = "7.52 13.75 19.77 25.56 31.66 37.45 43.25 48.91 54.35 60.25 66.02 9.24 15.67 22.00 28.14 34.40 40.30 46.45 52.00 57.42 63.57 69.74 12.97 20.20 26.81 33.24 39.79 46.82 51.91 57.95 63.71 69.94 76.63 7.52 17.85 32.00 49.65 71.86 97.18 126.58 159.48 196.37 236.54 282.45 9.24 19.96 34.91 53.12 76.07 102.14 131.70 165.58 202.92 244.15 291.40 12.97 24.60 41.07 60.16 84.45 111.01 143.09 177.20 215.74 257.68 307.64" }
    if ecdet == 2u8 { text = "10.49 16.85 23.11 29.12 34.75 40.91 46.32 52.16 57.87 63.18 69.26 12.25 18.96 25.54 31.46 37.52 43.97 49.42 55.50 61.29 66.23 72.72 16.26 23.65 30.34 36.65 42.36 49.51 54.71 62.46 67.88 73.73 79.23 10.49 22.76 39.06 59.14 83.20 110.42 141.01 176.67 215.17 256.72 303.13 12.25 25.32 42.44 62.99 87.31 114.90 146.76 182.82 222.21 263.42 310.81 16.26 30.45 48.45 70.05 96.58 124.75 158.49 196.08 234.41 279.07 327.45" }
    let (tb, e) = u2.numlist(a, text, 66usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var t = 0usize
    if qtype == 1u8 { t = 1usize }
    ret tb[row + 11usize * level + 33usize * t]
}
