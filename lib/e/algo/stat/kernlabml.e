// R kernlab rvm (regression), kfa (kernel feature analysis) and ranking (manifold ranking), ported from rvm.R, kfa.R and ranking.R with their loop and
// summation orders. Matrices are row-major; kernel matrices come from kernlabmmd.cross. rvm's Cholesky is the textbook upper factor (R's dpotrf agrees to rounding).
//
// Not here: rvm cross-validation and the kernelMatrix input, ranking with edgegraph = TRUE (the minimum spanning tree) and more than one labelled
// point (kernlab recycles a length-L column sum into the m-long start vector, which fails or silently repeats), the convergence matrix.

use e.math
use e.mem

error Fail

// rvm: k is the m by m kernel matrix (the 10e-7 diagonal is added here), y the targets. Out: w (m, 0 off the relevance vectors), nz (m, 1 on them), fit (m),
// res = [nRV, var, mlike, mse]. The loop is rvm.R's, including that the variance update comes last and mlike uses the updated variance with the last err.
fn rvm(a: *mem.Arena, k0: []const f64, y: []const f64, m: usize, alpha0: f64, var0: f64, var_fix: bool, iterations: usize, tol: f64, minmaxdiff: f64, w: []f64, nz: []f64, fit: []f64, res: []f64) -> err {
    let (kk, e1) = mem.alloc[f64](a, m * m)
    let (kml, e2) = mem.alloc[f64](a, m)
    let (theta, e3) = mem.alloc[f64](a, m)
    let (idx, e4) = mem.alloc[usize](a, m)
    let (logt, e5) = mem.alloc[f64](a, m)
    let (diag, e6) = mem.alloc[f64](a, m)
    let (zeta, e7) = mem.alloc[f64](a, m)
    let (tt, e8) = mem.alloc[f64](a, m)
    let (thl, e9) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret Fail }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            kk[i * m + j] = k0[i * m + j]
            j += 1usize
        }
        kk[i * m + i] = k0[i * m + i] + 10.0e-7f64
        theta[i] = 1.0f64 / alpha0
        w[i] = 1.0f64
        i += 1usize
    }
    // Kml = crossprod(K, y)
    var c = 0usize
    while c < m {
        var s = 0.0f64
        i = 0usize
        while i < m {
            s += kk[i * m + c] * y[i]
            i += 1usize
        }
        kml[c] = s
        c += 1usize
    }
    var vr = var0
    var sumlogdiag = 0.0f64
    var sumlogtheta = 0.0f64
    var quad = 0.0f64
    var errsum = 0.0f64
    var nlast = 0usize
    var it = 0usize
    while it < iterations {
        let start = mem.mark(a)
        var n = 0usize
        i = 0usize
        while i < m {
            nz[i] = 0.0f64
            if theta[i] > tol {
                nz[i] = 1.0f64
                idx[n] = i
                n += 1usize
            } else {
                theta[i] = 0.0f64
                w[i] = 0.0f64
            }
            i += 1usize
        }
        if n == 0usize { ret Fail }
        let (ak, f1) = mem.alloc[f64](a, n * n)
        let (rr, f2) = mem.alloc[f64](a, n * n)
        let (ri, f3) = mem.alloc[f64](a, n * n)
        let (tv, f4) = mem.alloc[f64](a, n)
        if f1 != ok || f2 != ok || f3 != ok || f4 != ok { ret Fail }
        // A = crossprod(Kr) / var + diag(1 / theta)
        var p = 0usize
        while p < n {
            var q = 0usize
            while q < n {
                var s = 0.0f64
                i = 0usize
                while i < m {
                    s += kk[i * m + idx[p]] * kk[i * m + idx[q]]
                    i += 1usize
                }
                ak[p * n + q] = s / vr
                if p == q { ak[p * n + q] = s / vr + 1.0f64 / theta[idx[p]] }
                q += 1usize
            }
            p += 1usize
        }
        // upper Cholesky factor rr, A = rr' rr
        p = 0usize
        while p < n {
            var d = ak[p * n + p]
            var l = 0usize
            while l < p {
                d -= rr[l * n + p] * rr[l * n + p]
                l += 1usize
            }
            rr[p * n + p] = math.sqrt[f64](d)
            var q = p + 1usize
            while q < n {
                var s = ak[p * n + q]
                l = 0usize
                while l < p {
                    s -= rr[l * n + p] * rr[l * n + q]
                    l += 1usize
                }
                rr[p * n + q] = s / rr[p * n + p]
                q += 1usize
            }
            p += 1usize
        }
        // ri = backsolve(rr, I)
        c = 0usize
        while c < n {
            var r = 0usize
            while r < n {
                ri[r * n + c] = 0.0f64
                r += 1usize
            }
            ri[c * n + c] = 1.0f64 / rr[c * n + c]
            var rw = c
            while rw > 0usize {
                rw -= 1usize
                var s = 0.0f64
                var l = rw + 1usize
                while l <= c {
                    s += rr[rw * n + l] * ri[l * n + c]
                    l += 1usize
                }
                ri[rw * n + c] = (0.0f64 - s) / rr[rw * n + rw]
            }
            c += 1usize
        }
        // wvec[nz] = Rinv (Rinv' Kml[nz]) / var
        p = 0usize
        while p < n {
            var s = 0.0f64
            var l = 0usize
            while l <= p {
                s += ri[l * n + p] * kml[idx[l]]
                l += 1usize
            }
            tv[p] = s
            p += 1usize
        }
        p = 0usize
        while p < n {
            var s = 0.0f64
            var l = p
            while l < n {
                s += ri[p * n + l] * tv[l]
                l += 1usize
            }
            w[idx[p]] = s / vr
            diag[p] = 0.0f64
            l = p
            while l < n {
                diag[p] += ri[p * n + l] * ri[p * n + l]
                l += 1usize
            }
            thl[p] = theta[idx[p]]
            p += 1usize
        }
        // fitted values and the squared error
        errsum = 0.0f64
        i = 0usize
        while i < m {
            var s = 0.0f64
            p = 0usize
            while p < n {
                s += kk[i * m + idx[p]] * w[idx[p]]
                p += 1usize
            }
            fit[i] = s
            errsum += (y[i] - s) * (y[i] - s)
            i += 1usize
        }
        nlast = n
        sumlogdiag = 0.0f64
        sumlogtheta = 0.0f64
        quad = 0.0f64
        p = 0usize
        while p < n {
            sumlogdiag += math.log[f64](ri[p * n + p])
            sumlogtheta += math.log[f64](thl[p])
            quad += w[idx[p]] * w[idx[p]] * (1.0f64 / thl[p])
            zeta[p] = 1.0f64 - diag[p] / thl[p]
            logt[p] = 0.0f64 - math.log[f64](thl[p])
            tt[p] = theta[idx[p]]
            p += 1usize
        }
        if vr < 2.0e-9f64 { break }
        let piter = f64(iterations) * 0.4f64
        p = 0usize
        while p < n {
            var nt = 0.0f64
            if f64(it + 1usize) < piter {
                nt = w[idx[p]] * w[idx[p]] / zeta[p]
            } else {
                nt = (w[idx[p]] * w[idx[p]] / zeta[p] - diag[p]) / zeta[p]
            }
            if nt <= 0.0f64 { nt = 0.0f64 }
            theta[idx[p]] = nt
            p += 1usize
        }
        var maxdiff = 0.0f64 - 1.0f64 / 0.0f64
        p = 0usize
        while p < n {
            if theta[idx[p]] != 0.0f64 {
                var dd = logt[p] + math.log[f64](theta[idx[p]])
                if dd < 0.0f64 { dd = 0.0f64 - dd }
                if dd > maxdiff { maxdiff = dd }
            }
            p += 1usize
        }
        mem.reset(a, start)
        if maxdiff < minmaxdiff { break }
        if !var_fix {
            var zs = 0.0f64
            p = 0usize
            while p < n {
                zs += zeta[p]
                p += 1usize
            }
            vr = errsum / (f64(m) - zs)
        }
        it += 1usize
    }
    res[0usize] = f64(nlast)
    res[1usize] = vr
    res[2usize] = 0.0f64 - 0.5f64 * (0.0f64 - 2.0f64 * sumlogdiag + sumlogtheta + f64(m) * math.log[f64](vr) + errsum / vr + quad)
    var mse = 0.0f64
    i = 0usize
    while i < m {
        mse += (fit[i] - y[i]) * (fit[i] - y[i])
        i += 1usize
    }
    res[3usize] = mse / f64(m)
    ret ok
}

// kfa on ks (subset by m, kernelMatrix(kernel, x[randomindex], x)): alphafeat (features by features) and sel (the chosen rows, 0-based positions in the subset)
fn kfa(a: *mem.Arena, ks: []const f64, subset: usize, m: usize, features: usize, normalize: bool, alphafeat: []f64, sel: []usize) -> err {
    let (alpha, e1) = mem.alloc[f64](a, subset * features)
    let (az, e2) = mem.alloc[f64](a, subset)
    let (taken, e3) = mem.alloc[f64](a, subset)
    let (ksub, e4) = mem.alloc[f64](a, features * features)
    let (asub, e5) = mem.alloc[f64](a, features)
    let (vv, e6) = mem.alloc[f64](a, features)
    let (dp, e7) = mem.alloc[f64](a, subset)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret Fail }
    var r = 0usize
    while r < subset {
        az[r] = 1.0f64
        taken[r] = 0.0f64
        var c = 0usize
        while c < features {
            alpha[r * features + c] = 0.0f64
            c += 1usize
        }
        r += 1usize
    }
    var i = 0usize
    while i < features * features {
        alphafeat[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < features {
        let start = mem.mark(a)
        let (pj, f1) = mem.alloc[f64](a, m)
        if f1 != ok { ret Fail }
        var best = 0usize
        var bq = 0.0f64 - 1.0f64
        r = 0usize
        while r < subset {
            if taken[r] == 0.0f64 {
                var tot = 0.0f64
                var c = 0usize
                while c < m {
                    var s = 0.0f64
                    var k = 0usize
                    while k < i {
                        s += alpha[r * features + k] * ks[sel[k] * m + c]
                        k += 1usize
                    }
                    pj[c] = ks[r * m + c] * az[r] + s
                    if i == 0usize { pj[c] = ks[r * m + c] * az[r] }
                    tot += pj[c]
                    c += 1usize
                }
                let mean = tot / f64(m)
                var ss = 0.0f64
                c = 0usize
                while c < m {
                    ss += (pj[c] - mean) * (pj[c] - mean)
                    c += 1usize
                }
                let q = math.sqrt[f64](ss / f64(m - 1usize))
                if q > bq {
                    bq = q
                    best = r
                }
            }
            r += 1usize
        }
        mem.reset(a, start)
        var k = 0usize
        while k < i {
            alphafeat[i * features + k] = alpha[best * features + k]
            k += 1usize
        }
        alphafeat[i * features + i] = az[best]
        sel[i] = best
        taken[best] = 1.0f64
        var p = 0usize
        while p <= i {
            var q = 0usize
            while q <= i {
                ksub[p * features + q] = ks[sel[p] * m + sel[q]]
                q += 1usize
            }
            asub[p] = alphafeat[i * features + p]
            p += 1usize
        }
        p = 0usize
        while p <= i {
            var s = 0.0f64
            var q = 0usize
            while q <= i {
                s += ksub[p * features + q] * asub[q]
                q += 1usize
            }
            vv[p] = s
            p += 1usize
        }
        var rowv = 0.0f64
        var phi = 0.0f64
        var q = 0usize
        while q <= i {
            rowv = 0.0f64
            p = 0usize
            while p <= i {
                rowv += asub[p] * ksub[p * features + q]
                p += 1usize
            }
            phi += rowv * asub[q]
            q += 1usize
        }
        r = 0usize
        while r < subset {
            var s1 = 0.0f64
            var s2 = 0.0f64
            p = 0usize
            while p <= i {
                s1 += ks[r * m + sel[p]] * asub[p]
                s2 += alpha[r * features + p] * vv[p]
                p += 1usize
            }
            dp[r] = (az[r] * s1 + s2) / phi
            r += 1usize
        }
        r = 0usize
        while r < subset {
            p = 0usize
            while p <= i {
                alpha[r * features + p] = alpha[r * features + p] - dp[r] * asub[p]
                p += 1usize
            }
            r += 1usize
        }
        if normalize {
            r = 0usize
            while r < subset {
                var sa = 0.0f64
                var c = 0usize
                while c < features {
                    var v = alpha[r * features + c]
                    if v < 0.0f64 { v = 0.0f64 - v }
                    sa += v
                    c += 1usize
                }
                let sum = az[r] + sa
                az[r] = az[r] / sum
                c = 0usize
                while c < features {
                    alpha[r * features + c] = alpha[r * features + c] / sum
                    c += 1usize
                }
                r += 1usize
            }
        }
        i += 1usize
    }
    ret ok
}

// kfa projection: kt is nt by features' kernel to the chosen points; out (nt by features) = (kt alphafeat) minus its column means
fn kfa_project(kt: []const f64, alphafeat: []const f64, nt: usize, features: usize, out: []f64) {
    var t = 0usize
    while t < nt {
        var c = 0usize
        while c < features {
            var s = 0.0f64
            var k = 0usize
            while k < features {
                s += kt[t * features + k] * alphafeat[k * features + c]
                k += 1usize
            }
            out[t * features + c] = s
            c += 1usize
        }
        t += 1usize
    }
    var c = 0usize
    while c < features {
        var s = 0.0f64
        t = 0usize
        while t < nt {
            s += out[t * features + c]
            t += 1usize
        }
        t = 0usize
        while t < nt {
            out[t * features + c] = out[t * features + c] - s / f64(nt)
            t += 1usize
        }
        c += 1usize
    }
}

// ranking with one labelled point (0-based lab) on the kernel matrix kk (m by m): score (m, NaN at the label) and rank (m, NaN at the label) after iterations steps
fn ranking(a: *mem.Arena, kk: []const f64, m: usize, lab: usize, alpha: f64, iterations: usize, score: []f64, rank: []f64) -> err {
    let (kn, e1) = mem.alloc[f64](a, m * m)
    let (dd, e2) = mem.alloc[f64](a, m)
    let (y0, e3) = mem.alloc[f64](a, m)
    let (cur, e4) = mem.alloc[f64](a, m)
    let (nxt, e5) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret Fail }
    var j = 0usize
    while j < m {
        var s = 0.0f64
        var i = 0usize
        while i < m {
            if i != j { s += kk[i * m + j] }
            i += 1usize
        }
        dd[j] = 1.0f64 / math.sqrt[f64](s)
        j += 1usize
    }
    var i = 0usize
    while i < m {
        j = 0usize
        while j < m {
            kn[i * m + j] = 0.0f64
            if i != j { kn[i * m + j] = dd[i] * (kk[i * m + j] * dd[j]) }
            j += 1usize
        }
        y0[i] = kn[i * m + lab]
        cur[i] = y0[i]
        i += 1usize
    }
    var it = 1usize
    while it < iterations {
        i = 0usize
        while i < m {
            var s = 0.0f64
            j = 0usize
            while j < m {
                if j != lab { s += alpha * kn[i * m + j] * cur[j] }
                j += 1usize
            }
            nxt[i] = y0[i] + s
            i += 1usize
        }
        i = 0usize
        while i < m {
            cur[i] = nxt[i]
            i += 1usize
        }
        it += 1usize
    }
    i = 0usize
    while i < m {
        score[i] = cur[i]
        rank[i] = 0.0f64
        if i == lab {
            score[i] = 0.0f64 / 0.0f64
            rank[i] = 0.0f64 / 0.0f64
        } else {
            var less = 0usize
            var eq = 0usize
            j = 0usize
            while j < m {
                if j != lab {
                    if 0.0f64 - cur[j] < 0.0f64 - cur[i] { less += 1usize }
                    if cur[j] == cur[i] { eq += 1usize }
                }
                j += 1usize
            }
            rank[i] = f64(less) + 0.5f64 * f64(eq + 1usize)
        }
        i += 1usize
    }
    ret ok
}
