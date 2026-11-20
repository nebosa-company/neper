// e.algo.stat.irlba_extra's prcomp_irlba against irlba. tests/oracle/spectra_prcomp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R spectra_prcomp`; the layout is at the top of scripts/r_oracle/groups/spectra_prcomp.R.

use e.algo.rand.r as rr
use e.algo.stat.irlba as il
use e.algo.stat.irlba_extra as ex
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn wsum(v: []f64, cnt: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let m = usize(z[0usize])
    let n = usize(z[1usize])
    let k = usize(z[2usize])
    let kind = usize(z[5usize])
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[4usize]))
    var out: ex.Prcomp = zero
    if ex.prcomp_irlba(a, &g, z[6usize..6usize + m * n], m, n, k, true, usize(z[3usize]) == 1usize, il.default_opts(k), &out) != ok { os.exit(5) }
    if kind == 0usize { ret wsum(out.sdev, k) }
    if kind == 1usize { ret out.totalvar }
    ret wsum(out.rot, n * k)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/spectra_prcomp.json")
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
