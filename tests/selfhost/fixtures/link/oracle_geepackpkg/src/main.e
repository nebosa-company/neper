// e.algo.stat.geepackpkg against geepack. tests/oracle/geepackpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R geepackpkg`; the layout is at the top of scripts/r_oracle/groups/geepackpkg.R.

use e.algo.stat.geepackpkg as gp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/geepackpkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        if str.eq(c.name, "geg") {
            // (what, index, family, corstr, k, m, p, y (k m), x row-major)
            let gk = usize(x[4usize])
            let gm = usize(x[5usize])
            let gpp = usize(x[6usize])
            let gn = gk * gm
            let (gb, ge1) = mem.alloc[f64](a, gpp)
            let (gv, ge2) = mem.alloc[f64](a, gpp * gpp)
            if ge1 != ok || ge2 != ok { os.exit(5) }
            let (gphi, galpha, ge3) = gp.geeglm_glm(a, x[7usize..7usize + gn], x[7usize + gn..7usize + gn + gn * gpp], gk, gm, gpp, usize(x[2usize]), usize(x[3usize]), gb, gv)
            if ge3 != ok { os.exit(7) }
            var gg = 0.0f64
            if usize(x[0usize]) == 0usize { gg = gb[usize(x[1usize])] }
            if usize(x[0usize]) == 1usize { gg = gv[usize(x[1usize])] }
            if usize(x[0usize]) == 2usize { gg = gphi }
            if usize(x[0usize]) == 3usize { gg = galpha }
            if !oracle.agrees(gg, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, gg))
                    let _ = io.print("\n")
                }
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if str.eq(c.name, "gx") {
            // (what, index, fam, link, corstr, dofij, k, p, maxm, sizes (k), y, x row-major, zc (maxm by maxm))
            let xk = usize(x[6usize])
            let xp = usize(x[7usize])
            let xm = usize(x[8usize])
            var xn = 0usize
            var xc = 0usize
            while xc < xk {
                xn += usize(x[9usize + xc])
                xc += 1usize
            }
            let ybase = 9usize + xk
            let xbase = ybase + xn
            let zbase = xbase + xn * xp
            let (xo, xe1) = mem.alloc[f64](a, gp.gee_out_len(xp, xm, usize(x[4usize])))
            if xe1 != ok { os.exit(5) }
            let (xphi, xe2) = gp.gee_fit(a, x[ybase..xbase], x[xbase..zbase], x[9usize..ybase], xk, xp, usize(x[2usize]), usize(x[3usize]), usize(x[4usize]), x[zbase..zbase + xm * xm], x[5usize] == 1.0f64, xo)
            if xe2 != ok { os.exit(7) }
            var xg = 0.0f64
            let xw = usize(x[0usize])
            let xi = usize(x[1usize])
            let xpp = xp * xp
            if xw == 0usize { xg = xo[xi] }
            if xw >= 1usize && xw <= 4usize { xg = xo[xp + (xw - 1usize) * xpp + xi] }
            if xw == 5usize { xg = xphi }
            if xw == 6usize { xg = xo[xp + 4usize * xpp + xi] }
            if !oracle.agrees(xg, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, xg))
                    let _ = io.print("\n")
                }
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        let k = usize(x[3usize])
        let m = usize(x[4usize])
        let p = usize(x[5usize])
        let n = k * m
        let (beta, e1) = mem.alloc[f64](a, p)
        if e1 != ok { os.exit(5) }
        let (vb, e2) = mem.alloc[f64](a, p * p)
        if e2 != ok { os.exit(6) }
        let (phi, alpha, e3) = gp.geeglm_gaussian(a, x[6usize..6usize + n], x[6usize + n..6usize + n + n * p], k, m, p, x[2usize] == 1.0f64, beta, vb)
        if e3 != ok { os.exit(7) }
        var got = 0.0f64
        let what = usize(x[0usize])
        let idx = usize(x[1usize])
        if what == 0usize { got = beta[idx] }
        if what == 1usize { got = vb[idx] }
        if what == 2usize { got = phi }
        if what == 3usize { got = alpha }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
