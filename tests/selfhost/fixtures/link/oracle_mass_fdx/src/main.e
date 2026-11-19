// e.algo.stat.fitdistx against MASS fitdistr with fixed parameters, starts, bounds and forced methods.
// tests/oracle/mass_fdx.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_fdx`; the layout is at the top of scripts/r_oracle/groups/mass_fdx.R.

use e.algo.stat.fitdistx as fx
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let kind = usize(z[0usize])
    let n = usize(z[1usize])
    let free = z[2usize..5usize]
    let fixed = z[5usize..8usize]
    let use_start = z[8usize] != 0.0f64
    let start = z[9usize..12usize]
    let bounded = z[12usize] != 0.0f64
    let lo3 = z[13usize..16usize]
    let up3 = z[16usize..19usize]
    let method = usize(z[19usize])
    let which = usize(z[20usize])
    let x = z[21usize..21usize + n]
    var nf = 0usize
    var lo: [3]f64 = zero
    var up: [3]f64 = zero
    var k = 0usize
    while k < 3usize {
        if free[k] != 0.0f64 {
            lo[nf] = lo3[k]
            up[nf] = up3[k]
            nf += 1usize
        }
        k += 1usize
    }
    let (out, e0) = mem.alloc[f64](a, 16usize)
    if e0 != ok { ret nan() }
    let e = fx.fitdistr(a, x, kind, free, fixed, start, use_start, bounded, lo[0usize..3usize], up[0usize..3usize], method, out)
    if e != ok { ret nan() }
    if which == 100usize { ret f64(n) }
    if which == 50usize {
        var t = 0.0f64
        var j = 0usize
        while j < nf * nf {
            t += f64(j + 1usize) * out[2usize * nf + 1usize + j]
            j += 1usize
        }
        ret t
    }
    if which == 51usize { ret out[2usize * nf + 2usize] }
    ret out[which]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_fdx.json")
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
