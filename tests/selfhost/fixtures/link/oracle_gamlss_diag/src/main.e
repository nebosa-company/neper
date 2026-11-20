// e.algo.stat.gamlssdiag (residual summary, wp, Q.stats, centiles and centiles.pred) against gamlss. tests/oracle/gamlss_diag.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_diag`; the header and data layout are at the top of scripts/r_oracle/groups/gamlss_diag.R.

use e.algo.stat.gamlssdiag as dg
use e.algo.stat.gamlssfit as gf
use e.io
use e.math
use e.math.dist as dist
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_diag.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (cents, ec9) = mem.alloc[f64](a, 9usize)
    if ec9 != ok { os.exit(4) }
    cents[0usize] = 0.4f64
    cents[1usize] = 2.0f64
    cents[2usize] = 10.0f64
    cents[3usize] = 25.0f64
    cents[4usize] = 50.0f64
    cents[5usize] = 75.0f64
    cents[6usize] = 90.0f64
    cents[7usize] = 98.0f64
    cents[8usize] = 99.6f64
    var failures = 0usize
    var at = 0usize
    var fam = 0usize
    var n = 0usize
    let (ncol, e1) = mem.alloc[usize](a, 3usize)
    let (link, e2) = mem.alloc[usize](a, 3usize)
    let (hs, e3) = mem.alloc[usize](a, 3usize)
    let (step, e4) = mem.alloc[f64](a, 3usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(4) }
    let scen = mem.mark(a)
    var out: gf.Out = zero
    var res: []f64 = zero
    var sm5: []f64 = zero
    var wpall: []f64 = zero
    var iv1: []f64 = zero
    var cf1: []f64 = zero
    var iv2: []f64 = zero
    var cf2: []f64 = zero
    var zq: []f64 = zero
    var xq: []f64 = zero
    var rq: []f64 = zero
    var cq: []f64 = zero
    var ordx: []usize = zero
    var below: []f64 = zero
    var pm: []f64 = zero
    var ordn: []usize = zero
    var newx: []const f64 = zero
    var yval: []const f64 = zero
    var ys: []const f64 = zero
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        if usize(x[0usize]) != 99usize {
            mem.reset(a, scen)
            fam = usize(x[0usize])
            n = usize(x[2usize])
            var k = 0usize
            while k < 3usize {
                ncol[k] = usize(x[3usize + k])
                link[k] = usize(x[6usize + k])
                step[k] = x[17usize + k]
                hs[k] = 0usize
                k += 1usize
            }
            let ninter = usize(x[16usize])
            let y = x[20usize..20usize + n]
            let w = x[20usize + n..20usize + 2usize * n]
            let pt = ncol[0usize] + ncol[1usize] + ncol[2usize]
            let xs = x[20usize + 2usize * n..20usize + 2usize * n + n * pt]
            let base = 20usize + 2usize * n + n * pt
            let xv = x[base..base + n]
            newx = x[base + n..base + n + 5usize]
            yval = x[base + n + 5usize..base + n + 10usize]
            let nc = usize(x[base + n + 10usize])
            let cuts = x[base + n + 11usize..base + n + 11usize + nc]
            let (off, e5) = mem.alloc[f64](a, 4usize * n)
            let (st, e6) = mem.alloc[f64](a, 4usize * n)
            if e5 != ok || e6 != ok { os.exit(5) }
            var i = 0usize
            while i < 4usize * n {
                off[i] = 0.0f64
                st[i] = 0.0f64
                i += 1usize
            }
            let (o, fe) = gf.fit_model(a, fam, usize(x[1usize]), y, w, xs, ncol, link, off, st, hs, step, x[11usize], usize(x[12usize]), 0.001f64, 50usize, x[15usize] == 1.0f64, usize(x[13usize]), usize(x[14usize]))
            if fe != ok { os.exit(6) }
            out = o
            ys = y
            let (r0, ea) = mem.alloc[f64](a, n + 1usize)
            let (s5, eb) = mem.alloc[f64](a, 5usize)
            let (w4, ec) = mem.alloc[f64](a, 4usize)
            let (v1, ed) = mem.alloc[f64](a, 2usize * (ninter + 2usize))
            let (c1, ee) = mem.alloc[f64](a, 4usize * (ninter + 2usize))
            let (v2, ef) = mem.alloc[f64](a, 2usize * (nc + 2usize))
            let (c2, eg) = mem.alloc[f64](a, 4usize * (nc + 2usize))
            let (v3, eh) = mem.alloc[f64](a, 2usize * (ninter + 3usize))
            let (q1, ei) = mem.alloc[f64](a, 6usize * (ninter + 6usize))
            let (q2, ej) = mem.alloc[f64](a, 6usize * (ninter + 6usize))
            let (q3, ek) = mem.alloc[f64](a, 6usize * (ninter + 6usize))
            let (q4, el) = mem.alloc[f64](a, 6usize * (nc + 5usize))
            let (q5, em) = mem.alloc[f64](a, 6usize * (nc + 5usize))
            let (q6, en) = mem.alloc[f64](a, 6usize * (ninter + 6usize))
            let (q7, eo) = mem.alloc[f64](a, 6usize * (ninter + 6usize))
            let (od, ep) = mem.alloc[usize](a, n + 1usize)
            let (bl, eq) = mem.alloc[f64](a, 9usize)
            let (pp, er) = mem.alloc[f64](a, 15usize)
            let (on, es) = mem.alloc[usize](a, 6usize)
            if ea != ok || eb != ok || ec != ok || ed != ok || ee != ok || ef != ok || eg != ok || eh != ok || ei != ok || ej != ok || ek != ok || el != ok || em != ok || en != ok || eo != ok || ep != ok || eq != ok || er != ok || es != ok { os.exit(5) }
            res = r0
            sm5 = s5
            wpall = w4
            iv1 = v1
            cf1 = c1
            iv2 = v2
            cf2 = c2
            zq = q1
            xq = q2
            rq = q3
            cq = q4
            ordx = od
            below = bl
            pm = pp
            ordn = on
            i = 0usize
            while i < n {
                res[i] = gf.rqres(fam, y[i], out.par[i], out.par[n + i], out.par[2usize * n + i])
                i += 1usize
            }
            if dg.summary(a, res[0usize..n], f64(n), sm5) != ok { os.exit(7) }
            if dg.worm_cubic(a, res[0usize..n], wpall) != ok { os.exit(7) }
            let (rows1, e7) = dg.co_intervals(a, xv, ninter, 0.0f64, iv1)
            if e7 != ok { os.exit(7) }
            dg.check_overlap(iv1, rows1)
            if dg.wp_panels(a, res[0usize..n], xv, iv1, rows1, cf1) != ok { os.exit(7) }
            let rows2 = dg.cut_intervals(xv, cuts, 0usize, iv2)
            if dg.wp_panels(a, res[0usize..n], xv, iv2, rows2, cf2) != ok { os.exit(7) }
            // the degrees of freedom of Q.stats: location, scale (sigma.df + 1) / 2, skewness
            let (dfv, e8) = mem.alloc[f64](a, 4usize)
            if e8 != ok { os.exit(5) }
            dfv[0usize] = f64(ncol[0usize])
            dfv[1usize] = (f64(ncol[1usize]) + 1.0f64) / 2.0f64
            dfv[2usize] = f64(ncol[2usize])
            dfv[3usize] = 0.0f64
            if dg.qstats(a, res[0usize..n], xv, iv1, rows1, dfv, zq, xq) != ok { os.exit(7) }
            let (rows3, e9) = dg.co_intervals(a, xv, ninter + 1usize, 0.0f64, v3)
            if e9 != ok { os.exit(7) }
            dg.check_overlap(v3, rows3)
            dfv[0usize] = 0.0f64
            dfv[1usize] = 0.0f64
            dfv[2usize] = 0.0f64
            if dg.qstats(a, res[0usize..n], xv, v3, rows3, dfv, rq, q7) != ok { os.exit(7) }
            let (iv4, ev4) = mem.alloc[f64](a, 2usize * (nc + 2usize))
            if ev4 != ok { os.exit(5) }
            let rows4 = dg.cut_intervals(xv, cuts, 1usize, iv4)
            dfv[0usize] = f64(ncol[0usize])
            dfv[1usize] = (f64(ncol[1usize]) + 1.0f64) / 2.0f64
            dfv[2usize] = f64(ncol[2usize])
            if dg.qstats(a, res[0usize..n], xv, iv4, rows4, dfv, cq, q5) != ok { os.exit(7) }
            dg.order_asc(xv, ordx)
            dg.order_asc(newx, ordn)
            var ci = 0usize
            while ci < 9usize {
                below[ci] = dg.centile_below(fam, out.par, y, n, cents[ci], ordx)
                ci += 1usize
            }
            var co0 = 0usize
            k = 0usize
            while k < 3usize {
                var j = 0usize
                while j < 5usize {
                    pm[k * 5usize + j] = 0.0f64
                    if ncol[k] > 0usize { pm[k * 5usize + j] = dg.predict_par(out.coef[co0..co0 + ncol[k]], ncol[k], link[k], newx[j]) }
                    j += 1usize
                }
                co0 += ncol[k]
                k += 1usize
            }
        }
        let kind = usize(x[9usize])
        let idx = usize(x[10usize])
        var got = 0.0f64
        if kind == 30usize { got = sm5[idx] }
        if kind == 31usize { got = wpall[idx] }
        if kind == 32usize { got = dg.worm_band(0.0f64 - 4.0f64 + 0.25f64 * f64(idx), n) }
        if kind == 33usize { got = iv1[idx] }
        if kind == 34usize { got = cf1[idx] }
        if kind == 35usize { got = iv2[idx] }
        if kind == 36usize { got = cf2[idx] }
        if kind == 37usize { got = zq[idx] }
        if kind == 38usize { got = xq[idx] }
        if kind == 39usize { got = rq[(idx / 4usize) * 6usize + idx % 4usize] }
        if kind == 40usize { got = cq[idx] }
        if kind == 41usize {
            got = dg.centile_curve(fam, out.par, n, cents[idx / n] / 100.0f64, ordx, idx % n)
        }
        if kind == 42usize { got = below[idx] }
        if kind == 43usize || kind == 45usize {
            let ci = idx / 5usize
            let j = ordn[idx % 5usize]
            var p = cents[ci] / 100.0f64
            if kind == 45usize {
                let dv = 0.0f64 - 4.0f64 + f64(ci)
                p = dist.pnorm(dv, 0.0f64, 1.0f64, true, false) * 100.0f64 / 100.0f64
            }
            got = gf.centile(fam, p, pm[j], pm[5usize + j], pm[10usize + j])
        }
        if kind == 44usize { got = gf.rqres(fam, yval[idx], pm[idx], pm[5usize + idx], pm[10usize + idx]) }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 8usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
