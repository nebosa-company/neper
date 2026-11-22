// e.algo.stat.kernlabspecc against kernlab specc. tests/oracle/kernlabspecc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kernlabspecc`; the argument layout is at the top of scripts/r_oracle/groups/kernlabspecc.R.

use e.algo.rand.r as rr
use e.algo.stat.kernlabspecc as sc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let m = usize(z[0usize])
    let p = usize(z[1usize])
    let nc = usize(z[2usize])
    let kd = z[3usize]
    let x = z[8usize..8usize + m * p]
    let (cl, e1) = mem.alloc[usize](a, m)
    let (size, e2) = mem.alloc[usize](a, nc + 1usize)
    let (cent, e3) = mem.alloc[f64](a, nc * p)
    let (wss, e4) = mem.alloc[f64](a, nc)
    var sig: [1]f64 = zero
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[5usize]))
    var kind = 0usize
    if kd > 0.5f64 { kind = usize(kd) }
    if sc.specc(a, &g, x, m, p, nc, kind, z[4usize], kd < 0.0f64, z[6usize], usize(z[7usize]), cl, size, cent, wss, sig[0usize..1usize]) != ok { ret nan }
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "cl") {
        while i < m {
            s += f64(cl[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "size") {
        while i < nc {
            s += f64(size[i + 1usize]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "cent") {
        while i < nc * p {
            s += cent[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "wss") {
        while i < nc {
            s += wss[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    ret sig[0usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kernlabspecc.json")
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
