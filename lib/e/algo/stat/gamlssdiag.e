// R gamlss diagnostics and centiles on a fitted model's residuals and fitted parameters: the residual summary of plot.gamlss, the worm plot data of wp()
// (cubic fit of the deviations, its panels and the confidence band), Q.stats() and centiles() with centiles.pred() for the standard families of e.algo.stat.gamlssfit.

use e.algo.stat.gamlssfit as gf
use e.algo.stat.massrlm as mr
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

// the stable ascending order of x, as R order()
fn order_asc(x: []const f64, ord: []usize) {
    var i = 0usize
    while i < x.len {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < x.len {
        let v = ord[i]
        var k = i
        while k > 0usize && x[ord[k - 1usize]] > x[v] {
            ord[k] = ord[k - 1usize]
            k -= 1usize
        }
        ord[k] = v
        i += 1usize
    }
}

// qqnorm(y)$x: qnorm(ppoints(n))[order(order(y))]
fn qq_theory(a: *mem.Arena, y: []const f64, out: []f64) -> err {
    let n = y.len
    let (ord, e1) = mem.alloc[usize](a, n + 1usize)
    if e1 != ok { ret e1 }
    order_asc(y, ord)
    var aa = 0.5f64
    if n <= 10usize { aa = 0.375f64 }
    var r = 0usize
    while r < n {
        out[ord[r]] = dist.qnorm((f64(r + 1usize) - aa) / (f64(n) + 1.0f64 - 2.0f64 * aa), 0.0f64, 1.0f64, true, false)
        r += 1usize
    }
    ret ok
}

// plot.gamlss summaries: out = mean, var, coef of skewness, coef of kurtosis, Filliben correlation; nobs is sum(w)
fn summary(a: *mem.Arena, r: []const f64, nobs: f64, out: []f64) -> err {
    let n = r.len
    let (q, e1) = mem.alloc[f64](a, n + 1usize)
    if e1 != ok { ret e1 }
    let e2 = qq_theory(a, r, q)
    if e2 != ok { ret e2 }
    let m1 = gf.mean_of(r, n)
    let m2 = gf.var_of(r, n)
    var s3 = 0.0f64
    var s4 = 0.0f64
    var i = 0usize
    while i < n {
        let d = r[i] - m1
        s3 += d * d * d
        s4 += d * d * d * d
        i += 1usize
    }
    let m3 = s3 / nobs
    let m4 = s4 / nobs
    let b1 = m3 * m3 / (m2 * m2 * m2)
    var sg = 1.0f64
    if m3 < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    if m3 == 0.0f64 { sg = 0.0f64 }
    out[0usize] = m1
    out[1usize] = m2
    out[2usize] = sg * math.sqrt[f64](math.abs[f64](b1))
    out[3usize] = m4 / (m2 * m2)
    let mq = gf.mean_of(q, n)
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    i = 0usize
    while i < n {
        sxy += (r[i] - m1) * (q[i] - mq)
        sxx += (r[i] - m1) * (r[i] - m1)
        syy += (q[i] - mq) * (q[i] - mq)
        i += 1usize
    }
    out[4usize] = sxy / (math.sqrt[f64](sxx) * math.sqrt[f64](syy))
    ret ok
}

// the cubic least squares fit of the worm plot deviations qq$y - qq$x on qq$x: coef gets the four coefficients
fn worm_cubic(a: *mem.Arena, y: []const f64, coef: []f64) -> err {
    let n = y.len
    let (q, e1) = mem.alloc[f64](a, n + 1usize)
    let (xm, e2) = mem.alloc[f64](a, 4usize * n + 1usize)
    let (dv, e3) = mem.alloc[f64](a, n + 1usize)
    let (w1, e4) = mem.alloc[f64](a, n + 1usize)
    let (rs, e5) = mem.alloc[f64](a, n + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    let e6 = qq_theory(a, y, q)
    if e6 != ok { ret e6 }
    var i = 0usize
    while i < n {
        xm[i] = 1.0f64
        xm[n + i] = q[i]
        xm[2usize * n + i] = q[i] * q[i]
        xm[3usize * n + i] = math.pow[f64](q[i], 3.0f64)
        dv[i] = y[i] - q[i]
        w1[i] = 1.0f64
        i += 1usize
    }
    ret mr.wfit(a, xm, n, 4usize, dv, w1, coef, rs)
}

// the lower limit of the 95% band of the worm plot at z for n points (the upper limit is its negative)
fn worm_band(z: f64, n: usize) -> f64 {
    let p = dist.pnorm(z, 0.0f64, 1.0f64, true, false)
    let se = (1.0f64 / dist.dnorm(z, 0.0f64, 1.0f64, false)) * math.sqrt[f64](p * (1.0f64 - p) / f64(n))
    ret dist.qnorm(0.025f64, 0.0f64, 1.0f64, true, false) * se
}

// graphics::co.intervals(x, number, overlap): iv gets the rows lo, hi one after the other, the answer is the number of rows
fn co_intervals(a: *mem.Arena, x: []const f64, number: usize, overlap: f64, iv: []f64) -> (usize, err) {
    let n = x.len
    let (xs, e1) = mem.alloc[f64](a, n + 1usize)
    let (ord, e2) = mem.alloc[usize](a, n + 1usize)
    if e1 != ok || e2 != ok { ret (0usize, mem.Full) }
    order_asc(x, ord)
    var i = 0usize
    while i < n {
        xs[i] = x[ord[i]]
        i += 1usize
    }
    let r = f64(n) / (f64(number) * (1.0f64 - overlap) + overlap)
    var jump = 0.0f64
    var have = false
    i = 1usize
    while i < n {
        let d = xs[i] - xs[i - 1usize]
        if d > 0.0f64 && (!have || d < jump) {
            jump = d
            have = true
        }
        i += 1usize
    }
    let eps = 0.5f64 * jump
    var rows = 0usize
    var plo = 0.0f64
    var phi = 0.0f64
    var k = 0usize
    while k < number {
        let ii = f64(k) * (1.0f64 - overlap) * r
        let lo = xs[usize(nm.rint(1.0f64 + ii)) - 1usize]
        let hi = xs[usize(nm.rint(r + ii)) - 1usize]
        if k == 0usize || lo - plo > 0.0f64 || hi - phi > 0.0f64 {
            iv[2usize * rows] = lo - eps
            iv[2usize * rows + 1usize] = hi + eps
            rows += 1usize
        }
        plo = lo
        phi = hi
        k += 1usize
    }
    ret (rows, ok)
}

fn check_overlap(iv: []f64, rows: usize) {
    var i = 0usize
    while i + 1usize < rows {
        if !(math.abs[f64](iv[2usize * i + 1usize] - iv[2usize * (i + 1usize)]) < 0.0001f64) { iv[2usize * (i + 1usize)] = iv[2usize * i + 1usize] }
        i += 1usize
    }
}

// the intervals of explicit cut points: the worm plot (kind 0) widens the last by 2 extra and shortens each upper end by extra, Q.stats (kind 1) cuts at the points
fn cut_intervals(x: []const f64, cuts: []const f64, kind: usize, iv: []f64) -> usize {
    var mn = x[0usize]
    var mx = x[0usize]
    var i = 1usize
    while i < x.len {
        if x[i] < mn { mn = x[i] }
        if x[i] > mx { mx = x[i] }
        i += 1usize
    }
    var extra = 0.0f64
    if kind == 0usize { extra = (mx - mn) / 100000.0f64 }
    let rows = cuts.len + 1usize
    var j = 0usize
    while j < rows {
        var lo = mn
        if j > 0usize { lo = cuts[j - 1usize] }
        var hi = mx + 2.0f64 * extra
        if j < cuts.len { hi = cuts[j] }
        iv[2usize * j] = lo
        iv[2usize * j + 1usize] = hi - extra
        j += 1usize
    }
    ret rows
}

// wp(object, xvar = x, ...): the cubic coefficients (4 per row) of each interval (both ends inclusive)
fn wp_panels(a: *mem.Arena, r: []const f64, xvar: []const f64, iv: []const f64, rows: usize, coefs: []f64) -> err {
    let n = r.len
    let (sub, e1) = mem.alloc[f64](a, n + 1usize)
    if e1 != ok { ret e1 }
    var p = 0usize
    while p < rows {
        var m = 0usize
        var i = 0usize
        while i < n {
            if iv[2usize * p] <= xvar[i] && xvar[i] <= iv[2usize * p + 1usize] {
                sub[m] = r[i]
                m += 1usize
            }
            i += 1usize
        }
        let e2 = worm_cubic(a, sub[0usize..m], coefs[4usize * p..4usize * p + 4usize])
        if e2 != ok { ret e2 }
        p += 1usize
    }
    ret ok
}

// Q.stats Qtest: out = Q1, Q2, Q3, Q4, z1, z2, z3, z4, AgostinoK2, N
fn qtest(x: []const f64, out: []f64) {
    let nn = x.len
    let n = f64(nn)
    let mx = gf.mean_of(x, nn)
    var s2 = 0.0f64
    var s3 = 0.0f64
    var s4 = 0.0f64
    var i = 0usize
    while i < nn {
        let d = x[i] - mx
        s2 += d * d
        s3 += math.pow[f64](d, 3.0f64)
        s4 += math.pow[f64](d, 4.0f64)
        i += 1usize
    }
    let m2 = s2 / n
    let m3 = s3 / n
    let m4 = s4 / n
    let sqrtb1 = m3 / math.pow[f64](m2, 1.5f64)
    let yval = sqrtb1 * math.sqrt[f64]((n + 1.0f64) * (n + 3.0f64) / (6.0f64 * (n - 2.0f64)))
    let b2b1 = 3.0f64 * (n * n + 27.0f64 * n - 70.0f64) * (n + 1.0f64) * (n + 3.0f64) / ((n - 2.0f64) * (n + 5.0f64) * (n + 7.0f64) * (n + 9.0f64))
    let wsq = (0.0f64 - 1.0f64) + math.sqrt[f64](2.0f64 * b2b1 - 2.0f64)
    let delta = 1.0f64 / math.sqrt[f64](0.5f64 * math.log[f64](wsq))
    let alpha = math.sqrt[f64](2.0f64 / (wsq - 1.0f64))
    let yalpha = yval / alpha
    let zb1 = delta * math.log[f64](yalpha + math.sqrt[f64](yalpha * yalpha + 1.0f64))
    let b2 = m4 / (m2 * m2)
    let meanb2 = 3.0f64 * (n - 1.0f64) / (n + 1.0f64)
    let varb2 = 24.0f64 * n * (n - 2.0f64) * (n - 3.0f64) / ((n + 1.0f64) * (n + 1.0f64) * (n + 3.0f64) * (n + 5.0f64))
    let xval = (b2 - meanb2) / math.sqrt[f64](varb2)
    var sb1b2 = 6.0f64 * (n * n - 5.0f64 * n + 2.0f64) / ((n + 7.0f64) * (n + 9.0f64))
    sb1b2 = sb1b2 * math.sqrt[f64](6.0f64 * (n + 3.0f64) * (n + 5.0f64) / (n * (n - 2.0f64) * (n - 3.0f64)))
    let isb1b2 = 1.0f64 / sb1b2
    let aa = 6.0f64 + 8.0f64 * isb1b2 * (2.0f64 * isb1b2 + math.sqrt[f64](1.0f64 + 4.0f64 * isb1b2 * isb1b2))
    var zb2 = (1.0f64 - 2.0f64 / (9.0f64 * aa)) - math.pow[f64]((1.0f64 - (2.0f64 / aa)) / (1.0f64 + xval * math.sqrt[f64](2.0f64 / (aa - 4.0f64))), 1.0f64 / 3.0f64)
    zb2 = zb2 / math.sqrt[f64](2.0f64 / (9.0f64 * aa))
    let k2 = zb1 * zb1 + zb2 * zb2
    let sdy = math.sqrt[f64](m2)
    let t23 = math.pow[f64](sdy, 2.0f64 / 3.0f64) - (1.0f64 - (2.0f64 / (9.0f64 * n - 9.0f64)))
    let q2 = t23 * t23 / (2.0f64 / (9.0f64 * n - 9.0f64))
    var sg = 1.0f64
    if t23 < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    if t23 == 0.0f64 { sg = 0.0f64 }
    out[0usize] = n * (mx * mx)
    out[1usize] = q2
    out[2usize] = zb1 * zb1
    out[3usize] = zb2 * zb2
    out[4usize] = math.sqrt[f64](n) * mx
    out[5usize] = math.sqrt[f64](q2) * sg
    out[6usize] = zb1
    out[7usize] = zb2
    out[8usize] = k2
    out[9usize] = n
}

// Q.stats(object, xvar): iv holds the intervals; df is location, scale, skewness, kurtosis. zm and xm get (rows + 3) by 6 cells row by row:
// the groups (Z1..Z4, K2, N or Q1..Q4, K2, N), the totals, the degrees of freedom and the p-values
fn qstats(a: *mem.Arena, r: []const f64, xvar: []const f64, iv: []const f64, rows: usize, df: []const f64, zm: []f64, xm: []f64) -> err {
    let n = r.len
    let (ord, e3) = mem.alloc[usize](a, n + 1usize)
    let (res, e4) = mem.alloc[f64](a, 10usize)
    let (ox, e1) = mem.alloc[f64](a, n + 1usize)
    if e1 != ok || e3 != ok || e4 != ok { ret mem.Full }
    order_asc(xvar, ord)
    var i = 0usize
    while i < n {
        ox[i] = xvar[ord[i]]
        i += 1usize
    }
    var tot: [6]f64 = zero
    var g = 0usize
    while g < rows {
        // cut(x, c(lower ends, last upper end), include.lowest = TRUE): the groups are (b[g], b[g + 1]]
        let lo = iv[2usize * g]
        var hi = iv[2usize * (rows - 1usize) + 1usize]
        if g + 1usize < rows { hi = iv[2usize * (g + 1usize)] }
        var m = 0usize
        i = 0usize
        while i < n {
            var inside = ox[i] > lo && ox[i] <= hi
            if g == 0usize && ox[i] == lo { inside = true }
            if inside { m += 1usize }
            i += 1usize
        }
        let (sub, e5) = mem.alloc[f64](a, m + 1usize)
        if e5 != ok { ret e5 }
        var k = 0usize
        i = 0usize
        while i < n {
            var inside = ox[i] > lo && ox[i] <= hi
            if g == 0usize && ox[i] == lo { inside = true }
            if inside {
                sub[k] = r[ord[i]]
                k += 1usize
            }
            i += 1usize
        }
        qtest(sub[0usize..m], res)
        var c = 0usize
        while c < 4usize {
            zm[g * 6usize + c] = res[4usize + c]
            xm[g * 6usize + c] = res[c]
            c += 1usize
        }
        zm[g * 6usize + 4usize] = res[8usize]
        xm[g * 6usize + 4usize] = res[8usize]
        zm[g * 6usize + 5usize] = res[9usize]
        xm[g * 6usize + 5usize] = res[9usize]
        tot[0usize] += res[0usize]
        tot[1usize] += res[1usize]
        tot[2usize] += res[2usize]
        tot[3usize] += res[3usize]
        tot[4usize] += res[8usize]
        tot[5usize] += res[9usize]
        g += 1usize
    }
    let h = f64(rows)
    var dfs: [6]f64 = zero
    dfs[0usize] = h - df[0usize]
    dfs[1usize] = h - df[1usize]
    dfs[2usize] = h - df[2usize]
    dfs[3usize] = h - df[3usize]
    dfs[4usize] = dfs[2usize] + dfs[3usize]
    var c = 0usize
    while c < 6usize {
        var pv = 0.0f64
        if c < 5usize { pv = nm.pchisq(tot[c], dfs[c], false, false) }
        zm[rows * 6usize + c] = tot[c]
        xm[rows * 6usize + c] = tot[c]
        zm[(rows + 1usize) * 6usize + c] = dfs[c]
        xm[(rows + 1usize) * 6usize + c] = dfs[c]
        zm[(rows + 2usize) * 6usize + c] = pv
        xm[(rows + 2usize) * 6usize + c] = pv
        c += 1usize
    }
    zm[(rows + 1usize) * 6usize + 5usize] = 0.0f64
    xm[(rows + 1usize) * 6usize + 5usize] = 0.0f64
    ret ok
}

// the parameters of the fitted model at the sorted x: par is k * n + i as gf.Out.par
fn centile_curve(fam: usize, par: []const f64, n: usize, p: f64, ord: []const usize, j: usize) -> f64 {
    let i = ord[j]
    ret gf.centile(fam, p, par[i], par[n + i], par[2usize * n + i])
}

// centiles(object, xvar, cent, save = TRUE): the percentage of cases below the curve of the centile p (in percent)
fn centile_below(fam: usize, par: []const f64, y: []const f64, n: usize, p: f64, ord: []const usize) -> f64 {
    var above = 0usize
    var j = 0usize
    while j < n {
        let ll = centile_curve(fam, par, n, p / 100.0f64, ord, j)
        if y[ord[j]] > ll { above += 1usize }
        j += 1usize
    }
    ret (1.0f64 - f64(above) / f64(n)) * 100.0f64
}

// centiles.pred for a model whose parameters are linear in x: the parameter k at the new x is the inverse link of coef[0] + coef[1] x (one coefficient: constant)
fn predict_par(coef: []const f64, ncol: usize, link: usize, x: f64) -> f64 {
    var eta = coef[0usize]
    if ncol > 1usize { eta += coef[1usize] * x }
    if link == 5usize { ret math.exp[f64](eta) }
    ret eta
}
