// e.algo.stat.spectrapkg's prcomp_irlba against irlba. tests/oracle/spectra_prcomp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R spectra_prcomp`; the layout is at the top of scripts/r_oracle/groups/spectra_prcomp.R.

use e.algo.stat.spectrapkg as sp
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let m = usize(z[0usize])
    let n = usize(z[1usize])
    let k = usize(z[2usize])
    let kind = usize(z[4usize])
    let (sd, e1) = mem.alloc[f64](a, k)
    let (rot, e2) = mem.alloc[f64](a, n * k)
    if e1 != ok || e2 != ok { os.exit(4) }
    var tv = 0.0f64
    if sp.prcomp_irlba(a, z[5usize..5usize + m * n], m, n, k, true, usize(z[3usize]) == 1usize, sd, rot, &tv) != ok { os.exit(5) }
    var s = 0.0f64
    var i = 0usize
    if kind == 1usize { ret tv }
    if kind == 0usize {
        while i < k {
            s += sd[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    var jj = 0usize
    while jj < k {
        var ii = 0usize
        while ii < n {
            s += math.abs[f64](rot[ii * k + jj]) * f64(jj * n + ii + 1usize)
            ii += 1usize
        }
        jj += 1usize
    }
    ret s
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
