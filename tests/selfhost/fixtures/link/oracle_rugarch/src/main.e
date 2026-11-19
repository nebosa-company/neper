// e.algo.stat.vgampkg's sGARCH(1,1) fit against rugarch::ugarchfit. tests/oracle/rugarch.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rugarch`; the layout is at the top of scripts/r_oracle/groups/rugarch.R.

use e.algo.stat.rugarchpkg as rg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    if c.name.len == 4usize {
        var o7: [6]f64 = zero
        if !rg.garch11_t(a, z[1usize..1usize + n], n, o7[0usize..6usize]) { ret 0.0f64 / 0.0f64 }
        ret o7[usize(z[1usize + n])]
    }
    if c.name.len == 3usize {
        var o6: [6]f64 = zero
        if !rg.gjrgarch11(a, z[1usize..1usize + n], n, o6[0usize..6usize]) { ret 0.0f64 / 0.0f64 }
        ret o6[usize(z[1usize + n])]
    }
    var out: [5]f64 = zero
    if !rg.garch11(a, z[1usize..1usize + n], n, out[0usize..5usize]) { ret 0.0f64 / 0.0f64 }
    ret out[usize(z[1usize + n])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rugarch.json")
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
