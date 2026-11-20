// e.algo.stat.nlmelist (lme, lmList, self-start models and nls fits) against nlme and stats.
// tests/oracle/nlmelist.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R nlmelist`; the case layout is at
// the top of scripts/r_oracle/groups/nlmelist.R. Cases of one fit differ only in the output index (args[1]), so a fit is cached
// while consecutive cases share the rest of the arguments.

use e.algo.stat.gls as g
use e.algo.stat.nlmelist as nl
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

type Parsed = struct { sp: g.Spec, end: usize, good: bool }

// one lme case block starting at x[at]: reml, n, p, ck, nv, ng, gs[ng], t[n], y[n], X[n*p], qz, Z[n*qz], then nv variance terms
fn parse_lme(a: *mem.Arena, x: []const f64, at: usize) -> Parsed {
    let reml = x[at] != 0.0f64
    let n = usize(x[at + 1usize])
    let p = usize(x[at + 2usize])
    let ck = i64(x[at + 3usize])
    let nv = usize(x[at + 4usize])
    let ng = usize(x[at + 5usize])
    var o = at + 6usize
    let gs = x[o..o + ng]
    o += ng
    let t = x[o..o + n]
    o += n
    let y = x[o..o + n]
    o += n
    let xm = x[o..o + n * p]
    o += n * p
    let qz = usize(x[o])
    o += 1usize
    let z = x[o..o + n * qz]
    o += n * qz
    let (vk, e1) = mem.alloc[f64](a, nv + 1usize)
    let (vn, e2) = mem.alloc[f64](a, nv + 1usize)
    let (vc, e3) = mem.alloc[f64](a, nv * n + 1usize)
    var sp = g.Spec { n: n, p: p, x: xm, y: y, t: t, gs: gs, ng: ng, ck: ck, nv: nv, vk: vk[0usize..0usize], vn: vn[0usize..0usize], vc: vc[0usize..0usize], reml: reml, q: qz, z: z }
    var res = Parsed { sp: sp, end: 0usize, good: false }
    if e1 != ok || e2 != ok || e3 != ok { ret res }
    var k = 0usize
    while k < nv {
        vk[k] = x[o]
        vn[k] = x[o + 1usize]
        var i = 0usize
        while i < n {
            vc[k * n + i] = x[o + 2usize + i]
            i += 1usize
        }
        o += 2usize + n
        k += 1usize
    }
    sp.vk = vk[0usize..nv]
    sp.vn = vn[0usize..nv]
    sp.vc = vc[0usize..nv * n]
    res.sp = sp
    res.end = o
    res.good = true
    ret res
}

// the fit vector of the case: lme (family 1), lmList (2), nls (4) or the lme likelihood-ratio statistic of two models (5); length 0 on failure
fn fit_vec(a: *mem.Arena, x: []const f64, out: []f64) -> usize {
    let fam = i64(x[0usize])
    if fam == 5i64 {
        let pa = parse_lme(a, x, 2usize)
        if !pa.good { ret 0usize }
        let pb = parse_lme(a, x, pa.end)
        if !pb.good { ret 0usize }
        let la = nl.lme_len(&pa.sp)
        let lb = nl.lme_len(&pb.sp)
        let (ta, e1) = mem.alloc[f64](a, la)
        let (tb, e2) = mem.alloc[f64](a, lb)
        if e1 != ok || e2 != ok || out.len < 1usize { ret 0usize }
        if nl.lme_fit(a, pa.sp, ta) != ok || nl.lme_fit(a, pb.sp, tb) != ok { ret 0usize }
        out[0usize] = 2.0f64 * (ta[pa.sp.p + 1usize] - tb[pb.sp.p + 1usize])
        ret 1usize
    }
    if fam == 1i64 {
        let pr = parse_lme(a, x, 2usize)
        if !pr.good { ret 0usize }
        let len = nl.lme_len(&pr.sp)
        let (tmp, oe) = mem.alloc[f64](a, len)
        if oe != ok || len > out.len { ret 0usize }
        if nl.lme_fit(a, pr.sp, tmp) != ok { ret 0usize }
        var k = 0usize
        while k < len {
            out[k] = tmp[k]
            k += 1usize
        }
        ret len
    }
    if fam == 2i64 {
        let n = usize(x[2usize])
        let p = usize(x[3usize])
        let ng = usize(x[4usize])
        var o = 5usize
        let gs = x[o..o + ng]
        o += ng
        let y = x[o..o + n]
        o += n
        let xm = x[o..o + n * p]
        let len = nl.lmlist_len(p, ng)
        let (tmp, oe) = mem.alloc[f64](a, len)
        if oe != ok || len > out.len { ret 0usize }
        if nl.lmlist_fit(a, n, p, xm, y, gs, ng, tmp) != ok { ret 0usize }
        var k = 0usize
        while k < len {
            out[k] = tmp[k]
            k += 1usize
        }
        ret len
    }
    let kind = i64(x[1usize])
    let n = usize(x[3usize])
    let len = nl.nls_len(kind)
    let (tmp, oe) = mem.alloc[f64](a, len)
    if oe != ok || len > out.len { ret 0usize }
    if nl.nls_fit(a, kind, n, x[4usize..4usize + n], x[4usize + n..4usize + 2usize * n], tmp) != ok { ret 0usize }
    var k = 0usize
    while k < len {
        out[k] = tmp[k]
        k += 1usize
    }
    ret len
}

fn ssval(x: []const f64) -> f64 {
    let kind = i64(x[1usize])
    let q_out = usize(x[2usize])
    var gr: [4]f64 = zero
    let v = nl.ss_eval(kind, x[3usize], x[4usize..x.len], gr[0usize..4usize])
    if q_out == 0usize { ret v }
    ret gr[q_out - 1usize]
}

// the lme, lmList and nls families keep the output index in args[1] (nls in args[2]); everything else is the fit's key
fn qidx(x: []const f64) -> usize {
    if i64(x[0usize]) == 4i64 { ret usize(x[2usize]) }
    ret usize(x[1usize])
}

fn same_fit(x: []const f64, y: []const f64) -> bool {
    if x.len != y.len { ret false }
    if x[0usize] != y[0usize] { ret false }
    let skip = 1usize
    var skip2 = skip
    if i64(x[0usize]) == 4i64 { skip2 = 2usize }
    var i = 1usize
    while i < x.len {
        if i != skip2 && x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nlmelist.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (cache, ce) = mem.alloc[f64](a, 4096usize)
    if ce != ok { os.exit(4) }
    var cache_len = 0usize
    var cache_key: []const f64 = golden.cases[0usize].args
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let st = mem.mark(a)
        var got = 0.0f64 / 0.0f64
        let fam = i64(c.args[0usize])
        if fam == 3i64 {
            got = ssval(c.args)
        } else {
            if cache_len == 0usize || !same_fit(cache_key, c.args) {
                cache_len = fit_vec(a, c.args, cache)
                cache_key = c.args
            }
            let q = qidx(c.args)
            if cache_len > q { got = cache[q] }
        }
        mem.reset(a, st)
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
