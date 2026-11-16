// e.algo.stat.miwa.pmvnorm_miwa against mvtnorm's Miwa algorithm. tests/oracle/miwa.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R miwa`; the layout is at the top of scripts/r_oracle/groups/miwa.R.

use e.algo.stat.miwa as miwa
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let (v, e) = miwa.pmvnorm_miwa(a, n, z[2usize..2usize + n], z[2usize + n..2usize + 2usize * n], z[2usize + 2usize * n..2usize + 2usize * n + n * n], usize(z[1usize]))
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/miwa.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let start = mem.mark(a)
        let got = answer(a, c)
        mem.reset(a, start)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    // checkCorr: a singular correlation matrix is refused, as R's solve refuses it
    var sing: [4]f64 = zero
    sing[0usize] = 1.0f64
    sing[1usize] = 1.0f64
    sing[2usize] = 1.0f64
    sing[3usize] = 1.0f64
    let (_v, se) = miwa.pmvnorm_miwa(a, 2usize, sing[0usize..2usize], sing[0usize..2usize], sing[0usize..4usize], 128usize)
    if se == ok { os.exit(4) }
    if failures > 0usize { os.exit(1) }
    ret ok
}
