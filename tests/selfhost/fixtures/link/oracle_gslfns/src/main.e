// e.algo.stat.gslfns against gsl. tests/oracle/gslfns.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gslfns`; the layout is at the top of scripts/r_oracle/groups/gslfns.R.

use e.algo.stat.gslfns as gs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "h") {
        let code = usize(x[0usize])
        if code == 0usize { ret gs.gamma_inc(x[1usize], x[2usize]) }
        if code == 1usize { ret gs.gamma_inc_p(x[1usize], x[2usize]) }
        if code == 2usize { ret gs.gamma_inc_q(x[1usize], x[2usize]) }
        if code == 3usize { ret gs.beta_inc(x[1usize], x[2usize], x[3usize]) }
        if code == 4usize { ret gs.poch(x[1usize], x[2usize]) }
        if code == 5usize { ret gs.lnpoch(x[1usize], x[2usize]) }
        if code == 6usize { ret gs.pochrel(x[1usize], x[2usize]) }
        if code == 7usize { ret gs.erf(x[1usize]) }
        if code == 8usize { ret gs.erfc(x[1usize]) }
        if code == 9usize { ret gs.log_erfc(x[1usize]) }
        if code == 10usize { ret gs.sinc(x[1usize]) }
        if code == 11usize { ret gs.choose_(x[1usize], x[2usize]) }
        if code == 12usize { ret gs.lnbeta(x[1usize], x[2usize]) }
        if code == 13usize { ret gs.lnfact(x[1usize]) }
        if code == 14usize { ret gs.doublefact(usize(x[1usize])) }
        if code == 15usize { ret gs.lndoublefact(usize(x[1usize])) }
        if code == 16usize { ret gs.lnsinh(x[1usize]) }
        if code == 17usize { ret gs.lncosh(x[1usize]) }
        ret gs.taylorcoeff(usize(x[1usize]), x[2usize])
    }
    if str.eq(k, "h2") {
        let code = usize(x[0usize])
        if code == 0usize { ret gs.psi_1(x[1usize]) }
        if code == 1usize { ret gs.psi_n(usize(x[1usize]), x[2usize]) }
        if code == 2usize { ret gs.gammainv(x[1usize]) }
        if code == 3usize { ret gs.gammastar(x[1usize]) }
        ret gs.hypot(x[1usize], x[2usize])
    }
    if str.eq(k, "h3") {
        let code = usize(x[0usize])
        if code == 0usize { ret gs.si(a, x[1usize]) }
        if code == 1usize { ret gs.ci(a, x[1usize]) }
        if code == 2usize { ret gs.shi(a, x[1usize]) }
        if code == 3usize { ret gs.chi(a, x[1usize]) }
        if code == 4usize { ret gs.atanint(a, x[1usize]) }
        if code == 5usize { ret gs.expint_3(a, x[1usize]) }
        if code == 6usize { ret gs.expint_en(a, usize(x[1usize]), x[2usize]) }
        if code == 7usize { ret gs.eta(x[1usize]) }
        if code == 8usize { ret gs.zetam1(x[1usize]) }
        if code == 9usize { ret gs.laguerre_n(usize(x[1usize]), x[2usize], x[3usize]) }
        if code == 10usize { ret gs.gegenpoly_n(usize(x[1usize]), x[2usize], x[3usize]) }
        if code == 11usize { ret gs.legendre_q0(x[1usize]) }
        if code == 12usize { ret gs.legendre_ql(usize(x[1usize]), x[2usize]) }
        if code == 13usize { ret gs.log_1plusx(x[1usize]) }
        if code == 14usize { ret gs.log_1plusx_mx(x[1usize]) }
        if code == 15usize { ret gs.ellint_rc(x[1usize], x[2usize]) }
        let (jo, g1) = mem.alloc[f64](a, 3usize)
        let (jm, g2) = mem.alloc[f64](a, 32usize)
        let (jn, g3) = mem.alloc[f64](a, 32usize)
        if g1 != ok || g2 != ok || g3 != ok { os.exit(4) }
        gs.elljac(x[1usize], x[2usize], jo, jm, jn)
        ret jo[code - 16usize]
    }
    if str.eq(k, "h4") {
        let code = usize(x[0usize])
        if code == 0usize { ret gs.ellint_rj(x[1usize], x[2usize], x[3usize], x[4usize]) }
        if code == 1usize { ret gs.ellint_p(x[1usize], x[2usize], x[3usize]) }
        if code == 2usize { ret gs.ellint_d(x[1usize], x[2usize]) }
        ret gs.bessel_yn(a, usize(x[1usize]), x[2usize])
    }
    if str.eq(k, "debye") { ret gs.debye(a, usize(x[0usize]), x[1usize]) }
    if str.eq(k, "transport") { ret gs.transport(a, usize(x[0usize]), x[1usize]) }
    if str.eq(k, "fd") { ret gs.fermi_dirac(a, x[0usize], x[1usize]) }
    if str.eq(k, "sync") {
        if x[0usize] == 1.0f64 { ret gs.synchrotron_1(a, x[1usize]) }
        ret gs.synchrotron_2(x[1usize])
    }
    if str.eq(k, "knu") { ret gs.bessel_knu(x[0usize], x[1usize]) }
    if str.eq(k, "inu") { ret gs.bessel_inu(x[0usize], x[1usize]) }
    if str.eq(k, "jn") { ret gs.bessel_jn(i64(x[0usize]), x[1usize]) }
    if str.eq(k, "w0") { ret gs.lambert_w(x[0usize], 0i64) }
    if str.eq(k, "wm1") { ret gs.lambert_w(x[0usize], 0i64 - 1i64) }
    if str.eq(k, "e1") { ret gs.expint_e1(x[0usize]) }
    if str.eq(k, "ei") { ret gs.expint_ei(x[0usize]) }
    if str.eq(k, "dawson") { ret gs.dawson(x[0usize]) }
    if str.eq(k, "clausen") { ret gs.clausen(x[0usize]) }
    if str.eq(k, "airy_ai") { ret gs.airy_ai(x[0usize]) }
    if str.eq(k, "airy_bi") { ret gs.airy_bi(x[0usize]) }
    if str.eq(k, "kcomp") { ret gs.ellint_kcomp(x[0usize]) }
    if str.eq(k, "ecomp") { ret gs.ellint_ecomp(x[0usize]) }
    if str.eq(k, "ellf") { ret gs.ellint_f(x[0usize], x[1usize]) }
    if str.eq(k, "elle") { ret gs.ellint_e(x[0usize], x[1usize]) }
    if str.eq(k, "rf") { ret gs.ellint_rf(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "rd") { ret gs.ellint_rd(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "f01") { ret gs.hyperg_0f1(x[0usize], x[1usize]) }
    if str.eq(k, "f11") { ret gs.hyperg_1f1(x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "f21") { ret gs.hyperg_2f1(x[0usize], x[1usize], x[2usize], x[3usize]) }
    if str.eq(k, "pl") { ret gs.legendre_pl(usize(x[0usize]), x[1usize]) }
    if str.eq(k, "plm") { ret gs.legendre_plm(usize(x[0usize]), usize(x[1usize]), x[2usize]) }
    if str.eq(k, "fd0") { ret gs.fermi_dirac_0(x[0usize]) }
    if str.eq(k, "dilog") { ret gs.dilog(x[0usize]) }
    if str.eq(k, "psi") { ret gs.psi(x[0usize]) }
    if str.eq(k, "hzeta") { ret gs.hzeta(x[0usize], x[1usize]) }
    ret gs.hzeta(x[0usize], 1.0f64)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gslfns.json")
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
