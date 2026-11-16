// R imputeTS: na_ma (simple, linear and exponential weights), na_mean (mean, median, mode, geometric, harmonic), na_replace.
// A missing value is NaN. na_locf and the interpolations are in e.algo.stat.zoo.
//
// Not here: na_kalman, na_seadec, na_seasplit, na_random, statsNA, the maxgap option.

use e.math
use e.mem

fn is_nan(x: f64) -> bool { ret x != x }

// kind: 0 simple, 1 linear (1 / (1 + d)), 2 exponential (1 / 2^d); the window widens until it holds two values
fn na_ma(a: *mem.Arena, x: []const f64, k: usize, kind: usize) -> ([]f64, err) {
    let (o, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (o, e) }
    let n = x.len
    var i = 0usize
    while i < n {
        o[i] = x[i]
        if is_nan(x[i]) {
            var kk = k
            var done = false
            while !done && kk <= n {
                var s = 0.0f64
                var w = 0.0f64
                var cnt = 0usize
                var j = 0usize
                if i > kk { j = i - kk }
                var hi = i + kk
                if hi > n - 1usize { hi = n - 1usize }
                while j <= hi {
                    if j != i && !is_nan(x[j]) {
                        var d = f64(i) - f64(j)
                        if d < 0.0f64 { d = 0.0f64 - d }
                        var wt = 1.0f64
                        if kind == 1usize { wt = 1.0f64 / (1.0f64 + d) }
                        if kind == 2usize { wt = math.pow[f64](2.0f64, 0.0f64 - d) }
                        s += wt * x[j]
                        w += wt
                        cnt += 1usize
                    }
                    j += 1usize
                }
                if cnt >= 2usize {
                    o[i] = s / w
                    done = true
                }
                kk += 1usize
            }
        }
        i += 1usize
    }
    ret (o, ok)
}

fn sorted_copy(a: *mem.Arena, v: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < v.len {
        s[i] = v[i]
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

// the value na_mean fills with; option 0 mean, 1 median, 2 mode (first of the most frequent, in sorted order), 3 geometric, 4 harmonic
fn na_mean_value(a: *mem.Arena, x: []const f64, option: usize) -> f64 {
    let (v, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var m = 0usize
    var i = 0usize
    while i < x.len {
        if !is_nan(x[i]) {
            v[m] = x[i]
            m += 1usize
        }
        i += 1usize
    }
    let obs = v[0usize..m]
    let (s, e2) = sorted_copy(a, obs)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let nf = f64(m)
    var t = 0.0f64
    i = 0usize
    if option == 0usize {
        while i < m {
            t += obs[i]
            i += 1usize
        }
        ret t / nf
    }
    if option == 1usize {
        if m % 2usize == 1usize { ret s[m / 2usize] }
        ret (s[m / 2usize - 1usize] + s[m / 2usize]) / 2.0f64
    }
    if option == 2usize {
        var best = 0usize
        var bc = 0usize
        var c = 1usize
        i = 1usize
        while i <= m {
            if i < m && s[i] == s[i - 1usize] {
                c += 1usize
            } else {
                if c > bc {
                    bc = c
                    best = i - 1usize
                }
                c = 1usize
            }
            i += 1usize
        }
        ret s[best]
    }
    if option == 3usize {
        while i < m {
            t += math.log[f64](obs[i])
            i += 1usize
        }
        ret math.exp[f64](t / nf)
    }
    while i < m {
        t += 1.0f64 / obs[i]
        i += 1usize
    }
    ret 1.0f64 / (t / nf)
}
