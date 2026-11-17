// R mclust: MclustDR (dimension reduction for model-based clustering and classification) from the mixture parameters.
//
// The directions depend on the mixture only through the proportions f (g), the means (p by g) and the covariances (g stacked p by p), so a Mclust fit and a MclustDA fit
// (f = pro * m_i / sum(m) over the class models) go through the same function. x is the n by p data, column-major. The SVDs are the exact LAPACK ports of the package (La.svd).

use e.math
use e.mem
use e.algo.linalg.lapack_gesdd as lapack

fn matmul(a: []const f64, b: []const f64, p: usize, c: []f64) {
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var k = 0usize
            while k < p {
                s += a[k * p + i] * b[j * p + k]
                k += 1usize
            }
            c[j * p + i] = s
            j += 1usize
        }
        i += 1usize
    }
}

fn tmatmul(a: []const f64, b: []const f64, p: usize, c: []f64) {
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var k = 0usize
            while k < p {
                s += a[i * p + k] * b[j * p + k]
                k += 1usize
            }
            c[j * p + i] = s
            j += 1usize
        }
        i += 1usize
    }
}

// out: M (p p), M.I (p p), M.II (p p), evalues (p), numdir (1), basis (p p, the first numdir columns), std.basis (p p), dir (n p, the first numdir columns)
fn mclust_dr(a: *mem.Arena, x: []const f64, n: usize, p: usize, g: usize, f: []const f64, mu_g: []const f64, sigma_g: []const f64, lambda0: f64, normalized: bool, out: []f64) -> err {
    let pq = p * p
    let (mu, e1) = mem.alloc[f64](a, p)
    let (sg, e2) = mem.alloc[f64](a, pq)
    let (sv, e3) = mem.alloc[f64](a, p)
    let (u, e4) = mem.alloc[f64](a, pq)
    let (vt, e5) = mem.alloc[f64](a, pq)
    let (isq, e6) = mem.alloc[f64](a, pq)
    let (s, e7) = mem.alloc[f64](a, pq)
    let (t1, e8) = mem.alloc[f64](a, pq)
    let (t2, e9) = mem.alloc[f64](a, pq)
    let (t3, e10) = mem.alloc[f64](a, pq)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret mem.Full }
    let nn = f64(n)
    var lambda = lambda0
    if lambda > 1.0f64 { lambda = 1.0f64 }
    if lambda < 0.0f64 { lambda = 0.0f64 }
    var j = 0usize
    while j < p {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += x[j * n + i]
            i += 1usize
        }
        mu[j] = m / nn
        j += 1usize
    }
    var b = 0usize
    while b < p {
        var c = 0usize
        while c < p {
            var t = 0.0f64
            var i = 0usize
            while i < n {
                t += (x[b * n + i] - mu[b]) * (x[c * n + i] - mu[c])
                i += 1usize
            }
            sg[c * p + b] = t / nn
            c += 1usize
        }
        b += 1usize
    }
    let se = lapack.svd_all(a, sg, p, p, sv, u, vt)
    if se != ok { ret se }
    // inverse square root of Sigma over the singular values above tol d1
    let tol = math.sqrt[f64](2.220446049250313e-16f64)
    var q = 0usize
    while q < pq {
        isq[q] = 0.0f64
        q += 1usize
    }
    var k = 0usize
    while k < p {
        if sv[k] > tol * sv[0usize] {
            b = 0usize
            while b < p {
                var c = 0usize
                while c < p {
                    isq[c * p + b] = isq[c * p + b] + vt[b * p + k] * vt[c * p + k] / math.sqrt[f64](sv[k])
                    c += 1usize
                }
                b += 1usize
            }
        }
        k += 1usize
    }
    // S = sum f_j Sigma_j
    q = 0usize
    while q < pq {
        s[q] = 0.0f64
        q += 1usize
    }
    j = 0usize
    while j < g {
        q = 0usize
        while q < pq {
            s[q] = s[q] + f[j] * sigma_g[j * pq + q]
            q += 1usize
        }
        j += 1usize
    }
    let mi = out[pq..2usize * pq]
    let mii = out[2usize * pq..3usize * pq]
    let mm = out[0usize..pq]
    q = 0usize
    while q < pq {
        mi[q] = 0.0f64
        mii[q] = 0.0f64
        q += 1usize
    }
    j = 0usize
    while j < g {
        b = 0usize
        while b < p {
            var c = 0usize
            while c < p {
                mi[c * p + b] = mi[c * p + b] + f[j] * (mu_g[j * p + b] - mu[b]) * (mu_g[j * p + c] - mu[c])
                c += 1usize
            }
            b += 1usize
        }
        j += 1usize
    }
    if lambda < 1.0f64 {
        j = 0usize
        while j < g {
            q = 0usize
            while q < pq {
                t1[q] = sigma_g[j * pq + q] - s[q]
                q += 1usize
            }
            matmul(isq, t1, p, t2)
            tmatmul(t2, t2, p, t3)
            q = 0usize
            while q < pq {
                mii[q] = mii[q] + f[j] * t3[q]
                q += 1usize
            }
            j += 1usize
        }
    }
    // M = 2 lambda crossprod(B M.I) + 2 (1 - lambda) M.II
    matmul(isq, mi, p, t1)
    tmatmul(t1, t1, p, t2)
    q = 0usize
    while q < pq {
        mm[q] = 2.0f64 * lambda * t2[q] + 2.0f64 * (1.0f64 - lambda) * mii[q]
        q += 1usize
    }
    // eigen.decomp(M, B, invsqrt = TRUE): svd of B' M B
    tmatmul(isq, mm, p, t1)
    matmul(t1, isq, p, t2)
    let se2 = lapack.svd_all(a, t2, p, p, sv, u, vt)
    if se2 != ok { ret se2 }
    // evectors = B V, V = t(vt)
    j = 0usize
    while j < p {
        b = 0usize
        while b < p {
            var t = 0.0f64
            k = 0usize
            while k < p {
                t += isq[k * p + b] * vt[k * p + j]
                k += 1usize
            }
            t3[j * p + b] = t
            b += 1usize
        }
        j += 1usize
    }
    var numdir = 0usize
    j = 0usize
    while j < p {
        var l = sv[j]
        l = (l + math.abs[f64](l)) / 2.0f64
        out[3usize * pq + j] = l
        if l > tol { numdir += 1usize }
        j += 1usize
    }
    if numdir > p { numdir = p }
    out[3usize * pq + p] = f64(numdir)
    // seq(0) is c(1, 0) in R: a zero numdir still keeps the first direction
    if numdir == 0usize { numdir = 1usize }
    let basis = out[3usize * pq + p + 1usize..3usize * pq + p + 1usize + pq]
    let stdb = out[4usize * pq + p + 1usize..4usize * pq + p + 1usize + pq]
    j = 0usize
    while j < p {
        var nb = 0.0f64
        var ns = 0.0f64
        b = 0usize
        while b < p {
            basis[j * p + b] = 0.0f64
            stdb[j * p + b] = 0.0f64
            if j < numdir {
                basis[j * p + b] = t3[j * p + b]
                stdb[j * p + b] = t3[j * p + b] * sg[b * p + b]
                nb += basis[j * p + b] * basis[j * p + b]
                ns += stdb[j * p + b] * stdb[j * p + b]
            }
            b += 1usize
        }
        if normalized && j < numdir {
            b = 0usize
            while b < p {
                basis[j * p + b] = basis[j * p + b] / math.sqrt[f64](nb)
                stdb[j * p + b] = stdb[j * p + b] / math.sqrt[f64](ns)
                b += 1usize
            }
        }
        j += 1usize
    }
    // the directions: centred data times the basis
    let dir = out[5usize * pq + p + 1usize..5usize * pq + p + 1usize + n * p]
    j = 0usize
    while j < p {
        var i = 0usize
        while i < n {
            var t = 0.0f64
            if j < numdir {
                b = 0usize
                while b < p {
                    t += (x[b * n + i] - mu[b]) * basis[j * p + b]
                    b += 1usize
                }
            }
            dir[j * n + i] = t
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}
