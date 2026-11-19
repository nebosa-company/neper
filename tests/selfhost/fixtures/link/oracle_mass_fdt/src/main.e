// e.algo.stat.fitdist's fitdistr_t against MASS fitdistr(x, "t"). tests/oracle/mass_fdt.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_fdt`; the layout is at the top of scripts/r_oracle/groups/mass_fdt.R.

use e.algo.stat.fitdist as fdi
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let n = usize(c.args[0usize])
    let (fo, fe) = mem.alloc[f64](a, 7usize)
    if fe != ok { ret nan }
    if fdi.fitdistr_t(a, c.args[2usize..2usize + n], fo) != ok { ret nan }
    ret fo[usize(c.args[1usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_fdt.json")
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
