// e.algo.stat.pmcmr's Dunn many-to-one test against PMCMRplus. tests/oracle/pmcmr_many.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pmcmr_many`; the layout is at the top of scripts/r_oracle/groups/pmcmr_many.R.

use e.algo.stat.pmcmr as pm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let kind = usize(z[2usize])
    let jj = usize(z[3usize])
    let x = z[4usize..4usize + n]
    let (grp, e0) = mem.alloc[usize](a, n)
    let (rbar, e1) = mem.alloc[f64](a, k)
    let (rn, e2) = mem.alloc[f64](a, k)
    let (ps, e3) = mem.alloc[f64](a, k - 1usize)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { os.exit(4) }
    var t = 0usize
    while t < n {
        grp[t] = usize(z[4usize + n + t])
        t += 1usize
    }
    let (q, e4) = pm.setup(a, x, grp, k, rbar, rn)
    if e4 != ok { os.exit(5) }
    t = 1usize
    while t < k {
        let (zz, p) = pm.dunn_many(q, rbar, rn, t)
        ps[t - 1usize] = p
        t += 1usize
    }
    if kind == 0usize {
        let (zv, pv) = pm.dunn_many(q, rbar, rn, jj)
        let _ = pv
        ret zv
    }
    if kind == 2usize {
        if pm.p_adjust(a, ps, 0usize) != ok { os.exit(6) }
    }
    ret ps[jj - 1usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pmcmr_many.json")
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
