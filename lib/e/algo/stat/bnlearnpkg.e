// R bnlearn::score for a given DAG: the discrete log-likelihood, AIC, BIC, BDe and K2 scores, and the Gaussian log-likelihood, AIC and BIC (loglik-g, aic-g, bic-g). The graph is an adjacency matrix with adj[p * v + i] = 1 for an arc p -> i; discrete data are 0-based level codes (row-major, n by v).
//
// Not here: structure learning, the BDs and other Dirichlet scores, mixed (conditional Gaussian) networks, parameter learning, inference.

use e.algo.stat.gparot as gp
use e.math
use e.math.nmath as nm
use e.mem

// out: loglik, aic, bic, bde (imaginary sample size iss), k2
fn discrete(a: *mem.Arena, data: []const f64, n: usize, v: usize, nlev: []const usize, adj: []const f64, iss: f64, out: []f64) -> err {
    var ll = 0.0f64
    var npar = 0.0f64
    var bde = 0.0f64
    var k2 = 0.0f64
    var node = 0usize
    while node < v {
        var q = 1usize
        var p = 0usize
        while p < v {
            if adj[p * v + node] > 0.5f64 { q *= nlev[p] }
            p += 1usize
        }
        let r = nlev[node]
        let (cnt, e1) = mem.alloc[f64](a, q * r)
        if e1 != ok { ret e1 }
        var i = 0usize
        while i < q * r {
            cnt[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < n {
            var cfg = 0usize
            p = 0usize
            while p < v {
                if adj[p * v + node] > 0.5f64 { cfg = cfg * nlev[p] + usize(data[i * v + p]) }
                p += 1usize
            }
            cnt[cfg * r + usize(data[i * v + node])] += 1.0f64
            i += 1usize
        }
        var j = 0usize
        while j < q {
            var nij = 0.0f64
            var k = 0usize
            while k < r {
                nij += cnt[j * r + k]
                k += 1usize
            }
            k = 0usize
            while k < r {
                let c = cnt[j * r + k]
                if c > 0.0f64 { ll += c * math.log[f64](c / nij) }
                let aijk = iss / f64(r * q)
                bde += nm.lgammafn(aijk + c) - nm.lgammafn(aijk)
                k2 += nm.lgammafn(1.0f64 + c) - nm.lgammafn(1.0f64)
                k += 1usize
            }
            bde += nm.lgammafn(iss / f64(q)) - nm.lgammafn(iss / f64(q) + nij)
            k2 += nm.lgammafn(f64(r)) - nm.lgammafn(f64(r) + nij)
            j += 1usize
        }
        npar += f64(q * (r - 1usize))
        node += 1usize
    }
    out[0usize] = ll
    out[1usize] = ll - npar
    out[2usize] = ll - 0.5f64 * math.log[f64](f64(n)) * npar
    out[3usize] = bde
    out[4usize] = k2
    ret ok
}

// out: loglik-g, aic-g, bic-g for continuous data (n by v row-major)
fn gaussian(a: *mem.Arena, data: []const f64, n: usize, v: usize, adj: []const f64, out: []f64) -> err {
    var ll = 0.0f64
    var npar = 0.0f64
    let nf = f64(n)
    var node = 0usize
    while node < v {
        var pa = 0usize
        var p = 0usize
        while p < v {
            if adj[p * v + node] > 0.5f64 { pa += 1usize }
            p += 1usize
        }
        let q = pa + 1usize
        let (g, e1) = mem.alloc[f64](a, q * q)
        let (rv, e2) = mem.alloc[f64](a, q)
        let (idx, e3) = mem.alloc[usize](a, q)
        if e1 != ok { ret e1 }
        if e2 != ok { ret e2 }
        if e3 != ok { ret e3 }
        var c = 1usize
        p = 0usize
        while p < v {
            if adj[p * v + node] > 0.5f64 {
                idx[c] = p
                c += 1usize
            }
            p += 1usize
        }
        var i = 0usize
        while i < q * q {
            g[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < q {
            rv[i] = 0.0f64
            i += 1usize
        }
        var t = 0usize
        while t < n {
            i = 0usize
            while i < q {
                var xi = 1.0f64
                if i > 0usize { xi = data[t * v + idx[i]] }
                rv[i] += xi * data[t * v + node]
                var j = 0usize
                while j < q {
                    var xj = 1.0f64
                    if j > 0usize { xj = data[t * v + idx[j]] }
                    g[i * q + j] += xi * xj
                    j += 1usize
                }
                i += 1usize
            }
            t += 1usize
        }
        let (gi, ge) = gp.invert(a, g, q)
        if ge != ok { ret ge }
        var rss = 0.0f64
        t = 0usize
        while t < n {
            var f = 0.0f64
            i = 0usize
            while i < q {
                var b = 0.0f64
                var j = 0usize
                while j < q {
                    b += gi[i * q + j] * rv[j]
                    j += 1usize
                }
                var xi = 1.0f64
                if i > 0usize { xi = data[t * v + idx[i]] }
                f += b * xi
                i += 1usize
            }
            rss += (data[t * v + node] - f) * (data[t * v + node] - f)
            t += 1usize
        }
        let s2 = rss / (nf - f64(q))
        ll += 0.0f64 - nf / 2.0f64 * math.log[f64](2.0f64 * 3.141592653589793f64 * s2) - rss / (2.0f64 * s2)
        npar += f64(q + 1usize)
        node += 1usize
    }
    out[0usize] = ll
    out[1usize] = ll - npar
    out[2usize] = ll - 0.5f64 * math.log[f64](nf) * npar
    ret ok
}
