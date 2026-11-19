// R MASS histogram helpers and R's own nclass.* rules they call: nclass.freq (MASS), nclass.scott and nclass.FD (grDevices), the histogram counts
// of hist(x, nclass) (pretty breaks with min.n = 1, the fuzzed right-closed bins of hist.default), and frequency.polygon's midpoints.

use e.algo.stat.classint as ci
use e.algo.stat.masslqs as lq
use e.algo.stat.massmisc as mm
use e.math
use e.math.scale as scale
use e.mem

fn var_of(x: []const f64) -> f64 {
    let nf = f64(x.len)
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / nf
    var v = 0.0f64
    i = 0usize
    while i < x.len {
        v += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret v / (nf - 1.0f64)
}

fn range_of(x: []const f64) -> f64 {
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 0usize
    while i < x.len {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    ret hi - lo
}

// MASS::nclass.freq
fn nclass_freq(x: []const f64) -> f64 {
    let h = 2.15f64 * math.sqrt[f64](var_of(x)) * math.pow[f64](f64(x.len), 0.0f64 - 0.2f64)
    ret math.ceil[f64](range_of(x) / h)
}

// grDevices::nclass.scott
fn nclass_scott(x: []const f64) -> f64 {
    let h = 3.5f64 * math.sqrt[f64](var_of(x)) * math.pow[f64](f64(x.len), 0.0f64 - 1.0f64 / 3.0f64)
    if h > 0.0f64 {
        let k = math.ceil[f64](range_of(x) / h)
        if k < 1.0f64 { ret 1.0f64 }
        ret k
    }
    ret 1.0f64
}

// grDevices::nclass.FD
fn nclass_fd(a: *mem.Arena, x: []const f64) -> f64 {
    let n = x.len
    let (sg, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        sg[i] = mm.signif5(x[i])
        i += 1usize
    }
    lq.sortf(sg)
    var h = 2.0f64 * (ci.quantile_r(sg, 0.75f64, 7u8) - ci.quantile_r(sg, 0.25f64, 7u8))
    var al = 0.25f64
    while h == 0.0f64 && al / 2.0f64 >= 1.0f64 / 512.0f64 {
        al = al / 2.0f64
        h = (ci.quantile_r(sg, 1.0f64 - al, 7u8) - ci.quantile_r(sg, al, 7u8)) / (1.0f64 - 2.0f64 * al)
    }
    if h == 0.0f64 { h = 3.5f64 * math.sqrt[f64](var_of(x)) }
    if h > 0.0f64 { ret math.ceil[f64](range_of(x) / h * math.pow[f64](f64(n), 1.0f64 / 3.0f64)) }
    ret 1.0f64
}

// hist(x, nclass, plot = FALSE): the breaks (pretty(range(x), nclass, min.n = 1)) and the counts of the fuzzed right-closed bins, include.lowest
fn hist_counts(a: *mem.Arena, x: []const f64, nclass: f64) -> ([]f64, []f64, err) {
    let n = x.len
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 0usize
    while i < n {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    let (b, e1) = scale.pretty_min(a, lo, hi, i64(nclass), 1i64)
    let (none, e0) = mem.alloc[f64](a, 0usize)
    if e1 != ok || e0 != ok { ret (none, none, e1) }
    let nb = b.len
    let (hs, e2) = mem.alloc[f64](a, nb - 1usize)
    let (cnt, e3) = mem.alloc[f64](a, nb - 1usize)
    let (fb, e4) = mem.alloc[f64](a, nb)
    if e2 != ok || e3 != ok || e4 != ok { ret (none, none, mem.Full) }
    i = 0usize
    while i + 1usize < nb {
        hs[i] = b[i + 1usize] - b[i]
        cnt[i] = 0.0f64
        i += 1usize
    }
    var diddle = 0.0f64
    if nb > 5usize {
        let (sh, e5) = ci.sorted_copy(a, hs)
        if e5 != ok { ret (none, none, e5) }
        diddle = ci.quantile_r(sh, 0.5f64, 7u8)
    } else if nb <= 3usize {
        diddle = hi - lo
    } else {
        var mn = 0.0f64
        i = 0usize
        while i + 1usize < nb {
            if hs[i] > 0.0f64 && (mn == 0.0f64 || hs[i] < mn) { mn = hs[i] }
            i += 1usize
        }
        diddle = mn
    }
    diddle = diddle * 0.0000001f64
    i = 0usize
    while i < nb {
        fb[i] = b[i] + diddle
        if i == 0usize { fb[i] = b[i] - diddle }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var k = 0usize
        while k + 1usize < nb {
            let hit = (x[i] > fb[k] && x[i] <= fb[k + 1usize]) || (k == 0usize && x[i] == fb[0usize])
            if hit {
                cnt[k] += 1.0f64
                k = nb
            } else { k += 1usize }
        }
        i += 1usize
    }
    ret (b, cnt, ok)
}
