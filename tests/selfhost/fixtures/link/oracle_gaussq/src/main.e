// e.algo.stat.gaussq against statmod: gauss.quad and gauss.quad.prob. tests/oracle/gaussq.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gaussq`; the layout is at the top of
// scripts/r_oracle/groups/gaussq.R.

use e.algo.rand.r as rng
use e.algo.stat.gaussq as gq
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "permp") { ret gq.permp(a, z[0usize], z[1usize], z[2usize], z[3usize], z[4usize], usize(z[5usize]), z[6usize] > 0.5f64) }
    if str.eq(c.name, "pft") { ret gq.power_fisher_test(a, z[0usize], z[1usize], z[2usize], z[3usize], z[4usize], usize(z[5usize]), i64(z[6usize])) }
    if str.eq(c.name, "igd") { ret gq.dinvgauss(z[0usize], z[1usize], z[2usize], false) }
    if str.eq(c.name, "igdl") { ret gq.dinvgauss(z[0usize], z[1usize], z[2usize], true) }
    if str.eq(c.name, "igp") { ret gq.pinvgauss(z[0usize], z[1usize], z[2usize], true, false) }
    if str.eq(c.name, "igpu") { ret gq.pinvgauss(z[0usize], z[1usize], z[2usize], false, false) }
    if str.eq(c.name, "qres") {
        let n = usize(z[2usize])
        let (o, e) = mem.alloc[f64](a, n)
        if e != ok { ret 0.0f64 / 0.0f64 }
        var rg: rng.Rng = zero
        rng.seed(&rg, i64(z[0usize]))
        gq.qresiduals(&rg, usize(z[1usize]), z[4usize..4usize + n], z[4usize + n..4usize + 2usize * n], z[4usize + 2usize * n..4usize + 3usize * n], z[3usize], o)
        var s = 0.0f64
        var q = 0usize
        while q < n {
            s += f64(q + 1usize) * o[q]
            q += 1usize
        }
        ret s
    }
    if str.eq(c.name, "igq") { ret gq.qinvgauss(z[0usize], z[1usize], z[2usize], true, false) }
    if str.eq(c.name, "igqu") { ret gq.qinvgauss(z[0usize], z[1usize], z[2usize], false, false) }
    if str.eq(c.name, "igql") { ret gq.qinvgauss(z[0usize], z[1usize], z[2usize], true, true) }
    if str.eq(c.name, "igpl") { ret gq.pinvgauss(z[0usize], z[1usize], z[2usize], true, true) }
    if str.eq(c.name, "igr") {
        // args (n, mean, dispersion, seed, index)
        let rn = usize(z[0usize])
        let (ro, roe) = mem.alloc[f64](a, rn)
        if roe != ok { ret nan }
        if gq.rinvgauss(a, rn, z[1usize], z[2usize], i64(z[3usize]), ro) != ok { ret nan }
        ret ro[usize(z[4usize])]
    }
    let id = usize(z[0usize])
    let n = usize(z[1usize])
    let p1 = z[2usize]
    let p2 = z[3usize]
    let i = usize(z[6usize])
    let (nodes, e1) = mem.alloc[f64](a, n)
    let (w, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret nan }
    var good = false
    if id < 10usize {
        good = gq.gauss_quad(a, n, u8(id), p1, p2, nodes, w)
    } else {
        let d = u8(id - 10usize)
        good = gq.gauss_quad_prob(a, n, d, p1, p2, p1, p2, p1, p2, nodes, w)
    }
    if !good { ret nan }
    if str.eq(c.name, "node") { ret nodes[i] }
    ret w[i]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gaussq.json")
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
