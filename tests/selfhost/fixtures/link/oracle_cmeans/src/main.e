// e.algo.stat.e1071 rwiener and cmeans against e1071 under set.seed. tests/oracle/cmeans.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R cmeans`; the layout is at the top of
// scripts/r_oracle/groups/cmeans.R.

use e.algo.rand.r as rr
use e.algo.stat.e1071 as ev
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[0usize]))
    if str.eq(c.name, "w") {
        let n = usize(z[1usize])
        let (out, e) = mem.alloc[f64](a, n)
        if e != ok { ret nan }
        ev.rwiener(&g, n, z[2usize], out)
        ret out[usize(z[3usize])]
    }
    let n = usize(z[1usize])
    let nc = usize(z[2usize])
    let k = usize(z[3usize])
    let m = z[4usize]
    let w = z[5usize..5usize + n]
    let x = z[5usize + n..5usize + n + n * nc]
    let cen0 = z[5usize + n + n * nc..5usize + n + n * nc + k * nc]
    let q = usize(z[5usize + n + n * nc + k * nc])
    let (cen, e1) = mem.alloc[f64](a, k * nc)
    let (u, e2) = mem.alloc[f64](a, n * k)
    if e1 != ok || e2 != ok { ret nan }
    var i = 0usize
    while i < k * nc {
        cen[i] = cen0[i]
        i += 1usize
    }
    let (iter, werr, e) = ev.cmeans(a, &g, x, n, nc, cen, k, w, m, 100usize, 1.4901161193847656e-8f64, u)
    if e != ok { ret nan }
    if q < k * nc { ret cen[q] }
    if q == k * nc { ret werr }
    if q == k * nc + 1usize { ret f64(iter) }
    ret u[q - k * nc - 2usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/cmeans.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
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
