// e.algo.stat.boot.tsboot against boot::tsboot (fixed and geometric blocks). tests/oracle/tsboot.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tsboot`; the layout is at the top of scripts/r_oracle/groups/tsboot.R.

use e.algo.rand.r as rng
use e.algo.stat.boot as bt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let seed = i64(z[0usize])
    let sim = u8(z[1usize])
    let ec = z[2usize] == 1.0f64
    let st = u8(z[3usize])
    let r = usize(z[4usize])
    let l = usize(z[5usize])
    let n = usize(z[6usize])
    let x = z[7usize..7usize + n]
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    let (b, e) = bt.tsboot(a, &g, x, st, r, l, sim, ec)
    if e != ok { ret nan }
    if str.eq(c.name, "t0") { ret b.t0 }
    if str.eq(c.name, "t") { ret b.t[usize(z[7usize + n])] }
    var s = 0.0f64
    var i = 0usize
    while i < r {
        s += b.t[i]
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tsboot.json")
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
