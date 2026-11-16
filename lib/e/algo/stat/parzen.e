// R modeest::parzen with the Gaussian kernel: statip's densityfun (the binned FFT kernel density estimate of the R before 4.4, with the kernel evaluated at offsets of
// 2 (up - lo) / (2 n - 1) and linear interpolation between the n = 512 grid values, zero outside the grid) maximised over range(x) by R's optimize (Brent's fmin).
//
// Not here: the other kernels, naive (uniform kernel on the data), vieu, lientz and tsybakov, and abc = TRUE.

use e.algo.stat.rdensity as rd
use e.math
use e.mem

const N: usize = 512usize

// the grid of the old-coordinate density: fills xords and kords (N values each); scratch holds 4 * N values
fn grid(x: []const f64, bw: f64, kernel: usize, xords: []f64, kords: []f64, scratch: []f64) {
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 0usize
    while i < x.len {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    let from = lo - 3.0f64 * bw
    let to = hi + 3.0f64 * bw
    let l = from - 4.0f64 * bw
    let u = to + 4.0f64 * bw
    let n2 = 2usize * N
    let y = scratch[0usize..n2]
    let kern = scratch[n2..2usize * n2]
    i = 0usize
    while i < n2 {
        y[i] = 0.0f64
        i += 1usize
    }
    let xdelta = (u - l) / f64(N - 1usize)
    let ixmax = N - 2usize
    i = 0usize
    while i < x.len {
        let xpos = (x[i] - l) / xdelta
        let ixf = math.floor[f64](xpos)
        let fx = xpos - ixf
        if ixf >= 0.0f64 && ixf <= f64(ixmax) {
            let ix = usize(ixf)
            y[ix] += 1.0f64 - fx
            y[ix + 1usize] += fx
        } else if ixf == 0.0f64 - 1.0f64 {
            y[0usize] += fx
        } else if ixf == f64(ixmax + 1usize) {
            y[ixmax + 1usize] += 1.0f64 - fx
        }
        i += 1usize
    }
    let step = 2.0f64 * (u - l) / f64(n2 - 1usize)
    i = 0usize
    while i < n2 {
        var off = f64(i)
        if i > N { off = f64(n2 - i) }
        let d = off * step
        if kernel == 0usize {
            kern[i] = math.exp[f64](0.0f64 - d * d / (2.0f64 * bw * bw)) / (bw * math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64))
        } else {
            // the uniform kernel 1 / 2 on |u| < 1, scaled by 1 / bw
            var kv = 0.0f64
            if d / bw < 1.0f64 { kv = 0.5f64 }
            kern[i] = kv / bw
        }
        i += 1usize
    }
    var j = 0usize
    while j < N {
        var s = 0.0f64
        var k = 0usize
        while k < n2 {
            var idx = k + n2 - j
            if idx >= n2 { idx -= n2 }
            s += y[k] * kern[idx]
            k += 1usize
        }
        var v = s / f64(x.len)
        if v < 0.0f64 { v = 0.0f64 }
        kords[j] = v
        xords[j] = l + (u - l) * f64(j) / f64(N - 1usize)
        j += 1usize
    }
}

// the interpolated density at z (zero outside the grid)
fn at(xords: []const f64, kords: []const f64, z: f64) -> f64 {
    if z < xords[0usize] || z > xords[N - 1usize] { ret 0.0f64 }
    let step = xords[1usize] - xords[0usize]
    var i = usize(math.floor[f64]((z - xords[0usize]) / step))
    if i >= N - 1usize { i = N - 2usize }
    let t = (z - xords[i]) / (xords[i + 1usize] - xords[i])
    ret kords[i] + t * (kords[i + 1usize] - kords[i])
}

// R's Brent_fmin on the negated density over [ax, bx]: the maximiser, to tolerance tol
fn fmin_max(xords: []const f64, kords: []const f64, ax: f64, bx: f64, tol: f64) -> f64 {
    let c = (3.0f64 - math.sqrt[f64](5.0f64)) * 0.5f64
    let eps = math.sqrt[f64](2.220446049250313e-16f64)
    var a = ax
    var b = bx
    var v = a + c * (b - a)
    var w = v
    var x = v
    var d = 0.0f64
    var e = 0.0f64
    var fx = 0.0f64 - at(xords, kords, x)
    var fv = fx
    var fw = fx
    let tol3 = tol / 3.0f64
    var guard = 0usize
    while guard < 1000usize {
        guard += 1usize
        let xm = (a + b) * 0.5f64
        let tol1 = eps * math.abs[f64](x) + tol3
        let t2 = tol1 * 2.0f64
        if math.abs[f64](x - xm) <= t2 - (b - a) * 0.5f64 { break }
        var p = 0.0f64
        var q = 0.0f64
        var r = 0.0f64
        if math.abs[f64](e) > tol1 {
            r = (x - w) * (fx - fv)
            q = (x - v) * (fx - fw)
            p = (x - v) * q - (x - w) * r
            q = (q - r) * 2.0f64
            if q > 0.0f64 { p = 0.0f64 - p } else { q = 0.0f64 - q }
            r = e
            e = d
        }
        var u = 0.0f64
        if math.abs[f64](p) >= math.abs[f64](q * 0.5f64 * r) || p <= q * (a - x) || p >= q * (b - x) {
            if x < xm { e = b - x } else { e = a - x }
            d = c * e
        } else {
            d = p / q
            u = x + d
            if u - a < t2 || b - u < t2 {
                d = tol1
                if x >= xm { d = 0.0f64 - d }
            }
        }
        if math.abs[f64](d) >= tol1 {
            u = x + d
        } else if d > 0.0f64 {
            u = x + tol1
        } else {
            u = x - tol1
        }
        let fu = 0.0f64 - at(xords, kords, u)
        if fu <= fx {
            if u < x { b = x } else { a = x }
            v = w
            w = x
            x = u
            fv = fw
            fw = fx
            fx = fu
        } else {
            if u < x { a = u } else { b = u }
            if fu <= fw || w == x {
                v = w
                fv = fw
                w = u
                fw = fu
            } else if fu <= fv || v == x || v == w {
                v = u
                fv = fu
            }
        }
    }
    ret x
}

// parzen(x, bw): bw <= 0 means "nrd0"; the optimize tolerance is eps^0.25
fn parzen(a: *mem.Arena, x: []const f64, bw0: f64) -> f64 {
    let (s, e0) = mem.alloc[f64](a, x.len)
    if e0 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    var bw = bw0
    if bw <= 0.0f64 { bw = rd.bw_nrd0(x, s) }
    let (xo, e1) = mem.alloc[f64](a, N)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (ko, e2) = mem.alloc[f64](a, N)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let (sc, e3) = mem.alloc[f64](a, 4usize * N)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    grid(x, bw, 0usize, xo, ko, sc)
    ret fmin_max(xo, ko, s[0usize], s[x.len - 1usize], math.pow[f64](2.220446049250313e-16f64, 0.25f64))
}

// naive(x, bw): the data points where the interpolated rectangular-kernel density (default bw 0.5) is largest; the number of such points and, through `which`, the first of them
fn naive(a: *mem.Arena, x: []const f64, bw: f64, which: usize) -> f64 {
    let (xo, e1) = mem.alloc[f64](a, N)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (ko, e2) = mem.alloc[f64](a, N)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let (sc, e3) = mem.alloc[f64](a, 4usize * N)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    grid(x, bw, 1usize, xo, ko, sc)
    var best = 0.0f64 - 1.0f64
    var i = 0usize
    while i < x.len {
        let v = at(xo, ko, x[i])
        if v > best { best = v }
        i += 1usize
    }
    var cnt = 0.0f64
    var first = 0.0f64
    var have = false
    i = 0usize
    while i < x.len {
        if at(xo, ko, x[i]) == best {
            cnt += 1.0f64
            if !have {
                first = x[i]
                have = true
            }
        }
        i += 1usize
    }
    if which == 0usize { ret cnt }
    ret first
}

// modeest vieu with the Gaussian kernel: the sum over x of the kernel derivative at (z - x) / bw
fn vieu_sum(x: []const f64, bw: f64, z: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        let u = (z - x[i]) / bw
        s += 0.0f64 - u * math.exp[f64](0.0f64 - u * u / 2.0f64) / math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64)
        i += 1usize
    }
    ret s
}

// vieu(x, bw): the root of vieu_sum over range(x) by R's uniroot (R_zeroin2, tol eps^0.25, 1000 iterations); bw <= 0 means "nrd0"
fn vieu(a: *mem.Arena, x: []const f64, bw0: f64) -> f64 {
    let (s, e0) = mem.alloc[f64](a, x.len)
    if e0 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    var bw = bw0
    if bw <= 0.0f64 { bw = rd.bw_nrd0(x, s) }
    let eps = 2.220446049250313e-16f64
    let tol = math.pow[f64](eps, 0.25f64)
    var lo = s[0usize]
    var hi = s[x.len - 1usize]
    var fa = vieu_sum(x, bw, lo)
    var fb = vieu_sum(x, bw, hi)
    var b = hi
    var cc = lo
    var aa = lo
    var fc = fa
    if fa == 0.0f64 { ret lo }
    if fb == 0.0f64 { ret hi }
    var maxit = 1001i64
    while maxit > 0i64 {
        maxit -= 1i64
        let prev_step = b - aa
        if math.abs[f64](fc) < math.abs[f64](fb) {
            aa = b
            b = cc
            cc = aa
            fa = fb
            fb = fc
            fc = fa
        }
        let tol_act = 2.0f64 * eps * math.abs[f64](b) + tol / 2.0f64
        var new_step = (cc - b) / 2.0f64
        if math.abs[f64](new_step) <= tol_act || fb == 0.0f64 { ret b }
        if math.abs[f64](prev_step) >= tol_act && math.abs[f64](fa) > math.abs[f64](fb) {
            let cb = cc - b
            var p = 0.0f64
            var q = 0.0f64
            if aa == cc {
                let t1 = fb / fa
                p = cb * t1
                q = 1.0f64 - t1
            } else {
                q = fa / fc
                let t1 = fb / fc
                let t2 = fb / fa
                p = t2 * (cb * q * (q - t1) - (b - aa) * (t1 - 1.0f64))
                q = (q - 1.0f64) * (t1 - 1.0f64) * (t2 - 1.0f64)
            }
            if p > 0.0f64 { q = 0.0f64 - q } else { p = 0.0f64 - p }
            if p < (0.75f64 * cb * q - math.abs[f64](tol_act * q) / 2.0f64) && p < math.abs[f64](prev_step * q / 2.0f64) { new_step = p / q }
        }
        if math.abs[f64](new_step) < tol_act {
            if new_step > 0.0f64 { new_step = tol_act } else { new_step = 0.0f64 - tol_act }
        }
        aa = b
        fa = fb
        b += new_step
        fb = vieu_sum(x, bw, b)
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            cc = aa
            fc = fa
        }
    }
    ret b
}
