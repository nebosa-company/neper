// e.algo.stat.gslmore2 against gsl. tests/oracle/gslmore2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslmore2`; the layout of each case is at the top of scripts/r_oracle/groups/gslmore2.R.

use e.algo.stat.gslcoulomb as gc
use e.algo.stat.gslfns as gs
use e.algo.stat.gslmore as gm
use e.algo.stat.gslmore2 as g2
use e.io
use e.math
use e.math.special as sp
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn grab(a: *mem.Arena, n: usize) -> []f64 {
    let (p, g) = mem.alloc[f64](a, n)
    if g != ok { os.exit(4) }
    ret p
}

fn arg(x: []const f64, i: usize) -> f64 {
    if i < x.len { ret x[i] }
    ret 0.0f64
}

fn n_case(a: *mem.Arena, x: []const f64) -> f64 {
    let code = usize(x[0usize])
    let p = arg(x, 1usize)
    let q = arg(x, 2usize)
    let r = arg(x, 3usize)
    let s = arg(x, 4usize)
    if code == 0usize { ret gm.hydrogenic_r(usize(p), usize(q), r, s) }
    if code == 1usize { ret gs.hyperg_1f1(p, q, r) }
    if code == 2usize { ret gs.hyperg_u(a, p, q, r) }
    if code == 3usize { ret gs.hyperg_2f1(p, q, r, s) / math.exp[f64](sp.lgamma(r)) }
    if code == 4usize { ret gm.hyperg_2f1_conj(p, q, r, s) }
    if code == 5usize { ret gm.hyperg_2f1_conj(p, q, r, s) / math.exp[f64](sp.lgamma(r)) }
    if code == 6usize || code == 7usize { ret gm.lngamma_abs(p) }
    if code == 8usize { ret gm.gamma_sign(p) }
    if code == 9usize { ret g2.lnpoch_sgn_val(p, q) }
    if code == 10usize { ret g2.lnpoch_sgn_sign(p, q) }
    if code == 11usize { ret math.log[f64](math.abs[f64](p)) }
    if code == 12usize { ret gm.pow_int(p, i64(q)) }
    if code == 13usize { ret gm.fact(usize(p)) }
    if code == 14usize { ret gm.erf_z(p) }
    if code == 15usize { ret gm.erf_q(p) }
    if code == 16usize { ret gm.expint_e2(p) }
    if code == 17usize { ret gm.legendre_q1(p) }
    if code == 18usize { ret gm.zetam1_int(usize(p)) }
    if code == 19usize { ret gc.psi_1piy(p) }
    if code == 20usize {
        let c4 = grab(a, 4usize)
        c4[0usize] = p
        c4[1usize] = q
        c4[2usize] = r
        c4[3usize] = s
        ret gm.poly_eval(c4, 4usize, arg(x, 5usize))
    }
    if code == 21usize { ret math.exp[f64](sp.lgamma(p) + sp.lgamma(q) - sp.lgamma(p + q)) }
    if code == 22usize { ret g2.choose_(usize(p), usize(q)) }
    if code == 23usize { ret g2.gamma_fn(p) }
    if code == 24usize { ret math.cos[f64](p) }
    if code == 25usize { ret math.sin[f64](p) }
    if code == 26usize { ret math.log[f64](p) }
    if code == 27usize { ret g2.airy_scaled_kind(usize(p), q) }
    if code == 28usize { ret gs.legendre_h3d(0usize, p, q) }
    if code == 29usize { ret gs.legendre_h3d(1usize, p, q) }
    if code == 30usize { ret gs.legendre_h3d(usize(p), q, r) }
    if code == 31usize { ret gs.legendre_pl(usize(p), q) }
    if code == 32usize { ret f64((usize(p) + 1usize) * (usize(p) + 6usize) / 2usize) }
    ret f64(usize(p) * (usize(p) + 1usize) / 2usize + usize(q))
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "n") { ret n_case(a, x) }
    let o = grab(a, 6usize)
    let r = grab(a, 3usize)
    let em = grab(a, 32usize)
    let en = grab(a, 32usize)
    ret g2.jacobi_ratio(usize(x[0usize]), usize(x[1usize]), x[2usize], x[3usize], x[4usize], o, r, em, en)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslmore2.json")
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
            if failures <= 14usize {
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
