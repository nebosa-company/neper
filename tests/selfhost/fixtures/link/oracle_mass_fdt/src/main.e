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
    let w = usize(c.args[1usize])
    let x = c.args[5usize..5usize + n]
    if w >= 10usize {
        if fdi.fitdistr_t_at(a, x, c.args[2usize], c.args[3usize], c.args[4usize], fo) != ok { ret nan }
        ret fo[w - 10usize]
    }
    if fdi.fitdistr_t(a, x, fo) != ok { ret nan }
    ret fo[w]
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
