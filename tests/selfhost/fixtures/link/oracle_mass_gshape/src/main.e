// e.algo.stat.mass's gamma_shape against MASS gamma.shape. tests/oracle/mass_gshape.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_gshape`; the layout is at the top of scripts/r_oracle/groups/mass_gshape.R.

use e.algo.stat.mass as ms
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    var out: [2]f64 = zero
    ms.gamma_shape(z[3usize..3usize + n], z[3usize + n..3usize + 2usize * n], z[3usize + 2usize * n..3usize + 3usize * n], z[1usize], z[2usize], 10usize, out[0usize..2usize])
    ret out[usize(z[3usize + 3usize * n])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_gshape.json")
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
