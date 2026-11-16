// e.gfx.palettes against ggsci and ggthemes: every discrete palette, with alpha. tests/oracle/palettes.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R palettes`; the layout is at the top
// of scripts/r_oracle/groups/palettes.R.

use e.gfx.palettes as pal
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "size") { ret f64(pal.size(usize(x[0usize]))) }
    ret f64(pal.colour(usize(x[0usize]), usize(x[1usize]), x[2usize]))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/palettes.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(c)
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
