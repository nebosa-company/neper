// e.algo.stat.logistf_r against the logistf R package. tests/oracle/logistf_full.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R logistf_full`; the case layout is at the top of scripts/r_oracle/groups/logistf_full.R.
// A case is one R call: the fixture runs the same call and the case passes when every number of R's answer is reproduced (1e-9 relative or
// 1e-10 absolute).

use e.algo.stat.logistf_r as lf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Prob = struct {
    n: usize, k: usize, m: usize, mask: usize, o: lf.Opt, y: []const f64, x: []const f64, w: []const f64, off: []const f64,
    plconf: []usize, terms: []usize, extra: []const f64, want: []const f64
}

fn flag(v: f64) -> bool { ret v != 0.0f64 }

fn parse(a: *mem.Arena, args: []const f64) -> (Prob, err) {
    let n = usize(args[0usize])
    let k = usize(args[1usize])
    let m = usize(args[2usize])
    var o = lf.opt_default()
    o.firth = flag(args[4usize])
    o.pl = flag(args[5usize])
    o.has_int = flag(args[6usize])
    o.flic = flag(args[7usize])
    o.c.maxit = usize(args[8usize])
    o.c.maxstep = args[9usize]
    o.c.maxhs = usize(args[10usize])
    o.c.lconv = args[11usize]
    o.c.gconv = args[12usize]
    o.c.xconv = args[13usize]
    o.c.irls = flag(args[14usize])
    o.c.tau = args[15usize]
    o.c.plmaxit = usize(args[16usize])
    o.c.plmaxstep = args[17usize]
    o.c.plmaxhs = usize(args[18usize])
    o.c.pllconv = args[19usize]
    o.c.plxconv = args[20usize]
    o.alpha = args[21usize]
    let npl = usize(args[22usize])
    let nt = usize(args[23usize])
    let has_w = flag(args[24usize])
    let has_o = flag(args[25usize])
    let ne = usize(args[26usize])
    o.c.collapse = flag(args[27usize])
    var at = 28usize
    let (plconf, e1) = mem.alloc[usize](a, npl + 1usize)
    if e1 != ok { ret (zero, e1) }
    var i = 0usize
    while i < npl {
        plconf[i] = usize(args[at + i])
        i += 1usize
    }
    at += npl
    let (terms, e2) = mem.alloc[usize](a, nt + 1usize)
    if e2 != ok { ret (zero, e2) }
    i = 0usize
    while i < nt {
        terms[i] = usize(args[at + i])
        i += 1usize
    }
    at += nt
    o.has_plconf = npl > 0usize
    o.has_terms = nt > 0usize
    o.plconf = plconf[0usize..npl]
    o.terms_fit = terms[0usize..nt]
    let y = args[at..at + n]
    at += n
    let x = args[at..at + n * k]
    at += n * k
    var w = args[at..at]
    if has_w {
        w = args[at..at + n]
        at += n
    }
    var off = args[at..at]
    if has_o {
        off = args[at..at + n]
        at += n
    }
    let extra = args[at..at + ne]
    at += ne
    let want = args[at..at + m]
    ret (Prob { n: n, k: k, m: m, mask: usize(args[3usize]), o: o, y: y, x: x, w: w, off: off, plconf: plconf, terms: terms, extra: extra, want: want }, ok)
}

fn bit(mask: usize, b: usize) -> bool { ret (mask >> b) & 1usize == 1usize }

type Out = struct { v: []f64, at: usize }

fn put(o: *Out, v: f64) {
    o.v[o.at] = v
    o.at += 1usize
}

fn flat(a: *mem.Arena, r: lf.Lf, mask: usize, pl: bool) -> ([]f64, err) {
    let (buf, e) = mem.alloc[f64](a, 64usize + 8usize * r.k * r.k + 12usize * r.n + 12usize * r.k)
    if e != ok { ret (buf, e) }
    var out = Out { v: buf, at: 0usize }
    let po = &out
    var i = 0usize
    if bit(mask, 0usize) {
        i = 0usize
        while i < r.k {
            put(po, r.coef[i])
            i += 1usize
        }
    }
    if bit(mask, 1usize) {
        i = 0usize
        while i < r.k * r.k {
            put(po, r.var_m[i])
            i += 1usize
        }
    }
    if bit(mask, 2usize) {
        i = 0usize
        while i < r.k {
            put(po, r.prob[i])
            i += 1usize
        }
        i = 0usize
        while i < r.k {
            put(po, r.ci_lo[i])
            i += 1usize
        }
        i = 0usize
        while i < r.k {
            put(po, r.ci_up[i])
            i += 1usize
        }
    }
    if bit(mask, 3usize) {
        put(po, r.ll_full)
        put(po, r.ll_null)
    }
    if bit(mask, 4usize) {
        put(po, f64(r.iter_full))
        put(po, f64(r.iter_null))
    }
    if bit(mask, 5usize) {
        put(po, f64(r.df))
        put(po, r.sumw)
    }
    if bit(mask, 6usize) {
        i = 0usize
        while i < r.n {
            put(po, r.lp[i])
            i += 1usize
        }
    }
    if bit(mask, 7usize) {
        i = 0usize
        while i < r.n {
            put(po, r.pred[i])
            i += 1usize
        }
    }
    if bit(mask, 8usize) {
        i = 0usize
        while i < r.n {
            put(po, r.hat[i])
            i += 1usize
        }
    }
    if bit(mask, 9usize) && pl {
        i = 0usize
        while i < 3usize * r.k {
            put(po, f64(r.pl_iter[i]))
            i += 1usize
        }
    }
    if bit(mask, 10usize) && pl {
        i = 0usize
        while i < 4usize * r.np {
            put(po, r.pl_conv[i])
            i += 1usize
        }
    }
    ret (buf[0usize..out.at], ok)
}

fn close(got: f64, want: f64) -> bool {
    if got == want { ret true }
    if got != got && want != want { ret true }
    if got != got || want != want { ret false }
    let d = math_abs(got - want)
    if d <= 1.0e-10f64 { ret true }
    ret d <= 1.0e-9f64 * math_abs(want)
}

fn math_abs(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

// the numbers that differ from R's, the first one described
fn compare(a: *mem.Arena, name: str, at: usize, got: []const f64, want: []const f64) -> usize {
    var bad = 0usize
    if got.len != want.len {
        let (initial, be) = str.builder(a, 96usize)
        if be == ok {
            var b = initial
            let _ = str.push(&b, name)
            let _ = str.push(&b, " case ")
            let _ = str.push_f64(&b, f64(at))
            let _ = str.push(&b, ": length ")
            let _ = str.push_f64(&b, f64(got.len))
            let _ = str.push(&b, " against R ")
            let _ = str.push_f64(&b, f64(want.len))
            let _ = str.push(&b, "\n")
            let _ = io.print(str.done(&b))
        }
        ret 1usize
    }
    var i = 0usize
    while i < got.len {
        if !close(got[i], want[i]) {
            bad += 1usize
            if bad <= 3usize {
                let (initial, be) = str.builder(a, 96usize)
                if be == ok {
                    var b = initial
                    let _ = str.push(&b, name)
                    let _ = str.push(&b, " case ")
                    let _ = str.push_f64(&b, f64(at))
                    let _ = str.push(&b, " item ")
                    let _ = str.push_f64(&b, f64(i))
                    let _ = str.push(&b, ": got ")
                    let _ = str.push_f64(&b, got[i])
                    let _ = str.push(&b, ", R says ")
                    let _ = str.push_f64(&b, want[i])
                    let _ = str.push(&b, "\n")
                    let _ = io.print(str.done(&b))
                }
            }
        }
        i += 1usize
    }
    ret bad
}

// a list of 1-based indices at extra[at..] (a count first) as 0-based, and where it ends
fn index_list(a: *mem.Arena, extra: []const f64, at: usize) -> ([]usize, usize, err) {
    let cnt = usize(extra[at])
    let (r, e) = mem.alloc[usize](a, cnt + 1usize)
    if e != ok { ret (r, at, e) }
    var i = 0usize
    while i < cnt {
        r[i] = usize(extra[at + 1usize + i]) - 1usize
        i += 1usize
    }
    ret (r[0usize..cnt], at + 1usize + cnt, ok)
}

fn value_list(extra: []const f64, at: usize) -> ([]const f64, usize) {
    let cnt = usize(extra[at])
    ret (extra[at + 1usize..at + 1usize + cnt], at + 1usize + cnt)
}

// the answer of a selection: the final model's coefficients, covariance, p values and limits placed by full-design column, the penalized
// log-likelihoods, the degrees of freedom and the order of entry or removal (1-based)
fn sel_flat(a: *mem.Arena, s: lf.Sel, kk: usize) -> ([]f64, err) {
    let (buf, e) = mem.alloc[f64](a, 5usize * kk + kk * kk + 8usize + s.order.len)
    if e != ok { ret (buf, e) }
    var out = Out { v: buf, at: 0usize }
    let po = &out
    var q = 0usize
    while q < 5usize * kk + kk * kk {
        put(po, 0.0f64)
        q += 1usize
    }
    let f = s.fit
    var i = 0usize
    while i < s.nc {
        let ci = s.cols[i]
        buf[ci] = f.coef[i]
        buf[kk + kk * kk + ci] = f.prob[i]
        buf[2usize * kk + kk * kk + ci] = f.ci_lo[i]
        buf[3usize * kk + kk * kk + ci] = f.ci_up[i]
        var j = 0usize
        while j < s.nc {
            buf[kk + ci + s.cols[j] * kk] = f.var_m[i + j * s.nc]
            j += 1usize
        }
        i += 1usize
    }
    out.at = 4usize * kk + kk * kk
    put(po, f.ll_full)
    put(po, f.ll_null)
    put(po, f64(f.df))
    put(po, f64(s.order.len))
    i = 0usize
    while i < s.order.len {
        put(po, f64(s.order[i] + 1usize))
        i += 1usize
    }
    ret (buf[0usize..out.at], ok)
}

fn run(a: *mem.Arena, c: *const oracle.Case, at: usize) -> usize {
    let (p, pe) = parse(a, c.args)
    if pe != ok { ret 1usize }
    let (wv, ew) = lf.weights_or_ones(a, p.w, p.n)
    let (ov, eo) = lf.offset_or_zeros(a, p.off, p.n)
    if ew != ok || eo != ok { ret 1usize }
    if str.eq(c.name, "test") {
        let (cols, p1, e1) = index_list(a, p.extra, 0usize)
        let (tst, p2, e2) = index_list(a, p.extra, p1)
        let (vals, p3) = value_list(p.extra, p2)
        let (b0, p4) = value_list(p.extra, p3)
        if e1 != ok || e2 != ok { ret 1usize }
        let (xs, e3) = lf.cols_of(a, p.x, p.n, cols)
        if e3 != ok { ret 1usize }
        let (t, e4) = lf.lf_test(a, xs, p.n, cols.len, p.y, wv, ov, tst, vals, b0, p.o.firth, p.o.c)
        if e4 != ok { ret 1usize }
        let (g, e5) = mem.alloc[f64](a, 4usize)
        if e5 != ok { ret 1usize }
        g[0usize] = t.ll_full
        g[1usize] = t.ll_null
        g[2usize] = f64(t.df)
        g[3usize] = t.prob
        ret compare(a, c.name, at, g, p.want)
    }
    if str.eq(c.name, "anova_n") || str.eq(c.name, "anova_p") || str.eq(c.name, "anova_f") {
        let (cols, p1, e1) = index_list(a, p.extra, 0usize)
        let (other, p2, e2) = index_list(a, p.extra, p1)
        if e1 != ok || e2 != ok { ret 1usize }
        var po = p.o
        if str.eq(c.name, "anova_p") == false {
            po.nv = usize(p.extra[p2])
            po.facs = p.extra[p2 + 1usize..p2 + 1usize + po.nv * p.k]
        }
        var r: lf.Anova = zero
        if str.eq(c.name, "anova_n") {
            let (r1, e3) = lf.anova_nested(a, p.x, p.n, p.y, wv, ov, cols, other, po)
            if e3 != ok { ret 1usize }
            r = r1
        }
        if str.eq(c.name, "anova_f") {
            let (r2, e4) = lf.anova_formula(a, p.x, p.n, p.y, wv, ov, cols, other, po)
            if e4 != ok { ret 1usize }
            r = r2
        }
        if str.eq(c.name, "anova_p") {
            let (f1, e5) = lf.fit_model(a, p.x, p.n, p.y, wv, ov, cols, p.o, false)
            let (f2, e6) = lf.fit_model(a, p.x, p.n, p.y, wv, ov, other, p.o, false)
            if e5 != ok || e6 != ok { ret 1usize }
            let (r3, e7) = lf.anova_plr(f1, f2)
            if e7 != ok { ret 1usize }
            r = r3
        }
        let (g, e8) = mem.alloc[f64](a, 5usize)
        if e8 != ok { ret 1usize }
        g[0usize] = r.chisq
        g[1usize] = f64(r.df)
        g[2usize] = r.pval
        g[3usize] = r.plr1
        g[4usize] = r.plr2
        ret compare(a, c.name, at, g, p.want)
    }
    if str.eq(c.name, "add1") || str.eq(c.name, "drop1") {
        let (cols, p1, e1) = index_list(a, p.extra, 0usize)
        let (sc, p2, e2) = index_list(a, p.extra, p1)
        if e1 != ok || e2 != ok { ret 1usize }
        let (g, e3) = mem.alloc[f64](a, 3usize * sc.len + 1usize)
        if e3 != ok { ret 1usize }
        var e4 = ok
        if str.eq(c.name, "add1") {
            e4 = lf.add1(a, p.x, p.n, p.y, wv, ov, cols, sc, p.o, g)
        } else {
            e4 = lf.drop1(a, p.x, p.n, p.y, wv, ov, cols, sc, sc[0usize..0usize], p.o, g)
        }
        if e4 != ok { ret 1usize }
        ret compare(a, c.name, at, g[0usize..3usize * sc.len], p.want)
    }
    if str.eq(c.name, "clip_ci") || str.eq(c.name, "clip_profile") {
        let ex = p.extra
        let nimp = usize(ex[0usize])
        let nsel = usize(ex[1usize])
        let k = p.k
        let (poss, e0) = mem.alloc[usize](a, nsel)
        if e0 != ok { ret 1usize }
        var i = 0usize
        while i < nsel {
            poss[i] = usize(ex[2usize + i]) - 1usize
            i += 1usize
        }
        let head = ex[2usize + nsel..14usize + nsel]
        var q = 14usize + nsel
        let (ns, e1) = mem.alloc[usize](a, nimp)
        if e1 != ok { ret 1usize }
        var tot = 0usize
        i = 0usize
        while i < nimp {
            ns[i] = usize(ex[q + i])
            tot += ns[i]
            i += 1usize
        }
        q += nimp
        let xs = ex[q..q + tot * k]
        q += tot * k
        let ys = ex[q..q + tot]
        q += tot
        let ws = ex[q..q + tot]
        q += tot
        let betas = ex[q..q + nimp * k]
        q += nimp * k
        let lls = ex[q..q + nimp]
        var cl = lf.Clip { xs: xs, ys: ys, ws: ws, ns: ns, nimp: nimp, k: k, betas: betas, logliks: lls, pos: poss[0usize], firth: p.o.firth, c: p.o.c }
        if str.eq(c.name, "clip_ci") {
            let (g, e3) = mem.alloc[f64](a, 10usize * nsel)
            if e3 != ok { ret 1usize }
            // estimate (nsel), ci (nsel by 2), pvalue (nsel), bound.lo (nsel by 2), bound.up (nsel by 2), iter (nsel by 2)
            let (m_lo, e4) = mem.alloc[f64](a, 2usize * nsel)
            let (m_up, e5) = mem.alloc[f64](a, 2usize * nsel)
            if e4 != ok || e5 != ok { ret 1usize }
            lf.fill_f(m_lo, 0.0f64)
            lf.fill_f(m_up, 0.0f64)
            var v = 0usize
            while v < nsel {
                cl.pos = poss[v]
                var est = 0.0f64
                i = 0usize
                while i < nimp {
                    est += betas[i * k + poss[v]]
                    i += 1usize
                }
                est = est / f64(nimp)
                let (r, e2) = lf.clip_confint(a, cl, v, nsel, m_lo, m_up, est, head[0usize], head[1usize])
                if e2 != ok { ret 1usize }
                g[v] = r.estimate
                g[nsel + v] = r.ci_lo
                g[2usize * nsel + v] = r.ci_up
                g[3usize * nsel + v] = r.pvalue
                g[8usize * nsel + v] = f64(r.iter0)
                g[9usize * nsel + v] = f64(r.iter1)
                v += 1usize
            }
            i = 0usize
            while i < 2usize * nsel {
                g[4usize * nsel + i] = m_lo[i]
                g[6usize * nsel + i] = m_up[i]
                i += 1usize
            }
            ret compare(a, c.name, at, g, p.want)
        }
        let steps = usize(head[11usize])
        let (g2, e6) = mem.alloc[f64](a, 3usize * (steps + 1usize))
        if e6 != ok { ret 1usize }
        let e7 = lf.clip_profile(a, cl, head[9usize], head[10usize], steps, g2[0usize..steps + 1usize], g2[steps + 1usize..2usize * (steps + 1usize)], g2[2usize * (steps + 1usize)..3usize * (steps + 1usize)])
        if e7 != ok { ret 1usize }
        ret compare(a, c.name, at, g2, p.want)
    }
    if str.eq(c.name, "fit_init") {
        var o = p.o
        o.has_init = true
        o.init = p.extra
        let (r, e) = lf.logistf(a, p.x, p.y, p.n, p.k, wv, ov, o)
        if e != ok { ret 1usize }
        let (g, e2) = flat(a, r, p.mask, o.pl)
        if e2 != ok { ret 1usize }
        ret compare(a, c.name, at, g, p.want)
    }
    if str.eq(c.name, "predict") {
        let ex = p.extra
        let objk = usize(ex[0usize])
        let typ = usize(ex[1usize])
        let sefit = flag(ex[2usize])
        let flicf = flag(ex[3usize])
        let has_new = flag(ex[4usize])
        let mm = usize(ex[5usize])
        var q = 6usize
        var xn = p.x
        var rows = p.n
        if has_new {
            xn = ex[q..q + mm * p.k]
            q += mm * p.k
            rows = mm
        }
        let nterms = usize(ex[q])
        let assign = ex[q + 1usize..q + 1usize + p.k]
        q += 1usize + p.k
        let nref = usize(ex[q])
        let refrow = ex[q + 1usize..q + 1usize + nref]
        var o = p.o
        o.pl = false
        var obj: lf.Lf = zero
        if objk == 2usize {
            let (r2, e2) = lf.flac(a, p.x, p.y, p.n, p.k, p.w, p.off, o)
            if e2 != ok { ret 1usize }
            obj = r2
        } else {
            o.flic = objk == 0usize && flicf
            let (r0, e0) = lf.logistf(a, p.x, p.y, p.n, p.k, p.w, p.off, o)
            if e0 != ok { ret 1usize }
            obj = r0
            if objk == 1usize {
                let (r1, e1) = lf.flic_fit(a, p.x, p.y, p.n, p.k, p.w, p.off, p.terms[0usize..0usize], r0)
                if e1 != ok { ret 1usize }
                obj = r1
            }
        }
        let (pred, e3) = mem.alloc[f64](a, rows * (nterms + 4usize) + 8usize)
        let (se, e4) = mem.alloc[f64](a, rows * (nterms + 1usize) + 8usize)
        if e3 != ok || e4 != ok { ret 1usize }
        let (res, e5) = mem.alloc[f64](a, 6usize * rows * (nterms + 1usize) + 16usize)
        if e5 != ok { ret 1usize }
        var out = Out { v: res, at: 0usize }
        let po = &out
        var i = 0usize
        if typ == 0usize {
            if has_new {
                lf.predict_link(obj.coef, xn, rows, p.k, pred)
            } else {
                lf.i_copy(obj.lp, pred, rows)
            }
            i = 0usize
            while i < rows {
                put(po, pred[i])
                i += 1usize
            }
            if sefit {
                lf.predict_se(obj.var_m, xn, rows, p.k, se)
                i = 0usize
                while i < rows {
                    put(po, se[i])
                    i += 1usize
                }
            }
        }
        if typ == 1usize {
            if has_new {
                lf.predict_response(obj.coef, xn, rows, p.k, pred)
            } else {
                lf.i_copy(obj.pred, pred, rows)
            }
            i = 0usize
            while i < rows {
                put(po, pred[i])
                i += 1usize
            }
            if sefit {
                lf.predict_se(obj.var_m, xn, rows, p.k, se)
                i = 0usize
                while i < rows {
                    put(po, pred[i] - 1.96f64 * se[i])
                    i += 1usize
                }
                i = 0usize
                while i < rows {
                    put(po, pred[i] + 1.96f64 * se[i])
                    i += 1usize
                }
            }
        }
        if typ == 2usize {
            let cst = lf.predict_terms(obj.coef, obj.var_m, p.x, p.n, xn, rows, p.k, assign_u(a, assign), nterms, refrow, pred, se)
            i = 0usize
            while i < rows * nterms {
                put(po, pred[i])
                i += 1usize
            }
            if sefit {
                i = 0usize
                while i < rows * nterms {
                    put(po, se[i])
                    i += 1usize
                }
            }
            put(po, cst)
        }
        ret compare(a, c.name, at, res[0usize..out.at], p.want)
    }
    if str.eq(c.name, "profile") {
        let ex = p.extra
        let pos = usize(ex[0usize]) - 1usize
        let steps = usize(ex[1usize])
        let pitch = ex[2usize]
        let have = flag(ex[3usize])
        var o = p.o
        o.pl = false
        let (f, e1) = lf.logistf(a, p.x, p.y, p.n, p.k, wv, ov, o)
        if e1 != ok { ret 1usize }
        let (res, e2) = mem.alloc[f64](a, 6usize * (steps + 1usize) + 1usize)
        if e2 != ok { ret 1usize }
        let (kept, e3) = lf.profile_lf(a, p.x, p.n, p.k, p.y, wv, ov, f, pos, steps, pitch, have, ex[4usize], ex[5usize], ex[6usize], o.firth, o.c, res)
        if e3 != ok { ret 1usize }
        let (g, e4) = mem.alloc[f64](a, 6usize * kept + 1usize)
        if e4 != ok { ret 1usize }
        g[0usize] = f64(kept)
        var part = 0usize
        while part < 6usize {
            var i = 0usize
            while i < kept {
                g[1usize + part * kept + i] = res[part * (steps + 1usize) + i]
                i += 1usize
            }
            part += 1usize
        }
        ret compare(a, c.name, at, g[0usize..6usize * kept + 1usize], p.want)
    }
    if str.eq(c.name, "pdf") {
        let ex = p.extra
        let pos = usize(ex[0usize]) - 1usize
        let (r, e) = lf.logistf_pdf(a, p.x, p.n, p.k, p.y, wv, ov, p.o.firth, p.o.c, pos, ex[1usize], ex[2usize..2usize + p.k], ex[2usize + p.k])
        if e != ok { ret 1usize }
        let (g, e2) = mem.alloc[f64](a, 2usize)
        if e2 != ok { ret 1usize }
        g[0usize] = r.chisq
        g[1usize] = r.pdf
        ret compare(a, c.name, at, g, p.want)
    }
    if str.eq(c.name, "pl") {
        let ex = p.extra
        let pos = usize(ex[0usize]) - 1usize
        let (bm, eb) = lf.bump_for(a, p.n, p.k)
        if eb != ok { ret 1usize }
        var bump = bm
        let (hist, eh) = mem.alloc[f64](a, p.o.c.plmaxit * p.k)
        if eh != ok { ret 1usize }
        let (r, e) = lf.logistpl(&bump, p.x, p.y, p.n, p.k, wv, ov, ex[3usize..3usize + p.k], pos, ex[2usize], p.o.firth, ex[1usize], p.o.c, hist)
        if e != ok { ret 1usize }
        let (g, e2) = mem.alloc[f64](a, 5usize + r.iter * p.k)
        if e2 != ok { ret 1usize }
        g[0usize] = r.beta
        g[1usize] = r.loglik
        g[2usize] = f64(r.iter)
        g[3usize] = r.c0
        g[4usize] = r.c1
        var col = 0usize
        while col < p.k {
            var rw = 0usize
            while rw < r.iter {
                g[5usize + col * r.iter + rw] = hist[col * p.o.c.plmaxit + rw]
                rw += 1usize
            }
            col += 1usize
        }
        ret compare(a, c.name, at, g, p.want)
    }
    if str.eq(c.name, "pvr") {
        let ex = p.extra
        let nimp = usize(ex[0usize])
        let nvar = usize(ex[1usize])
        let sz = nimp * nvar
        let (g, e) = mem.alloc[f64](a, 5usize * nvar)
        if e != ok { ret 1usize }
        lf.pvr_confint(ex[2usize..2usize + sz], ex[2usize + sz..2usize + 2usize * sz], ex[2usize + 2usize * sz..2usize + 3usize * sz], nimp, nvar, ex[2usize + 3usize * sz], flag(ex[3usize + 3usize * sz]), g[0usize..nvar], g[nvar..2usize * nvar], g[2usize * nvar..3usize * nvar], g[3usize * nvar..4usize * nvar], g[4usize * nvar..5usize * nvar])
        ret compare(a, c.name, at, g, p.want)
    }
    if str.eq(c.name, "summary") {
        var o = p.o
        let (f, e1) = lf.logistf(a, p.x, p.y, p.n, p.k, p.w, p.off, o)
        if e1 != ok { ret 1usize }
        let (chi, e2) = mem.alloc[f64](a, p.k)
        if e2 != ok { ret 1usize }
        let (sm, e3) = lf.summary_lf(a, f, p.terms[0usize..0usize], chi)
        if e3 != ok { ret 1usize }
        let (aic_df, aic) = lf.extract_aic(f, p.extra[0usize])
        let (g, e4) = mem.alloc[f64](a, p.k + 6usize)
        if e4 != ok { ret 1usize }
        var i = 0usize
        while i < p.k {
            g[i] = chi[i]
            i += 1usize
        }
        g[p.k] = sm.lr
        g[p.k + 1usize] = sm.lr_p
        g[p.k + 2usize] = sm.wald
        g[p.k + 3usize] = sm.wald_p
        g[p.k + 4usize] = aic_df
        g[p.k + 5usize] = aic
        ret compare(a, c.name, at, g, p.want)
    }
    if str.eq(c.name, "forward") {
        let (start, p1, e1) = index_list(a, p.extra, 0usize)
        let (sc, p2, e2) = index_list(a, p.extra, p1)
        if e1 != ok || e2 != ok { ret 1usize }
        let steps = usize(p.extra[p2])
        let slentry = p.extra[p2 + 1usize]
        let plf = flag(p.extra[p2 + 2usize])
        let (s, e3) = lf.forward(a, p.x, p.n, p.y, wv, ov, start, sc, p.o, steps, slentry, plf)
        if e3 != ok { ret 1usize }
        let (g, e4) = sel_flat(a, s, p.k)
        if e4 != ok { ret 1usize }
        ret compare(a, c.name, at, g, p.want)
    }
    if str.eq(c.name, "backward") {
        let (start, p1, e1) = index_list(a, p.extra, 0usize)
        if e1 != ok { ret 1usize }
        let nv = usize(p.extra[p1])
        let facs = p.extra[p1 + 1usize..p1 + 1usize + nv * p.k]
        let q = p1 + 1usize + nv * p.k
        let steps = usize(p.extra[q])
        let slstay = p.extra[q + 1usize]
        let fp = flag(p.extra[q + 2usize])
        let (s, e3) = lf.backward(a, p.x, p.n, p.k, p.y, wv, ov, start, facs, nv, p.o, steps, slstay, fp)
        if e3 != ok { ret 1usize }
        let (g, e4) = sel_flat(a, s, p.k)
        if e4 != ok { ret 1usize }
        ret compare(a, c.name, at, g, p.want)
    }
    if str.eq(c.name, "fit") {
        let (r, e) = lf.logistf(a, p.x, p.y, p.n, p.k, p.w, p.off, p.o)
        if e != ok { ret 1usize }
        let (g, e2) = flat(a, r, p.mask, p.o.pl)
        if e2 != ok { ret 1usize }
        ret compare(a, c.name, at, g, p.want)
    }
    if str.eq(c.name, "flic") {
        var o = p.o
        o.flic = false
        let (r0, e) = lf.logistf(a, p.x, p.y, p.n, p.k, p.w, p.off, o)
        if e != ok { ret 1usize }
        let (r, e1) = lf.flic_fit(a, p.x, p.y, p.n, p.k, p.w, p.off, p.terms[0usize..p.o.terms_fit.len], r0)
        if e1 != ok { ret 1usize }
        let (g, e2) = flat(a, r, p.mask, p.o.pl)
        if e2 != ok { ret 1usize }
        ret compare(a, c.name, at, g, p.want)
    }
    if str.eq(c.name, "flac") {
        let (r, e) = lf.flac(a, p.x, p.y, p.n, p.k, p.w, p.off, p.o)
        if e != ok { ret 1usize }
        let (g, e2) = flat(a, r, p.mask, p.o.pl)
        if e2 != ok { ret 1usize }
        ret compare(a, c.name, at, g, p.want)
    }
    ret 1usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/logistf_full.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let bad = run(a, c, at)
        if bad > 0usize { failures += 1usize }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}

fn assign_u(a: *mem.Arena, v: []const f64) -> []usize {
    let (r, e) = mem.alloc[usize](a, v.len + 1usize)
    var i = 0usize
    while i < v.len {
        r[i] = usize(v[i])
        i += 1usize
    }
    ret r[0usize..v.len]
}
