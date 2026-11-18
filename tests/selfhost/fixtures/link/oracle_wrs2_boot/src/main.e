// e.algo.stat.wrs2 yuenbt and pb2gen against WRS2 under set.seed. tests/oracle/wrs2_boot.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R wrs2_boot`; the layout is at the top of scripts/r_oracle/groups/wrs2_boot.R.

use e.algo.rand.r as rr
use e.algo.stat.wrs2 as w
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let kind = usize(z[0usize])
    let nx = usize(z[2usize])
    let ny = usize(z[3usize])
    let nboot = usize(z[5usize])
    let which = usize(z[6usize])
    let x = z[7usize..7usize + nx]
    let y = z[7usize + nx..7usize + nx + ny]
    var rng: rr.Rng = zero
    rr.seed(&rng, i64(z[1usize]))
    var r: w.Boot = zero
    var e = ok
    if kind == 2usize {
        let (b, eb) = w.pb2gen(a, &rng, x, y, usize(z[4usize]), nboot)
        r = b
        e = eb
    } else {
        let (b, eb) = w.yuenbt(a, &rng, x, y, z[4usize], nboot, kind == 0usize)
        r = b
        e = eb
    }
    if e != ok { os.exit(5) }
    if which == 0usize { ret r.test }
    if which == 1usize { ret r.lo }
    if which == 2usize { ret r.hi }
    if which == 3usize { ret r.p }
    ret r.diff
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/wrs2_boot.json")
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
