// R mvtnorm's Miwa algorithm (`miwa.c`, Miwa, Hayter and Kuriki, with Mi and Hothorn's interface): normal orthant and box
// probabilities by a sum over orthoschemes, each a chain of cubic-spline integrals on a grid. `pmvnorm_miwa` is the whole of
// `pmvnorm(..., algorithm = Miwa(steps))` on a correlation matrix: it reduces a pair of infinite limits, turns an upper-only
// coordinate into a lower-only one by flipping its sign, answers a one-sided box by one orthant and a two-sided box by
// the inclusion-exclusion over at most eight lowered limits (R's `R_miwa` stops at eight, so does this). Not here: the
// `checkCorr` singularity test is a Cholesky pivot test (`Invalid` for a matrix that is not numerically positive definite,
// where R's `solve` stops on a reciprocal condition number under 2.2e-16). The limits of a box shifted by a mean are the caller's to shift.

use e.algo.stat.mvt as mvt
use e.math
use e.math.dist as dist
use e.mem

type Work = struct {
    n: usize,
    m: usize,
    z: []f64,
    w: []f64,
    p: []f64,
    d: []f64,
    w2: []f64,
    w3: []f64,
    q: []f64,
    id: []usize,
    zz: []f64,
    nd: []f64,
    np: []f64,
    b: []f64,
    fgrd: []f64,
    f: []f64,
    df: []f64,
    c: []f64,
    dd: []f64,
    r: []f64,
    h: []f64,
}

fn cd(x: f64) -> f64 { ret dist.pnorm(x, 0.0f64, 1.0f64, true, false) }
fn dn(x: f64) -> f64 { ret dist.dnorm(x, 0.0f64, 1.0f64, false) }

fn nrml_lq(p: f64) -> f64 {
    let y = 0.0f64 - math.log[f64](4.0f64 * p * (1.0f64 - p))
    var u = math.sqrt[f64](y * (2.0611786f64 - 5.7262204f64 / (y + 11.640595f64)))
    if p < 0.5f64 { u = 0.0f64 - u }
    var delta = 0.0f64
    var itr = 1i64
    while itr < 51i64 {
        let f = cd(u) - p
        if math.abs[f64](delta) < 1.0e-8f64 && math.abs[f64](f) < 1.0e-8f64 { break }
        let f1 = math.exp[f64](0.0f64 - 0.5f64 * u * u) * 0.39894228040143268f64
        let f2 = 0.0f64 - u * f1
        let r = f1 * f1 - 2.0f64 * f * f2
        if r > 0.0f64 { delta = 2.0f64 * f / (0.0f64 - f1 - math.sqrt[f64](r)) } else { delta = (0.0f64 - f1) / f2 }
        u = u + delta
        itr += 1i64
    }
    ret u
}

fn gridcalc(wk: *Work, hgrd: usize) {
    let ngrd = 2usize * hgrd
    var nres = 3usize
    if hgrd >= 100usize { nres = 6usize }
    wk.z[0usize] = 0.0f64 - 8.0f64
    wk.z[hgrd] = 0.0f64
    wk.z[ngrd] = 8.0f64
    wk.p[0usize] = 0.0f64
    wk.p[hgrd] = 0.5f64
    wk.p[ngrd] = 1.0f64
    wk.d[0usize] = 0.0f64
    wk.d[hgrd] = 0.3989422804014327f64
    wk.d[ngrd] = 0.0f64
    if hgrd < 16usize {
        wk.z[0usize] = 0.0f64 - 5.0f64
        wk.z[ngrd] = 5.0f64
        nres = 0usize
    }
    let pdelta = (cd(2.5f64) - 0.5f64) / f64(hgrd - nres)
    var i = 1usize
    while i < hgrd - nres {
        wk.z[hgrd + i] = 2.0f64 * nrml_lq(0.5f64 + f64(i) * pdelta)
        wk.z[hgrd - i] = 0.0f64 - wk.z[hgrd + i]
        wk.p[hgrd + i] = cd(wk.z[hgrd + i])
        wk.p[hgrd - i] = 1.0f64 - wk.p[hgrd + i]
        wk.d[hgrd + i] = dn(wk.z[hgrd + i])
        wk.d[hgrd - i] = wk.d[hgrd + i]
        i += 1usize
    }
    i = 0usize
    while i < nres {
        wk.z[ngrd - nres + i] = 5.0f64 + f64(i) * 3.0f64 / f64(nres)
        wk.z[nres - i] = 0.0f64 - wk.z[ngrd - nres + i]
        wk.p[ngrd - nres + i] = cd(wk.z[ngrd - nres + i])
        wk.p[nres - i] = 1.0f64 - wk.p[ngrd - nres + i]
        wk.d[ngrd - nres + i] = dn(wk.z[ngrd - nres + i])
        wk.d[nres - i] = wk.d[ngrd - nres + i]
        i += 1usize
    }
    wk.w[0usize] = 0.0f64
    wk.w2[0usize] = 0.0f64
    wk.w3[0usize] = 0.0f64
    wk.q[0usize] = 0.0f64
    wk.q[1usize] = 0.0f64
    wk.q[2usize] = 0.0f64
    wk.q[3usize] = 0.0f64
    i = 1usize
    while i <= ngrd {
        wk.w[i] = wk.z[i] - wk.z[i - 1usize]
        wk.w2[i] = wk.w[i] * wk.w[i]
        wk.w3[i] = wk.w[i] * wk.w2[i]
        wk.q[i * 4usize] = wk.p[i] - wk.p[i - 1usize]
        wk.q[i * 4usize + 1usize] = 0.0f64 - wk.d[i] + wk.d[i - 1usize] - wk.z[i - 1usize] * wk.q[i * 4usize]
        wk.q[i * 4usize + 2usize] = 0.0f64 - wk.w[i] * wk.d[i] - wk.z[i - 1usize] * wk.q[i * 4usize + 1usize] + wk.q[i * 4usize]
        wk.q[i * 4usize + 3usize] = 0.0f64 - wk.w2[i] * wk.d[i] - wk.z[i - 1usize] * wk.q[i * 4usize + 2usize] + 2.0f64 * wk.q[i * 4usize + 1usize]
        i += 1usize
    }
    wk.n = ngrd
}

// coefficients of the cubic on cell j, into b[4j..4j+4]
fn b_calc(wk: *Work, j: usize) {
    let f0 = wk.f[j - 1usize]
    let f1 = wk.f[j]
    let d0 = wk.df[j - 1usize]
    let d1 = wk.df[j]
    wk.b[j * 4usize] = f0
    wk.b[j * 4usize + 1usize] = d0
    wk.b[j * 4usize + 2usize] = 3.0f64 * (0.0f64 - f0 + f1) / wk.w2[j] - (2.0f64 * d0 + d1) / wk.w[j]
    wk.b[j * 4usize + 3usize] = 2.0f64 * (f0 - f1) / wk.w3[j] + (d0 + d1) / wk.w2[j]
}

// integral of f(x) phi(x) from z[j-1] to z[j-1] + dz
fn dlt_f(wk: *Work, j: usize, np: f64, nd: f64, dz: f64) -> f64 {
    let q0 = np - wk.p[j - 1usize]
    let q1 = 0.0f64 - nd + wk.d[j - 1usize] - wk.z[j - 1usize] * q0
    let q2 = 0.0f64 - dz * nd - wk.z[j - 1usize] * q1 + q0
    let q3 = 0.0f64 - dz * dz * nd - wk.z[j - 1usize] * q2 + 2.0f64 * q1
    ret wk.b[j * 4usize] * q0 + wk.b[j * 4usize + 1usize] * q1 + wk.b[j * 4usize + 2usize] * q2 + wk.b[j * 4usize + 3usize] * q3
}

// the orthoscheme probability for the sub-diagonal `r` (m - 1) and the limits `h` (m)
fn orschm(wk: *Work, r: []const f64, h: []const f64) -> f64 {
    let m = wk.m
    let ngrd = wk.n
    let ng1 = ngrd + 1usize
    var detr1 = 1.0f64
    var i = 1usize
    while i < m {
        let detr = 1.0f64 - r[i - 1usize] * r[i - 1usize] / detr1
        wk.c[i] = h[i] / math.sqrt[f64](detr)
        wk.dd[i] = (0.0f64 - r[i - 1usize]) / math.sqrt[f64](detr1 * detr)
        detr1 = detr
        i += 1usize
    }
    i = 1usize
    while i + 1usize < m {
        var j = 0usize
        while j <= ngrd {
            let zv = wk.c[i] + wk.dd[i] * wk.z[j]
            wk.zz[i * ng1 + j] = zv
            wk.nd[i * ng1 + j] = dn(zv)
            wk.np[i * ng1 + j] = cd(zv)
            j += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i + 1usize < m {
        if wk.dd[i] > 0.0f64 {
            var j = 0usize
            var k = 0usize
            while j <= ngrd {
                while k <= ngrd && wk.zz[i * ng1 + k] <= wk.z[j] {
                    wk.id[i * ng1 + k] = j
                    k += 1usize
                }
                j += 1usize
            }
            while k <= ngrd {
                wk.id[i * ng1 + k] = ngrd + 1usize
                k += 1usize
            }
        } else {
            var j = 0usize
            var k = ngrd + 1usize
            while j <= ngrd {
                while k > 0usize && wk.zz[i * ng1 + k - 1usize] <= wk.z[j] {
                    wk.id[i * ng1 + k - 1usize] = j
                    k -= 1usize
                }
                j += 1usize
            }
            while k > 0usize {
                wk.id[i * ng1 + k - 1usize] = ngrd + 1usize
                k -= 1usize
            }
        }
        i += 1usize
    }
    var j = 0usize
    while j <= ngrd {
        let zv = wk.c[m - 1usize] + wk.dd[m - 1usize] * wk.z[j]
        wk.f[j] = cd(zv)
        wk.df[j] = wk.dd[m - 1usize] * dn(zv)
        j += 1usize
    }
    if m >= 3usize {
        i = m - 2usize
        while i > 0usize {
            wk.fgrd[0usize] = 0.0f64
            j = 1usize
            while j <= ngrd {
                b_calc(wk, j)
                wk.fgrd[j] = wk.fgrd[j - 1usize] + wk.b[j * 4usize] * wk.q[j * 4usize] + wk.b[j * 4usize + 1usize] * wk.q[j * 4usize + 1usize] + wk.b[j * 4usize + 2usize] * wk.q[j * 4usize + 2usize] + wk.b[j * 4usize + 3usize] * wk.q[j * 4usize + 3usize]
                j += 1usize
            }
            var k = 0usize
            while k <= ngrd {
                let idk = wk.id[i * ng1 + k]
                if idk < 1usize {
                    wk.f[k] = 0.0f64
                    wk.df[k] = 0.0f64
                } else if idk > ngrd {
                    wk.df[k] = 0.0f64
                    wk.f[k] = wk.fgrd[ngrd]
                } else {
                    let dz = wk.zz[i * ng1 + k] - wk.z[idk - 1usize]
                    wk.df[k] = wk.nd[i * ng1 + k] * wk.dd[i] * (wk.b[idk * 4usize] + dz * (wk.b[idk * 4usize + 1usize] + dz * (wk.b[idk * 4usize + 2usize] + dz * wk.b[idk * 4usize + 3usize])))
                    wk.f[k] = wk.fgrd[idk - 1usize] + dlt_f(wk, idk, wk.np[i * ng1 + k], wk.nd[i * ng1 + k], dz)
                }
                k += 1usize
            }
            i -= 1usize
        }
    }
    var fbase = 0.0f64
    j = 1usize
    while j <= ngrd && wk.z[j] <= h[0usize] {
        b_calc(wk, j)
        fbase = fbase + wk.b[j * 4usize] * wk.q[j * 4usize] + wk.b[j * 4usize + 1usize] * wk.q[j * 4usize + 1usize] + wk.b[j * 4usize + 2usize] * wk.q[j * 4usize + 2usize] + wk.b[j * 4usize + 3usize] * wk.q[j * 4usize + 3usize]
        j += 1usize
    }
    if j <= ngrd && wk.z[j - 1usize] < h[0usize] {
        b_calc(wk, j)
        let npv = cd(h[0usize])
        let ndv = dn(h[0usize])
        let dz = h[0usize] - wk.z[j - 1usize]
        fbase = fbase + dlt_f(wk, j, npv, ndv, dz)
    }
    ret fbase
}

// the orthant probability P(X_i < h[0][i]) by the cone expansion; r[0] holds the correlations, h[0] the limits
fn orthant(a: *mem.Arena, wk: *Work) -> f64 {
    let m = wk.m
    let mm = m * m
    let (nz, e1) = mem.alloc[usize](a, mm)
    let (sg, e2) = mem.alloc[i64](a, mm)
    let (nxt, e3) = mem.alloc[usize](a, m)
    let (dlt, e4) = mem.alloc[i64](a, m)
    let (rvec, e5) = mem.alloc[f64](a, m)
    let (hvec, e6) = mem.alloc[f64](a, m)
    let (c, e7) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret 0.0f64 / 0.0f64 }
    let reps = 1.0e-6f64
    var p = 0.0f64
    var stg = 0usize
    var live = true
    var srch = true
    dlt[0usize] = 1i64
    hvec[0usize] = wk.h[0usize]
    while live {
        if stg + 2usize == m {
            rvec[stg] = wk.r[(stg * m + stg) * m + stg + 1usize]
            hvec[stg + 1usize] = wk.h[stg * m + stg + 1usize]
            p += f64(dlt[stg]) * orschm(wk, rvec, hvec)
            srch = false
            if stg == 0usize { live = false } else { stg -= 1usize }
        } else if srch {
            var plus = false
            nz[stg * m] = 0usize
            var j = 1usize
            var i = stg + 1usize
            while i < m {
                let rv = wk.r[(stg * m + stg) * m + i]
                if rv > reps {
                    plus = true
                    nz[stg * m] += 1usize
                    nz[stg * m + j] = i
                    sg[stg * m + j] = 1i64
                    j += 1usize
                } else if rv < 0.0f64 - reps {
                    nz[stg * m] += 1usize
                    nz[stg * m + j] = i
                    sg[stg * m + j] = 0i64 - 1i64
                    j += 1usize
                }
                i += 1usize
            }
            if nz[stg * m] == 0usize {
                nxt[stg] = 0usize
            } else {
                nxt[stg] = 1usize
                if !plus {
                    j = 1usize
                    while j <= nz[stg * m] {
                        sg[stg * m + j] = 1i64
                        j += 1usize
                    }
                }
            }
            srch = false
        } else if nxt[stg] > nz[stg * m] {
            if stg == 0usize { live = false } else { stg -= 1usize }
        } else if nz[stg * m] == 0usize {
            rvec[stg] = 0.0f64
            hvec[stg + 1usize] = wk.h[stg * m + stg + 1usize]
            var i = stg + 2usize
            while i < m {
                wk.h[(stg + 1usize) * m + i] = wk.h[stg * m + i]
                i += 1usize
            }
            i = stg + 1usize
            while i + 1usize < m {
                var j = i + 1usize
                while j < m {
                    wk.r[((stg + 1usize) * m + i) * m + j] = wk.r[(stg * m + i) * m + j]
                    j += 1usize
                }
                i += 1usize
            }
            dlt[stg + 1usize] = dlt[stg]
            nxt[stg] += 1usize
            stg += 1usize
            srch = true
        } else {
            let ns = nxt[stg]
            let nzs = nz[stg * m + ns]
            let sgn = sg[stg * m + ns]
            let sgf = f64(sgn)
            let r1k = wk.r[(stg * m + stg) * m + nzs]
            rvec[stg] = sgf * r1k
            hvec[stg + 1usize] = sgf * wk.h[stg * m + nzs]
            var i = stg + 1usize
            var j = stg + 2usize
            while j < m {
                if i == nzs { i += 1usize }
                let r1ik = wk.r[(stg * m + stg) * m + i] / r1k
                var rik = 0.0f64
                if i < nzs { rik = wk.r[(stg * m + i) * m + nzs] } else { rik = wk.r[(stg * m + nzs) * m + i] }
                c[j] = math.sqrt[f64](1.0f64 - 2.0f64 * r1ik * rik + r1ik * r1ik)
                wk.h[(stg + 1usize) * m + j] = (wk.h[stg * m + i] - r1ik * wk.h[stg * m + nzs]) / c[j]
                wk.r[((stg + 1usize) * m + stg + 1usize) * m + j] = sgf / c[j] * (rik - r1ik)
                i += 1usize
                j += 1usize
            }
            i = stg + 1usize
            j = stg + 2usize
            while j + 1usize < m {
                if i == nzs { i += 1usize }
                var u = i + 1usize
                var v = j + 1usize
                while v < m {
                    if u == nzs { u += 1usize }
                    var rik = 0.0f64
                    var ruk = 0.0f64
                    if i < nzs { rik = wk.r[(stg * m + i) * m + nzs] } else { rik = wk.r[(stg * m + nzs) * m + i] }
                    if u < nzs { ruk = wk.r[(stg * m + u) * m + nzs] } else { ruk = wk.r[(stg * m + nzs) * m + u] }
                    let r0i = wk.r[(stg * m + stg) * m + i]
                    let r0u = wk.r[(stg * m + stg) * m + u]
                    wk.r[((stg + 1usize) * m + j) * m + v] = (wk.r[(stg * m + i) * m + u] - r0u / r1k * rik - r0i / r1k * ruk + r0i * r0u / r1k / r1k) / c[j] / c[v]
                    u += 1usize
                    v += 1usize
                }
                i += 1usize
                j += 1usize
            }
            dlt[stg + 1usize] = sgn * dlt[stg]
            nxt[stg] += 1usize
            stg += 1usize
            srch = true
        }
    }
    ret p
}

// orthant of the limits in `lim` (m) for the correlations `corr` (row-major m x m, upper triangle read)
fn orthant_at(a: *mem.Arena, wk: *Work, corr: []const f64, lim: []const f64) -> f64 {
    let m = wk.m
    var i = 0usize
    while i < m {
        wk.h[i] = lim[i]
        var j = i + 1usize
        while j < m {
            wk.r[i * m + j] = corr[i * m + j]
            j += 1usize
        }
        i += 1usize
    }
    let start = mem.mark(a)
    let v = orthant(a, wk)
    mem.reset(a, start)
    ret v
}

// sum over the subsets of size k of {0..m-1} (k = 0 is the empty set), lowering those limits, with the sign (-1)^k
fn subsets(a: *mem.Arena, wk: *Work, corr: []const f64, upper: []const f64, lower: []const f64, lim: []f64, pick: []usize, from: usize, depth: usize, k: usize) -> f64 {
    let m = wk.m
    if depth == k {
        var i = 0usize
        while i < m {
            lim[i] = upper[i]
            i += 1usize
        }
        i = 0usize
        while i < k {
            lim[pick[i]] = lower[pick[i]]
            i += 1usize
        }
        ret orthant_at(a, wk, corr, lim)
    }
    var s = 0.0f64
    var i = from
    while i + (k - depth) <= m {
        pick[depth] = i
        s = s + subsets(a, wk, corr, upper, lower, lim, pick, i + 1usize, depth + 1usize, k)
        i += 1usize
    }
    ret s
}

// true when the correlation matrix has a Cholesky factor whose smallest pivot is not negligible
fn positive_definite(a: *mem.Arena, n: usize, cr: []const f64) -> bool {
    let (l, e) = mem.alloc[f64](a, n * n)
    if e != ok { ret false }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j <= i {
            var s = cr[i * n + j]
            var k = 0usize
            while k < j {
                s = s - l[i * n + k] * l[j * n + k]
                k += 1usize
            }
            if i == j {
                if s <= 1.0e-14f64 { ret false }
                l[i * n + i] = math.sqrt[f64](s)
            } else {
                l[i * n + j] = s / l[j * n + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// pmvnorm(lower, upper, corr = corr, algorithm = Miwa(steps)): a limit at or beyond +-1e300 is infinite; corr is n x n row-major
fn pmvnorm_miwa(a: *mem.Arena, n0: usize, lower0: []const f64, upper0: []const f64, corr0: []const f64, steps: usize) -> (f64, err) {
    let nan = 0.0f64 / 0.0f64
    if steps > 4097usize || n0 > 20usize || n0 < 1usize { ret (nan, mem.Invalid) }
    let (keep, k1) = mem.alloc[usize](a, n0)
    if k1 != ok { ret (nan, k1) }
    var n = 0usize
    var i = 0usize
    while i < n0 {
        let lf = lower0[i] <= 0.0f64 - 1.0e300f64
        let uf = upper0[i] >= 1.0e300f64
        if !(lf && uf) {
            keep[n] = i
            n += 1usize
        }
        i += 1usize
    }
    if n == 0usize { ret (1.0f64, ok) }
    let (lo, e1) = mem.alloc[f64](a, n)
    let (up, e2) = mem.alloc[f64](a, n)
    let (cr, e3) = mem.alloc[f64](a, n * n)
    let (lim, e4) = mem.alloc[f64](a, n)
    let (pick, e5) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (nan, e1) }
    i = 0usize
    while i < n {
        lo[i] = lower0[keep[i]]
        up[i] = upper0[keep[i]]
        var j = 0usize
        while j < n {
            cr[i * n + j] = corr0[keep[i] * n0 + keep[j]]
            j += 1usize
        }
        i += 1usize
    }
    if n == 1usize { ret (mvt.mvphi(up[0usize]) - mvt.mvphi(lo[0usize]), ok) }
    if !positive_definite(a, n, cr) { ret (nan, mem.Invalid) }
    var low_only = true
    i = 0usize
    while i < n {
        let lf = lo[i] <= 0.0f64 - 1.0e300f64
        if lf {
            let t = 0.0f64 - lo[i]
            lo[i] = 0.0f64 - up[i]
            up[i] = t
            var j = 0usize
            while j < n {
                if j != i {
                    cr[i * n + j] = 0.0f64 - cr[i * n + j]
                    cr[j * n + i] = 0.0f64 - cr[j * n + i]
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        if up[i] < 1.0e300f64 { low_only = false }
        i += 1usize
    }
    var wk: Work = zero
    let hg = steps / 2usize
    let ng1 = 2usize * hg + 1usize
    wk.m = n
    let (z, g1) = mem.alloc[f64](a, ng1)
    let (w, g2) = mem.alloc[f64](a, ng1)
    let (p, g3) = mem.alloc[f64](a, ng1)
    let (d, g4) = mem.alloc[f64](a, ng1)
    let (w2, g5) = mem.alloc[f64](a, ng1)
    let (w3, g6) = mem.alloc[f64](a, ng1)
    let (q, g7) = mem.alloc[f64](a, ng1 * 4usize)
    let (id, g8) = mem.alloc[usize](a, n * ng1)
    let (zz, g9) = mem.alloc[f64](a, n * ng1)
    let (nd, g10) = mem.alloc[f64](a, n * ng1)
    let (np, g11) = mem.alloc[f64](a, n * ng1)
    let (b, g12) = mem.alloc[f64](a, ng1 * 4usize)
    let (fgrd, g13) = mem.alloc[f64](a, ng1)
    let (f, g14) = mem.alloc[f64](a, ng1)
    let (df, g15) = mem.alloc[f64](a, ng1)
    let (cc, g16) = mem.alloc[f64](a, n)
    let (dd, g17) = mem.alloc[f64](a, n)
    let (rr, g18) = mem.alloc[f64](a, n * n * n)
    let (hh, g19) = mem.alloc[f64](a, n * n)
    if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok || g7 != ok || g8 != ok || g9 != ok || g10 != ok || g11 != ok || g12 != ok || g13 != ok || g14 != ok || g15 != ok || g16 != ok || g17 != ok || g18 != ok || g19 != ok { ret (nan, g1) }
    wk.z = z
    wk.w = w
    wk.p = p
    wk.d = d
    wk.w2 = w2
    wk.w3 = w3
    wk.q = q
    wk.id = id
    wk.zz = zz
    wk.nd = nd
    wk.np = np
    wk.b = b
    wk.fgrd = fgrd
    wk.f = f
    wk.df = df
    wk.c = cc
    wk.dd = dd
    wk.r = rr
    wk.h = hh
    gridcalc(&wk, hg)
    if low_only {
        i = 0usize
        while i < n {
            lim[i] = 0.0f64 - lo[i]
            i += 1usize
        }
        ret (orthant_at(a, &wk, cr, lim), ok)
    }
    i = 0usize
    while i < n {
        if up[i] >= 1.0e300f64 { up[i] = 1000.0f64 }
        i += 1usize
    }
    var sum = 0.0f64
    var k = 0usize
    while k <= 8usize && k <= n {
        let s = subsets(a, &wk, cr, up, lo, lim, pick, 0usize, 0usize, k)
        if k % 2usize == 0usize { sum = sum + s } else { sum = sum - s }
        k += 1usize
    }
    ret (sum, ok)
}
