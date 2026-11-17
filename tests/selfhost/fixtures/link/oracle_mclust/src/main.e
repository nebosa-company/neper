// e.algo.stat.mclustpkg against mclust. tests/oracle/mclust.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust`; the layout is at the top of scripts/r_oracle/groups/mclust.R.

use e.algo.stat.mclustpkg as mc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "npar") { ret mc.n_mclust_params(mc.model_name(usize(z[0usize])), z[1usize], z[2usize], z[3usize] != 0.0f64, z[4usize] != 0.0f64) }
    if str.eq(c.name, "bic") { ret mc.bic(mc.model_name(usize(z[0usize])), z[1usize], z[2usize], z[3usize], z[4usize], z[5usize] != 0.0f64, z[6usize] != 0.0f64) }
    if str.eq(c.name, "ari") {
        let n = usize(z[0usize])
        let (x, e1) = mem.alloc[usize](a, n)
        let (y, e2) = mem.alloc[usize](a, n)
        if e1 != ok || e2 != ok { ret nan }
        var i = 0usize
        while i < n {
            x[i] = usize(z[1usize + i])
            y[i] = usize(z[1usize + n + i])
            i += 1usize
        }
        ret mc.adjusted_rand_index(a, x, y)
    }
    if str.eq(c.name, "map") {
        let n = usize(z[0usize])
        let k = usize(z[1usize])
        let (o, e) = mem.alloc[usize](a, n)
        if e != ok { ret nan }
        mc.map(z[2usize..2usize + n * k], n, k, o)
        ret f64(o[usize(z[2usize + n * k])])
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust.json")
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
