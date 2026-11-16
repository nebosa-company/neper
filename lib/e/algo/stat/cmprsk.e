// R cmprsk::cuminc for one group and one cause: Gray's `cinc` routine, the estimate of the cumulative incidence
// function of a cause with its variance, written as the corner points of the step function (x, f, v), line for line.
//
// Also `timepoints`. Not here: the plot and print methods.

use e.algo.stat.psych as ps
use e.math
use e.mem

// y ascending; ic 1 when the case failed from any cause; icc 1 when from the cause of interest; x, f, v need
// 2 * (distinct cause times) + 2 slots (2 n + 2 is always enough); answers the number of points written
fn cinc(y: []const f64, ic: []const i64, icc: []const i64, x: []f64, f: []f64, v: []f64) -> usize {
    let n = y.len
    var fk = 1.0f64
    var v1 = 0.0f64
    var v2 = 0.0f64
    var v3 = 0.0f64
    // slot k of the Fortran arrays is index k - 1 here
    x[0usize] = 0.0f64
    f[0usize] = 0.0f64
    v[0usize] = 0.0f64
    var lcnt = 1usize
    var l = 1usize
    var ll = 1usize
    var rs = f64(n)
    var ty = y[0usize]
    while true {
        // find the end l of the block of tied times starting at ll
        l = ll
        while l + 1usize <= n && y[l] == ty { l += 1usize }
        var nd1 = 0.0f64
        var nd2 = 0.0f64
        var i = ll
        while i <= l {
            nd1 += f64(icc[i - 1usize])
            nd2 += f64(ic[i - 1usize] - icc[i - 1usize])
            i += 1usize
        }
        let nd = nd1 + nd2
        if nd != 0.0f64 {
            let fkn = fk * (rs - nd) / rs
            if nd1 > 0.0f64 {
                lcnt += 2usize
                f[lcnt - 2usize] = f[lcnt - 3usize]
                f[lcnt - 1usize] = f[lcnt - 2usize] + fk * nd1 / rs
            }
            if nd2 > 0.0f64 && fkn > 0.0f64 {
                var t5 = 1.0f64
                if nd2 > 1.0f64 { t5 = 1.0f64 - (nd2 - 1.0f64) / (rs - 1.0f64) }
                let t6 = fk * fk * t5 * nd2 / (rs * rs)
                let t3 = 1.0f64 / fkn
                let t4 = f[lcnt - 1usize] / fkn
                v1 += t4 * t4 * t6
                v2 += t3 * t4 * t6
                v3 += t3 * t3 * t6
            }
            if nd1 > 0.0f64 {
                var t5 = 1.0f64
                if nd1 > 1.0f64 { t5 = 1.0f64 - (nd1 - 1.0f64) / (rs - 1.0f64) }
                let t6 = fk * fk * t5 * nd1 / (rs * rs)
                var t3 = 0.0f64
                if fkn > 0.0f64 { t3 = 1.0f64 / fkn }
                let t4 = 1.0f64 + t3 * f[lcnt - 1usize]
                v1 += t4 * t4 * t6
                v2 += t3 * t4 * t6
                v3 += t3 * t3 * t6
                let t2 = f[lcnt - 1usize]
                x[lcnt - 2usize] = y[l - 1usize]
                x[lcnt - 1usize] = y[l - 1usize]
                v[lcnt - 2usize] = v[lcnt - 3usize]
                v[lcnt - 1usize] = v1 + t2 * t2 * v3 - 2.0f64 * t2 * v2
            }
            fk = fkn
        }
        rs = f64(n - l)
        l += 1usize
        if l > n { break }
        ll = l
        ty = y[l - 1usize]
    }
    lcnt += 1usize
    x[lcnt - 1usize] = y[n - 1usize]
    f[lcnt - 1usize] = f[lcnt - 2usize]
    v[lcnt - 1usize] = v[lcnt - 2usize]
    ret lcnt
}

// Gray's crst and crstm: the scores s (ng - 1) and their variance matrix vs ((ng - 1)^2, row-major) for comparing the
// cumulative incidence of cause 1 among ng groups. m is 0 censored, 1 the cause, 2 another cause; ig is the 0-based
// group; ist the 0-based stratum, nst strata; y ascending. Answers the statistic s' vs^-1 s, or -1 when vs is singular.
fn crstm(a: *mem.Arena, y: []const f64, m: []const i64, ig: []const i64, ist: []const i64, nst: usize, ng: usize, rho: f64, s: []f64, vs: []f64) -> f64 {
    let ng1 = ng - 1usize
    let nv = ng1 * (ng1 + 1usize) / 2usize
    let (v, e1) = mem.alloc[f64](a, nv)
    let (st, e2) = mem.alloc[f64](a, ng1)
    let (vt, e3) = mem.alloc[f64](a, nv)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < ng1 {
        s[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nv {
        v[i] = 0.0f64
        i += 1usize
    }
    var ks = 0usize
    while ks < nst {
        var n = 0usize
        i = 0usize
        while i < y.len {
            if usize(ist[i]) == ks { n += 1usize }
            i += 1usize
        }
        let (ys, e4) = mem.alloc[f64](a, n)
        let (ms, e5) = mem.alloc[i64](a, n)
        let (igs, e6) = mem.alloc[i64](a, n)
        if e4 != ok || e5 != ok || e6 != ok { ret 0.0f64 / 0.0f64 }
        var k = 0usize
        i = 0usize
        while i < y.len {
            if usize(ist[i]) == ks {
                ys[k] = y[i]
                ms[k] = m[i]
                igs[k] = ig[i]
                k += 1usize
            }
            i += 1usize
        }
        crst(a, ys, ms, igs, ng, rho, st, vt)
        i = 0usize
        while i < ng1 {
            s[i] += st[i]
            i += 1usize
        }
        i = 0usize
        while i < nv {
            v[i] += vt[i]
            i += 1usize
        }
        ks += 1usize
    }
    i = 0usize
    while i < ng1 {
        var j = 0usize
        while j <= i {
            vs[i * ng1 + j] = v[i * (i + 1usize) / 2usize + j]
            vs[j * ng1 + i] = vs[i * ng1 + j]
            j += 1usize
        }
        i += 1usize
    }
    let (inv, e7) = mem.alloc[f64](a, ng1 * ng1)
    if e7 != ok { ret 0.0f64 / 0.0f64 }
    if !ps.invert(a, vs, ng1, inv) { ret 0.0f64 - 1.0f64 }
    var stat = 0.0f64
    i = 0usize
    while i < ng1 {
        var j = 0usize
        while j < ng1 {
            stat += s[i] * inv[i * ng1 + j] * s[j]
            j += 1usize
        }
        i += 1usize
    }
    ret stat
}

fn crst(a: *mem.Arena, y: []const f64, m: []const i64, ig: []const i64, ng: usize, rho: f64, s: []f64, v: []f64) {
    let n = y.len
    let ng1 = ng - 1usize
    let nv = ng1 * (ng1 + 1usize) / 2usize
    let (f1m, e1) = mem.alloc[f64](a, ng)
    let (f1, e2) = mem.alloc[f64](a, ng)
    let (skmm, e3) = mem.alloc[f64](a, ng)
    let (skm, e4) = mem.alloc[f64](a, ng)
    let (c, e5) = mem.alloc[f64](a, ng * ng)
    let (am, e6) = mem.alloc[f64](a, ng * ng)
    let (v3, e7) = mem.alloc[f64](a, ng)
    let (v2, e8) = mem.alloc[f64](a, ng1 * ng)
    let (rs, e9) = mem.alloc[f64](a, ng)
    let (d, e10) = mem.alloc[f64](a, 3usize * ng)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret }
    var i = 0usize
    while i < ng {
        rs[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        rs[usize(ig[i])] += 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < ng1 {
        s[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nv {
        v[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < ng {
        f1m[i] = 0.0f64
        f1[i] = 0.0f64
        skmm[i] = 1.0f64
        skm[i] = 1.0f64
        v3[i] = 0.0f64
        var j = 0usize
        while j < ng1 {
            v2[j + ng1 * i] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < ng {
            c[i + ng * j] = 0.0f64
            am[i + ng * j] = 0.0f64
            j += 1usize
        }
        i += 1usize
    }
    var fm = 0.0f64
    var f = 0.0f64
    var ll = 0usize
    while true {
        var lu = ll
        while lu + 1usize < n && y[lu + 1usize] <= y[ll] { lu += 1usize }
        i = 0usize
        while i < 3usize * ng {
            d[i] = 0.0f64
            i += 1usize
        }
        i = ll
        while i <= lu {
            d[usize(m[i]) + 3usize * usize(ig[i])] += 1.0f64
            i += 1usize
        }
        var nd1 = 0.0f64
        var nd2 = 0.0f64
        i = 0usize
        while i < ng {
            nd1 += d[1usize + 3usize * i]
            nd2 += d[2usize + 3usize * i]
            i += 1usize
        }
        if nd1 != 0.0f64 || nd2 != 0.0f64 {
            var tr = 0.0f64
            var tq = 0.0f64
            i = 0usize
            while i < ng {
                if rs[i] > 0.0f64 {
                    let td = d[1usize + 3usize * i] + d[2usize + 3usize * i]
                    skm[i] = skmm[i] * (rs[i] - td) / rs[i]
                    f1[i] = f1m[i] + skmm[i] * d[1usize + 3usize * i] / rs[i]
                    tr += rs[i] / skmm[i]
                    tq += rs[i] * (1.0f64 - f1m[i]) / skmm[i]
                }
                i += 1usize
            }
            f = fm + nd1 / tr
            let fb = math.pow[f64](1.0f64 - fm, rho)
            i = 0usize
            while i < ng {
                var j = i
                while j < ng {
                    am[i + ng * j] = 0.0f64
                    j += 1usize
                }
                if rs[i] > 0.0f64 {
                    let t1 = rs[i] / skmm[i]
                    am[i + ng * i] = fb * t1 * (1.0f64 - t1 / tr)
                    if am[i + ng * i] != 0.0f64 { c[i + ng * i] += am[i + ng * i] * nd1 / (tr * (1.0f64 - fm)) }
                    j = i + 1usize
                    while j < ng {
                        if rs[j] > 0.0f64 {
                            am[i + ng * j] = 0.0f64 - fb * t1 * rs[j] / (skmm[j] * tr)
                            if am[i + ng * j] != 0.0f64 { c[i + ng * j] += am[i + ng * j] * nd1 / (tr * (1.0f64 - fm)) }
                        }
                        j += 1usize
                    }
                }
                i += 1usize
            }
            i = 1usize
            while i < ng {
                var j = 0usize
                while j < i {
                    am[i + ng * j] = am[j + ng * i]
                    c[i + ng * j] = c[j + ng * i]
                    j += 1usize
                }
                i += 1usize
            }
            i = 0usize
            while i < ng1 {
                if rs[i] > 0.0f64 { s[i] += fb * (d[1usize + 3usize * i] - nd1 * rs[i] * (1.0f64 - f1m[i]) / (skmm[i] * tq)) }
                i += 1usize
            }
            if nd1 > 0.0f64 {
                var k = 0usize
                while k < ng {
                    if rs[k] > 0.0f64 {
                        var t4 = 1.0f64
                        if skm[k] > 0.0f64 { t4 = 1.0f64 - (1.0f64 - f) / skm[k] }
                        var t5 = 1.0f64
                        if nd1 > 1.0f64 { t5 = 1.0f64 - (nd1 - 1.0f64) / (tr * skmm[k] - 1.0f64) }
                        let t3 = t5 * skmm[k] * nd1 / (tr * rs[k])
                        v3[k] += t4 * t4 * t3
                        i = 0usize
                        while i < ng1 {
                            let t1 = am[i + ng * k] - t4 * c[i + ng * k]
                            v2[i + ng1 * k] += t1 * t4 * t3
                            var j = 0usize
                            while j <= i {
                                let t2 = am[j + ng * k] - t4 * c[j + ng * k]
                                v[i * (i + 1usize) / 2usize + j] += t1 * t2 * t3
                                j += 1usize
                            }
                            i += 1usize
                        }
                    }
                    k += 1usize
                }
            }
            if nd2 != 0.0f64 {
                var k = 0usize
                while k < ng {
                    if skm[k] > 0.0f64 && d[2usize + 3usize * k] > 0.0f64 {
                        let t4 = (1.0f64 - f) / skm[k]
                        var t5 = 1.0f64
                        if d[2usize + 3usize * k] > 1.0f64 { t5 = 1.0f64 - (d[2usize + 3usize * k] - 1.0f64) / (rs[k] - 1.0f64) }
                        let t3 = t5 * (skmm[k] * skmm[k] * d[2usize + 3usize * k]) / (rs[k] * rs[k])
                        v3[k] += t4 * t4 * t3
                        i = 0usize
                        while i < ng1 {
                            let t1 = t4 * c[i + ng * k]
                            v2[i + ng1 * k] -= t1 * t4 * t3
                            var j = 0usize
                            while j <= i {
                                let t2 = t4 * c[j + ng * k]
                                v[i * (i + 1usize) / 2usize + j] += t1 * t2 * t3
                                j += 1usize
                            }
                            i += 1usize
                        }
                    }
                    k += 1usize
                }
            }
        }
        if lu + 1usize >= n { break }
        i = ll
        while i <= lu {
            rs[usize(ig[i])] -= 1.0f64
            i += 1usize
        }
        fm = f
        i = 0usize
        while i < ng {
            f1m[i] = f1[i]
            skmm[i] = skm[i]
            i += 1usize
        }
        ll = lu + 1usize
    }
    i = 0usize
    while i < ng1 {
        var j = 0usize
        while j <= i {
            let l = i * (i + 1usize) / 2usize + j
            var k = 0usize
            while k < ng {
                v[l] += c[i + ng * k] * c[j + ng * k] * v3[k]
                v[l] += c[i + ng * k] * v2[j + ng1 * k]
                v[l] += c[j + ng * k] * v2[i + ng1 * k]
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
}

// timepoints: the estimate and variance of a cuminc step function (corners x, f, v, k of them) at ascending times; NaN beyond the last corner or before the first
fn timepoints(x: []const f64, f: []const f64, v: []const f64, times: []const f64, est: []f64, var_: []f64) {
    let nan = 0.0f64 / 0.0f64
    let n = x.len
    var t = 0usize
    while t < times.len {
        est[t] = nan
        var_[t] = nan
        let tp = times[t]
        if x[n - 1usize] < tp { t += 1usize
            continue }
        var at = 0usize
        var have = false
        if x[n - 1usize] == tp {
            at = n
            have = true
        } else {
            var k = n - 1usize
            while k >= 1usize {
                if x[k - 1usize] <= tp {
                    at = k + 1usize
                    have = true
                    break
                }
                k -= 1usize
            }
        }
        if have {
            est[t] = f[at - 1usize]
            var_[t] = v[at - 1usize]
        }
        t += 1usize
    }
}
