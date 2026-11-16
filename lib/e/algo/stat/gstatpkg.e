// R gstat: single-structure variogram models (vgm with Sph, Exp, Gau and Lin plus a nugget), the empirical omnidirectional variogram of variogram(z ~ 1, ~x + y, cutoff, width),
// and ordinary kriging with a given model (prediction and variance).
//
// Not here: anisotropy, directional variograms, nested structures, the other model families, model fitting, simple and universal kriging, co-kriging and the spatio-temporal functions.

use e.algo.stat.carlmtest as ols
use e.math
use e.mem

// the semivariance at distance h of a model (0 Sph, 1 Exp, 2 Gau, 3 Lin) with partial sill, range and nugget; zero at h = 0
fn vgm_gamma(model: usize, psill: f64, range: f64, nugget: f64, h: f64) -> f64 {
    if h <= 0.0f64 { ret 0.0f64 }
    let u = h / range
    if model == 0usize {
        if u >= 1.0f64 { ret nugget + psill }
        ret nugget + psill * (1.5f64 * u - 0.5f64 * u * u * u)
    }
    if model == 1usize { ret nugget + psill * (1.0f64 - math.exp[f64](0.0f64 - u)) }
    if model == 2usize { ret nugget + psill * (1.0f64 - math.exp[f64](0.0f64 - u * u)) }
    if u >= 1.0f64 { ret nugget + psill }
    ret nugget + psill * u
}

fn pair_dist(xy: []const f64, i: usize, j: usize) -> f64 {
    let dx = xy[2usize * i] - xy[2usize * j]
    let dy = xy[2usize * i + 1usize] - xy[2usize * j + 1usize]
    ret math.sqrt[f64](dx * dx + dy * dy)
}

// the empirical variogram: bin b (floor(d / width), d < cutoff) as (np, mean distance, gamma = half the mean squared difference); np is 0 when the bin is empty
fn empirical_variogram(xy: []const f64, z: []const f64, n: usize, cutoff: f64, width: f64, b: usize) -> (f64, f64, f64) {
    var np = 0.0f64
    var sd = 0.0f64
    var sg = 0.0f64
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            let d = pair_dist(xy, i, j)
            if d <= cutoff && usize(math.floor[f64](d / width)) == b {
                np += 1.0f64
                sd += d
                sg += (z[i] - z[j]) * (z[i] - z[j])
            }
            j += 1usize
        }
        i += 1usize
    }
    if np == 0.0f64 { ret (0.0f64, 0.0f64, 0.0f64) }
    ret (np, sd / np, sg / (2.0f64 * np))
}

// ordinary kriging at (px, py): part 0 the prediction, 1 the kriging variance
fn ordinary_krige(a: *mem.Arena, xy: []const f64, z: []const f64, n: usize, model: usize, psill: f64, range: f64, nugget: f64, px: f64, py: f64, part: usize) -> f64 {
    let m = n + 1usize
    let (g, e1) = mem.alloc[f64](a, m * m)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (gi, e2) = mem.alloc[f64](a, m * m)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let (rhs, e3) = mem.alloc[f64](a, m)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            g[i * m + j] = vgm_gamma(model, psill, range, nugget, pair_dist(xy, i, j))
            j += 1usize
        }
        g[i * m + n] = 1.0f64
        g[n * m + i] = 1.0f64
        let dx = xy[2usize * i] - px
        let dy = xy[2usize * i + 1usize] - py
        rhs[i] = vgm_gamma(model, psill, range, nugget, math.sqrt[f64](dx * dx + dy * dy))
        i += 1usize
    }
    g[n * m + n] = 0.0f64
    rhs[n] = 1.0f64
    if ols.inverse(a, g, m, gi) != ok { ret 0.0f64 / 0.0f64 }
    var pred = 0.0f64
    var variance = 0.0f64
    i = 0usize
    while i < m {
        var w = 0.0f64
        var j = 0usize
        while j < m {
            w += gi[i * m + j] * rhs[j]
            j += 1usize
        }
        if i < n { pred += w * z[i] }
        variance += w * rhs[i]
        i += 1usize
    }
    if part == 0usize { ret pred }
    ret variance
}
