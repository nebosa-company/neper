// e.algo.stat.mass's step_aic_lm against MASS stepAIC. tests/oracle/mass_stepx.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_step`; the layout is at the top of scripts/r_oracle/groups/mass_step.R.

use e.algo.stat.massstep as st
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn bsum(t: *const st.Tab, usedev: bool) -> f64 {
    var v = 0.0f64
    var i = 0usize
    while i < t.m {
        let w = f64(i + 1usize)
        if t.df[i] == t.df[i] { v += w * t.df[i] }
        if usedev && t.dev[i] == t.dev[i] { v += 2.0f64 * w * t.dev[i] }
        if t.aic[i] == t.aic[i] { v += 3.0f64 * w * t.aic[i] }
        if t.stat[i] == t.stat[i] { v += 4.0f64 * w * t.stat[i] }
        if t.p[i] == t.p[i] { v += 5.0f64 * w * t.p[i] }
        i += 1usize
    }
    ret v
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let mode = usize(z[0usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let nt = usize(z[4usize])
    let dir = usize(z[5usize])
    let nst = usize(z[10usize])
    var at = 11usize
    let (start, e0) = mem.alloc[usize](a, nst + 1usize)
    let (lo, e1) = mem.alloc[bool](a, nt)
    let (up, e2) = mem.alloc[bool](a, nt)
    let (inm, e3) = mem.alloc[bool](a, nt)
    let (asg, e4) = mem.alloc[usize](a, p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var i = 0usize
    while i < nst {
        start[i] = usize(z[at + i])
        i += 1usize
    }
    at += nst
    let x = z[at..at + n * p]
    at += n * p
    i = 0usize
    while i < p {
        asg[i] = usize(z[at + i])
        i += 1usize
    }
    at += p
    let vm = z[at..at + nt]
    at += nt
    let y = z[at..at + n]
    at += n
    i = 0usize
    while i < nt {
        lo[i] = z[at + i] != 0.0f64
        up[i] = z[at + nt + i] != 0.0f64
        inm[i] = false
        i += 1usize
    }
    i = 0usize
    while i < nst {
        inm[start[i] - 1usize] = true
        i += 1usize
    }
    let sp = st.Spec { n: n, p: p, x: x, assign: asg, nt: nt, vmask: vm, y: y, fam: usize(z[1usize]), scale: z[7usize], k: z[6usize] }
    if mode >= 2usize {
        var cand: []usize = zero
        var nc = 0usize
        var e = ok
        if mode == 2usize {
            let (cc, m, ee) = st.drop_scope(&sp, start, nst, lo, a)
            cand = cc
            nc = m
            e = ee
        } else {
            let (cc, m, ee) = st.add_scope(&sp, inm, up, a)
            cand = cc
            nc = m
            e = ee
        }
        if e != ok { ret nan }
        let (tb, te) = st.table(a, &sp, inm, cand[0usize..nc], mode == 3usize, usize(z[9usize]))
        if te != ok { ret nan }
        ret bsum(&tb, sp.fam != 3usize)
    }
    let (out, oe) = mem.alloc[f64](a, 6usize)
    let (fin, fe) = mem.alloc[bool](a, nt)
    if oe != ok || fe != ok { ret nan }
    let e = st.step_aic(a, &sp, start[0usize..nst], lo, up, dir != 2usize, dir != 1usize, usize(z[8usize]), out, fin)
    if e != ok { ret nan }
    if mode == 1usize { ret out[0usize] + 5.0f64 * out[1usize] + 0.37f64 * out[4usize] + 0.11f64 * out[5usize] }
    ret out[2usize] * 100000.0f64 + out[3usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_stepx.json")
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
                var shown = *c
                shown.args = c.args[0usize..11usize]
                let _ = io.print(oracle.describe(a, &shown, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
