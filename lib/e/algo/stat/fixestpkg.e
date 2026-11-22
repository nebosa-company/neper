// R fixest: feols, fepois, feglm and femlm (Poisson and logit) with any number of fixed effects, instrumental variables
// (2SLS), the IID, heteroskedasticity-robust, clustered (one or two variables), Newey-West and Driscoll-Kraay variances
// under fixest's default small-sample corrections, coefficient tables, Wald tests, predictions and the Sun-Abraham estimator.
//
// Fixed effects are demeaned by alternating projections until the group means move by less than 1e-14 of the data scale; the
// GLM families run fixest's IRLS (starting values, deviance stopping rule at 3e-13, final-iteration scores). A fixed effect
// beyond the second counts G - 1 parameters, as fixest does without fixef.force_exact. Not here: varying slopes, the
// fixed-effect estimates as a result, weights, offsets, negative binomial, probit and the other glm families, and fixest's
// step-halving and collinearity removal (a rank-deficient design fails with Singular).
//
// Layout of `out` for fit (p = nx + ne coefficients, exogenous first, then endogenous):
//   [0, p) coef, [p, 2p) se, [2p, 3p) t, [3p, 4p) p-value (t distribution; normal for the GLM families),
//   4p df of the t distribution, 4p+1 K (parameters), 4p+2 K for the cluster correction, 4p+3 rss (deviance for a GLM),
//   [4p+4, 4p+4+p*p) the variance matrix, then the fixed-effect levels' effects (sum of the group counts).

use e.algo.stat.gparot as gp
use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.mem

fn find(par: []usize, v: usize) -> usize {
    var r = v
    while par[r] != r { r = par[r] }
    ret r
}

fn out_len(p: usize, tg: usize) -> usize { ret 4usize * p + 4usize + p * p + tg }

// 1 + the largest code in column `col` of a row-major code matrix
fn ngroups(c: []const usize, n: usize, stride: usize, col: usize) -> usize {
    var m = 0usize
    var i = 0usize
    while i < n {
        let v = c[i * stride + col]
        if v + 1usize > m { m = v + 1usize }
        i += 1usize
    }
    ret m
}

// dense 0-based ids for codes below `range`, and how many distinct codes there are
fn dense(a: *mem.Arena, codes: []const usize, n: usize, range: usize) -> ([]usize, usize, err) {
    let (ids, e1) = mem.alloc[usize](a, n)
    let (map, e2) = mem.alloc[usize](a, range + 1usize)
    if e1 != ok { ret (ids, 0usize, e1) }
    if e2 != ok { ret (ids, 0usize, e2) }
    var r = 0usize
    while r < range {
        map[r] = 4294967295usize
        r += 1usize
    }
    var cnt = 0usize
    var i = 0usize
    while i < n {
        if map[codes[i]] == 4294967295usize {
            map[codes[i]] = cnt
            cnt += 1usize
        }
        ids[i] = map[codes[i]]
        i += 1usize
    }
    ret (ids, cnt, ok)
}

// in place: subtract the (w-weighted) group means of every fixed effect from v until they stop moving; acc, when it has
// the group count, collects the subtracted means (the fixed-effect estimates)
fn demean1(v: []f64, n: usize, fe: []const usize, nf: usize, goff: []const usize, gw: []const f64, w: []const f64, gs: []f64, acc: []f64) {
    var scale = 1.0f64
    var i = 0usize
    while i < n {
        if math.abs[f64](v[i]) > scale { scale = math.abs[f64](v[i]) }
        i += 1usize
    }
    let useacc = acc.len > 0usize
    var sweep = 0usize
    while sweep < 100000usize {
        var change = 0.0f64
        var j = 0usize
        while j < nf {
            let o = goff[j]
            let o2 = goff[j + 1usize]
            var g = o
            while g < o2 {
                gs[g] = 0.0f64
                g += 1usize
            }
            i = 0usize
            while i < n {
                gs[o + fe[i * nf + j]] += w[i] * v[i]
                i += 1usize
            }
            g = o
            while g < o2 {
                if gw[g] > 0.0f64 {
                    gs[g] = gs[g] / gw[g]
                    if useacc { acc[g] += gs[g] }
                    if math.abs[f64](gs[g]) > change { change = math.abs[f64](gs[g]) }
                }
                g += 1usize
            }
            i = 0usize
            while i < n {
                v[i] -= gs[o + fe[i * nf + j]]
                i += 1usize
            }
            j += 1usize
        }
        if nf == 1usize || change < 1.0e-14f64 * scale { break }
        sweep += 1usize
    }
}

fn gweights(n: usize, fe: []const usize, nf: usize, goff: []const usize, w: []const f64, gw: []f64) {
    var k = 0usize
    while k < goff[nf] {
        gw[k] = 0.0f64
        k += 1usize
    }
    var j = 0usize
    while j < nf {
        var i = 0usize
        while i < n {
            gw[goff[j] + fe[i * nf + j]] += w[i]
            i += 1usize
        }
        j += 1usize
    }
}

// the fixed-effect parameter count over the effects with use[j]: the first counts its levels, the second the levels
// less the connected components of the two, later ones levels - 1; nothing used counts 1
fn fe_params(a: *mem.Arena, fe: []const usize, n: usize, nf: usize, goff: []const usize, used: []const usize) -> usize {
    var first = 4294967295usize
    var second = 4294967295usize
    var total = 0usize
    var j = 0usize
    while j < nf {
        if used[j] == 1usize {
            let sz = goff[j + 1usize] - goff[j]
            if first == 4294967295usize {
                first = j
                total = sz
            } else {
                if second == 4294967295usize {
                    second = j
                    total += sz
                } else {
                    total += sz - 1usize
                }
            }
        }
        j += 1usize
    }
    if first == 4294967295usize { ret 1usize }
    if second != 4294967295usize {
        let g1 = goff[first + 1usize] - goff[first]
        let g2 = goff[second + 1usize] - goff[second]
        let start = mem.mark(a)
        let (par, e1) = mem.alloc[usize](a, g1 + g2)
        if e1 != ok { ret total }
        var q = 0usize
        while q < g1 + g2 {
            par[q] = q
            q += 1usize
        }
        var t = 0usize
        while t < n {
            let r1 = find(par, fe[t * nf + first])
            let r2 = find(par, g1 + fe[t * nf + second])
            if r1 != r2 { par[r1] = r2 }
            t += 1usize
        }
        var comps = 0usize
        q = 0usize
        while q < g1 + g2 {
            if find(par, q) == q { comps += 1usize }
            q += 1usize
        }
        total = total - comps
        mem.reset(a, start)
    }
    ret total
}

// does every level of fixed effect j sit inside one level of cluster variable cc?
fn nested_in(a: *mem.Arena, fe: []const usize, nf: usize, j: usize, gj: usize, n: usize, cl: []const usize, ncl: usize, cc: usize) -> bool {
    let start = mem.mark(a)
    let (first, e1) = mem.alloc[usize](a, gj)
    if e1 != ok { ret false }
    var q = 0usize
    while q < gj {
        first[q] = 4294967295usize
        q += 1usize
    }
    var yes = true
    var t = 0usize
    while t < n {
        let lv = fe[t * nf + j]
        let c = cl[t * ncl + cc]
        if first[lv] == 4294967295usize { first[lv] = c }
        if first[lv] != c { yes = false }
        t += 1usize
    }
    mem.reset(a, start)
    ret yes
}

// least squares of yv on the columns of xh (instrumented regressors) with residuals taken against xo
fn solve_ls(a: *mem.Arena, xh: []const f64, xo: []const f64, yv: []const f64, w: []const f64, n: usize, k: usize, beta: []f64, gi: []f64, res: []f64) -> err {
    let (gm, e1) = mem.alloc[f64](a, k * k)
    let (rv, e2) = mem.alloc[f64](a, k)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < k {
        var s2 = 0.0f64
        var t = 0usize
        while t < n {
            s2 += w[t] * xh[i * n + t] * yv[t]
            t += 1usize
        }
        rv[i] = s2
        var j = 0usize
        while j < k {
            var s = 0.0f64
            t = 0usize
            while t < n {
                s += w[t] * xh[i * n + t] * xh[j * n + t]
                t += 1usize
            }
            gm[i * k + j] = s
            j += 1usize
        }
        i += 1usize
    }
    let (inv, ge) = gp.invert(a, gm, k)
    if ge != ok { ret ge }
    i = 0usize
    while i < k * k {
        gi[i] = inv[i]
        i += 1usize
    }
    i = 0usize
    while i < k {
        var s3 = 0.0f64
        var j2 = 0usize
        while j2 < k {
            s3 += inv[i * k + j2] * rv[j2]
            j2 += 1usize
        }
        beta[i] = s3
        i += 1usize
    }
    var t2 = 0usize
    while t2 < n {
        var f = 0.0f64
        i = 0usize
        while i < k {
            f += xo[i * n + t2] * beta[i]
            i += 1usize
        }
        res[t2] = yv[t2] - f
        t2 += 1usize
    }
    ret ok
}

// v = corr * gi * meat * gi (all p x p)
fn sandwich(a: *mem.Arena, gi: []const f64, meat: []const f64, p: usize, corr: f64, v: []f64) -> err {
    let (tmp, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var q = 0usize
            while q < p {
                s += gi[i * p + q] * meat[q * p + j]
                q += 1usize
            }
            tmp[i * p + j] = s
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < p {
        var j2 = 0usize
        while j2 < p {
            var s2 = 0.0f64
            var q2 = 0usize
            while q2 < p {
                s2 += tmp[i * p + q2] * gi[q2 * p + j2]
                q2 += 1usize
            }
            v[i * p + j2] = corr * s2
            j2 += 1usize
        }
        i += 1usize
    }
    ret ok
}

// meat += sgn * sum over groups of (group score total)(group score total)'
fn cluster_meat(a: *mem.Arena, sc: []const f64, n: usize, p: usize, ids: []const usize, g: usize, sgn: f64, meat: []f64) -> err {
    let (cs, e1) = mem.alloc[f64](a, g * p)
    if e1 != ok { ret e1 }
    var q = 0usize
    while q < g * p {
        cs[q] = 0.0f64
        q += 1usize
    }
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            cs[ids[i] * p + c] += sc[c * n + i]
            c += 1usize
        }
        i += 1usize
    }
    var gg = 0usize
    while gg < g {
        var r = 0usize
        while r < p {
            var s = 0usize
            while s < p {
                meat[r * p + s] += sgn * cs[gg * p + r] * cs[gg * p + s]
                s += 1usize
            }
            r += 1usize
        }
        gg += 1usize
    }
    ret ok
}

// fixest's non-positive-definite repair: when an eigenvalue of the symmetric v is <= 0, every eigenvalue is raised to at
// least 1e-16 and v rebuilt (eigenvalues by cyclic Jacobi rotations)
fn eigfix(a: *mem.Arena, v: []f64, p: usize) -> err {
    let (m, e1) = mem.alloc[f64](a, p * p)
    let (ev, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < p * p {
        m[i] = v[i]
        ev[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        ev[i * p + i] = 1.0f64
        i += 1usize
    }
    var fro = 0.0f64
    i = 0usize
    while i < p * p {
        fro += m[i] * m[i]
        i += 1usize
    }
    var sweep = 0usize
    while sweep < 60usize {
        var off = 0.0f64
        var r = 0usize
        while r < p {
            var s = r + 1usize
            while s < p {
                off += m[r * p + s] * m[r * p + s]
                s += 1usize
            }
            r += 1usize
        }
        if off <= 1.0e-32f64 * fro { break }
        r = 0usize
        while r < p {
            var s2 = r + 1usize
            while s2 < p {
                let apq = m[r * p + s2]
                if math.abs[f64](apq) > 1.0e-300f64 {
                    let theta = (m[s2 * p + s2] - m[r * p + r]) / (2.0f64 * apq)
                    var t = 1.0f64
                    if theta < 0.0f64 { t = 0.0f64 - 1.0f64 }
                    t = t / (math.abs[f64](theta) + math.sqrt[f64](theta * theta + 1.0f64))
                    let cs = 1.0f64 / math.sqrt[f64](t * t + 1.0f64)
                    let sn = t * cs
                    var k = 0usize
                    while k < p {
                        let akp = m[k * p + r]
                        let akq = m[k * p + s2]
                        m[k * p + r] = cs * akp - sn * akq
                        m[k * p + s2] = sn * akp + cs * akq
                        k += 1usize
                    }
                    k = 0usize
                    while k < p {
                        let apk = m[r * p + k]
                        let aqk = m[s2 * p + k]
                        m[r * p + k] = cs * apk - sn * aqk
                        m[s2 * p + k] = sn * apk + cs * aqk
                        k += 1usize
                    }
                    k = 0usize
                    while k < p {
                        let vkp = ev[k * p + r]
                        let vkq = ev[k * p + s2]
                        ev[k * p + r] = cs * vkp - sn * vkq
                        ev[k * p + s2] = sn * vkp + cs * vkq
                        k += 1usize
                    }
                }
                s2 += 1usize
            }
            r += 1usize
        }
        sweep += 1usize
    }
    var bad = false
    i = 0usize
    while i < p {
        if m[i * p + i] <= 0.0f64 { bad = true }
        i += 1usize
    }
    if !bad { ret ok }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s3 = 0.0f64
            var q = 0usize
            while q < p {
                var lam = m[q * p + q]
                if lam < 1.0e-16f64 { lam = 1.0e-16f64 }
                s3 += ev[i * p + q] * lam * ev[j * p + q]
                q += 1usize
            }
            v[i * p + j] = s3
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// the variance matrix v (p x p) and info = [t degrees of freedom]
fn vcovs(a: *mem.Arena, sc: []const f64, gi: []const f64, n: usize, p: usize, kfull: f64, kcl: f64, vk: usize, cl: []const usize, ncl: usize, lag0: usize, c0: f64, v: []f64, info: []f64) -> err {
    let (meat, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret e1 }
    var z = 0usize
    while z < p * p {
        meat[z] = 0.0f64
        z += 1usize
    }
    let nn = f64(n)
    if vk == 0usize {
        z = 0usize
        while z < p * p {
            v[z] = c0 * gi[z]
            z += 1usize
        }
        info[0usize] = nn - kfull
        ret ok
    }
    var corr = 1.0f64
    if vk == 1usize {
        var i = 0usize
        while i < n {
            var r = 0usize
            while r < p {
                var s = 0usize
                while s < p {
                    meat[r * p + s] += sc[r * n + i] * sc[s * n + i]
                    s += 1usize
                }
                r += 1usize
            }
            i += 1usize
        }
        corr = nn / (nn - kfull)
        info[0usize] = nn - kfull
    }
    if vk == 2usize {
        let (c1raw, e2) = mem.alloc[usize](a, n)
        if e2 != ok { ret e2 }
        var i2 = 0usize
        while i2 < n {
            c1raw[i2] = cl[i2 * ncl]
            i2 += 1usize
        }
        let (id1, g1, e3) = dense(a, c1raw, n, ngroups(cl, n, ncl, 0usize))
        if e3 != ok { ret e3 }
        let ce1 = cluster_meat(a, sc, n, p, id1, g1, 1.0f64, meat)
        if ce1 != ok { ret ce1 }
        var gm = g1
        if ncl == 2usize {
            let (c2raw, e4) = mem.alloc[usize](a, n)
            let (c12, e5) = mem.alloc[usize](a, n)
            if e4 != ok { ret e4 }
            if e5 != ok { ret e5 }
            i2 = 0usize
            while i2 < n {
                c2raw[i2] = cl[i2 * ncl + 1usize]
                i2 += 1usize
            }
            let rg2 = ngroups(cl, n, ncl, 1usize)
            let (id2, g2, e6) = dense(a, c2raw, n, rg2)
            if e6 != ok { ret e6 }
            i2 = 0usize
            while i2 < n {
                c12[i2] = id1[i2] * g2 + id2[i2]
                i2 += 1usize
            }
            let (id12, g12, e7) = dense(a, c12, n, g1 * g2)
            if e7 != ok { ret e7 }
            let ce2 = cluster_meat(a, sc, n, p, id2, g2, 1.0f64, meat)
            if ce2 != ok { ret ce2 }
            let ce3 = cluster_meat(a, sc, n, p, id12, g12, -1.0f64, meat)
            if ce3 != ok { ret ce3 }
            if g2 < gm { gm = g2 }
        }
        let gf = f64(gm)
        corr = gf / (gf - 1.0f64) * (nn - 1.0f64) / (nn - kcl)
        info[0usize] = gf - 1.0f64
    }
    if vk == 3usize || vk == 4usize {
        // Newey-West (unit = cl col 0, time = cl col 1) or Driscoll-Kraay (time = cl col 0): Bartlett weights over time gaps
        var tc = 0usize
        if vk == 4usize { tc = 0usize } else { tc = 1usize }
        var tmax = 0usize
        var i3 = 0usize
        while i3 < n {
            if cl[i3 * ncl + tc] > tmax { tmax = cl[i3 * ncl + tc] }
            i3 += 1usize
        }
        let (seen, e8) = mem.alloc[f64](a, tmax + 1usize)
        if e8 != ok { ret e8 }
        var q = 0usize
        while q <= tmax {
            seen[q] = 0.0f64
            q += 1usize
        }
        i3 = 0usize
        while i3 < n {
            seen[cl[i3 * ncl + tc]] = 1.0f64
            i3 += 1usize
        }
        var nt = 0usize
        q = 0usize
        while q <= tmax {
            if seen[q] > 0.0f64 { nt += 1usize }
            q += 1usize
        }
        var lag = lag0
        if lag0 == 1000000usize { lag = usize(math.sqrt[f64](math.sqrt[f64](f64(nt)))) }
        // rows: the observations (NW) or the time totals (DK), each with a unit and a time
        var rows = n
        if vk == 4usize { rows = tmax + 1usize }
        let (s2, e9) = mem.alloc[f64](a, rows * p)
        let (ru, e10) = mem.alloc[usize](a, rows)
        let (rt, e11) = mem.alloc[usize](a, rows)
        let (rp, e12) = mem.alloc[f64](a, rows)
        if e9 != ok { ret e9 }
        if e10 != ok { ret e10 }
        if e11 != ok { ret e11 }
        if e12 != ok { ret e12 }
        q = 0usize
        while q < rows * p {
            s2[q] = 0.0f64
            q += 1usize
        }
        q = 0usize
        while q < rows {
            rp[q] = 0.0f64
            ru[q] = 0usize
            rt[q] = q
            q += 1usize
        }
        i3 = 0usize
        while i3 < n {
            var row = i3
            if vk == 4usize { row = cl[i3 * ncl] }
            rp[row] = 1.0f64
            if vk == 3usize {
                ru[row] = cl[i3 * ncl]
                rt[row] = cl[i3 * ncl + 1usize]
            }
            var c = 0usize
            while c < p {
                s2[row * p + c] += sc[c * n + i3]
                c += 1usize
            }
            i3 += 1usize
        }
        var ra = 0usize
        while ra < rows {
            if rp[ra] > 0.0f64 {
                var r = 0usize
                while r < p {
                    var s = 0usize
                    while s < p {
                        meat[r * p + s] += s2[ra * p + r] * s2[ra * p + s]
                        s += 1usize
                    }
                    r += 1usize
                }
                var rb = ra + 1usize
                while rb < rows {
                    var gap = 0usize
                    if rt[rb] > rt[ra] { gap = rt[rb] - rt[ra] } else { gap = rt[ra] - rt[rb] }
                    if rp[rb] > 0.0f64 && ru[rb] == ru[ra] && gap >= 1usize && gap <= lag {
                        let wt = 1.0f64 - f64(gap) / f64(lag + 1usize)
                        r = 0usize
                        while r < p {
                            var s3 = 0usize
                            while s3 < p {
                                meat[r * p + s3] += wt * (s2[ra * p + r] * s2[rb * p + s3] + s2[rb * p + r] * s2[ra * p + s3])
                                s3 += 1usize
                            }
                            r += 1usize
                        }
                    }
                    rb += 1usize
                }
            }
            ra += 1usize
        }
        let tf = f64(nt)
        corr = tf / (tf - 1.0f64) * (nn - 1.0f64) / (nn - kfull)
        info[0usize] = tf - 1.0f64
    }
    ret sandwich(a, gi, meat, p, corr, v)
}

// fam: 0 least squares (with instruments when ne > 0), 1 Poisson, 2 logit. x (n*nx), en (n*ne endogenous), zi (n*nz excluded
// instruments) are row-major; fe holds 0-based codes (n*nf); vk: 0 iid, 1 hetero, 2 cluster by cl column 0 (and 1),
// 3 Newey-West (unit, time), 4 Driscoll-Kraay (time); lag0 1000000 means fixest's floor(T^(1/4)).
fn fit(a: *mem.Arena, fam: usize, y: []const f64, x: []const f64, nx: usize, en: []const f64, ne: usize, zi: []const f64, nz: usize, fe: []const usize, nf: usize, vk: usize, cl: []const usize, ncl: usize, lag0: usize, out: []f64) -> err {
    let n = y.len
    let p = nx + ne
    let nc = p + nz + 1usize
    let (goff, e1) = mem.alloc[usize](a, nf + 1usize)
    if e1 != ok { ret e1 }
    goff[0usize] = 0usize
    var j = 0usize
    while j < nf {
        goff[j + 1usize] = goff[j] + ngroups(fe, n, nf, j)
        j += 1usize
    }
    let tg = goff[nf]
    let (gw, e2) = mem.alloc[f64](a, tg)
    let (gs, e3) = mem.alloc[f64](a, tg)
    let (acc, e4) = mem.alloc[f64](a, tg)
    let (w, e5) = mem.alloc[f64](a, n)
    let (dm, e6) = mem.alloc[f64](a, nc * n)
    let (beta, e7) = mem.alloc[f64](a, p)
    let (gi, e8) = mem.alloc[f64](a, p * p)
    let (res, e9) = mem.alloc[f64](a, n)
    let (sc, e10) = mem.alloc[f64](a, p * n)
    let (rv, e11) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    let xh = dm[0usize..p * n]
    var dev = 0.0f64
    var c0 = 1.0f64
    let nnf = f64(n)
    // fixed-effect parameters
    let (usedall, e12) = mem.alloc[usize](a, nf)
    if e12 != ok { ret e12 }
    j = 0usize
    while j < nf {
        usedall[j] = 1usize
        j += 1usize
    }
    let kfe = fe_params(a, fe, n, nf, goff, usedall)
    let kfull = f64(p + kfe)

    if fam == 0usize {
        gweights(n, fe, nf, goff, w, gw)
        // columns: exogenous, endogenous, instruments, response
        var c = 0usize
        while c < nc {
            i = 0usize
            while i < n {
                if c < nx { dm[c * n + i] = x[i * nx + c] } else {
                    if c < p { dm[c * n + i] = en[i * ne + (c - nx)] } else {
                        if c < p + nz { dm[c * n + i] = zi[i * nz + (c - p)] } else { dm[c * n + i] = y[i] }
                    }
                }
                i += 1usize
            }
            demean1(dm[c * n..(c + 1usize) * n], n, fe, nf, goff, gw, w, gs, acc[0usize..0usize])
            c += 1usize
        }
        let ydm = dm[(p + nz) * n..(p + nz + 1usize) * n]
        if ne == 0usize {
            let se0 = solve_ls(a, xh, xh, ydm, w, n, p, beta, gi, res)
            if se0 != ok { ret se0 }
            i = 0usize
            while i < p * n {
                sc[i] = xh[i]
                i += 1usize
            }
        } else {
            // first stage on [exogenous, instruments]
            let kh = nx + nz
            let (hm, e13) = mem.alloc[f64](a, kh * n)
            let (xi, e14) = mem.alloc[f64](a, p * n)
            let (hb, e15) = mem.alloc[f64](a, kh)
            let (hg, e16) = mem.alloc[f64](a, kh * kh)
            let (hr, e17) = mem.alloc[f64](a, n)
            if e13 != ok { ret e13 }
            if e14 != ok { ret e14 }
            if e15 != ok { ret e15 }
            if e16 != ok { ret e16 }
            if e17 != ok { ret e17 }
            i = 0usize
            while i < nx * n {
                hm[i] = dm[i]
                xi[i] = dm[i]
                i += 1usize
            }
            i = 0usize
            while i < nz * n {
                hm[nx * n + i] = dm[p * n + i]
                i += 1usize
            }
            var ec = 0usize
            while ec < ne {
                let es = dm[(nx + ec) * n..(nx + ec + 1usize) * n]
                let se1 = solve_ls(a, hm, hm, es, w, n, kh, hb, hg, hr)
                if se1 != ok { ret se1 }
                i = 0usize
                while i < n {
                    xi[(nx + ec) * n + i] = es[i] - hr[i]
                    i += 1usize
                }
                ec += 1usize
            }
            let se2 = solve_ls(a, xi, xh, ydm, w, n, p, beta, gi, res)
            if se2 != ok { ret se2 }
            i = 0usize
            while i < p * n {
                sc[i] = xi[i]
                i += 1usize
            }
        }
        var rss = 0.0f64
        i = 0usize
        while i < n {
            rss += res[i] * res[i]
            i += 1usize
        }
        dev = rss
        c0 = rss / (nnf - kfull)
        // the fixed effects: demean y - X beta, collecting the means
        i = 0usize
        while i < n {
            var f = y[i]
            c = 0usize
            while c < p {
                if c < nx { f -= x[i * nx + c] * beta[c] } else { f -= en[i * ne + (c - nx)] * beta[c] }
                c += 1usize
            }
            rv[i] = f
            i += 1usize
        }
        var q = 0usize
        while q < tg {
            acc[q] = 0.0f64
            q += 1usize
        }
        demean1(rv, n, fe, nf, goff, gw, w, gs, acc)
        // scores = columns times residuals
        c = 0usize
        while c < p {
            i = 0usize
            while i < n {
                sc[c * n + i] = sc[c * n + i] * res[i]
                i += 1usize
            }
            c += 1usize
        }
    } else {
        // IRLS with the canonical link
        let (mu, e13) = mem.alloc[f64](a, n)
        let (eta, e14) = mem.alloc[f64](a, n)
        let (zw, e15) = mem.alloc[f64](a, n)
        if e13 != ok { ret e13 }
        if e14 != ok { ret e14 }
        if e15 != ok { ret e15 }
        i = 0usize
        while i < n {
            if fam == 1usize {
                mu[i] = y[i] + 0.1f64
                eta[i] = math.log[f64](mu[i])
            } else {
                mu[i] = (y[i] + 0.5f64) / 2.0f64
                eta[i] = math.log[f64](mu[i] / (1.0f64 - mu[i]))
            }
            i += 1usize
        }
        var old = 0.0f64
        i = 0usize
        while i < n {
            if fam == 1usize {
                var t1 = 0.0f64
                if y[i] > 0.0f64 { t1 = y[i] * math.log[f64](y[i] / mu[i]) }
                old += 2.0f64 * (t1 - (y[i] - mu[i]))
            } else {
                old -= 2.0f64 * (y[i] * math.log[f64](mu[i]) + (1.0f64 - y[i]) * math.log[f64](1.0f64 - mu[i]))
            }
            i += 1usize
        }
        var it = 0usize
        while it < 500usize {
            i = 0usize
            while i < n {
                if fam == 1usize { w[i] = mu[i] } else { w[i] = mu[i] * (1.0f64 - mu[i]) }
                zw[i] = eta[i] + (y[i] - mu[i]) / w[i]
                i += 1usize
            }
            gweights(n, fe, nf, goff, w, gw)
            var c = 0usize
            while c <= p {
                i = 0usize
                while i < n {
                    if c < p { dm[c * n + i] = x[i * nx + c] } else { dm[c * n + i] = zw[i] }
                    i += 1usize
                }
                demean1(dm[c * n..(c + 1usize) * n], n, fe, nf, goff, gw, w, gs, acc[0usize..0usize])
                c += 1usize
            }
            let zdm = dm[p * n..(p + 1usize) * n]
            let se3 = solve_ls(a, xh, xh, zdm, w, n, p, beta, gi, res)
            if se3 != ok { ret se3 }
            // eta = z - (z - X beta demeaned)
            i = 0usize
            while i < n {
                var f = zw[i]
                c = 0usize
                while c < p {
                    f -= x[i * nx + c] * beta[c]
                    c += 1usize
                }
                rv[i] = f
                i += 1usize
            }
            var q = 0usize
            while q < tg {
                acc[q] = 0.0f64
                q += 1usize
            }
            demean1(rv, n, fe, nf, goff, gw, w, gs, acc)
            var d2 = 0.0f64
            i = 0usize
            while i < n {
                eta[i] = zw[i] - rv[i]
                if fam == 1usize {
                    mu[i] = math.exp[f64](eta[i])
                    var t2 = 0.0f64
                    if y[i] > 0.0f64 { t2 = y[i] * math.log[f64](y[i] / mu[i]) }
                    d2 += 2.0f64 * (t2 - (y[i] - mu[i]))
                } else {
                    mu[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta[i]))
                    d2 -= 2.0f64 * (y[i] * math.log[f64](mu[i]) + (1.0f64 - y[i]) * math.log[f64](1.0f64 - mu[i]))
                }
                i += 1usize
            }
            dev = d2
            let done = math.abs[f64](d2 - old) / (0.1f64 + math.abs[f64](d2)) < 3.0e-13f64
            old = d2
            it += 1usize
            if done { break }
        }
        c0 = (nnf - 1.0f64) / (nnf - kfull)
        // scores from the last working regression
        var c3 = 0usize
        while c3 < p {
            i = 0usize
            while i < n {
                sc[c3 * n + i] = dm[c3 * n + i] * w[i] * res[i]
                i += 1usize
            }
            c3 += 1usize
        }
    }

    // nested fixed effects drop out of the cluster correction
    var kcl = kfull
    if vk == 2usize {
        let (usedcl, e18) = mem.alloc[usize](a, nf)
        if e18 != ok { ret e18 }
        j = 0usize
        while j < nf {
            usedcl[j] = 1usize
            var cc = 0usize
            while cc < ncl {
                if nested_in(a, fe, nf, j, goff[j + 1usize] - goff[j], n, cl, ncl, cc) { usedcl[j] = 0usize }
                cc += 1usize
            }
            j += 1usize
        }
        kcl = f64(p + fe_params(a, fe, n, nf, goff, usedcl))
    }
    let vo = 4usize * p + 4usize
    let info = out[4usize * p..4usize * p + 1usize]
    let ve = vcovs(a, sc, gi, n, p, kfull, kcl, vk, cl, ncl, lag0, c0, out[vo..vo + p * p], info)
    if ve != ok { ret ve }
    let fx2 = eigfix(a, out[vo..vo + p * p], p)
    if fx2 != ok { ret fx2 }
    j = 0usize
    while j < p {
        out[j] = beta[j]
        let sd = math.sqrt[f64](out[vo + j * p + j])
        out[p + j] = sd
        let tv = beta[j] / sd
        out[2usize * p + j] = tv
        if fam == 0usize {
            out[3usize * p + j] = 2.0f64 * nb.pt(0.0f64 - math.abs[f64](tv), out[4usize * p], true, false)
        } else {
            out[3usize * p + j] = 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](tv), 0.0f64, 1.0f64, true, false)
        }
        j += 1usize
    }
    out[4usize * p + 1usize] = kfull
    out[4usize * p + 2usize] = kcl
    out[4usize * p + 3usize] = dev
    j = 0usize
    while j < tg {
        out[vo + p * p + j] = acc[j]
        j += 1usize
    }
    ret ok
}

// F statistic of H0: coefficients [from, to) are zero, with the model's variance; o = [stat, p-value, df1, df2]
fn wald(a: *mem.Arena, fb: []const f64, p: usize, from: usize, to: usize, o: []f64) -> err {
    let q = to - from
    let (sub, e1) = mem.alloc[f64](a, q * q)
    if e1 != ok { ret e1 }
    let vo = 4usize * p + 4usize
    var i = 0usize
    while i < q {
        var j = 0usize
        while j < q {
            sub[i * q + j] = fb[vo + (from + i) * p + from + j]
            j += 1usize
        }
        i += 1usize
    }
    let (inv, e2) = gp.invert(a, sub, q)
    if e2 != ok { ret e2 }
    var s = 0.0f64
    i = 0usize
    while i < q {
        var j2 = 0usize
        while j2 < q {
            s += fb[from + i] * inv[i * q + j2] * fb[from + j2]
            j2 += 1usize
        }
        i += 1usize
    }
    let f = s / f64(q)
    o[0usize] = f
    o[1usize] = nb.pf(f, f64(q), fb[4usize * p], false, false)
    o[2usize] = f64(q)
    o[3usize] = fb[4usize * p]
    ret ok
}

// predictions for m new rows (levels seen in estimation): link scale when link is true or the model is least squares
fn predict(fb: []const f64, p: usize, nf: usize, sizes: []const usize, xn: []const f64, fen: []const usize, m: usize, fam: usize, link: bool, o: []f64) {
    let ao = 4usize * p + 4usize + p * p
    var r = 0usize
    while r < m {
        var eta = 0.0f64
        var c = 0usize
        while c < p {
            eta += xn[r * p + c] * fb[c]
            c += 1usize
        }
        var base = 0usize
        var j = 0usize
        while j < nf {
            eta += fb[ao + base + fen[r * nf + j]]
            base += sizes[j]
            j += 1usize
        }
        var v = eta
        if !link {
            if fam == 1usize { v = math.exp[f64](eta) }
            if fam == 2usize { v = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta)) }
        }
        o[r] = v
        r += 1usize
    }
}

// Sun-Abraham: cohort-by-relative-period dummies (never-treated cohort value `never`, relative period -1 as the reference),
// fitted by least squares with the fixed effects and aggregated over cohorts by the cell counts. out = [coef (na), se (na)]
// with na = nx + the number of relative periods that have a cell, written as out[0] = na, coef at 1, se at 1 + na; x holds
// the other regressors (n*nx, row-major).
fn sunab(a: *mem.Arena, y: []const f64, x: []const f64, nx: usize, coh: []const f64, per: []const f64, never: f64, fe: []const usize, nf: usize, vk: usize, cl: []const usize, ncl: usize, lag0: usize, out: []f64) -> err {
    let n = y.len
    let (cohs, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var nc = 0usize
    var relmin = 1.0e9f64
    var relmax = 0.0f64 - 1.0e9f64
    var i = 0usize
    while i < n {
        if coh[i] != never {
            var found = false
            var q = 0usize
            while q < nc {
                if cohs[q] == coh[i] { found = true }
                q += 1usize
            }
            if !found {
                cohs[nc] = coh[i]
                nc += 1usize
            }
            let rl = per[i] - coh[i]
            if rl < relmin { relmin = rl }
            if rl > relmax { relmax = rl }
        }
        i += 1usize
    }
    let nrel = usize(relmax - relmin + 0.5f64) + 1usize
    let (cnt, e2) = mem.alloc[f64](a, nrel * nc)
    let (colmap, e3) = mem.alloc[usize](a, nrel * nc)
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var q2 = 0usize
    while q2 < nrel * nc {
        cnt[q2] = 0.0f64
        colmap[q2] = 4294967295usize
        q2 += 1usize
    }
    i = 0usize
    while i < n {
        if coh[i] != never {
            var ci = 0usize
            while cohs[ci] != coh[i] { ci += 1usize }
            let ri = usize(per[i] - coh[i] - relmin + 0.5f64)
            cnt[ri * nc + ci] += 1.0f64
        }
        i += 1usize
    }
    // cohort order does not matter, the dummies are taken by relative period then cohort
    var nd = 0usize
    var r = 0usize
    while r < nrel {
        let rl2 = relmin + f64(r)
        if rl2 != 0.0f64 - 1.0f64 {
            var c = 0usize
            while c < nc {
                if cnt[r * nc + c] > 0.0f64 {
                    colmap[r * nc + c] = nd
                    nd += 1usize
                }
                c += 1usize
            }
        }
        r += 1usize
    }
    let p2 = nx + nd
    let (x2, e4) = mem.alloc[f64](a, n * p2)
    if e4 != ok { ret e4 }
    q2 = 0usize
    while q2 < n * p2 {
        x2[q2] = 0.0f64
        q2 += 1usize
    }
    i = 0usize
    while i < n {
        var cx = 0usize
        while cx < nx {
            x2[i * p2 + cx] = x[i * nx + cx]
            cx += 1usize
        }
        if coh[i] != never {
            var ci2 = 0usize
            while cohs[ci2] != coh[i] { ci2 += 1usize }
            let ri2 = usize(per[i] - coh[i] - relmin + 0.5f64)
            if colmap[ri2 * nc + ci2] != 4294967295usize { x2[i * p2 + nx + colmap[ri2 * nc + ci2]] = 1.0f64 }
        }
        i += 1usize
    }
    var tg = 0usize
    var jf = 0usize
    while jf < nf {
        tg += ngroups(fe, n, nf, jf)
        jf += 1usize
    }
    let (fb, e5) = mem.alloc[f64](a, out_len(p2, tg))
    if e5 != ok { ret e5 }
    let fe0 = fit(a, 0usize, y, x2, p2, y[0usize..0usize], 0usize, y[0usize..0usize], 0usize, fe, nf, vk, cl, ncl, lag0, fb)
    if fe0 != ok { ret fe0 }
    // aggregation matrix rows: the other regressors, then one row per relative period with a cell
    var na = nx
    r = 0usize
    while r < nrel {
        var any = false
        var c2 = 0usize
        while c2 < nc {
            if colmap[r * nc + c2] != 4294967295usize { any = true }
            c2 += 1usize
        }
        if any { na += 1usize }
        r += 1usize
    }
    let (wm, e6) = mem.alloc[f64](a, na * p2)
    if e6 != ok { ret e6 }
    q2 = 0usize
    while q2 < na * p2 {
        wm[q2] = 0.0f64
        q2 += 1usize
    }
    var row = 0usize
    while row < nx {
        wm[row * p2 + row] = 1.0f64
        row += 1usize
    }
    r = 0usize
    while r < nrel {
        var tot = 0.0f64
        var c3 = 0usize
        while c3 < nc {
            if colmap[r * nc + c3] != 4294967295usize { tot += cnt[r * nc + c3] }
            c3 += 1usize
        }
        if tot > 0.0f64 {
            c3 = 0usize
            while c3 < nc {
                if colmap[r * nc + c3] != 4294967295usize { wm[row * p2 + nx + colmap[r * nc + c3]] = cnt[r * nc + c3] / tot }
                c3 += 1usize
            }
            row += 1usize
        }
        r += 1usize
    }
    let vo = 4usize * p2 + 4usize
    var ro = 0usize
    while ro < na {
        var cf = 0.0f64
        var vr = 0.0f64
        var s1 = 0usize
        while s1 < p2 {
            cf += wm[ro * p2 + s1] * fb[s1]
            var s2 = 0usize
            while s2 < p2 {
                vr += wm[ro * p2 + s1] * wm[ro * p2 + s2] * fb[vo + s1 * p2 + s2]
                s2 += 1usize
            }
            s1 += 1usize
        }
        out[1usize + ro] = cf
        out[1usize + na + ro] = math.sqrt[f64](vr)
        ro += 1usize
    }
    out[0usize] = f64(na)
    ret ok
}
