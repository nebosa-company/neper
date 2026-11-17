// R package cluster: fanny (fuzzy analysis), ported from cluster 2.1.8.2's fanny.c: dysta3, the fuzzy iterations, caddy (the closest hard clustering) and fygur
// (silhouette of the hard clustering). A dissimilarity here is R's dist vector, the column-wise lower triangle (dss[0] = d(2,1), dss[1] = d(3,1), ...).
// A data matrix is n by p column-major; an NA in a column marked jtmd[j] < 0 is coded by valmd[j] (e.algo.stat.clusterpkg.na_prepare).

use e.algo.stat.clusterpkg as cp
use e.math
use e.mem

// memb: n by k column-major memberships; dunn, normalized: the two coefficients of $coeff; obj: $objective; k_crisp: the number of non-empty hard clusters;
// iter: the iteration count (-1 when not converged within maxit); clu: the closest hard clustering 1..k; silinf: n by 4 column-major (cluster, neighbour, width,
// observation) and avsil the average width per cluster, ttsil the overall one, when there are 2 <= k_crisp < n hard clusters and all_stats
type FannyFit = struct {
    memb: []f64, dunn: f64, normalized: f64, obj: f64, k_crisp: usize, clu: []usize, iter: i64, converged: bool,
    silinf: []f64, avsil: []f64, ttsil: f64, has_sil: bool
}

// the dist vector of the rows of x: ndyst 1 euclidean, 2 manhattan, 3 squared euclidean; 1 when a pair has no variable in common (that entry is -1)
fn dysta3(x: []const f64, nn: usize, p: usize, dys: []f64, ndyst: usize, jtmd: []const i64, valmd: []const f64) -> usize {
    var jhalt = 0usize
    var nlk = 0usize
    var l = 0usize
    while l + 1usize < nn {
        var k = l + 1usize
        while k < nn {
            var clk = 0.0f64
            var npres = 0usize
            var jj = 0usize
            var j = 0usize
            while j < p {
                var skip = false
                if jtmd[j] < 0i64 {
                    if x[l + jj] == valmd[j] || x[k + jj] == valmd[j] { skip = true }
                }
                if !skip {
                    npres += 1usize
                    let d = x[l + jj] - x[k + jj]
                    if ndyst != 2usize { clk += d * d } else { clk += math.abs[f64](d) }
                }
                j += 1usize
                jj += nn
            }
            if npres == 0usize {
                dys[nlk] = 0.0f64 - 1.0f64
                jhalt = 1usize
            } else {
                clk *= f64(p) / f64(npres)
                if ndyst == 1usize { dys[nlk] = math.sqrt[f64](clk) } else { dys[nlk] = clk }
            }
            k += 1usize
            nlk += 1usize
        }
        l += 1usize
    }
    ret jhalt
}

// the index into dss of the pair (m, i), 0-based, m != i
fn dss_at(nn: usize, m: usize, i: usize) -> usize {
    var lo = m
    var hi = i
    if i < m {
        lo = i
        hi = m
    }
    ret lo * nn + hi - (lo + 1usize) * (lo + 2usize) / 2usize
}

// the iterations; p holds the memberships (compute_p false) or is overwritten with the initial ones; returns the iteration count in nit (-1 not converged)
// and obj[0..4) = (-, criterion, PC, normalized PC)
fn fuzzy(nn: usize, k: usize, p: []f64, dp: []f64, pt: []f64, dss: []const f64, esp: []f64, ef: []f64, obj: []f64, r: f64, tol: f64, nit: []i64, compute_p: bool) {
    var j = 0usize
    var m = 0usize
    if compute_p {
        let p0 = 0.1f64 / f64(k - 1usize)
        m = 0usize
        while m < nn {
            j = 0usize
            while j < k {
                p[m + j * nn] = p0
                j += 1usize
            }
            m += 1usize
        }
        let ndk = nn / k
        var nd = ndk
        j = 0usize
        m = 0usize
        while m < nn {
            p[m + j * nn] = 0.9f64
            if m + 1usize >= nd {
                j += 1usize
                if j + 1usize == k { nd = nn } else { nd += ndk }
            }
            var jj = 0usize
            while jj < k {
                p[m + jj * nn] = math.pow[f64](p[m + jj * nn], r)
                jj += 1usize
            }
            m += 1usize
        }
    } else {
        m = 0usize
        while m < nn {
            j = 0usize
            while j < k {
                p[m + j * nn] = math.pow[f64](p[m + j * nn], r)
                j += 1usize
            }
            m += 1usize
        }
    }
    var cryt = 0.0f64
    j = 0usize
    while j < k {
        esp[j] = 0.0f64
        ef[j] = 0.0f64
        m = 0usize
        while m < nn {
            esp[j] += p[m + j * nn]
            var i = 0usize
            while i < nn {
                if i != m {
                    let mi = dss_at(nn, m, i)
                    dp[m + j * nn] += p[i + j * nn] * dss[mi]
                    ef[j] += p[i + j * nn] * p[m + j * nn] * dss[mi]
                }
                i += 1usize
            }
            m += 1usize
        }
        cryt += ef[j] / (esp[j] * 2.0f64)
        j += 1usize
    }
    var crt = cryt
    let reen = 1.0f64 / (r - 1.0f64)
    var it = 0usize
    var converged = false
    while true {
        it += 1usize
        if i64(it) > nit[0usize] { break }
        m = 0usize
        while m < nn {
            var dt = 0.0f64
            j = 0usize
            while j < k {
                pt[j] = math.pow[f64](esp[j] / (dp[m + j * nn] - ef[j] / (2.0f64 * esp[j])), reen)
                dt += pt[j]
                j += 1usize
            }
            var xx = 0.0f64
            j = 0usize
            while j < k {
                pt[j] /= dt
                if pt[j] < 0.0f64 { xx += pt[j] }
                j += 1usize
            }
            j = 0usize
            while j < k {
                if pt[j] > 0.0f64 { pt[j] = math.pow[f64](pt[j] / (1.0f64 - xx), r) } else { pt[j] = 0.0f64 }
                let d_mj = pt[j] - p[m + j * nn]
                esp[j] += d_mj
                var i = 0usize
                while i < nn {
                    if i != m {
                        let mi = dss_at(nn, m, i)
                        let ddd = d_mj * dss[mi]
                        dp[i + j * nn] += ddd
                        ef[j] += p[i + j * nn] * 2.0f64 * ddd
                    }
                    i += 1usize
                }
                p[m + j * nn] = pt[j]
                j += 1usize
            }
            m += 1usize
        }
        cryt = 0.0f64
        j = 0usize
        while j < k {
            cryt += ef[j] / (esp[j] * 2.0f64)
            j += 1usize
        }
        var gap = cryt - crt
        if gap < 0.0f64 { gap = 0.0f64 - gap }
        if gap <= tol * cryt {
            converged = true
            break
        }
        crt = cryt
    }
    if converged { nit[0usize] = i64(it) } else { nit[0usize] = 0i64 - 1i64 }
    obj[1usize] = cryt
    crt = 0.0f64
    j = 0usize
    while j < k {
        crt += esp[j]
        j += 1usize
    }
    crt /= f64(nn)
    obj[2usize] = crt
    var xx = math.pow[f64](f64(k), r - 1.0f64)
    obj[3usize] = (xx * crt - 1.0f64) / (xx - 1.0f64)
    xx = 1.0f64 / r
    m = 0usize
    while m < nn {
        j = 0usize
        while j < k {
            p[m + j * nn] = math.pow[f64](p[m + j * nn], xx)
            j += 1usize
        }
        m += 1usize
    }
}

// caddy: the closest hard clustering ncluv (1..ktrue), the order nfuzz in which the memberships' columns are reported, and the columns reordered
fn caddy(nn: usize, k: usize, p: []f64, nfuzz: []usize, ncluv: []usize, rdraw: []f64) -> usize {
    var pbest = p[0usize]
    var nbest = 1usize
    var i = 1usize
    while i < k {
        if pbest < p[i * nn] {
            pbest = p[i * nn]
            nbest = i + 1usize
        }
        i += 1usize
    }
    nfuzz[0usize] = nbest
    ncluv[0usize] = 1usize
    var ktrue = 1usize
    var m = 1usize
    while m < nn {
        pbest = p[m]
        nbest = 1usize
        i = 1usize
        while i < k {
            if pbest < p[m + i * nn] {
                pbest = p[m + i * nn]
                nbest = i + 1usize
            }
            i += 1usize
        }
        var stay = false
        var ktry = 0usize
        while ktry < ktrue {
            if nfuzz[ktry] == nbest {
                stay = true
                ncluv[m] = ktry + 1usize
                break
            }
            ktry += 1usize
        }
        if !stay {
            nfuzz[ktrue] = nbest
            ktrue += 1usize
            ncluv[m] = ktrue
        }
        m += 1usize
    }
    if ktrue < k {
        var kwalk = ktrue
        while kwalk < k {
            var kleft = 1usize
            while kleft <= k {
                var stay = false
                var ktry = 0usize
                while ktry < kwalk {
                    if nfuzz[ktry] == kleft {
                        stay = true
                        break
                    }
                    ktry += 1usize
                }
                if !stay {
                    nfuzz[kwalk] = kleft
                    break
                }
                kleft += 1usize
            }
            kwalk += 1usize
        }
    }
    m = 0usize
    while m < nn {
        i = 0usize
        while i < k {
            rdraw[i] = p[m + (nfuzz[i] - 1usize) * nn]
            i += 1usize
        }
        i = 0usize
        while i < k {
            p[m + i * nn] = rdraw[i]
            i += 1usize
        }
        m += 1usize
    }
    ret ktrue
}

// fygur: the silhouette information of the hard clustering ncluv (1-based labels, 0-based array) from dss; avsyl[1..kk]; returns the overall average
fn fygur(a: *mem.Arena, kk: usize, nn: usize, ncluv: []const usize, dss: []const f64, s: f64, avsyl: []f64, sylinf: []f64) -> (f64, err) {
    let (nelem, e1) = cp.zu(a, nn + 1usize)
    if e1 != ok { ret (0.0f64, e1) }
    let (nsend, e2) = cp.zu(a, nn + 1usize)
    if e2 != ok { ret (0.0f64, e2) }
    let (negbr, e3) = cp.zi(a, nn + 1usize)
    if e3 != ok { ret (0.0f64, e3) }
    let (syl, e4) = cp.zf(a, nn + 1usize)
    if e4 != ok { ret (0.0f64, e4) }
    let (srank, e5) = cp.zf(a, nn + 1usize)
    if e5 != ok { ret (0.0f64, e5) }
    var nsylr = 0usize
    var ttsyl = 0.0f64
    var k = 1usize
    while k <= kk {
        var ntt = 0usize
        var j = 1usize
        while j <= nn {
            if ncluv[j - 1usize] == k {
                nelem[ntt] = j
                ntt += 1usize
            }
            j += 1usize
        }
        j = 0usize
        while j < ntt {
            let nj = nelem[j]
            var dysb = s * 1.1f64 + 1.0f64
            negbr[j] = 0i64 - 1i64
            var kq = 1usize
            while kq <= kk {
                if kq != k {
                    var nbb = 0usize
                    var db = 0.0f64
                    var l = 1usize
                    while l <= nn {
                        if ncluv[l - 1usize] == kq {
                            nbb += 1usize
                            if l != nj { db += dss[dss_at(nn, l - 1usize, nj - 1usize)] }
                        }
                        l += 1usize
                    }
                    db /= f64(nbb)
                    if dysb > db {
                        dysb = db
                        negbr[j] = i64(kq)
                    }
                }
                kq += 1usize
            }
            if ntt > 1usize {
                var dysa = 0.0f64
                var l = 0usize
                while l < ntt {
                    let nl = nelem[l]
                    if nj != nl { dysa += dss[dss_at(nn, nj - 1usize, nl - 1usize)] }
                    l += 1usize
                }
                dysa /= f64(ntt - 1usize)
                if dysa > 0.0f64 {
                    if dysb > 0.0f64 {
                        if dysb > dysa {
                            syl[j] = 1.0f64 - dysa / dysb
                        } else {
                            if dysb < dysa { syl[j] = dysb / dysa - 1.0f64 } else { syl[j] = 0.0f64 }
                        }
                        if syl[j] < 0.0f64 - 1.0f64 {
                            syl[j] = 0.0f64 - 1.0f64
                        } else {
                            if syl[j] > 1.0f64 { syl[j] = 1.0f64 }
                        }
                    } else {
                        syl[j] = 0.0f64 - 1.0f64
                    }
                } else {
                    if dysb > 0.0f64 { syl[j] = 1.0f64 } else { syl[j] = 0.0f64 }
                }
            } else {
                syl[j] = 0.0f64
            }
            j += 1usize
        }
        avsyl[k] = 0.0f64
        j = 0usize
        while j < ntt {
            var lang = 0usize
            var symax = 0.0f64 - 2.0f64
            var l = 0usize
            while l < ntt {
                if symax < syl[l] {
                    symax = syl[l]
                    lang = l
                }
                l += 1usize
            }
            nsend[j] = lang
            srank[j] = symax
            avsyl[k] += srank[j]
            syl[lang] = 0.0f64 - 3.0f64
            j += 1usize
        }
        ttsyl += avsyl[k]
        avsyl[k] /= f64(ntt)
        if ntt < 2usize {
            sylinf[nsylr] = f64(k)
            sylinf[nn + nsylr] = f64(negbr[0usize])
            sylinf[2usize * nn + nsylr] = 0.0f64
            sylinf[3usize * nn + nsylr] = f64(nelem[0usize])
            nsylr += 1usize
        } else {
            j = 0usize
            while j < ntt {
                let nj = nsend[j]
                sylinf[nsylr] = f64(k)
                sylinf[nn + nsylr] = f64(negbr[nj])
                sylinf[2usize * nn + nsylr] = srank[j]
                sylinf[3usize * nn + nsylr] = f64(nelem[nj])
                nsylr += 1usize
                j += 1usize
            }
        }
        k += 1usize
    }
    ret (ttsyl / f64(nn), ok)
}

// cluster::fanny. With have_diss the dist vector is dss_in (length n (n - 1) / 2), otherwise dysta3 computes it from x (n by jpp, column-major) and ndyst.
// r is memb.exp (> 1), ini holds the starting memberships (n by k) when has_ini, all_stats false is cluster.only. kk must be in 1..n/2 - 1
fn fanny(a: *mem.Arena, dss_in: []const f64, have_diss: bool, x: []const f64, nn: usize, jpp: usize, kk: usize, jtmd: []const i64, valmd: []const f64, ndyst: usize,
         r: f64, tol: f64, maxit: usize, ini: []const f64, has_ini: bool, all_stats: bool) -> (FannyFit, err) {
    var fit: FannyFit = zero
    if kk < 1usize || nn / 2usize < 2usize || kk > nn / 2usize - 1usize || !(r > 1.0f64) { ret (fit, cp.BadArgument) }
    let nd = nn * (nn - 1usize) / 2usize
    let (dss, e1) = cp.zf(a, nd + 1usize)
    if e1 != ok { ret (fit, e1) }
    if have_diss {
        var q = 0usize
        while q < nd {
            dss[q] = dss_in[q]
            q += 1usize
        }
    } else {
        if dysta3(x, nn, jpp, dss, ndyst, jtmd, valmd) != 0usize { ret (fit, cp.BadArgument) }
    }
    let (p, e2) = cp.zf(a, nn * kk)
    if e2 != ok { ret (fit, e2) }
    let (dp, e3) = cp.zf(a, nn * kk)
    if e3 != ok { ret (fit, e3) }
    let (pt, e4) = cp.zf(a, kk + 1usize)
    if e4 != ok { ret (fit, e4) }
    let (esp, e5) = cp.zf(a, kk)
    if e5 != ok { ret (fit, e5) }
    let (ef, e6) = cp.zf(a, kk)
    if e6 != ok { ret (fit, e6) }
    let (obj, e7) = cp.zf(a, 4usize)
    if e7 != ok { ret (fit, e7) }
    let (nit, e8) = cp.zi(a, 1usize)
    if e8 != ok { ret (fit, e8) }
    nit[0usize] = i64(maxit)
    if has_ini {
        var q = 0usize
        while q < nn * kk {
            p[q] = ini[q]
            q += 1usize
        }
    }
    fuzzy(nn, kk, p, dp, pt, dss, esp, ef, obj, r, tol, nit, !has_ini)
    let (nfuzz, e9) = cp.zu(a, kk)
    if e9 != ok { ret (fit, e9) }
    let (ncluv, e10) = cp.zu(a, nn)
    if e10 != ok { ret (fit, e10) }
    let ktrue = caddy(nn, kk, p, nfuzz, ncluv, pt)
    fit.memb = p
    fit.clu = ncluv
    fit.k_crisp = ktrue
    fit.obj = obj[1usize]
    fit.iter = nit[0usize]
    fit.converged = nit[0usize] > 0i64
    if r == 2.0f64 {
        fit.dunn = obj[2usize]
        fit.normalized = obj[3usize]
    } else {
        var cf = 0.0f64
        var q = 0usize
        while q < nn * kk {
            cf += p[q] * p[q]
            q += 1usize
        }
        cf /= f64(nn)
        fit.dunn = cf
        fit.normalized = (f64(kk) * cf - 1.0f64) / f64(kk - 1usize)
    }
    if all_stats && 2usize <= ktrue && ktrue < nn {
        var s = 0.0f64
        var i = 0usize
        while i < nd {
            if s < dss[i] { s = dss[i] }
            i += 1usize
        }
        let (sylinf, e11) = cp.zf(a, nn * 4usize)
        if e11 != ok { ret (fit, e11) }
        let (av2, e12) = cp.zf(a, ktrue + 1usize)
        if e12 != ok { ret (fit, e12) }
        let (tt, e13) = fygur(a, ktrue, nn, ncluv, dss, s, av2, sylinf)
        if e13 != ok { ret (fit, e13) }
        let (avs, e14) = cp.zf(a, ktrue)
        if e14 != ok { ret (fit, e14) }
        i = 0usize
        while i < ktrue {
            avs[i] = av2[i + 1usize]
            i += 1usize
        }
        fit.silinf = sylinf
        fit.avsil = avs
        fit.ttsil = tt
        fit.has_sil = true
    }
    ret (fit, ok)
}
