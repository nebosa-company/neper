// e.algo.stat.signaldsp against signal. tests/oracle/signaldsp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R signaldsp`; the layout of each case is in scripts/r_oracle/groups/signaldsp.R.

use e.algo.stat.signaldsp as sd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "db") || str.eq(k, "da") {
        let n = usize(x[2usize])
        let nw = usize(x[5usize])
        var len = n + 1usize
        if nw == 2usize { len = 2usize * n + 1usize }
        let (b, e1) = mem.alloc[f64](a, len)
        if e1 != ok { os.exit(5) }
        let (aa, e2) = mem.alloc[f64](a, len)
        if e2 != ok { os.exit(6) }
        if sd.design(usize(x[0usize]), n, x[3usize], x[4usize], x[6usize..6usize + nw], usize(x[1usize]), true, b, aa) != ok { os.exit(7) }
        if str.eq(k, "db") { ret wsum(b) }
        ret wsum(aa)
    }
    os.exit(9)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/signaldsp.json")
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
