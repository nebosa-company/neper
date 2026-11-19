// e.algo.stat.agricolae grouping letters and the Kruskal post-hoc against agricolae. tests/oracle/agricolae_groups.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R agricolae_groups`; the layout is at the top of scripts/r_oracle/groups/agricolae_groups.R.

use e.algo.stat.agricolae as ag
use e.algo.rand.r as rr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let k = usize(x[2usize])
    if kind == 6usize {
        let (sr, es) = mem.alloc[f64](a, k)
        if es != ok { os.exit(7) }
        let fr = ag.friedman(a, x[3usize..3usize + n * k], n, k, sr)
        if str.eq(c.name, "fgm") || str.eq(c.name, "fgo") {
            let (pvf, q1) = mem.alloc[f64](a, k * k)
            let (qo, q2) = mem.alloc[usize](a, k)
            let (qm, q3) = mem.alloc[u64](a, k)
            if q1 != ok || q2 != ok || q3 != ok { os.exit(25) }
            var u = 0usize
            while u < k * k {
                pvf[u] = 1.0f64
                u += 1usize
            }
            u = 0usize
            while u < k {
                var v = u + 1usize
                while v < k {
                    let (dd0, pp0, lo0, hi0) = ag.friedman_pair(fr, sr, n, u, v, 0.05f64)
                    pvf[u * k + v] = pp0
                    pvf[v * k + u] = pp0
                    v += 1usize
                }
                u += 1usize
            }
            ag.group_letters(sr, pvf, k, 0.05f64, qo, qm)
            let gi = usize(x[3usize + n * k])
            if str.eq(c.name, "fgo") { ret f64(qo[gi] + 1usize) }
            ret f64(qm[gi])
        }
        if str.eq(c.name, "fc") { ret fr.chisq }
        if str.eq(c.name, "fp") { ret fr.pchisq }
        if str.eq(c.name, "ff") { ret fr.f }
        if str.eq(c.name, "fpf") { ret fr.pf }
        var tot = 0.0f64
        var pos = 1usize
        var pp = 0usize
        while pp < k {
            var qq = pp + 1usize
            while qq < k {
                let (d, pv, lo, hi) = ag.friedman_pair(fr, sr, n, pp, qq, 0.05f64)
                var v = d
                if str.eq(c.name, "fq") { v = pv }
                if str.eq(c.name, "fl") { v = lo }
                if str.eq(c.name, "fu") { v = hi }
                tot += v * f64(pos)
                pos += 1usize
                qq += 1usize
            }
            pp += 1usize
        }
        ret tot
    }
    if kind == 17usize {
        var rg5: rr.Rng = zero
        if x[2usize] > 0.5f64 { rr.seed_super(&rg5, i64(x[1usize])) } else { rr.seed(&rg5, i64(x[1usize])) }
        let antr = usize(x[3usize])
        let ak = usize(x[4usize])
        let ar = usize(x[5usize])
        let (ao, h7) = mem.alloc[usize](a, ar * antr)
        if h7 != ok { os.exit(23) }
        let ea = ag.design_alpha(a, &rg5, antr, ak, ar, ao)
        if ea != ok { os.exit(24) }
        ret f64(ao[usize(x[6usize])])
    }
    if kind == 16usize {
        var rg4: rr.Rng = zero
        if x[2usize] > 0.5f64 { rr.seed_super(&rg4, i64(x[1usize])) } else { rr.seed(&rg4, i64(x[1usize])) }
        let lk = usize(x[3usize])
        let (lo, h6) = mem.alloc[usize](a, 3usize * lk * lk)
        if h6 != ok { os.exit(21) }
        let el2 = ag.design_lattice(a, &rg4, lk, usize(x[4usize]), lo)
        if el2 != ok { os.exit(22) }
        ret f64(lo[usize(x[5usize])])
    }
    if kind == 15usize {
        var rg3: rr.Rng = zero
        if x[2usize] > 0.5f64 { rr.seed_super(&rg3, i64(x[1usize])) } else { rr.seed(&rg3, i64(x[1usize])) }
        let bv = usize(x[3usize])
        let bk = usize(x[4usize])
        let brep = ag.bib_r(bv, bk, 20usize)
        let (bo, h5) = mem.alloc[usize](a, bv * brep)
        if h5 != ok { os.exit(19) }
        let eb2 = ag.design_bib(a, &rg3, bv, bk, brep, bo)
        if eb2 != ok { os.exit(20) }
        ret f64(bo[usize(x[5usize])])
    }
    if kind >= 12usize && kind <= 14usize {
        var rng2: rr.Rng = zero
        if x[2usize] > 0.5f64 { rr.seed_super(&rng2, i64(x[1usize])) } else { rr.seed(&rng2, i64(x[1usize])) }
        if kind == 12usize {
            let r2 = usize(x[3usize])
            let (lo, h1) = mem.alloc[usize](a, r2 * r2)
            if h1 != ok { os.exit(15) }
            let el = ag.design_lsd(a, &rng2, r2, x[4usize] > 0.5f64, lo)
            if el != ok { os.exit(16) }
            ret f64(lo[usize(x[5usize])])
        }
        var n1 = usize(x[3usize])
        var blocks = 0usize
        var n2 = 0usize
        var fst = false
        var pidx = 0usize
        var applied = 0usize
        if kind == 13usize {
            blocks = usize(x[4usize])
            n2 = usize(x[5usize])
            fst = x[6usize] > 0.5f64
            pidx = usize(x[7usize])
        } else {
            applied = 1usize
            blocks = n1
            n2 = usize(x[4usize])
            fst = x[5usize] > 0.5f64
            pidx = usize(x[6usize])
        }
        let nplot = n1 * blocks
        let (plan, h2) = mem.alloc[usize](a, nplot)
        let (sub, h3) = mem.alloc[usize](a, nplot * n2)
        if h2 != ok || h3 != ok { os.exit(17) }
        let es = ag.design_split(a, &rng2, applied, n1, blocks, n2, fst, plan, sub)
        if es != ok { os.exit(18) }
        if str.eq(c.name, "s1") || str.eq(c.name, "t1") { ret f64(plan[pidx / n2]) }
        ret f64(sub[pidx])
    }
    if kind >= 8usize && kind <= 11usize {
        var rng: rr.Rng = zero
        if kind >= 10usize { rr.seed_super(&rng, i64(x[1usize])) } else { rr.seed(&rng, i64(x[1usize])) }
        if kind == 8usize || kind == 10usize {
            // (8, seed, t, idx, reps...)
            let tn = k
            let didx = usize(x[3usize])
            let (reps, g1) = mem.alloc[usize](a, tn)
            if g1 != ok { os.exit(10) }
            var total = 0usize
            var ri = 0usize
            while ri < tn {
                reps[ri] = usize(x[4usize + ri])
                total += reps[ri]
                ri += 1usize
            }
            let (tr, g2) = mem.alloc[usize](a, total)
            let (rp, g3) = mem.alloc[usize](a, total)
            if g2 != ok || g3 != ok { os.exit(11) }
            let ed = ag.design_crd(a, &rng, reps, tr, rp)
            if ed != ok { os.exit(12) }
            if str.eq(c.name, "dt") || str.eq(c.name, "dst") { ret f64(tr[didx]) }
            ret f64(rp[didx])
        }
        // (9, seed, t, blocks, first, idx)
        let blocks = usize(x[3usize])
        let first = x[4usize] > 0.5f64
        let pidx = usize(x[5usize])
        let (bo, g4) = mem.alloc[usize](a, k * blocks)
        if g4 != ok { os.exit(13) }
        let eb = ag.design_rcbd(a, &rng, k, blocks, first, bo)
        if eb != ok { os.exit(14) }
        ret f64(bo[pidx])
    }
    if kind == 7usize {
        let wy = x[3usize..3usize + n]
        let (wg, f1) = mem.alloc[usize](a, n)
        let (wmn, f2) = mem.alloc[f64](a, k)
        let (wsz, f3) = mem.alloc[f64](a, k)
        if f1 != ok || f2 != ok || f3 != ok { os.exit(8) }
        var wi = 0usize
        while wi < n {
            wg[wi] = usize(x[3usize + n + wi])
            wi += 1usize
        }
        let ww = ag.one_way(wy, wg, k, wmn, wsz)
        let fc = ag.waller_fc(ww, wy, wmn, wsz)
        let tw = ag.waller(a, 100.0f64, f64(k) - 1.0f64, ww.df, fc)
        if str.eq(c.name, "wt") { ret tw }
        if str.eq(c.name, "wf") { ret fc }
        var tot = 0.0f64
        var pos = 1usize
        var p1 = 0usize
        while p1 < k {
            var q1 = p1 + 1usize
            while q1 < k {
                tot += ag.waller_msd(ww, tw, wsz, p1, q1) * f64(pos)
                pos += 1usize
                q1 += 1usize
            }
            p1 += 1usize
        }
        if str.eq(c.name, "wm") { ret tot }
        let (wp, f4) = mem.alloc[f64](a, k * k)
        let (wq, f5) = mem.alloc[usize](a, k)
        let (wk, f6) = mem.alloc[u64](a, k)
        if f4 != ok || f5 != ok || f6 != ok { os.exit(9) }
        var u = 0usize
        while u < k {
            var v = 0usize
            while v < k {
                wp[u * k + v] = 1.0f64
                if u != v {
                    var d = wmn[u] - wmn[v]
                    if d < 0.0f64 { d = 0.0f64 - d }
                    if d > ag.waller_msd(ww, tw, wsz, u, v) { wp[u * k + v] = 0.0f64 }
                }
                v += 1usize
            }
            u += 1usize
        }
        ag.group_letters(wmn, wp, k, 0.0f64, wq, wk)
        let widx = usize(x[3usize + 2usize * n])
        if str.eq(c.name, "wo") { ret f64(wq[widx] + 1usize) }
        ret f64(wk[widx])
    }
    let y = x[3usize..3usize + n]
    let (grp, e1) = mem.alloc[usize](a, n)
    let (mean, e2) = mem.alloc[f64](a, k)
    let (size, e3) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        grp[i] = usize(x[3usize + n + i])
        i += 1usize
    }
    if kind == 5usize {
        let kw = ag.kruskal(a, y, grp, k, mean, size)
        if str.eq(c.name, "kgm") || str.eq(c.name, "kgo") {
            let (pvk, q1) = mem.alloc[f64](a, k * k)
            let (qo, q2) = mem.alloc[usize](a, k)
            let (qm, q3) = mem.alloc[u64](a, k)
            if q1 != ok || q2 != ok || q3 != ok { os.exit(26) }
            var u = 0usize
            while u < k * k {
                pvk[u] = 1.0f64
                u += 1usize
            }
            u = 0usize
            while u < k {
                var v = u + 1usize
                while v < k {
                    let (dd0, pp0, lo0, hi0) = ag.kruskal_pair(kw, mean, size, u, v, 0.05f64)
                    pvk[u * k + v] = pp0
                    pvk[v * k + u] = pp0
                    v += 1usize
                }
                u += 1usize
            }
            ag.group_letters(mean, pvk, k, 0.05f64, qo, qm)
            let gi = usize(x[3usize + 2usize * n])
            if str.eq(c.name, "kgo") { ret f64(qo[gi] + 1usize) }
            ret f64(qm[gi])
        }
        if str.eq(c.name, "kh") { ret kw.h }
        if str.eq(c.name, "kp") { ret kw.pchisq }
        var s = 0.0f64
        var pos = 1usize
        var p = 0usize
        while p < k {
            var q = p + 1usize
            while q < k {
                let (d, pv, lo, hi) = ag.kruskal_pair(kw, mean, size, p, q, 0.05f64)
                var v = d
                if str.eq(c.name, "kpv") { v = pv }
                if str.eq(c.name, "kl") { v = lo }
                if str.eq(c.name, "ku") { v = hi }
                s += v * f64(pos)
                pos += 1usize
                q += 1usize
            }
            p += 1usize
        }
        ret s
    }
    let w = ag.one_way(y, grp, k, mean, size)
    let (pv, e4) = mem.alloc[f64](a, k * k)
    let (ord, e5) = mem.alloc[usize](a, k)
    let (mk, e6) = mem.alloc[u64](a, k)
    if e4 != ok || e5 != ok || e6 != ok { os.exit(6) }
    var p = 0usize
    while p < k {
        var q = 0usize
        while q < k {
            pv[p * k + q] = 1.0f64
            q += 1usize
        }
        p += 1usize
    }
    p = 0usize
    while p < k {
        var q = p + 1usize
        while q < k {
            let (d, pr, lo, hi) = ag.pairwise(w, mean, size, p, q, kind, 0.05f64)
            // the package rounds every p value to four decimals before the letters are assigned
            let rp = ag.round4(pr)
            pv[p * k + q] = rp
            pv[q * k + p] = rp
            q += 1usize
        }
        p += 1usize
    }
    ag.group_letters(mean, pv, k, 0.05f64, ord, mk)
    let idx = usize(x[3usize + 2usize * n])
    if str.eq(c.name, "gt") { ret f64(ord[idx] + 1usize) }
    ret f64(mk[idx])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/agricolae_groups.json")
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
