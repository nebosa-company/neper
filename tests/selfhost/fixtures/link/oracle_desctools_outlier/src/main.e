// e.algo.stat.desctools's Mode and Outlier against DescTools. tests/oracle/desctools_outlier.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R desctools_outlier`; the layout of every case is at the top of scripts/r_oracle/groups/desctools_outlier.R.

use e.algo.stat.desctools as dt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let kind = usize(z[0usize])
    let n = usize(z[1usize])
    let x = z[2usize..2usize + n]
    let j = usize(z[z.len - 1usize])
    if kind == 0usize {
        let (buf, e) = mem.alloc[f64](a, n + 1usize)
        if e != ok { os.exit(10) }
        let (k, freq, me) = dt.mode_of(a, x, buf)
        if me != ok { os.exit(11) }
        if j == 0usize { ret f64(k) }
        if j == 2usize { ret freq }
        var s = 0.0f64
        var i = 0usize
        while i < k {
            s += buf[i]
            i += 1usize
        }
        ret s
    }
    var cnt = 0usize
    var sum = 0.0f64
    var oe = ok
    if kind == 1usize {
        let (c1, s1, e1) = dt.outlier_box(a, x)
        cnt = c1
        sum = s1
        oe = e1
    } else {
        let (c2, s2, e2) = dt.outlier_hampel(a, x)
        cnt = c2
        sum = s2
        oe = e2
    }
    if oe != ok { os.exit(12) }
    if j == 0usize { ret f64(cnt) }
    ret sum
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/desctools_outlier.json")
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
