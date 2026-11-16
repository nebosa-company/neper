// e.algo.stat.pcapp against pcaPP cor.fk, l1median_HoCr, l1median_VaZh and l1median. tests/oracle/pcapp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pcapp`; the layout is at the top of scripts/r_oracle/groups/pcapp.R.

use e.algo.stat.pcapp as pc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    if str.eq(c.name, "corfk") { ret pc.cor_fk(a, z[1usize..1usize + n], z[1usize + n..1usize + 2usize * n], true) }
    if str.eq(c.name, "qn") { ret pc.qn_of(a, z[1usize..1usize + n]) }
    if str.eq(c.name, "pj") {
        let pp = usize(z[1usize])
        let k = usize(z[2usize])
        let off = 8usize
        let (yy, ey) = mem.alloc[f64](a, n * pp)
        let (ld, el) = mem.alloc[f64](a, pp * k)
        let (zz, ez) = mem.alloc[f64](a, n * k)
        let (lm, em) = mem.alloc[f64](a, k)
        if ey != ok || el != ok || ez != ok || em != ok { ret nan }
        var q = 0usize
        while q < n * pp {
            yy[q] = z[off + q] - z[off + n * pp + q / n]
            q += 1usize
        }
        let e = pc.pca_proj(a, yy, n, pp, n, k, i64(z[3usize]), z[7usize], z[4usize] == 1.0f64, usize(z[5usize]), usize(z[6usize]), ld, zz, lm)
        if e != ok { ret nan }
        pc.proj_finish(pp, n, k, ld, zz, lm)
        let wi = usize(z[off + n * pp + pp])
        if wi < k { ret lm[wi] }
        if wi < k + pp * k { ret ld[wi - k] }
        ret zz[wi - k - pp * k]
    }
    let p = usize(z[1usize])
    let x = z[5usize..5usize + n * p]
    let (med, e1) = mem.alloc[f64](a, p)
    if e1 != ok { ret nan }
    var j = 0usize
    while j < p {
        med[j] = z[5usize + n * p + j]
        j += 1usize
    }
    let w = usize(z[5usize + n * p + p])
    var iter = 0i64
    var code = 0i64
    if str.eq(c.name, "vazh") {
        let (r, e) = pc.l1median_vazh(a, x, n, p, med, z[3usize], z[4usize], i64(z[2usize]))
        if e != ok { ret nan }
        iter = r.iter
        code = r.code
    } else {
        let (r, e) = pc.l1median_hocr(a, x, n, p, med, z[3usize], i64(z[2usize]))
        if e != ok { ret nan }
        iter = r.iter + 1i64
        code = r.code
    }
    if w < p { ret med[w] }
    if w == p { ret pc.l1_obj(x, n, p, med) }
    if w == p + 1usize { ret f64(code) }
    ret f64(iter)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pcapp.json")
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
