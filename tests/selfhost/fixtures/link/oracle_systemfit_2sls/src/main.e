// e.algo.stat.systemfitpkg's twosls against systemfit method = "2SLS". tests/oracle/systemfit_2sls.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R systemfit_2sls`; the layout is at the top of scripts/r_oracle/groups/systemfit_2sls.R.

use e.algo.stat.systemfitpkg as sf
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let q = usize(z[2usize])
    let (cf, e0) = mem.alloc[f64](a, k)
    let (se, e1) = mem.alloc[f64](a, k)
    if e0 != ok || e1 != ok { ret nan }
    let (s2, e) = sf.twosls(a, z[3usize..3usize + n * k], z[3usize + n * k..3usize + n * k + n * q], z[3usize + n * k + n * q..3usize + n * k + n * q + n], n, k, q, cf, se)
    if e != ok { ret nan }
    let w = usize(z[3usize + n * k + n * q + n])
    if w < k { ret cf[w] }
    if w < 2usize * k { ret se[w - k] }
    ret s2
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/systemfit_2sls.json")
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
