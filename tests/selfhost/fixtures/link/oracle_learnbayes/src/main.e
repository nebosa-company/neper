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


type LgCtx = struct { x: []const f64, n: []const f64, y: []const f64 }

fn lg_logf(c: *LgCtx, th: []const f64) -> f64 { ret lb.logisticpost(th[0usize], th[1usize], c.x, c.n, c.y) }

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name

    if str.eq(k, "nps") {
        // (seed, hasprior, m, n, a, b, mu0, tau2, which (0 mu, 1 sigma2), index, data[n])
        var rr: rng.Rng = zero
        rng.seed(&rr, i64(x[0usize]))
        let m = usize(x[2usize])
        let n = usize(x[3usize])
        let (omu, e1) = mem.alloc[f64](a, m)
        let (os2, e2) = mem.alloc[f64](a, m)
        if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
        lb.normpostsim(&rr, x[10usize..10usize + n], x[1usize] != 0.0f64, x[4usize], x[5usize], x[6usize], x[7usize], m, omu, os2)
        if x[8usize] == 0.0f64 { ret omu[usize(x[9usize])] }
        ret os2[usize(x[9usize])]
    }
    if str.eq(k, "blr") {
        // (seed, hasprior, m, n, p, c0, which (0 sigma, 1 beta), index, b0[p], y[n], X[n p])
        var rr: rng.Rng = zero
        rng.seed(&rr, i64(x[0usize]))
        let m = usize(x[2usize])
        let n = usize(x[3usize])
        let p = usize(x[4usize])
        let (sg, e1) = mem.alloc[f64](a, m)
        let (bt, e2) = mem.alloc[f64](a, m * p)
        if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
        if lb.blinreg(a, &rr, x[8usize + p..8usize + p + n], x[8usize + p + n..8usize + p + n + n * p], n, p, m, x[1usize] != 0.0f64, x[5usize], x[8usize..8usize + p], sg, bt) != ok { ret 0.0f64 / 0.0f64 }
        if x[6usize] == 0.0f64 { ret sg[usize(x[7usize])] }
        ret bt[usize(x[7usize])]
    }

    if str.eq(k, "sir") {
        // (seed, index, m, n, df, 0, mean[2], var[4], x[m], nn[m], y[m]): element index of the resampled n by 2 matrix
        var rr: rng.Rng = zero
        rng.seed(&rr, i64(x[0usize]))
        let m = usize(x[2usize])
        let ns = usize(x[3usize])
        var lc = LgCtx{ x: x[12usize..12usize + m], n: x[12usize + m..12usize + 2usize * m], y: x[12usize + 2usize * m..12usize + 3usize * m] }
        let (so, se) = mem.alloc[f64](a, ns * 2usize)
        if se != ok { ret 0.0f64 / 0.0f64 }
        if lb.sir[LgCtx](a, &rr, &lc, lg_logf, x[6usize..8usize], x[8usize..12usize], x[4usize], ns, so) != ok { ret 0.0f64 / 0.0f64 }
        ret so[usize(x[1usize])]
    }
    if str.eq(k, "gib") {
        // (seed, index, m, n, scale1, scale2, start[2], x[m], nn[m], y[m]): index < n * 2 the chain element (column-major, n sweeps), index >= n * 2 the acceptance rate of coordinate index - 2 n
        var rr: rng.Rng = zero
        rng.seed(&rr, i64(x[0usize]))
        let m = usize(x[2usize])
        let ns = usize(x[3usize])
        var lc = LgCtx{ x: x[8usize..8usize + m], n: x[8usize + m..8usize + 2usize * m], y: x[8usize + 2usize * m..8usize + 3usize * m] }
        let (go, ge) = mem.alloc[f64](a, ns * 2usize)
        let (ga, gae) = mem.alloc[f64](a, 2usize)
        if ge != ok || gae != ok { ret 0.0f64 / 0.0f64 }
        let sc = x[4usize..6usize]
        if lb.gibbs[LgCtx](a, &rr, &lc, lg_logf, x[6usize..8usize], ns, sc, go, ga) != ok { ret 0.0f64 / 0.0f64 }
        let ix = usize(x[1usize])
        if ix < ns * 2usize { ret go[ix] }
        ret ga[ix - ns * 2usize]
    }
    if str.eq(k, "rej") || str.eq(k, "imp2") {
        // (seed, which, m, n, df, dmax or hidx, mean[2], var[4], x[m], nn[m], y[m]) rej: the number kept (which 0) or the sum of the kept first-coordinate values (1); imp2: est (0) or se (1)
        var rr: rng.Rng = zero
        rng.seed(&rr, i64(x[0usize]))
        let w = usize(x[1usize])
        let m = usize(x[2usize])
        let ns = usize(x[3usize])
        let mean = x[6usize..8usize]
        let vr = x[8usize..12usize]
        var lc = LgCtx{ x: x[12usize..12usize + m], n: x[12usize + m..12usize + 2usize * m], y: x[12usize + 2usize * m..12usize + 3usize * m] }
        if str.eq(k, "rej") {
            let (keep, ke) = mem.alloc[f64](a, ns * 2usize)
            if ke != ok { ret 0.0f64 / 0.0f64 }
            let cnt = lb.rejectsampling[LgCtx](a, &rr, &lc, lg_logf, mean, vr, x[4usize], x[5usize], ns, keep)
            if w == 0usize { ret f64(cnt) }
            var sm = 0.0f64
            var q = 0usize
            while q < cnt {
                sm += keep[q]
                q += 1usize
            }
            ret sm
        }
        let (o2, oe) = mem.alloc[f64](a, 2usize)
        if oe != ok { ret 0.0f64 / 0.0f64 }
        if lb.impsampling[LgCtx](a, &rr, &lc, lg_logf, mean, vr, x[4usize], ns, usize(x[5usize]), o2) != ok { ret 0.0f64 / 0.0f64 }
        ret o2[w]
    }

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
