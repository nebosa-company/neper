// R MASS stepAIC, addterm and dropterm for lm and for glm fits (Poisson log, binomial logit, negative binomial log through glm.nb), with term groups
// (factor dummies, interactions) under marginality, a scope with lower and upper formulas, the penalty k, the scale, a step limit, and the F and Chisq tests.
//
// The model is described by its largest design: x is n by p column-major, column 0 the intercept, assign[j] the term (1 .. nt) of column j, vmask[t - 1] the bit set of the
// variables in term t (marginality: s is contained in t when its bits are a subset of t's). Terms are numbered in the upper formula's order (by degree, then appearance).
// fam 0 lm, 1 Poisson, 2 binomial, 3 negative binomial.

use e.algo.linalg.decomp as decomp
use e.algo.stat.massnb as nb
use e.math
use e.math.nmath as nm
use e.math.nmath_beta as nbeta
use e.mem

error BadInput

type Spec = struct { n: usize, p: usize, x: []const f64, assign: []const usize, nt: usize, vmask: []const f64, y: []const f64, fam: usize, scale: f64, k: f64 }

type Fr = struct { rank: usize, dev: f64, aic: f64, theta: f64 }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn bits(v: f64) -> u64 { ret u64(v) }

fn popcount(v: u64) -> usize {
    var c = 0usize
    var x = v
    while x != 0u64 {
        c += usize(x & 1u64)
        x = x >> 1u64
    }
    ret c
}

// the design with the columns of the terms in `inm` (term t - 1 -> inm[t - 1]) and the intercept
fn design(a: *mem.Arena, sp: *const Spec, inm: []const bool) -> ([]f64, usize, err) {
    var cols = 0usize
    var j = 0usize
    while j < sp.p {
        if sp.assign[j] == 0usize || inm[sp.assign[j] - 1usize] { cols += 1usize }
        j += 1usize
    }
    let (xs, e) = mem.alloc[f64](a, sp.n * cols + 1usize)
    if e != ok { ret (xs, 0usize, e) }
    var c = 0usize
    j = 0usize
    while j < sp.p {
        if sp.assign[j] == 0usize || inm[sp.assign[j] - 1usize] {
            var i = 0usize
            while i < sp.n {
                xs[i + sp.n * c] = sp.x[i + sp.n * j]
                i += 1usize
            }
            c += 1usize
        }
        j += 1usize
    }
    ret (xs, cols, ok)
}

// the family aic of glm.fit for the unit-weight fit, plus 2 rank
fn fam_aic(fam: usize, y: []const f64, mu: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < y.len {
        if fam == 1usize { s += nm.dpois(y[i], mu[i], true) }
        if fam == 2usize { s += y[i] * math.log[f64](mu[i]) + (1.0f64 - y[i]) * math.log[f64](1.0f64 - mu[i]) }
        i += 1usize
    }
    ret 0.0f64 - 2.0f64 * s
}

// the fit of the model `inm` and its extractAIC(fit, scale, k)
fn fit_set(a: *mem.Arena, sp: *const Spec, inm: []const bool) -> (Fr, err) {
    var out: Fr = zero
    let (xs, cols, de) = design(a, sp, inm)
    if de != ok { ret (out, de) }
    let n = sp.n
    let nf = f64(n)
    if sp.fam == 0usize {
        let (f, fe) = decomp.lm_fit(a, xs, n, cols, sp.y, 1.0e-7f64)
        if fe != ok { ret (out, fe) }
        var rss = 0.0f64
        var i = 0usize
        while i < n {
            rss += f.residuals[i] * f.residuals[i]
            i += 1usize
        }
        out.rank = f.rank
        out.dev = rss
        if sp.scale > 0.0f64 { out.aic = rss / sp.scale - nf + sp.k * f64(f.rank) } else { out.aic = nf * math.log[f64](rss / nf) + sp.k * f64(f.rank) }
        ret (out, ok)
    }
    let (w, we) = mem.alloc[f64](a, n)
    let (off, oe) = mem.alloc[f64](a, n)
    if we != ok || oe != ok { ret (out, mem.Full) }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        off[i] = 0.0f64
        i += 1usize
    }
    if sp.fam == 3usize {
        let (r, e) = nb.glm_nb(a, xs, n, cols, sp.y, w, off, 0usize, nan(), 25usize, 1.0e-8f64, true, false)
        if e != ok { ret (out, e) }
        out.rank = r.fit.rank
        out.dev = r.fit.dev
        out.theta = r.theta
        out.aic = sp.k * f64(r.fit.rank) - r.twologlik
        ret (out, ok)
    }
    var fam = 0usize
    var link = 0usize
    if sp.fam == 2usize {
        fam = 2usize
        link = 3usize
    }
    let (g, ge) = nb.glm_fit(a, xs, n, cols, sp.y, w, off, false, off, fam, 1.0f64, link, 1.0e-8f64, 25usize, true)
    if ge != ok { ret (out, ge) }
    out.rank = g.rank
    out.dev = g.dev
    out.aic = fam_aic(sp.fam, sp.y, g.mu) + 2.0f64 * f64(g.rank) + (sp.k - 2.0f64) * f64(g.rank)
    ret (out, ok)
}

type Tab = struct { m: usize, df: []f64, dev: []f64, aic: []f64, sumsq: []f64, stat: []f64, p: []f64, rdf: f64 }

// the single-term table of dropterm (adding false) or addterm (adding true) over the candidate terms `cand` (term indices, 1-based): row 0 is <none>.
// test 0 none, 1 Chisq, 2 F; stat is the F value or the LRT, p the matching P value (NaN when absent)
fn table(a: *mem.Arena, sp: *const Spec, inm: []const bool, cand: []const usize, adding: bool, test: usize) -> (Tab, err) {
    var tb: Tab = zero
    let m = cand.len + 1usize
    let (df, e1) = mem.alloc[f64](a, m)
    let (dev, e2) = mem.alloc[f64](a, m)
    let (aic, e3) = mem.alloc[f64](a, m)
    let (ss, e4) = mem.alloc[f64](a, m)
    let (st, e5) = mem.alloc[f64](a, m)
    let (pp, e6) = mem.alloc[f64](a, m)
    let (rk, e7) = mem.alloc[f64](a, m)
    let (cur, e8) = mem.alloc[bool](a, sp.nt)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (tb, mem.Full) }
    let (f0, fe0) = fit_set(a, sp, inm)
    if fe0 != ok { ret (tb, fe0) }
    let n = f64(sp.n)
    rk[0usize] = f64(f0.rank)
    dev[0usize] = f0.dev
    aic[0usize] = f0.aic
    var i = 0usize
    while i < cand.len {
        var t = 0usize
        while t < sp.nt {
            cur[t] = inm[t]
            t += 1usize
        }
        cur[cand[i] - 1usize] = adding
        let mk = mem.mark(a)
        let (fi, fe) = fit_set(a, sp, cur)
        mem.reset(a, mk)
        if fe != ok {
            rk[i + 1usize] = nan()
            dev[i + 1usize] = nan()
            aic[i + 1usize] = nan()
        } else {
            rk[i + 1usize] = f64(fi.rank)
            dev[i + 1usize] = fi.dev
            aic[i + 1usize] = fi.aic
        }
        i += 1usize
    }
    // Df, and the AIC column as addterm / dropterm define it
    let rdf = n - rk[0usize]
    var disp = 1.0f64
    if sp.scale > 0.0f64 { disp = sp.scale }
    i = 0usize
    while i < m {
        if i == 0usize { df[0usize] = nan() } else if adding { df[i] = rk[i] - rk[0usize] } else { df[i] = rk[0usize] - rk[i] }
        i += 1usize
    }
    if sp.fam == 0usize {
        // dropterm.lm / addterm.lm: the aic recomputed from the RSS and the rank
        i = 0usize
        while i < m {
            if sp.scale > 0.0f64 { aic[i] = dev[i] / sp.scale - n + sp.k * rk[i] } else { aic[i] = n * math.log[f64](dev[i] / n) + sp.k * rk[i] }
            i += 1usize
        }
    } else if sp.fam != 3usize {
        // dropterm.glm / addterm.glm: dev / dispersion + k * rank, moved to the baseline of extractAIC
        var l0 = 0.0f64
        i = 0usize
        while i < m {
            let ll = dev[i] / disp + sp.k * rk[i]
            if i == 0usize { l0 = ll }
            aic[i] = ll
            i += 1usize
        }
        let shift = f0.aic - l0
        i = 0usize
        while i < m {
            aic[i] = aic[i] + shift
            i += 1usize
        }
    }
    i = 0usize
    while i < m {
        ss[i] = nan()
        st[i] = nan()
        pp[i] = nan()
        i += 1usize
    }
    if sp.fam == 0usize {
        i = 1usize
        while i < m {
            if adding { ss[i] = dev[0usize] - dev[i] } else { ss[i] = dev[i] - dev[0usize] }
            i += 1usize
        }
        if test == 1usize {
            i = 1usize
            while i < m {
                var d = ss[i] / sp.scale
                if adding {
                    if sp.scale == 0.0f64 { d = n * math.log[f64](dev[0usize] / n) - n * math.log[f64](dev[i] / n) } else { d = ss[i] / sp.scale }
                }
                if df[i] > 0.0f64 { pp[i] = nm.pchisq(d, df[i], false, false) }
                i += 1usize
            }
        }
        if test == 2usize {
            i = 1usize
            while i < m {
                var f = 0.0f64
                if adding { f = (ss[i] / df[i]) / ((dev[0usize] - ss[i]) / (rdf - df[i])) } else { f = (ss[i] / df[i]) / (dev[0usize] / rdf) }
                if df[i] < 0.0001f64 { f = nan() }
                st[i] = f
                if f == f {
                    if adding { pp[i] = nbeta.pf(f, df[i], rdf - df[i], false, false) } else { pp[i] = nbeta.pf(f, df[i], rdf, false, false) }
                }
                i += 1usize
            }
        }
    } else if sp.fam != 3usize {
        i = 1usize
        while i < m {
            var d = (dev[0usize] - dev[i]) / disp
            if !adding { d = (dev[i] - dev[0usize]) / disp }
            if d < 0.0f64 { d = 0.0f64 }
            if test == 1usize {
                st[i] = d
                if df[i] > 0.0f64 { pp[i] = nm.pchisq(d, df[i], false, false) }
            }
            if test == 2usize {
                var f = 0.0f64
                if adding {
                    var diff = (dev[0usize] - dev[i]) / df[i]
                    if diff < 0.0f64 { diff = 0.0f64 }
                    f = diff / (dev[i] / (rdf - df[i]))
                    if df[i] < 2.220446049250313e-16f64 { f = nan() }
                } else {
                    var dd = dev[i] - dev[0usize]
                    if dd < 0.0f64 { dd = 0.0f64 }
                    f = (dd / df[i]) / (dev[0usize] / rdf)
                    if df[i] < 0.0001f64 { f = nan() }
                }
                st[i] = f
                if f == f && df[i] > 0.0f64 {
                    if adding { pp[i] = nbeta.pf(f, df[i], rdf - df[i], false, false) } else { pp[i] = nbeta.pf(f, df[i], rdf, false, false) }
                }
            }
            i += 1usize
        }
    } else if test == 1usize {
        // dropterm.negbin / addterm.negbin are the default methods: refits, and the LRT from the aic minus k * edf
        let d0 = aic[0usize] - sp.k * rk[0usize]
        i = 1usize
        while i < m {
            var d = (aic[i] - sp.k * rk[i]) - d0
            if adding { d = d0 - (aic[i] - sp.k * rk[i]) }
            st[i] = d
            if df[i] > 0.0f64 { pp[i] = nm.pchisq(d, df[i], false, false) }
            i += 1usize
        }
    }
    tb = Tab { m: m, df: df, dev: dev, aic: aic, sumsq: ss, stat: st, p: pp, rdf: rdf }
    ret (tb, ok)
}

fn nterm_deg(sp: *const Spec, t: usize) -> usize { ret popcount(bits(sp.vmask[t - 1usize])) }

// factor.scope's drop list: the model terms (in model order) outside `lower`, minus those contained in another of those terms
fn drop_scope(sp: *const Spec, ord: []const usize, nord: usize, lower: []const bool, a: *mem.Arena) -> ([]usize, usize, err) {
    let (c, e) = mem.alloc[usize](a, nord + 1usize)
    if e != ok { ret (c, 0usize, e) }
    var m = 0usize
    var i = 0usize
    while i < nord {
        if !lower[ord[i] - 1usize] {
            var keep = true
            let vi = bits(sp.vmask[ord[i] - 1usize])
            var j = 0usize
            while j < nord {
                if j != i && !lower[ord[j] - 1usize] {
                    let vj = bits(sp.vmask[ord[j] - 1usize])
                    if (vi & vj) == vi { keep = false }
                }
                j += 1usize
            }
            if keep {
                c[m] = ord[i]
                m += 1usize
            }
        }
        i += 1usize
    }
    ret (c, m, ok)
}

// factor.scope's add list: the upper terms not in the model, minus those that contain another such term
fn add_scope(sp: *const Spec, inm: []const bool, upper: []const bool, a: *mem.Arena) -> ([]usize, usize, err) {
    let (c, e) = mem.alloc[usize](a, sp.nt + 1usize)
    if e != ok { ret (c, 0usize, e) }
    var m = 0usize
    var t = 1usize
    while t <= sp.nt {
        if upper[t - 1usize] && !inm[t - 1usize] {
            var keep = true
            let vt = bits(sp.vmask[t - 1usize])
            var u = 1usize
            while u <= sp.nt {
                if u != t && upper[u - 1usize] && !inm[u - 1usize] {
                    let vu = bits(sp.vmask[u - 1usize])
                    if (vu & vt) == vu { keep = false }
                }
                u += 1usize
            }
            if keep {
                c[m] = t
                m += 1usize
            }
        }
        t += 1usize
    }
    ret (c, m, ok)
}

// the model terms in terms() order: by degree, then by when they entered
fn sort_by_degree(sp: *const Spec, ord: []usize, nord: usize) {
    var i = 1usize
    while i < nord {
        let t = ord[i]
        var j = i
        while j > 0usize && nterm_deg(sp, ord[j - 1usize]) > nterm_deg(sp, t) {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = t
        i += 1usize
    }
}

// stepAIC. start lists the terms of the start model in terms() order (1-based), lower / upper flag the scope terms (all false / the start terms when there is no scope).
// out: 0 final extractAIC, 1 its edf, 2 models in the path, 3 sum of (step number) * (signed term: + added, - dropped), 4 sum of the path deviances, 5 sum of the path AICs.
// final_in receives the final model's terms.
fn step_aic(a: *mem.Arena, sp: *const Spec, start: []const usize, lower: []const bool, upper: []const bool, backward: bool, forward: bool, steps_in: usize, out: []f64, final_in: []bool) -> err {
    let (ord, e1) = mem.alloc[usize](a, sp.nt + 1usize)
    let (inm, e2) = mem.alloc[bool](a, sp.nt)
    if e1 != ok || e2 != ok { ret mem.Full }
    var nord = start.len
    var t = 0usize
    while t < sp.nt {
        inm[t] = false
        t += 1usize
    }
    var i = 0usize
    while i < nord {
        ord[i] = start[i]
        inm[start[i] - 1usize] = true
        i += 1usize
    }
    let (f0, fe) = fit_set(a, sp, inm)
    if fe != ok { ret fe }
    var bic = f0.aic
    var edf = f64(f0.rank)
    out[2usize] = 1.0f64
    out[3usize] = 0.0f64
    out[4usize] = f0.dev
    out[5usize] = bic
    var nm_ = 1usize
    var steps = steps_in
    while steps > 0usize {
        steps -= 1usize
        let aic0 = bic
        let mk = mem.mark(a)
        let (dc, nd, de) = drop_scope(sp, ord, nord, lower, a)
        let (ac, na, ae) = add_scope(sp, inm, upper, a)
        if de != ok || ae != ok { ret mem.Full }
        // rows: <none>, the drops, the adds
        let total = 1usize + nd + na
        let (raic, re1) = mem.alloc[f64](a, total)
        let (rdf, re2) = mem.alloc[f64](a, total)
        let (rterm, re3) = mem.alloc[i64](a, total)
        if re1 != ok || re2 != ok || re3 != ok { ret mem.Full }
        var have_none = false
        var change = 0i64
        var zero_df = false
        if backward && nd > 0usize {
            let (tb, te) = table(a, sp, inm, dc[0usize..nd], false, 0usize)
            if te != ok { ret te }
            raic[0usize] = tb.aic[0usize]
            rdf[0usize] = nan()
            rterm[0usize] = 0i64
            have_none = true
            var r = 1usize
            while r <= nd {
                raic[r] = tb.aic[r]
                rdf[r] = tb.df[r]
                rterm[r] = 0i64 - i64(dc[r - 1usize])
                if tb.df[r] == 0.0f64 {
                    zero_df = true
                    change = rterm[r]
                }
                r += 1usize
            }
        }
        var rows = 0usize
        if have_none { rows = 1usize + nd }
        if !zero_df {
            if forward && na > 0usize {
                let (tb, te) = table(a, sp, inm, ac[0usize..na], true, 0usize)
                if te != ok { ret te }
                var r = 0usize
                if !have_none {
                    raic[0usize] = tb.aic[0usize]
                    rdf[0usize] = nan()
                    rterm[0usize] = 0i64
                    have_none = true
                    rows = 1usize
                }
                r = 1usize
                while r <= na {
                    raic[rows] = tb.aic[r]
                    rdf[rows] = tb.df[r]
                    rterm[rows] = i64(ac[r - 1usize])
                    rows += 1usize
                    r += 1usize
                }
            }
            if !have_none { break }
            // order(aic) over the rows with nonzero df (or NA df): the first minimum, ties to the earlier row
            var best = 0usize
            var r = 1usize
            while r < rows {
                if rdf[r] != 0.0f64 && raic[r] < raic[best] { best = r }
                r += 1usize
            }
            if best == 0usize { break }
            change = rterm[best]
        }
        // update the model by the change
        var tt = change
        if change < 0i64 { tt = 0i64 - change }
        let term = usize(tt)
        let (hist, he) = mem.alloc[bool](a, sp.nt)
        if he != ok { ret he }
        t = 0usize
        while t < sp.nt {
            hist[t] = inm[t]
            t += 1usize
        }
        hist[term - 1usize] = change > 0i64
        let (fn_, fe2) = fit_set(a, sp, hist)
        if fe2 != ok { ret fe2 }
        if fn_.aic >= aic0 + 0.0000001f64 { break }
        // commit
        if change > 0i64 {
            ord[nord] = term
            nord += 1usize
            sort_by_degree(sp, ord, nord)
            inm[term - 1usize] = true
        } else {
            var w = 0usize
            i = 0usize
            while i < nord {
                if ord[i] != term {
                    ord[w] = ord[i]
                    w += 1usize
                }
                i += 1usize
            }
            nord = w
            inm[term - 1usize] = false
        }
        bic = fn_.aic
        edf = f64(fn_.rank)
        nm_ += 1usize
        out[3usize] += f64(nm_ - 1usize) * f64(change)
        out[4usize] += fn_.dev
        out[5usize] += bic
        // the step's scratch is released; ord and inm live in the outer arena region
        let _ = mk
    }
    out[0usize] = bic
    out[1usize] = edf
    out[2usize] = f64(nm_)
    t = 0usize
    while t < sp.nt {
        final_in[t] = inm[t]
        t += 1usize
    }
    ret ok
}
