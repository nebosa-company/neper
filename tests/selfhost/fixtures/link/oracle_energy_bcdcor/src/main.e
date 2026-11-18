// e.algo.stat.energy's bcdcor against energy::bcdcor. tests/oracle/energy_bcdcor.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R energy_bcdcor`; the layout of every case is at the top of scripts/r_oracle/groups/energy_bcdcor.R.

use e.algo.stat.energy as en
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let dx = usize(z[1usize])
    let dy = usize(z[2usize])
    let x = z[3usize..3usize + n * dx]
    let y = z[3usize + n * dx..3usize + n * dx + n * dy]
    let (v, e) = en.bcdcor(a, x, y, n, dx, dy)
    if e != ok { os.exit(10) }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/energy_bcdcor.json")
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
