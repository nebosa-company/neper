// e.algo.stat.margeff end to end against marginaleffects: Neper's own glm.fit (e.algo.stat.armglm) fits the data in each case, then margeff takes slopes, comparisons, predictions,
// hypotheses over the estimates and joint tests of that fit. tests/oracle/margeff2.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R margeff2`; the layout is at the top of scripts/r_oracle/groups/margeff2.R.

use e.algo.stat.margeff as mf
use e.algo.stat.armglm as ag
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// fl: 0 gaussian identity, 1 binomial logit, 2 poisson log, 3 binomial probit, 4 binomial cloglog, 6 poisson sqrt
fn fam_of(fl: usize) -> usize {
    if fl == 0usize { ret 0usize }
    if fl == 2usize || fl == 6usize { ret 2usize }
    ret 1usize
}

fn link_of(fl: usize) -> usize {
    if fl == 0usize { ret 0usize }
    if fl == 1usize { ret 3usize }
    if fl == 2usize { ret 1usize }
    if fl == 3usize { ret 4usize }
    if fl == 4usize { ret 6usize }
    ret 7usize
}

fn mfit(a: *mem.Arena, z: []const f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let model = usize(z[1usize])
    let coding = usize(z[2usize])
    let nf = usize(z[3usize])
    let fl = usize(z[4usize])
    let op = usize(z[5usize])
    let ga = usize(z[6usize])
    let gb = usize(z[7usize])
    let kind = usize(z[8usize])
    let which = usize(z[9usize])
    let y = z[10usize..10usize + n]
    let fcol = z[10usize + n..10usize + 2usize * n]
    let xcol = z[10usize + 2usize * n..10usize + 3usize * n]
    let wcol = z[10usize + 3usize * n..10usize + 4usize * n]
    let ext = 10usize + 4usize * n
    let pmax = 12usize
    let (xm, e1) = mem.alloc[f64](a, n * pmax)
    let (xr, e2) = mem.alloc[f64](a, n * pmax)
    let (xh, e3) = mem.alloc[f64](a, n * pmax)
    let (xl, e4) = mem.alloc[f64](a, n * pmax)
    let (fc, e5) = mem.alloc[f64](a, n)
    let (xc, e6) = mem.alloc[f64](a, n)
    let (mk, e7) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret nan }
    let p = mf.mm_design(model, coding, nf, fcol, xcol, wcol, n, xm)
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            xr[i * p + j] = xm[j * n + i]
            j += 1usize
        }
        i += 1usize
    }
    let (bh, e8) = mem.alloc[f64](a, p)
    let (cu, e9) = mem.alloc[f64](a, p * p)
    let (vm, e10) = mem.alloc[f64](a, p * p)
    let (inf, e11) = mem.alloc[f64](a, 8usize)
    let (jac, e12) = mem.alloc[f64](a, p)
    let (jacs, e13) = mem.alloc[f64](a, 4usize * p)
    if e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret nan }
    let nowt: []const f64 = z[0usize..0usize]
    let it = ag.glm_fit_gen(a, xr[0usize..n * p], y, n, p, fam_of(fl), link_of(fl), nowt, nowt, true, bh, cu, inf)
    if it == 0usize { ret nan }
    ag.vbeta_from(cu, inf[0usize], p, vm)
    var ml = fl
    if fl == 6usize { ml = 6usize }
    var o: [4]f64 = zero
    let x0 = xm[0usize..n * p]
    let nomask: []const f64 = z[0usize..0usize]
    if op == 0usize {
        var lo = xcol[0usize]
        var hi = xcol[0usize]
        i = 1usize
        while i < n {
            if xcol[i] < lo { lo = xcol[i] }
            if xcol[i] > hi { hi = xcol[i] }
            i += 1usize
        }
        let h = 1.0e-4f64 * (hi - lo)
        i = 0usize
        while i < n {
            xc[i] = xcol[i] + h / 2.0f64
            mk[i] = 0.0f64
            if ga > 0usize && usize(fcol[i]) == ga - 1usize { mk[i] = 1.0f64 }
            i += 1usize
        }
        let _ = mf.mm_design(model, coding, nf, fcol, xc, wcol, n, xh)
        i = 0usize
        while i < n {
            xc[i] = xcol[i] - h / 2.0f64
            i += 1usize
        }
        let _ = mf.mm_design(model, coding, nf, fcol, xc, wcol, n, xl)
        var msk = nomask
        if ga > 0usize { msk = mk }
        mf.glm_pair(a, ml, 0usize, xh[0usize..n * p], xl[0usize..n * p], bh, vm, n, p, msk, h, jac, o[0usize..2usize])
        ret o[which]
    }
    if op == 1usize {
        i = 0usize
        while i < n {
            fc[i] = f64(ga)
            i += 1usize
        }
        let _ = mf.mm_design(model, coding, nf, fc, xcol, wcol, n, xh)
        i = 0usize
        while i < n {
            fc[i] = f64(gb)
            i += 1usize
        }
        let _ = mf.mm_design(model, coding, nf, fc, xcol, wcol, n, xl)
        mf.glm_pair(a, ml, kind, xh[0usize..n * p], xl[0usize..n * p], bh, vm, n, p, nomask, 1.0f64, jac, o[0usize..2usize])
        ret o[which]
    }
    if op == 2usize {
        i = 0usize
        while i < n {
            mk[i] = 0.0f64
            if usize(fcol[i]) == ga { mk[i] = 1.0f64 }
            i += 1usize
        }
        mf.glm_pair(a, ml, 4usize, x0, x0, bh, vm, n, p, mk, 1.0f64, jac, o[0usize..2usize])
        ret o[which]
    }
    if op == 3usize {
        i = 0usize
        while i < n {
            xc[i] = xcol[i] + 1.0f64
            mk[i] = 0.0f64
            if usize(fcol[i]) == ga { mk[i] = 1.0f64 }
            i += 1usize
        }
        let _ = mf.mm_design(model, coding, nf, fcol, xc, wcol, n, xh)
        mf.glm_pair(a, ml, 0usize, xh[0usize..n * p], x0, bh, vm, n, p, mk, 1.0f64, jac, o[0usize..2usize])
        ret o[which]
    }
    if op == 8usize {
        let grp = z[ext]
        i = 0usize
        while i < n {
            fc[i] = f64(ga)
            mk[i] = 0.0f64
            var pos = 0.0f64
            if wcol[i] > 0.0f64 { pos = 1.0f64 }
            if pos == grp { mk[i] = 1.0f64 }
            i += 1usize
        }
        let _ = mf.mm_design(model, coding, nf, fc, xcol, wcol, n, xh)
        i = 0usize
        while i < n {
            fc[i] = 0.0f64
            i += 1usize
        }
        let _ = mf.mm_design(model, coding, nf, fc, xcol, wcol, n, xl)
        mf.glm_pair(a, ml, kind, xh[0usize..n * p], xl[0usize..n * p], bh, vm, n, p, mk, 1.0f64, jac, o[0usize..2usize])
        ret o[which]
    }
    if op == 7usize {
        let q = nf - 1usize
        var fs = 1usize
        if model == 3usize { fs = 3usize }
        if model == 4usize { fs = 4usize }
        var rr: [64]f64 = zero
        var r0: [8]f64 = zero
        var k = 0usize
        while k < q {
            rr[k * p + fs + k] = 1.0f64
            k += 1usize
        }
        var jo: [5]f64 = zero
        mf.lin_joint(a, bh, vm, rr[0usize..q * p], r0[0usize..q], p, q, inf[4usize], jo[0usize..5usize])
        if which == 0usize { ret jo[3usize] }
        if which == 1usize { ret jo[4usize] }
        if which == 2usize { ret jo[0usize] }
        ret jo[2usize]
    }
    // ops 4, 5, 6: hypotheses over the by-group estimates (4, 6 average predictions, 5 average slopes of x)
    var est: [4]f64 = zero
    var lo2 = xcol[0usize]
    var hi2 = xcol[0usize]
    i = 1usize
    while i < n {
        if xcol[i] < lo2 { lo2 = xcol[i] }
        if xcol[i] > hi2 { hi2 = xcol[i] }
        i += 1usize
    }
    let h2 = 1.0e-4f64 * (hi2 - lo2)
    i = 0usize
    while i < n {
        xc[i] = xcol[i] + h2 / 2.0f64
        i += 1usize
    }
    let _ = mf.mm_design(model, coding, nf, fcol, xc, wcol, n, xh)
    i = 0usize
    while i < n {
        xc[i] = xcol[i] - h2 / 2.0f64
        i += 1usize
    }
    let _ = mf.mm_design(model, coding, nf, fcol, xc, wcol, n, xl)
    var g = 0usize
    while g < nf {
        i = 0usize
        while i < n {
            mk[i] = 0.0f64
            if usize(fcol[i]) == g { mk[i] = 1.0f64 }
            i += 1usize
        }
        if op == 5usize {
            mf.glm_pair(a, ml, 0usize, xh[0usize..n * p], xl[0usize..n * p], bh, vm, n, p, mk, h2, jac, o[0usize..2usize])
        } else {
            mf.glm_pair(a, ml, 4usize, x0, x0, bh, vm, n, p, mk, 1.0f64, jac, o[0usize..2usize])
        }
        est[g] = o[0usize]
        var k = 0usize
        while k < p {
            jacs[g * p + k] = jac[k]
            k += 1usize
        }
        g += 1usize
    }
    var rw: [4]f64 = zero
    var qv = 0.0f64
    if op == 6usize {
        var s = 0usize
        if ga == 1usize { s = nf + 1usize }
        var k = 0usize
        while k < nf {
            rw[k] = z[ext + s + k]
            k += 1usize
        }
        qv = z[ext + s + nf]
    } else {
        if !mf.hyp_weights(kind, nf, ga, rw[0usize..4usize]) { ret nan }
    }
    var oh: [4]f64 = zero
    mf.hyp_est(est[0usize..4usize], jacs, rw[0usize..4usize], qv, vm, p, nf, oh[0usize..4usize])
    ret oh[which]
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "mfit") { ret mfit(a, c.args) }
    ret 0.0f64 / 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/margeff2.json")
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
                var head = *c
                head.args = c.args[0usize..10usize]
                let _ = io.print(oracle.describe(a, &head, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
