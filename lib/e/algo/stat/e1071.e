// R's e1071 helpers that are plain arithmetic: `skewness` and `kurtosis` (types 1 to 3, as moments.type
// of the package defines them) and `countpattern` (the counts of the 2^nvar 0/1 patterns of the columns).
//
// Not here: cmeans and cshell (random starts), rwiener, bclust and matchClasses.

use e.math
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn centred_sums(x: []const f64) -> (f64, f64, f64, f64) {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    let m = s / f64(x.len)
    var m2 = 0.0f64
    var m3 = 0.0f64
    var m4 = 0.0f64
    i = 0usize
    while i < x.len {
        let d = x[i] - m
        m2 += d * d
        m3 += d * d * d
        m4 += d * d * d * d
        i += 1usize
    }
    ret (m, m2, m3, m4)
}

// skewness type 1, 2 or 3; NaN where R stops (type 2 below three observations)
fn skewness(x: []const f64, qtype: u8) -> f64 {
    let n = f64(x.len)
    let (m, m2, m3, m4) = centred_sums(x)
    var y = math.sqrt[f64](n) * m3 / math.pow[f64](m2, 1.5f64)
    if qtype == 2u8 {
        if x.len < 3usize { ret nan() }
        y = y * math.sqrt[f64](n * (n - 1.0f64)) / (n - 2.0f64)
    } else if qtype == 3u8 {
        y = y * math.pow[f64](1.0f64 - 1.0f64 / n, 1.5f64)
    }
    ret y
}

fn kurtosis(x: []const f64, qtype: u8) -> f64 {
    let n = f64(x.len)
    let (m, m2, m3, m4) = centred_sums(x)
    let r = n * m4 / (m2 * m2)
    if qtype == 1u8 { ret r - 3.0f64 }
    if qtype == 2u8 {
        if x.len < 4usize { ret nan() }
        ret ((n + 1.0f64) * (r - 3.0f64) + 6.0f64) * (n - 1.0f64) / ((n - 2.0f64) * (n - 3.0f64))
    }
    let f = 1.0f64 - 1.0f64 / n
    ret r * f * f - 3.0f64
}

// countpattern for a 0/1 matrix given row-wise: counts[k] is the number of rows whose bits, first
// column most significant, read k.
fn count_pattern(a: *mem.Arena, rows: []const f64, nrow: usize, nvar: usize) -> ([]f64, err) {
    var size = 1usize
    var v = 0usize
    while v < nvar {
        size *= 2usize
        v += 1usize
    }
    let (out, e) = mem.alloc[f64](a, size)
    if e != ok { ret (out, e) }
    var k = 0usize
    while k < size {
        out[k] = 0.0f64
        k += 1usize
    }
    var r = 0usize
    while r < nrow {
        var code = 0usize
        var c = 0usize
        while c < nvar {
            code = code * 2usize
            if rows[r * nvar + c] != 0.0f64 { code += 1usize }
            c += 1usize
        }
        out[code] += 1.0f64
        r += 1usize
    }
    ret (out, ok)
}
