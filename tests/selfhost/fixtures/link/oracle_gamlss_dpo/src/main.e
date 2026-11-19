// e.algo.stat.gamlssdist's double Poisson DPO density, distribution and quantile against gamlss.dist (dDPO, pDPO, qDPO). tests/oracle/gamlss_dpo.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_dpo`; the layout of every case is at the top of scripts/r_oracle/groups/gamlss_dpo.R.

use e.algo.stat.gamlssdist as gd
use e.io
use e.mem
use e.algo.rand.r as rrg
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let which = usize(z[0usize])
    if which >= 100usize {
        var g: rrg.Rng = zero
        rrg.seed(&g, i64(z[1usize]))
        let nn = usize(z[2usize])
        let m = z[3usize]
        let sg = z[4usize]
        let v = z[5usize]
        let t = z[6usize]
        var tot = 0.0f64
        var i = 0usize
        while i < nn {
            let u = rrg.unif(&g)
            var x = 0.0f64
            let fam = which - 100usize
            if fam == 0usize { x = gd.qgg(u, m, sg, v) }
            if fam == 1usize { x = gd.qbccg(u, m, sg, v) }
            if fam == 2usize { x = gd.qig(u, m, sg) }
            if fam == 3usize { x = gd.qbct(u, m, sg, v, t) }
            if fam == 4usize { x = gd.qbcpe(u, m, sg, v, t) }
            if fam == 5usize { x = gd.qlno(u, m, sg, v) }
            if fam == 6usize { x = gd.qjsu(u, m, sg, v, t) }
            if fam == 7usize { x = gd.qgaf(u, m, sg, v) }
            if fam == 8usize { x = gd.qsichel(u, m, sg, v) }
            if fam == 9usize { x = gd.qnbii(u, m, sg) }
            tot += f64(i + 1usize) * x
            i += 1usize
        }
        ret tot
    }
    if which == 0usize { ret gd.ddpo(z[3usize], z[1usize], z[2usize]) }
    if which == 1usize { ret gd.pdpo(z[3usize], z[1usize], z[2usize]) }
    if which == 2usize { ret gd.qdpo(z[3usize], z[1usize], z[2usize]) }
    if which == 3usize { ret gd.ddbi(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 4usize { ret gd.pdbi(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 5usize { ret gd.qdbi(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 6usize { ret gd.dgaf(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 7usize { ret gd.pgaf(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 8usize { ret gd.qgaf(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 9usize { ret gd.dzisichel(z[3usize], z[1usize], z[2usize], z[4usize], z[5usize]) }
    if which == 10usize { ret gd.dsep(z[3usize], z[1usize], z[2usize], z[4usize], z[5usize]) }
    if which == 11usize { ret gd.dzasichel(z[3usize], z[1usize], z[2usize], z[4usize], z[5usize]) }
    if which == 12usize { ret gd.ddel(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 13usize { ret gd.pdel(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 14usize { ret gd.qdel(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 15usize { ret gd.psichel(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 16usize { ret gd.pzasichel(z[3usize], z[1usize], z[2usize], z[4usize], z[5usize]) }
    if which == 17usize { ret gd.qsichel(z[3usize], z[1usize], z[2usize], z[4usize]) }
    if which == 18usize { ret gd.qzasichel(z[3usize], z[1usize], z[2usize], z[4usize], z[5usize]) }
    if which == 19usize { ret gd.pzisichel(z[3usize], z[1usize], z[2usize], z[4usize], z[5usize]) }
    if which == 20usize { ret gd.qzisichel(z[3usize], z[1usize], z[2usize], z[4usize], z[5usize]) }
    if which == 21usize { ret gd.psep(a, z[3usize], z[1usize], z[2usize], z[4usize], z[5usize]) }
    ret gd.qsep(a, z[3usize], z[1usize], z[2usize], z[4usize], z[5usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_dpo.json")
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
