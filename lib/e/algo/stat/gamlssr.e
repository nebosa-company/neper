// R gamlss.dist random numbers for every family: rfam draws one value of r<FAMILY>(n, ...) from the stream (the package's r functions draw runif(n) and apply the quantile function, or call
// the base generators rnorm, rexp, rlogis, rlnorm, rpois and rweibull; every draw consumes the stream in the package's order). The quantile calls are the ones the package's r functions make,
// including those that leave a parameter at its default: rGP calls qGB2 without nu and tau, rZINBF calls qZINBF without tau (0.1) and rZISICHEL calls qZISICHEL without tau (0.1), and
// rBCCGo, rBCPEo and rBCTo call the quantile of the other parametrisation.
//
// fam indexes the package's families in alphabetical order: 0 BB, 1 BCCG, 2 BCCGo, 3 BCPE, 4 BCPEo, 5 BCT, 6 BCTo, 7 BE, 8 BEINF, 9 BEINF0, 10 BEINF1, 11 BEo, 12 BEOI, 13 BEZI, 14 BI, 15 BNB,
// 16 DBI, 17 DBURR12, 18 DEL, 19 DPO, 20 EGB2, 21 EXP, 22 GA, 23 GAF, 24 GB1, 25 GB2, 26 GEOM, 27 GEOMo, 28 GG, 29 GIG, 30 GP, 31 GPO, 32 GT, 33 GU, 34 IG, 35 IGAMMA, 36 JSU, 37 JSUo, 38 LG,
// 39 LNO, 40 LO, 41 LOGITNO, 42 LOGNO, 43 LOGNO2, 44 LOGSHASH, 45 LQNO, 46 MN3, 47 MN4, 48 MN5, 49 NBF, 50 NBI, 51 NBII, 52 NET, 53 NO, 54 NO2, 55 NOF, 56 PARETO, 57 PARETO1, 58 PARETO1o,
// 59 PARETO2, 60 PARETO2o, 61 PE, 62 PE2, 63 PIG, 64 PIG2, 65 PO, 66 RG, 67 RGE, 68 SEP, 69 SEP1, 70 SEP2, 71 SEP3, 72 SEP4, 73 SHASH, 74 SHASHo, 75 SHASHo2, 76 SI, 77 SICHEL, 78 SIMPLEX,
// 79 SN1, 80 SN2, 81 SST, 82 ST1, 83 ST2, 84 ST3, 85 ST3C, 86 ST4, 87 ST5, 88 TF, 89 TF2, 90 WARING, 91 WEI, 92 WEI2, 93 WEI3, 94 YULE, 95 ZABB, 96 ZABI, 97 ZABNB, 98 ZAGA, 99 ZAIG, 100 ZALG,
// 101 ZANBI, 102 ZAP, 103 ZAPIG, 104 ZASICHEL, 105 ZAZIPF, 106 ZIBB, 107 ZIBI, 108 ZIBNB, 109 ZINBF, 110 ZINBI, 111 ZIP, 112 ZIP2, 113 ZIPF, 114 ZIPIG, 115 ZISICHEL.

use e.math
use e.algo.rand.r as rg
use e.algo.rand.rdist as rds
use e.algo.stat.gamlssdist as gd
use e.algo.stat.gamlssq as gq
use e.mem

fn families() -> usize { ret 116usize }

// the families whose r function returns as.integer(...)
fn is_int(fam: usize) -> bool {
    if fam == 0usize || fam == 14usize || fam == 15usize || fam == 16usize || fam == 17usize || fam == 18usize || fam == 19usize { ret true }
    if fam == 26usize || fam == 27usize || fam == 38usize { ret true }
    if fam >= 46usize && fam <= 51usize { ret true }
    if fam == 64usize || fam == 65usize || fam == 76usize || fam == 77usize || fam == 90usize || fam == 94usize { ret true }
    if fam == 95usize || fam == 96usize || fam == 97usize { ret true }
    if fam >= 100usize && fam <= 102usize { ret true }
    if fam == 103usize || fam == 104usize || fam == 105usize { ret true }
    if fam >= 106usize && fam <= 115usize && fam != 98usize && fam != 99usize { ret true }
    ret false
}

// the quantile the family's r function applies to a uniform
fn qfam(a: *mem.Arena, fam: usize, p: f64, mu: f64, sg: f64, nu: f64, tau: f64, bd: f64) -> f64 {
    let mx = 10000.0f64
    if fam == 0usize { ret gq.qbb(p, mu, sg, bd) }
    if fam == 1usize || fam == 2usize { ret gd.qbccg(p, mu, sg, nu) }
    if fam == 3usize || fam == 4usize { ret gd.qbcpe(p, mu, sg, nu, tau) }
    if fam == 5usize || fam == 6usize { ret gd.qbct(p, mu, sg, nu, tau) }
    if fam == 7usize { ret gd.qbe(p, mu, sg) }
    if fam == 8usize { ret gd.qbeinf(p, mu, sg, nu, tau) }
    if fam == 9usize { ret gd.qbeinf0(p, mu, sg, nu) }
    if fam == 10usize { ret gd.qbeinf1(p, mu, sg, nu) }
    if fam == 11usize { ret gd.qbeo(p, mu, sg) }
    if fam == 12usize { ret gd.qbeoi(p, mu, sg, nu) }
    if fam == 13usize { ret gd.qbezi(p, mu, sg, nu) }
    if fam == 14usize { ret gd.qbi(p, mu, bd) }
    if fam == 15usize { ret gq.qbnb(p, mu, sg, nu, mx) }
    if fam == 16usize { ret gd.qdbi(p, mu, sg, bd) }
    if fam == 17usize { ret gd.qdburr12(p, mu, sg, nu) }
    if fam == 18usize { ret gd.qdel(p, mu, sg, nu) }
    if fam == 19usize { ret gd.qdpo(p, mu, sg) }
    if fam == 20usize { ret gd.qegb2(p, mu, sg, nu, tau) }
    if fam == 22usize { ret gd.qga(p, mu, sg) }
    if fam == 23usize { ret gd.qgaf(p, mu, sg, nu) }
    if fam == 24usize { ret gd.qgb1(p, mu, sg, nu, tau) }
    if fam == 25usize { ret gd.qgb2(p, mu, sg, nu, tau) }
    if fam == 26usize { ret gd.qgeom_mu(p, mu) }
    if fam == 27usize { ret gd.qgeomo(p, mu) }
    if fam == 28usize { ret gd.qgg(p, mu, sg, nu) }
    if fam == 29usize { ret gd.qgig(a, p, mu, sg, nu) }
    if fam == 30usize { ret gd.qgb2(p, mu, sg, 1.0f64, 0.5f64) }
    if fam == 31usize { ret gq.qgpo(p, mu, sg, mx) }
    if fam == 32usize { ret gd.qgt(a, p, mu, sg, nu, tau) }
    if fam == 33usize { ret gd.qgu(p, mu, sg) }
    if fam == 34usize { ret gd.qig(p, mu, sg) }
    if fam == 35usize { ret gd.qigamma(p, mu, sg) }
    if fam == 36usize { ret gd.qjsu(p, mu, sg, nu, tau) }
    if fam == 37usize { ret gd.qjsuo(p, mu, sg, nu, tau) }
    if fam == 38usize { ret gd.qlg(p, mu, mx) }
    if fam == 39usize { ret gd.qlno(p, mu, sg, nu) }
    if fam == 44usize { ret gd.qlogshash(p, mu, sg, nu, tau) }
    if fam >= 46usize && fam <= 48usize { ret gd.family_mn(2usize, fam - 43usize, p, mu, sg, nu, tau) }
    if fam == 49usize { ret gq.qnbf(p, mu, sg, nu) }
    if fam == 50usize { ret gd.qnbi(p, mu, sg) }
    if fam == 51usize { ret gd.qnbii(p, mu, sg) }
    if fam == 52usize { ret gq.qnet(p, mu, sg, nu, tau) }
    if fam == 55usize { ret gq.qnof(p, mu, sg, nu) }
    if fam == 56usize { ret gd.qpareto(p, mu) }
    if fam == 57usize { ret gd.qpareto1(p, mu) }
    if fam == 58usize { ret gd.qpareto1o(p, mu, sg) }
    if fam == 59usize { ret gd.qpareto2(p, mu, sg) }
    if fam == 60usize { ret gd.qpareto2o(p, mu, sg) }
    if fam == 61usize { ret gd.qpe(p, mu, sg, nu) }
    if fam == 62usize { ret gd.qpe2(p, mu, sg, nu) }
    if fam == 63usize { ret gq.qpig(p, mu, sg, mx) }
    if fam == 64usize { ret gq.qpig2(p, mu, sg, mx) }
    if fam == 66usize { ret gd.qrg(p, mu, sg) }
    if fam == 67usize { ret gd.qrge(p, mu, sg, nu) }
    if fam == 68usize { ret gd.qsep(a, p, mu, sg, nu, tau) }
    if fam == 69usize { ret gq.qsep1(a, p, mu, sg, nu, tau) }
    if fam == 70usize { ret gq.qsep2(a, p, mu, sg, nu, tau) }
    if fam == 71usize { ret gd.qsep3(p, mu, sg, nu, tau) }
    if fam == 72usize { ret gd.qsep4(p, mu, sg, nu, tau) }
    if fam == 73usize { ret gd.qshash(p, mu, sg, nu, tau) }
    if fam == 74usize { ret gd.qshasho(p, mu, sg, nu, tau) }
    if fam == 75usize { ret gd.qshasho2(p, mu, sg, nu, tau) }
    if fam == 76usize { ret gd.qsi(p, mu, sg, nu) }
    if fam == 77usize { ret gd.qsichel(p, mu, sg, nu) }
    if fam == 78usize { ret gd.qsimplex(a, p, mu, sg) }
    if fam == 79usize { ret gd.qsn1(a, p, mu, sg, nu) }
    if fam == 80usize { ret gd.qsn2(p, mu, sg, nu) }
    if fam == 81usize { ret gd.qsst(p, mu, sg, nu, tau) }
    if fam == 82usize { ret gq.qst1(a, p, mu, sg, nu, tau) }
    if fam == 83usize { ret gq.qst2(a, p, mu, sg, nu, tau) }
    if fam == 84usize || fam == 85usize { ret gd.qst3(p, mu, sg, nu, tau) }
    if fam == 86usize { ret gq.qst4(p, mu, sg, nu, tau) }
    if fam == 87usize { ret gq.qst5(p, mu, sg, nu, tau) }
    if fam == 88usize { ret gd.qtf(p, mu, sg, nu) }
    if fam == 89usize { ret gd.qtf2(p, mu, sg, nu) }
    if fam == 90usize { ret gq.qwaring(p, mu, sg, mx) }
    if fam == 94usize { ret gd.qyule(p, mu, mx) }
    if fam == 95usize { ret gq.qzabb(p, mu, sg, nu, bd) }
    if fam == 96usize { ret gd.qzabi(p, mu, sg, bd) }
    if fam == 97usize { ret gq.qzabnb(p, mu, sg, nu, tau, mx) }
    if fam == 98usize { ret gd.qzaga(p, mu, sg, nu) }
    if fam == 99usize { ret gd.qzaig(p, mu, sg, nu) }
    if fam == 100usize { ret gq.qzalg(p, mu, sg, mx) }
    if fam == 101usize { ret gd.qzanbi(p, mu, sg, nu) }
    if fam == 102usize { ret gd.qzap(p, mu, sg) }
    if fam == 103usize { ret gq.qzapig(p, mu, sg, nu, mx) }
    if fam == 104usize { ret gd.qzasichel(p, mu, sg, nu, tau) }
    if fam == 105usize { ret gq.qzazipf(p, mu, sg, mx) }
    if fam == 106usize { ret gq.qzibb(p, mu, sg, nu, bd) }
    if fam == 107usize { ret gd.qzibi(p, mu, sg, bd) }
    if fam == 108usize { ret gq.qzibnb(p, mu, sg, nu, 0.1f64, mx) }
    if fam == 109usize { ret gq.qzinbf(p, mu, sg, nu, 0.1f64) }
    if fam == 110usize { ret gd.qzinbi(p, mu, sg, nu) }
    if fam == 111usize { ret gd.qzip(p, mu, sg) }
    if fam == 112usize { ret gd.qzip2(p, mu, sg) }
    if fam == 113usize { ret gq.qzipf(p, mu, mx) }
    if fam == 114usize { ret gq.qzipig(p, mu, sg, nu, mx) }
    ret gd.qzisichel(p, mu, sg, nu, 0.1f64)
}

// one draw of r<FAMILY>(1, mu, sigma, nu, tau, bd) from the stream
fn rfam(a: *mem.Arena, r: *rg.Rng, fam: usize, mu: f64, sg: f64, nu: f64, tau: f64, bd: f64) -> f64 {
    if fam == 21usize { ret rg.rexp(r, mu) }
    if fam == 40usize { ret rds.rlogis(r, mu, sg) }
    if fam == 41usize {
        let rz = rg.rnorm(r, math.log[f64](mu / (1.0f64 - mu)), sg)
        ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - rz))
    }
    if fam == 42usize { ret rds.rlnorm(r, mu, sg) }
    if fam == 43usize { ret math.exp[f64](rg.rnorm(r, math.log[f64](mu), sg)) }
    if fam == 45usize { ret rg.rnorm(r, mu, math.sqrt[f64](mu * (1.0f64 + sg * mu))) }
    if fam == 53usize { ret rg.rnorm(r, mu, sg) }
    if fam == 54usize { ret rg.rnorm(r, mu, math.sqrt[f64](sg)) }
    if fam == 65usize { ret rds.rpois(r, mu) }
    if fam == 91usize { ret rds.rweibull(r, sg, mu) }
    if fam == 92usize { ret rds.rweibull(r, sg, math.pow[f64](mu, 0.0f64 - 1.0f64 / sg)) }
    if fam == 93usize { ret rds.rweibull(r, sg, gd.wei3_scale(mu, sg)) }
    let u = rg.unif(r)
    ret qfam(a, fam, u, mu, sg, nu, tau, bd)
}

// up to eight draws of r<FAMILY>(n, ...), with the package's vectorised behaviour: qMN3 starts from q <- 1 and so leaves every category 1 but the first draw NA, and qZIBNB and qZINBF
// re-assign pnew[pnew > 0] <- pnew, which puts the first values of pnew on the positions of the positive ones (and the quantile is then taken at those)
type Draws = struct { v: [8]f64 }

fn rfam_n(a: *mem.Arena, r: *rg.Rng, fam: usize, n: usize, mu: f64, sg: f64, nu: f64, tau: f64, bd: f64) -> Draws {
    var d: Draws = zero
    let mx = 10000.0f64
    if fam == 108usize || fam == 109usize {
        var u: [8]f64 = zero
        var pn: [8]f64 = zero
        var i = 0usize
        while i < n {
            u[i] = rg.unif(r)
            pn[i] = (u[i] - 0.1f64) / (1.0f64 - 0.1f64)
            i += 1usize
        }
        var j = 0usize
        i = 0usize
        while i < n {
            var pq = pn[i]
            if pn[i] > 0.0f64 {
                pq = pn[j]
                j += 1usize
            }
            if pq < 0.0f64 { pq = 0.0f64 }
            if fam == 108usize { d.v[i] = gq.qzibnb_pn(u[i], pq, mu, sg, nu, mx) } else { d.v[i] = gq.qzinbf_pn(u[i], pq, mu, sg, nu) }
            i += 1usize
        }
        ret d
    }
    var i = 0usize
    while i < n {
        d.v[i] = rfam(a, r, fam, mu, sg, nu, tau, bd)
        if fam == 46usize && i > 0usize && d.v[i] == 1.0f64 { d.v[i] = nan_() }
        i += 1usize
    }
    ret d
}

fn nan_() -> f64 { ret 0.0f64 / 0.0f64 }

// the value as the r function returns it: NaN or Inf, and an integer outside the range of as.integer, are NA, here the sentinel -1; the integer families truncate toward zero
fn rvalue(fam: usize, v: f64) -> f64 {
    if !(v - v == 0.0f64) { ret 0.0f64 - 1.0f64 }
    if is_int(fam) {
        if math.abs[f64](v) >= 2147483648.0f64 { ret 0.0f64 - 1.0f64 }
        if v < 0.0f64 { ret math.ceil[f64](v) }
        ret math.floor[f64](v)
    }
    ret v
}
