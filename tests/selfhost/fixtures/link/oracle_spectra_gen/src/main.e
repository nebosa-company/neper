// e.algo.stat.spectrapkg's eigs_general against RSpectra::eigs on general real matrices. tests/oracle/spectra_gen.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R spectra_gen`; the layout is at the top of scripts/r_oracle/groups/spectra_gen.R.

use e.algo.stat.spectrapkg as sp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let wh = usize(z[2usize])
    let kind = usize(z[3usize])
    let (re, e1) = mem.alloc[f64](a, k)
    let (im, e2) = mem.alloc[f64](a, k)
    let (vm, e3) = mem.alloc[f64](a, n * k)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(4) }
    if sp.eigs_general(a, z[4usize..4usize + n * n], n, k, wh, re, im, vm) != ok { os.exit(5) }
    var s = 0.0f64
    if kind == 2usize {
        var cc = 0usize
        while cc < k {
            var rr2 = 0usize
            while rr2 < n {
                s += vm[rr2 * k + cc] * f64(cc * n + rr2 + 1usize)
                rr2 += 1usize
            }
            cc += 1usize
        }
        ret s
    }
    var i = 0usize
    while i < k {
        if kind == 0usize { s += re[i] * f64(i + 1usize) } else { s += im[i] * f64(i + 1usize) }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/spectra_gen.json")
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
