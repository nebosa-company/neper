// e.algo.stat.fpc_mixpred against fpc. tests/oracle/fpc_mixpred.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_mixpred`; the layout is at the top of scripts/r_oracle/groups/fpc_mixpred.R.

use e.algo.rand.r as rg
use e.algo.stat.fpc_mixpred as fm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn is(c: *const oracle.Case, s: str) -> bool {
    if c.name.len != s.len { ret false }
    var i = 0usize
    while i < s.len {
        if c.name[i] != s[i] { ret false }
        i += 1usize
    }
    ret true
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    var g: rg.Rng = zero
    rg.seed(&g, i64(z[0usize]))
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let gc = usize(z[3usize])
    let mm = usize(z[5usize])
    let what = usize(z[6usize])
    let idx = usize(z[7usize])
    let x = z[8usize..8usize + n * p]
    var models: [14]usize = zero
    var nm = 0usize
    if p == 1usize {
        models[0usize] = 0usize
        models[1usize] = 1usize
        nm = 2usize
    } else {
        var i = 2usize
        while i < 16usize {
            models[i - 2usize] = i
            i += 1usize
        }
        nm = 14usize
    }
    if is(c, "mp") {
        let (pc, e0) = mem.alloc[f64](a, mm)
        if e0 != ok { os.exit(4) }
        let (mean, e1) = fm.mixpredictive(a, &g, x, n, p, gc, usize(z[4usize]), mm, models[0usize..nm], pc)
        if e1 != ok { os.exit(5) }
        if what == 0usize { ret mean }
        ret pc[idx]
    }
    let (pv, e2) = mem.alloc[f64](a, gc)
    let (mp, e3) = mem.alloc[usize](a, gc)
    let (cls, e5) = mem.alloc[usize](a, n)
    if e2 != ok || e3 != ok || e5 != ok { os.exit(4) }
    let (gopt, e4) = fm.predictive(a, &g, x, n, p, gc, z[4usize], mm, models[0usize..nm], pv, mp, cls)
    if e4 != ok { os.exit(5) }
    if what == 0usize { ret pv[idx] }
    if what == 1usize { ret f64(gopt) }
    var t = 0.0f64
    var q = 0usize
    if what == 2usize {
        while q < gc {
            t += f64(mp[q]) * f64(q + 1usize)
            q += 1usize
        }
        ret t
    }
    q = 0usize
    while q < n {
        t += f64(cls[q]) * f64(q + 1usize)
        q += 1usize
    }
    ret t
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_mixpred.json")
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
                c2.args = c.args[0usize..8usize]
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
