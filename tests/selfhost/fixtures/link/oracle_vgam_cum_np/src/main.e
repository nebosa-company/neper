// e.algo.stat.vgampkg's proportional odds model against VGAM::vglm(cumulative(parallel = TRUE)). tests/oracle/vgam_cum_np.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vgam_cum_np`; the layout is at the top of scripts/r_oracle/groups/vgam_cum_np.R.

use e.algo.stat.vgampkg as vg
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let jn = usize(z[2usize])
    let lk = usize(z[3usize])
    let (out, e1) = mem.alloc[f64](a, 2usize * (jn - 1usize) * (p + 1usize) + 2usize)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    if !vg.cum_np(a, z[4usize + n..4usize + n + n * p], z[4usize..4usize + n], n, p, jn, lk, out) { ret 0.0f64 / 0.0f64 }
    ret out[usize(z[4usize + n + n * p])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vgam_cum_np.json")
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
