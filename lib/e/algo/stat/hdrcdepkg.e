// R hdrcde 3.5.0: hdr (falpha by the alpha-quantile of the density at the sample, region ends by all_roots with R's uniroot/zeroin, modes), tdensity with Box-Cox,
// hdrbw (the direct plug-in bandwidth for highest density regions, with its Monte-Carlo pilot), cde (normal-reference and cross-validated bandwidths, the Nadaraya-Watson
// conditional density through ksmooth), hdr.cde, and modalreg for given bandwidths.
//
// Not here: the locfit routes of cde (deg > 0, link, nearest-neighbour bandwidths), the bias adjustment, cde.bandwidths methods 1 and 4 (the bootstrap), the plots, hdr.2d, hdrconf
// and the box plots.

use e.algo.linalg.decomp as dc
use e.algo.rand.r as rr
use e.algo.stat.classint as ci
use e.algo.stat.rdensity as rd
use e.math
use e.math.dist as dist
use e.mem

error NoMem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn absf(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn newf(a: *mem.Arena, n: usize) -> []f64 {
    let (s, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok {
        var none: []f64 = zero
        ret none
    }
    ret s[0usize..n]
}

// seq.int(from, to, length.out = n)[i], 0-based: from + i by, the last value exactly to
fn seqat(from: f64, to: f64, i: usize, n: usize) -> f64 {
    if i + 1usize == n { ret to }
    ret from + f64(i) * ((to - from) / f64(n - 1usize))
}

fn sift(v: []f64, root0: usize, end: usize) {
    var root = root0
    while true {
        var child = 2usize * root + 1usize
        if child >= end { break }
        if child + 1usize < end && v[child] < v[child + 1usize] { child += 1usize }
        if v[root] >= v[child] { break }
        let t = v[root]
        v[root] = v[child]
        v[child] = t
        root = child
    }
}

// in place ascending
fn sort_f64(v: []f64) {
    let n = v.len
    if n < 2usize { ret }
    var start = n / 2usize
    while start > 0usize {
        start -= 1usize
        sift(v, start, n)
    }
    var end = n
    while end > 1usize {
        end -= 1usize
        let t = v[0usize]
        v[0usize] = v[end]
        v[end] = t
        sift(v, 0usize, end)
    }
}

// approx(xs, ys - sub, xout = v) with rule 1 (NaN outside) or rule 2 (the end values), R's approx1
fn approx_r(xs: []const f64, ys: []const f64, sub: f64, v: f64, rule2: bool) -> f64 {
    let n = xs.len
    if v < xs[0usize] {
        if rule2 { ret ys[0usize] - sub }
        ret nan()
    }
    if v > xs[n - 1usize] {
        if rule2 { ret ys[n - 1usize] - sub }
        ret nan()
    }
    var i = 0usize
    var j = n - 1usize
    while i + 1usize < j {
        let ij = (i + j) / 2usize
        if v < xs[ij] { j = ij } else { i = ij }
    }
    if v == xs[j] { ret ys[j] - sub }
    if v == xs[i] { ret ys[i] - sub }
    let yi = ys[i] - sub
    let yj = ys[j] - sub
    ret yi + (yj - yi) * ((v - xs[i]) / (xs[j] - xs[i]))
}

fn approx2(xs: []const f64, ys: []const f64, v: f64) -> f64 { ret approx_r(xs, ys, 0.0f64, v, true) }

// density(x, bw, n = nout) on its grid: xs and ys hold nout values; sorted is x ascending; scratch holds 5 * 1024 values (more past nout 1024)
fn den_grid_n(x: []const f64, sorted: []const f64, bw: f64, nout: usize, xs: []f64, ys: []f64, scratch: []f64) {
    let from = sorted[0usize] - 3.0f64 * bw
    let to = sorted[sorted.len - 1usize] + 3.0f64 * bw
    rd.density_gauss(x, sorted, bw, nout, ys, scratch)
    var i = 0usize
    while i < nout {
        xs[i] = seqat(from, to, i, nout)
        i += 1usize
    }
}

// the default 512-point density; scratch holds 2560 values
fn den_grid(x: []const f64, sorted: []const f64, bw: f64, xs: []f64, ys: []f64, scratch: []f64) {
    den_grid_n(x, sorted, bw, 512usize, xs, ys, scratch)
}

// the alpha-quantile (type 7) of the density heights at the points x (a sample); sorted_fx is scratch of x.len values
fn falpha_of(x: []const f64, xs: []const f64, ys: []const f64, alpha: f64, sorted_fx: []f64) -> f64 {
    var i = 0usize
    while i < x.len {
        sorted_fx[i] = approx2(xs, ys, x[i])
        i += 1usize
    }
    sort_f64(sorted_fx[0usize..x.len])
    ret rd.quant7(sorted_fx[0usize..x.len], alpha)
}

// R's zeroin2 (Brent) for the linearly interpolated density minus falpha on [ax, bx]; fa and fb are the values there
fn zeroin_hdr(xs: []const f64, ys: []const f64, fal: f64, ax: f64, bx: f64, fa0: f64, fb0: f64) -> f64 {
    let eps = 2.220446049250313e-16f64
    let tol = math.pow[f64](eps, 0.25f64)
    var a = ax
    var b = bx
    var c = a
    var fa = fa0
    var fb = fb0
    var fc = fa
    if fa == 0.0f64 { ret a }
    if fb == 0.0f64 { ret b }
    var maxit = 1001i64
    while maxit > 0i64 {
        maxit -= 1i64
        let prev_step = b - a
        if absf(fc) < absf(fb) {
            a = b
            b = c
            c = a
            fa = fb
            fb = fc
            fc = fa
        }
        let tol_act = 2.0f64 * eps * absf(b) + tol / 2.0f64
        var new_step = (c - b) / 2.0f64
        if absf(new_step) <= tol_act || fb == 0.0f64 { ret b }
        if absf(prev_step) >= tol_act && absf(fa) > absf(fb) {
            var p = 0.0f64
            var q = 0.0f64
            let cb = c - b
            if a == c {
                let t1 = fb / fa
                p = cb * t1
                q = 1.0f64 - t1
            } else {
                q = fa / fc
                let t1 = fb / fc
                let t2 = fb / fa
                p = t2 * (cb * q * (q - t1) - (b - a) * (t1 - 1.0f64))
                q = (q - 1.0f64) * (t1 - 1.0f64) * (t2 - 1.0f64)
            }
            if p > 0.0f64 { q = 0.0f64 - q } else { p = 0.0f64 - p }
            if p < (0.75f64 * cb * q - absf(tol_act * q) / 2.0f64) && p < absf(prev_step * q / 2.0f64) { new_step = p / q }
        }
        if absf(new_step) < tol_act {
            if new_step > 0.0f64 { new_step = tol_act } else { new_step = 0.0f64 - tol_act }
        }
        a = b
        fa = fb
        b += new_step
        fb = approx_r(xs, ys, fal, b, false)
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            c = a
            fc = fa
        }
    }
    ret b
}

// hdr.ends: all_roots of the interpolated density minus falpha (101 equally spaced points, uniroot on each sign change, sorted), then the grid ends when the density is above
// falpha just inside them; written to out (at least 128 values), returns how many (0 when falpha exceeds the density, where R answers NA)
fn hdr_ends(xs: []const f64, ys: []const f64, falpha: f64, out: []f64) -> usize {
    let n = xs.len
    var maxy = ys[0usize]
    var i = 1usize
    while i < n {
        if ys[i] > maxy { maxy = ys[i] }
        i += 1usize
    }
    if falpha > maxy { ret 0usize }
    let lo = xs[0usize]
    let hi = xs[n - 1usize]
    var gx: [101]f64 = zero
    var fx: [101]f64 = zero
    i = 0usize
    while i < 101usize {
        gx[i] = seqat(lo, hi, i, 101usize)
        fx[i] = approx_r(xs, ys, falpha, gx[i], false)
        i += 1usize
    }
    var cnt = 0usize
    i = 0usize
    while i < 101usize {
        if fx[i] == 0.0f64 {
            out[cnt] = gx[i]
            cnt += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < 100usize {
        if fx[i] * fx[i + 1usize] < 0.0f64 && cnt < 120usize {
            out[cnt] = zeroin_hdr(xs, ys, falpha, gx[i], gx[i + 1usize], fx[i], fx[i + 1usize])
            cnt += 1usize
        }
        i += 1usize
    }
    // sort the roots
    i = 1usize
    while i < cnt {
        let t = out[i]
        var j = i
        while j > 0usize && out[j - 1usize] > t {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = t
        i += 1usize
    }
    if cnt == 0usize {
        out[0usize] = xs[0usize]
        out[1usize] = xs[n - 1usize]
        ret 2usize
    }
    if approx_r(xs, ys, falpha, 0.5f64 * (out[0usize] + xs[0usize]), false) > 0.0f64 {
        var j = cnt
        while j > 0usize {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[0usize] = xs[0usize]
        cnt += 1usize
    }
    if approx_r(xs, ys, falpha, 0.5f64 * (out[cnt - 1usize] + xs[n - 1usize]), false) > 0.0f64 {
        out[cnt] = xs[n - 1usize]
        cnt += 1usize
    }
    ret cnt
}

// the modes hdr reports: the grid points where the density equals its maximum, or with all the local maxima (a point above both neighbours, the ends padded with 0, or the maximum)
fn hdr_modes(xs: []const f64, ys: []const f64, all: bool, out: []f64) -> usize {
    let n = xs.len
    var maxy = ys[0usize]
    var i = 1usize
    while i < n {
        if ys[i] > maxy { maxy = ys[i] }
        i += 1usize
    }
    var cnt = 0usize
    i = 0usize
    while i < n {
        var hit = ys[i] == maxy
        if all {
            var left = 0.0f64
            var right = 0.0f64
            if i > 0usize { left = ys[i - 1usize] }
            if i + 1usize < n { right = ys[i + 1usize] }
            if ys[i] > left && ys[i] > right { hit = true }
        }
        if hit && cnt < out.len {
            out[cnt] = xs[i]
            cnt += 1usize
        }
        i += 1usize
    }
    ret cnt
}

// R's revsort: a descending by heapsort, ib alongside
fn revsort(a: []f64, ib: []i64) {
    let n = a.len
    if n <= 1usize { ret }
    var l = n / 2usize + 1usize
    var ir = n
    while true {
        var ra = 0.0f64
        var ii = 0i64
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
                break
            }
        }
        var i = l
        var j = l * 2usize
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

// sample(xs, nn, replace = TRUE, prob = ps): R's ProbSampleReplace (inversion on the sorted cumulative) or Walker's alias method past 200 probabilities above 0.1 / n; out gets the sampled xs
fn sample_prob(a: *mem.Arena, r: *rr.Rng, xs: []const f64, ps: []const f64, nn: usize, out: []f64) -> err {
    let n = ps.len
    let p = newf(a, n)
    if p.len == 0usize { ret NoMem }
    var sum = 0.0f64
    var i = 0usize
    while i < n {
        sum += ps[i]
        i += 1usize
    }
    var nc = 0usize
    i = 0usize
    while i < n {
        p[i] = ps[i] / sum
        if f64(n) * p[i] > 0.1f64 { nc += 1usize }
        i += 1usize
    }
    let (perm, pe) = mem.alloc[i64](a, n + 1usize)
    if pe != ok { ret pe }
    if nc > 200usize {
        let q = p
        let hl = perm
        let (aa, ae) = mem.alloc[i64](a, n + 1usize)
        if ae != ok { ret ae }
        var hcnt = 0usize
        var lp = n
        i = 0usize
        while i < n {
            q[i] = p[i] * f64(n)
            if q[i] < 1.0f64 {
                hl[hcnt] = i64(i)
                hcnt += 1usize
            } else {
                lp -= 1usize
                hl[lp] = i64(i)
            }
            i += 1usize
        }
        if hcnt > 0usize && lp < n {
            var k = 0usize
            while k + 1usize < n {
                let ii = usize(hl[k])
                let jj = usize(hl[lp])
                aa[ii] = i64(jj)
                q[jj] += q[ii] - 1.0f64
                if q[jj] < 1.0f64 { lp += 1usize }
                if lp >= n { break }
                k += 1usize
            }
        }
        i = 0usize
        while i < n {
            q[i] += f64(i)
            i += 1usize
        }
        i = 0usize
        while i < nn {
            let k = usize(rr.unif_index(r, f64(n)))
            let ru = f64(k) + rr.unif(r)
            if ru < q[k] { out[i] = xs[k] } else { out[i] = xs[usize(aa[k])] }
            i += 1usize
        }
        ret ok
    }
    i = 0usize
    while i < n {
        perm[i] = i64(i)
        i += 1usize
    }
    revsort(p, perm[0usize..n])
    i = 1usize
    while i < n {
        p[i] += p[i - 1usize]
        i += 1usize
    }
    i = 0usize
    while i < nn {
        let ru = rr.unif(r)
        var j = 0usize
        while j + 1usize < n {
            if ru <= p[j] { break }
            j += 1usize
        }
        out[i] = xs[usize(perm[j])]
        i += 1usize
    }
    ret ok
}

fn boxcox(x: f64, lambda: f64) -> f64 {
    if lambda == 0.0f64 { ret math.log[f64](x) }
    ret (math.pow[f64](x, lambda) - 1.0f64) / lambda
}

fn inv_boxcox(x: f64, lambda: f64) -> f64 {
    if lambda == 0.0f64 { ret math.exp[f64](x) }
    ret math.pow[f64]((x * lambda + 1.0f64), 1.0f64 / lambda)
}

// tdensity(x, bw, lambda): density of the Box-Cox transform on 1001 points, back-transformed; xo and yo hold 1002 values; returns how many are filled
fn tdensity(a: *mem.Arena, x: []const f64, bw: f64, lambda: f64, xo: []f64, yo: []f64) -> (usize, err) {
    let n = x.len
    let y = newf(a, n)
    let g = newf(a, 1001usize)
    let gy = newf(a, 1001usize)
    let sc = newf(a, 5usize * 1024usize)
    if y.len == 0usize || g.len == 0usize || gy.len == 0usize || sc.len == 0usize { ret (0usize, NoMem) }
    var i = 0usize
    while i < n {
        if lambda == 1.0f64 { y[i] = x[i] } else { y[i] = boxcox(x[i], lambda) }
        i += 1usize
    }
    let s = newf(a, n)
    if s.len == 0usize { ret (0usize, NoMem) }
    i = 0usize
    while i < n {
        s[i] = y[i]
        i += 1usize
    }
    sort_f64(s)
    den_grid_n(y, s, bw, 1001usize, g, gy, sc)
    if lambda == 1.0f64 {
        i = 0usize
        while i < 1001usize {
            xo[i] = g[i]
            yo[i] = gy[i]
            i += 1usize
        }
        ret (1001usize, ok)
    }
    var cut = 0.0f64 - 1.0f64 / 0.0f64
    if lambda != 0.0f64 { cut = 0.1f64 - 1.0f64 / lambda }
    xo[0usize] = 0.0f64
    yo[0usize] = 0.0f64
    var cnt = 1usize
    i = 0usize
    while i < 1001usize {
        if g[i] > cut {
            let xg = inv_boxcox(g[i], lambda)
            xo[cnt] = xg
            yo[cnt] = gy[i] * math.pow[f64](xg, lambda - 1.0f64)
            cnt += 1usize
        }
        i += 1usize
    }
    ret (cnt, ok)
}

// --- hdrbw

fn sd_of(x: []const f64) -> f64 {
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / f64(x.len)
    var s = 0.0f64
    i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret math.sqrt[f64](s / f64(x.len - 1usize))
}

// densDPI(x, drv): the direct plug-in bandwidth for the derivative order drv (0, 1 or 2) on a 401-point grid
fn dens_dpi(a: *mem.Arena, x: []const f64, drv: usize) -> (f64, err) {
    let n = f64(x.len)
    let s = newf(a, x.len)
    if s.len == 0usize { ret (0.0f64, NoMem) }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    sort_f64(s)
    let lo = s[0usize]
    let hi = s[x.len - 1usize]
    let (g, ge) = ci.linbin(a, x, lo, hi, 401usize)
    if ge != ok { ret (0.0f64, ge) }
    var scale = sd_of(x)
    let iqr = (rd.quant7(s, 0.75f64) - rd.quant7(s, 0.25f64)) / 1.349f64
    if iqr < scale { scale = iqr }
    let rt2 = math.sqrt[f64](2.0f64)
    let c2 = math.sqrt[f64](2.0f64 / 3.141592653589793f64)
    var h = 0.0f64
    if drv == 0usize {
        var al = math.pow[f64](2.0f64 * math.pow[f64](rt2 * scale, 9.0f64) / (7.0f64 * n), 1.0f64 / 9.0f64)
        let psi6 = ci.bkfe(g, 6usize, al, lo, hi)
        al = math.pow[f64](0.0f64 - 3.0f64 * c2 / (psi6 * n), 1.0f64 / 7.0f64)
        let psi4 = ci.bkfe(g, 4usize, al, lo, hi)
        h = math.pow[f64](1.0f64 / (2.0f64 * math.sqrt[f64](3.141592653589793f64) * psi4 * n), 0.2f64)
    }
    if drv == 1usize {
        var al = math.pow[f64](2.0f64 * math.pow[f64](rt2 * scale, 11.0f64) / (9.0f64 * n), 1.0f64 / 11.0f64)
        let psi8 = ci.bkfe(g, 8usize, al, lo, hi)
        al = math.pow[f64](15.0f64 * c2 / (psi8 * n), 1.0f64 / 9.0f64)
        let psi6 = ci.bkfe(g, 6usize, al, lo, hi)
        h = math.pow[f64](0.0f64 - 3.0f64 / (4.0f64 * math.sqrt[f64](3.141592653589793f64) * psi6 * n), 1.0f64 / 7.0f64)
    }
    if drv == 2usize {
        var al = math.pow[f64](2.0f64 * math.pow[f64](rt2 * scale, 13.0f64) / (11.0f64 * n), 1.0f64 / 13.0f64)
        let psi10 = ci.bkfe(g, 10usize, al, lo, hi)
        al = math.pow[f64](0.0f64 - 105.0f64 * c2 / (psi10 * n), 1.0f64 / 11.0f64)
        let psi8 = ci.bkfe(g, 8usize, al, lo, hi)
        h = math.pow[f64](15.0f64 / (8.0f64 * math.sqrt[f64](3.141592653589793f64) * psi8 * n), 1.0f64 / 9.0f64)
    }
    ret (h, ok)
}

fn dn(x: f64) -> f64 { ret dist.dnorm(x, 0.0f64, 1.0f64, false) }

// drvKDE(x, x0, bandwidth, drv) for drv 1 and 2
fn drv_kde(x: []const f64, x0: f64, h: f64, drv: usize) -> f64 {
    let n = f64(x.len)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        let u = (x0 - x[i]) / h
        if drv == 1usize { s += 0.0f64 - u * dn(u) } else { s += (u * u - 1.0f64) * dn(u) }
        i += 1usize
    }
    if drv == 1usize { ret s / (n * h * h) }
    ret s / (n * h * h * h)
}

// KernSmooth::bkde with the normal kernel on a given range and grid, written as the direct convolution the FFT computes; y has m values
fn bkde_range(a: *mem.Arena, x: []const f64, h: f64, lo: f64, hi: f64, m: usize, y: []f64) -> err {
    let n = f64(x.len)
    let (g, ge) = ci.linbin(a, x, lo, hi, m)
    if ge != ok { ret ge }
    let delta = (hi - lo) / (h * f64(m - 1usize))
    var ll = usize(math.floor[f64](4.0f64 / delta))
    if ll > m { ll = m }
    let kap = newf(a, ll + 1usize)
    if kap.len == 0usize { ret NoMem }
    var tot = 0.0f64
    var l = 0usize
    while l <= ll {
        kap[l] = dn(f64(l) * delta) / (n * h)
        if l == 0usize { tot += kap[l] } else { tot += 2.0f64 * kap[l] }
        l += 1usize
    }
    tot = tot * (hi - lo) / f64(m - 1usize) * n
    var j = 0usize
    while j < m {
        var s = 0.0f64
        var k = 0usize
        while k < m {
            var d = j
            if k > j { d = k - j } else { d = j - k }
            if d <= ll { s += g[k] * (kap[d] / tot) }
            k += 1usize
        }
        y[j] = s
        j += 1usize
    }
    ret ok
}

fn sgn(x: f64) -> f64 {
    if x > 0.0f64 { ret 1.0f64 }
    if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 0.0f64
}

// hdrbw(x, level): the bandwidth minimising the estimated risk of the highest density region of the given level; mc draws for the Monte-Carlo pilot (1e6 in R), the generator seeded with seed
fn hdrbw(a: *mem.Arena, x: []const f64, level0: f64, seed: i64, mc: usize) -> (f64, err) {
    var level = level0
    if level > 1.0f64 && level < 100.0f64 { level = level / 100.0f64 }
    let n = x.len
    let nf = f64(n)
    let (h0, e0) = dens_dpi(a, x, 0usize)
    if e0 != ok { ret (0.0f64, e0) }
    let (h1, e1) = dens_dpi(a, x, 1usize)
    if e1 != ok { ret (0.0f64, e1) }
    let (h2, e2) = dens_dpi(a, x, 2usize)
    if e2 != ok { ret (0.0f64, e2) }
    var r: rr.Rng = zero
    rr.seed(&r, seed)
    let xh = newf(a, mc)
    if xh.len == 0usize { ret (0.0f64, NoMem) }
    var i = 0usize
    while i < mc {
        xh[i] = x[usize(rr.unif_index(&r, nf))]
        i += 1usize
    }
    var xmin = 0.0f64
    var xmax = 0.0f64
    i = 0usize
    while i < mc {
        xh[i] = xh[i] + h0 * rr.norm(&r)
        if i == 0usize || xh[i] < xmin { xmin = xh[i] }
        if i == 0usize || xh[i] > xmax { xmax = xh[i] }
        i += 1usize
    }
    let fy = newf(a, 801usize)
    let fx = newf(a, 801usize)
    if fy.len == 0usize || fx.len == 0usize { ret (0.0f64, NoMem) }
    let be = bkde_range(a, x, h0, xmin, xmax, 801usize, fy)
    if be != ok { ret (0.0f64, be) }
    i = 0usize
    while i < 801usize {
        fx[i] = seqat(xmin, xmax, i, 801usize)
        i += 1usize
    }
    i = 0usize
    while i < mc {
        xh[i] = approx2(fx, fy, xh[i])
        i += 1usize
    }
    sort_f64(xh)
    let ftau = rd.quant7(xh, level)
    // the cut points of the pilot estimate with the level
    let cuts = newf(a, 801usize)
    if cuts.len == 0usize { ret (0.0f64, NoMem) }
    var nc = 0usize
    i = 1usize
    while i < 801usize {
        let d = sgn(fy[i] - ftau) - sgn(fy[i - 1usize] - ftau)
        if d != 0.0f64 {
            cuts[nc] = (fx[i] + fx[i - 1usize]) / 2.0f64
            nc += 1usize
        }
        i += 1usize
    }
    if nc < 2usize { ret (0.0f64, NoMem) }
    let fd = newf(a, nc)
    let fdd = newf(a, nc)
    let b1 = newf(a, nc)
    let b2 = newf(a, nc)
    let b3 = newf(a, nc)
    if fd.len == 0usize || fdd.len == 0usize || b1.len == 0usize || b2.len == 0usize || b3.len == 0usize { ret (0.0f64, NoMem) }
    var j = 0usize
    while j < nc {
        fd[j] = drv_kde(x, cuts[j], h1, 1usize)
        fdd[j] = drv_kde(x, cuts[j], h2, 2usize)
        j += 1usize
    }
    // hdrBvals
    let rk = 1.0f64 / (2.0f64 * math.sqrt[f64](3.141592653589793f64))
    var hs = 0.0f64
    var d1s1 = 0.0f64
    j = 0usize
    while j < nc {
        hs += 1.0f64 / absf(fd[j])
        d1s1 += fdd[j] / absf(fd[j])
        j += 1usize
    }
    let fdhar = 1.0f64 / hs
    var d1s2 = 0.0f64
    j = 1usize
    while j < nc {
        d1s2 += fd[j] - fd[j - 1usize]
        j += 2usize
    }
    d1s2 = d1s2 / ftau
    let d1 = 0.5f64 * fdhar * (d1s1 + d1s2)
    var inv2 = 0.0f64
    j = 0usize
    while j < nc {
        inv2 += 1.0f64 / (fd[j] * fd[j])
        j += 1usize
    }
    let d2 = rk * ftau * fdhar * fdhar * inv2
    j = 0usize
    while j < nc {
        let d3 = rk * ftau * fdhar / absf(fd[j])
        let root = math.sqrt[f64](rk * ftau - 2.0f64 * d3 + d2)
        b1[j] = 2.0f64 * ftau * root / absf(fd[j])
        b2[j] = ftau * absf(0.5f64 * fdd[j] - d1) / root
        b3[j] = ftau * absf(0.5f64 * fdd[j] - d1) / absf(fd[j])
        j += 1usize
    }
    let hh = h0
    var smid = math.pow[f64](nf, 0.1f64) * math.sqrt[f64](hh)
    var slow = smid / 5.0f64
    var supp = 5.0f64 * smid
    var cap = 0usize
    var captured = false
    while !captured && cap < 400usize {
        let fl = risk_d1(slow, b1, b2, b3)
        let fu = risk_d1(supp, b1, b2, b3)
        if fl > 0.0f64 { slow = slow / 2.0f64 }
        if fu < 0.0f64 { supp = 2.0f64 * supp }
        if fl < 0.0f64 && fu > 0.0f64 { captured = true }
        cap += 1usize
    }
    var ib = 0usize
    while ib < 100usize {
        smid = (slow + supp) / 2.0f64
        let fm = risk_d1(smid, b1, b2, b3)
        if fm < 0.0f64 { slow = smid }
        if fm > 0.0f64 { supp = smid }
        ib += 1usize
    }
    var s = smid
    var finished = false
    var it = 0usize
    while !finished {
        it += 1usize
        var fds = 0.0f64
        var fdds = 0.0f64
        j = 0usize
        while j < nc {
            let farg = b2[j] * math.pow[f64](s, 5.0f64)
            let dd = dn(farg)
            let pp = dist.pnorm(farg, 0.0f64, 1.0f64, true, false)
            fds += ((0.0f64 - 1.0f64 / (s * s)) * b1[j] + 10.0f64 * b2[j] * b3[j] * math.pow[f64](s, 8.0f64) - 5.0f64 * b1[j] * (b2[j] * b2[j]) * math.pow[f64](s, 8.0f64)) * dd + 4.0f64 * b3[j] * math.pow[f64](s, 3.0f64) * (2.0f64 * pp - 1.0f64)
            fdds += (2.0f64 * b1[j] * (1.0f64 / math.pow[f64](s, 3.0f64)) + 5.0f64 * b2[j] * (24.0f64 * b3[j] - 7.0f64 * b1[j] * b2[j]) * math.pow[f64](s, 7.0f64) - 25.0f64 * math.pow[f64](b2[j], 3.0f64) * (2.0f64 * b3[j] - b1[j] * b2[j]) * math.pow[f64](s, 17.0f64)) * dd + 12.0f64 * b3[j] * (s * s) * (2.0f64 * pp - 1.0f64)
            j += 1usize
        }
        let snew = s - fds / fdds
        if snew < 0.0f64 { ret (nan(), ok) }
        let rel = absf((snew - s) / s)
        if rel < 1.0e-7f64 { finished = true }
        if it > 100usize { ret (nan(), ok) }
        s = snew
    }
    ret ((s * s) * math.pow[f64](nf, 0.0f64 - 0.2f64), ok)
}

// the first derivative of the risk in s
fn risk_d1(s: f64, b1: []const f64, b2: []const f64, b3: []const f64) -> f64 {
    var t = 0.0f64
    var j = 0usize
    while j < b1.len {
        let farg = b2[j] * math.pow[f64](s, 5.0f64)
        let dd = dn(farg)
        let pp = dist.pnorm(farg, 0.0f64, 1.0f64, true, false)
        t += ((0.0f64 - 1.0f64 / (s * s)) * b1[j] + 10.0f64 * b2[j] * b3[j] * math.pow[f64](s, 8.0f64) - 5.0f64 * b1[j] * (b2[j] * b2[j]) * math.pow[f64](s, 8.0f64)) * dd + 4.0f64 * b3[j] * math.pow[f64](s, 3.0f64) * (2.0f64 * pp - 1.0f64)
        j += 1usize
    }
    ret t
}

// --- cde

// lm(y ~ x): intercept and slope, and the residual standard deviation sqrt(RSS / (n - 2))
fn simple_lm(x: []const f64, y: []const f64) -> (f64, f64, f64) {
    let n = f64(x.len)
    var mx = 0.0f64
    var my = 0.0f64
    var i = 0usize
    while i < x.len {
        mx += x[i]
        my += y[i]
        i += 1usize
    }
    mx = mx / n
    my = my / n
    var sxx = 0.0f64
    var sxy = 0.0f64
    i = 0usize
    while i < x.len {
        sxx += (x[i] - mx) * (x[i] - mx)
        sxy += (x[i] - mx) * (y[i] - my)
        i += 1usize
    }
    let b1 = sxy / sxx
    let b0 = my - b1 * mx
    var rss = 0.0f64
    i = 0usize
    while i < x.len {
        let r = y[i] - b0 - b1 * x[i]
        rss += r * r
        i += 1usize
    }
    ret (b0, b1, math.sqrt[f64](rss / (n - 2.0f64)))
}

// cdeband.rules0(x, y) with its defaults (normal marginal density, k = 3, no modification): returns (a, b)
fn cdeband_rules0(x: []const f64, y: []const f64) -> (f64, f64) {
    let pi = 3.141592653589793f64
    let rk = 0.5f64 / math.sqrt[f64](pi)
    let sk = 1.0f64
    let n = f64(x.len)
    let (_b0, d, p) = simple_lm(x, y)
    let erf = 0.954499736f64
    let k = 3.0f64
    let sm = sd_of(x)
    let v = 3.0f64 * erf * d * d * math.pow[f64](sm, 3.0f64) * pi - 8.0f64 * math.sqrt[f64](2.0f64 * pi) * p * p * k * math.exp[f64](0.0f64 - k * k / 2.0f64) + 8.0f64 * pi * p * p * erf
    let anum = math.pow[f64](16.0f64 * rk * rk * k * math.pow[f64](pi, 1.25f64) * math.pow[f64](p, 5.0f64) * math.pow[f64](sm, 2.5f64) / (n * math.pow[f64](absf(d), 2.5f64) * math.pow[f64](sk, 4.0f64)), 1.0f64 / 6.0f64)
    let adem = math.pow[f64](math.pow[f64](math.pow[f64](v, 5.0f64) / (3.0f64 * pi * pi * math.pow[f64](sm, 4.0f64) * erf), 0.25f64) + 3.0f64 * d * math.pow[f64](v * math.pow[f64](erf, 1.0f64 / 3.0f64) / 3.0f64, 0.75f64), 1.0f64 / 6.0f64)
    let aa = anum / adem
    let bb = math.pow[f64]((d * d * v) / (3.0f64 * pi * sm * erf), 0.25f64) * aa
    ret (aa, bb)
}

// stats::ksmooth(x, y, "normal", bandwidth, x.points = xp): x ascending (carrying y); yp gets NaN where no point falls within the window
fn ksmooth_normal(x: []const f64, y: []const f64, xp: []const f64, bandwidth: f64, yp: []f64) {
    let bw = bandwidth * 0.3706506f64
    let cutoff = 4.0f64 * bw
    let n = x.len
    var imin = 0usize
    while imin < n && x[imin] < xp[0usize] - cutoff { imin += 1usize }
    var j = 0usize
    while j < xp.len {
        var num = 0.0f64
        var den = 0.0f64
        let x0 = xp[j]
        var i = imin
        while i < n {
            if x[i] < x0 - cutoff { imin = i } else {
                if x[i] > x0 + cutoff { break }
                let u = absf(x[i] - x0) / bw
                let w = math.exp[f64](-0.5f64 * u * u)
                num += w * y[i]
                den += w
            }
            i += 1usize
        }
        if den > 0.0f64 { yp[j] = num / den } else { yp[j] = nan() }
        j += 1usize
    }
}

// order x ascending with y carried, stable; into xo and yo
fn sort_pairs(x: []const f64, y: []const f64, xo: []f64, yo: []f64) {
    var i = 0usize
    while i < x.len {
        let tx = x[i]
        let ty = y[i]
        var j = i
        while j > 0usize && xo[j - 1usize] > tx {
            xo[j] = xo[j - 1usize]
            yo[j] = yo[j - 1usize]
            j -= 1usize
        }
        xo[j] = tx
        yo[j] = ty
        i += 1usize
    }
}

// cde(x, y, a, b, x.margin, y.margin) with deg 0: z[i * ny + j] is the density of y at ym[j] given x at xm[i] (xm ascending); the kernel bandwidths a (x) and b (y)
fn cde_z(a: *mem.Arena, x: []const f64, y: []const f64, aa: f64, bb: f64, xm: []const f64, ym: []const f64, z: []f64) -> err {
    let n = x.len
    let nx = xm.len
    let ny = ym.len
    let xs = newf(a, n)
    let ys = newf(a, n)
    let ny1 = newf(a, n)
    let col = newf(a, nx)
    if xs.len == 0usize || ys.len == 0usize || ny1.len == 0usize || col.len == 0usize { ret NoMem }
    sort_pairs(x, y, xs, ys)
    var j = 0usize
    while j < ny {
        var mx = 0.0f64
        var i = 0usize
        while i < n {
            // Kernel(y, y.margin[j], b, "normal") with y in the sorted order of x
            let v = dist.dnorm(ym[j] - ys[i], 0.0f64, bb, false)
            ny1[i] = v
            if absf(v) > mx { mx = absf(v) }
            i += 1usize
        }
        if mx < 1.0e-20f64 {
            i = 0usize
            while i < nx {
                z[i * ny + j] = 0.0f64
                i += 1usize
            }
        } else {
            ksmooth_normal(xs, ny1, xm, 2.697959f64 * aa, col)
            i = 0usize
            while i < nx {
                var c = col[i]
                if c != c { c = 0.0f64 }
                z[i * ny + j] = c
                i += 1usize
            }
        }
        j += 1usize
    }
    let delta = ym[1usize] - ym[0usize]
    var i = 0usize
    while i < nx {
        var sumz = 0.0f64
        j = 0usize
        while j < ny {
            sumz += z[i * ny + j]
            j += 1usize
        }
        if sumz > 0.0f64 {
            j = 0usize
            while j < ny {
                z[i * ny + j] = z[i * ny + j] / sumz
                j += 1usize
            }
        }
        j = 0usize
        while j < ny {
            z[i * ny + j] = z[i * ny + j] / delta
            if z[i * ny + j] < 0.0f64 { z[i * ny + j] = 0.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

fn epanech(u: f64, h: f64) -> f64 {
    let xx = u / h
    if absf(xx) < 1.0f64 { ret 0.75f64 * (1.0f64 - xx * xx) }
    ret 0.0f64
}

// CDEband.regress: the penalised cross-validation criterion over a grid of x bandwidths with the Epanechnikov kernel (penalty 4); q gets the criterion times the y spacing; returns the
// minimiser, NaN when it sits on the grid edge
fn cdeband_regress1(a: *mem.Arena, x: []const f64, y: []const f64, agrid: []const f64, b: f64, ym: []const f64, q: []f64) -> (f64, err) {
    let n = x.len
    let ny = ym.len
    let delta = ym[1usize] - ym[0usize]
    let v = newf(a, n * ny)
    let w = newf(a, n * n)
    let t = newf(a, n * ny)
    if v.len == 0usize || w.len == 0usize || t.len == 0usize { ret (0.0f64, NoMem) }
    var i = 0usize
    while i < n {
        var m = 0usize
        while m < ny {
            v[i * ny + m] = epanech(ym[m] - y[i], b)
            m += 1usize
        }
        i += 1usize
    }
    var ia = 0usize
    while ia < agrid.len {
        i = 0usize
        while i < n {
            var rs = 0.0f64
            var k = 0usize
            while k < n {
                w[i * n + k] = epanech(x[i] - x[k], agrid[ia])
                k += 1usize
            }
            k = 0usize
            while k < n {
                rs += w[i * n + k]
                k += 1usize
            }
            k = 0usize
            while k < n {
                w[i * n + k] = w[i * n + k] / rs
                k += 1usize
            }
            i += 1usize
        }
        // t = w' v
        var k = 0usize
        while k < n {
            var m = 0usize
            while m < ny {
                var s = 0.0f64
                i = 0usize
                while i < n {
                    s += w[i * n + k] * v[i * ny + m]
                    i += 1usize
                }
                t[k * ny + m] = s
                m += 1usize
            }
            k += 1usize
        }
        var tot = 0.0f64
        var valid = 0usize
        k = 0usize
        while k < n {
            var tmp = 0.0f64
            var m = 0usize
            while m < ny {
                let d = v[k * ny + m] - t[k * ny + m]
                tmp += d * d
                m += 1usize
            }
            let dw = w[k * n + k]
            let term = tmp * ((1.0f64 + dw) / (1.0f64 - dw))
            if term == term {
                tot += term
                valid += 1usize
            }
            k += 1usize
        }
        q[ia] = tot / f64(valid)
        ia += 1usize
    }
    var qmin = q[0usize]
    var idx = 0usize
    ia = 1usize
    while ia < agrid.len {
        if q[ia] < qmin {
            qmin = q[ia]
            idx = ia
        }
        ia += 1usize
    }
    ia = 0usize
    while ia < agrid.len {
        q[ia] = q[ia] * delta
        ia += 1usize
    }
    if idx == 0usize || idx + 1usize == agrid.len { ret (nan(), ok) }
    ret (agrid[idx], ok)
}

// stable ordering of g with q carried
fn sort_gq(g: []f64, q: []f64) {
    var i = 1usize
    while i < g.len {
        let tg = g[i]
        let tq = q[i]
        var j = i
        while j > 0usize && g[j - 1usize] > tg {
            g[j] = g[j - 1usize]
            q[j] = q[j - 1usize]
            j -= 1usize
        }
        g[j] = tg
        q[j] = tq
        i += 1usize
    }
}

// cdeband.regress(x, y, y.margin = ym) with its defaults (grid 0.01 .. 3 times the rule of thumb, two passes, quadratic polish); returns the cross-validated a (NaN when none)
fn cdeband_regress(a: *mem.Arena, x: []const f64, y: []const f64, ym: []const f64) -> (f64, err) {
    let (ra, rb) = cdeband_rules0(x, y)
    let g1 = newf(a, 10usize)
    let gout = newf(a, 140usize)
    if g1.len == 0usize || gout.len == 0usize { ret (nan(), NoMem) }
    var i = 0usize
    while i < 10usize {
        g1[i] = ra * seqat(0.01f64, 3.0f64, i, 10usize)
        i += 1usize
    }
    let (best, be) = cdeband_regress_with(a, x, y, ym, g1, rb, gout)
    ret (best, be)
}

// cdeband.regress with the given grid g1 of x bandwidths and y bandwidth rb; gout (140 values) gets the count of grid points searched and then the grid
fn cdeband_regress_with(a: *mem.Arena, x: []const f64, y: []const f64, ym: []const f64, g1: []const f64, rb: f64, gout: []f64) -> (f64, err) {
    let n0 = g1.len
    var q1 = newf(a, n0)
    if q1.len == 0usize { ret (nan(), NoMem) }
    var i = 0usize
    let (a1, e1) = cdeband_regress1(a, x, y, g1, rb, ym, q1)
    if e1 != ok { ret (nan(), e1) }
    var first_a = a1
    var ng = n0
    var cur = newf(a, n0)
    if cur.len == 0usize { ret (nan(), NoMem) }
    var curq = q1
    var grid_len = n0
    i = 0usize
    while i < n0 {
        cur[i] = g1[i]
        i += 1usize
    }
    if first_a != first_a {
        let g2 = newf(a, 50usize)
        let q2 = newf(a, 50usize)
        let gm = newf(a, n0 + 50usize)
        let qm = newf(a, n0 + 50usize)
        if g2.len == 0usize || q2.len == 0usize || gm.len == 0usize || qm.len == 0usize { ret (nan(), NoMem) }
        i = 0usize
        while i < 50usize {
            g2[i] = seqat(g1[0usize] / 20.0f64, 1.1f64 * g1[n0 - 1usize], i, 50usize)
            i += 1usize
        }
        let (a2, e2) = cdeband_regress1(a, x, y, g2, rb, ym, q2)
        if e2 != ok { ret (nan(), e2) }
        i = 0usize
        while i < n0 {
            gm[i] = g1[i]
            qm[i] = q1[i]
            i += 1usize
        }
        i = 0usize
        while i < 50usize {
            gm[n0 + i] = g2[i]
            qm[n0 + i] = q2[i]
            i += 1usize
        }
        sort_gq(gm, qm)
        first_a = a2
        ng = n0 + 50usize
        cur = gm
        curq = qm
        grid_len = 50usize
    }
    var best = first_a
    var fulla = cur
    var fullq = curq
    var nfull = ng
    if best == best {
        var lo = 0usize
        while lo < ng && cur[lo] != first_a { lo += 1usize }
        var from = 0usize
        var to = ng - 1usize
        if ng > 4usize {
            if lo >= 2usize { from = lo - 2usize }
            if lo + 2usize < ng { to = lo + 2usize }
        } else {
            if lo >= 1usize { from = lo - 1usize }
            if lo + 1usize < ng { to = lo + 1usize }
        }
        let g3 = newf(a, grid_len)
        let q3 = newf(a, grid_len)
        let gf = newf(a, ng + grid_len)
        let qf = newf(a, ng + grid_len)
        if g3.len == 0usize || q3.len == 0usize || gf.len == 0usize || qf.len == 0usize { ret (nan(), NoMem) }
        i = 0usize
        while i < grid_len {
            g3[i] = seqat(0.95f64 * cur[from], 1.05f64 * cur[to], i, grid_len)
            i += 1usize
        }
        let (a3, e3) = cdeband_regress1(a, x, y, g3, rb, ym, q3)
        if e3 != ok { ret (nan(), e3) }
        i = 0usize
        while i < ng {
            gf[i] = cur[i]
            qf[i] = curq[i]
            i += 1usize
        }
        i = 0usize
        while i < grid_len {
            gf[ng + i] = g3[i]
            qf[ng + i] = q3[i]
            i += 1usize
        }
        sort_gq(gf, qf)
        best = a3
        fulla = gf
        fullq = qf
        nfull = ng + grid_len
    }
    if best == best {
        var lo = 0usize
        while lo < nfull && fulla[lo] != best { lo += 1usize }
        var from = 0usize
        var to = nfull - 1usize
        if nfull > 4usize {
            if lo >= 2usize { from = lo - 2usize }
            if lo + 2usize < nfull { to = lo + 2usize }
        } else {
            if lo >= 1usize { from = lo - 1usize }
            if lo + 1usize < nfull { to = lo + 1usize }
        }
        var cnt = 0usize
        i = from
        while i <= to {
            if fullq[i] != 1.0f64 / 0.0f64 { cnt += 1usize }
            i += 1usize
        }
        if cnt > 3usize {
            let des = newf(a, cnt * 3usize)
            let yy = newf(a, cnt)
            if des.len == 0usize || yy.len == 0usize { ret (nan(), NoMem) }
            var r = 0usize
            i = from
            while i <= to {
                if fullq[i] != 1.0f64 / 0.0f64 {
                    des[r] = 1.0f64
                    des[cnt + r] = fulla[i]
                    des[2usize * cnt + r] = fulla[i] * fulla[i]
                    yy[r] = fullq[i]
                    r += 1usize
                }
                i += 1usize
            }
            let (fit, fe) = dc.lm_fit(a, des, cnt, 3usize, yy, 1.0e-7f64)
            if fe != ok { ret (nan(), fe) }
            let bq = 0.0f64 - 0.5f64 * fit.coef[1usize] / fit.coef[2usize]
            if bq > 0.0f64 { best = bq }
        }
    }
    gout[0usize] = f64(nfull)
    i = 0usize
    while i < nfull && i + 1usize < gout.len {
        gout[1usize + i] = fulla[i]
        i += 1usize
    }
    ret (best, ok)
}

// lm(y ~ 1 + x + .. + x^(p-1)): fitted values into fitted, returns (residual sum of squares, rank)
fn poly_fit(a: *mem.Arena, x: []const f64, y: []const f64, p: usize, fitted: []f64) -> (f64, usize, err) {
    let n = x.len
    let des = newf(a, n * p)
    if des.len == 0usize { ret (0.0f64, 0usize, NoMem) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            if j == 0usize { des[i] = 1.0f64 } else if j == 1usize { des[n + i] = x[i] } else if j == 2usize { des[2usize * n + i] = x[i] * x[i] } else { des[j * n + i] = math.pow[f64](x[i], f64(j)) }
            j += 1usize
        }
        i += 1usize
    }
    let (fit, fe) = dc.lm_fit(a, des, n, p, y, 1.0e-7f64)
    if fe != ok { ret (0.0f64, 0usize, fe) }
    var rss = 0.0f64
    i = 0usize
    while i < n {
        rss += fit.residuals[i] * fit.residuals[i]
        fitted[i] = y[i] - fit.residuals[i]
        i += 1usize
    }
    ret (rss, fit.rank, ok)
}

// cdeband.bootstrap(x, y, a.grid, b.grid, m, nx, y.margin): the grids of x and y bandwidths scored by the integrated squared error of the conditional density of parametric
// bootstrap samples (a polynomial of degree 0 to 3 chosen by AIC, normal errors); the generator r is advanced as R does; returns the best (a, b)
fn cdeband_bootstrap(a: *mem.Arena, r: *rr.Rng, x: []const f64, y: []const f64, agrid: []const f64, bgrid: []const f64, m0: usize, nx0: usize, ym: []const f64) -> (f64, f64, err) {
    let n = x.len
    let nf = f64(n)
    let ny = ym.len
    let fits = newf(a, n)
    let tryf = newf(a, n)
    if fits.len == 0usize || tryf.len == 0usize { ret (nan(), nan(), NoMem) }
    var best_aic = 0.0f64
    var rse = 0.0f64
    var p = 1usize
    while p <= 4usize {
        let (rss, rank, fe) = poly_fit(a, x, y, p, tryf)
        if fe != ok { ret (nan(), nan(), fe) }
        let df = nf - f64(rank)
        let aic = rss + 2.0f64 * (nf - df) * rss / df
        if p == 1usize || aic < best_aic {
            best_aic = aic
            rse = math.sqrt[f64](rss / df)
            var i = 0usize
            while i < n {
                fits[i] = tryf[i]
                i += 1usize
            }
        }
        p += 1usize
    }
    var nx = nx0
    let xm = newf(a, n)
    if xm.len == 0usize { ret (nan(), nan(), NoMem) }
    if n < nx0 {
        nx = n
        var i = 0usize
        while i < n {
            xm[i] = x[i]
            i += 1usize
        }
    } else {
        let (idx, se) = rr.sample_int(a, r, i64(n), i64(nx0), false)
        if se != ok { ret (nan(), nan(), se) }
        var i = 0usize
        while i < nx {
            xm[i] = x[usize(idx[i] - 1i64)]
            i += 1usize
        }
    }
    sort_f64(xm[0usize..nx])
    // approx(x, fits, xout = xm, rule = 2): x regularised (sorted, ties averaged)
    let sx = newf(a, n)
    let sf = newf(a, n)
    let ux = newf(a, n)
    let uf = newf(a, n)
    if sx.len == 0usize || sf.len == 0usize || ux.len == 0usize || uf.len == 0usize { ret (nan(), nan(), NoMem) }
    sort_pairs(x, fits, sx, sf)
    var nu = 0usize
    var i = 0usize
    while i < n {
        var j = i
        var s = 0.0f64
        while j < n && sx[j] == sx[i] {
            s += sf[j]
            j += 1usize
        }
        ux[nu] = sx[i]
        uf[nu] = s / f64(j - i)
        nu += 1usize
        i = j
    }
    let z0 = newf(a, nx * ny)
    let zb = newf(a, nx * ny)
    if z0.len == 0usize || zb.len == 0usize { ret (nan(), nan(), NoMem) }
    i = 0usize
    while i < nx {
        let fg = approx_r(ux[0usize..nu], uf[0usize..nu], 0.0f64, xm[i], true)
        var j = 0usize
        while j < ny {
            z0[i * ny + j] = dist.dnorm(ym[j], fg, rse, false)
            j += 1usize
        }
        i += 1usize
    }
    var m = m0
    if m < 5usize { m = 5usize }
    let bs = newf(a, n * m)
    if bs.len == 0usize { ret (nan(), nan(), NoMem) }
    var k = 0usize
    while k < m {
        i = 0usize
        while i < n {
            bs[k * n + i] = fits[i] + rr.rnorm(r, 0.0f64, rse)
            i += 1usize
        }
        k += 1usize
    }
    let na = agrid.len
    let nb = bgrid.len
    let imse = newf(a, na * nb)
    let diff = newf(a, m)
    if imse.len == 0usize || diff.len == 0usize { ret (nan(), nan(), NoMem) }
    var ia = 0usize
    while ia < na {
        var ib = 0usize
        while ib < nb {
            k = 0usize
            while k < 3usize {
                if cde_z(a, x, bs[k * n..k * n + n], agrid[ia], bgrid[ib], xm[0usize..nx], ym, zb) != ok { ret (nan(), nan(), NoMem) }
                diff[k] = z_diff(zb, z0) / (f64(m) * f64(nx))
                k += 1usize
            }
            imse[ia * nb + ib] = ((diff[0usize] + diff[1usize]) + diff[2usize]) / 3.0f64
            ib += 1usize
        }
        ia += 1usize
    }
    var mn = imse[0usize]
    i = 1usize
    while i < na * nb {
        if imse[i] < mn { mn = imse[i] }
        i += 1usize
    }
    // rows and columns holding exactly one minimum
    var rstar = 3usize
    var cstar = 3usize
    ia = 0usize
    while ia < na {
        var cnt = 0usize
        var ib = 0usize
        while ib < nb {
            if imse[ia * nb + ib] == mn { cnt += 1usize }
            ib += 1usize
        }
        if cnt == 1usize && ia + 1usize > rstar { rstar = ia + 1usize }
        ia += 1usize
    }
    var cb = 0usize
    while cb < nb {
        var cnt = 0usize
        ia = 0usize
        while ia < na {
            if imse[ia * nb + cb] == mn { cnt += 1usize }
            ia += 1usize
        }
        if cnt == 1usize && cb + 1usize > cstar { cstar = cb + 1usize }
        cb += 1usize
    }
    var da = 0usize
    while da < 5usize {
        let ria = rstar + da - 2usize
        if ria >= 1usize && ria <= na {
            var db = 0usize
            while db < 5usize {
                let rib = cstar + db - 2usize
                if rib >= 1usize && rib <= nb {
                    k = 3usize
                    while k < m {
                        if cde_z(a, x, bs[k * n..k * n + n], agrid[ria - 1usize], bgrid[rib - 1usize], xm[0usize..nx], ym, zb) != ok { ret (nan(), nan(), NoMem) }
                        diff[k] = z_diff(zb, z0) / (f64(m) * f64(nx))
                        k += 1usize
                    }
                    var s = 0.0f64
                    k = 3usize
                    while k < m {
                        s += diff[k]
                        k += 1usize
                    }
                    let cell = (ria - 1usize) * nb + (rib - 1usize)
                    imse[cell] = (3.0f64 * imse[cell] + f64(m - 3usize) * (s / f64(m - 3usize))) / f64(m)
                }
                db += 1usize
            }
        }
        da += 1usize
    }
    mn = imse[0usize]
    i = 1usize
    while i < na * nb {
        if imse[i] < mn { mn = imse[i] }
        i += 1usize
    }
    var bra = 0usize
    var brb = 0usize
    var found = false
    ia = 0usize
    while ia < na && !found {
        var ib2 = 0usize
        while ib2 < nb {
            if imse[ia * nb + ib2] == mn {
                found = true
                bra = ia
            }
            ib2 += 1usize
        }
        ia += 1usize
    }
    found = false
    cb = 0usize
    while cb < nb && !found {
        ia = 0usize
        while ia < na {
            if imse[ia * nb + cb] == mn {
                found = true
                brb = cb
            }
            ia += 1usize
        }
        cb += 1usize
    }
    ret (agrid[bra], bgrid[brb], ok)
}

fn z_diff(z: []const f64, z0: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < z.len {
        s += (z[i] - z0[i]) * (z[i] - z0[i])
        i += 1usize
    }
    ret s
}

// cde.bandwidths(x, y, method = 4): the bootstrap over the default grids 0.4 .. 2 by 0.2 times the rule of thumb
fn cde_bandwidths_m4(a: *mem.Arena, r: *rr.Rng, x: []const f64, y: []const f64, ym: []const f64) -> (f64, f64, err) {
    let (ra, rb) = cdeband_rules0(x, y)
    let ag = newf(a, 9usize)
    let bg = newf(a, 9usize)
    if ag.len == 0usize || bg.len == 0usize { ret (nan(), nan(), NoMem) }
    var i = 0usize
    while i < 9usize {
        let s = 0.4f64 + f64(i) * 0.2f64
        ag[i] = ra * s
        bg[i] = rb * s
        i += 1usize
    }
    let (ba, bb, be) = cdeband_bootstrap(a, r, x, y, ag, bg, 25usize, 30usize, ym)
    ret (ba, bb, be)
}

// cde.bandwidths(x, y, method = 1): two passes of cdeband.regress for a and the bootstrap for b over grids of 8
fn cde_bandwidths_m1(a: *mem.Arena, r: *rr.Rng, x: []const f64, y: []const f64, ym: []const f64) -> (f64, f64, err) {
    let (ra0, rb0) = cdeband_rules0(x, y)
    var ba = ra0
    var bb = rb0
    var ag = newf(a, 8usize)
    var bg = newf(a, 8usize)
    let gout = newf(a, 140usize)
    if ag.len == 0usize || bg.len == 0usize || gout.len == 0usize { ret (nan(), nan(), NoMem) }
    var i = 0usize
    while i < 8usize {
        ag[i] = ba * seqat(0.1f64, 3.0f64, i, 8usize)
        bg[i] = bb * seqat(0.1f64, 3.0f64, i, 8usize)
        i += 1usize
    }
    var pass = 0usize
    while pass < 2usize {
        if pass > 0usize {
            let na = usize(gout[0usize])
            var best = absf(ba - gout[1usize])
            i = 1usize
            while i < na {
                if absf(ba - gout[1usize + i]) < best { best = absf(ba - gout[1usize + i]) }
                i += 1usize
            }
            var first = 0usize
            var last = 0usize
            var seen = false
            i = 0usize
            while i < na {
                if absf(ba - gout[1usize + i]) == best {
                    if !seen { first = i }
                    last = i
                    seen = true
                }
                i += 1usize
            }
            var lo = 0usize
            if last >= 2usize { lo = last - 2usize }
            var hi = na - 1usize
            if first + 2usize < na { hi = first + 2usize }
            let nag = newf(a, 8usize)
            if nag.len == 0usize { ret (nan(), nan(), NoMem) }
            i = 0usize
            while i < 8usize {
                nag[i] = seqat(gout[1usize + lo], gout[1usize + hi], i, 8usize)
                i += 1usize
            }
            ag = nag
            let nb = bg.len
            var bbest = absf(bb - bg[0usize])
            i = 1usize
            while i < nb {
                if absf(bb - bg[i]) < bbest { bbest = absf(bb - bg[i]) }
                i += 1usize
            }
            var bfirst = 0usize
            var blast = 0usize
            seen = false
            i = 0usize
            while i < nb {
                if absf(bb - bg[i]) == bbest {
                    if !seen { bfirst = i }
                    blast = i
                    seen = true
                }
                i += 1usize
            }
            var blo = 0usize
            if blast >= 2usize { blo = blast - 2usize }
            var bhi = nb - 1usize
            if bfirst + 2usize < nb { bhi = bfirst + 2usize }
            let nbg = newf(a, 8usize)
            if nbg.len == 0usize { ret (nan(), nan(), NoMem) }
            i = 0usize
            while i < 8usize {
                nbg[i] = seqat(bg[blo], bg[bhi], i, 8usize)
                i += 1usize
            }
            bg = nbg
        }
        let (rega, re) = cdeband_regress_with(a, x, y, ym, ag, bb, gout)
        if re != ok { ret (nan(), nan(), re) }
        if rega != rega { ba = ra0 } else { ba = rega }
        let one = newf(a, 1usize)
        if one.len == 0usize { ret (nan(), nan(), NoMem) }
        one[0usize] = ba
        let (ba2, bb2, be) = cdeband_bootstrap(a, r, x, y, one, bg, 25usize, 30usize, ym)
        if be != ok { ret (nan(), nan(), be) }
        let _ = ba2
        bb = bb2
        pass += 1usize
    }
    ret (ba, bb, ok)
}

// --- modalreg with given bandwidths

fn kern1(x: f64, x0: f64, h: f64) -> f64 { ret 1.0f64 / h * dn((x0 - x) / h) }

// cond.meanshift (deg 0) or cond.linear.meanshift (deg 1)
fn meanshift(x: []const f64, y: []const f64, x0: f64, y0: f64, aa: f64, bb: f64, deg: usize) -> f64 {
    var num = 0.0f64
    var den = 0.0f64
    var sn1 = 0.0f64
    var sn2 = 0.0f64
    var i = 0usize
    if deg == 1usize {
        while i < x.len {
            sn1 += kern1(x[i], x0, aa) * (x0 - x[i])
            sn2 += kern1(x[i], x0, aa) * ((x0 - x[i]) * (x0 - x[i]))
            i += 1usize
        }
    }
    i = 0usize
    while i < x.len {
        var w = kern1(x[i], x0, aa) * kern1(y[i], y0, bb)
        if deg == 1usize { w = kern1(x[i], x0, aa) * (sn2 - (x0 - x[i]) * sn1) * kern1(y[i], y0, bb) }
        num += w * y[i]
        den += w
        i += 1usize
    }
    ret num / den
}

// the modal regression value for starting value y0 at x0: up to iter shifts, stopping at the last finite value
fn modal_fit(x: []const f64, y: []const f64, x0: f64, y0: f64, aa: f64, bb: f64, deg: usize, iter: usize) -> f64 {
    var cur = y0
    var j = 0usize
    while j < iter {
        let old = cur
        cur = meanshift(x, y, x0, cur, aa, bb, deg)
        if cur != cur { ret old }
        j += 1usize
    }
    ret cur
}

// kde2d.point(x, y, x0, y0, a, b)
fn kde2d_point(x: []const f64, y: []const f64, x0: f64, y0: f64, aa: f64, bb: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += kern1(x[i], x0, aa) * kern1(y[i], y0, bb)
        i += 1usize
    }
    ret s / f64(x.len)
}
