// e.algo.stat.laeken_ext against laeken. tests/oracle/laeken_ext.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R laeken_ext`; the layout of every case is at the top of scripts/r_oracle/groups/laeken_ext.R.

use e.algo.rand.r as rng
use e.algo.stat.laeken_ext as lx
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn wsum(v: []const f64, weighted: bool) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        if weighted { s += v[i] * f64(i + 1usize) } else { s += v[i] }
        i += 1usize
    }
    ret s
}

fn do_calib(a: *mem.Arena, z: []const f64) -> f64 {
    let m = usize(z[0usize])
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let q = usize(z[5usize])
    let x = z[6usize..6usize + n * p]
    let d = z[6usize + n * p..6usize + n * p + n]
    let tot = z[6usize + n * p + n..6usize + n * p + n + p]
    let (g, e1) = mem.alloc[f64](a, n)
    let (qq, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret nan() }
    var i = 0usize
    while i < n {
        qq[i] = 1.0f64
        i += 1usize
    }
    if !lx.calib_weights(a, x, n, p, d, tot, qq, m, z[3usize], z[4usize], 500usize, 1.0e-6f64, g) { ret nan() }
    if q == 0usize { ret wsum(g, false) }
    if q == 1usize { ret wsum(g, true) }
    var mn = g[0usize]
    var mx = g[0usize]
    i = 1usize
    while i < n {
        if g[i] < mn { mn = g[i] }
        if g[i] > mx { mx = g[i] }
        i += 1usize
    }
    if q == 2usize { ret mn }
    ret mx
}

fn do_boot(a: *mem.Arena, z: []const f64) -> f64 {
    let kind = usize(z[0usize])
    let pp = z[1usize]
    let n = usize(z[2usize])
    let nlev = usize(z[3usize])
    let calib = z[4usize] != 0.0f64
    let nrep = usize(z[5usize])
    let ci = usize(z[6usize])
    let alpha = z[7usize]
    let seed = i64(z[8usize])
    let naux = usize(z[9usize])
    let hasd = z[10usize] != 0.0f64
    let hasc = z[11usize] != 0.0f64
    let q = usize(z[12usize])
    var at = 13usize
    let inc = z[at..at + n]
    at += n
    let w = z[at..at + n]
    at += n
    let male = z[at..at + n]
    at += n
    let stratum = z[at..at + n]
    at += n
    let design = z[at..at + n]
    at += n
    let cluster = z[at..at + n]
    at += n
    let aux = z[at..at + n * naux]
    at += n * naux
    let totals = z[at..at + naux]
    at += naux
    let levels = z[at..at + nlev]
    let ns = 1usize + nlev
    let (ov, e1) = mem.alloc[f64](a, ns)
    let (oc, e2) = mem.alloc[f64](a, 2usize * ns)
    if e1 != ok || e2 != ok { ret nan() }
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    var sp = lx.Spec { kind: kind, p: pp, nlev: nlev }
    var mm: []const f64 = zero
    if kind >= 4usize { mm = male }
    var ss: []const f64 = zero
    if nlev > 0usize { ss = stratum }
    var dd: []const f64 = zero
    if hasd { dd = design }
    var cc: []const f64 = zero
    if hasc { cc = cluster }
    if lx.boot_var(a, &rg, sp, inc, w, mm, ss, levels, dd, cc, aux, naux, totals, calib, 0usize, 0.0f64, 0.0f64, nrep, ci, alpha, ov, oc) != ok { ret nan() }
    if q < ns { ret ov[q] }
    ret oc[q - ns]
}

fn do_tail(a: *mem.Arena, z: []const f64) -> f64 {
    let method = usize(z[0usize])
    let usek = z[1usize] != 0.0f64
    let k = usize(z[2usize])
    let x0 = z[3usize]
    let n = usize(z[4usize])
    let hasw = z[5usize] != 0.0f64
    let alpha = z[6usize]
    let c1 = z[7usize]
    let c2 = z[8usize]
    let bias = z[9usize] != 0.0f64
    let q = usize(z[10usize])
    let x = z[11usize..11usize + n]
    var w: []const f64 = zero
    if hasw { w = z[11usize + n..11usize + 2usize * n] }
    let (tail, e1) = mem.alloc[usize](a, n)
    let (out, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret nan() }
    let (t, e) = lx.pareto_tail(a, x, usek, k, x0, method, w, alpha, c1, c2, bias, tail, out)
    if e != ok { ret nan() }
    if q == 0usize { ret t.theta }
    if q == 1usize { ret t.x0 }
    if q == 2usize { ret f64(t.k) }
    if q == 3usize { ret t.q }
    if q == 4usize { ret f64(t.nout) }
    var s = 0.0f64
    var i = 0usize
    if q == 5usize {
        while i < t.nout {
            s += f64(out[i])
            i += 1usize
        }
        ret s
    }
    while i < t.k {
        s += f64(tail[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "calib") { ret do_calib(a, z) }
    if str.eq(c.name, "boot") { ret do_boot(a, z) }
    if str.eq(c.name, "ptail") { ret do_tail(a, z) }
    if str.eq(c.name, "gpg") {
        let n = usize(z[1usize])
        ret lx.gender_gap(a, z[2usize..2usize + n], z[2usize + 2usize * n..2usize + 3usize * n], z[2usize + n..2usize + 2usize * n], usize(z[0usize]))
    }
    if str.eq(c.name, "wrate") {
        let n = usize(z[0usize])
        ret lx.weighted_rate(z[2usize..2usize + n], z[2usize + n..2usize + 2usize * n], z[1usize])
    }
    if str.eq(c.name, "eqss") {
        let n = usize(z[0usize])
        let (o, e) = mem.alloc[f64](a, n)
        if e != ok { ret nan() }
        lx.eq_ss(z[2usize..2usize + n], z[2usize + n..2usize + 2usize * n], o)
        ret o[usize(z[1usize])]
    }
    if str.eq(c.name, "eqinc") {
        let n = usize(z[0usize])
        let nhp = usize(z[2usize])
        let nhm = usize(z[3usize])
        let npp = usize(z[4usize])
        let npm = usize(z[5usize])
        var at = 6usize
        let hid = z[at..at + n]
        at += n
        let hp = z[at..at + n * nhp]
        at += n * nhp
        let hm = z[at..at + n * nhm]
        at += n * nhm
        let pp = z[at..at + n * npp]
        at += n * npp
        let pm = z[at..at + n * npm]
        at += n * npm
        let es = z[at..at + n]
        let (o, e) = mem.alloc[f64](a, n)
        if e != ok { ret nan() }
        if lx.eq_inc(a, hid, hp, nhp, hm, nhm, pp, npp, pm, npm, es, o) != ok { ret nan() }
        ret o[usize(z[1usize])]
    }
    if str.eq(c.name, "pscale") {
        let n = usize(z[3usize])
        var w: []const f64 = zero
        if z[4usize] != 0.0f64 { w = z[6usize + n..6usize + 2usize * n] }
        let (x0, k) = lx.pareto_scale(a, z[6usize..6usize + n], w, usize(z[0usize]), z[1usize], z[2usize])
        if usize(z[5usize]) == 0usize { ret x0 }
        ret f64(k)
    }
    if str.eq(c.name, "fitp") {
        let n = usize(z[5usize])
        let (o, e) = mem.alloc[f64](a, n)
        if e != ok { ret nan() }
        var rg: rng.Rng = zero
        rng.seed(&rg, i64(z[0usize]))
        var c1 = 0.0f64
        var c2 = 0.0f64
        let method = usize(z[1usize])
        if method == 6usize {
            c1 = 0.05f64
            c2 = 0.05f64
        }
        if method == 7usize { c1 = 2.5f64 }
        if method == 8usize {
            c1 = 0.005f64
            c2 = 0.005f64
        }
        if lx.fit_pareto(a, &rg, z[7usize..7usize + n], z[2usize] != 0.0f64, usize(z[3usize]), z[4usize], method, z[7usize..7usize + 0usize], c1, c2, true, o) != ok { ret nan() }
        ret wsum(o, usize(z[6usize]) == 1usize)
    }
    if str.eq(c.name, "repl") {
        let n = usize(z[4usize])
        let x = z[6usize..6usize + n]
        let (tail, e1) = mem.alloc[usize](a, n)
        let (out, e2) = mem.alloc[usize](a, n)
        let (o, e3) = mem.alloc[f64](a, n)
        if e1 != ok || e2 != ok || e3 != ok { ret nan() }
        let (t, e) = lx.pareto_tail(a, x, true, usize(z[2usize]), 0.0f64, 2usize, z[6usize..6usize], z[3usize], 0.0f64, 0.0f64, true, tail, out)
        if e != ok { ret nan() }
        var rg: rng.Rng = zero
        rng.seed(&rg, i64(z[0usize]))
        let mode = usize(z[1usize])
        if mode == 0usize { if lx.replace_tail(a, &rg, x, tail[0usize..t.k], t.x0, t.theta, o) != ok { ret nan() } }
        if mode == 1usize { if lx.replace_tail(a, &rg, x, out[0usize..t.nout], t.x0, t.theta, o) != ok { ret nan() } }
        if mode == 2usize { lx.shrink_out(x, out[0usize..t.nout], t.q, o) }
        ret wsum(o, usize(z[5usize]) == 1usize)
    }
    if str.eq(c.name, "rw") {
        let hasw = z[0usize] != 0.0f64
        let method = usize(z[1usize])
        let n = usize(z[2usize])
        let p = usize(z[3usize])
        let x = z[7usize..7usize + n]
        var w: []const f64 = zero
        if hasw { w = z[7usize + n..7usize + 2usize * n] }
        let xm = z[7usize + 2usize * n..7usize + 2usize * n + n * p]
        let (tail, e1) = mem.alloc[usize](a, n)
        let (out, e2) = mem.alloc[usize](a, n)
        let (o, e3) = mem.alloc[f64](a, n)
        if e1 != ok || e2 != ok || e3 != ok { ret nan() }
        let (t, e) = lx.pareto_tail(a, x, true, usize(z[4usize]), 0.0f64, 0usize, w, z[5usize], 0.0f64, 0.0f64, true, tail, out)
        if e != ok { ret nan() }
        if !lx.reweight_out(a, out[0usize..t.nout], n, xm, p, w, method, 0.2f64, 5.0f64, o) { ret nan() }
        ret wsum(o, usize(z[6usize]) == 1usize)
    }
    if str.eq(c.name, "amse") {
        let n = usize(z[0usize])
        var rr: [5]f64 = zero
        if lx.min_amse(a, z[3usize..3usize + n], z[1usize] != 0.0f64, n / 100usize, n - 2usize, n - 1usize, 0usize, 100usize, rr[0usize..5usize]) != ok { ret nan() }
        ret rr[usize(z[2usize])]
    }
    if str.eq(c.name, "mexp") {
        let n = usize(z[0usize])
        let np = usize(z[2usize])
        var w: []const f64 = zero
        if z[1usize] != 0.0f64 { w = z[4usize + n..4usize + 2usize * n] }
        let (mu, e1) = mem.alloc[f64](a, n)
        let (me, e2) = mem.alloc[f64](a, n)
        if e1 != ok || e2 != ok { ret nan() }
        let cnt = lx.mean_excess(a, z[4usize..4usize + n], w, z[4usize + 2usize * n..4usize + 2usize * n + np], mu, me)
        let q = usize(z[3usize])
        if q == 0usize { ret wsum(mu[0usize..cnt], false) }
        if q == 1usize { ret wsum(me[0usize..cnt], false) }
        ret f64(cnt)
    }
    if str.eq(c.name, "pqy") {
        let n = usize(z[0usize])
        var w: []const f64 = zero
        if z[1usize] != 0.0f64 { w = z[3usize + n..3usize + 2usize * n] }
        let (y, e) = mem.alloc[f64](a, n)
        if e != ok { ret nan() }
        if lx.pareto_q_y(a, z[3usize..3usize + n], w, y) != ok { ret nan() }
        ret wsum(y, usize(z[2usize]) == 1usize)
    }
    ret nan()
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/laeken_ext.json")
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
