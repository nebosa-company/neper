// e.algo.stat.randomforest against randomForest 4.7-1.2. tests/oracle/randomforest.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R randomforest`; the layout is at the top of scripts/r_oracle/groups/randomforest.R.

use e.algo.rand.r as rng
use e.algo.stat.randomforest as rf
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

const HEAD: usize = 28usize
const NOUT: usize = 28usize

// the sum of (position + 1) times the value, NaN skipped
fn cs(v: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        if v[i] == v[i] { s += f64(i + 1usize) * v[i] }
        i += 1usize
    }
    ret s
}

fn csi(v: []const i64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += f64(i + 1usize) * f64(v[i])
        i += 1usize
    }
    ret s
}

fn scaled(v: f64, sd: f64) -> f64 {
    if sd < 2.220446049250313e-16f64 { ret v }
    ret v / sd
}

fn forest(a: *mem.Arena, c: *const oracle.Case, out: []f64) -> err {
    let x = c.args
    let kind = usize(x[1usize])
    let n = usize(x[2usize])
    let p = usize(x[3usize])
    let nclass = usize(x[14usize])
    let ntest = usize(x[16usize])
    var o: rf.Opts = zero
    o.ntree = usize(x[4usize])
    o.mtry = usize(x[5usize])
    o.nodesize = usize(x[6usize])
    o.sampsize = usize(x[7usize])
    o.replace = x[8usize] != 0.0f64
    o.importance = x[9usize] != 0.0f64
    o.local_imp = x[10usize] != 0.0f64
    o.nperm = usize(x[11usize])
    o.proximity = x[12usize] != 0.0f64
    o.maxnodes = usize(x[13usize])
    o.use_classwt = x[19usize] != 0.0f64
    o.keep_inbag = x[21usize] != 0.0f64
    o.corr_bias = x[23usize] != 0.0f64
    o.oob_prox = x[24usize] != 0.0f64
    let testmode = usize(x[22usize])
    let npt = usize(x[20usize])
    let pv = usize(x[17usize])
    var g: rng.Rng = zero
    rng.seed(&g, i64(x[15usize]))
    let wt = x[HEAD..HEAD + nclass]
    let cutoff = x[HEAD + nclass..HEAD + 2usize * nclass]
    let base = HEAD + 2usize * nclass
    let yv = x[base..base + n]
    let xd = x[base + n..base + n + n * p]
    let xn = x[base + n + n * p..base + n + n * p + ntest * p]
    let ytv = x[base + n + n * p + ntest * p..base + n + n * p + ntest * p + ntest]
    var i = 0usize
    while i < NOUT {
        out[i] = 0.0f64
        i += 1usize
    }
    let (xpt, e1) = mem.alloc[f64](a, npt + 1usize)
    let (ypt, e2) = mem.alloc[f64](a, npt + 1usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var ts: rf.TestSet = zero
    let (tcl, e0) = mem.alloc[i64](a, ntest + 1usize)
    if e0 != ok { ret e0 }
    i = 0usize
    while i < ntest {
        if kind == 0usize { tcl[i] = i64(ytv[i]) }
        i += 1usize
    }
    ts.x = xn
    ts.cl = tcl
    ts.y = ytv
    if testmode > 0usize {
        ts.n = ntest
        ts.labels = testmode == 2usize
    }
    if kind == 0usize {
        let (cl, e3) = mem.alloc[i64](a, n)
        if e3 != ok { ret e3 }
        i = 0usize
        while i < n {
            cl[i] = i64(yv[i])
            i += 1usize
        }
        let (f, e4) = rf.rf_fit_class(a, &g, xd, cl, nclass, n, p, wt, cutoff, &o, &ts)
        if e4 != ok { ret e4 }
        let kc = nclass
        out[0usize] = f.err[(o.ntree - 1usize) * (kc + 1usize)]
        out[1usize] = cs(f.err, (kc + 1usize) * o.ntree)
        var s2 = 0.0f64
        var s3 = 0.0f64
        var s4 = 0.0f64
        i = 0usize
        while i < n {
            if f.oobn[i] > 0i64 {
                s2 += f64(i + 1usize) * f64(f.outcl[i])
                var j = 0usize
                while j < kc {
                    s3 += f64(i * kc + j + 1usize) * (f64(f.votes[i * kc + j]) / f64(f.oobn[i]))
                    j += 1usize
                }
            }
            s4 += f64(i + 1usize) * f64(f.oobn[i])
            i += 1usize
        }
        out[2usize] = s2
        out[3usize] = s3
        out[4usize] = s4
        if o.importance {
            out[5usize] = cs(f.cimp[kc * p..(kc + 1usize) * p], p)
            out[7usize] = cs(f.cimp[0usize..kc * p], kc * p)
            out[8usize] = cs(f.impsd, (kc + 1usize) * p)
            var s9 = 0.0f64
            var s10 = 0.0f64
            var m = 0usize
            while m < p {
                s9 += f64(m + 1usize) * scaled(f.cimp[kc * p + m], f.impsd[kc * p + m])
                m += 1usize
            }
            var col = 0usize
            while col <= kc {
                m = 0usize
                while m < p {
                    s10 += f64(col * p + m + 1usize) * scaled(f.cimp[col * p + m], f.impsd[col * p + m])
                    m += 1usize
                }
                col += 1usize
            }
            m = 0usize
            while m < p {
                s10 += f64((kc + 1usize) * p + m + 1usize) * f.cimp[(kc + 1usize) * p + m]
                m += 1usize
            }
            out[9usize] = s9
            out[10usize] = s10
        }
        out[6usize] = cs(f.cimp[(kc + 1usize) * p..(kc + 2usize) * p], p)
        if o.proximity { out[11usize] = cs(f.prox, n * n) }
        if o.local_imp { out[12usize] = cs(f.impmat, n * p) }
        if o.keep_inbag { out[17usize] = csi(f.inbag, n * o.ntree) }
        let (counts, e5) = mem.alloc[f64](a, ntest * kc + 1usize)
        let (jet, e6) = mem.alloc[i64](a, ntest + 1usize)
        if e5 != ok { ret e5 }
        if e6 != ok { ret e6 }
        let e7 = rf.rf_predict_class(a, &g, &f, xn, ntest, cutoff, counts, jet)
        if e7 != ok { ret e7 }
        out[13usize] = csi(jet, ntest)
        let e8 = rf.rf_predict_class(a, &g, &f, xn, ntest, cutoff, counts, jet)
        if e8 != ok { ret e8 }
        var s14 = 0.0f64
        i = 0usize
        while i < ntest * kc {
            s14 += f64(i + 1usize) * (counts[i] / f64(o.ntree))
            i += 1usize
        }
        out[14usize] = s14
        let e9 = rf.rf_predict_class(a, &g, &f, xn, ntest, cutoff, counts, jet)
        if e9 != ok { ret e9 }
        out[15usize] = cs(counts, ntest * kc)
        if npt > 0usize {
            let e10 = rf.rf_partial_class(a, &g, &f, xd, n, pv, usize(x[18usize]) - 1usize, npt, cutoff, xpt, ypt)
            if e10 != ok { ret e10 }
            out[16usize] = cs(ypt, npt)
            out[18usize] = cs(xpt, npt)
        }
        let (pxm, e11) = mem.alloc[f64](a, ntest * ntest + 1usize)
        let (nds, e12) = mem.alloc[i64](a, ntest * o.ntree + 1usize)
        let (alp, e13) = mem.alloc[i64](a, ntest * o.ntree + 1usize)
        if e11 != ok || e12 != ok || e13 != ok { ret mem.Exhausted }
        let e14 = rf.rf_predict_class_full(a, &g, &f, xn, ntest, cutoff, counts, jet, pxm, true, nds, true, alp, false)
        if e14 != ok { ret e14 }
        out[19usize] = cs(pxm, ntest * ntest)
        out[20usize] = csi(nds, ntest * o.ntree)
        let e15 = rf.rf_predict_class_full(a, &g, &f, xn, ntest, cutoff, counts, jet, pxm, false, nds, false, alp, true)
        if e15 != ok { ret e15 }
        out[21usize] = csi(alp, ntest * o.ntree)
        if testmode > 0usize {
            out[22usize] = csi(f.tcls, ntest)
            var s23 = 0.0f64
            i = 0usize
            while i < ntest * kc {
                s23 += f64(i + 1usize) * (f.tvotes[i] / f64(o.ntree))
                i += 1usize
            }
            out[23usize] = s23
            if testmode == 2usize { out[24usize] = cs(f.terr, (kc + 1usize) * o.ntree) }
            if o.proximity { out[25usize] = cs(f.tprox, ntest * (ntest + n)) }
        }
        ret ok
    }
    let (f, e3) = rf.rf_fit_reg(a, &g, xd, yv, n, p, &o, &ts)
    if e3 != ok { ret e3 }
    out[0usize] = f.err[o.ntree - 1usize]
    out[1usize] = cs(f.err, o.ntree)
    var s2 = 0.0f64
    var s3 = 0.0f64
    i = 0usize
    while i < n {
        if f.oobn[i] > 0i64 { s2 += f64(i + 1usize) * f.ypred[i] }
        s3 += f64(i + 1usize) * f64(f.oobn[i])
        i += 1usize
    }
    out[2usize] = s2
    out[3usize] = s3
    let ym = rf.rf_mean(yv)
    var vy = 0.0f64
    i = 0usize
    while i < n {
        vy += (yv[i] - ym) * (yv[i] - ym)
        i += 1usize
    }
    out[4usize] = 1.0f64 - out[0usize] / (vy / f64(n - 1usize) * f64(n - 1usize) / f64(n))
    if o.importance {
        out[5usize] = cs(f.imp[0usize..p], p)
        out[7usize] = cs(f.impsd, p)
        var s8 = 0.0f64
        var s9 = 0.0f64
        var m = 0usize
        while m < p {
            s8 += f64(m + 1usize) * scaled(f.imp[m], f.impsd[m])
            m += 1usize
        }
        s9 = s8
        m = 0usize
        while m < p {
            s9 += f64(p + m + 1usize) * f.imp[p + m]
            m += 1usize
        }
        out[8usize] = s8
        out[9usize] = s9
    }
    out[6usize] = cs(f.imp[p..2usize * p], p)
    if o.proximity { out[10usize] = cs(f.prox, n * n) }
    if o.local_imp { out[11usize] = cs(f.impmat, n * p) }
    if o.keep_inbag { out[14usize] = csi(f.inbag, n * o.ntree) }
    let (pr, e4) = mem.alloc[f64](a, ntest + 1usize)
    if e4 != ok { ret e4 }
    let e5 = rf.rf_predict_reg(a, &f, xn, ntest, pr)
    if e5 != ok { ret e5 }
    out[12usize] = cs(pr, ntest)
    if npt > 0usize {
        let e6 = rf.rf_partial_reg(a, &f, xd, n, pv, npt, xpt, ypt)
        if e6 != ok { ret e6 }
        out[13usize] = cs(ypt, npt)
        out[15usize] = cs(xpt, npt)
    }
    let (pxm, e7) = mem.alloc[f64](a, ntest * ntest + 1usize)
    let (nds, e8) = mem.alloc[i64](a, ntest * o.ntree + 1usize)
    let (alp, e9) = mem.alloc[f64](a, ntest * o.ntree + 1usize)
    if e7 != ok || e8 != ok || e9 != ok { ret mem.Exhausted }
    let e10 = rf.rf_predict_reg_full(a, &f, xn, ntest, pr, pxm, true, nds, true, alp, true)
    if e10 != ok { ret e10 }
    out[16usize] = cs(pxm, ntest * ntest)
    out[17usize] = csi(nds, ntest * o.ntree)
    out[18usize] = cs(alp, ntest * o.ntree)
    if testmode > 0usize {
        i = 0usize
        while i < ntest {
            pr[i] = f.treg[i]
            i += 1usize
        }
        out[19usize] = cs(f.treg, ntest)
        if testmode == 2usize {
            out[20usize] = cs(f.terr, o.ntree)
            let yt = rf.rf_mean(ytv)
            var vt = 0.0f64
            i = 0usize
            while i < ntest {
                vt += (ytv[i] - yt) * (ytv[i] - yt)
                i += 1usize
            }
            out[21usize] = 1.0f64 - f.terr[o.ntree - 1usize] / (vt / f64(ntest - 1usize) * f64(n - 1usize) / f64(n))
        }
        if o.proximity {
            var s22 = 0.0f64
            i = 0usize
            while i < ntest * (ntest + n) {
                s22 += f64(i + 1usize) * (f.tprox[i] / f64(o.ntree))
                i += 1usize
            }
            out[22usize] = s22
        }
    }
    ret ok
}

fn same(u: []const f64, v: []const f64) -> bool {
    if u.len != v.len { ret false }
    var i = 0usize
    while i < u.len {
        if u[i] != v[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/randomforest.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (out, oe) = mem.alloc[f64](a, NOUT)
    if oe != ok { os.exit(4) }
    let base = mem.mark(a)
    var failures = 0usize
    var at = 0usize
    var cached = false
    var key: []const f64 = zero
    while at < golden.cases.len {
        let c = &golden.cases[at]
        var got = 0.0f64
        if str.eq(c.name, "qsort") {
            let mark = mem.mark(a)
            let n = c.args.len
            let (v, e1) = mem.alloc[f64](a, n)
            let (ix, e2) = mem.alloc[i64](a, n)
            if e1 != ok || e2 != ok { os.exit(5) }
            var i = 0usize
            while i < n {
                v[i] = c.args[i]
                ix[i] = i64(i)
                i += 1usize
            }
            rf.rf_qsort_i(v, ix, 0i64, i64(n) - 1i64)
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += f64(i + 1usize) * f64(ix[i] + 1i64)
                i += 1usize
            }
            got = s
            mem.reset(a, mark)
        } else {
            let sel = usize(c.args[0usize])
            let rest = c.args[1usize..]
            if !(cached && same(key, rest)) {
                mem.reset(a, base)
                let fe = forest(a, c, out)
                if fe != ok { os.exit(6) }
                key = rest
                cached = true
            }
            got = out[sel]
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
