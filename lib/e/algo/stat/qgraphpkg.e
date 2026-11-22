// R qgraph: centrality_auto (centrality: the connected undirected case; centrality_auto: directed, unweighted and disconnected graphs, edge betweenness, shortest paths), centralityTable's
// transforms, EBICglasso over e.algo.stat.glasso, FDRnetwork, mat2vec, cor_auto (Pearson, polychoric, polyserial) and the spring layout.
//
// Not here: the clustering coefficients (WS, Zhang, Onnela, Barrat), bridge centrality, layout constraints and groups, cor_auto's forcePD, FIML and npn.SKEPTIC,
// factor columns. cor_auto solves the analytic score for the polychoric and polyserial correlation to full precision where R's nlminb stops at its own tolerance (about 1e-6).

use e.algo.stat.armx87 as xe
use e.algo.stat.fdrtool as fd
use e.algo.stat.glasso as gl
use e.math
use e.math.dist as dst
use e.algo.stat.pbivnorm as pbv
use e.text.prettyunits as pu
use e.mem

error Singular

// out: 4 blocks of n: betweenness, closeness, strength, expected influence
fn centrality(a: *mem.Arena, w: []const f64, n: usize, out: []f64) -> err {
    let (dist, e1) = mem.alloc[f64](a, n * n)
    let (cnt, e2) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    let inf = 1.0e300f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            dist[i * n + j] = inf
            cnt[i * n + j] = 0.0f64
            if i == j {
                dist[i * n + j] = 0.0f64
                cnt[i * n + j] = 1.0f64
            } else if w[i * n + j] != 0.0f64 {
                dist[i * n + j] = 1.0f64 / math.abs[f64](w[i * n + j])
                cnt[i * n + j] = 1.0f64
            }
            j += 1usize
        }
        i += 1usize
    }
    var k = 0usize
    while k < n {
        i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                if i != k && j != k && dist[i * n + k] < inf && dist[k * n + j] < inf {
                    let via = dist[i * n + k] + dist[k * n + j]
                    let tol = 1.0e-9f64 * (1.0f64 + via)
                    if via < dist[i * n + j] - tol {
                        dist[i * n + j] = via
                        cnt[i * n + j] = cnt[i * n + k] * cnt[k * n + j]
                    } else if math.abs[f64](via - dist[i * n + j]) <= tol && i != j {
                        cnt[i * n + j] += cnt[i * n + k] * cnt[k * n + j]
                    }
                }
                j += 1usize
            }
            i += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < 4usize * n {
        out[i] = 0.0f64
        i += 1usize
    }
    var s = 0usize
    while s < n {
        var tt = s + 1usize
        while tt < n {
            var v = 0usize
            while v < n {
                if v != s && v != tt {
                    let via = dist[s * n + v] + dist[v * n + tt]
                    if math.abs[f64](via - dist[s * n + tt]) <= 1.0e-9f64 * (1.0f64 + via) { out[v] += cnt[s * n + v] * cnt[v * n + tt] / cnt[s * n + tt] }
                }
                v += 1usize
            }
            tt += 1usize
        }
        s += 1usize
    }
    i = 0usize
    while i < n {
        var sum = 0.0f64
        var st = 0.0f64
        var ei = 0.0f64
        var j = 0usize
        while j < n {
            if j != i {
                sum += dist[i * n + j]
                st += math.abs[f64](w[i * n + j])
                ei += w[i * n + j]
            }
            j += 1usize
        }
        out[n + i] = 1.0f64 / sum
        out[2usize * n + i] = st
        out[3usize * n + i] = ei
        i += 1usize
    }
    ret ok
}

// stats::cov2cor of a column-major p by p matrix: (Is_i V_ij) Is_j, a unit diagonal
fn cov2cor(v: []const f64, p: usize, out: []f64) {
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < p {
            let si = math.sqrt[f64](1.0f64 / v[i * p + i])
            let sj = math.sqrt[f64](1.0f64 / v[j * p + j])
            out[j * p + i] = si * v[j * p + i] * sj
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < p {
        out[j * p + j] = 1.0f64
        j += 1usize
    }
}

// qgraph wi2net: minus the correlation scaling of a precision matrix, a zero diagonal, the upper triangle mirrored
fn wi2net(wi: []const f64, p: usize, out: []f64) {
    cov2cor(wi, p, out)
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < j {
            out[j * p + i] = 0.0f64 - out[j * p + i]
            out[i * p + j] = out[j * p + i]
            i += 1usize
        }
        out[j * p + j] = 0.0f64
        j += 1usize
    }
}

// log(det(K)) as R computes it: LU with partial pivoting, the modulus summed in logs, exp then log; NaN for a negative determinant
fn logdet_r(a: *mem.Arena, k: []const f64, p: usize) -> f64 {
    let (w, e) = gl.zalloc(a, p * p)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < p * p {
        w[i] = k[i]
        i += 1usize
    }
    var modulus = 0.0f64
    var neg = false
    var c = 0usize
    while c < p {
        var piv = c
        i = c + 1usize
        while i < p {
            if math.abs[f64](w[c * p + i]) > math.abs[f64](w[c * p + piv]) { piv = i }
            i += 1usize
        }
        if w[c * p + piv] == 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
        if piv != c {
            neg = !neg
            var q = 0usize
            while q < p {
                let t = w[q * p + c]
                w[q * p + c] = w[q * p + piv]
                w[q * p + piv] = t
                q += 1usize
            }
        }
        if w[c * p + c] < 0.0f64 { neg = !neg }
        modulus += math.log[f64](math.abs[f64](w[c * p + c]))
        i = c + 1usize
        while i < p {
            let f = w[c * p + i] / w[c * p + c]
            var q = c + 1usize
            while q < p {
                w[q * p + i] -= f * w[q * p + c]
                q += 1usize
            }
            i += 1usize
        }
        c += 1usize
    }
    if neg { ret 0.0f64 / 0.0f64 }
    ret math.log[f64](math.exp[f64](modulus))
}

// glasso's loglik for nobs observations: -(nobs / 2) * (-log det(xx) + tr(s xx) + sum |rho * xx|), the diagonal of xx left out when it is not penalised
fn glasso_loglik(a: *mem.Arena, s: []const f64, rho: []const f64, xx: []const f64, p: usize, nobs: f64, pen_diag: bool) -> f64 {
    var tr = 0.0f64
    var pen = 0.0f64
    var i = 0usize
    while i < p {
        var t = 0.0f64
        var j = 0usize
        while j < p {
            t += s[j * p + i] * xx[i * p + j]
            if pen_diag || i != j { pen += math.abs[f64](rho[j * p + i] * xx[j * p + i]) }
            j += 1usize
        }
        tr += t
        i += 1usize
    }
    let crit = 0.0f64 - logdet_r(a, xx, p) + tr + pen
    ret 0.0f64 - nobs / 2.0f64 * crit
}

// qgraph EBIC(S, K, n, gamma, countDiagonal)
fn ebic(a: *mem.Arena, s: []const f64, k: []const f64, p: usize, n: f64, gamma: f64, count_diag: bool) -> f64 {
    var tr = 0.0f64
    var i = 0usize
    while i < p {
        var t = 0.0f64
        var j = 0usize
        while j < p {
            t += k[j * p + i] * s[i * p + j]
            j += 1usize
        }
        tr += t
        i += 1usize
    }
    let l = n / 2.0f64 * (logdet_r(a, k, p) - tr)
    var e = 0usize
    var j = 0usize
    while j < p {
        i = j
        if !count_diag { i = j + 1usize }
        while i < p {
            if k[j * p + i] != 0.0f64 { e += 1usize }
            i += 1usize
        }
        j += 1usize
    }
    let ef = f64(e)
    ret 0.0f64 - 2.0f64 * l + ef * math.log[f64](n) + 4.0f64 * ef * gamma * math.log[f64](f64(p))
}

// qgraph EBICglasso(S, n, gamma, penalize.diagonal, nlambda, lambda.min.ratio, countDiagonal, refit, threshold, penalizeMatrix).
// s is a covariance matrix (column-major p by p); pen_matrix is empty or p by p. net receives the network (p by p), ebics and
// lambda the nlambda values; returns the 0-based index of the lowest EBIC. nlambda >= 2.
fn ebic_glasso(a: *mem.Arena, s0: []const f64, p: usize, n: f64, gamma: f64, pen_diag: bool, nlambda: usize, lmr: f64, count_diag: bool, refit: bool, threshold: bool, pen_matrix: []const f64, net: []f64, ebics: []f64, lambda: []f64) -> (usize, err) {
    let pp = p * p
    let (s, e0) = gl.zalloc(a, pp)
    let (beta, e1) = gl.zalloc(a, pp * nlambda)
    let (what, e2) = gl.zalloc(a, pp * nlambda)
    if e0 != ok { ret (0usize, e0) }
    if e1 != ok { ret (0usize, e1) }
    if e2 != ok { ret (0usize, e2) }
    cov2cor(s0, p, s)
    var mx = 0.0f64
    var mn = 0.0f64
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < p {
            if i != j {
                if s[j * p + i] > mx { mx = s[j * p + i] }
                if s[j * p + i] < mn { mn = s[j * p + i] }
            }
            i += 1usize
        }
        j += 1usize
    }
    var lmax = mx
    if 0.0f64 - mn > lmax { lmax = 0.0f64 - mn }
    let lmin = lmr * lmax
    let from = xe.log_r(lmin)
    let to = xe.log_r(lmax)
    let by = (to - from) / f64(nlambda - 1usize)
    var q = 0usize
    while q < nlambda {
        var v = from + f64(q) * by
        if q == 0usize { v = from }
        if q == nlambda - 1usize { v = to }
        lambda[q] = xe.exp_r(v)
        q += 1usize
    }
    if pen_matrix.len == 0usize {
        let pe = gl.path(a, p, s, lambda[0usize..nlambda], false, pen_diag, 1.0e-4f64, 10000usize, beta, what)
        if pe != ok { ret (0usize, pe) }
    } else {
        let (rho, er) = gl.zalloc(a, pp)
        let (ww, ew) = gl.zalloc(a, pp)
        let (wwi, ei) = gl.zalloc(a, pp)
        let (info, ef) = gl.zalloc(a, 2usize)
        if er != ok { ret (0usize, er) }
        if ew != ok { ret (0usize, ew) }
        if ei != ok { ret (0usize, ei) }
        if ef != ok { ret (0usize, ef) }
        q = 0usize
        while q < nlambda {
            var t = 0usize
            while t < pp {
                rho[t] = pen_matrix[t] * lambda[q]
                ww[t] = 0.0f64
                wwi[t] = 0.0f64
                t += 1usize
            }
            let fe = gl.fit(a, p, s, rho, false, false, pen_diag, 1.0e-4f64, 10000usize, ww, wwi, info)
            if fe != ok { ret (0usize, fe) }
            t = 0usize
            while t < pp {
                beta[q * pp + t] = wwi[t]
                what[q * pp + t] = ww[t]
                t += 1usize
            }
            q += 1usize
        }
    }
    if threshold {
        let pf = f64(p)
        let th = math.log[f64](pf * (pf - 1.0f64) / 2.0f64) / math.sqrt[f64](n)
        q = 0usize
        while q < pp * nlambda {
            if math.abs[f64](beta[q]) < th { beta[q] = 0.0f64 }
            q += 1usize
        }
    }
    var opt = nlambda
    q = 0usize
    while q < nlambda {
        ebics[q] = ebic(a, s, beta[q * pp..(q + 1usize) * pp], p, n, gamma, count_diag)
        if ebics[q] == ebics[q] {
            if opt == nlambda { opt = q } else if ebics[q] < ebics[opt] { opt = q }
        }
        q += 1usize
    }
    if opt == nlambda { ret (0usize, Singular) }
    wi2net(beta[opt * pp..(opt + 1usize) * pp], p, net)
    if refit {
        var full = true
        j = 0usize
        while j < p {
            var i = 0usize
            while i < j {
                if net[j * p + i] == 0.0f64 { full = false }
                i += 1usize
            }
            j += 1usize
        }
        let (rho, er) = gl.zalloc(a, pp)
        let (ww, ew) = gl.zalloc(a, pp)
        let (wwi, ei) = gl.zalloc(a, pp)
        let (info, ef) = gl.zalloc(a, 2usize)
        if er != ok { ret (0usize, er) }
        if ew != ok { ret (0usize, ew) }
        if ei != ok { ret (0usize, ei) }
        if ef != ok { ret (0usize, ef) }
        if !full {
            j = 0usize
            while j < p {
                var i = 0usize
                while i < j {
                    if net[j * p + i] == 0.0f64 {
                        rho[j * p + i] = 10.0e9f64
                        rho[i * p + j] = 10.0e9f64
                    }
                    i += 1usize
                }
                j += 1usize
            }
        }
        let fe = gl.fit(a, p, s, rho, false, false, pen_diag, 1.0e-4f64, 10000usize, ww, wwi, info)
        if fe != ok { ret (0usize, fe) }
        wi2net(wwi, p, net)
    }
    ret (opt, ok)
}

// base::all.equal.numeric(x, y, tolerance = tol) as a truth value (countEQ = FALSE, scale NULL)
fn all_equal(x: []const f64, y: []const f64, tol: f64) -> bool {
    var cnt = 0usize
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { cnt += 1usize }
        i += 1usize
    }
    if cnt == 0usize { ret true }
    let nf = f64(cnt)
    var sa = 0.0f64
    i = 0usize
    while i < x.len {
        if x[i] != y[i] { sa += math.abs[f64](x[i]) / nf }
        i += 1usize
    }
    var scale = 1.0f64
    if sa == sa && sa < 1.0e300f64 && sa > tol { scale = sa }
    var xy = 0.0f64
    i = 0usize
    while i < x.len {
        if x[i] != y[i] { xy += math.abs[f64](x[i] - y[i]) / (nf * scale) }
        i += 1usize
    }
    if xy != xy { ret false }
    ret !(xy > tol)
}

// base::isSymmetric.matrix on a column-major n by n matrix: the quick row/column checks at 8 tol, then all.equal(x, t(x), tol)
fn is_symmetric(a: *mem.Arena, x: []const f64, n: usize, tol: f64) -> bool {
    let mk = mem.mark(a)
    let (r, e1) = gl.zalloc(a, n)
    let (c, e2) = gl.zalloc(a, n)
    if e1 != ok || e2 != ok { ret false }
    if n > 1usize {
        var pass = true
        var q = 0usize
        while q < 4usize {
            var i = 0usize
            if q == 1usize { i = 1usize }
            if q == 2usize { i = n - 2usize }
            if q == 3usize { i = n - 1usize }
            var seen = false
            var p2 = 0usize
            while p2 < q {
                var pi = 0usize
                if p2 == 1usize { pi = 1usize }
                if p2 == 2usize { pi = n - 2usize }
                if pi == i { seen = true }
                p2 += 1usize
            }
            if !seen {
                var k = 0usize
                while k < n {
                    r[k] = x[k * n + i]
                    c[k] = x[i * n + k]
                    k += 1usize
                }
                if !all_equal(r, c, 8.0f64 * tol) { pass = false }
            }
            q += 1usize
        }
        if !pass {
            mem.reset(a, mk)
            ret false
        }
    }
    let (t, e3) = gl.zalloc(a, n * n)
    if e3 != ok { ret false }
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < n {
            t[j * n + i] = x[i * n + j]
            i += 1usize
        }
        j += 1usize
    }
    let ok2 = all_equal(x, t, tol)
    mem.reset(a, mk)
    ret ok2
}

// qgraph mat2vec(x, diag, tol) of a column-major n by n matrix; returns the length written to out
fn mat2vec(a: *mem.Arena, x: []const f64, n: usize, diag: bool, tol: f64, out: []f64) -> usize {
    var k = 0usize
    if diag {
        while k < n * n {
            out[k] = x[k]
            k += 1usize
        }
        ret k
    }
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < j {
            out[k] = x[j * n + i]
            k += 1usize
            i += 1usize
        }
        j += 1usize
    }
    if !is_symmetric(a, x, n, tol) {
        j = 0usize
        while j < n {
            var i = j + 1usize
            while i < n {
                out[k] = x[j * n + i]
                k += 1usize
                i += 1usize
            }
            j += 1usize
        }
    }
    ret k
}

// igraph_cmp_epsilon with IGRAPH_SHORTEST_PATH_EPSILON
fn cmp_eps(x: f64, y: f64) -> i32 {
    if x == y { ret 0i32 }
    let diff = x - y
    let sum = math.abs[f64](x) + math.abs[f64](y)
    var rel = math.abs[f64](diff)
    if x != 0.0f64 && y != 0.0f64 && sum >= 2.2250738585072014e-308f64 { rel = rel / sum }
    if rel < 1.0e-10f64 { ret 0i32 }
    if diff < 0.0f64 { ret 0i32 - 1i32 }
    ret 1i32
}

// Brandes with weighted shortest paths and igraph's epsilon ties. len is column-major, len[j * n + i] the length of the arc i -> j (infinity for none).
// vb: node betweenness over ordered pairs; eb: column-major arc betweenness; dist: column-major dist[t * n + s] (infinity for unreachable).
fn brandes(a: *mem.Arena, len: []const f64, n: usize, cutoff: f64, vb: []f64, eb: []f64, dist: []f64) -> err {
    let mk = mem.mark(a)
    let (d, e1) = gl.zalloc(a, n)
    let (sg, e2) = gl.zalloc(a, n)
    let (dl, e3) = gl.zalloc(a, n)
    let (ord, e4) = mem.alloc[usize](a, n)
    let (done, e5) = mem.alloc[bool](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    let inf = 1.0f64 / 0.0f64
    var i = 0usize
    while i < n {
        vb[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        eb[i] = 0.0f64
        i += 1usize
    }
    var s = 0usize
    while s < n {
        i = 0usize
        while i < n {
            d[i] = inf
            sg[i] = 0.0f64
            dl[i] = 0.0f64
            done[i] = false
            i += 1usize
        }
        d[s] = 0.0f64
        sg[s] = 1.0f64
        var cnt = 0usize
        var go = true
        while go {
            var u = n
            i = 0usize
            while i < n {
                if !done[i] && d[i] < inf {
                    if u == n || d[i] < d[u] { u = i }
                }
                i += 1usize
            }
            if u == n {
                go = false
            } else {
                done[u] = true
                ord[cnt] = u
                cnt += 1usize
                var v = 0usize
                while v < n {
                    let l = len[v * n + u]
                    if l < inf && !done[v] {
                        let alt = d[u] + l
                        if alt <= cutoff {
                            if d[v] == inf {
                                d[v] = alt
                                sg[v] = sg[u]
                            } else {
                                let cc = cmp_eps(alt, d[v])
                                if cc < 0i32 {
                                    d[v] = alt
                                    sg[v] = sg[u]
                                } else if cc == 0i32 {
                                    sg[v] += sg[u]
                                }
                            }
                        }
                    }
                    v += 1usize
                }
            }
        }
        var k = cnt
        while k > 0usize {
            k -= 1usize
            let w = ord[k]
            var v = 0usize
            while v < n {
                let l = len[w * n + v]
                if l < inf && v != w && done[v] {
                    if cmp_eps(d[v] + l, d[w]) == 0i32 {
                        let c = sg[v] / sg[w] * (1.0f64 + dl[w])
                        dl[v] += c
                        eb[w * n + v] += c
                    }
                }
                v += 1usize
            }
            if w != s { vb[w] += dl[w] }
        }
        i = 0usize
        while i < n {
            dist[i * n + s] = d[i]
            i += 1usize
        }
        s += 1usize
    }
    mem.reset(a, mk)
    ret ok
}

type CentInfo = struct { directed: bool, weighted: bool, edges: usize }

// decimal string order of two positive integers
fn dec_less(x: usize, y: usize) -> bool {
    var dx = 0usize
    var t = x
    while t > 0usize {
        dx += 1usize
        t = t / 10usize
    }
    var dy = 0usize
    t = y
    while t > 0usize {
        dy += 1usize
        t = t / 10usize
    }
    let ox = dx
    let oy = dy
    var px = x
    var py = y
    while dx > dy {
        px = px / 10usize
        dx -= 1usize
    }
    while dy > dx {
        py = py / 10usize
        dy -= 1usize
    }
    if px != py { ret px < py }
    ret ox < oy
}

// qgraph centrality_auto(W, weighted, signed) on a column-major n by n weight matrix (W[j * n + i] the weight i -> j).
// out: 6 blocks of n: Betweenness (halved when undirected), Closeness (NaN for NA), out strength (Strength / Degree), in strength,
// out expected influence, in expected influence. spl: column-major shortest path lengths spl[j * n + i] (infinity when unreachable).
// ef / et / ev: the edge betweenness table in qgraph's order (decreasing value), 0-based endpoints; info.edges its length (capacity n * n).
fn centrality_auto(a: *mem.Arena, w0: []const f64, n: usize, weighted: bool, signed: bool, out: []f64, spl: []f64, ef: []usize, et: []usize, ev: []f64) -> (CentInfo, err) {
    var info = CentInfo { directed: false, weighted: false, edges: 0usize }
    let nn = n * n
    let mk = mem.mark(a)
    let (w, e0) = gl.zalloc(a, nn)
    let (len, e1) = gl.zalloc(a, nn)
    let (vb, e2) = gl.zalloc(a, n)
    let (eb, e3) = gl.zalloc(a, nn)
    let (dist, e4) = gl.zalloc(a, nn)
    if e0 != ok { ret (info, e0) }
    if e1 != ok { ret (info, e1) }
    if e2 != ok { ret (info, e2) }
    if e3 != ok { ret (info, e3) }
    if e4 != ok { ret (info, e4) }
    let inf = 1.0f64 / 0.0f64
    var i = 0usize
    while i < nn {
        var v = w0[i]
        if !weighted {
            if v > 0.0f64 { v = 1.0f64 } else if v < 0.0f64 { v = 0.0f64 - 1.0f64 }
        }
        if !signed { v = math.abs[f64](v) }
        w[i] = v
        i += 1usize
    }
    i = 0usize
    while i < n {
        w[i * n + i] = 0.0f64
        i += 1usize
    }
    info.directed = !is_symmetric(a, w, n, 1.0e-12f64)
    var wg = false
    var j = 0usize
    while j < n {
        i = 0usize
        while i < n {
            if i != j && w[j * n + i] != 0.0f64 && w[j * n + i] != 1.0f64 { wg = true }
            i += 1usize
        }
        j += 1usize
    }
    info.weighted = wg
    i = 0usize
    while i < nn {
        len[i] = inf
        if w[i] != 0.0f64 { len[i] = 1.0f64 / math.abs[f64](w[i]) }
        i += 1usize
    }
    let bf = brandes(a, len, n, 1.0e10f64, vb, eb, dist)
    if bf != ok { ret (info, bf) }
    // weak components, the largest first-found
    let (comp, e5) = mem.alloc[usize](a, n)
    if e5 != ok { ret (info, e5) }
    i = 0usize
    while i < n {
        comp[i] = n
        i += 1usize
    }
    var ncomp = 0usize
    var best = 0usize
    var bestsize = 0usize
    var s0 = 0usize
    while s0 < n {
        if comp[s0] == n {
            comp[s0] = ncomp
            var size = 1usize
            var grew = true
            while grew {
                grew = false
                var u = 0usize
                while u < n {
                    if comp[u] == ncomp {
                        var v = 0usize
                        while v < n {
                            if comp[v] == n && (w[v * n + u] != 0.0f64 || w[u * n + v] != 0.0f64) {
                                comp[v] = ncomp
                                size += 1usize
                                grew = true
                            }
                            v += 1usize
                        }
                    }
                    u += 1usize
                }
            }
            if size > bestsize {
                bestsize = size
                best = ncomp
            }
            ncomp += 1usize
        }
        s0 += 1usize
    }
    i = 0usize
    while i < n {
        var sum = 0.0f64
        var os = 0.0f64
        var is = 0.0f64
        var oe = 0.0f64
        var ie = 0.0f64
        let partial = bestsize > 1usize && bestsize < n
        j = 0usize
        while j < n {
            if j != i {
                if !partial || comp[j] == best { sum += dist[j * n + i] }
                os += math.abs[f64](w[j * n + i])
                is += math.abs[f64](w[i * n + j])
                oe += w[j * n + i]
                ie += w[i * n + j]
            }
            j += 1usize
        }
        out[n + i] = 1.0f64 / sum
        if partial && comp[i] != best { out[n + i] = 0.0f64 / 0.0f64 }
        out[2usize * n + i] = os
        out[3usize * n + i] = is
        out[4usize * n + i] = oe
        out[5usize * n + i] = ie
        var b = vb[i]
        if !info.directed { b = b / 2.0f64 }
        out[i] = b
        i += 1usize
    }
    i = 0usize
    while i < nn {
        spl[i] = dist[i]
        i += 1usize
    }
    // the edge list: row-major over the adjacency (i < j when undirected), igraph's order
    var m = 0usize
    i = 0usize
    while i < n {
        j = 0usize
        if !info.directed { j = i + 1usize }
        while j < n {
            if w[j * n + i] != 0.0f64 && i != j {
                ef[m] = i
                et[m] = j
                var v = eb[j * n + i]
                if !info.directed { v = (eb[j * n + i] + eb[i * n + j]) / 2.0f64 }
                ev[m] = v
                m += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    // merge(el, edgebet, by = 0) sorts on the row names as strings; order(decreasing = TRUE) is then stable
    let (idx, e6) = mem.alloc[usize](a, m + 1usize)
    if e6 != ok { ret (info, e6) }
    var k = 0usize
    while k < m {
        idx[k] = k
        k += 1usize
    }
    k = 1usize
    while k < m {
        let cur = idx[k]
        var p = k
        while p > 0usize && dec_less(cur + 1usize, idx[p - 1usize] + 1usize) {
            idx[p] = idx[p - 1usize]
            p -= 1usize
        }
        idx[p] = cur
        k += 1usize
    }
    k = 1usize
    while k < m {
        let cur = idx[k]
        var p = k
        while p > 0usize && ev[idx[p - 1usize]] < ev[cur] {
            idx[p] = idx[p - 1usize]
            p -= 1usize
        }
        idx[p] = cur
        k += 1usize
    }
    let (tf, e7) = mem.alloc[usize](a, m + 1usize)
    let (tt, e8) = mem.alloc[usize](a, m + 1usize)
    let (tv, e9) = gl.zalloc(a, m + 1usize)
    if e7 != ok { ret (info, e7) }
    if e8 != ok { ret (info, e8) }
    if e9 != ok { ret (info, e9) }
    k = 0usize
    while k < m {
        tf[k] = ef[idx[k]]
        tt[k] = et[idx[k]]
        tv[k] = ev[idx[k]]
        k += 1usize
    }
    k = 0usize
    while k < m {
        ef[k] = tf[k]
        et[k] = tt[k]
        ev[k] = tv[k]
        k += 1usize
    }
    info.edges = m
    mem.reset(a, mk)
    ret (info, ok)
}

// qgraph centralityTable's per-measure transform on a column-major n by m matrix of measures (NaN is NA), in place:
// standardized = scale2 (z score with the n - 1 sd, zeros when the sd is zero), relative = divide by the largest absolute value
fn centrality_table(x: []f64, n: usize, m: usize, standardized: bool, relative: bool) {
    var j = 0usize
    while j < m {
        if standardized {
            var cnt = 0usize
            var s = 0.0f64
            var i = 0usize
            while i < n {
                if x[j * n + i] == x[j * n + i] {
                    cnt += 1usize
                    s += x[j * n + i]
                }
                i += 1usize
            }
            if cnt == 0usize {
                i = 0usize
                while i < n {
                    x[j * n + i] = 0.0f64 / 0.0f64
                    i += 1usize
                }
            } else {
                let mean = s / f64(cnt)
                var r = 0.0f64
                i = 0usize
                while i < n {
                    if x[j * n + i] == x[j * n + i] { r += x[j * n + i] - mean }
                    i += 1usize
                }
                let mu = mean + r / f64(cnt)
                var ss = 0.0f64
                i = 0usize
                while i < n {
                    if x[j * n + i] == x[j * n + i] { ss += (x[j * n + i] - mu) * (x[j * n + i] - mu) }
                    i += 1usize
                }
                var sd = 0.0f64
                if cnt > 1usize { sd = math.sqrt[f64](ss / f64(cnt - 1usize)) }
                i = 0usize
                while i < n {
                    if sd != 0.0f64 {
                        x[j * n + i] = (x[j * n + i] - mu) / sd
                    } else {
                        x[j * n + i] = 0.0f64
                    }
                    i += 1usize
                }
            }
        }
        if relative {
            var mx = 0.0f64
            var i = 0usize
            while i < n {
                let v = math.abs[f64](x[j * n + i])
                if v == v && v > mx { mx = v }
                i += 1usize
            }
            if mx != 0.0f64 {
                i = 0usize
                while i < n {
                    x[j * n + i] = x[j * n + i] / mx
                    i += 1usize
                }
            }
        }
        j += 1usize
    }
}

error NotSymmetric
error NotPositiveDefinite

// qgraph FDRnetwork(net, cutoff, method): method 0 "lfdr", 1 "pval", 2 "qval". net is a column-major n by n (partial) correlation matrix
fn fdr_network(a: *mem.Arena, net: []const f64, n: usize, cutoff: f64, method: u8, out: []f64) -> err {
    if !is_symmetric(a, net, n, 100.0f64 * 2.220446049250313e-16f64) { ret NotSymmetric }
    let mk = mem.mark(a)
    let (ch, e0) = gl.zalloc(a, n * n)
    if e0 != ok { ret e0 }
    var i = 0usize
    while i < n * n {
        ch[i] = net[i]
        i += 1usize
    }
    var c = 0usize
    while c < n {
        var q = 0usize
        while q < c {
            ch[c * n + c] -= ch[q * n + c] * ch[q * n + c]
            q += 1usize
        }
        if !(ch[c * n + c] > 0.0f64) { ret NotPositiveDefinite }
        ch[c * n + c] = math.sqrt[f64](ch[c * n + c])
        var r = c + 1usize
        while r < n {
            var q2 = 0usize
            while q2 < c {
                ch[c * n + r] -= ch[q2 * n + r] * ch[q2 * n + c]
                q2 += 1usize
            }
            ch[c * n + r] = ch[c * n + r] / ch[c * n + c]
            r += 1usize
        }
        c += 1usize
    }
    let m = n * (n - 1usize) / 2usize
    let (vec, e1) = gl.zalloc(a, m)
    let (qv, e2) = gl.zalloc(a, m)
    let (lf, e3) = gl.zalloc(a, m)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var k = 0usize
    var j = 0usize
    while j < n {
        i = 0usize
        while i < j {
            vec[k] = net[j * n + i]
            k += 1usize
            i += 1usize
        }
        j += 1usize
    }
    let (res, fe) = fd.fdrtool_corr_cut(a, vec, qv, lf, 2u8, 0.75f64)
    if fe != ok { ret fe }
    i = 0usize
    while i < n * n {
        out[i] = net[i]
        i += 1usize
    }
    k = 0usize
    j = 0usize
    while j < n {
        i = 0usize
        while i < j {
            var stat = lf[k]
            if method == 1u8 { stat = fd.stat_pval(1u8, vec[k], res.sd) }
            if method == 2u8 { stat = qv[k] }
            if stat > cutoff {
                out[j * n + i] = 0.0f64
                out[i * n + j] = 0.0f64
            } else {
                out[i * n + j] = out[j * n + i]
            }
            k += 1usize
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        out[i * n + i] = 1.0f64
        i += 1usize
    }
    mem.reset(a, mk)
    ret ok
}

// qgraph's Fruchterman-Reingold (qgraph_layout_Cpp): ef / et 0-based endpoints, w the absolute edge weights, x / y the start positions
// (updated in place), maxdelta per node. Constraints are not supported.
fn fr_layout(a: *mem.Arena, n: usize, ef: []const usize, et: []const usize, w: []const f64, niter: usize, maxdelta: []const f64, area: f64, coolexp: f64, repulserad: f64, x: []f64, y: []f64, digits: usize) -> err {
    let mk = mem.mark(a)
    let (dx, e1) = gl.zalloc(a, n)
    let (dy, e2) = gl.zalloc(a, n)
    let (t, e3) = gl.zalloc(a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    let frk = math.sqrt[f64](area / f64(n))
    var it = niter + 1usize
    while it > 0usize {
        it -= 1usize
        let i = it
        var j = 0usize
        while j < n {
            dx[j] = 0.0f64
            dy[j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < n {
            t[j] = maxdelta[j] * math.pow64(f64(i) / f64(niter), coolexp)
            var k = j + 1usize
            while k < n {
                var xd = x[j] - x[k]
                var yd = y[j] - y[k]
                let ded = math.sqrt[f64](xd * xd + yd * yd)
                xd = xd / ded
                yd = yd / ded
                let rf = frk * frk * (1.0f64 / ded - ded * ded / repulserad)
                dx[j] += xd * rf
                dx[k] -= xd * rf
                dy[j] += yd * rf
                dy[k] -= yd * rf
                k += 1usize
            }
            j += 1usize
        }
        j = 0usize
        while j < ef.len {
            let k = ef[j]
            let l = et[j]
            var xd = x[k] - x[l]
            var yd = y[k] - y[l]
            let ded = math.sqrt[f64](xd * xd + yd * yd)
            if math.abs[f64](ded) > 0.000001f64 {
                xd = xd / ded
                yd = yd / ded
            }
            let af = ded * ded / frk * w[j]
            dx[k] -= xd * af
            dx[l] += xd * af
            dy[k] -= yd * af
            dy[l] += yd * af
            j += 1usize
        }
        j = 0usize
        while j < n {
            var ded = math.sqrt[f64](dx[j] * dx[j] + dy[j] * dy[j])
            if ded > t[j] {
                ded = t[j] / ded
                dx[j] = dx[j] * ded
                dy[j] = dy[j] * ded
            }
            x[j] += pu.fround(dx[j], digits)
            y[j] += pu.fround(dy[j], digits)
            j += 1usize
        }
    }
    mem.reset(a, mk)
    ret ok
}

// qgraph(W, layout = "spring", DoNotPlot = TRUE): raw receives the Fruchterman-Reingold coordinates ($layout.orig, n by 2 column-major),
// scaled the same rescaled to [-1, 1] per axis ($layout). W is column-major. niter 500, repulsion 1 and the other defaults are R's; pass
// NaN for area, cool_exp or repulse_rad to take the default (n^2, 1.5, n^(3 repulsion)).
fn spring_layout(a: *mem.Arena, w0: []const f64, n: usize, niter: usize, repulsion: f64, area0: f64, cool0: f64, rep0: f64, raw: []f64, scaled: []f64) -> err {
    let mk = mem.mark(a)
    let nn = n * n
    let (ef, e1) = mem.alloc[usize](a, nn)
    let (et, e2) = mem.alloc[usize](a, nn)
    let (ew, e3) = gl.zalloc(a, nn)
    let (md, e4) = gl.zalloc(a, n)
    let (xs, e5) = gl.zalloc(a, n)
    let (ys, e6) = gl.zalloc(a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    let sym = is_symmetric(a, w0, n, 100.0f64 * 2.220446049250313e-16f64)
    var m = 0usize
    var mx = 0.0f64
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < n {
            var inc = true
            if sym && i >= j { inc = false }
            if i == j { inc = false }
            if inc && w0[j * n + i] != 0.0f64 {
                ef[m] = i
                et[m] = j
                ew[m] = w0[j * n + i]
                if math.abs[f64](ew[m]) > mx { mx = math.abs[f64](ew[m]) }
                m += 1usize
            }
            i += 1usize
        }
        j += 1usize
    }
    var k = 0usize
    while k < m {
        let r = math.abs[f64](ew[k] / mx)
        ew[k] = pu.fround(r * r, 5usize)
        k += 1usize
    }
    let nf = f64(n)
    var area = nf * nf
    if area0 == area0 { area = area0 }
    var cool = 1.5f64
    if cool0 == cool0 { cool = cool0 }
    var rep = math.pow64(nf, 3.0f64 * repulsion)
    if rep0 == rep0 { rep = rep0 }
    k = 0usize
    while k < n {
        md[k] = nf
        var ang = 0.0f64
        if k > 0usize { ang = f64(k) * (2.0f64 * 3.141592653589793f64 / nf) }
        xs[k] = pu.fround(math.sin64(ang), 5usize)
        ys[k] = pu.fround(math.cos64(ang), 5usize)
        k += 1usize
    }
    let fe = fr_layout(a, n, ef[0usize..m], et[0usize..m], ew[0usize..m], niter, md, area, cool, rep, xs, ys, 5usize)
    if fe != ok { ret fe }
    k = 0usize
    while k < n {
        raw[k] = xs[k]
        raw[n + k] = ys[k]
        k += 1usize
    }
    var col = 0usize
    while col < 2usize {
        var lo = raw[col * n]
        var hi = lo
        var uniq = false
        k = 0usize
        while k < n {
            let v = raw[col * n + k]
            if v < lo { lo = v }
            if v > hi { hi = v }
            if v != raw[col * n] { uniq = true }
            k += 1usize
        }
        k = 0usize
        while k < n {
            if uniq {
                scaled[col * n + k] = (raw[col * n + k] - lo) / (hi - lo) * 2.0f64 - 1.0f64
            } else {
                scaled[col * n + k] = 0.0f64
            }
            k += 1usize
        }
        col += 1usize
    }
    mem.reset(a, mk)
    ret ok
}

// ---------------------------------------------------------------------------------------------------------------
// qgraph cor_auto(data, detectOrdinal, ordinalLevelMax, missing = "pairwise"): lavaan's two-step correlations, Pearson for a
// continuous pair, polychoric for an ordinal pair, polyserial for a mixed pair. lavaan's nlminb (bounded Newton with the analytic
// Hessian) is replaced by the root of the analytic gradient, to full precision; R stops at its own tolerance, so the two agree to about
// 1e-8 rather than to the last digit.

fn pn(x: f64) -> f64 { ret dst.pnorm(x, 0.0f64, 1.0f64, true, false) }

fn bvn_clip(x: f64, y: f64, rho: f64) -> f64 {
    var u = x
    var v = y
    if u > 10.0f64 { u = 10.0f64 }
    if v > 10.0f64 { v = 10.0f64 }
    if u < 0.0f64 - 10.0f64 || v < 0.0f64 - 10.0f64 { ret 0.0f64 }
    ret pbv.pbivnorm(u, v, rho)
}

// bivariate normal density at (x, y), zero at an infinite argument
fn bvn_dens(x: f64, y: f64, rho: f64) -> f64 {
    if x > 1.0e10f64 || x < 0.0f64 - 1.0e10f64 || y > 1.0e10f64 || y < 0.0f64 - 1.0e10f64 { ret 0.0f64 }
    let r2 = 1.0f64 - rho * rho
    ret math.exp[f64](0.0f64 - (x * x - 2.0f64 * rho * x * y + y * y) / (2.0f64 * r2)) / (2.0f64 * 3.141592653589793f64 * math.sqrt[f64](r2))
}

// the root of g on [lo, hi]: g(lo) > 0 > g(hi) is the interior case; otherwise the boundary the objective prefers
fn grad_root[C: type](c: *C, g: fn(*C, f64) -> f64, lo: f64, hi: f64) -> f64 {
    var x0 = lo
    var x1 = hi
    var it = 0usize
    while it < 200usize {
        let mid = 0.5f64 * (x0 + x1)
        if mid == x0 || mid == x1 { it = 200usize } else if g(c, mid) > 0.0f64 { x0 = mid } else { x1 = mid }
        it += 1usize
    }
    let r = 0.5f64 * (x0 + x1)
    if r < lo + 1.0e-12f64 { ret lo }
    if r > hi - 1.0e-12f64 { ret hi }
    ret r
}

type PcCtx = struct { fr: []const f64, th1: []const f64, th2: []const f64, nr: usize, nc: usize }

fn pc_edge(th: []const f64, k: usize, i: usize, upper: bool) -> f64 {
    let inf = 1.0e300f64
    if upper {
        if i + 1usize > k - 1usize { ret inf }
        ret th[i]
    }
    if i == 0usize { ret 0.0f64 - inf }
    ret th[i - 1usize]
}

fn pc_grad(c: *PcCtx, rho: f64) -> f64 {
    var g = 0.0f64
    var i = 0usize
    while i < c.nr {
        let a1 = pc_edge(c.th1, c.nr, i, true)
        let a0 = pc_edge(c.th1, c.nr, i, false)
        var j = 0usize
        while j < c.nc {
            let b1 = pc_edge(c.th2, c.nc, j, true)
            let b0 = pc_edge(c.th2, c.nc, j, false)
            let f = c.fr[j * c.nr + i]
            if f > 0.0f64 {
                let p = bvn_clip(a1, b1, rho) - bvn_clip(a0, b1, rho) - bvn_clip(a1, b0, rho) + bvn_clip(a0, b0, rho)
                let dp = bvn_dens(a1, b1, rho) - bvn_dens(a0, b1, rho) - bvn_dens(a1, b0, rho) + bvn_dens(a0, b0, rho)
                if !(p > 1.0e-10f64) {
                    // the cell has no mass at this rho: the observed count pulls rho back towards zero
                    if rho > 0.0f64 { ret 0.0f64 - 1.0e300f64 }
                    ret 1.0e300f64
                }
                g += f * dp / p
            }
            j += 1usize
        }
        i += 1usize
    }
    ret g
}

// lavaan lav_bvord_cor_twostep_fit for a table fr (column-major nr by nc) and thresholds th1 (nr - 1), th2 (nc - 1)
fn polychoric_table(fr: []f64, th1: []const f64, th2: []const f64, nr: usize, nc: usize) -> f64 {
    var zeros = 0usize
    var i = 0usize
    while i < nr * nc {
        if fr[i] == 0.0f64 { zeros += 1usize }
        i += 1usize
    }
    if nr == 2usize && nc == 2usize {
        if zeros == 2usize {
            if fr[0usize] > 0.0f64 { ret 1.0f64 }
            ret 0.0f64 - 1.0f64
        }
        if zeros == 1usize {
            var d = 0.5f64
            if fr[0usize] == 0.0f64 || fr[3usize] == 0.0f64 { d = 0.5f64 } else { d = 0.0f64 - 0.5f64 }
            fr[0usize] += d
            fr[3usize] += d
            fr[1usize] -= d
            fr[2usize] -= d
        }
        if fr[0usize] * fr[3usize] == fr[2usize] * fr[1usize] { ret 0.0f64 }
        if th1[0usize] == 0.0f64 && th2[0usize] == 0.0f64 {
            ret 0.0f64 - math.cos64(2.0f64 * 3.141592653589793f64 * fr[0usize] / (fr[0usize] + fr[1usize] + fr[2usize] + fr[3usize]))
        }
    }
    var c = PcCtx { fr: fr, th1: th1, th2: th2, nr: nr, nc: nc }
    ret grad_root[PcCtx](&c, pc_grad, 0.0f64 - 0.999f64, 0.999f64)
}

type RegCtx = struct { n: f64, p: f64, s: f64 }

// the score of the standardised bivariate normal in rho, times (1 - rho^2)^2 (positive): n rho (1 - rho^2) + p (1 + rho^2) - rho s
fn reg_grad(c: *RegCtx, rho: f64) -> f64 { ret c.n * rho * (1.0f64 - rho * rho) + c.p * (1.0f64 + rho * rho) - rho * c.s }

// var() of a column over its non-NA rows
fn colvar(x: []const f64, nobs: usize, j: usize) -> f64 {
    var cnt = 0usize
    var s = 0.0f64
    var i = 0usize
    while i < nobs {
        if x[j * nobs + i] == x[j * nobs + i] {
            cnt += 1usize
            s += x[j * nobs + i]
        }
        i += 1usize
    }
    let m = s / f64(cnt)
    var q = 0.0f64
    i = 0usize
    while i < nobs {
        if x[j * nobs + i] == x[j * nobs + i] { q += (x[j * nobs + i] - m) * (x[j * nobs + i] - m) }
        i += 1usize
    }
    ret q / f64(cnt - 1usize)
}

type PsCtx = struct { z: []const f64, hi: []const f64, lo: []const f64 }

fn ps_grad(c: *PsCtx, rho: f64) -> f64 {
    let r = math.sqrt[f64](1.0f64 - rho * rho)
    var g = 0.0f64
    var i = 0usize
    while i < c.z.len {
        let inf = 1.0e300f64
        var ph = 1.0f64
        var pl = 0.0f64
        var dh = 0.0f64
        var dl = 0.0f64
        if c.hi[i] < inf {
            let t = (c.hi[i] - rho * c.z[i]) / r
            ph = pn(t)
            dh = math.exp[f64](0.0f64 - 0.5f64 * t * t) / 2.5066282746310002f64 * (rho * c.hi[i] - c.z[i])
        }
        if c.lo[i] > 0.0f64 - inf {
            let t = (c.lo[i] - rho * c.z[i]) / r
            pl = pn(t)
            dl = math.exp[f64](0.0f64 - 0.5f64 * t * t) / 2.5066282746310002f64 * (rho * c.lo[i] - c.z[i])
        }
        var p = ph - pl
        if p < 2.220446049250313e-16f64 { p = 2.220446049250313e-16f64 }
        g += (dh - dl) / (r * r * r * p)
        i += 1usize
    }
    ret g
}

// cor_auto over a column-major nobs by p data matrix (NaN is NA, every column has an observation). ord_flag[j] = 1 marks a column that is an
// ordered factor; otherwise a column is ordinal when detect and its values are all whole numbers with at most level_max distinct values (NA counts as one).
fn cor_auto(a: *mem.Arena, x: []const f64, nobs: usize, p: usize, ord_flag: []const f64, detect: bool, level_max: usize, out: []f64) -> err {
    let mk = mem.mark(a)
    let (isord, e1) = mem.alloc[bool](a, p)
    let (nlev, e2) = mem.alloc[usize](a, p)
    let (code, e3) = gl.zalloc(a, nobs * p)
    let (th, e4) = gl.zalloc(a, p * 40usize)
    let (zc, e5) = gl.zalloc(a, nobs * p)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var j = 0usize
    while j < p {
        var allint = true
        var nuniq = 0usize
        var hasna = false
        var i = 0usize
        while i < nobs {
            let v = x[j * nobs + i]
            if v != v {
                hasna = true
            } else {
                if v - math.floor[f64](v) != 0.0f64 { allint = false }
                var seen = false
                var q = 0usize
                while q < i {
                    if x[j * nobs + q] == v { seen = true }
                    q += 1usize
                }
                if !seen { nuniq += 1usize }
            }
            i += 1usize
        }
        if hasna { nuniq += 1usize }
        isord[j] = ord_flag[j] != 0.0f64 || (detect && allint && nuniq <= level_max)
        j += 1usize
    }
    // ordinal columns: category codes 0.. by sorted distinct value, marginal thresholds; continuous: z scores with the ML sd
    j = 0usize
    while j < p {
        var cnt = 0usize
        var i = 0usize
        while i < nobs {
            if x[j * nobs + i] == x[j * nobs + i] { cnt += 1usize }
            i += 1usize
        }
        if isord[j] {
            var k = 0usize
            i = 0usize
            while i < nobs {
                let v = x[j * nobs + i]
                if v == v {
                    var below = 0usize
                    var q = 0usize
                    while q < nobs {
                        let u = x[j * nobs + q]
                        if u == u && u < v {
                            var first = true
                            var r = 0usize
                            while r < q {
                                if x[j * nobs + r] == u { first = false }
                                r += 1usize
                            }
                            if first { below += 1usize }
                        }
                        q += 1usize
                    }
                    code[j * nobs + i] = f64(below)
                    if below + 1usize > k { k = below + 1usize }
                } else {
                    code[j * nobs + i] = v
                }
                i += 1usize
            }
            nlev[j] = k
            if k > 40usize { ret Singular }
            var cum = 0.0f64
            var l = 0usize
            while l + 1usize < k {
                var c2 = 0usize
                i = 0usize
                while i < nobs {
                    if code[j * nobs + i] == f64(l) { c2 += 1usize }
                    i += 1usize
                }
                cum += f64(c2)
                th[j * 40usize + l] = dst.qnorm(cum / f64(cnt), 0.0f64, 1.0f64, true, false)
                l += 1usize
                // the cumulative count is rebuilt below for every level, so the loop adds one level at a time
            }
        } else {
            var m = 0.0f64
            i = 0usize
            while i < nobs {
                if x[j * nobs + i] == x[j * nobs + i] { m += x[j * nobs + i] }
                i += 1usize
            }
            m = m / f64(cnt)
            var s2 = 0.0f64
            i = 0usize
            while i < nobs {
                if x[j * nobs + i] == x[j * nobs + i] { s2 += (x[j * nobs + i] - m) * (x[j * nobs + i] - m) }
                i += 1usize
            }
            let sd = math.sqrt[f64](s2 / f64(cnt))
            i = 0usize
            while i < nobs {
                zc[j * nobs + i] = (x[j * nobs + i] - m) / sd
                i += 1usize
            }
            nlev[j] = 0usize
        }
        j += 1usize
    }
    j = 0usize
    while j < p {
        out[j * p + j] = 1.0f64
        var k = j + 1usize
        while k < p {
            var r = 0.0f64
            if !isord[j] && !isord[k] {
                var n2 = 0usize
                var mj = 0.0f64
                var mk2 = 0.0f64
                var i = 0usize
                while i < nobs {
                    if x[j * nobs + i] == x[j * nobs + i] && x[k * nobs + i] == x[k * nobs + i] {
                        n2 += 1usize
                        mj += x[j * nobs + i]
                        mk2 += x[k * nobs + i]
                    }
                    i += 1usize
                }
                mj = mj / f64(n2)
                mk2 = mk2 / f64(n2)
                // cov2cor(cov(x, use = "pairwise.complete.obs")): the covariance on the pair's rows, each variance on all of its own rows
                var sjk = 0.0f64
                i = 0usize
                while i < nobs {
                    if x[j * nobs + i] == x[j * nobs + i] && x[k * nobs + i] == x[k * nobs + i] { sjk += (x[j * nobs + i] - mj) * (x[k * nobs + i] - mk2) }
                    i += 1usize
                }
                let vj = colvar(x, nobs, j)
                let vk = colvar(x, nobs, k)
                r = sjk / f64(n2 - 1usize) / math.sqrt[f64](vj * vk)
                var anyord = false
                var q = 0usize
                while q < p {
                    if isord[q] { anyord = true }
                    q += 1usize
                }
                var anyna = false
                i = 0usize
                while i < nobs {
                    if x[j * nobs + i] != x[j * nobs + i] || x[k * nobs + i] != x[k * nobs + i] { anyna = true }
                    i += 1usize
                }
                if anyord {
                    // lavaan's two-step on a pair of continuous columns beside ordinal ones: Pearson on complete columns, else the bivariate
                    // normal ML with the margins fixed at each column's own mean and ML sd
                    var sjj = 0.0f64
                    var skk = 0.0f64
                    var zp = 0.0f64
                    var ss = 0.0f64
                    i = 0usize
                    while i < nobs {
                        if x[j * nobs + i] == x[j * nobs + i] && x[k * nobs + i] == x[k * nobs + i] {
                            zp += zc[j * nobs + i] * zc[k * nobs + i]
                            ss += zc[j * nobs + i] * zc[j * nobs + i] + zc[k * nobs + i] * zc[k * nobs + i]
                            sjj += (x[j * nobs + i] - mj) * (x[j * nobs + i] - mj)
                            skk += (x[k * nobs + i] - mk2) * (x[k * nobs + i] - mk2)
                        }
                        i += 1usize
                    }
                    r = sjk / math.sqrt[f64](sjj * skk)
                    if anyna {
                        var rc = RegCtx { n: f64(n2), p: zp, s: ss }
                        r = grad_root[RegCtx](&rc, reg_grad, 0.0f64 - 0.999f64, 0.999f64)
                    }
                }
            } else if isord[j] && isord[k] {
                let nr = nlev[j]
                let nc = nlev[k]
                let (fr, ef) = gl.zalloc(a, nr * nc)
                if ef != ok { ret ef }
                var i = 0usize
                while i < nobs {
                    let u = code[j * nobs + i]
                    let v = code[k * nobs + i]
                    if u == u && v == v { fr[usize(v) * nr + usize(u)] += 1.0f64 }
                    i += 1usize
                }
                r = polychoric_table(fr, th[j * 40usize..j * 40usize + 40usize], th[k * 40usize..k * 40usize + 40usize], nr, nc)
            } else {
                var oc = j
                var cc = k
                if isord[k] {
                    oc = k
                    cc = j
                }
                let kk = nlev[oc]
                let (zv, e6) = gl.zalloc(a, nobs)
                let (hv, e7) = gl.zalloc(a, nobs)
                let (lv, e8) = gl.zalloc(a, nobs)
                if e6 != ok || e7 != ok || e8 != ok { ret e6 }
                var m = 0usize
                var i = 0usize
                while i < nobs {
                    let u = code[oc * nobs + i]
                    if u == u && x[cc * nobs + i] == x[cc * nobs + i] {
                        zv[m] = zc[cc * nobs + i]
                        hv[m] = pc_edge(th[oc * 40usize..oc * 40usize + 40usize], kk, usize(u), true)
                        lv[m] = pc_edge(th[oc * 40usize..oc * 40usize + 40usize], kk, usize(u), false)
                        m += 1usize
                    }
                    i += 1usize
                }
                var c = PsCtx { z: zv[0usize..m], hi: hv[0usize..m], lo: lv[0usize..m] }
                r = grad_root[PsCtx](&c, ps_grad, 0.0f64 - 0.995f64, 0.995f64)
            }
            out[k * p + j] = r
            out[j * p + k] = r
            k += 1usize
        }
        j += 1usize
    }
    mem.reset(a, mk)
    ret ok
}
