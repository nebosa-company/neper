// e.algo.stat.armmer against arm for an lme4 model with one random intercept. tests/oracle/armmer.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R armmer`; the layout of a case is at the top of scripts/r_oracle/groups/armmer.R.

use e.algo.rand.r as rng
use e.algo.stat.armmer as am
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var t = 0usize
    while t < v.len {
        s += f64(t + 1usize) * v[t]
        t += 1usize
    }
    ret s
}

fn answer_glmer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let z = c.args
    let seed = z[0usize]
    let nsims = usize(z[1usize])
    let n = usize(z[2usize])
    let p = usize(z[3usize])
    let ng = usize(z[4usize])
    let theta = z[5usize]
    let which = usize(z[6usize])
    let from = usize(z[7usize])
    let len = usize(z[8usize])
    var at = 9usize
    let beta = z[at..at + p]
    at += p
    let u = z[at..at + ng]
    at += ng
    let w = z[at..at + n]
    at += n
    let x = z[at..at + n * p]
    at += n * p
    let (g, e0) = mem.alloc[usize](a, n)
    if e0 != ok { os.exit(10) }
    var i = 0usize
    while i < n {
        g[i] = usize(z[at + i])
        i += 1usize
    }
    let (fx, e3) = mem.alloc[f64](a, nsims * p)
    let (rn, e4) = mem.alloc[f64](a, nsims * ng)
    if e3 != ok || e4 != ok { os.exit(12) }
    var r: rng.Rng = zero
    rng.seed(&r, i64(seed))
    if am.sim_glmer(a, &r, x, w, g, n, p, ng, theta, beta, u, nsims, fx, rn) != ok { ret nan }
    if which == 1usize { ret wsum(fx[from * p..from * p + len]) }
    ret wsum(rn[from * ng..from * ng + len])
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let nan = 0.0f64 / 0.0f64
    var z = c.args
    var seed = 0.0f64
    var nsims = 0usize
    if str.eq(c.name, "simglmer") { ret answer_glmer(a, c) }
    let simt = str.eq(c.name, "simmert")
    let semt = str.eq(c.name, "semert")
    let sim = str.eq(c.name, "simmer") || simt
    var theta = 0.0f64
    if sim {
        seed = z[0usize]
        nsims = usize(z[1usize])
        z = z[2usize..z.len]
    }
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let ng = usize(z[2usize])
    var reml = true
    var at = 4usize
    if simt || semt {
        theta = z[3usize]
    } else {
        reml = z[3usize] == 1.0f64
    }
    var which = 0usize
    var from = 0usize
    var len = 0usize
    if str.eq(c.name, "dicmer") == false {
        which = usize(z[at])
        at += 1usize
    }
    if sim {
        from = usize(z[at])
        len = usize(z[at + 1usize])
        at += 2usize
    }
    let x = z[at..at + n * p]
    at += n * p
    let (g, e0) = mem.alloc[usize](a, n)
    if e0 != ok { os.exit(10) }
    var i = 0usize
    while i < n {
        g[i] = usize(z[at + i])
        i += 1usize
    }
    at += n
    let y = z[at..at + n]
    if str.eq(c.name, "dicmer") {
        let (d, de) = am.dic_mer(a, x, y, g, n, p, ng, reml)
        if de != ok { ret nan }
        ret d
    }
    if str.eq(c.name, "semer") || semt {
        let (sf, e1) = mem.alloc[f64](a, p)
        let (sr, e2) = mem.alloc[f64](a, ng)
        if e1 != ok || e2 != ok { os.exit(11) }
        if semt {
            if am.se_mer_theta(a, x, y, g, n, p, ng, theta, sf, sr) != ok { ret nan }
        } else if am.se_mer(a, x, y, g, n, p, ng, reml, sf, sr) != ok { ret nan }
        if which == 0usize { ret wsum(sf) }
        ret wsum(sr)
    }
    let (fx, e3) = mem.alloc[f64](a, nsims * p)
    let (rn, e4) = mem.alloc[f64](a, nsims * ng)
    let (sg, e5) = mem.alloc[f64](a, nsims)
    if e3 != ok || e4 != ok || e5 != ok { os.exit(12) }
    var r: rng.Rng = zero
    rng.seed(&r, i64(seed))
    if simt {
        if am.sim_mer_theta(a, &r, x, y, g, n, p, ng, theta, nsims, fx, rn, sg) != ok { ret nan }
    } else if am.sim_mer(a, &r, x, y, g, n, p, ng, nsims, fx, rn, sg) != ok { ret nan }
    if which == 0usize { ret wsum(sg) }
    if which == 1usize { ret wsum(fx[from * p..from * p + len]) }
    ret wsum(rn[from * ng..from * ng + len])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/armmer.json")
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
