// e.algo.stat.tmpkg against tm weightings and removeSparseTerms and tidytext bind_tf_idf. tests/oracle/tm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tm`; the layout is at the top of scripts/r_oracle/groups/tm.R.

use e.algo.stat.tmpkg as tm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let nd = usize(z[0usize])
    let nt = usize(z[1usize])
    let m = z[5usize..5usize + nd * nt]
    let (out, e1) = mem.alloc[f64](a, nd * nd + nd * nt)
    if e1 != ok { ret nan }
    var r = ok
    if str.eq(c.name, "tfidf_norm") { r = tm.tfidf(a, m, nd, nt, true, out) }
    if str.eq(c.name, "tfidf_raw") { r = tm.tfidf(a, m, nd, nt, false, out) }
    if str.eq(c.name, "tidy") { r = tm.bind_tf_idf(a, m, nd, nt, out) }
    if str.eq(c.name, "smart") { r = tm.smart(a, m, nd, nt, usize(z[2usize]), usize(z[3usize]), usize(z[4usize]), out) }
    if str.eq(c.name, "cosine") { tm.cosine(m, nd, nt, out) }
    if r != ok { ret nan }
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "sparse") {
        let kept = tm.sparse_terms(a, m, nd, nt, z[2usize], out)
        while i < nt {
            s += out[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    var count = nd * nt
    if str.eq(c.name, "cosine") { count = nd * nd }
    while i < count {
        s += out[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tm.json")
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
