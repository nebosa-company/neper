// e.algo.stat.fpc_coord against fpc: adcoord, mvdcoord, awcoord and ancoord. tests/oracle/fpc_coord.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_coord`; the layout of every case is at the top of scripts/r_oracle/groups/fpc_coord.R.

use e.algo.stat.fpc_coord as fc
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let fn_id = usize(z[0usize])
    let what = usize(z[1usize])
    let idx = usize(z[2usize])
    let n = usize(z[3usize])
    let p = usize(z[4usize])
    let kn = usize(z[5usize])
    let nn = usize(z[6usize])
    let f1 = z[7usize] > 0.5f64
    let f2 = z[8usize] > 0.5f64
    let alpha = z[9usize]
    let x = z[10usize..10usize + n * p]
    let (lab, e0) = mem.alloc[usize](a, n)
    let (ev, e1) = mem.alloc[f64](a, p)
    let (un, e2) = mem.alloc[f64](a, p * p)
    let (pj, e3) = mem.alloc[f64](a, n * p)
    let (wg, e4) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(4) }
    var i = 0usize
    while i < n {
        lab[i] = usize(z[10usize + n * p + i])
        i += 1usize
    }
    var e = ok
    var nw = 0usize
    if fn_id == 1usize { e = fc.adcoord(a, x, n, p, lab, ev, un, pj) }
    if fn_id == 2usize {
        var sphere = z[0usize..0usize]
        if f1 { sphere = z[10usize + n * p + n..10usize + n * p + n + p * p] }
        e = fc.mvdcoord(a, x, n, p, lab, kn, sphere, ev, un, pj)
    }
    if fn_id == 3usize { e = fc.awcoord(a, x, n, p, lab, f1, f2, alpha, ev, un, pj, wg) }
    if fn_id == 4usize { e = fc.ancoord(a, x, n, p, lab, nn, ev, un, pj) }
    if e != ok { os.exit(6) }
    if what == 0usize { ret ev[idx] }
    if what == 1usize { ret un[idx] }
    var tot = 0.0f64
    if what == 4usize {
        nw = n
        if !f2 {
            nw = 0usize
            i = 0usize
            while i < n {
                if lab[i] == 0usize { nw += 1usize }
                i += 1usize
            }
        }
        i = 0usize
        while i < nw {
            tot += f64(i + 1usize) * wg[i]
            i += 1usize
        }
        ret tot
    }
    i = 0usize
    while i < n {
        tot += f64(i + 1usize) * pj[i * p + idx]
        i += 1usize
    }
    ret tot
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_coord.json")
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
            if failures <= 10usize {
                var c2 = *c
                c2.args = c.args[0usize..10usize]
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
