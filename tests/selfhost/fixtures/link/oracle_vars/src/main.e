// e.algo.stat.vars against vars. tests/oracle/vars.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vars`; the layout is at the top of scripts/r_oracle/groups/vars.R.

use e.algo.stat.vars as vr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let t0 = usize(x[0usize])
    let k = usize(x[1usize])
    let p = usize(x[2usize])
    let lm = usize(x[3usize])
    let y = x[4usize..4usize + t0 * k]
    let nm = c.name
    if str.eq(nm, "aic") { ret vr.var_select(a, y, t0, k, p, lm, 0usize) }
    if str.eq(nm, "hq") { ret vr.var_select(a, y, t0, k, p, lm, 1usize) }
    if str.eq(nm, "sc") { ret vr.var_select(a, y, t0, k, p, lm, 2usize) }
    if str.eq(nm, "fpe") { ret vr.var_select(a, y, t0, k, p, lm, 3usize) }
    if str.eq(nm, "fcst") || str.eq(nm, "irf") || str.eq(nm, "oirf") {
        let rows = t0 - p
        let w = k * p + 1usize
        let (cf, g1) = mem.alloc[f64](a, k * w)
        if g1 != ok { os.exit(9) }
        let (rs, g2) = mem.alloc[f64](a, rows * k)
        if g2 != ok { os.exit(10) }
        if vr.var_fit(a, y, t0, k, p, p, cf, rs) != ok { os.exit(11) }
        var tot = 0.0f64
        if str.eq(nm, "fcst") {
            let (fo, g3) = mem.alloc[f64](a, 5usize * k)
            if g3 != ok { os.exit(12) }
            let (hh, g4) = mem.alloc[f64](a, (p + 5usize) * k)
            if g4 != ok { os.exit(13) }
            vr.var_forecast(y, t0, k, p, cf, 5usize, fo, hh)
            var q = 0usize
            while q < 5usize * k {
                tot += fo[q] * f64(q + 1usize)
                q += 1usize
            }
            ret tot
        }
        let (ph, g5) = mem.alloc[f64](a, 6usize * k * k)
        if g5 != ok { os.exit(14) }
        vr.var_phi(cf, k, p, 5usize, ph)
        var src = ph
        if str.eq(nm, "oirf") {
            let (sg0, g6) = mem.alloc[f64](a, k * k)
            if g6 != ok { os.exit(15) }
            vr.sigma_u(rs, rows, k, p, sg0)
            let (pc, g7) = mem.alloc[f64](a, k * k)
            if g7 != ok { os.exit(16) }
            if !vr.var_chol(sg0, k, pc) { os.exit(17) }
            let (oo, g8) = mem.alloc[f64](a, 6usize * k * k)
            if g8 != ok { os.exit(18) }
            vr.var_oirf(ph, pc, k, 5usize, oo)
            src = oo
        }
        // R lists the responses to each impulse in turn: impulse j, then horizon, then the responding series
        var pos = 0usize
        var imp = 0usize
        while imp < k {
            var s = 0usize
            while s <= 5usize {
                var resp = 0usize
                while resp < k {
                    pos += 1usize
                    tot += src[s * k * k + resp * k + imp] * f64(pos)
                    resp += 1usize
                }
                s += 1usize
            }
            imp += 1usize
        }
        ret tot
    }
    let rows = t0 - p
    let w = k * p + 1usize
    let (coef, e1) = mem.alloc[f64](a, k * w)
    if e1 != ok { os.exit(5) }
    let (res, e2) = mem.alloc[f64](a, rows * k)
    if e2 != ok { os.exit(6) }
    if vr.var_fit(a, y, t0, k, p, p, coef, res) != ok { os.exit(7) }
    var s = 0.0f64
    if str.eq(nm, "coef") {
        // Bcoef is K by (K p + 1), R's as.vector(t(B)) reads it row by row
        var i = 0usize
        while i < k * w {
            s += coef[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    let (sg, e3) = mem.alloc[f64](a, k * k)
    if e3 != ok { os.exit(8) }
    vr.sigma_u(res, rows, k, p, sg)
    // as.vector(S) is column-major, S symmetric
    var j = 0usize
    while j < k {
        var i = 0usize
        while i < k {
            s += sg[i * k + j] * f64(j * k + i + 1usize)
            i += 1usize
        }
        j += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vars.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
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
