// e.algo.stat.ipredpkg against ipred. tests/oracle/ipred.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ipred`; the layout is at the top of scripts/r_oracle/groups/ipred.R.

use e.algo.stat.ipredpkg as ip
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "sb") {
        let n = usize(z[0usize])
        ret ip.sbrier_one(a, z[2usize..2usize + n], z[2usize + n..2usize + 2usize * n], z[2usize + 2usize * n..2usize + 3usize * n], z[1usize])
    }
    if str.eq(c.name, "kf") {
        let k = usize(z[0usize])
        let (o, e) = mem.alloc[usize](a, k)
        if e != ok { ret nan }
        ip.kfoldcv(k, usize(z[1usize]), o)
        ret f64(o[usize(z[2usize])])
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ipred.json")
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
