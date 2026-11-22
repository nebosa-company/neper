// e.algo.stat.kernlabgpc against kernlab gausspr classification. tests/oracle/kernlabgpc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kernlabgpc`; the argument layout is at the top of scripts/r_oracle/groups/kernlabgpc.R.

use e.algo.stat.kernlabclass as cl
use e.algo.stat.kernlabgpc as gc
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(v: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let kc = usize(z[2usize])
    let scaled = z[4usize] != 0.0f64
    let nt = usize(z[6usize])
    let (x, e1) = mem.alloc[f64](a, n * p)
    let (xt, e2) = mem.alloc[f64](a, nt * p)
    let (cen, e3) = mem.alloc[f64](a, p)
    let (scl, e4) = mem.alloc[f64](a, p)
    let (cls, e5) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan }
    var i = 0usize
    while i < n {
        cls[i] = usize(z[7usize + i]) - 1usize
        i += 1usize
    }
    i = 0usize
    while i < n * p {
        x[i] = z[7usize + n + i]
        i += 1usize
    }
    i = 0usize
    while i < nt * p {
        xt[i] = z[7usize + n + n * p + i]
        i += 1usize
    }
    if scaled {
        if cl.scale_cols(a, x, n, p, cen, scl) != ok { ret nan }
        cl.apply_scale(xt, nt, p, cen, scl)
    }
    let np = kc * (kc - 1usize) / 2usize
    let (alpha, e6) = mem.alloc[f64](a, np * n)
    let (dec, e7) = mem.alloc[f64](a, np * nt)
    let (resp, e8) = mem.alloc[usize](a, nt)
    let (pr, e9) = mem.alloc[f64](a, nt * kc)
    if e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret nan }
    if gc.fit(a, x, n, p, cls, kc, 0usize, z[3usize], z[5usize], alpha) != ok { ret nan }
    if str.eq(c.name, "alpha") { ret wsum(alpha, np * n) }
    if gc.decisions(a, x, n, p, kc, 0usize, z[3usize], alpha, xt, nt, dec) != ok { ret nan }
    if str.eq(c.name, "resp") {
        gc.respond(dec, kc, nt, resp)
        var s = 0.0f64
        i = 0usize
        while i < nt {
            s += f64(resp[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    var which = 0usize
    if str.eq(c.name, "prob_pkpd") { which = 1usize }
    if str.eq(c.name, "prob_vote") { which = 2usize }
    if gc.probabilities(a, dec, kc, nt, which, pr) != ok { ret nan }
    ret wsum(pr, nt * kc)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kernlabgpc.json")
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
