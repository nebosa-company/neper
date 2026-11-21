// R bayesm: the scale-usage sampler rscaleUsage, equal to the package under set.seed (keep = 1, every draw switched on).
//
// Matrices are column-major as R passes them; draw rep is Sigma (p p), mu (p), tau (n), sigma (n), Lambda (4, column-major) and e.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.bayesmgibbs as bg
use e.algo.stat.bayesmpkg as bz
use e.math
use e.math.dist as mdist
use e.mem

// cgetC(e, k): the k + 1 sorted cutoffs into c; false when no solution exists
fn cget_c(e: f64, k: usize, c: []f64) -> bool {
    var m1 = 0.0f64
    var m2 = 0.0f64
    var i = 0usize
    while i + 1usize < k {
        let t = f64(i) + 1.5f64
        m1 += t
        m2 += t * t
        i += 1usize
    }
    let s0 = f64(k) - 1.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    var s3 = 0.0f64
    var s4 = 0.0f64
    i = 1usize
    while i < k {
        let fi = f64(i)
        s1 += fi
        s2 += fi * fi
        s3 += fi * fi * fi
        s4 += fi * fi * fi * fi
        i += 1usize
    }
    let aq = s0 * s2 - s1 * s1
    let bq = 2.0f64 * e * s0 * s3 - 2.0f64 * e * s1 * s2
    let cq = m1 * m1 - m2 * s0 + e * e * s0 * s4 - e * e * s2 * s2
    let det = bq * bq - 4.0f64 * aq * cq
    if det < 0.0f64 { ret false }
    let b = (-bq + math.sqrt[f64](det)) / (2.0f64 * aq)
    let aa = (m1 - b * s1 - e * s2) / s0
    c[0usize] = -1000.0f64
    c[k] = 1000.0f64
    i = 1usize
    while i < k {
        let fi = f64(i)
        c[i] = aa + b * fi + e * fi * fi
        i += 1usize
    }
    // insertion sort
    i = 1usize
    while i <= k {
        let v = c[i]
        var j = i
        while j > 0usize && c[j - 1usize] > v {
            c[j] = c[j - 1usize]
            j -= 1usize
        }
        c[j] = v
        i += 1usize
    }
    ret true
}

// ghk with the lower factor l (dim by dim) over a[j] <= x_j <= b[j]; z is dim scratch
fn ghk(r: *rng.Rng, l: []const f64, lo: []const f64, hi: []const f64, n: usize, dim: usize, z: []f64) -> f64 {
    var res = 0.0f64
    var i = 0usize
    while i < n {
        var prod = 1.0f64
        var j = 0usize
        while j < dim {
            var mu = 0.0f64
            var t = 0usize
            while t < j {
                mu += l[t * dim + j] * z[t]
                t += 1usize
            }
            let aa = (lo[j] - mu) / l[j * dim + j]
            let bb = (hi[j] - mu) / l[j * dim + j]
            let pa = mdist.pnorm(aa, 0.0f64, 1.0f64, true, false)
            let pb = mdist.pnorm(bb, 0.0f64, 1.0f64, true, false)
            prod *= pb - pa
            let u = rng.unif(r)
            var arg = u * pb + (1.0f64 - u) * pa
            if arg > 0.999999999f64 { arg = 0.999999999f64 }
            if arg < 0.0000000001f64 { arg = 0.0000000001f64 }
            z[j] = mdist.qnorm(arg, 0.0f64, 1.0f64, true, false)
            j += 1usize
        }
        res += prod
        i += 1usize
    }
    ret res / f64(n)
}

// rlpx: the log likelihood of the data for the cutoff parameter e; u is the upper Cholesky factor of Sigma
fn rlpx(a: *mem.Arena, r: *rng.Rng, x: []const f64, n: usize, p: usize, k: usize, e: f64, mu: []const f64, tau: []const f64, u: []const f64, sigma: []const f64, nd: usize) -> (f64, err) {
    let start = mem.mark(a)
    let (cc, e1) = bg.zal(a, k + 1usize)
    let (li, e2) = bg.zal(a, p * p)
    let (lo, e3) = bg.zal(a, p)
    let (hi, e4) = bg.zal(a, p)
    let (z, e5) = bg.zal(a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0.0f64, mem.Full) }
    if !cget_c(e, k, cc) { ret (0.0f64, mem.Full) }
    let offset = f64(p) * math.log[f64](f64(k))
    var sum = 0.0f64
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            var rr = 0usize
            while rr < p {
                // L = U'
                li[c * p + rr] = sigma[i] * u[rr * p + c]
                rr += 1usize
            }
            c += 1usize
        }
        c = 0usize
        while c < p {
            let xi = usize(x[c * n + i])
            lo[c] = cc[xi - 1usize] - mu[c] - tau[i]
            hi[c] = cc[xi] - mu[c] - tau[i]
            c += 1usize
        }
        var g = ghk(r, li, lo, hi, nd, p, z)
        if g < 2.2250738585072014e-308f64 { g = 2.2250738585072014e-308f64 }
        sum += math.log[f64](g) + offset
        i += 1usize
    }
    mem.reset(a, start)
    ret (sum, ok)
}

// exp-normalise the log weights pv and draw one grid value as sample(g, 1, false, pv)
fn grid_draw(a: *mem.Arena, r: *rng.Rng, g: []const f64, pv: []f64) -> (f64, err) {
    var mx = pv[0usize]
    var i = 1usize
    while i < pv.len {
        if pv[i] > mx { mx = pv[i] }
        i += 1usize
    }
    var s = 0.0f64
    i = 0usize
    while i < pv.len {
        pv[i] = math.exp[f64](pv[i] - mx)
        s += pv[i]
        i += 1usize
    }
    i = 0usize
    while i < pv.len {
        pv[i] = pv[i] / s
        i += 1usize
    }
    let (idx, se) = rd.sample_prob(a, r, pv.len, 1usize, false, pv)
    if se != ok { ret (0.0f64, se) }
    ret (g[usize(idx[0usize] - 1i64)], ok)
}

// the Lambda likelihood on the grid: lam, ss and vl are 2 by 2 column-major
fn ll_lam(lam: []const f64, n: f64, ss: []const f64, vl: []const f64, nu: f64) -> f64 {
    let dlam = lam[0usize] * lam[3usize] - lam[2usize] * lam[2usize]
    let i00 = lam[3usize] / dlam
    let i01 = -lam[2usize] / dlam
    let i10 = -lam[1usize] / dlam
    let i11 = lam[0usize] / dlam
    let tr = (ss[0usize] + vl[0usize]) * i00 + (ss[2usize] + vl[2usize]) * i10 + (ss[1usize] + vl[1usize]) * i01 + (ss[3usize] + vl[3usize]) * i11
    ret -0.5f64 * (n + nu + 3.0f64) * math.log[f64](dlam) - 0.5f64 * tr
}

fn get_s(lam: []const f64, n: f64, m: []const f64, ss: []f64) {
    ss[0usize] = (n - 1.0f64) * m[2usize] + n * m[0usize] * m[0usize]
    ss[2usize] = (n - 1.0f64) * m[3usize] + n * m[0usize] * (m[1usize] - lam[3usize])
    ss[1usize] = ss[2usize]
    ss[3usize] = (n - 1.0f64) * m[4usize] + n * (m[1usize] - lam[3usize]) * (m[1usize] - lam[3usize])
}

// rscaleUsage with keep = 1; x is n by p with entries 1..k, y0 n by p; out gets nr draws of Sigma, mu, tau, sigma, Lambda, e
fn rscale_usage(a: *mem.Arena, r: *rng.Rng, k: usize, x: []const f64, p: usize, n: usize, nr: usize, ndghk: usize, y0: []const f64, mu0: []const f64, sigma_m0: []const f64, tau0: []const f64, sig0: []const f64, lam0: []const f64, e0: f64, nu: f64, v: []const f64, mubar: []const f64, am: []const f64, gsigma: []const f64, gl11: []const f64, gl22: []const f64, gl12: []const f64, nul: f64, vl: []const f64, ge: []const f64, out: []f64) -> err {
    let fn_ = f64(n)
    let (y, e1) = bg.zal(a, n * p)
    let (mu, e2) = bg.zal(a, p)
    let (sm, e3) = bg.zal(a, p * p)
    let (tau, e4) = bg.zal(a, n)
    let (sig, e5) = bg.zal(a, n)
    let (lam, e6) = bg.zal(a, 4usize)
    let (cc, e7) = bg.zal(a, k + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var i = 0usize
    while i < n * p {
        y[i] = y0[i]
        i += 1usize
    }
    i = 0usize
    while i < p {
        mu[i] = mu0[i]
        i += 1usize
    }
    i = 0usize
    while i < p * p {
        sm[i] = sigma_m0[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        tau[i] = tau0[i]
        sig[i] = sig0[i]
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        lam[i] = lam0[i]
        i += 1usize
    }
    var e = e0
    let w = p * p + p + 2usize * n + 5usize
    var rep = 0usize
    while rep < nr {
        let start = mem.mark(a)
        if !cget_c(e, k, cc) { ret mem.Full }
        // condd(Sigma)
        let (si, f1) = bg.zal(a, p * p)
        let (cb, f2) = bg.zal(a, p * p)
        let (sv, f3) = bg.zal(a, p)
        if f1 != ok || f2 != ok || f3 != ok { ret mem.Full }
        if sym_inv(a, sm, p, si) != ok { ret mem.Full }
        i = 0usize
        while i < p {
            var j = 0usize
            while j + 1usize < p {
                var ind = j
                if j >= i { ind = j + 1usize }
                cb[i * (p - 1usize) + j] = -si[i * p + ind] / si[i * p + i]
                j += 1usize
            }
            sv[i] = math.sqrt[f64](1.0f64 / si[i * p + i])
            i += 1usize
        }
        // dy
        var q = 0usize
        while q < n {
            var t = 0usize
            while t < p {
                let cs = sv[t] * sig[q]
                var cm = mu[t] + tau[q]
                var j = 0usize
                while j < t {
                    cm += cb[t * (p - 1usize) + j] * (y[j * n + q] - mu[j] - tau[q])
                    j += 1usize
                }
                j = t + 1usize
                while j < p {
                    cm += cb[t * (p - 1usize) + j - 1usize] * (y[j * n + q] - mu[j] - tau[q])
                    j += 1usize
                }
                let xi = usize(x[t * n + q])
                let lo = (cc[xi - 1usize] - cm) / cs
                let hi = (cc[xi] - cm) / cs
                let pa = mdist.pnorm(lo, 0.0f64, 1.0f64, true, false)
                let pb = mdist.pnorm(hi, 0.0f64, 1.0f64, true, false)
                let u = rng.unif(r)
                let qo = mdist.qnorm(u * pb + (1.0f64 - u) * pa, 0.0f64, 1.0f64, true, false)
                y[t * n + q] = cm + cs * qo
                t += 1usize
            }
            q += 1usize
        }
        // Sigma
        let (res, g1) = bg.zal(a, n * p)
        let (ss, g2) = bg.zal(a, p * p)
        let (vs, g3) = bg.zal(a, p * p)
        let (vi, g4) = bg.zal(a, p * p)
        let (wm, g5) = bg.zal(a, p * p)
        let (iw, g6) = bg.zal(a, p * p)
        let (cw, g7) = bg.zal(a, p * p)
        let (ci, g8) = bg.zal(a, p * p)
        if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok || g7 != ok || g8 != ok { ret mem.Full }
        i = 0usize
        while i < p {
            q = 0usize
            while q < n {
                res[i * n + q] = (y[i * n + q] - mu[i] - tau[q]) / sig[q]
                q += 1usize
            }
            i += 1usize
        }
        bg.gemm(true, false, res, n, res, n, p, p, n, ss)
        i = 0usize
        while i < p * p {
            vs[i] = v[i] + ss[i]
            i += 1usize
        }
        if sym_inv(a, vs, p, vi) != ok { ret mem.Full }
        if bz.rwishart(a, r, nu + fn_, vi, p, wm, iw, cw, ci) != ok { ret mem.Full }
        i = 0usize
        while i < p * p {
            sm[i] = iw[i]
            i += 1usize
        }
        // mu
        let (si2, h1) = bg.zal(a, p * p)
        let (vmi, h2) = bg.zal(a, p * p)
        let (rm, h3) = bg.zal(a, p * p)
        let (ri, h4) = bg.zal(a, p * p)
        let (vm, h5) = bg.zal(a, p * p)
        let (rhs, h6) = bg.zal(a, p)
        let (tv, h7) = bg.zal(a, p)
        let (zz, h8) = bg.zal(a, p)
        if h1 != ok || h2 != ok || h3 != ok || h4 != ok || h5 != ok || h6 != ok || h7 != ok || h8 != ok { ret mem.Full }
        if sym_inv(a, sm, p, si2) != ok { ret mem.Full }
        var sumi = 0.0f64
        q = 0usize
        while q < n {
            sumi += 1.0f64 / (sig[q] * sig[q])
            q += 1usize
        }
        i = 0usize
        while i < p * p {
            vmi[i] = sumi * si2[i] + am[i]
            i += 1usize
        }
        if !bz.chol_upper(vmi, p, rm) { ret mem.Full }
        bz.inv_upper(rm, p, ri)
        if sym_inv(a, vmi, p, vm) != ok { ret mem.Full }
        i = 0usize
        while i < p {
            var s = 0.0f64
            q = 0usize
            while q < n {
                s += (y[i * n + q] - tau[q]) * (1.0f64 / (sig[q] * sig[q]))
                q += 1usize
            }
            tv[i] = s
            i += 1usize
        }
        i = 0usize
        while i < p {
            var s = 0.0f64
            var s2 = 0.0f64
            var j = 0usize
            while j < p {
                s += si2[j * p + i] * tv[j]
                s2 += am[j * p + i] * mubar[j]
                j += 1usize
            }
            rhs[i] = s + s2
            i += 1usize
        }
        i = 0usize
        while i < p {
            zz[i] = rng.norm(r)
            i += 1usize
        }
        i = 0usize
        while i < p {
            var s = 0.0f64
            var s2 = 0.0f64
            var j = 0usize
            while j < p {
                s += vm[j * p + i] * rhs[j]
                j += 1usize
            }
            j = i
            while j < p {
                s2 += ri[j * p + i] * zz[j]
                j += 1usize
            }
            mu[i] = s + s2
            i += 1usize
        }
        // tau: Rm = chol(Sigma), Ri its inverse; (Rm' ^ -1 v)[c] = sum_t Ri[t, c] v[t]
        let (u2, k1) = bg.zal(a, p * p)
        let (ru, k2) = bg.zal(a, p * p)
        let (xx, k3) = bg.zal(a, p)
        let (yy, k4) = bg.zal(a, n * p)
        if k1 != ok || k2 != ok || k3 != ok || k4 != ok { ret mem.Full }
        if !bz.chol_upper(sm, p, u2) { ret mem.Full }
        bz.inv_upper(u2, p, ru)
        let ai = lam[0usize] - lam[2usize] * lam[2usize] / lam[3usize]
        let aprec = 1.0f64 / ai
        var xtx = 0.0f64
        i = 0usize
        while i < p {
            var s = 0.0f64
            var t = 0usize
            while t <= i {
                s += ru[i * p + t]
                t += 1usize
            }
            xx[i] = s
            xtx += s * s
            i += 1usize
        }
        q = 0usize
        while q < n {
            i = 0usize
            while i < p {
                var s = 0.0f64
                var t = 0usize
                while t <= i {
                    s += ru[i * p + t] * (y[t * n + q] - mu[t])
                    t += 1usize
                }
                yy[i * n + q] = s
                i += 1usize
            }
            q += 1usize
        }
        let tb = aprec * lam[2usize] / lam[3usize]
        q = 0usize
        while q < n {
            var xty = 0.0f64
            i = 0usize
            while i < p {
                xty += xx[i] * yy[i * n + q]
                i += 1usize
            }
            let sg2 = sig[q] * sig[q]
            var s2 = xtx / sg2 + aprec
            s2 = 1.0f64 / s2
            let m = s2 * (xty / sg2 + tb * (math.log[f64](sig[q]) - lam[3usize]))
            tau[q] = m + math.sqrt[f64](s2) * rng.norm(r)
            q += 1usize
        }
        // sigma
        let (pg, l1) = bg.zal(a, gsigma.len)
        if l1 != ok { ret mem.Full }
        let ba = lam[3usize]
        let bb = lam[2usize] / lam[0usize]
        let bs = math.sqrt[f64](lam[3usize] - lam[2usize] * lam[2usize] / lam[0usize])
        q = 0usize
        while q < n {
            var ete = 0.0f64
            i = 0usize
            while i < p {
                var s = 0.0f64
                var t = 0usize
                while t <= i {
                    s += ru[i * p + t] * (y[t * n + q] - tau[q] - mu[t])
                    t += 1usize
                }
                ete += s * s
                i += 1usize
            }
            var g = 0usize
            while g < gsigma.len {
                let gs = gsigma[g]
                let zt = (math.log[f64](gs) - (ba + bb * tau[q])) / bs
                pg[g] = -(f64(p) + 1.0f64) * math.log[f64](gs) - 0.5f64 * ete / (gs * gs) - 0.5f64 * zt * zt
                g += 1usize
            }
            let (dv, de) = grid_draw(a, r, gsigma, pg)
            if de != ok { ret de }
            sig[q] = dv
            q += 1usize
        }
        // Lambda
        let (mm, n1) = bg.zal(a, 5usize)
        let (sl, n2) = bg.zal(a, 4usize)
        let (rg, n3) = bg.zal(a, gl11.len + gl12.len + gl22.len)
        let (pl, n4) = bg.zal(a, gl11.len + gl12.len + gl22.len)
        if n1 != ok || n2 != ok || n3 != ok || n4 != ok { ret mem.Full }
        var mt = 0.0f64
        var mh = 0.0f64
        q = 0usize
        while q < n {
            mt += tau[q]
            mh += math.log[f64](sig[q])
            q += 1usize
        }
        mt = mt / fn_
        mh = mh / fn_
        var c00 = 0.0f64
        var c01 = 0.0f64
        var c11 = 0.0f64
        q = 0usize
        while q < n {
            let dt = tau[q] - mt
            let dh = math.log[f64](sig[q]) - mh
            c00 += dt * dt
            c01 += dt * dh
            c11 += dh * dh
            q += 1usize
        }
        mm[0usize] = mt
        mm[1usize] = mh
        mm[2usize] = c00 / (fn_ - 1.0f64)
        mm[3usize] = c01 / (fn_ - 1.0f64)
        mm[4usize] = c11 / (fn_ - 1.0f64)
        get_s(lam, fn_, mm, sl)
        var ng = 0usize
        var g = 0usize
        let lim1 = lam[2usize] * lam[2usize] / lam[3usize]
        while g < gl11.len {
            if gl11[g] > lim1 {
                rg[ng] = gl11[g]
                ng += 1usize
            }
            g += 1usize
        }
        g = 0usize
        while g < ng {
            lam[0usize] = rg[g]
            pl[g] = ll_lam(lam, fn_, sl, vl, nul)
            g += 1usize
        }
        let (d0, de0) = grid_draw(a, r, rg[0usize..ng], pl[0usize..ng])
        if de0 != ok { ret de0 }
        lam[0usize] = d0
        let lim2 = math.sqrt[f64](lam[0usize] * lam[3usize])
        ng = 0usize
        g = 0usize
        while g < gl12.len {
            if gl12[g] < lim2 && gl12[g] > -lim2 {
                rg[ng] = gl12[g]
                ng += 1usize
            }
            g += 1usize
        }
        g = 0usize
        while g < ng {
            lam[2usize] = rg[g]
            lam[1usize] = rg[g]
            pl[g] = ll_lam(lam, fn_, sl, vl, nul)
            g += 1usize
        }
        let (d1, de1) = grid_draw(a, r, rg[0usize..ng], pl[0usize..ng])
        if de1 != ok { ret de1 }
        lam[2usize] = d1
        lam[1usize] = d1
        let lim3 = lam[2usize] * lam[2usize] / lam[0usize]
        ng = 0usize
        g = 0usize
        while g < gl22.len {
            if gl22[g] > lim3 {
                rg[ng] = gl22[g]
                ng += 1usize
            }
            g += 1usize
        }
        g = 0usize
        while g < ng {
            lam[3usize] = rg[g]
            get_s(lam, fn_, mm, sl)
            pl[g] = ll_lam(lam, fn_, sl, vl, nul)
            g += 1usize
        }
        let (d2, de2) = grid_draw(a, r, rg[0usize..ng], pl[0usize..ng])
        if de2 != ok { ret de2 }
        lam[3usize] = d2
        // e
        let ngr = ge.len
        var best = 1.0e300f64
        g = 0usize
        while g < ngr {
            var df = e - ge[g]
            if df < 0.0f64 { df = -df }
            if df < best { best = df }
            g += 1usize
        }
        var ei = 0usize
        g = ngr
        while g > 0usize {
            g -= 1usize
            var df = e - ge[g]
            if df < 0.0f64 { df = -df }
            if df == best { ei = g }
        }
        var pi = 0usize
        var qr = 1.0f64
        if ei == 1usize {
            pi = 2usize
            qr = 0.5f64
        } else {
            if ei == ngr {
                pi = ngr - 1usize
                qr = 0.5f64
            } else {
                if ei == 0usize || ei + 1usize >= ngr { ret mem.Full }
                let bn = rd.rbinom(r, 1.0f64, 0.5f64)
                if bn == 1.0f64 { pi = ei + 1usize } else { pi = ei - 1usize }
            }
        }
        let eold = ge[ei]
        let eprop = ge[pi]
        let (llold, le1) = rlpx(a, r, x, n, p, k, eold, mu, tau, u2, sig, ndghk)
        if le1 != ok { ret le1 }
        let (llprop, le2) = rlpx(a, r, x, n, p, k, eprop, mu, tau, u2, sig, ndghk)
        if le2 != ok { ret le2 }
        let lrat = llprop - llold + math.log[f64](qr)
        if lrat > 0.0f64 {
            e = eprop
        } else {
            var pacc = math.exp[f64](lrat)
            if pacc > 1.0f64 { pacc = 1.0f64 }
            if rd.rbinom(r, 1.0f64, pacc) == 1.0f64 { e = eprop } else { e = eold }
        }
        mem.reset(a, start)
        // draw rep
        var o = rep * w
        i = 0usize
        while i < p * p {
            out[o + i] = sm[i]
            i += 1usize
        }
        o += p * p
        i = 0usize
        while i < p {
            out[o + i] = mu[i]
            i += 1usize
        }
        o += p
        i = 0usize
        while i < n {
            out[o + i] = tau[i]
            out[o + n + i] = sig[i]
            i += 1usize
        }
        o += 2usize * n
        i = 0usize
        while i < 4usize {
            out[o + i] = lam[i]
            i += 1usize
        }
        out[o + 4usize] = e
        rep += 1usize
    }
    ret ok
}

// the inverse of the symmetric positive definite s (k by k) into out
fn sym_inv(a: *mem.Arena, s: []const f64, k: usize, out: []f64) -> err {
    let start = mem.mark(a)
    let (u, e1) = bg.zal(a, k * k)
    let (ui, e2) = bg.zal(a, k * k)
    if e1 != ok || e2 != ok { ret mem.Full }
    if !bz.chol_upper(s, k, u) { ret mem.Full }
    bz.inv_upper(u, k, ui)
    bg.gemm(false, true, ui, k, ui, k, k, k, k, out)
    mem.reset(a, start)
    ret ok
}
