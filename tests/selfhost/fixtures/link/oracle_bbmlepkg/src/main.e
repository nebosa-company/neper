// e.algo.stat.bbmlepkg against bbmle: mle2, profile, confint (spline and quad) and AICtab / BICtab / AICctab. tests/oracle/bbmlepkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R bbmlepkg`; the case layouts are at the top of scripts/r_oracle/groups/bbmlepkg.R.

use e.algo.stat.bbmlepkg as bb
use e.algo.stat.maxlikpkg as ml
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// a fit context for model `model` over the data x, y (the latter may be empty for models that do not use it)
fn setup(a: *mem.Arena, model: usize, x: []const f64, y: []const f64, mc: *ml.MCtx, fc: *bb.FitCtx) -> bool {
    let p = ml.npar(model)
    let n = x.len
    let (gm, e1) = mem.alloc[f64](a, n * p)
    let (fx, e2) = mem.alloc[f64](a, p)
    let (fv, e3) = mem.alloc[f64](a, p)
    let (fu, e4) = mem.alloc[f64](a, p)
    let (xs, e5) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret false }
    var j = 0usize
    while j < p {
        fx[j] = 0.0f64
        j += 1usize
    }
    mc.model = model
    mc.n = n
    mc.p = p
    mc.x = x
    mc.y = y
    mc.gm = gm
    mc.fcnt = 0usize
    mc.gcnt = 0usize
    fc.m = mc
    fc.p = p
    fc.fixed = fx
    fc.fval = fv
    fc.full = fu
    fc.xs = xs
    fc.bad = false
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/bbmlepkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        var got = 0.0f64 / 0.0f64
        var mc = ml.MCtx{ model: 0usize, n: 0usize, p: 0usize, x: x, y: x, gm: x, fcnt: 0usize, gcnt: 0usize }
        var fc = bb.FitCtx{ m: &mc, p: 0usize, fixed: x, fval: x, full: x, xs: x, bad: false }
        if str.eq(c.name, "bb_ic") {
            let kk = usize(x[1usize])
            let kind = usize(x[2usize])
            let n = usize(x[3usize])
            let xd = x[9usize..9usize + n]
            var ll: [3]f64 = zero
            var df: [3]f64 = zero
            var okk = true
            var mi = 0usize
            while mi < 3usize {
                var model = 0usize
                if mi > 0usize { model = 3usize }
                if !setup(a, model, xd, xd, &mc, &fc) { os.exit(5) }
                var sp: [2]f64 = zero
                var co: [2]f64 = zero
                var se: [2]f64 = zero
                if mi == 0usize {
                    sp[0usize] = x[4usize]
                    sp[1usize] = x[5usize]
                } else if mi == 1usize {
                    sp[0usize] = x[6usize]
                    sp[1usize] = x[7usize]
                }
                if mi < 2usize {
                    let mn = bb.mle2(a, &fc, sp[0usize..2usize], co[0usize..2usize], se[0usize..2usize])
                    if mn != mn { okk = false }
                    ll[mi] = 0.0f64 - mn
                    df[mi] = 2.0f64
                } else {
                    fc.fixed[0usize] = 1.0f64
                    fc.fval[0usize] = 1.0f64
                    co[0usize] = x[8usize]
                    let mn = bb.fit(a, &fc, co[0usize..1usize])
                    if fc.bad { okk = false }
                    ll[mi] = 0.0f64 - mn
                    df[mi] = 1.0f64
                }
                mi += 1usize
            }
            var order: [3]usize = zero
            var d: [3]f64 = zero
            var w: [3]f64 = zero
            bb.ictab(ll[0usize..3usize], df[0usize..3usize], 3usize, f64(n), kind, order[0usize..3usize], d[0usize..3usize], w[0usize..3usize])
            let what = usize(x[0usize])
            if okk {
                if what == 0usize { got = f64(order[kk] + 1usize) }
                if what == 1usize { got = d[kk] }
                if what == 2usize { got = df[order[kk]] }
                if what == 3usize { got = w[kk] }
            }
        } else {
            // the other three: the data sit after the header, whose width differs
            var hdr = 4usize
            if str.eq(c.name, "bb_prof") { hdr = 6usize }
            if str.eq(c.name, "bb_ci") { hdr = 5usize }
            var mpos = 2usize
            if str.eq(c.name, "bb_prof") { mpos = 4usize }
            if str.eq(c.name, "bb_ci") { mpos = 3usize }
            let model = usize(x[mpos])
            let n = usize(x[mpos + 1usize])
            let p = ml.npar(model)
            let st0 = x[mpos + 2usize..mpos + 2usize + p]
            let xd = x[mpos + 2usize + p..mpos + 2usize + p + n]
            let yd = x[mpos + 2usize + p + n..mpos + 2usize + p + 2usize * n]
            let _ = hdr
            if !setup(a, model, xd, yd, &mc, &fc) { os.exit(5) }
            let (coef, e1) = mem.alloc[f64](a, p)
            let (se, e2) = mem.alloc[f64](a, p)
            if e1 != ok || e2 != ok { os.exit(5) }
            let mn = bb.mle2(a, &fc, st0, coef, se)
            let what = usize(x[0usize])
            if str.eq(c.name, "bb_mle2") {
                let j = usize(x[1usize])
                if what == 0usize { got = coef[j] }
                if what == 1usize { got = mn }
                if what == 2usize { got = se[j] }
            } else if str.eq(c.name, "bb_ci") && what == 1usize {
                let i = usize(x[1usize])
                var ci: [2]f64 = zero
                bb.confint_quad(coef[i], se[i], 0.95f64, ci[0usize..2usize])
                got = ci[usize(x[2usize])]
            } else {
                let i = usize(x[1usize])
                let (zs, e3) = mem.alloc[f64](a, 400usize)
                let (pv, e4) = mem.alloc[f64](a, 400usize * p)
                if e3 != ok || e4 != ok { os.exit(5) }
                let m = bb.profile(a, &fc, coef, se, mn, i, zs, pv)
                if str.eq(c.name, "bb_prof") {
                    if what == 0usize { got = f64(m) }
                    if what == 1usize { got = zs[usize(x[2usize])] }
                    if what == 2usize { got = pv[usize(x[2usize]) * p + usize(x[3usize])] }
                } else {
                    let (col, e5) = mem.alloc[f64](a, m)
                    if e5 != ok { os.exit(5) }
                    var k = 0usize
                    while k < m {
                        col[k] = pv[k * p + i]
                        k += 1usize
                    }
                    var ci: [2]f64 = zero
                    bb.confint_profile(a, zs[0usize..m], col, m, 0.95f64, ci[0usize..2usize])
                    got = ci[usize(x[2usize])]
                }
            }
        }
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
