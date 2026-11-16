// R DescTools: Skew and Kurt (methods 1, 2 and 3, the moment, sample-adjusted and Minitab-style forms), Gini (unbiased or not), MeanAD about the mean, Gmean,
// Hmean, Entropy (Shannon, base 2, of the values as frequencies) and CoefVar.
//
// Not here: the rest of the package (Winsorize, Mode, the association measures, tests and confidence intervals).

use e.math
use e.mem

fn mean_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    ret s / f64(x.len)
}

fn moment(x: []const f64, k: f64) -> f64 {
    let m = mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += math.pow[f64](x[i] - m, k)
        i += 1usize
    }
    ret s / f64(x.len)
}

fn sd_of(x: []const f64) -> f64 {
    let m = mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret math.sqrt[f64](s / (f64(x.len) - 1.0f64))
}

// method 1 g1 = m3 / m2^1.5; 2 G1 = g1 sqrt(n (n - 1)) / (n - 2); 3 b1 = m3 / s^3 with the (n - 1) standard deviation
fn skew(x: []const f64, method: usize) -> f64 {
    let n = f64(x.len)
    let m2 = moment(x, 2.0f64)
    let m3 = moment(x, 3.0f64)
    let g1 = m3 / math.pow[f64](m2, 1.5f64)
    if method == 1usize { ret g1 }
    if method == 2usize { ret g1 * math.sqrt[f64](n * (n - 1.0f64)) / (n - 2.0f64) }
    ret m3 / math.pow[f64](sd_of(x), 3.0f64)
}

// method 1 g2 = m4 / m2^2 - 3; 2 G2 = (n - 1) / ((n - 2)(n - 3)) ((n + 1) g2 + 6); 3 b2 = m4 / s^4 - 3 with the (n - 1) standard deviation
fn kurt(x: []const f64, method: usize) -> f64 {
    let n = f64(x.len)
    let m2 = moment(x, 2.0f64)
    let m4 = moment(x, 4.0f64)
    let g2 = m4 / (m2 * m2) - 3.0f64
    if method == 1usize { ret g2 }
    if method == 2usize { ret (n - 1.0f64) / ((n - 2.0f64) * (n - 3.0f64)) * ((n + 1.0f64) * g2 + 6.0f64) }
    ret m4 / math.pow[f64](sd_of(x), 4.0f64) - 3.0f64
}

fn sorted_copy(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (s, e) }
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
    ret (s, ok)
}

// Gini(x, unbiased): 2 sum i x_(i) / (n sum x) - (n + 1) / n, times n / (n - 1) when unbiased
fn gini(a: *mem.Arena, x: []const f64, unbiased: bool) -> f64 {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let n = f64(x.len)
    var num = 0.0f64
    var tot = 0.0f64
    var i = 0usize
    while i < s.len {
        num += f64(i + 1usize) * s[i]
        tot += s[i]
        i += 1usize
    }
    let g = 2.0f64 * num / (n * tot) - (n + 1.0f64) / n
    if unbiased { ret g * n / (n - 1.0f64) }
    ret g
}

fn mean_ad(x: []const f64) -> f64 {
    let m = mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += math.abs[f64](x[i] - m)
        i += 1usize
    }
    ret s / f64(x.len)
}

fn gmean(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += math.log[f64](x[i])
        i += 1usize
    }
    ret math.exp[f64](s / f64(x.len))
}

fn hmean(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += 1.0f64 / x[i]
        i += 1usize
    }
    ret f64(x.len) / s
}

// Entropy(x): the Shannon entropy in bits of the values taken as frequencies
fn entropy(x: []const f64) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < x.len {
        t += x[i]
        i += 1usize
    }
    var h = 0.0f64
    i = 0usize
    while i < x.len {
        let p = x[i] / t
        if p > 0.0f64 { h -= p * math.log[f64](p) / math.log[f64](2.0f64) }
        i += 1usize
    }
    ret h
}

fn coef_var(x: []const f64) -> f64 { ret sd_of(x) / mean_of(x) }
