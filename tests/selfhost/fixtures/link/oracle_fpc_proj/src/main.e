// e.algo.stat.fpc discrproj against fpc. tests/oracle/fpc_proj.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_proj`; the layout is at the top of scripts/r_oracle/groups/fpc_proj.R.

use e.algo.stat.fpc_proj as fj
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let method = usize(z[0usize])
    let what = usize(z[1usize])
    let idx = usize(z[2usize])
    let n = usize(z[3usize])
    let p = usize(z[4usize])
    let k = usize(z[5usize])
    let clnum = usize(z[6usize])
    let ign = z[7usize] > 0.5f64
    let nn = usize(z[8usize])
    let md = z[9usize] > 0.5f64
    let cw = z[10usize] > 0.5f64
    let alpha = z[11usize]
    let sph = z[12usize] > 0.5f64
    let x = z[13usize..13usize + n * p]
    let (cl, e0) = mem.alloc[usize](a, n)
    if e0 != ok { os.exit(4) }
    var i = 0usize
    while i < n {
        cl[i] = usize(z[13usize + n * p + i])
        i += 1usize
    }
    let cvm = z[13usize + n * p + n..z.len]
    let (ev, e1) = mem.alloc[f64](a, p)
    let (un, e2) = mem.alloc[f64](a, p * p)
    let (pj, e3) = mem.alloc[f64](a, n * p)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
    var sphere = cvm[0usize..0usize]
    if sph { sphere = cvm }
    let e = fj.discrproj(a, x, n, p, cl, k, method, clnum, ign, nn, md, cw, alpha, sphere, ev, un, pj)
    if e != ok { os.exit(6) }
    if what == 0usize { ret ev[idx] }
    if what == 1usize { ret un[idx] }
    var tot = 0.0f64
    var r = 0usize
    while r < n {
        tot += f64(r + 1usize) * pj[r * p + idx]
        r += 1usize
    }
    ret tot
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_proj.json")
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
                var c2 = *c
                c2.args = c.args[0usize..13usize]
                let _ = io.print(oracle.describe(a, &c2, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
