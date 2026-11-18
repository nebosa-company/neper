// e.algo.stat.desctools's ccc and cronbach_alpha against DescTools. tests/oracle/desctools_agree.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R desctools_agree`; the layout is at the top of scripts/r_oracle/groups/desctools_agree.R.

use e.algo.stat.desctools as dt
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let (o, e) = mem.alloc[f64](a, 6usize)
    if e != ok { os.exit(4) }
    if z[0usize] == 0.0f64 {
        let n = usize(z[3usize])
        dt.ccc(z[4usize..4usize + n], z[4usize + n..4usize + 2usize * n], z[2usize], usize(z[1usize]), o)
        ret o[usize(z[4usize + 2usize * n])]
    }
    let n = usize(z[1usize])
    let nc = usize(z[2usize])
    let ce = dt.cronbach_alpha(a, z[4usize..4usize + n * nc], n, nc, z[3usize], o)
    if ce != ok { os.exit(5) }
    ret o[usize(z[4usize + n * nc])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/desctools_agree.json")
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
