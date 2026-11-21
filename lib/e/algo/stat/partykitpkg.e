// R partykit ctree: conditional inference trees with the default quadratic test statistic, asymptotic chi-square p values, Bonferroni or univariate adjustment, and the maximally selected statistic for the split point. Numeric and unordered factor predictors; a numeric response, or a factor response through its indicator columns (the last two levels of a binary factor reduce to the second level's indicator, exactly as .y2infl does).
//
// Not here: ordered factors, missing values, case weights, surrogate splits, cforest, MOB, other responses (survival, multivariate, ordered).
//
// The algorithm is libcoin's: the linear statistic T = sum x h over the node, its permutation mean and covariance (Strasser-Weber), the quadratic form with the Moore-Penrose inverse (eigenvalues below sqrt(eps) of the largest are dropped, their count is the degrees of freedom), and for the split the same statistic on the left part at every admissible cut point, the first maximum winning.

use e.algo.linalg.lapack_syevr as sy
use e.algo.rand.r as rr
use e.algo.stat.mvt as mvt
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

type Ctx = struct { x: []const f64, n: usize, p: usize, nl: []const usize, h: []const f64, q: usize, yl: usize, y: []const f64, maxst: bool, wt: []const f64, rg: *rr.Rng, lat: *const mvt.Lat, nres: usize, spl: bool }

type Ctl = struct { minsplit: usize, minbucket: usize, minprob: f64, logmin: f64, bonf: bool, maxdepth: usize, stump: bool, splittry: usize, mtry: usize, maxvar: usize, inter: bool, statcrit: bool, ord: []const bool }

// extended options of ctree_core: the criterion is the statistic itself (testtype Teststatistic), the maximum statistic (teststat = splitstat = maximum, with several degrees of freedom the p value is mvtnorm Genz-Bretz on the seeded stream of ctree_xs), the log of mincriterion when given, and which numeric-coded predictors are ordered factors (intersplit leaves them alone)
type Xo = struct { statcrit: bool, maxst: bool, setlog: bool, logmin: f64, ord: []const bool, w: []const f64, nres: usize, spl: bool, mtry: usize, maxvar: usize }

// one node per row, ids in pre-order (1-based, as partykit numbers them); vr is the split variable (1-based, 0 for a leaf)
type Out = struct { vr: []i64, brk: []f64, kid1: []i64, kid2: []i64, nobs: []f64, pval: []f64, stat: []f64, fit: []f64, lmap: []i64, prob1: []f64, maxlev: usize, count: usize, sv: []bool }

type Split = struct { found: bool, brk: f64, dir: []i64 }

// the sum of the case weights of the rows in sub
fn sumw(c: *const Ctx, sub: []const usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < sub.len {
        s += c.wt[sub[i]]
        i += 1usize
    }
    ret s
}

fn tolv() -> f64 { ret 0.000000014901161193847656f64 }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// d' MP d for the symmetric m by m matrix cov (column-major) and its rank, libcoin's C_MPinv_sym
fn quad(a: *mem.Arena, cov: []const f64, d: []const f64, m: usize) -> (f64, usize, err) {
    let tol = tolv()
    if m == 1usize {
        if cov[0] > tol { ret (d[0] * d[0] / cov[0], 1usize, ok) }
        ret (0.0f64, 0usize, ok)
    }
    let (w, e1) = mem.alloc[f64](a, m)
    let (z, e2) = mem.alloc[f64](a, m * m)
    if e1 != ok || e2 != ok { ret (0.0f64, 0usize, mem.Full) }
    let e = sy.dsyevr_all(a, cov, m, w, z)
    if e != ok { ret (0.0f64, 0usize, e) }
    let dtol = w[m - 1usize] * tol
    var stat = 0.0f64
    var rank = 0usize
    var k = 0usize
    while k < m {
        if !(w[k] < dtol) {
            var c = 0.0f64
            var i = 0usize
            while i < m {
                c += z[k * m + i] * d[i]
                i += 1usize
            }
            stat += c * c / w[k]
            rank += 1usize
        }
        k += 1usize
    }
    ret (stat, rank, ok)
}

// influence mean and covariance over the subset: ei[q], ci[q * Q + r]
fn influence(c: *const Ctx, sub: []const usize, ei: []f64, ci: []f64) {
    let m = sumw(c, sub)
    let q = c.q
    var k = 0usize
    while k < q {
        var s = 0.0f64
        var i = 0usize
        while i < sub.len {
            s += c.h[k * c.n + sub[i]] * c.wt[sub[i]]
            i += 1usize
        }
        ei[k] = s / m
        k += 1usize
    }
    k = 0usize
    while k < q {
        var r = 0usize
        while r < q {
            var s = 0.0f64
            var i = 0usize
            while i < sub.len {
                s += ((c.h[k * c.n + sub[i]] - ei[k]) * (c.h[r * c.n + sub[i]] - ei[r])) * c.wt[sub[i]]
                i += 1usize
            }
            ci[k * q + r] = s / m
            r += 1usize
        }
        k += 1usize
    }
}

// the split statistic: the quadratic form, or for teststat = maximum the largest standardised element (libcoin's C_maxabsstand_Variance)
fn split_stat(a: *mem.Arena, c: *const Ctx, cov: []const f64, d: []const f64, q: usize) -> (f64, usize, err) {
    if !c.maxst {
        let (s0, r0, e0) = quad(a, cov, d, q)
        ret (s0, r0, e0)
    }
    var m = 0.0f64
    var k = 0usize
    while k < q {
        var t = 0.0f64
        let v = cov[k * q + k]
        if v > tolv() { t = math.abs[f64](d[k] / math.sqrt[f64](v)) }
        if t > m { m = t }
        k += 1usize
    }
    ret (m, q, ok)
}

// libcoin's C_maxtype_pvalue for the two-sided maximum: log(1 - p) from mvtnorm's Genz-Bretz mvtdst over the elements with variance above tol
fn maxtype_lp(a: *mem.Arena, c: *const Ctx, cov: []const f64, mxs: f64, dim: usize) -> (f64, err) {
    let (idx, e1) = mem.alloc[usize](a, dim)
    if e1 != ok { ret (0.0f64, e1) }
    var nz = 0usize
    var u = 0usize
    while u < dim {
        if cov[u * dim + u] > tolv() {
            idx[nz] = u
            nz += 1usize
        }
        u += 1usize
    }
    let (lo, e2) = mem.alloc[f64](a, nz)
    let (up, e3) = mem.alloc[f64](a, nz)
    let (dl, e4) = mem.alloc[f64](a, nz)
    let (inf, e5) = mem.alloc[i64](a, nz)
    let (cor, e6) = mem.alloc[f64](a, nz * nz / 2usize + 1usize)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (0.0f64, mem.Full) }
    var k = 0usize
    var i = 0usize
    while i < nz {
        lo[i] = 0.0f64 - mxs
        up[i] = mxs
        dl[i] = 0.0f64
        inf[i] = 2i64
        var j = 0usize
        while j < i {
            let ii = idx[i]
            let jj = idx[j]
            cor[k] = cov[ii * dim + jj] / (math.sqrt[f64](cov[ii * dim + ii]) * math.sqrt[f64](cov[jj * dim + jj]))
            k += 1usize
            j += 1usize
        }
        i += 1usize
    }
    let (r, e7) = mvt.mvtdst(a, c.rg, c.lat, nz, 0i64, lo, up, inf, cor[0usize..nz * (nz - 1usize) / 2usize], dl, 25000i64, 0.001f64, 0.0f64)
    if e7 != ok { ret (0.0f64, e7) }
    var ans = r.value
    if r.inform == 2i64 || r.inform == 3i64 { ans = 0.0f64 }
    ret (math.log[f64](ans), ok)
}

// libcoin's C_MPinv_sym into mp (m by m): eigenvalues below sqrt(eps) of the largest are dropped
fn mpinv(a: *mem.Arena, cov: []const f64, m: usize, mp: []f64) -> err {
    var i = 0usize
    while i < m * m {
        mp[i] = 0.0f64
        i += 1usize
    }
    if m == 1usize {
        if cov[0] > tolv() { mp[0] = 1.0f64 / cov[0] }
        ret ok
    }
    let (w, e1) = mem.alloc[f64](a, m)
    let (z, e2) = mem.alloc[f64](a, m * m)
    if e1 != ok || e2 != ok { ret mem.Full }
    let e = sy.dsyevr_all(a, cov, m, w, z)
    if e != ok { ret e }
    let dtol = w[m - 1usize] * tolv()
    var k = 0usize
    while k < m {
        if !(w[k] < dtol) {
            let vi = 1.0f64 / w[k]
            var r = 0usize
            while r < m {
                var s = 0usize
                while s < m {
                    mp[r * m + s] += vi * z[k * m + r] * z[k * m + s]
                    s += 1usize
                }
                r += 1usize
            }
        }
        k += 1usize
    }
    ret ok
}

// the statistic of the linear statistic deviation d: the quadratic form d' MP d, or the largest standardised element for the maximum statistic
fn mcstat(c: *const Ctx, mp: []const f64, cov: []const f64, d: []const f64, m: usize) -> f64 {
    var acc = 0.0f64
    if c.maxst {
        var k = 0usize
        while k < m {
            let v = cov[k * m + k]
            if v > tolv() {
                let t = math.abs[f64](d[k] / math.sqrt[f64](v))
                if t > acc { acc = t }
            }
            k += 1usize
        }
        ret acc
    }
    ret qform(mp, d, m)
}

// libcoin's C_quadform on the deviation d
fn qform(mp: []const f64, d: []const f64, m: usize) -> f64 {
    var acc = 0.0f64
    var qq = 0usize
    while qq < m {
        var tmp = 0.0f64
        var p = 0usize
        while p < m {
            tmp += d[p] * mp[p * m + qq]
            p += 1usize
        }
        acc += tmp * d[qq]
        qq += 1usize
    }
    ret acc
}

// libcoin's C_Permute: a random permutation of expd into perm, tmp is scratch (R's n * unif_rand() truncated)
fn draw_perm(rg: *rr.Rng, expd: []const usize, tmp: []usize, perm: []usize) {
    var n = expd.len
    var i = 0usize
    while i < n {
        tmp[i] = expd[i]
        i += 1usize
    }
    i = 0usize
    while i < expd.len {
        let j = usize(f64(n) * rr.unif(rg))
        perm[i] = tmp[j]
        n -= 1usize
        tmp[j] = tmp[n]
        i += 1usize
    }
}

// the subset with every row repeated by its integer case weight (libcoin's RC_setup_subset)
fn expand_sub(a: *mem.Arena, c: *const Ctx, sub: []const usize) -> ([]usize, err) {
    var tot = 0usize
    var i = 0usize
    while i < sub.len {
        tot += usize(c.wt[sub[i]])
        i += 1usize
    }
    let (ex, e1) = mem.alloc[usize](a, tot)
    if e1 != ok { ret (ex, e1) }
    var at = 0usize
    i = 0usize
    while i < sub.len {
        var r = 0usize
        let wi = usize(c.wt[sub[i]])
        while r < wi {
            ex[at] = sub[i]
            at += 1usize
            r += 1usize
        }
        i += 1usize
    }
    ret (ex, ok)
}

// libcoin draws the nresample permutations before it looks at the variance, so a predictor without variation still consumes the stream
fn burn_perms(a: *mem.Arena, c: *const Ctx, sub: []const usize) -> err {
    if c.nres == 0usize { ret ok }
    let (expd, e1) = expand_sub(a, c, sub)
    let (tmp, e2) = mem.alloc[usize](a, expd.len)
    let (perm, e3) = mem.alloc[usize](a, expd.len)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var b = 0usize
    while b < c.nres {
        draw_perm(c.rg, expd, tmp, perm)
        b += 1usize
    }
    ret ok
}

// testtype MonteCarlo of one predictor without splittest: (log(1 - p), statistic); the permutation p value counts the permuted statistics at least the observed one up to tol
fn mc_plain(a: *mem.Arena, c: *const Ctx, sub: []const usize, j: usize, d: []const f64, cov: []const f64, dim: usize, np: usize, pidx: []const usize, pres: []const usize, cnt: []const f64, ei: []const f64) -> (f64, f64, err) {
    let q = c.q
    let lv = c.nl[j]
    let (mp, e1) = mem.alloc[f64](a, dim * dim)
    let (dp, e2) = mem.alloc[f64](a, dim)
    if e1 != ok || e2 != ok { ret (0.0f64, 0.0f64, mem.Full) }
    let e3 = mpinv(a, cov, dim, mp)
    if e3 != ok { ret (0.0f64, 0.0f64, e3) }
    let st = mcstat(c, mp, cov, d, dim)
    let (expd, e4) = expand_sub(a, c, sub)
    let (tmp, e5) = mem.alloc[usize](a, expd.len)
    let (perm, e6) = mem.alloc[usize](a, expd.len)
    if e4 != ok || e5 != ok || e6 != ok { ret (0.0f64, 0.0f64, mem.Full) }
    var ex = 0.0f64
    var i = 0usize
    while i < sub.len {
        ex += c.x[j * c.n + sub[i]] * c.wt[sub[i]]
        i += 1usize
    }
    var greater = 0usize
    var b = 0usize
    while b < c.nres {
        draw_perm(c.rg, expd, tmp, perm)
        var u = 0usize
        while u < dim {
            dp[u] = 0.0f64
            u += 1usize
        }
        i = 0usize
        while i < expd.len {
            let ob = expd[i]
            let yb = perm[i]
            var k = 0usize
            if lv == 0usize {
                let xv = c.x[j * c.n + ob]
                while k < q {
                    dp[k] += xv * c.h[k * c.n + yb]
                    k += 1usize
                }
            } else {
                let l = pidx[usize(c.x[j * c.n + ob])]
                while k < q {
                    dp[k * np + l] += c.h[k * c.n + yb]
                    k += 1usize
                }
            }
            i += 1usize
        }
        var k2 = 0usize
        while k2 < q {
            if lv == 0usize {
                dp[k2] -= ex * ei[k2]
            } else {
                var l2 = 0usize
                while l2 < np {
                    dp[k2 * np + l2] -= cnt[pres[l2]] * ei[k2]
                    l2 += 1usize
                }
            }
            k2 += 1usize
        }
        let pst = mcstat(c, mp, cov, dp, dim)
        if pst > st || math.abs[f64](pst - st) < tolv() { greater += 1usize }
        b += 1usize
    }
    ret (dist.log1p(0.0f64 - f64(greater) / f64(c.nres)), st, ok)
}

// the cut points of one predictor over its present groups (splittest = TRUE), visited as libcoin's C_ordered_Xfactor and C_unordered_Xfactor do: running left sums, one covariance and one Moore-Penrose inverse per cut, then the observed and every permuted statistic against it
type SpC = struct { num: bool, g: usize, q: usize, m: f64, mb: f64, f1: f64, f2: f64, ei: []const f64, ci: []const f64, maxst: bool, nres: usize, ml: []f64, mex: []f64, mbl: []f64, mp: []f64, cv: []f64, dd: []f64, ls: []f64, best: f64, bmax: []f64 }

// the statistic of the linear statistic ls with expectation ex at the current cut
fn cut_stat(s: *SpC, ls: []const f64, ex: []const f64) -> f64 {
    let q = s.q
    if s.maxst {
        var ans = 0.0f64 - 1.0f64 / 0.0f64
        var k = 0usize
        while k < q {
            var t = 0.0f64
            if s.cv[k] > tolv() { t = math.abs[f64]((ls[k] - ex[k]) / math.sqrt[f64](s.cv[k])) }
            if t > ans { ans = t }
            k += 1usize
        }
        ret ans
    }
    var k2 = 0usize
    while k2 < q {
        s.dd[k2] = ls[k2] - ex[k2]
        k2 += 1usize
    }
    ret qform(s.mp, s.dd, q)
}

// one admissible cut with sl observations on the left: refresh the variance or covariance and its inverse, then update the observed maximum and the permuted ones
fn cut_eval(a: *mem.Arena, s: *SpC, sl: f64) -> err {
    let start = mem.mark(a)
    let q = s.q
    let f1 = s.f1
    let f2 = s.f2
    if q == 1usize {
        var v = f1 * s.ci[0usize] * sl
        v -= f2 * s.ci[0usize] * sl * sl
        s.cv[0usize] = v
    } else {
        var k = 0usize
        while k < q {
            var r = 0usize
            while r < q {
                if s.maxst {
                    if r == k { s.cv[k] = s.ci[k * q + k] * (f1 * sl - f2 * sl * sl) }
                } else {
                    s.cv[k * q + r] = s.ci[k * q + r] * (f1 * sl - f2 * (sl * sl))
                }
                r += 1usize
            }
            k += 1usize
        }
    }
    if !s.maxst {
        let e = mpinv(a, s.cv, q, s.mp)
        if e != ok { ret e }
    }
    let t = cut_stat(s, s.ml, s.mex)
    if t > s.best { s.best = t }
    var b = 0usize
    while b < s.nres {
        let pst = cut_stat(s, s.mbl[b * q..b * q + q], s.mex)
        if pst > s.bmax[b] { s.bmax[b] = pst }
        b += 1usize
    }
    mem.reset(a, start)
    ret ok
}

// every cut point against the group table gl (g by q linear statistics) with sizes cg and the permuted tables pt (nres of them)
fn cut_run(a: *mem.Arena, s: *SpC, gl: []const f64, cg: []const f64, pt: []const f64) -> err {
    let q = s.q
    let ng = s.g
    if s.num {
        var sl = 0.0f64
        var k = 0usize
        while k < q {
            s.ml[k] = 0.0f64
            s.mex[k] = 0.0f64
            k += 1usize
        }
        var u = 0usize
        while u < s.nres * q {
            s.mbl[u] = 0.0f64
            u += 1usize
        }
        var g = 0usize
        while g < ng {
            sl += cg[g]
            k = 0usize
            while k < q {
                s.ml[k] += gl[g * q + k]
                s.mex[k] += cg[g] * s.ei[k]
                var b = 0usize
                while b < s.nres {
                    s.mbl[b * q + k] += pt[b * ng * q + g * q + k]
                    b += 1usize
                }
                k += 1usize
            }
            if sl >= s.mb && s.m - sl >= s.mb {
                let e = cut_eval(a, s, sl)
                if e != ok { ret e }
            }
            g += 1usize
        }
        ret ok
    }
    var mi = 1usize
    var l = 1usize
    while l < ng {
        mi *= 2usize
        l += 1usize
    }
    var jv = 1usize
    while jv < mi {
        var sl = 0.0f64
        var k = 0usize
        while k < q {
            s.ml[k] = 0.0f64
            s.mex[k] = 0.0f64
            k += 1usize
        }
        var u = 0usize
        while u < s.nres * q {
            s.mbl[u] = 0.0f64
            u += 1usize
        }
        var jj = jv
        l = 1usize
        while l < ng {
            if jj % 2usize == 1usize {
                sl += cg[l]
                k = 0usize
                while k < q {
                    s.ml[k] += gl[l * q + k]
                    s.mex[k] += cg[l] * s.ei[k]
                    var b = 0usize
                    while b < s.nres {
                        s.mbl[b * q + k] += pt[b * ng * q + l * q + k]
                        b += 1usize
                    }
                    k += 1usize
                }
            }
            jj /= 2usize
            l += 1usize
        }
        if sl >= s.mb && s.m - sl >= s.mb {
            let e = cut_eval(a, s, sl)
            if e != ok { ret e }
        }
        jv += 1usize
    }
    ret ok
}

// splittest = TRUE: the test of predictor j is the maximally selected statistic over its cut points; with nres > 0 the p value is the permutation one; (log statistic, log(1 - p), valid)
fn test_split(a: *mem.Arena, c: *const Ctx, sub: []const usize, j: usize, mb: usize) -> (f64, f64, bool, err) {
    let start = mem.mark(a)
    let q = c.q
    let m = sumw(c, sub)
    let (ei, e1) = mem.alloc[f64](a, q)
    let (ci, e2) = mem.alloc[f64](a, q * q)
    let (gid, e3) = mem.alloc[usize](a, c.n)
    if e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, 0.0f64, false, mem.Full) }
    influence(c, sub, ei, ci)
    let lv = c.nl[j]
    var ng = 0usize
    if lv == 0usize {
        let (srt, e4) = mem.alloc[usize](a, sub.len)
        if e4 != ok { ret (0.0f64, 0.0f64, false, e4) }
        var i = 0usize
        while i < sub.len {
            srt[i] = sub[i]
            i += 1usize
        }
        sort_by(srt, c.x, j, c.n)
        i = 0usize
        while i < srt.len {
            if i > 0usize && c.x[j * c.n + srt[i]] != c.x[j * c.n + srt[i - 1usize]] { ng += 1usize }
            gid[srt[i]] = ng
            i += 1usize
        }
        ng += 1usize
    } else {
        let (pix, e4) = mem.alloc[usize](a, lv)
        let (pc, e5) = mem.alloc[f64](a, lv)
        if e4 != ok || e5 != ok { ret (0.0f64, 0.0f64, false, mem.Full) }
        var l = 0usize
        while l < lv {
            pc[l] = 0.0f64
            l += 1usize
        }
        var i = 0usize
        while i < sub.len {
            pc[usize(c.x[j * c.n + sub[i]])] += c.wt[sub[i]]
            i += 1usize
        }
        l = 0usize
        while l < lv {
            if pc[l] > 0.0f64 {
                pix[l] = ng
                ng += 1usize
            }
            l += 1usize
        }
        i = 0usize
        while i < sub.len {
            gid[sub[i]] = pix[usize(c.x[j * c.n + sub[i]])]
            i += 1usize
        }
    }
    let (cg, e6) = mem.alloc[f64](a, ng)
    let (gl, e7) = mem.alloc[f64](a, ng * q)
    let (mp, e9) = mem.alloc[f64](a, q * q)
    let (ml, e10) = mem.alloc[f64](a, q)
    let (dd, e11) = mem.alloc[f64](a, q)
    let (mex, e11b) = mem.alloc[f64](a, q)
    let (cv, e11c) = mem.alloc[f64](a, q * q)
    let (mbl, e11d) = mem.alloc[f64](a, c.nres * q + 1usize)
    let (bmax, e11e) = mem.alloc[f64](a, c.nres + 1usize)
    if e6 != ok || e7 != ok || e9 != ok || e10 != ok || e11 != ok || e11b != ok || e11c != ok || e11d != ok || e11e != ok { ret (0.0f64, 0.0f64, false, mem.Full) }
    var g = 0usize
    while g < ng {
        cg[g] = 0.0f64
        var k = 0usize
        while k < q {
            gl[g * q + k] = 0.0f64
            k += 1usize
        }
        g += 1usize
    }
    var i = 0usize
    while i < sub.len {
        let gi = gid[sub[i]]
        cg[gi] += c.wt[sub[i]]
        var k = 0usize
        while k < q {
            gl[gi * q + k] += c.h[k * c.n + sub[i]] * c.wt[sub[i]]
            k += 1usize
        }
        i += 1usize
    }
    let f1 = m / (m - 1.0f64)
    let f2 = 1.0f64 / (m - 1.0f64)
    var allsmall = true
    g = 0usize
    while g < ng {
        var k = 0usize
        while k < q {
            if !(ci[k * q + k] * (f1 * cg[g] - f2 * cg[g] * cg[g]) < tolv()) { allsmall = false }
            k += 1usize
        }
        g += 1usize
    }
    // the permutations are drawn before the variance is looked at
    var pt: []f64 = zero
    if c.nres > 0usize {
        let (expd, e13) = expand_sub(a, c, sub)
        let (tmp, e14) = mem.alloc[usize](a, expd.len)
        let (perm, e15) = mem.alloc[usize](a, expd.len)
        let (pt0, e16) = mem.alloc[f64](a, c.nres * ng * q)
        if e13 != ok || e14 != ok || e15 != ok || e16 != ok { ret (0.0f64, 0.0f64, false, mem.Full) }
        var b = 0usize
        while b < c.nres {
            draw_perm(c.rg, expd, tmp, perm)
            var u = 0usize
            while u < ng * q {
                pt0[b * ng * q + u] = 0.0f64
                u += 1usize
            }
            i = 0usize
            while i < expd.len {
                let gi = gid[expd[i]]
                var k = 0usize
                while k < q {
                    pt0[b * ng * q + gi * q + k] += c.h[k * c.n + perm[i]]
                    k += 1usize
                }
                i += 1usize
            }
            b += 1usize
        }
        pt = pt0
    }
    if allsmall {
        mem.reset(a, start)
        ret (0.0f64, 0.0f64, false, ok)
    }
    var sp = SpC { num: lv == 0usize, g: ng, q: q, m: m, mb: f64(mb), f1: f1, f2: f2, ei: ei, ci: ci, maxst: c.maxst, nres: c.nres, ml: ml, mex: mex, mbl: mbl, mp: mp, cv: cv, dd: dd, ls: ml, best: 0.0f64, bmax: bmax }
    var bi = 0usize
    while bi < c.nres {
        bmax[bi] = 0.0f64
        bi += 1usize
    }
    let ecr = cut_run(a, &sp, gl, cg, pt)
    if ecr != ok { ret (0.0f64, 0.0f64, false, ecr) }
    var lp = 0.0f64
    if c.nres > 0usize {
        var greater = 0usize
        bi = 0usize
        while bi < c.nres {
            if bmax[bi] > sp.best { greater += 1usize }
            bi += 1usize
        }
        lp = dist.log1p(0.0f64 - f64(greater) / f64(c.nres))
    }
    mem.reset(a, start)
    var sm = sp.best
    if sm < 2.220446049250313e-16f64 { sm = 2.220446049250313e-16f64 }
    ret (math.log[f64](sm), lp, true, ok)
}

// (log statistic, log(1 - p), valid): the test of predictor j on the subset; mb is the node's minbucket (only splittest = TRUE reads it)
fn test_var(a: *mem.Arena, c: *const Ctx, sub: []const usize, j: usize, mb: usize) -> (f64, f64, bool, err) {
    if c.spl {
        let (ls0, lp0, v0, e0) = test_split(a, c, sub, j, mb)
        ret (ls0, lp0, v0, e0)
    }
    let start = mem.mark(a)
    let q = c.q
    let m = sumw(c, sub)
    let f1 = m / (m - 1.0f64)
    let f2 = 1.0f64 / (m - 1.0f64)
    let (ei, e1) = mem.alloc[f64](a, q)
    let (ci, e2) = mem.alloc[f64](a, q * q)
    if e1 != ok || e2 != ok { ret (0.0f64, 0.0f64, false, mem.Full) }
    influence(c, sub, ei, ci)
    var np = 1usize
    let lv = c.nl[j]
    var cnt: []f64 = zero
    var pres: []usize = zero
    var pidx: []usize = zero
    if lv > 0usize {
        let (cn, e3) = mem.alloc[f64](a, lv)
        let (pr, e4) = mem.alloc[usize](a, lv)
        let (pi, e5) = mem.alloc[usize](a, lv)
        if e3 != ok || e4 != ok || e5 != ok { ret (0.0f64, 0.0f64, false, mem.Full) }
        var l = 0usize
        while l < lv {
            cn[l] = 0.0f64
            l += 1usize
        }
        var i = 0usize
        while i < sub.len {
            let l2 = usize(c.x[j * c.n + sub[i]])
            cn[l2] += c.wt[sub[i]]
            i += 1usize
        }
        np = 0usize
        l = 0usize
        while l < lv {
            if cn[l] > 0.0f64 {
                pr[np] = l
                pi[l] = np
                np += 1usize
            }
            l += 1usize
        }
        cnt = cn
        pres = pr
        pidx = pi
    }
    let dim = np * q
    let (d, e6) = mem.alloc[f64](a, dim)
    let (cov, e7) = mem.alloc[f64](a, dim * dim)
    if e6 != ok || e7 != ok { ret (0.0f64, 0.0f64, false, mem.Full) }
    if lv == 0usize {
        var ex = 0.0f64
        var cx = 0.0f64
        var i = 0usize
        while i < sub.len {
            let xv = c.x[j * c.n + sub[i]]
            ex += xv * c.wt[sub[i]]
            cx += xv * xv * c.wt[sub[i]]
            i += 1usize
        }
        var k = 0usize
        while k < q {
            var t = 0.0f64
            i = 0usize
            while i < sub.len {
                t += (c.x[j * c.n + sub[i]] * c.h[k * c.n + sub[i]]) * c.wt[sub[i]]
                i += 1usize
            }
            d[k] = t - ex * ei[k]
            var r = 0usize
            while r < q {
                cov[k * q + r] = ci[k * q + r] * (f1 * cx - f2 * ex * ex)
                r += 1usize
            }
            k += 1usize
        }
    } else {
        var k = 0usize
        while k < q {
            var l = 0usize
            while l < np {
                d[k * np + l] = 0.0f64
                l += 1usize
            }
            var i = 0usize
            while i < sub.len {
                let l2 = pidx[usize(c.x[j * c.n + sub[i]])]
                d[k * np + l2] += c.h[k * c.n + sub[i]] * c.wt[sub[i]]
                i += 1usize
            }
            l = 0usize
            while l < np {
                d[k * np + l] -= cnt[pres[l]] * ei[k]
                l += 1usize
            }
            k += 1usize
        }
        k = 0usize
        while k < q {
            var r = 0usize
            while r < q {
                var l = 0usize
                while l < np {
                    var l2 = 0usize
                    while l2 < np {
                        var dg = 0.0f64
                        if l == l2 { dg = f1 * cnt[pres[l]] }
                        cov[(k * np + l) * dim + r * np + l2] = ci[k * q + r] * (dg - f2 * cnt[pres[l]] * cnt[pres[l2]])
                        l2 += 1usize
                    }
                    l += 1usize
                }
                r += 1usize
            }
            k += 1usize
        }
    }
    var allsmall = true
    var u = 0usize
    while u < dim {
        if !(cov[u * dim + u] < tolv()) { allsmall = false }
        u += 1usize
    }
    if allsmall {
        let eb = burn_perms(a, c, sub)
        if eb != ok { ret (0.0f64, 0.0f64, false, eb) }
        mem.reset(a, start)
        ret (0.0f64, 0.0f64, false, ok)
    }
    if c.nres > 0usize {
        let (lpm, stm, em) = mc_plain(a, c, sub, j, d, cov, dim, np, pidx, pres, cnt, ei)
        mem.reset(a, start)
        if em != ok { ret (0.0f64, 0.0f64, false, em) }
        var sm0 = stm
        if sm0 < 2.220446049250313e-16f64 { sm0 = 2.220446049250313e-16f64 }
        ret (math.log[f64](sm0), lpm, true, ok)
    }
    if c.maxst && dim != 1usize {
        var mxs = 0.0f64
        u = 0usize
        while u < dim {
            if cov[u * dim + u] > tolv() {
                let t = math.abs[f64](d[u] / math.sqrt[f64](cov[u * dim + u]))
                if t > mxs { mxs = t }
            }
            u += 1usize
        }
        let (lpm, em) = maxtype_lp(a, c, cov, mxs, dim)
        mem.reset(a, start)
        if em != ok { ret (0.0f64, 0.0f64, false, em) }
        if mxs < 2.220446049250313e-16f64 { mxs = 2.220446049250313e-16f64 }
        ret (math.log[f64](mxs), lpm, true, ok)
    }
    let (stat, rank, e8) = quad(a, cov, d, dim)
    mem.reset(a, start)
    if e8 != ok { ret (0.0f64, 0.0f64, false, e8) }
    if rank == 0usize { ret (0.0f64, 0.0f64, false, ok) }
    let lp = nm.pchisq(stat, f64(rank), true, true)
    var sm = stat
    if c.maxst { sm = math.sqrt[f64](stat) }
    if sm < 2.220446049250313e-16f64 { sm = 2.220446049250313e-16f64 }
    ret (math.log[f64](sm), lp, true, ok)
}

// sort idx ascending by key (insertion; the node sizes here are small)
fn sort_by(idx: []usize, key: []const f64, col: usize, n: usize) {
    var i = 1usize
    while i < idx.len {
        let v = idx[i]
        var j = i
        while j > 0usize && key[col * n + idx[j - 1usize]] > key[col * n + v] {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = v
        i += 1usize
    }
}

// the maximally selected split of predictor j; numeric: x <= brk goes to child 1; factor: dir[level] is 0 (child 1), 1 (child 2) or -1 (absent)
fn find_split(a: *mem.Arena, c: *const Ctx, sub: []const usize, j: usize, mb: usize, dir: []i64) -> (Split, err) {
    var res: Split = zero
    res.dir = dir
    let q = c.q
    let m = sumw(c, sub)
    let f1 = m / (m - 1.0f64)
    let f2 = 1.0f64 / (m - 1.0f64)
    let mbf = f64(mb)
    let (ei, e1) = mem.alloc[f64](a, q)
    let (ci, e2) = mem.alloc[f64](a, q * q)
    let (ml, e3) = mem.alloc[f64](a, q)
    let (cov, e4) = mem.alloc[f64](a, q * q)
    let (dd, e5) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (res, mem.Full) }
    influence(c, sub, ei, ci)
    let lv = c.nl[j]
    var maxstat = 0.0f64
    if lv == 0usize {
        let (srt, e6) = mem.alloc[usize](a, sub.len)
        if e6 != ok { ret (res, e6) }
        var i = 0usize
        while i < sub.len {
            srt[i] = sub[i]
            i += 1usize
        }
        sort_by(srt, c.x, j, c.n)
        var k = 0usize
        while k < q {
            ml[k] = 0.0f64
            k += 1usize
        }
        var sumleft = 0.0f64
        i = 0usize
        while i < srt.len {
            var e = i
            while e + 1usize < srt.len && c.x[j * c.n + srt[e + 1usize]] == c.x[j * c.n + srt[i]] { e += 1usize }
            var g = i
            while g <= e {
                k = 0usize
                while k < q {
                    ml[k] += c.h[k * c.n + srt[g]] * c.wt[srt[g]]
                    k += 1usize
                }
                g += 1usize
            }
            var tw = 0.0f64
            g = i
            while g <= e {
                tw += c.wt[srt[g]]
                g += 1usize
            }
            sumleft += tw
            let sumright = m - sumleft
            if sumleft >= mbf && sumright >= mbf {
                k = 0usize
                while k < q {
                    dd[k] = ml[k] - sumleft * ei[k]
                    var r = 0usize
                    while r < q {
                        cov[k * q + r] = ci[k * q + r] * (f1 * sumleft - f2 * sumleft * sumleft)
                        r += 1usize
                    }
                    k += 1usize
                }
                let (st, rk, e7) = split_stat(a, c, cov, dd, q)
                if e7 != ok { ret (res, e7) }
                if st > maxstat {
                    maxstat = st
                    res.found = true
                    res.brk = c.x[j * c.n + srt[i]]
                }
            }
            i = e + 1usize
        }
        ret (res, ok)
    }
    // unordered factor: every two-way partition of the levels present, the first present level always in child 1
    let (cnt, e8) = mem.alloc[f64](a, lv)
    let (sl, e9) = mem.alloc[f64](a, lv * q)
    let (pres, e10) = mem.alloc[usize](a, lv)
    if e8 != ok || e9 != ok || e10 != ok { ret (res, mem.Full) }
    var l = 0usize
    while l < lv {
        cnt[l] = 0.0f64
        var k = 0usize
        while k < q {
            sl[k * lv + l] = 0.0f64
            k += 1usize
        }
        dir[l] = 0i64 - 1i64
        l += 1usize
    }
    var i = 0usize
    while i < sub.len {
        let l2 = usize(c.x[j * c.n + sub[i]])
        cnt[l2] += c.wt[sub[i]]
        var k = 0usize
        while k < q {
            sl[k * lv + l2] += c.h[k * c.n + sub[i]] * c.wt[sub[i]]
            k += 1usize
        }
        i += 1usize
    }
    var npz = 0usize
    l = 0usize
    while l < lv {
        if cnt[l] > 0.0f64 {
            pres[npz] = l
            npz += 1usize
        }
        l += 1usize
    }
    if npz < 2usize { ret (res, ok) }
    var mi = 1usize
    l = 1usize
    while l < npz {
        mi *= 2usize
        l += 1usize
    }
    var jv = 1usize
    while jv < mi {
        var sumleft = 0.0f64
        var k = 0usize
        while k < q {
            ml[k] = 0.0f64
            k += 1usize
        }
        var jj = jv
        l = 1usize
        while l < npz {
            if jj % 2usize == 1usize {
                sumleft += cnt[pres[l]]
                k = 0usize
                while k < q {
                    ml[k] += sl[k * lv + pres[l]]
                    k += 1usize
                }
            }
            jj /= 2usize
            l += 1usize
        }
        let sumright = m - sumleft
        if sumleft >= mbf && sumright >= mbf {
            k = 0usize
            while k < q {
                dd[k] = ml[k] - sumleft * ei[k]
                var r = 0usize
                while r < q {
                    cov[k * q + r] = ci[k * q + r] * (f1 * sumleft - f2 * sumleft * sumleft)
                    r += 1usize
                }
                k += 1usize
            }
            let (st, rk, e7) = split_stat(a, c, cov, dd, q)
            if e7 != ok { ret (res, e7) }
            if st > maxstat {
                maxstat = st
                res.found = true
                dir[pres[0usize]] = 0i64
                jj = jv
                l = 1usize
                while l < npz {
                    dir[pres[l]] = i64(jj % 2usize)
                    jj /= 2usize
                    l += 1usize
                }
            }
        }
        jv += 1usize
    }
    ret (res, ok)
}

fn node_fit(c: *const Ctx, sub: []const usize, cnt: []f64) -> f64 {
    if c.yl == 0usize {
        var s = 0.0f64
        var i = 0usize
        while i < sub.len {
            s += c.y[sub[i]] * c.wt[sub[i]]
            i += 1usize
        }
        ret s / sumw(c, sub)
    }
    var l = 0usize
    while l < c.yl {
        cnt[l] = 0.0f64
        l += 1usize
    }
    var i = 0usize
    while i < sub.len {
        cnt[usize(c.y[sub[i]])] += c.wt[sub[i]]
        i += 1usize
    }
    var best = 0usize
    l = 1usize
    while l < c.yl {
        if cnt[l] > cnt[best] { best = l }
        l += 1usize
    }
    ret f64(best)
}

// R's heapsort into descending order of a, permuting ib alongside (revsort in sort.c); 0-based storage of R's 1-based algorithm
fn revsort(a: []f64, ib: []usize, n: usize) {
    if n <= 1usize { ret }
    var l = (n >> 1usize) + 1usize
    var ir = n
    while true {
        var ra = 0.0f64
        var ii = 0usize
        if l > 1usize {
            l -= 1usize
            ra = a[l - 1usize]
            ii = ib[l - 1usize]
        } else {
            ra = a[ir - 1usize]
            ii = ib[ir - 1usize]
            a[ir - 1usize] = a[0usize]
            ib[ir - 1usize] = ib[0usize]
            ir -= 1usize
            if ir == 1usize {
                a[0usize] = ra
                ib[0usize] = ii
                ret
            }
        }
        var i = l
        var j = l << 1usize
        while j <= ir {
            if j < ir && a[j - 1usize] > a[j] { j += 1usize }
            if ra > a[j - 1usize] {
                a[i - 1usize] = a[j - 1usize]
                ib[i - 1usize] = ib[j - 1usize]
                i = j
                j += i
            } else {
                j = ir + 1usize
            }
        }
        a[i - 1usize] = ra
        ib[i - 1usize] = ii
    }
}

// sample.int(n, size, prob = rep(1, n)) without replacement (R's ProbSampleNoReplace); the result holds 0-based positions
fn sample_prob(a: *mem.Arena, rg: *rr.Rng, n: usize, size: usize) -> ([]usize, err) {
    let (p, e1) = mem.alloc[f64](a, n)
    let (perm, e2) = mem.alloc[usize](a, n)
    let (ans, e3) = mem.alloc[usize](a, size + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret (ans, mem.Full) }
    var i = 0usize
    var sum = 0.0f64
    while i < n {
        sum += 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        p[i] = 1.0f64 / sum
        perm[i] = i + 1usize
        i += 1usize
    }
    revsort(p, perm, n)
    var total = 1.0f64
    var n1 = n - 1usize
    i = 0usize
    while i < size {
        let rt = total * rr.unif(rg)
        var mass = 0.0f64
        var j = 0usize
        while j < n1 {
            mass += p[j]
            if rt <= mass { break }
            j += 1usize
        }
        ans[i] = perm[j] - 1usize
        total -= p[j]
        var k = j
        while k < n1 {
            p[k] = p[k + 1usize]
            perm[k] = perm[k + 1usize]
            k += 1usize
        }
        i += 1usize
        if n1 > 0usize { n1 -= 1usize }
    }
    ret (ans, ok)
}

fn grow(a: *mem.Arena, c: *const Ctx, ctl: *const Ctl, o: *Out, rg: *rr.Rng, sub: []usize, id: usize, depth: usize) -> (usize, err) {
    let k = id - 1usize
    let m = sub.len
    let mw = sumw(c, sub)
    if id > o.count { o.count = id }
    o.vr[k] = 0i64
    o.nobs[k] = mw
    o.pval[k] = nan()
    o.stat[k] = nan()
    var ycnt: []f64 = zero
    if c.yl > 0usize {
        let (yc, ey) = mem.alloc[f64](a, c.yl)
        if ey != ok { ret (id, ey) }
        ycnt = yc
    }
    o.fit[k] = node_fit(c, sub, ycnt)
    if depth >= ctl.maxdepth { ret (id, ok) }
    if id > 1usize && ctl.stump { ret (id, ok) }
    if mw < f64(ctl.minsplit) { ret (id, ok) }
    var mb = ctl.minbucket
    let swp = usize(math.ceil[f64](mw * ctl.minprob))
    if mb < swp { mb = swp }
    let (ls, e1) = mem.alloc[f64](a, c.p)
    let (lp, e2) = mem.alloc[f64](a, c.p)
    let (cr, e3) = mem.alloc[f64](a, c.p)
    let (okv, e4) = mem.alloc[bool](a, c.p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (id, mem.Full) }
    // mtry: the variables tried at this node are a random draw (R's .resample with prob, drawn before any test)
    let (usev, e12) = mem.alloc[bool](a, c.p)
    if e12 != ok { ret (id, mem.Full) }
    // maxvar: once that many variables have split somewhere in the tree (depth-first, as R's shared splitvars), only those stay candidates
    var nsv = 0usize
    var j = 0usize
    while j < c.p {
        if o.sv[j] { nsv += 1usize }
        j += 1usize
    }
    let (sl, e14) = mem.alloc[usize](a, c.p)
    if e14 != ok { ret (id, mem.Full) }
    var nsl = 0usize
    j = 0usize
    while j < c.p {
        usev[j] = false
        if nsv < ctl.maxvar || o.sv[j] {
            usev[j] = true
            sl[nsl] = j
            nsl += 1usize
        }
        j += 1usize
    }
    if ctl.mtry > 0usize && ctl.mtry < 1000000usize && nsl > 0usize {
        var mt = ctl.mtry
        if mt > nsl { mt = nsl }
        j = 0usize
        while j < c.p {
            usev[j] = false
            j += 1usize
        }
        let (pick, e13) = sample_prob(a, rg, nsl, mt)
        if e13 != ok { ret (id, e13) }
        j = 0usize
        while j < mt {
            usev[sl[pick[j]]] = true
            j += 1usize
        }
    }
    var nvalid = 0usize
    j = 0usize
    while j < c.p {
        ls[j] = 0.0f64
        lp[j] = 0.0f64
        okv[j] = false
        if usev[j] {
            let (s1, p1, v1, et) = test_var(a, c, sub, j, mb)
            if et != ok { ret (id, et) }
            ls[j] = s1
            lp[j] = p1
            okv[j] = v1
            if v1 { nvalid += 1usize }
        }
        j += 1usize
    }
    if nvalid == 0usize { ret (id, ok) }
    var mult = 1.0f64
    if ctl.bonf { mult = f64(nvalid) }
    var maxc = 0.0f64 - 1.0f64 / 0.0f64
    j = 0usize
    while j < c.p {
        cr[j] = 0.0f64 - 1.0f64 / 0.0f64
        if okv[j] {
            cr[j] = lp[j] * mult
            if ctl.statcrit { cr[j] = ls[j] }
        }
        if cr[j] > maxc { maxc = cr[j] }
        j += 1usize
    }
    // ties: crit + rank(statistic) / (sum(tied positions) * 1000), positions 1-based as R's sum(ties) adds them
    var nt = 0usize
    var tsum = 0.0f64
    j = 0usize
    while j < c.p {
        var d = cr[j] - maxc
        if d < 0.0f64 { d = 0.0f64 - d }
        if d < 1.4916681462400413e-154f64 {
            nt += 1usize
            tsum += f64(j + 1usize)
        }
        j += 1usize
    }
    var adj = cr[0usize]
    if nt > 1usize {
        let (ncr, e5) = mem.alloc[f64](a, c.p)
        if e5 != ok { ret (id, mem.Full) }
        j = 0usize
        while j < c.p {
            ncr[j] = cr[j]
            var d = cr[j] - maxc
            if d < 0.0f64 { d = 0.0f64 - d }
            if d < 1.4916681462400413e-154f64 {
                var below = 0.0f64
                var eq = 0.0f64
                var i = 0usize
                while i < c.p {
                    var di = cr[i] - maxc
                    if di < 0.0f64 { di = 0.0f64 - di }
                    if di < 1.4916681462400413e-154f64 {
                        if ls[i] < ls[j] { below += 1.0f64 }
                        if ls[i] == ls[j] { eq += 1.0f64 }
                    }
                    i += 1usize
                }
                let rk = below + (eq + 1.0f64) / 2.0f64
                ncr[j] = cr[j] + rk / (tsum * 1000.0f64)
            }
            j += 1usize
        }
        j = 0usize
        while j < c.p {
            cr[j] = ncr[j]
            j += 1usize
        }
    }
    // the stable ascending order of the criterion; the last entry is the best (ties to the higher index)
    let (ord, e6) = mem.alloc[usize](a, c.p)
    if e6 != ok { ret (id, mem.Full) }
    j = 0usize
    while j < c.p {
        ord[j] = j
        j += 1usize
    }
    var i = 1usize
    while i < c.p {
        let v = ord[i]
        var jj = i
        while jj > 0usize && cr[ord[jj - 1usize]] > cr[v] {
            ord[jj] = ord[jj - 1usize]
            jj -= 1usize
        }
        ord[jj] = v
        i += 1usize
    }
    let best = ord[c.p - 1usize]
    var pm = 0.0f64 - dist.expm1(lp[best] * mult)
    if ctl.statcrit { pm = nan() }
    o.pval[k] = pm
    o.stat[k] = math.exp[f64](ls[best])
    if !(cr[best] > ctl.logmin) { ret (id, ok) }
    var nfin = 0usize
    j = 0usize
    while j < c.p {
        if cr[j] > 0.0f64 - 1.0f64 / 0.0f64 { nfin += 1usize }
        j += 1usize
    }
    var st = nfin
    if st > ctl.splittry { st = ctl.splittry }
    let (dir, e7) = mem.alloc[i64](a, o.maxlev + 1usize)
    if e7 != ok { ret (id, mem.Full) }
    var sp: Split = zero
    var t = 0usize
    var chosen = c.p
    while t < st && chosen == c.p {
        let jsel = ord[c.p - 1usize - t]
        if cr[jsel] > ctl.logmin {
            let (s, es) = find_split(a, c, sub, jsel, mb, dir)
            if es != ok { ret (id, es) }
            if s.found {
                sp = s
                chosen = jsel
            }
        }
        t += 1usize
    }
    if chosen == c.p { ret (id, ok) }
    o.vr[k] = i64(chosen + 1usize)
    o.sv[chosen] = true
    o.stat[k] = math.exp[f64](ls[chosen])
    var bk = sp.brk
    var isord = false
    if ctl.ord.len > chosen { isord = ctl.ord[chosen] }
    if ctl.inter && c.nl[chosen] == 0usize && !isord {
        // intersplit: the midpoint to the next distinct value of the predictor over the whole data
        var nxt = 0.0f64
        var hasn = false
        var r2 = 0usize
        while r2 < c.n {
            let xv2 = c.x[chosen * c.n + r2]
            if xv2 > bk && (!hasn || xv2 < nxt) {
                nxt = xv2
                hasn = true
            }
            r2 += 1usize
        }
        if hasn { bk = (bk + nxt) / 2.0f64 }
    }
    sp.brk = bk
    o.brk[k] = sp.brk
    var n1 = 0usize
    var n2 = 0usize
    i = 0usize
    while i < m {
        let xv = c.x[chosen * c.n + sub[i]]
        var left = false
        if c.nl[chosen] == 0usize {
            left = xv <= sp.brk
        } else {
            left = dir[usize(xv)] == 0i64
        }
        if left { n1 += 1usize } else { n2 += 1usize }
        i += 1usize
    }
    let (s1, e8) = mem.alloc[usize](a, n1)
    let (s2, e9) = mem.alloc[usize](a, n2)
    if e8 != ok || e9 != ok { ret (id, mem.Full) }
    n1 = 0usize
    n2 = 0usize
    i = 0usize
    while i < m {
        let xv = c.x[chosen * c.n + sub[i]]
        var left = false
        if c.nl[chosen] == 0usize {
            left = xv <= sp.brk
        } else {
            left = dir[usize(xv)] == 0i64
        }
        if left {
            s1[n1] = sub[i]
            n1 += 1usize
        } else {
            s2[n2] = sub[i]
            n2 += 1usize
        }
        i += 1usize
    }
    var l = 0usize
    while l < o.maxlev {
        o.lmap[k * o.maxlev + l] = 0i64 - 1i64
        if c.nl[chosen] > 0usize && l < c.nl[chosen] { o.lmap[k * o.maxlev + l] = dir[l] }
        l += 1usize
    }
    o.prob1[k] = sumw(c, s1) / mw
    o.kid1[k] = i64(id + 1usize)
    let (mx1, e10) = grow(a, c, ctl, o, rg, s1, id + 1usize, depth + 1usize)
    if e10 != ok { ret (mx1, e10) }
    o.kid2[k] = i64(mx1 + 1usize)
    let (mx2, e11) = grow(a, c, ctl, o, rg, s2, mx1 + 1usize, depth + 1usize)
    ret (mx2, e11)
}

// ctree on x (n by p column-major), nl[j] = 0 for a numeric predictor or the number of levels (codes 0 .. nl - 1) of a factor,
// y numeric (yl = 0) or the class codes of a factor response with yl levels
fn ctree(a: *mem.Arena, x: []const f64, n: usize, p: usize, nl: []const usize, y: []const f64, yl: usize, minsplit: usize, minbucket: usize, minprob: f64, alpha: f64, bonf: bool, maxdepth: usize, stump: bool, inter: bool) -> (Out, err) {
    var rg: rr.Rng = zero
    var none: []const usize = zero
    var none2: []const bool = zero
    var none4: []const f64 = zero
    let xo = Xo { statcrit: false, maxst: false, setlog: false, logmin: 0.0f64, ord: none2, w: none4, nres: 0usize, spl: false, mtry: 0usize, maxvar: 1000000usize }
    let (o, e) = ctree_core(a, x, n, p, nl, y, yl, minsplit, minbucket, minprob, alpha, bonf, maxdepth, stump, inter, 0usize, &rg, none, &xo)
    ret (o, e)
}


// ctree with the extended controls: w the case weights per row (empty = 1; the weighted sums are accumulated per row as libcoin does, so exact ties between cut points fall as in R; a zero weight drops the row from growing
// while it stays in x for the intersplit neighbour), xo the criterion options; mincrit is mincriterion (1 - alpha unless testtype is Teststatistic)
fn ctree_x(a: *mem.Arena, x: []const f64, n: usize, p: usize, nl: []const usize, y: []const f64, yl: usize, minsplit: usize, minbucket: usize, minprob: f64, mincrit: f64, bonf: bool, maxdepth: usize, stump: bool, inter: bool, w: []const f64, xo: *const Xo) -> (Out, err) {
    let (o, e) = ctree_xs(a, x, n, p, nl, y, yl, minsplit, minbucket, minprob, mincrit, bonf, maxdepth, stump, inter, w, xo, 1i64)
    ret (o, e)
}

// ctree_x with R's set.seed(seed) in force: the maximum statistic's p values draw from the stream
fn ctree_xs(a: *mem.Arena, x: []const f64, n: usize, p: usize, nl: []const usize, y: []const f64, yl: usize, minsplit: usize, minbucket: usize, minprob: f64, mincrit: f64, bonf: bool, maxdepth: usize, stump: bool, inter: bool, w: []const f64, xo: *const Xo, seed: i64) -> (Out, err) {
    var rg: rr.Rng = zero
    rr.seed(&rg, seed)
    var none: []const usize = zero
    let xo2 = Xo { statcrit: xo.statcrit, maxst: xo.maxst, setlog: xo.setlog, logmin: xo.logmin, ord: xo.ord, w: w, nres: xo.nres, spl: xo.spl, mtry: xo.mtry, maxvar: xo.maxvar }
    let (o, e) = ctree_core(a, x, n, p, nl, y, yl, minsplit, minbucket, minprob, 1.0f64 - mincrit, bonf, maxdepth, stump, inter, 0usize, &rg, none, &xo2)
    ret (o, e)
}

// ctree_xs that also returns the node of every training row as partykit stores it at fit time: fitted_node on all rows with the stream where the growing left it (rows that meet an unseen level draw their kid)
fn ctree_xsf(a: *mem.Arena, x: []const f64, n: usize, p: usize, nl: []const usize, y: []const f64, yl: usize, minsplit: usize, minbucket: usize, minprob: f64, mincrit: f64, bonf: bool, maxdepth: usize, stump: bool, inter: bool, w: []const f64, xo: *const Xo, seed: i64, fit: []usize) -> (Out, err) {
    var rg: rr.Rng = zero
    rr.seed(&rg, seed)
    var none: []const usize = zero
    let xo2 = Xo { statcrit: xo.statcrit, maxst: xo.maxst, setlog: xo.setlog, logmin: xo.logmin, ord: xo.ord, w: w, nres: xo.nres, spl: xo.spl, mtry: xo.mtry, maxvar: xo.maxvar }
    let (o, e) = ctree_core(a, x, n, p, nl, y, yl, minsplit, minbucket, minprob, 1.0f64 - mincrit, bonf, maxdepth, stump, inter, 0usize, &rg, none, &xo2)
    if e != ok { ret (o, e) }
    let (allrows, e2) = mem.alloc[usize](a, n)
    if e2 != ok { ret (o, e2) }
    var i = 0usize
    while i < n {
        allrows[i] = i
        i += 1usize
    }
    let ef = fitted_rec(a, &o, nl, x, n, 1usize, allrows, fit, &rg)
    ret (o, ef)
}

// ctree grown on the rows ini (all rows when empty) with mtry variables drawn from rg at every node (0 = all), as cforest grows each tree
fn ctree_core(a: *mem.Arena, x: []const f64, n: usize, p: usize, nl: []const usize, y: []const f64, yl: usize, minsplit: usize, minbucket: usize, minprob: f64, alpha: f64, bonf: bool, maxdepth: usize, stump: bool, inter: bool, mtry: usize, rg: *rr.Rng, ini: []const usize, xo: *const Xo) -> (Out, err) {
    var o: Out = zero
    var q = 1usize
    if yl > 2usize { q = yl }
    let (h, e1) = mem.alloc[f64](a, n * q)
    if e1 != ok { ret (o, e1) }
    var i = 0usize
    while i < n {
        if yl == 0usize {
            h[i] = y[i]
        } else {
            var k = 0usize
            while k < q {
                h[k * n + i] = 0.0f64
                k += 1usize
            }
            if yl == 2usize {
                if y[i] > 0.5f64 { h[i] = 1.0f64 }
            } else {
                h[usize(y[i]) * n + i] = 1.0f64
            }
        }
        i += 1usize
    }
    var ml = 1usize
    var j = 0usize
    while j < p {
        if nl[j] > ml { ml = nl[j] }
        j += 1usize
    }
    let cap = 2usize * n + 2usize
    let (vr, e2) = mem.alloc[i64](a, cap)
    let (brk, e3) = mem.alloc[f64](a, cap)
    let (k1, e4) = mem.alloc[i64](a, cap)
    let (k2, e5) = mem.alloc[i64](a, cap)
    let (nb, e6) = mem.alloc[f64](a, cap)
    let (pv, e7) = mem.alloc[f64](a, cap)
    let (stv, e7b) = mem.alloc[f64](a, cap)
    if e7b != ok { ret (o, mem.Full) }
    o.stat = stv
    let (ft, e8) = mem.alloc[f64](a, cap)
    let (lm, e9) = mem.alloc[i64](a, cap * ml)
    let (p1, e10) = mem.alloc[f64](a, cap)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret (o, mem.Full) }
    i = 0usize
    while i < cap {
        k1[i] = 0i64
        k2[i] = 0i64
        brk[i] = 0.0f64
        p1[i] = 0.0f64
        i += 1usize
    }
    o.vr = vr
    o.brk = brk
    o.kid1 = k1
    o.kid2 = k2
    o.nobs = nb
    o.pval = pv
    o.fit = ft
    o.lmap = lm
    o.prob1 = p1
    o.maxlev = ml
    o.count = 0usize
    let (svb, e15) = mem.alloc[bool](a, p)
    if e15 != ok { ret (o, e15) }
    i = 0usize
    while i < p {
        svb[i] = false
        i += 1usize
    }
    o.sv = svb
    let (wts, e12) = mem.alloc[f64](a, n)
    if e12 != ok { ret (o, e12) }
    i = 0usize
    while i < n {
        wts[i] = 1.0f64
        if xo.w.len > 0usize { wts[i] = xo.w[i] }
        i += 1usize
    }
    var lat: mvt.Lat = zero
    if xo.maxst { mvt.load_lattice(&lat) }
    let c = Ctx { x: x, n: n, p: p, nl: nl, h: h, q: q, yl: yl, y: y, maxst: xo.maxst, wt: wts, rg: rg, lat: &lat, nres: xo.nres, spl: xo.spl }
    var mt0 = mtry
    if xo.mtry > 0usize { mt0 = xo.mtry }
    var lgm = math.log[f64](1.0f64 - alpha)
    if xo.setlog { lgm = xo.logmin }
    let ctl = Ctl { minsplit: minsplit, minbucket: minbucket, minprob: minprob, logmin: lgm, bonf: bonf, maxdepth: maxdepth, stump: stump, splittry: 2usize, mtry: mt0, maxvar: xo.maxvar, inter: inter, statcrit: xo.statcrit, ord: xo.ord }
    var ns = 0usize
    i = 0usize
    while i < n {
        if wts[i] > 0.0f64 { ns += 1usize }
        i += 1usize
    }
    if ini.len > 0usize { ns = ini.len }
    let (sub, e11) = mem.alloc[usize](a, ns)
    if e11 != ok { ret (o, e11) }
    var si = 0usize
    i = 0usize
    while i < n && ini.len == 0usize {
        if wts[i] > 0.0f64 {
            sub[si] = i
            si += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < ini.len {
        sub[i] = ini[i]
        i += 1usize
    }
    let (mx, eg) = grow(a, &c, &ctl, &o, rg, sub, 1usize, 0usize)
    ret (o, eg)
}

// the node id (1-based) of observation i of x (nr rows by p columns); nl as given to ctree
fn predict_node(o: *const Out, nl: []const usize, x: []const f64, nr: usize, i: usize) -> usize {
    var id = 1usize
    while o.vr[id - 1usize] != 0i64 {
        let k = id - 1usize
        let j = usize(o.vr[k] - 1i64)
        let xv = x[j * nr + i]
        var left = false
        if nl[j] == 0usize {
            left = xv <= o.brk[k]
        } else {
            left = o.lmap[k * o.maxlev + usize(xv)] == 0i64
        }
        if left { id = usize(o.kid1[k]) } else { id = usize(o.kid2[k]) }
    }
    ret id
}

// partykit's fitted_node: the node of each row in obs (indices into x, nr rows), walking down with the rows of a node together. A level the node never saw has no kid: the rows with one draw their kid
// together with sample(1:2, k, prob = c(share of kid 1, share of kid 2), replace = TRUE), and the kids are then visited in the order they first appear among the rows, as R does, so the draws come in R's order
fn fitted_rec(a: *mem.Arena, o: *const Out, nl: []const usize, x: []const f64, nr: usize, id: usize, obs: []const usize, out: []usize, rg: *rr.Rng) -> err {
    if obs.len == 0usize { ret ok }
    let k = id - 1usize
    if o.vr[k] == 0i64 {
        var t = 0usize
        while t < obs.len {
            out[obs[t]] = id
            t += 1usize
        }
        ret ok
    }
    let j = usize(o.vr[k] - 1i64)
    let (nx, e1) = mem.alloc[usize](a, obs.len)
    if e1 != ok { ret e1 }
    var nna = 0usize
    var i = 0usize
    while i < obs.len {
        let xv = x[j * nr + obs[i]]
        var kid = 0usize
        if nl[j] == 0usize {
            if xv <= o.brk[k] { kid = 1usize } else { kid = 2usize }
        } else {
            let d = o.lmap[k * o.maxlev + usize(xv)]
            if d == 0i64 { kid = 1usize }
            if d == 1i64 { kid = 2usize }
        }
        if kid == 0usize { nna += 1usize }
        nx[i] = kid
        i += 1usize
    }
    if nna > 0usize {
        let (pp, e2) = mem.alloc[f64](a, 2usize)
        let (pm, e3) = mem.alloc[usize](a, 2usize)
        if e2 != ok || e3 != ok { ret mem.Full }
        pp[0usize] = o.prob1[k]
        pp[1usize] = 1.0f64 - o.prob1[k]
        pm[0usize] = 1usize
        pm[1usize] = 2usize
        revsort(pp, pm, 2usize)
        pp[1usize] += pp[0usize]
        i = 0usize
        while i < obs.len {
            if nx[i] == 0usize {
                let ru = rr.unif(rg)
                var jj = 0usize
                if !(ru <= pp[0usize]) { jj = 1usize }
                nx[i] = pm[jj]
            }
            i += 1usize
        }
    }
    let first = nx[0usize]
    let second = 3usize - first
    i = 0usize
    var which = 0usize
    while which < 2usize {
        var kid = first
        if which == 1usize { kid = second }
        var cnt = 0usize
        i = 0usize
        while i < obs.len {
            if nx[i] == kid { cnt += 1usize }
            i += 1usize
        }
        if cnt > 0usize {
            let (sub, e4) = mem.alloc[usize](a, cnt)
            if e4 != ok { ret mem.Full }
            var q = 0usize
            i = 0usize
            while i < obs.len {
                if nx[i] == kid {
                    sub[q] = obs[i]
                    q += 1usize
                }
                i += 1usize
            }
            var child = o.kid1[k]
            if kid == 2usize { child = o.kid2[k] }
            let e5 = fitted_rec(a, o, nl, x, nr, usize(child), sub, out, rg)
            if e5 != ok { ret e5 }
        }
        which += 1usize
    }
    ret ok
}

// cforest (numeric predictors): ntree trees on subsamples of floor(0.632 n) rows (all drawn first, sample.int without replacement) then grown in order with mtry variables per node
// from one stream seeded as set.seed(seed). pred[j] is the forest prediction for row j of xnew (nn rows): the weighted mean of y, or the class code with the largest weight,
// the weights being the in-bag rows sharing a leaf with the row, each tree's weights scaled to sum to one
fn cforest(a: *mem.Arena, x: []const f64, n: usize, p: usize, nl: []const usize, y: []const f64, yl: usize, ntree: usize, mtry: usize, minsplit: usize, minbucket: usize, minprob: f64, seed: i64, xnew: []const f64, nn: usize, pred: []f64) -> err {
    var rg: rr.Rng = zero
    var none3: []const bool = zero
    var none5: []const f64 = zero
    let xo0 = Xo { statcrit: false, maxst: false, setlog: false, logmin: 0.0f64, ord: none3, w: none5, nres: 0usize, spl: false, mtry: 0usize, maxvar: 1000000usize }
    rr.seed(&rg, seed)
    let size = usize(math.floor[f64](f64(n) * 0.632f64))
    let (rw, e1) = mem.alloc[usize](a, ntree * size)
    if e1 != ok { ret e1 }
    var b = 0usize
    while b < ntree {
        let (s, es) = rr.sample_int(a, &rg, i64(n), i64(size), false)
        if es != ok { ret es }
        var q = 0usize
        while q < size {
            rw[b * size + q] = usize(s[q]) - 1usize
            q += 1usize
        }
        var i = 1usize
        while i < size {
            let v = rw[b * size + i]
            var j = i
            while j > 0usize && rw[b * size + j - 1usize] > v {
                rw[b * size + j] = rw[b * size + j - 1usize]
                j -= 1usize
            }
            rw[b * size + j] = v
            i += 1usize
        }
        b += 1usize
    }
    let (acc, e2) = mem.alloc[f64](a, nn * (yl + 2usize))
    let (inbag, e3) = mem.alloc[bool](a, n)
    let (tn, e4) = mem.alloc[usize](a, n)
    if e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var t = 0usize
    while t < nn * (yl + 2usize) {
        acc[t] = 0.0f64
        t += 1usize
    }
    // all trees are grown first; then, as predict.cforest does, every tree's fitted nodes of the training rows (out-of-bag rows may draw a kid at a level the node never saw), then of the new rows
    let (outs, e5) = mem.alloc[Out](a, ntree)
    let (tnall, e6) = mem.alloc[usize](a, ntree * n)
    let (nnall, e7) = mem.alloc[usize](a, ntree * nn)
    let (allrows, e8) = mem.alloc[usize](a, n + nn)
    if e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    var r0 = 0usize
    while r0 < n + nn {
        allrows[r0] = r0
        if r0 >= n { allrows[r0] = r0 - n }
        r0 += 1usize
    }
    b = 0usize
    while b < ntree {
        let ini = rw[b * size..b * size + size]
        let (o, eo) = ctree_core(a, x, n, p, nl, y, yl, minsplit, minbucket, minprob, 1.0f64, false, 1000000usize, false, false, mtry, &rg, ini, &xo0)
        if eo != ok { ret eo }
        outs[b] = o
        b += 1usize
    }
    b = 0usize
    while b < ntree {
        let ef = fitted_rec(a, &outs[b], nl, x, n, 1usize, allrows[0usize..n], tnall[b * n..b * n + n], &rg)
        if ef != ok { ret ef }
        b += 1usize
    }
    b = 0usize
    while b < ntree {
        let ef = fitted_rec(a, &outs[b], nl, xnew, nn, 1usize, allrows[n..n + nn], nnall[b * nn..b * nn + nn], &rg)
        if ef != ok { ret ef }
        b += 1usize
    }
    b = 0usize
    while b < ntree {
        let ini = rw[b * size..b * size + size]
        var i = 0usize
        while i < n {
            inbag[i] = false
            tn[i] = tnall[b * n + i]
            i += 1usize
        }
        i = 0usize
        while i < size {
            inbag[ini[i]] = true
            i += 1usize
        }
        var j = 0usize
        while j < nn {
            let nd = nnall[b * nn + j]
            var sw = 0.0f64
            i = 0usize
            while i < n {
                if inbag[i] && tn[i] == nd { sw += 1.0f64 }
                i += 1usize
            }
            i = 0usize
            while i < n {
                if inbag[i] && tn[i] == nd {
                    let w = 1.0f64 / sw
                    if yl == 0usize {
                        acc[j * 2usize] += w
                        acc[j * 2usize + 1usize] += w * y[i]
                    } else {
                        acc[j * (yl + 2usize) + 2usize + usize(y[i])] += w
                    }
                }
                i += 1usize
            }
            j += 1usize
        }
        b += 1usize
    }
    var j = 0usize
    while j < nn {
        if yl == 0usize {
            pred[j] = acc[j * 2usize + 1usize] / acc[j * 2usize]
        } else {
            var bestc = 0usize
            var c2 = 1usize
            while c2 < yl {
                if acc[j * (yl + 2usize) + 2usize + c2] > acc[j * (yl + 2usize) + 2usize + bestc] { bestc = c2 }
                c2 += 1usize
            }
            pred[j] = f64(bestc)
        }
        j += 1usize
    }
    ret ok
}
