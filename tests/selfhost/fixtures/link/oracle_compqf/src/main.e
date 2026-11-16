// e.algo.stat.compqf against CompQuadForm davies and farebrother. tests/oracle/compqf.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R compqf`; the layout is at the top of scripts/r_oracle/groups/compqf.R.

use e.algo.stat.compqf as cq
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let r = usize(z[0usize])
    let (h, e1) = mem.alloc[i64](a, r)
    if e1 != ok { ret nan }
    var i = 0usize
    while i < r {
        h[i] = i64(z[5usize + r + i])
        i += 1usize
    }
    let lam = z[5usize..5usize + r]
    let dl = z[5usize + 2usize * r..5usize + 3usize * r]
    let w = usize(z[5usize + 3usize * r])
    if str.eq(c.name, "davies") {
        let (out, e) = cq.davies(a, lam, dl, h, z[1usize], z[2usize], i64(z[3usize]), z[4usize])
        if e != ok { ret nan }
        if w == 0usize { ret out.qq }
        if w == 1usize { ret f64(out.ifault) }
        ret out.trace[w - 2usize]
    }
    let (out, e) = cq.farebrother(a, lam, h, dl, z[1usize], z[4usize], usize(z[2usize]), z[3usize])
    if e != ok { ret nan }
    if w == 0usize { ret out.qq }
    if w == 1usize { ret out.dnsty }
    ret f64(out.ifault)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/compqf.json")
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
