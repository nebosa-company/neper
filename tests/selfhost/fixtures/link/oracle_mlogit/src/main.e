// e.algo.stat.mlogitpkg against mlogit conditional logit. tests/oracle/mlogit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mlogit`; the layout is at the top of scripts/r_oracle/groups/mlogit.R.

use e.algo.stat.mlogitpkg as ml
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let j = usize(z[1usize])
    let k = usize(z[2usize])
    let asc = z[3usize] > 0.5f64
    var q = k
    if asc { q = j - 1usize + k }
    let (out, e1) = mem.alloc[f64](a, 2usize * q + 1usize)
    if e1 != ok { ret nan }
    if ml.clogit(a, z[4usize + n..4usize + n + n * j * k], z[4usize..4usize + n], n, j, k, asc, out) != ok { ret nan }
    if str.eq(c.name, "ll") { ret out[2usize * q] }
    var lo = 0usize
    if str.eq(c.name, "se") { lo = q }
    var s = 0.0f64
    var i = 0usize
    while i < q {
        s += out[lo + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mlogit.json")
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
