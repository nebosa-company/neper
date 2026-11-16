// R bayestestR on a posterior sample: hdi (the shortest window of ceiling(ci n) sorted draws), eti (the equal-tailed type-7 quantiles), p_direction (the share of draws on the
// larger side of zero) and rope (the share of draws inside the range).
//
// Not here: the density-based point estimates and methods, bayes factors, the other indices and model objects.

use e.algo.stat.desctools as dt
use e.math
use e.mem

// the HDI limits: part 0 low, 1 high
fn hdi(a: *mem.Arena, x: []const f64, ci: f64, part: usize) -> f64 {
    let (s, e) = dt.sorted_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let n = s.len
    let w = usize(math.ceil[f64](ci * f64(n)))
    let nci = n - w
    var best = 1.0e300f64
    var first = 0usize
    var last = 0usize
    var cnt = 0usize
    var i = 0usize
    while i < nci {
        let width = s[i + w] - s[i]
        if width < best {
            best = width
            first = i
            last = i
            cnt = 1usize
        } else if width == best {
            last = i
            cnt += 1usize
        }
        i += 1usize
    }
    var pick = first
    if cnt > 1usize {
        if last - first + 1usize != cnt { pick = last } else { pick = (first + last) / 2usize }
    }
    if part == 0usize { ret s[pick] }
    ret s[pick + w]
}

// the equal-tailed interval limits
fn eti(a: *mem.Arena, x: []const f64, ci: f64, part: usize) -> f64 {
    let (s, e) = dt.sorted_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if part == 0usize { ret dt.quant7(s, (1.0f64 - ci) / 2.0f64) }
    ret dt.quant7(s, (1.0f64 + ci) / 2.0f64)
}

fn p_direction(x: []const f64) -> f64 {
    var pos = 0.0f64
    var neg = 0.0f64
    var i = 0usize
    while i < x.len {
        if x[i] > 0.0f64 { pos += 1.0f64 }
        if x[i] < 0.0f64 { neg += 1.0f64 }
        i += 1usize
    }
    var m = pos
    if neg > m { m = neg }
    ret m / f64(x.len)
}

fn rope_share(x: []const f64, lo: f64, hi: f64) -> f64 {
    var c = 0.0f64
    var i = 0usize
    while i < x.len {
        if x[i] >= lo && x[i] <= hi { c += 1.0f64 }
        i += 1usize
    }
    ret c / f64(x.len)
}
