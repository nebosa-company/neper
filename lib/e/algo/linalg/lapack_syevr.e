// Reference LAPACK 3.12.1 dsyevr and everything under it (dsytrd/dsytd2/dlatrd, dstemr, dlarre, dlarrv, dlar1v, dlarrf, dlarrb,
// dlasq2, dormtr, ...), translated statement for statement from the Fortran so that eigenvalues AND the signs of the
// eigenvectors are the ones R's eigen(symmetric = TRUE) returns. Generated from the Fortran sources, not edited by hand.
// dsyevr_all at the end is the call La_rs makes: jobz V, range A, uplo L, abstol 0, after a workspace query.

use e.math
use e.mem
use e.algo.linalg.lapack_base as lbase

fn dsyevr(jobz: str, range: str, uplo: str, n: i64, a: []f64, lda: i64, vl: f64, vu: f64, il: i64, iu: i64, abstol: f64, m_ref: *i64, w: []f64, z: []f64, ldz: i64, isuppz: []i64, work: []f64, lwork: i64, iwork: []i64, liwork: i64, info_ref: *i64) {
    var m = *m_ref
    var info = *info_ref
    var alleig: bool = false
    var indeig: bool = false
    var lower: bool = false
    var lquery: bool = false
    var valeig: bool = false
    var wantz: bool = false
    var tryrac: bool = false
    var order: str = ""
    var i: i64 = 0i64
    var ieeeok: i64 = 0i64
    var iinfo: i64 = 0i64
    var imax: i64 = 0i64
    var indd: i64 = 0i64
    var inddd: i64 = 0i64
    var inde: i64 = 0i64
    var indee: i64 = 0i64
    var indibl: i64 = 0i64
    var indifl: i64 = 0i64
    var indisp: i64 = 0i64
    var indiwo: i64 = 0i64
    var indtau: i64 = 0i64
    var indwk: i64 = 0i64
    var indwkn: i64 = 0i64
    var iscale: i64 = 0i64
    var j: i64 = 0i64
    var jj: i64 = 0i64
    var liwmin: i64 = 0i64
    var llwork: i64 = 0i64
    var llwrkn: i64 = 0i64
    var lwkopt: i64 = 0i64
    var lwmin: i64 = 0i64
    var nb: i64 = 0i64
    var nsplit: i64 = 0i64
    var abstll: f64 = 0.0f64
    var anrm: f64 = 0.0f64
    var bignum: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var rmax: f64 = 0.0f64
    var rmin: f64 = 0.0f64
    var safmin: f64 = 0.0f64
    var sigma: f64 = 0.0f64
    var smlnum: f64 = 0.0f64
    var tmp1: f64 = 0.0f64
    var vll: f64 = 0.0f64
    var vuu: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            ieeeok = lbase.ilaenv(10i64, "DSYEVR", "N", 1i64, 2i64, 3i64, 4i64)
            lower = lbase.lsame(uplo, "L")
            wantz = lbase.lsame(jobz, "V")
            alleig = lbase.lsame(range, "A")
            valeig = lbase.lsame(range, "V")
            indeig = lbase.lsame(range, "I")
            lquery = ((((lwork == (-1i64))) || ((liwork == (-1i64)))))
            if (n <= 1i64) {
                lwmin = 1i64
                liwmin = 1i64
            } else {
                lwmin = (26i64 * n)
                liwmin = (10i64 * n)
            }
            info = 0i64
            if (!((wantz || lbase.lsame(jobz, "N")))) {
                info = (-1i64)
            } else if (!(((alleig || valeig) || indeig))) {
                info = (-2i64)
            } else if (!((lower || lbase.lsame(uplo, "U")))) {
                info = (-3i64)
            } else if (n < 0i64) {
                info = (-4i64)
            } else if (lda < lbase.i_max(1i64, n)) {
                info = (-6i64)
            } else {
                if valeig {
                    if ((n > 0i64) && (vu <= vl)) {
                        info = (-8i64)
                    }
                } else if indeig {
                    if ((il < 1i64) || (il > lbase.i_max(1i64, n))) {
                        info = (-9i64)
                    } else if ((iu < lbase.i_min(n, il)) || (iu > n)) {
                        info = (-10i64)
                    }
                }
            }
            if (info == 0i64) {
                if ((ldz < 1i64) || ((wantz && (ldz < n)))) {
                    info = (-15i64)
                } else if ((lwork < lwmin) && (!lquery)) {
                    info = (-18i64)
                } else if ((liwork < liwmin) && (!lquery)) {
                    info = (-20i64)
                }
            }
            if (info == 0i64) {
                nb = lbase.ilaenv(1i64, "DSYTRD", uplo, n, (-1i64), (-1i64), (-1i64))
                nb = lbase.i_max(nb, lbase.ilaenv(1i64, "DORMTR", uplo, n, (-1i64), (-1i64), (-1i64)))
                lwkopt = lbase.i_max((((nb + 1i64)) * n), lwmin)
                work[usize((1i64 - 1i64))] = f64(lwkopt)
                iwork[usize((1i64 - 1i64))] = liwmin
            }
            if (info != 0i64) {
                *m_ref = m
                *info_ref = info
                ret
            } else if lquery {
                *m_ref = m
                *info_ref = info
                ret
            }
            m = 0i64
            if (n == 0i64) {
                work[usize((1i64 - 1i64))] = 1.0f64
                *m_ref = m
                *info_ref = info
                ret
            }
            if (n == 1i64) {
                work[usize((1i64 - 1i64))] = 1.0f64
                if (alleig || indeig) {
                    m = 1i64
                    w[usize((1i64 - 1i64))] = a[usize((1i64 - 1i64) + (1i64 - 1i64) * lda)]
                } else {
                    if ((vl < a[usize((1i64 - 1i64) + (1i64 - 1i64) * lda)]) && (vu >= a[usize((1i64 - 1i64) + (1i64 - 1i64) * lda)])) {
                        m = 1i64
                        w[usize((1i64 - 1i64))] = a[usize((1i64 - 1i64) + (1i64 - 1i64) * lda)]
                    }
                }
                if wantz {
                    z[usize((1i64 - 1i64) + (1i64 - 1i64) * ldz)] = 1.0f64
                    isuppz[usize((1i64 - 1i64))] = 1i64
                    isuppz[usize((2i64 - 1i64))] = 1i64
                }
                *m_ref = m
                *info_ref = info
                ret
            }
            safmin = 2.2250738585072014e-308f64
            eps = 2.220446049250313e-16f64
            smlnum = (safmin / eps)
            bignum = (1.0f64 / smlnum)
            rmin = math.sqrt[f64](smlnum)
            rmax = lbase.f_min(math.sqrt[f64](bignum), (1.0f64 / math.sqrt[f64](math.sqrt[f64](safmin))))
            iscale = 0i64
            abstll = abstol
            if valeig {
                vll = vl
                vuu = vu
            }
            anrm = lbase.dlansy("M", uplo, n, a[0usize..], lda, work[0usize..])
            if ((anrm > 0.0f64) && (anrm < rmin)) {
                iscale = 1i64
                sigma = (rmin / anrm)
            } else if (anrm > rmax) {
                iscale = 1i64
                sigma = (rmax / anrm)
            }
            if (iscale == 1i64) {
                if lower {
                    j = 1i64
                    zc1 = (n - j) + 1i64
                    while zc1 > 0i64 {
                        lbase.dscal(((n - j) + 1i64), sigma, lbase.sl[f64](a[0usize..], usize((j - 1i64) + (j - 1i64) * lda)), 1i64)
                        j = j + 1i64
                        zc1 = zc1 - 1i64
                    }
                } else {
                    j = 1i64
                    zc2 = (n - j) + 1i64
                    while zc2 > 0i64 {
                        lbase.dscal(j, sigma, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (j - 1i64) * lda)), 1i64)
                        j = j + 1i64
                        zc2 = zc2 - 1i64
                    }
                }
                if (abstol > 0.0f64) {
                    abstll = (abstol * sigma)
                }
                if valeig {
                    vll = (vl * sigma)
                    vuu = (vu * sigma)
                }
            }
            indtau = 1i64
            indd = (indtau + n)
            inde = (indd + n)
            inddd = (inde + n)
            indee = (inddd + n)
            indwk = (indee + n)
            llwork = ((lwork - indwk) + 1i64)
            indibl = 1i64
            indisp = (indibl + n)
            indifl = (indisp + n)
            indiwo = (indifl + n)
            dsytrd(uplo, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((indd - 1i64))), lbase.sl[f64](work[0usize..], usize((inde - 1i64))), lbase.sl[f64](work[0usize..], usize((indtau - 1i64))), lbase.sl[f64](work[0usize..], usize((indwk - 1i64))), llwork, &iinfo)
            if !(((alleig || (((indeig && (il == 1i64)) && (iu == n))))) && (ieeeok == 1i64)) {
                pc = 2i64
                continue
            }
            if (!wantz) {
                lbase.dcopy(n, lbase.sl[f64](work[0usize..], usize((indd - 1i64))), 1i64, w[0usize..], 1i64)
                lbase.dcopy((n - 1i64), lbase.sl[f64](work[0usize..], usize((inde - 1i64))), 1i64, lbase.sl[f64](work[0usize..], usize((indee - 1i64))), 1i64)
                dsterf(n, w[0usize..], lbase.sl[f64](work[0usize..], usize((indee - 1i64))), &info)
            } else {
                lbase.dcopy((n - 1i64), lbase.sl[f64](work[0usize..], usize((inde - 1i64))), 1i64, lbase.sl[f64](work[0usize..], usize((indee - 1i64))), 1i64)
                lbase.dcopy(n, lbase.sl[f64](work[0usize..], usize((indd - 1i64))), 1i64, lbase.sl[f64](work[0usize..], usize((inddd - 1i64))), 1i64)
                if (abstol <= ((2.0f64 * f64(n)) * eps)) {
                    tryrac = true
                } else {
                    tryrac = false
                }
                dstemr(jobz, "A", n, lbase.sl[f64](work[0usize..], usize((inddd - 1i64))), lbase.sl[f64](work[0usize..], usize((indee - 1i64))), vl, vu, il, iu, &m, w[0usize..], z[0usize..], ldz, n, isuppz[0usize..], &tryrac, lbase.sl[f64](work[0usize..], usize((indwk - 1i64))), lwork, iwork[0usize..], liwork, &info)
                if (wantz && (info == 0i64)) {
                    indwkn = inde
                    llwrkn = ((lwork - indwkn) + 1i64)
                    dormtr("L", uplo, "N", n, m, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((indtau - 1i64))), z[0usize..], ldz, lbase.sl[f64](work[0usize..], usize((indwkn - 1i64))), llwrkn, &iinfo)
                }
            }
            if !(info == 0i64) {
                pc = 4i64
                continue
            }
            m = n
            pc = 5i64
            continue
        }
        if pc == 4i64 {
            pc = 3i64
        }
        if pc == 3i64 {
            info = 0i64
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            pc = 1i64
        }
        if pc == 1i64 {
            if wantz {
                order = "B"
            } else {
                order = "E"
            }
            dstebz(range, order, n, vll, vuu, il, iu, abstll, lbase.sl[f64](work[0usize..], usize((indd - 1i64))), lbase.sl[f64](work[0usize..], usize((inde - 1i64))), &m, &nsplit, w[0usize..], lbase.sl[i64](iwork[0usize..], usize((indibl - 1i64))), lbase.sl[i64](iwork[0usize..], usize((indisp - 1i64))), lbase.sl[f64](work[0usize..], usize((indwk - 1i64))), lbase.sl[i64](iwork[0usize..], usize((indiwo - 1i64))), &info)
            if wantz {
                dstein(n, lbase.sl[f64](work[0usize..], usize((indd - 1i64))), lbase.sl[f64](work[0usize..], usize((inde - 1i64))), m, w[0usize..], lbase.sl[i64](iwork[0usize..], usize((indibl - 1i64))), lbase.sl[i64](iwork[0usize..], usize((indisp - 1i64))), z[0usize..], ldz, lbase.sl[f64](work[0usize..], usize((indwk - 1i64))), lbase.sl[i64](iwork[0usize..], usize((indiwo - 1i64))), lbase.sl[i64](iwork[0usize..], usize((indifl - 1i64))), &info)
                indwkn = inde
                llwrkn = ((lwork - indwkn) + 1i64)
                dormtr("L", uplo, "N", n, m, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((indtau - 1i64))), z[0usize..], ldz, lbase.sl[f64](work[0usize..], usize((indwkn - 1i64))), llwrkn, &iinfo)
            }
            pc = 5i64
        }
        if pc == 5i64 {
            if (iscale == 1i64) {
                if (info == 0i64) {
                    imax = m
                } else {
                    imax = (info - 1i64)
                }
                lbase.dscal(imax, (1.0f64 / sigma), w[0usize..], 1i64)
            }
            if wantz {
                j = 1i64
                zc3 = ((m - 1i64) - j) + 1i64
                while zc3 > 0i64 {
                    i = 0i64
                    tmp1 = w[usize((j - 1i64))]
                    jj = (j + 1i64)
                    zc4 = (m - jj) + 1i64
                    while zc4 > 0i64 {
                        if (w[usize((jj - 1i64))] < tmp1) {
                            i = jj
                            tmp1 = w[usize((jj - 1i64))]
                        }
                        jj = jj + 1i64
                        zc4 = zc4 - 1i64
                    }
                    if (i != 0i64) {
                        w[usize((i - 1i64))] = w[usize((j - 1i64))]
                        w[usize((j - 1i64))] = tmp1
                        lbase.dswap(n, lbase.sl[f64](z[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldz)), 1i64, lbase.sl[f64](z[0usize..], usize((1i64 - 1i64) + (j - 1i64) * ldz)), 1i64)
                    }
                    j = j + 1i64
                    zc3 = zc3 - 1i64
                }
            }
            work[usize((1i64 - 1i64))] = f64(lwkopt)
            iwork[usize((1i64 - 1i64))] = liwmin
            *m_ref = m
            *info_ref = info
            ret
        }
    }
}

fn dsytd2(uplo: str, n: i64, a: []f64, lda: i64, d: []f64, e: []f64, tau: []f64, info_ref: *i64) {
    var info = *info_ref
    var upper: bool = false
    var i: i64 = 0i64
    var alpha: f64 = 0.0f64
    var taui: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
    var zc3: i64 = 0i64
    info = 0i64
    upper = lbase.lsame(uplo, "U")
    if ((!upper) && (!lbase.lsame(uplo, "L"))) {
        info = (-1i64)
    } else if (n < 0i64) {
        info = (-2i64)
    } else if (lda < lbase.i_max(1i64, n)) {
        info = (-4i64)
    }
    if (info != 0i64) {
        *info_ref = info
        ret
    }
    if (n <= 0i64) {
        *info_ref = info
        ret
    }
    if upper {
        i = (n - 1i64)
        zs2 = (-1i64)
        zc1 = ((1i64 - i) + zs2) / zs2
        while zc1 > 0i64 {
            lbase.dlarfg(i, &a[usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)], lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + ((i + 1i64) - 1i64) * lda)), 1i64, &taui)
            e[usize((i - 1i64))] = a[usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)]
            if (taui != 0.0f64) {
                a[usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)] = 1.0f64
                lbase.dsymv(uplo, i, taui, a[0usize..], lda, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + ((i + 1i64) - 1i64) * lda)), 1i64, 0.0f64, tau[0usize..], 1i64)
                alpha = (-((0.5f64 * taui) * lbase.ddot(i, tau[0usize..], 1i64, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + ((i + 1i64) - 1i64) * lda)), 1i64)))
                lbase.daxpy(i, alpha, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + ((i + 1i64) - 1i64) * lda)), 1i64, tau[0usize..], 1i64)
                lbase.dsyr2(uplo, i, (-1.0f64), lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + ((i + 1i64) - 1i64) * lda)), 1i64, tau[0usize..], 1i64, a[0usize..], lda)
                a[usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)] = e[usize((i - 1i64))]
            }
            d[usize(((i + 1i64) - 1i64))] = a[usize(((i + 1i64) - 1i64) + ((i + 1i64) - 1i64) * lda)]
            tau[usize((i - 1i64))] = taui
            i = i + zs2
            zc1 = zc1 - 1i64
        }
        d[usize((1i64 - 1i64))] = a[usize((1i64 - 1i64) + (1i64 - 1i64) * lda)]
    } else {
        i = 1i64
        zc3 = ((n - 1i64) - i) + 1i64
        while zc3 > 0i64 {
            lbase.dlarfg((n - i), &a[usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)], lbase.sl[f64](a[0usize..], usize((lbase.i_min((i + 2i64), n) - 1i64) + (i - 1i64) * lda)), 1i64, &taui)
            e[usize((i - 1i64))] = a[usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)]
            if (taui != 0.0f64) {
                a[usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)] = 1.0f64
                lbase.dsymv(uplo, (n - i), taui, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64, 0.0f64, lbase.sl[f64](tau[0usize..], usize((i - 1i64))), 1i64)
                alpha = (-((0.5f64 * taui) * lbase.ddot((n - i), lbase.sl[f64](tau[0usize..], usize((i - 1i64))), 1i64, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64)))
                lbase.daxpy((n - i), alpha, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64, lbase.sl[f64](tau[0usize..], usize((i - 1i64))), 1i64)
                lbase.dsyr2(uplo, (n - i), (-1.0f64), lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64, lbase.sl[f64](tau[0usize..], usize((i - 1i64))), 1i64, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + ((i + 1i64) - 1i64) * lda)), lda)
                a[usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)] = e[usize((i - 1i64))]
            }
            d[usize((i - 1i64))] = a[usize((i - 1i64) + (i - 1i64) * lda)]
            tau[usize((i - 1i64))] = taui
            i = i + 1i64
            zc3 = zc3 - 1i64
        }
        d[usize((n - 1i64))] = a[usize((n - 1i64) + (n - 1i64) * lda)]
    }
    *info_ref = info
    ret
}

fn dormtr(side: str, uplo: str, trans: str, m: i64, n: i64, a: []f64, lda: i64, tau: []f64, c: []f64, ldc: i64, work: []f64, lwork: i64, info_ref: *i64) {
    var info = *info_ref
    var left: bool = false
    var lquery: bool = false
    var upper: bool = false
    var i1: i64 = 0i64
    var i2: i64 = 0i64
    var iinfo: i64 = 0i64
    var lwkopt: i64 = 0i64
    var mi: i64 = 0i64
    var nb: i64 = 0i64
    var ni: i64 = 0i64
    var nq: i64 = 0i64
    var nw: i64 = 0i64
    info = 0i64
    left = lbase.lsame(side, "L")
    upper = lbase.lsame(uplo, "U")
    lquery = ((lwork == (-1i64)))
    if left {
        nq = m
        nw = lbase.i_max(1i64, n)
    } else {
        nq = n
        nw = lbase.i_max(1i64, m)
    }
    if ((!left) && (!lbase.lsame(side, "R"))) {
        info = (-1i64)
    } else if ((!upper) && (!lbase.lsame(uplo, "L"))) {
        info = (-2i64)
    } else if ((!lbase.lsame(trans, "N")) && (!lbase.lsame(trans, "T"))) {
        info = (-3i64)
    } else if (m < 0i64) {
        info = (-4i64)
    } else if (n < 0i64) {
        info = (-5i64)
    } else if (lda < lbase.i_max(1i64, nq)) {
        info = (-7i64)
    } else if (ldc < lbase.i_max(1i64, m)) {
        info = (-10i64)
    } else if ((lwork < nw) && (!lquery)) {
        info = (-12i64)
    }
    if (info == 0i64) {
        if upper {
            if left {
                nb = lbase.ilaenv(1i64, "DORMQL", side, (m - 1i64), n, (m - 1i64), (-1i64))
            } else {
                nb = lbase.ilaenv(1i64, "DORMQL", side, m, (n - 1i64), (n - 1i64), (-1i64))
            }
        } else {
            if left {
                nb = lbase.ilaenv(1i64, "DORMQR", side, (m - 1i64), n, (m - 1i64), (-1i64))
            } else {
                nb = lbase.ilaenv(1i64, "DORMQR", side, m, (n - 1i64), (n - 1i64), (-1i64))
            }
        }
        lwkopt = (nw * nb)
        work[usize((1i64 - 1i64))] = f64(lwkopt)
    }
    if (info != 0i64) {
        *info_ref = info
        ret
    } else if lquery {
        *info_ref = info
        ret
    }
    if (((m == 0i64) || (n == 0i64)) || (nq == 1i64)) {
        work[usize((1i64 - 1i64))] = 1.0f64
        *info_ref = info
        ret
    }
    if left {
        mi = (m - 1i64)
        ni = n
    } else {
        mi = m
        ni = (n - 1i64)
    }
    if upper {
        lbase.dormql(side, trans, mi, ni, (nq - 1i64), lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (2i64 - 1i64) * lda)), lda, tau[0usize..], c[0usize..], ldc, work[0usize..], lwork, &iinfo)
    } else {
        if left {
            i1 = 2i64
            i2 = 1i64
        } else {
            i1 = 1i64
            i2 = 2i64
        }
        lbase.dormqr(side, trans, mi, ni, (nq - 1i64), lbase.sl[f64](a[0usize..], usize((2i64 - 1i64) + (1i64 - 1i64) * lda)), lda, tau[0usize..], lbase.sl[f64](c[0usize..], usize((i1 - 1i64) + (i2 - 1i64) * ldc)), ldc, work[0usize..], lwork, &iinfo)
    }
    work[usize((1i64 - 1i64))] = f64(lwkopt)
    *info_ref = info
    ret
}

fn dstemr(jobz: str, range: str, n: i64, d: []f64, e: []f64, vl: f64, vu: f64, il: i64, iu: i64, m_ref: *i64, w: []f64, z: []f64, ldz: i64, nzc: i64, isuppz: []i64, tryrac_ref: *bool, work: []f64, lwork: i64, iwork: []i64, liwork: i64, info_ref: *i64) {
    var m = *m_ref
    var tryrac = *tryrac_ref
    var info = *info_ref
    var alleig: bool = false
    var indeig: bool = false
    var lquery: bool = false
    var valeig: bool = false
    var wantz: bool = false
    var zquery: bool = false
    var laeswap: bool = false
    var i: i64 = 0i64
    var ibegin: i64 = 0i64
    var iend: i64 = 0i64
    var ifirst: i64 = 0i64
    var iil: i64 = 0i64
    var iindbl: i64 = 0i64
    var iindw: i64 = 0i64
    var iindwk: i64 = 0i64
    var iinfo: i64 = 0i64
    var iinspl: i64 = 0i64
    var iiu: i64 = 0i64
    var ilast: i64 = 0i64
    var in_: i64 = 0i64
    var indd: i64 = 0i64
    var inde2: i64 = 0i64
    var inderr: i64 = 0i64
    var indgp: i64 = 0i64
    var indgrs: i64 = 0i64
    var indwrk: i64 = 0i64
    var itmp: i64 = 0i64
    var itmp2: i64 = 0i64
    var j: i64 = 0i64
    var jblk: i64 = 0i64
    var jj: i64 = 0i64
    var liwmin: i64 = 0i64
    var lwmin: i64 = 0i64
    var nsplit: i64 = 0i64
    var nzcmin: i64 = 0i64
    var offset: i64 = 0i64
    var wbegin: i64 = 0i64
    var wend: i64 = 0i64
    var bignum: f64 = 0.0f64
    var cs: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var pivmin: f64 = 0.0f64
    var r1: f64 = 0.0f64
    var r2: f64 = 0.0f64
    var rmax: f64 = 0.0f64
    var rmin: f64 = 0.0f64
    var rtol1: f64 = 0.0f64
    var rtol2: f64 = 0.0f64
    var safmin: f64 = 0.0f64
    var scale: f64 = 0.0f64
    var smlnum: f64 = 0.0f64
    var sn: f64 = 0.0f64
    var thresh: f64 = 0.0f64
    var tmp: f64 = 0.0f64
    var tnrm: f64 = 0.0f64
    var wl: f64 = 0.0f64
    var wu: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            wantz = lbase.lsame(jobz, "V")
            alleig = lbase.lsame(range, "A")
            valeig = lbase.lsame(range, "V")
            indeig = lbase.lsame(range, "I")
            lquery = ((((lwork == (-1i64))) || ((liwork == (-1i64)))))
            zquery = ((nzc == (-1i64)))
            laeswap = false
            if wantz {
                lwmin = (18i64 * n)
                liwmin = (10i64 * n)
            } else {
                lwmin = (12i64 * n)
                liwmin = (8i64 * n)
            }
            wl = 0.0f64
            wu = 0.0f64
            iil = 0i64
            iiu = 0i64
            nsplit = 0i64
            if valeig {
                wl = vl
                wu = vu
            } else if indeig {
                iil = il
                iiu = iu
            }
            info = 0i64
            if (!((wantz || lbase.lsame(jobz, "N")))) {
                info = (-1i64)
            } else if (!(((alleig || valeig) || indeig))) {
                info = (-2i64)
            } else if (n < 0i64) {
                info = (-3i64)
            } else if ((valeig && (n > 0i64)) && (wu <= wl)) {
                info = (-7i64)
            } else if (indeig && (((iil < 1i64) || (iil > n)))) {
                info = (-8i64)
            } else if (indeig && (((iiu < iil) || (iiu > n)))) {
                info = (-9i64)
            } else if ((ldz < 1i64) || ((wantz && (ldz < n)))) {
                info = (-13i64)
            } else if ((lwork < lwmin) && (!lquery)) {
                info = (-17i64)
            } else if ((liwork < liwmin) && (!lquery)) {
                info = (-19i64)
            }
            safmin = 2.2250738585072014e-308f64
            eps = 2.220446049250313e-16f64
            smlnum = (safmin / eps)
            bignum = (1.0f64 / smlnum)
            rmin = math.sqrt[f64](smlnum)
            rmax = lbase.f_min(math.sqrt[f64](bignum), (1.0f64 / math.sqrt[f64](math.sqrt[f64](safmin))))
            if (info == 0i64) {
                work[usize((1i64 - 1i64))] = f64(lwmin)
                iwork[usize((1i64 - 1i64))] = liwmin
                if (wantz && alleig) {
                    nzcmin = n
                } else if (wantz && valeig) {
                    dlarrc("T", n, vl, vu, d[0usize..], e[0usize..], safmin, &nzcmin, &itmp, &itmp2, &info)
                } else if (wantz && indeig) {
                    nzcmin = ((iiu - iil) + 1i64)
                } else {
                    nzcmin = 0i64
                }
                if (zquery && (info == 0i64)) {
                    z[usize((1i64 - 1i64) + (1i64 - 1i64) * ldz)] = f64(nzcmin)
                } else if ((nzc < nzcmin) && (!zquery)) {
                    info = (-14i64)
                }
            }
            if (info != 0i64) {
                *m_ref = m
                *tryrac_ref = tryrac
                *info_ref = info
                ret
            } else if (lquery || zquery) {
                *m_ref = m
                *tryrac_ref = tryrac
                *info_ref = info
                ret
            }
            m = 0i64
            if (n == 0i64) {
                *m_ref = m
                *tryrac_ref = tryrac
                *info_ref = info
                ret
            }
            if (n == 1i64) {
                if (alleig || indeig) {
                    m = 1i64
                    w[usize((1i64 - 1i64))] = d[usize((1i64 - 1i64))]
                } else {
                    if ((wl < d[usize((1i64 - 1i64))]) && (wu >= d[usize((1i64 - 1i64))])) {
                        m = 1i64
                        w[usize((1i64 - 1i64))] = d[usize((1i64 - 1i64))]
                    }
                }
                if (wantz && ((!zquery))) {
                    z[usize((1i64 - 1i64) + (1i64 - 1i64) * ldz)] = 1.0f64
                    isuppz[usize((1i64 - 1i64))] = 1i64
                    isuppz[usize((2i64 - 1i64))] = 1i64
                }
                *m_ref = m
                *tryrac_ref = tryrac
                *info_ref = info
                ret
            }
            if !(n == 2i64) {
                pc = 2i64
                continue
            }
            if (!wantz) {
                lbase.dlae2(d[usize((1i64 - 1i64))], e[usize((1i64 - 1i64))], d[usize((2i64 - 1i64))], &r1, &r2)
            } else if (wantz && ((!zquery))) {
                lbase.dlaev2(d[usize((1i64 - 1i64))], e[usize((1i64 - 1i64))], d[usize((2i64 - 1i64))], &r1, &r2, &cs, &sn)
            }
            if (r1 < r2) {
                e[usize((2i64 - 1i64))] = r1
                r1 = r2
                r2 = e[usize((2i64 - 1i64))]
                laeswap = true
            }
            if ((alleig || (((valeig && ((r2 > wl))) && ((r2 <= wu))))) || ((indeig && ((iil == 1i64))))) {
                m = (m + 1i64)
                w[usize((m - 1i64))] = r2
                if (wantz && ((!zquery))) {
                    if laeswap {
                        z[usize((1i64 - 1i64) + (m - 1i64) * ldz)] = cs
                        z[usize((2i64 - 1i64) + (m - 1i64) * ldz)] = sn
                    } else {
                        z[usize((1i64 - 1i64) + (m - 1i64) * ldz)] = (-sn)
                        z[usize((2i64 - 1i64) + (m - 1i64) * ldz)] = cs
                    }
                    if (sn != 0.0f64) {
                        if (cs != 0.0f64) {
                            isuppz[usize((((2i64 * m) - 1i64) - 1i64))] = 1i64
                            isuppz[usize(((2i64 * m) - 1i64))] = 2i64
                        } else {
                            isuppz[usize((((2i64 * m) - 1i64) - 1i64))] = 1i64
                            isuppz[usize(((2i64 * m) - 1i64))] = 1i64
                        }
                    } else {
                        isuppz[usize((((2i64 * m) - 1i64) - 1i64))] = 2i64
                        isuppz[usize(((2i64 * m) - 1i64))] = 2i64
                    }
                }
            }
            if ((alleig || (((valeig && ((r1 > wl))) && ((r1 <= wu))))) || ((indeig && ((iiu == 2i64))))) {
                m = (m + 1i64)
                w[usize((m - 1i64))] = r1
                if (wantz && ((!zquery))) {
                    if laeswap {
                        z[usize((1i64 - 1i64) + (m - 1i64) * ldz)] = (-sn)
                        z[usize((2i64 - 1i64) + (m - 1i64) * ldz)] = cs
                    } else {
                        z[usize((1i64 - 1i64) + (m - 1i64) * ldz)] = cs
                        z[usize((2i64 - 1i64) + (m - 1i64) * ldz)] = sn
                    }
                    if (sn != 0.0f64) {
                        if (cs != 0.0f64) {
                            isuppz[usize((((2i64 * m) - 1i64) - 1i64))] = 1i64
                            isuppz[usize(((2i64 * m) - 1i64))] = 2i64
                        } else {
                            isuppz[usize((((2i64 * m) - 1i64) - 1i64))] = 1i64
                            isuppz[usize(((2i64 * m) - 1i64))] = 1i64
                        }
                    } else {
                        isuppz[usize((((2i64 * m) - 1i64) - 1i64))] = 2i64
                        isuppz[usize(((2i64 * m) - 1i64))] = 2i64
                    }
                }
            }
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            indgrs = 1i64
            inderr = ((2i64 * n) + 1i64)
            indgp = ((3i64 * n) + 1i64)
            indd = ((4i64 * n) + 1i64)
            inde2 = ((5i64 * n) + 1i64)
            indwrk = ((6i64 * n) + 1i64)
            iinspl = 1i64
            iindbl = (n + 1i64)
            iindw = ((2i64 * n) + 1i64)
            iindwk = ((3i64 * n) + 1i64)
            scale = 1.0f64
            tnrm = lbase.dlanst("M", n, d[0usize..], e[0usize..])
            if ((tnrm > 0.0f64) && (tnrm < rmin)) {
                scale = (rmin / tnrm)
            } else if (tnrm > rmax) {
                scale = (rmax / tnrm)
            }
            if (scale != 1.0f64) {
                lbase.dscal(n, scale, d[0usize..], 1i64)
                lbase.dscal((n - 1i64), scale, e[0usize..], 1i64)
                tnrm = (tnrm * scale)
                if valeig {
                    wl = (wl * scale)
                    wu = (wu * scale)
                }
            }
            if tryrac {
                dlarrr(n, d[0usize..], e[0usize..], &iinfo)
            } else {
                iinfo = (-1i64)
            }
            if (iinfo == 0i64) {
                thresh = eps
            } else {
                thresh = (-eps)
                tryrac = false
            }
            if tryrac {
                lbase.dcopy(n, d[0usize..], 1i64, lbase.sl[f64](work[0usize..], usize((indd - 1i64))), 1i64)
            }
            j = 1i64
            zc1 = ((n - 1i64) - j) + 1i64
            while zc1 > 0i64 {
                work[usize((((inde2 + j) - 1i64) - 1i64))] = ((e[usize((j - 1i64))]) * (e[usize((j - 1i64))]))
                j = j + 1i64
                zc1 = zc1 - 1i64
            }
            if (!wantz) {
                rtol1 = (4.0f64 * eps)
                rtol2 = (4.0f64 * eps)
            } else {
                rtol1 = math.sqrt[f64](eps)
                rtol2 = lbase.f_max((math.sqrt[f64](eps) * 0.005f64), (4.0f64 * eps))
            }
            dlarre(range, n, &wl, &wu, iil, iiu, d[0usize..], e[0usize..], lbase.sl[f64](work[0usize..], usize((inde2 - 1i64))), rtol1, rtol2, thresh, &nsplit, lbase.sl[i64](iwork[0usize..], usize((iinspl - 1i64))), &m, w[0usize..], lbase.sl[f64](work[0usize..], usize((inderr - 1i64))), lbase.sl[f64](work[0usize..], usize((indgp - 1i64))), lbase.sl[i64](iwork[0usize..], usize((iindbl - 1i64))), lbase.sl[i64](iwork[0usize..], usize((iindw - 1i64))), lbase.sl[f64](work[0usize..], usize((indgrs - 1i64))), &pivmin, lbase.sl[f64](work[0usize..], usize((indwrk - 1i64))), lbase.sl[i64](iwork[0usize..], usize((iindwk - 1i64))), &iinfo)
            if (iinfo != 0i64) {
                info = (10i64 + lbase.i_abs(iinfo))
                *m_ref = m
                *tryrac_ref = tryrac
                *info_ref = info
                ret
            }
            if wantz {
                dlarrv(n, wl, wu, d[0usize..], e[0usize..], pivmin, lbase.sl[i64](iwork[0usize..], usize((iinspl - 1i64))), m, 1i64, m, 0.001f64, &rtol1, &rtol2, w[0usize..], lbase.sl[f64](work[0usize..], usize((inderr - 1i64))), lbase.sl[f64](work[0usize..], usize((indgp - 1i64))), lbase.sl[i64](iwork[0usize..], usize((iindbl - 1i64))), lbase.sl[i64](iwork[0usize..], usize((iindw - 1i64))), lbase.sl[f64](work[0usize..], usize((indgrs - 1i64))), z[0usize..], ldz, isuppz[0usize..], lbase.sl[f64](work[0usize..], usize((indwrk - 1i64))), lbase.sl[i64](iwork[0usize..], usize((iindwk - 1i64))), &iinfo)
                if (iinfo != 0i64) {
                    info = (20i64 + lbase.i_abs(iinfo))
                    *m_ref = m
                    *tryrac_ref = tryrac
                    *info_ref = info
                    ret
                }
            } else {
                j = 1i64
                zc2 = (m - j) + 1i64
                while zc2 > 0i64 {
                    itmp = iwork[usize((((iindbl + j) - 1i64) - 1i64))]
                    w[usize((j - 1i64))] = (w[usize((j - 1i64))] + e[usize((iwork[usize((((iinspl + itmp) - 1i64) - 1i64))] - 1i64))])
                    j = j + 1i64
                    zc2 = zc2 - 1i64
                }
            }
            if !tryrac {
                pc = 4i64
                continue
            }
            ibegin = 1i64
            wbegin = 1i64
            jblk = 1i64
            zc3 = (iwork[usize((((iindbl + m) - 1i64) - 1i64))] - jblk) + 1i64
            pc = 5i64
        }
        if pc == 5i64 {
            if zc3 <= 0i64 {
                pc = 6i64
                continue
            }
            iend = iwork[usize((((iinspl + jblk) - 1i64) - 1i64))]
            in_ = ((iend - ibegin) + 1i64)
            wend = (wbegin - 1i64)
            pc = 7i64
        }
        if pc == 7i64 {
            if !(wend < m) {
                pc = 9i64
                continue
            }
            if !(iwork[usize(((iindbl + wend) - 1i64))] == jblk) {
                pc = 11i64
                continue
            }
            wend = (wend + 1i64)
            pc = 7i64
            continue
        }
        if pc == 11i64 {
            pc = 10i64
        }
        if pc == 10i64 {
            pc = 8i64
            continue
        }
        if pc == 9i64 {
            pc = 8i64
        }
        if pc == 8i64 {
            if !(wend < wbegin) {
                pc = 13i64
                continue
            }
            ibegin = (iend + 1i64)
            pc = 14i64
            continue
        }
        if pc == 13i64 {
            pc = 12i64
        }
        if pc == 12i64 {
            offset = (iwork[usize((((iindw + wbegin) - 1i64) - 1i64))] - 1i64)
            ifirst = iwork[usize((((iindw + wbegin) - 1i64) - 1i64))]
            ilast = iwork[usize((((iindw + wend) - 1i64) - 1i64))]
            rtol2 = (4.0f64 * eps)
            dlarrj(in_, lbase.sl[f64](work[0usize..], usize((((indd + ibegin) - 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize((((inde2 + ibegin) - 1i64) - 1i64))), ifirst, ilast, rtol2, offset, lbase.sl[f64](w[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](work[0usize..], usize((((inderr + wbegin) - 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize((indwrk - 1i64))), lbase.sl[i64](iwork[0usize..], usize((iindwk - 1i64))), pivmin, tnrm, &iinfo)
            ibegin = (iend + 1i64)
            wbegin = (wend + 1i64)
            pc = 14i64
        }
        if pc == 14i64 {
            jblk = jblk + 1i64
            zc3 = zc3 - 1i64
            pc = 5i64
            continue
        }
        if pc == 6i64 {
            pc = 3i64
            continue
        }
        if pc == 4i64 {
            pc = 3i64
        }
        if pc == 3i64 {
            if (scale != 1.0f64) {
                lbase.dscal(m, (1.0f64 / scale), w[0usize..], 1i64)
            }
            pc = 1i64
            continue
        }
        if pc == 1i64 {
            if ((nsplit > 1i64) || (n == 2i64)) {
                if (!wantz) {
                    lbase.dlasrt("I", m, w[0usize..], &iinfo)
                    if (iinfo != 0i64) {
                        info = 3i64
                        *m_ref = m
                        *tryrac_ref = tryrac
                        *info_ref = info
                        ret
                    }
                } else {
                    j = 1i64
                    zc4 = ((m - 1i64) - j) + 1i64
                    while zc4 > 0i64 {
                        i = 0i64
                        tmp = w[usize((j - 1i64))]
                        jj = (j + 1i64)
                        zc5 = (m - jj) + 1i64
                        while zc5 > 0i64 {
                            if (w[usize((jj - 1i64))] < tmp) {
                                i = jj
                                tmp = w[usize((jj - 1i64))]
                            }
                            jj = jj + 1i64
                            zc5 = zc5 - 1i64
                        }
                        if (i != 0i64) {
                            w[usize((i - 1i64))] = w[usize((j - 1i64))]
                            w[usize((j - 1i64))] = tmp
                            if wantz {
                                lbase.dswap(n, lbase.sl[f64](z[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldz)), 1i64, lbase.sl[f64](z[0usize..], usize((1i64 - 1i64) + (j - 1i64) * ldz)), 1i64)
                                itmp = isuppz[usize((((2i64 * i) - 1i64) - 1i64))]
                                isuppz[usize((((2i64 * i) - 1i64) - 1i64))] = isuppz[usize((((2i64 * j) - 1i64) - 1i64))]
                                isuppz[usize((((2i64 * j) - 1i64) - 1i64))] = itmp
                                itmp = isuppz[usize(((2i64 * i) - 1i64))]
                                isuppz[usize(((2i64 * i) - 1i64))] = isuppz[usize(((2i64 * j) - 1i64))]
                                isuppz[usize(((2i64 * j) - 1i64))] = itmp
                            }
                        }
                        j = j + 1i64
                        zc4 = zc4 - 1i64
                    }
                }
            }
            work[usize((1i64 - 1i64))] = f64(lwmin)
            iwork[usize((1i64 - 1i64))] = liwmin
            *m_ref = m
            *tryrac_ref = tryrac
            *info_ref = info
            ret
        }
    }
}

fn dlarre(range: str, n: i64, vl_ref: *f64, vu_ref: *f64, il: i64, iu: i64, d: []f64, e: []f64, e2: []f64, rtol1: f64, rtol2: f64, spltol: f64, nsplit_ref: *i64, isplit: []i64, m_ref: *i64, w: []f64, werr: []f64, wgap: []f64, iblock: []i64, indexw: []i64, gers: []f64, pivmin_ref: *f64, work: []f64, iwork: []i64, info_ref: *i64) {
    var vl = *vl_ref
    var vu = *vu_ref
    var nsplit = *nsplit_ref
    var m = *m_ref
    var pivmin = *pivmin_ref
    var info = *info_ref
    var forceb: bool = false
    var norep: bool = false
    var usedqd: bool = false
    var cnt: i64 = 0i64
    var cnt1: i64 = 0i64
    var cnt2: i64 = 0i64
    var i: i64 = 0i64
    var ibegin: i64 = 0i64
    var idum: i64 = 0i64
    var iend: i64 = 0i64
    var iinfo: i64 = 0i64
    var in_: i64 = 0i64
    var indl: i64 = 0i64
    var indu: i64 = 0i64
    var irange: i64 = 0i64
    var j: i64 = 0i64
    var jblk: i64 = 0i64
    var mb: i64 = 0i64
    var mm: i64 = 0i64
    var wbegin: i64 = 0i64
    var wend: i64 = 0i64
    var avgap: f64 = 0.0f64
    var bsrtol: f64 = 0.0f64
    var clwdth: f64 = 0.0f64
    var dmax: f64 = 0.0f64
    var dpivot: f64 = 0.0f64
    var eabs: f64 = 0.0f64
    var emax: f64 = 0.0f64
    var eold: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var gl: f64 = 0.0f64
    var gu: f64 = 0.0f64
    var isleft: f64 = 0.0f64
    var isrght: f64 = 0.0f64
    var rtl: f64 = 0.0f64
    var rtol: f64 = 0.0f64
    var s1: f64 = 0.0f64
    var s2: f64 = 0.0f64
    var safmin: f64 = 0.0f64
    var sgndef: f64 = 0.0f64
    var sigma: f64 = 0.0f64
    var spdiam: f64 = 0.0f64
    var tau: f64 = 0.0f64
    var tmp: f64 = 0.0f64
    var tmp1: f64 = 0.0f64
    var iseed: [4]i64 = zero
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    var zc6: i64 = 0i64
    var zc7: i64 = 0i64
    var zc8: i64 = 0i64
    var zc9: i64 = 0i64
    var zc10: i64 = 0i64
    var zc11: i64 = 0i64
    var zc12: i64 = 0i64
    var zc13: i64 = 0i64
    var zc14: i64 = 0i64
    var zc15: i64 = 0i64
    var zc16: i64 = 0i64
    var zc17: i64 = 0i64
    var zc18: i64 = 0i64
    var zc19: i64 = 0i64
    var zc20: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            nsplit = 0i64
            m = 0i64
            if (n <= 0i64) {
                *vl_ref = vl
                *vu_ref = vu
                *nsplit_ref = nsplit
                *m_ref = m
                *pivmin_ref = pivmin
                *info_ref = info
                ret
            }
            if lbase.lsame(range, "A") {
                irange = 1i64
            } else if lbase.lsame(range, "V") {
                irange = 3i64
            } else if lbase.lsame(range, "I") {
                irange = 2i64
            }
            safmin = 2.2250738585072014e-308f64
            eps = 2.220446049250313e-16f64
            rtl = math.sqrt[f64](eps)
            bsrtol = math.sqrt[f64](eps)
            if (n == 1i64) {
                if ((((irange == 1i64)) || (((((irange == 3i64)) && ((d[usize((1i64 - 1i64))] > vl))) && ((d[usize((1i64 - 1i64))] <= vu))))) || (((((irange == 2i64)) && ((il == 1i64))) && ((iu == 1i64))))) {
                    m = 1i64
                    w[usize((1i64 - 1i64))] = d[usize((1i64 - 1i64))]
                    werr[usize((1i64 - 1i64))] = 0.0f64
                    wgap[usize((1i64 - 1i64))] = 0.0f64
                    iblock[usize((1i64 - 1i64))] = 1i64
                    indexw[usize((1i64 - 1i64))] = 1i64
                    gers[usize((1i64 - 1i64))] = d[usize((1i64 - 1i64))]
                    gers[usize((2i64 - 1i64))] = d[usize((1i64 - 1i64))]
                }
                e[usize((1i64 - 1i64))] = 0.0f64
                *vl_ref = vl
                *vu_ref = vu
                *nsplit_ref = nsplit
                *m_ref = m
                *pivmin_ref = pivmin
                *info_ref = info
                ret
            }
            gl = d[usize((1i64 - 1i64))]
            gu = d[usize((1i64 - 1i64))]
            eold = 0.0f64
            emax = 0.0f64
            e[usize((n - 1i64))] = 0.0f64
            i = 1i64
            zc1 = (n - i) + 1i64
            while zc1 > 0i64 {
                werr[usize((i - 1i64))] = 0.0f64
                wgap[usize((i - 1i64))] = 0.0f64
                eabs = math.abs[f64](e[usize((i - 1i64))])
                if (eabs >= emax) {
                    emax = eabs
                }
                tmp1 = (eabs + eold)
                gers[usize((((2i64 * i) - 1i64) - 1i64))] = (d[usize((i - 1i64))] - tmp1)
                gl = lbase.f_min(gl, gers[usize((((2i64 * i) - 1i64) - 1i64))])
                gers[usize(((2i64 * i) - 1i64))] = (d[usize((i - 1i64))] + tmp1)
                gu = lbase.f_max(gu, gers[usize(((2i64 * i) - 1i64))])
                eold = eabs
                i = i + 1i64
                zc1 = zc1 - 1i64
            }
            pivmin = (safmin * lbase.f_max(1.0f64, (emax * emax)))
            spdiam = (gu - gl)
            dlarra(n, d[0usize..], e[0usize..], e2[0usize..], spltol, spdiam, &nsplit, isplit[0usize..], &iinfo)
            forceb = false
            usedqd = ((((irange == 1i64)) && ((!forceb))))
            if (((irange == 1i64)) && ((!forceb))) {
                vl = gl
                vu = gu
            } else {
                dlarrd(range, "B", n, vl, vu, il, iu, gers[0usize..], bsrtol, d[0usize..], e[0usize..], e2[0usize..], pivmin, nsplit, isplit[0usize..], &mm, w[0usize..], werr[0usize..], &vl, &vu, iblock[0usize..], indexw[0usize..], work[0usize..], iwork[0usize..], &iinfo)
                if (iinfo != 0i64) {
                    info = (-1i64)
                    *vl_ref = vl
                    *vu_ref = vu
                    *nsplit_ref = nsplit
                    *m_ref = m
                    *pivmin_ref = pivmin
                    *info_ref = info
                    ret
                }
                i = (mm + 1i64)
                zc2 = (n - i) + 1i64
                while zc2 > 0i64 {
                    w[usize((i - 1i64))] = 0.0f64
                    werr[usize((i - 1i64))] = 0.0f64
                    iblock[usize((i - 1i64))] = 0i64
                    indexw[usize((i - 1i64))] = 0i64
                    i = i + 1i64
                    zc2 = zc2 - 1i64
                }
            }
            ibegin = 1i64
            wbegin = 1i64
            jblk = 1i64
            zc3 = (nsplit - jblk) + 1i64
            pc = 1i64
        }
        if pc == 1i64 {
            if zc3 <= 0i64 {
                pc = 2i64
                continue
            }
            iend = isplit[usize((jblk - 1i64))]
            in_ = ((iend - ibegin) + 1i64)
            if !(in_ == 1i64) {
                pc = 4i64
                continue
            }
            if ((((irange == 1i64)) || (((((irange == 3i64)) && ((d[usize((ibegin - 1i64))] > vl))) && ((d[usize((ibegin - 1i64))] <= vu))))) || ((((irange == 2i64)) && ((iblock[usize((wbegin - 1i64))] == jblk))))) {
                m = (m + 1i64)
                w[usize((m - 1i64))] = d[usize((ibegin - 1i64))]
                werr[usize((m - 1i64))] = 0.0f64
                wgap[usize((m - 1i64))] = 0.0f64
                iblock[usize((m - 1i64))] = jblk
                indexw[usize((m - 1i64))] = 1i64
                wbegin = (wbegin + 1i64)
            }
            e[usize((iend - 1i64))] = 0.0f64
            ibegin = (iend + 1i64)
            pc = 5i64
            continue
        }
        if pc == 4i64 {
            pc = 3i64
        }
        if pc == 3i64 {
            e[usize((iend - 1i64))] = 0.0f64
            gl = d[usize((ibegin - 1i64))]
            gu = d[usize((ibegin - 1i64))]
            i = ibegin
            zc4 = (iend - i) + 1i64
            while zc4 > 0i64 {
                gl = lbase.f_min(gers[usize((((2i64 * i) - 1i64) - 1i64))], gl)
                gu = lbase.f_max(gers[usize(((2i64 * i) - 1i64))], gu)
                i = i + 1i64
                zc4 = zc4 - 1i64
            }
            spdiam = (gu - gl)
            if !(!((((irange == 1i64)) && ((!forceb))))) {
                pc = 7i64
                continue
            }
            mb = 0i64
            i = wbegin
            zc5 = (mm - i) + 1i64
            pc = 8i64
        }
        if pc == 8i64 {
            if zc5 <= 0i64 {
                pc = 9i64
                continue
            }
            if !(iblock[usize((i - 1i64))] == jblk) {
                pc = 11i64
                continue
            }
            mb = (mb + 1i64)
            pc = 10i64
            continue
        }
        if pc == 11i64 {
            pc = 12i64
            continue
        }
        if pc == 10i64 {
            i = i + 1i64
            zc5 = zc5 - 1i64
            pc = 8i64
            continue
        }
        if pc == 9i64 {
            pc = 12i64
        }
        if pc == 12i64 {
            if !(mb == 0i64) {
                pc = 14i64
                continue
            }
            e[usize((iend - 1i64))] = 0.0f64
            ibegin = (iend + 1i64)
            pc = 5i64
            continue
        }
        if pc == 14i64 {
            usedqd = ((((f64(mb) > (0.5f64 * f64(in_)))) && ((!forceb))))
            wend = ((wbegin + mb) - 1i64)
            sigma = 0.0f64
            i = wbegin
            zc6 = ((wend - 1i64) - i) + 1i64
            while zc6 > 0i64 {
                wgap[usize((i - 1i64))] = lbase.f_max(0.0f64, ((w[usize(((i + 1i64) - 1i64))] - werr[usize(((i + 1i64) - 1i64))]) - ((w[usize((i - 1i64))] + werr[usize((i - 1i64))]))))
                i = i + 1i64
                zc6 = zc6 - 1i64
            }
            wgap[usize((wend - 1i64))] = lbase.f_max(0.0f64, ((vu - sigma) - ((w[usize((wend - 1i64))] + werr[usize((wend - 1i64))]))))
            indl = indexw[usize((wbegin - 1i64))]
            indu = indexw[usize((wend - 1i64))]
            pc = 13i64
            continue
        }
        if pc == 13i64 {
            pc = 6i64
            continue
        }
        if pc == 7i64 {
            pc = 6i64
        }
        if pc == 6i64 {
            if (((((irange == 1i64)) && ((!forceb)))) || usedqd) {
                dlarrk(in_, 1i64, gl, gu, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](e2[0usize..], usize((ibegin - 1i64))), pivmin, rtl, &tmp, &tmp1, &iinfo)
                if (iinfo != 0i64) {
                    info = (-1i64)
                    *vl_ref = vl
                    *vu_ref = vu
                    *nsplit_ref = nsplit
                    *m_ref = m
                    *pivmin_ref = pivmin
                    *info_ref = info
                    ret
                }
                isleft = lbase.f_max(gl, ((tmp - tmp1) - ((100.0f64 * eps) * math.abs[f64]((tmp - tmp1)))))
                dlarrk(in_, in_, gl, gu, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](e2[0usize..], usize((ibegin - 1i64))), pivmin, rtl, &tmp, &tmp1, &iinfo)
                if (iinfo != 0i64) {
                    info = (-1i64)
                    *vl_ref = vl
                    *vu_ref = vu
                    *nsplit_ref = nsplit
                    *m_ref = m
                    *pivmin_ref = pivmin
                    *info_ref = info
                    ret
                }
                isrght = lbase.f_min(gu, ((tmp + tmp1) + ((100.0f64 * eps) * math.abs[f64]((tmp + tmp1)))))
                spdiam = (isrght - isleft)
            } else {
                isleft = lbase.f_max(gl, ((w[usize((wbegin - 1i64))] - werr[usize((wbegin - 1i64))]) - ((100.0f64 * eps) * math.abs[f64]((w[usize((wbegin - 1i64))] - werr[usize((wbegin - 1i64))])))))
                isrght = lbase.f_min(gu, ((w[usize((wend - 1i64))] + werr[usize((wend - 1i64))]) + ((100.0f64 * eps) * math.abs[f64]((w[usize((wend - 1i64))] + werr[usize((wend - 1i64))])))))
            }
            if (((irange == 1i64)) && ((!forceb))) {
                usedqd = true
                indl = 1i64
                indu = in_
                mb = in_
                wend = ((wbegin + mb) - 1i64)
                s1 = (isleft + (0.25f64 * spdiam))
                s2 = (isrght - (0.25f64 * spdiam))
            } else {
                if usedqd {
                    s1 = (isleft + (0.25f64 * spdiam))
                    s2 = (isrght - (0.25f64 * spdiam))
                } else {
                    tmp = (lbase.f_min(isrght, vu) - lbase.f_max(isleft, vl))
                    s1 = (lbase.f_max(isleft, vl) + (0.25f64 * tmp))
                    s2 = (lbase.f_min(isrght, vu) - (0.25f64 * tmp))
                }
            }
            if (mb > 1i64) {
                dlarrc("T", in_, s1, s2, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](e[0usize..], usize((ibegin - 1i64))), pivmin, &cnt, &cnt1, &cnt2, &iinfo)
            }
            if (mb == 1i64) {
                sigma = gl
                sgndef = 1.0f64
            } else if ((cnt1 - indl) >= (indu - cnt2)) {
                if (((irange == 1i64)) && ((!forceb))) {
                    sigma = lbase.f_max(isleft, gl)
                } else if usedqd {
                    sigma = isleft
                } else {
                    sigma = lbase.f_max(isleft, vl)
                }
                sgndef = 1.0f64
            } else {
                if (((irange == 1i64)) && ((!forceb))) {
                    sigma = lbase.f_min(isrght, gu)
                } else if usedqd {
                    sigma = isrght
                } else {
                    sigma = lbase.f_min(isrght, vu)
                }
                sgndef = (-1.0f64)
            }
            if usedqd {
                tau = (((spdiam * eps) * f64(n)) + (2.0f64 * pivmin))
                tau = lbase.f_max(tau, ((2.0f64 * eps) * math.abs[f64](sigma)))
            } else {
                if (mb > 1i64) {
                    clwdth = (((w[usize((wend - 1i64))] + werr[usize((wend - 1i64))]) - w[usize((wbegin - 1i64))]) - werr[usize((wbegin - 1i64))])
                    avgap = math.abs[f64]((clwdth / f64((wend - wbegin))))
                    if (sgndef == 1.0f64) {
                        tau = (0.5f64 * lbase.f_max(wgap[usize((wbegin - 1i64))], avgap))
                        tau = lbase.f_max(tau, werr[usize((wbegin - 1i64))])
                    } else {
                        tau = (0.5f64 * lbase.f_max(wgap[usize(((wend - 1i64) - 1i64))], avgap))
                        tau = lbase.f_max(tau, werr[usize((wend - 1i64))])
                    }
                } else {
                    tau = werr[usize((wbegin - 1i64))]
                }
            }
            idum = 1i64
            zc7 = (6i64 - idum) + 1i64
            pc = 15i64
        }
        if pc == 15i64 {
            if zc7 <= 0i64 {
                pc = 16i64
                continue
            }
            dpivot = (d[usize((ibegin - 1i64))] - sigma)
            work[usize((1i64 - 1i64))] = dpivot
            dmax = math.abs[f64](work[usize((1i64 - 1i64))])
            j = ibegin
            i = 1i64
            zc8 = ((in_ - 1i64) - i) + 1i64
            while zc8 > 0i64 {
                work[usize((((2i64 * in_) + i) - 1i64))] = (1.0f64 / work[usize((i - 1i64))])
                tmp = (e[usize((j - 1i64))] * work[usize((((2i64 * in_) + i) - 1i64))])
                work[usize(((in_ + i) - 1i64))] = tmp
                dpivot = (((d[usize(((j + 1i64) - 1i64))] - sigma)) - (tmp * e[usize((j - 1i64))]))
                work[usize(((i + 1i64) - 1i64))] = dpivot
                dmax = lbase.f_max(dmax, math.abs[f64](dpivot))
                j = (j + 1i64)
                i = i + 1i64
                zc8 = zc8 - 1i64
            }
            if (dmax > (64.0f64 * spdiam)) {
                norep = true
            } else {
                norep = false
            }
            if (usedqd && (!norep)) {
                i = 1i64
                zc9 = (in_ - i) + 1i64
                while zc9 > 0i64 {
                    tmp = (sgndef * work[usize((i - 1i64))])
                    if (tmp < 0.0f64) {
                        norep = true
                    }
                    i = i + 1i64
                    zc9 = zc9 - 1i64
                }
            }
            if !norep {
                pc = 18i64
                continue
            }
            if (idum == (6i64 - 1i64)) {
                if (sgndef == 1.0f64) {
                    sigma = ((gl - (((2.0f64 * spdiam) * eps) * f64(n))) - ((2.0f64 * 2.0f64) * pivmin))
                } else {
                    sigma = ((gu + (((2.0f64 * spdiam) * eps) * f64(n))) + ((2.0f64 * 2.0f64) * pivmin))
                }
            } else {
                sigma = (sigma - (sgndef * tau))
                tau = (2.0f64 * tau)
            }
            pc = 17i64
            continue
        }
        if pc == 18i64 {
            pc = 19i64
            continue
        }
        if pc == 17i64 {
            idum = idum + 1i64
            zc7 = zc7 - 1i64
            pc = 15i64
            continue
        }
        if pc == 16i64 {
            info = 2i64
            *vl_ref = vl
            *vu_ref = vu
            *nsplit_ref = nsplit
            *m_ref = m
            *pivmin_ref = pivmin
            *info_ref = info
            ret
        }
        if pc == 19i64 {
            e[usize((iend - 1i64))] = sigma
            lbase.dcopy(in_, work[0usize..], 1i64, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), 1i64)
            lbase.dcopy((in_ - 1i64), lbase.sl[f64](work[0usize..], usize(((in_ + 1i64) - 1i64))), 1i64, lbase.sl[f64](e[0usize..], usize((ibegin - 1i64))), 1i64)
            if (mb > 1i64) {
                i = 1i64
                zc10 = (4i64 - i) + 1i64
                while zc10 > 0i64 {
                    iseed[usize((i - 1i64))] = 1i64
                    i = i + 1i64
                    zc10 = zc10 - 1i64
                }
                dlarnv(2i64, iseed[0usize..], ((2i64 * in_) - 1i64), lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))))
                i = 1i64
                zc11 = ((in_ - 1i64) - i) + 1i64
                while zc11 > 0i64 {
                    d[usize((((ibegin + i) - 1i64) - 1i64))] = (d[usize((((ibegin + i) - 1i64) - 1i64))] * ((1.0f64 + ((eps * 8.0f64) * work[usize((i - 1i64))]))))
                    e[usize((((ibegin + i) - 1i64) - 1i64))] = (e[usize((((ibegin + i) - 1i64) - 1i64))] * ((1.0f64 + ((eps * 8.0f64) * work[usize(((in_ + i) - 1i64))]))))
                    i = i + 1i64
                    zc11 = zc11 - 1i64
                }
                d[usize((iend - 1i64))] = (d[usize((iend - 1i64))] * ((1.0f64 + ((eps * 4.0f64) * work[usize((in_ - 1i64))]))))
            }
            if (!usedqd) {
                j = wbegin
                zc12 = (wend - j) + 1i64
                while zc12 > 0i64 {
                    w[usize((j - 1i64))] = (w[usize((j - 1i64))] - sigma)
                    werr[usize((j - 1i64))] = (werr[usize((j - 1i64))] + (math.abs[f64](w[usize((j - 1i64))]) * eps))
                    j = j + 1i64
                    zc12 = zc12 - 1i64
                }
                i = ibegin
                zc13 = ((iend - 1i64) - i) + 1i64
                while zc13 > 0i64 {
                    work[usize((i - 1i64))] = (d[usize((i - 1i64))] * ((e[usize((i - 1i64))]) * (e[usize((i - 1i64))])))
                    i = i + 1i64
                    zc13 = zc13 - 1i64
                }
                dlarrb(in_, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](work[0usize..], usize((ibegin - 1i64))), indl, indu, rtol1, rtol2, (indl - 1i64), lbase.sl[f64](w[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](wgap[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](werr[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](work[0usize..], usize((((2i64 * n) + 1i64) - 1i64))), iwork[0usize..], pivmin, spdiam, in_, &iinfo)
                if (iinfo != 0i64) {
                    info = (-4i64)
                    *vl_ref = vl
                    *vu_ref = vu
                    *nsplit_ref = nsplit
                    *m_ref = m
                    *pivmin_ref = pivmin
                    *info_ref = info
                    ret
                }
                wgap[usize((wend - 1i64))] = lbase.f_max(0.0f64, (((vu - sigma)) - ((w[usize((wend - 1i64))] + werr[usize((wend - 1i64))]))))
                i = indl
                zc14 = (indu - i) + 1i64
                while zc14 > 0i64 {
                    m = (m + 1i64)
                    iblock[usize((m - 1i64))] = jblk
                    indexw[usize((m - 1i64))] = i
                    i = i + 1i64
                    zc14 = zc14 - 1i64
                }
            } else {
                rtol = ((math.log[f64](f64(in_)) * 4.0f64) * eps)
                j = ibegin
                i = 1i64
                zc15 = ((in_ - 1i64) - i) + 1i64
                while zc15 > 0i64 {
                    work[usize((((2i64 * i) - 1i64) - 1i64))] = math.abs[f64](d[usize((j - 1i64))])
                    work[usize(((2i64 * i) - 1i64))] = ((e[usize((j - 1i64))] * e[usize((j - 1i64))]) * work[usize((((2i64 * i) - 1i64) - 1i64))])
                    j = (j + 1i64)
                    i = i + 1i64
                    zc15 = zc15 - 1i64
                }
                work[usize((((2i64 * in_) - 1i64) - 1i64))] = math.abs[f64](d[usize((iend - 1i64))])
                work[usize(((2i64 * in_) - 1i64))] = 0.0f64
                dlasq2(in_, work[0usize..], &iinfo)
                if (iinfo != 0i64) {
                    info = (-5i64)
                    *vl_ref = vl
                    *vu_ref = vu
                    *nsplit_ref = nsplit
                    *m_ref = m
                    *pivmin_ref = pivmin
                    *info_ref = info
                    ret
                } else {
                    i = 1i64
                    zc16 = (in_ - i) + 1i64
                    while zc16 > 0i64 {
                        if (work[usize((i - 1i64))] < 0.0f64) {
                            info = (-6i64)
                            *vl_ref = vl
                            *vu_ref = vu
                            *nsplit_ref = nsplit
                            *m_ref = m
                            *pivmin_ref = pivmin
                            *info_ref = info
                            ret
                        }
                        i = i + 1i64
                        zc16 = zc16 - 1i64
                    }
                }
                if (sgndef > 0.0f64) {
                    i = indl
                    zc17 = (indu - i) + 1i64
                    while zc17 > 0i64 {
                        m = (m + 1i64)
                        w[usize((m - 1i64))] = work[usize((((in_ - i) + 1i64) - 1i64))]
                        iblock[usize((m - 1i64))] = jblk
                        indexw[usize((m - 1i64))] = i
                        i = i + 1i64
                        zc17 = zc17 - 1i64
                    }
                } else {
                    i = indl
                    zc18 = (indu - i) + 1i64
                    while zc18 > 0i64 {
                        m = (m + 1i64)
                        w[usize((m - 1i64))] = (-work[usize((i - 1i64))])
                        iblock[usize((m - 1i64))] = jblk
                        indexw[usize((m - 1i64))] = i
                        i = i + 1i64
                        zc18 = zc18 - 1i64
                    }
                }
                i = ((m - mb) + 1i64)
                zc19 = (m - i) + 1i64
                while zc19 > 0i64 {
                    werr[usize((i - 1i64))] = (rtol * math.abs[f64](w[usize((i - 1i64))]))
                    i = i + 1i64
                    zc19 = zc19 - 1i64
                }
                i = ((m - mb) + 1i64)
                zc20 = ((m - 1i64) - i) + 1i64
                while zc20 > 0i64 {
                    wgap[usize((i - 1i64))] = lbase.f_max(0.0f64, ((w[usize(((i + 1i64) - 1i64))] - werr[usize(((i + 1i64) - 1i64))]) - ((w[usize((i - 1i64))] + werr[usize((i - 1i64))]))))
                    i = i + 1i64
                    zc20 = zc20 - 1i64
                }
                wgap[usize((m - 1i64))] = lbase.f_max(0.0f64, (((vu - sigma)) - ((w[usize((m - 1i64))] + werr[usize((m - 1i64))]))))
            }
            ibegin = (iend + 1i64)
            wbegin = (wend + 1i64)
            pc = 5i64
        }
        if pc == 5i64 {
            jblk = jblk + 1i64
            zc3 = zc3 - 1i64
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            *vl_ref = vl
            *vu_ref = vu
            *nsplit_ref = nsplit
            *m_ref = m
            *pivmin_ref = pivmin
            *info_ref = info
            ret
        }
    }
}

fn dlarra(n: i64, d: []f64, e: []f64, e2: []f64, spltol: f64, tnrm: f64, nsplit_ref: *i64, isplit: []i64, info_ref: *i64) {
    var nsplit = *nsplit_ref
    var info = *info_ref
    var i: i64 = 0i64
    var eabs: f64 = 0.0f64
    var tmp1: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    info = 0i64
    nsplit = 1i64
    if (n <= 0i64) {
        *nsplit_ref = nsplit
        *info_ref = info
        ret
    }
    if (spltol < 0.0f64) {
        tmp1 = (math.abs[f64](spltol) * tnrm)
        i = 1i64
        zc1 = ((n - 1i64) - i) + 1i64
        while zc1 > 0i64 {
            eabs = math.abs[f64](e[usize((i - 1i64))])
            if (eabs <= tmp1) {
                e[usize((i - 1i64))] = 0.0f64
                e2[usize((i - 1i64))] = 0.0f64
                isplit[usize((nsplit - 1i64))] = i
                nsplit = (nsplit + 1i64)
            }
            i = i + 1i64
            zc1 = zc1 - 1i64
        }
    } else {
        i = 1i64
        zc2 = ((n - 1i64) - i) + 1i64
        while zc2 > 0i64 {
            eabs = math.abs[f64](e[usize((i - 1i64))])
            if (eabs <= ((spltol * math.sqrt[f64](math.abs[f64](d[usize((i - 1i64))]))) * math.sqrt[f64](math.abs[f64](d[usize(((i + 1i64) - 1i64))])))) {
                e[usize((i - 1i64))] = 0.0f64
                e2[usize((i - 1i64))] = 0.0f64
                isplit[usize((nsplit - 1i64))] = i
                nsplit = (nsplit + 1i64)
            }
            i = i + 1i64
            zc2 = zc2 - 1i64
        }
    }
    isplit[usize((nsplit - 1i64))] = n
    *nsplit_ref = nsplit
    *info_ref = info
    ret
}

fn dlarrc(jobt: str, n: i64, vl: f64, vu: f64, d: []f64, e: []f64, pivmin: f64, eigcnt_ref: *i64, lcnt_ref: *i64, rcnt_ref: *i64, info_ref: *i64) {
    var eigcnt = *eigcnt_ref
    var lcnt = *lcnt_ref
    var rcnt = *rcnt_ref
    var info = *info_ref
    var i: i64 = 0i64
    var matt: bool = false
    var lpivot: f64 = 0.0f64
    var rpivot: f64 = 0.0f64
    var sl: f64 = 0.0f64
    var su: f64 = 0.0f64
    var tmp: f64 = 0.0f64
    var tmp2: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    info = 0i64
    lcnt = 0i64
    rcnt = 0i64
    eigcnt = 0i64
    if (n <= 0i64) {
        *eigcnt_ref = eigcnt
        *lcnt_ref = lcnt
        *rcnt_ref = rcnt
        *info_ref = info
        ret
    }
    matt = lbase.lsame(jobt, "T")
    if matt {
        lpivot = (d[usize((1i64 - 1i64))] - vl)
        rpivot = (d[usize((1i64 - 1i64))] - vu)
        if (lpivot <= 0.0f64) {
            lcnt = (lcnt + 1i64)
        }
        if (rpivot <= 0.0f64) {
            rcnt = (rcnt + 1i64)
        }
        i = 1i64
        zc1 = ((n - 1i64) - i) + 1i64
        while zc1 > 0i64 {
            tmp = ((e[usize((i - 1i64))]) * (e[usize((i - 1i64))]))
            lpivot = (((d[usize(((i + 1i64) - 1i64))] - vl)) - (tmp / lpivot))
            rpivot = (((d[usize(((i + 1i64) - 1i64))] - vu)) - (tmp / rpivot))
            if (lpivot <= 0.0f64) {
                lcnt = (lcnt + 1i64)
            }
            if (rpivot <= 0.0f64) {
                rcnt = (rcnt + 1i64)
            }
            i = i + 1i64
            zc1 = zc1 - 1i64
        }
    } else {
        sl = (-vl)
        su = (-vu)
        i = 1i64
        zc2 = ((n - 1i64) - i) + 1i64
        while zc2 > 0i64 {
            lpivot = (d[usize((i - 1i64))] + sl)
            rpivot = (d[usize((i - 1i64))] + su)
            if (lpivot <= 0.0f64) {
                lcnt = (lcnt + 1i64)
            }
            if (rpivot <= 0.0f64) {
                rcnt = (rcnt + 1i64)
            }
            tmp = ((e[usize((i - 1i64))] * d[usize((i - 1i64))]) * e[usize((i - 1i64))])
            tmp2 = (tmp / lpivot)
            if (tmp2 == 0.0f64) {
                sl = (tmp - vl)
            } else {
                sl = ((sl * tmp2) - vl)
            }
            tmp2 = (tmp / rpivot)
            if (tmp2 == 0.0f64) {
                su = (tmp - vu)
            } else {
                su = ((su * tmp2) - vu)
            }
            i = i + 1i64
            zc2 = zc2 - 1i64
        }
        lpivot = (d[usize((n - 1i64))] + sl)
        rpivot = (d[usize((n - 1i64))] + su)
        if (lpivot <= 0.0f64) {
            lcnt = (lcnt + 1i64)
        }
        if (rpivot <= 0.0f64) {
            rcnt = (rcnt + 1i64)
        }
    }
    eigcnt = (rcnt - lcnt)
    *eigcnt_ref = eigcnt
    *lcnt_ref = lcnt
    *rcnt_ref = rcnt
    *info_ref = info
    ret
}

fn dlarrd(range: str, order: str, n: i64, vl: f64, vu: f64, il: i64, iu: i64, gers: []f64, reltol: f64, d: []f64, e: []f64, e2: []f64, pivmin: f64, nsplit: i64, isplit: []i64, m_ref: *i64, w: []f64, werr: []f64, wl_ref: *f64, wu_ref: *f64, iblock: []i64, indexw: []i64, work: []f64, iwork: []i64, info_ref: *i64) {
    var m = *m_ref
    var wl = *wl_ref
    var wu = *wu_ref
    var info = *info_ref
    var ncnvrg: bool = false
    var toofew: bool = false
    var i: i64 = 0i64
    var ib: i64 = 0i64
    var ibegin: i64 = 0i64
    var idiscl: i64 = 0i64
    var idiscu: i64 = 0i64
    var ie: i64 = 0i64
    var iend: i64 = 0i64
    var iinfo: i64 = 0i64
    var im: i64 = 0i64
    var in_: i64 = 0i64
    var ioff: i64 = 0i64
    var iout: i64 = 0i64
    var irange: i64 = 0i64
    var itmax: i64 = 0i64
    var itmp1: i64 = 0i64
    var itmp2: i64 = 0i64
    var iw: i64 = 0i64
    var iwoff: i64 = 0i64
    var j: i64 = 0i64
    var jblk: i64 = 0i64
    var jdisc: i64 = 0i64
    var je: i64 = 0i64
    var jee: i64 = 0i64
    var nb: i64 = 0i64
    var nwl: i64 = 0i64
    var nwu: i64 = 0i64
    var atoli: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var gl: f64 = 0.0f64
    var gu: f64 = 0.0f64
    var rtoli: f64 = 0.0f64
    var tmp1: f64 = 0.0f64
    var tmp2: f64 = 0.0f64
    var tnorm: f64 = 0.0f64
    var uflow: f64 = 0.0f64
    var wkill: f64 = 0.0f64
    var wlu: f64 = 0.0f64
    var wul: f64 = 0.0f64
    var idumma: [1]i64 = zero
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    var zc6: i64 = 0i64
    var zc7: i64 = 0i64
    var zs8: i64 = 0i64
    var zc9: i64 = 0i64
    var zc10: i64 = 0i64
    var zc11: i64 = 0i64
    var zc12: i64 = 0i64
    var zc13: i64 = 0i64
    var zc14: i64 = 0i64
    var zc15: i64 = 0i64
    var zc16: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            m = 0i64
            if (n <= 0i64) {
                *m_ref = m
                *wl_ref = wl
                *wu_ref = wu
                *info_ref = info
                ret
            }
            if lbase.lsame(range, "A") {
                irange = 1i64
            } else if lbase.lsame(range, "V") {
                irange = 2i64
            } else if lbase.lsame(range, "I") {
                irange = 3i64
            } else {
                irange = 0i64
            }
            if (irange <= 0i64) {
                info = (-1i64)
            } else if (!((lbase.lsame(order, "B") || lbase.lsame(order, "E")))) {
                info = (-2i64)
            } else if (n < 0i64) {
                info = (-3i64)
            } else if (irange == 2i64) {
                if (vl >= vu) {
                    info = (-5i64)
                }
            } else if ((irange == 3i64) && (((il < 1i64) || (il > lbase.i_max(1i64, n))))) {
                info = (-6i64)
            } else if ((irange == 3i64) && (((iu < lbase.i_min(n, il)) || (iu > n)))) {
                info = (-7i64)
            }
            if (info != 0i64) {
                *m_ref = m
                *wl_ref = wl
                *wu_ref = wu
                *info_ref = info
                ret
            }
            ncnvrg = false
            toofew = false
            if (((irange == 3i64) && (il == 1i64)) && (iu == n)) {
                irange = 1i64
            }
            eps = 2.220446049250313e-16f64
            uflow = 2.2250738585072014e-308f64
            if (n == 1i64) {
                if ((((irange == 1i64)) || (((((irange == 2i64)) && ((d[usize((1i64 - 1i64))] > vl))) && ((d[usize((1i64 - 1i64))] <= vu))))) || (((((irange == 3i64)) && ((il == 1i64))) && ((iu == 1i64))))) {
                    m = 1i64
                    w[usize((1i64 - 1i64))] = d[usize((1i64 - 1i64))]
                    werr[usize((1i64 - 1i64))] = 0.0f64
                    iblock[usize((1i64 - 1i64))] = 1i64
                    indexw[usize((1i64 - 1i64))] = 1i64
                }
                *m_ref = m
                *wl_ref = wl
                *wu_ref = wu
                *info_ref = info
                ret
            }
            nb = lbase.ilaenv(1i64, "DSTEBZ", " ", n, (-1i64), (-1i64), (-1i64))
            if (nb <= 1i64) {
                nb = 0i64
            }
            gl = d[usize((1i64 - 1i64))]
            gu = d[usize((1i64 - 1i64))]
            i = 1i64
            zc1 = (n - i) + 1i64
            while zc1 > 0i64 {
                gl = lbase.f_min(gl, gers[usize((((2i64 * i) - 1i64) - 1i64))])
                gu = lbase.f_max(gu, gers[usize(((2i64 * i) - 1i64))])
                i = i + 1i64
                zc1 = zc1 - 1i64
            }
            tnorm = lbase.f_max(math.abs[f64](gl), math.abs[f64](gu))
            gl = ((gl - (((2.0f64 * tnorm) * eps) * f64(n))) - ((2.0f64 * 2.0f64) * pivmin))
            gu = ((gu + (((2.0f64 * tnorm) * eps) * f64(n))) + ((2.0f64 * 2.0f64) * pivmin))
            rtoli = reltol
            atoli = (((2.0f64 * 2.0f64) * uflow) + ((2.0f64 * 2.0f64) * pivmin))
            if (irange == 3i64) {
                itmax = (i64((((math.log[f64]((tnorm + pivmin)) - math.log[f64](pivmin))) / math.log[f64](2.0f64))) + 2i64)
                work[usize(((n + 1i64) - 1i64))] = gl
                work[usize(((n + 2i64) - 1i64))] = gl
                work[usize(((n + 3i64) - 1i64))] = gu
                work[usize(((n + 4i64) - 1i64))] = gu
                work[usize(((n + 5i64) - 1i64))] = gl
                work[usize(((n + 6i64) - 1i64))] = gu
                iwork[usize((1i64 - 1i64))] = (-1i64)
                iwork[usize((2i64 - 1i64))] = (-1i64)
                iwork[usize((3i64 - 1i64))] = (n + 1i64)
                iwork[usize((4i64 - 1i64))] = (n + 1i64)
                iwork[usize((5i64 - 1i64))] = (il - 1i64)
                iwork[usize((6i64 - 1i64))] = iu
                dlaebz(3i64, itmax, n, 2i64, 2i64, nb, atoli, rtoli, pivmin, d[0usize..], e[0usize..], e2[0usize..], lbase.sl[i64](iwork[0usize..], usize((5i64 - 1i64))), lbase.sl[f64](work[0usize..], usize(((n + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize(((n + 5i64) - 1i64))), &iout, iwork[0usize..], w[0usize..], iblock[0usize..], &iinfo)
                if (iinfo != 0i64) {
                    info = iinfo
                    *m_ref = m
                    *wl_ref = wl
                    *wu_ref = wu
                    *info_ref = info
                    ret
                }
                if (iwork[usize((6i64 - 1i64))] == iu) {
                    wl = work[usize(((n + 1i64) - 1i64))]
                    wlu = work[usize(((n + 3i64) - 1i64))]
                    nwl = iwork[usize((1i64 - 1i64))]
                    wu = work[usize(((n + 4i64) - 1i64))]
                    wul = work[usize(((n + 2i64) - 1i64))]
                    nwu = iwork[usize((4i64 - 1i64))]
                } else {
                    wl = work[usize(((n + 2i64) - 1i64))]
                    wlu = work[usize(((n + 4i64) - 1i64))]
                    nwl = iwork[usize((2i64 - 1i64))]
                    wu = work[usize(((n + 3i64) - 1i64))]
                    wul = work[usize(((n + 1i64) - 1i64))]
                    nwu = iwork[usize((3i64 - 1i64))]
                }
                if ((((nwl < 0i64) || (nwl >= n)) || (nwu < 1i64)) || (nwu > n)) {
                    info = 4i64
                    *m_ref = m
                    *wl_ref = wl
                    *wu_ref = wu
                    *info_ref = info
                    ret
                }
            } else if (irange == 2i64) {
                wl = vl
                wu = vu
            } else if (irange == 1i64) {
                wl = gl
                wu = gu
            }
            m = 0i64
            iend = 0i64
            info = 0i64
            nwl = 0i64
            nwu = 0i64
            jblk = 1i64
            zc2 = (nsplit - jblk) + 1i64
            pc = 1i64
        }
        if pc == 1i64 {
            if zc2 <= 0i64 {
                pc = 2i64
                continue
            }
            ioff = iend
            ibegin = (ioff + 1i64)
            iend = isplit[usize((jblk - 1i64))]
            in_ = (iend - ioff)
            if !(in_ == 1i64) {
                pc = 4i64
                continue
            }
            if (wl >= (d[usize((ibegin - 1i64))] - pivmin)) {
                nwl = (nwl + 1i64)
            }
            if (wu >= (d[usize((ibegin - 1i64))] - pivmin)) {
                nwu = (nwu + 1i64)
            }
            if ((irange == 1i64) || (((wl < (d[usize((ibegin - 1i64))] - pivmin)) && (wu >= (d[usize((ibegin - 1i64))] - pivmin))))) {
                m = (m + 1i64)
                w[usize((m - 1i64))] = d[usize((ibegin - 1i64))]
                werr[usize((m - 1i64))] = 0.0f64
                iblock[usize((m - 1i64))] = jblk
                indexw[usize((m - 1i64))] = 1i64
            }
            pc = 3i64
            continue
        }
        if pc == 4i64 {
            gu = d[usize((ibegin - 1i64))]
            gl = d[usize((ibegin - 1i64))]
            tmp1 = 0.0f64
            j = ibegin
            zc3 = (iend - j) + 1i64
            while zc3 > 0i64 {
                gl = lbase.f_min(gl, gers[usize((((2i64 * j) - 1i64) - 1i64))])
                gu = lbase.f_max(gu, gers[usize(((2i64 * j) - 1i64))])
                j = j + 1i64
                zc3 = zc3 - 1i64
            }
            gl = ((gl - (((2.0f64 * tnorm) * eps) * f64(in_))) - (2.0f64 * pivmin))
            gu = ((gu + (((2.0f64 * tnorm) * eps) * f64(in_))) + (2.0f64 * pivmin))
            if !(irange > 1i64) {
                pc = 6i64
                continue
            }
            if !(gu < wl) {
                pc = 8i64
                continue
            }
            nwl = (nwl + in_)
            nwu = (nwu + in_)
            pc = 9i64
            continue
        }
        if pc == 8i64 {
            pc = 7i64
        }
        if pc == 7i64 {
            gl = lbase.f_max(gl, wl)
            gu = lbase.f_min(gu, wu)
            if !(gl >= gu) {
                pc = 11i64
                continue
            }
            pc = 9i64
            continue
        }
        if pc == 11i64 {
            pc = 10i64
        }
        if pc == 10i64 {
            pc = 5i64
            continue
        }
        if pc == 6i64 {
            pc = 5i64
        }
        if pc == 5i64 {
            work[usize(((n + 1i64) - 1i64))] = gl
            work[usize((((n + in_) + 1i64) - 1i64))] = gu
            dlaebz(1i64, 0i64, in_, in_, 1i64, nb, atoli, rtoli, pivmin, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](e[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](e2[0usize..], usize((ibegin - 1i64))), idumma[0usize..], lbase.sl[f64](work[0usize..], usize(((n + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize((((n + (2i64 * in_)) + 1i64) - 1i64))), &im, iwork[0usize..], lbase.sl[f64](w[0usize..], usize(((m + 1i64) - 1i64))), lbase.sl[i64](iblock[0usize..], usize(((m + 1i64) - 1i64))), &iinfo)
            if (iinfo != 0i64) {
                info = iinfo
                *m_ref = m
                *wl_ref = wl
                *wu_ref = wu
                *info_ref = info
                ret
            }
            nwl = (nwl + iwork[usize((1i64 - 1i64))])
            nwu = (nwu + iwork[usize(((in_ + 1i64) - 1i64))])
            iwoff = (m - iwork[usize((1i64 - 1i64))])
            itmax = (i64((((math.log[f64](((gu - gl) + pivmin)) - math.log[f64](pivmin))) / math.log[f64](2.0f64))) + 2i64)
            dlaebz(2i64, itmax, in_, in_, 1i64, nb, atoli, rtoli, pivmin, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](e[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](e2[0usize..], usize((ibegin - 1i64))), idumma[0usize..], lbase.sl[f64](work[0usize..], usize(((n + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize((((n + (2i64 * in_)) + 1i64) - 1i64))), &iout, iwork[0usize..], lbase.sl[f64](w[0usize..], usize(((m + 1i64) - 1i64))), lbase.sl[i64](iblock[0usize..], usize(((m + 1i64) - 1i64))), &iinfo)
            if (iinfo != 0i64) {
                info = iinfo
                *m_ref = m
                *wl_ref = wl
                *wu_ref = wu
                *info_ref = info
                ret
            }
            j = 1i64
            zc4 = (iout - j) + 1i64
            while zc4 > 0i64 {
                tmp1 = (0.5f64 * ((work[usize(((j + n) - 1i64))] + work[usize((((j + in_) + n) - 1i64))])))
                tmp2 = (0.5f64 * math.abs[f64]((work[usize(((j + n) - 1i64))] - work[usize((((j + in_) + n) - 1i64))])))
                if (j > (iout - iinfo)) {
                    ncnvrg = true
                    ib = (-jblk)
                } else {
                    ib = jblk
                }
                je = ((iwork[usize((j - 1i64))] + 1i64) + iwoff)
                zc5 = ((iwork[usize(((j + in_) - 1i64))] + iwoff) - je) + 1i64
                while zc5 > 0i64 {
                    w[usize((je - 1i64))] = tmp1
                    werr[usize((je - 1i64))] = tmp2
                    indexw[usize((je - 1i64))] = (je - iwoff)
                    iblock[usize((je - 1i64))] = ib
                    je = je + 1i64
                    zc5 = zc5 - 1i64
                }
                j = j + 1i64
                zc4 = zc4 - 1i64
            }
            m = (m + im)
            pc = 3i64
            continue
        }
        if pc == 3i64 {
            pc = 9i64
        }
        if pc == 9i64 {
            jblk = jblk + 1i64
            zc2 = zc2 - 1i64
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            if (irange == 3i64) {
                idiscl = ((il - 1i64) - nwl)
                idiscu = (nwu - iu)
                if (idiscl > 0i64) {
                    im = 0i64
                    je = 1i64
                    zc6 = (m - je) + 1i64
                    while zc6 > 0i64 {
                        if ((w[usize((je - 1i64))] <= wlu) && (idiscl > 0i64)) {
                            idiscl = (idiscl - 1i64)
                        } else {
                            im = (im + 1i64)
                            w[usize((im - 1i64))] = w[usize((je - 1i64))]
                            werr[usize((im - 1i64))] = werr[usize((je - 1i64))]
                            indexw[usize((im - 1i64))] = indexw[usize((je - 1i64))]
                            iblock[usize((im - 1i64))] = iblock[usize((je - 1i64))]
                        }
                        je = je + 1i64
                        zc6 = zc6 - 1i64
                    }
                    m = im
                }
                if (idiscu > 0i64) {
                    im = (m + 1i64)
                    je = m
                    zs8 = (-1i64)
                    zc7 = ((1i64 - je) + zs8) / zs8
                    while zc7 > 0i64 {
                        if ((w[usize((je - 1i64))] >= wul) && (idiscu > 0i64)) {
                            idiscu = (idiscu - 1i64)
                        } else {
                            im = (im - 1i64)
                            w[usize((im - 1i64))] = w[usize((je - 1i64))]
                            werr[usize((im - 1i64))] = werr[usize((je - 1i64))]
                            indexw[usize((im - 1i64))] = indexw[usize((je - 1i64))]
                            iblock[usize((im - 1i64))] = iblock[usize((je - 1i64))]
                        }
                        je = je + zs8
                        zc7 = zc7 - 1i64
                    }
                    jee = 0i64
                    je = im
                    zc9 = (m - je) + 1i64
                    while zc9 > 0i64 {
                        jee = (jee + 1i64)
                        w[usize((jee - 1i64))] = w[usize((je - 1i64))]
                        werr[usize((jee - 1i64))] = werr[usize((je - 1i64))]
                        indexw[usize((jee - 1i64))] = indexw[usize((je - 1i64))]
                        iblock[usize((jee - 1i64))] = iblock[usize((je - 1i64))]
                        je = je + 1i64
                        zc9 = zc9 - 1i64
                    }
                    m = ((m - im) + 1i64)
                }
                if ((idiscl > 0i64) || (idiscu > 0i64)) {
                    if (idiscl > 0i64) {
                        wkill = wu
                        jdisc = 1i64
                        zc10 = (idiscl - jdisc) + 1i64
                        while zc10 > 0i64 {
                            iw = 0i64
                            je = 1i64
                            zc11 = (m - je) + 1i64
                            while zc11 > 0i64 {
                                if ((iblock[usize((je - 1i64))] != 0i64) && (((w[usize((je - 1i64))] < wkill) || (iw == 0i64)))) {
                                    iw = je
                                    wkill = w[usize((je - 1i64))]
                                }
                                je = je + 1i64
                                zc11 = zc11 - 1i64
                            }
                            iblock[usize((iw - 1i64))] = 0i64
                            jdisc = jdisc + 1i64
                            zc10 = zc10 - 1i64
                        }
                    }
                    if (idiscu > 0i64) {
                        wkill = wl
                        jdisc = 1i64
                        zc12 = (idiscu - jdisc) + 1i64
                        while zc12 > 0i64 {
                            iw = 0i64
                            je = 1i64
                            zc13 = (m - je) + 1i64
                            while zc13 > 0i64 {
                                if ((iblock[usize((je - 1i64))] != 0i64) && (((w[usize((je - 1i64))] >= wkill) || (iw == 0i64)))) {
                                    iw = je
                                    wkill = w[usize((je - 1i64))]
                                }
                                je = je + 1i64
                                zc13 = zc13 - 1i64
                            }
                            iblock[usize((iw - 1i64))] = 0i64
                            jdisc = jdisc + 1i64
                            zc12 = zc12 - 1i64
                        }
                    }
                    im = 0i64
                    je = 1i64
                    zc14 = (m - je) + 1i64
                    while zc14 > 0i64 {
                        if (iblock[usize((je - 1i64))] != 0i64) {
                            im = (im + 1i64)
                            w[usize((im - 1i64))] = w[usize((je - 1i64))]
                            werr[usize((im - 1i64))] = werr[usize((je - 1i64))]
                            indexw[usize((im - 1i64))] = indexw[usize((je - 1i64))]
                            iblock[usize((im - 1i64))] = iblock[usize((je - 1i64))]
                        }
                        je = je + 1i64
                        zc14 = zc14 - 1i64
                    }
                    m = im
                }
                if ((idiscl < 0i64) || (idiscu < 0i64)) {
                    toofew = true
                }
            }
            if ((((irange == 1i64) && (m != n))) || (((irange == 3i64) && (m != ((iu - il) + 1i64))))) {
                toofew = true
            }
            if (lbase.lsame(order, "E") && (nsplit > 1i64)) {
                je = 1i64
                zc15 = ((m - 1i64) - je) + 1i64
                while zc15 > 0i64 {
                    ie = 0i64
                    tmp1 = w[usize((je - 1i64))]
                    j = (je + 1i64)
                    zc16 = (m - j) + 1i64
                    while zc16 > 0i64 {
                        if (w[usize((j - 1i64))] < tmp1) {
                            ie = j
                            tmp1 = w[usize((j - 1i64))]
                        }
                        j = j + 1i64
                        zc16 = zc16 - 1i64
                    }
                    if (ie != 0i64) {
                        tmp2 = werr[usize((ie - 1i64))]
                        itmp1 = iblock[usize((ie - 1i64))]
                        itmp2 = indexw[usize((ie - 1i64))]
                        w[usize((ie - 1i64))] = w[usize((je - 1i64))]
                        werr[usize((ie - 1i64))] = werr[usize((je - 1i64))]
                        iblock[usize((ie - 1i64))] = iblock[usize((je - 1i64))]
                        indexw[usize((ie - 1i64))] = indexw[usize((je - 1i64))]
                        w[usize((je - 1i64))] = tmp1
                        werr[usize((je - 1i64))] = tmp2
                        iblock[usize((je - 1i64))] = itmp1
                        indexw[usize((je - 1i64))] = itmp2
                    }
                    je = je + 1i64
                    zc15 = zc15 - 1i64
                }
            }
            info = 0i64
            if ncnvrg {
                info = (info + 1i64)
            }
            if toofew {
                info = (info + 2i64)
            }
            *m_ref = m
            *wl_ref = wl
            *wu_ref = wu
            *info_ref = info
            ret
        }
    }
}

fn dlaebz(ijob: i64, nitmax: i64, n: i64, mmax: i64, minp: i64, nbmin: i64, abstol: f64, reltol: f64, pivmin: f64, d: []f64, e: []f64, e2: []f64, nval: []i64, ab: []f64, c: []f64, mout_ref: *i64, nab: []i64, work: []f64, iwork: []i64, info_ref: *i64) {
    var mout = *mout_ref
    var info = *info_ref
    var itmp1: i64 = 0i64
    var itmp2: i64 = 0i64
    var j: i64 = 0i64
    var ji: i64 = 0i64
    var jit: i64 = 0i64
    var jp: i64 = 0i64
    var kf: i64 = 0i64
    var kfnew: i64 = 0i64
    var kl: i64 = 0i64
    var klnew: i64 = 0i64
    var tmp1: f64 = 0.0f64
    var tmp2: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    var zc6: i64 = 0i64
    var zc7: i64 = 0i64
    var zc8: i64 = 0i64
    var zc9: i64 = 0i64
    var zc10: i64 = 0i64
    var zc11: i64 = 0i64
    var zc12: i64 = 0i64
    var zc13: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            if ((ijob < 1i64) || (ijob > 3i64)) {
                info = (-1i64)
                *mout_ref = mout
                *info_ref = info
                ret
            }
            if (ijob == 1i64) {
                mout = 0i64
                ji = 1i64
                zc1 = (minp - ji) + 1i64
                while zc1 > 0i64 {
                    jp = 1i64
                    zc2 = (2i64 - jp) + 1i64
                    while zc2 > 0i64 {
                        tmp1 = (d[usize((1i64 - 1i64))] - ab[usize((ji - 1i64) + (jp - 1i64) * mmax)])
                        if (math.abs[f64](tmp1) < pivmin) {
                            tmp1 = (-pivmin)
                        }
                        nab[usize((ji - 1i64) + (jp - 1i64) * mmax)] = 0i64
                        if (tmp1 <= 0.0f64) {
                            nab[usize((ji - 1i64) + (jp - 1i64) * mmax)] = 1i64
                        }
                        j = 2i64
                        zc3 = (n - j) + 1i64
                        while zc3 > 0i64 {
                            tmp1 = ((d[usize((j - 1i64))] - (e2[usize(((j - 1i64) - 1i64))] / tmp1)) - ab[usize((ji - 1i64) + (jp - 1i64) * mmax)])
                            if (math.abs[f64](tmp1) < pivmin) {
                                tmp1 = (-pivmin)
                            }
                            if (tmp1 <= 0.0f64) {
                                nab[usize((ji - 1i64) + (jp - 1i64) * mmax)] = (nab[usize((ji - 1i64) + (jp - 1i64) * mmax)] + 1i64)
                            }
                            j = j + 1i64
                            zc3 = zc3 - 1i64
                        }
                        jp = jp + 1i64
                        zc2 = zc2 - 1i64
                    }
                    mout = ((mout + nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)]) - nab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)])
                    ji = ji + 1i64
                    zc1 = zc1 - 1i64
                }
                *mout_ref = mout
                *info_ref = info
                ret
            }
            kf = 1i64
            kl = minp
            if (ijob == 2i64) {
                ji = 1i64
                zc4 = (minp - ji) + 1i64
                while zc4 > 0i64 {
                    c[usize((ji - 1i64))] = (0.5f64 * ((ab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)] + ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)])))
                    ji = ji + 1i64
                    zc4 = zc4 - 1i64
                }
            }
            jit = 1i64
            zc5 = (nitmax - jit) + 1i64
            pc = 1i64
        }
        if pc == 1i64 {
            if zc5 <= 0i64 {
                pc = 2i64
                continue
            }
            if ((((kl - kf) + 1i64) >= nbmin) && (nbmin > 0i64)) {
                ji = kf
                zc6 = (kl - ji) + 1i64
                while zc6 > 0i64 {
                    work[usize((ji - 1i64))] = (d[usize((1i64 - 1i64))] - c[usize((ji - 1i64))])
                    iwork[usize((ji - 1i64))] = 0i64
                    if (work[usize((ji - 1i64))] <= pivmin) {
                        iwork[usize((ji - 1i64))] = 1i64
                        work[usize((ji - 1i64))] = lbase.f_min(work[usize((ji - 1i64))], (-pivmin))
                    }
                    j = 2i64
                    zc7 = (n - j) + 1i64
                    while zc7 > 0i64 {
                        work[usize((ji - 1i64))] = ((d[usize((j - 1i64))] - (e2[usize(((j - 1i64) - 1i64))] / work[usize((ji - 1i64))])) - c[usize((ji - 1i64))])
                        if (work[usize((ji - 1i64))] <= pivmin) {
                            iwork[usize((ji - 1i64))] = (iwork[usize((ji - 1i64))] + 1i64)
                            work[usize((ji - 1i64))] = lbase.f_min(work[usize((ji - 1i64))], (-pivmin))
                        }
                        j = j + 1i64
                        zc7 = zc7 - 1i64
                    }
                    ji = ji + 1i64
                    zc6 = zc6 - 1i64
                }
                if (ijob <= 2i64) {
                    klnew = kl
                    ji = kf
                    zc8 = (kl - ji) + 1i64
                    while zc8 > 0i64 {
                        iwork[usize((ji - 1i64))] = lbase.i_min(nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)], lbase.i_max(nab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)], iwork[usize((ji - 1i64))]))
                        if (iwork[usize((ji - 1i64))] == nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)]) {
                            ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)] = c[usize((ji - 1i64))]
                        } else if (iwork[usize((ji - 1i64))] == nab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)]) {
                            ab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)] = c[usize((ji - 1i64))]
                        } else {
                            klnew = (klnew + 1i64)
                            if (klnew <= mmax) {
                                ab[usize((klnew - 1i64) + (2i64 - 1i64) * mmax)] = ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)]
                                nab[usize((klnew - 1i64) + (2i64 - 1i64) * mmax)] = nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)]
                                ab[usize((klnew - 1i64) + (1i64 - 1i64) * mmax)] = c[usize((ji - 1i64))]
                                nab[usize((klnew - 1i64) + (1i64 - 1i64) * mmax)] = iwork[usize((ji - 1i64))]
                                ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)] = c[usize((ji - 1i64))]
                                nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)] = iwork[usize((ji - 1i64))]
                            } else {
                                info = (mmax + 1i64)
                            }
                        }
                        ji = ji + 1i64
                        zc8 = zc8 - 1i64
                    }
                    if (info != 0i64) {
                        *mout_ref = mout
                        *info_ref = info
                        ret
                    }
                    kl = klnew
                } else {
                    ji = kf
                    zc9 = (kl - ji) + 1i64
                    while zc9 > 0i64 {
                        if (iwork[usize((ji - 1i64))] <= nval[usize((ji - 1i64))]) {
                            ab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)] = c[usize((ji - 1i64))]
                            nab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)] = iwork[usize((ji - 1i64))]
                        }
                        if (iwork[usize((ji - 1i64))] >= nval[usize((ji - 1i64))]) {
                            ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)] = c[usize((ji - 1i64))]
                            nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)] = iwork[usize((ji - 1i64))]
                        }
                        ji = ji + 1i64
                        zc9 = zc9 - 1i64
                    }
                }
            } else {
                klnew = kl
                ji = kf
                zc10 = (kl - ji) + 1i64
                while zc10 > 0i64 {
                    tmp1 = c[usize((ji - 1i64))]
                    tmp2 = (d[usize((1i64 - 1i64))] - tmp1)
                    itmp1 = 0i64
                    if (tmp2 <= pivmin) {
                        itmp1 = 1i64
                        tmp2 = lbase.f_min(tmp2, (-pivmin))
                    }
                    j = 2i64
                    zc11 = (n - j) + 1i64
                    while zc11 > 0i64 {
                        tmp2 = ((d[usize((j - 1i64))] - (e2[usize(((j - 1i64) - 1i64))] / tmp2)) - tmp1)
                        if (tmp2 <= pivmin) {
                            itmp1 = (itmp1 + 1i64)
                            tmp2 = lbase.f_min(tmp2, (-pivmin))
                        }
                        j = j + 1i64
                        zc11 = zc11 - 1i64
                    }
                    if (ijob <= 2i64) {
                        itmp1 = lbase.i_min(nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)], lbase.i_max(nab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)], itmp1))
                        if (itmp1 == nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)]) {
                            ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)] = tmp1
                        } else if (itmp1 == nab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)]) {
                            ab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)] = tmp1
                        } else if (klnew < mmax) {
                            klnew = (klnew + 1i64)
                            ab[usize((klnew - 1i64) + (2i64 - 1i64) * mmax)] = ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)]
                            nab[usize((klnew - 1i64) + (2i64 - 1i64) * mmax)] = nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)]
                            ab[usize((klnew - 1i64) + (1i64 - 1i64) * mmax)] = tmp1
                            nab[usize((klnew - 1i64) + (1i64 - 1i64) * mmax)] = itmp1
                            ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)] = tmp1
                            nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)] = itmp1
                        } else {
                            info = (mmax + 1i64)
                            *mout_ref = mout
                            *info_ref = info
                            ret
                        }
                    } else {
                        if (itmp1 <= nval[usize((ji - 1i64))]) {
                            ab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)] = tmp1
                            nab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)] = itmp1
                        }
                        if (itmp1 >= nval[usize((ji - 1i64))]) {
                            ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)] = tmp1
                            nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)] = itmp1
                        }
                    }
                    ji = ji + 1i64
                    zc10 = zc10 - 1i64
                }
                kl = klnew
            }
            kfnew = kf
            ji = kf
            zc12 = (kl - ji) + 1i64
            while zc12 > 0i64 {
                tmp1 = math.abs[f64]((ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)] - ab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)]))
                tmp2 = lbase.f_max(math.abs[f64](ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)]), math.abs[f64](ab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)]))
                if ((tmp1 < lbase.f_max(lbase.f_max(abstol, pivmin), (reltol * tmp2))) || (nab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)] >= nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)])) {
                    if (ji > kfnew) {
                        tmp1 = ab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)]
                        tmp2 = ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)]
                        itmp1 = nab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)]
                        itmp2 = nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)]
                        ab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)] = ab[usize((kfnew - 1i64) + (1i64 - 1i64) * mmax)]
                        ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)] = ab[usize((kfnew - 1i64) + (2i64 - 1i64) * mmax)]
                        nab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)] = nab[usize((kfnew - 1i64) + (1i64 - 1i64) * mmax)]
                        nab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)] = nab[usize((kfnew - 1i64) + (2i64 - 1i64) * mmax)]
                        ab[usize((kfnew - 1i64) + (1i64 - 1i64) * mmax)] = tmp1
                        ab[usize((kfnew - 1i64) + (2i64 - 1i64) * mmax)] = tmp2
                        nab[usize((kfnew - 1i64) + (1i64 - 1i64) * mmax)] = itmp1
                        nab[usize((kfnew - 1i64) + (2i64 - 1i64) * mmax)] = itmp2
                        if (ijob == 3i64) {
                            itmp1 = nval[usize((ji - 1i64))]
                            nval[usize((ji - 1i64))] = nval[usize((kfnew - 1i64))]
                            nval[usize((kfnew - 1i64))] = itmp1
                        }
                    }
                    kfnew = (kfnew + 1i64)
                }
                ji = ji + 1i64
                zc12 = zc12 - 1i64
            }
            kf = kfnew
            ji = kf
            zc13 = (kl - ji) + 1i64
            while zc13 > 0i64 {
                c[usize((ji - 1i64))] = (0.5f64 * ((ab[usize((ji - 1i64) + (1i64 - 1i64) * mmax)] + ab[usize((ji - 1i64) + (2i64 - 1i64) * mmax)])))
                ji = ji + 1i64
                zc13 = zc13 - 1i64
            }
            if !(kf > kl) {
                pc = 4i64
                continue
            }
            pc = 5i64
            continue
        }
        if pc == 4i64 {
            pc = 3i64
        }
        if pc == 3i64 {
            jit = jit + 1i64
            zc5 = zc5 - 1i64
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            pc = 5i64
        }
        if pc == 5i64 {
            info = lbase.i_max(((kl + 1i64) - kf), 0i64)
            mout = kl
            *mout_ref = mout
            *info_ref = info
            ret
        }
    }
}

fn dlarrk(n: i64, iw: i64, gl: f64, gu: f64, d: []f64, e2: []f64, pivmin: f64, reltol: f64, w_ref: *f64, werr_ref: *f64, info_ref: *i64) {
    var w = *w_ref
    var werr = *werr_ref
    var info = *info_ref
    var i: i64 = 0i64
    var it: i64 = 0i64
    var itmax: i64 = 0i64
    var negcnt: i64 = 0i64
    var atoli: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var left: f64 = 0.0f64
    var mid: f64 = 0.0f64
    var right: f64 = 0.0f64
    var rtoli: f64 = 0.0f64
    var tmp1: f64 = 0.0f64
    var tmp2: f64 = 0.0f64
    var tnorm: f64 = 0.0f64
    var zc1: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            if (n <= 0i64) {
                info = 0i64
                *w_ref = w
                *werr_ref = werr
                *info_ref = info
                ret
            }
            eps = 2.220446049250313e-16f64
            tnorm = lbase.f_max(math.abs[f64](gl), math.abs[f64](gu))
            rtoli = reltol
            atoli = ((2.0f64 * 2.0f64) * pivmin)
            itmax = (i64((((math.log[f64]((tnorm + pivmin)) - math.log[f64](pivmin))) / math.log[f64](2.0f64))) + 2i64)
            info = (-1i64)
            left = ((gl - (((2.0f64 * tnorm) * eps) * f64(n))) - ((2.0f64 * 2.0f64) * pivmin))
            right = ((gu + (((2.0f64 * tnorm) * eps) * f64(n))) + ((2.0f64 * 2.0f64) * pivmin))
            it = 0i64
            pc = 1i64
        }
        if pc == 1i64 {
            tmp1 = math.abs[f64]((right - left))
            tmp2 = lbase.f_max(math.abs[f64](right), math.abs[f64](left))
            if !(tmp1 < lbase.f_max(lbase.f_max(atoli, pivmin), (rtoli * tmp2))) {
                pc = 3i64
                continue
            }
            info = 0i64
            pc = 4i64
            continue
        }
        if pc == 3i64 {
            pc = 2i64
        }
        if pc == 2i64 {
            if !(it > itmax) {
                pc = 6i64
                continue
            }
            pc = 4i64
            continue
        }
        if pc == 6i64 {
            pc = 5i64
        }
        if pc == 5i64 {
            it = (it + 1i64)
            mid = (0.5f64 * ((left + right)))
            negcnt = 0i64
            tmp1 = (d[usize((1i64 - 1i64))] - mid)
            if (math.abs[f64](tmp1) < pivmin) {
                tmp1 = (-pivmin)
            }
            if (tmp1 <= 0.0f64) {
                negcnt = (negcnt + 1i64)
            }
            i = 2i64
            zc1 = (n - i) + 1i64
            while zc1 > 0i64 {
                tmp1 = ((d[usize((i - 1i64))] - (e2[usize(((i - 1i64) - 1i64))] / tmp1)) - mid)
                if (math.abs[f64](tmp1) < pivmin) {
                    tmp1 = (-pivmin)
                }
                if (tmp1 <= 0.0f64) {
                    negcnt = (negcnt + 1i64)
                }
                i = i + 1i64
                zc1 = zc1 - 1i64
            }
            if (negcnt >= iw) {
                right = mid
            } else {
                left = mid
            }
            pc = 1i64
            continue
        }
        if pc == 4i64 {
            w = (0.5f64 * ((left + right)))
            werr = (0.5f64 * math.abs[f64]((right - left)))
            *w_ref = w
            *werr_ref = werr
            *info_ref = info
            ret
        }
    }
}

fn dlasq1(n: i64, d: []f64, e: []f64, work: []f64, info_ref: *i64) {
    var info = *info_ref
    var i: i64 = 0i64
    var iinfo: i64 = 0i64
    var eps: f64 = 0.0f64
    var scale: f64 = 0.0f64
    var safmin: f64 = 0.0f64
    var sigmn: f64 = 0.0f64
    var sigmx: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    info = 0i64
    if (n < 0i64) {
        info = (-1i64)
        *info_ref = info
        ret
    } else if (n == 0i64) {
        *info_ref = info
        ret
    } else if (n == 1i64) {
        d[usize((1i64 - 1i64))] = math.abs[f64](d[usize((1i64 - 1i64))])
        *info_ref = info
        ret
    } else if (n == 2i64) {
        lbase.dlas2(d[usize((1i64 - 1i64))], e[usize((1i64 - 1i64))], d[usize((2i64 - 1i64))], &sigmn, &sigmx)
        d[usize((1i64 - 1i64))] = sigmx
        d[usize((2i64 - 1i64))] = sigmn
        *info_ref = info
        ret
    }
    sigmx = 0.0f64
    i = 1i64
    zc1 = ((n - 1i64) - i) + 1i64
    while zc1 > 0i64 {
        d[usize((i - 1i64))] = math.abs[f64](d[usize((i - 1i64))])
        sigmx = lbase.f_max(sigmx, math.abs[f64](e[usize((i - 1i64))]))
        i = i + 1i64
        zc1 = zc1 - 1i64
    }
    d[usize((n - 1i64))] = math.abs[f64](d[usize((n - 1i64))])
    if (sigmx == 0.0f64) {
        lbase.dlasrt("D", n, d[0usize..], &iinfo)
        *info_ref = info
        ret
    }
    i = 1i64
    zc2 = (n - i) + 1i64
    while zc2 > 0i64 {
        sigmx = lbase.f_max(sigmx, d[usize((i - 1i64))])
        i = i + 1i64
        zc2 = zc2 - 1i64
    }
    eps = 2.220446049250313e-16f64
    safmin = 2.2250738585072014e-308f64
    scale = math.sqrt[f64]((eps / safmin))
    lbase.dcopy(n, d[0usize..], 1i64, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), 2i64)
    lbase.dcopy((n - 1i64), e[0usize..], 1i64, lbase.sl[f64](work[0usize..], usize((2i64 - 1i64))), 2i64)
    lbase.dlascl("G", 0i64, 0i64, sigmx, scale, ((2i64 * n) - 1i64), 1i64, work[0usize..], ((2i64 * n) - 1i64), &iinfo)
    i = 1i64
    zc3 = (((2i64 * n) - 1i64) - i) + 1i64
    while zc3 > 0i64 {
        work[usize((i - 1i64))] = ((work[usize((i - 1i64))]) * (work[usize((i - 1i64))]))
        i = i + 1i64
        zc3 = zc3 - 1i64
    }
    work[usize(((2i64 * n) - 1i64))] = 0.0f64
    dlasq2(n, work[0usize..], &info)
    if (info == 0i64) {
        i = 1i64
        zc4 = (n - i) + 1i64
        while zc4 > 0i64 {
            d[usize((i - 1i64))] = math.sqrt[f64](work[usize((i - 1i64))])
            i = i + 1i64
            zc4 = zc4 - 1i64
        }
        lbase.dlascl("G", 0i64, 0i64, scale, sigmx, n, 1i64, d[0usize..], n, &iinfo)
    } else if (info == 2i64) {
        i = 1i64
        zc5 = (n - i) + 1i64
        while zc5 > 0i64 {
            d[usize((i - 1i64))] = math.sqrt[f64](work[usize((((2i64 * i) - 1i64) - 1i64))])
            e[usize((i - 1i64))] = math.sqrt[f64](work[usize(((2i64 * i) - 1i64))])
            i = i + 1i64
            zc5 = zc5 - 1i64
        }
        lbase.dlascl("G", 0i64, 0i64, scale, sigmx, n, 1i64, d[0usize..], n, &iinfo)
        lbase.dlascl("G", 0i64, 0i64, scale, sigmx, n, 1i64, e[0usize..], n, &iinfo)
    }
    *info_ref = info
    ret
}

fn dlasq2(n: i64, z: []f64, info_ref: *i64) {
    var info = *info_ref
    var ieee: bool = false
    var i0: i64 = 0i64
    var i1: i64 = 0i64
    var i4: i64 = 0i64
    var iinfo: i64 = 0i64
    var ipn4: i64 = 0i64
    var iter: i64 = 0i64
    var iwhila: i64 = 0i64
    var iwhilb: i64 = 0i64
    var k: i64 = 0i64
    var kmin: i64 = 0i64
    var n0: i64 = 0i64
    var n1: i64 = 0i64
    var nbig: i64 = 0i64
    var ndiv: i64 = 0i64
    var nfail: i64 = 0i64
    var pp: i64 = 0i64
    var splt: i64 = 0i64
    var ttype: i64 = 0i64
    var d: f64 = 0.0f64
    var dee: f64 = 0.0f64
    var deemin: f64 = 0.0f64
    var desig: f64 = 0.0f64
    var dmin: f64 = 0.0f64
    var dmin1: f64 = 0.0f64
    var dmin2: f64 = 0.0f64
    var dn: f64 = 0.0f64
    var dn1: f64 = 0.0f64
    var dn2: f64 = 0.0f64
    var e: f64 = 0.0f64
    var emax: f64 = 0.0f64
    var emin: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var g: f64 = 0.0f64
    var oldemn: f64 = 0.0f64
    var qmax: f64 = 0.0f64
    var qmin: f64 = 0.0f64
    var s: f64 = 0.0f64
    var safmin: f64 = 0.0f64
    var sigma: f64 = 0.0f64
    var t: f64 = 0.0f64
    var tau: f64 = 0.0f64
    var temp: f64 = 0.0f64
    var tol: f64 = 0.0f64
    var tol2: f64 = 0.0f64
    var trace: f64 = 0.0f64
    var zmax: f64 = 0.0f64
    var tempe: f64 = 0.0f64
    var tempq: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zs5: i64 = 0i64
    var zc6: i64 = 0i64
    var zs7: i64 = 0i64
    var zc8: i64 = 0i64
    var zc9: i64 = 0i64
    var zs10: i64 = 0i64
    var zc11: i64 = 0i64
    var zs12: i64 = 0i64
    var zc13: i64 = 0i64
    var zs14: i64 = 0i64
    var zc15: i64 = 0i64
    var zc16: i64 = 0i64
    var zs17: i64 = 0i64
    var zc18: i64 = 0i64
    var zs19: i64 = 0i64
    var zc20: i64 = 0i64
    var zs21: i64 = 0i64
    var zc22: i64 = 0i64
    var zc23: i64 = 0i64
    var zs24: i64 = 0i64
    var zc25: i64 = 0i64
    var zc26: i64 = 0i64
    var zc27: i64 = 0i64
    var zc28: i64 = 0i64
    var zs29: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            eps = 2.220446049250313e-16f64
            safmin = 2.2250738585072014e-308f64
            tol = (eps * 100.0f64)
            tol2 = (tol * tol)
            if (n < 0i64) {
                info = (-1i64)
                *info_ref = info
                ret
            } else if (n == 0i64) {
                *info_ref = info
                ret
            } else if (n == 1i64) {
                if (z[usize((1i64 - 1i64))] < 0.0f64) {
                    info = (-201i64)
                }
                *info_ref = info
                ret
            } else if (n == 2i64) {
                if (z[usize((1i64 - 1i64))] < 0.0f64) {
                    info = (-201i64)
                    *info_ref = info
                    ret
                } else if (z[usize((2i64 - 1i64))] < 0.0f64) {
                    info = (-202i64)
                    *info_ref = info
                    ret
                } else if (z[usize((3i64 - 1i64))] < 0.0f64) {
                    info = (-203i64)
                    *info_ref = info
                    ret
                } else if (z[usize((3i64 - 1i64))] > z[usize((1i64 - 1i64))]) {
                    d = z[usize((3i64 - 1i64))]
                    z[usize((3i64 - 1i64))] = z[usize((1i64 - 1i64))]
                    z[usize((1i64 - 1i64))] = d
                }
                z[usize((5i64 - 1i64))] = ((z[usize((1i64 - 1i64))] + z[usize((2i64 - 1i64))]) + z[usize((3i64 - 1i64))])
                if (z[usize((2i64 - 1i64))] > (z[usize((3i64 - 1i64))] * tol2)) {
                    t = (0.5f64 * ((((z[usize((1i64 - 1i64))] - z[usize((3i64 - 1i64))])) + z[usize((2i64 - 1i64))])))
                    s = (z[usize((3i64 - 1i64))] * ((z[usize((2i64 - 1i64))] / t)))
                    if (s <= t) {
                        s = (z[usize((3i64 - 1i64))] * ((z[usize((2i64 - 1i64))] / ((t * ((1.0f64 + math.sqrt[f64]((1.0f64 + (s / t))))))))))
                    } else {
                        s = (z[usize((3i64 - 1i64))] * ((z[usize((2i64 - 1i64))] / ((t + (math.sqrt[f64](t) * math.sqrt[f64]((t + s))))))))
                    }
                    t = (z[usize((1i64 - 1i64))] + ((s + z[usize((2i64 - 1i64))])))
                    z[usize((3i64 - 1i64))] = (z[usize((3i64 - 1i64))] * ((z[usize((1i64 - 1i64))] / t)))
                    z[usize((1i64 - 1i64))] = t
                }
                z[usize((2i64 - 1i64))] = z[usize((3i64 - 1i64))]
                z[usize((6i64 - 1i64))] = (z[usize((2i64 - 1i64))] + z[usize((1i64 - 1i64))])
                *info_ref = info
                ret
            }
            z[usize(((2i64 * n) - 1i64))] = 0.0f64
            emin = z[usize((2i64 - 1i64))]
            qmax = 0.0f64
            zmax = 0.0f64
            d = 0.0f64
            e = 0.0f64
            k = 1i64
            zs2 = 2i64
            zc1 = (((2i64 * ((n - 1i64))) - k) + zs2) / zs2
            while zc1 > 0i64 {
                if (z[usize((k - 1i64))] < 0.0f64) {
                    info = (-((200i64 + k)))
                    *info_ref = info
                    ret
                } else if (z[usize(((k + 1i64) - 1i64))] < 0.0f64) {
                    info = (-(((200i64 + k) + 1i64)))
                    *info_ref = info
                    ret
                }
                d = (d + z[usize((k - 1i64))])
                e = (e + z[usize(((k + 1i64) - 1i64))])
                qmax = lbase.f_max(qmax, z[usize((k - 1i64))])
                emin = lbase.f_min(emin, z[usize(((k + 1i64) - 1i64))])
                zmax = lbase.f_max(lbase.f_max(qmax, zmax), z[usize(((k + 1i64) - 1i64))])
                k = k + zs2
                zc1 = zc1 - 1i64
            }
            if (z[usize((((2i64 * n) - 1i64) - 1i64))] < 0.0f64) {
                info = (-(((200i64 + (2i64 * n)) - 1i64)))
                *info_ref = info
                ret
            }
            d = (d + z[usize((((2i64 * n) - 1i64) - 1i64))])
            qmax = lbase.f_max(qmax, z[usize((((2i64 * n) - 1i64) - 1i64))])
            zmax = lbase.f_max(qmax, zmax)
            if (e == 0.0f64) {
                k = 2i64
                zc3 = (n - k) + 1i64
                while zc3 > 0i64 {
                    z[usize((k - 1i64))] = z[usize((((2i64 * k) - 1i64) - 1i64))]
                    k = k + 1i64
                    zc3 = zc3 - 1i64
                }
                lbase.dlasrt("D", n, z[0usize..], &iinfo)
                z[usize((((2i64 * n) - 1i64) - 1i64))] = d
                *info_ref = info
                ret
            }
            trace = (d + e)
            if (trace == 0.0f64) {
                z[usize((((2i64 * n) - 1i64) - 1i64))] = 0.0f64
                *info_ref = info
                ret
            }
            ieee = ((lbase.ilaenv(10i64, "DLASQ2", "N", 1i64, 2i64, 3i64, 4i64) == 1i64))
            k = (2i64 * n)
            zs5 = (-2i64)
            zc4 = ((2i64 - k) + zs5) / zs5
            while zc4 > 0i64 {
                z[usize(((2i64 * k) - 1i64))] = 0.0f64
                z[usize((((2i64 * k) - 1i64) - 1i64))] = z[usize((k - 1i64))]
                z[usize((((2i64 * k) - 2i64) - 1i64))] = 0.0f64
                z[usize((((2i64 * k) - 3i64) - 1i64))] = z[usize(((k - 1i64) - 1i64))]
                k = k + zs5
                zc4 = zc4 - 1i64
            }
            i0 = 1i64
            n0 = n
            if ((1.5f64 * z[usize((((4i64 * i0) - 3i64) - 1i64))]) < z[usize((((4i64 * n0) - 3i64) - 1i64))]) {
                ipn4 = (4i64 * ((i0 + n0)))
                i4 = (4i64 * i0)
                zs7 = 4i64
                zc6 = (((2i64 * (((i0 + n0) - 1i64))) - i4) + zs7) / zs7
                while zc6 > 0i64 {
                    temp = z[usize(((i4 - 3i64) - 1i64))]
                    z[usize(((i4 - 3i64) - 1i64))] = z[usize((((ipn4 - i4) - 3i64) - 1i64))]
                    z[usize((((ipn4 - i4) - 3i64) - 1i64))] = temp
                    temp = z[usize(((i4 - 1i64) - 1i64))]
                    z[usize(((i4 - 1i64) - 1i64))] = z[usize((((ipn4 - i4) - 5i64) - 1i64))]
                    z[usize((((ipn4 - i4) - 5i64) - 1i64))] = temp
                    i4 = i4 + zs7
                    zc6 = zc6 - 1i64
                }
            }
            pp = 0i64
            k = 1i64
            zc8 = (2i64 - k) + 1i64
            while zc8 > 0i64 {
                d = z[usize(((((4i64 * n0) + pp) - 3i64) - 1i64))]
                i4 = ((4i64 * ((n0 - 1i64))) + pp)
                zs10 = (-4i64)
                zc9 = ((((4i64 * i0) + pp) - i4) + zs10) / zs10
                while zc9 > 0i64 {
                    if (z[usize(((i4 - 1i64) - 1i64))] <= (tol2 * d)) {
                        z[usize(((i4 - 1i64) - 1i64))] = (-0.0f64)
                        d = z[usize(((i4 - 3i64) - 1i64))]
                    } else {
                        d = (z[usize(((i4 - 3i64) - 1i64))] * ((d / ((d + z[usize(((i4 - 1i64) - 1i64))])))))
                    }
                    i4 = i4 + zs10
                    zc9 = zc9 - 1i64
                }
                emin = z[usize(((((4i64 * i0) + pp) + 1i64) - 1i64))]
                d = z[usize(((((4i64 * i0) + pp) - 3i64) - 1i64))]
                i4 = ((4i64 * i0) + pp)
                zs12 = 4i64
                zc11 = ((((4i64 * ((n0 - 1i64))) + pp) - i4) + zs12) / zs12
                while zc11 > 0i64 {
                    z[usize((((i4 - (2i64 * pp)) - 2i64) - 1i64))] = (d + z[usize(((i4 - 1i64) - 1i64))])
                    if (z[usize(((i4 - 1i64) - 1i64))] <= (tol2 * d)) {
                        z[usize(((i4 - 1i64) - 1i64))] = (-0.0f64)
                        z[usize((((i4 - (2i64 * pp)) - 2i64) - 1i64))] = d
                        z[usize(((i4 - (2i64 * pp)) - 1i64))] = 0.0f64
                        d = z[usize(((i4 + 1i64) - 1i64))]
                    } else if (((safmin * z[usize(((i4 + 1i64) - 1i64))]) < z[usize((((i4 - (2i64 * pp)) - 2i64) - 1i64))]) && ((safmin * z[usize((((i4 - (2i64 * pp)) - 2i64) - 1i64))]) < z[usize(((i4 + 1i64) - 1i64))])) {
                        temp = (z[usize(((i4 + 1i64) - 1i64))] / z[usize((((i4 - (2i64 * pp)) - 2i64) - 1i64))])
                        z[usize(((i4 - (2i64 * pp)) - 1i64))] = (z[usize(((i4 - 1i64) - 1i64))] * temp)
                        d = (d * temp)
                    } else {
                        z[usize(((i4 - (2i64 * pp)) - 1i64))] = (z[usize(((i4 + 1i64) - 1i64))] * ((z[usize(((i4 - 1i64) - 1i64))] / z[usize((((i4 - (2i64 * pp)) - 2i64) - 1i64))])))
                        d = (z[usize(((i4 + 1i64) - 1i64))] * ((d / z[usize((((i4 - (2i64 * pp)) - 2i64) - 1i64))])))
                    }
                    emin = lbase.f_min(emin, z[usize(((i4 - (2i64 * pp)) - 1i64))])
                    i4 = i4 + zs12
                    zc11 = zc11 - 1i64
                }
                z[usize(((((4i64 * n0) - pp) - 2i64) - 1i64))] = d
                qmax = z[usize(((((4i64 * i0) - pp) - 2i64) - 1i64))]
                i4 = (((4i64 * i0) - pp) + 2i64)
                zs14 = 4i64
                zc13 = (((((4i64 * n0) - pp) - 2i64) - i4) + zs14) / zs14
                while zc13 > 0i64 {
                    qmax = lbase.f_max(qmax, z[usize((i4 - 1i64))])
                    i4 = i4 + zs14
                    zc13 = zc13 - 1i64
                }
                pp = (1i64 - pp)
                k = k + 1i64
                zc8 = zc8 - 1i64
            }
            ttype = 0i64
            dmin1 = 0.0f64
            dmin2 = 0.0f64
            dn = 0.0f64
            dn1 = 0.0f64
            dn2 = 0.0f64
            g = 0.0f64
            tau = 0.0f64
            iter = 2i64
            nfail = 0i64
            ndiv = (2i64 * ((n0 - i0)))
            iwhila = 1i64
            zc15 = ((n + 1i64) - iwhila) + 1i64
            pc = 1i64
        }
        if pc == 1i64 {
            if zc15 <= 0i64 {
                pc = 2i64
                continue
            }
            if !(n0 < 1i64) {
                pc = 4i64
                continue
            }
            pc = 5i64
            continue
        }
        if pc == 4i64 {
            pc = 3i64
        }
        if pc == 3i64 {
            desig = 0.0f64
            if (n0 == n) {
                sigma = 0.0f64
            } else {
                sigma = (-z[usize((((4i64 * n0) - 1i64) - 1i64))])
            }
            if (sigma < 0.0f64) {
                info = 1i64
                *info_ref = info
                ret
            }
            emax = 0.0f64
            if (n0 > i0) {
                emin = math.abs[f64](z[usize((((4i64 * n0) - 5i64) - 1i64))])
            } else {
                emin = 0.0f64
            }
            qmin = z[usize((((4i64 * n0) - 3i64) - 1i64))]
            qmax = qmin
            i4 = (4i64 * n0)
            zs17 = (-4i64)
            zc16 = ((8i64 - i4) + zs17) / zs17
            pc = 6i64
        }
        if pc == 6i64 {
            if zc16 <= 0i64 {
                pc = 7i64
                continue
            }
            if !(z[usize(((i4 - 5i64) - 1i64))] <= 0.0f64) {
                pc = 9i64
                continue
            }
            pc = 10i64
            continue
        }
        if pc == 9i64 {
            pc = 8i64
        }
        if pc == 8i64 {
            if (qmin >= (4.0f64 * emax)) {
                qmin = lbase.f_min(qmin, z[usize(((i4 - 3i64) - 1i64))])
                emax = lbase.f_max(emax, z[usize(((i4 - 5i64) - 1i64))])
            }
            qmax = lbase.f_max(qmax, (z[usize(((i4 - 7i64) - 1i64))] + z[usize(((i4 - 5i64) - 1i64))]))
            emin = lbase.f_min(emin, z[usize(((i4 - 5i64) - 1i64))])
            i4 = i4 + zs17
            zc16 = zc16 - 1i64
            pc = 6i64
            continue
        }
        if pc == 7i64 {
            i4 = 4i64
            pc = 10i64
        }
        if pc == 10i64 {
            i0 = (i4 / 4i64)
            pp = 0i64
            if ((n0 - i0) > 1i64) {
                dee = z[usize((((4i64 * i0) - 3i64) - 1i64))]
                deemin = dee
                kmin = i0
                i4 = ((4i64 * i0) + 1i64)
                zs19 = 4i64
                zc18 = ((((4i64 * n0) - 3i64) - i4) + zs19) / zs19
                while zc18 > 0i64 {
                    dee = (z[usize((i4 - 1i64))] * ((dee / ((dee + z[usize(((i4 - 2i64) - 1i64))])))))
                    if (dee <= deemin) {
                        deemin = dee
                        kmin = (((i4 + 3i64)) / 4i64)
                    }
                    i4 = i4 + zs19
                    zc18 = zc18 - 1i64
                }
                if (((((kmin - i0)) * 2i64) < (n0 - kmin)) && (deemin <= (0.5f64 * z[usize((((4i64 * n0) - 3i64) - 1i64))]))) {
                    ipn4 = (4i64 * ((i0 + n0)))
                    pp = 2i64
                    i4 = (4i64 * i0)
                    zs21 = 4i64
                    zc20 = (((2i64 * (((i0 + n0) - 1i64))) - i4) + zs21) / zs21
                    while zc20 > 0i64 {
                        temp = z[usize(((i4 - 3i64) - 1i64))]
                        z[usize(((i4 - 3i64) - 1i64))] = z[usize((((ipn4 - i4) - 3i64) - 1i64))]
                        z[usize((((ipn4 - i4) - 3i64) - 1i64))] = temp
                        temp = z[usize(((i4 - 2i64) - 1i64))]
                        z[usize(((i4 - 2i64) - 1i64))] = z[usize((((ipn4 - i4) - 2i64) - 1i64))]
                        z[usize((((ipn4 - i4) - 2i64) - 1i64))] = temp
                        temp = z[usize(((i4 - 1i64) - 1i64))]
                        z[usize(((i4 - 1i64) - 1i64))] = z[usize((((ipn4 - i4) - 5i64) - 1i64))]
                        z[usize((((ipn4 - i4) - 5i64) - 1i64))] = temp
                        temp = z[usize((i4 - 1i64))]
                        z[usize((i4 - 1i64))] = z[usize((((ipn4 - i4) - 4i64) - 1i64))]
                        z[usize((((ipn4 - i4) - 4i64) - 1i64))] = temp
                        i4 = i4 + zs21
                        zc20 = zc20 - 1i64
                    }
                }
            }
            dmin = (-lbase.f_max(0.0f64, (qmin - ((2.0f64 * math.sqrt[f64](qmin)) * math.sqrt[f64](emax)))))
            nbig = (100i64 * (((n0 - i0) + 1i64)))
            iwhilb = 1i64
            zc22 = (nbig - iwhilb) + 1i64
            pc = 11i64
        }
        if pc == 11i64 {
            if zc22 <= 0i64 {
                pc = 12i64
                continue
            }
            if !(i0 > n0) {
                pc = 14i64
                continue
            }
            pc = 15i64
            continue
        }
        if pc == 14i64 {
            pc = 13i64
        }
        if pc == 13i64 {
            dlasq3(i0, &n0, z[0usize..], &pp, &dmin, &sigma, &desig, &qmax, &nfail, &iter, &ndiv, ieee, &ttype, &dmin1, &dmin2, &dn, &dn1, &dn2, &g, &tau)
            pp = (1i64 - pp)
            if ((pp == 0i64) && ((n0 - i0) >= 3i64)) {
                if ((z[usize(((4i64 * n0) - 1i64))] <= (tol2 * qmax)) || (z[usize((((4i64 * n0) - 1i64) - 1i64))] <= (tol2 * sigma))) {
                    splt = (i0 - 1i64)
                    qmax = z[usize((((4i64 * i0) - 3i64) - 1i64))]
                    emin = z[usize((((4i64 * i0) - 1i64) - 1i64))]
                    oldemn = z[usize(((4i64 * i0) - 1i64))]
                    i4 = (4i64 * i0)
                    zs24 = 4i64
                    zc23 = (((4i64 * ((n0 - 3i64))) - i4) + zs24) / zs24
                    while zc23 > 0i64 {
                        if ((z[usize((i4 - 1i64))] <= (tol2 * z[usize(((i4 - 3i64) - 1i64))])) || (z[usize(((i4 - 1i64) - 1i64))] <= (tol2 * sigma))) {
                            z[usize(((i4 - 1i64) - 1i64))] = (-sigma)
                            splt = (i4 / 4i64)
                            qmax = 0.0f64
                            emin = z[usize(((i4 + 3i64) - 1i64))]
                            oldemn = z[usize(((i4 + 4i64) - 1i64))]
                        } else {
                            qmax = lbase.f_max(qmax, z[usize(((i4 + 1i64) - 1i64))])
                            emin = lbase.f_min(emin, z[usize(((i4 - 1i64) - 1i64))])
                            oldemn = lbase.f_min(oldemn, z[usize((i4 - 1i64))])
                        }
                        i4 = i4 + zs24
                        zc23 = zc23 - 1i64
                    }
                    z[usize((((4i64 * n0) - 1i64) - 1i64))] = emin
                    z[usize(((4i64 * n0) - 1i64))] = oldemn
                    i0 = (splt + 1i64)
                }
            }
            iwhilb = iwhilb + 1i64
            zc22 = zc22 - 1i64
            pc = 11i64
            continue
        }
        if pc == 12i64 {
            info = 2i64
            i1 = i0
            n1 = n0
            pc = 16i64
        }
        if pc == 16i64 {
            tempq = z[usize((((4i64 * i0) - 3i64) - 1i64))]
            z[usize((((4i64 * i0) - 3i64) - 1i64))] = (z[usize((((4i64 * i0) - 3i64) - 1i64))] + sigma)
            k = (i0 + 1i64)
            zc25 = (n0 - k) + 1i64
            while zc25 > 0i64 {
                tempe = z[usize((((4i64 * k) - 5i64) - 1i64))]
                z[usize((((4i64 * k) - 5i64) - 1i64))] = (z[usize((((4i64 * k) - 5i64) - 1i64))] * ((tempq / z[usize((((4i64 * k) - 7i64) - 1i64))])))
                tempq = z[usize((((4i64 * k) - 3i64) - 1i64))]
                z[usize((((4i64 * k) - 3i64) - 1i64))] = (((z[usize((((4i64 * k) - 3i64) - 1i64))] + sigma) + tempe) - z[usize((((4i64 * k) - 5i64) - 1i64))])
                k = k + 1i64
                zc25 = zc25 - 1i64
            }
            if !(i1 > 1i64) {
                pc = 18i64
                continue
            }
            n1 = (i1 - 1i64)
            while (((i1 >= 2i64)) && ((z[usize((((4i64 * i1) - 5i64) - 1i64))] >= 0.0f64))) {
                i1 = (i1 - 1i64)
            }
            sigma = (-z[usize((((4i64 * n1) - 1i64) - 1i64))])
            pc = 16i64
            continue
        }
        if pc == 18i64 {
            pc = 17i64
        }
        if pc == 17i64 {
            k = 1i64
            zc26 = (n - k) + 1i64
            while zc26 > 0i64 {
                z[usize((((2i64 * k) - 1i64) - 1i64))] = z[usize((((4i64 * k) - 3i64) - 1i64))]
                if (k < n0) {
                    z[usize(((2i64 * k) - 1i64))] = z[usize((((4i64 * k) - 1i64) - 1i64))]
                } else {
                    z[usize(((2i64 * k) - 1i64))] = 0.0f64
                }
                k = k + 1i64
                zc26 = zc26 - 1i64
            }
            *info_ref = info
            ret
        }
        if pc == 15i64 {
            iwhila = iwhila + 1i64
            zc15 = zc15 - 1i64
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            info = 3i64
            *info_ref = info
            ret
        }
        if pc == 5i64 {
            k = 2i64
            zc27 = (n - k) + 1i64
            while zc27 > 0i64 {
                z[usize((k - 1i64))] = z[usize((((4i64 * k) - 3i64) - 1i64))]
                k = k + 1i64
                zc27 = zc27 - 1i64
            }
            lbase.dlasrt("D", n, z[0usize..], &iinfo)
            e = 0.0f64
            k = n
            zs29 = (-1i64)
            zc28 = ((1i64 - k) + zs29) / zs29
            while zc28 > 0i64 {
                e = (e + z[usize((k - 1i64))])
                k = k + zs29
                zc28 = zc28 - 1i64
            }
            z[usize((((2i64 * n) + 1i64) - 1i64))] = trace
            z[usize((((2i64 * n) + 2i64) - 1i64))] = e
            z[usize((((2i64 * n) + 3i64) - 1i64))] = f64(iter)
            z[usize((((2i64 * n) + 4i64) - 1i64))] = (f64(ndiv) / f64((n * n)))
            z[usize((((2i64 * n) + 5i64) - 1i64))] = ((100.0f64 * f64(nfail)) / f64(iter))
            *info_ref = info
            ret
        }
    }
}

fn dlasq3(i0: i64, n0_ref: *i64, z: []f64, pp_ref: *i64, dmin_ref: *f64, sigma_ref: *f64, desig_ref: *f64, qmax_ref: *f64, nfail_ref: *i64, iter_ref: *i64, ndiv_ref: *i64, ieee: bool, ttype_ref: *i64, dmin1_ref: *f64, dmin2_ref: *f64, dn_ref: *f64, dn1_ref: *f64, dn2_ref: *f64, g_ref: *f64, tau_ref: *f64) {
    var n0 = *n0_ref
    var pp = *pp_ref
    var dmin = *dmin_ref
    var sigma = *sigma_ref
    var desig = *desig_ref
    var qmax = *qmax_ref
    var nfail = *nfail_ref
    var iter = *iter_ref
    var ndiv = *ndiv_ref
    var ttype = *ttype_ref
    var dmin1 = *dmin1_ref
    var dmin2 = *dmin2_ref
    var dn = *dn_ref
    var dn1 = *dn1_ref
    var dn2 = *dn2_ref
    var g = *g_ref
    var tau = *tau_ref
    var ipn4: i64 = 0i64
    var j4: i64 = 0i64
    var n0in: i64 = 0i64
    var nn: i64 = 0i64
    var eps: f64 = 0.0f64
    var s: f64 = 0.0f64
    var t: f64 = 0.0f64
    var temp: f64 = 0.0f64
    var tol: f64 = 0.0f64
    var tol2: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            n0in = n0
            eps = 2.220446049250313e-16f64
            tol = (eps * 100.0f64)
            tol2 = (tol * tol)
            pc = 1i64
        }
        if pc == 1i64 {
            if (n0 < i0) {
                *n0_ref = n0
                *pp_ref = pp
                *dmin_ref = dmin
                *sigma_ref = sigma
                *desig_ref = desig
                *qmax_ref = qmax
                *nfail_ref = nfail
                *iter_ref = iter
                *ndiv_ref = ndiv
                *ttype_ref = ttype
                *dmin1_ref = dmin1
                *dmin2_ref = dmin2
                *dn_ref = dn
                *dn1_ref = dn1
                *dn2_ref = dn2
                *g_ref = g
                *tau_ref = tau
                ret
            }
            if !(n0 == i0) {
                pc = 3i64
                continue
            }
            pc = 4i64
            continue
        }
        if pc == 3i64 {
            pc = 2i64
        }
        if pc == 2i64 {
            nn = ((4i64 * n0) + pp)
            if !(n0 == ((i0 + 1i64))) {
                pc = 6i64
                continue
            }
            pc = 7i64
            continue
        }
        if pc == 6i64 {
            pc = 5i64
        }
        if pc == 5i64 {
            if !((z[usize(((nn - 5i64) - 1i64))] > (tol2 * ((sigma + z[usize(((nn - 3i64) - 1i64))])))) && (z[usize((((nn - (2i64 * pp)) - 4i64) - 1i64))] > (tol2 * z[usize(((nn - 7i64) - 1i64))]))) {
                pc = 9i64
                continue
            }
            pc = 10i64
            continue
        }
        if pc == 9i64 {
            pc = 8i64
        }
        if pc == 8i64 {
            pc = 4i64
        }
        if pc == 4i64 {
            z[usize((((4i64 * n0) - 3i64) - 1i64))] = (z[usize(((((4i64 * n0) + pp) - 3i64) - 1i64))] + sigma)
            n0 = (n0 - 1i64)
            pc = 1i64
            continue
        }
        if pc == 10i64 {
            if !((z[usize(((nn - 9i64) - 1i64))] > (tol2 * sigma)) && (z[usize((((nn - (2i64 * pp)) - 8i64) - 1i64))] > (tol2 * z[usize(((nn - 11i64) - 1i64))]))) {
                pc = 12i64
                continue
            }
            pc = 13i64
            continue
        }
        if pc == 12i64 {
            pc = 11i64
        }
        if pc == 11i64 {
            pc = 7i64
        }
        if pc == 7i64 {
            if (z[usize(((nn - 3i64) - 1i64))] > z[usize(((nn - 7i64) - 1i64))]) {
                s = z[usize(((nn - 3i64) - 1i64))]
                z[usize(((nn - 3i64) - 1i64))] = z[usize(((nn - 7i64) - 1i64))]
                z[usize(((nn - 7i64) - 1i64))] = s
            }
            t = (0.5f64 * ((((z[usize(((nn - 7i64) - 1i64))] - z[usize(((nn - 3i64) - 1i64))])) + z[usize(((nn - 5i64) - 1i64))])))
            if ((z[usize(((nn - 5i64) - 1i64))] > (z[usize(((nn - 3i64) - 1i64))] * tol2)) && (t != 0.0f64)) {
                s = (z[usize(((nn - 3i64) - 1i64))] * ((z[usize(((nn - 5i64) - 1i64))] / t)))
                if (s <= t) {
                    s = (z[usize(((nn - 3i64) - 1i64))] * ((z[usize(((nn - 5i64) - 1i64))] / ((t * ((1.0f64 + math.sqrt[f64]((1.0f64 + (s / t))))))))))
                } else {
                    s = (z[usize(((nn - 3i64) - 1i64))] * ((z[usize(((nn - 5i64) - 1i64))] / ((t + (math.sqrt[f64](t) * math.sqrt[f64]((t + s))))))))
                }
                t = (z[usize(((nn - 7i64) - 1i64))] + ((s + z[usize(((nn - 5i64) - 1i64))])))
                z[usize(((nn - 3i64) - 1i64))] = (z[usize(((nn - 3i64) - 1i64))] * ((z[usize(((nn - 7i64) - 1i64))] / t)))
                z[usize(((nn - 7i64) - 1i64))] = t
            }
            z[usize((((4i64 * n0) - 7i64) - 1i64))] = (z[usize(((nn - 7i64) - 1i64))] + sigma)
            z[usize((((4i64 * n0) - 3i64) - 1i64))] = (z[usize(((nn - 3i64) - 1i64))] + sigma)
            n0 = (n0 - 2i64)
            pc = 1i64
            continue
        }
        if pc == 13i64 {
            if (pp == 2i64) {
                pp = 0i64
            }
            if ((dmin <= 0.0f64) || (n0 < n0in)) {
                if ((1.5f64 * z[usize(((((4i64 * i0) + pp) - 3i64) - 1i64))]) < z[usize(((((4i64 * n0) + pp) - 3i64) - 1i64))]) {
                    ipn4 = (4i64 * ((i0 + n0)))
                    j4 = (4i64 * i0)
                    zs2 = 4i64
                    zc1 = (((2i64 * (((i0 + n0) - 1i64))) - j4) + zs2) / zs2
                    while zc1 > 0i64 {
                        temp = z[usize(((j4 - 3i64) - 1i64))]
                        z[usize(((j4 - 3i64) - 1i64))] = z[usize((((ipn4 - j4) - 3i64) - 1i64))]
                        z[usize((((ipn4 - j4) - 3i64) - 1i64))] = temp
                        temp = z[usize(((j4 - 2i64) - 1i64))]
                        z[usize(((j4 - 2i64) - 1i64))] = z[usize((((ipn4 - j4) - 2i64) - 1i64))]
                        z[usize((((ipn4 - j4) - 2i64) - 1i64))] = temp
                        temp = z[usize(((j4 - 1i64) - 1i64))]
                        z[usize(((j4 - 1i64) - 1i64))] = z[usize((((ipn4 - j4) - 5i64) - 1i64))]
                        z[usize((((ipn4 - j4) - 5i64) - 1i64))] = temp
                        temp = z[usize((j4 - 1i64))]
                        z[usize((j4 - 1i64))] = z[usize((((ipn4 - j4) - 4i64) - 1i64))]
                        z[usize((((ipn4 - j4) - 4i64) - 1i64))] = temp
                        j4 = j4 + zs2
                        zc1 = zc1 - 1i64
                    }
                    if ((n0 - i0) <= 4i64) {
                        z[usize(((((4i64 * n0) + pp) - 1i64) - 1i64))] = z[usize(((((4i64 * i0) + pp) - 1i64) - 1i64))]
                        z[usize((((4i64 * n0) - pp) - 1i64))] = z[usize((((4i64 * i0) - pp) - 1i64))]
                    }
                    dmin2 = lbase.f_min(dmin2, z[usize(((((4i64 * n0) + pp) - 1i64) - 1i64))])
                    z[usize(((((4i64 * n0) + pp) - 1i64) - 1i64))] = lbase.f_min(lbase.f_min(z[usize(((((4i64 * n0) + pp) - 1i64) - 1i64))], z[usize(((((4i64 * i0) + pp) - 1i64) - 1i64))]), z[usize(((((4i64 * i0) + pp) + 3i64) - 1i64))])
                    z[usize((((4i64 * n0) - pp) - 1i64))] = lbase.f_min(lbase.f_min(z[usize((((4i64 * n0) - pp) - 1i64))], z[usize((((4i64 * i0) - pp) - 1i64))]), z[usize(((((4i64 * i0) - pp) + 4i64) - 1i64))])
                    qmax = lbase.f_max(lbase.f_max(qmax, z[usize(((((4i64 * i0) + pp) - 3i64) - 1i64))]), z[usize(((((4i64 * i0) + pp) + 1i64) - 1i64))])
                    dmin = (-0.0f64)
                }
            }
            dlasq4(i0, n0, z[0usize..], pp, n0in, dmin, dmin1, dmin2, dn, dn1, dn2, &tau, &ttype, &g)
            pc = 14i64
        }
        if pc == 14i64 {
            dlasq5(i0, n0, z[0usize..], pp, &tau, sigma, &dmin, &dmin1, &dmin2, &dn, &dn1, &dn2, ieee, eps)
            ndiv = (ndiv + (((n0 - i0) + 2i64)))
            iter = (iter + 1i64)
            if !((dmin >= 0.0f64) && (dmin1 >= 0.0f64)) {
                pc = 16i64
                continue
            }
            pc = 17i64
            continue
        }
        if pc == 16i64 {
            if !((((dmin < 0.0f64) && (dmin1 > 0.0f64)) && (z[usize((((4i64 * ((n0 - 1i64))) - pp) - 1i64))] < (tol * ((sigma + dn1))))) && (math.abs[f64](dn) < (tol * sigma))) {
                pc = 18i64
                continue
            }
            z[usize(((((4i64 * ((n0 - 1i64))) - pp) + 2i64) - 1i64))] = 0.0f64
            dmin = 0.0f64
            pc = 17i64
            continue
        }
        if pc == 18i64 {
            if !(dmin < 0.0f64) {
                pc = 19i64
                continue
            }
            nfail = (nfail + 1i64)
            if (ttype < (-22i64)) {
                tau = 0.0f64
            } else if (dmin1 > 0.0f64) {
                tau = (((tau + dmin)) * ((1.0f64 - (2.0f64 * eps))))
                ttype = (ttype - 11i64)
            } else {
                tau = (0.25f64 * tau)
                ttype = (ttype - 12i64)
            }
            pc = 14i64
            continue
        }
        if pc == 19i64 {
            if !lbase.disnan(dmin) {
                pc = 20i64
                continue
            }
            if !(tau == 0.0f64) {
                pc = 22i64
                continue
            }
            pc = 23i64
            continue
        }
        if pc == 22i64 {
            tau = 0.0f64
            pc = 14i64
            continue
        }
        if pc == 21i64 {
            pc = 15i64
            continue
        }
        if pc == 20i64 {
            pc = 23i64
            continue
        }
        if pc == 15i64 {
            pc = 23i64
        }
        if pc == 23i64 {
            dlasq6(i0, n0, z[0usize..], pp, &dmin, &dmin1, &dmin2, &dn, &dn1, &dn2)
            ndiv = (ndiv + (((n0 - i0) + 2i64)))
            iter = (iter + 1i64)
            tau = 0.0f64
            pc = 17i64
        }
        if pc == 17i64 {
            if (tau < sigma) {
                desig = (desig + tau)
                t = (sigma + desig)
                desig = (desig - ((t - sigma)))
            } else {
                t = (sigma + tau)
                desig = ((sigma - ((t - tau))) + desig)
            }
            sigma = t
            *n0_ref = n0
            *pp_ref = pp
            *dmin_ref = dmin
            *sigma_ref = sigma
            *desig_ref = desig
            *qmax_ref = qmax
            *nfail_ref = nfail
            *iter_ref = iter
            *ndiv_ref = ndiv
            *ttype_ref = ttype
            *dmin1_ref = dmin1
            *dmin2_ref = dmin2
            *dn_ref = dn
            *dn1_ref = dn1
            *dn2_ref = dn2
            *g_ref = g
            *tau_ref = tau
            ret
        }
    }
}

fn dlasq4(i0: i64, n0: i64, z: []f64, pp: i64, n0in: i64, dmin: f64, dmin1: f64, dmin2: f64, dn: f64, dn1: f64, dn2: f64, tau_ref: *f64, ttype_ref: *i64, g_ref: *f64) {
    var tau = *tau_ref
    var ttype = *ttype_ref
    var g = *g_ref
    var i4: i64 = 0i64
    var nn: i64 = 0i64
    var np: i64 = 0i64
    var a2: f64 = 0.0f64
    var b1: f64 = 0.0f64
    var b2: f64 = 0.0f64
    var gam: f64 = 0.0f64
    var gap1: f64 = 0.0f64
    var gap2: f64 = 0.0f64
    var s: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
    var zc3: i64 = 0i64
    var zs4: i64 = 0i64
    var zc5: i64 = 0i64
    var zs6: i64 = 0i64
    var zc7: i64 = 0i64
    var zs8: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            if (dmin <= 0.0f64) {
                tau = (-dmin)
                ttype = (-1i64)
                *tau_ref = tau
                *ttype_ref = ttype
                *g_ref = g
                ret
            }
            nn = ((4i64 * n0) + pp)
            if !(n0in == n0) {
                pc = 2i64
                continue
            }
            if !((dmin == dn) || (dmin == dn1)) {
                pc = 4i64
                continue
            }
            b1 = (math.sqrt[f64](z[usize(((nn - 3i64) - 1i64))]) * math.sqrt[f64](z[usize(((nn - 5i64) - 1i64))]))
            b2 = (math.sqrt[f64](z[usize(((nn - 7i64) - 1i64))]) * math.sqrt[f64](z[usize(((nn - 9i64) - 1i64))]))
            a2 = (z[usize(((nn - 7i64) - 1i64))] + z[usize(((nn - 5i64) - 1i64))])
            if !((dmin == dn) && (dmin1 == dn1)) {
                pc = 6i64
                continue
            }
            gap2 = ((dmin2 - a2) - (dmin2 * 0.25f64))
            if ((gap2 > 0.0f64) && (gap2 > b2)) {
                gap1 = ((a2 - dn) - (((b2 / gap2)) * b2))
            } else {
                gap1 = ((a2 - dn) - ((b1 + b2)))
            }
            if ((gap1 > 0.0f64) && (gap1 > b1)) {
                s = lbase.f_max((dn - (((b1 / gap1)) * b1)), (0.5f64 * dmin))
                ttype = (-2i64)
            } else {
                s = 0.0f64
                if (dn > b1) {
                    s = (dn - b1)
                }
                if (a2 > ((b1 + b2))) {
                    s = lbase.f_min(s, (a2 - ((b1 + b2))))
                }
                s = lbase.f_max(s, (0.333f64 * dmin))
                ttype = (-3i64)
            }
            pc = 5i64
            continue
        }
        if pc == 6i64 {
            ttype = (-4i64)
            s = (0.25f64 * dmin)
            if (dmin == dn) {
                gam = dn
                a2 = 0.0f64
                if (z[usize(((nn - 5i64) - 1i64))] > z[usize(((nn - 7i64) - 1i64))]) {
                    *tau_ref = tau
                    *ttype_ref = ttype
                    *g_ref = g
                    ret
                }
                b2 = (z[usize(((nn - 5i64) - 1i64))] / z[usize(((nn - 7i64) - 1i64))])
                np = (nn - 9i64)
            } else {
                np = (nn - (2i64 * pp))
                gam = dn1
                if (z[usize(((np - 4i64) - 1i64))] > z[usize(((np - 2i64) - 1i64))]) {
                    *tau_ref = tau
                    *ttype_ref = ttype
                    *g_ref = g
                    ret
                }
                a2 = (z[usize(((np - 4i64) - 1i64))] / z[usize(((np - 2i64) - 1i64))])
                if (z[usize(((nn - 9i64) - 1i64))] > z[usize(((nn - 11i64) - 1i64))]) {
                    *tau_ref = tau
                    *ttype_ref = ttype
                    *g_ref = g
                    ret
                }
                b2 = (z[usize(((nn - 9i64) - 1i64))] / z[usize(((nn - 11i64) - 1i64))])
                np = (nn - 13i64)
            }
            a2 = (a2 + b2)
            i4 = np
            zs2 = (-4i64)
            zc1 = (((((4i64 * i0) - 1i64) + pp) - i4) + zs2) / zs2
            pc = 7i64
        }
        if pc == 7i64 {
            if zc1 <= 0i64 {
                pc = 8i64
                continue
            }
            if !(b2 == 0.0f64) {
                pc = 10i64
                continue
            }
            pc = 11i64
            continue
        }
        if pc == 10i64 {
            pc = 9i64
        }
        if pc == 9i64 {
            b1 = b2
            if (z[usize((i4 - 1i64))] > z[usize(((i4 - 2i64) - 1i64))]) {
                *tau_ref = tau
                *ttype_ref = ttype
                *g_ref = g
                ret
            }
            b2 = (b2 * ((z[usize((i4 - 1i64))] / z[usize(((i4 - 2i64) - 1i64))])))
            a2 = (a2 + b2)
            if !(((100.0f64 * lbase.f_max(b2, b1)) < a2) || (0.563f64 < a2)) {
                pc = 13i64
                continue
            }
            pc = 11i64
            continue
        }
        if pc == 13i64 {
            pc = 12i64
        }
        if pc == 12i64 {
            i4 = i4 + zs2
            zc1 = zc1 - 1i64
            pc = 7i64
            continue
        }
        if pc == 8i64 {
            pc = 11i64
        }
        if pc == 11i64 {
            a2 = (1.05f64 * a2)
            if (a2 < 0.563f64) {
                s = ((gam * ((1.0f64 - math.sqrt[f64](a2)))) / ((1.0f64 + a2)))
            }
            pc = 5i64
            continue
        }
        if pc == 5i64 {
            pc = 3i64
            continue
        }
        if pc == 4i64 {
            if !(dmin == dn2) {
                pc = 14i64
                continue
            }
            ttype = (-5i64)
            s = (0.25f64 * dmin)
            np = (nn - (2i64 * pp))
            b1 = z[usize(((np - 2i64) - 1i64))]
            b2 = z[usize(((np - 6i64) - 1i64))]
            gam = dn2
            if ((z[usize(((np - 8i64) - 1i64))] > b2) || (z[usize(((np - 4i64) - 1i64))] > b1)) {
                *tau_ref = tau
                *ttype_ref = ttype
                *g_ref = g
                ret
            }
            a2 = (((z[usize(((np - 8i64) - 1i64))] / b2)) * ((1.0f64 + (z[usize(((np - 4i64) - 1i64))] / b1))))
            if !((n0 - i0) > 2i64) {
                pc = 16i64
                continue
            }
            b2 = (z[usize(((nn - 13i64) - 1i64))] / z[usize(((nn - 15i64) - 1i64))])
            a2 = (a2 + b2)
            i4 = (nn - 17i64)
            zs4 = (-4i64)
            zc3 = (((((4i64 * i0) - 1i64) + pp) - i4) + zs4) / zs4
            pc = 17i64
        }
        if pc == 17i64 {
            if zc3 <= 0i64 {
                pc = 18i64
                continue
            }
            if !(b2 == 0.0f64) {
                pc = 20i64
                continue
            }
            pc = 21i64
            continue
        }
        if pc == 20i64 {
            pc = 19i64
        }
        if pc == 19i64 {
            b1 = b2
            if (z[usize((i4 - 1i64))] > z[usize(((i4 - 2i64) - 1i64))]) {
                *tau_ref = tau
                *ttype_ref = ttype
                *g_ref = g
                ret
            }
            b2 = (b2 * ((z[usize((i4 - 1i64))] / z[usize(((i4 - 2i64) - 1i64))])))
            a2 = (a2 + b2)
            if !(((100.0f64 * lbase.f_max(b2, b1)) < a2) || (0.563f64 < a2)) {
                pc = 23i64
                continue
            }
            pc = 21i64
            continue
        }
        if pc == 23i64 {
            pc = 22i64
        }
        if pc == 22i64 {
            i4 = i4 + zs4
            zc3 = zc3 - 1i64
            pc = 17i64
            continue
        }
        if pc == 18i64 {
            pc = 21i64
        }
        if pc == 21i64 {
            a2 = (1.05f64 * a2)
            pc = 15i64
            continue
        }
        if pc == 16i64 {
            pc = 15i64
        }
        if pc == 15i64 {
            if (a2 < 0.563f64) {
                s = ((gam * ((1.0f64 - math.sqrt[f64](a2)))) / ((1.0f64 + a2)))
            }
            pc = 3i64
            continue
        }
        if pc == 14i64 {
            if (ttype == (-6i64)) {
                g = (g + (0.333f64 * ((1.0f64 - g))))
            } else if (ttype == (-18i64)) {
                g = (0.25f64 * 0.333f64)
            } else {
                g = 0.25f64
            }
            s = (g * dmin)
            ttype = (-6i64)
            pc = 3i64
            continue
        }
        if pc == 3i64 {
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            if !(n0in == ((n0 + 1i64))) {
                pc = 24i64
                continue
            }
            if !((dmin1 == dn1) && (dmin2 == dn2)) {
                pc = 26i64
                continue
            }
            ttype = (-7i64)
            s = (0.333f64 * dmin1)
            if (z[usize(((nn - 5i64) - 1i64))] > z[usize(((nn - 7i64) - 1i64))]) {
                *tau_ref = tau
                *ttype_ref = ttype
                *g_ref = g
                ret
            }
            b1 = (z[usize(((nn - 5i64) - 1i64))] / z[usize(((nn - 7i64) - 1i64))])
            b2 = b1
            if !(b2 == 0.0f64) {
                pc = 28i64
                continue
            }
            pc = 29i64
            continue
        }
        if pc == 28i64 {
            pc = 27i64
        }
        if pc == 27i64 {
            i4 = (((4i64 * n0) - 9i64) + pp)
            zs6 = (-4i64)
            zc5 = (((((4i64 * i0) - 1i64) + pp) - i4) + zs6) / zs6
            pc = 30i64
        }
        if pc == 30i64 {
            if zc5 <= 0i64 {
                pc = 31i64
                continue
            }
            a2 = b1
            if (z[usize((i4 - 1i64))] > z[usize(((i4 - 2i64) - 1i64))]) {
                *tau_ref = tau
                *ttype_ref = ttype
                *g_ref = g
                ret
            }
            b1 = (b1 * ((z[usize((i4 - 1i64))] / z[usize(((i4 - 2i64) - 1i64))])))
            b2 = (b2 + b1)
            if !((100.0f64 * lbase.f_max(b1, a2)) < b2) {
                pc = 33i64
                continue
            }
            pc = 29i64
            continue
        }
        if pc == 33i64 {
            pc = 32i64
        }
        if pc == 32i64 {
            i4 = i4 + zs6
            zc5 = zc5 - 1i64
            pc = 30i64
            continue
        }
        if pc == 31i64 {
            pc = 29i64
        }
        if pc == 29i64 {
            b2 = math.sqrt[f64]((1.05f64 * b2))
            a2 = (dmin1 / ((1.0f64 + (b2 * b2))))
            gap2 = ((0.5f64 * dmin2) - a2)
            if ((gap2 > 0.0f64) && (gap2 > (b2 * a2))) {
                s = lbase.f_max(s, (a2 * ((1.0f64 - (((1.01f64 * a2) * ((b2 / gap2))) * b2)))))
            } else {
                s = lbase.f_max(s, (a2 * ((1.0f64 - (1.01f64 * b2)))))
                ttype = (-8i64)
            }
            pc = 25i64
            continue
        }
        if pc == 26i64 {
            s = (0.25f64 * dmin1)
            if (dmin1 == dn1) {
                s = (0.5f64 * dmin1)
            }
            ttype = (-9i64)
            pc = 25i64
            continue
        }
        if pc == 25i64 {
            pc = 1i64
            continue
        }
        if pc == 24i64 {
            if !(n0in == ((n0 + 2i64))) {
                pc = 34i64
                continue
            }
            if !((dmin2 == dn2) && ((2.0f64 * z[usize(((nn - 5i64) - 1i64))]) < z[usize(((nn - 7i64) - 1i64))])) {
                pc = 36i64
                continue
            }
            ttype = (-10i64)
            s = (0.333f64 * dmin2)
            if (z[usize(((nn - 5i64) - 1i64))] > z[usize(((nn - 7i64) - 1i64))]) {
                *tau_ref = tau
                *ttype_ref = ttype
                *g_ref = g
                ret
            }
            b1 = (z[usize(((nn - 5i64) - 1i64))] / z[usize(((nn - 7i64) - 1i64))])
            b2 = b1
            if !(b2 == 0.0f64) {
                pc = 38i64
                continue
            }
            pc = 39i64
            continue
        }
        if pc == 38i64 {
            pc = 37i64
        }
        if pc == 37i64 {
            i4 = (((4i64 * n0) - 9i64) + pp)
            zs8 = (-4i64)
            zc7 = (((((4i64 * i0) - 1i64) + pp) - i4) + zs8) / zs8
            pc = 40i64
        }
        if pc == 40i64 {
            if zc7 <= 0i64 {
                pc = 41i64
                continue
            }
            if (z[usize((i4 - 1i64))] > z[usize(((i4 - 2i64) - 1i64))]) {
                *tau_ref = tau
                *ttype_ref = ttype
                *g_ref = g
                ret
            }
            b1 = (b1 * ((z[usize((i4 - 1i64))] / z[usize(((i4 - 2i64) - 1i64))])))
            b2 = (b2 + b1)
            if !((100.0f64 * b1) < b2) {
                pc = 43i64
                continue
            }
            pc = 39i64
            continue
        }
        if pc == 43i64 {
            pc = 42i64
        }
        if pc == 42i64 {
            i4 = i4 + zs8
            zc7 = zc7 - 1i64
            pc = 40i64
            continue
        }
        if pc == 41i64 {
            pc = 39i64
        }
        if pc == 39i64 {
            b2 = math.sqrt[f64]((1.05f64 * b2))
            a2 = (dmin2 / ((1.0f64 + (b2 * b2))))
            gap2 = (((z[usize(((nn - 7i64) - 1i64))] + z[usize(((nn - 9i64) - 1i64))]) - (math.sqrt[f64](z[usize(((nn - 11i64) - 1i64))]) * math.sqrt[f64](z[usize(((nn - 9i64) - 1i64))]))) - a2)
            if ((gap2 > 0.0f64) && (gap2 > (b2 * a2))) {
                s = lbase.f_max(s, (a2 * ((1.0f64 - (((1.01f64 * a2) * ((b2 / gap2))) * b2)))))
            } else {
                s = lbase.f_max(s, (a2 * ((1.0f64 - (1.01f64 * b2)))))
            }
            pc = 35i64
            continue
        }
        if pc == 36i64 {
            s = (0.25f64 * dmin2)
            ttype = (-11i64)
            pc = 35i64
            continue
        }
        if pc == 35i64 {
            pc = 1i64
            continue
        }
        if pc == 34i64 {
            if !(n0in > ((n0 + 2i64))) {
                pc = 44i64
                continue
            }
            s = 0.0f64
            ttype = (-12i64)
            pc = 1i64
            continue
        }
        if pc == 44i64 {
            pc = 1i64
        }
        if pc == 1i64 {
            tau = s
            *tau_ref = tau
            *ttype_ref = ttype
            *g_ref = g
            ret
        }
    }
}

fn dlasq5(i0: i64, n0: i64, z: []f64, pp: i64, tau_ref: *f64, sigma: f64, dmin_ref: *f64, dmin1_ref: *f64, dmin2_ref: *f64, dn_ref: *f64, dnm1_ref: *f64, dnm2_ref: *f64, ieee: bool, eps: f64) {
    var tau = *tau_ref
    var dmin = *dmin_ref
    var dmin1 = *dmin1_ref
    var dmin2 = *dmin2_ref
    var dn = *dn_ref
    var dnm1 = *dnm1_ref
    var dnm2 = *dnm2_ref
    var j4: i64 = 0i64
    var j4p2: i64 = 0i64
    var d: f64 = 0.0f64
    var emin: f64 = 0.0f64
    var temp: f64 = 0.0f64
    var dthresh: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
    var zc3: i64 = 0i64
    var zs4: i64 = 0i64
    var zc5: i64 = 0i64
    var zs6: i64 = 0i64
    var zc7: i64 = 0i64
    var zs8: i64 = 0i64
    var zc9: i64 = 0i64
    var zs10: i64 = 0i64
    var zc11: i64 = 0i64
    var zs12: i64 = 0i64
    var zc13: i64 = 0i64
    var zs14: i64 = 0i64
    var zc15: i64 = 0i64
    var zs16: i64 = 0i64
    if ((((n0 - i0) - 1i64)) <= 0i64) {
        *tau_ref = tau
        *dmin_ref = dmin
        *dmin1_ref = dmin1
        *dmin2_ref = dmin2
        *dn_ref = dn
        *dnm1_ref = dnm1
        *dnm2_ref = dnm2
        ret
    }
    dthresh = (eps * ((sigma + tau)))
    if (tau < (dthresh * 0.5f64)) {
        tau = 0.0f64
    }
    if (tau != 0.0f64) {
        j4 = (((4i64 * i0) + pp) - 3i64)
        emin = z[usize(((j4 + 4i64) - 1i64))]
        d = (z[usize((j4 - 1i64))] - tau)
        dmin = d
        dmin1 = (-z[usize((j4 - 1i64))])
        if ieee {
            if (pp == 0i64) {
                j4 = (4i64 * i0)
                zs2 = 4i64
                zc1 = (((4i64 * ((n0 - 3i64))) - j4) + zs2) / zs2
                while zc1 > 0i64 {
                    z[usize(((j4 - 2i64) - 1i64))] = (d + z[usize(((j4 - 1i64) - 1i64))])
                    temp = (z[usize(((j4 + 1i64) - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])
                    d = ((d * temp) - tau)
                    dmin = lbase.f_min(dmin, d)
                    z[usize((j4 - 1i64))] = (z[usize(((j4 - 1i64) - 1i64))] * temp)
                    emin = lbase.f_min(z[usize((j4 - 1i64))], emin)
                    j4 = j4 + zs2
                    zc1 = zc1 - 1i64
                }
            } else {
                j4 = (4i64 * i0)
                zs4 = 4i64
                zc3 = (((4i64 * ((n0 - 3i64))) - j4) + zs4) / zs4
                while zc3 > 0i64 {
                    z[usize(((j4 - 3i64) - 1i64))] = (d + z[usize((j4 - 1i64))])
                    temp = (z[usize(((j4 + 2i64) - 1i64))] / z[usize(((j4 - 3i64) - 1i64))])
                    d = ((d * temp) - tau)
                    dmin = lbase.f_min(dmin, d)
                    z[usize(((j4 - 1i64) - 1i64))] = (z[usize((j4 - 1i64))] * temp)
                    emin = lbase.f_min(z[usize(((j4 - 1i64) - 1i64))], emin)
                    j4 = j4 + zs4
                    zc3 = zc3 - 1i64
                }
            }
            dnm2 = d
            dmin2 = dmin
            j4 = ((4i64 * ((n0 - 2i64))) - pp)
            j4p2 = ((j4 + (2i64 * pp)) - 1i64)
            z[usize(((j4 - 2i64) - 1i64))] = (dnm2 + z[usize((j4p2 - 1i64))])
            z[usize((j4 - 1i64))] = (z[usize(((j4p2 + 2i64) - 1i64))] * ((z[usize((j4p2 - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])))
            dnm1 = ((z[usize(((j4p2 + 2i64) - 1i64))] * ((dnm2 / z[usize(((j4 - 2i64) - 1i64))]))) - tau)
            dmin = lbase.f_min(dmin, dnm1)
            dmin1 = dmin
            j4 = (j4 + 4i64)
            j4p2 = ((j4 + (2i64 * pp)) - 1i64)
            z[usize(((j4 - 2i64) - 1i64))] = (dnm1 + z[usize((j4p2 - 1i64))])
            z[usize((j4 - 1i64))] = (z[usize(((j4p2 + 2i64) - 1i64))] * ((z[usize((j4p2 - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])))
            dn = ((z[usize(((j4p2 + 2i64) - 1i64))] * ((dnm1 / z[usize(((j4 - 2i64) - 1i64))]))) - tau)
            dmin = lbase.f_min(dmin, dn)
        } else {
            if (pp == 0i64) {
                j4 = (4i64 * i0)
                zs6 = 4i64
                zc5 = (((4i64 * ((n0 - 3i64))) - j4) + zs6) / zs6
                while zc5 > 0i64 {
                    z[usize(((j4 - 2i64) - 1i64))] = (d + z[usize(((j4 - 1i64) - 1i64))])
                    if (d < 0.0f64) {
                        *tau_ref = tau
                        *dmin_ref = dmin
                        *dmin1_ref = dmin1
                        *dmin2_ref = dmin2
                        *dn_ref = dn
                        *dnm1_ref = dnm1
                        *dnm2_ref = dnm2
                        ret
                    } else {
                        z[usize((j4 - 1i64))] = (z[usize(((j4 + 1i64) - 1i64))] * ((z[usize(((j4 - 1i64) - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])))
                        d = ((z[usize(((j4 + 1i64) - 1i64))] * ((d / z[usize(((j4 - 2i64) - 1i64))]))) - tau)
                    }
                    dmin = lbase.f_min(dmin, d)
                    emin = lbase.f_min(emin, z[usize((j4 - 1i64))])
                    j4 = j4 + zs6
                    zc5 = zc5 - 1i64
                }
            } else {
                j4 = (4i64 * i0)
                zs8 = 4i64
                zc7 = (((4i64 * ((n0 - 3i64))) - j4) + zs8) / zs8
                while zc7 > 0i64 {
                    z[usize(((j4 - 3i64) - 1i64))] = (d + z[usize((j4 - 1i64))])
                    if (d < 0.0f64) {
                        *tau_ref = tau
                        *dmin_ref = dmin
                        *dmin1_ref = dmin1
                        *dmin2_ref = dmin2
                        *dn_ref = dn
                        *dnm1_ref = dnm1
                        *dnm2_ref = dnm2
                        ret
                    } else {
                        z[usize(((j4 - 1i64) - 1i64))] = (z[usize(((j4 + 2i64) - 1i64))] * ((z[usize((j4 - 1i64))] / z[usize(((j4 - 3i64) - 1i64))])))
                        d = ((z[usize(((j4 + 2i64) - 1i64))] * ((d / z[usize(((j4 - 3i64) - 1i64))]))) - tau)
                    }
                    dmin = lbase.f_min(dmin, d)
                    emin = lbase.f_min(emin, z[usize(((j4 - 1i64) - 1i64))])
                    j4 = j4 + zs8
                    zc7 = zc7 - 1i64
                }
            }
            dnm2 = d
            dmin2 = dmin
            j4 = ((4i64 * ((n0 - 2i64))) - pp)
            j4p2 = ((j4 + (2i64 * pp)) - 1i64)
            z[usize(((j4 - 2i64) - 1i64))] = (dnm2 + z[usize((j4p2 - 1i64))])
            if (dnm2 < 0.0f64) {
                *tau_ref = tau
                *dmin_ref = dmin
                *dmin1_ref = dmin1
                *dmin2_ref = dmin2
                *dn_ref = dn
                *dnm1_ref = dnm1
                *dnm2_ref = dnm2
                ret
            } else {
                z[usize((j4 - 1i64))] = (z[usize(((j4p2 + 2i64) - 1i64))] * ((z[usize((j4p2 - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])))
                dnm1 = ((z[usize(((j4p2 + 2i64) - 1i64))] * ((dnm2 / z[usize(((j4 - 2i64) - 1i64))]))) - tau)
            }
            dmin = lbase.f_min(dmin, dnm1)
            dmin1 = dmin
            j4 = (j4 + 4i64)
            j4p2 = ((j4 + (2i64 * pp)) - 1i64)
            z[usize(((j4 - 2i64) - 1i64))] = (dnm1 + z[usize((j4p2 - 1i64))])
            if (dnm1 < 0.0f64) {
                *tau_ref = tau
                *dmin_ref = dmin
                *dmin1_ref = dmin1
                *dmin2_ref = dmin2
                *dn_ref = dn
                *dnm1_ref = dnm1
                *dnm2_ref = dnm2
                ret
            } else {
                z[usize((j4 - 1i64))] = (z[usize(((j4p2 + 2i64) - 1i64))] * ((z[usize((j4p2 - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])))
                dn = ((z[usize(((j4p2 + 2i64) - 1i64))] * ((dnm1 / z[usize(((j4 - 2i64) - 1i64))]))) - tau)
            }
            dmin = lbase.f_min(dmin, dn)
        }
    } else {
        j4 = (((4i64 * i0) + pp) - 3i64)
        emin = z[usize(((j4 + 4i64) - 1i64))]
        d = (z[usize((j4 - 1i64))] - tau)
        dmin = d
        dmin1 = (-z[usize((j4 - 1i64))])
        if ieee {
            if (pp == 0i64) {
                j4 = (4i64 * i0)
                zs10 = 4i64
                zc9 = (((4i64 * ((n0 - 3i64))) - j4) + zs10) / zs10
                while zc9 > 0i64 {
                    z[usize(((j4 - 2i64) - 1i64))] = (d + z[usize(((j4 - 1i64) - 1i64))])
                    temp = (z[usize(((j4 + 1i64) - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])
                    d = ((d * temp) - tau)
                    if (d < dthresh) {
                        d = 0.0f64
                    }
                    dmin = lbase.f_min(dmin, d)
                    z[usize((j4 - 1i64))] = (z[usize(((j4 - 1i64) - 1i64))] * temp)
                    emin = lbase.f_min(z[usize((j4 - 1i64))], emin)
                    j4 = j4 + zs10
                    zc9 = zc9 - 1i64
                }
            } else {
                j4 = (4i64 * i0)
                zs12 = 4i64
                zc11 = (((4i64 * ((n0 - 3i64))) - j4) + zs12) / zs12
                while zc11 > 0i64 {
                    z[usize(((j4 - 3i64) - 1i64))] = (d + z[usize((j4 - 1i64))])
                    temp = (z[usize(((j4 + 2i64) - 1i64))] / z[usize(((j4 - 3i64) - 1i64))])
                    d = ((d * temp) - tau)
                    if (d < dthresh) {
                        d = 0.0f64
                    }
                    dmin = lbase.f_min(dmin, d)
                    z[usize(((j4 - 1i64) - 1i64))] = (z[usize((j4 - 1i64))] * temp)
                    emin = lbase.f_min(z[usize(((j4 - 1i64) - 1i64))], emin)
                    j4 = j4 + zs12
                    zc11 = zc11 - 1i64
                }
            }
            dnm2 = d
            dmin2 = dmin
            j4 = ((4i64 * ((n0 - 2i64))) - pp)
            j4p2 = ((j4 + (2i64 * pp)) - 1i64)
            z[usize(((j4 - 2i64) - 1i64))] = (dnm2 + z[usize((j4p2 - 1i64))])
            z[usize((j4 - 1i64))] = (z[usize(((j4p2 + 2i64) - 1i64))] * ((z[usize((j4p2 - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])))
            dnm1 = ((z[usize(((j4p2 + 2i64) - 1i64))] * ((dnm2 / z[usize(((j4 - 2i64) - 1i64))]))) - tau)
            dmin = lbase.f_min(dmin, dnm1)
            dmin1 = dmin
            j4 = (j4 + 4i64)
            j4p2 = ((j4 + (2i64 * pp)) - 1i64)
            z[usize(((j4 - 2i64) - 1i64))] = (dnm1 + z[usize((j4p2 - 1i64))])
            z[usize((j4 - 1i64))] = (z[usize(((j4p2 + 2i64) - 1i64))] * ((z[usize((j4p2 - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])))
            dn = ((z[usize(((j4p2 + 2i64) - 1i64))] * ((dnm1 / z[usize(((j4 - 2i64) - 1i64))]))) - tau)
            dmin = lbase.f_min(dmin, dn)
        } else {
            if (pp == 0i64) {
                j4 = (4i64 * i0)
                zs14 = 4i64
                zc13 = (((4i64 * ((n0 - 3i64))) - j4) + zs14) / zs14
                while zc13 > 0i64 {
                    z[usize(((j4 - 2i64) - 1i64))] = (d + z[usize(((j4 - 1i64) - 1i64))])
                    if (d < 0.0f64) {
                        *tau_ref = tau
                        *dmin_ref = dmin
                        *dmin1_ref = dmin1
                        *dmin2_ref = dmin2
                        *dn_ref = dn
                        *dnm1_ref = dnm1
                        *dnm2_ref = dnm2
                        ret
                    } else {
                        z[usize((j4 - 1i64))] = (z[usize(((j4 + 1i64) - 1i64))] * ((z[usize(((j4 - 1i64) - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])))
                        d = ((z[usize(((j4 + 1i64) - 1i64))] * ((d / z[usize(((j4 - 2i64) - 1i64))]))) - tau)
                    }
                    if (d < dthresh) {
                        d = 0.0f64
                    }
                    dmin = lbase.f_min(dmin, d)
                    emin = lbase.f_min(emin, z[usize((j4 - 1i64))])
                    j4 = j4 + zs14
                    zc13 = zc13 - 1i64
                }
            } else {
                j4 = (4i64 * i0)
                zs16 = 4i64
                zc15 = (((4i64 * ((n0 - 3i64))) - j4) + zs16) / zs16
                while zc15 > 0i64 {
                    z[usize(((j4 - 3i64) - 1i64))] = (d + z[usize((j4 - 1i64))])
                    if (d < 0.0f64) {
                        *tau_ref = tau
                        *dmin_ref = dmin
                        *dmin1_ref = dmin1
                        *dmin2_ref = dmin2
                        *dn_ref = dn
                        *dnm1_ref = dnm1
                        *dnm2_ref = dnm2
                        ret
                    } else {
                        z[usize(((j4 - 1i64) - 1i64))] = (z[usize(((j4 + 2i64) - 1i64))] * ((z[usize((j4 - 1i64))] / z[usize(((j4 - 3i64) - 1i64))])))
                        d = ((z[usize(((j4 + 2i64) - 1i64))] * ((d / z[usize(((j4 - 3i64) - 1i64))]))) - tau)
                    }
                    if (d < dthresh) {
                        d = 0.0f64
                    }
                    dmin = lbase.f_min(dmin, d)
                    emin = lbase.f_min(emin, z[usize(((j4 - 1i64) - 1i64))])
                    j4 = j4 + zs16
                    zc15 = zc15 - 1i64
                }
            }
            dnm2 = d
            dmin2 = dmin
            j4 = ((4i64 * ((n0 - 2i64))) - pp)
            j4p2 = ((j4 + (2i64 * pp)) - 1i64)
            z[usize(((j4 - 2i64) - 1i64))] = (dnm2 + z[usize((j4p2 - 1i64))])
            if (dnm2 < 0.0f64) {
                *tau_ref = tau
                *dmin_ref = dmin
                *dmin1_ref = dmin1
                *dmin2_ref = dmin2
                *dn_ref = dn
                *dnm1_ref = dnm1
                *dnm2_ref = dnm2
                ret
            } else {
                z[usize((j4 - 1i64))] = (z[usize(((j4p2 + 2i64) - 1i64))] * ((z[usize((j4p2 - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])))
                dnm1 = ((z[usize(((j4p2 + 2i64) - 1i64))] * ((dnm2 / z[usize(((j4 - 2i64) - 1i64))]))) - tau)
            }
            dmin = lbase.f_min(dmin, dnm1)
            dmin1 = dmin
            j4 = (j4 + 4i64)
            j4p2 = ((j4 + (2i64 * pp)) - 1i64)
            z[usize(((j4 - 2i64) - 1i64))] = (dnm1 + z[usize((j4p2 - 1i64))])
            if (dnm1 < 0.0f64) {
                *tau_ref = tau
                *dmin_ref = dmin
                *dmin1_ref = dmin1
                *dmin2_ref = dmin2
                *dn_ref = dn
                *dnm1_ref = dnm1
                *dnm2_ref = dnm2
                ret
            } else {
                z[usize((j4 - 1i64))] = (z[usize(((j4p2 + 2i64) - 1i64))] * ((z[usize((j4p2 - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])))
                dn = ((z[usize(((j4p2 + 2i64) - 1i64))] * ((dnm1 / z[usize(((j4 - 2i64) - 1i64))]))) - tau)
            }
            dmin = lbase.f_min(dmin, dn)
        }
    }
    z[usize(((j4 + 2i64) - 1i64))] = dn
    z[usize((((4i64 * n0) - pp) - 1i64))] = emin
    *tau_ref = tau
    *dmin_ref = dmin
    *dmin1_ref = dmin1
    *dmin2_ref = dmin2
    *dn_ref = dn
    *dnm1_ref = dnm1
    *dnm2_ref = dnm2
    ret
}

fn dlasq6(i0: i64, n0: i64, z: []f64, pp: i64, dmin_ref: *f64, dmin1_ref: *f64, dmin2_ref: *f64, dn_ref: *f64, dnm1_ref: *f64, dnm2_ref: *f64) {
    var dmin = *dmin_ref
    var dmin1 = *dmin1_ref
    var dmin2 = *dmin2_ref
    var dn = *dn_ref
    var dnm1 = *dnm1_ref
    var dnm2 = *dnm2_ref
    var j4: i64 = 0i64
    var j4p2: i64 = 0i64
    var d: f64 = 0.0f64
    var emin: f64 = 0.0f64
    var safmin: f64 = 0.0f64
    var temp: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
    var zc3: i64 = 0i64
    var zs4: i64 = 0i64
    if ((((n0 - i0) - 1i64)) <= 0i64) {
        *dmin_ref = dmin
        *dmin1_ref = dmin1
        *dmin2_ref = dmin2
        *dn_ref = dn
        *dnm1_ref = dnm1
        *dnm2_ref = dnm2
        ret
    }
    safmin = 2.2250738585072014e-308f64
    j4 = (((4i64 * i0) + pp) - 3i64)
    emin = z[usize(((j4 + 4i64) - 1i64))]
    d = z[usize((j4 - 1i64))]
    dmin = d
    if (pp == 0i64) {
        j4 = (4i64 * i0)
        zs2 = 4i64
        zc1 = (((4i64 * ((n0 - 3i64))) - j4) + zs2) / zs2
        while zc1 > 0i64 {
            z[usize(((j4 - 2i64) - 1i64))] = (d + z[usize(((j4 - 1i64) - 1i64))])
            if (z[usize(((j4 - 2i64) - 1i64))] == 0.0f64) {
                z[usize((j4 - 1i64))] = 0.0f64
                d = z[usize(((j4 + 1i64) - 1i64))]
                dmin = d
                emin = 0.0f64
            } else if (((safmin * z[usize(((j4 + 1i64) - 1i64))]) < z[usize(((j4 - 2i64) - 1i64))]) && ((safmin * z[usize(((j4 - 2i64) - 1i64))]) < z[usize(((j4 + 1i64) - 1i64))])) {
                temp = (z[usize(((j4 + 1i64) - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])
                z[usize((j4 - 1i64))] = (z[usize(((j4 - 1i64) - 1i64))] * temp)
                d = (d * temp)
            } else {
                z[usize((j4 - 1i64))] = (z[usize(((j4 + 1i64) - 1i64))] * ((z[usize(((j4 - 1i64) - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])))
                d = (z[usize(((j4 + 1i64) - 1i64))] * ((d / z[usize(((j4 - 2i64) - 1i64))])))
            }
            dmin = lbase.f_min(dmin, d)
            emin = lbase.f_min(emin, z[usize((j4 - 1i64))])
            j4 = j4 + zs2
            zc1 = zc1 - 1i64
        }
    } else {
        j4 = (4i64 * i0)
        zs4 = 4i64
        zc3 = (((4i64 * ((n0 - 3i64))) - j4) + zs4) / zs4
        while zc3 > 0i64 {
            z[usize(((j4 - 3i64) - 1i64))] = (d + z[usize((j4 - 1i64))])
            if (z[usize(((j4 - 3i64) - 1i64))] == 0.0f64) {
                z[usize(((j4 - 1i64) - 1i64))] = 0.0f64
                d = z[usize(((j4 + 2i64) - 1i64))]
                dmin = d
                emin = 0.0f64
            } else if (((safmin * z[usize(((j4 + 2i64) - 1i64))]) < z[usize(((j4 - 3i64) - 1i64))]) && ((safmin * z[usize(((j4 - 3i64) - 1i64))]) < z[usize(((j4 + 2i64) - 1i64))])) {
                temp = (z[usize(((j4 + 2i64) - 1i64))] / z[usize(((j4 - 3i64) - 1i64))])
                z[usize(((j4 - 1i64) - 1i64))] = (z[usize((j4 - 1i64))] * temp)
                d = (d * temp)
            } else {
                z[usize(((j4 - 1i64) - 1i64))] = (z[usize(((j4 + 2i64) - 1i64))] * ((z[usize((j4 - 1i64))] / z[usize(((j4 - 3i64) - 1i64))])))
                d = (z[usize(((j4 + 2i64) - 1i64))] * ((d / z[usize(((j4 - 3i64) - 1i64))])))
            }
            dmin = lbase.f_min(dmin, d)
            emin = lbase.f_min(emin, z[usize(((j4 - 1i64) - 1i64))])
            j4 = j4 + zs4
            zc3 = zc3 - 1i64
        }
    }
    dnm2 = d
    dmin2 = dmin
    j4 = ((4i64 * ((n0 - 2i64))) - pp)
    j4p2 = ((j4 + (2i64 * pp)) - 1i64)
    z[usize(((j4 - 2i64) - 1i64))] = (dnm2 + z[usize((j4p2 - 1i64))])
    if (z[usize(((j4 - 2i64) - 1i64))] == 0.0f64) {
        z[usize((j4 - 1i64))] = 0.0f64
        dnm1 = z[usize(((j4p2 + 2i64) - 1i64))]
        dmin = dnm1
        emin = 0.0f64
    } else if (((safmin * z[usize(((j4p2 + 2i64) - 1i64))]) < z[usize(((j4 - 2i64) - 1i64))]) && ((safmin * z[usize(((j4 - 2i64) - 1i64))]) < z[usize(((j4p2 + 2i64) - 1i64))])) {
        temp = (z[usize(((j4p2 + 2i64) - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])
        z[usize((j4 - 1i64))] = (z[usize((j4p2 - 1i64))] * temp)
        dnm1 = (dnm2 * temp)
    } else {
        z[usize((j4 - 1i64))] = (z[usize(((j4p2 + 2i64) - 1i64))] * ((z[usize((j4p2 - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])))
        dnm1 = (z[usize(((j4p2 + 2i64) - 1i64))] * ((dnm2 / z[usize(((j4 - 2i64) - 1i64))])))
    }
    dmin = lbase.f_min(dmin, dnm1)
    dmin1 = dmin
    j4 = (j4 + 4i64)
    j4p2 = ((j4 + (2i64 * pp)) - 1i64)
    z[usize(((j4 - 2i64) - 1i64))] = (dnm1 + z[usize((j4p2 - 1i64))])
    if (z[usize(((j4 - 2i64) - 1i64))] == 0.0f64) {
        z[usize((j4 - 1i64))] = 0.0f64
        dn = z[usize(((j4p2 + 2i64) - 1i64))]
        dmin = dn
        emin = 0.0f64
    } else if (((safmin * z[usize(((j4p2 + 2i64) - 1i64))]) < z[usize(((j4 - 2i64) - 1i64))]) && ((safmin * z[usize(((j4 - 2i64) - 1i64))]) < z[usize(((j4p2 + 2i64) - 1i64))])) {
        temp = (z[usize(((j4p2 + 2i64) - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])
        z[usize((j4 - 1i64))] = (z[usize((j4p2 - 1i64))] * temp)
        dn = (dnm1 * temp)
    } else {
        z[usize((j4 - 1i64))] = (z[usize(((j4p2 + 2i64) - 1i64))] * ((z[usize((j4p2 - 1i64))] / z[usize(((j4 - 2i64) - 1i64))])))
        dn = (z[usize(((j4p2 + 2i64) - 1i64))] * ((dnm1 / z[usize(((j4 - 2i64) - 1i64))])))
    }
    dmin = lbase.f_min(dmin, dn)
    z[usize(((j4 + 2i64) - 1i64))] = dn
    z[usize((((4i64 * n0) - pp) - 1i64))] = emin
    *dmin_ref = dmin
    *dmin1_ref = dmin1
    *dmin2_ref = dmin2
    *dn_ref = dn
    *dnm1_ref = dnm1
    *dnm2_ref = dnm2
    ret
}

fn dlarnv(idist: i64, iseed: []i64, n: i64, x: []f64) {
    var i: i64 = 0i64
    var il: i64 = 0i64
    var il2: i64 = 0i64
    var iv: i64 = 0i64
    var u: [128]f64 = zero
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    iv = 1i64
    zs2 = (128i64 / 2i64)
    zc1 = ((n - iv) + zs2) / zs2
    while zc1 > 0i64 {
        il = lbase.i_min((128i64 / 2i64), ((n - iv) + 1i64))
        if (idist == 3i64) {
            il2 = (2i64 * il)
        } else {
            il2 = il
        }
        dlaruv(iseed[0usize..], il2, u[0usize..])
        if (idist == 1i64) {
            i = 1i64
            zc3 = (il - i) + 1i64
            while zc3 > 0i64 {
                x[usize((((iv + i) - 1i64) - 1i64))] = u[usize((i - 1i64))]
                i = i + 1i64
                zc3 = zc3 - 1i64
            }
        } else if (idist == 2i64) {
            i = 1i64
            zc4 = (il - i) + 1i64
            while zc4 > 0i64 {
                x[usize((((iv + i) - 1i64) - 1i64))] = ((2.0f64 * u[usize((i - 1i64))]) - 1.0f64)
                i = i + 1i64
                zc4 = zc4 - 1i64
            }
        } else if (idist == 3i64) {
            i = 1i64
            zc5 = (il - i) + 1i64
            while zc5 > 0i64 {
                x[usize((((iv + i) - 1i64) - 1i64))] = (math.sqrt[f64]((-(2.0f64 * math.log[f64](u[usize((((2i64 * i) - 1i64) - 1i64))])))) * math.cos[f64]((6.283185307179586f64 * u[usize(((2i64 * i) - 1i64))])))
                i = i + 1i64
                zc5 = zc5 - 1i64
            }
        }
        iv = iv + zs2
        zc1 = zc1 - 1i64
    }
    ret
}

fn dlaruv(iseed: []i64, n: i64, x: []f64) {
    var i: i64 = 0i64
    var i1: i64 = 0i64
    var i2: i64 = 0i64
    var i3: i64 = 0i64
    var i4: i64 = 0i64
    var it1: i64 = 0i64
    var it2: i64 = 0i64
    var it3: i64 = 0i64
    var it4: i64 = 0i64
    var j: i64 = 0i64
    var mm: [512]i64 = zero
    mm[usize((1i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 494i64
    mm[usize((1i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 322i64
    mm[usize((1i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2508i64
    mm[usize((1i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2549i64
    mm[usize((2i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2637i64
    mm[usize((2i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 789i64
    mm[usize((2i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3754i64
    mm[usize((2i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1145i64
    mm[usize((3i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 255i64
    mm[usize((3i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1440i64
    mm[usize((3i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1766i64
    mm[usize((3i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2253i64
    mm[usize((4i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2008i64
    mm[usize((4i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 752i64
    mm[usize((4i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3572i64
    mm[usize((4i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 305i64
    mm[usize((5i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1253i64
    mm[usize((5i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2859i64
    mm[usize((5i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2893i64
    mm[usize((5i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3301i64
    mm[usize((6i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3344i64
    mm[usize((6i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 123i64
    mm[usize((6i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 307i64
    mm[usize((6i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1065i64
    mm[usize((7i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 4084i64
    mm[usize((7i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1848i64
    mm[usize((7i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1297i64
    mm[usize((7i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3133i64
    mm[usize((8i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1739i64
    mm[usize((8i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 643i64
    mm[usize((8i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3966i64
    mm[usize((8i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2913i64
    mm[usize((9i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3143i64
    mm[usize((9i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2405i64
    mm[usize((9i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 758i64
    mm[usize((9i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3285i64
    mm[usize((10i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3468i64
    mm[usize((10i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2638i64
    mm[usize((10i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2598i64
    mm[usize((10i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1241i64
    mm[usize((11i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 688i64
    mm[usize((11i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2344i64
    mm[usize((11i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3406i64
    mm[usize((11i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1197i64
    mm[usize((12i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1657i64
    mm[usize((12i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 46i64
    mm[usize((12i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2922i64
    mm[usize((12i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3729i64
    mm[usize((13i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1238i64
    mm[usize((13i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3814i64
    mm[usize((13i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1038i64
    mm[usize((13i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2501i64
    mm[usize((14i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3166i64
    mm[usize((14i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 913i64
    mm[usize((14i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2934i64
    mm[usize((14i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1673i64
    mm[usize((15i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1292i64
    mm[usize((15i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3649i64
    mm[usize((15i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2091i64
    mm[usize((15i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 541i64
    mm[usize((16i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3422i64
    mm[usize((16i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 339i64
    mm[usize((16i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2451i64
    mm[usize((16i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2753i64
    mm[usize((17i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1270i64
    mm[usize((17i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3808i64
    mm[usize((17i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1580i64
    mm[usize((17i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 949i64
    mm[usize((18i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2016i64
    mm[usize((18i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 822i64
    mm[usize((18i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1958i64
    mm[usize((18i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2361i64
    mm[usize((19i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 154i64
    mm[usize((19i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2832i64
    mm[usize((19i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2055i64
    mm[usize((19i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1165i64
    mm[usize((20i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2862i64
    mm[usize((20i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3078i64
    mm[usize((20i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1507i64
    mm[usize((20i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 4081i64
    mm[usize((21i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 697i64
    mm[usize((21i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3633i64
    mm[usize((21i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1078i64
    mm[usize((21i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2725i64
    mm[usize((22i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1706i64
    mm[usize((22i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2970i64
    mm[usize((22i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3273i64
    mm[usize((22i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3305i64
    mm[usize((23i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 491i64
    mm[usize((23i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 637i64
    mm[usize((23i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 17i64
    mm[usize((23i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3069i64
    mm[usize((24i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 931i64
    mm[usize((24i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2249i64
    mm[usize((24i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 854i64
    mm[usize((24i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3617i64
    mm[usize((25i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1444i64
    mm[usize((25i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2081i64
    mm[usize((25i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2916i64
    mm[usize((25i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3733i64
    mm[usize((26i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 444i64
    mm[usize((26i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 4019i64
    mm[usize((26i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3971i64
    mm[usize((26i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 409i64
    mm[usize((27i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3577i64
    mm[usize((27i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1478i64
    mm[usize((27i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2889i64
    mm[usize((27i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2157i64
    mm[usize((28i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3944i64
    mm[usize((28i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 242i64
    mm[usize((28i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3831i64
    mm[usize((28i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1361i64
    mm[usize((29i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2184i64
    mm[usize((29i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 481i64
    mm[usize((29i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2621i64
    mm[usize((29i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3973i64
    mm[usize((30i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1661i64
    mm[usize((30i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2075i64
    mm[usize((30i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1541i64
    mm[usize((30i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1865i64
    mm[usize((31i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3482i64
    mm[usize((31i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 4058i64
    mm[usize((31i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 893i64
    mm[usize((31i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2525i64
    mm[usize((32i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 657i64
    mm[usize((32i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 622i64
    mm[usize((32i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 736i64
    mm[usize((32i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1409i64
    mm[usize((33i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3023i64
    mm[usize((33i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3376i64
    mm[usize((33i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3992i64
    mm[usize((33i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3445i64
    mm[usize((34i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3618i64
    mm[usize((34i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 812i64
    mm[usize((34i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 787i64
    mm[usize((34i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3577i64
    mm[usize((35i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1267i64
    mm[usize((35i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 234i64
    mm[usize((35i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2125i64
    mm[usize((35i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 77i64
    mm[usize((36i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1828i64
    mm[usize((36i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 641i64
    mm[usize((36i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2364i64
    mm[usize((36i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3761i64
    mm[usize((37i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 164i64
    mm[usize((37i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 4005i64
    mm[usize((37i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2460i64
    mm[usize((37i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2149i64
    mm[usize((38i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3798i64
    mm[usize((38i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1122i64
    mm[usize((38i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 257i64
    mm[usize((38i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1449i64
    mm[usize((39i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3087i64
    mm[usize((39i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3135i64
    mm[usize((39i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1574i64
    mm[usize((39i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3005i64
    mm[usize((40i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2400i64
    mm[usize((40i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2640i64
    mm[usize((40i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3912i64
    mm[usize((40i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 225i64
    mm[usize((41i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2870i64
    mm[usize((41i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2302i64
    mm[usize((41i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1216i64
    mm[usize((41i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 85i64
    mm[usize((42i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3876i64
    mm[usize((42i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 40i64
    mm[usize((42i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3248i64
    mm[usize((42i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3673i64
    mm[usize((43i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1905i64
    mm[usize((43i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1832i64
    mm[usize((43i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3401i64
    mm[usize((43i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3117i64
    mm[usize((44i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1593i64
    mm[usize((44i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2247i64
    mm[usize((44i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2124i64
    mm[usize((44i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3089i64
    mm[usize((45i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1797i64
    mm[usize((45i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2034i64
    mm[usize((45i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2762i64
    mm[usize((45i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1349i64
    mm[usize((46i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1234i64
    mm[usize((46i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2637i64
    mm[usize((46i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 149i64
    mm[usize((46i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2057i64
    mm[usize((47i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3460i64
    mm[usize((47i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1287i64
    mm[usize((47i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2245i64
    mm[usize((47i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 413i64
    mm[usize((48i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 328i64
    mm[usize((48i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1691i64
    mm[usize((48i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 166i64
    mm[usize((48i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 65i64
    mm[usize((49i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2861i64
    mm[usize((49i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 496i64
    mm[usize((49i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 466i64
    mm[usize((49i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1845i64
    mm[usize((50i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1950i64
    mm[usize((50i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1597i64
    mm[usize((50i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 4018i64
    mm[usize((50i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 697i64
    mm[usize((51i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 617i64
    mm[usize((51i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2394i64
    mm[usize((51i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1399i64
    mm[usize((51i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3085i64
    mm[usize((52i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2070i64
    mm[usize((52i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2584i64
    mm[usize((52i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 190i64
    mm[usize((52i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3441i64
    mm[usize((53i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3331i64
    mm[usize((53i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1843i64
    mm[usize((53i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2879i64
    mm[usize((53i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1573i64
    mm[usize((54i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 769i64
    mm[usize((54i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 336i64
    mm[usize((54i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 153i64
    mm[usize((54i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3689i64
    mm[usize((55i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1558i64
    mm[usize((55i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1472i64
    mm[usize((55i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2320i64
    mm[usize((55i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2941i64
    mm[usize((56i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2412i64
    mm[usize((56i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2407i64
    mm[usize((56i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 18i64
    mm[usize((56i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 929i64
    mm[usize((57i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2800i64
    mm[usize((57i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 433i64
    mm[usize((57i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 712i64
    mm[usize((57i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 533i64
    mm[usize((58i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 189i64
    mm[usize((58i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2096i64
    mm[usize((58i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2159i64
    mm[usize((58i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2841i64
    mm[usize((59i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 287i64
    mm[usize((59i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1761i64
    mm[usize((59i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2318i64
    mm[usize((59i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 4077i64
    mm[usize((60i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2045i64
    mm[usize((60i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2810i64
    mm[usize((60i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2091i64
    mm[usize((60i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 721i64
    mm[usize((61i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1227i64
    mm[usize((61i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 566i64
    mm[usize((61i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3443i64
    mm[usize((61i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2821i64
    mm[usize((62i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2838i64
    mm[usize((62i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 442i64
    mm[usize((62i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1510i64
    mm[usize((62i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2249i64
    mm[usize((63i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 209i64
    mm[usize((63i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 41i64
    mm[usize((63i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 449i64
    mm[usize((63i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2397i64
    mm[usize((64i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2770i64
    mm[usize((64i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1238i64
    mm[usize((64i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1956i64
    mm[usize((64i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2817i64
    mm[usize((65i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3654i64
    mm[usize((65i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1086i64
    mm[usize((65i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2201i64
    mm[usize((65i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 245i64
    mm[usize((66i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3993i64
    mm[usize((66i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 603i64
    mm[usize((66i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3137i64
    mm[usize((66i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1913i64
    mm[usize((67i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 192i64
    mm[usize((67i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 840i64
    mm[usize((67i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3399i64
    mm[usize((67i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1997i64
    mm[usize((68i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2253i64
    mm[usize((68i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3168i64
    mm[usize((68i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1321i64
    mm[usize((68i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3121i64
    mm[usize((69i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3491i64
    mm[usize((69i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1499i64
    mm[usize((69i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2271i64
    mm[usize((69i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 997i64
    mm[usize((70i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2889i64
    mm[usize((70i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1084i64
    mm[usize((70i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3667i64
    mm[usize((70i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1833i64
    mm[usize((71i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2857i64
    mm[usize((71i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3438i64
    mm[usize((71i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2703i64
    mm[usize((71i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2877i64
    mm[usize((72i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2094i64
    mm[usize((72i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2408i64
    mm[usize((72i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 629i64
    mm[usize((72i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1633i64
    mm[usize((73i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1818i64
    mm[usize((73i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1589i64
    mm[usize((73i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2365i64
    mm[usize((73i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 981i64
    mm[usize((74i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 688i64
    mm[usize((74i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2391i64
    mm[usize((74i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2431i64
    mm[usize((74i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2009i64
    mm[usize((75i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1407i64
    mm[usize((75i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 288i64
    mm[usize((75i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1113i64
    mm[usize((75i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 941i64
    mm[usize((76i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 634i64
    mm[usize((76i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 26i64
    mm[usize((76i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3922i64
    mm[usize((76i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2449i64
    mm[usize((77i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3231i64
    mm[usize((77i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 512i64
    mm[usize((77i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2554i64
    mm[usize((77i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 197i64
    mm[usize((78i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 815i64
    mm[usize((78i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1456i64
    mm[usize((78i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 184i64
    mm[usize((78i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2441i64
    mm[usize((79i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3524i64
    mm[usize((79i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 171i64
    mm[usize((79i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2099i64
    mm[usize((79i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 285i64
    mm[usize((80i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1914i64
    mm[usize((80i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1677i64
    mm[usize((80i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3228i64
    mm[usize((80i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1473i64
    mm[usize((81i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 516i64
    mm[usize((81i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2657i64
    mm[usize((81i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 4012i64
    mm[usize((81i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2741i64
    mm[usize((82i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 164i64
    mm[usize((82i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2270i64
    mm[usize((82i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1921i64
    mm[usize((82i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3129i64
    mm[usize((83i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 303i64
    mm[usize((83i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2587i64
    mm[usize((83i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3452i64
    mm[usize((83i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 909i64
    mm[usize((84i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2144i64
    mm[usize((84i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2961i64
    mm[usize((84i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3901i64
    mm[usize((84i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2801i64
    mm[usize((85i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3480i64
    mm[usize((85i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1970i64
    mm[usize((85i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 572i64
    mm[usize((85i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 421i64
    mm[usize((86i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 119i64
    mm[usize((86i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1817i64
    mm[usize((86i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3309i64
    mm[usize((86i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 4073i64
    mm[usize((87i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3357i64
    mm[usize((87i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 676i64
    mm[usize((87i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3171i64
    mm[usize((87i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2813i64
    mm[usize((88i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 837i64
    mm[usize((88i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1410i64
    mm[usize((88i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 817i64
    mm[usize((88i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2337i64
    mm[usize((89i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2826i64
    mm[usize((89i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3723i64
    mm[usize((89i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3039i64
    mm[usize((89i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1429i64
    mm[usize((90i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2332i64
    mm[usize((90i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2803i64
    mm[usize((90i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1696i64
    mm[usize((90i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1177i64
    mm[usize((91i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2089i64
    mm[usize((91i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3185i64
    mm[usize((91i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1256i64
    mm[usize((91i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1901i64
    mm[usize((92i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3780i64
    mm[usize((92i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 184i64
    mm[usize((92i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3715i64
    mm[usize((92i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 81i64
    mm[usize((93i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1700i64
    mm[usize((93i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 663i64
    mm[usize((93i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2077i64
    mm[usize((93i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1669i64
    mm[usize((94i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3712i64
    mm[usize((94i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 499i64
    mm[usize((94i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3019i64
    mm[usize((94i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2633i64
    mm[usize((95i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 150i64
    mm[usize((95i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3784i64
    mm[usize((95i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1497i64
    mm[usize((95i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2269i64
    mm[usize((96i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2000i64
    mm[usize((96i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1631i64
    mm[usize((96i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1101i64
    mm[usize((96i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 129i64
    mm[usize((97i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3375i64
    mm[usize((97i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1925i64
    mm[usize((97i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 717i64
    mm[usize((97i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1141i64
    mm[usize((98i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1621i64
    mm[usize((98i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3912i64
    mm[usize((98i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 51i64
    mm[usize((98i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 249i64
    mm[usize((99i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3090i64
    mm[usize((99i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1398i64
    mm[usize((99i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 981i64
    mm[usize((99i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3917i64
    mm[usize((100i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3765i64
    mm[usize((100i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1349i64
    mm[usize((100i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1978i64
    mm[usize((100i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2481i64
    mm[usize((101i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1149i64
    mm[usize((101i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1441i64
    mm[usize((101i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1813i64
    mm[usize((101i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3941i64
    mm[usize((102i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3146i64
    mm[usize((102i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2224i64
    mm[usize((102i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3881i64
    mm[usize((102i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2217i64
    mm[usize((103i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 33i64
    mm[usize((103i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2411i64
    mm[usize((103i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 76i64
    mm[usize((103i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2749i64
    mm[usize((104i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3082i64
    mm[usize((104i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1907i64
    mm[usize((104i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3846i64
    mm[usize((104i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3041i64
    mm[usize((105i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2741i64
    mm[usize((105i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3192i64
    mm[usize((105i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3694i64
    mm[usize((105i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1877i64
    mm[usize((106i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 359i64
    mm[usize((106i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2786i64
    mm[usize((106i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1682i64
    mm[usize((106i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 345i64
    mm[usize((107i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3316i64
    mm[usize((107i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 382i64
    mm[usize((107i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 124i64
    mm[usize((107i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2861i64
    mm[usize((108i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1749i64
    mm[usize((108i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 37i64
    mm[usize((108i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1660i64
    mm[usize((108i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1809i64
    mm[usize((109i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 185i64
    mm[usize((109i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 759i64
    mm[usize((109i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3997i64
    mm[usize((109i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3141i64
    mm[usize((110i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2784i64
    mm[usize((110i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2948i64
    mm[usize((110i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 479i64
    mm[usize((110i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2825i64
    mm[usize((111i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2202i64
    mm[usize((111i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1862i64
    mm[usize((111i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1141i64
    mm[usize((111i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 157i64
    mm[usize((112i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2199i64
    mm[usize((112i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3802i64
    mm[usize((112i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 886i64
    mm[usize((112i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2881i64
    mm[usize((113i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1364i64
    mm[usize((113i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2423i64
    mm[usize((113i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3514i64
    mm[usize((113i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3637i64
    mm[usize((114i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1244i64
    mm[usize((114i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2051i64
    mm[usize((114i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1301i64
    mm[usize((114i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1465i64
    mm[usize((115i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2020i64
    mm[usize((115i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2295i64
    mm[usize((115i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3604i64
    mm[usize((115i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2829i64
    mm[usize((116i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3160i64
    mm[usize((116i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1332i64
    mm[usize((116i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1888i64
    mm[usize((116i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2161i64
    mm[usize((117i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2785i64
    mm[usize((117i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1832i64
    mm[usize((117i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1836i64
    mm[usize((117i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3365i64
    mm[usize((118i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2772i64
    mm[usize((118i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2405i64
    mm[usize((118i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1990i64
    mm[usize((118i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 361i64
    mm[usize((119i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1217i64
    mm[usize((119i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3638i64
    mm[usize((119i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2058i64
    mm[usize((119i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2685i64
    mm[usize((120i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1822i64
    mm[usize((120i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3661i64
    mm[usize((120i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 692i64
    mm[usize((120i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3745i64
    mm[usize((121i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1245i64
    mm[usize((121i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 327i64
    mm[usize((121i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 1194i64
    mm[usize((121i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2325i64
    mm[usize((122i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2252i64
    mm[usize((122i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3660i64
    mm[usize((122i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 20i64
    mm[usize((122i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3609i64
    mm[usize((123i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 3904i64
    mm[usize((123i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 716i64
    mm[usize((123i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3285i64
    mm[usize((123i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3821i64
    mm[usize((124i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2774i64
    mm[usize((124i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1842i64
    mm[usize((124i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2046i64
    mm[usize((124i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3537i64
    mm[usize((125i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 997i64
    mm[usize((125i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 3987i64
    mm[usize((125i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 2107i64
    mm[usize((125i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 517i64
    mm[usize((126i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 2573i64
    mm[usize((126i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1368i64
    mm[usize((126i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3508i64
    mm[usize((126i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 3017i64
    mm[usize((127i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 1148i64
    mm[usize((127i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 1848i64
    mm[usize((127i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3525i64
    mm[usize((127i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 2141i64
    mm[usize((128i64 - 1i64) + (1i64 - 1i64) * 128i64)] = 545i64
    mm[usize((128i64 - 1i64) + (2i64 - 1i64) * 128i64)] = 2366i64
    mm[usize((128i64 - 1i64) + (3i64 - 1i64) * 128i64)] = 3801i64
    mm[usize((128i64 - 1i64) + (4i64 - 1i64) * 128i64)] = 1537i64
    var zc1: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            if (n < 1i64) {
                ret
            }
            i1 = iseed[usize((1i64 - 1i64))]
            i2 = iseed[usize((2i64 - 1i64))]
            i3 = iseed[usize((3i64 - 1i64))]
            i4 = iseed[usize((4i64 - 1i64))]
            i = 1i64
            zc1 = (lbase.i_min(n, 128i64) - i) + 1i64
            pc = 1i64
        }
        if pc == 1i64 {
            if zc1 <= 0i64 {
                pc = 2i64
                continue
            }
            pc = 3i64
        }
        if pc == 3i64 {
            it4 = (i4 * mm[usize((i - 1i64) + (4i64 - 1i64) * 128i64)])
            it3 = (it4 / 4096i64)
            it4 = (it4 - (4096i64 * it3))
            it3 = ((it3 + (i3 * mm[usize((i - 1i64) + (4i64 - 1i64) * 128i64)])) + (i4 * mm[usize((i - 1i64) + (3i64 - 1i64) * 128i64)]))
            it2 = (it3 / 4096i64)
            it3 = (it3 - (4096i64 * it2))
            it2 = (((it2 + (i2 * mm[usize((i - 1i64) + (4i64 - 1i64) * 128i64)])) + (i3 * mm[usize((i - 1i64) + (3i64 - 1i64) * 128i64)])) + (i4 * mm[usize((i - 1i64) + (2i64 - 1i64) * 128i64)]))
            it1 = (it2 / 4096i64)
            it2 = (it2 - (4096i64 * it1))
            it1 = ((((it1 + (i1 * mm[usize((i - 1i64) + (4i64 - 1i64) * 128i64)])) + (i2 * mm[usize((i - 1i64) + (3i64 - 1i64) * 128i64)])) + (i3 * mm[usize((i - 1i64) + (2i64 - 1i64) * 128i64)])) + (i4 * mm[usize((i - 1i64) + (1i64 - 1i64) * 128i64)]))
            it1 = (it1 % 4096i64)
            x[usize((i - 1i64))] = (0.000244140625f64 * ((f64(it1) + (0.000244140625f64 * ((f64(it2) + (0.000244140625f64 * ((f64(it3) + (0.000244140625f64 * f64(it4)))))))))))
            if !(x[usize((i - 1i64))] == 1.0f64) {
                pc = 5i64
                continue
            }
            i1 = (i1 + 2i64)
            i2 = (i2 + 2i64)
            i3 = (i3 + 2i64)
            i4 = (i4 + 2i64)
            pc = 3i64
            continue
        }
        if pc == 5i64 {
            pc = 4i64
        }
        if pc == 4i64 {
            i = i + 1i64
            zc1 = zc1 - 1i64
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            iseed[usize((1i64 - 1i64))] = it1
            iseed[usize((2i64 - 1i64))] = it2
            iseed[usize((3i64 - 1i64))] = it3
            iseed[usize((4i64 - 1i64))] = it4
            ret
        }
    }
}

fn dlarrv(n: i64, vl: f64, vu: f64, d: []f64, l: []f64, pivmin: f64, isplit: []i64, m: i64, dol: i64, dou: i64, minrgp: f64, rtol1_ref: *f64, rtol2_ref: *f64, w: []f64, werr: []f64, wgap: []f64, iblock: []i64, indexw: []i64, gers: []f64, z: []f64, ldz: i64, isuppz: []i64, work: []f64, iwork: []i64, info_ref: *i64) {
    var rtol1 = *rtol1_ref
    var rtol2 = *rtol2_ref
    var info = *info_ref
    var eskip: bool = false
    var needbs: bool = false
    var stp2ii: bool = false
    var tryrqc: bool = false
    var usedbs: bool = false
    var usedrq: bool = false
    var done: i64 = 0i64
    var i: i64 = 0i64
    var ibegin: i64 = 0i64
    var idone: i64 = 0i64
    var iend: i64 = 0i64
    var ii: i64 = 0i64
    var iindc1: i64 = 0i64
    var iindc2: i64 = 0i64
    var iindr: i64 = 0i64
    var iindwk: i64 = 0i64
    var iinfo: i64 = 0i64
    var im: i64 = 0i64
    var in_: i64 = 0i64
    var indeig: i64 = 0i64
    var indld: i64 = 0i64
    var indlld: i64 = 0i64
    var indwrk: i64 = 0i64
    var isupmn: i64 = 0i64
    var isupmx: i64 = 0i64
    var iter: i64 = 0i64
    var itmp1: i64 = 0i64
    var j: i64 = 0i64
    var jblk: i64 = 0i64
    var k: i64 = 0i64
    var miniwsize: i64 = 0i64
    var minwsize: i64 = 0i64
    var nclus: i64 = 0i64
    var ndepth: i64 = 0i64
    var negcnt: i64 = 0i64
    var newcls: i64 = 0i64
    var newfst: i64 = 0i64
    var newftt: i64 = 0i64
    var newlst: i64 = 0i64
    var newsiz: i64 = 0i64
    var offset: i64 = 0i64
    var oldcls: i64 = 0i64
    var oldfst: i64 = 0i64
    var oldien: i64 = 0i64
    var oldlst: i64 = 0i64
    var oldncl: i64 = 0i64
    var p: i64 = 0i64
    var parity: i64 = 0i64
    var q: i64 = 0i64
    var wbegin: i64 = 0i64
    var wend: i64 = 0i64
    var windex: i64 = 0i64
    var windmn: i64 = 0i64
    var windpl: i64 = 0i64
    var zfrom: i64 = 0i64
    var zto: i64 = 0i64
    var zusedl: i64 = 0i64
    var zusedu: i64 = 0i64
    var zusedw: i64 = 0i64
    var bstres: f64 = 0.0f64
    var bstw: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var fudge: f64 = 0.0f64
    var gap: f64 = 0.0f64
    var gaptol: f64 = 0.0f64
    var gl: f64 = 0.0f64
    var gu: f64 = 0.0f64
    var lambda: f64 = 0.0f64
    var left: f64 = 0.0f64
    var lgap: f64 = 0.0f64
    var mingma: f64 = 0.0f64
    var nrminv: f64 = 0.0f64
    var resid: f64 = 0.0f64
    var rgap: f64 = 0.0f64
    var right: f64 = 0.0f64
    var rqcorr: f64 = 0.0f64
    var rqtol: f64 = 0.0f64
    var savgap: f64 = 0.0f64
    var sgndef: f64 = 0.0f64
    var sigma: f64 = 0.0f64
    var spdiam: f64 = 0.0f64
    var ssigma: f64 = 0.0f64
    var tau: f64 = 0.0f64
    var tmp: f64 = 0.0f64
    var tol: f64 = 0.0f64
    var ztz: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    var zc6: i64 = 0i64
    var zc7: i64 = 0i64
    var zc8: i64 = 0i64
    var zc9: i64 = 0i64
    var zc10: i64 = 0i64
    var zc11: i64 = 0i64
    var zc12: i64 = 0i64
    var zc13: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            if (((n <= 0i64)) || ((m <= 0i64))) {
                *rtol1_ref = rtol1
                *rtol2_ref = rtol2
                *info_ref = info
                ret
            }
            indld = (n + 1i64)
            indlld = ((2i64 * n) + 1i64)
            indwrk = ((3i64 * n) + 1i64)
            minwsize = (12i64 * n)
            i = 1i64
            zc1 = (minwsize - i) + 1i64
            while zc1 > 0i64 {
                work[usize((i - 1i64))] = 0.0f64
                i = i + 1i64
                zc1 = zc1 - 1i64
            }
            iindr = 0i64
            iindc1 = n
            iindc2 = (2i64 * n)
            iindwk = ((3i64 * n) + 1i64)
            miniwsize = (7i64 * n)
            i = 1i64
            zc2 = (miniwsize - i) + 1i64
            while zc2 > 0i64 {
                iwork[usize((i - 1i64))] = 0i64
                i = i + 1i64
                zc2 = zc2 - 1i64
            }
            zusedl = 1i64
            if (dol > 1i64) {
                zusedl = (dol - 1i64)
            }
            zusedu = m
            if (dou < m) {
                zusedu = (dou + 1i64)
            }
            zusedw = ((zusedu - zusedl) + 1i64)
            lbase.dlaset("Full", n, zusedw, 0.0f64, 0.0f64, lbase.sl[f64](z[0usize..], usize((1i64 - 1i64) + (zusedl - 1i64) * ldz)), ldz)
            eps = 2.220446049250313e-16f64
            rqtol = (2.0f64 * eps)
            tryrqc = true
            if (((dol == 1i64)) && ((dou == m))) {
            } else {
                rtol1 = (4.0f64 * eps)
                rtol2 = (4.0f64 * eps)
            }
            done = 0i64
            ibegin = 1i64
            wbegin = 1i64
            jblk = 1i64
            zc3 = (iblock[usize((m - 1i64))] - jblk) + 1i64
            pc = 1i64
        }
        if pc == 1i64 {
            if zc3 <= 0i64 {
                pc = 2i64
                continue
            }
            iend = isplit[usize((jblk - 1i64))]
            sigma = l[usize((iend - 1i64))]
            wend = (wbegin - 1i64)
            pc = 3i64
        }
        if pc == 3i64 {
            if !(wend < m) {
                pc = 5i64
                continue
            }
            if !(iblock[usize(((wend + 1i64) - 1i64))] == jblk) {
                pc = 7i64
                continue
            }
            wend = (wend + 1i64)
            pc = 3i64
            continue
        }
        if pc == 7i64 {
            pc = 6i64
        }
        if pc == 6i64 {
            pc = 4i64
            continue
        }
        if pc == 5i64 {
            pc = 4i64
        }
        if pc == 4i64 {
            if !(wend < wbegin) {
                pc = 9i64
                continue
            }
            ibegin = (iend + 1i64)
            pc = 10i64
            continue
        }
        if pc == 9i64 {
            if !(((wend < dol)) || ((wbegin > dou))) {
                pc = 11i64
                continue
            }
            ibegin = (iend + 1i64)
            wbegin = (wend + 1i64)
            pc = 10i64
            continue
        }
        if pc == 11i64 {
            pc = 8i64
        }
        if pc == 8i64 {
            gl = gers[usize((((2i64 * ibegin) - 1i64) - 1i64))]
            gu = gers[usize(((2i64 * ibegin) - 1i64))]
            i = (ibegin + 1i64)
            zc4 = (iend - i) + 1i64
            while zc4 > 0i64 {
                gl = lbase.f_min(gers[usize((((2i64 * i) - 1i64) - 1i64))], gl)
                gu = lbase.f_max(gers[usize(((2i64 * i) - 1i64))], gu)
                i = i + 1i64
                zc4 = zc4 - 1i64
            }
            spdiam = (gu - gl)
            oldien = (ibegin - 1i64)
            in_ = ((iend - ibegin) + 1i64)
            im = ((wend - wbegin) + 1i64)
            if !(ibegin == iend) {
                pc = 13i64
                continue
            }
            done = (done + 1i64)
            z[usize((ibegin - 1i64) + (wbegin - 1i64) * ldz)] = 1.0f64
            isuppz[usize((((2i64 * wbegin) - 1i64) - 1i64))] = ibegin
            isuppz[usize(((2i64 * wbegin) - 1i64))] = ibegin
            w[usize((wbegin - 1i64))] = (w[usize((wbegin - 1i64))] + sigma)
            work[usize((wbegin - 1i64))] = w[usize((wbegin - 1i64))]
            ibegin = (iend + 1i64)
            wbegin = (wbegin + 1i64)
            pc = 10i64
            continue
        }
        if pc == 13i64 {
            pc = 12i64
        }
        if pc == 12i64 {
            lbase.dcopy(im, lbase.sl[f64](w[0usize..], usize((wbegin - 1i64))), 1i64, lbase.sl[f64](work[0usize..], usize((wbegin - 1i64))), 1i64)
            i = 1i64
            zc5 = (im - i) + 1i64
            while zc5 > 0i64 {
                w[usize((((wbegin + i) - 1i64) - 1i64))] = (w[usize((((wbegin + i) - 1i64) - 1i64))] + sigma)
                i = i + 1i64
                zc5 = zc5 - 1i64
            }
            ndepth = 0i64
            parity = 1i64
            nclus = 1i64
            iwork[usize(((iindc1 + 1i64) - 1i64))] = 1i64
            iwork[usize(((iindc1 + 2i64) - 1i64))] = im
            idone = 0i64
            pc = 14i64
        }
        if pc == 14i64 {
            if !(idone < im) {
                pc = 16i64
                continue
            }
            if (ndepth > m) {
                info = (-2i64)
                *rtol1_ref = rtol1
                *rtol2_ref = rtol2
                *info_ref = info
                ret
            }
            oldncl = nclus
            nclus = 0i64
            parity = (1i64 - parity)
            if (parity == 0i64) {
                oldcls = iindc1
                newcls = iindc2
            } else {
                oldcls = iindc2
                newcls = iindc1
            }
            i = 1i64
            zc6 = (oldncl - i) + 1i64
            pc = 17i64
        }
        if pc == 17i64 {
            if zc6 <= 0i64 {
                pc = 18i64
                continue
            }
            j = (oldcls + (2i64 * i))
            oldfst = iwork[usize(((j - 1i64) - 1i64))]
            oldlst = iwork[usize((j - 1i64))]
            if (ndepth > 0i64) {
                if (((dol == 1i64)) && ((dou == m))) {
                    j = ((wbegin + oldfst) - 1i64)
                } else {
                    if (((wbegin + oldfst) - 1i64) < dol) {
                        j = (dol - 1i64)
                    } else if (((wbegin + oldfst) - 1i64) > dou) {
                        j = dou
                    } else {
                        j = ((wbegin + oldfst) - 1i64)
                    }
                }
                lbase.dcopy(in_, lbase.sl[f64](z[0usize..], usize((ibegin - 1i64) + (j - 1i64) * ldz)), 1i64, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), 1i64)
                lbase.dcopy((in_ - 1i64), lbase.sl[f64](z[0usize..], usize((ibegin - 1i64) + ((j + 1i64) - 1i64) * ldz)), 1i64, lbase.sl[f64](l[0usize..], usize((ibegin - 1i64))), 1i64)
                sigma = z[usize((iend - 1i64) + ((j + 1i64) - 1i64) * ldz)]
                lbase.dlaset("Full", in_, 2i64, 0.0f64, 0.0f64, lbase.sl[f64](z[0usize..], usize((ibegin - 1i64) + (j - 1i64) * ldz)), ldz)
            }
            j = ibegin
            zc7 = ((iend - 1i64) - j) + 1i64
            while zc7 > 0i64 {
                tmp = (d[usize((j - 1i64))] * l[usize((j - 1i64))])
                work[usize((((indld - 1i64) + j) - 1i64))] = tmp
                work[usize((((indlld - 1i64) + j) - 1i64))] = (tmp * l[usize((j - 1i64))])
                j = j + 1i64
                zc7 = zc7 - 1i64
            }
            if (ndepth > 0i64) {
                p = indexw[usize((((wbegin - 1i64) + oldfst) - 1i64))]
                q = indexw[usize((((wbegin - 1i64) + oldlst) - 1i64))]
                offset = (indexw[usize((wbegin - 1i64))] - 1i64)
                dlarrb(in_, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](work[0usize..], usize((((indlld + ibegin) - 1i64) - 1i64))), p, q, rtol1, rtol2, offset, lbase.sl[f64](work[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](wgap[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](werr[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](work[0usize..], usize((indwrk - 1i64))), lbase.sl[i64](iwork[0usize..], usize((iindwk - 1i64))), pivmin, spdiam, in_, &iinfo)
                if (iinfo != 0i64) {
                    info = (-1i64)
                    *rtol1_ref = rtol1
                    *rtol2_ref = rtol2
                    *info_ref = info
                    ret
                }
                if (oldfst > 1i64) {
                    wgap[usize((((wbegin + oldfst) - 2i64) - 1i64))] = lbase.f_max(wgap[usize((((wbegin + oldfst) - 2i64) - 1i64))], (((w[usize((((wbegin + oldfst) - 1i64) - 1i64))] - werr[usize((((wbegin + oldfst) - 1i64) - 1i64))]) - w[usize((((wbegin + oldfst) - 2i64) - 1i64))]) - werr[usize((((wbegin + oldfst) - 2i64) - 1i64))]))
                }
                if (((wbegin + oldlst) - 1i64) < wend) {
                    wgap[usize((((wbegin + oldlst) - 1i64) - 1i64))] = lbase.f_max(wgap[usize((((wbegin + oldlst) - 1i64) - 1i64))], (((w[usize(((wbegin + oldlst) - 1i64))] - werr[usize(((wbegin + oldlst) - 1i64))]) - w[usize((((wbegin + oldlst) - 1i64) - 1i64))]) - werr[usize((((wbegin + oldlst) - 1i64) - 1i64))]))
                }
                j = oldfst
                zc8 = (oldlst - j) + 1i64
                while zc8 > 0i64 {
                    w[usize((((wbegin + j) - 1i64) - 1i64))] = (work[usize((((wbegin + j) - 1i64) - 1i64))] + sigma)
                    j = j + 1i64
                    zc8 = zc8 - 1i64
                }
            }
            newfst = oldfst
            j = oldfst
            zc9 = (oldlst - j) + 1i64
            pc = 19i64
        }
        if pc == 19i64 {
            if zc9 <= 0i64 {
                pc = 20i64
                continue
            }
            if !(j == oldlst) {
                pc = 22i64
                continue
            }
            newlst = j
            pc = 21i64
            continue
        }
        if pc == 22i64 {
            if !(wgap[usize((((wbegin + j) - 1i64) - 1i64))] >= (minrgp * math.abs[f64](work[usize((((wbegin + j) - 1i64) - 1i64))]))) {
                pc = 23i64
                continue
            }
            newlst = j
            pc = 21i64
            continue
        }
        if pc == 23i64 {
            pc = 24i64
            continue
        }
        if pc == 21i64 {
            newsiz = ((newlst - newfst) + 1i64)
            if (((dol == 1i64)) && ((dou == m))) {
                newftt = ((wbegin + newfst) - 1i64)
            } else {
                if (((wbegin + newfst) - 1i64) < dol) {
                    newftt = (dol - 1i64)
                } else if (((wbegin + newfst) - 1i64) > dou) {
                    newftt = dou
                } else {
                    newftt = ((wbegin + newfst) - 1i64)
                }
            }
            if !(newsiz > 1i64) {
                pc = 26i64
                continue
            }
            if (newfst == 1i64) {
                lgap = lbase.f_max(0.0f64, ((w[usize((wbegin - 1i64))] - werr[usize((wbegin - 1i64))]) - vl))
            } else {
                lgap = wgap[usize((((wbegin + newfst) - 2i64) - 1i64))]
            }
            rgap = wgap[usize((((wbegin + newlst) - 1i64) - 1i64))]
            k = 1i64
            zc10 = (2i64 - k) + 1i64
            while zc10 > 0i64 {
                if (k == 1i64) {
                    p = indexw[usize((((wbegin - 1i64) + newfst) - 1i64))]
                } else {
                    p = indexw[usize((((wbegin - 1i64) + newlst) - 1i64))]
                }
                offset = (indexw[usize((wbegin - 1i64))] - 1i64)
                dlarrb(in_, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](work[0usize..], usize((((indlld + ibegin) - 1i64) - 1i64))), p, p, rqtol, rqtol, offset, lbase.sl[f64](work[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](wgap[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](werr[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](work[0usize..], usize((indwrk - 1i64))), lbase.sl[i64](iwork[0usize..], usize((iindwk - 1i64))), pivmin, spdiam, in_, &iinfo)
                k = k + 1i64
                zc10 = zc10 - 1i64
            }
            if !(((((wbegin + newlst) - 1i64) < dol)) || ((((wbegin + newfst) - 1i64) > dou))) {
                pc = 28i64
                continue
            }
            idone = (((idone + newlst) - newfst) + 1i64)
            pc = 29i64
            continue
        }
        if pc == 28i64 {
            pc = 27i64
        }
        if pc == 27i64 {
            dlarrf(in_, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](l[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](work[0usize..], usize((((indld + ibegin) - 1i64) - 1i64))), newfst, newlst, lbase.sl[f64](work[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](wgap[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](werr[0usize..], usize((wbegin - 1i64))), spdiam, lgap, rgap, pivmin, &tau, lbase.sl[f64](z[0usize..], usize((ibegin - 1i64) + (newftt - 1i64) * ldz)), lbase.sl[f64](z[0usize..], usize((ibegin - 1i64) + ((newftt + 1i64) - 1i64) * ldz)), lbase.sl[f64](work[0usize..], usize((indwrk - 1i64))), &iinfo)
            if (iinfo == 0i64) {
                ssigma = (sigma + tau)
                z[usize((iend - 1i64) + ((newftt + 1i64) - 1i64) * ldz)] = ssigma
                k = newfst
                zc11 = (newlst - k) + 1i64
                while zc11 > 0i64 {
                    fudge = ((3.0f64 * eps) * math.abs[f64](work[usize((((wbegin + k) - 1i64) - 1i64))]))
                    work[usize((((wbegin + k) - 1i64) - 1i64))] = (work[usize((((wbegin + k) - 1i64) - 1i64))] - tau)
                    fudge = (fudge + ((4.0f64 * eps) * math.abs[f64](work[usize((((wbegin + k) - 1i64) - 1i64))])))
                    werr[usize((((wbegin + k) - 1i64) - 1i64))] = (werr[usize((((wbegin + k) - 1i64) - 1i64))] + fudge)
                    k = k + 1i64
                    zc11 = zc11 - 1i64
                }
                nclus = (nclus + 1i64)
                k = (newcls + (2i64 * nclus))
                iwork[usize(((k - 1i64) - 1i64))] = newfst
                iwork[usize((k - 1i64))] = newlst
            } else {
                info = (-2i64)
                *rtol1_ref = rtol1
                *rtol2_ref = rtol2
                *info_ref = info
                ret
            }
            pc = 25i64
            continue
        }
        if pc == 26i64 {
            iter = 0i64
            tol = ((4.0f64 * math.log[f64](f64(in_))) * eps)
            k = newfst
            windex = ((wbegin + k) - 1i64)
            windmn = lbase.i_max((windex - 1i64), 1i64)
            windpl = lbase.i_min((windex + 1i64), m)
            lambda = work[usize((windex - 1i64))]
            done = (done + 1i64)
            if !(((windex < dol)) || ((windex > dou))) {
                pc = 31i64
                continue
            }
            eskip = true
            pc = 32i64
            continue
        }
        if pc == 31i64 {
            eskip = false
            pc = 30i64
            continue
        }
        if pc == 30i64 {
            left = (work[usize((windex - 1i64))] - werr[usize((windex - 1i64))])
            right = (work[usize((windex - 1i64))] + werr[usize((windex - 1i64))])
            indeig = indexw[usize((windex - 1i64))]
            if (k == 1i64) {
                lgap = (eps * lbase.f_max(math.abs[f64](left), math.abs[f64](right)))
            } else {
                lgap = wgap[usize((windmn - 1i64))]
            }
            if (k == im) {
                rgap = (eps * lbase.f_max(math.abs[f64](left), math.abs[f64](right)))
            } else {
                rgap = wgap[usize((windex - 1i64))]
            }
            gap = lbase.f_min(lgap, rgap)
            if (((k == 1i64)) || ((k == im))) {
                gaptol = 0.0f64
            } else {
                gaptol = (gap * eps)
            }
            isupmn = in_
            isupmx = 1i64
            savgap = wgap[usize((windex - 1i64))]
            wgap[usize((windex - 1i64))] = gap
            usedbs = false
            usedrq = false
            needbs = (!tryrqc)
            pc = 33i64
        }
        if pc == 33i64 {
            if needbs {
                usedbs = true
                itmp1 = iwork[usize(((iindr + windex) - 1i64))]
                offset = (indexw[usize((wbegin - 1i64))] - 1i64)
                dlarrb(in_, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](work[0usize..], usize((((indlld + ibegin) - 1i64) - 1i64))), indeig, indeig, 0.0f64, (2.0f64 * eps), offset, lbase.sl[f64](work[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](wgap[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](werr[0usize..], usize((wbegin - 1i64))), lbase.sl[f64](work[0usize..], usize((indwrk - 1i64))), lbase.sl[i64](iwork[0usize..], usize((iindwk - 1i64))), pivmin, spdiam, itmp1, &iinfo)
                if (iinfo != 0i64) {
                    info = (-3i64)
                    *rtol1_ref = rtol1
                    *rtol2_ref = rtol2
                    *info_ref = info
                    ret
                }
                lambda = work[usize((windex - 1i64))]
                iwork[usize(((iindr + windex) - 1i64))] = 0i64
            }
            dlar1v(in_, 1i64, in_, lambda, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](l[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](work[0usize..], usize((((indld + ibegin) - 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize((((indlld + ibegin) - 1i64) - 1i64))), pivmin, gaptol, lbase.sl[f64](z[0usize..], usize((ibegin - 1i64) + (windex - 1i64) * ldz)), (!usedbs), &negcnt, &ztz, &mingma, &iwork[usize(((iindr + windex) - 1i64))], lbase.sl[i64](isuppz[0usize..], usize((((2i64 * windex) - 1i64) - 1i64))), &nrminv, &resid, &rqcorr, lbase.sl[f64](work[0usize..], usize((indwrk - 1i64))))
            if (iter == 0i64) {
                bstres = resid
                bstw = lambda
            } else if (resid < bstres) {
                bstres = resid
                bstw = lambda
            }
            isupmn = lbase.i_min(isupmn, isuppz[usize((((2i64 * windex) - 1i64) - 1i64))])
            isupmx = lbase.i_max(isupmx, isuppz[usize(((2i64 * windex) - 1i64))])
            iter = (iter + 1i64)
            if !(((resid > (tol * gap)) && (math.abs[f64](rqcorr) > (rqtol * math.abs[f64](lambda)))) && (!usedbs)) {
                pc = 35i64
                continue
            }
            if (indeig <= negcnt) {
                sgndef = (-1.0f64)
            } else {
                sgndef = 1.0f64
            }
            if (((((rqcorr * sgndef) >= 0.0f64)) && (((lambda + rqcorr) <= right))) && (((lambda + rqcorr) >= left))) {
                usedrq = true
                if (sgndef == 1.0f64) {
                    left = lambda
                } else {
                    right = lambda
                }
                work[usize((windex - 1i64))] = (0.5f64 * ((right + left)))
                lambda = (lambda + rqcorr)
                werr[usize((windex - 1i64))] = (0.5f64 * ((right - left)))
            } else {
                needbs = true
            }
            if !((right - left) < (rqtol * math.abs[f64](lambda))) {
                pc = 37i64
                continue
            }
            usedbs = true
            pc = 33i64
            continue
        }
        if pc == 37i64 {
            if !(iter < 10i64) {
                pc = 38i64
                continue
            }
            pc = 33i64
            continue
        }
        if pc == 38i64 {
            if !(iter == 10i64) {
                pc = 39i64
                continue
            }
            needbs = true
            pc = 33i64
            continue
        }
        if pc == 39i64 {
            info = 5i64
            *rtol1_ref = rtol1
            *rtol2_ref = rtol2
            *info_ref = info
            ret
        }
        if pc == 36i64 {
            pc = 34i64
            continue
        }
        if pc == 35i64 {
            stp2ii = false
            if ((usedrq && usedbs) && (bstres <= resid)) {
                lambda = bstw
                stp2ii = true
            }
            if stp2ii {
                dlar1v(in_, 1i64, in_, lambda, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](l[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](work[0usize..], usize((((indld + ibegin) - 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize((((indlld + ibegin) - 1i64) - 1i64))), pivmin, gaptol, lbase.sl[f64](z[0usize..], usize((ibegin - 1i64) + (windex - 1i64) * ldz)), (!usedbs), &negcnt, &ztz, &mingma, &iwork[usize(((iindr + windex) - 1i64))], lbase.sl[i64](isuppz[0usize..], usize((((2i64 * windex) - 1i64) - 1i64))), &nrminv, &resid, &rqcorr, lbase.sl[f64](work[0usize..], usize((indwrk - 1i64))))
            }
            work[usize((windex - 1i64))] = lambda
            pc = 34i64
            continue
        }
        if pc == 34i64 {
            isuppz[usize((((2i64 * windex) - 1i64) - 1i64))] = (isuppz[usize((((2i64 * windex) - 1i64) - 1i64))] + oldien)
            isuppz[usize(((2i64 * windex) - 1i64))] = (isuppz[usize(((2i64 * windex) - 1i64))] + oldien)
            zfrom = isuppz[usize((((2i64 * windex) - 1i64) - 1i64))]
            zto = isuppz[usize(((2i64 * windex) - 1i64))]
            isupmn = (isupmn + oldien)
            isupmx = (isupmx + oldien)
            if (isupmn < zfrom) {
                ii = isupmn
                zc12 = ((zfrom - 1i64) - ii) + 1i64
                while zc12 > 0i64 {
                    z[usize((ii - 1i64) + (windex - 1i64) * ldz)] = 0.0f64
                    ii = ii + 1i64
                    zc12 = zc12 - 1i64
                }
            }
            if (isupmx > zto) {
                ii = (zto + 1i64)
                zc13 = (isupmx - ii) + 1i64
                while zc13 > 0i64 {
                    z[usize((ii - 1i64) + (windex - 1i64) * ldz)] = 0.0f64
                    ii = ii + 1i64
                    zc13 = zc13 - 1i64
                }
            }
            lbase.dscal(((zto - zfrom) + 1i64), nrminv, lbase.sl[f64](z[0usize..], usize((zfrom - 1i64) + (windex - 1i64) * ldz)), 1i64)
            pc = 32i64
        }
        if pc == 32i64 {
            w[usize((windex - 1i64))] = (lambda + sigma)
            if (!eskip) {
                if (k > 1i64) {
                    wgap[usize((windmn - 1i64))] = lbase.f_max(wgap[usize((windmn - 1i64))], (((w[usize((windex - 1i64))] - werr[usize((windex - 1i64))]) - w[usize((windmn - 1i64))]) - werr[usize((windmn - 1i64))]))
                }
                if (windex < wend) {
                    wgap[usize((windex - 1i64))] = lbase.f_max(savgap, (((w[usize((windpl - 1i64))] - werr[usize((windpl - 1i64))]) - w[usize((windex - 1i64))]) - werr[usize((windex - 1i64))]))
                }
            }
            idone = (idone + 1i64)
            pc = 25i64
            continue
        }
        if pc == 25i64 {
            pc = 29i64
        }
        if pc == 29i64 {
            newfst = (j + 1i64)
            pc = 24i64
        }
        if pc == 24i64 {
            j = j + 1i64
            zc9 = zc9 - 1i64
            pc = 19i64
            continue
        }
        if pc == 20i64 {
            i = i + 1i64
            zc6 = zc6 - 1i64
            pc = 17i64
            continue
        }
        if pc == 18i64 {
            ndepth = (ndepth + 1i64)
            pc = 14i64
            continue
        }
        if pc == 16i64 {
            pc = 15i64
        }
        if pc == 15i64 {
            ibegin = (iend + 1i64)
            wbegin = (wend + 1i64)
            pc = 10i64
        }
        if pc == 10i64 {
            jblk = jblk + 1i64
            zc3 = zc3 - 1i64
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            *rtol1_ref = rtol1
            *rtol2_ref = rtol2
            *info_ref = info
            ret
        }
    }
}

fn dlar1v(n: i64, b1: i64, bn: i64, lambda: f64, d: []f64, l: []f64, ld: []f64, lld: []f64, pivmin: f64, gaptol: f64, z: []f64, wantnc: bool, negcnt_ref: *i64, ztz_ref: *f64, mingma_ref: *f64, r_ref: *i64, isuppz: []i64, nrminv_ref: *f64, resid_ref: *f64, rqcorr_ref: *f64, work: []f64) {
    var negcnt = *negcnt_ref
    var ztz = *ztz_ref
    var mingma = *mingma_ref
    var r = *r_ref
    var nrminv = *nrminv_ref
    var resid = *resid_ref
    var rqcorr = *rqcorr_ref
    var sawnan1: bool = false
    var sawnan2: bool = false
    var i: i64 = 0i64
    var indlpl: i64 = 0i64
    var indp: i64 = 0i64
    var inds: i64 = 0i64
    var indumn: i64 = 0i64
    var neg1: i64 = 0i64
    var neg2: i64 = 0i64
    var r1: i64 = 0i64
    var r2: i64 = 0i64
    var dminus: f64 = 0.0f64
    var dplus: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var s: f64 = 0.0f64
    var tmp: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    var zs6: i64 = 0i64
    var zc7: i64 = 0i64
    var zs8: i64 = 0i64
    var zc9: i64 = 0i64
    var zc10: i64 = 0i64
    var zs11: i64 = 0i64
    var zc12: i64 = 0i64
    var zs13: i64 = 0i64
    var zc14: i64 = 0i64
    var zc15: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            eps = 2.220446049250313e-16f64
            if (r == 0i64) {
                r1 = b1
                r2 = bn
            } else {
                r1 = r
                r2 = r
            }
            indlpl = 0i64
            indumn = n
            inds = ((2i64 * n) + 1i64)
            indp = ((3i64 * n) + 1i64)
            if (b1 == 1i64) {
                work[usize((inds - 1i64))] = 0.0f64
            } else {
                work[usize((((inds + b1) - 1i64) - 1i64))] = lld[usize(((b1 - 1i64) - 1i64))]
            }
            sawnan1 = false
            neg1 = 0i64
            s = (work[usize((((inds + b1) - 1i64) - 1i64))] - lambda)
            i = b1
            zc1 = ((r1 - 1i64) - i) + 1i64
            while zc1 > 0i64 {
                dplus = (d[usize((i - 1i64))] + s)
                work[usize(((indlpl + i) - 1i64))] = (ld[usize((i - 1i64))] / dplus)
                if (dplus < 0.0f64) {
                    neg1 = (neg1 + 1i64)
                }
                work[usize(((inds + i) - 1i64))] = ((s * work[usize(((indlpl + i) - 1i64))]) * l[usize((i - 1i64))])
                s = (work[usize(((inds + i) - 1i64))] - lambda)
                i = i + 1i64
                zc1 = zc1 - 1i64
            }
            sawnan1 = lbase.disnan(s)
            if !sawnan1 {
                pc = 2i64
                continue
            }
            pc = 3i64
            continue
        }
        if pc == 2i64 {
            pc = 1i64
        }
        if pc == 1i64 {
            i = r1
            zc2 = ((r2 - 1i64) - i) + 1i64
            while zc2 > 0i64 {
                dplus = (d[usize((i - 1i64))] + s)
                work[usize(((indlpl + i) - 1i64))] = (ld[usize((i - 1i64))] / dplus)
                work[usize(((inds + i) - 1i64))] = ((s * work[usize(((indlpl + i) - 1i64))]) * l[usize((i - 1i64))])
                s = (work[usize(((inds + i) - 1i64))] - lambda)
                i = i + 1i64
                zc2 = zc2 - 1i64
            }
            sawnan1 = lbase.disnan(s)
            pc = 3i64
        }
        if pc == 3i64 {
            if sawnan1 {
                neg1 = 0i64
                s = (work[usize((((inds + b1) - 1i64) - 1i64))] - lambda)
                i = b1
                zc3 = ((r1 - 1i64) - i) + 1i64
                while zc3 > 0i64 {
                    dplus = (d[usize((i - 1i64))] + s)
                    if (math.abs[f64](dplus) < pivmin) {
                        dplus = (-pivmin)
                    }
                    work[usize(((indlpl + i) - 1i64))] = (ld[usize((i - 1i64))] / dplus)
                    if (dplus < 0.0f64) {
                        neg1 = (neg1 + 1i64)
                    }
                    work[usize(((inds + i) - 1i64))] = ((s * work[usize(((indlpl + i) - 1i64))]) * l[usize((i - 1i64))])
                    if (work[usize(((indlpl + i) - 1i64))] == 0.0f64) {
                        work[usize(((inds + i) - 1i64))] = lld[usize((i - 1i64))]
                    }
                    s = (work[usize(((inds + i) - 1i64))] - lambda)
                    i = i + 1i64
                    zc3 = zc3 - 1i64
                }
                i = r1
                zc4 = ((r2 - 1i64) - i) + 1i64
                while zc4 > 0i64 {
                    dplus = (d[usize((i - 1i64))] + s)
                    if (math.abs[f64](dplus) < pivmin) {
                        dplus = (-pivmin)
                    }
                    work[usize(((indlpl + i) - 1i64))] = (ld[usize((i - 1i64))] / dplus)
                    work[usize(((inds + i) - 1i64))] = ((s * work[usize(((indlpl + i) - 1i64))]) * l[usize((i - 1i64))])
                    if (work[usize(((indlpl + i) - 1i64))] == 0.0f64) {
                        work[usize(((inds + i) - 1i64))] = lld[usize((i - 1i64))]
                    }
                    s = (work[usize(((inds + i) - 1i64))] - lambda)
                    i = i + 1i64
                    zc4 = zc4 - 1i64
                }
            }
            sawnan2 = false
            neg2 = 0i64
            work[usize((((indp + bn) - 1i64) - 1i64))] = (d[usize((bn - 1i64))] - lambda)
            i = (bn - 1i64)
            zs6 = (-1i64)
            zc5 = ((r1 - i) + zs6) / zs6
            while zc5 > 0i64 {
                dminus = (lld[usize((i - 1i64))] + work[usize(((indp + i) - 1i64))])
                tmp = (d[usize((i - 1i64))] / dminus)
                if (dminus < 0.0f64) {
                    neg2 = (neg2 + 1i64)
                }
                work[usize(((indumn + i) - 1i64))] = (l[usize((i - 1i64))] * tmp)
                work[usize((((indp + i) - 1i64) - 1i64))] = ((work[usize(((indp + i) - 1i64))] * tmp) - lambda)
                i = i + zs6
                zc5 = zc5 - 1i64
            }
            tmp = work[usize((((indp + r1) - 1i64) - 1i64))]
            sawnan2 = lbase.disnan(tmp)
            if sawnan2 {
                neg2 = 0i64
                i = (bn - 1i64)
                zs8 = (-1i64)
                zc7 = ((r1 - i) + zs8) / zs8
                while zc7 > 0i64 {
                    dminus = (lld[usize((i - 1i64))] + work[usize(((indp + i) - 1i64))])
                    if (math.abs[f64](dminus) < pivmin) {
                        dminus = (-pivmin)
                    }
                    tmp = (d[usize((i - 1i64))] / dminus)
                    if (dminus < 0.0f64) {
                        neg2 = (neg2 + 1i64)
                    }
                    work[usize(((indumn + i) - 1i64))] = (l[usize((i - 1i64))] * tmp)
                    work[usize((((indp + i) - 1i64) - 1i64))] = ((work[usize(((indp + i) - 1i64))] * tmp) - lambda)
                    if (tmp == 0.0f64) {
                        work[usize((((indp + i) - 1i64) - 1i64))] = (d[usize((i - 1i64))] - lambda)
                    }
                    i = i + zs8
                    zc7 = zc7 - 1i64
                }
            }
            mingma = (work[usize((((inds + r1) - 1i64) - 1i64))] + work[usize((((indp + r1) - 1i64) - 1i64))])
            if (mingma < 0.0f64) {
                neg1 = (neg1 + 1i64)
            }
            if wantnc {
                negcnt = (neg1 + neg2)
            } else {
                negcnt = (-1i64)
            }
            if (math.abs[f64](mingma) == 0.0f64) {
                mingma = (eps * work[usize((((inds + r1) - 1i64) - 1i64))])
            }
            r = r1
            i = r1
            zc9 = ((r2 - 1i64) - i) + 1i64
            while zc9 > 0i64 {
                tmp = (work[usize(((inds + i) - 1i64))] + work[usize(((indp + i) - 1i64))])
                if (tmp == 0.0f64) {
                    tmp = (eps * work[usize(((inds + i) - 1i64))])
                }
                if (math.abs[f64](tmp) <= math.abs[f64](mingma)) {
                    mingma = tmp
                    r = (i + 1i64)
                }
                i = i + 1i64
                zc9 = zc9 - 1i64
            }
            isuppz[usize((1i64 - 1i64))] = b1
            isuppz[usize((2i64 - 1i64))] = bn
            z[usize((r - 1i64))] = 1.0f64
            ztz = 1.0f64
            if !((!sawnan1) && (!sawnan2)) {
                pc = 5i64
                continue
            }
            i = (r - 1i64)
            zs11 = (-1i64)
            zc10 = ((b1 - i) + zs11) / zs11
            pc = 6i64
        }
        if pc == 6i64 {
            if zc10 <= 0i64 {
                pc = 7i64
                continue
            }
            z[usize((i - 1i64))] = (-((work[usize(((indlpl + i) - 1i64))] * z[usize(((i + 1i64) - 1i64))])))
            if !((((math.abs[f64](z[usize((i - 1i64))]) + math.abs[f64](z[usize(((i + 1i64) - 1i64))]))) * math.abs[f64](ld[usize((i - 1i64))])) < gaptol) {
                pc = 9i64
                continue
            }
            z[usize((i - 1i64))] = 0.0f64
            isuppz[usize((1i64 - 1i64))] = (i + 1i64)
            pc = 10i64
            continue
        }
        if pc == 9i64 {
            pc = 8i64
        }
        if pc == 8i64 {
            ztz = (ztz + (z[usize((i - 1i64))] * z[usize((i - 1i64))]))
            i = i + zs11
            zc10 = zc10 - 1i64
            pc = 6i64
            continue
        }
        if pc == 7i64 {
            pc = 10i64
        }
        if pc == 10i64 {
            pc = 4i64
            continue
        }
        if pc == 5i64 {
            i = (r - 1i64)
            zs13 = (-1i64)
            zc12 = ((b1 - i) + zs13) / zs13
            pc = 11i64
        }
        if pc == 11i64 {
            if zc12 <= 0i64 {
                pc = 12i64
                continue
            }
            if (z[usize(((i + 1i64) - 1i64))] == 0.0f64) {
                z[usize((i - 1i64))] = (-(((ld[usize(((i + 1i64) - 1i64))] / ld[usize((i - 1i64))])) * z[usize(((i + 2i64) - 1i64))]))
            } else {
                z[usize((i - 1i64))] = (-((work[usize(((indlpl + i) - 1i64))] * z[usize(((i + 1i64) - 1i64))])))
            }
            if !((((math.abs[f64](z[usize((i - 1i64))]) + math.abs[f64](z[usize(((i + 1i64) - 1i64))]))) * math.abs[f64](ld[usize((i - 1i64))])) < gaptol) {
                pc = 14i64
                continue
            }
            z[usize((i - 1i64))] = 0.0f64
            isuppz[usize((1i64 - 1i64))] = (i + 1i64)
            pc = 15i64
            continue
        }
        if pc == 14i64 {
            pc = 13i64
        }
        if pc == 13i64 {
            ztz = (ztz + (z[usize((i - 1i64))] * z[usize((i - 1i64))]))
            i = i + zs13
            zc12 = zc12 - 1i64
            pc = 11i64
            continue
        }
        if pc == 12i64 {
            pc = 15i64
        }
        if pc == 15i64 {
            pc = 4i64
            continue
        }
        if pc == 4i64 {
            if !((!sawnan1) && (!sawnan2)) {
                pc = 17i64
                continue
            }
            i = r
            zc14 = ((bn - 1i64) - i) + 1i64
            pc = 18i64
        }
        if pc == 18i64 {
            if zc14 <= 0i64 {
                pc = 19i64
                continue
            }
            z[usize(((i + 1i64) - 1i64))] = (-((work[usize(((indumn + i) - 1i64))] * z[usize((i - 1i64))])))
            if !((((math.abs[f64](z[usize((i - 1i64))]) + math.abs[f64](z[usize(((i + 1i64) - 1i64))]))) * math.abs[f64](ld[usize((i - 1i64))])) < gaptol) {
                pc = 21i64
                continue
            }
            z[usize(((i + 1i64) - 1i64))] = 0.0f64
            isuppz[usize((2i64 - 1i64))] = i
            pc = 22i64
            continue
        }
        if pc == 21i64 {
            pc = 20i64
        }
        if pc == 20i64 {
            ztz = (ztz + (z[usize(((i + 1i64) - 1i64))] * z[usize(((i + 1i64) - 1i64))]))
            i = i + 1i64
            zc14 = zc14 - 1i64
            pc = 18i64
            continue
        }
        if pc == 19i64 {
            pc = 22i64
        }
        if pc == 22i64 {
            pc = 16i64
            continue
        }
        if pc == 17i64 {
            i = r
            zc15 = ((bn - 1i64) - i) + 1i64
            pc = 23i64
        }
        if pc == 23i64 {
            if zc15 <= 0i64 {
                pc = 24i64
                continue
            }
            if (z[usize((i - 1i64))] == 0.0f64) {
                z[usize(((i + 1i64) - 1i64))] = (-(((ld[usize(((i - 1i64) - 1i64))] / ld[usize((i - 1i64))])) * z[usize(((i - 1i64) - 1i64))]))
            } else {
                z[usize(((i + 1i64) - 1i64))] = (-((work[usize(((indumn + i) - 1i64))] * z[usize((i - 1i64))])))
            }
            if !((((math.abs[f64](z[usize((i - 1i64))]) + math.abs[f64](z[usize(((i + 1i64) - 1i64))]))) * math.abs[f64](ld[usize((i - 1i64))])) < gaptol) {
                pc = 26i64
                continue
            }
            z[usize(((i + 1i64) - 1i64))] = 0.0f64
            isuppz[usize((2i64 - 1i64))] = i
            pc = 27i64
            continue
        }
        if pc == 26i64 {
            pc = 25i64
        }
        if pc == 25i64 {
            ztz = (ztz + (z[usize(((i + 1i64) - 1i64))] * z[usize(((i + 1i64) - 1i64))]))
            i = i + 1i64
            zc15 = zc15 - 1i64
            pc = 23i64
            continue
        }
        if pc == 24i64 {
            pc = 27i64
        }
        if pc == 27i64 {
            pc = 16i64
            continue
        }
        if pc == 16i64 {
            tmp = (1.0f64 / ztz)
            nrminv = math.sqrt[f64](tmp)
            resid = (math.abs[f64](mingma) * nrminv)
            rqcorr = (mingma * tmp)
            *negcnt_ref = negcnt
            *ztz_ref = ztz
            *mingma_ref = mingma
            *r_ref = r
            *nrminv_ref = nrminv
            *resid_ref = resid
            *rqcorr_ref = rqcorr
            ret
        }
    }
}

fn dlaneg(n: i64, d: []f64, lld: []f64, sigma: f64, pivmin: f64, r: i64) -> i64 {
    var result_: i64 = 0i64
    var bj: i64 = 0i64
    var j: i64 = 0i64
    var neg1: i64 = 0i64
    var neg2: i64 = 0i64
    var negcnt: i64 = 0i64
    var bsav: f64 = 0.0f64
    var dminus: f64 = 0.0f64
    var dplus: f64 = 0.0f64
    var gamma: f64 = 0.0f64
    var p: f64 = 0.0f64
    var t: f64 = 0.0f64
    var tmp: f64 = 0.0f64
    var sawnan: bool = false
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    var zs6: i64 = 0i64
    var zc7: i64 = 0i64
    var zs8: i64 = 0i64
    var zc9: i64 = 0i64
    var zs10: i64 = 0i64
    negcnt = 0i64
    t = (-sigma)
    bj = 1i64
    zs2 = 128i64
    zc1 = (((r - 1i64) - bj) + zs2) / zs2
    while zc1 > 0i64 {
        neg1 = 0i64
        bsav = t
        j = bj
        zc3 = (lbase.i_min(((bj + 128i64) - 1i64), (r - 1i64)) - j) + 1i64
        while zc3 > 0i64 {
            dplus = (d[usize((j - 1i64))] + t)
            if (dplus < 0.0f64) {
                neg1 = (neg1 + 1i64)
            }
            tmp = (t / dplus)
            t = ((tmp * lld[usize((j - 1i64))]) - sigma)
            j = j + 1i64
            zc3 = zc3 - 1i64
        }
        sawnan = lbase.disnan(t)
        if sawnan {
            neg1 = 0i64
            t = bsav
            j = bj
            zc4 = (lbase.i_min(((bj + 128i64) - 1i64), (r - 1i64)) - j) + 1i64
            while zc4 > 0i64 {
                dplus = (d[usize((j - 1i64))] + t)
                if (dplus < 0.0f64) {
                    neg1 = (neg1 + 1i64)
                }
                tmp = (t / dplus)
                if lbase.disnan(tmp) {
                    tmp = 1.0f64
                }
                t = ((tmp * lld[usize((j - 1i64))]) - sigma)
                j = j + 1i64
                zc4 = zc4 - 1i64
            }
        }
        negcnt = (negcnt + neg1)
        bj = bj + zs2
        zc1 = zc1 - 1i64
    }
    p = (d[usize((n - 1i64))] - sigma)
    bj = (n - 1i64)
    zs6 = (-128i64)
    zc5 = ((r - bj) + zs6) / zs6
    while zc5 > 0i64 {
        neg2 = 0i64
        bsav = p
        j = bj
        zs8 = (-1i64)
        zc7 = ((lbase.i_max(((bj - 128i64) + 1i64), r) - j) + zs8) / zs8
        while zc7 > 0i64 {
            dminus = (lld[usize((j - 1i64))] + p)
            if (dminus < 0.0f64) {
                neg2 = (neg2 + 1i64)
            }
            tmp = (p / dminus)
            p = ((tmp * d[usize((j - 1i64))]) - sigma)
            j = j + zs8
            zc7 = zc7 - 1i64
        }
        sawnan = lbase.disnan(p)
        if sawnan {
            neg2 = 0i64
            p = bsav
            j = bj
            zs10 = (-1i64)
            zc9 = ((lbase.i_max(((bj - 128i64) + 1i64), r) - j) + zs10) / zs10
            while zc9 > 0i64 {
                dminus = (lld[usize((j - 1i64))] + p)
                if (dminus < 0.0f64) {
                    neg2 = (neg2 + 1i64)
                }
                tmp = (p / dminus)
                if lbase.disnan(tmp) {
                    tmp = 1.0f64
                }
                p = ((tmp * d[usize((j - 1i64))]) - sigma)
                j = j + zs10
                zc9 = zc9 - 1i64
            }
        }
        negcnt = (negcnt + neg2)
        bj = bj + zs6
        zc5 = zc5 - 1i64
    }
    gamma = (((t + sigma)) + p)
    if (gamma < 0.0f64) {
        negcnt = (negcnt + 1i64)
    }
    result_ = negcnt
    ret result_
}

fn dlarrb(n: i64, d: []f64, lld: []f64, ifirst: i64, ilast: i64, rtol1: f64, rtol2: f64, offset: i64, w: []f64, wgap: []f64, werr: []f64, work: []f64, iwork: []i64, pivmin: f64, spdiam: f64, twist: i64, info_ref: *i64) {
    var info = *info_ref
    var maxitr: i64 = 0i64
    var i: i64 = 0i64
    var i1: i64 = 0i64
    var ii: i64 = 0i64
    var ip: i64 = 0i64
    var iter: i64 = 0i64
    var k: i64 = 0i64
    var negcnt: i64 = 0i64
    var next: i64 = 0i64
    var nint: i64 = 0i64
    var olnint: i64 = 0i64
    var prev: i64 = 0i64
    var r: i64 = 0i64
    var back: f64 = 0.0f64
    var cvrgd: f64 = 0.0f64
    var gap: f64 = 0.0f64
    var left: f64 = 0.0f64
    var lgap: f64 = 0.0f64
    var mid: f64 = 0.0f64
    var mnwdth: f64 = 0.0f64
    var rgap: f64 = 0.0f64
    var right: f64 = 0.0f64
    var tmp: f64 = 0.0f64
    var width: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            if (n <= 0i64) {
                *info_ref = info
                ret
            }
            maxitr = (i64((((math.log[f64]((spdiam + pivmin)) - math.log[f64](pivmin))) / math.log[f64](2.0f64))) + 2i64)
            mnwdth = (2.0f64 * pivmin)
            r = twist
            if (((r < 1i64)) || ((r > n))) {
                r = n
            }
            i1 = ifirst
            nint = 0i64
            prev = 0i64
            rgap = wgap[usize(((i1 - offset) - 1i64))]
            i = i1
            zc1 = (ilast - i) + 1i64
            pc = 1i64
        }
        if pc == 1i64 {
            if zc1 <= 0i64 {
                pc = 2i64
                continue
            }
            k = (2i64 * i)
            ii = (i - offset)
            left = (w[usize((ii - 1i64))] - werr[usize((ii - 1i64))])
            right = (w[usize((ii - 1i64))] + werr[usize((ii - 1i64))])
            lgap = rgap
            rgap = wgap[usize((ii - 1i64))]
            gap = lbase.f_min(lgap, rgap)
            back = werr[usize((ii - 1i64))]
            pc = 3i64
        }
        if pc == 3i64 {
            negcnt = dlaneg(n, d[0usize..], lld[0usize..], left, pivmin, r)
            if !(negcnt > (i - 1i64)) {
                pc = 5i64
                continue
            }
            left = (left - back)
            back = (2.0f64 * back)
            pc = 3i64
            continue
        }
        if pc == 5i64 {
            pc = 4i64
        }
        if pc == 4i64 {
            back = werr[usize((ii - 1i64))]
            pc = 6i64
        }
        if pc == 6i64 {
            negcnt = dlaneg(n, d[0usize..], lld[0usize..], right, pivmin, r)
            if !(negcnt < i) {
                pc = 8i64
                continue
            }
            right = (right + back)
            back = (2.0f64 * back)
            pc = 6i64
            continue
        }
        if pc == 8i64 {
            pc = 7i64
        }
        if pc == 7i64 {
            width = (0.5f64 * math.abs[f64]((left - right)))
            tmp = lbase.f_max(math.abs[f64](left), math.abs[f64](right))
            cvrgd = lbase.f_max((rtol1 * gap), (rtol2 * tmp))
            if ((width <= cvrgd) || (width <= mnwdth)) {
                iwork[usize(((k - 1i64) - 1i64))] = (-1i64)
                if (((i == i1)) && ((i < ilast))) {
                    i1 = (i + 1i64)
                }
                if (((prev >= i1)) && ((i <= ilast))) {
                    iwork[usize((((2i64 * prev) - 1i64) - 1i64))] = (i + 1i64)
                }
            } else {
                prev = i
                nint = (nint + 1i64)
                iwork[usize(((k - 1i64) - 1i64))] = (i + 1i64)
                iwork[usize((k - 1i64))] = negcnt
            }
            work[usize(((k - 1i64) - 1i64))] = left
            work[usize((k - 1i64))] = right
            i = i + 1i64
            zc1 = zc1 - 1i64
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            iter = 0i64
            pc = 9i64
        }
        if pc == 9i64 {
            prev = (i1 - 1i64)
            i = i1
            olnint = nint
            ip = 1i64
            zc2 = (olnint - ip) + 1i64
            pc = 10i64
        }
        if pc == 10i64 {
            if zc2 <= 0i64 {
                pc = 11i64
                continue
            }
            k = (2i64 * i)
            ii = (i - offset)
            rgap = wgap[usize((ii - 1i64))]
            lgap = rgap
            if (ii > 1i64) {
                lgap = wgap[usize(((ii - 1i64) - 1i64))]
            }
            gap = lbase.f_min(lgap, rgap)
            next = iwork[usize(((k - 1i64) - 1i64))]
            left = work[usize(((k - 1i64) - 1i64))]
            right = work[usize((k - 1i64))]
            mid = (0.5f64 * ((left + right)))
            width = (right - mid)
            tmp = lbase.f_max(math.abs[f64](left), math.abs[f64](right))
            cvrgd = lbase.f_max((rtol1 * gap), (rtol2 * tmp))
            if !((((width <= cvrgd)) || ((width <= mnwdth))) || ((iter == maxitr))) {
                pc = 13i64
                continue
            }
            nint = (nint - 1i64)
            iwork[usize(((k - 1i64) - 1i64))] = 0i64
            if (i1 == i) {
                i1 = next
            } else {
                if (prev >= i1) {
                    iwork[usize((((2i64 * prev) - 1i64) - 1i64))] = next
                }
            }
            i = next
            pc = 14i64
            continue
        }
        if pc == 13i64 {
            pc = 12i64
        }
        if pc == 12i64 {
            prev = i
            negcnt = dlaneg(n, d[0usize..], lld[0usize..], mid, pivmin, r)
            if (negcnt <= (i - 1i64)) {
                work[usize(((k - 1i64) - 1i64))] = mid
            } else {
                work[usize((k - 1i64))] = mid
            }
            i = next
            pc = 14i64
        }
        if pc == 14i64 {
            ip = ip + 1i64
            zc2 = zc2 - 1i64
            pc = 10i64
            continue
        }
        if pc == 11i64 {
            iter = (iter + 1i64)
            if !(((nint > 0i64)) && ((iter <= maxitr))) {
                pc = 16i64
                continue
            }
            pc = 9i64
            continue
        }
        if pc == 16i64 {
            pc = 15i64
        }
        if pc == 15i64 {
            i = ifirst
            zc3 = (ilast - i) + 1i64
            while zc3 > 0i64 {
                k = (2i64 * i)
                ii = (i - offset)
                if (iwork[usize(((k - 1i64) - 1i64))] == 0i64) {
                    w[usize((ii - 1i64))] = (0.5f64 * ((work[usize(((k - 1i64) - 1i64))] + work[usize((k - 1i64))])))
                    werr[usize((ii - 1i64))] = (work[usize((k - 1i64))] - w[usize((ii - 1i64))])
                }
                i = i + 1i64
                zc3 = zc3 - 1i64
            }
            i = (ifirst + 1i64)
            zc4 = (ilast - i) + 1i64
            while zc4 > 0i64 {
                k = (2i64 * i)
                ii = (i - offset)
                wgap[usize(((ii - 1i64) - 1i64))] = lbase.f_max(0.0f64, (((w[usize((ii - 1i64))] - werr[usize((ii - 1i64))]) - w[usize(((ii - 1i64) - 1i64))]) - werr[usize(((ii - 1i64) - 1i64))]))
                i = i + 1i64
                zc4 = zc4 - 1i64
            }
            *info_ref = info
            ret
        }
    }
}

fn dlarrf(n: i64, d: []f64, l: []f64, ld: []f64, clstrt: i64, clend: i64, w: []f64, wgap: []f64, werr: []f64, spdiam: f64, clgapl: f64, clgapr: f64, pivmin: f64, sigma_ref: *f64, dplus: []f64, lplus: []f64, work: []f64, info_ref: *i64) {
    var sigma = *sigma_ref
    var info = *info_ref
    var dorrr1: bool = false
    var forcer: bool = false
    var nofail: bool = false
    var sawnan1: bool = false
    var sawnan2: bool = false
    var tryrrr1: bool = false
    var i: i64 = 0i64
    var indx: i64 = 0i64
    var ktry: i64 = 0i64
    var shift: i64 = 0i64
    var avgap: f64 = 0.0f64
    var bestshift: f64 = 0.0f64
    var clwdth: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var fact: f64 = 0.0f64
    var fail: f64 = 0.0f64
    var fail2: f64 = 0.0f64
    var growthbound: f64 = 0.0f64
    var ldelta: f64 = 0.0f64
    var ldmax: f64 = 0.0f64
    var lsigma: f64 = 0.0f64
    var max1: f64 = 0.0f64
    var max2: f64 = 0.0f64
    var mingap: f64 = 0.0f64
    var oldp: f64 = 0.0f64
    var prod: f64 = 0.0f64
    var rdelta: f64 = 0.0f64
    var rdmax: f64 = 0.0f64
    var rrr1: f64 = 0.0f64
    var rrr2: f64 = 0.0f64
    var rsigma: f64 = 0.0f64
    var s: f64 = 0.0f64
    var smlgrowth: f64 = 0.0f64
    var tmp: f64 = 0.0f64
    var znm2: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zs4: i64 = 0i64
    var zc5: i64 = 0i64
    var zs6: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            if (n <= 0i64) {
                *sigma_ref = sigma
                *info_ref = info
                ret
            }
            fact = f64(lbase.i_pow(2i64, 1i64))
            eps = 2.220446049250313e-16f64
            shift = 0i64
            forcer = false
            nofail = false
            clwdth = ((math.abs[f64]((w[usize((clend - 1i64))] - w[usize((clstrt - 1i64))])) + werr[usize((clend - 1i64))]) + werr[usize((clstrt - 1i64))])
            avgap = (clwdth / f64((clend - clstrt)))
            mingap = lbase.f_min(clgapl, clgapr)
            lsigma = (lbase.f_min(w[usize((clstrt - 1i64))], w[usize((clend - 1i64))]) - werr[usize((clstrt - 1i64))])
            rsigma = (lbase.f_max(w[usize((clstrt - 1i64))], w[usize((clend - 1i64))]) + werr[usize((clend - 1i64))])
            lsigma = (lsigma - ((math.abs[f64](lsigma) * 4.0f64) * eps))
            rsigma = (rsigma + ((math.abs[f64](rsigma) * 4.0f64) * eps))
            ldmax = ((0.25f64 * mingap) + (2.0f64 * pivmin))
            rdmax = ((0.25f64 * mingap) + (2.0f64 * pivmin))
            ldelta = (lbase.f_max(avgap, wgap[usize((clstrt - 1i64))]) / fact)
            rdelta = (lbase.f_max(avgap, wgap[usize(((clend - 1i64) - 1i64))]) / fact)
            s = 2.2250738585072014e-308f64
            smlgrowth = (1.0f64 / s)
            fail = ((f64((n - 1i64)) * mingap) / ((spdiam * eps)))
            fail2 = ((f64((n - 1i64)) * mingap) / ((spdiam * math.sqrt[f64](eps))))
            bestshift = lsigma
            ktry = 0i64
            growthbound = (8.0f64 * spdiam)
            pc = 1i64
        }
        if pc == 1i64 {
            sawnan1 = false
            sawnan2 = false
            ldelta = lbase.f_min(ldmax, ldelta)
            rdelta = lbase.f_min(rdmax, rdelta)
            s = (-lsigma)
            dplus[usize((1i64 - 1i64))] = (d[usize((1i64 - 1i64))] + s)
            if (math.abs[f64](dplus[usize((1i64 - 1i64))]) < pivmin) {
                dplus[usize((1i64 - 1i64))] = (-pivmin)
                sawnan1 = true
            }
            max1 = math.abs[f64](dplus[usize((1i64 - 1i64))])
            i = 1i64
            zc1 = ((n - 1i64) - i) + 1i64
            while zc1 > 0i64 {
                lplus[usize((i - 1i64))] = (ld[usize((i - 1i64))] / dplus[usize((i - 1i64))])
                s = (((s * lplus[usize((i - 1i64))]) * l[usize((i - 1i64))]) - lsigma)
                dplus[usize(((i + 1i64) - 1i64))] = (d[usize(((i + 1i64) - 1i64))] + s)
                if (math.abs[f64](dplus[usize(((i + 1i64) - 1i64))]) < pivmin) {
                    dplus[usize(((i + 1i64) - 1i64))] = (-pivmin)
                    sawnan1 = true
                }
                max1 = lbase.f_max(max1, math.abs[f64](dplus[usize(((i + 1i64) - 1i64))]))
                i = i + 1i64
                zc1 = zc1 - 1i64
            }
            sawnan1 = (sawnan1 || lbase.disnan(max1))
            if !(forcer || (((max1 <= growthbound) && (!sawnan1)))) {
                pc = 3i64
                continue
            }
            sigma = lsigma
            shift = 1i64
            pc = 4i64
            continue
        }
        if pc == 3i64 {
            pc = 2i64
        }
        if pc == 2i64 {
            s = (-rsigma)
            work[usize((1i64 - 1i64))] = (d[usize((1i64 - 1i64))] + s)
            if (math.abs[f64](work[usize((1i64 - 1i64))]) < pivmin) {
                work[usize((1i64 - 1i64))] = (-pivmin)
                sawnan2 = true
            }
            max2 = math.abs[f64](work[usize((1i64 - 1i64))])
            i = 1i64
            zc2 = ((n - 1i64) - i) + 1i64
            while zc2 > 0i64 {
                work[usize(((n + i) - 1i64))] = (ld[usize((i - 1i64))] / work[usize((i - 1i64))])
                s = (((s * work[usize(((n + i) - 1i64))]) * l[usize((i - 1i64))]) - rsigma)
                work[usize(((i + 1i64) - 1i64))] = (d[usize(((i + 1i64) - 1i64))] + s)
                if (math.abs[f64](work[usize(((i + 1i64) - 1i64))]) < pivmin) {
                    work[usize(((i + 1i64) - 1i64))] = (-pivmin)
                    sawnan2 = true
                }
                max2 = lbase.f_max(max2, math.abs[f64](work[usize(((i + 1i64) - 1i64))]))
                i = i + 1i64
                zc2 = zc2 - 1i64
            }
            sawnan2 = (sawnan2 || lbase.disnan(max2))
            if !(forcer || (((max2 <= growthbound) && (!sawnan2)))) {
                pc = 6i64
                continue
            }
            sigma = rsigma
            shift = 2i64
            pc = 4i64
            continue
        }
        if pc == 6i64 {
            pc = 5i64
        }
        if pc == 5i64 {
            if !(sawnan1 && sawnan2) {
                pc = 8i64
                continue
            }
            pc = 9i64
            continue
        }
        if pc == 8i64 {
            if (!sawnan1) {
                indx = 1i64
                if (max1 <= smlgrowth) {
                    smlgrowth = max1
                    bestshift = lsigma
                }
            }
            if (!sawnan2) {
                if (sawnan1 || (max2 <= max1)) {
                    indx = 2i64
                }
                if (max2 <= smlgrowth) {
                    smlgrowth = max2
                    bestshift = rsigma
                }
            }
            pc = 7i64
            continue
        }
        if pc == 7i64 {
            if (((((clwdth < (mingap / 128.0f64))) && ((lbase.f_min(max1, max2) < fail2))) && ((!sawnan1))) && ((!sawnan2))) {
                dorrr1 = true
            } else {
                dorrr1 = false
            }
            tryrrr1 = true
            if !(tryrrr1 && dorrr1) {
                pc = 11i64
                continue
            }
            if !(indx == 1i64) {
                pc = 13i64
                continue
            }
            tmp = math.abs[f64](dplus[usize((n - 1i64))])
            znm2 = 1.0f64
            prod = 1.0f64
            oldp = 1.0f64
            i = (n - 1i64)
            zs4 = (-1i64)
            zc3 = ((1i64 - i) + zs4) / zs4
            while zc3 > 0i64 {
                if (prod <= eps) {
                    prod = (((((dplus[usize(((i + 1i64) - 1i64))] * work[usize((((n + i) + 1i64) - 1i64))])) / ((dplus[usize((i - 1i64))] * work[usize(((n + i) - 1i64))])))) * oldp)
                } else {
                    prod = (prod * math.abs[f64](work[usize(((n + i) - 1i64))]))
                }
                oldp = prod
                znm2 = (znm2 + (prod * prod))
                tmp = lbase.f_max(tmp, math.abs[f64]((dplus[usize((i - 1i64))] * prod)))
                i = i + zs4
                zc3 = zc3 - 1i64
            }
            rrr1 = (tmp / ((spdiam * math.sqrt[f64](znm2))))
            if !(rrr1 <= 8.0f64) {
                pc = 15i64
                continue
            }
            sigma = lsigma
            shift = 1i64
            pc = 4i64
            continue
        }
        if pc == 15i64 {
            pc = 14i64
        }
        if pc == 14i64 {
            pc = 12i64
            continue
        }
        if pc == 13i64 {
            if !(indx == 2i64) {
                pc = 16i64
                continue
            }
            tmp = math.abs[f64](work[usize((n - 1i64))])
            znm2 = 1.0f64
            prod = 1.0f64
            oldp = 1.0f64
            i = (n - 1i64)
            zs6 = (-1i64)
            zc5 = ((1i64 - i) + zs6) / zs6
            while zc5 > 0i64 {
                if (prod <= eps) {
                    prod = (((((work[usize(((i + 1i64) - 1i64))] * lplus[usize(((i + 1i64) - 1i64))])) / ((work[usize((i - 1i64))] * lplus[usize((i - 1i64))])))) * oldp)
                } else {
                    prod = (prod * math.abs[f64](lplus[usize((i - 1i64))]))
                }
                oldp = prod
                znm2 = (znm2 + (prod * prod))
                tmp = lbase.f_max(tmp, math.abs[f64]((work[usize((i - 1i64))] * prod)))
                i = i + zs6
                zc5 = zc5 - 1i64
            }
            rrr2 = (tmp / ((spdiam * math.sqrt[f64](znm2))))
            if !(rrr2 <= 8.0f64) {
                pc = 18i64
                continue
            }
            sigma = rsigma
            shift = 2i64
            pc = 4i64
            continue
        }
        if pc == 18i64 {
            pc = 17i64
        }
        if pc == 17i64 {
            pc = 12i64
            continue
        }
        if pc == 16i64 {
            pc = 12i64
        }
        if pc == 12i64 {
            pc = 10i64
            continue
        }
        if pc == 11i64 {
            pc = 10i64
        }
        if pc == 10i64 {
            pc = 9i64
        }
        if pc == 9i64 {
            if !(ktry < 1i64) {
                pc = 20i64
                continue
            }
            lsigma = lbase.f_max((lsigma - ldelta), (lsigma - ldmax))
            rsigma = lbase.f_min((rsigma + rdelta), (rsigma + rdmax))
            ldelta = (2.0f64 * ldelta)
            rdelta = (2.0f64 * rdelta)
            ktry = (ktry + 1i64)
            pc = 1i64
            continue
        }
        if pc == 20i64 {
            if !(((smlgrowth < fail)) || nofail) {
                pc = 22i64
                continue
            }
            lsigma = bestshift
            rsigma = bestshift
            forcer = true
            pc = 1i64
            continue
        }
        if pc == 22i64 {
            info = 1i64
            *sigma_ref = sigma
            *info_ref = info
            ret
        }
        if pc == 21i64 {
            pc = 19i64
            continue
        }
        if pc == 19i64 {
            pc = 4i64
        }
        if pc == 4i64 {
            if (shift == 1i64) {
            } else if (shift == 2i64) {
                lbase.dcopy(n, work[0usize..], 1i64, dplus[0usize..], 1i64)
                lbase.dcopy((n - 1i64), lbase.sl[f64](work[0usize..], usize(((n + 1i64) - 1i64))), 1i64, lplus[0usize..], 1i64)
            }
            *sigma_ref = sigma
            *info_ref = info
            ret
        }
    }
}

fn dlarrj(n: i64, d: []f64, e2: []f64, ifirst: i64, ilast: i64, rtol: f64, offset: i64, w: []f64, werr: []f64, work: []f64, iwork: []i64, pivmin: f64, spdiam: f64, info_ref: *i64) {
    var info = *info_ref
    var maxitr: i64 = 0i64
    var cnt: i64 = 0i64
    var i: i64 = 0i64
    var i1: i64 = 0i64
    var i2: i64 = 0i64
    var ii: i64 = 0i64
    var iter: i64 = 0i64
    var j: i64 = 0i64
    var k: i64 = 0i64
    var next: i64 = 0i64
    var nint: i64 = 0i64
    var olnint: i64 = 0i64
    var p: i64 = 0i64
    var prev: i64 = 0i64
    var savi1: i64 = 0i64
    var dplus: f64 = 0.0f64
    var fac: f64 = 0.0f64
    var left: f64 = 0.0f64
    var mid: f64 = 0.0f64
    var right: f64 = 0.0f64
    var s: f64 = 0.0f64
    var tmp: f64 = 0.0f64
    var width: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    var zc6: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            if (n <= 0i64) {
                *info_ref = info
                ret
            }
            maxitr = (i64((((math.log[f64]((spdiam + pivmin)) - math.log[f64](pivmin))) / math.log[f64](2.0f64))) + 2i64)
            i1 = ifirst
            i2 = ilast
            nint = 0i64
            prev = 0i64
            i = i1
            zc1 = (i2 - i) + 1i64
            pc = 1i64
        }
        if pc == 1i64 {
            if zc1 <= 0i64 {
                pc = 2i64
                continue
            }
            k = (2i64 * i)
            ii = (i - offset)
            left = (w[usize((ii - 1i64))] - werr[usize((ii - 1i64))])
            mid = w[usize((ii - 1i64))]
            right = (w[usize((ii - 1i64))] + werr[usize((ii - 1i64))])
            width = (right - mid)
            tmp = lbase.f_max(math.abs[f64](left), math.abs[f64](right))
            if !(width < (rtol * tmp)) {
                pc = 4i64
                continue
            }
            iwork[usize(((k - 1i64) - 1i64))] = (-1i64)
            if (((i == i1)) && ((i < i2))) {
                i1 = (i + 1i64)
            }
            if (((prev >= i1)) && ((i <= i2))) {
                iwork[usize((((2i64 * prev) - 1i64) - 1i64))] = (i + 1i64)
            }
            pc = 3i64
            continue
        }
        if pc == 4i64 {
            prev = i
            fac = 1.0f64
            pc = 5i64
        }
        if pc == 5i64 {
            cnt = 0i64
            s = left
            dplus = (d[usize((1i64 - 1i64))] - s)
            if (dplus < 0.0f64) {
                cnt = (cnt + 1i64)
            }
            j = 2i64
            zc2 = (n - j) + 1i64
            while zc2 > 0i64 {
                dplus = ((d[usize((j - 1i64))] - s) - (e2[usize(((j - 1i64) - 1i64))] / dplus))
                if (dplus < 0.0f64) {
                    cnt = (cnt + 1i64)
                }
                j = j + 1i64
                zc2 = zc2 - 1i64
            }
            if !(cnt > (i - 1i64)) {
                pc = 7i64
                continue
            }
            left = (left - (werr[usize((ii - 1i64))] * fac))
            fac = (2.0f64 * fac)
            pc = 5i64
            continue
        }
        if pc == 7i64 {
            pc = 6i64
        }
        if pc == 6i64 {
            fac = 1.0f64
            pc = 8i64
        }
        if pc == 8i64 {
            cnt = 0i64
            s = right
            dplus = (d[usize((1i64 - 1i64))] - s)
            if (dplus < 0.0f64) {
                cnt = (cnt + 1i64)
            }
            j = 2i64
            zc3 = (n - j) + 1i64
            while zc3 > 0i64 {
                dplus = ((d[usize((j - 1i64))] - s) - (e2[usize(((j - 1i64) - 1i64))] / dplus))
                if (dplus < 0.0f64) {
                    cnt = (cnt + 1i64)
                }
                j = j + 1i64
                zc3 = zc3 - 1i64
            }
            if !(cnt < i) {
                pc = 10i64
                continue
            }
            right = (right + (werr[usize((ii - 1i64))] * fac))
            fac = (2.0f64 * fac)
            pc = 8i64
            continue
        }
        if pc == 10i64 {
            pc = 9i64
        }
        if pc == 9i64 {
            nint = (nint + 1i64)
            iwork[usize(((k - 1i64) - 1i64))] = (i + 1i64)
            iwork[usize((k - 1i64))] = cnt
            pc = 3i64
            continue
        }
        if pc == 3i64 {
            work[usize(((k - 1i64) - 1i64))] = left
            work[usize((k - 1i64))] = right
            i = i + 1i64
            zc1 = zc1 - 1i64
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            savi1 = i1
            iter = 0i64
            pc = 11i64
        }
        if pc == 11i64 {
            prev = (i1 - 1i64)
            i = i1
            olnint = nint
            p = 1i64
            zc4 = (olnint - p) + 1i64
            pc = 12i64
        }
        if pc == 12i64 {
            if zc4 <= 0i64 {
                pc = 13i64
                continue
            }
            k = (2i64 * i)
            ii = (i - offset)
            next = iwork[usize(((k - 1i64) - 1i64))]
            left = work[usize(((k - 1i64) - 1i64))]
            right = work[usize((k - 1i64))]
            mid = (0.5f64 * ((left + right)))
            width = (right - mid)
            tmp = lbase.f_max(math.abs[f64](left), math.abs[f64](right))
            if !(((width < (rtol * tmp))) || ((iter == maxitr))) {
                pc = 15i64
                continue
            }
            nint = (nint - 1i64)
            iwork[usize(((k - 1i64) - 1i64))] = 0i64
            if (i1 == i) {
                i1 = next
            } else {
                if (prev >= i1) {
                    iwork[usize((((2i64 * prev) - 1i64) - 1i64))] = next
                }
            }
            i = next
            pc = 16i64
            continue
        }
        if pc == 15i64 {
            pc = 14i64
        }
        if pc == 14i64 {
            prev = i
            cnt = 0i64
            s = mid
            dplus = (d[usize((1i64 - 1i64))] - s)
            if (dplus < 0.0f64) {
                cnt = (cnt + 1i64)
            }
            j = 2i64
            zc5 = (n - j) + 1i64
            while zc5 > 0i64 {
                dplus = ((d[usize((j - 1i64))] - s) - (e2[usize(((j - 1i64) - 1i64))] / dplus))
                if (dplus < 0.0f64) {
                    cnt = (cnt + 1i64)
                }
                j = j + 1i64
                zc5 = zc5 - 1i64
            }
            if (cnt <= (i - 1i64)) {
                work[usize(((k - 1i64) - 1i64))] = mid
            } else {
                work[usize((k - 1i64))] = mid
            }
            i = next
            pc = 16i64
        }
        if pc == 16i64 {
            p = p + 1i64
            zc4 = zc4 - 1i64
            pc = 12i64
            continue
        }
        if pc == 13i64 {
            iter = (iter + 1i64)
            if !(((nint > 0i64)) && ((iter <= maxitr))) {
                pc = 18i64
                continue
            }
            pc = 11i64
            continue
        }
        if pc == 18i64 {
            pc = 17i64
        }
        if pc == 17i64 {
            i = savi1
            zc6 = (ilast - i) + 1i64
            while zc6 > 0i64 {
                k = (2i64 * i)
                ii = (i - offset)
                if (iwork[usize(((k - 1i64) - 1i64))] == 0i64) {
                    w[usize((ii - 1i64))] = (0.5f64 * ((work[usize(((k - 1i64) - 1i64))] + work[usize((k - 1i64))])))
                    werr[usize((ii - 1i64))] = (work[usize((k - 1i64))] - w[usize((ii - 1i64))])
                }
                i = i + 1i64
                zc6 = zc6 - 1i64
            }
            *info_ref = info
            ret
        }
    }
}

fn dlarrr(n: i64, d: []f64, e: []f64, info_ref: *i64) {
    var info = *info_ref
    var i: i64 = 0i64
    var yesrel: bool = false
    var eps: f64 = 0.0f64
    var safmin: f64 = 0.0f64
    var smlnum: f64 = 0.0f64
    var rmin: f64 = 0.0f64
    var tmp: f64 = 0.0f64
    var tmp2: f64 = 0.0f64
    var offdig: f64 = 0.0f64
    var offdig2: f64 = 0.0f64
    var zc1: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            if (n <= 0i64) {
                info = 0i64
                *info_ref = info
                ret
            }
            info = 1i64
            safmin = 2.2250738585072014e-308f64
            eps = 2.220446049250313e-16f64
            smlnum = (safmin / eps)
            rmin = math.sqrt[f64](smlnum)
            yesrel = true
            offdig = 0.0f64
            tmp = math.sqrt[f64](math.abs[f64](d[usize((1i64 - 1i64))]))
            if (tmp < rmin) {
                yesrel = false
            }
            if !(!yesrel) {
                pc = 2i64
                continue
            }
            pc = 3i64
            continue
        }
        if pc == 2i64 {
            pc = 1i64
        }
        if pc == 1i64 {
            i = 2i64
            zc1 = (n - i) + 1i64
            pc = 4i64
        }
        if pc == 4i64 {
            if zc1 <= 0i64 {
                pc = 5i64
                continue
            }
            tmp2 = math.sqrt[f64](math.abs[f64](d[usize((i - 1i64))]))
            if (tmp2 < rmin) {
                yesrel = false
            }
            if !(!yesrel) {
                pc = 7i64
                continue
            }
            pc = 3i64
            continue
        }
        if pc == 7i64 {
            pc = 6i64
        }
        if pc == 6i64 {
            offdig2 = (math.abs[f64](e[usize(((i - 1i64) - 1i64))]) / ((tmp * tmp2)))
            if ((offdig + offdig2) >= 0.999f64) {
                yesrel = false
            }
            if !(!yesrel) {
                pc = 9i64
                continue
            }
            pc = 3i64
            continue
        }
        if pc == 9i64 {
            pc = 8i64
        }
        if pc == 8i64 {
            tmp = tmp2
            offdig = offdig2
            i = i + 1i64
            zc1 = zc1 - 1i64
            pc = 4i64
            continue
        }
        if pc == 5i64 {
            pc = 3i64
        }
        if pc == 3i64 {
            if yesrel {
                info = 0i64
                *info_ref = info
                ret
            } else {
            }
            *info_ref = info
            ret
        }
    }
}

fn dsytrd(uplo: str, n: i64, a: []f64, lda: i64, d: []f64, e: []f64, tau: []f64, work: []f64, lwork: i64, info_ref: *i64) {
    var info = *info_ref
    var lquery: bool = false
    var upper: bool = false
    var i: i64 = 0i64
    var iinfo: i64 = 0i64
    var iws: i64 = 0i64
    var j: i64 = 0i64
    var kk: i64 = 0i64
    var ldwork: i64 = 0i64
    var lwkopt: i64 = 0i64
    var nb: i64 = 0i64
    var nbmin: i64 = 0i64
    var nx: i64 = 0i64
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zs5: i64 = 0i64
    var zc6: i64 = 0i64
    info = 0i64
    upper = lbase.lsame(uplo, "U")
    lquery = ((lwork == (-1i64)))
    if ((!upper) && (!lbase.lsame(uplo, "L"))) {
        info = (-1i64)
    } else if (n < 0i64) {
        info = (-2i64)
    } else if (lda < lbase.i_max(1i64, n)) {
        info = (-4i64)
    } else if ((lwork < 1i64) && (!lquery)) {
        info = (-9i64)
    }
    if (info == 0i64) {
        nb = lbase.ilaenv(1i64, "DSYTRD", uplo, n, (-1i64), (-1i64), (-1i64))
        lwkopt = lbase.i_max(1i64, (n * nb))
        work[usize((1i64 - 1i64))] = f64(lwkopt)
    }
    if (info != 0i64) {
        *info_ref = info
        ret
    } else if lquery {
        *info_ref = info
        ret
    }
    if (n == 0i64) {
        work[usize((1i64 - 1i64))] = 1.0f64
        *info_ref = info
        ret
    }
    nx = n
    iws = 1i64
    if ((nb > 1i64) && (nb < n)) {
        nx = lbase.i_max(nb, lbase.ilaenv(3i64, "DSYTRD", uplo, n, (-1i64), (-1i64), (-1i64)))
        if (nx < n) {
            ldwork = n
            iws = (ldwork * nb)
            if (lwork < iws) {
                nb = lbase.i_max((lwork / ldwork), 1i64)
                nbmin = lbase.ilaenv(2i64, "DSYTRD", uplo, n, (-1i64), (-1i64), (-1i64))
                if (nb < nbmin) {
                    nx = n
                }
            }
        } else {
            nx = n
        }
    } else {
        nb = 1i64
    }
    if upper {
        kk = (n - (((((((n - nx) + nb) - 1i64)) / nb)) * nb))
        i = ((n - nb) + 1i64)
        zs2 = (-nb)
        zc1 = (((kk + 1i64) - i) + zs2) / zs2
        while zc1 > 0i64 {
            dlatrd(uplo, ((i + nb) - 1i64), nb, a[0usize..], lda, e[0usize..], tau[0usize..], work[0usize..], ldwork)
            lbase.dsyr2k(uplo, "No transpose", (i - 1i64), nb, (-1.0f64), lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), lda, work[0usize..], ldwork, 1.0f64, a[0usize..], lda)
            j = i
            zc3 = (((i + nb) - 1i64) - j) + 1i64
            while zc3 > 0i64 {
                a[usize(((j - 1i64) - 1i64) + (j - 1i64) * lda)] = e[usize(((j - 1i64) - 1i64))]
                d[usize((j - 1i64))] = a[usize((j - 1i64) + (j - 1i64) * lda)]
                j = j + 1i64
                zc3 = zc3 - 1i64
            }
            i = i + zs2
            zc1 = zc1 - 1i64
        }
        dsytd2(uplo, kk, a[0usize..], lda, d[0usize..], e[0usize..], tau[0usize..], &iinfo)
    } else {
        i = 1i64
        zs5 = nb
        zc4 = (((n - nx) - i) + zs5) / zs5
        while zc4 > 0i64 {
            dlatrd(uplo, ((n - i) + 1i64), nb, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), lda, lbase.sl[f64](e[0usize..], usize((i - 1i64))), lbase.sl[f64](tau[0usize..], usize((i - 1i64))), work[0usize..], ldwork)
            lbase.dsyr2k(uplo, "No transpose", (((n - i) - nb) + 1i64), nb, (-1.0f64), lbase.sl[f64](a[0usize..], usize(((i + nb) - 1i64) + (i - 1i64) * lda)), lda, lbase.sl[f64](work[0usize..], usize(((nb + 1i64) - 1i64))), ldwork, 1.0f64, lbase.sl[f64](a[0usize..], usize(((i + nb) - 1i64) + ((i + nb) - 1i64) * lda)), lda)
            j = i
            zc6 = (((i + nb) - 1i64) - j) + 1i64
            while zc6 > 0i64 {
                a[usize(((j + 1i64) - 1i64) + (j - 1i64) * lda)] = e[usize((j - 1i64))]
                d[usize((j - 1i64))] = a[usize((j - 1i64) + (j - 1i64) * lda)]
                j = j + 1i64
                zc6 = zc6 - 1i64
            }
            i = i + zs5
            zc4 = zc4 - 1i64
        }
        dsytd2(uplo, ((n - i) + 1i64), lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), lda, lbase.sl[f64](d[0usize..], usize((i - 1i64))), lbase.sl[f64](e[0usize..], usize((i - 1i64))), lbase.sl[f64](tau[0usize..], usize((i - 1i64))), &iinfo)
    }
    work[usize((1i64 - 1i64))] = f64(lwkopt)
    *info_ref = info
    ret
}

fn dlatrd(uplo: str, n: i64, nb: i64, a: []f64, lda: i64, e: []f64, tau: []f64, w: []f64, ldw: i64) {
    var i: i64 = 0i64
    var iw: i64 = 0i64
    var alpha: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
    var zc3: i64 = 0i64
    if (n <= 0i64) {
        ret
    }
    if lbase.lsame(uplo, "U") {
        i = n
        zs2 = (-1i64)
        zc1 = ((((n - nb) + 1i64) - i) + zs2) / zs2
        while zc1 > 0i64 {
            iw = ((i - n) + nb)
            if (i < n) {
                lbase.dgemv("No transpose", i, (n - i), (-1.0f64), lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, lbase.sl[f64](w[0usize..], usize((i - 1i64) + ((iw + 1i64) - 1i64) * ldw)), ldw, 1.0f64, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), 1i64)
                lbase.dgemv("No transpose", i, (n - i), (-1.0f64), lbase.sl[f64](w[0usize..], usize((1i64 - 1i64) + ((iw + 1i64) - 1i64) * ldw)), ldw, lbase.sl[f64](a[0usize..], usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, 1.0f64, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), 1i64)
            }
            if (i > 1i64) {
                lbase.dlarfg((i - 1i64), &a[usize(((i - 1i64) - 1i64) + (i - 1i64) * lda)], lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), 1i64, &tau[usize(((i - 1i64) - 1i64))])
                e[usize(((i - 1i64) - 1i64))] = a[usize(((i - 1i64) - 1i64) + (i - 1i64) * lda)]
                a[usize(((i - 1i64) - 1i64) + (i - 1i64) * lda)] = 1.0f64
                lbase.dsymv("Upper", (i - 1i64), 1.0f64, a[0usize..], lda, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), 1i64, 0.0f64, lbase.sl[f64](w[0usize..], usize((1i64 - 1i64) + (iw - 1i64) * ldw)), 1i64)
                if (i < n) {
                    lbase.dgemv("Transpose", (i - 1i64), (n - i), 1.0f64, lbase.sl[f64](w[0usize..], usize((1i64 - 1i64) + ((iw + 1i64) - 1i64) * ldw)), ldw, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), 1i64, 0.0f64, lbase.sl[f64](w[0usize..], usize(((i + 1i64) - 1i64) + (iw - 1i64) * ldw)), 1i64)
                    lbase.dgemv("No transpose", (i - 1i64), (n - i), (-1.0f64), lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, lbase.sl[f64](w[0usize..], usize(((i + 1i64) - 1i64) + (iw - 1i64) * ldw)), 1i64, 1.0f64, lbase.sl[f64](w[0usize..], usize((1i64 - 1i64) + (iw - 1i64) * ldw)), 1i64)
                    lbase.dgemv("Transpose", (i - 1i64), (n - i), 1.0f64, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), 1i64, 0.0f64, lbase.sl[f64](w[0usize..], usize(((i + 1i64) - 1i64) + (iw - 1i64) * ldw)), 1i64)
                    lbase.dgemv("No transpose", (i - 1i64), (n - i), (-1.0f64), lbase.sl[f64](w[0usize..], usize((1i64 - 1i64) + ((iw + 1i64) - 1i64) * ldw)), ldw, lbase.sl[f64](w[0usize..], usize(((i + 1i64) - 1i64) + (iw - 1i64) * ldw)), 1i64, 1.0f64, lbase.sl[f64](w[0usize..], usize((1i64 - 1i64) + (iw - 1i64) * ldw)), 1i64)
                }
                lbase.dscal((i - 1i64), tau[usize(((i - 1i64) - 1i64))], lbase.sl[f64](w[0usize..], usize((1i64 - 1i64) + (iw - 1i64) * ldw)), 1i64)
                alpha = (-((0.5f64 * tau[usize(((i - 1i64) - 1i64))]) * lbase.ddot((i - 1i64), lbase.sl[f64](w[0usize..], usize((1i64 - 1i64) + (iw - 1i64) * ldw)), 1i64, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), 1i64)))
                lbase.daxpy((i - 1i64), alpha, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), 1i64, lbase.sl[f64](w[0usize..], usize((1i64 - 1i64) + (iw - 1i64) * ldw)), 1i64)
            }
            i = i + zs2
            zc1 = zc1 - 1i64
        }
    } else {
        i = 1i64
        zc3 = (nb - i) + 1i64
        while zc3 > 0i64 {
            lbase.dgemv("No transpose", ((n - i) + 1i64), (i - 1i64), (-1.0f64), lbase.sl[f64](a[0usize..], usize((i - 1i64) + (1i64 - 1i64) * lda)), lda, lbase.sl[f64](w[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldw)), ldw, 1.0f64, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), 1i64)
            lbase.dgemv("No transpose", ((n - i) + 1i64), (i - 1i64), (-1.0f64), lbase.sl[f64](w[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldw)), ldw, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (1i64 - 1i64) * lda)), lda, 1.0f64, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), 1i64)
            if (i < n) {
                lbase.dlarfg((n - i), &a[usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)], lbase.sl[f64](a[0usize..], usize((lbase.i_min((i + 2i64), n) - 1i64) + (i - 1i64) * lda)), 1i64, &tau[usize((i - 1i64))])
                e[usize((i - 1i64))] = a[usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)]
                a[usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)] = 1.0f64
                lbase.dsymv("Lower", (n - i), 1.0f64, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64, 0.0f64, lbase.sl[f64](w[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldw)), 1i64)
                lbase.dgemv("Transpose", (n - i), (i - 1i64), 1.0f64, lbase.sl[f64](w[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * ldw)), ldw, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64, 0.0f64, lbase.sl[f64](w[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldw)), 1i64)
                lbase.dgemv("No transpose", (n - i), (i - 1i64), (-1.0f64), lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * lda)), lda, lbase.sl[f64](w[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldw)), 1i64, 1.0f64, lbase.sl[f64](w[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldw)), 1i64)
                lbase.dgemv("Transpose", (n - i), (i - 1i64), 1.0f64, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * lda)), lda, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64, 0.0f64, lbase.sl[f64](w[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldw)), 1i64)
                lbase.dgemv("No transpose", (n - i), (i - 1i64), (-1.0f64), lbase.sl[f64](w[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * ldw)), ldw, lbase.sl[f64](w[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldw)), 1i64, 1.0f64, lbase.sl[f64](w[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldw)), 1i64)
                lbase.dscal((n - i), tau[usize((i - 1i64))], lbase.sl[f64](w[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldw)), 1i64)
                alpha = (-((0.5f64 * tau[usize((i - 1i64))]) * lbase.ddot((n - i), lbase.sl[f64](w[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldw)), 1i64, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64)))
                lbase.daxpy((n - i), alpha, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64, lbase.sl[f64](w[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldw)), 1i64)
            }
            i = i + 1i64
            zc3 = zc3 - 1i64
        }
    }
    ret
}

fn dsterf(n: i64, d: []f64, e: []f64, info_ref: *i64) {
    var info = *info_ref
    var i: i64 = 0i64
    var iscale: i64 = 0i64
    var jtot: i64 = 0i64
    var l: i64 = 0i64
    var l1: i64 = 0i64
    var lend: i64 = 0i64
    var lendsv: i64 = 0i64
    var lsv: i64 = 0i64
    var m: i64 = 0i64
    var nmaxit: i64 = 0i64
    var alpha: f64 = 0.0f64
    var anorm: f64 = 0.0f64
    var bb: f64 = 0.0f64
    var c: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var eps2: f64 = 0.0f64
    var gamma: f64 = 0.0f64
    var oldc: f64 = 0.0f64
    var oldgam: f64 = 0.0f64
    var p: f64 = 0.0f64
    var r: f64 = 0.0f64
    var rt1: f64 = 0.0f64
    var rt2: f64 = 0.0f64
    var rte: f64 = 0.0f64
    var s: f64 = 0.0f64
    var safmax: f64 = 0.0f64
    var safmin: f64 = 0.0f64
    var sigma: f64 = 0.0f64
    var ssfmax: f64 = 0.0f64
    var ssfmin: f64 = 0.0f64
    var rmax: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zs5: i64 = 0i64
    var zc6: i64 = 0i64
    var zs7: i64 = 0i64
    var zc8: i64 = 0i64
    var zc9: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            if (n < 0i64) {
                info = (-1i64)
                *info_ref = info
                ret
            }
            if (n <= 1i64) {
                *info_ref = info
                ret
            }
            eps = 1.1102230246251565e-16f64
            eps2 = (eps * eps)
            safmin = 2.2250738585072014e-308f64
            safmax = (1.0f64 / safmin)
            ssfmax = (math.sqrt[f64](safmax) / 3.0f64)
            ssfmin = (math.sqrt[f64](safmin) / eps2)
            rmax = 1.7976931348623157e308f64
            nmaxit = (n * 30i64)
            sigma = 0.0f64
            jtot = 0i64
            l1 = 1i64
            pc = 1i64
        }
        if pc == 1i64 {
            if !(l1 > n) {
                pc = 3i64
                continue
            }
            pc = 4i64
            continue
        }
        if pc == 3i64 {
            pc = 2i64
        }
        if pc == 2i64 {
            if (l1 > 1i64) {
                e[usize(((l1 - 1i64) - 1i64))] = 0.0f64
            }
            m = l1
            zc1 = ((n - 1i64) - m) + 1i64
            pc = 5i64
        }
        if pc == 5i64 {
            if zc1 <= 0i64 {
                pc = 6i64
                continue
            }
            if !(math.abs[f64](e[usize((m - 1i64))]) <= (((math.sqrt[f64](math.abs[f64](d[usize((m - 1i64))])) * math.sqrt[f64](math.abs[f64](d[usize(((m + 1i64) - 1i64))])))) * eps)) {
                pc = 8i64
                continue
            }
            e[usize((m - 1i64))] = 0.0f64
            pc = 9i64
            continue
        }
        if pc == 8i64 {
            pc = 7i64
        }
        if pc == 7i64 {
            m = m + 1i64
            zc1 = zc1 - 1i64
            pc = 5i64
            continue
        }
        if pc == 6i64 {
            m = n
            pc = 9i64
        }
        if pc == 9i64 {
            l = l1
            lsv = l
            lend = m
            lendsv = lend
            l1 = (m + 1i64)
            if !(lend == l) {
                pc = 11i64
                continue
            }
            pc = 1i64
            continue
        }
        if pc == 11i64 {
            pc = 10i64
        }
        if pc == 10i64 {
            anorm = lbase.dlanst("M", ((lend - l) + 1i64), lbase.sl[f64](d[0usize..], usize((l - 1i64))), lbase.sl[f64](e[0usize..], usize((l - 1i64))))
            iscale = 0i64
            if !(anorm == 0.0f64) {
                pc = 13i64
                continue
            }
            pc = 1i64
            continue
        }
        if pc == 13i64 {
            pc = 12i64
        }
        if pc == 12i64 {
            if ((anorm > ssfmax)) {
                iscale = 1i64
                lbase.dlascl("G", 0i64, 0i64, anorm, ssfmax, ((lend - l) + 1i64), 1i64, lbase.sl[f64](d[0usize..], usize((l - 1i64))), n, &info)
                lbase.dlascl("G", 0i64, 0i64, anorm, ssfmax, (lend - l), 1i64, lbase.sl[f64](e[0usize..], usize((l - 1i64))), n, &info)
            } else if (anorm < ssfmin) {
                iscale = 2i64
                lbase.dlascl("G", 0i64, 0i64, anorm, ssfmin, ((lend - l) + 1i64), 1i64, lbase.sl[f64](d[0usize..], usize((l - 1i64))), n, &info)
                lbase.dlascl("G", 0i64, 0i64, anorm, ssfmin, (lend - l), 1i64, lbase.sl[f64](e[0usize..], usize((l - 1i64))), n, &info)
            }
            i = l
            zc2 = ((lend - 1i64) - i) + 1i64
            while zc2 > 0i64 {
                e[usize((i - 1i64))] = ((e[usize((i - 1i64))]) * (e[usize((i - 1i64))]))
                i = i + 1i64
                zc2 = zc2 - 1i64
            }
            if (math.abs[f64](d[usize((lend - 1i64))]) < math.abs[f64](d[usize((l - 1i64))])) {
                lend = lsv
                l = lendsv
            }
            if !(lend >= l) {
                pc = 15i64
                continue
            }
            pc = 16i64
        }
        if pc == 16i64 {
            if !(l != lend) {
                pc = 18i64
                continue
            }
            m = l
            zc3 = ((lend - 1i64) - m) + 1i64
            pc = 19i64
        }
        if pc == 19i64 {
            if zc3 <= 0i64 {
                pc = 20i64
                continue
            }
            if !(math.abs[f64](e[usize((m - 1i64))]) <= (eps2 * math.abs[f64]((d[usize((m - 1i64))] * d[usize(((m + 1i64) - 1i64))])))) {
                pc = 22i64
                continue
            }
            pc = 23i64
            continue
        }
        if pc == 22i64 {
            pc = 21i64
        }
        if pc == 21i64 {
            m = m + 1i64
            zc3 = zc3 - 1i64
            pc = 19i64
            continue
        }
        if pc == 20i64 {
            pc = 17i64
            continue
        }
        if pc == 18i64 {
            pc = 17i64
        }
        if pc == 17i64 {
            m = lend
            pc = 23i64
        }
        if pc == 23i64 {
            if (m < lend) {
                e[usize((m - 1i64))] = 0.0f64
            }
            p = d[usize((l - 1i64))]
            if !(m == l) {
                pc = 25i64
                continue
            }
            pc = 26i64
            continue
        }
        if pc == 25i64 {
            pc = 24i64
        }
        if pc == 24i64 {
            if !(m == (l + 1i64)) {
                pc = 28i64
                continue
            }
            rte = math.sqrt[f64](e[usize((l - 1i64))])
            lbase.dlae2(d[usize((l - 1i64))], rte, d[usize(((l + 1i64) - 1i64))], &rt1, &rt2)
            d[usize((l - 1i64))] = rt1
            d[usize(((l + 1i64) - 1i64))] = rt2
            e[usize((l - 1i64))] = 0.0f64
            l = (l + 2i64)
            if !(l <= lend) {
                pc = 30i64
                continue
            }
            pc = 16i64
            continue
        }
        if pc == 30i64 {
            pc = 29i64
        }
        if pc == 29i64 {
            pc = 31i64
            continue
        }
        if pc == 28i64 {
            pc = 27i64
        }
        if pc == 27i64 {
            if !(jtot == nmaxit) {
                pc = 33i64
                continue
            }
            pc = 31i64
            continue
        }
        if pc == 33i64 {
            pc = 32i64
        }
        if pc == 32i64 {
            jtot = (jtot + 1i64)
            rte = math.sqrt[f64](e[usize((l - 1i64))])
            sigma = (((d[usize(((l + 1i64) - 1i64))] - p)) / ((2.0f64 * rte)))
            r = lbase.dlapy2(sigma, 1.0f64)
            sigma = (p - ((rte / ((sigma + lbase.f_sign(r, sigma))))))
            c = 1.0f64
            s = 0.0f64
            gamma = (d[usize((m - 1i64))] - sigma)
            p = (gamma * gamma)
            i = (m - 1i64)
            zs5 = (-1i64)
            zc4 = ((l - i) + zs5) / zs5
            while zc4 > 0i64 {
                bb = e[usize((i - 1i64))]
                r = (p + bb)
                if (i != (m - 1i64)) {
                    e[usize(((i + 1i64) - 1i64))] = (s * r)
                }
                oldc = c
                c = (p / r)
                s = (bb / r)
                oldgam = gamma
                alpha = d[usize((i - 1i64))]
                gamma = ((c * ((alpha - sigma))) - (s * oldgam))
                d[usize(((i + 1i64) - 1i64))] = (oldgam + ((alpha - gamma)))
                if (c != 0.0f64) {
                    p = (((gamma * gamma)) / c)
                } else {
                    p = (oldc * bb)
                }
                i = i + zs5
                zc4 = zc4 - 1i64
            }
            e[usize((l - 1i64))] = (s * p)
            d[usize((l - 1i64))] = (sigma + gamma)
            pc = 16i64
            continue
        }
        if pc == 26i64 {
            d[usize((l - 1i64))] = p
            l = (l + 1i64)
            if !(l <= lend) {
                pc = 35i64
                continue
            }
            pc = 16i64
            continue
        }
        if pc == 35i64 {
            pc = 34i64
        }
        if pc == 34i64 {
            pc = 31i64
            continue
        }
        if pc == 15i64 {
            pc = 36i64
        }
        if pc == 36i64 {
            m = l
            zs7 = (-1i64)
            zc6 = (((lend + 1i64) - m) + zs7) / zs7
            pc = 37i64
        }
        if pc == 37i64 {
            if zc6 <= 0i64 {
                pc = 38i64
                continue
            }
            if !(math.abs[f64](e[usize(((m - 1i64) - 1i64))]) <= (eps2 * math.abs[f64]((d[usize((m - 1i64))] * d[usize(((m - 1i64) - 1i64))])))) {
                pc = 40i64
                continue
            }
            pc = 41i64
            continue
        }
        if pc == 40i64 {
            pc = 39i64
        }
        if pc == 39i64 {
            m = m + zs7
            zc6 = zc6 - 1i64
            pc = 37i64
            continue
        }
        if pc == 38i64 {
            m = lend
            pc = 41i64
        }
        if pc == 41i64 {
            if (m > lend) {
                e[usize(((m - 1i64) - 1i64))] = 0.0f64
            }
            p = d[usize((l - 1i64))]
            if !(m == l) {
                pc = 43i64
                continue
            }
            pc = 44i64
            continue
        }
        if pc == 43i64 {
            pc = 42i64
        }
        if pc == 42i64 {
            if !(m == (l - 1i64)) {
                pc = 46i64
                continue
            }
            rte = math.sqrt[f64](e[usize(((l - 1i64) - 1i64))])
            lbase.dlae2(d[usize((l - 1i64))], rte, d[usize(((l - 1i64) - 1i64))], &rt1, &rt2)
            d[usize((l - 1i64))] = rt1
            d[usize(((l - 1i64) - 1i64))] = rt2
            e[usize(((l - 1i64) - 1i64))] = 0.0f64
            l = (l - 2i64)
            if !(l >= lend) {
                pc = 48i64
                continue
            }
            pc = 36i64
            continue
        }
        if pc == 48i64 {
            pc = 47i64
        }
        if pc == 47i64 {
            pc = 31i64
            continue
        }
        if pc == 46i64 {
            pc = 45i64
        }
        if pc == 45i64 {
            if !(jtot == nmaxit) {
                pc = 50i64
                continue
            }
            pc = 31i64
            continue
        }
        if pc == 50i64 {
            pc = 49i64
        }
        if pc == 49i64 {
            jtot = (jtot + 1i64)
            rte = math.sqrt[f64](e[usize(((l - 1i64) - 1i64))])
            sigma = (((d[usize(((l - 1i64) - 1i64))] - p)) / ((2.0f64 * rte)))
            r = lbase.dlapy2(sigma, 1.0f64)
            sigma = (p - ((rte / ((sigma + lbase.f_sign(r, sigma))))))
            c = 1.0f64
            s = 0.0f64
            gamma = (d[usize((m - 1i64))] - sigma)
            p = (gamma * gamma)
            i = m
            zc8 = ((l - 1i64) - i) + 1i64
            while zc8 > 0i64 {
                bb = e[usize((i - 1i64))]
                r = (p + bb)
                if (i != m) {
                    e[usize(((i - 1i64) - 1i64))] = (s * r)
                }
                oldc = c
                c = (p / r)
                s = (bb / r)
                oldgam = gamma
                alpha = d[usize(((i + 1i64) - 1i64))]
                gamma = ((c * ((alpha - sigma))) - (s * oldgam))
                d[usize((i - 1i64))] = (oldgam + ((alpha - gamma)))
                if (c != 0.0f64) {
                    p = (((gamma * gamma)) / c)
                } else {
                    p = (oldc * bb)
                }
                i = i + 1i64
                zc8 = zc8 - 1i64
            }
            e[usize(((l - 1i64) - 1i64))] = (s * p)
            d[usize((l - 1i64))] = (sigma + gamma)
            pc = 36i64
            continue
        }
        if pc == 44i64 {
            d[usize((l - 1i64))] = p
            l = (l - 1i64)
            if !(l >= lend) {
                pc = 52i64
                continue
            }
            pc = 36i64
            continue
        }
        if pc == 52i64 {
            pc = 51i64
        }
        if pc == 51i64 {
            pc = 31i64
            continue
        }
        if pc == 14i64 {
            pc = 31i64
        }
        if pc == 31i64 {
            if (iscale == 1i64) {
                lbase.dlascl("G", 0i64, 0i64, ssfmax, anorm, ((lendsv - lsv) + 1i64), 1i64, lbase.sl[f64](d[0usize..], usize((lsv - 1i64))), n, &info)
            }
            if (iscale == 2i64) {
                lbase.dlascl("G", 0i64, 0i64, ssfmin, anorm, ((lendsv - lsv) + 1i64), 1i64, lbase.sl[f64](d[0usize..], usize((lsv - 1i64))), n, &info)
            }
            if !(jtot < nmaxit) {
                pc = 54i64
                continue
            }
            pc = 1i64
            continue
        }
        if pc == 54i64 {
            pc = 53i64
        }
        if pc == 53i64 {
            i = 1i64
            zc9 = ((n - 1i64) - i) + 1i64
            while zc9 > 0i64 {
                if (e[usize((i - 1i64))] != 0.0f64) {
                    info = (info + 1i64)
                }
                i = i + 1i64
                zc9 = zc9 - 1i64
            }
            pc = 55i64
            continue
        }
        if pc == 4i64 {
            lbase.dlasrt("I", n, d[0usize..], &info)
            pc = 55i64
        }
        if pc == 55i64 {
            *info_ref = info
            ret
        }
    }
}

fn dstebz(range: str, order: str, n: i64, vl: f64, vu: f64, il: i64, iu: i64, abstol: f64, d: []f64, e: []f64, m_ref: *i64, nsplit_ref: *i64, w: []f64, iblock: []i64, isplit: []i64, work: []f64, iwork: []i64, info_ref: *i64) {
    var m = *m_ref
    var nsplit = *nsplit_ref
    var info = *info_ref
    var ncnvrg: bool = false
    var toofew: bool = false
    var ib: i64 = 0i64
    var ibegin: i64 = 0i64
    var idiscl: i64 = 0i64
    var idiscu: i64 = 0i64
    var ie: i64 = 0i64
    var iend: i64 = 0i64
    var iinfo: i64 = 0i64
    var im: i64 = 0i64
    var in_: i64 = 0i64
    var ioff: i64 = 0i64
    var iorder: i64 = 0i64
    var iout: i64 = 0i64
    var irange: i64 = 0i64
    var itmax: i64 = 0i64
    var itmp1: i64 = 0i64
    var iw: i64 = 0i64
    var iwoff: i64 = 0i64
    var j: i64 = 0i64
    var jb: i64 = 0i64
    var jdisc: i64 = 0i64
    var je: i64 = 0i64
    var nb: i64 = 0i64
    var nwl: i64 = 0i64
    var nwu: i64 = 0i64
    var atoli: f64 = 0.0f64
    var bnorm: f64 = 0.0f64
    var gl: f64 = 0.0f64
    var gu: f64 = 0.0f64
    var pivmin: f64 = 0.0f64
    var rtoli: f64 = 0.0f64
    var safemn: f64 = 0.0f64
    var tmp1: f64 = 0.0f64
    var tmp2: f64 = 0.0f64
    var tnorm: f64 = 0.0f64
    var ulp: f64 = 0.0f64
    var wkill: f64 = 0.0f64
    var wl: f64 = 0.0f64
    var wlu: f64 = 0.0f64
    var wu: f64 = 0.0f64
    var wul: f64 = 0.0f64
    var idumma: [1]i64 = zero
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    var zc6: i64 = 0i64
    var zc7: i64 = 0i64
    var zc8: i64 = 0i64
    var zc9: i64 = 0i64
    var zc10: i64 = 0i64
    var zc11: i64 = 0i64
    var zc12: i64 = 0i64
    var zc13: i64 = 0i64
    var zc14: i64 = 0i64
    var zc15: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            if lbase.lsame(range, "A") {
                irange = 1i64
            } else if lbase.lsame(range, "V") {
                irange = 2i64
            } else if lbase.lsame(range, "I") {
                irange = 3i64
            } else {
                irange = 0i64
            }
            if lbase.lsame(order, "B") {
                iorder = 2i64
            } else if lbase.lsame(order, "E") {
                iorder = 1i64
            } else {
                iorder = 0i64
            }
            if (irange <= 0i64) {
                info = (-1i64)
            } else if (iorder <= 0i64) {
                info = (-2i64)
            } else if (n < 0i64) {
                info = (-3i64)
            } else if (irange == 2i64) {
                if (vl >= vu) {
                    info = (-5i64)
                }
            } else if ((irange == 3i64) && (((il < 1i64) || (il > lbase.i_max(1i64, n))))) {
                info = (-6i64)
            } else if ((irange == 3i64) && (((iu < lbase.i_min(n, il)) || (iu > n)))) {
                info = (-7i64)
            }
            if (info != 0i64) {
                *m_ref = m
                *nsplit_ref = nsplit
                *info_ref = info
                ret
            }
            info = 0i64
            ncnvrg = false
            toofew = false
            m = 0i64
            if (n == 0i64) {
                *m_ref = m
                *nsplit_ref = nsplit
                *info_ref = info
                ret
            }
            if (((irange == 3i64) && (il == 1i64)) && (iu == n)) {
                irange = 1i64
            }
            safemn = 2.2250738585072014e-308f64
            ulp = 2.220446049250313e-16f64
            rtoli = (ulp * 2.0f64)
            nb = lbase.ilaenv(1i64, "DSTEBZ", " ", n, (-1i64), (-1i64), (-1i64))
            if (nb <= 1i64) {
                nb = 0i64
            }
            if (n == 1i64) {
                nsplit = 1i64
                isplit[usize((1i64 - 1i64))] = 1i64
                if ((irange == 2i64) && (((vl >= d[usize((1i64 - 1i64))]) || (vu < d[usize((1i64 - 1i64))])))) {
                    m = 0i64
                } else {
                    w[usize((1i64 - 1i64))] = d[usize((1i64 - 1i64))]
                    iblock[usize((1i64 - 1i64))] = 1i64
                    m = 1i64
                }
                *m_ref = m
                *nsplit_ref = nsplit
                *info_ref = info
                ret
            }
            nsplit = 1i64
            work[usize((n - 1i64))] = 0.0f64
            pivmin = 1.0f64
            j = 2i64
            zc1 = (n - j) + 1i64
            while zc1 > 0i64 {
                tmp1 = ((e[usize(((j - 1i64) - 1i64))]) * (e[usize(((j - 1i64) - 1i64))]))
                if (((math.abs[f64]((d[usize((j - 1i64))] * d[usize(((j - 1i64) - 1i64))])) * (ulp * ulp)) + safemn) > tmp1) {
                    isplit[usize((nsplit - 1i64))] = (j - 1i64)
                    nsplit = (nsplit + 1i64)
                    work[usize(((j - 1i64) - 1i64))] = 0.0f64
                } else {
                    work[usize(((j - 1i64) - 1i64))] = tmp1
                    pivmin = lbase.f_max(pivmin, tmp1)
                }
                j = j + 1i64
                zc1 = zc1 - 1i64
            }
            isplit[usize((nsplit - 1i64))] = n
            pivmin = (pivmin * safemn)
            if (irange == 3i64) {
                gu = d[usize((1i64 - 1i64))]
                gl = d[usize((1i64 - 1i64))]
                tmp1 = 0.0f64
                j = 1i64
                zc2 = ((n - 1i64) - j) + 1i64
                while zc2 > 0i64 {
                    tmp2 = math.sqrt[f64](work[usize((j - 1i64))])
                    gu = lbase.f_max(gu, ((d[usize((j - 1i64))] + tmp1) + tmp2))
                    gl = lbase.f_min(gl, ((d[usize((j - 1i64))] - tmp1) - tmp2))
                    tmp1 = tmp2
                    j = j + 1i64
                    zc2 = zc2 - 1i64
                }
                gu = lbase.f_max(gu, (d[usize((n - 1i64))] + tmp1))
                gl = lbase.f_min(gl, (d[usize((n - 1i64))] - tmp1))
                tnorm = lbase.f_max(math.abs[f64](gl), math.abs[f64](gu))
                gl = ((gl - (((2.1f64 * tnorm) * ulp) * f64(n))) - ((2.1f64 * 2.0f64) * pivmin))
                gu = ((gu + (((2.1f64 * tnorm) * ulp) * f64(n))) + (2.1f64 * pivmin))
                itmax = (i64((((math.log[f64]((tnorm + pivmin)) - math.log[f64](pivmin))) / math.log[f64](2.0f64))) + 2i64)
                if (abstol <= 0.0f64) {
                    atoli = (ulp * tnorm)
                } else {
                    atoli = abstol
                }
                work[usize(((n + 1i64) - 1i64))] = gl
                work[usize(((n + 2i64) - 1i64))] = gl
                work[usize(((n + 3i64) - 1i64))] = gu
                work[usize(((n + 4i64) - 1i64))] = gu
                work[usize(((n + 5i64) - 1i64))] = gl
                work[usize(((n + 6i64) - 1i64))] = gu
                iwork[usize((1i64 - 1i64))] = (-1i64)
                iwork[usize((2i64 - 1i64))] = (-1i64)
                iwork[usize((3i64 - 1i64))] = (n + 1i64)
                iwork[usize((4i64 - 1i64))] = (n + 1i64)
                iwork[usize((5i64 - 1i64))] = (il - 1i64)
                iwork[usize((6i64 - 1i64))] = iu
                dlaebz(3i64, itmax, n, 2i64, 2i64, nb, atoli, rtoli, pivmin, d[0usize..], e[0usize..], work[0usize..], lbase.sl[i64](iwork[0usize..], usize((5i64 - 1i64))), lbase.sl[f64](work[0usize..], usize(((n + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize(((n + 5i64) - 1i64))), &iout, iwork[0usize..], w[0usize..], iblock[0usize..], &iinfo)
                if (iwork[usize((6i64 - 1i64))] == iu) {
                    wl = work[usize(((n + 1i64) - 1i64))]
                    wlu = work[usize(((n + 3i64) - 1i64))]
                    nwl = iwork[usize((1i64 - 1i64))]
                    wu = work[usize(((n + 4i64) - 1i64))]
                    wul = work[usize(((n + 2i64) - 1i64))]
                    nwu = iwork[usize((4i64 - 1i64))]
                } else {
                    wl = work[usize(((n + 2i64) - 1i64))]
                    wlu = work[usize(((n + 4i64) - 1i64))]
                    nwl = iwork[usize((2i64 - 1i64))]
                    wu = work[usize(((n + 3i64) - 1i64))]
                    wul = work[usize(((n + 1i64) - 1i64))]
                    nwu = iwork[usize((3i64 - 1i64))]
                }
                if ((((nwl < 0i64) || (nwl >= n)) || (nwu < 1i64)) || (nwu > n)) {
                    info = 4i64
                    *m_ref = m
                    *nsplit_ref = nsplit
                    *info_ref = info
                    ret
                }
            } else {
                tnorm = lbase.f_max((math.abs[f64](d[usize((1i64 - 1i64))]) + math.abs[f64](e[usize((1i64 - 1i64))])), (math.abs[f64](d[usize((n - 1i64))]) + math.abs[f64](e[usize(((n - 1i64) - 1i64))])))
                j = 2i64
                zc3 = ((n - 1i64) - j) + 1i64
                while zc3 > 0i64 {
                    tnorm = lbase.f_max(tnorm, ((math.abs[f64](d[usize((j - 1i64))]) + math.abs[f64](e[usize(((j - 1i64) - 1i64))])) + math.abs[f64](e[usize((j - 1i64))])))
                    j = j + 1i64
                    zc3 = zc3 - 1i64
                }
                if (abstol <= 0.0f64) {
                    atoli = (ulp * tnorm)
                } else {
                    atoli = abstol
                }
                if (irange == 2i64) {
                    wl = vl
                    wu = vu
                } else {
                    wl = 0.0f64
                    wu = 0.0f64
                }
            }
            m = 0i64
            iend = 0i64
            info = 0i64
            nwl = 0i64
            nwu = 0i64
            jb = 1i64
            zc4 = (nsplit - jb) + 1i64
            pc = 1i64
        }
        if pc == 1i64 {
            if zc4 <= 0i64 {
                pc = 2i64
                continue
            }
            ioff = iend
            ibegin = (ioff + 1i64)
            iend = isplit[usize((jb - 1i64))]
            in_ = (iend - ioff)
            if !(in_ == 1i64) {
                pc = 4i64
                continue
            }
            if ((irange == 1i64) || (wl >= (d[usize((ibegin - 1i64))] - pivmin))) {
                nwl = (nwl + 1i64)
            }
            if ((irange == 1i64) || (wu >= (d[usize((ibegin - 1i64))] - pivmin))) {
                nwu = (nwu + 1i64)
            }
            if ((irange == 1i64) || (((wl < (d[usize((ibegin - 1i64))] - pivmin)) && (wu >= (d[usize((ibegin - 1i64))] - pivmin))))) {
                m = (m + 1i64)
                w[usize((m - 1i64))] = d[usize((ibegin - 1i64))]
                iblock[usize((m - 1i64))] = jb
            }
            pc = 3i64
            continue
        }
        if pc == 4i64 {
            gu = d[usize((ibegin - 1i64))]
            gl = d[usize((ibegin - 1i64))]
            tmp1 = 0.0f64
            j = ibegin
            zc5 = ((iend - 1i64) - j) + 1i64
            while zc5 > 0i64 {
                tmp2 = math.abs[f64](e[usize((j - 1i64))])
                gu = lbase.f_max(gu, ((d[usize((j - 1i64))] + tmp1) + tmp2))
                gl = lbase.f_min(gl, ((d[usize((j - 1i64))] - tmp1) - tmp2))
                tmp1 = tmp2
                j = j + 1i64
                zc5 = zc5 - 1i64
            }
            gu = lbase.f_max(gu, (d[usize((iend - 1i64))] + tmp1))
            gl = lbase.f_min(gl, (d[usize((iend - 1i64))] - tmp1))
            bnorm = lbase.f_max(math.abs[f64](gl), math.abs[f64](gu))
            gl = ((gl - (((2.1f64 * bnorm) * ulp) * f64(in_))) - (2.1f64 * pivmin))
            gu = ((gu + (((2.1f64 * bnorm) * ulp) * f64(in_))) + (2.1f64 * pivmin))
            if (abstol <= 0.0f64) {
                atoli = (ulp * lbase.f_max(math.abs[f64](gl), math.abs[f64](gu)))
            } else {
                atoli = abstol
            }
            if !(irange > 1i64) {
                pc = 6i64
                continue
            }
            if !(gu < wl) {
                pc = 8i64
                continue
            }
            nwl = (nwl + in_)
            nwu = (nwu + in_)
            pc = 9i64
            continue
        }
        if pc == 8i64 {
            pc = 7i64
        }
        if pc == 7i64 {
            gl = lbase.f_max(gl, wl)
            gu = lbase.f_min(gu, wu)
            if !(gl >= gu) {
                pc = 11i64
                continue
            }
            pc = 9i64
            continue
        }
        if pc == 11i64 {
            pc = 10i64
        }
        if pc == 10i64 {
            pc = 5i64
            continue
        }
        if pc == 6i64 {
            pc = 5i64
        }
        if pc == 5i64 {
            work[usize(((n + 1i64) - 1i64))] = gl
            work[usize((((n + in_) + 1i64) - 1i64))] = gu
            dlaebz(1i64, 0i64, in_, in_, 1i64, nb, atoli, rtoli, pivmin, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](e[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](work[0usize..], usize((ibegin - 1i64))), idumma[0usize..], lbase.sl[f64](work[0usize..], usize(((n + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize((((n + (2i64 * in_)) + 1i64) - 1i64))), &im, iwork[0usize..], lbase.sl[f64](w[0usize..], usize(((m + 1i64) - 1i64))), lbase.sl[i64](iblock[0usize..], usize(((m + 1i64) - 1i64))), &iinfo)
            nwl = (nwl + iwork[usize((1i64 - 1i64))])
            nwu = (nwu + iwork[usize(((in_ + 1i64) - 1i64))])
            iwoff = (m - iwork[usize((1i64 - 1i64))])
            itmax = (i64((((math.log[f64](((gu - gl) + pivmin)) - math.log[f64](pivmin))) / math.log[f64](2.0f64))) + 2i64)
            dlaebz(2i64, itmax, in_, in_, 1i64, nb, atoli, rtoli, pivmin, lbase.sl[f64](d[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](e[0usize..], usize((ibegin - 1i64))), lbase.sl[f64](work[0usize..], usize((ibegin - 1i64))), idumma[0usize..], lbase.sl[f64](work[0usize..], usize(((n + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize((((n + (2i64 * in_)) + 1i64) - 1i64))), &iout, iwork[0usize..], lbase.sl[f64](w[0usize..], usize(((m + 1i64) - 1i64))), lbase.sl[i64](iblock[0usize..], usize(((m + 1i64) - 1i64))), &iinfo)
            j = 1i64
            zc6 = (iout - j) + 1i64
            while zc6 > 0i64 {
                tmp1 = (0.5f64 * ((work[usize(((j + n) - 1i64))] + work[usize((((j + in_) + n) - 1i64))])))
                if (j > (iout - iinfo)) {
                    ncnvrg = true
                    ib = (-jb)
                } else {
                    ib = jb
                }
                je = ((iwork[usize((j - 1i64))] + 1i64) + iwoff)
                zc7 = ((iwork[usize(((j + in_) - 1i64))] + iwoff) - je) + 1i64
                while zc7 > 0i64 {
                    w[usize((je - 1i64))] = tmp1
                    iblock[usize((je - 1i64))] = ib
                    je = je + 1i64
                    zc7 = zc7 - 1i64
                }
                j = j + 1i64
                zc6 = zc6 - 1i64
            }
            m = (m + im)
            pc = 3i64
            continue
        }
        if pc == 3i64 {
            pc = 9i64
        }
        if pc == 9i64 {
            jb = jb + 1i64
            zc4 = zc4 - 1i64
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            if (irange == 3i64) {
                im = 0i64
                idiscl = ((il - 1i64) - nwl)
                idiscu = (nwu - iu)
                if ((idiscl > 0i64) || (idiscu > 0i64)) {
                    je = 1i64
                    zc8 = (m - je) + 1i64
                    while zc8 > 0i64 {
                        if ((w[usize((je - 1i64))] <= wlu) && (idiscl > 0i64)) {
                            idiscl = (idiscl - 1i64)
                        } else if ((w[usize((je - 1i64))] >= wul) && (idiscu > 0i64)) {
                            idiscu = (idiscu - 1i64)
                        } else {
                            im = (im + 1i64)
                            w[usize((im - 1i64))] = w[usize((je - 1i64))]
                            iblock[usize((im - 1i64))] = iblock[usize((je - 1i64))]
                        }
                        je = je + 1i64
                        zc8 = zc8 - 1i64
                    }
                    m = im
                }
                if ((idiscl > 0i64) || (idiscu > 0i64)) {
                    if (idiscl > 0i64) {
                        wkill = wu
                        jdisc = 1i64
                        zc9 = (idiscl - jdisc) + 1i64
                        while zc9 > 0i64 {
                            iw = 0i64
                            je = 1i64
                            zc10 = (m - je) + 1i64
                            while zc10 > 0i64 {
                                if ((iblock[usize((je - 1i64))] != 0i64) && (((w[usize((je - 1i64))] < wkill) || (iw == 0i64)))) {
                                    iw = je
                                    wkill = w[usize((je - 1i64))]
                                }
                                je = je + 1i64
                                zc10 = zc10 - 1i64
                            }
                            iblock[usize((iw - 1i64))] = 0i64
                            jdisc = jdisc + 1i64
                            zc9 = zc9 - 1i64
                        }
                    }
                    if (idiscu > 0i64) {
                        wkill = wl
                        jdisc = 1i64
                        zc11 = (idiscu - jdisc) + 1i64
                        while zc11 > 0i64 {
                            iw = 0i64
                            je = 1i64
                            zc12 = (m - je) + 1i64
                            while zc12 > 0i64 {
                                if ((iblock[usize((je - 1i64))] != 0i64) && (((w[usize((je - 1i64))] > wkill) || (iw == 0i64)))) {
                                    iw = je
                                    wkill = w[usize((je - 1i64))]
                                }
                                je = je + 1i64
                                zc12 = zc12 - 1i64
                            }
                            iblock[usize((iw - 1i64))] = 0i64
                            jdisc = jdisc + 1i64
                            zc11 = zc11 - 1i64
                        }
                    }
                    im = 0i64
                    je = 1i64
                    zc13 = (m - je) + 1i64
                    while zc13 > 0i64 {
                        if (iblock[usize((je - 1i64))] != 0i64) {
                            im = (im + 1i64)
                            w[usize((im - 1i64))] = w[usize((je - 1i64))]
                            iblock[usize((im - 1i64))] = iblock[usize((je - 1i64))]
                        }
                        je = je + 1i64
                        zc13 = zc13 - 1i64
                    }
                    m = im
                }
                if ((idiscl < 0i64) || (idiscu < 0i64)) {
                    toofew = true
                }
            }
            if ((iorder == 1i64) && (nsplit > 1i64)) {
                je = 1i64
                zc14 = ((m - 1i64) - je) + 1i64
                while zc14 > 0i64 {
                    ie = 0i64
                    tmp1 = w[usize((je - 1i64))]
                    j = (je + 1i64)
                    zc15 = (m - j) + 1i64
                    while zc15 > 0i64 {
                        if (w[usize((j - 1i64))] < tmp1) {
                            ie = j
                            tmp1 = w[usize((j - 1i64))]
                        }
                        j = j + 1i64
                        zc15 = zc15 - 1i64
                    }
                    if (ie != 0i64) {
                        itmp1 = iblock[usize((ie - 1i64))]
                        w[usize((ie - 1i64))] = w[usize((je - 1i64))]
                        iblock[usize((ie - 1i64))] = iblock[usize((je - 1i64))]
                        w[usize((je - 1i64))] = tmp1
                        iblock[usize((je - 1i64))] = itmp1
                    }
                    je = je + 1i64
                    zc14 = zc14 - 1i64
                }
            }
            info = 0i64
            if ncnvrg {
                info = (info + 1i64)
            }
            if toofew {
                info = (info + 2i64)
            }
            *m_ref = m
            *nsplit_ref = nsplit
            *info_ref = info
            ret
        }
    }
}

fn dstein(n: i64, d: []f64, e: []f64, m: i64, w: []f64, iblock: []i64, isplit: []i64, z: []f64, ldz: i64, work: []f64, iwork: []i64, ifail: []i64, info_ref: *i64) {
    var info = *info_ref
    var b1: i64 = 0i64
    var blksiz: i64 = 0i64
    var bn: i64 = 0i64
    var gpind: i64 = 0i64
    var i: i64 = 0i64
    var iinfo: i64 = 0i64
    var indrv1: i64 = 0i64
    var indrv2: i64 = 0i64
    var indrv3: i64 = 0i64
    var indrv4: i64 = 0i64
    var indrv5: i64 = 0i64
    var its: i64 = 0i64
    var j: i64 = 0i64
    var j1: i64 = 0i64
    var jblk: i64 = 0i64
    var jmax: i64 = 0i64
    var nblk: i64 = 0i64
    var nrmchk: i64 = 0i64
    var dtpcrt: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var eps1: f64 = 0.0f64
    var nrm: f64 = 0.0f64
    var onenrm: f64 = 0.0f64
    var ortol: f64 = 0.0f64
    var pertol: f64 = 0.0f64
    var scl: f64 = 0.0f64
    var sep: f64 = 0.0f64
    var tol: f64 = 0.0f64
    var xj: f64 = 0.0f64
    var xjm: f64 = 0.0f64
    var ztr: f64 = 0.0f64
    var iseed: [4]i64 = zero
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    var zc6: i64 = 0i64
    var zc7: i64 = 0i64
    var zc8: i64 = 0i64
    var zc9: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            i = 1i64
            zc1 = (m - i) + 1i64
            while zc1 > 0i64 {
                ifail[usize((i - 1i64))] = 0i64
                i = i + 1i64
                zc1 = zc1 - 1i64
            }
            if !(n < 0i64) {
                pc = 2i64
                continue
            }
            info = (-1i64)
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            if !((m < 0i64) || (m > n)) {
                pc = 3i64
                continue
            }
            info = (-4i64)
            pc = 1i64
            continue
        }
        if pc == 3i64 {
            if !(ldz < lbase.i_max(1i64, n)) {
                pc = 4i64
                continue
            }
            info = (-9i64)
            pc = 1i64
            continue
        }
        if pc == 4i64 {
            j = 2i64
            zc2 = (m - j) + 1i64
            pc = 5i64
        }
        if pc == 5i64 {
            if zc2 <= 0i64 {
                pc = 6i64
                continue
            }
            if !(iblock[usize((j - 1i64))] < iblock[usize(((j - 1i64) - 1i64))]) {
                pc = 8i64
                continue
            }
            info = (-6i64)
            pc = 9i64
            continue
        }
        if pc == 8i64 {
            pc = 7i64
        }
        if pc == 7i64 {
            if !((iblock[usize((j - 1i64))] == iblock[usize(((j - 1i64) - 1i64))]) && (w[usize((j - 1i64))] < w[usize(((j - 1i64) - 1i64))])) {
                pc = 11i64
                continue
            }
            info = (-5i64)
            pc = 9i64
            continue
        }
        if pc == 11i64 {
            pc = 10i64
        }
        if pc == 10i64 {
            j = j + 1i64
            zc2 = zc2 - 1i64
            pc = 5i64
            continue
        }
        if pc == 6i64 {
            pc = 9i64
        }
        if pc == 9i64 {
            pc = 1i64
            continue
        }
        if pc == 1i64 {
            if (info != 0i64) {
                *info_ref = info
                ret
            }
            if ((n == 0i64) || (m == 0i64)) {
                *info_ref = info
                ret
            } else if (n == 1i64) {
                z[usize((1i64 - 1i64) + (1i64 - 1i64) * ldz)] = 1.0f64
                *info_ref = info
                ret
            }
            eps = 2.220446049250313e-16f64
            i = 1i64
            zc3 = (4i64 - i) + 1i64
            while zc3 > 0i64 {
                iseed[usize((i - 1i64))] = 1i64
                i = i + 1i64
                zc3 = zc3 - 1i64
            }
            indrv1 = 0i64
            indrv2 = (indrv1 + n)
            indrv3 = (indrv2 + n)
            indrv4 = (indrv3 + n)
            indrv5 = (indrv4 + n)
            j1 = 1i64
            nblk = 1i64
            zc4 = (iblock[usize((m - 1i64))] - nblk) + 1i64
            pc = 12i64
        }
        if pc == 12i64 {
            if zc4 <= 0i64 {
                pc = 13i64
                continue
            }
            if (nblk == 1i64) {
                b1 = 1i64
            } else {
                b1 = (isplit[usize(((nblk - 1i64) - 1i64))] + 1i64)
            }
            bn = isplit[usize((nblk - 1i64))]
            blksiz = ((bn - b1) + 1i64)
            if !(blksiz == 1i64) {
                pc = 15i64
                continue
            }
            pc = 16i64
            continue
        }
        if pc == 15i64 {
            pc = 14i64
        }
        if pc == 14i64 {
            gpind = j1
            onenrm = (math.abs[f64](d[usize((b1 - 1i64))]) + math.abs[f64](e[usize((b1 - 1i64))]))
            onenrm = lbase.f_max(onenrm, (math.abs[f64](d[usize((bn - 1i64))]) + math.abs[f64](e[usize(((bn - 1i64) - 1i64))])))
            i = (b1 + 1i64)
            zc5 = ((bn - 1i64) - i) + 1i64
            while zc5 > 0i64 {
                onenrm = lbase.f_max(onenrm, ((math.abs[f64](d[usize((i - 1i64))]) + math.abs[f64](e[usize(((i - 1i64) - 1i64))])) + math.abs[f64](e[usize((i - 1i64))])))
                i = i + 1i64
                zc5 = zc5 - 1i64
            }
            ortol = (0.001f64 * onenrm)
            dtpcrt = math.sqrt[f64]((0.1f64 / f64(blksiz)))
            pc = 16i64
        }
        if pc == 16i64 {
            jblk = 0i64
            j = j1
            zc6 = (m - j) + 1i64
            pc = 17i64
        }
        if pc == 17i64 {
            if zc6 <= 0i64 {
                pc = 18i64
                continue
            }
            if !(iblock[usize((j - 1i64))] != nblk) {
                pc = 20i64
                continue
            }
            j1 = j
            pc = 21i64
            continue
        }
        if pc == 20i64 {
            pc = 19i64
        }
        if pc == 19i64 {
            jblk = (jblk + 1i64)
            xj = w[usize((j - 1i64))]
            if !(blksiz == 1i64) {
                pc = 23i64
                continue
            }
            work[usize(((indrv1 + 1i64) - 1i64))] = 1.0f64
            pc = 24i64
            continue
        }
        if pc == 23i64 {
            pc = 22i64
        }
        if pc == 22i64 {
            if (jblk > 1i64) {
                eps1 = math.abs[f64]((eps * xj))
                pertol = (10.0f64 * eps1)
                sep = (xj - xjm)
                if (sep < pertol) {
                    xj = (xjm + pertol)
                }
            }
            its = 0i64
            nrmchk = 0i64
            dlarnv(2i64, iseed[0usize..], blksiz, lbase.sl[f64](work[0usize..], usize(((indrv1 + 1i64) - 1i64))))
            lbase.dcopy(blksiz, lbase.sl[f64](d[0usize..], usize((b1 - 1i64))), 1i64, lbase.sl[f64](work[0usize..], usize(((indrv4 + 1i64) - 1i64))), 1i64)
            lbase.dcopy((blksiz - 1i64), lbase.sl[f64](e[0usize..], usize((b1 - 1i64))), 1i64, lbase.sl[f64](work[0usize..], usize(((indrv2 + 2i64) - 1i64))), 1i64)
            lbase.dcopy((blksiz - 1i64), lbase.sl[f64](e[0usize..], usize((b1 - 1i64))), 1i64, lbase.sl[f64](work[0usize..], usize(((indrv3 + 1i64) - 1i64))), 1i64)
            tol = 0.0f64
            dlagtf(blksiz, lbase.sl[f64](work[0usize..], usize(((indrv4 + 1i64) - 1i64))), xj, lbase.sl[f64](work[0usize..], usize(((indrv2 + 2i64) - 1i64))), lbase.sl[f64](work[0usize..], usize(((indrv3 + 1i64) - 1i64))), tol, lbase.sl[f64](work[0usize..], usize(((indrv5 + 1i64) - 1i64))), iwork[0usize..], &iinfo)
            pc = 25i64
        }
        if pc == 25i64 {
            its = (its + 1i64)
            if !(its > 5i64) {
                pc = 27i64
                continue
            }
            pc = 28i64
            continue
        }
        if pc == 27i64 {
            pc = 26i64
        }
        if pc == 26i64 {
            jmax = lbase.idamax(blksiz, lbase.sl[f64](work[0usize..], usize(((indrv1 + 1i64) - 1i64))), 1i64)
            scl = (((f64(blksiz) * onenrm) * lbase.f_max(eps, math.abs[f64](work[usize(((indrv4 + blksiz) - 1i64))]))) / math.abs[f64](work[usize(((indrv1 + jmax) - 1i64))]))
            lbase.dscal(blksiz, scl, lbase.sl[f64](work[0usize..], usize(((indrv1 + 1i64) - 1i64))), 1i64)
            dlagts((-1i64), blksiz, lbase.sl[f64](work[0usize..], usize(((indrv4 + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize(((indrv2 + 2i64) - 1i64))), lbase.sl[f64](work[0usize..], usize(((indrv3 + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize(((indrv5 + 1i64) - 1i64))), iwork[0usize..], lbase.sl[f64](work[0usize..], usize(((indrv1 + 1i64) - 1i64))), &tol, &iinfo)
            if !(jblk == 1i64) {
                pc = 30i64
                continue
            }
            pc = 31i64
            continue
        }
        if pc == 30i64 {
            pc = 29i64
        }
        if pc == 29i64 {
            if (math.abs[f64]((xj - xjm)) > ortol) {
                gpind = j
            }
            if (gpind != j) {
                i = gpind
                zc7 = ((j - 1i64) - i) + 1i64
                while zc7 > 0i64 {
                    ztr = (-lbase.ddot(blksiz, lbase.sl[f64](work[0usize..], usize(((indrv1 + 1i64) - 1i64))), 1i64, lbase.sl[f64](z[0usize..], usize((b1 - 1i64) + (i - 1i64) * ldz)), 1i64))
                    lbase.daxpy(blksiz, ztr, lbase.sl[f64](z[0usize..], usize((b1 - 1i64) + (i - 1i64) * ldz)), 1i64, lbase.sl[f64](work[0usize..], usize(((indrv1 + 1i64) - 1i64))), 1i64)
                    i = i + 1i64
                    zc7 = zc7 - 1i64
                }
            }
            pc = 31i64
        }
        if pc == 31i64 {
            jmax = lbase.idamax(blksiz, lbase.sl[f64](work[0usize..], usize(((indrv1 + 1i64) - 1i64))), 1i64)
            nrm = math.abs[f64](work[usize(((indrv1 + jmax) - 1i64))])
            if !(nrm < dtpcrt) {
                pc = 33i64
                continue
            }
            pc = 25i64
            continue
        }
        if pc == 33i64 {
            pc = 32i64
        }
        if pc == 32i64 {
            nrmchk = (nrmchk + 1i64)
            if !(nrmchk < (2i64 + 1i64)) {
                pc = 35i64
                continue
            }
            pc = 25i64
            continue
        }
        if pc == 35i64 {
            pc = 34i64
        }
        if pc == 34i64 {
            pc = 36i64
            continue
        }
        if pc == 28i64 {
            info = (info + 1i64)
            ifail[usize((info - 1i64))] = j
            pc = 36i64
        }
        if pc == 36i64 {
            scl = (1.0f64 / lbase.dnrm2(blksiz, lbase.sl[f64](work[0usize..], usize(((indrv1 + 1i64) - 1i64))), 1i64))
            jmax = lbase.idamax(blksiz, lbase.sl[f64](work[0usize..], usize(((indrv1 + 1i64) - 1i64))), 1i64)
            if (work[usize(((indrv1 + jmax) - 1i64))] < 0.0f64) {
                scl = (-scl)
            }
            lbase.dscal(blksiz, scl, lbase.sl[f64](work[0usize..], usize(((indrv1 + 1i64) - 1i64))), 1i64)
            pc = 24i64
        }
        if pc == 24i64 {
            i = 1i64
            zc8 = (n - i) + 1i64
            while zc8 > 0i64 {
                z[usize((i - 1i64) + (j - 1i64) * ldz)] = 0.0f64
                i = i + 1i64
                zc8 = zc8 - 1i64
            }
            i = 1i64
            zc9 = (blksiz - i) + 1i64
            while zc9 > 0i64 {
                z[usize((((b1 + i) - 1i64) - 1i64) + (j - 1i64) * ldz)] = work[usize(((indrv1 + i) - 1i64))]
                i = i + 1i64
                zc9 = zc9 - 1i64
            }
            xjm = xj
            j = j + 1i64
            zc6 = zc6 - 1i64
            pc = 17i64
            continue
        }
        if pc == 18i64 {
            pc = 21i64
        }
        if pc == 21i64 {
            nblk = nblk + 1i64
            zc4 = zc4 - 1i64
            pc = 12i64
            continue
        }
        if pc == 13i64 {
            *info_ref = info
            ret
        }
    }
}

fn dlagtf(n: i64, a: []f64, lambda: f64, b: []f64, c: []f64, tol: f64, d: []f64, in_: []i64, info_ref: *i64) {
    var info = *info_ref
    var k: i64 = 0i64
    var eps: f64 = 0.0f64
    var mult: f64 = 0.0f64
    var piv1: f64 = 0.0f64
    var piv2: f64 = 0.0f64
    var scale1: f64 = 0.0f64
    var scale2: f64 = 0.0f64
    var temp: f64 = 0.0f64
    var tl: f64 = 0.0f64
    var zc1: i64 = 0i64
    info = 0i64
    if (n < 0i64) {
        info = (-1i64)
        *info_ref = info
        ret
    }
    if (n == 0i64) {
        *info_ref = info
        ret
    }
    a[usize((1i64 - 1i64))] = (a[usize((1i64 - 1i64))] - lambda)
    in_[usize((n - 1i64))] = 0i64
    if (n == 1i64) {
        if (a[usize((1i64 - 1i64))] == 0.0f64) {
            in_[usize((1i64 - 1i64))] = 1i64
        }
        *info_ref = info
        ret
    }
    eps = 1.1102230246251565e-16f64
    tl = lbase.f_max(tol, eps)
    scale1 = (math.abs[f64](a[usize((1i64 - 1i64))]) + math.abs[f64](b[usize((1i64 - 1i64))]))
    k = 1i64
    zc1 = ((n - 1i64) - k) + 1i64
    while zc1 > 0i64 {
        a[usize(((k + 1i64) - 1i64))] = (a[usize(((k + 1i64) - 1i64))] - lambda)
        scale2 = (math.abs[f64](c[usize((k - 1i64))]) + math.abs[f64](a[usize(((k + 1i64) - 1i64))]))
        if (k < ((n - 1i64))) {
            scale2 = (scale2 + math.abs[f64](b[usize(((k + 1i64) - 1i64))]))
        }
        if (a[usize((k - 1i64))] == 0.0f64) {
            piv1 = 0.0f64
        } else {
            piv1 = (math.abs[f64](a[usize((k - 1i64))]) / scale1)
        }
        if (c[usize((k - 1i64))] == 0.0f64) {
            in_[usize((k - 1i64))] = 0i64
            piv2 = 0.0f64
            scale1 = scale2
            if (k < ((n - 1i64))) {
                d[usize((k - 1i64))] = 0.0f64
            }
        } else {
            piv2 = (math.abs[f64](c[usize((k - 1i64))]) / scale2)
            if (piv2 <= piv1) {
                in_[usize((k - 1i64))] = 0i64
                scale1 = scale2
                c[usize((k - 1i64))] = (c[usize((k - 1i64))] / a[usize((k - 1i64))])
                a[usize(((k + 1i64) - 1i64))] = (a[usize(((k + 1i64) - 1i64))] - (c[usize((k - 1i64))] * b[usize((k - 1i64))]))
                if (k < ((n - 1i64))) {
                    d[usize((k - 1i64))] = 0.0f64
                }
            } else {
                in_[usize((k - 1i64))] = 1i64
                mult = (a[usize((k - 1i64))] / c[usize((k - 1i64))])
                a[usize((k - 1i64))] = c[usize((k - 1i64))]
                temp = a[usize(((k + 1i64) - 1i64))]
                a[usize(((k + 1i64) - 1i64))] = (b[usize((k - 1i64))] - (mult * temp))
                if (k < ((n - 1i64))) {
                    d[usize((k - 1i64))] = b[usize(((k + 1i64) - 1i64))]
                    b[usize(((k + 1i64) - 1i64))] = (-(mult * d[usize((k - 1i64))]))
                }
                b[usize((k - 1i64))] = temp
                c[usize((k - 1i64))] = mult
            }
        }
        if (((lbase.f_max(piv1, piv2) <= tl)) && ((in_[usize((n - 1i64))] == 0i64))) {
            in_[usize((n - 1i64))] = k
        }
        k = k + 1i64
        zc1 = zc1 - 1i64
    }
    if (((math.abs[f64](a[usize((n - 1i64))]) <= (scale1 * tl))) && ((in_[usize((n - 1i64))] == 0i64))) {
        in_[usize((n - 1i64))] = n
    }
    *info_ref = info
    ret
}

fn dlagts(job: i64, n: i64, a: []f64, b: []f64, c: []f64, d: []f64, in_: []i64, y: []f64, tol_ref: *f64, info_ref: *i64) {
    var tol = *tol_ref
    var info = *info_ref
    var k: i64 = 0i64
    var absak: f64 = 0.0f64
    var ak: f64 = 0.0f64
    var bignum: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var pert: f64 = 0.0f64
    var sfmin: f64 = 0.0f64
    var temp: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zs4: i64 = 0i64
    var zc5: i64 = 0i64
    var zs6: i64 = 0i64
    var zc7: i64 = 0i64
    var zc8: i64 = 0i64
    var zc9: i64 = 0i64
    var zs10: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            if (((lbase.i_abs(job) > 2i64)) || ((job == 0i64))) {
                info = (-1i64)
            } else if (n < 0i64) {
                info = (-2i64)
            }
            if (info != 0i64) {
                *tol_ref = tol
                *info_ref = info
                ret
            }
            if (n == 0i64) {
                *tol_ref = tol
                *info_ref = info
                ret
            }
            eps = 1.1102230246251565e-16f64
            sfmin = 2.2250738585072014e-308f64
            bignum = (1.0f64 / sfmin)
            if (job < 0i64) {
                if (tol <= 0.0f64) {
                    tol = math.abs[f64](a[usize((1i64 - 1i64))])
                    if (n > 1i64) {
                        tol = lbase.f_max(lbase.f_max(tol, math.abs[f64](a[usize((2i64 - 1i64))])), math.abs[f64](b[usize((1i64 - 1i64))]))
                    }
                    k = 3i64
                    zc1 = (n - k) + 1i64
                    while zc1 > 0i64 {
                        tol = lbase.f_max(lbase.f_max(lbase.f_max(tol, math.abs[f64](a[usize((k - 1i64))])), math.abs[f64](b[usize(((k - 1i64) - 1i64))])), math.abs[f64](d[usize(((k - 2i64) - 1i64))]))
                        k = k + 1i64
                        zc1 = zc1 - 1i64
                    }
                    tol = (tol * eps)
                    if (tol == 0.0f64) {
                        tol = eps
                    }
                }
            }
            if !(lbase.i_abs(job) == 1i64) {
                pc = 2i64
                continue
            }
            k = 2i64
            zc2 = (n - k) + 1i64
            while zc2 > 0i64 {
                if (in_[usize(((k - 1i64) - 1i64))] == 0i64) {
                    y[usize((k - 1i64))] = (y[usize((k - 1i64))] - (c[usize(((k - 1i64) - 1i64))] * y[usize(((k - 1i64) - 1i64))]))
                } else {
                    temp = y[usize(((k - 1i64) - 1i64))]
                    y[usize(((k - 1i64) - 1i64))] = y[usize((k - 1i64))]
                    y[usize((k - 1i64))] = (temp - (c[usize(((k - 1i64) - 1i64))] * y[usize((k - 1i64))]))
                }
                k = k + 1i64
                zc2 = zc2 - 1i64
            }
            if !(job == 1i64) {
                pc = 4i64
                continue
            }
            k = n
            zs4 = (-1i64)
            zc3 = ((1i64 - k) + zs4) / zs4
            while zc3 > 0i64 {
                if (k <= (n - 2i64)) {
                    temp = ((y[usize((k - 1i64))] - (b[usize((k - 1i64))] * y[usize(((k + 1i64) - 1i64))])) - (d[usize((k - 1i64))] * y[usize(((k + 2i64) - 1i64))]))
                } else if (k == (n - 1i64)) {
                    temp = (y[usize((k - 1i64))] - (b[usize((k - 1i64))] * y[usize(((k + 1i64) - 1i64))]))
                } else {
                    temp = y[usize((k - 1i64))]
                }
                ak = a[usize((k - 1i64))]
                absak = math.abs[f64](ak)
                if (absak < 1.0f64) {
                    if (absak < sfmin) {
                        if ((absak == 0.0f64) || ((math.abs[f64](temp) * sfmin) > absak)) {
                            info = k
                            *tol_ref = tol
                            *info_ref = info
                            ret
                        } else {
                            temp = (temp * bignum)
                            ak = (ak * bignum)
                        }
                    } else if (math.abs[f64](temp) > (absak * bignum)) {
                        info = k
                        *tol_ref = tol
                        *info_ref = info
                        ret
                    }
                }
                y[usize((k - 1i64))] = (temp / ak)
                k = k + zs4
                zc3 = zc3 - 1i64
            }
            pc = 3i64
            continue
        }
        if pc == 4i64 {
            k = n
            zs6 = (-1i64)
            zc5 = ((1i64 - k) + zs6) / zs6
            pc = 5i64
        }
        if pc == 5i64 {
            if zc5 <= 0i64 {
                pc = 6i64
                continue
            }
            if (k <= (n - 2i64)) {
                temp = ((y[usize((k - 1i64))] - (b[usize((k - 1i64))] * y[usize(((k + 1i64) - 1i64))])) - (d[usize((k - 1i64))] * y[usize(((k + 2i64) - 1i64))]))
            } else if (k == (n - 1i64)) {
                temp = (y[usize((k - 1i64))] - (b[usize((k - 1i64))] * y[usize(((k + 1i64) - 1i64))]))
            } else {
                temp = y[usize((k - 1i64))]
            }
            ak = a[usize((k - 1i64))]
            pert = lbase.f_sign(tol, ak)
            pc = 7i64
        }
        if pc == 7i64 {
            absak = math.abs[f64](ak)
            if !(absak < 1.0f64) {
                pc = 9i64
                continue
            }
            if !(absak < sfmin) {
                pc = 11i64
                continue
            }
            if !((absak == 0.0f64) || ((math.abs[f64](temp) * sfmin) > absak)) {
                pc = 13i64
                continue
            }
            ak = (ak + pert)
            pert = (2.0f64 * pert)
            pc = 7i64
            continue
        }
        if pc == 13i64 {
            temp = (temp * bignum)
            ak = (ak * bignum)
            pc = 12i64
            continue
        }
        if pc == 12i64 {
            pc = 10i64
            continue
        }
        if pc == 11i64 {
            if !(math.abs[f64](temp) > (absak * bignum)) {
                pc = 14i64
                continue
            }
            ak = (ak + pert)
            pert = (2.0f64 * pert)
            pc = 7i64
            continue
        }
        if pc == 14i64 {
            pc = 10i64
        }
        if pc == 10i64 {
            pc = 8i64
            continue
        }
        if pc == 9i64 {
            pc = 8i64
        }
        if pc == 8i64 {
            y[usize((k - 1i64))] = (temp / ak)
            k = k + zs6
            zc5 = zc5 - 1i64
            pc = 5i64
            continue
        }
        if pc == 6i64 {
            pc = 3i64
            continue
        }
        if pc == 3i64 {
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            if !(job == 2i64) {
                pc = 16i64
                continue
            }
            k = 1i64
            zc7 = (n - k) + 1i64
            while zc7 > 0i64 {
                if (k >= 3i64) {
                    temp = ((y[usize((k - 1i64))] - (b[usize(((k - 1i64) - 1i64))] * y[usize(((k - 1i64) - 1i64))])) - (d[usize(((k - 2i64) - 1i64))] * y[usize(((k - 2i64) - 1i64))]))
                } else if (k == 2i64) {
                    temp = (y[usize((k - 1i64))] - (b[usize(((k - 1i64) - 1i64))] * y[usize(((k - 1i64) - 1i64))]))
                } else {
                    temp = y[usize((k - 1i64))]
                }
                ak = a[usize((k - 1i64))]
                absak = math.abs[f64](ak)
                if (absak < 1.0f64) {
                    if (absak < sfmin) {
                        if ((absak == 0.0f64) || ((math.abs[f64](temp) * sfmin) > absak)) {
                            info = k
                            *tol_ref = tol
                            *info_ref = info
                            ret
                        } else {
                            temp = (temp * bignum)
                            ak = (ak * bignum)
                        }
                    } else if (math.abs[f64](temp) > (absak * bignum)) {
                        info = k
                        *tol_ref = tol
                        *info_ref = info
                        ret
                    }
                }
                y[usize((k - 1i64))] = (temp / ak)
                k = k + 1i64
                zc7 = zc7 - 1i64
            }
            pc = 15i64
            continue
        }
        if pc == 16i64 {
            k = 1i64
            zc8 = (n - k) + 1i64
            pc = 17i64
        }
        if pc == 17i64 {
            if zc8 <= 0i64 {
                pc = 18i64
                continue
            }
            if (k >= 3i64) {
                temp = ((y[usize((k - 1i64))] - (b[usize(((k - 1i64) - 1i64))] * y[usize(((k - 1i64) - 1i64))])) - (d[usize(((k - 2i64) - 1i64))] * y[usize(((k - 2i64) - 1i64))]))
            } else if (k == 2i64) {
                temp = (y[usize((k - 1i64))] - (b[usize(((k - 1i64) - 1i64))] * y[usize(((k - 1i64) - 1i64))]))
            } else {
                temp = y[usize((k - 1i64))]
            }
            ak = a[usize((k - 1i64))]
            pert = lbase.f_sign(tol, ak)
            pc = 19i64
        }
        if pc == 19i64 {
            absak = math.abs[f64](ak)
            if !(absak < 1.0f64) {
                pc = 21i64
                continue
            }
            if !(absak < sfmin) {
                pc = 23i64
                continue
            }
            if !((absak == 0.0f64) || ((math.abs[f64](temp) * sfmin) > absak)) {
                pc = 25i64
                continue
            }
            ak = (ak + pert)
            pert = (2.0f64 * pert)
            pc = 19i64
            continue
        }
        if pc == 25i64 {
            temp = (temp * bignum)
            ak = (ak * bignum)
            pc = 24i64
            continue
        }
        if pc == 24i64 {
            pc = 22i64
            continue
        }
        if pc == 23i64 {
            if !(math.abs[f64](temp) > (absak * bignum)) {
                pc = 26i64
                continue
            }
            ak = (ak + pert)
            pert = (2.0f64 * pert)
            pc = 19i64
            continue
        }
        if pc == 26i64 {
            pc = 22i64
        }
        if pc == 22i64 {
            pc = 20i64
            continue
        }
        if pc == 21i64 {
            pc = 20i64
        }
        if pc == 20i64 {
            y[usize((k - 1i64))] = (temp / ak)
            k = k + 1i64
            zc8 = zc8 - 1i64
            pc = 17i64
            continue
        }
        if pc == 18i64 {
            pc = 15i64
            continue
        }
        if pc == 15i64 {
            k = n
            zs10 = (-1i64)
            zc9 = ((2i64 - k) + zs10) / zs10
            while zc9 > 0i64 {
                if (in_[usize(((k - 1i64) - 1i64))] == 0i64) {
                    y[usize(((k - 1i64) - 1i64))] = (y[usize(((k - 1i64) - 1i64))] - (c[usize(((k - 1i64) - 1i64))] * y[usize((k - 1i64))]))
                } else {
                    temp = y[usize(((k - 1i64) - 1i64))]
                    y[usize(((k - 1i64) - 1i64))] = y[usize((k - 1i64))]
                    y[usize((k - 1i64))] = (temp - (c[usize(((k - 1i64) - 1i64))] * y[usize((k - 1i64))]))
                }
                k = k + zs10
                zc9 = zc9 - 1i64
            }
            pc = 1i64
            continue
        }
        if pc == 1i64 {
            *tol_ref = tol
            *info_ref = info
            ret
        }
    }
}

// R's La_rs for symmetric = TRUE: x is n by n column-major (only its lower triangle is read), w gets the n eigenvalues
// ascending (LAPACK order; R reverses them), z the n by n eigenvectors column-major, column k for w[k].
fn dsyevr_all(a: *mem.Arena, x: []const f64, n: usize, w: []f64, z: []f64) -> err {
    let nn = i64(n)
    let (aa, e1) = mem.alloc[f64](a, n * n)
    let (isuppz, e2) = mem.alloc[i64](a, 2usize * n)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n * n {
        aa[i] = x[i]
        i += 1usize
    }
    var m = 0i64
    var info = 0i64
    var wk: [1]f64 = zero
    var iwk: [1]i64 = zero
    dsyevr("V", "A", "L", nn, aa[0usize..], nn, 0.0f64, 0.0f64, 1i64, 1i64, 0.0f64, &m, w, z, nn, isuppz[0usize..], wk[0usize..], -1i64, iwk[0usize..], -1i64, &info)
    if info != 0i64 { ret mem.Full }
    let lwork = usize(i64(wk[0usize]))
    let liwork = usize(iwk[0usize])
    let (work, e3) = mem.alloc[f64](a, lwork)
    let (iwork, e4) = mem.alloc[i64](a, liwork)
    if e3 != ok || e4 != ok { ret mem.Full }
    dsyevr("V", "A", "L", nn, aa[0usize..], nn, 0.0f64, 0.0f64, 1i64, 1i64, 0.0f64, &m, w, z, nn, isuppz[0usize..], work[0usize..], i64(lwork), iwork[0usize..], i64(liwork), &info)
    if info != 0i64 { ret mem.Full }
    ret ok
}
