// e.algo.stat.gam step_gam against R gam::step.Gam. tests/oracle/gam_step.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gam_step`; the argument layout is at the top of scripts/r_oracle/groups/gam_step.R.

use e.algo.stat.gam as gm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let fam = usize(z[0usize])
    let n = usize(z[1usize])
    let nv = usize(z[2usize])
    let maxopt = usize(z[3usize])
    let direction = usize(z[4usize])
    let steps = usize(z[5usize])
    let o_start = 6usize
    let o_nopt = o_start + nv
    let o_kind = o_nopt + nv
    let o_df = o_kind + nv * maxopt
    let o_x = o_df + nv * maxopt
    let o_y = o_x + nv * n
    let what = usize(z[o_y + n])
    let idx = usize(z[o_y + n + 1usize])
    let (start, e1) = mem.alloc[usize](a, nv + 1usize)
    let (nopt, e2) = mem.alloc[usize](a, nv + 1usize)
    let (kind, e3) = mem.alloc[usize](a, nv * maxopt + 1usize)
    let (w, e4) = mem.alloc[f64](a, n + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var i = 0usize
    while i < nv {
        start[i] = usize(z[o_start + i])
        nopt[i] = usize(z[o_nopt + i])
        i += 1usize
    }
    i = 0usize
    while i < nv * maxopt {
        kind[i] = usize(z[o_kind + i])
        i += 1usize
    }
    i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    var path: gm.StepPath = zero
    if gm.step_gam(a, z[o_x..o_x + nv * n], n, nv, z[o_y..o_y + n], w[0usize..n], fam, maxopt, nopt[0usize..nv], kind[0usize..nv * maxopt], z[o_df..o_df + nv * maxopt], start[0usize..nv], direction, steps, &path) != ok { ret nan }
    if what == 0usize { ret f64(path.nm) }
    if what == 1usize { ret f64(path.items[idx]) }
    if what == 2usize { ret path.aic[idx] }
    if what == 3usize { ret path.dev[idx] }
    if what == 4usize { ret path.dfres[idx] }
    if what == 5usize { ret path.final_fit.coef[idx] }
    ret path.final_fit.eta[idx]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gam_step.json")
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
