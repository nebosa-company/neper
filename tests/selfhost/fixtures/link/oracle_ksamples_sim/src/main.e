// e.algo.stat.ksamples_sim against kSamples: the simulated and exact p-values, the null distributions, normal scores and the combined tests.
// tests/oracle/ksamples_sim.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ksamples_sim`; the case layouts are at the top of
// scripts/r_oracle/groups/ksamples_sim.R. A simulated count is compared exactly: the stream is seeded the way set.seed does.

use e.algo.rand.r as rng
use e.algo.stat.ksamples_sim as sm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn pick(v: []const f64, i: usize) -> f64 {
    if i < v.len { ret v[i] }
    ret nan()
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var g: rng.Rng = zero
    let nm0 = c.name[0usize]
    let nm2 = c.name[2usize]
    if nm0 == 110u8 {
        let (v, e) = sm.kx_norm_order(a, usize(x[0usize]))
        if e != ok { os.exit(5) }
        ret v[usize(x[1usize]) - 1usize]
    }
    if nm0 == 97u8 && nm2 == 115u8 {
        // ads (method, seed, Nsim, part, idx, k, sizes..., data...)
        rng.seed(&g, i64(x[1usize]))
        let k = usize(x[5usize])
        let (sz, e0) = mem.alloc[usize](a, k)
        if e0 != ok { os.exit(5) }
        var tot = 0usize
        var i = 0usize
        while i < k {
            sz[i] = usize(x[6usize + i])
            tot += sz[i]
            i += 1usize
        }
        let part = usize(x[3usize])
        let (r, e) = sm.kx_ad_test(a, &g, x[6usize + k..6usize + k + tot], sz, usize(x[0usize]), true, usize(x[2usize]))
        if e != ok { os.exit(6) }
        if part == 0usize { ret sm.kx_signif(r.p1, 5i64) }
        if part == 1usize { ret sm.kx_signif(r.p2, 5i64) }
        if part == 2usize { ret pick(r.d1, usize(x[4usize]) - 1usize) }
        if part == 3usize { ret pick(r.d2, usize(x[4usize]) - 1usize) }
        if part == 4usize { ret f64(r.d1.len) }
        ret sm.kx_round(r.sig, 5i64)
    }
    if nm0 == 113u8 && nm2 == 115u8 {
        // qns (method, test, seed, Nsim, part, idx, k, sizes..., data...)
        rng.seed(&g, i64(x[2usize]))
        let k = usize(x[6usize])
        let (sz, e0) = mem.alloc[usize](a, k)
        if e0 != ok { os.exit(5) }
        var tot = 0usize
        var i = 0usize
        while i < k {
            sz[i] = usize(x[7usize + i])
            tot += sz[i]
            i += 1usize
        }
        let (r, e) = sm.kx_qn_test(a, &g, x[7usize + k..7usize + k + tot], sz, usize(x[1usize]), usize(x[0usize]), true, usize(x[3usize]))
        if e != ok { os.exit(6) }
        let part = usize(x[4usize])
        if part == 0usize { ret r.stat }
        if part == 1usize { ret r.asym }
        if part == 2usize { ret r.p }
        if part == 3usize { ret pick(r.dist, usize(x[5usize]) - 1usize) }
        if part == 4usize { ret f64(r.dist.len) }
        ret f64(r.nties)
    }
    if nm0 == 99u8 && nm2 == 115u8 {
        // c2s (method, seed, Nsim, part, idx, tab0, t, A..., B...)
        rng.seed(&g, i64(x[1usize]))
        let t = usize(x[6usize])
        let (r, e) = sm.kx_contingency(a, &g, x[7usize..7usize + t], x[7usize + t..7usize + 2usize * t], usize(x[0usize]), true, x[5usize] != 0.0f64, usize(x[2usize]))
        if e != ok { os.exit(6) }
        let part = usize(x[3usize])
        if part == 0usize { ret r.kw }
        if part == 1usize { ret r.asym }
        if part == 2usize { ret r.p }
        if part == 3usize { ret pick(r.vals, usize(x[4usize]) - 1usize) }
        if part == 4usize { ret pick(r.probs, usize(x[4usize]) - 1usize) }
        ret f64(r.vals.len)
    }
    if nm0 == 97u8 && nm2 == 99u8 {
        // adc (method, seed, Nsim, part, idx, M, k per set..., sizes..., data...)
        rng.seed(&g, i64(x[1usize]))
        let mm = usize(x[5usize])
        let (setk, e0) = mem.alloc[usize](a, mm)
        if e0 != ok { os.exit(5) }
        var ntot = 0usize
        var i = 0usize
        while i < mm {
            setk[i] = usize(x[6usize + i])
            ntot += setk[i]
            i += 1usize
        }
        let (sz, e1) = mem.alloc[usize](a, ntot)
        if e1 != ok { os.exit(5) }
        var tot = 0usize
        i = 0usize
        while i < ntot {
            sz[i] = usize(x[6usize + mm + i])
            tot += sz[i]
            i += 1usize
        }
        let at = 6usize + mm + ntot
        let (r, e) = sm.kx_ad_combined(a, &g, x[at..at + tot], sz, setk, usize(x[0usize]), usize(x[2usize]))
        if e != ok { os.exit(6) }
        let part = usize(x[3usize])
        if part == 0usize { ret r.ad1 }
        if part == 1usize { ret r.t1 }
        if part == 2usize { ret r.a1 }
        if part == 3usize { ret r.p1 }
        if part == 4usize { ret r.ad2 }
        if part == 5usize { ret r.t2 }
        if part == 6usize { ret r.a2 }
        if part == 7usize { ret r.p2 }
        if part == 8usize { ret r.sig }
        if part == 9usize { ret r.mu }
        if part == 10usize { ret pick(r.d1, usize(x[4usize]) - 1usize) }
        ret f64(r.d1.len)
    }
    if nm0 == 113u8 && nm2 == 99u8 {
        // qnc (method, test, seed, Nsim, part, idx, M, k per set..., sizes..., data...)
        rng.seed(&g, i64(x[2usize]))
        let mm = usize(x[6usize])
        let (setk, e0) = mem.alloc[usize](a, mm)
        if e0 != ok { os.exit(5) }
        var ntot = 0usize
        var i = 0usize
        while i < mm {
            setk[i] = usize(x[7usize + i])
            ntot += setk[i]
            i += 1usize
        }
        let (sz, e1) = mem.alloc[usize](a, ntot)
        if e1 != ok { os.exit(5) }
        var tot = 0usize
        i = 0usize
        while i < ntot {
            sz[i] = usize(x[7usize + mm + i])
            tot += sz[i]
            i += 1usize
        }
        let at = 7usize + mm + ntot
        let (r, e) = sm.kx_qn_combined(a, &g, x[at..at + tot], sz, setk, usize(x[1usize]), usize(x[0usize]), usize(x[3usize]))
        if e != ok { os.exit(6) }
        let part = usize(x[4usize])
        if part == 0usize { ret r.stat }
        if part == 1usize { ret r.asym }
        if part == 2usize { ret r.p }
        if part == 3usize { ret pick(r.dist, usize(x[5usize]) - 1usize) }
        ret f64(r.dist.len)
    }
    // c2c (method, seed, Nsim, part, idx, M, t per set..., A and B per set...)
    rng.seed(&g, i64(x[1usize]))
    let mm = usize(x[5usize])
    let (tv, e0) = mem.alloc[usize](a, mm)
    let (av, e1) = mem.alloc[f64](a, 64usize)
    let (bv, e2) = mem.alloc[f64](a, 64usize)
    if e0 != ok || e1 != ok || e2 != ok { os.exit(5) }
    var at = 6usize + mm
    var na = 0usize
    var i = 0usize
    while i < mm {
        tv[i] = usize(x[6usize + i])
        var q = 0usize
        while q < tv[i] {
            av[na + q] = x[at + q]
            bv[na + q] = x[at + tv[i] + q]
            q += 1usize
        }
        at += 2usize * tv[i]
        na += tv[i]
        i += 1usize
    }
    let (r, e) = sm.kx_c2_combined(a, &g, av[0usize..na], bv[0usize..na], tv, usize(x[0usize]), true, usize(x[2usize]))
    if e != ok { os.exit(6) }
    let part = usize(x[3usize])
    if part == 0usize { ret r.kw }
    if part == 1usize { ret r.asym }
    if part == 2usize { ret r.p }
    if part == 3usize { ret pick(r.vals, usize(x[4usize]) - 1usize) }
    if part == 4usize { ret pick(r.probs, usize(x[4usize]) - 1usize) }
    ret f64(r.vals.len)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ksamples_sim.json")
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
