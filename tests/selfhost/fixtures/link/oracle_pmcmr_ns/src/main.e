// e.algo.stat.pmcmr's vanWaerdenManyOneTest against PMCMRplus. tests/oracle/pmcmr_ns.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pmcmr_ns`; the layout is at the top of scripts/r_oracle/groups/pmcmr_ns.R.

use e.algo.stat.pmcmr as pm
use e.io
use e.math.dist as dist
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let kind = usize(z[2usize])
    let jj = usize(z[3usize])
    let ns_flag = true
    let x = z[4usize..4usize + n]
    let (grp, e0) = mem.alloc[usize](a, n)
    let (rbar, e1) = mem.alloc[f64](a, k)
    let (rn, e2) = mem.alloc[f64](a, k)
    let (ps, e3) = mem.alloc[f64](a, k - 1usize)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { os.exit(4) }
    var t = 0usize
    while t < n {
        grp[t] = usize(z[4usize + n + t]) - 1usize
        t += 1usize
    }
    t = 1usize
    while t < k {
        let (tv, p, pt, e7) = pm.vdw_pair(a, n, k, x, grp, t, 0usize, true, ns_flag)
        let _ = pt
        if e7 != ok { os.exit(7) }
        if kind == 0usize && t == jj { ret tv }
        if kind == 3usize && t == jj {
            var g3 = 0usize
            while g3 < k {
                rn[g3] = 0.0f64
                g3 += 1usize
            }
            var u3 = 0usize
            while u3 < n {
                rn[grp[u3]] += 1.0f64
                u3 += 1usize
            }
            ret pm.t_single_step_p(tv, rn, k, f64(n) - f64(k))
        }
        ps[t - 1usize] = p
        t += 1usize
    }
    if kind == 2usize {
        if pm.p_adjust(a, ps, 0usize) != ok { os.exit(6) }
    }
    ret ps[jj - 1usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pmcmr_ns.json")
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
