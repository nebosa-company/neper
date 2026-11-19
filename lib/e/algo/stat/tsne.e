// R Rtsne with theta = 0 (the exact t-SNE of van der Maaten's bhtsne): the Gaussian affinities by binary search on the precision (tolerance 1e-5, 200 steps), symmetrized and normalized to
// sum 1, then gradient descent with momentum and the gains rule from the given start Y. x is n by d row-major; y is n by dims row-major and is the start on entry and the embedding on exit.
// mode 0 plain, 1 normalize (Rtsne's default), 2 x is an n by n distance matrix (is_distance, squared as Rtsne does for theta = 0). Normalize centers each column and divides by the largest absolute value (Rtsne's normalize_input).
//
// Not here: the Barnes-Hut tree (theta > 0), the random start from R's generator and the PCA step.

use e.algo.linalg.lapack_syevr as sy
use e.math
use e.mem

fn dbl_min() -> f64 { ret 2.2250738585072014e-308f64 }
fn dbl_max() -> f64 { ret 1.7976931348623157e308f64 }

fn sgn(x: f64) -> f64 {
    if x == 0.0f64 { ret 0.0f64 }
    if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 1.0f64
}

fn zero_mean(x: []f64, n: usize, d: usize) {
    var j = 0usize
    while j < d {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += x[i * d + j]
            i += 1usize
        }
        s /= f64(n)
        i = 0usize
        while i < n {
            x[i * d + j] -= s
            i += 1usize
        }
        j += 1usize
    }
}

fn sqdist(x: []const f64, n: usize, d: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var c = 0usize
            while c < d {
                let t = x[i * d + c] - x[j * d + c]
                s += t * t
                c += 1usize
            }
            out[i * n + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

fn tsne_exact(a: *mem.Arena, x: []const f64, n: usize, d: usize, dims: usize, perplexity: f64, y: []f64, max_iter: usize, stop_lying: usize, mom_switch: usize, momentum0: f64, final_momentum: f64, eta: f64, exaggeration: f64, mode: usize) -> err {
    let (xs, e0) = mem.alloc[f64](a, n * d)
    let (dd, e1) = mem.alloc[f64](a, n * n)
    let (p, e2) = mem.alloc[f64](a, n * n)
    let (q, e3) = mem.alloc[f64](a, n * n)
    let (dy, e4) = mem.alloc[f64](a, n * dims)
    let (uy, e5) = mem.alloc[f64](a, n * dims)
    let (gains, e6) = mem.alloc[f64](a, n * dims)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e0 }
    var i = 0usize
    while i < n * d {
        xs[i] = x[i]
        i += 1usize
    }
    if mode == 1usize {
        zero_mean(xs, n, d)
        var mx = 0.0f64
        i = 0usize
        while i < n * d {
            let v = math.abs[f64](xs[i])
            if v > mx { mx = v }
            i += 1usize
        }
        i = 0usize
        while i < n * d {
            xs[i] /= mx
            i += 1usize
        }
    }
    if mode == 2usize {
        i = 0usize
        while i < n * n {
            dd[i] = xs[i] * xs[i]
            i += 1usize
        }
    } else {
        sqdist(xs, n, d, dd)
    }
    let lp = math.log[f64](perplexity)
    var r = 0usize
    while r < n {
        var found = false
        var beta = 1.0f64
        var minb = 0.0f64 - dbl_max()
        var maxb = dbl_max()
        var it = 0usize
        var sum_p = 0.0f64
        while !found && it < 200usize {
            var m = 0usize
            while m < n {
                p[r * n + m] = math.exp[f64](0.0f64 - beta * dd[r * n + m])
                m += 1usize
            }
            p[r * n + r] = dbl_min()
            sum_p = dbl_min()
            m = 0usize
            while m < n {
                sum_p += p[r * n + m]
                m += 1usize
            }
            var h = 0.0f64
            m = 0usize
            while m < n {
                h += beta * (dd[r * n + m] * p[r * n + m])
                m += 1usize
            }
            h = h / sum_p + math.log[f64](sum_p)
            let hd = h - lp
            if hd < 1.0e-5f64 && 0.0f64 - hd < 1.0e-5f64 {
                found = true
            } else {
                if hd > 0.0f64 {
                    minb = beta
                    if maxb == dbl_max() || maxb == 0.0f64 - dbl_max() { beta *= 2.0f64 } else { beta = (beta + maxb) / 2.0f64 }
                } else {
                    maxb = beta
                    if minb == 0.0f64 - dbl_max() || minb == dbl_max() { beta /= 2.0f64 } else { beta = (beta + minb) / 2.0f64 }
                }
                it += 1usize
            }
        }
        var m = 0usize
        while m < n {
            p[r * n + m] /= sum_p
            m += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < n {
        var m = r + 1usize
        while m < n {
            p[r * n + m] += p[m * n + r]
            p[m * n + r] = p[r * n + m]
            m += 1usize
        }
        r += 1usize
    }
    var sp = 0.0f64
    i = 0usize
    while i < n * n {
        sp += p[i]
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        p[i] /= sp
        p[i] *= exaggeration
        i += 1usize
    }
    i = 0usize
    while i < n * dims {
        uy[i] = 0.0f64
        gains[i] = 1.0f64
        i += 1usize
    }
    var momentum = momentum0
    var iter = 0usize
    while iter < max_iter {
        if iter == stop_lying {
            i = 0usize
            while i < n * n {
                p[i] /= exaggeration
                i += 1usize
            }
        }
        if iter == mom_switch { momentum = final_momentum }
        sqdist(y, n, dims, dd)
        var sq = 0.0f64
        r = 0usize
        while r < n {
            var m = 0usize
            while m < n {
                if r != m { q[r * n + m] = 1.0f64 / (1.0f64 + dd[r * n + m]) } else { q[r * n + m] = dbl_min() }
                sq += q[r * n + m]
                m += 1usize
            }
            r += 1usize
        }
        i = 0usize
        while i < n * dims {
            dy[i] = 0.0f64
            i += 1usize
        }
        r = 0usize
        while r < n {
            var m = 0usize
            while m < n {
                if r != m {
                    let mult = (p[r * n + m] - q[r * n + m] / sq) * q[r * n + m]
                    var c = 0usize
                    while c < dims {
                        dy[r * dims + c] += (y[r * dims + c] - y[m * dims + c]) * mult
                        c += 1usize
                    }
                }
                m += 1usize
            }
            r += 1usize
        }
        i = 0usize
        while i < n * dims {
            if sgn(dy[i]) != sgn(uy[i]) { gains[i] += 0.2f64 } else { gains[i] *= 0.8f64 }
            if gains[i] < 0.01f64 { gains[i] = 0.01f64 }
            i += 1usize
        }
        i = 0usize
        while i < n * dims {
            uy[i] = momentum * uy[i] - eta * gains[i] * dy[i]
            y[i] += uy[i]
            i += 1usize
        }
        zero_mean(y, n, dims)
        iter += 1usize
    }
    ret ok
}

// Rtsne's PCA step: prcomp(x, center = TRUE, scale. = FALSE, rank. = k)$x, the first k principal-component scores of the n by d matrix x (row-major) into out (n by k). Component signs are
// LAPACK's and do not matter to t-SNE, which only sees distances
fn pca_scores(a: *mem.Arena, x: []const f64, n: usize, d: usize, k: usize, out: []f64) -> err {
    let (xc, e0) = mem.alloc[f64](a, n * d)
    let (cv, e1) = mem.alloc[f64](a, d * d)
    let (w, e2) = mem.alloc[f64](a, d)
    let (v, e3) = mem.alloc[f64](a, d * d)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret e0 }
    var i = 0usize
    while i < n * d {
        xc[i] = x[i]
        i += 1usize
    }
    zero_mean(xc, n, d)
    var r = 0usize
    while r < d {
        var c = 0usize
        while c < d {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += xc[i * d + r] * xc[i * d + c]
                i += 1usize
            }
            cv[r * d + c] = s / f64(n - 1usize)
            c += 1usize
        }
        r += 1usize
    }
    let ee = sy.dsyevr_all(a, cv, d, w, v)
    if ee != ok { ret ee }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < k {
            let col = d - 1usize - j
            var s = 0.0f64
            var c = 0usize
            while c < d {
                s += xc[i * d + c] * v[col * d + c]
                c += 1usize
            }
            out[i * k + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}
