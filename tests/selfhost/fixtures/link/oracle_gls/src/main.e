// e.algo.stat.gls against nlme::gls (estimated correlation and variance structures, groups, anova, intervals).
// tests/oracle/gls.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gls`; the case layout is at the top of
// scripts/r_oracle/groups/gls.R.

use e.algo.stat.gls as g
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

type Parsed = struct { s: g.Spec, next: usize }

// the variance terms sit after the data as (kind, nstr, v[n]) triples; kinds and strata counts are gathered into two arrays
fn parse(a: *mem.Arena, x: []const f64, at: usize) -> (Parsed, err) {
    let reml = x[at] != 0.0f64
    let n = usize(x[at + 1usize])
    let p = usize(x[at + 2usize])
    let ck = i64(x[at + 3usize])
    let nv = usize(x[at + 4usize])
    let ng = usize(x[at + 5usize])
    var o = at + 6usize
    let gs = x[o..o + ng]
    o += ng
    let t = x[o..o + n]
    o += n
    let y = x[o..o + n]
    o += n
    let xm = x[o..o + n * p]
    o += n * p
    let (vk, e1) = mem.alloc[f64](a, nv + 1usize)
    let (vn, e2) = mem.alloc[f64](a, nv + 1usize)
    let (vc, e3) = mem.alloc[f64](a, nv * n + 1usize)
    var sp: g.Spec = zero
    if e1 != ok || e2 != ok || e3 != ok { ret (Parsed { s: sp, next: o }, e1) }
    var k = 0usize
    while k < nv {
        vk[k] = x[o]
        vn[k] = x[o + 1usize]
        var i = 0usize
        while i < n {
            vc[k * n + i] = x[o + 2usize + i]
            i += 1usize
        }
        o += 2usize + n
        k += 1usize
    }
    sp = g.Spec { n: n, p: p, x: xm, y: y, t: t, gs: gs, ng: ng, ck: ck, nv: nv, vk: vk[0usize..nv], vn: vn[0usize..nv], vc: vc[0usize..nv * n], reml: reml, q: 0usize, z: x[0usize..0usize], pd: 0i64 }
    ret (Parsed { s: sp, next: o }, ok)
}

fn loglik(a: *mem.Arena, x: []const f64, at: usize) -> (f64, usize, f64, err) {
    let (pr, pe) = parse(a, x, at)
    if pe != ok { ret (0.0f64, at, 0.0f64, pe) }
    let len = g.out_len(&pr.s)
    let (out, oe) = mem.alloc[f64](a, len)
    if oe != ok { ret (0.0f64, at, 0.0f64, oe) }
    let fe = g.gls_fit(a, pr.s, out)
    if fe != ok { ret (0.0f64, pr.next, 0.0f64, fe) }
    ret (out[pr.s.p + 1usize], pr.next, 0.0f64, ok)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let mode = x[0usize]
    let q = usize(x[1usize])
    let nan = 0.0f64 / 0.0f64
    let (pr, pe) = parse(a, x, 2usize)
    if pe != ok { ret nan }
    let len = g.out_len(&pr.s)
    let (out, oe) = mem.alloc[f64](a, len)
    if oe != ok { ret nan }
    let fe = g.gls_fit(a, pr.s, out)
    if fe != ok { ret nan }
    if mode == 0.0f64 { ret out[q] }
    let (l2, nx, z, le) = loglik(a, x, pr.next)
    if le != ok { ret nan }
    ret 2.0f64 * (out[pr.s.p + 1usize] - l2)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gls.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let st = mem.mark(a)
        let got = answer(a, c)
        mem.reset(a, st)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
