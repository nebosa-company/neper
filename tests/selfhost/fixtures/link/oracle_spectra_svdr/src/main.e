// e.algo.stat.spectrapkg's svdr against irlba::svdr. tests/oracle/spectra_svdr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R spectra_svdr`; the layout is at the top of scripts/r_oracle/groups/spectra_svdr.R.

use e.algo.rand.r as rr
use e.algo.stat.spectrapkg as sp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let m = usize(z[0usize])
    let n = usize(z[1usize])
    let k = usize(z[2usize])
    let ex = usize(z[3usize])
    let (d, e1) = mem.alloc[f64](a, k)
    if e1 != ok { os.exit(4) }
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[4usize]))
    let (iters, e) = sp.svdr(a, &g, z[6usize..6usize + m * n], m, n, k, ex, 1.0e-5f64, 100usize, d)
    let _ = iters
    if e != ok { os.exit(5) }
    ret d[usize(z[5usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/spectra_svdr.json")
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
