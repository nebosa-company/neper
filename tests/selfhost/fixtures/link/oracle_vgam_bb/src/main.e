// e.algo.stat.vgampkg's beta-binomial regression against VGAM::vglm(betabinomial). tests/oracle/vgam_bb.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vgam_bb`; the layout is at the top of scripts/r_oracle/groups/vgam_bb.R.

use e.algo.stat.vgampkg as vg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let (x, e0) = mem.alloc[f64](a, n * (p + 1usize))
    let (out, e1) = mem.alloc[f64](a, p + 3usize)
    if e0 != ok || e1 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        x[i * (p + 1usize)] = 1.0f64
        var t = 0usize
        while t < p {
            x[i * (p + 1usize) + 1usize + t] = z[2usize + 2usize * n + i * p + t]
            t += 1usize
        }
        i += 1usize
    }
    if !vg.betabinomial(a, x, z[2usize..2usize + n], z[2usize + n..2usize + 2usize * n], n, p + 1usize, out) { ret 0.0f64 / 0.0f64 }
    ret out[usize(z[2usize + 2usize * n + n * p])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vgam_bb.json")
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
