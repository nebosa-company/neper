// R QCA: the models of minimize(): every minimum-cardinality set of prime implicants that covers the outcome-1 configurations, with the unobserved configurations
// either excluded (the complex solution) or taken as don't cares (the parsimonious solution, include = "?"), on the prime implicants of e.algo.logic.
//
// Not here: the intermediate solution and directional expectations, inclusion and PRI cut-offs, necessity and sufficiency parameters of fit, superSubset and the case labels.

use e.algo.logic as lg
use e.mem

// the number of minimum-cardinality covers of the minterms by the primes (their size in `size`), by subset enumeration over at most 22 primes; the primes that cover no
// minterm are ignored, as QCA's prime implicant chart has only the ones that do
fn min_covers(a: *mem.Arena, minterms: []const u32, primes: []const lg.Implicant) -> (usize, usize, err) {
    var np = 0usize
    var i = 0usize
    let (keep, e1) = mem.alloc[usize](a, primes.len)
    if e1 != ok { ret (0usize, 0usize, e1) }
    while i < primes.len {
        var any = false
        var m = 0usize
        while m < minterms.len {
            if lg.covers(primes[i], minterms[m]) { any = true }
            m += 1usize
        }
        if any {
            keep[np] = i
            np += 1usize
        }
        i += 1usize
    }
    if np > 22usize { ret (0usize, 0usize, lg.TooSmall) }
    // the bit mask of the minterms each kept prime covers (at most 64 minterms)
    if minterms.len > 64usize { ret (0usize, 0usize, lg.TooSmall) }
    let (cov, e2) = mem.alloc[u64](a, np)
    if e2 != ok { ret (0usize, 0usize, e2) }
    i = 0usize
    while i < np {
        var bits = 0u64
        var m = 0usize
        while m < minterms.len {
            if lg.covers(primes[keep[i]], minterms[m]) { bits = bits | (1u64 << u64(m)) }
            m += 1usize
        }
        cov[i] = bits
        i += 1usize
    }
    var full = 0u64
    var m = 0usize
    while m < minterms.len {
        full = full | (1u64 << u64(m))
        m += 1usize
    }
    var best = np + 1usize
    var count = 0usize
    var mask = 1u64
    let total = 1u64 << u64(np)
    while mask < total {
        var got = 0u64
        var j = 0usize
        while j < np {
            if (mask >> u64(j)) & 1u64 == 1u64 { got = got | cov[j] }
            j += 1usize
        }
        if got == full {
            let s = lg.popcount(u32(mask))
            if s < best {
                best = s
                count = 1usize
            } else if s == best {
                count += 1usize
            }
        }
        mask += 1u64
    }
    ret (best, count, ok)
}

// the fuzzy membership of row r in a sum of products: `terms` is nterms, then for each term its literal count and, per literal, the column and 1 for a negation;
// the product of literals is the minimum, the sum of terms the maximum
fn expr_member(d: []const f64, nv: usize, r: usize, spec: []const f64) -> f64 {
    let nterms = usize(spec[0usize])
    var at = 1usize
    var best = 0.0f64
    var t = 0usize
    while t < nterms {
        let nl = usize(spec[at])
        at += 1usize
        var m = 1.0f64
        var l = 0usize
        while l < nl {
            var v = d[r * nv + usize(spec[at])]
            if spec[at + 1usize] == 1.0f64 { v = 1.0f64 - v }
            if v < m { m = v }
            at += 2usize
            l += 1usize
        }
        if m > best { best = m }
        t += 1usize
    }
    ret best
}

// pof() of the expression against the outcome column y: relation 0 sufficiency (which 0 inclS, 1 PRI, 2 covS), 1 necessity (0 inclN, 1 RoN, 2 covN)
fn pof(d: []const f64, y: []const f64, n: usize, nv: usize, spec: []const f64, relation: usize, which: usize) -> f64 {
    var sx = 0.0f64
    var sy = 0.0f64
    var smin = 0.0f64
    var sminn = 0.0f64
    var s1x = 0.0f64
    var s1m = 0.0f64
    var r = 0usize
    while r < n {
        let x = expr_member(d, nv, r, spec)
        let yy = y[r]
        var mn = x
        if yy < mn { mn = yy }
        var mm = mn
        if 1.0f64 - yy < mm { mm = 1.0f64 - yy }
        sx += x
        sy += yy
        smin += mn
        sminn += mm
        s1x += 1.0f64 - x
        s1m += 1.0f64 - mn
        r += 1usize
    }
    if relation == 0usize {
        if which == 0usize { ret smin / sx }
        if which == 1usize { ret (smin - sminn) / (sx - sminn) }
        ret smin / sy
    }
    if which == 0usize { ret smin / sy }
    if which == 1usize { ret s1x / s1m }
    ret smin / sx
}

// truthTable(): for each of the 2^k configurations of the k condition columns of d (n rows by nv columns, the conditions in columns 0 .. k - 1; the first condition is the most
// significant bit of the row number, row 0 = all conditions absent) the number of cases with membership above 0.5, the sufficiency inclusion and PRI of the configuration's membership
// (the minimum of its literals) against y, and the output: 1 when n >= n_cut, incl >= incl_cut and PRI >= pri_cut, 0 when it has enough cases but fails, -1 (the "?" row) when it has fewer than n_cut cases.
// out receives 4 values per configuration: n, incl, PRI, OUT (incl and PRI are NaN for an empty configuration).
fn truth_table(d: []const f64, y: []const f64, n: usize, nv: usize, k: usize, incl_cut: f64, n_cut: f64, pri_cut: f64, out: []f64) {
    let nan = 0.0f64 / 0.0f64
    let rows = usize(1u64 << u64(k))
    var c = 0usize
    while c < rows {
        var sx = 0.0f64
        var smin = 0.0f64
        var sminn = 0.0f64
        var cnt = 0.0f64
        var r = 0usize
        while r < n {
            var x = 1.0f64
            var j = 0usize
            while j < k {
                var v = d[r * nv + j]
                let bit = (c >> (k - 1usize - j)) & 1usize
                if bit == 0usize { v = 1.0f64 - v }
                if v < x { x = v }
                j += 1usize
            }
            if x > 0.5f64 { cnt += 1.0f64 }
            let yy = y[r]
            var mn = x
            if yy < mn { mn = yy }
            var mm = mn
            if 1.0f64 - yy < mm { mm = 1.0f64 - yy }
            sx += x
            smin += mn
            sminn += mm
            r += 1usize
        }
        out[c * 4usize] = cnt
        if cnt == 0.0f64 {
            out[c * 4usize + 1usize] = nan
            out[c * 4usize + 2usize] = nan
            out[c * 4usize + 3usize] = -1.0f64
        } else {
            let incl = smin / sx
            let pri = (smin - sminn) / (sx - sminn)
            out[c * 4usize + 1usize] = incl
            out[c * 4usize + 2usize] = pri
            var o = 0.0f64
            if cnt < n_cut { o = -1.0f64 }
            if cnt >= n_cut && incl >= incl_cut && pri >= pri_cut { o = 1.0f64 }
            out[c * 4usize + 3usize] = o
        }
        c += 1usize
    }
}
