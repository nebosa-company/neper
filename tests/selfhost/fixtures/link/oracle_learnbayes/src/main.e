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

    if str.eq(k, "lpost2") {
        // (which, m, p, th[...], ...) which 0 logisticpost (th = b0, b1; x[m], n[m], y[m]) 1 weibullregpost (th = 2 + p; t[m], c[m], X[m p])
        // 2 groupeddatapost (th = mu, lsig; f[m], lo[m], hi[m]) 3 logctablepost (th = 2; s1, f1, s2, f2) 4 transplantpost (th = 3; x[m], t[m], y[m], d[m])
        let w = usize(x[0usize])
        let m = usize(x[1usize])
        let pp = usize(x[2usize])
        var nth = 2usize
        if w == 1usize { nth = 2usize + pp }
        if w == 4usize { nth = 3usize }
        let th = x[3usize..3usize + nth]
        let d = x[3usize + nth..x.len]
        if w == 0usize { ret lb.logisticpost(th[0usize], th[1usize], d[0usize..m], d[m..2usize * m], d[2usize * m..3usize * m]) }
        if w == 1usize { ret lb.weibullregpost(th, d[0usize..m], d[m..2usize * m], d[2usize * m..2usize * m + m * pp], m, pp) }
        if w == 2usize { ret lb.groupeddatapost(th[0usize], th[1usize], d[0usize..m], d[m..2usize * m], d[2usize * m..3usize * m]) }
        if w == 3usize { ret lb.logctablepost(th[0usize], th[1usize], d[0usize], d[1usize], d[2usize], d[3usize]) }
        ret lb.transplantpost(th, d[0usize..m], d[m..2usize * m], d[2usize * m..3usize * m], d[3usize * m..4usize * m])
    }

    if str.eq(k, "lpost") {
        // (which, a, b, n, y[n], e or n[n]) which 0 normchi2post, 1 betabinexch0, 2 betabinexch, 3 poissgamexch, 4 lbinorm, 5 cauchyerrorpost
        let w = usize(x[0usize])
        let m = usize(x[3usize])
        let y = x[4usize..4usize + m]
        let v2 = x[4usize + m..4usize + 2usize * m]
        if w == 0usize { ret lb.normchi2post(x[1usize], x[2usize], y) }
        if w == 1usize { ret lb.betabinexch0(x[1usize], x[2usize], y, v2) }
        if w == 2usize { ret lb.betabinexch(x[1usize], x[2usize], y, v2) }
        if w == 3usize { ret lb.poissgamexch(x[1usize], x[2usize], v2, y, x[4usize + 2usize * m]) }
        if w == 4usize { ret lb.lbinorm(x[1usize], x[2usize], x[4usize], x[5usize], x[6usize], x[7usize], x[8usize]) }
        ret lb.cauchyerrorpost(x[1usize], x[2usize], y)
    }
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
    if str.eq(k, "rigamma") {
        var r: rng.Rng = zero
        rng.seed(&r, i64(x[0usize]))
        var v = 0.0f64
        var q = 0usize
        while q <= usize(x[3usize]) {
            v = lb.rigamma(&r, x[1usize], x[2usize])
            q += 1usize
        }
        ret v
    }
    if str.eq(k, "rmnorm") {
        // (seed, n, d, index, mean[d], varcov[d d])
        var r: rng.Rng = zero
        rng.seed(&r, i64(x[0usize]))
        let rn = usize(x[1usize])
        let rd2 = usize(x[2usize])
        let (o, oe) = mem.alloc[f64](a, rn * rd2)
        if oe != ok { os.exit(5) }
        if lb.rmnorm(a, &r, rn, x[4usize..4usize + rd2], x[4usize + rd2..4usize + rd2 + rd2 * rd2], o) != ok { os.exit(6) }
        ret o[usize(x[3usize])]
    }
    if str.eq(k, "pdisc") {
        // (n, s, f, index, p[n], prior[n])
        let pn = usize(x[0usize])
        let (o, oe) = mem.alloc[f64](a, pn)
        if oe != ok { os.exit(5) }
        lb.pdisc(x[4usize..4usize + pn], x[4usize + pn..4usize + 2usize * pn], x[1usize], x[2usize], o)
        ret o[usize(x[3usize])]
    }
    if str.eq(k, "mixb") || str.eq(k, "mixn") || str.eq(k, "mixp") {
        // (n, which 0 post 1 par1 2 par2, index, d1, d2, probs[n], par1[n], par2[n], [y[d1], t[d1] for mixp])
        let mn = usize(x[0usize])
        let (po, e1) = mem.alloc[f64](a, mn)
        let (q1, e2) = mem.alloc[f64](a, mn)
        let (q2, e3) = mem.alloc[f64](a, mn)
        if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
        let pr = x[5usize..5usize + mn]
        let a1 = x[5usize + mn..5usize + 2usize * mn]
        let a2 = x[5usize + 2usize * mn..5usize + 3usize * mn]
        if str.eq(k, "mixb") { lb.binomial_beta_mix(pr, a1, a2, x[3usize], x[4usize], po, q1, q2) }
        if str.eq(k, "mixn") { lb.normal_normal_mix(pr, a1, a2, x[3usize], x[4usize], po, q1, q2) }
        if str.eq(k, "mixp") {
            let dn = usize(x[3usize])
            lb.poisson_gamma_mix(pr, a1, a2, x[5usize + 3usize * mn..5usize + 3usize * mn + dn], x[5usize + 3usize * mn + dn..5usize + 3usize * mn + 2usize * dn], po, q1, q2)
        }
        let w = usize(x[1usize])
        let idx = usize(x[2usize])
        if w == 0usize { ret po[idx] }
        if w == 1usize { ret q1[idx] }
        ret q2[idx]
    }
    if str.eq(k, "pbetat") {
        let (bf, po) = lb.pbetat(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize])
        if x[6usize] < 0.5f64 { ret bf }
        ret po
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
