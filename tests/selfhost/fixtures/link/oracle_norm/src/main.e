// e.algo.stat.normem against norm: em.norm and loglik.norm. tests/oracle/norm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R norm`; the layout is at the top of
// scripts/r_oracle/groups/norm.R.

use e.algo.stat.normem as nm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "mi") {
        let mm = usize(z[0usize])
        let (ev, e5) = mem.alloc[f64](a, mm)
        let (sv, e6) = mem.alloc[f64](a, mm)
        let (ov, e7) = mem.alloc[f64](a, 8usize)
        if e5 != ok || e6 != ok || e7 != ok { ret 0.0f64 / 0.0f64 }
        let qq = usize(z[2usize + 4usize * mm])
        var k = 0usize
        while k < mm {
            ev[k] = z[2usize + k * 2usize + qq]
            sv[k] = z[2usize + 2usize * mm + k * 2usize + qq]
            k += 1usize
        }
        nm.mi_inference(ev, sv, z[1usize], ov)
        ret ov[usize(z[3usize + 4usize * mm])]
    }
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let x = z[3usize..3usize + n * p]
    if str.eq(c.name, "post") {
        let (pm, ep1) = mem.alloc[f64](a, p)
        let (ps2, ep2) = mem.alloc[f64](a, p * p)
        if ep1 != ok || ep2 != ok { ret 0.0f64 / 0.0f64 }
        let (pit, pe) = nm.em_norm(a, x, n, p, 0.0001f64, 1000usize, pm, ps2)
        if pe != ok { ret 0.0f64 / 0.0f64 }
        let b = 3usize + n * p
        let (lp, lpe) = nm.logpost_norm(a, x, n, p, pm, ps2, z[b], z[b + 1usize], z[b + 2usize..b + 2usize + p], z[b + 2usize + p..b + 2usize + p + p * p])
        if lpe != ok { ret 0.0f64 / 0.0f64 }
        ret lp
    }
    let q = usize(z[3usize + n * p])
    let (mu, e1) = mem.alloc[f64](a, p)
    let (sg, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    let (it, e) = nm.em_norm(a, x, n, p, z[2usize], 1000usize, mu, sg)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if q < p { ret mu[q] }
    if q < p + p * p { ret sg[q - p] }
    let (ll, le) = nm.loglik_norm(a, x, n, p, mu, sg)
    if le != ok { ret 0.0f64 / 0.0f64 }
    ret ll
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/norm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
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
