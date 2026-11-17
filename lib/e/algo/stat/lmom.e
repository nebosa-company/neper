// R lmom: `samlmu` (sample L-moments l1 .. l5 and the ratios, from the unbiased probability-weighted moments of the
// sorted data), and the closed-form distributions: `lmr` (the first four L-moments and ratios), `qua` (quantile
// function) and `pel` (parameters from the L-moments) for the exponential (0), Gumbel (1), generalised logistic (2),
// generalised Pareto (3), normal (4) and generalised extreme value (5, `lmr` and `qua` only) distributions.
//
// Not here: trimmed L-moments, Hosking's iterative GEV, Pearson III, lognormal, Wakeby and kappa fits, the cdf
// functions, and the generalised lambda distribution of gld.

use e.algo.sort
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn euler() -> f64 { ret 0.5772156649015328606f64 }
fn pi() -> f64 { ret 3.141592653589793f64 }

// samlmu(x, nmom <= 5): l[0..nmom] unsorted-input safe; ratios turns l3.. into l / l2
fn samlmu(a: *mem.Arena, x: []const f64, nmom: usize, ratios: bool, out: []f64) -> err {
    let n = x.len
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        s[i] = x[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    var b: [5]f64 = zero
    var r = 0usize
    while r < nmom {
        var acc = 0.0f64
        i = 0usize
        while i < n {
            // C(i, r) / C(n - 1, r) for the i-th order statistic (0-based)
            var w = 1.0f64
            var k = 0usize
            while k < r {
                w = w * (f64(i) - f64(k)) / (f64(n - 1usize) - f64(k))
                k += 1usize
            }
            acc += w * s[i]
            i += 1usize
        }
        b[r] = acc / f64(n)
        r += 1usize
    }
    out[0usize] = b[0usize]
    if nmom > 1usize { out[1usize] = 2.0f64 * b[1usize] - b[0usize] }
    if nmom > 2usize { out[2usize] = 6.0f64 * b[2usize] - 6.0f64 * b[1usize] + b[0usize] }
    if nmom > 3usize { out[3usize] = 20.0f64 * b[3usize] - 30.0f64 * b[2usize] + 12.0f64 * b[1usize] - b[0usize] }
    if nmom > 4usize { out[4usize] = 70.0f64 * b[4usize] - 140.0f64 * b[3usize] + 90.0f64 * b[2usize] - 20.0f64 * b[1usize] + b[0usize] }
    if ratios && nmom > 2usize {
        var j = 2usize
        while j < nmom {
            out[j] = out[j] / out[1usize]
            j += 1usize
        }
    }
    ret ok
}

// lmr(dist, para): out = (l1, l2, t3, t4); para = (xi, alpha, k) (exp: xi, alpha; gum: xi, alpha; nor: mu, sigma)
fn lmr(kind: u8, xi: f64, alpha: f64, k: f64, out: []f64) {
    if kind == 0u8 {
        out[0usize] = xi + alpha
        out[1usize] = alpha / 2.0f64
        out[2usize] = 1.0f64 / 3.0f64
        out[3usize] = 1.0f64 / 6.0f64
    } else if kind == 1u8 {
        out[0usize] = xi + euler() * alpha
        out[1usize] = alpha * math.log[f64](2.0f64)
        out[2usize] = 2.0f64 * math.log[f64](3.0f64) / math.log[f64](2.0f64) - 3.0f64
        out[3usize] = 16.0f64 - 10.0f64 * math.log[f64](3.0f64) / math.log[f64](2.0f64)
    } else if kind == 2u8 {
        let g = pi() * k / math.sin(pi() * k)
        out[0usize] = xi + alpha * (1.0f64 - g) / k
        out[1usize] = alpha * g
        out[2usize] = 0.0f64 - k
        out[3usize] = (1.0f64 + 5.0f64 * k * k) / 6.0f64
    } else if kind == 3u8 {
        out[0usize] = xi + alpha / (1.0f64 + k)
        out[1usize] = alpha / ((1.0f64 + k) * (2.0f64 + k))
        out[2usize] = (1.0f64 - k) / (3.0f64 + k)
        out[3usize] = (1.0f64 - k) * (2.0f64 - k) / ((3.0f64 + k) * (4.0f64 + k))
    } else if kind == 4u8 {
        out[0usize] = xi
        out[1usize] = alpha / math.sqrt[f64](pi())
        out[2usize] = 0.0f64
        out[3usize] = 30.0f64 * math.atan[f64](math.sqrt[f64](2.0f64)) / pi() - 9.0f64
    } else {
        let g = nm.gammafn(1.0f64 + k)
        let d1 = 1.0f64 - math.pow[f64](2.0f64, 0.0f64 - k)
        let d2 = 1.0f64 - math.pow[f64](3.0f64, 0.0f64 - k)
        let d3 = 1.0f64 - math.pow[f64](4.0f64, 0.0f64 - k)
        out[0usize] = xi + alpha * (1.0f64 - g) / k
        out[1usize] = alpha * d1 * g / k
        out[2usize] = 2.0f64 * d2 / d1 - 3.0f64
        out[3usize] = (5.0f64 * d3 - 10.0f64 * d2 + 6.0f64 * d1) / d1
    }
}

// qua(f, dist, para)
fn qua(kind: u8, f: f64, xi: f64, alpha: f64, k: f64) -> f64 {
    if kind == 0u8 { ret xi - alpha * math.log[f64](1.0f64 - f) }
    if kind == 1u8 { ret xi - alpha * math.log[f64](0.0f64 - math.log[f64](f)) }
    if kind == 2u8 { ret xi + alpha * (1.0f64 - math.pow[f64]((1.0f64 - f) / f, k)) / k }
    if kind == 3u8 { ret xi + alpha * (1.0f64 - math.pow[f64](1.0f64 - f, k)) / k }
    if kind == 4u8 { ret dist.qnorm(f, xi, alpha, true, false) }
    ret xi + alpha * (1.0f64 - math.pow[f64](0.0f64 - math.log[f64](f), k)) / k
}

// cdf(x, dist, para): the distribution function (the GEV, GLO and GPD through the reduced variate y, a positive-part clip inside the logarithm)
fn cdf(kind: u8, x: f64, xi: f64, alpha: f64, k: f64) -> f64 {
    if kind == 0u8 {
        var d = x - xi
        if d < 0.0f64 { d = 0.0f64 }
        ret 1.0f64 - math.exp[f64](0.0f64 - d / alpha)
    }
    if kind == 1u8 { ret math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - (x - xi) / alpha)) }
    if kind == 4u8 { ret dist.pnorm(x, xi, alpha, true, false) }
    var y = (x - xi) / alpha
    if k != 0.0f64 {
        var inner = 1.0f64 - k * (x - xi) / alpha
        if inner < 0.0f64 { inner = 0.0f64 }
        y = 0.0f64 - 1.0f64 / k * math.log[f64](inner)
    }
    if kind == 2u8 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - y)) }
    if kind == 3u8 {
        var yp = y
        if yp < 0.0f64 { yp = 0.0f64 }
        ret 1.0f64 - math.exp[f64](0.0f64 - yp)
    }
    ret math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - y))
}

// pel(dist, lmom = (l1, l2, t3)): out = (xi, alpha, k)
fn pel(kind: u8, l1: f64, l2: f64, t3: f64, out: []f64) {
    if kind == 0u8 {
        out[1usize] = 2.0f64 * l2
        out[0usize] = l1 - out[1usize]
        out[2usize] = 0.0f64
    } else if kind == 1u8 {
        out[1usize] = l2 / math.log[f64](2.0f64)
        out[0usize] = l1 - euler() * out[1usize]
        out[2usize] = 0.0f64
    } else if kind == 2u8 {
        let k = 0.0f64 - t3
        let g = pi() * k / math.sin(pi() * k)
        out[2usize] = k
        out[1usize] = l2 / g
        out[0usize] = l1 - out[1usize] * (1.0f64 - g) / k
    } else if kind == 3u8 {
        let k = (1.0f64 - 3.0f64 * t3) / (1.0f64 + t3)
        out[2usize] = k
        out[1usize] = (1.0f64 + k) * (2.0f64 + k) * l2
        out[0usize] = l1 - (2.0f64 + k) * l2
    } else {
        out[0usize] = l1
        out[1usize] = l2 * math.sqrt[f64](pi())
        out[2usize] = 0.0f64
    }
}
