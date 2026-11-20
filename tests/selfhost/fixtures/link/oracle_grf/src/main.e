// e.algo.stat.grf against grf 2.6.1. tests/oracle/grf.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R grf`; the layout is at the top of scripts/r_oracle/groups/grf.R.

use e.algo.rand.r as rng
use e.algo.stat.grf as grf
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

const HEAD: usize = 20usize
const NOUT: usize = 14usize

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

fn forest(a: *mem.Arena, c: *const oracle.Case, out: []f64) -> err {
    let x = c.args
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let nnew = usize(x[14usize])
    let hasw = x[15usize] != 0.0f64
    var o: grf.Opts = zero
    o.num_trees = usize(x[3usize])
    o.mtry = usize(x[4usize])
    o.min_node_size = usize(x[5usize])
    o.sample_fraction = x[6usize]
    o.honesty = x[7usize] != 0.0f64
    o.honesty_fraction = x[8usize]
    o.honesty_prune = x[9usize] != 0.0f64
    o.ci_group_size = usize(x[10usize])
    o.alpha = x[11usize]
    o.imbalance_penalty = x[12usize]
    o.seed = u64(x[13usize])
    let max_depth = usize(x[16usize])
    let decay = x[17usize]
    var wn = 0usize
    if hasw { wn = n }
    let yv = x[HEAD..HEAD + n]
    let wv = x[HEAD + n..HEAD + n + wn]
    let xd = x[HEAD + n + wn..HEAD + n + wn + n * p]
    let xn = x[HEAD + n + wn + n * p..HEAD + n + wn + n * p + nnew * p]
    var d: grf.Data = zero
    d.n = n
    d.p = p
    d.x = xd
    d.y = yv
    d.w = wv
    var i = 0usize
    while i < NOUT {
        out[i] = 0.0f64
        i += 1usize
    }
    let (f, fe) = grf.train(a, &d, &o)
    if fe != ok { ret fe }
    let (oob, oe) = grf.predict(a, &f, &d, xd, n, true, false, 0usize)
    if oe != ok { ret oe }
    out[0usize] = cs(oob.pred, n)
    out[1usize] = cs(oob.err, n)
    out[2usize] = cs(oob.exc, n)
    out[7usize] = oob.pred[0usize]
    var s = 0.0f64
    var k = 0usize
    i = 0usize
    while i < n {
        if oob.pred[i] == oob.pred[i] {
            s += oob.pred[i]
            k += 1usize
        }
        i += 1usize
    }
    out[8usize] = s / f64(k)
    let wantv = o.ci_group_size > 1usize
    let (pt, pe) = grf.predict(a, &f, &d, xn, nnew, false, wantv, 0usize)
    if pe != ok { ret pe }
    out[3usize] = cs(pt.pred, nnew)
    if wantv {
        out[4usize] = cs(pt.var_est, nnew)
        let (ov, ve) = grf.predict(a, &f, &d, xd, n, true, true, 0usize)
        if ve != ok { ret ve }
        out[5usize] = cs(ov.var_est, n)
    }
    let (vi, ie) = grf.variable_importance(a, &f, decay, max_depth)
    if ie != ok { ret ie }
    out[6usize] = cs(vi, p)
    ret ok
}

const HEAD2: usize = 24usize

fn sub(a: *mem.Arena, u: []const f64, v: []const f64, n: usize) -> ([]f64, err) {
    let (r, e) = mem.alloc[f64](a, n)
    if e != ok { ret (r, e) }
    var i = 0usize
    while i < n {
        r[i] = u[i] - v[i]
        i += 1usize
    }
    ret (r, ok)
}

// causal_forest (iv false) and instrumental_forest (iv true): the nuisance forests, the effect forest on the centered data, and the doubly robust average effect
fn cforest(a: *mem.Arena, c: *const oracle.Case, out: []f64, iv: bool) -> err {
    let x = c.args
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let nnew = usize(x[14usize])
    let hasw = x[15usize] != 0.0f64
    var o: grf.Opts = zero
    o.num_trees = usize(x[3usize])
    o.mtry = usize(x[4usize])
    o.min_node_size = usize(x[5usize])
    o.sample_fraction = x[6usize]
    o.honesty = x[7usize] != 0.0f64
    o.honesty_fraction = x[8usize]
    o.honesty_prune = x[9usize] != 0.0f64
    o.ci_group_size = usize(x[10usize])
    o.alpha = x[11usize]
    o.imbalance_penalty = x[12usize]
    o.seed = u64(x[13usize])
    o.kind = 1usize
    o.stabilize = x[18usize] != 0.0f64
    o.rfw = x[19usize]
    let max_depth = usize(x[16usize])
    let decay = x[17usize]
    var wn = 0usize
    if hasw { wn = n }
    var off = HEAD2
    let yv = x[off..off + n]
    off += n
    let tv = x[off..off + n]
    off += n
    var zv = x[off..off]
    if iv {
        zv = x[off..off + n]
        off += n
    }
    let wv = x[off..off + wn]
    off += wn
    let xd = x[off..off + n * p]
    off += n * p
    let xn = x[off..off + nnew * p]
    var i = 0usize
    while i < NOUT {
        out[i] = 0.0f64
        i += 1usize
    }
    var d0: grf.Data = zero
    d0.n = n
    d0.p = p
    d0.x = xd
    d0.w = wv
    var ntr = o.num_trees / 4usize
    if ntr < 50usize { ntr = 50usize }
    if iv {
        ntr = o.num_trees
        if ntr > 500usize { ntr = 500usize }
    }
    d0.y = yv
    let (yhat, ye) = grf.nuisance(a, &d0, &o, ntr)
    if ye != ok { ret ye }
    d0.y = tv
    let (what, we) = grf.nuisance(a, &d0, &o, ntr)
    if we != ok { ret we }
    var zhat = yhat
    if iv {
        d0.y = zv
        let (zh, ze) = grf.nuisance(a, &d0, &o, ntr)
        if ze != ok { ret ze }
        zhat = zh
    }
    out[9usize] = cs(yhat, n)
    out[10usize] = cs(what, n)
    if iv { out[13usize] = cs(zhat, n) }
    let (yc, ce1) = sub(a, yv, yhat, n)
    if ce1 != ok { ret ce1 }
    let (tc, ce2) = sub(a, tv, what, n)
    if ce2 != ok { ret ce2 }
    var d: grf.Data = zero
    d.n = n
    d.p = p
    d.x = xd
    d.w = wv
    d.y = yc
    d.t = tc
    if iv {
        let (zc, ce3) = sub(a, zv, zhat, n)
        if ce3 != ok { ret ce3 }
        d.z = zc
        d.zsep = true
    }
    let (f, fe) = grf.train(a, &d, &o)
    if fe != ok { ret fe }
    let (oob, oe) = grf.predict(a, &f, &d, xd, n, true, false, 1usize)
    if oe != ok { ret oe }
    out[0usize] = cs(oob.pred, n)
    out[1usize] = cs(oob.err, n)
    out[2usize] = cs(oob.exc, n)
    out[7usize] = oob.pred[0usize]
    var s = 0.0f64
    var k = 0usize
    i = 0usize
    while i < n {
        if oob.pred[i] == oob.pred[i] {
            s += oob.pred[i]
            k += 1usize
        }
        i += 1usize
    }
    out[8usize] = s / f64(k)
    let wantv = o.ci_group_size > 1usize
    let (pt, pe) = grf.predict(a, &f, &d, xn, nnew, false, wantv, 1usize)
    if pe != ok { ret pe }
    out[3usize] = cs(pt.pred, nnew)
    if wantv {
        out[4usize] = cs(pt.var_est, nnew)
        let (ov, ve) = grf.predict(a, &f, &d, xd, n, true, true, 1usize)
        if ve != ok { ret ve }
        out[5usize] = cs(ov.var_est, n)
    }
    let (vi, ie) = grf.variable_importance(a, &f, decay, max_depth)
    if ie != ok { ret ie }
    out[6usize] = cs(vi, p)
    // average_treatment_effect: debiasing weights from the propensity (causal) or from the instrument and a compliance forest (instrumental)
    let (deb, de) = mem.alloc[f64](a, n)
    if de != ok { ret de }
    if iv {
        let (wc, ce4) = sub(a, tv, what, n)
        if ce4 != ok { ret ce4 }
        var dc: grf.Data = zero
        dc.n = n
        dc.p = p
        dc.x = xd
        dc.w = wv
        dc.y = wc
        dc.t = d.z
        var oc = o
        oc.num_trees = 500usize
        oc.min_node_size = 5usize
        oc.honesty = true
        oc.honesty_fraction = 0.5f64
        oc.honesty_prune = true
        oc.alpha = 0.05f64
        oc.imbalance_penalty = 0.0f64
        oc.ci_group_size = 2usize
        oc.stabilize = true
        oc.rfw = 0.0f64
        oc.sample_fraction = 0.5f64
        let (cf, cfe) = grf.train(a, &dc, &oc)
        if cfe != ok { ret cfe }
        let (cp, cpe) = grf.predict(a, &cf, &dc, xd, n, true, false, 1usize)
        if cpe != ok { ret cpe }
        i = 0usize
        while i < n {
            deb[i] = (zv[i] - zhat[i]) / (zhat[i] * (1.0f64 - zhat[i])) / cp.pred[i]
            i += 1usize
        }
    } else {
        i = 0usize
        while i < n {
            deb[i] = (tv[i] - what[i]) / (what[i] * (1.0f64 - what[i]))
            i += 1usize
        }
    }
    let (sc, se) = mem.alloc[f64](a, n)
    if se != ok { ret se }
    grf.dr_scores(sc, oob.pred, yv, yhat, tv, what, deb, n)
    let ate = grf.ate_all(sc, wv, n)
    out[11usize] = ate.estimate
    out[12usize] = ate.std_err
    ret ok
}

// quantile_forest: the quantile (or regression) splitting forest and its weighted quantile predictions
fn qforest(a: *mem.Arena, c: *const oracle.Case, out: []f64) -> err {
    let x = c.args
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let nnew = usize(x[13usize])
    let nq = usize(x[15usize])
    var o: grf.Opts = zero
    o.num_trees = usize(x[3usize])
    o.mtry = usize(x[4usize])
    o.min_node_size = usize(x[5usize])
    o.sample_fraction = x[6usize]
    o.honesty = x[7usize] != 0.0f64
    o.honesty_fraction = x[8usize]
    o.honesty_prune = x[9usize] != 0.0f64
    o.ci_group_size = 1usize
    o.alpha = x[10usize]
    o.imbalance_penalty = x[11usize]
    o.seed = u64(x[12usize])
    o.kind = 2usize
    if x[14usize] != 0.0f64 { o.kind = 0usize }
    var off = HEAD2
    let qs = x[off..off + nq]
    off += nq
    o.quantiles = qs
    let yv = x[off..off + n]
    off += n
    let xd = x[off..off + n * p]
    off += n * p
    let xn = x[off..off + nnew * p]
    var d: grf.Data = zero
    d.n = n
    d.p = p
    d.x = xd
    d.y = yv
    let (f, fe) = grf.train(a, &d, &o)
    if fe != ok { ret fe }
    let (oq, oe) = mem.alloc[f64](a, n * nq)
    if oe != ok { ret oe }
    let (tq, te) = mem.alloc[f64](a, nnew * nq)
    if te != ok { ret te }
    let pe = grf.predict_quantile(a, &f, &d, xd, n, true, qs, oq)
    if pe != ok { ret pe }
    let pe2 = grf.predict_quantile(a, &f, &d, xn, nnew, false, qs, tq)
    if pe2 != ok { ret pe2 }
    out[0usize] = cs(oq, n * nq)
    out[1usize] = cs(tq, nnew * nq)
    var s = 0.0f64
    var q = 0usize
    while q < nq {
        s += oq[q * n]
        q += 1usize
    }
    out[2usize] = s
    ret ok
}

// ll_regression_forest and its local linear predictions
fn llforest(a: *mem.Arena, c: *const oracle.Case, out: []f64) -> err {
    let x = c.args
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let nnew = usize(x[14usize])
    let nlc = usize(x[21usize])
    var o: grf.Opts = zero
    o.num_trees = usize(x[3usize])
    o.mtry = usize(x[4usize])
    o.min_node_size = usize(x[5usize])
    o.sample_fraction = x[6usize]
    o.honesty = x[7usize] != 0.0f64
    o.honesty_fraction = x[8usize]
    o.honesty_prune = x[9usize] != 0.0f64
    o.ci_group_size = usize(x[10usize])
    o.alpha = x[11usize]
    o.imbalance_penalty = x[12usize]
    o.seed = u64(x[13usize])
    let split = x[15usize] != 0.0f64
    let ll_split_lambda = x[16usize]
    let ll_split_wpen = x[17usize] != 0.0f64
    let ll_split_cutoff = usize(x[18usize])
    let ll_lambda = x[19usize]
    let ll_wpen = x[20usize] != 0.0f64
    var off = HEAD2
    let (vars, ve) = mem.alloc[usize](a, nlc)
    if ve != ok { ret ve }
    var i = 0usize
    while i < nlc {
        vars[i] = usize(x[off + i]) - 1usize
        i += 1usize
    }
    off += nlc
    let yv = x[off..off + n]
    off += n
    let xd = x[off..off + n * p]
    off += n * p
    let xn = x[off..off + nnew * p]
    var d: grf.Data = zero
    d.n = n
    d.p = p
    d.x = xd
    d.y = yv
    if split {
        // overall.beta: (D'D + lambda J)^-1 D'Y over [1, X]; the split variables are 1..p as the R wrapper passes them
        let k = p + 1usize
        let (sv, se) = mem.alloc[usize](a, p)
        if se != ok { ret se }
        i = 0usize
        while i < p {
            sv[i] = i + 1usize
            i += 1usize
        }
        let (mm, me) = mem.alloc[f64](a, k * k)
        let (bb, be) = mem.alloc[f64](a, k)
        let (beta, bte) = mem.alloc[f64](a, k)
        if me != ok { ret me }
        if be != ok { ret be }
        if bte != ok { ret bte }
        var r = 0usize
        while r < k {
            var cc = 0usize
            while cc < k {
                var acc = 0.0f64
                i = 0usize
                while i < n {
                    var dr = 1.0f64
                    if r > 0usize { dr = xd[i * p + r - 1usize] }
                    var dc = 1.0f64
                    if cc > 0usize { dc = xd[i * p + cc - 1usize] }
                    acc += dr * dc
                    i += 1usize
                }
                if r == cc && r > 0usize { acc += ll_split_lambda }
                mm[r * k + cc] = acc
                cc += 1usize
            }
            var bacc = 0.0f64
            i = 0usize
            while i < n {
                var dr = 1.0f64
                if r > 0usize { dr = xd[i * p + r - 1usize] }
                bacc += dr * yv[i]
                i += 1usize
            }
            bb[r] = bacc
            r += 1usize
        }
        grf.solve_sym(mm, bb, beta, k)
        o.kind = 3usize
        o.ll_lambda = ll_split_lambda
        o.ll_wpen = ll_split_wpen
        o.ll_cutoff = ll_split_cutoff
        o.ll_beta = beta
        o.ll_vars = sv
    }
    let (f, fe) = grf.train(a, &d, &o)
    if fe != ok { ret fe }
    var path: [10]f64 = zero
    path[1usize] = 0.001f64
    path[2usize] = 0.01f64
    path[3usize] = 0.05f64
    path[4usize] = 0.1f64
    path[5usize] = 0.3f64
    path[6usize] = 0.5f64
    path[7usize] = 0.7f64
    path[8usize] = 1.0f64
    path[9usize] = 10.0f64
    var lam = ll_lambda
    if ll_lambda < 0.0f64 {
        let (pp, pe) = mem.alloc[f64](a, n * 10usize)
        if pe != ok { ret pe }
        let (nv, nve) = mem.alloc[f64](a, 1usize)
        if nve != ok { ret nve }
        let te = grf.predict_ll(a, &f, &d, xd, n, true, path[0usize..10usize], ll_wpen, vars, false, pp, nv)
        if te != ok { ret te }
        lam = grf.ll_lambda_min(pp, yv, n, path[0usize..10usize])
    }
    var ls: [1]f64 = zero
    ls[0usize] = lam
    let (oo, oe) = mem.alloc[f64](a, n)
    let (ov, ove) = mem.alloc[f64](a, n)
    let (to, toe) = mem.alloc[f64](a, nnew)
    let (tv, tve) = mem.alloc[f64](a, nnew)
    if oe != ok { ret oe }
    if ove != ok { ret ove }
    if toe != ok { ret toe }
    if tve != ok { ret tve }
    let e1 = grf.predict_ll(a, &f, &d, xd, n, true, ls[0usize..1usize], ll_wpen, vars, true, oo, ov)
    if e1 != ok { ret e1 }
    let e2 = grf.predict_ll(a, &f, &d, xn, nnew, false, ls[0usize..1usize], ll_wpen, vars, true, to, tv)
    if e2 != ok { ret e2 }
    out[0usize] = cs(oo, n)
    out[1usize] = cs(ov, n)
    out[2usize] = cs(to, nnew)
    out[3usize] = cs(tv, nnew)
    out[4usize] = lam
    ret ok
}

// survival_forest: log-rank splitting and Kaplan-Meier or Nelson-Aalen curves from the forest weights
fn sforest(a: *mem.Arena, c: *const oracle.Case, out: []f64) -> err {
    let x = c.args
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let nnew = usize(x[12usize])
    let hasw = x[13usize] != 0.0f64
    var o: grf.Opts = zero
    o.num_trees = usize(x[3usize])
    o.mtry = usize(x[4usize])
    o.min_node_size = usize(x[5usize])
    o.sample_fraction = x[6usize]
    o.honesty = x[7usize] != 0.0f64
    o.honesty_fraction = x[8usize]
    o.honesty_prune = x[9usize] != 0.0f64
    o.ci_group_size = 1usize
    o.alpha = x[10usize]
    o.seed = u64(x[11usize])
    o.kind = 4usize
    let nelson = x[14usize] != 0.0f64
    var wn = 0usize
    if hasw { wn = n }
    var off = HEAD2
    let yv = x[off..off + n]
    off += n
    let dv = x[off..off + n]
    off += n
    let wv = x[off..off + wn]
    off += wn
    let xd = x[off..off + n * p]
    off += n * p
    let xn = x[off..off + nnew * p]
    // failure.times: the sorted distinct times of the failures; the outcome becomes the number of failure times at or below it
    let (ft, fe1) = mem.alloc[f64](a, n)
    let (rl, fe2) = mem.alloc[f64](a, n)
    if fe1 != ok { ret fe1 }
    if fe2 != ok { ret fe2 }
    var nf = 0usize
    var i = 0usize
    while i < n {
        if dv[i] > 0.0f64 {
            var j = nf
            while j > 0usize && ft[j - 1usize] > yv[i] {
                ft[j] = ft[j - 1usize]
                j -= 1usize
            }
            ft[j] = yv[i]
            nf += 1usize
        }
        i += 1usize
    }
    var nu = 0usize
    i = 0usize
    while i < nf {
        if nu == 0usize || ft[nu - 1usize] != ft[i] {
            ft[nu] = ft[i]
            nu += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var cnt = 0usize
        var j = 0usize
        while j < nu {
            if ft[j] <= yv[i] { cnt += 1usize }
            j += 1usize
        }
        rl[i] = f64(cnt)
        i += 1usize
    }
    var d: grf.Data = zero
    d.n = n
    d.p = p
    d.x = xd
    d.y = rl
    d.w = wv
    d.cens = dv
    let (f, fe) = grf.train(a, &d, &o)
    if fe != ok { ret fe }
    let (oq, oe) = mem.alloc[f64](a, n * nu)
    if oe != ok { ret oe }
    let (tq, te) = mem.alloc[f64](a, nnew * nu)
    if te != ok { ret te }
    let pe = grf.predict_survival(a, &f, &d, xd, n, true, nu, nelson, oq)
    if pe != ok { ret pe }
    let pe2 = grf.predict_survival(a, &f, &d, xn, nnew, false, nu, nelson, tq)
    if pe2 != ok { ret pe2 }
    out[0usize] = cs(oq, n * nu)
    out[1usize] = cs(tq, nnew * nu)
    out[2usize] = f64(nu)
    var s = 0.0f64
    var k = 0usize
    while k < nu {
        s += oq[k]
        k += 1usize
    }
    out[3usize] = s
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/grf.json")
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
        if str.eq(c.name, "runif_seed") {
            var g: rng.Rng = zero
            rng.seed(&g, i64(c.args[0usize]))
            got = rng.runif(&g, 0.0f64, 2147483647.0f64)
        } else {
            let sel = usize(c.args[0usize])
            let rest = c.args[1usize..]
            if !(cached && same(key, rest)) {
                mem.reset(a, base)
                var fe = ok
                if str.eq(c.name, "grf_causal") {
                    fe = cforest(a, c, out, false)
                } else if str.eq(c.name, "grf_iv") {
                    fe = cforest(a, c, out, true)
                } else if str.eq(c.name, "grf_surv") {
                    fe = sforest(a, c, out)
                } else if str.eq(c.name, "grf_ll") {
                    fe = llforest(a, c, out)
                } else if str.eq(c.name, "grf_quantile") {
                    fe = qforest(a, c, out)
                } else {
                    fe = forest(a, c, out)
                }
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
