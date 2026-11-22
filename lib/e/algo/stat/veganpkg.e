// R vegan on a sites-by-species count matrix (row-major): the diversity indices (Shannon, Simpson, inverse Simpson, Pielou), richness, rarefied richness, Chao1, and the vegdist dissimilarities euclidean, manhattan, bray, kulczynski, canberra, gower, horn, morisita and jaccard (quantitative and binary).
//
// Not here: ordination, ACE, Fisher alpha, the remaining vegdist methods, permutation tests and the community-ecology tests.

use e.algo.linalg.decomp as dc
use e.algo.linalg.lapack_syevr as sy
use e.math
use e.math.nmath as nm
use e.mem

// diversity of row r: out = Shannon (natural log), Simpson 1 - sum p^2, inverse Simpson, Pielou evenness, richness, Chao1 (bias-corrected)
fn diversity(m: []const f64, nr: usize, nc: usize, r: usize, out: []f64) {
    var tot = 0.0f64
    var j = 0usize
    while j < nc {
        tot += m[r * nc + j]
        j += 1usize
    }
    var h = 0.0f64
    var sp = 0.0f64
    var s = 0.0f64
    var f1 = 0.0f64
    var f2 = 0.0f64
    j = 0usize
    while j < nc {
        let x = m[r * nc + j]
        if x > 0.0f64 {
            let p = x / tot
            h -= p * math.log[f64](p)
            sp += p * p
            s += 1.0f64
            if x == 1.0f64 { f1 += 1.0f64 }
            if x == 2.0f64 { f2 += 1.0f64 }
        }
        j += 1usize
    }
    out[0usize] = h
    out[1usize] = 1.0f64 - sp
    out[2usize] = 1.0f64 / sp
    out[3usize] = h / math.log[f64](s)
    out[4usize] = s
    out[5usize] = s + f1 * (f1 - 1.0f64) / (2.0f64 * (f2 + 1.0f64))
}

// vegan::estimateR's abundance-based rows for row r: out = S.obs, S.chao1, se.chao1, S.ACE. The rare
// species are the ones with abundance at most 10 (vegan's threshold), and a[i] counts the species seen
// exactly i times. se.ACE needs the delta-method gradient over the ten abundance classes and is not ported.
fn estimate_r(m: []const f64, nc: usize, r: usize, out: []f64) {
    var a: [11]f64 = zero
    var s_obs = 0.0f64
    var s_rare = 0.0f64
    var s_abund = 0.0f64
    var n_rare = 0.0f64
    var j = 0usize
    while j < nc {
        let x = m[r * nc + j]
        if x > 0.0f64 {
            s_obs += 1.0f64
            if x <= 10.0f64 {
                s_rare += 1.0f64
                n_rare += x
                let k = usize(x)
                if k <= 10usize { a[k] += 1.0f64 }
            } else {
                s_abund += 1.0f64
            }
        }
        j += 1usize
    }
    // Chao1 with the bias correction (SSC = 1)
    let a1 = a[1usize]
    let a2 = a[2usize]
    let chao1 = s_obs + a1 * (a1 - 1.0f64) / (a2 + 1.0f64) / 2.0f64
    // its standard error, vegan's closed form
    let inner1 = (0.0f64 - (a2 * a2) + (0.0f64 - 2.0f64 * a2 - a1) * a1) * a1
    let inner2 = (0.0f64 - 1.0f64 + (0.0f64 - 4.0f64 + (0.0f64 - 5.0f64 - 2.0f64 * a2) * a2) * a2 +
        (0.0f64 - 2.0f64 + (0.0f64 - 1.0f64 + (2.0f64 * a2 + 2.0f64) * a2) * a2 +
            (4.0f64 + (6.0f64 + 4.0f64 * a2) * a2 + a1 * a2) * a1) * a1) * chao1
    var se_chao1 = 0.0f64 / 0.0f64
    if chao1 != 0.0f64 {
        se_chao1 = a1 * (inner1 + inner2) / 4.0f64 / math.pow[f64](a2 + 1.0f64, 4.0f64) / chao1
        // a row with no singletons has a variance of exactly zero, which is a real answer and not a failure
        if se_chao1 < 0.0f64 { se_chao1 = 0.0f64 / 0.0f64 } else { se_chao1 = math.sqrt[f64](se_chao1) }
    }
    // ACE, with C.ace the sample coverage of the rare species
    var c_ace = 0.0f64 / 0.0f64
    var s_ace = 0.0f64 / 0.0f64
    if n_rare > 1.0f64 {
        c_ace = 1.0f64 - a1 / n_rare
        var sum_i = 0.0f64
        var i = 1usize
        while i <= 10usize {
            sum_i += f64(i) * f64(i - 1usize) * a[i]
            i += 1usize
        }
        var gam = sum_i * s_rare / (c_ace * n_rare * (n_rare - 1.0f64)) - 1.0f64
        if gam < 0.0f64 { gam = 0.0f64 }
        s_ace = s_abund + s_rare / c_ace + gam * a1 / c_ace
    }
    out[0usize] = s_obs
    out[1usize] = chao1
    out[2usize] = se_chao1
    out[3usize] = s_ace
}

// vegan::adonis2's R^2 for a single grouping factor (the permutation test needs R's RNG and is not produced
// here): with the Bray-Curtis distances Gower-centred by G_ij = -0.5 (D^2_ij - rowmean - colmean + grandmean),
// SS_total is the trace of G and SS_model is sum_k (1/n_k) of the sum over the pairs inside group k, so
// R^2 = SS_model / SS_total. group holds one class code per site.
fn adonis_r2(a: *mem.Arena, m: []const f64, nr: usize, nc: usize, group: []const usize) -> (f64, err) {
    if nr < 2usize { ret (0.0f64 / 0.0f64, ok) }
    let (dd, e1) = mem.alloc[f64](a, nr * nr)
    let (gg, e2) = mem.alloc[f64](a, nr * nr)
    let (rowmean, e3) = mem.alloc[f64](a, nr)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    if e3 != ok { ret (0.0f64, e3) }
    var i = 0usize
    while i < nr {
        var j = 0usize
        while j < nr {
            if i == j {
                dd[i * nr + j] = 0.0f64
            } else if i < j {
                let d = vegdist(m, nr, nc, j, i, 2usize)
                dd[i * nr + j] = d * d
                dd[j * nr + i] = d * d
            }
            j += 1usize
        }
        i += 1usize
    }
    var grand = 0.0f64
    i = 0usize
    while i < nr {
        var s = 0.0f64
        var j = 0usize
        while j < nr {
            s += dd[i * nr + j]
            j += 1usize
        }
        rowmean[i] = s / f64(nr)
        grand += s
        i += 1usize
    }
    grand = grand / f64(nr * nr)
    var ss_tot = 0.0f64
    i = 0usize
    while i < nr {
        var j = 0usize
        while j < nr {
            gg[i * nr + j] = 0.0f64 - 0.5f64 * (dd[i * nr + j] - rowmean[i] - rowmean[j] + grand)
            if i == j { ss_tot += gg[i * nr + j] }
            j += 1usize
        }
        i += 1usize
    }
    if ss_tot == 0.0f64 { ret (0.0f64 / 0.0f64, ok) }
    // one pass per group (groups are visited at their first site): its size and the sum of G over its block
    var ss_mod = 0.0f64
    var first = 0usize
    while first < nr {
        var seen = false
        var t = 0usize
        while t < first {
            if group[t] == group[first] { seen = true }
            t += 1usize
        }
        if !seen {
            var size = 0.0f64
            var k = 0usize
            while k < nr {
                if group[k] == group[first] { size += 1.0f64 }
                k += 1usize
            }
            var block = 0.0f64
            var r = 0usize
            while r < nr {
                if group[r] == group[first] {
                    var c = 0usize
                    while c < nr {
                        if group[c] == group[first] { block += gg[r * nr + c] }
                        c += 1usize
                    }
                }
                r += 1usize
            }
            if size > 0.0f64 { ss_mod += block / size }
        }
        first += 1usize
    }
    ret (ss_mod / ss_tot, ok)
}

// vegan::anosim's R statistic (the permutation p-value needs R's RNG and is not produced here): rank every
// pairwise Bray-Curtis dissimilarity (average ranks for ties), then R = (mean rank between groups - mean rank
// within groups) / (n (n - 1) / 4). group holds one class code per site.
fn anosim_r(a: *mem.Arena, m: []const f64, nr: usize, nc: usize, group: []const usize) -> (f64, err) {
    let np = nr * (nr - 1usize) / 2usize
    let (d, e1) = mem.alloc[f64](a, np + 1usize)
    let (ranks, e2) = mem.alloc[f64](a, np + 1usize)
    let (within, e3) = mem.alloc[bool](a, np + 1usize)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    if e3 != ok { ret (0.0f64, e3) }
    if np == 0usize { ret (0.0f64 / 0.0f64, ok) }
    var k = 0usize
    var any_within = false
    var j = 0usize
    while j < nr {
        var i = j + 1usize
        while i < nr {
            d[k] = vegdist(m, nr, nc, i, j, 2usize)
            ranks[k] = d[k]
            within[k] = group[i] == group[j]
            if within[k] { any_within = true }
            k += 1usize
            i += 1usize
        }
        j += 1usize
    }
    if !any_within { ret (0.0f64 / 0.0f64, ok) }
    if rank_avg(ranks[0usize..np]) != ok { ret (0.0f64, mem.Full) }
    var sw = 0.0f64
    var nw = 0.0f64
    var sb = 0.0f64
    var nb = 0.0f64
    k = 0usize
    while k < np {
        if within[k] {
            sw += ranks[k]
            nw += 1.0f64
        } else {
            sb += ranks[k]
            nb += 1.0f64
        }
        k += 1usize
    }
    if nw == 0.0f64 || nb == 0.0f64 { ret (0.0f64 / 0.0f64, ok) }
    let mean_w = sw / nw
    let mean_b = sb / nb
    let div = f64(nr * (nr - 1usize)) / 4.0f64
    ret ((mean_b - mean_w) / div, ok)
}

// R's rank() with ties.method = "average", in place
fn rank_avg(v: []f64) -> err {
    var copy: [4096]f64 = zero
    let m = v.len
    if m > 4096usize { ret mem.Full }
    var i = 0usize
    while i < m {
        copy[i] = v[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        var less = 0usize
        var same = 0usize
        var j = 0usize
        while j < m {
            if copy[j] < copy[i] {
                less += 1usize
            } else if copy[j] == copy[i] {
                same += 1usize
            }
            j += 1usize
        }
        v[i] = f64(less) + (f64(same) + 1.0f64) / 2.0f64
        i += 1usize
    }
    ret ok
}

// vegan::mantel's test statistic: the correlation between the two distance matrices' lower triangles, taken
// column by column the way as.vector(dist) orders them. method 0 is Pearson (the default) and 1 is Spearman,
// which is Pearson on the average ranks. The permutation p-value is not produced here: it needs R's RNG.
fn mantel_r(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, method: usize) -> (f64, err) {
    let m = n * (n - 1usize) / 2usize
    let (vx, e1) = mem.alloc[f64](a, m + 1usize)
    let (vy, e2) = mem.alloc[f64](a, m + 1usize)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    var k = 0usize
    var j = 0usize
    while j < n {
        var i = j + 1usize
        while i < n {
            vx[k] = x[i * n + j]
            vy[k] = y[i * n + j]
            k += 1usize
            i += 1usize
        }
        j += 1usize
    }
    if m < 2usize { ret (0.0f64 / 0.0f64, ok) }
    if method == 1usize {
        if rank_avg(vx[0usize..m]) != ok { ret (0.0f64, mem.Full) }
        if rank_avg(vy[0usize..m]) != ok { ret (0.0f64, mem.Full) }
    }
    var mx = 0.0f64
    var my = 0.0f64
    var i = 0usize
    while i < m {
        mx += vx[i]
        my += vy[i]
        i += 1usize
    }
    mx = mx / f64(m)
    my = my / f64(m)
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    i = 0usize
    while i < m {
        let dx = vx[i] - mx
        let dy = vy[i] - my
        sxy += dx * dy
        sxx += dx * dx
        syy += dy * dy
        i += 1usize
    }
    if sxx <= 0.0f64 || syy <= 0.0f64 { ret (0.0f64 / 0.0f64, ok) }
    ret (sxy / math.sqrt[f64](sxx * syy), ok)
}

// vegan::procrustes with its defaults (asymmetric, scale = TRUE) on two n by k matrices: both are centred by
// column, the SVD of X'Y gives the singular values d, the isotropic scale is c = sum(d)/trace(Y) with
// trace(M) = sum(M^2), and the residual sum of squares is trace(X) + c^2 trace(Y) - 2 c sum(d), clamped at 0.
// Returns ss and, through scale_out, the scale c. The rotation and the rotated scores follow from the same
// SVD and are not returned here.
fn procrustes_fit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, scale_out: *f64) -> (f64, err) {
    let (cx, e1) = mem.alloc[f64](a, n * k)
    let (cy, e2) = mem.alloc[f64](a, n * k)
    let (cross, e3) = mem.alloc[f64](a, k * k)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    if e3 != ok { ret (0.0f64, e3) }
    var j = 0usize
    while j < k {
        var mx = 0.0f64
        var my = 0.0f64
        var i = 0usize
        while i < n {
            mx += x[i * k + j]
            my += y[i * k + j]
            i += 1usize
        }
        mx = mx / f64(n)
        my = my / f64(n)
        i = 0usize
        while i < n {
            cx[i * k + j] = x[i * k + j] - mx
            cy[i * k + j] = y[i * k + j] - my
            i += 1usize
        }
        j += 1usize
    }
    var r = 0usize
    while r < k {
        var c = 0usize
        while c < k {
            var sum = 0.0f64
            var i = 0usize
            while i < n {
                sum += cx[i * k + r] * cy[i * k + c]
                i += 1usize
            }
            cross[r * k + c] = sum
            c += 1usize
        }
        r += 1usize
    }
    let (sv, e4) = dc.jacobi_svd(a, cross, k, k)
    if e4 != ok { ret (0.0f64, e4) }
    var sum_d = 0.0f64
    var i = 0usize
    while i < sv.k {
        sum_d += sv.d[i]
        i += 1usize
    }
    var tr_x = 0.0f64
    var tr_y = 0.0f64
    i = 0usize
    while i < n * k {
        tr_x += cx[i] * cx[i]
        tr_y += cy[i] * cy[i]
        i += 1usize
    }
    var scale = 0.0f64
    if tr_y != 0.0f64 { scale = sum_d / tr_y }
    var ss = tr_x + scale * scale * tr_y - 2.0f64 * scale * sum_d
    if ss < 0.0f64 { ss = 0.0f64 }
    *scale_out = scale
    ret (ss, ok)
}

// vegan::fisher.alpha: the alpha of the log-series, the root of alpha * ln(1 + N/alpha) = S with S the
// species count and N the individual count of row r (0 when the row is empty). R's fisherfit calls uniroot
// with its default tolerance (about 1e-4), so the oracle solves the same equation more precisely instead of
// comparing against the loosely converged value (D7770); bisection is used because the left side is
// monotone increasing in alpha. A row where every species is a singleton (S == N) has no root - R warns
// that alpha is arbitrarily high there - so the oracle skips the draws that contain one.
fn fisher_alpha(m: []const f64, nc: usize, r: usize) -> f64 {
    var s = 0.0f64
    var n = 0.0f64
    var j = 0usize
    while j < nc {
        let x = m[r * nc + j]
        if x > 0.0f64 {
            s += 1.0f64
            n += x
        }
        j += 1usize
    }
    if s <= 0.0f64 { ret 0.0f64 }
    var lo = 0.1f64
    var hi = 50.0f64
    var f_hi = hi * math.log[f64](1.0f64 + n / hi) - s
    var guard = 0usize
    while f_hi < 0.0f64 && guard < 60usize {
        hi = hi * 2.0f64
        f_hi = hi * math.log[f64](1.0f64 + n / hi) - s
        guard += 1usize
    }
    var i = 0usize
    while i < 200usize {
        let mid = 0.5f64 * (lo + hi)
        let f_mid = mid * math.log[f64](1.0f64 + n / mid) - s
        if f_mid < 0.0f64 { lo = mid } else { hi = mid }
        if hi - lo <= 1.0e-15f64 * hi { break }
        i += 1usize
    }
    ret 0.5f64 * (lo + hi)
}

// vegan rarefy: expected richness of a subsample of size n from row r
fn rarefy(m: []const f64, nc: usize, r: usize, n: f64) -> f64 {
    var tot = 0.0f64
    var j = 0usize
    while j < nc {
        tot += m[r * nc + j]
        j += 1usize
    }
    var s = 0.0f64
    j = 0usize
    while j < nc {
        let x = m[r * nc + j]
        if x > 0.0f64 {
            var miss = 0.0f64
            if tot - x >= n { miss = math.exp[f64](nm.lgammafn(tot - x + 1.0f64) - nm.lgammafn(n + 1.0f64) - nm.lgammafn(tot - x - n + 1.0f64) - (nm.lgammafn(tot + 1.0f64) - nm.lgammafn(n + 1.0f64) - nm.lgammafn(tot - n + 1.0f64))) }
            s += 1.0f64 - miss
        }
        j += 1usize
    }
    ret s
}

// vegan::specaccum's accumulation curve (the deterministic methods): method 0 collector (species seen after
// the first i sites in the given order), 1 exact (the expected species count over all random orders,
// 1 - C(n - freq, i)/C(n, i) per species), 2 coleman (1 - (1 - i/n)^freq per species). out holds nr values.
// The random, rarefaction and area methods are not ported here.
fn specaccum(m: []const f64, nr: usize, nc: usize, method: usize, out: []f64) -> err {
    if out.len < nr { ret mem.Full }
    if method == 0usize {
        var i = 0usize
        while i < nr {
            var seen = 0.0f64
            var j = 0usize
            while j < nc {
                var t = 0usize
                while t <= i {
                    if m[t * nc + j] > 0.0f64 {
                        seen += 1.0f64
                        break
                    }
                    t += 1usize
                }
                j += 1usize
            }
            out[i] = seen
            i += 1usize
        }
        ret ok
    }
    if method == 1usize {
        let fnr = f64(nr)
        var i = 0usize
        while i < nr {
            let ii = f64(i + 1usize)
            let ldiv = lchoose(fnr, ii)
            var total = 0.0f64
            var j = 0usize
            while j < nc {
                var freq = 0.0f64
                var t = 0usize
                while t < nr {
                    if m[t * nc + j] > 0.0f64 { freq += 1.0f64 }
                    t += 1usize
                }
                if freq > 0.0f64 {
                    var term = 0.0f64
                    if fnr - freq >= ii { term = math.exp[f64](lchoose(fnr - freq, ii) - ldiv) }
                    total += 1.0f64 - term
                }
                j += 1usize
            }
            out[i] = total
            i += 1usize
        }
        ret ok
    }
    var i = 0usize
    while i < nr {
        let p = f64(i + 1usize) / f64(nr)
        var total = 0.0f64
        var j = 0usize
        while j < nc {
            var freq = 0.0f64
            var t = 0usize
            while t < nr {
                if m[t * nc + j] > 0.0f64 { freq += 1.0f64 }
                t += 1usize
            }
            total += 1.0f64 - math.pow[f64](1.0f64 - p, freq)
            j += 1usize
        }
        out[i] = total
        i += 1usize
    }
    ret ok
}

// log of the binomial coefficient, through lgamma
fn lchoose(n: f64, k: f64) -> f64 {
    ret nm.lgammafn(n + 1.0f64) - nm.lgammafn(k + 1.0f64) - nm.lgammafn(n - k + 1.0f64)
}

// R's phyper(q, m, n, k, lower.tail = TRUE): the hypergeometric CDF, summed directly because the count
// matrix a vegdist pair sees has at most a few dozen species.
fn hyper_cdf(q: f64, m: f64, n: f64, k: f64) -> f64 {
    if q < 0.0f64 { ret 0.0f64 }
    var hi = q
    if hi > m { hi = m }
    if hi > k { hi = k }
    var lo = k - n
    if lo < 0.0f64 { lo = 0.0f64 }
    let den = lchoose(m + n, k)
    var sum = 0.0f64
    var i = lo
    while i <= hi {
        sum += math.exp[f64](lchoose(m, i) + lchoose(n, k - i) - den)
        i += 1.0f64
    }
    ret sum
}

// vegan's vegdist(method = "mahalanobis"): the data are centred and whitened by the inverse square root of
// their covariance, then Euclidean distance is taken between the whitened rows. The square root comes from
// eigen(s2, symmetric = TRUE), keeping the eigenvalues above max(tol, tol * largest) with tol =
// sqrt(.Machine$double.eps); only z z^T is used, so eigenvector signs do not matter. out is nr by nr row-major.
fn mahalanobis_dist(a: *mem.Arena, m: []const f64, nr: usize, nc: usize, out: []f64) -> err {
    let (centre, e1) = mem.alloc[f64](a, nc)
    let (s, e2) = mem.alloc[f64](a, nc * nc)
    let (w, e3) = mem.alloc[f64](a, nc)
    let (z, e4) = mem.alloc[f64](a, nc * nc)
    let (sis, e5) = mem.alloc[f64](a, nc * nc)
    let (y, e6) = mem.alloc[f64](a, nr * nc)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    var j = 0usize
    while j < nc {
        var mean = 0.0f64
        var i = 0usize
        while i < nr {
            mean += m[i * nc + j]
            i += 1usize
        }
        centre[j] = mean / f64(nr)
        j += 1usize
    }
    // the covariance, divided by nr - 1 (R's cov)
    var c = 0usize
    while c < nc {
        var r = 0usize
        while r < nc {
            var sum = 0.0f64
            var i = 0usize
            while i < nr {
                sum += (m[i * nc + c] - centre[c]) * (m[i * nc + r] - centre[r])
                i += 1usize
            }
            s[c * nc + r] = sum / f64(nr - 1usize)
            r += 1usize
        }
        c += 1usize
    }
    if sy.dsyevr_all(a, s, nc, w, z) != ok { ret mem.Full }
    let tol = 1.4901161193847656e-8f64
    var lam_max = 0.0f64
    j = 0usize
    while j < nc {
        if w[j] > lam_max { lam_max = w[j] }
        j += 1usize
    }
    var cut = tol
    if tol * lam_max > cut { cut = tol * lam_max }
    j = 0usize
    while j < nc * nc {
        sis[j] = 0.0f64
        j += 1usize
    }
    var k = 0usize
    while k < nc {
        if w[k] > cut {
            let scale = 1.0f64 / math.sqrt[f64](w[k])
            var r = 0usize
            while r < nc {
                var c2 = 0usize
                while c2 < nc {
                    sis[r * nc + c2] += z[k * nc + r] * z[k * nc + c2] * scale
                    c2 += 1usize
                }
                r += 1usize
            }
        }
        k += 1usize
    }
    // y = centred data times the inverse square root
    var i = 0usize
    while i < nr {
        var q = 0usize
        while q < nc {
            var sum = 0.0f64
            var jj = 0usize
            while jj < nc {
                sum += (m[i * nc + jj] - centre[jj]) * sis[q * nc + jj]
                jj += 1usize
            }
            y[i * nc + q] = sum
            q += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nr {
        var r = 0usize
        while r < nr {
            var sum = 0.0f64
            var q = 0usize
            while q < nc {
                let d = y[i * nc + q] - y[r * nc + q]
                sum += d * d
                q += 1usize
            }
            out[i * nr + r] = math.sqrt[f64](sum)
            r += 1usize
        }
        i += 1usize
    }
    ret ok
}

// vegdist between rows a and b (morisita is clipped at 0 as vegan does, gower divides by the non-constant columns); method 0 euclidean, 1 manhattan, 2 bray, 3 kulczynski, 4 canberra, 5 gower, 6 horn, 7 morisita, 8 jaccard, 9 binary jaccard (binary bray gives the same ordering as 2B/(1+B)), 10 altGower (|a - b| averaged over the sites where not both are zero), 11 cao (the entropy term of Cao et al. with values below 0.1 floored, natural log), 12 clark (((a - b)/(a + b))^2 averaged over the sites where not both are zero, square rooted)
fn vegdist(m: []const f64, nr: usize, nc: usize, ra: usize, rb: usize, method: usize) -> f64 {
    var sa = 0.0f64
    var sb = 0.0f64
    var sab = 0.0f64
    var smin = 0.0f64
    var sabs = 0.0f64
    var ssq = 0.0f64
    var saa = 0.0f64
    var sbb = 0.0f64
    var saa1 = 0.0f64
    var sbb1 = 0.0f64
    var can = 0.0f64
    var nz = 0.0f64
    var gw = 0.0f64
    var gcount = 0.0f64
    var alt = 0.0f64
    var altc = 0.0f64
    var cao = 0.0f64
    var caoc = 0.0f64
    var clark = 0.0f64
    var clarkc = 0.0f64
    var ctot_a = 0.0f64
    var ctot_b = 0.0f64
    var cshare_a = 0.0f64
    var cshare_b = 0.0f64
    var cshare1_a = 0.0f64
    var cshare1_b = 0.0f64
    var a_once = 0.0f64
    var a_twice = 0.0f64
    var b_once = 0.0f64
    var b_twice = 0.0f64
    var rsim = 0.0f64
    var rt1 = 0.0f64
    var rt2 = 0.0f64
    var millar = 0.0f64
    var j = 0usize
    while j < nc {
        var x = m[ra * nc + j]
        var y = m[rb * nc + j]
        if method == 9usize {
            if x > 0.0f64 { x = 1.0f64 }
            if y > 0.0f64 { y = 1.0f64 }
        }
        sa += x
        sb += y
        sab += x * y
        if x < y { smin += x } else { smin += y }
        sabs += math.abs[f64](x - y)
        ssq += (x - y) * (x - y)
        saa += x * x
        sbb += y * y
        saa1 += x * (x - 1.0f64)
        sbb1 += y * (y - 1.0f64)
        // Chao-Jaccard's terms: vegan counts a value within 0.01 of 1 or 2 as a singleton or doubleton
        ctot_a += x
        ctot_b += y
        if x > 0.0f64 && y > 0.0f64 {
            cshare_a += x
            cshare_b += y
            if math.abs[f64](y - 1.0f64) < 0.01f64 {
                cshare1_a += x
                b_once += 1.0f64
            } else if math.abs[f64](y - 2.0f64) < 0.01f64 {
                b_twice += 1.0f64
            }
            if math.abs[f64](x - 1.0f64) < 0.01f64 {
                cshare1_b += y
                a_once += 1.0f64
            } else if math.abs[f64](x - 2.0f64) < 0.01f64 {
                a_twice += 1.0f64
            }
        }
        // Raup-Crick's presence/absence counts
        if x > 0.0f64 && y > 0.0f64 { rsim += 1.0f64 }
        if x > 0.0f64 { rt1 += 1.0f64 }
        if y > 0.0f64 { rt2 += 1.0f64 }
        if x + y > 0.0f64 {
            can += math.abs[f64](x - y) / (x + y)
            nz += 1.0f64
            // Millar's binomial deviance term
            let nk = x + y
            let lnnk = math.log[f64](nk)
            var mt1 = 0.0f64
            if x > 0.0f64 { mt1 = x * (math.log[f64](x) - lnnk) }
            var mt2 = 0.0f64
            if y > 0.0f64 { mt2 = y * (math.log[f64](y) - lnnk) }
            millar += (mt1 + mt2 + nk * math.log[f64](2.0f64)) / nk
        }
        if x > 0.0f64 || y > 0.0f64 {
            alt += math.abs[f64](x - y)
            altc += 1.0f64
            // clark answers an infinite term when the pair sums to zero (both negative), as vegan does
            let denom = x + y
            if denom > 0.0f64 {
                let t = (x - y) / denom
                clark += t * t
            } else {
                clark += 1.0e300f64
            }
            clarkc += 1.0f64
            // cao: a value below 0.1 is floored to 0.1, log(t1) - log(2) - (x1 log x2 + x2 log x1)/t1
            var x1 = x
            var x2 = y
            if x1 < 0.1f64 { x1 = 0.1f64 }
            if x2 < 0.1f64 { x2 = 0.1f64 }
            let t1 = x1 + x2
            cao += math.log[f64](t1) - math.log[f64](2.0f64) - (x1 * math.log[f64](x2) + x2 * math.log[f64](x1)) / t1
            caoc += 1.0f64
        }
        var lo = 1.0e300f64
        var hi = 0.0f64 - 1.0e300f64
        var i = 0usize
        while i < nr {
            let v = m[i * nc + j]
            if v < lo { lo = v }
            if v > hi { hi = v }
            i += 1usize
        }
        if hi > lo {
            gw += math.abs[f64](x - y) / (hi - lo)
            gcount += 1.0f64
        }
        j += 1usize
    }
    if method == 0usize { ret math.sqrt[f64](ssq) }
    if method == 1usize { ret sabs }
    if method == 2usize || method == 9usize {
        let b = sabs / (sa + sb)
        if method == 9usize { ret 2.0f64 * b / (1.0f64 + b) }
        ret b
    }
    if method == 3usize { ret 1.0f64 - 0.5f64 * (smin / sa + smin / sb) }
    if method == 4usize { ret can / nz }
    if method == 5usize { ret gw / gcount }
    if method == 6usize { ret 1.0f64 - 2.0f64 * sab / ((saa / (sa * sa) + sbb / (sb * sb)) * sa * sb) }
    if method == 7usize {
        let d = 1.0f64 - 2.0f64 * sab / ((saa1 / (sa * (sa - 1.0f64)) + sbb1 / (sb * (sb - 1.0f64))) * sa * sb)
        if d < 1.0e-15f64 { ret 0.0f64 }
        ret d
    }
    if method == 10usize {
        if altc == 0.0f64 { ret 0.0f64 / 0.0f64 }
        ret alt / altc
    }
    if method == 11usize {
        if caoc == 0.0f64 { ret 0.0f64 / 0.0f64 }
        let d = cao / caoc
        if d < 0.0f64 { ret 0.0f64 }
        ret d
    }
    if method == 12usize {
        if clarkc == 0.0f64 { ret 0.0f64 / 0.0f64 }
        ret math.sqrt[f64](clark / clarkc)
    }
    if method == 13usize {
        // Chao-Jaccard: U and V are the shared-abundance corrections for each side, then 1 - UV/(U + V - UV)
        var u = cshare_a / ctot_a
        if cshare1_a > 0.0f64 {
            var jonce = b_once
            var jtwice = b_twice
            if jonce < 1.0f64 { jonce = 1.0f64 }
            if jtwice < 1.0f64 { jtwice = 1.0f64 }
            u += (ctot_b - 1.0f64) / ctot_b * jonce / jtwice / 2.0f64 * cshare1_a / ctot_a
        }
        if u > 1.0f64 { u = 1.0f64 }
        var v = cshare_b / ctot_b
        if cshare1_b > 0.0f64 {
            var ionce = a_once
            var itwice = a_twice
            if ionce < 1.0f64 { ionce = 1.0f64 }
            if itwice < 1.0f64 { itwice = 1.0f64 }
            v += (ctot_a - 1.0f64) / ctot_a * ionce / itwice / 2.0f64 * cshare1_b / ctot_b
        }
        if v > 1.0f64 { v = 1.0f64 }
        if u <= 0.0f64 || v <= 0.0f64 { ret 1.0f64 }
        let d = 1.0f64 - u * v / (u + v - u * v)
        if d < 0.0f64 { ret 0.0f64 }
        ret d
    }
    if method == 15usize {
        // mountford: the Newton iteration on exp(d a) + exp(d b) - exp(d (a + b - j)) = 1; the two
        // degenerate cases set the root theta, and the answer is ln(2) - theta (so no shared species
        // answers ln(2), and one richness contained in the other answers 0)
        let ln2 = math.log[f64](2.0f64)
        if rt1 == 0.0f64 || rt2 == 0.0f64 { ret 0.0f64 / 0.0f64 }
        if rsim == 0.0f64 { ret ln2 }
        if rsim == rt1 || rsim == rt2 { ret 0.0f64 }
        let a = rt1
        let b = rt2
        var d = 2.0f64 * rsim / (2.0f64 * a * b - (a + b) * rsim)
        var iter = 0usize
        while iter < 20usize {
            let od = d
            let fa = math.exp[f64](d * a)
            let fb = math.exp[f64](d * b)
            let fj = math.exp[f64](d * (a + b - rsim))
            let f = fa + fb - fj - 1.0f64
            let fp = a * fa + b * fb - (a + b - rsim) * fj
            d = d - f / fp
            let diff = math.abs[f64](od - d)
            if diff / od < 1.0e-5f64 || diff < 1.0e-12f64 { break }
            iter += 1usize
        }
        ret ln2 - d
    }
    if method == 16usize {
        // binomial: Millar's deviance sum, clamped at 0
        if millar < 0.0f64 { ret 0.0f64 }
        ret millar
    }
    if method == 14usize {
        // Raup-Crick: 1 - phyper(sim - 1, min richness, count - min, max richness), count the sites
        let jj = rsim - 1.0f64
        var a = rt1
        var b = rt2
        if a > b {
            a = rt2
            b = rt1
        }
        ret 1.0f64 - hyper_cdf(jj, a, f64(nc) - a, b)
    }
    let b = sabs / (sa + sb)
    ret 2.0f64 * b / (1.0f64 + b)
}
