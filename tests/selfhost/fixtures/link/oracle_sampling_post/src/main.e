// e.algo.stat.sampling's postest against sampling. tests/oracle/sampling_post.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sampling_post`; the layout is at the top of scripts/r_oracle/groups/sampling_post.R.

use e.algo.stat.sampling as sp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let k = usize(x[1usize])
    if str.eq(c.name, "pw") {
        let h = usize(x[2usize])
        ret sp.post_estimator2(x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], x[3usize + 3usize * n..3usize + 4usize * n], x[3usize + 2usize * n..3usize + 3usize * n], x[3usize + 4usize * n..3usize + 4usize * n + h * k], h, k)
    }
    ret sp.post_estimator(x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], x[2usize + 2usize * n..2usize + 3usize * n], x[2usize + 3usize * n..2usize + 3usize * n + k])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sampling_post.json")
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
