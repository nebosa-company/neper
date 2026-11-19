// e.algo.stat.gslmore against gsl. tests/oracle/gslmore.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslmore`; the layout of each case is at the top of scripts/r_oracle/groups/gslmore.R.

use e.algo.stat.gslfns as gs
use e.algo.stat.gslmore as gm
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn grab(a: *mem.Arena, n: usize) -> []f64 {
    let (p, g) = mem.alloc[f64](a, n)
    if g != ok { os.exit(4) }
    ret p
}

fn sph(a: *mem.Arena, kind: usize, l: usize, x: f64) -> f64 {
    let o = grab(a, l + 1usize)
    if kind == 0usize { gm.sph_j_array(l, x, o) }
    if kind == 1usize { gm.sph_y_array(l, x, o) }
    ret o[l]
}

fn m_case(a: *mem.Arena, x: []const f64) -> f64 {
    let code = usize(x[0usize])
    let p = x[1usize]
    let v = x[2usize]
    if code == 0usize { ret gm.bessel_in(i64(p), v) }
    if code == 1usize { ret gm.in_sc(p, v) }
    if code == 2usize { ret gm.bessel_kn(i64(p), v) }
    if code == 3usize || code == 4usize { ret gm.kn_sc(p, v) }
    if code == 5usize { ret gm.in_sc(p, v) }
    if code == 6usize { ret math.log[f64](gm.kn_sc(p, v)) - v }
    if code == 7usize { ret gm.bessel_jnu_q(a, p, v) }
    if code == 8usize { ret gm.bessel_jnu_q(a, 0.0f64, v) }
    if code == 9usize { ret gm.bessel_jnu_q(a, 1.0f64, v) }
    if code == 10usize { ret gs.bessel_yn(a, 0usize, v) }
    if code == 11usize { ret gs.bessel_yn(a, 1usize, v) }
    if code == 12usize || code == 13usize { ret gm.in_sc(f64(code - 12usize), v) }
    if code == 14usize || code == 15usize { ret gm.kn_sc(f64(code - 14usize), v) }
    if code == 16usize || code == 17usize { ret gm.bessel_in(i64(code - 16usize), v) }
    if code == 18usize || code == 19usize { ret gm.bessel_kn(i64(code - 18usize), v) }
    if code == 20usize { ret sph(a, 0usize, usize(p), v) }
    if code == 21usize { ret sph(a, 1usize, usize(p), v) }
    if code == 22usize { ret gm.sph_i_scaled(usize(p), v) }
    if code == 23usize { ret gm.sph_k_scaled(usize(p), v) }
    if code >= 24usize && code <= 26usize { ret sph(a, 0usize, code - 24usize, v) }
    if code >= 27usize && code <= 29usize { ret sph(a, 1usize, code - 27usize, v) }
    if code >= 30usize && code <= 32usize { ret gm.sph_i_scaled(code - 30usize, v) }
    ret gm.sph_k_scaled(code - 33usize, v)
}

fn arr_case(a: *mem.Arena, x: []const f64) -> f64 {
    let kind = usize(x[0usize])
    let j = usize(x[1usize])
    let p1 = x[2usize]
    let xv = x[4usize]
    if kind == 0usize { ret gm.bessel_jnu_q(a, p1 + f64(j), xv) }
    if kind == 1usize { ret gm.bessel_in(i64(p1) + i64(j), xv) }
    if kind == 2usize { ret gm.in_sc(p1 + f64(j), xv) }
    if kind == 3usize { ret gm.bessel_kn(i64(p1) + i64(j), xv) }
    if kind == 4usize { ret gm.kn_sc(p1 + f64(j), xv) }
    if kind == 5usize || kind == 6usize { ret sph(a, 0usize, j, xv) }
    if kind == 7usize { ret sph(a, 1usize, j, xv) }
    if kind == 8usize { ret gm.sph_i_scaled(j, xv) }
    if kind == 9usize { ret gm.sph_k_scaled(j, xv) }
    if kind == 10usize { ret gs.bessel_yn(a, usize(p1) + j, xv) }
    if kind == 11usize { ret gs.gegenpoly_n(j, x[3usize], xv) }
    ret gm.bessel_jnu_q(a, p1, xv)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "m") { ret m_case(a, x) }
    if str.eq(k, "arr") { ret arr_case(a, x) }
    ret gm.leg_value(usize(x[0usize]), usize(x[1usize]), x[2usize], usize(x[5usize]), usize(x[6usize]), x[4usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslmore.json")
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
