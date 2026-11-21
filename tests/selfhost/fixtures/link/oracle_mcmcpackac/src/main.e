// e.algo.stat.mcmcpackac against MCMCoprobit (AC method) and the Cowles method under a user beta.start. tests/oracle/mcmcpackac.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mcmcpackac`; the argument layout is at the top of scripts/r_oracle/groups/mcmcpackac.R.

use e.algo.stat.mcmcpackac as ac
use e.algo.stat.mcmcpackord as mo
use e.algo.stat.mcmcpacksamp as ms
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(m: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < m.len {
        s += f64(i + 1usize) * m[i]
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    var g: ms.Sc = zero
    ms.sc_seed(&g, u64(z[0usize]))
    let n = usize(z[1usize])
    let k = usize(z[2usize])
    let ncat = usize(z[3usize])
    let burn = usize(z[4usize])
    let mc = usize(z[5usize])
    let thin = usize(z[6usize])
    let tune = z[7usize]
    let tdf = z[8usize]
    let m = ncat - 1usize
    var o = 9usize
    let y = z[o..o + n]
    o += n
    let x = z[o..o + n * k]
    o += n * k
    let b0 = z[o..o + k]
    o += k
    let bb = z[o..o + k * k]
    o += k * k
    let a0 = z[o..o + m]
    o += m
    let aprec = z[o..o + m * m]
    o += m * m
    let beta0 = z[o..o + k]
    o += k
    let gamma0 = z[o..o + ncat + 1usize]
    let (out, e1) = mem.alloc[f64](a, (mc / thin) * (k + ncat - 2usize))
    if e1 != ok { ret nan }
    var e = ok
    if str.eq(c.name, "ac") {
        e = ac.oprobit_ac(a, &g, y, x, n, k, ncat, tune, tdf, a0, aprec, gamma0, beta0, b0, bb, burn, mc, thin, out)
    } else {
        e = mo.oprobit_cowles(a, &g, y, x, n, k, ncat, tune, gamma0, beta0, b0, bb, burn, mc, thin, out)
    }
    if e == ac.NotConverged { ret -1.0f64 }
    if e == ms.NotPd { ret -2.0f64 }
    if e != ok { ret nan }
    ret wsum(out)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mcmcpackac.json")
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
