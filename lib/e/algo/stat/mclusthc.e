// R mclust: model-based hierarchical agglomeration (hc for VII and VVV, with the use transforms), hclass and qclass.
//
// The merge criterion of the Fortran routines hcvii and hcvvv is the classification log likelihood of a regularised model; the clusters are kept as sizes, means and scatter matrices
// instead of the QR factors the Fortran carries, and the scan order and tie rule of the Fortran (position j over 2..g, position i over 1..j - 1, the last smallest wins) are kept.

use e.math
use e.mem
use e.algo.stat.mclustpkg as mp
use e.algo.linalg.lapack_gesdd as lapack

// the sum of squares about the column means (traceW)
fn trace_w(x: []const f64, n: usize, p: usize) -> f64 {
    var t = 0.0f64
    var j = 0usize
    while j < p {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += x[j * n + i]
            i += 1usize
        }
        m = m / f64(n)
        i = 0usize
        while i < n {
            let d = x[j * n + i] - m
            t += d * d
            i += 1usize
        }
        j += 1usize
    }
    ret t
}

// scale(x, center = TRUE, scale = TRUE) into out
fn scale_cols(x: []const f64, n: usize, p: usize, out: []f64) {
    var j = 0usize
    while j < p {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += x[j * n + i]
            i += 1usize
        }
        m = m / f64(n)
        var s = 0.0f64
        i = 0usize
        while i < n {
            let d = x[j * n + i] - m
            s += d * d
            i += 1usize
        }
        let sd = math.sqrt[f64](s / f64(n - 1usize))
        i = 0usize
        while i < n {
            out[j * n + i] = (x[j * n + i] - m) / sd
            i += 1usize
        }
        j += 1usize
    }
}

// the data hc works on for each use: 0 VARS, 1 STD, 2 PCR, 3 PCS, 4 SPH, 5 SVD; z receives n by p values
fn hc_prep(a: *mem.Arena, x: []const f64, n: usize, p: usize, uz: usize, z: []f64) -> err {
    var i = 0usize
    if uz == 0usize {
        while i < n * p {
            z[i] = x[i]
            i += 1usize
        }
        ret ok
    }
    let (d, e1) = mem.alloc[f64](a, n * p)
    let (s, e2) = mem.alloc[f64](a, p)
    let (u, e3) = mem.alloc[f64](a, n * p)
    let (vt, e4) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    if uz == 1usize {
        scale_cols(x, n, p, z)
        ret ok
    }
    if uz == 3usize || uz == 4usize {
        // centre only
        var j = 0usize
        while j < p {
            var m = 0.0f64
            i = 0usize
            while i < n {
                m += x[j * n + i]
                i += 1usize
            }
            m = m / f64(n)
            i = 0usize
            while i < n {
                d[j * n + i] = x[j * n + i] - m
                i += 1usize
            }
            j += 1usize
        }
    } else {
        scale_cols(x, n, p, d)
    }
    if uz == 4usize {
        // the covariance (divisor n) of the centred data, then its SVD
        let (cv, e5) = mem.alloc[f64](a, p * p)
        if e5 != ok { ret mem.Full }
        var b = 0usize
        while b < p {
            var c = 0usize
            while c < p {
                var t = 0.0f64
                i = 0usize
                while i < n {
                    t += d[b * n + i] * d[c * n + i]
                    i += 1usize
                }
                cv[c * p + b] = t / f64(n)
                c += 1usize
            }
            b += 1usize
        }
        let (u2, e6) = mem.alloc[f64](a, p * p)
        if e6 != ok { ret mem.Full }
        let se = lapack.svd_all(a, cv, p, p, s, u2, vt)
        if se != ok { ret se }
    } else {
        let se = lapack.svd_all(a, d, n, p, s, u, vt)
        if se != ok { ret se }
    }
    // Z = data V diag(w): V is t(vt)
    var j = 0usize
    while j < p {
        var w = 1.0f64
        if uz == 5usize { w = 1.0f64 / math.sqrt[f64](s[j]) }
        if uz == 4usize { w = 1.0f64 / math.sqrt[f64](s[j]) }
        i = 0usize
        while i < n {
            var t = 0.0f64
            var b = 0usize
            while b < p {
                t += d[b * n + i] * vt[b * p + j]
                b += 1usize
            }
            z[j * n + i] = t * w
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// the term of a cluster of l points with scatter matrix s (p by p) and trace tr
fn hc_term(model: usize, l: f64, p: usize, tr: f64, s: []const f64, alpha: f64, beta: f64, lf: []f64, ln: usize) -> f64 {
    if model == 0usize { ret l * math.log[f64]((tr + alpha) / l) }
    let pp = f64(p)
    var inner = math.log[f64](beta * (tr + alpha) / l)
    if l > pp {
        if tr == 0.0f64 {
            inner = math.log[f64]((alpha * beta) / l)
        } else {
            var detlog = 0.0f64 - 1.7976931348623157e308f64
            if mp.chol_lower(s, p, lf) {
                var dl = 0.0f64
                var q = 0usize
                while q < p {
                    dl += 2.0f64 * math.log[f64](lf[q * p + q])
                    q += 1usize
                }
                detlog = dl - pp * math.log[f64](l)
            }
            if detlog == 0.0f64 - 1.7976931348623157e308f64 {
                inner = math.log[f64](beta * (tr + alpha) / l)
            } else if detlog <= 0.0f64 {
                inner = math.log[f64](math.exp[f64](detlog) + beta * (tr + alpha) / l)
            } else {
                inner = math.log[f64](1.0f64 + math.exp[f64](0.0f64 - detlog) * (beta * (tr + alpha) / l)) + detlog
            }
        }
    }
    ret l * inner
}

// hc(data, modelName = "VII" (0) or "VVV" (1), use = "VARS") on z (n by p) with the singleton partition: out holds the merges as 2 (n - 1) one-based observation numbers,
// each cluster named by its smallest member and the smaller name first. alpha_mult and beta are the alpha and beta arguments of hc.
fn hc_run(a: *mem.Arena, z: []const f64, n: usize, p: usize, model: usize, alpha_mult: f64, beta: f64, out: []usize) -> err {
    let (sz, e1) = mem.alloc[f64](a, n)
    let (mean, e2) = mem.alloc[f64](a, n * p)
    let (sc, e3) = mem.alloc[f64](a, n * p * p)
    let (tr, e4) = mem.alloc[f64](a, n)
    let (tm, e5) = mem.alloc[f64](a, n)
    let (lab, e6) = mem.alloc[usize](a, n)
    let (dd, e7) = mem.alloc[f64](a, n * n)
    let (ms, e8) = mem.alloc[f64](a, p * p)
    let (lf, e9) = mem.alloc[f64](a, p * p)
    let (best_s, e10) = mem.alloc[f64](a, p * p)
    let (dv, e11) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret mem.Full }
    // alpha * traceW(data / sqrt(n p))
    var alpha = alpha_mult * trace_w(z, n, p) / (f64(n) * f64(p))
    if alpha < 2.220446049250313e-16f64 { alpha = 2.220446049250313e-16f64 }
    var i = 0usize
    while i < n {
        sz[i] = 1.0f64
        lab[i] = i + 1usize
        tr[i] = 0.0f64
        var j = 0usize
        while j < p {
            mean[i * p + j] = z[j * n + i]
            j += 1usize
        }
        j = 0usize
        while j < p * p {
            sc[i * p * p + j] = 0.0f64
            j += 1usize
        }
        tm[i] = math.log[f64](beta * alpha)
        if model == 0usize { tm[i] = math.log[f64](alpha) }
        i += 1usize
    }
    var lg = n
    // merged cluster of positions i and j into ms (scatter), returning the trace through tro and the size through nro
    var step = 0usize
    var first = true
    while lg > 1usize {
        // distances: all pairs the first time, afterwards only those of the merged position were refreshed
        if first {
            var j = 1usize
            while j < lg {
                var q = 0usize
                while q < j {
                    dd[j * n + q] = hc_pair(model, p, sz, mean, sc, tr, tm, j, q, alpha, beta, ms, lf, dv)
                    q += 1usize
                }
                j += 1usize
            }
            first = false
        }
        var dopt = 1.7976931348623157e308f64
        var io = 0usize
        var jo = 1usize
        var j = 1usize
        while j < lg {
            var q = 0usize
            while q < j {
                if dd[j * n + q] <= dopt {
                    dopt = dd[j * n + q]
                    io = q
                    jo = j
                }
                q += 1usize
            }
            j += 1usize
        }
        // the pair of names
        var la = lab[io]
        var lb = lab[jo]
        var lo = la
        var hi = lb
        if lb < la {
            lo = lb
            hi = la
        }
        out[2usize * step] = lo
        out[2usize * step + 1usize] = hi
        // merge into position io
        let ni = sz[io]
        let nj = sz[jo]
        let nij = ni + nj
        var t = 0.0f64
        var c = 0usize
        while c < p {
            dv[c] = mean[io * p + c] - mean[jo * p + c]
            t += dv[c] * dv[c]
            c += 1usize
        }
        let w = ni * nj / nij
        var b = 0usize
        while b < p * p {
            let r = b % p
            let cc = b / p
            sc[io * p * p + b] = sc[io * p * p + b] + sc[jo * p * p + b] + w * dv[r] * dv[cc]
            b += 1usize
        }
        tr[io] = tr[io] + tr[jo] + w * t
        c = 0usize
        while c < p {
            mean[io * p + c] = (ni * mean[io * p + c] + nj * mean[jo * p + c]) / nij
            c += 1usize
        }
        sz[io] = nij
        lab[io] = lo
        tm[io] = hc_term(model, nij, p, tr[io], sc[io * p * p..io * p * p + p * p], alpha, beta, lf, p)
        // the last position takes the slot of jo
        let last = lg - 1usize
        if jo != last {
            sz[jo] = sz[last]
            lab[jo] = lab[last]
            tr[jo] = tr[last]
            tm[jo] = tm[last]
            c = 0usize
            while c < p {
                mean[jo * p + c] = mean[last * p + c]
                c += 1usize
            }
            b = 0usize
            while b < p * p {
                sc[jo * p * p + b] = sc[last * p * p + b]
                b += 1usize
            }
            // distances of the moved cluster to every position
            var q = 0usize
            while q < last {
                if q != jo && q != io {
                    var dlo = q
                    var dhi = jo
                    if q > jo {
                        dlo = jo
                        dhi = q
                    }
                    var slo = q
                    var shi = last
                    if q > last {
                        slo = last
                        shi = q
                    }
                    dd[dhi * n + dlo] = dd[shi * n + slo]
                }
                q += 1usize
            }
        }
        lg = last
        step += 1usize
        if lg > 1usize {
            // the distances of the merged cluster to the others
            var q = 0usize
            while q < lg {
                if q != io {
                    var dlo = q
                    var dhi = io
                    if q > io {
                        dlo = io
                        dhi = q
                    }
                    dd[dhi * n + dlo] = hc_pair(model, p, sz, mean, sc, tr, tm, dhi, dlo, alpha, beta, ms, lf, dv)
                }
                q += 1usize
            }
        }
    }
    ret ok
}

// the criterion of merging the clusters at positions j and q
fn hc_pair(model: usize, p: usize, sz: []const f64, mean: []const f64, sc: []const f64, tr: []const f64, tm: []const f64, j: usize, q: usize, alpha: f64, beta: f64, ms: []f64, lf: []f64, dv: []f64) -> f64 {
    let ni = sz[q]
    let nj = sz[j]
    let nij = ni + nj
    var t = 0.0f64
    var c = 0usize
    while c < p {
        dv[c] = mean[q * p + c] - mean[j * p + c]
        t += dv[c] * dv[c]
        c += 1usize
    }
    let w = ni * nj / nij
    let trc = tr[q] + tr[j] + w * t
    if model == 1usize {
        var b = 0usize
        while b < p * p {
            let r = b % p
            let cc = b / p
            ms[b] = sc[q * p * p + b] + sc[j * p * p + b] + w * dv[r] * dv[cc]
            b += 1usize
        }
    }
    let tmij = hc_term(model, nij, p, trc, ms, alpha, beta, lf, p)
    ret tmij - (tm[q] + tm[j])
}

// hclass(hc, g): the group of each observation (0-based, numbered in order of first appearance) after the first n - g merges
fn hclass(a: *mem.Arena, pairs: []const usize, n: usize, g: usize, lab: []usize) -> err {
    let (root, e2) = mem.alloc[usize](a, n)
    if e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        root[i] = i
        i += 1usize
    }
    var s = 0usize
    while s + g < n {
        let u = pairs[2usize * s] - 1usize
        let v = pairs[2usize * s + 1usize] - 1usize
        let rv = root[v]
        let ru = root[u]
        i = 0usize
        while i < n {
            if root[i] == rv { root[i] = ru }
            i += 1usize
        }
        s += 1usize
    }
    var next = 0usize
    i = 0usize
    while i < n {
        var found = false
        var j = 0usize
        while j < i && !found {
            if root[j] == root[i] {
                lab[i] = lab[j]
                found = true
            }
            j += 1usize
        }
        if !found {
            lab[i] = next
            next += 1usize
        }
        i += 1usize
    }
    ret ok
}
