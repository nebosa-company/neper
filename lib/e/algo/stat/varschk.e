// R vars' tests on a fitted VAR (e.algo.stat.vars2.Var): causality (the Granger F test, its bootstrap, and the instantaneous chi-squared test), serial.test
// (Portmanteau asymptotic and adjusted, Breusch-Godfrey, Edgerton-Shukur), arch.test (multivariate and univariate) and normality.test (multivariate and
// univariate Jarque-Bera), each answering R's statistic, parameters and p value, plus the Blanchard-Quah decomposition.
//
// Not here: causality with a custom vcov. (sandwich), and the tests on a vec2var object.

use e.algo.rand.r as rng
use e.algo.stat.vars as v1
use e.algo.stat.vars2 as vr
use e.math
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

fn p_chisq(stat: f64, df: f64) -> f64 { ret 1.0f64 - nm.pchisq(stat, df, true, false) }

fn p_f(stat: f64, d1: f64, d2: f64) -> f64 { ret 1.0f64 - nb.pf(stat, d1, d2, true, false) }

fn bit(mask: usize, i: usize) -> bool { ret (mask >> i) % 2usize == 1usize }

// the unrestricted least squares fit of every equation on all the columns of z: coefficients (k by nz) and residuals (obs by k)
fn full_fit(a: *mem.Arena, v: *const vr.Var, yend: []const f64, coef: []f64, resid: []f64) -> err {
    let cols = vr.zeros_usize(a, v.nz)
    var c = 0usize
    while c < v.nz {
        cols[c] = c
        c += 1usize
    }
    let yy = vr.zeros(a, v.obs)
    let cf = vr.zeros(a, v.nz)
    let rs = vr.zeros(a, v.obs)
    var i = 0usize
    while i < v.k {
        var t = 0usize
        while t < v.obs {
            yy[t] = yend[t * v.k + i]
            t += 1usize
        }
        let e = vr.ols_cols(a, v.z, v.obs, v.nz, cols, v.nz, yy, cf, rs)
        if e != ok { ret e }
        c = 0usize
        while c < v.nz {
            coef[i * v.nz + c] = cf[c]
            c += 1usize
        }
        t = 0usize
        while t < v.obs {
            resid[t * v.k + i] = rs[t]
            t += 1usize
        }
        i += 1usize
    }
    ret ok
}

// the row of PI (coef(toMlm(x))) that regressor column c of z occupies: the constant comes first, as model.matrix puts the intercept
fn pi_row(v: *const vr.Var, c: usize) -> usize {
    let has_const = v.det == 1usize || v.det == 3usize
    if !has_const { ret c }
    let cc = v.k * v.p
    if c == cc { ret 0usize }
    if c < cc { ret c + 1usize }
    ret c
}

// the Wald F statistic (R pi)' (R V R')^-1 (R pi) / N of the selected positions of vec(PI)
fn granger_stat(a: *mem.Arena, k: usize, nz: usize, pi: []const f64, sigma_pi: []const f64, nres: usize, rsel: []const usize) -> f64 {
    // R pi and R V R' for the selected vec(PI) positions (column-major in R: equation e, row r is index e nz + r)
    let rp = vr.zeros(a, nres)
    let rv = vr.zeros(a, nres * nres)
    var i = 0usize
    while i < nres {
        rp[i] = pi[rsel[i]]
        var j = 0usize
        while j < nres {
            rv[i * nres + j] = sigma_pi[rsel[i] * k * nz + rsel[j]]
            j += 1usize
        }
        i += 1usize
    }
    let inv = vr.minv(a, rv, nres)
    var s = 0.0f64
    i = 0usize
    while i < nres {
        var j = 0usize
        while j < nres {
            s += rp[i] * inv[i * nres + j] * rp[j]
            j += 1usize
        }
        i += 1usize
    }
    ret s / f64(nres)
}

// causality(x, cause, boot, boot.runs): out = (Granger F, df1, df2, p value [the bootstrap p value when boot], Instant chi-squared, df, p value); the seed is
// set only when boot; rows of z with bit i of cmask are the cause variables' lags
fn var_causality(a: *mem.Arena, v: *const vr.Var, cmask: usize, boot: bool, runs: usize, seed: i64, out: []f64) -> err {
    let k = v.k
    let nz = v.nz
    let obs = v.obs
    // PI as R lays it out: rows in model.matrix order, columns the equations; stored equation-major: pi[e nz + r]
    let coef = vr.zeros(a, k * nz)
    let res = vr.zeros(a, obs * k)
    let e0 = full_fit(a, v, v.yend, coef, res)
    if e0 != ok { ret e0 }
    let pi = vr.zeros(a, k * nz)
    var e = 0usize
    while e < k {
        var c = 0usize
        while c < nz {
            pi[e * nz + pi_row(v, c)] = coef[e * nz + c]
            c += 1usize
        }
        e += 1usize
    }
    // the design in PI's row order and its (x'x)^-1
    let xm = vr.zeros(a, obs * nz)
    var t = 0usize
    while t < obs {
        var c = 0usize
        while c < nz {
            xm[pi_row(v, c) * obs + t] = v.z[t * nz + c]
            c += 1usize
        }
        t += 1usize
    }
    let xinv = vr.zeros(a, nz * nz)
    let e1 = vr.xtx_inverse_cm(a, xm, obs, nz, xinv)
    if e1 != ok { ret e1 }
    let sg = vr.resid_cov(a, res, obs, k, f64(obs - nz))
    // vcov = kronecker(sg, xinv): index (e1 nz + r1, e2 nz + r2)
    let sp = vr.zeros(a, k * nz * k * nz)
    e = 0usize
    while e < k {
        var f = 0usize
        while f < k {
            var r1 = 0usize
            while r1 < nz {
                var r2 = 0usize
                while r2 < nz {
                    sp[(e * nz + r1) * k * nz + f * nz + r2] = sg[e * k + f] * xinv[r1 * nz + r2]
                    r2 += 1usize
                }
                r1 += 1usize
            }
            f += 1usize
        }
        e += 1usize
    }
    // R2: the cause variables' lags in the other equations, plus (restricted model) the coefficients the model sets to zero
    let sel = vr.zeros_usize(a, k * nz)
    var nres = 0usize
    e = 0usize
    while e < k {
        var c = 0usize
        while c < nz {
            var flag = false
            if c < k * v.p && bit(cmask, c % k) && !bit(cmask, e) { flag = true }
            if v.restricted && v.mask[e * nz + c] == 0.0f64 { flag = true }
            if flag {
                sel[nres] = e * nz + pi_row(v, c)
                nres += 1usize
            }
            c += 1usize
        }
        e += 1usize
    }
    // the selected positions in increasing vec order
    var i = 1usize
    while i < nres {
        let x = sel[i]
        var q = i
        while q > 0usize && sel[q - 1usize] > x {
            sel[q] = sel[q - 1usize]
            q -= 1usize
        }
        sel[q] = x
        i += 1usize
    }
    let stat = granger_stat(a, k, nz, pi, sp, nres, sel)
    var n1 = 0usize
    var n2 = 0usize
    i = 0usize
    while i < k {
        if bit(cmask, i) { n1 += 1usize } else { n2 += 1usize }
        i += 1usize
    }
    out[0usize] = stat
    out[1usize] = f64(v.p * n1 * n2)
    out[2usize] = f64(k * obs - k * nz)
    out[3usize] = p_f(stat, out[1usize], out[2usize])
    if boot {
        let e2 = granger_boot(a, v, cmask, stat, pi, sp, nres, sel, xm, xinv, runs, seed, out)
        if e2 != ok { ret e2 }
    }
    // instantaneous causality
    let su = vr.resid_cov(a, v.resid, obs, k, f64(obs - nz))
    let kk = k * (k + 1usize) / 2usize
    let sv = vr.zeros(a, kk)
    let pos = vr.zeros_usize(a, kk * 2usize)
    var cnt = 0usize
    var j = 0usize
    while j < k {
        i = j
        while i < k {
            sv[cnt] = su[i * k + j]
            pos[cnt * 2usize] = i
            pos[cnt * 2usize + 1usize] = j
            cnt += 1usize
            i += 1usize
        }
        j += 1usize
    }
    let idx = vr.zeros_usize(a, kk)
    var nn = 0usize
    i = 0usize
    while i < kk {
        let r = pos[i * 2usize]
        let c = pos[i * 2usize + 1usize]
        if (bit(cmask, r) && !bit(cmask, c)) || (bit(cmask, c) && !bit(cmask, r)) {
            idx[nn] = i
            nn += 1usize
        }
        i += 1usize
    }
    // Dinv = diag(1 / d) D' with d = 1 on the diagonal, 2 off it; Dinv (Sigma kron Sigma) Dinv'
    let dm = vr.zeros(a, k * k * kk)
    j = 0usize
    while j < k {
        i = j
        while i < k {
            var col = 0usize
            var q = 0usize
            while q < kk {
                if pos[q * 2usize] == i && pos[q * 2usize + 1usize] == j { col = q }
                q += 1usize
            }
            dm[(j * k + i) * kk + col] = 1.0f64
            dm[(i * k + j) * kk + col] = 1.0f64
            i += 1usize
        }
        j += 1usize
    }
    // Dinv[q][r] = D[r][q] / d_q
    let dinv = vr.zeros(a, kk * k * k)
    var q = 0usize
    while q < kk {
        var d = 1.0f64
        if pos[q * 2usize] != pos[q * 2usize + 1usize] { d = 2.0f64 }
        var r = 0usize
        while r < k * k {
            dinv[q * k * k + r] = dm[r * kk + q] / d
            r += 1usize
        }
        q += 1usize
    }
    let ks = vr.zeros(a, k * k * k * k)
    i = 0usize
    while i < k {
        j = 0usize
        while j < k {
            var l1 = 0usize
            while l1 < k {
                var l2 = 0usize
                while l2 < k {
                    // kronecker(su, su)[(i k + l1), (j k + l2)] = su[i][j] su[l1][l2]
                    ks[(i * k + l1) * k * k + j * k + l2] = su[i * k + j] * su[l1 * k + l2]
                    l2 += 1usize
                }
                l1 += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    // Dinv takes vec in column-major order: row index of the vec is (col k + row); su symmetric, so R's kronecker matches the layout used here
    let t1 = vr.mmul(a, dinv, ks, kk, k * k, k * k)
    let dinvt = vr.mtr(a, dinv, kk, k * k)
    let t2 = vr.mmul(a, t1, dinvt, kk, k * k, kk)
    let cm = vr.zeros(a, nn * nn)
    let cs = vr.zeros(a, nn)
    i = 0usize
    while i < nn {
        cs[i] = sv[idx[i]]
        j = 0usize
        while j < nn {
            cm[i * nn + j] = 2.0f64 * t2[idx[i] * kk + idx[j]]
            j += 1usize
        }
        i += 1usize
    }
    let cinv = vr.minv(a, cm, nn)
    var lam = 0.0f64
    i = 0usize
    while i < nn {
        j = 0usize
        while j < nn {
            lam += cs[i] * cinv[i * nn + j] * cs[j]
            j += 1usize
        }
        i += 1usize
    }
    lam = lam * f64(obs)
    out[4usize] = lam
    out[5usize] = f64(nn)
    out[6usize] = p_chisq(lam, f64(nn))
    ret ok
}

// the bootstrap p value of causality(boot = TRUE): the restricted model's fitted values plus its residuals scaled by one rnorm per observation
fn granger_boot(a: *mem.Arena, v: *const vr.Var, cmask: usize, stat: f64, pi: []const f64, sp: []const f64, nres: usize, sel: []const usize, xm: []const f64, xinv: []const f64, runs: usize, seed: i64, out: []f64) -> err {
    let k = v.k
    let nz = v.nz
    let obs = v.obs
    // R2inv: free coefficients of the model fitted under H0 (the cause lags dropped from the other equations), times the model's own restrictions
    var vm = vr.var_copy(a, v)
    var q = 0usize
    while q < k * nz {
        vm.mask[q] = 1.0f64
        q += 1usize
    }
    var e = 0usize
    while e < k {
        var c = 0usize
        while c < nz {
            if c < k * v.p && bit(cmask, c % k) && !bit(cmask, e) { vm.mask[e * nz + c] = 0.0f64 }
            if v.restricted && v.mask[e * nz + c] == 0.0f64 { vm.mask[e * nz + c] = 0.0f64 }
            c += 1usize
        }
        e += 1usize
    }
    let fe = vr.var_fit_eqs(a, &vm)
    if fe != ok { ret fe }
    // pred = yend - resid
    let pred = vr.zeros(a, obs * k)
    q = 0usize
    while q < obs * k {
        pred[q] = v.yend[q] - vm.resid[q]
        q += 1usize
    }
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    // the fixed inside matrix of the unrestricted branch
    var rv = vr.zeros(a, nres * nres)
    var i = 0usize
    while i < nres {
        var j = 0usize
        while j < nres {
            rv[i * nres + j] = sp[sel[i] * k * nz + sel[j]]
            j += 1usize
        }
        i += 1usize
    }
    let inside = vr.minv(a, rv, nres)
    var exceed = 0usize
    var run = 0usize
    while run < runs {
        let start = mem.mark(a)
        let ynew = vr.zeros(a, obs * k)
        var t = 0usize
        while t < obs {
            let z = rng.norm(&rg)
            var j = 0usize
            while j < k {
                ynew[t * k + j] = pred[t * k + j] + vm.resid[t * k + j] * z
                j += 1usize
            }
            t += 1usize
        }
        let cb = vr.zeros(a, k * nz)
        let rb = vr.zeros(a, obs * k)
        let fe2 = full_fit(a, v, ynew, cb, rb)
        if fe2 != ok { ret fe2 }
        let pib = vr.zeros(a, k * nz)
        e = 0usize
        while e < k {
            var c = 0usize
            while c < nz {
                pib[e * nz + pi_row(v, c)] = cb[e * nz + c]
                c += 1usize
            }
            e += 1usize
        }
        var sb = 0.0f64
        if !v.restricted {
            let rp = vr.zeros(a, nres)
            i = 0usize
            while i < nres {
                rp[i] = pib[sel[i]]
                i += 1usize
            }
            i = 0usize
            while i < nres {
                var j = 0usize
                while j < nres {
                    sb += rp[i] * inside[i * nres + j] * rp[j]
                    j += 1usize
                }
                i += 1usize
            }
            sb = sb / f64(nres)
        } else {
            let sgb = vr.resid_cov(a, rb, obs, k, f64(obs - nz))
            let rvb = vr.zeros(a, nres * nres)
            i = 0usize
            while i < nres {
                var j = 0usize
                while j < nres {
                    let e1 = sel[i] / nz
                    let r1 = sel[i] % nz
                    let e2 = sel[j] / nz
                    let r2 = sel[j] % nz
                    rvb[i * nres + j] = sgb[e1 * k + e2] * xinv[r1 * nz + r2]
                    j += 1usize
                }
                i += 1usize
            }
            let invb = vr.minv(a, rvb, nres)
            i = 0usize
            while i < nres {
                var j = 0usize
                while j < nres {
                    sb += pib[sel[i]] * invb[i * nres + j] * pib[sel[j]]
                    j += 1usize
                }
                i += 1usize
            }
            sb = sb / f64(nres)
        }
        if sb > stat { exceed += 1usize }
        mem.reset(a, start)
        run += 1usize
    }
    out[3usize] = f64(exceed) / f64(runs)
    ret ok
}

// serial.test PT: out = (asymptotic statistic, adjusted statistic, df, p value of each of the two)
fn var_serial_pt(a: *mem.Arena, v: *const vr.Var, lags: usize, out: []f64) {
    let k = v.k
    let obs = v.obs
    let r = v.resid
    let c0 = vr.resid_cov(a, r, obs, k, f64(obs))
    let c0i = vr.minv(a, c0, k)
    var qh = 0.0f64
    var qs = 0.0f64
    var l = 1usize
    while l <= lags {
        // Ci = crossprod(U_t, U_{t-i}) / obs over the rows t = i .. obs - 1
        let ci = vr.zeros(a, k * k)
        var x = 0usize
        while x < k {
            var y = 0usize
            while y < k {
                var s = 0.0f64
                var t = l
                while t < obs {
                    s += r[t * k + x] * r[(t - l) * k + y]
                    t += 1usize
                }
                ci[x * k + y] = s / f64(obs)
                y += 1usize
            }
            x += 1usize
        }
        // trace(Ci' C0^-1 Ci C0^-1)
        let cit = vr.mtr(a, ci, k, k)
        let m1 = vr.mmul(a, cit, c0i, k, k, k)
        let m2 = vr.mmul(a, m1, ci, k, k, k)
        let m3 = vr.mmul(a, m2, c0i, k, k, k)
        let ts = vr.trace_of(m3, k)
        qh += ts
        qs += ts / f64(obs - l)
        l += 1usize
    }
    let n = f64(obs)
    out[0usize] = n * qh
    out[1usize] = n * n * qs
    out[2usize] = f64(k * k * lags - k * k * v.p)
    out[3usize] = p_chisq(out[0usize], out[2usize])
    out[4usize] = p_chisq(out[1usize], out[2usize])
}

// serial.test BG and ES: out = (LM statistic, df, p, Edgerton-Shukur F, df1, df2, p)
fn var_serial_bg(a: *mem.Arena, v: *const vr.Var, lags: usize, out: []f64) -> err {
    let k = v.k
    let obs = v.obs
    let nz = v.nz
    let w = nz + k * lags
    let zw = vr.zeros(a, obs * w)
    var t = 0usize
    while t < obs {
        var c = 0usize
        while c < nz {
            zw[t * w + c] = v.z[t * nz + c]
            c += 1usize
        }
        var l = 1usize
        while l <= lags {
            if t >= l {
                var j = 0usize
                while j < k {
                    zw[t * w + nz + (l - 1usize) * k + j] = v.resid[(t - l) * k + j]
                    j += 1usize
                }
            }
            l += 1usize
        }
        t += 1usize
    }
    let r0 = vr.zeros(a, obs * k)
    let r1 = vr.zeros(a, obs * k)
    let cols = vr.zeros_usize(a, w)
    let yy = vr.zeros(a, obs)
    let cf = vr.zeros(a, w)
    let rs = vr.zeros(a, obs)
    var i = 0usize
    while i < k {
        var nsel = 0usize
        var c = 0usize
        while c < nz {
            if v.mask[i * nz + c] != 0.0f64 {
                cols[nsel] = c
                nsel += 1usize
            }
            c += 1usize
        }
        t = 0usize
        while t < obs {
            yy[t] = v.resid[t * k + i]
            t += 1usize
        }
        let e1 = vr.ols_cols(a, zw, obs, w, cols, nsel, yy, cf, rs)
        if e1 != ok { ret e1 }
        t = 0usize
        while t < obs {
            r1[t * k + i] = rs[t]
            t += 1usize
        }
        c = 0usize
        while c < k * lags {
            cols[nsel + c] = nz + c
            c += 1usize
        }
        let e0 = vr.ols_cols(a, zw, obs, w, cols, nsel + k * lags, yy, cf, rs)
        if e0 != ok { ret e0 }
        t = 0usize
        while t < obs {
            r0[t * k + i] = rs[t]
            t += 1usize
        }
        i += 1usize
    }
    let s0 = vr.resid_cov(a, r0, obs, k, f64(obs))
    let s1 = vr.resid_cov(a, r1, obs, k, f64(obs))
    let s1i = vr.minv(a, s1, k)
    var tr = 0.0f64
    i = 0usize
    while i < k * k {
        tr += s1i[i] * s0[i]
        i += 1usize
    }
    let n = f64(obs)
    let lm = n * (f64(k) - tr)
    out[0usize] = lm
    out[1usize] = f64(lags * k * k)
    out[2usize] = p_chisq(lm, out[1usize])
    let r2r = 1.0f64 - vr.mdet(a, s0, k) / vr.mdet(a, s1, k)
    let m = f64(k * lags)
    let q = 0.5f64 * f64(k) * m - 1.0f64
    let kf = f64(k)
    let nn = n - f64(nz) - m - 0.5f64 * (kf - m + 1.0f64)
    let r = math.sqrt[f64]((kf * kf * m * m - 4.0f64) / (kf * kf + m * m - 5.0f64))
    let om = math.pow[f64](1.0f64 - r2r, 1.0f64 / r)
    let f = (1.0f64 - om) / om * (nn * r - q) / (kf * m)
    out[3usize] = f
    out[4usize] = f64(lags * k * k)
    out[5usize] = math.floor[f64](nn * r - q)
    out[6usize] = p_f(f, out[4usize], out[5usize])
    ret ok
}

// the columns of x (n by m) centred, and scaled to unit sample standard deviation when `scale`
fn centre_scale(a: *mem.Arena, x: []const f64, n: usize, m: usize, scale: bool) -> []f64 {
    let o = vr.zeros(a, n * m)
    var j = 0usize
    while j < m {
        var mean = 0.0f64
        var t = 0usize
        while t < n {
            mean += x[t * m + j]
            t += 1usize
        }
        mean = mean / f64(n)
        var ss = 0.0f64
        t = 0usize
        while t < n {
            ss += (x[t * m + j] - mean) * (x[t * m + j] - mean)
            t += 1usize
        }
        let sd = math.sqrt[f64](ss / f64(n - 1usize))
        t = 0usize
        while t < n {
            o[t * m + j] = x[t * m + j] - mean
            if scale { o[t * m + j] = o[t * m + j] / sd }
            t += 1usize
        }
        j += 1usize
    }
    ret o
}

// least squares of the columns of y (n by m) on an intercept and the columns `xc` (n by q); residuals (n by m)
fn resid_on(a: *mem.Arena, y: []const f64, xc: []const f64, n: usize, m: usize, q: usize) -> ([]f64, err) {
    let w = q + 1usize
    let zz = vr.zeros(a, n * w)
    var t = 0usize
    while t < n {
        zz[t * w] = 1.0f64
        var c = 0usize
        while c < q {
            zz[t * w + 1usize + c] = xc[t * q + c]
            c += 1usize
        }
        t += 1usize
    }
    let cols = vr.zeros_usize(a, w)
    var c = 0usize
    while c < w {
        cols[c] = c
        c += 1usize
    }
    let out = vr.zeros(a, n * m)
    let yy = vr.zeros(a, n)
    let cf = vr.zeros(a, w)
    let rs = vr.zeros(a, n)
    var j = 0usize
    while j < m {
        t = 0usize
        while t < n {
            yy[t] = y[t * m + j]
            t += 1usize
        }
        let e = vr.ols_cols(a, zz, n, w, cols, w, yy, cf, rs)
        if e != ok { ret (out, e) }
        t = 0usize
        while t < n {
            out[t * m + j] = rs[t]
            t += 1usize
        }
        j += 1usize
    }
    ret (out, ok)
}

// arch.test multivariate: out = (statistic, df, p value)
fn var_arch_multi(a: *mem.Arena, v: *const vr.Var, lags: usize, out: []f64) -> err {
    let k = v.k
    let obs = v.obs
    let sr = centre_scale(a, v.resid, obs, k, true)
    let m = k * (k + 1usize) / 2usize
    let ad = vr.zeros(a, obs * m)
    var t = 0usize
    while t < obs {
        var c = 0usize
        var j = 0usize
        while j < k {
            var i = j
            while i < k {
                ad[t * m + c] = sr[t * k + i] * sr[t * k + j]
                c += 1usize
                i += 1usize
            }
            j += 1usize
        }
        t += 1usize
    }
    let n = obs - lags
    // embed(arch.df, lags + 1): row r is time t = lags + r; block 0 is the response, block l the l-th lag
    let yb = vr.zeros(a, n * m)
    let xb = vr.zeros(a, n * m * lags)
    var r = 0usize
    while r < n {
        let tt = lags + r
        var c = 0usize
        while c < m {
            yb[r * m + c] = ad[tt * m + c]
            var l = 1usize
            while l <= lags {
                xb[r * m * lags + (l - 1usize) * m + c] = ad[(tt - l) * m + c]
                l += 1usize
            }
            c += 1usize
        }
        r += 1usize
    }
    let (res0, e0) = resid_on(a, yb, xb, n, m, 0usize)
    if e0 != ok { ret e0 }
    let (res1, e1) = resid_on(a, yb, xb, n, m, m * lags)
    if e1 != ok { ret e1 }
    let c0 = centre_scale(a, res0, n, m, false)
    let c1 = centre_scale(a, res1, n, m, false)
    let om0 = vr.resid_cov(a, c0, n, m, f64(n - 1usize))
    let om1 = vr.resid_cov(a, c1, n, m, f64(n - 1usize))
    let prod = vr.mmul(a, om1, vr.minv(a, om0, m), m, m, m)
    let kf = f64(k)
    let r2m = 1.0f64 - 2.0f64 / (kf * (kf + 1.0f64)) * vr.trace_of(prod, m)
    let stat = 0.5f64 * f64(n) * kf * (kf + 1.0f64) * r2m
    out[0usize] = stat
    out[1usize] = f64(lags) * kf * kf * (kf + 1.0f64) * (kf + 1.0f64) / 4.0f64
    out[2usize] = p_chisq(stat, out[1usize])
    ret ok
}

// arch.test univariate for equation eq: out = (statistic, df, p value)
fn var_arch_uni(a: *mem.Arena, v: *const vr.Var, eq: usize, lags: usize, out: []f64) -> err {
    let k = v.k
    let obs = v.obs
    let sr = centre_scale(a, v.resid, obs, k, true)
    let col = vr.zeros(a, obs)
    var t = 0usize
    while t < obs {
        col[t] = sr[t * k + eq]
        t += 1usize
    }
    // scale(x) once more, then squared
    let s2 = centre_scale(a, col, obs, 1usize, true)
    let sq = vr.zeros(a, obs)
    t = 0usize
    while t < obs {
        sq[t] = s2[t] * s2[t]
        t += 1usize
    }
    let n = obs - lags
    let yb = vr.zeros(a, n)
    let xb = vr.zeros(a, n * lags)
    var r = 0usize
    while r < n {
        yb[r] = sq[lags + r]
        var l = 1usize
        while l <= lags {
            xb[r * lags + (l - 1usize)] = sq[lags + r - l]
            l += 1usize
        }
        r += 1usize
    }
    let (res, e) = resid_on(a, yb, xb, n, 1usize, lags)
    if e != ok { ret e }
    var mean = 0.0f64
    r = 0usize
    while r < n {
        mean += yb[r]
        r += 1usize
    }
    mean = mean / f64(n)
    var rss = 0.0f64
    var tss = 0.0f64
    r = 0usize
    while r < n {
        rss += res[r] * res[r]
        tss += (yb[r] - mean) * (yb[r] - mean)
        r += 1usize
    }
    let r2 = 1.0f64 - rss / tss
    out[0usize] = r2 * f64(n)
    out[1usize] = f64(lags)
    out[2usize] = p_chisq(out[0usize], out[1usize])
    ret ok
}

// normality.test multivariate: out = (JB statistic, df, p, skewness statistic, df, p, kurtosis statistic, df, p)
fn var_jb_multi(a: *mem.Arena, v: *const vr.Var, out: []f64) -> bool {
    let k = v.k
    let obs = v.obs
    let x = centre_scale(a, v.resid, obs, k, false)
    let sg = vr.resid_cov(a, x, obs, k, f64(obs))
    // chol() is upper: P = L'; the standardised residuals are x P^-1
    let l = vr.zeros(a, k * k)
    if !v1.var_chol(sg, k, l) { ret false }
    let pu = vr.mtr(a, l, k, k)
    let pinv = vr.minv(a, pu, k)
    let st = vr.mmul(a, x, pinv, obs, k, k)
    var s3 = 0.0f64
    var s4 = 0.0f64
    var j = 0usize
    while j < k {
        var b1 = 0.0f64
        var b2 = 0.0f64
        var t = 0usize
        while t < obs {
            let z = st[t * k + j]
            b1 += z * z * z
            b2 += z * z * z * z
            t += 1usize
        }
        b1 = b1 / f64(obs)
        b2 = b2 / f64(obs)
        s3 += b1 * b1
        s4 += (b2 - 3.0f64) * (b2 - 3.0f64)
        j += 1usize
    }
    let n = f64(obs)
    s3 = n * s3 / 6.0f64
    s4 = n * s4 / 24.0f64
    out[0usize] = s3 + s4
    out[1usize] = 2.0f64 * f64(k)
    out[2usize] = p_chisq(out[0usize], out[1usize])
    out[3usize] = s3
    out[4usize] = f64(k)
    out[5usize] = p_chisq(s3, out[4usize])
    out[6usize] = s4
    out[7usize] = f64(k)
    out[8usize] = p_chisq(s4, out[7usize])
    ret true
}

// normality.test univariate for equation eq: out = (statistic, df, p value)
fn var_jb_uni(a: *mem.Arena, v: *const vr.Var, eq: usize, out: []f64) {
    let k = v.k
    let obs = v.obs
    let x = centre_scale(a, v.resid, obs, k, false)
    let n = f64(obs)
    var m1 = 0.0f64
    var t = 0usize
    while t < obs {
        m1 += x[t * k + eq]
        t += 1usize
    }
    m1 = m1 / n
    var m2 = 0.0f64
    var m3 = 0.0f64
    var m4 = 0.0f64
    t = 0usize
    while t < obs {
        let d = x[t * k + eq] - m1
        m2 += d * d
        m3 += d * d * d
        m4 += d * d * d * d
        t += 1usize
    }
    m2 = m2 / n
    m3 = m3 / n
    m4 = m4 / n
    let b1 = (m3 / math.pow[f64](m2, 1.5f64)) * (m3 / math.pow[f64](m2, 1.5f64))
    let b2 = m4 / (m2 * m2)
    out[0usize] = n * b1 / 6.0f64 + n * (b2 - 3.0f64) * (b2 - 3.0f64) / 24.0f64
    out[1usize] = 2.0f64
    out[2usize] = p_chisq(out[0usize], 2.0f64)
}

// BQ(x): the long-run impact matrix LRIM = t(chol(M1^-1 Sigma M2^-1)) and the contemporaneous impact matrix B = M1 LRIM, both k by k, with
// M1 = I - sum A_i, M2 = I - sum A_i' and Sigma = crossprod(resid) / (obs - free coefficients of equation 1)
fn var_bq(a: *mem.Arena, v: *const vr.Var, lrim: []f64, cim: []f64) -> bool {
    let k = v.k
    let m1 = vr.ident(a, k)
    let m2 = vr.ident(a, k)
    var l = 0usize
    while l < v.p {
        var i = 0usize
        while i < k {
            var j = 0usize
            while j < k {
                m1[i * k + j] -= v.coef[i * v.nz + l * k + j]
                m2[j * k + i] -= v.coef[i * v.nz + l * k + j]
                j += 1usize
            }
            i += 1usize
        }
        l += 1usize
    }
    let su = vr.resid_cov(a, v.resid, v.obs, k, vr.eq_df(v, 0usize))
    let ev = vr.mmul(a, vr.mmul(a, vr.minv(a, m1, k), su, k, k, k), vr.minv(a, m2, k), k, k, k)
    if !v1.var_chol(ev, k, lrim) { ret false }
    let b = vr.mmul(a, m1, lrim, k, k, k)
    var q = 0usize
    while q < k * k {
        cim[q] = b[q]
        q += 1usize
    }
    ret true
}
