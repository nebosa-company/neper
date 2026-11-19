// R MASS scaling: `sammon` (Sammon's nonlinear mapping, VR_sammon), `isomds` (Kruskal's non-metric MDS, VR_mds_*
// with optim's vmmin at abstol 1e-2) and `shepard` (the isotonic fit of a Shepard plot). Ports of MASS/src/MASS.c.
//
// Distances arrive as a full n by n column-major matrix; the starting configuration (cmdscale in R) is an argument,
// n by k column-major.

use e.algo.sort
use e.algo.stat.rbfgs as bf
use e.math
use e.mem

error BadInput

// Sammon mapping. y (n * k, column-major) is the start and the answer; NaN distances are skipped. Returns the stress.
fn sammon(a: *mem.Arena, dd: []const f64, n: usize, k: usize, y: []f64, niter: usize, magic0: f64, tol: f64) -> (f64, err) {
    let (xu, e1) = mem.alloc[f64](a, n * k)
    let (xv, e2) = mem.alloc[f64](a, k)
    let (g1, e3) = mem.alloc[f64](a, k)
    let (g2, e4) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0.0f64, BadInput) }
    var magic = magic0
    var e = 0.0f64
    var tot = 0.0f64
    var j = 1usize
    while j < n {
        var kk = 0usize
        while kk < j {
            let d = dd[kk * n + j]
            if d == d {
                tot += d
                var d1 = 0.0f64
                var m = 0usize
                while m < k {
                    let xd = y[j + m * n] - y[kk + m * n]
                    d1 += xd * xd
                    m += 1usize
                }
                let ee = d - math.sqrt[f64](d1)
                if d1 == 0.0f64 { ret (0.0f64, BadInput) }
                e += ee * ee / d
            }
            kk += 1usize
        }
        j += 1usize
    }
    e /= tot
    var epast = e
    var eprev = e
    var i = 1usize
    var stop = false
    while i <= niter && !stop {
        var redo = true
        while redo {
            redo = false
            j = 0usize
            while j < n {
                var m = 0usize
                while m < k {
                    g1[m] = 0.0f64
                    g2[m] = 0.0f64
                    m += 1usize
                }
                var kk = 0usize
                while kk < n {
                    let dt = dd[kk * n + j]
                    if j != kk && dt == dt {
                        var d1 = 0.0f64
                        m = 0usize
                        while m < k {
                            let xd = y[j + m * n] - y[kk + m * n]
                            d1 += xd * xd
                            xv[m] = xd
                            m += 1usize
                        }
                        let dpj = math.sqrt[f64](d1)
                        let dq = dt - dpj
                        let dr = dt * dpj
                        m = 0usize
                        while m < k {
                            g1[m] += xv[m] * dq / dr
                            g2[m] += (dq - xv[m] * xv[m] * (1.0f64 + dq / dpj) / dpj) / dr
                            m += 1usize
                        }
                    }
                    kk += 1usize
                }
                m = 0usize
                while m < k {
                    xu[j + m * n] = y[j + m * n] + magic * g1[m] / math.abs[f64](g2[m])
                    m += 1usize
                }
                j += 1usize
            }
            e = 0.0f64
            j = 1usize
            while j < n {
                var kk = 0usize
                while kk < j {
                    let d = dd[kk * n + j]
                    if d == d {
                        var d1 = 0.0f64
                        var m = 0usize
                        while m < k {
                            let xd = xu[j + m * n] - xu[kk + m * n]
                            d1 += xd * xd
                            m += 1usize
                        }
                        let ee = d - math.sqrt[f64](d1)
                        e += ee * ee / d
                    }
                    kk += 1usize
                }
                j += 1usize
            }
            e /= tot
            if e > eprev {
                e = eprev
                magic = magic * 0.2f64
                if magic > 0.001f64 { redo = true } else { stop = true }
            }
        }
        if !stop {
            magic *= 1.5f64
            if magic > 0.5f64 { magic = 0.5f64 }
            eprev = e
            var m = 0usize
            while m < k {
                var xx = 0.0f64
                j = 0usize
                while j < n {
                    xx += xu[j + m * n]
                    j += 1usize
                }
                xx /= f64(n)
                j = 0usize
                while j < n {
                    y[j + m * n] = xu[j + m * n] - xx
                    j += 1usize
                }
                m += 1usize
            }
            if i % 10usize == 0usize {
                if e > epast - tol { stop = true }
                epast = e
            }
            i += 1usize
        }
    }
    ret (e, ok)
}

type MdsCtx = struct { n: usize, nr: usize, nc: usize, ord: []usize, ord2: []usize, d: []f64, y: []f64, yf: []f64, ycs: []f64, mink: f64 }

fn calc_dist(c: *MdsCtx, x: []const f64) {
    let euclid = c.mink == 2.0f64
    var index = 0usize
    var r1 = 0usize
    while r1 < c.nr {
        var r2 = r1 + 1usize
        while r2 < c.nr {
            var tmp = 0.0f64
            var cc = 0usize
            while cc < c.nc {
                let t1 = x[r1 + cc * c.nr] - x[r2 + cc * c.nr]
                if euclid { tmp += t1 * t1 } else { tmp += math.pow[f64](math.abs[f64](t1), c.mink) }
                cc += 1usize
            }
            if euclid { c.d[index] = math.sqrt[f64](tmp) } else { c.d[index] = math.pow[f64](tmp, 1.0f64 / c.mink) }
            index += 1usize
            r2 += 1usize
        }
        r1 += 1usize
    }
    index = 0usize
    while index < c.n {
        c.y[index] = c.d[c.ord[index]]
        index += 1usize
    }
}

// VR_mds_fn: the isotonic regression of y (in dissimilarity order) into yf, returns the stress; with der non-empty also the gradient.
fn mds_fn(c: *MdsCtx, y: []const f64, yf: []f64, x: []const f64, der: []f64, deriv: bool) -> f64 {
    let n = c.n
    let yc = c.ycs
    yc[0usize] = 0.0f64
    var tmp = 0.0f64
    var i = 0usize
    while i < n {
        tmp += y[i]
        yc[i + 1usize] = tmp
        i += 1usize
    }
    var known = 0usize
    var ip = 0usize
    var more = true
    while more {
        var slope = 1.0e+200f64
        i = known + 1usize
        while i <= n {
            let t = (yc[i] - yc[known]) / f64(i - known)
            if t < slope {
                slope = t
                ip = i
            }
            i += 1usize
        }
        i = known
        while i < ip {
            yf[i] = (yc[ip] - yc[known]) / f64(ip - known)
            i += 1usize
        }
        known = ip
        more = known < n
    }
    var sstar = 0.0f64
    var tstar = 0.0f64
    i = 0usize
    while i < n {
        let t = y[i] - yf[i]
        sstar += t * t
        tstar += y[i] * y[i]
        i += 1usize
    }
    let ssq = 100.0f64 * math.sqrt[f64](sstar / tstar)
    if !deriv { ret ssq }
    let r = c.nr
    let euclid = c.mink == 2.0f64
    var u = 0usize
    while u < r {
        i = 0usize
        while i < c.nc {
            var t = 0.0f64
            var s = 0usize
            while s < r {
                if s != u {
                    var kk = 0usize
                    if s > u { kk = r * u - u * (u + 1usize) / 2usize + s - u } else { kk = r * s - s * (s + 1usize) / 2usize + u - s }
                    kk = c.ord2[kk - 1usize]
                    if kk < n {
                        var t1 = x[u + r * i] - x[s + r * i]
                        var sgn = 1.0f64
                        if t1 < 0.0f64 { sgn = -1.0f64 }
                        t1 = math.abs[f64](t1) / y[kk]
                        if !euclid { t1 = math.pow[f64](t1, c.mink - 1.0f64) }
                        t += ((y[kk] - yf[kk]) / sstar - y[kk] / tstar) * sgn * t1
                    }
                }
                s += 1usize
            }
            der[u + i * r] = t * ssq
            i += 1usize
        }
        u += 1usize
    }
    ret ssq
}

fn mds_f(c: *MdsCtx, x: []const f64) -> f64 {
    calc_dist(c, x)
    let none = c.d[0usize..0usize]
    ret mds_fn(c, c.y, c.yf, x, none, false)
}

fn mds_g(c: *MdsCtx, x: []const f64, der: []f64) {
    calc_dist(c, x)
    let _ = mds_fn(c, c.y, c.yf, x, der, true)
}

fn cmp_dis(ctx: *[]const f64, p: usize, q: usize) -> i32 {
    let dd = *ctx
    // order(): NaN last, ties by index (the sort is stable)
    let pn = dd[p] != dd[p]
    let qn = dd[q] != dd[q]
    if pn && qn { ret 0i32 }
    if pn { ret 1i32 }
    if qn { ret 0i32 - 1i32 }
    if dd[p] < dd[q] { ret 0i32 - 1i32 }
    if dd[p] > dd[q] { ret 1i32 }
    ret 0i32
}

// Kruskal's non-metric MDS. d is n by n column-major (positive off the diagonal, NaN or Inf allowed: they order last), y0 the n by k start;
// the fitted configuration goes to pts. Returns the stress (percent).
fn isomds(a: *mem.Arena, d: []const f64, n: usize, k: usize, y0: []const f64, p: f64, maxit: usize, tol: f64, pts: []f64) -> (f64, err) {
    let nd = n * (n - 1usize) / 2usize
    let (dis, e1) = mem.alloc[f64](a, nd)
    let (ord, e2) = mem.alloc[usize](a, nd)
    let (ord2, e3) = mem.alloc[usize](a, nd)
    let (dv, e4) = mem.alloc[f64](a, nd)
    let (yv, e5) = mem.alloc[f64](a, nd)
    let (yf, e6) = mem.alloc[f64](a, nd)
    let (yc, e7) = mem.alloc[f64](a, nd + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (0.0f64, BadInput) }
    var idx = 0usize
    var col = 0usize
    while col < n {
        var row = col + 1usize
        while row < n {
            let v = d[row + col * n]
            if v <= 0.0f64 { ret (0.0f64, BadInput) }
            dis[idx] = v
            idx += 1usize
            row += 1usize
        }
        col += 1usize
    }
    idx = 0usize
    while idx < nd {
        ord[idx] = idx
        idx += 1usize
    }
    var dref: []const f64 = dis
    let se = sort.stable_in_place_by[usize, []const f64](a, ord, &dref, cmp_dis)
    if se != ok { ret (0.0f64, se) }
    idx = 0usize
    while idx < nd {
        ord2[ord[idx]] = idx
        idx += 1usize
    }
    var c = MdsCtx { n: nd, nr: n, nc: k, ord: ord, ord2: ord2, d: dv, y: yv, yf: yf, ycs: yc, mink: p }
    idx = 0usize
    while idx < n * k {
        pts[idx] = y0[idx]
        idx += 1usize
    }
    let val = bf.vmmin_abs[MdsCtx](a, &c, mds_f, mds_g, pts, tol, maxit, 0.01f64)
    ret (val, ok)
}

// Shepard plot numerics: dis is the dissimilarity vector (lower triangle, column by column), x the n by k configuration.
// ys gets the configuration's Minkowski distances in order of dis, yf their isotonic fit; returns the stress.
fn shepard(a: *mem.Arena, dis: []const f64, x: []const f64, n: usize, k: usize, p: f64, ys: []f64, yf: []f64) -> (f64, err) {
    let nd = dis.len
    let (ord, e2) = mem.alloc[usize](a, nd)
    let (dv, e3) = mem.alloc[f64](a, nd)
    let (yc, e1) = mem.alloc[f64](a, nd + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, BadInput) }
    var i = 0usize
    while i < nd {
        ord[i] = i
        i += 1usize
    }
    var dref: []const f64 = dis
    let se = sort.stable_in_place_by[usize, []const f64](a, ord, &dref, cmp_dis)
    if se != ok { ret (0.0f64, se) }
    var c = MdsCtx { n: nd, nr: n, nc: k, ord: ord, ord2: ord, d: dv, y: ys, yf: yf, ycs: yc, mink: p }
    calc_dist(&c, x)
    ret (mds_fn(&c, ys, yf, x, yf[0usize..0usize], false), ok)
}
