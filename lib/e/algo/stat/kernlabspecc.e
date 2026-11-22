// R kernlab specc on matrix input: the automatic sigma search (the log-spaced and linear sigma grid of specc.R, each candidate scored by the
// within sums of squares of R's kmeans) or a given kernel, the row-normalised top eigenvectors of D K D (R's eigen, LAPACK dsyevr) and the final
// kmeans, all on R's random stream. Matrices are row-major; kernels come from kernlabmmd.cross.
//
// Not here: local scaling (kpar = "local"), the Nystrom reduction, string kernels.

use e.algo.linalg.lapack_syevr as sy
use e.algo.rand.r as rr
use e.algo.stat.armld as ld
use e.algo.stat.fpc_km as fk
use e.algo.stat.kernlabmmd as km
use e.math
use e.mem

error Fail

// seq(from, to, by) as seq.default answers it: the values (one value when from == to), or an error where R stops
fn seq_by(a: *mem.Arena, from: f64, to: f64, by: f64) -> ([]f64, err) {
    var none: []f64 = zero
    let del = to - from
    var n = 0.0f64
    if del != 0.0f64 || to != 0.0f64 {
        if !(by == 0.0f64 && del == 0.0f64) {
            n = del / by
            if n != n || n - n != 0.0f64 { ret (none, Fail) }
            if n < 0.0f64 { ret (none, Fail) }
        }
    }
    var mx = to
    if mx < 0.0f64 { mx = 0.0f64 - mx }
    var af = from
    if af < 0.0f64 { af = 0.0f64 - af }
    if af > mx { mx = af }
    var ad = del
    if ad < 0.0f64 { ad = 0.0f64 - ad }
    var cnt = 1usize
    if del != 0.0f64 && ad / mx >= 100.0f64 * 2.220446049250313e-16f64 { cnt = usize(n + 1.0e-10f64) + 1usize }
    let (v, e) = mem.alloc[f64](a, cnt)
    if e != ok { ret (none, e) }
    var i = 0usize
    while i < cnt {
        v[i] = from + f64(i) * by
        if cnt > 1usize {
            if by > 0.0f64 && v[i] > to { v[i] = to }
            if by < 0.0f64 && v[i] < to { v[i] = to }
        }
        i += 1usize
    }
    if cnt == 1usize { v[0usize] = from }
    ret (v, ok)
}

// yi (n by nc) = the row-normalised top nc eigenvectors of D km D (D = 1 / sqrt(rowSums(km))); the flag is false when D is unusable and check is set
fn embed(a: *mem.Arena, kmm: []const f64, n: usize, nc: usize, check: bool, yi: []f64) -> (bool, err) {
    let (d, e1) = mem.alloc[f64](a, n)
    let (xc, e2) = mem.alloc[f64](a, n * n)
    let (w, e3) = mem.alloc[f64](a, n)
    let (z, e4) = mem.alloc[f64](a, n * n)
    let (sq, e5) = mem.alloc[f64](a, nc)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (false, Fail) }
    var i = 0usize
    var dmax = 0.0f64 - 1.0f64 / 0.0f64
    var dmin = 1.0f64 / 0.0f64
    var bad = false
    while i < n {
        d[i] = 1.0f64 / math.sqrt[f64](ld.sum_ld(kmm[i * n..(i + 1usize) * n]))
        if d[i] != d[i] || d[i] - d[i] != 0.0f64 { bad = true }
        if d[i] > dmax { dmax = d[i] }
        if d[i] < dmin { dmin = d[i] }
        i += 1usize
    }
    if check && (bad || dmax - dmin >= 10000.0f64) { ret (false, ok) }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            xc[i + j * n] = d[i] * (kmm[i * n + j] * d[j])
            j += 1usize
        }
        i += 1usize
    }
    let e = sy.dsyevr_all(a, xc, n, w, z)
    if e != ok { ret (false, e) }
    i = 0usize
    while i < n {
        var c = 0usize
        while c < nc {
            yi[i * nc + c] = z[(n - 1usize - c) * n + i]
            sq[c] = yi[i * nc + c] * yi[i * nc + c]
            c += 1usize
        }
        let rs = math.sqrt[f64](ld.sum_ld(sq[0usize..nc]))
        c = 0usize
        while c < nc {
            yi[i * nc + c] = yi[i * nc + c] / rs
            c += 1usize
        }
        i += 1usize
    }
    ret (true, ok)
}

// the sigma the automatic search picks (rbfdot's sigma = tmpsig^-2 / 2) on the subsample of mod_sample * m rows
fn auto_sigma(a: *mem.Arena, g: *rr.Rng, x: []const f64, m: usize, p: usize, nc: usize, mod_sample: f64, iters: usize) -> (f64, err) {
    let (kcent, e4) = mem.alloc[f64](a, nc * nc)
    let (kwss, e5) = mem.alloc[f64](a, nc)
    let (ksz, e6) = mem.alloc[usize](a, nc + 1usize)
    var info: [5]f64 = zero
    if e4 != ok || e5 != ok || e6 != ok { ret (0.0f64, Fail) }
    let ns0 = usize(mod_sample * f64(m))
    let (sam, f1) = rr.sample_int(a, g, i64(m), i64(ns0), false)
    let (sx, f2) = mem.alloc[f64](a, ns0 * p)
    if f1 != ok || f2 != ok { ret (0.0f64, Fail) }
    var ns = 0usize
    var i = 0usize
    while i < ns0 {
        var seen = false
        var j = 0usize
        while j < ns {
            var same = true
            var q = 0usize
            while q < p {
                if sx[j * p + q] != x[(usize(sam[i]) - 1usize) * p + q] { same = false }
                q += 1usize
            }
            if same { seen = true }
            j += 1usize
        }
        if !seen {
            var q = 0usize
            while q < p {
                sx[ns * p + q] = x[(usize(sam[i]) - 1usize) * p + q]
                q += 1usize
            }
            ns += 1usize
        }
        i += 1usize
    }
    let (kt, f3) = mem.alloc[f64](a, ns * ns)
    let (dota, f4) = mem.alloc[f64](a, ns)
    let (sqv, f5) = mem.alloc[f64](a, p)
    if f3 != ok || f4 != ok || f5 != ok { ret (0.0f64, Fail) }
    i = 0usize
    while i < ns {
        var q = 0usize
        while q < p {
            sqv[q] = sx[i * p + q] * sx[i * p + q]
            q += 1usize
        }
        dota[i] = ld.sum_ld(sqv[0usize..p]) / 2.0f64
        i += 1usize
    }
    i = 0usize
    while i < ns {
        var j = 0usize
        while j < ns {
            var dot = 0.0f64
            var q = 0usize
            while q < p {
                dot += sx[i * p + q] * sx[j * p + q]
                q += 1usize
            }
            var v = 2.0f64 * ((0.0f64 - dot + dota[j]) + dota[i])
            if v < 0.0f64 { v = 0.0f64 }
            kt[i * ns + j] = math.sqrt[f64](v)
            j += 1usize
        }
        i += 1usize
    }
    var kmax = kt[0usize]
    var kmin = 1.0f64 / 0.0f64
    i = 0usize
    while i < ns {
        var j = 0usize
        while j < ns {
            if kt[i * ns + j] > kmax { kmax = kt[i * ns + j] }
            if i != j && kt[i * ns + j] < kmin { kmin = kt[i * ns + j] }
            j += 1usize
        }
        i += 1usize
    }
    let kmea = ld.sum_ld(kt[0usize..ns * ns]) / f64(ns * ns)
    let lsmin = math.log2[f64](kmin)
    let lsmax = math.log2[f64](kmax)
    var midmax = 2.0f64 * kmea
    if kmax < midmax { midmax = kmax }
    var midmin = kmea / 2.0f64
    if kmin > midmin { midmin = kmin }
    let (r1, g1) = seq_by(a, midmin, 0.9f64 * kmea, 0.05f64 * kmea)
    let (r2, g2) = seq_by(a, kmea, midmax, 0.08f64 * kmea)
    if g1 != ok || g2 != ok { ret (0.0f64, Fail) }
    var step = 0.5f64
    if lsmax - (math.log2[f64](midmax) + 0.5f64) < 0.5f64 { step = lsmax - (math.log2[f64](midmax) + 0.5f64) }
    var stepm = 0.5f64
    if (math.log2[f64](midmin) - 0.5f64) - lsmin < 0.5f64 { stepm = (math.log2[f64](midmin) - 0.5f64) - lsmin }
    let (s1, g3) = seq_by(a, lsmin, math.log2[f64](midmin) - 0.5f64, stepm)
    let (s3, g4) = seq_by(a, math.log2[f64](midmax) + 0.5f64, lsmax, step)
    if g3 != ok || g4 != ok { ret (0.0f64, Fail) }
    let nsig = s1.len + r1.len + r2.len + s3.len
    let (ts, g5) = mem.alloc[f64](a, nsig)
    let (diss, g6) = mem.alloc[f64](a, nsig * nc)
    let (ka, g7) = mem.alloc[f64](a, ns * ns)
    let (yk, g8) = mem.alloc[f64](a, ns * nc)
    let (kk2, g9) = mem.alloc[usize](a, ns + 1usize)
    if g5 != ok || g6 != ok || g7 != ok || g8 != ok || g9 != ok { ret (0.0f64, Fail) }
    var t = 0usize
    i = 0usize
    while i < s1.len {
        ts[t] = math.pow[f64](2.0f64, s1[i])
        t += 1usize
        i += 1usize
    }
    i = 0usize
    while i < r1.len {
        ts[t] = r1[i]
        t += 1usize
        i += 1usize
    }
    i = 0usize
    while i < r2.len {
        ts[t] = r2[i]
        t += 1usize
        i += 1usize
    }
    i = 0usize
    while i < s3.len {
        ts[t] = math.pow[f64](2.0f64, s3[i])
        t += 1usize
        i += 1usize
    }
    t = 0usize
    while t < nsig {
        var c = 0usize
        while c < nc {
            diss[t * nc + c] = 1.0f64 / 0.0f64
            c += 1usize
        }
        let st = mem.mark(a)
        i = 0usize
        while i < ns {
            var j = 0usize
            while j < ns {
                ka[i * ns + j] = 0.0f64
                if i != j { ka[i * ns + j] = math.exp[f64]((0.0f64 - kt[i * ns + j] * kt[i * ns + j]) / (2.0f64 * (ts[t] * ts[t]))) }
                j += 1usize
            }
            i += 1usize
        }
        let (okk, h1) = embed(a, ka, ns, nc, true, yk)
        if h1 != ok { ret (0.0f64, h1) }
        if okk {
            let (cc, h2) = fk.kmeans_hw(a, g, yk, ns, nc, nc, iters, 1usize, kk2, kcent, kwss, ksz, info[0usize..5usize])
            if h2 != ok || cc != 0usize { ret (0.0f64, Fail) }
            c = 0usize
            while c < nc {
                diss[t * nc + c] = kwss[c]
                c += 1usize
            }
        }
        mem.reset(a, st)
        t += 1usize
    }
    var best = 0usize
    var bv = 0.0f64
    t = 0usize
    while t < nsig {
        let rs = ld.sum_ld(diss[t * nc..(t + 1usize) * nc])
        if t == 0usize || rs < bv {
            bv = rs
            best = t
        }
        t += 1usize
    }
    ret (1.0f64 / (ts[best] * ts[best]) / 2.0f64, ok)
}

// specc: cl (m, 1-based labels), size (nc + 1, from 1), cent (nc by p, colMeans of each cluster), wss (nc, the within sums of squares about those), sig (1, the sigma used)
fn specc(a: *mem.Arena, g: *rr.Rng, x: []const f64, m: usize, p: usize, nc: usize, kind: usize, par1: f64, auto: bool, mod_sample: f64, iters: usize, cl: []usize, size: []usize, cent: []f64, wss: []f64, sig: []f64) -> err {
    var sigma = par1
    var kd = kind
    if auto {
        let (sg, ae) = auto_sigma(a, g, x, m, p, nc, mod_sample, iters)
        if ae != ok { ret ae }
        sigma = sg
        kd = 0usize
    }
    let (kmm, e1) = mem.alloc[f64](a, m * m)
    let (yi, e2) = mem.alloc[f64](a, m * nc)
    let (kc, e3) = mem.alloc[usize](a, m + 1usize)
    let (kcent, e4) = mem.alloc[f64](a, nc * nc)
    let (kwss, e5) = mem.alloc[f64](a, nc)
    let (ksz, e6) = mem.alloc[usize](a, nc + 1usize)
    let (tmp, e7) = mem.alloc[f64](a, m * p)
    var info: [5]f64 = zero
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret Fail }
    sig[0usize] = sigma
    km.cross(true, kd, x, x, m, m, p, sigma, 0.0f64, 0.0f64, kmm)
    var i = 0usize
    if kd == 0usize {
        while i < m {
            kmm[i * m + i] = 0.0f64
            i += 1usize
        }
    }
    let (okf, h3) = embed(a, kmm, m, nc, false, yi)
    if h3 != ok { ret h3 }
    let (cc, h4) = fk.kmeans_hw(a, g, yi, m, nc, nc, iters, 1usize, kc, kcent, kwss, ksz, info[0usize..5usize])
    if h4 != ok || cc != 0usize { ret Fail }
    i = 0usize
    while i < m {
        cl[i] = kc[i + 1usize]
        i += 1usize
    }
    var c = 0usize
    while c < nc + 1usize {
        size[c] = ksz[c]
        c += 1usize
    }
    c = 0usize
    while c < nc {
        var q = 0usize
        while q < p {
            var cnt = 0usize
            i = 0usize
            while i < m {
                if cl[i] == c + 1usize {
                    tmp[cnt] = x[i * p + q]
                    cnt += 1usize
                }
                i += 1usize
            }
            cent[c * p + q] = ld.sum_ld(tmp[0usize..cnt]) / f64(cnt)
            q += 1usize
        }
        var nl = 0usize
        i = 0usize
        while i < m {
            if cl[i] == c + 1usize { nl += 1usize }
            i += 1usize
        }
        // R recycles cent[c, ] down the column-major matrix x[rows, ] - cent[c, ], so element e is taken against cent[c, e mod p]
        var cnt = 0usize
        q = 0usize
        while q < p {
            i = 0usize
            while i < m {
                if cl[i] == c + 1usize {
                    let ce = cent[c * p + (cnt % p)]
                    tmp[cnt] = (x[i * p + q] - ce) * (x[i * p + q] - ce)
                    cnt += 1usize
                }
                i += 1usize
            }
            q += 1usize
        }
        wss[c] = ld.sum_ld(tmp[0usize..cnt])
        c += 1usize
    }
    ret ok
}
