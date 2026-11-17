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
use e.str

type Rule = struct { kind: u8, m1: u64, m2: u64 }

type Table = struct { nm: usize, nt: usize, id: []usize, mask: []u64, df: []f64, ll: []f64, ic: []f64, delta: []f64, weight: []f64, nex: usize, extra: []f64, est: []f64, se: []f64, cdf: []f64, raw: []f64, vc: []f64, nobs: f64, ndim: usize, vv: []usize }

// the fitting configuration: family, theta of fam 9, prior weights and offset (empty: none), and the alternative weight and offset arrays varying picks from (n each, option k is array k - 1)
type Spec = struct { fam: u8, theta: f64, wt: []const f64, off: []const f64, altw: []const f64, alto: []const f64 }

// one option of a varying dimension: kind 0 sets the family, 1 theta, 2 the weights (arr = 0 none, else the alternative array), 3 the offset
type Opt = struct { dim: usize, kind: u8, fam: u8, theta: f64, arr: usize }

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
fn fit_spec(a: *mem.Arena, x: []const f64, n: usize, nt: usize, mask: u64, y: []const f64, sp: *const Spec) -> mf.Model {
    ret mf.fit_ext(a, x, n, mask_cols(a, mask, nt), y, sp.fam, sp.wt, sp.off, sp.theta)
}

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
fn build_table(a: *mem.Arena, mods: []const mf.Model, masks: []const u64, ids: []const usize, nt: usize, y: []const f64, ll0: f64, rank: u8, chat: f64, beta: u8, extra: []const u8, ndim: usize, vcodes: []const usize) -> Table {
    let nm = mods.len
    let q = nt + 1usize
    var t: Table = zero
    t.nm = nm
    t.nt = nt
    t.nex = extra.len
    t.nobs = f64(mods[0usize].n)
    t.ndim = ndim
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
    let (vvv, vve) = mem.alloc[usize](a, nm * ndim + 1usize)
    if vve != ok { os.exit(70) }
    t.vv = vvv[0usize..nm * ndim]
    let nan = mf.nan()
    let be = mf.zalloc(a, q)
    let bs = mf.zalloc(a, q)
    var r = 0usize
    while r < nm {
        let s = ord[r]
        let m = &mods[s]
        t.id[r] = ids[s]
        t.mask[r] = masks[s]
        var vq = 0usize
        while vq < ndim {
            t.vv[r * ndim + vq] = vcodes[s * ndim + vq]
            vq += 1usize
        }
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

// model.sel on models given by their masks (refit under spec sp); ids are 1..m
fn model_sel(a: *mem.Arena, x: []const f64, n: usize, nt: usize, masks: []const u64, y: []const f64, sp: *const Spec, rank: u8, chat: f64, beta: u8, extra: []const u8) -> Table {
    let (ms, me) = mem.alloc[mf.Model](a, masks.len + 1usize)
    let (ids, ie) = mem.alloc[usize](a, masks.len + 1usize)
    if me != ok || ie != ok { os.exit(70) }
    var i = 0usize
    while i < masks.len {
        ms[i] = fit_spec(a, x, n, nt, masks[i], y, sp)
        ids[i] = i + 1usize
        i += 1usize
    }
    let m0 = fit_spec(a, x, n, nt, 0u64, y, sp)
    ret build_table(a, ms[0usize..masks.len], masks, ids[0usize..masks.len], nt, y, m0.ll, rank, chat, beta, extra, 0usize, zero_usize(a))
}

fn zero_usize(a: *mem.Arena) -> []usize {
    let (b, e) = mem.alloc[usize](a, 1usize)
    if e != ok { os.exit(70) }
    ret b[0usize..0usize]
}

// --- subset expressions: ! && & || | ( ) term names (letters, digits, . _ :), TRUE FALSE, dc(a, b, ...) (presence nonincreasing), xor(a, b), sum(a, b, ...) with a comparison and a number

type Parser = struct { s: str, at: usize, names: []const str, mask: u64, bad: bool }

fn is_ident(c: u8) -> bool {
    if c >= 97u8 && c <= 122u8 { ret true }
    if c >= 65u8 && c <= 90u8 { ret true }
    if c >= 48u8 && c <= 57u8 { ret true }
    ret c == 46u8 || c == 95u8 || c == 58u8
}

fn skip_ws(p: *Parser) {
    while p.at < p.s.len && p.s[p.at] == 32u8 { p.at += 1usize }
}

fn peek(p: *Parser) -> u8 {
    skip_ws(p)
    if p.at >= p.s.len { ret 0u8 }
    ret p.s[p.at]
}

fn parse_or(p: *Parser) -> bool {
    var v = parse_and(p)
    while peek(p) == 124u8 {
        p.at += 1usize
        if peek(p) == 124u8 { p.at += 1usize }
        let w = parse_and(p)
        v = v || w
    }
    ret v
}

fn parse_and(p: *Parser) -> bool {
    var v = parse_not(p)
    while peek(p) == 38u8 {
        p.at += 1usize
        if peek(p) == 38u8 { p.at += 1usize }
        let w = parse_not(p)
        v = v && w
    }
    ret v
}

fn parse_not(p: *Parser) -> bool {
    let c = peek(p)
    if c == 33u8 {
        p.at += 1usize
        let v = parse_not(p)
        ret !v
    }
    if c == 40u8 {
        p.at += 1usize
        let v = parse_or(p)
        if peek(p) == 41u8 { p.at += 1usize } else { p.bad = true }
        ret v
    }
    skip_ws(p)
    let st = p.at
    while p.at < p.s.len && is_ident(p.s[p.at]) { p.at += 1usize }
    if p.at == st {
        p.bad = true
        ret false
    }
    let id = p.s[st..p.at]
    if peek(p) == 40u8 {
        p.at += 1usize
        var cnt = 0usize
        var nargs = 0usize
        var prev = true
        var ordered = true
        var first = false
        var second = false
        var more = true
        while more {
            let v = parse_or(p)
            nargs += 1usize
            if v { cnt += 1usize }
            if nargs > 1usize && v && !prev { ordered = false }
            prev = v
            if nargs == 1usize { first = v }
            if nargs == 2usize { second = v }
            if peek(p) == 44u8 { p.at += 1usize } else { more = false }
        }
        if peek(p) == 41u8 { p.at += 1usize } else { p.bad = true }
        if str.eq(id, "dc") { ret ordered }
        if str.eq(id, "xor") { ret first != second }
        if str.eq(id, "sum") {
            let c1 = peek(p)
            var op = 0u8
            p.at += 1usize
            let c2 = peek(p)
            // c1, c2: < > = !
            if c1 == 60u8 && c2 == 61u8 { op = 1u8 }
            if c1 == 60u8 && c2 != 61u8 { op = 2u8 }
            if c1 == 62u8 && c2 == 61u8 { op = 3u8 }
            if c1 == 62u8 && c2 != 61u8 { op = 4u8 }
            if c1 == 61u8 { op = 5u8 }
            if c1 == 33u8 { op = 6u8 }
            if op == 1u8 || op == 3u8 || op == 5u8 || op == 6u8 { p.at += 1usize }
            skip_ws(p)
            var num = 0usize
            while p.at < p.s.len && p.s[p.at] >= 48u8 && p.s[p.at] <= 57u8 {
                num = num * 10usize + usize(p.s[p.at] - 48u8)
                p.at += 1usize
            }
            if op == 1u8 { ret cnt <= num }
            if op == 2u8 { ret cnt < num }
            if op == 3u8 { ret cnt >= num }
            if op == 4u8 { ret cnt > num }
            if op == 5u8 { ret cnt == num }
            ret cnt != num
        }
        p.bad = true
        ret false
    }
    if str.eq(id, "TRUE") { ret true }
    if str.eq(id, "FALSE") { ret false }
    var t = 0usize
    while t < p.names.len {
        if str.eq(p.names[t], id) { ret ((p.mask >> u64(t)) & 1u64) == 1u64 }
        t += 1usize
    }
    p.bad = true
    ret false
}

fn expr_ok(expr: str, names: []const str, mask: u64) -> bool {
    var p = Parser { s: expr, at: 0usize, names: names, mask: mask, bad: false }
    let v = parse_or(&p)
    if p.bad { os.exit(75) }
    ret v
}

// variant k of the varying dimensions: the option picked in each dimension, the first dimension running fastest
fn variant_spec(sp: *const Spec, opts: []const Opt, ndim: usize, k: usize, n: usize, codes: []usize) -> Spec {
    var out = Spec { fam: sp.fam, theta: sp.theta, wt: sp.wt, off: sp.off, altw: sp.altw, alto: sp.alto }
    var rest = k
    var d = 0usize
    while d < ndim {
        var len = 0usize
        var i = 0usize
        while i < opts.len {
            if opts[i].dim == d { len += 1usize }
            i += 1usize
        }
        let pick = rest % len
        rest = rest / len
        codes[d] = pick + 1usize
        var seen = 0usize
        i = 0usize
        while i < opts.len {
            if opts[i].dim == d {
                if seen == pick {
                    let o = &opts[i]
                    if o.kind == 0u8 { out.fam = o.fam }
                    if o.kind == 1u8 { out.theta = o.theta }
                    if o.kind == 2u8 {
                        if o.arr == 0usize { out.wt = sp.altw[0usize..0usize] } else { out.wt = sp.altw[(o.arr - 1usize) * n..o.arr * n] }
                    }
                    if o.kind == 3u8 {
                        if o.arr == 0usize { out.off = sp.alto[0usize..0usize] } else { out.off = sp.alto[(o.arr - 1usize) * n..o.arr * n] }
                    }
                }
                seen += 1usize
            }
            i += 1usize
        }
        d += 1usize
    }
    ret out
}

fn dredge(a: *mem.Arena, x: []const f64, n: usize, nt: usize, y: []const f64, sp: *const Spec, opts: []const Opt, ndim: usize, fixed: u64, mlo: usize, mhi0: usize, parents: []const u64, rules: []const Rule, expr: str, names: []const str, rank: u8, chat: f64, beta: u8, extra: []const u8) -> Table {
    // glm.nb: the submodels are refitted with init.theta = signif(theta of the global model, 10), which MuMIn takes from the global call
    var spl = Spec { fam: sp.fam, theta: sp.theta, wt: sp.wt, off: sp.off, altw: sp.altw, alto: sp.alto }
    if spl.fam == 10u8 && spl.theta <= 0.0f64 {
        let gfit = fit_spec(a, x, n, nt, (1u64 << u64(nt)) - 1u64, y, sp)
        let pw = math.exp[f64](math.log[f64](10.0f64) * (9.0f64 - math.floor[f64](math.log[f64](gfit.theta) / math.log[f64](10.0f64))))
        spl.theta = math.round[f64](gfit.theta * pw) / pw
    }
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
    var nvar = 1usize
    var d = 0usize
    while d < ndim {
        var len = 0usize
        var i = 0usize
        while i < opts.len {
            if opts[i].dim == d { len += 1usize }
            i += 1usize
        }
        nvar = nvar * len
        d += 1usize
    }
    let total = 1usize << nov
    let cap = total * nvar
    let (ms, me) = mem.alloc[mf.Model](a, cap + 1usize)
    let (mk, ke) = mem.alloc[u64](a, cap + 1usize)
    let (ids, ie) = mem.alloc[usize](a, cap + 1usize)
    let (vcs, ve) = mem.alloc[usize](a, cap * ndim + 1usize)
    if me != ok || ke != ok || ie != ok || ve != ok { os.exit(70) }
    let codes = zero_usize(a)
    let (cd, cde) = mem.alloc[usize](a, ndim + 1usize)
    if cde != ok { os.exit(70) }
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
        let nv = popcnt(mask)
        if nv > mhi || nv < mlo { ok1 = false }
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
        if ok1 && expr.len > 0usize { ok1 = expr_ok(expr, names, mask) }
        if ok1 {
            var vk = 0usize
            while vk < nvar {
                let vs = variant_spec(&spl, opts, ndim, vk, n, cd)
                ms[k] = fit_spec(a, x, n, nt, mask, y, &vs)
                mk[k] = mask
                ids[k] = jc * nvar + vk + 1usize
                var q = 0usize
                while q < ndim {
                    vcs[k * ndim + q] = cd[q]
                    q += 1usize
                }
                k += 1usize
                vk += 1usize
            }
        }
        jc += 1usize
    }
    let _ = codes
    if k == 0usize { os.exit(74) }
    let m0 = fit_spec(a, x, n, nt, 0u64, y, &spl)
    ret build_table(a, ms[0usize..k], mk[0usize..k], ids[0usize..k], nt, y, m0.ll, rank, chat, beta, extra, ndim, vcs[0usize..k * ndim])
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
fn predict_models(a: *mem.Arena, t: *const Table, rows: []const usize, av: *const Avg, newx: []const f64, n2: usize, newoff: []const f64, fam: u8, resp: bool, se_fit: bool, backtransform: bool, revised: bool, fit: []f64, se: []f64) {
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
            if newoff.len > 0usize { eta += newoff[i] }
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
