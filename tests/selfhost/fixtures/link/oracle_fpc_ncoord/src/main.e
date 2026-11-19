// e.algo.stat.fpc ncoord against fpc. tests/oracle/fpc_ncoord.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_ncoord`; the layout is at the top of scripts/r_oracle/groups/fpc_ncoord.R.

use e.algo.stat.fpc as fp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let k = usize(z[2usize])
    let nn = usize(z[3usize])
    let wtd = z[4usize] > 0.5f64
    let sph = z[5usize] > 0.5f64
    let what = usize(z[6usize])
    let idx = usize(z[7usize])
    let x = z[8usize..8usize + n * p]
    let (cl, e0) = mem.alloc[usize](a, n)
    if e0 != ok { os.exit(4) }
    var i = 0usize
    while i < n {
        cl[i] = usize(z[8usize + n * p + i])
        i += 1usize
    }
    let cvm = z[8usize + n * p + n..8usize + n * p + n + p * p]
    let (ev, e1) = mem.alloc[f64](a, p)
    let (un, e2) = mem.alloc[f64](a, p * p)
    let (pj, e3) = mem.alloc[f64](a, n * p)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
    var sphere = cvm[0usize..0usize]
    if sph { sphere = cvm }
    let e = fp.ncoord(a, x, n, p, cl, k, nn, wtd, sphere, ev, un, pj)
    if e != ok { os.exit(6) }
    if what == 0usize { ret ev[idx] }
    // the axis sign: the largest-magnitude entry of the direction made positive
    var col = idx % p
    var bestv = 0.0f64
    var sgn = 1.0f64
    var r = 0usize
    while r < p {
        var av = un[r * p + col]
        if av < 0.0f64 { av = 0.0f64 - av }
        if av > bestv {
            bestv = av
            sgn = 1.0f64
            if un[r * p + col] < 0.0f64 { sgn = 0.0f64 - 1.0f64 }
        }
        r += 1usize
    }
    if what == 1usize { ret sgn * un[idx] }
    ret sgn * pj[idx]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_ncoord.json")
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
