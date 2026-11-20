// e.algo.stat.gamlssfit with smoothers (pb) against gamlss. tests/oracle/gamlss_smooth.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_smooth`; the header and data layout are at the top of scripts/r_oracle/groups/gamlss_smooth.R.

use e.algo.stat.gamlssfit as gf
use e.algo.stat.gamlsssmooth as sm
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn b2u(b: bool) -> usize {
    var r = 0usize
    if b { r = 1usize }
    ret r
}

fn show(a: *mem.Arena, sn: usize, c: *const oracle.Case, got: f64) {
    let (initial, be) = str.builder(a, 160usize)
    if be != ok { ret }
    var b = initial
    let _ = str.push(&b, "scen ")
    let _ = str.push_f64(&b, f64(sn))
    let _ = str.push(&b, " kind ")
    let _ = str.push_f64(&b, c.args[9usize - 8usize * b2u(c.args[0usize] >= 86.0f64)])
    let _ = str.push(&b, " idx ")
    let _ = str.push_f64(&b, c.args[10usize - 8usize * b2u(c.args[0usize] >= 86.0f64)])
    let _ = str.push(&b, " got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, " R ")
    let _ = str.push_f64(&b, c.want)
    let _ = io.print(str.done(&b))
    let _ = io.print("\n")
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_smooth.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    var fam = 0usize
    var n = 0usize
    let (ncol, e1) = mem.alloc[usize](a, 3usize)
    let (link, e2) = mem.alloc[usize](a, 3usize)
    let (hs, e3) = mem.alloc[usize](a, 3usize)
    let (step, e4) = mem.alloc[f64](a, 3usize)
    let (sc, e0) = mem.alloc[usize](a, 3usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e0 != ok { os.exit(4) }
    let scen = mem.mark(a)
    var out: gf.Out = zero
    var ws: []const f64 = zero
    var sn = 0usize
    var pbnl = 0.0f64
    var pblam = 0.0f64
    var pbfv: []f64 = zero
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        if usize(x[0usize]) == 86usize {
            if x.len > 12usize {
                mem.reset(a, scen)
                sn += 1usize
                let pn = usize(x[3usize])
                let (t, pe) = sm.cs_build(a, x[6usize + 2usize * pn..6usize + 3usize * pn], x[4usize], x[5usize])
                if pe != ok { os.exit(7) }
                var tt = t
                let (fv, e8) = mem.alloc[f64](a, pn)
                if e8 != ok { os.exit(5) }
                let (nl, lam, fe) = sm.cs_fit(a, &tt, x[6usize..6usize + pn], x[6usize + pn..6usize + 2usize * pn], fv)
                if fe != ok { os.exit(6) }
                pbnl = nl
                pblam = lam
                pbfv = fv
            }
            var pg = pblam
            if usize(x[1usize]) == 1usize { pg = pbnl }
            if usize(x[1usize]) == 2usize { pg = pbfv[usize(x[2usize])] }
            if !oracle.agrees(pg, c) {
                failures += 1usize
                if failures <= 400usize { show(a, sn, c, pg) }
            }
            at += 1usize
            continue
        }
        if usize(x[0usize]) == 87usize {
            if x.len > 12usize {
                mem.reset(a, scen)
                sn += 1usize
                let pn = usize(x[3usize])
                let (t, pe) = sm.lo_build(a, x[7usize + 2usize * pn..7usize + 3usize * pn], x[4usize], usize(x[5usize]), x[6usize])
                if pe != ok { os.exit(7) }
                var tt = t
                let (fv, e8) = mem.alloc[f64](a, pn)
                if e8 != ok { os.exit(5) }
                let (nl, lam, fe) = sm.lo_fit(a, &tt, x[7usize..7usize + pn], x[7usize + pn..7usize + 2usize * pn], fv)
                if fe != ok { os.exit(6) }
                pbnl = nl
                pblam = lam
                pbfv = fv
            }
            var pg = pblam
            if usize(x[1usize]) == 1usize { pg = pbnl }
            if usize(x[1usize]) == 2usize { pg = pbfv[usize(x[2usize])] }
            if !oracle.agrees(pg, c) {
                failures += 1usize
                if failures <= 400usize { show(a, sn, c, pg) }
            }
            at += 1usize
            continue
        }
        if usize(x[0usize]) == 88usize {
            if x.len > 12usize {
                mem.reset(a, scen)
                sn += 1usize
                let pn = usize(x[3usize])
                let (t, pe) = sm.pb_build(a, x[10usize + 2usize * pn..10usize + 3usize * pn], usize(x[4usize]), usize(x[5usize]), usize(x[6usize]), x[7usize], x[8usize], x[9usize], 0usize, 2.0f64)
                if pe != ok { os.exit(7) }
                var tt = t
                let (fv, e8) = mem.alloc[f64](a, pn)
                if e8 != ok { os.exit(5) }
                let (nl, lam, fe) = sm.pb_fit(a, &tt, x[10usize..10usize + pn], x[10usize + pn..10usize + 2usize * pn], fv)
                if fe != ok { os.exit(6) }
                pbnl = nl
                pblam = lam
                pbfv = fv
            }
            var pg = pblam
            if usize(x[1usize]) == 1usize { pg = pbnl }
            if usize(x[1usize]) == 2usize { pg = pbfv[usize(x[2usize])] }
            if !oracle.agrees(pg, c) {
                failures += 1usize
                if failures <= 400usize { show(a, sn, c, pg) }
            }
            at += 1usize
            continue
        }
        if usize(x[0usize]) != 99usize {
            mem.reset(a, scen)
            sn += 1usize
            fam = usize(x[0usize])
            n = usize(x[2usize])
            var k = 0usize
            var nsm = 0usize
            while k < 3usize {
                ncol[k] = usize(x[3usize + k])
                link[k] = usize(x[6usize + k])
                step[k] = x[17usize + k]
                sc[k] = usize(x[20usize + k])
                nsm += sc[k]
                hs[k] = 0usize
                k += 1usize
            }
            let base = 23usize + 8usize * nsm
            let y = x[base..base + n]
            let w = x[base + n..base + 2usize * n]
            let xs = x[base + 2usize * n..base + 2usize * n + n * (ncol[0usize] + ncol[1usize] + ncol[2usize])]
            let sx = base + 2usize * n + n * (ncol[0usize] + ncol[1usize] + ncol[2usize])
            let (smo, e9) = mem.alloc[sm.Smo](a, nsm + 1usize)
            if e9 != ok { os.exit(5) }
            var j = 0usize
            while j < nsm {
                let h = 23usize + 8usize * j
                if usize(x[h]) == 2usize {
                    let (t2, ce) = sm.cs_build(a, x[sx + j * n..sx + j * n + n], x[h + 4usize], x[h + 5usize])
                    if ce != ok { os.exit(7) }
                    smo[j] = t2
                } else if usize(x[h]) == 3usize {
                    let (t3, le) = sm.lo_build(a, x[sx + j * n..sx + j * n + n], x[h + 1usize], usize(x[h + 2usize]), x[h + 4usize])
                    if le != ok { os.exit(7) }
                    smo[j] = t3
                } else {
                    let (t, be) = sm.pb_build(a, x[sx + j * n..sx + j * n + n], usize(x[h + 1usize]), usize(x[h + 2usize]), usize(x[h + 3usize]), x[h + 4usize], x[h + 5usize], x[h + 7usize], usize(x[h + 6usize]), 2.0f64)
                    if be != ok { os.exit(7) }
                    smo[j] = t
                }
                j += 1usize
            }
            let (off, e5) = mem.alloc[f64](a, 4usize * n)
            let (st, e6) = mem.alloc[f64](a, 4usize * n)
            if e5 != ok || e6 != ok { os.exit(5) }
            var i = 0usize
            while i < 4usize * n {
                off[i] = 0.0f64
                st[i] = 0.0f64
                i += 1usize
            }
            let (o, fe) = gf.fit_smo(a, smo[0usize..nsm], sc, fam, usize(x[1usize]), y, w, xs, ncol, link, off, st, hs, step, x[11usize], usize(x[12usize]), 0.001f64, 50usize, x[15usize] == 1.0f64, usize(x[13usize]), usize(x[14usize]))
            if fe != ok { os.exit(6) }
            out = o
            ws = w
        }
        let kind = usize(x[9usize])
        let idx = usize(x[10usize])
        var got = 0.0f64
        if kind == 0usize { got = out.coef[idx] }
        if kind == 1usize { got = out.gdev }
        if kind == 2usize { got = f64(out.iter) }
        if kind == 3usize && out.conv { got = 1.0f64 }
        if kind == 4usize { got = out.par[idx] }
        if kind == 5usize { got = out.df }
        if kind == 6usize { got = out.gdev + 2.0f64 * out.df }
        if kind == 7usize {
            var nobs = f64(n)
            var all_int = true
            var sw = 0.0f64
            var j = 0usize
            while j < n {
                if ws[j] != f64(i64(ws[j])) { all_int = false }
                sw += ws[j]
                j += 1usize
            }
            if all_int { nobs = sw }
            got = out.gdev + math.log[f64](nobs) * out.df
        }
        if kind == 8usize { got = out.wv[idx] }
        if kind == 9usize { got = out.wt[idx] }
        if kind == 10usize { got = out.eta[idx] }
        if kind == 13usize { got = out.nldf[idx] }
        if kind == 14usize { got = out.pen }
        if kind == 15usize { got = out.slam[idx] }
        if kind == 16usize { got = out.ss[idx] }
        if kind == 17usize { got = out.gdev + out.pen }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 400usize {
                show(a, sn, c, got)
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
