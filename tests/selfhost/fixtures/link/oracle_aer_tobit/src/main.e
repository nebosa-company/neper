// e.algo.stat.aerpkg tobit against AER::tobit. tests/oracle/aer_tobit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R aer_tobit`; the argument layout is at the top of scripts/r_oracle/groups/aer_tobit.R.

use e.algo.stat.aerpkg as aer
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn wsum(v: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let which = usize(z[4usize])
    let m = p + 1usize
    let (out, e1) = mem.alloc[f64](a, m + 1usize + m * m)
    if e1 != ok { ret nan }
    if aer.tobit(a, z[5usize + n..5usize + n + n * p], z[5usize..5usize + n], n, p, z[2usize], z[3usize], out) != ok { ret nan }
    if which == 0usize { ret wsum(out, p) }
    if which == 1usize { ret math.exp[f64](out[p]) }
    if which == 2usize { ret out[m] }
    if which == 3usize {
        var s = 0.0f64
        var i = 0usize
        while i < m {
            s += math.sqrt[f64](out[m + 1usize + i * m + i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    ret out[p]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/aer_tobit.json")
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
