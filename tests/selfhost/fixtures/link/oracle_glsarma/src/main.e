// e.algo.stat.gls against nlme::gls with corARMA(p, q) of orders other than (1, 1).
// tests/oracle/glsarma.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R glsarma`; the case layout is at the
// top of scripts/r_oracle/groups/glsarma.R.

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

// cases of one fit differ only in the output index (args[0]): the fit is kept in kout while the rest of the arguments repeat
fn same_fit(key: []const f64, x: []const f64, klen: usize) -> bool {
    if klen != x.len { ret false }
    var i = 1usize
    while i < x.len {
        if key[i] != x[i] { ret false }
        i += 1usize
    }
    ret true
}

fn answer(a: *mem.Arena, c: *const oracle.Case, key: []f64, kout: []f64, klen: *usize, kgood: *bool) -> f64 {
    let x = c.args
    let q = usize(x[0usize])
    let nan = 0.0f64 / 0.0f64
    if !(*kgood && same_fit(key, x, *klen)) {
        *kgood = false
        let (pr, pe) = parse(a, x, 1usize)
        if pe != ok { ret nan }
        let len = g.out_len(&pr.s)
        if len > kout.len || x.len > key.len { ret nan }
        let fe = g.gls_fit(a, pr.s, kout[0usize..len])
        if fe != ok { ret nan }
        var i = 0usize
        while i < x.len {
            key[i] = x[i]
            i += 1usize
        }
        *klen = x.len
        *kgood = true
    }
    ret kout[q]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/glsarma.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    let (key, ke) = mem.alloc[f64](a, 4096usize)
    let (kout, oe) = mem.alloc[f64](a, 64usize)
    if ke != ok || oe != ok { os.exit(4) }
    var klen = 0usize
    var kgood = false
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let st = mem.mark(a)
        let got = answer(a, c, key, kout, &klen, &kgood)
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
