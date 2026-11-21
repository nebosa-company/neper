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
const NOUT: usize = 40000usize

// the first 20 entries of a vector, one slot each from `base`: the elementwise comparison
fn elems(out: []f64, base: usize, v: []const f64, n: usize) {
    var i = 0usize
    while i < n && i < 999usize {
        out[base + i] = v[i]
        i += 1usize
    }
}

fn elems_all(out: []f64, base: usize, v: []const f64, n: usize) {
    var i = 0usize
    while i < n {
        out[base + i] = v[i]
        i += 1usize
    }
}

// A "sel" case whose text is a comma list of R's values from slot `base` on ("NA" is skipped): the
// elementwise comparison, one tolerance for every value (rel 1e-9, abs 1e-10). Returns the
// number of values that disagree.
fn vec_disagree(out: []const f64, base: usize, text: str) -> usize {
    var (it, _se) = str.split(text, ",")
    var at = 0usize
    var bad = 0usize
    while true {
        let (item, more) = str.split_next(&it)
        if !more { break }
        if !str.eq(item, "NA") {
            let (want, pe) = str.parse_f64(item)
            let got = out[base + at]
            var gap = got - want
            if gap < 0.0f64 { gap = 0.0f64 - gap }
            var scale = want
            if scale < 0.0f64 { scale = 0.0f64 - scale }
            var sg = got
            if sg < 0.0f64 { sg = 0.0f64 - sg }
            if sg > scale { scale = sg }
            if pe != ok || !(gap <= 1.0e-10f64 || gap <= 1.0e-9f64 * scale) {
                bad += 1usize
            }
        }
        at += 1usize
    }
    ret bad
}

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
    elems(out, 1000usize, oob.pred, n)
    elems(out, 5000usize, oob.err, n)
    elems(out, 6000usize, oob.exc, n)
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
    elems(out, 3000usize, pt.pred, nnew)
    if wantv {
        out[4usize] = cs(pt.var_est, nnew)
        elems(out, 4000usize, pt.var_est, nnew)
        let (ov, ve) = grf.predict(a, &f, &d, xd, n, true, true, 0usize)
        if ve != ok { ret ve }
        out[5usize] = cs(ov.var_est, n)
        elems(out, 2000usize, ov.var_est, n)
    }
    let (vi, ie) = grf.variable_importance(a, &f, decay, max_depth)
    if ie != ok { ret ie }
    out[6usize] = cs(vi, p)
    elems(out, 7000usize, vi, p)
    ret ok
}

// boosted_regression_forest: the regression forest and the forests on the out-of-bag residuals
fn bforest(a: *mem.Arena, c: *const oracle.Case, out: []f64) -> err {
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
    let steps = usize(x[18usize])
    let max_steps = usize(x[19usize])
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
    let (b, be) = grf.boosted(a, &d, &o, steps, 0.97f64, max_steps, 10usize)
    if be != ok { ret be }
    out[0usize] = cs(b.yhat, n)
    elems(out, 1000usize, b.yhat, n)
    elems(out, 2000usize, b.errs, b.nf)
    out[1usize] = f64(b.nf)
    out[2usize] = cs(b.errs, b.nf)
    let (acc, ae) = mem.alloc[f64](a, nnew)
    if ae != ok { ret ae }
    i = 0usize
    while i < nnew {
        acc[i] = 0.0f64
        i += 1usize
    }
    var k = 0usize
    while k < b.nf {
        let (pt, pe) = grf.predict(a, &b.forests[k], &d, xn, nnew, false, false, 0usize)
        if pe != ok { ret pe }
        i = 0usize
        while i < nnew {
            acc[i] += pt.pred[i]
            i += 1usize
        }
        k += 1usize
    }
    out[3usize] = cs(acc, nnew)
    elems(out, 3000usize, acc, nnew)
    ret ok
}

// probability_forest: class-index outcomes, the multi-class splitting rule and the class-frequency predictions with their variance estimates
fn pforest(a: *mem.Arena, c: *const oracle.Case, out: []f64) -> err {
    let x = c.args
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let nnew = usize(x[14usize])
    let hasw = x[15usize] != 0.0f64
    let max_depth = usize(x[16usize])
    let decay = x[17usize]
    let nclass = usize(x[18usize])
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
    o.kind = 5usize
    o.nclass = nclass
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
    let wantv = o.ci_group_size > 1usize
    let (op, e1) = mem.alloc[f64](a, n * nclass)
    let (ov, e2) = mem.alloc[f64](a, n * nclass)
    let (tp, e3) = mem.alloc[f64](a, nnew * nclass)
    let (tv, e4) = mem.alloc[f64](a, nnew * nclass)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    let pe1 = grf.predict_prob(a, &f, xd, n, true, wantv, nclass, op, ov)
    if pe1 != ok { ret pe1 }
    let pe2 = grf.predict_prob(a, &f, xn, nnew, false, wantv, nclass, tp, tv)
    if pe2 != ok { ret pe2 }
    out[0usize] = cs(op, n * nclass)
    elems(out, 1000usize, op, n * nclass)
    elems(out, 3000usize, tp, nnew * nclass)
    out[2usize] = cs(tp, nnew * nclass)
    var s = 0.0f64
    var k = 0usize
    while k < nclass {
        s += op[k]
        k += 1usize
    }
    out[5usize] = s
    if wantv {
        out[1usize] = cs(ov, n * nclass)
        out[3usize] = cs(tv, nnew * nclass)
        elems(out, 2000usize, ov, n * nclass)
        elems(out, 4000usize, tv, nnew * nclass)
    }
    let (vi, ie) = grf.variable_importance(a, &f, decay, max_depth)
    if ie != ok { ret ie }
    out[4usize] = cs(vi, p)
    elems(out, 7000usize, vi, p)
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
    let cmode = usize(x[20usize])
    var clv: []usize = zero
    var cl: grf.Clu = zero
    var ow = x[off - wn..off]
    if cmode > 0usize {
        let (cu, cue) = mem.alloc[usize](a, n)
        if cue != ok { ret cue }
        var q = 0usize
        while q < n {
            cu[q] = usize(x[off + q])
            q += 1usize
        }
        clv = cu
        off += n
        o.cluster = cu
        o.equalize = cmode == 2usize
        // dense cluster ids in order of first appearance, and the observation weights (1 / cluster size when equalized)
        let (cid, ce2) = mem.alloc[usize](a, n)
        let (lab, ce3) = mem.alloc[usize](a, n)
        let (sz, ce4) = mem.alloc[usize](a, n)
        let (owv, ce5) = mem.alloc[f64](a, n)
        if ce2 != ok { ret ce2 }
        if ce3 != ok { ret ce3 }
        if ce4 != ok { ret ce4 }
        if ce5 != ok { ret ce5 }
        var kk = 0usize
        q = 0usize
        while q < n {
            var fnd = n
            var r = 0usize
            while r < kk {
                if lab[r] == cu[q] { fnd = r }
                r += 1usize
            }
            if fnd == n {
                lab[kk] = cu[q]
                sz[kk] = 0usize
                fnd = kk
                kk += 1usize
            }
            cid[q] = fnd
            sz[fnd] += 1usize
            q += 1usize
        }
        q = 0usize
        while q < n {
            owv[q] = 1.0f64
            if hasw { owv[q] = ow[q] }
            if cmode == 2usize { owv[q] = 1.0f64 / f64(sz[cid[q]]) }
            q += 1usize
        }
        cl.cid = cid
        cl.k = kk
        ow = owv
    }
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
    elems(out, 1000usize, oob.pred, n)
    elems(out, 5000usize, oob.err, n)
    elems(out, 6000usize, oob.exc, n)
    elems(out, 8000usize, yhat, n)
    elems(out, 9000usize, what, n)
    if iv { elems(out, 9500usize, zhat, n) }
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
    elems(out, 3000usize, pt.pred, nnew)
    if wantv {
        out[4usize] = cs(pt.var_est, nnew)
        elems(out, 4000usize, pt.var_est, nnew)
        let (ov, ve) = grf.predict(a, &f, &d, xd, n, true, true, 1usize)
        if ve != ok { ret ve }
        out[5usize] = cs(ov.var_est, n)
        elems(out, 2000usize, ov.var_est, n)
    }
    let (vi, ie) = grf.variable_importance(a, &f, decay, max_depth)
    if ie != ok { ret ie }
    out[6usize] = cs(vi, p)
    elems(out, 7000usize, vi, p)
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
        oc.equalize = false
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
    var ate = grf.ate_all(sc, ow, n)
    if cl.k > 0usize {
        let (ac, ace) = grf.ate_all_c(a, sc, ow, &cl, n)
        if ace != ok { ret ace }
        ate = ac
    }
    out[11usize] = ate.estimate
    out[12usize] = ate.std_err
    if !iv {
        var kk = 0usize
        while kk < 6usize {
            var tg = 1usize
            var md = 0usize
            if kk == 1usize { tg = 2usize }
            if kk == 2usize { tg = 3usize }
            if kk >= 3usize { md = 1usize }
            if kk == 3usize { tg = 0usize }
            if kk == 4usize { tg = 1usize }
            if kk == 5usize { tg = 2usize }
            if !(md == 1usize && hasw) {
                let (r2, re) = grf.ate_target(a, tg, md, oob.pred, yv, yhat, tv, what, ow, &cl, n)
                if re != ok { ret re }
                out[14usize + 2usize * kk] = r2.estimate
                out[15usize + 2usize * kk] = r2.std_err
            }
            kk += 1usize
        }
    }
    ret ok
}

// the whole of a vector, one slot each from `base` (at most 999)
fn put(out: []f64, base: usize, v: []const f64, n: usize) {
    var i = 0usize
    while i < n && i < 999usize {
        out[base + i] = v[i]
        i += 1usize
    }
}

// multi_arm_causal_forest: Y.hat from a multi regression forest, W.hat from a probability forest over the treatment levels, then the multi causal forest on the
// centered data (treatment level 0 is the reference). args: head (stabilize at 18, treatment levels L at 19, outcomes at 20), Y (n by nout), W level index, w, X, Xnew
fn mforest(a: *mem.Arena, c: *const oracle.Case, out: []f64) -> err {
    let x = c.args
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let nnew = usize(x[14usize])
    let hasw = x[15usize] != 0.0f64
    let nl = usize(x[19usize])
    let no = usize(x[20usize])
    let kk = nl - 1usize
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
    o.kind = 6usize
    o.stabilize = x[18usize] != 0.0f64
    let max_depth = usize(x[16usize])
    let decay = x[17usize]
    var wn = 0usize
    if hasw { wn = n }
    let off = HEAD2
    let yv = x[off..off + n * no]
    let wl = x[off + n * no..off + n * no + n]
    let wv = x[off + n * no + n..off + n * no + n + wn]
    let xo = off + n * no + n + wn
    let xd = x[xo..xo + n * p]
    let xn = x[xo + n * p..xo + n * p + nnew * p]
    var i = 0usize
    while i < NOUT {
        out[i] = 0.0f64
        i += 1usize
    }
    // the nuisance forests
    var oq = o
    var nt = o.num_trees / 4usize
    if nt < 50usize { nt = 50usize }
    oq.num_trees = nt
    oq.min_node_size = 5usize
    oq.honesty = true
    oq.honesty_fraction = 0.5f64
    oq.ci_group_size = 1usize
    var dy: grf.Data = zero
    dy.n = n
    dy.p = p
    dy.x = xd
    dy.w = wv
    dy.ym = yv
    dy.nout = no
    oq.kind = 7usize
    let (fy, fye) = grf.train(a, &dy, &oq)
    if fye != ok { ret fye }
    let (yhat, yhe) = mem.alloc[f64](a, n * no)
    if yhe != ok { ret yhe }
    let pe0 = grf.predict_multi(a, &fy, 7usize, 0usize, no, xd, n, true, false, yhat, yhat)
    if pe0 != ok { ret pe0 }
    var dw: grf.Data = zero
    dw.n = n
    dw.p = p
    dw.x = xd
    dw.y = wl
    dw.w = wv
    oq.kind = 5usize
    oq.nclass = nl
    let (fw, fwe) = grf.train(a, &dw, &oq)
    if fwe != ok { ret fwe }
    let (what, whe) = mem.alloc[f64](a, n * nl)
    if whe != ok { ret whe }
    let pe1 = grf.predict_prob(a, &fw, xd, n, true, false, nl, what, what)
    if pe1 != ok { ret pe1 }
    let (yc, yce) = mem.alloc[f64](a, n * no)
    let (wc, wce) = mem.alloc[f64](a, n * kk)
    if yce != ok { ret yce }
    if wce != ok { ret wce }
    i = 0usize
    while i < n * no {
        yc[i] = yv[i] - yhat[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        var l = 1usize
        while l < nl {
            var ind = 0.0f64
            if usize(wl[i]) == l { ind = 1.0f64 }
            wc[i * kk + l - 1usize] = ind - what[i * nl + l]
            l += 1usize
        }
        i += 1usize
    }
    var d6: grf.Data = zero
    d6.n = n
    d6.p = p
    d6.x = xd
    d6.w = wv
    d6.ym = yc
    d6.tm = wc
    d6.nout = no
    d6.ntr = kk
    let (f, fe) = grf.train(a, &d6, &o)
    if fe != ok { ret fe }
    let wantv = o.ci_group_size > 1usize && no == 1usize
    let plen = kk * no
    let (op, e1) = mem.alloc[f64](a, n * plen)
    let (ov, e2) = mem.alloc[f64](a, n * kk)
    let (tp, e3) = mem.alloc[f64](a, nnew * plen)
    let (tv, e4) = mem.alloc[f64](a, nnew * kk)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    let pe2 = grf.predict_multi(a, &f, 6usize, kk, no, xd, n, true, wantv, op, ov)
    if pe2 != ok { ret pe2 }
    let pe3 = grf.predict_multi(a, &f, 6usize, kk, no, xn, nnew, false, wantv, tp, tv)
    if pe3 != ok { ret pe3 }
    out[0usize] = cs(op, n * plen)
    out[2usize] = cs(tp, nnew * plen)
    put(out, 1000usize, op, n * plen)
    put(out, 3000usize, tp, nnew * plen)
    if wantv {
        out[1usize] = cs(ov, n * kk)
        out[3usize] = cs(tv, nnew * kk)
        put(out, 2000usize, ov, n * kk)
        put(out, 4000usize, tv, nnew * kk)
    }
    let (vi, ie) = grf.variable_importance(a, &f, decay, max_depth)
    if ie != ok { ret ie }
    out[4usize] = cs(vi, p)
    put(out, 7000usize, vi, p)
    out[5usize] = cs(yhat, n * no)
    put(out, 8000usize, yhat, n * no)
    out[6usize] = cs(what, n * nl)
    put(out, 9000usize, what, n * nl)
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
    elems(out, 1000usize, oq, n * nq)
    elems(out, 3000usize, tq, nnew * nq)
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
    elems(out, 1000usize, oo, n)
    elems(out, 2000usize, ov, n)
    elems(out, 3000usize, to, nnew)
    elems(out, 4000usize, tv, nnew)
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
    elems_all(out, 20000usize, oq, n * nu)
    elems(out, 3000usize, tq, nnew * nu)
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
        } else if str.eq(c.name, "sel") && c.text.len > 0usize {
            let bad = vec_disagree(out, usize(c.args[0usize]), c.text)
            if bad > 0usize {
                failures += 1usize
                if failures <= 30usize {
                    let (vb, vbe) = str.builder(a, 64usize)
                    if vbe == ok {
                        var b = vb
                        let _ = str.push(&b, "--- vector slot ")
                        let _ = str.push_f64(&b, c.args[0usize])
                        let _ = str.push(&b, ": values that differ ")
                        let _ = str.push_f64(&b, f64(bad))
                        let _ = io.print(str.done(&b))
                    }
                    let _ = io.print("\n")
                }
            }
            at += 1usize
            continue
        } else if str.eq(c.name, "sel") {
            got = out[usize(c.args[0usize])]
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
                } else if str.eq(c.name, "grf_boost") {
                    fe = bforest(a, c, out)
                } else if str.eq(c.name, "grf_multi") {
                    fe = mforest(a, c, out)
                } else if str.eq(c.name, "grf_prob") {
                    fe = pforest(a, c, out)
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
            if failures <= 30usize {
                if str.eq(c.name, "sel") {
                    let _ = io.print(oracle.describe(a, c, got))
                } else {
                    let _ = io.print("--- full case ")
                    let _ = io.print(c.name)
                    if c.args.len > 5usize {
                        let (nb, nbe) = str.builder(a, 64usize)
                        if nbe == ok {
                            var b = nb
                            let _ = str.push(&b, " n=")
                            let _ = str.push_f64(&b, c.args[1usize])
                            let _ = str.push(&b, " p=")
                            let _ = str.push_f64(&b, c.args[2usize])
                            let _ = str.push(&b, " trees=")
                            let _ = str.push_f64(&b, c.args[3usize])
                            let _ = io.print(str.done(&b))
                        }
                    }
                }
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
