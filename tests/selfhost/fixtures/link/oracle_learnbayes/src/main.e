// e.algo.stat.learnbayes against LearnBayes. tests/oracle/learnbayes.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R learnbayes`; the layout is at the top of scripts/r_oracle/groups/learnbayes.R.

use e.algo.stat.learnbayes as lb
use e.io
use e.mem
use e.os
use e.str
use e.algo.rand.r as rng
use e.test.oracle as oracle

fn rnd2(v: f64) -> f64 {
    let s = v * 100.0f64
    var f = s - e_floor(s)
    var r = e_floor(s)
    if f > 0.5f64 { r = r + 1.0f64 }
    if f == 0.5f64 {
        var h = r / 2.0f64
        if h - e_floor(h) != 0.0f64 { r = r + 1.0f64 }
    }
    ret r / 100.0f64
}

fn e_floor(v: f64) -> f64 {
    var i = i64(v)
    if f64(i) > v { i -= 1i64 }
    ret f64(i)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "rwm") || str.eq(k, "ind") {
        // args (seed, kind, pb, m, scale, index (-1 acceptance), par[4], [mu[pb] for ind], var[pb^2], start[pb])
        var r: rng.Rng = zero
        rng.seed(&r, i64(x[0usize]))
        let kd = usize(x[1usize])
        let pb = usize(x[2usize])
        let m = usize(x[3usize])
        let par = x[6usize..10usize]
        let (o, oe) = mem.alloc[f64](a, m * pb)
        if oe != ok { os.exit(5) }
        var acc = 0.0f64
        if str.eq(k, "rwm") {
            acc = lb.rwmetrop(a, &r, kd, par, x[10usize..10usize + pb * pb], x[4usize], x[10usize + pb * pb..10usize + pb * pb + pb], m, o)
        } else {
            acc = lb.indepmetrop(a, &r, kd, par, x[10usize..10usize + pb], x[10usize + pb..10usize + pb + pb * pb], x[10usize + pb + pb * pb..10usize + pb + pb * pb + pb], m, o)
        }
        if x[5usize] < 0.0f64 { ret acc }
        ret o[usize(x[5usize])]
    }
    if str.eq(k, "pbetap") { ret lb.pbetap(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "discint") {
        let n = usize(x[1usize])
        let (ord, e) = mem.alloc[usize](a, n)
        if e != ok { os.exit(5) }
        let (ep, cnt) = lb.discint(a, x[3usize..3usize + n], x[0usize], ord)
        if x[2usize] < 0.5f64 { ret ep }
        ret f64(cnt)
    }
    if str.eq(k, "bf") { ret lb.mnormt_onesided_bf(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize]) }
    if str.eq(k, "nsel") {
        let (mu, sg) = lb.normal_select(x[0usize], x[1usize], x[2usize], x[3usize])
        if x[4usize] < 0.5f64 { ret mu }
        ret sg
    }
    if str.eq(k, "bsel") {
        let (aa, bb, e) = lb.beta_select(a, x[0usize], x[1usize], x[2usize], x[3usize])
        if e != ok { os.exit(6) }
        if x[4usize] < 0.5f64 { ret rnd2(aa) }
        ret rnd2(bb)
    }
    let g = usize(x[2usize])
    ret lb.bfexch(x[0usize], x[1usize], x[3usize..3usize + g], x[3usize + g..3usize + 2usize * g])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/learnbayes.json")
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
