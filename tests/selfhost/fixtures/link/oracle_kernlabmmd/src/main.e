// e.algo.stat.kernlabmmd against kernlab kmmd. tests/oracle/kernlabmmd.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kernlabmmd`; the argument layout is at the top of scripts/r_oracle/groups/kernlabmmd.R.

use e.algo.rand.r as rr
use e.algo.stat.kernlabmmd as km
use e.algo.stat.kernlabsig as sg
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let m = usize(z[0usize])
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let x = z[12usize..12usize + m * p]
    let y = z[12usize + m * p..12usize + m * p + n * p]
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[11usize]))
    let (out, e1) = mem.alloc[f64](a, 4usize)
    if e1 != ok { ret nan }
    var kind = usize(z[3usize])
    var par1 = z[4usize]
    if kind >= 100usize {
        // kpar = "automatic": sigma = sigest(rbind(x, y), scaled = FALSE)[2]
        var sr: [3]f64 = zero
        if sg.sigest(a, &g, z[12usize..12usize + (m + n) * p], m + n, p, 0.5f64, false, sr[0usize..3usize]) != ok { ret nan }
        par1 = sr[1usize]
        kind = kind - 100usize
    }
    let e = km.kmmd(a, &g, x, y, m, n, p, kind, par1, z[5usize], z[6usize], z[7usize], true, z[9usize], usize(z[8usize]), z[10usize] > 0.5f64, out)
    if e != ok { ret nan }
    if str.eq(c.name, "mmd1") { ret out[0usize] }
    if str.eq(c.name, "mmd3") { ret out[1usize] }
    if str.eq(c.name, "rad") { ret out[2usize] }
    ret out[3usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kernlabmmd.json")
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
