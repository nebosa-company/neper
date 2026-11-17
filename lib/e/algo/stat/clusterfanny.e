// R cluster (Maechler et al., 2.1.8.2): fanny, fuzzy analysis clustering, ported from the package's fanny.c.
//
//   fanny_dysta   the dissimilarities of a data matrix with missing values, in R's dist order (euclidean, manhattan, SqEuclidean)
//   fanny_core    the membership matrix by the fuzzy iterations (memb.exp, tol, maxit, starting memberships given or computed),
//                 the objective, Dunn's partition coefficient and its normalised form, the crisp clustering with k.crisp, the
//                 number of iterations and whether they converged, and the silhouette of the crisp clustering
//
// A data matrix is n by p row-major with NaN as a missing value; the dissimilarity is an R dist vector of n(n-1)/2 entries. The
// membership matrix is n by k column-major.
//
// Not here: the print and summary methods.

use e.math
use e.mem

type FannyOut = struct {
    p: []f64,
    clu: []usize,
    ktrue: usize,
    cryt: f64,
    pc: f64,
    npc: f64,
    nit: i64,
    avsil: []f64,
    ttsil: f64,
    silinf: []f64,
    dosyl: bool
}

// dysta3(): ndyst 1 euclidean, 2 manhattan, 3 squared euclidean; 1 is returned when some pair shares no observed column (those
// entries are -1)
fn fanny_dysta(x: []const f64, n: usize, p: usize, ndyst: usize, dys: []f64) -> usize {
    var jhalt = 0usize
    var nlk = 0usize
    var l = 0usize
    while l + 1usize < n {
        var k = l + 1usize
        while k < n {
            var clk = 0.0f64
            var npres = 0usize
            var j = 0usize
            while j < p {
                let u = x[l * p + j]
                let v = x[k * p + j]
                if u == u && v == v {
                    npres += 1usize
                    let d = u - v
                    if ndyst != 2usize {
                        clk += d * d
                    } else {
                        clk += math.abs[f64](d)
                    }
                }
                j += 1usize
            }
            if npres == 0usize {
                dys[nlk] = 0.0f64 - 1.0f64
                jhalt = 1usize
            } else {
                clk = clk * (f64(p) / f64(npres))
                if ndyst == 1usize {
                    dys[nlk] = math.sqrt[f64](clk)
                } else {
                    dys[nlk] = clk
                }
            }
            nlk += 1usize
            k += 1usize
        }
        l += 1usize
    }
    ret jhalt
}

// the index of d(m, i), 0-based, in a dist vector of nn objects
fn fanny_mi(nn: usize, m: usize, i: usize) -> usize {
    var lo = m
    var hi = i
    if i < m {
        lo = i
        hi = m
    }
    ret lo * nn + hi - (lo + 1usize) * (lo + 2usize) / 2usize
}

// fanny(): ini holds n * k starting memberships (column-major), or is empty to compute them. maxit is the iteration limit.
fn fanny_core(a: *mem.Arena, dss: []const f64, nn: usize, k: usize, ini: []const f64, r: f64, tol: f64, maxit: usize, all_stats: bool) -> (FannyOut, err) {
    let (p, e1) = mem.alloc[f64](a, nn * k)
    if e1 != ok { ret (zero, e1) }
    let (dp, e2) = mem.alloc[f64](a, nn * k)
    if e2 != ok { ret (zero, e2) }
    let (pt, e3) = mem.alloc[f64](a, k)
    if e3 != ok { ret (zero, e3) }
    let (esp, e4) = mem.alloc[f64](a, k)
    if e4 != ok { ret (zero, e4) }
    let (ef, e5) = mem.alloc[f64](a, k)
    if e5 != ok { ret (zero, e5) }
    let (nfuzz, e6) = mem.alloc[usize](a, k)
    if e6 != ok { ret (zero, e6) }
    let (ncluv, e7) = mem.alloc[usize](a, nn)
    if e7 != ok { ret (zero, e7) }
    var i = 0usize
    while i < nn * k {
        dp[i] = 0.0f64
        p[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        pt[i] = 0.0f64
        esp[i] = 0.0f64
        ef[i] = 0.0f64
        nfuzz[i] = 0usize
        i += 1usize
    }
    // fuzzy()
    if ini.len == 0usize {
        let p0 = 0.1f64 / f64(k - 1usize)
        var m = 0usize
        var j = 0usize
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
                if j + 1usize == k {
                    nd = nn
                } else {
                    nd += ndk
                }
            }
            var jj = 0usize
            while jj < k {
                p[m + jj * nn] = math.pow[f64](p[m + jj * nn], r)
                jj += 1usize
            }
            m += 1usize
        }
    } else {
        i = 0usize
        while i < nn * k {
            p[i] = math.pow[f64](ini[i], r)
            i += 1usize
        }
    }
    var cryt = 0.0f64
    var j = 0usize
    while j < k {
        esp[j] = 0.0f64
        ef[j] = 0.0f64
        var m = 0usize
        while m < nn {
            esp[j] += p[m + j * nn]
            i = 0usize
            while i < nn {
                if i != m {
                    let mi = fanny_mi(nn, m, i)
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
    var converged = false
    var it = 0usize
    var going = true
    while going {
        it += 1usize
        if it > maxit {
            going = false
        } else {
            var m = 0usize
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
                    pt[j] = pt[j] / dt
                    if pt[j] < 0.0f64 { xx += pt[j] }
                    j += 1usize
                }
                j = 0usize
                while j < k {
                    if pt[j] > 0.0f64 {
                        pt[j] = math.pow[f64](pt[j] / (1.0f64 - xx), r)
                    } else {
                        pt[j] = 0.0f64
                    }
                    let d_mj = pt[j] - p[m + j * nn]
                    esp[j] += d_mj
                    i = 0usize
                    while i < nn {
                        if i != m {
                            let mi = fanny_mi(nn, m, i)
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
            if math.abs[f64](cryt - crt) <= tol * cryt {
                converged = true
                going = false
            } else {
                crt = cryt
            }
        }
    }
    var nit = 0i64 - 1i64
    if converged { nit = i64(it) }
    crt = 0.0f64
    j = 0usize
    while j < k {
        crt += esp[j]
        j += 1usize
    }
    crt = crt / f64(nn)
    let pc = crt
    var xk = math.pow[f64](f64(k), r - 1.0f64)
    let npc = (xk * crt - 1.0f64) / (xk - 1.0f64)
    xk = 1.0f64 / r
    i = 0usize
    while i < nn * k {
        p[i] = math.pow[f64](p[i], xk)
        i += 1usize
    }
    // caddy(): the crisp clustering and the memberships in the order of the clusters found
    var pbest = p[0usize]
    var nbest = 1usize
    i = 1usize
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
        while ktry < ktrue && !stay {
            if nfuzz[ktry] == nbest {
                stay = true
                ncluv[m] = ktry + 1usize
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
            var placed = false
            while kleft <= k && !placed {
                var seen = false
                var ktry = 0usize
                while ktry < kwalk {
                    if nfuzz[ktry] == kleft { seen = true }
                    ktry += 1usize
                }
                if !seen {
                    nfuzz[kwalk] = kleft
                    placed = true
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
            pt[i] = p[m + (nfuzz[i] - 1usize) * nn]
            i += 1usize
        }
        i = 0usize
        while i < k {
            p[m + i * nn] = pt[i]
            i += 1usize
        }
        m += 1usize
    }
    let (silinf, e8) = mem.alloc[f64](a, nn * 4usize)
    if e8 != ok { ret (zero, e8) }
    // the package keeps the per-cluster silhouette averages in the scratch vector pt, so entries past the crisp clusters hold what the
    // membership step left there
    let avsil = pt
    i = 0usize
    while i < nn * 4usize {
        silinf[i] = 0.0f64
        i += 1usize
    }
    var ttsil = 0.0f64
    let dosyl = all_stats && 2usize <= ktrue && ktrue < nn
    if dosyl {
        // fygur(): the silhouette of the crisp clustering
        let nhalf = nn * (nn - 1usize) / 2usize
        var s = 0.0f64
        i = 0usize
        while i < nhalf {
            if s < dss[i] { s = dss[i] }
            i += 1usize
        }
        let (syl, e10) = mem.alloc[f64](a, nn)
        if e10 != ok { ret (zero, e10) }
        let (srank, e11) = mem.alloc[f64](a, nn)
        if e11 != ok { ret (zero, e11) }
        let (negbr, e12) = mem.alloc[usize](a, nn)
        if e12 != ok { ret (zero, e12) }
        let (nelem, e13) = mem.alloc[usize](a, nn)
        if e13 != ok { ret (zero, e13) }
        let (nsend, e14) = mem.alloc[usize](a, nn)
        if e14 != ok { ret (zero, e14) }
        var nsylr = 0usize
        var kc = 1usize
        while kc <= ktrue {
            var ntt = 0usize
            var jx = 1usize
            while jx <= nn {
                if ncluv[jx - 1usize] == kc {
                    nelem[ntt] = jx
                    ntt += 1usize
                }
                jx += 1usize
            }
            var jj = 0usize
            while jj < ntt {
                let nj = nelem[jj]
                var dysb = s * 1.1f64 + 1.0f64
                negbr[jj] = 0usize
                var kq = 1usize
                while kq <= ktrue {
                    if kq != kc {
                        var nbb = 0usize
                        var db = 0.0f64
                        var l = 1usize
                        while l <= nn {
                            if ncluv[l - 1usize] == kq {
                                nbb += 1usize
                                if l != nj { db += dss[fanny_mi(nn, l - 1usize, nj - 1usize)] }
                            }
                            l += 1usize
                        }
                        db = db / f64(nbb)
                        if dysb > db {
                            dysb = db
                            negbr[jj] = kq
                        }
                    }
                    kq += 1usize
                }
                if ntt > 1usize {
                    var dysa = 0.0f64
                    var l = 0usize
                    while l < ntt {
                        let nl = nelem[l]
                        if nj != nl { dysa += dss[fanny_mi(nn, nj - 1usize, nl - 1usize)] }
                        l += 1usize
                    }
                    dysa = dysa / f64(ntt - 1usize)
                    if dysa > 0.0f64 {
                        if dysb > 0.0f64 {
                            if dysb > dysa {
                                syl[jj] = 1.0f64 - dysa / dysb
                            } else {
                                if dysb < dysa {
                                    syl[jj] = dysb / dysa - 1.0f64
                                } else {
                                    syl[jj] = 0.0f64
                                }
                            }
                            if syl[jj] < 0.0f64 - 1.0f64 {
                                syl[jj] = 0.0f64 - 1.0f64
                            } else {
                                if syl[jj] > 1.0f64 { syl[jj] = 1.0f64 }
                            }
                        } else {
                            syl[jj] = 0.0f64 - 1.0f64
                        }
                    } else {
                        if dysb > 0.0f64 {
                            syl[jj] = 1.0f64
                        } else {
                            syl[jj] = 0.0f64
                        }
                    }
                } else {
                    syl[jj] = 0.0f64
                }
                jj += 1usize
            }
            avsil[kc - 1usize] = 0.0f64
            jj = 0usize
            while jj < ntt {
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
                nsend[jj] = lang
                srank[jj] = symax
                avsil[kc - 1usize] += srank[jj]
                syl[lang] = 0.0f64 - 3.0f64
                jj += 1usize
            }
            ttsil += avsil[kc - 1usize]
            avsil[kc - 1usize] = avsil[kc - 1usize] / f64(ntt)
            if ntt < 2usize {
                silinf[nsylr] = f64(kc)
                silinf[nsylr + nn] = f64(negbr[0usize])
                silinf[nsylr + 2usize * nn] = 0.0f64
                silinf[nsylr + 3usize * nn] = f64(nelem[0usize])
                nsylr += 1usize
            } else {
                jj = 0usize
                while jj < ntt {
                    let nj = nsend[jj]
                    silinf[nsylr] = f64(kc)
                    silinf[nsylr + nn] = f64(negbr[nj])
                    silinf[nsylr + 2usize * nn] = srank[jj]
                    silinf[nsylr + 3usize * nn] = f64(nelem[nj])
                    nsylr += 1usize
                    jj += 1usize
                }
            }
            kc += 1usize
        }
        ttsil = ttsil / f64(nn)
    }
    ret (FannyOut { p: p, clu: ncluv, ktrue: ktrue, cryt: cryt, pc: pc, npc: npc, nit: nit, avsil: avsil, ttsil: ttsil, silinf: silinf, dosyl: dosyl }, ok)
}

// fanny()'s coeff: Dunn's partition coefficient and its normalised form; for memb.exp 2 the iteration's own, otherwise the
// coefficient of the squared final memberships
fn fanny_coef(o: FannyOut, nn: usize, k: usize, r: f64) -> (f64, f64) {
    if r == 2.0f64 { ret (o.pc, o.npc) }
    var s = 0.0f64
    var i = 0usize
    while i < nn * k {
        s += o.p[i] * o.p[i]
        i += 1usize
    }
    let cf = s / f64(nn)
    ret (cf, (f64(k) * cf - 1.0f64) / (f64(k) - 1.0f64))
}
