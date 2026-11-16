// e.algo.stat.mvt against mvtnorm's pmvnorm and pmvt (Genz-Bretz). tests/oracle/mvt.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mvt`; the layout is at the top of scripts/r_oracle/groups/mvt.R.

use e.algo.rand.r as rng
use e.algo.stat.mvt as mvt
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, lat: *const mvt.Lat, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let seed = i64(z[0usize])
    let n = usize(z[1usize])
    let df = i64(z[2usize])
    let maxpts = i64(z[3usize])
    let abseps = z[4usize]
    let releps = z[5usize]
    let q = usize(z[6usize + 3usize * n + n * n])
    let (lo, e1) = mem.alloc[f64](a, n)
    let (up, e2) = mem.alloc[f64](a, n)
    let (infin, e3) = mem.alloc[i64](a, n)
    let (cor, e4) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var i = 0usize
    while i < n {
        let l = z[6usize + i]
        let u = z[6usize + n + i]
        var lf = l <= 0.0f64 - 1.0e300f64
        var uf = u >= 1.0e300f64
        infin[i] = 2i64
        if uf { infin[i] = 1i64 }
        if lf { infin[i] = 0i64 }
        if lf && uf { infin[i] = 0i64 - 1i64 }
        lo[i] = l
        up[i] = u
        if lf { lo[i] = 0.0f64 }
        if uf { up[i] = 0.0f64 }
        i += 1usize
    }
    var k = 0usize
    i = 1usize
    while i < n {
        var j = 0usize
        while j < i {
            cor[k] = z[6usize + 3usize * n + j * n + i]
            k += 1usize
            j += 1usize
        }
        i += 1usize
    }
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    let (res, re) = mvt.mvtdst(a, &g, lat, n, df, lo, up, infin, cor[0usize..n * (n - 1usize) / 2usize], z[6usize + 2usize * n..6usize + 3usize * n], maxpts, abseps, releps)
    if re != ok { ret nan }
    if q == 0usize { ret res.value }
    if q == 1usize { ret res.abserr }
    ret f64(res.inform)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mvt.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var lat: mvt.Lat = zero
    mvt.load_lattice(&lat)
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, &lat, c)
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
