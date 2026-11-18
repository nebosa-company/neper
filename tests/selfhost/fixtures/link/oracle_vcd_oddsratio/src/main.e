// e.algo.stat.vcdeffect's loddsratio against vcd::oddsratio (no reference categories). tests/oracle/vcd_oddsratio.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vcd_oddsratio`; the layout of every case is at the top of scripts/r_oracle/groups/vcd_oddsratio.R.

use e.algo.stat.vcdeffect as ve
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn pick(v: []const f64, j: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        if j == 0usize { s += v[i] }
        if j == 1usize { s += v[i] * f64(i + 1usize) }
        if j == 2usize { s += v[i] * v[i] }
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let r = usize(z[0usize])
    let cc = usize(z[1usize])
    let s = usize(z[2usize])
    let cells = z[3usize..3usize + r * cc * s]
    let which = usize(z[z.len - 1usize])
    let m = (r - 1usize) * (cc - 1usize) * s
    let (coef, e1) = mem.alloc[f64](a, m)
    let (vd, e2) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok { os.exit(10) }
    if ve.loddsratio(a, cells, r, cc, s, coef, vd) != ok { os.exit(11) }
    if which < 2usize { ret pick(coef[0usize..m], which) }
    ret pick(vd[0usize..m], which - 2usize)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vcd_oddsratio.json")
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
