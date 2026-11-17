// R MuMIn: dredge over the model space of a global lm/glm, model.sel, model.avg (full and conditional averages, adjusted SE, confidence
// intervals, importance, vcov), predict.averaging and get.models, over the fits of e.algo.stat.mumin_fit.
//
// The global model is a design matrix x (n by nt + 1, column-major, column 0 the intercept) whose column t + 1 is term t (an interaction
// is the product column). A model is a bit mask over the terms. The intercept is always in. Marginality: parents[t] is the mask of the terms
// term t depends on (a:b depends on a and b), a model holding t without them is skipped (MuMIn's default subset). Further `subset`
// constraints are Rules over the mask bits (kinds in rule_ok). `fixed` terms are in every model; mlo..mhi bound the number of terms (m.lim).
//
// Rows of a table are sorted by the criterion (stable, like order()), id is MuMIn's row name (the position of the model in the enumeration: the
// bits of id - 1 run over the non-fixed terms in order). Coefficient entries of an absent term are NaN.
//
// Not here: varying, subset expressions beyond Rule, cluster evaluation, models that fail to fit are not skipped (they stop).

use e.algo.stat.mumin_fit as mf
use e.algo.stat.bigglm as bg
use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.mem
use e.os

type Rule = struct { kind: u8, m1: u64, m2: u64 }

type Table = struct { nm: usize, nt: usize, id: []usize, mask: []u64, df: []f64, ll: []f64, ic: []f64, delta: []f64, weight: []f64, nex: usize, extra: []f64, est: []f64, se: []f64, cdf: []f64, raw: []f64, vc: []f64, nobs: f64 }

type Avg = struct { nm: usize, q: usize, w: []f64, coef_full: []f64, coef_cond: []f64, full: []f64, cond: []f64, sw: []f64, nmod: []f64 }

fn popcnt(x: u64) -> usize {
    var c = 0usize
    var v = x
    while v != 0u64 {
        if (v & 1u64) == 1u64 { c += 1usize }
        v = v >> 1u64
    }
    ret c
}

// Rule kinds: 0 forbid all of m1 together (!(a && b)); 1 at least one of m1; 2 all of m1 imply all of m2 (!a | b); 3 at most m2 of m1;
// 4 at least m2 of m1; 5 exactly m2 of m1 (xor for 1); 6 dc(): the terms of m1 in index order are nonincreasing in presence.
fn rule_ok(mask: u64, r: *const Rule) -> bool {
    let c = popcnt(mask & r.m1)
    if r.kind == 0u8 { ret (mask & r.m1) != r.m1 }
    if r.kind == 1u8 { ret (mask & r.m1) != 0u64 }
    if r.kind == 2u8 {
        if (mask & r.m1) == r.m1 { ret (mask & r.m2) == r.m2 }
        ret true
    }
    if r.kind == 3u8 { ret c <= usize(r.m2) }
    if r.kind == 4u8 { ret c >= usize(r.m2) }
    if r.kind == 5u8 { ret c == usize(r.m2) }
    var prev = true
    var t = 0usize
    while t < 64usize {
        if ((r.m1 >> u64(t)) & 1u64) == 1u64 {
            let here = ((mask >> u64(t)) & 1u64) == 1u64
            if here && !prev { ret false }
            prev = here
        }
        t += 1usize
    }
    ret true
}

// the column list of a mask: the intercept then the present terms in order
fn mask_cols(a: *mem.Arena, mask: u64, nt: usize) -> []usize {
    let (c, e) = mem.alloc[usize](a, nt + 2usize)
    if e != ok { os.exit(70) }
    var k = 1usize
    c[0usize] = 0usize
    var t = 0usize
    while t < nt {
        if ((mask >> u64(t)) & 1u64) == 1u64 {
            c[k] = t + 1usize
            k += 1usize
        }
        t += 1usize
    }
    ret c[0usize..k]
}

// get.models for one mask: the refit of that model
fn fit_mask(a: *mem.Arena, x: []const f64, n: usize, nt: usize, mask: u64, y: []const f64, fam: u8) -> mf.Model {
    ret mf.fit_cols(a, x, n, mask_cols(a, mask, nt), y, fam)
}

// extra column kinds: 1 AIC, 2 BIC, 5 Cp, 6 R^2 and 7 adjusted R^2 (r.squaredLR against the intercept-only log likelihood ll0)
fn extra_of(m: *const mf.Model, ll0: f64, kind: u8) -> f64 {
    if kind == 1u8 { ret mf.ic_of(m, 1u8, 1.0f64) }
    if kind == 2u8 { ret mf.ic_of(m, 2u8, 1.0f64) }
    if kind == 5u8 { ret mf.ic_of(m, 5u8, 1.0f64) }
    let nn = f64(m.n)
    let r2 = 1.0f64 - math.exp[f64](0.0f64 - 2.0f64 / nn * (m.ll - ll0))
    if kind == 6u8 { ret r2 }
    ret r2 / (1.0f64 - math.exp[f64](2.0f64 / nn * ll0))
}

// the table of the given fitted models (model.sel on them, or dredge on its enumeration): sorted by the criterion; beta 0 raw coefficients, 1 std.coef, 2 partial.sd
fn build_table(a: *mem.Arena, mods: []const mf.Model, masks: []const u64, ids: []const usize, nt: usize, y: []const f64, ll0: f64, rank: u8, chat: f64, beta: u8, extra: []const u8) -> Table {
    let nm = mods.len
    let q = nt + 1usize
    var t: Table = zero
    t.nm = nm
    t.nt = nt
    t.nex = extra.len
    t.nobs = f64(mods[0usize].n)
    let icu = mf.zalloc(a, nm)
    var i = 0usize
    while i < nm {
        icu[i] = mf.ic_of(&mods[i], rank, chat)
        i += 1usize
    }
    // stable order by the criterion
    let (ord, oe) = mem.alloc[usize](a, nm + 1usize)
    if oe != ok { os.exit(70) }
    i = 0usize
    while i < nm {
        var j = i
        while j > 0usize && icu[ord[j - 1usize]] > icu[i] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = i
        i += 1usize
    }
    let (idv, e1) = mem.alloc[usize](a, nm + 1usize)
    let (mk, e2) = mem.alloc[u64](a, nm + 1usize)
    if e1 != ok || e2 != ok { os.exit(70) }
    t.id = idv[0usize..nm]
    t.mask = mk[0usize..nm]
    t.df = mf.zalloc(a, nm)
    t.ll = mf.zalloc(a, nm)
    t.ic = mf.zalloc(a, nm)
    t.delta = mf.zalloc(a, nm)
    t.weight = mf.zalloc(a, nm)
    t.extra = mf.zalloc(a, nm * extra.len)
    t.est = mf.zalloc(a, nm * q)
    t.se = mf.zalloc(a, nm * q)
    t.cdf = mf.zalloc(a, nm * q)
    t.raw = mf.zalloc(a, nm * q)
    t.vc = mf.zalloc(a, nm * q * q)
    let nan = mf.nan()
    let be = mf.zalloc(a, q)
    let bs = mf.zalloc(a, q)
    var r = 0usize
    while r < nm {
        let s = ord[r]
        let m = &mods[s]
        t.id[r] = ids[s]
        t.mask[r] = masks[s]
        t.df[r] = m.npar
        t.ll[r] = m.ll
        t.ic[r] = icu[s]
        var e = 0usize
        while e < extra.len {
            t.extra[e * nm + r] = extra_of(m, ll0, extra[e])
            e += 1usize
        }
        var j = 0usize
        while j < q * q {
            t.vc[r * q * q + j] = nan
            j += 1usize
        }
        j = 0usize
        while j < q {
            t.est[j * nm + r] = nan
            t.se[j * nm + r] = nan
            t.cdf[j * nm + r] = nan
            t.raw[j * nm + r] = nan
            j += 1usize
        }
        if beta != 0u8 { mf.std_coef(a, m, y, beta == 2u8, be, bs) }
        var c = 0usize
        while c < m.nc {
            let g = m.cols[c]
            t.raw[g * nm + r] = m.coef[c]
            if beta == 0u8 {
                t.est[g * nm + r] = m.coef[c]
                t.se[g * nm + r] = m.se[c]
            } else {
                t.est[g * nm + r] = be[c]
                t.se[g * nm + r] = bs[c]
            }
            t.cdf[g * nm + r] = m.dfres
            var d = 0usize
            while d < m.nc {
                t.vc[r * q * q + m.cols[d] * q + g] = m.vcov[d * m.nc + c]
                d += 1usize
            }
            c += 1usize
        }
        r += 1usize
    }
    var mn = t.ic[0usize]
    i = 0usize
    while i < nm {
        if t.ic[i] < mn { mn = t.ic[i] }
        i += 1usize
    }
    i = 0usize
    while i < nm {
        t.delta[i] = t.ic[i] - mn
        i += 1usize
    }
    mf.crit_weights(t.ic, t.weight)
    ret t
}

// model.sel on models given by their masks (refit); ids are 1..m
fn model_sel(a: *mem.Arena, x: []const f64, n: usize, nt: usize, masks: []const u64, y: []const f64, fam: u8, rank: u8, chat: f64, beta: u8, extra: []const u8) -> Table {
    let (ms, me) = mem.alloc[mf.Model](a, masks.len + 1usize)
    let (ids, ie) = mem.alloc[usize](a, masks.len + 1usize)
    if me != ok || ie != ok { os.exit(70) }
    var i = 0usize
    while i < masks.len {
        ms[i] = fit_mask(a, x, n, nt, masks[i], y, fam)
        ids[i] = i + 1usize
        i += 1usize
    }
    let m0 = fit_mask(a, x, n, nt, 0u64, y, fam)
    ret build_table(a, ms[0usize..masks.len], masks, ids[0usize..masks.len], nt, y, m0.ll, rank, chat, beta, extra)
}

fn dredge(a: *mem.Arena, x: []const f64, n: usize, nt: usize, y: []const f64, fam: u8, fixed: u64, mlo: usize, mhi0: usize, parents: []const u64, rules: []const Rule, rank: u8, chat: f64, beta: u8, extra: []const u8) -> Table {
    var mhi = mhi0
    if mhi > nt { mhi = nt }
    let (nf, nfe) = mem.alloc[usize](a, nt + 1usize)
    if nfe != ok { os.exit(70) }
    var nov = 0usize
    var t = 0usize
    while t < nt {
        if ((fixed >> u64(t)) & 1u64) == 0u64 {
            nf[nov] = t
            nov += 1usize
        }
        t += 1usize
    }
    let total = 1usize << nov
    let (ms, me) = mem.alloc[mf.Model](a, total + 1usize)
    let (mk, ke) = mem.alloc[u64](a, total + 1usize)
    let (ids, ie) = mem.alloc[usize](a, total + 1usize)
    if me != ok || ke != ok || ie != ok { os.exit(70) }
    var k = 0usize
    var jc = 0usize
    while jc < total {
        var mask = fixed
        var b = 0usize
        while b < nov {
            if ((jc >> b) & 1usize) == 1usize { mask = mask | (1u64 << u64(nf[b])) }
            b += 1usize
        }
        var ok1 = true
        let nvar = popcnt(mask)
        if nvar > mhi || nvar < mlo { ok1 = false }
        t = 0usize
        while ok1 && t < nt {
            if ((mask >> u64(t)) & 1u64) == 1u64 && (parents[t] & mask) != parents[t] { ok1 = false }
            t += 1usize
        }
        var ri = 0usize
        while ok1 && ri < rules.len {
            if !rule_ok(mask, &rules[ri]) { ok1 = false }
            ri += 1usize
        }
        if ok1 {
            ms[k] = fit_mask(a, x, n, nt, mask, y, fam)
            mk[k] = mask
            ids[k] = jc + 1usize
            k += 1usize
        }
        jc += 1usize
    }
    if k == 0usize { os.exit(74) }
    let m0 = fit_mask(a, x, n, nt, 0u64, y, fam)
    ret build_table(a, ms[0usize..k], mk[0usize..k], ids[0usize..k], nt, y, m0.ll, rank, chat, beta, extra)
}

// the rows of a table with delta < cutoff (subset = delta < cutoff); answers how many
fn rows_delta(t: *const Table, cutoff: f64, rows: []usize) -> usize {
    var k = 0usize
    var i = 0usize
    while i < t.nm {
        if t.delta[i] < cutoff {
            rows[k] = i
            k += 1usize
        }
        i += 1usize
    }
    ret k
}

fn qt_or_norm(p: f64, df: f64) -> f64 {
    if df > 1.0e300f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, true, false) }
    ret nb.qt(p, df, true, false)
}

// par.avg over the selected rows for coefficient column j: out = (Coefficient, SE, Adjusted SE, Lower CI, Upper CI); full true treats an absent term as estimate 0 with variance 0
fn par_avg(t: *const Table, rows: []const usize, w: []const f64, j: usize, full: bool, revised: bool, level: f64, out: []f64) {
    let nm = t.nm
    let a2 = 1.0f64 - (1.0f64 - level) / 2.0f64
    let zq = dist.qnorm(a2, 0.0f64, 1.0f64, true, false)
    var sw = 0.0f64
    var swx = 0.0f64
    var i = 0usize
    while i < rows.len {
        let r = rows[i]
        var xv = t.est[j * nm + r]
        var present = !mf.is_nan(xv)
        if full && !present {
            xv = 0.0f64
            present = true
        }
        if present {
            sw += w[i]
            swx += w[i] * xv
        }
        i += 1usize
    }
    let wx = swx / sw
    var vu = 0.0f64
    var va = 0.0f64
    i = 0usize
    while i < rows.len {
        let r = rows[i]
        var xv = t.est[j * nm + r]
        var sev = t.se[j * nm + r]
        var dfv = t.cdf[j * nm + r]
        var present = !mf.is_nan(xv)
        if full && !present {
            xv = 0.0f64
            sev = 0.0f64
            dfv = 1.0e308f64
            present = true
        }
        if present {
            let sq = (xv - wx) * (xv - wx)
            let zz = qt_or_norm(a2, dfv) / zq
            if revised {
                vu += w[i] * (sev * sev + sq)
                va += w[i] * (sev * sev * zz * zz + sq)
            } else {
                vu += w[i] * math.sqrt[f64](sev * sev + sq)
                va += w[i] * math.sqrt[f64](sev * sev * zz * zz + sq)
            }
        }
        i += 1usize
    }
    var usd = vu / sw
    var ase = va / sw
    if revised {
        usd = math.sqrt[f64](usd)
        ase = math.sqrt[f64](ase)
    }
    out[0usize] = wx
    out[1usize] = usd
    out[2usize] = ase
    out[3usize] = wx - zq * ase
    out[4usize] = wx + zq * ase
}

// model.avg of the selected rows (weights recomputed over them): per coefficient column the full and the conditional par.avg, and the sum of weights (sw) of each term
fn model_avg(a: *mem.Arena, t: *const Table, rows: []const usize, revised: bool, level: f64) -> Avg {
    let q = t.nt + 1usize
    var av: Avg = zero
    av.nm = rows.len
    av.q = q
    let ic = mf.zalloc(a, rows.len)
    var i = 0usize
    while i < rows.len {
        ic[i] = t.ic[rows[i]]
        i += 1usize
    }
    av.w = mf.zalloc(a, rows.len)
    mf.crit_weights(ic, av.w)
    av.full = mf.zalloc(a, 5usize * q)
    av.cond = mf.zalloc(a, 5usize * q)
    av.coef_full = mf.zalloc(a, q)
    av.coef_cond = mf.zalloc(a, q)
    av.sw = mf.zalloc(a, q)
    av.nmod = mf.zalloc(a, q)
    let tmp = mf.zalloc(a, 5usize)
    var j = 0usize
    while j < q {
        par_avg(t, rows, av.w, j, true, revised, level, tmp)
        var k = 0usize
        while k < 5usize {
            av.full[j * 5usize + k] = tmp[k]
            k += 1usize
        }
        av.coef_full[j] = tmp[0usize]
        var cnt = 0usize
        var sws = 0.0f64
        i = 0usize
        while i < rows.len {
            if !mf.is_nan(t.est[j * t.nm + rows[i]]) {
                cnt += 1usize
                sws += av.w[i]
            }
            i += 1usize
        }
        av.sw[j] = sws
        av.nmod[j] = f64(cnt)
        if cnt == 0usize {
            k = 0usize
            while k < 5usize {
                av.cond[j * 5usize + k] = mf.nan()
                k += 1usize
            }
            av.coef_cond[j] = mf.nan()
        } else {
            par_avg(t, rows, av.w, j, false, revised, level, tmp)
            k = 0usize
            while k < 5usize {
                av.cond[j * 5usize + k] = tmp[k]
                k += 1usize
            }
            av.coef_cond[j] = tmp[0usize]
        }
        j += 1usize
    }
    ret av
}

// vcov.averaging (full or conditional) into out (q by q, column-major)
fn avg_vcov(t: *const Table, rows: []const usize, av: *const Avg, full: bool, out: []f64) {
    let q = av.q
    let nm = t.nm
    var c1 = 0usize
    while c1 < q {
        var c2 = 0usize
        while c2 < q {
            var sw = 0.0f64
            var s = 0.0f64
            var i = 0usize
            while i < rows.len {
                let r = rows[i]
                var b1 = t.raw[c1 * nm + r]
                var b2 = t.raw[c2 * nm + r]
                var v = t.vc[r * q * q + c2 * q + c1]
                var avg1 = av.coef_cond[c1]
                var avg2 = av.coef_cond[c2]
                if full {
                    if mf.is_nan(b1) { b1 = 0.0f64 }
                    if mf.is_nan(b2) { b2 = 0.0f64 }
                    if mf.is_nan(v) { v = 0.0f64 }
                    avg1 = av.coef_full[c1]
                    avg2 = av.coef_full[c2]
                }
                let term = v + (b1 - avg1) * (b2 - avg2)
                if !mf.is_nan(term) {
                    sw += av.w[i]
                    s += av.w[i] * term
                }
                i += 1usize
            }
            out[c2 * q + c1] = s / sw
            c2 += 1usize
        }
        c1 += 1usize
    }
}

// predict.averaging for a link-scale prediction from the averaged coefficients (full or conditional) at newx (n2 by q)
fn predict_coef(av: *const Avg, newx: []const f64, n2: usize, full: bool, out: []f64) {
    var i = 0usize
    while i < n2 {
        var s = 0.0f64
        var j = 0usize
        while j < av.q {
            if full { s += newx[j * n2 + i] * av.coef_full[j] }
            if !full && !mf.is_nan(av.coef_cond[j]) { s += newx[j * n2 + i] * av.coef_cond[j] }
            j += 1usize
        }
        out[i] = s
        i += 1usize
    }
}

// predict.averaging through the component models: each model predicts (link scale, or the response scale when resp), with its standard error when se_fit; the predictions are averaged
// by the weights (par.avg without df when se_fit, a weighted mean otherwise); backtransform maps an averaged link prediction through the inverse link.
// fit and se receive n2 values each (se untouched unless se_fit).
fn predict_models(a: *mem.Arena, t: *const Table, rows: []const usize, av: *const Avg, newx: []const f64, n2: usize, fam: u8, resp: bool, se_fit: bool, backtransform: bool, revised: bool, fit: []f64, se: []f64) {
    let q = av.q
    let nm = t.nm
    let fb = mf.base_fam(fam)
    let fl = mf.zalloc(a, rows.len)
    let sl = mf.zalloc(a, rows.len)
    var i = 0usize
    while i < n2 {
        var r = 0usize
        while r < rows.len {
            let row = rows[r]
            var eta = 0.0f64
            var v = 0.0f64
            var j = 0usize
            while j < q {
                if !mf.is_nan(t.raw[j * nm + row]) {
                    eta += newx[j * n2 + i] * t.raw[j * nm + row]
                    var k = 0usize
                    while k < q {
                        if !mf.is_nan(t.raw[k * nm + row]) { v += newx[j * n2 + i] * t.vc[row * q * q + k * q + j] * newx[k * n2 + i] }
                        k += 1usize
                    }
                }
                j += 1usize
            }
            var s = math.sqrt[f64](v)
            var f = eta
            if resp && fam != 200u8 {
                f = bg.linkinv(fb, eta)
                var me = bg.mu_eta(fb, eta)
                if me < 0.0f64 { me = 0.0f64 - me }
                s = s * me
            }
            fl[r] = f
            sl[r] = s
            r += 1usize
        }
        var sw = 0.0f64
        var swf = 0.0f64
        var r2 = 0usize
        while r2 < rows.len {
            sw += av.w[r2]
            swf += av.w[r2] * fl[r2]
            r2 += 1usize
        }
        let wf = swf / sw
        if !se_fit {
            fit[i] = wf
        } else {
            var vsum = 0.0f64
            r2 = 0usize
            while r2 < rows.len {
                let sq = (fl[r2] - wf) * (fl[r2] - wf)
                if revised { vsum += av.w[r2] * (sl[r2] * sl[r2] + sq) } else { vsum += av.w[r2] * math.sqrt[f64](sl[r2] * sl[r2] + sq) }
                r2 += 1usize
            }
            var sd = vsum / sw
            if revised { sd = math.sqrt[f64](sd) }
            fit[i] = wf
            se[i] = sd
            if backtransform && fam != 200u8 {
                var me = bg.mu_eta(fb, wf)
                if me < 0.0f64 { me = 0.0f64 - me }
                fit[i] = bg.linkinv(fb, wf)
                se[i] = sd * me
            }
        }
        if !se_fit && backtransform && fam != 200u8 { fit[i] = bg.linkinv(fb, wf) }
        i += 1usize
    }
}
