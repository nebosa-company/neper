// R Kendall::Kendall(x, y) and MannKendall(x): Kendall's score S, the denominator D = sqrt((n0 - Tx)(n0 - Ty)), tau = S / D,
// the tie-corrected variance of S (algorithm AS 71) and the two-sided normal p value with the continuity correction
// (|S| - 1) / sqrt(var). The package works in single precision, so its values carry about 7 digits.
//
// Not here: the exact small-sample distribution, SeasonalMannKendall.

use e.algo.sort
use e.math
use e.math.dist as dist
use e.mem

type Tau = struct { tau: f64, sl: f64, s: f64, d: f64, vars: f64 }

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

// sums over the tie groups of a sample: sum t(t-1)/2, sum t(t-1)(2t+5), sum t(t-1), sum t(t-1)(t-2)
fn ties(a: *mem.Arena, x: []const f64) -> (f64, f64, f64, f64) {
    let n = x.len
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret (0.0f64, 0.0f64, 0.0f64, 0.0f64) }
    var i = 0usize
    while i < n {
        s[i] = x[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    var t0 = 0.0f64
    var t1 = 0.0f64
    var t2 = 0.0f64
    var t3 = 0.0f64
    i = 0usize
    while i < n {
        var j = i
        while j + 1usize < n && s[j + 1usize] == s[i] { j += 1usize }
        let t = f64(j - i + 1usize)
        t0 += t * (t - 1.0f64) / 2.0f64
        t1 += t * (t - 1.0f64) * (2.0f64 * t + 5.0f64)
        t2 += t * (t - 1.0f64)
        t3 += t * (t - 1.0f64) * (t - 2.0f64)
        i = j + 1usize
    }
    ret (t0, t1, t2, t3)
}

fn kendall(a: *mem.Arena, x: []const f64, y: []const f64) -> Tau {
    var r: Tau = zero
    let n = x.len
    let nf = f64(n)
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            let dx = x[i] - x[j]
            let dy = y[i] - y[j]
            var sx = 0.0f64
            var sy = 0.0f64
            if dx > 0.0f64 { sx = 1.0f64 } else if dx < 0.0f64 { sx = 0.0f64 - 1.0f64 }
            if dy > 0.0f64 { sy = 1.0f64 } else if dy < 0.0f64 { sy = 0.0f64 - 1.0f64 }
            s += sx * sy
            j += 1usize
        }
        i += 1usize
    }
    let (tx0, tx1, tx2, tx3) = ties(a, x)
    let (ty0, ty1, ty2, ty3) = ties(a, y)
    let n0 = nf * (nf - 1.0f64) / 2.0f64
    r.s = s
    r.d = math.sqrt[f64]((n0 - tx0) * (n0 - ty0))
    r.tau = s / r.d
    let v0 = nf * (nf - 1.0f64) * (2.0f64 * nf + 5.0f64)
    r.vars = (v0 - tx1 - ty1) / 18.0f64 + tx2 * ty2 / (2.0f64 * nf * (nf - 1.0f64)) + tx3 * ty3 / (9.0f64 * nf * (nf - 1.0f64) * (nf - 2.0f64))
    var z = 0.0f64
    if math.abs[f64](s) > 1.0f64 { z = (math.abs[f64](s) - 1.0f64) / math.sqrt[f64](r.vars) }
    r.sl = 2.0f64 * (1.0f64 - dist.pnorm(z, 0.0f64, 1.0f64, true, false))
    ret r
}

// SeasonalMannKendall(x) for a series of `freq` seasons: the scores, denominators and variances of MannKendall on each season's
// subseries add up; tau = S / D and the p value uses S / sqrt(var) without a continuity correction
fn seasonal(a: *mem.Arena, x: []const f64, freq: usize) -> Tau {
    var r: Tau = zero
    let n = x.len
    var sc = 0.0f64
    var dn = 0.0f64
    var vr = 0.0f64
    var season = 0usize
    while season < freq {
        var m = 0usize
        var t = season
        while t < n {
            m += 1usize
            t += freq
        }
        let (sub, e1) = mem.alloc[f64](a, m)
        let (idx, e2) = mem.alloc[f64](a, m)
        if e1 != ok || e2 != ok { ret r }
        var k = 0usize
        t = season
        while t < n {
            sub[k] = x[t]
            idx[k] = f64(k + 1usize)
            k += 1usize
            t += freq
        }
        let q = kendall(a, idx, sub)
        sc += q.s
        dn += q.d
        vr += q.vars
        season += 1usize
    }
    r.s = sc
    r.d = dn
    r.vars = vr
    r.tau = sc / dn
    r.sl = 2.0f64 * (1.0f64 - dist.pnorm(math.abs[f64](sc / math.sqrt[f64](vr)), 0.0f64, 1.0f64, true, false))
    ret r
}
