// e.algo.stat.mediationpkg medsens against mediation::medsens under set.seed. tests/oracle/medsens.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R medsens`; the case layout, the data
// draws and the flattened output order are at the top of scripts/r_oracle/groups/medsens.R, which this fixture repeats.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.mediationpkg as md
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case, out: []f64) -> err {
    let z = c.args
    let kind = usize(z[0usize])
    let int = usize(z[1usize])
    let s1 = i64(z[2usize])
    let n = usize(z[3usize])
    let by = z[4usize]
    let conf = z[5usize]
    let sims = usize(z[6usize])
    let s2 = i64(z[7usize])
    var g: rng.Rng = zero
    rng.seed(&g, s1)
    let (x, e1) = mem.alloc[f64](a, n)
    let (tr, e2) = mem.alloc[f64](a, n)
    let (m, e3) = mem.alloc[f64](a, n)
    let (y, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        x[i] = rng.rnorm(&g, 0.0f64, 1.0f64)
        i += 1usize
    }
    i = 0usize
    while i < n {
        tr[i] = rd.rbinom(&g, 1.0f64, 0.5f64)
        i += 1usize
    }
    i = 0usize
    while i < n {
        var ind = 0.0f64
        if x[i] > 0.0f64 { ind = 1.0f64 }
        if kind == 2usize { m[i] = rd.rbinom(&g, 1.0f64, 0.25f64 + 0.3f64 * tr[i] + 0.15f64 * ind) }
        if kind != 2usize { m[i] = 0.5f64 * tr[i] + 0.3f64 * x[i] + rng.rnorm(&g, 0.0f64, 1.0f64) }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var ind = 0.0f64
        if x[i] > 0.0f64 { ind = 1.0f64 }
        var mi = 0.0f64
        if m[i] > 0.0f64 { mi = 1.0f64 }
        if kind != 1usize { y[i] = 0.4f64 * tr[i] + 0.6f64 * m[i] + 0.2f64 * x[i] + 0.3f64 * f64(int) * tr[i] * m[i] + rng.rnorm(&g, 0.0f64, 1.0f64) }
        if kind == 1usize { y[i] = rd.rbinom(&g, 1.0f64, 0.3f64 + 0.2f64 * tr[i] + 0.15f64 * mi + 0.1f64 * ind) }
        i += 1usize
    }
    let py = 4usize + int
    let (xm, e5) = mem.alloc[f64](a, n * 3usize)
    let (xy, e6) = mem.alloc[f64](a, n * py)
    if e5 != ok || e6 != ok { ret mem.Full }
    i = 0usize
    while i < n {
        xm[i * 3usize] = 1.0f64
        xm[i * 3usize + 1usize] = tr[i]
        xm[i * 3usize + 2usize] = x[i]
        xy[i * py] = 1.0f64
        xy[i * py + 1usize] = tr[i]
        xy[i * py + 2usize] = m[i]
        xy[i * py + 3usize] = x[i]
        if int == 1usize { xy[i * py + 4usize] = tr[i] * m[i] }
        i += 1usize
    }
    var tmy = py
    if int == 1usize { tmy = 4usize }
    let eps = math_sqrt_eps()
    if kind == 0usize { ret md.medsens_ct(a, xm, m, 3usize, xy, y, py, n, 1usize, 1usize, 2usize, tmy, by, conf, eps, out) }
    rng.seed(&g, s2)
    if kind == 2usize { ret md.medsens_bm(a, &g, xm, m, 3usize, xy, y, py, n, 1usize, 1usize, 2usize, tmy, by, conf, sims, eps, out) }
    ret md.medsens_bo(a, &g, xm, m, 3usize, xy, y, py, n, 1usize, 1usize, 2usize, by, conf, sims, out)
}

fn math_sqrt_eps() -> f64 { ret 1.4901161193847656e-8f64 }

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/medsens.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    var cache: [560]f64 = zero
    var key: [8]f64 = zero
    var have = false
    var bad = false
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        var same = have
        var k = 0usize
        while k < 8usize {
            if c.args[k] != key[k] { same = false }
            k += 1usize
        }
        if !same {
            bad = answer(a, c, cache[0usize..560usize]) != ok
            k = 0usize
            while k < 8usize {
                key[k] = c.args[k]
                k += 1usize
            }
            have = true
        }
        var got = 0.0f64 / 0.0f64
        if !bad { got = cache[usize(c.args[8usize])] }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
