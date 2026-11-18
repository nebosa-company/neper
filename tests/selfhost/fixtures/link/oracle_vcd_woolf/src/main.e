// e.algo.stat.vcdeffect's woolf against vcd::woolf_test. tests/oracle/vcd_woolf.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vcd_woolf`; the layout of every case is at the top of scripts/r_oracle/groups/vcd_woolf.R.

use e.algo.stat.vcdeffect as ve
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let k = usize(z[0usize])
    let cells = z[1usize..1usize + 4usize * k]
    let which = usize(z[z.len - 1usize])
    let (stat, p, e) = ve.woolf(a, cells, k)
    if e != ok { os.exit(10) }
    if which == 0usize { ret stat }
    ret p
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vcd_woolf.json")
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
