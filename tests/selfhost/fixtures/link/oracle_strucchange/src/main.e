// e.algo.stat.strucpkg against strucchange Fstats and breakpoints. tests/oracle/strucchange.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R strucchange`; the layout is at the top of scripts/r_oracle/groups/strucchange.R.

use e.algo.stat.strucpkg as sc
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let m = usize(z[2usize])
    let y = z[3usize..3usize + n]
    let x = z[3usize + n..3usize + n + n * p]
    let from = usize(math.floor[f64](0.15f64 * f64(n)))
    let to = n - from
    if str.eq(c.name, "fsum") || str.eq(c.name, "supf") {
        let (f, e1) = mem.alloc[f64](a, to - from + 1usize)
        if e1 != ok { ret nan }
        sc.fstats(a, y, x, n, p, from, to, f)
        var s = 0.0f64
        var mx = f[0usize]
        var i = 0usize
        while i < f.len {
            s += f[i] * f64(i + 1usize)
            if f[i] > mx { mx = f[i] }
            i += 1usize
        }
        if str.eq(c.name, "supf") { ret mx }
        ret s
    }
    let (bp, e2) = mem.alloc[f64](a, m)
    if e2 != ok { ret nan }
    let rss = sc.breakpoints(a, y, x, n, p, from, m, bp)
    if str.eq(c.name, "rss") { ret rss }
    var s = 0.0f64
    var i = 0usize
    while i < m {
        s += bp[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/strucchange.json")
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
