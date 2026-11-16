// R modeest, the location-of-the-mode estimators that need no density: `venter` (the midpoint, the order
// statistic, the median or the mean of the shortest half, and Ekblom's rule), `hsm` (the half-sample mode),
// `grenander` (the power-weighted mode), `meanshift` (Gaussian kernel from the shorth, bandwidth bw.nrd0) and
// `asselin` (Asselin de Beauville's trimming). Ties among equally short intervals take the mean index, truncated,
// as R indexes with a fractional position.
//
// Not here: parzen, naive, vieu, lientz and tsybakov (they need statip's kernel density functions), and the other
// bandwidth rules of meanshift.

use e.algo.sort
use e.algo.stat.mass as ms
use e.math
use e.mem

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn sorted_copy(a: *mem.Arena, v: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < v.len {
        s[i] = v[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    ret (s, ok)
}

// the 1-based start of the shortest window of k + 1 order statistics of the sorted y, ties by the truncated mean index
fn shortest_start(y: []const f64, k: usize) -> usize {
    let n = y.len
    var best = 1.0e300f64
    var j = 0usize
    while j + k < n {
        let d = y[j + k] - y[j]
        if d < best { best = d }
        j += 1usize
    }
    var sum = 0.0f64
    var cnt = 0.0f64
    j = 0usize
    while j + k < n {
        if y[j + k] - y[j] == best {
            sum += f64(j + 1usize)
            cnt += 1.0f64
        }
        j += 1usize
    }
    ret usize(math.floor[f64](sum / cnt))
}

fn median_of(y: []const f64) -> f64 {
    let n = y.len
    if n % 2usize == 1usize { ret y[n / 2usize] }
    ret (y[n / 2usize - 1usize] + y[n / 2usize]) / 2.0f64
}

// venter(x, type): 1 midpoint, 2 order statistic, 3 dalenius (median), 4 shorth (mean), 5 ekblom; k < 0 means the default
fn venter(a: *mem.Arena, x: []const f64, kind: u8, kin: i64) -> (f64, err) {
    let (y, e) = sorted_copy(a, x)
    if e != ok { ret (0.0f64, e) }
    let n = y.len
    var k = usize(math.ceil[f64](f64(n) / 2.0f64)) - 1usize
    if kind == 5u8 { k = 1usize }
    if kin >= 0i64 { k = usize(kin) }
    let i = shortest_start(y, k)
    if kind == 1u8 { ret ((y[i - 1usize] + y[i - 1usize + k]) / 2.0f64, ok) }
    if kind == 2u8 { ret (y[i - 1usize + (k + 1usize) / 2usize], ok) }
    if kind == 3u8 { ret (median_of(y[i - 1usize..i + k]), ok) }
    if kind == 4u8 {
        var s = 0.0f64
        var j = i - 1usize
        while j < i + k {
            s += y[j]
            j += 1usize
        }
        ret (s / f64(k + 1usize), ok)
    }
    if i < 2usize { ret (0.0f64 / 0.0f64, ok) }
    if y[i + 1usize] - y[i] > y[i - 1usize] - y[i - 2usize] { ret (y[i - 1usize], ok) }
    ret (y[i], ok)
}

// hsm(x, bw = 0.5)
fn hsm(a: *mem.Arena, x: []const f64, bw: f64) -> (f64, err) {
    let (y0, e) = sorted_copy(a, x)
    if e != ok { ret (0.0f64, e) }
    var lo = 0usize
    var len = y0.len
    while len >= 4usize {
        let k = usize(math.ceil[f64](bw * f64(len))) - 1usize
        let i = shortest_start(y0[lo..lo + len], k)
        let d = y0[lo + i - 1usize + k] - y0[lo + i - 1usize]
        if d == 0.0f64 {
            lo = lo + i - 1usize
            len = 1usize
        } else {
            lo = lo + i - 1usize
            len = k + 1usize
        }
    }
    if len == 3usize {
        let z = 2.0f64 * y0[lo + 1usize] - y0[lo] - y0[lo + 2usize]
        if z < 0.0f64 { ret ((y0[lo] + y0[lo + 1usize]) / 2.0f64, ok) }
        if z > 0.0f64 { ret ((y0[lo + 1usize] + y0[lo + 2usize]) / 2.0f64, ok) }
        ret (y0[lo + 1usize], ok)
    }
    var s = 0.0f64
    var j = 0usize
    while j < len {
        s += y0[lo + j]
        j += 1usize
    }
    ret (s / f64(len), ok)
}

// grenander(x, p) with the default k = ceiling(n / 2) - 1
fn grenander(a: *mem.Arena, x: []const f64, p: f64) -> (f64, err) {
    let (y, e) = sorted_copy(a, x)
    if e != ok { ret (0.0f64, e) }
    let n = y.len
    let k = usize(math.ceil[f64](f64(n) / 2.0f64)) - 1usize
    var zero_sum = 0.0f64
    var zero_cnt = 0.0f64
    var b = 0.0f64
    var aa = 0.0f64
    var j = 0usize
    while j + k < n {
        let d = y[j + k] - y[j]
        let t = y[j] + y[j + k]
        if d == 0.0f64 {
            zero_sum += t
            zero_cnt += 1.0f64
        }
        b += t / math.pow[f64](d, p)
        aa += 1.0f64 / math.pow[f64](d, p)
        j += 1usize
    }
    if zero_cnt > 0.0f64 { ret (zero_sum / zero_cnt / 2.0f64, ok) }
    ret (b / 2.0f64 / aa, ok)
}

// bw.nrd0
fn bw_nrd0(a: *mem.Arena, x: []const f64) -> (f64, err) {
    let (y, e) = sorted_copy(a, x)
    if e != ok { ret (0.0f64, e) }
    let n = f64(y.len)
    var m = 0.0f64
    var i = 0usize
    while i < y.len {
        m += y[i]
        i += 1usize
    }
    m = m / n
    var ss = 0.0f64
    i = 0usize
    while i < y.len {
        ss += (y[i] - m) * (y[i] - m)
        i += 1usize
    }
    let hi = math.sqrt[f64](ss / (n - 1.0f64))
    var lo = (ms.quant7(y, 0.75f64) - ms.quant7(y, 0.25f64)) / 1.34f64
    if hi < lo { lo = hi }
    if lo == 0.0f64 {
        lo = hi
        if lo == 0.0f64 { lo = math.abs[f64](y[0usize]) }
        if lo == 0.0f64 { lo = 1.0f64 }
    }
    ret (0.9f64 * lo * math.pow[f64](n, 0.0f64 - 0.2f64), ok)
}

// meanshift(x, kernel = "gaussian", bw = "nrd0", par = shorth(x)): the iterate and the iteration count
fn meanshift(a: *mem.Arena, x: []const f64) -> (f64, usize, err) {
    let (bw, be) = bw_nrd0(a, x)
    if be != ok { ret (0.0f64, 0usize, be) }
    let (p0, pe) = venter(a, x, 4u8, 0i64 - 1i64)
    if pe != ok { ret (0.0f64, 0usize, pe) }
    var par = p0
    var it = 1usize
    while it <= 1000usize {
        var sk = 0.0f64
        var sxk = 0.0f64
        var i = 0usize
        while i < x.len {
            let z = (x[i] - par) / bw
            let k = math.exp[f64](0.0f64 - z * z / 2.0f64)
            sk += k
            sxk += x[i] * k
            i += 1usize
        }
        let m = sxk / sk
        let th = math.abs[f64](m / par - 1.0f64)
        if th < 1.4901161193847656e-8f64 { ret (par, it, ok) }
        par = m
        it += 1usize
    }
    ret (par, 0usize, ok)
}

// sum of n[from], n[from +- 1], ..., n[to] following R's `from:to` (ascending or descending; index 0 contributes nothing); 1-based
fn rsum(n: []const f64, from: usize, to: usize) -> f64 {
    var s = 0.0f64
    if from <= to {
        var j = from
        while j <= to {
            if j >= 1usize { s += n[j - 1usize] }
            j += 1usize
        }
    } else {
        var j = from
        while j >= to {
            if j >= 1usize { s += n[j - 1usize] }
            if j == 0usize { break }
            j -= 1usize
        }
    }
    ret s
}

// asselin(x, bw = 1); NaN where R stops with `k < 3`
fn asselin(a: *mem.Arena, x: []const f64) -> (f64, err) {
    let nan = 0.0f64 / 0.0f64
    let nx = x.len
    var mult = 15.0f64
    if nx < 30usize { mult = 10.0f64 }
    let kmax = usize(math.floor[f64](mult * math.log[f64](f64(nx))))
    let (y0, e0) = sorted_copy(a, x)
    let (yab, e1) = mem.alloc[f64](a, nx)
    let (cnt, e2) = mem.alloc[f64](a, nx + kmax + 4usize)
    let (v, e3) = mem.alloc[f64](a, nx + kmax + 4usize)
    let (bk, e4) = mem.alloc[f64](a, nx + kmax + 4usize)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (nan, e0) }
    var ylo = 0usize
    var ylen = nx
    var ok1 = false
    var result = nan
    while !ok1 {
        let y = y0[ylo..ylo + ylen]
        let ny0 = ylen
        if ylen == 1usize { ret (y[0usize], ok) }
        let q1 = ms.quant7(y, 0.1f64)
        let q2 = ms.quant7(y, 0.25f64)
        let q3 = ms.quant7(y, 0.5f64)
        let q4 = ms.quant7(y, 0.75f64)
        let q5 = ms.quant7(y, 0.9f64)
        var delta = q5 - q4
        if q2 - q1 < delta { delta = q2 - q1 }
        let alo = q1 - 3.0f64 * delta
        let ahi = q5 + 3.0f64 * delta
        var ny = 0usize
        var i = 0usize
        while i < ylen {
            if y[i] >= alo && y[i] <= ahi {
                yab[ny] = y[i]
                ny += 1usize
            }
            i += 1usize
        }
        let ya = yab[0usize..ny]
        var k = kmax
        var ok2 = false
        var w = 1usize
        var w2 = 1usize
        while !ok2 {
            // b = seq(min, max, length = k + 1)
            let mn = ya[0usize]
            let mx = ya[ny - 1usize]
            i = 0usize
            while i <= k {
                bk[i] = mn + f64(i) * ((mx - mn) / f64(k))
                i += 1usize
            }
            bk[k] = mx
            i = 0usize
            while i <= k {
                cnt[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < ny {
                // findInterval(yab, b[-(k + 1)]): the count of b[1..k] <= value
                var c = 0usize
                while c < k && bk[c] <= ya[i] { c += 1usize }
                if c >= 1usize { cnt[c - 1usize] += 1.0f64 }
                i += 1usize
            }
            var total = 0.0f64
            i = 0usize
            while i <= k {
                total += cnt[i]
                i += 1usize
            }
            i = 0usize
            while i <= k {
                if cnt[i] >= total / f64(k) { v[i] = 1.0f64 } else { v[i] = 0.0f64 }
                i += 1usize
            }
            // w = which.max(v), w2 = which.min(v[w:(k + 1)]) + w - 1
            w = 1usize
            i = 0usize
            while i <= k {
                if v[i] > v[w - 1usize] { w = i + 1usize }
                i += 1usize
            }
            var m2 = w
            i = w
            while i <= k + 1usize {
                if v[i - 1usize] < v[m2 - 1usize] { m2 = i }
                i += 1usize
            }
            w2 = m2
            var any1 = false
            i = w2
            while i <= k + 1usize {
                if v[i - 1usize] == 1.0f64 { any1 = true }
                i += 1usize
            }
            let nc = rsum(cnt, w, w2 - 1usize)
            if any1 && nc == 1.0f64 {
                if k > 3usize {
                    k -= 1usize
                } else if k == 3usize {
                    if cnt[2usize] > 1.0f64 {
                        w = 3usize
                        w2 = 4usize
                    }
                    ok2 = true
                } else {
                    ret (nan, ok)
                }
            } else if any1 && nc > 1.0f64 {
                if k > 3usize {
                    k -= 1usize
                } else if k == 3usize {
                    if cnt[2usize] > 1.0f64 {
                        var p1 = 1.0f64 / cnt[0usize]
                        var p2 = 1.0f64 / cnt[2usize]
                        var prev1 = 0.0f64
                        var have1 = false
                        var prev2 = 0.0f64
                        var have2 = false
                        i = 0usize
                        while i < ny {
                            if ya[i] >= bk[w - 1usize] && ya[i] <= bk[w2 - 1usize] {
                                if have1 { p1 = p1 * (ya[i] - prev1) }
                                prev1 = ya[i]
                                have1 = true
                            }
                            if ya[i] >= bk[2usize] && ya[i] <= bk[3usize] {
                                if have2 { p2 = p2 * (ya[i] - prev2) }
                                prev2 = ya[i]
                                have2 = true
                            }
                            i += 1usize
                        }
                        if p1 > p2 {
                            w = 3usize
                            w2 = 4usize
                        }
                    }
                    ok2 = true
                } else {
                    ret (nan, ok)
                }
            } else if !any1 {
                ok2 = true
            }
        }
        let nc = rsum(cnt, w, w2 - 1usize)
        var d = (q4 + q2 - 2.0f64 * q3) / (q4 - q2)
        if d < 0.0f64 { d = 0.0f64 - d }
        let nc2 = f64(ny0) * (1.0f64 - d)
        // y <- yab[yab >= b[w] & yab <= b[w2]], written back over the working sample
        var out = 0usize
        i = 0usize
        while i < ny {
            if ya[i] >= bk[w - 1usize] && ya[i] <= bk[w2 - 1usize] {
                y0[ylo + out] = ya[i]
                out += 1usize
            }
            i += 1usize
        }
        ylen = out
        if nc == f64(ny0) { ok1 = true } else {
            var lim = nc2
            if nx < 30usize { lim = f64(nx) / 3.0f64 }
            if nc <= lim { ok1 = true }
        }
        result = median_of(y0[ylo..ylo + ylen])
    }
    ret (result, ok)
}

// tsybakov(x, kernel, dmp, alpha) with the default bandwidths (1 .. n)^(-1/7), the steps a_n = n^(-alpha) and the start shorth(x); kernel 0 triangular (derivative -sign(u) for |u| <= 1), 1 gaussian
fn tsybakov(a: *mem.Arena, x: []const f64, kernel: usize, dmp: bool, alpha: f64) -> f64 {
    let (par, e) = venter(a, x, 4u8, 0i64 - 1i64)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let n = x.len
    var m = par
    var mdmp = par
    var cum = 0.0f64
    var i = 1usize
    while i <= n {
        let bw = math.pow[f64](f64(i), 0.0f64 - 1.0f64 / 7.0f64)
        let an = math.pow[f64](f64(i), 0.0f64 - alpha)
        let bn = an / (bw * bw)
        let pn = bw * bw * bw
        cum += pn
        let u = (m - x[i - 1usize]) / bw
        var k = 0.0f64
        if kernel == 0usize {
            if math.abs[f64](u) <= 1.0f64 {
                if u > 0.0f64 { k = 0.0f64 - 1.0f64 }
                if u < 0.0f64 { k = 1.0f64 }
            }
        } else {
            k = 0.0f64 - u * math.exp[f64](0.0f64 - u * u / 2.0f64) / math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64)
        }
        m = m + bn * k
        mdmp = mdmp + (pn / cum) * (m - mdmp)
        i += 1usize
    }
    if dmp { ret mdmp }
    ret m
}

// lientz(x, bw) evaluated at z: the distance from z to the nearest half-sample mode candidate of the sorted sample (k = ceiling(bw n) - 1)
fn lientz(a: *mem.Arena, x: []const f64, bw: f64, z: f64) -> f64 {
    let (y, e) = sorted_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let ny = y.len
    let k = usize(math.ceil[f64](bw * f64(ny))) - 1usize
    let inf = 1.0f64 / 0.0f64
    if k == 0usize {
        // yy_i = (y_i + y_{i+1}) / 2 with +Inf past the end; i = first index with z <= yy_i
        var i = 0usize
        while i < ny {
            var nx = inf
            if i + 1usize < ny { nx = y[i + 1usize] }
            let yy = (y[i] + nx) / 2.0f64
            if z <= yy { ret math.abs[f64](y[i] - z) }
            i += 1usize
        }
        ret 0.0f64 / 0.0f64
    }
    // the sorted vector of (y_i + y_{i+k}) / 2 and (y_i + y_{i+k+1}) / 2, +Inf past the end
    let (yy, e2) = mem.alloc[f64](a, 2usize * ny)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < ny {
        var y1 = inf
        if i + k < ny { y1 = y[i + k] }
        var y2 = inf
        if i + k + 1usize < ny { y2 = y[i + k + 1usize] }
        yy[i] = (y[i] + y1) / 2.0f64
        yy[ny + i] = (y[i] + y2) / 2.0f64
        i += 1usize
    }
    i = 1usize
    while i < 2usize * ny {
        let t = yy[i]
        var j = i
        while j > 0usize && yy[j - 1usize] > t {
            yy[j] = yy[j - 1usize]
            j -= 1usize
        }
        yy[j] = t
        i += 1usize
    }
    var idx = 0usize
    while idx < 2usize * ny {
        if z <= yy[idx] { break }
        idx += 1usize
    }
    let one = idx + 1usize
    let jj = one % 2usize
    let pos = jj * k + (one + jj) / 2usize
    let val = y[pos - 1usize]
    if jj == 1usize { ret val - z }
    ret z - val
}
