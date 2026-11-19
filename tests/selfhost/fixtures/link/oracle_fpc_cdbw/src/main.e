// e.algo.stat.fpc_cdbw against fpc. tests/oracle/fpc_cdbw.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_cdbw`; the layout is at the top of scripts/r_oracle/groups/fpc_cdbw.R.

use e.algo.stat.fpc_cdbw as fd
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let what = usize(z[0usize])
    let r = usize(z[1usize])
    let ns = usize(z[2usize])
    let cs = z[3usize] > 0.5f64
    let n = usize(z[4usize])
    let p = usize(z[5usize])
    let cn = usize(z[6usize])
    let s = z[7usize..7usize + ns]
    let (cl, e0) = mem.alloc[usize](a, n)
    let (out, e1) = mem.alloc[f64](a, 4usize)
    if e0 != ok || e1 != ok { os.exit(4) }
    var i = 0usize
    while i < n {
        cl[i] = usize(z[7usize + ns + i])
        i += 1usize
    }
    let e = fd.cdbw(a, z[7usize + ns + n..], n, p, cl, cn, r, s, cs, out)
    if e != ok { os.exit(6) }
    ret out[what]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_cdbw.json")
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
                c2.args = c.args[0usize..7usize]
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
