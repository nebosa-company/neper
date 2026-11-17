// e.algo.stat.mclusthc against mclust. tests/oracle/mclust3.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust3`; the layout is at the top of scripts/r_oracle/groups/mclust3.R.

use e.algo.stat.mclusthc as hc
use e.algo.stat.mclusthcv as hv
use e.algo.stat.mclustpkg as mp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "hc1") {
        // (model 0 E 1 V, n, id, x[n]): hc of one variable is the VII criterion with p = 1 (V) or Ward (E)
        let m1 = usize(z[0usize])
        let n1 = usize(z[1usize])
        let (pr, pe) = mem.alloc[usize](a, 2usize * n1)
        if pe != ok { ret nan }
        if m1 == 0usize {
            if mp.hc_eii(a, z[3usize..3usize + n1], n1, 1usize, pr) != ok { ret nan }
        } else {
            if hc.hc_run(a, z[3usize..3usize + n1], n1, 1usize, 0usize, 1.0f64, 1.0f64, pr) != ok { ret nan }
        }
        if z[2usize] < 0.0f64 {
            var s1 = 0.0f64
            var q1 = 0usize
            while q1 < 2usize * (n1 - 1usize) {
                s1 += f64(q1 + 1usize) * f64(pr[q1])
                q1 += 1usize
            }
            ret s1
        }
        ret 1000.0f64 * f64(pr[0usize]) + f64(pr[1usize])
    }
    let model = usize(z[0usize])
    let uz = usize(z[1usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let id = z[4usize]
    let (zz, e1) = mem.alloc[f64](a, n * p)
    let (pairs, e2) = mem.alloc[usize](a, 2usize * n)
    if e1 != ok || e2 != ok { ret nan }
    if hc.hc_prep(a, z[5usize..5usize + n * p], n, p, uz, zz) != ok { ret nan }
    if model == 1usize {
        if hv.hc_vvv(a, zz, n, p, 1.0f64, 1.0f64, pairs) != ok { ret nan }
    } else {
        if hc.hc_run(a, zz, n, p, model, 1.0f64, 1.0f64, pairs) != ok { ret nan }
    }
    if str.eq(c.name, "hc3") {
        if id < 0.0f64 {
            var s = 0.0f64
            var q = 0usize
            while q < 2usize * (n - 1usize) {
                s += f64(q + 1usize) * f64(pairs[q])
                q += 1usize
            }
            ret s
        }
        let m = usize(id)
        ret 1000.0f64 * f64(pairs[2usize * m]) + f64(pairs[2usize * m + 1usize])
    }
    if str.eq(c.name, "hcl") {
        let (lab, e3) = mem.alloc[usize](a, n)
        if e3 != ok { ret nan }
        if hc.hclass(a, pairs, n, usize(id), lab) != ok { ret nan }
        var s = 0.0f64
        var q = 0usize
        while q < n {
            s += f64(q + 1usize) * f64(lab[q] + 1usize)
            q += 1usize
        }
        ret s
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust3.json")
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
