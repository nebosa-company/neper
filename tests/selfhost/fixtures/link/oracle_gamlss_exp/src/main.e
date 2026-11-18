// e.algo.stat.gamlssdist's EXP and RG functions against gamlss.dist (dEXP, pEXP, qEXP, dRG, pRG, qRG, dPARETO2, pPARETO2, qPARETO2, dPARETO1, pPARETO1, qPARETO1, dNO, pNO, qNO, dPO, pPO, qPO). tests/oracle/gamlss_exp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_exp`; the layout of every case is at the top of scripts/r_oracle/groups/gamlss_exp.R.

use e.algo.stat.gamlssdist as gd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let which = usize(z[0usize])
    let mu = z[1usize]
    let sigma = z[2usize]
    let x = z[3usize]
    if which == 0usize { ret gd.dexp_mu(x, mu) }
    if which == 1usize { ret gd.pexp_mu(x, mu) }
    if which == 2usize { ret gd.qexp_mu(x, mu) }
    if which == 3usize { ret gd.drg(x, mu, sigma) }
    if which == 4usize { ret gd.prg(x, mu, sigma) }
    if which == 5usize { ret gd.qrg(x, mu, sigma) }
    if which == 6usize { ret gd.dpareto2(x, mu, sigma) }
    if which == 7usize { ret gd.ppareto2(x, mu, sigma) }
    if which == 8usize { ret gd.qpareto2(x, mu, sigma) }
    if which == 9usize { ret gd.dpareto1(x, mu) }
    if which == 10usize { ret gd.ppareto1(x, mu) }
    if which == 11usize { ret gd.qpareto1(x, mu) }
    if which == 12usize { ret gd.dno(x, mu, sigma) }
    if which == 13usize { ret gd.pno(x, mu, sigma) }
    if which == 14usize { ret gd.qno(x, mu, sigma) }
    if which == 15usize { ret gd.dpo(x, mu) }
    if which == 16usize { ret gd.ppo(x, mu) }
    if which == 17usize { ret gd.qpo(x, mu) }
    if which == 18usize { ret gd.dga(x, mu, sigma) }
    if which == 19usize { ret gd.pga(x, mu, sigma) }
    if which == 20usize { ret gd.qga(x, mu, sigma) }
    if which == 21usize { ret gd.dwei(x, mu, sigma) }
    if which == 22usize { ret gd.pwei(x, mu, sigma) }
    if which == 23usize { ret gd.qwei(x, mu, sigma) }
    if which == 24usize { ret gd.dlogno(x, mu, sigma) }
    if which == 25usize { ret gd.plogno(x, mu, sigma) }
    if which == 26usize { ret gd.qlogno(x, mu, sigma) }
    if which == 27usize { ret gd.pig(x, mu, sigma) }
    if which == 28usize { ret gd.pzip(x, mu, sigma) }
    if which == 29usize { ret gd.qzip(x, mu, sigma) }
    if which == 30usize { ret gd.dnbi(x, mu, sigma) }
    if which == 31usize { ret gd.pnbi(x, mu, sigma) }
    if which == 32usize { ret gd.qnbi(x, mu, sigma) }
    let nu = z[4usize]
    if which == 33usize { ret gd.dtf(x, mu, sigma, nu) }
    if which == 34usize { ret gd.ptf(x, mu, sigma, nu) }
    if which == 35usize { ret gd.qtf(x, mu, sigma, nu) }
    if which == 36usize { ret gd.pbccg(x, mu, sigma, nu) }
    if which == 37usize { ret gd.qbccg(x, mu, sigma, nu) }
    if which == 38usize { ret gd.dgp(x, mu, sigma) }
    if which == 39usize { ret gd.pgp(x, mu, sigma) }
    if which == 40usize { ret gd.qgp(x, mu, sigma) }
    if which == 41usize { ret gd.dbe(x, mu, sigma) }
    if which == 42usize { ret gd.pbe(x, mu, sigma) }
    if which == 43usize { ret gd.qbe(x, mu, sigma) }
    if which == 44usize { ret gd.dlno(x, mu, sigma, nu) }
    if which == 45usize { ret gd.plno(x, mu, sigma, nu) }
    if which == 46usize { ret gd.qlno(x, mu, sigma, nu) }
    if which == 47usize { ret gd.dgg(x, mu, sigma, nu) }
    if which == 48usize { ret gd.pgg(x, mu, sigma, nu) }
    if which == 49usize { ret gd.qgg(x, mu, sigma, nu) }
    let tau = z[5usize]
    if which == 50usize { ret gd.dgb2(x, mu, sigma, nu, tau) }
    if which == 51usize { ret gd.pgb2(x, mu, sigma, nu, tau) }
    if which == 52usize { ret gd.qgb2(x, mu, sigma, nu, tau) }
    if which == 53usize { ret gd.dbi(x, mu, tau) }
    if which == 54usize { ret gd.pbi(x, mu, tau) }
    if which == 55usize { ret gd.qbi(x, mu, tau) }
    if which == 56usize { ret gd.digamma_(x, mu, sigma) }
    if which == 57usize { ret gd.pigamma(x, mu, sigma) }
    if which == 58usize { ret gd.qigamma(x, mu, sigma) }
    if which == 59usize { ret gd.drge(x, mu, sigma, nu) }
    if which == 60usize { ret gd.prge(x, mu, sigma, nu) }
    if which == 61usize { ret gd.qrge(x, mu, sigma, nu) }
    if which == 62usize { ret gd.dno2(x, mu, sigma) }
    if which == 63usize { ret gd.pno2(x, mu, sigma) }
    if which == 64usize { ret gd.qno2(x, mu, sigma) }
    if which == 65usize { ret gd.dgeom_mu(x, mu) }
    if which == 66usize { ret gd.pgeom_mu(x, mu) }
    if which == 67usize { ret gd.qgeom_mu(x, mu) }
    if which == 68usize { ret gd.dgeomo(x, mu) }
    if which == 69usize { ret gd.pgeomo(x, mu) }
    if which == 70usize { ret gd.qgeomo(x, mu) }
    if which == 71usize { ret gd.dwei2(x, mu, sigma) }
    if which == 72usize { ret gd.pwei2(x, mu, sigma) }
    if which == 73usize { ret gd.qwei2(x, mu, sigma) }
    if which == 74usize { ret gd.dwei3(x, mu, sigma) }
    if which == 75usize { ret gd.pwei3(x, mu, sigma) }
    if which == 76usize { ret gd.qwei3(x, mu, sigma) }
    if which == 77usize { ret gd.dlogno2(x, mu, sigma) }
    if which == 78usize { ret gd.plogno2(x, mu, sigma) }
    if which == 79usize { ret gd.qlogno2(x, mu, sigma) }
    if which == 80usize { ret gd.dbeo(x, mu, sigma) }
    if which == 81usize { ret gd.pbeo(x, mu, sigma) }
    if which == 82usize { ret gd.qbeo(x, mu, sigma) }
    if which == 83usize { ret gd.dtf2(x, mu, sigma, nu) }
    if which == 84usize { ret gd.ptf2(x, mu, sigma, nu) }
    if which == 85usize { ret gd.qtf2(x, mu, sigma, nu) }
    if which == 86usize { ret gd.dzibi(x, mu, sigma, tau) }
    if which == 87usize { ret gd.pzibi(x, mu, sigma, tau) }
    if which == 88usize { ret gd.qzibi(x, mu, sigma, tau) }
    if which == 89usize { ret gd.dzabi(x, mu, sigma, tau) }
    if which == 90usize { ret gd.pzabi(x, mu, sigma, tau) }
    if which == 91usize { ret gd.qzabi(x, mu, sigma, tau) }
    if which == 92usize { ret gd.dzap(x, mu, sigma) }
    if which == 93usize { ret gd.pzap(x, mu, sigma) }
    if which == 94usize { ret gd.qzap(x, mu, sigma) }
    if which == 95usize { ret gd.dzip2(x, mu, sigma) }
    if which == 96usize { ret gd.pzip2(x, mu, sigma) }
    if which == 97usize { ret gd.qzip2(x, mu, sigma) }
    if which == 98usize { ret gd.dzanbi(x, mu, sigma, nu) }
    if which == 99usize { ret gd.pzanbi(x, mu, sigma, nu) }
    if which == 100usize { ret gd.qzanbi(x, mu, sigma, nu) }
    if which == 101usize { ret gd.dzinbi(x, mu, sigma, nu) }
    if which == 102usize { ret gd.pzinbi(x, mu, sigma, nu) }
    if which == 103usize { ret gd.qzinbi(x, mu, sigma, nu) }
    if which == 104usize { ret gd.dzaga(x, mu, sigma, nu) }
    if which == 105usize { ret gd.pzaga(x, mu, sigma, nu) }
    if which == 106usize { ret gd.qzaga(x, mu, sigma, nu) }
    if which == 107usize { ret gd.dpe_full(x, mu, sigma, nu) }
    if which == 108usize { ret gd.ppe(x, mu, sigma, nu) }
    if which == 109usize { ret gd.qpe(x, mu, sigma, nu) }
    if which == 110usize { ret gd.degb2(x, mu, sigma, nu, tau) }
    if which == 111usize { ret gd.pegb2(x, mu, sigma, nu, tau) }
    if which == 112usize { ret gd.qegb2(x, mu, sigma, nu, tau) }
    if which == 113usize { ret gd.dpareto2o(x, mu, sigma) }
    if which == 114usize { ret gd.ppareto2o(x, mu, sigma) }
    if which == 115usize { ret gd.qpareto2o(x, mu, sigma) }
    if which == 116usize { ret gd.dlg(x, mu) }
    if which == 117usize { ret gd.plg(x, mu) }
    if which == 118usize { ret gd.qlg(x, mu, tau) }
    if which == 119usize { ret gd.dyule(x, mu) }
    if which == 120usize { ret gd.pyule(x, mu) }
    if which == 121usize { ret gd.qyule(x, mu, tau) }
    if which == 122usize { ret gd.dpareto1o(x, mu, sigma) }
    if which == 123usize { ret gd.ppareto1o(x, mu, sigma) }
    if which == 124usize { ret gd.qpareto1o(x, mu, sigma) }
    if which == 125usize { ret gd.dnbii(x, mu, sigma) }
    if which == 126usize { ret gd.pnbii(x, mu, sigma) }
    if which == 127usize { ret gd.qnbii(x, mu, sigma) }
    if which == 128usize { ret gd.dlogitno(x, mu, sigma) }
    if which == 129usize { ret gd.plogitno(x, mu, sigma) }
    if which == 130usize { ret gd.qlogitno(x, mu, sigma) }
    if which == 131usize { ret gd.dwaring(x, mu, sigma) }
    if which == 132usize { ret gd.pwaring(x, mu, sigma) }
    if which == 133usize { ret gd.dzalg(x, mu, sigma) }
    if which == 134usize { ret gd.pzalg(x, mu, sigma) }
    if which == 135usize { ret gd.dgpo(x, mu, sigma) }
    if which == 136usize { ret gd.qexgaus(x, mu, sigma, nu) }
    if which == 137usize { ret gd.pjsu(x, mu, sigma, nu, tau) }
    if which == 138usize { ret gd.qjsu(x, mu, sigma, nu, tau) }
    if which == 139usize { ret gd.djsuo(x, mu, sigma, nu, tau) }
    if which == 140usize { ret gd.pjsuo(x, mu, sigma, nu, tau) }
    if which == 141usize { ret gd.qjsuo(x, mu, sigma, nu, tau) }
    if which == 142usize { ret gd.dshasho(x, mu, sigma, nu, tau) }
    if which == 143usize { ret gd.pshasho(x, mu, sigma, nu, tau) }
    if which == 144usize { ret gd.qshasho(x, mu, sigma, nu, tau) }
    if which == 145usize { ret gd.pshash(x, mu, sigma, nu, tau) }
    if which == 146usize { ret gd.qshash(x, mu, sigma, nu, tau) }
    if which == 147usize { ret gd.dbct(x, mu, sigma, nu, tau) }
    if which == 148usize { ret gd.pbct(x, mu, sigma, nu, tau) }
    if which == 149usize { ret gd.qbct(x, mu, sigma, nu, tau) }
    if which == 150usize { ret gd.dbcto(x, mu, sigma, nu, tau) }
    if which == 151usize { ret gd.pbct(x, mu, sigma, nu, tau) }
    if which == 152usize { ret gd.qbct(x, mu, sigma, nu, tau) }
    if which == 153usize { ret gd.dbccg(x, mu, sigma, nu) }
    if which == 154usize { ret gd.pbccg(x, mu, sigma, nu) }
    if which == 155usize { ret gd.qbccg(x, mu, sigma, nu) }
    if which == 156usize { ret gd.dshasho2(x, mu, sigma, nu, tau) }
    if which == 157usize { ret gd.pshasho2(x, mu, sigma, nu, tau) }
    ret gd.qshasho2(x, mu, sigma, nu, tau)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_exp.json")
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
