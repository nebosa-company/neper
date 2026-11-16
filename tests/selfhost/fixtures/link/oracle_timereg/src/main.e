// e.algo.stat.timeregpkg against timereg aalen. tests/oracle/timereg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R timereg`; the layout is at the top of scripts/r_oracle/groups/timereg.R.

use e.algo.stat.timeregpkg as tr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let q = p + 1usize
    let (cum, e1) = mem.alloc[f64](a, n * q)
    let (times, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret nan }
    let rows = tr.aalen(a, z[2usize..2usize + n], z[2usize + n..2usize + 2usize * n], z[2usize + 2usize * n..2usize + 2usize * n + n * p], n, p, cum, times)
    if str.eq(c.name, "rows") { ret f64(rows) }
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "last") {
        while i < q {
            s += cum[(rows - 1usize) * q + i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    while i < rows * q {
        s += cum[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/timereg.json")
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
