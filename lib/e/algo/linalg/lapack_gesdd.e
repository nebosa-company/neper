// Reference LAPACK 3.12.1 dgesdd and everything under it (dgebrd/dgebd2/dlabrd, dgeqrf, dgelqf, dorgbr, dormbr, dbdsdc, dlasd0-5,
// dlasdq, dbdsqr, ...), translated statement for statement from the Fortran so that singular values and the signs of the
// singular vectors are the ones R's svd() returns. Generated from the Fortran sources, not edited by hand.
// svd_all at the end is the call La.svd makes: jobz S, after a workspace query.

use e.math
use e.mem
use e.algo.linalg.lapack_base as lbase
use e.algo.linalg.lapack_syevr as lsyevr

fn dgesdd(jobz: str, m: i64, n: i64, a: []f64, lda: i64, s: []f64, u: []f64, ldu: i64, vt: []f64, ldvt: i64, work: []f64, lwork: i64, iwork: []i64, info_ref: *i64) {
    var info = *info_ref
    var lquery: bool = false
    var wntqa: bool = false
    var wntqas: bool = false
    var wntqn: bool = false
    var wntqo: bool = false
    var wntqs: bool = false
    var bdspac: i64 = 0i64
    var blk: i64 = 0i64
    var chunk: i64 = 0i64
    var i: i64 = 0i64
    var ie: i64 = 0i64
    var ierr: i64 = 0i64
    var il: i64 = 0i64
    var ir: i64 = 0i64
    var iscl: i64 = 0i64
    var itau: i64 = 0i64
    var itaup: i64 = 0i64
    var itauq: i64 = 0i64
    var iu: i64 = 0i64
    var ivt: i64 = 0i64
    var ldwkvt: i64 = 0i64
    var ldwrkl: i64 = 0i64
    var ldwrkr: i64 = 0i64
    var ldwrku: i64 = 0i64
    var maxwrk: i64 = 0i64
    var minmn: i64 = 0i64
    var minwrk: i64 = 0i64
    var mnthr: i64 = 0i64
    var nwork: i64 = 0i64
    var wrkbl: i64 = 0i64
    var lwork_dgebrd_mn: i64 = 0i64
    var lwork_dgebrd_mm: i64 = 0i64
    var lwork_dgebrd_nn: i64 = 0i64
    var lwork_dgelqf_mn: i64 = 0i64
    var lwork_dgeqrf_mn: i64 = 0i64
    var lwork_dorgbr_p_mm: i64 = 0i64
    var lwork_dorgbr_q_nn: i64 = 0i64
    var lwork_dorglq_mn: i64 = 0i64
    var lwork_dorglq_nn: i64 = 0i64
    var lwork_dorgqr_mm: i64 = 0i64
    var lwork_dorgqr_mn: i64 = 0i64
    var lwork_dormbr_prt_mm: i64 = 0i64
    var lwork_dormbr_qln_mm: i64 = 0i64
    var lwork_dormbr_prt_mn: i64 = 0i64
    var lwork_dormbr_qln_mn: i64 = 0i64
    var lwork_dormbr_prt_nn: i64 = 0i64
    var lwork_dormbr_qln_nn: i64 = 0i64
    var anrm: f64 = 0.0f64
    var bignum: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var smlnum: f64 = 0.0f64
    var idum: [1]i64 = zero
    var dum: [1]f64 = zero
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
    var zc3: i64 = 0i64
    var zs4: i64 = 0i64
    var zc5: i64 = 0i64
    var zs6: i64 = 0i64
    var zc7: i64 = 0i64
    var zs8: i64 = 0i64
    info = 0i64
    minmn = lbase.i_min(m, n)
    wntqa = lbase.lsame(jobz, "A")
    wntqs = lbase.lsame(jobz, "S")
    wntqas = (wntqa || wntqs)
    wntqo = lbase.lsame(jobz, "O")
    wntqn = lbase.lsame(jobz, "N")
    lquery = ((lwork == (-1i64)))
    if (!((((wntqa || wntqs) || wntqo) || wntqn))) {
        info = (-1i64)
    } else if (m < 0i64) {
        info = (-2i64)
    } else if (n < 0i64) {
        info = (-3i64)
    } else if (lda < lbase.i_max(1i64, m)) {
        info = (-5i64)
    } else if (((ldu < 1i64) || ((wntqas && (ldu < m)))) || (((wntqo && (m < n)) && (ldu < m)))) {
        info = (-8i64)
    } else if ((((ldvt < 1i64) || ((wntqa && (ldvt < n)))) || ((wntqs && (ldvt < minmn)))) || (((wntqo && (m >= n)) && (ldvt < n)))) {
        info = (-10i64)
    }
    if (info == 0i64) {
        minwrk = 1i64
        maxwrk = 1i64
        bdspac = 0i64
        mnthr = i64(((f64(minmn) * 11.0f64) / 6.0f64))
        if ((m >= n) && (minmn > 0i64)) {
            if wntqn {
                bdspac = (7i64 * n)
            } else {
                bdspac = (((3i64 * n) * n) + (4i64 * n))
            }
            dgebrd(m, n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dgebrd_mn = i64(dum[usize((1i64 - 1i64))])
            dgebrd(n, n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dgebrd_nn = i64(dum[usize((1i64 - 1i64))])
            lbase.dgeqrf(m, n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dgeqrf_mn = i64(dum[usize((1i64 - 1i64))])
            dorgbr("Q", n, n, n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dorgbr_q_nn = i64(dum[usize((1i64 - 1i64))])
            lbase.dorgqr(m, m, n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dorgqr_mm = i64(dum[usize((1i64 - 1i64))])
            lbase.dorgqr(m, n, n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dorgqr_mn = i64(dum[usize((1i64 - 1i64))])
            dormbr("P", "R", "T", n, n, n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dormbr_prt_nn = i64(dum[usize((1i64 - 1i64))])
            dormbr("Q", "L", "N", n, n, n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dormbr_qln_nn = i64(dum[usize((1i64 - 1i64))])
            dormbr("Q", "L", "N", m, n, n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dormbr_qln_mn = i64(dum[usize((1i64 - 1i64))])
            dormbr("Q", "L", "N", m, m, n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dormbr_qln_mm = i64(dum[usize((1i64 - 1i64))])
            if (m >= mnthr) {
                if wntqn {
                    wrkbl = (n + lwork_dgeqrf_mn)
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dgebrd_nn))
                    maxwrk = lbase.i_max(wrkbl, (bdspac + n))
                    minwrk = (bdspac + n)
                } else if wntqo {
                    wrkbl = (n + lwork_dgeqrf_mn)
                    wrkbl = lbase.i_max(wrkbl, (n + lwork_dorgqr_mn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dgebrd_nn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dormbr_qln_nn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dormbr_prt_nn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + bdspac))
                    maxwrk = (wrkbl + ((2i64 * n) * n))
                    minwrk = ((bdspac + ((2i64 * n) * n)) + (3i64 * n))
                } else if wntqs {
                    wrkbl = (n + lwork_dgeqrf_mn)
                    wrkbl = lbase.i_max(wrkbl, (n + lwork_dorgqr_mn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dgebrd_nn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dormbr_qln_nn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dormbr_prt_nn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + bdspac))
                    maxwrk = (wrkbl + (n * n))
                    minwrk = ((bdspac + (n * n)) + (3i64 * n))
                } else if wntqa {
                    wrkbl = (n + lwork_dgeqrf_mn)
                    wrkbl = lbase.i_max(wrkbl, (n + lwork_dorgqr_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dgebrd_nn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dormbr_qln_nn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dormbr_prt_nn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + bdspac))
                    maxwrk = (wrkbl + (n * n))
                    minwrk = ((n * n) + lbase.i_max(((3i64 * n) + bdspac), (n + m)))
                }
            } else {
                wrkbl = ((3i64 * n) + lwork_dgebrd_mn)
                if wntqn {
                    maxwrk = lbase.i_max(wrkbl, ((3i64 * n) + bdspac))
                    minwrk = ((3i64 * n) + lbase.i_max(m, bdspac))
                } else if wntqo {
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dormbr_prt_nn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dormbr_qln_mn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + bdspac))
                    maxwrk = (wrkbl + (m * n))
                    minwrk = ((3i64 * n) + lbase.i_max(m, ((n * n) + bdspac)))
                } else if wntqs {
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dormbr_qln_mn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dormbr_prt_nn))
                    maxwrk = lbase.i_max(wrkbl, ((3i64 * n) + bdspac))
                    minwrk = ((3i64 * n) + lbase.i_max(m, bdspac))
                } else if wntqa {
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dormbr_qln_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * n) + lwork_dormbr_prt_nn))
                    maxwrk = lbase.i_max(wrkbl, ((3i64 * n) + bdspac))
                    minwrk = ((3i64 * n) + lbase.i_max(m, bdspac))
                }
            }
        } else if (minmn > 0i64) {
            if wntqn {
                bdspac = (7i64 * m)
            } else {
                bdspac = (((3i64 * m) * m) + (4i64 * m))
            }
            dgebrd(m, n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dgebrd_mn = i64(dum[usize((1i64 - 1i64))])
            dgebrd(m, m, a[0usize..], m, s[0usize..], lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dgebrd_mm = i64(dum[usize((1i64 - 1i64))])
            lbase.dgelqf(m, n, a[0usize..], m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dgelqf_mn = i64(dum[usize((1i64 - 1i64))])
            lbase.dorglq(n, n, m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dorglq_nn = i64(dum[usize((1i64 - 1i64))])
            lbase.dorglq(m, n, m, a[0usize..], m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dorglq_mn = i64(dum[usize((1i64 - 1i64))])
            dorgbr("P", m, m, m, a[0usize..], n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dorgbr_p_mm = i64(dum[usize((1i64 - 1i64))])
            dormbr("P", "R", "T", m, m, m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dormbr_prt_mm = i64(dum[usize((1i64 - 1i64))])
            dormbr("P", "R", "T", m, n, m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dormbr_prt_mn = i64(dum[usize((1i64 - 1i64))])
            dormbr("P", "R", "T", n, n, m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), n, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dormbr_prt_nn = i64(dum[usize((1i64 - 1i64))])
            dormbr("Q", "L", "N", m, m, m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), m, lbase.sl[f64](dum[0usize..], usize((1i64 - 1i64))), (-1i64), &ierr)
            lwork_dormbr_qln_mm = i64(dum[usize((1i64 - 1i64))])
            if (n >= mnthr) {
                if wntqn {
                    wrkbl = (m + lwork_dgelqf_mn)
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dgebrd_mm))
                    maxwrk = lbase.i_max(wrkbl, (bdspac + m))
                    minwrk = (bdspac + m)
                } else if wntqo {
                    wrkbl = (m + lwork_dgelqf_mn)
                    wrkbl = lbase.i_max(wrkbl, (m + lwork_dorglq_mn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dgebrd_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dormbr_qln_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dormbr_prt_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + bdspac))
                    maxwrk = (wrkbl + ((2i64 * m) * m))
                    minwrk = ((bdspac + ((2i64 * m) * m)) + (3i64 * m))
                } else if wntqs {
                    wrkbl = (m + lwork_dgelqf_mn)
                    wrkbl = lbase.i_max(wrkbl, (m + lwork_dorglq_mn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dgebrd_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dormbr_qln_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dormbr_prt_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + bdspac))
                    maxwrk = (wrkbl + (m * m))
                    minwrk = ((bdspac + (m * m)) + (3i64 * m))
                } else if wntqa {
                    wrkbl = (m + lwork_dgelqf_mn)
                    wrkbl = lbase.i_max(wrkbl, (m + lwork_dorglq_nn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dgebrd_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dormbr_qln_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dormbr_prt_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + bdspac))
                    maxwrk = (wrkbl + (m * m))
                    minwrk = ((m * m) + lbase.i_max(((3i64 * m) + bdspac), (m + n)))
                }
            } else {
                wrkbl = ((3i64 * m) + lwork_dgebrd_mn)
                if wntqn {
                    maxwrk = lbase.i_max(wrkbl, ((3i64 * m) + bdspac))
                    minwrk = ((3i64 * m) + lbase.i_max(n, bdspac))
                } else if wntqo {
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dormbr_qln_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dormbr_prt_mn))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + bdspac))
                    maxwrk = (wrkbl + (m * n))
                    minwrk = ((3i64 * m) + lbase.i_max(n, ((m * m) + bdspac)))
                } else if wntqs {
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dormbr_qln_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dormbr_prt_mn))
                    maxwrk = lbase.i_max(wrkbl, ((3i64 * m) + bdspac))
                    minwrk = ((3i64 * m) + lbase.i_max(n, bdspac))
                } else if wntqa {
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dormbr_qln_mm))
                    wrkbl = lbase.i_max(wrkbl, ((3i64 * m) + lwork_dormbr_prt_nn))
                    maxwrk = lbase.i_max(wrkbl, ((3i64 * m) + bdspac))
                    minwrk = ((3i64 * m) + lbase.i_max(n, bdspac))
                }
            }
        }
        maxwrk = lbase.i_max(maxwrk, minwrk)
        work[usize((1i64 - 1i64))] = lbase.droundup_lwork(maxwrk)
        if ((lwork < minwrk) && (!lquery)) {
            info = (-12i64)
        }
    }
    if (info != 0i64) {
        *info_ref = info
        ret
    } else if lquery {
        *info_ref = info
        ret
    }
    if ((m == 0i64) || (n == 0i64)) {
        *info_ref = info
        ret
    }
    eps = 2.220446049250313e-16f64
    smlnum = (math.sqrt[f64](2.2250738585072014e-308f64) / eps)
    bignum = (1.0f64 / smlnum)
    anrm = lbase.dlange("M", m, n, a[0usize..], lda, dum[0usize..])
    if lbase.disnan(anrm) {
        info = (-4i64)
        *info_ref = info
        ret
    }
    iscl = 0i64
    if ((anrm > 0.0f64) && (anrm < smlnum)) {
        iscl = 1i64
        lbase.dlascl("G", 0i64, 0i64, anrm, smlnum, m, n, a[0usize..], lda, &ierr)
    } else if (anrm > bignum) {
        iscl = 1i64
        lbase.dlascl("G", 0i64, 0i64, anrm, bignum, m, n, a[0usize..], lda, &ierr)
    }
    if (m >= n) {
        if (m >= mnthr) {
            if wntqn {
                itau = 1i64
                nwork = (itau + n)
                lbase.dgeqrf(m, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dlaset("L", (n - 1i64), (n - 1i64), 0.0f64, 0.0f64, lbase.sl[f64](a[0usize..], usize((2i64 - 1i64) + (1i64 - 1i64) * lda)), lda)
                ie = 1i64
                itauq = (ie + n)
                itaup = (itauq + n)
                nwork = (itaup + n)
                dgebrd(n, n, a[0usize..], lda, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                nwork = (ie + n)
                dbdsdc("U", "N", n, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), dum[0usize..], 1i64, dum[0usize..], 1i64, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
            } else if wntqo {
                ir = 1i64
                if (lwork >= ((((lda * n) + (n * n)) + (3i64 * n)) + bdspac)) {
                    ldwrkr = lda
                } else {
                    ldwrkr = (((((lwork - (n * n)) - (3i64 * n)) - bdspac)) / n)
                }
                itau = (ir + (ldwrkr * n))
                nwork = (itau + n)
                lbase.dgeqrf(m, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dlacpy("U", n, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr)
                lbase.dlaset("L", (n - 1i64), (n - 1i64), 0.0f64, 0.0f64, lbase.sl[f64](work[0usize..], usize(((ir + 1i64) - 1i64))), ldwrkr)
                lbase.dorgqr(m, n, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                ie = itau
                itauq = (ie + n)
                itaup = (itauq + n)
                nwork = (itaup + n)
                dgebrd(n, n, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                iu = nwork
                nwork = (iu + (n * n))
                dbdsdc("U", "I", n, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), lbase.sl[f64](work[0usize..], usize((iu - 1i64))), n, vt[0usize..], ldvt, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
                dormbr("Q", "L", "N", n, n, n, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr, lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((iu - 1i64))), n, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dormbr("P", "R", "T", n, n, n, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr, lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), vt[0usize..], ldvt, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                i = 1i64
                zs2 = ldwrkr
                zc1 = ((m - i) + zs2) / zs2
                while zc1 > 0i64 {
                    chunk = lbase.i_min(((m - i) + 1i64), ldwrkr)
                    lbase.dgemm("N", "N", chunk, n, n, 1.0f64, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (1i64 - 1i64) * lda)), lda, lbase.sl[f64](work[0usize..], usize((iu - 1i64))), n, 0.0f64, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr)
                    lbase.dlacpy("F", chunk, n, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (1i64 - 1i64) * lda)), lda)
                    i = i + zs2
                    zc1 = zc1 - 1i64
                }
            } else if wntqs {
                ir = 1i64
                ldwrkr = n
                itau = (ir + (ldwrkr * n))
                nwork = (itau + n)
                lbase.dgeqrf(m, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dlacpy("U", n, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr)
                lbase.dlaset("L", (n - 1i64), (n - 1i64), 0.0f64, 0.0f64, lbase.sl[f64](work[0usize..], usize(((ir + 1i64) - 1i64))), ldwrkr)
                lbase.dorgqr(m, n, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                ie = itau
                itauq = (ie + n)
                itaup = (itauq + n)
                nwork = (itaup + n)
                dgebrd(n, n, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dbdsdc("U", "I", n, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), u[0usize..], ldu, vt[0usize..], ldvt, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
                dormbr("Q", "L", "N", n, n, n, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr, lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dormbr("P", "R", "T", n, n, n, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr, lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), vt[0usize..], ldvt, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dlacpy("F", n, n, u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr)
                lbase.dgemm("N", "N", m, n, n, 1.0f64, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr, 0.0f64, u[0usize..], ldu)
            } else if wntqa {
                iu = 1i64
                ldwrku = n
                itau = (iu + (ldwrku * n))
                nwork = (itau + n)
                lbase.dgeqrf(m, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dlacpy("L", m, n, a[0usize..], lda, u[0usize..], ldu)
                lbase.dorgqr(m, m, n, u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dlaset("L", (n - 1i64), (n - 1i64), 0.0f64, 0.0f64, lbase.sl[f64](a[0usize..], usize((2i64 - 1i64) + (1i64 - 1i64) * lda)), lda)
                ie = itau
                itauq = (ie + n)
                itaup = (itauq + n)
                nwork = (itaup + n)
                dgebrd(n, n, a[0usize..], lda, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dbdsdc("U", "I", n, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), lbase.sl[f64](work[0usize..], usize((iu - 1i64))), n, vt[0usize..], ldvt, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
                dormbr("Q", "L", "N", n, n, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((iu - 1i64))), ldwrku, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dormbr("P", "R", "T", n, n, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), vt[0usize..], ldvt, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dgemm("N", "N", m, n, n, 1.0f64, u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((iu - 1i64))), ldwrku, 0.0f64, a[0usize..], lda)
                lbase.dlacpy("F", m, n, a[0usize..], lda, u[0usize..], ldu)
            }
        } else {
            ie = 1i64
            itauq = (ie + n)
            itaup = (itauq + n)
            nwork = (itaup + n)
            dgebrd(m, n, a[0usize..], lda, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
            if wntqn {
                dbdsdc("U", "N", n, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), dum[0usize..], 1i64, dum[0usize..], 1i64, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
            } else if wntqo {
                iu = nwork
                if (lwork >= (((m * n) + (3i64 * n)) + bdspac)) {
                    ldwrku = m
                    nwork = (iu + (ldwrku * n))
                    lbase.dlaset("F", m, n, 0.0f64, 0.0f64, lbase.sl[f64](work[0usize..], usize((iu - 1i64))), ldwrku)
                    ir = (-1i64)
                } else {
                    ldwrku = n
                    nwork = (iu + (ldwrku * n))
                    ir = nwork
                    ldwrkr = ((((lwork - (n * n)) - (3i64 * n))) / n)
                }
                nwork = (iu + (ldwrku * n))
                dbdsdc("U", "I", n, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), lbase.sl[f64](work[0usize..], usize((iu - 1i64))), ldwrku, vt[0usize..], ldvt, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
                dormbr("P", "R", "T", n, n, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), vt[0usize..], ldvt, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                if (lwork >= (((m * n) + (3i64 * n)) + bdspac)) {
                    dormbr("Q", "L", "N", m, n, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((iu - 1i64))), ldwrku, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                    lbase.dlacpy("F", m, n, lbase.sl[f64](work[0usize..], usize((iu - 1i64))), ldwrku, a[0usize..], lda)
                } else {
                    dorgbr("Q", m, n, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                    i = 1i64
                    zs4 = ldwrkr
                    zc3 = ((m - i) + zs4) / zs4
                    while zc3 > 0i64 {
                        chunk = lbase.i_min(((m - i) + 1i64), ldwrkr)
                        lbase.dgemm("N", "N", chunk, n, n, 1.0f64, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (1i64 - 1i64) * lda)), lda, lbase.sl[f64](work[0usize..], usize((iu - 1i64))), ldwrku, 0.0f64, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr)
                        lbase.dlacpy("F", chunk, n, lbase.sl[f64](work[0usize..], usize((ir - 1i64))), ldwrkr, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (1i64 - 1i64) * lda)), lda)
                        i = i + zs4
                        zc3 = zc3 - 1i64
                    }
                }
            } else if wntqs {
                lbase.dlaset("F", m, n, 0.0f64, 0.0f64, u[0usize..], ldu)
                dbdsdc("U", "I", n, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), u[0usize..], ldu, vt[0usize..], ldvt, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
                dormbr("Q", "L", "N", m, n, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dormbr("P", "R", "T", n, n, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), vt[0usize..], ldvt, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
            } else if wntqa {
                lbase.dlaset("F", m, m, 0.0f64, 0.0f64, u[0usize..], ldu)
                dbdsdc("U", "I", n, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), u[0usize..], ldu, vt[0usize..], ldvt, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
                if (m > n) {
                    lbase.dlaset("F", (m - n), (m - n), 0.0f64, 1.0f64, lbase.sl[f64](u[0usize..], usize(((n + 1i64) - 1i64) + ((n + 1i64) - 1i64) * ldu)), ldu)
                }
                dormbr("Q", "L", "N", m, m, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dormbr("P", "R", "T", n, n, m, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), vt[0usize..], ldvt, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
            }
        }
    } else {
        if (n >= mnthr) {
            if wntqn {
                itau = 1i64
                nwork = (itau + m)
                lbase.dgelqf(m, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dlaset("U", (m - 1i64), (m - 1i64), 0.0f64, 0.0f64, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (2i64 - 1i64) * lda)), lda)
                ie = 1i64
                itauq = (ie + m)
                itaup = (itauq + m)
                nwork = (itaup + m)
                dgebrd(m, m, a[0usize..], lda, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                nwork = (ie + m)
                dbdsdc("U", "N", m, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), dum[0usize..], 1i64, dum[0usize..], 1i64, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
            } else if wntqo {
                ivt = 1i64
                il = (ivt + (m * m))
                if (lwork >= ((((m * n) + (m * m)) + (3i64 * m)) + bdspac)) {
                    ldwrkl = m
                    chunk = n
                } else {
                    ldwrkl = m
                    chunk = (((lwork - (m * m))) / m)
                }
                itau = (il + (ldwrkl * m))
                nwork = (itau + m)
                lbase.dgelqf(m, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dlacpy("L", m, m, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((il - 1i64))), ldwrkl)
                lbase.dlaset("U", (m - 1i64), (m - 1i64), 0.0f64, 0.0f64, lbase.sl[f64](work[0usize..], usize(((il + ldwrkl) - 1i64))), ldwrkl)
                lbase.dorglq(m, n, m, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                ie = itau
                itauq = (ie + m)
                itaup = (itauq + m)
                nwork = (itaup + m)
                dgebrd(m, m, lbase.sl[f64](work[0usize..], usize((il - 1i64))), ldwrkl, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dbdsdc("U", "I", m, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((ivt - 1i64))), m, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
                dormbr("Q", "L", "N", m, m, m, lbase.sl[f64](work[0usize..], usize((il - 1i64))), ldwrkl, lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dormbr("P", "R", "T", m, m, m, lbase.sl[f64](work[0usize..], usize((il - 1i64))), ldwrkl, lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((ivt - 1i64))), m, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                i = 1i64
                zs6 = chunk
                zc5 = ((n - i) + zs6) / zs6
                while zc5 > 0i64 {
                    blk = lbase.i_min(((n - i) + 1i64), chunk)
                    lbase.dgemm("N", "N", m, blk, m, 1.0f64, lbase.sl[f64](work[0usize..], usize((ivt - 1i64))), m, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), lda, 0.0f64, lbase.sl[f64](work[0usize..], usize((il - 1i64))), ldwrkl)
                    lbase.dlacpy("F", m, blk, lbase.sl[f64](work[0usize..], usize((il - 1i64))), ldwrkl, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), lda)
                    i = i + zs6
                    zc5 = zc5 - 1i64
                }
            } else if wntqs {
                il = 1i64
                ldwrkl = m
                itau = (il + (ldwrkl * m))
                nwork = (itau + m)
                lbase.dgelqf(m, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dlacpy("L", m, m, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((il - 1i64))), ldwrkl)
                lbase.dlaset("U", (m - 1i64), (m - 1i64), 0.0f64, 0.0f64, lbase.sl[f64](work[0usize..], usize(((il + ldwrkl) - 1i64))), ldwrkl)
                lbase.dorglq(m, n, m, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                ie = itau
                itauq = (ie + m)
                itaup = (itauq + m)
                nwork = (itaup + m)
                dgebrd(m, m, lbase.sl[f64](work[0usize..], usize((il - 1i64))), ldwrkl, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dbdsdc("U", "I", m, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), u[0usize..], ldu, vt[0usize..], ldvt, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
                dormbr("Q", "L", "N", m, m, m, lbase.sl[f64](work[0usize..], usize((il - 1i64))), ldwrkl, lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dormbr("P", "R", "T", m, m, m, lbase.sl[f64](work[0usize..], usize((il - 1i64))), ldwrkl, lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), vt[0usize..], ldvt, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dlacpy("F", m, m, vt[0usize..], ldvt, lbase.sl[f64](work[0usize..], usize((il - 1i64))), ldwrkl)
                lbase.dgemm("N", "N", m, n, m, 1.0f64, lbase.sl[f64](work[0usize..], usize((il - 1i64))), ldwrkl, a[0usize..], lda, 0.0f64, vt[0usize..], ldvt)
            } else if wntqa {
                ivt = 1i64
                ldwkvt = m
                itau = (ivt + (ldwkvt * m))
                nwork = (itau + m)
                lbase.dgelqf(m, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dlacpy("U", m, n, a[0usize..], lda, vt[0usize..], ldvt)
                lbase.dorglq(n, n, m, vt[0usize..], ldvt, lbase.sl[f64](work[0usize..], usize((itau - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dlaset("U", (m - 1i64), (m - 1i64), 0.0f64, 0.0f64, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (2i64 - 1i64) * lda)), lda)
                ie = itau
                itauq = (ie + m)
                itaup = (itauq + m)
                nwork = (itaup + m)
                dgebrd(m, m, a[0usize..], lda, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dbdsdc("U", "I", m, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((ivt - 1i64))), ldwkvt, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
                dormbr("Q", "L", "N", m, m, m, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dormbr("P", "R", "T", m, m, m, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((ivt - 1i64))), ldwkvt, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                lbase.dgemm("N", "N", m, n, m, 1.0f64, lbase.sl[f64](work[0usize..], usize((ivt - 1i64))), ldwkvt, vt[0usize..], ldvt, 0.0f64, a[0usize..], lda)
                lbase.dlacpy("F", m, n, a[0usize..], lda, vt[0usize..], ldvt)
            }
        } else {
            ie = 1i64
            itauq = (ie + m)
            itaup = (itauq + m)
            nwork = (itaup + m)
            dgebrd(m, n, a[0usize..], lda, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
            if wntqn {
                dbdsdc("L", "N", m, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), dum[0usize..], 1i64, dum[0usize..], 1i64, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
            } else if wntqo {
                ldwkvt = m
                ivt = nwork
                if (lwork >= (((m * n) + (3i64 * m)) + bdspac)) {
                    lbase.dlaset("F", m, n, 0.0f64, 0.0f64, lbase.sl[f64](work[0usize..], usize((ivt - 1i64))), ldwkvt)
                    nwork = (ivt + (ldwkvt * n))
                    il = (-1i64)
                } else {
                    nwork = (ivt + (ldwkvt * m))
                    il = nwork
                    chunk = ((((lwork - (m * m)) - (3i64 * m))) / m)
                }
                dbdsdc("L", "I", m, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((ivt - 1i64))), ldwkvt, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
                dormbr("Q", "L", "N", m, m, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                if (lwork >= (((m * n) + (3i64 * m)) + bdspac)) {
                    dormbr("P", "R", "T", m, n, m, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((ivt - 1i64))), ldwkvt, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                    lbase.dlacpy("F", m, n, lbase.sl[f64](work[0usize..], usize((ivt - 1i64))), ldwkvt, a[0usize..], lda)
                } else {
                    dorgbr("P", m, n, m, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                    i = 1i64
                    zs8 = chunk
                    zc7 = ((n - i) + zs8) / zs8
                    while zc7 > 0i64 {
                        blk = lbase.i_min(((n - i) + 1i64), chunk)
                        lbase.dgemm("N", "N", m, blk, m, 1.0f64, lbase.sl[f64](work[0usize..], usize((ivt - 1i64))), ldwkvt, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), lda, 0.0f64, lbase.sl[f64](work[0usize..], usize((il - 1i64))), m)
                        lbase.dlacpy("F", m, blk, lbase.sl[f64](work[0usize..], usize((il - 1i64))), m, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), lda)
                        i = i + zs8
                        zc7 = zc7 - 1i64
                    }
                }
            } else if wntqs {
                lbase.dlaset("F", m, n, 0.0f64, 0.0f64, vt[0usize..], ldvt)
                dbdsdc("L", "I", m, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), u[0usize..], ldu, vt[0usize..], ldvt, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
                dormbr("Q", "L", "N", m, m, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dormbr("P", "R", "T", m, n, m, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), vt[0usize..], ldvt, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
            } else if wntqa {
                lbase.dlaset("F", n, n, 0.0f64, 0.0f64, vt[0usize..], ldvt)
                dbdsdc("L", "I", m, s[0usize..], lbase.sl[f64](work[0usize..], usize((ie - 1i64))), u[0usize..], ldu, vt[0usize..], ldvt, dum[0usize..], idum[0usize..], lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), iwork[0usize..], &info)
                if (n > m) {
                    lbase.dlaset("F", (n - m), (n - m), 0.0f64, 1.0f64, lbase.sl[f64](vt[0usize..], usize(((m + 1i64) - 1i64) + ((m + 1i64) - 1i64) * ldvt)), ldvt)
                }
                dormbr("Q", "L", "N", m, m, n, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itauq - 1i64))), u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
                dormbr("P", "R", "T", n, n, m, a[0usize..], lda, lbase.sl[f64](work[0usize..], usize((itaup - 1i64))), vt[0usize..], ldvt, lbase.sl[f64](work[0usize..], usize((nwork - 1i64))), ((lwork - nwork) + 1i64), &ierr)
            }
        }
    }
    if (iscl == 1i64) {
        if (anrm > bignum) {
            lbase.dlascl("G", 0i64, 0i64, bignum, anrm, minmn, 1i64, s[0usize..], minmn, &ierr)
        }
        if (anrm < smlnum) {
            lbase.dlascl("G", 0i64, 0i64, smlnum, anrm, minmn, 1i64, s[0usize..], minmn, &ierr)
        }
    }
    work[usize((1i64 - 1i64))] = lbase.droundup_lwork(maxwrk)
    *info_ref = info
    ret
}

fn dgebrd(m: i64, n: i64, a: []f64, lda: i64, d: []f64, e: []f64, tauq: []f64, taup: []f64, work: []f64, lwork: i64, info_ref: *i64) {
    var info = *info_ref
    var lquery: bool = false
    var i: i64 = 0i64
    var iinfo: i64 = 0i64
    var j: i64 = 0i64
    var ldwrkx: i64 = 0i64
    var ldwrky: i64 = 0i64
    var lwkmin: i64 = 0i64
    var lwkopt: i64 = 0i64
    var minmn: i64 = 0i64
    var nb: i64 = 0i64
    var nbmin: i64 = 0i64
    var nx: i64 = 0i64
    var ws: i64 = 0i64
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    info = 0i64
    minmn = lbase.i_min(m, n)
    if (minmn == 0i64) {
        lwkmin = 1i64
        lwkopt = 1i64
    } else {
        lwkmin = lbase.i_max(m, n)
        nb = lbase.i_max(1i64, lbase.ilaenv(1i64, "DGEBRD", " ", m, n, (-1i64), (-1i64)))
        lwkopt = (((m + n)) * nb)
    }
    work[usize((1i64 - 1i64))] = f64(lwkopt)
    lquery = ((lwork == (-1i64)))
    if (m < 0i64) {
        info = (-1i64)
    } else if (n < 0i64) {
        info = (-2i64)
    } else if (lda < lbase.i_max(1i64, m)) {
        info = (-4i64)
    } else if ((lwork < lwkmin) && (!lquery)) {
        info = (-10i64)
    }
    if (info < 0i64) {
        *info_ref = info
        ret
    } else if lquery {
        *info_ref = info
        ret
    }
    if (minmn == 0i64) {
        work[usize((1i64 - 1i64))] = 1.0f64
        *info_ref = info
        ret
    }
    ws = lbase.i_max(m, n)
    ldwrkx = m
    ldwrky = n
    if ((nb > 1i64) && (nb < minmn)) {
        nx = lbase.i_max(nb, lbase.ilaenv(3i64, "DGEBRD", " ", m, n, (-1i64), (-1i64)))
        if (nx < minmn) {
            ws = lwkopt
            if (lwork < ws) {
                nbmin = lbase.ilaenv(2i64, "DGEBRD", " ", m, n, (-1i64), (-1i64))
                if (lwork >= (((m + n)) * nbmin)) {
                    nb = (lwork / ((m + n)))
                } else {
                    nb = 1i64
                    nx = minmn
                }
            }
        }
    } else {
        nx = minmn
    }
    i = 1i64
    zs2 = nb
    zc1 = (((minmn - nx) - i) + zs2) / zs2
    while zc1 > 0i64 {
        dlabrd(((m - i) + 1i64), ((n - i) + 1i64), nb, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), lda, lbase.sl[f64](d[0usize..], usize((i - 1i64))), lbase.sl[f64](e[0usize..], usize((i - 1i64))), lbase.sl[f64](tauq[0usize..], usize((i - 1i64))), lbase.sl[f64](taup[0usize..], usize((i - 1i64))), work[0usize..], ldwrkx, lbase.sl[f64](work[0usize..], usize((((ldwrkx * nb) + 1i64) - 1i64))), ldwrky)
        lbase.dgemm("No transpose", "Transpose", (((m - i) - nb) + 1i64), (((n - i) - nb) + 1i64), nb, (-1.0f64), lbase.sl[f64](a[0usize..], usize(((i + nb) - 1i64) + (i - 1i64) * lda)), lda, lbase.sl[f64](work[0usize..], usize(((((ldwrkx * nb) + nb) + 1i64) - 1i64))), ldwrky, 1.0f64, lbase.sl[f64](a[0usize..], usize(((i + nb) - 1i64) + ((i + nb) - 1i64) * lda)), lda)
        lbase.dgemm("No transpose", "No transpose", (((m - i) - nb) + 1i64), (((n - i) - nb) + 1i64), nb, (-1.0f64), lbase.sl[f64](work[0usize..], usize(((nb + 1i64) - 1i64))), ldwrkx, lbase.sl[f64](a[0usize..], usize((i - 1i64) + ((i + nb) - 1i64) * lda)), lda, 1.0f64, lbase.sl[f64](a[0usize..], usize(((i + nb) - 1i64) + ((i + nb) - 1i64) * lda)), lda)
        if (m >= n) {
            j = i
            zc3 = (((i + nb) - 1i64) - j) + 1i64
            while zc3 > 0i64 {
                a[usize((j - 1i64) + (j - 1i64) * lda)] = d[usize((j - 1i64))]
                a[usize((j - 1i64) + ((j + 1i64) - 1i64) * lda)] = e[usize((j - 1i64))]
                j = j + 1i64
                zc3 = zc3 - 1i64
            }
        } else {
            j = i
            zc4 = (((i + nb) - 1i64) - j) + 1i64
            while zc4 > 0i64 {
                a[usize((j - 1i64) + (j - 1i64) * lda)] = d[usize((j - 1i64))]
                a[usize(((j + 1i64) - 1i64) + (j - 1i64) * lda)] = e[usize((j - 1i64))]
                j = j + 1i64
                zc4 = zc4 - 1i64
            }
        }
        i = i + zs2
        zc1 = zc1 - 1i64
    }
    dgebd2(((m - i) + 1i64), ((n - i) + 1i64), lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), lda, lbase.sl[f64](d[0usize..], usize((i - 1i64))), lbase.sl[f64](e[0usize..], usize((i - 1i64))), lbase.sl[f64](tauq[0usize..], usize((i - 1i64))), lbase.sl[f64](taup[0usize..], usize((i - 1i64))), work[0usize..], &iinfo)
    work[usize((1i64 - 1i64))] = f64(ws)
    *info_ref = info
    ret
}

fn dgebd2(m: i64, n: i64, a: []f64, lda: i64, d: []f64, e: []f64, tauq: []f64, taup: []f64, work: []f64, info_ref: *i64) {
    var info = *info_ref
    var i: i64 = 0i64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    info = 0i64
    if (m < 0i64) {
        info = (-1i64)
    } else if (n < 0i64) {
        info = (-2i64)
    } else if (lda < lbase.i_max(1i64, m)) {
        info = (-4i64)
    }
    if (info < 0i64) {
        *info_ref = info
        ret
    }
    if (m >= n) {
        i = 1i64
        zc1 = (n - i) + 1i64
        while zc1 > 0i64 {
            lbase.dlarfg(((m - i) + 1i64), &a[usize((i - 1i64) + (i - 1i64) * lda)], lbase.sl[f64](a[0usize..], usize((lbase.i_min((i + 1i64), m) - 1i64) + (i - 1i64) * lda)), 1i64, &tauq[usize((i - 1i64))])
            d[usize((i - 1i64))] = a[usize((i - 1i64) + (i - 1i64) * lda)]
            if (i < n) {
                lbase.dlarf1f("Left", ((m - i) + 1i64), (n - i), lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), 1i64, tauq[usize((i - 1i64))], lbase.sl[f64](a[0usize..], usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, work[0usize..])
            }
            if (i < n) {
                lbase.dlarfg((n - i), &a[usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)], lbase.sl[f64](a[0usize..], usize((i - 1i64) + (lbase.i_min((i + 2i64), n) - 1i64) * lda)), lda, &taup[usize((i - 1i64))])
                e[usize((i - 1i64))] = a[usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)]
                lbase.dlarf1f("Right", (m - i), (n - i), lbase.sl[f64](a[0usize..], usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, taup[usize((i - 1i64))], lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, work[0usize..])
            } else {
                taup[usize((i - 1i64))] = 0.0f64
            }
            i = i + 1i64
            zc1 = zc1 - 1i64
        }
    } else {
        i = 1i64
        zc2 = (m - i) + 1i64
        while zc2 > 0i64 {
            lbase.dlarfg(((n - i) + 1i64), &a[usize((i - 1i64) + (i - 1i64) * lda)], lbase.sl[f64](a[0usize..], usize((i - 1i64) + (lbase.i_min((i + 1i64), n) - 1i64) * lda)), lda, &taup[usize((i - 1i64))])
            d[usize((i - 1i64))] = a[usize((i - 1i64) + (i - 1i64) * lda)]
            if (i < m) {
                lbase.dlarf1f("Right", (m - i), ((n - i) + 1i64), lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), lda, taup[usize((i - 1i64))], lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), lda, work[0usize..])
            }
            if (i < m) {
                lbase.dlarfg((m - i), &a[usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)], lbase.sl[f64](a[0usize..], usize((lbase.i_min((i + 2i64), m) - 1i64) + (i - 1i64) * lda)), 1i64, &tauq[usize((i - 1i64))])
                e[usize((i - 1i64))] = a[usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)]
                lbase.dlarf1f("Left", (m - i), (n - i), lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64, tauq[usize((i - 1i64))], lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, work[0usize..])
            } else {
                tauq[usize((i - 1i64))] = 0.0f64
            }
            i = i + 1i64
            zc2 = zc2 - 1i64
        }
    }
    *info_ref = info
    ret
}

fn dlabrd(m: i64, n: i64, nb: i64, a: []f64, lda: i64, d: []f64, e: []f64, tauq: []f64, taup: []f64, x: []f64, ldx: i64, y: []f64, ldy: i64) {
    var i: i64 = 0i64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    if ((m <= 0i64) || (n <= 0i64)) {
        ret
    }
    if (m >= n) {
        i = 1i64
        zc1 = (nb - i) + 1i64
        while zc1 > 0i64 {
            lbase.dgemv("No transpose", ((m - i) + 1i64), (i - 1i64), (-1.0f64), lbase.sl[f64](a[0usize..], usize((i - 1i64) + (1i64 - 1i64) * lda)), lda, lbase.sl[f64](y[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldy)), ldy, 1.0f64, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), 1i64)
            lbase.dgemv("No transpose", ((m - i) + 1i64), (i - 1i64), (-1.0f64), lbase.sl[f64](x[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldx)), ldx, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), 1i64, 1.0f64, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), 1i64)
            lbase.dlarfg(((m - i) + 1i64), &a[usize((i - 1i64) + (i - 1i64) * lda)], lbase.sl[f64](a[0usize..], usize((lbase.i_min((i + 1i64), m) - 1i64) + (i - 1i64) * lda)), 1i64, &tauq[usize((i - 1i64))])
            d[usize((i - 1i64))] = a[usize((i - 1i64) + (i - 1i64) * lda)]
            if (i < n) {
                a[usize((i - 1i64) + (i - 1i64) * lda)] = 1.0f64
                lbase.dgemv("Transpose", ((m - i) + 1i64), (n - i), 1.0f64, lbase.sl[f64](a[0usize..], usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), 1i64, 0.0f64, lbase.sl[f64](y[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldy)), 1i64)
                lbase.dgemv("Transpose", ((m - i) + 1i64), (i - 1i64), 1.0f64, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (1i64 - 1i64) * lda)), lda, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), 1i64, 0.0f64, lbase.sl[f64](y[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldy)), 1i64)
                lbase.dgemv("No transpose", (n - i), (i - 1i64), (-1.0f64), lbase.sl[f64](y[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * ldy)), ldy, lbase.sl[f64](y[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldy)), 1i64, 1.0f64, lbase.sl[f64](y[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldy)), 1i64)
                lbase.dgemv("Transpose", ((m - i) + 1i64), (i - 1i64), 1.0f64, lbase.sl[f64](x[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldx)), ldx, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), 1i64, 0.0f64, lbase.sl[f64](y[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldy)), 1i64)
                lbase.dgemv("Transpose", (i - 1i64), (n - i), (-1.0f64), lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, lbase.sl[f64](y[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldy)), 1i64, 1.0f64, lbase.sl[f64](y[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldy)), 1i64)
                lbase.dscal((n - i), tauq[usize((i - 1i64))], lbase.sl[f64](y[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldy)), 1i64)
                lbase.dgemv("No transpose", (n - i), i, (-1.0f64), lbase.sl[f64](y[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * ldy)), ldy, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (1i64 - 1i64) * lda)), lda, 1.0f64, lbase.sl[f64](a[0usize..], usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)), lda)
                lbase.dgemv("Transpose", (i - 1i64), (n - i), (-1.0f64), lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, lbase.sl[f64](x[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldx)), ldx, 1.0f64, lbase.sl[f64](a[0usize..], usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)), lda)
                lbase.dlarfg((n - i), &a[usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)], lbase.sl[f64](a[0usize..], usize((i - 1i64) + (lbase.i_min((i + 2i64), n) - 1i64) * lda)), lda, &taup[usize((i - 1i64))])
                e[usize((i - 1i64))] = a[usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)]
                a[usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)] = 1.0f64
                lbase.dgemv("No transpose", (m - i), (n - i), 1.0f64, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, lbase.sl[f64](a[0usize..], usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, 0.0f64, lbase.sl[f64](x[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldx)), 1i64)
                lbase.dgemv("Transpose", (n - i), i, 1.0f64, lbase.sl[f64](y[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * ldy)), ldy, lbase.sl[f64](a[0usize..], usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, 0.0f64, lbase.sl[f64](x[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldx)), 1i64)
                lbase.dgemv("No transpose", (m - i), i, (-1.0f64), lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * lda)), lda, lbase.sl[f64](x[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldx)), 1i64, 1.0f64, lbase.sl[f64](x[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldx)), 1i64)
                lbase.dgemv("No transpose", (i - 1i64), (n - i), 1.0f64, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, lbase.sl[f64](a[0usize..], usize((i - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, 0.0f64, lbase.sl[f64](x[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldx)), 1i64)
                lbase.dgemv("No transpose", (m - i), (i - 1i64), (-1.0f64), lbase.sl[f64](x[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * ldx)), ldx, lbase.sl[f64](x[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldx)), 1i64, 1.0f64, lbase.sl[f64](x[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldx)), 1i64)
                lbase.dscal((m - i), taup[usize((i - 1i64))], lbase.sl[f64](x[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldx)), 1i64)
            }
            i = i + 1i64
            zc1 = zc1 - 1i64
        }
    } else {
        i = 1i64
        zc2 = (nb - i) + 1i64
        while zc2 > 0i64 {
            lbase.dgemv("No transpose", ((n - i) + 1i64), (i - 1i64), (-1.0f64), lbase.sl[f64](y[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldy)), ldy, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (1i64 - 1i64) * lda)), lda, 1.0f64, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), lda)
            lbase.dgemv("Transpose", (i - 1i64), ((n - i) + 1i64), (-1.0f64), lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), lda, lbase.sl[f64](x[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldx)), ldx, 1.0f64, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), lda)
            lbase.dlarfg(((n - i) + 1i64), &a[usize((i - 1i64) + (i - 1i64) * lda)], lbase.sl[f64](a[0usize..], usize((i - 1i64) + (lbase.i_min((i + 1i64), n) - 1i64) * lda)), lda, &taup[usize((i - 1i64))])
            d[usize((i - 1i64))] = a[usize((i - 1i64) + (i - 1i64) * lda)]
            if (i < m) {
                a[usize((i - 1i64) + (i - 1i64) * lda)] = 1.0f64
                lbase.dgemv("No transpose", (m - i), ((n - i) + 1i64), 1.0f64, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), lda, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), lda, 0.0f64, lbase.sl[f64](x[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldx)), 1i64)
                lbase.dgemv("Transpose", ((n - i) + 1i64), (i - 1i64), 1.0f64, lbase.sl[f64](y[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldy)), ldy, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), lda, 0.0f64, lbase.sl[f64](x[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldx)), 1i64)
                lbase.dgemv("No transpose", (m - i), (i - 1i64), (-1.0f64), lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * lda)), lda, lbase.sl[f64](x[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldx)), 1i64, 1.0f64, lbase.sl[f64](x[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldx)), 1i64)
                lbase.dgemv("No transpose", (i - 1i64), ((n - i) + 1i64), 1.0f64, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), lda, lbase.sl[f64](a[0usize..], usize((i - 1i64) + (i - 1i64) * lda)), lda, 0.0f64, lbase.sl[f64](x[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldx)), 1i64)
                lbase.dgemv("No transpose", (m - i), (i - 1i64), (-1.0f64), lbase.sl[f64](x[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * ldx)), ldx, lbase.sl[f64](x[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldx)), 1i64, 1.0f64, lbase.sl[f64](x[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldx)), 1i64)
                lbase.dscal((m - i), taup[usize((i - 1i64))], lbase.sl[f64](x[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldx)), 1i64)
                lbase.dgemv("No transpose", (m - i), (i - 1i64), (-1.0f64), lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * lda)), lda, lbase.sl[f64](y[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldy)), ldy, 1.0f64, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64)
                lbase.dgemv("No transpose", (m - i), i, (-1.0f64), lbase.sl[f64](x[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * ldx)), ldx, lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (i - 1i64) * lda)), 1i64, 1.0f64, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64)
                lbase.dlarfg((m - i), &a[usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)], lbase.sl[f64](a[0usize..], usize((lbase.i_min((i + 2i64), m) - 1i64) + (i - 1i64) * lda)), 1i64, &tauq[usize((i - 1i64))])
                e[usize((i - 1i64))] = a[usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)]
                a[usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)] = 1.0f64
                lbase.dgemv("Transpose", (m - i), (n - i), 1.0f64, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64, 0.0f64, lbase.sl[f64](y[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldy)), 1i64)
                lbase.dgemv("Transpose", (m - i), (i - 1i64), 1.0f64, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * lda)), lda, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64, 0.0f64, lbase.sl[f64](y[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldy)), 1i64)
                lbase.dgemv("No transpose", (n - i), (i - 1i64), (-1.0f64), lbase.sl[f64](y[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * ldy)), ldy, lbase.sl[f64](y[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldy)), 1i64, 1.0f64, lbase.sl[f64](y[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldy)), 1i64)
                lbase.dgemv("Transpose", (m - i), i, 1.0f64, lbase.sl[f64](x[0usize..], usize(((i + 1i64) - 1i64) + (1i64 - 1i64) * ldx)), ldx, lbase.sl[f64](a[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * lda)), 1i64, 0.0f64, lbase.sl[f64](y[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldy)), 1i64)
                lbase.dgemv("Transpose", i, (n - i), (-1.0f64), lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + ((i + 1i64) - 1i64) * lda)), lda, lbase.sl[f64](y[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldy)), 1i64, 1.0f64, lbase.sl[f64](y[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldy)), 1i64)
                lbase.dscal((n - i), tauq[usize((i - 1i64))], lbase.sl[f64](y[0usize..], usize(((i + 1i64) - 1i64) + (i - 1i64) * ldy)), 1i64)
            }
            i = i + 1i64
            zc2 = zc2 - 1i64
        }
    }
    ret
}

fn dorgbr(vect: str, m: i64, n: i64, k: i64, a: []f64, lda: i64, tau: []f64, work: []f64, lwork: i64, info_ref: *i64) {
    var info = *info_ref
    var lquery: bool = false
    var wantq: bool = false
    var i: i64 = 0i64
    var iinfo: i64 = 0i64
    var j: i64 = 0i64
    var lwkopt: i64 = 0i64
    var mn: i64 = 0i64
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    var zc6: i64 = 0i64
    var zc7: i64 = 0i64
    var zs8: i64 = 0i64
    info = 0i64
    wantq = lbase.lsame(vect, "Q")
    mn = lbase.i_min(m, n)
    lquery = ((lwork == (-1i64)))
    if ((!wantq) && (!lbase.lsame(vect, "P"))) {
        info = (-1i64)
    } else if (m < 0i64) {
        info = (-2i64)
    } else if (((n < 0i64) || ((wantq && (((n > m) || (n < lbase.i_min(m, k))))))) || (((!wantq) && (((m > n) || (m < lbase.i_min(n, k))))))) {
        info = (-3i64)
    } else if (k < 0i64) {
        info = (-4i64)
    } else if (lda < lbase.i_max(1i64, m)) {
        info = (-6i64)
    } else if ((lwork < lbase.i_max(1i64, mn)) && (!lquery)) {
        info = (-9i64)
    }
    if (info == 0i64) {
        work[usize((1i64 - 1i64))] = 1.0f64
        if wantq {
            if (m >= k) {
                lbase.dorgqr(m, n, k, a[0usize..], lda, tau[0usize..], work[0usize..], (-1i64), &iinfo)
            } else {
                if (m > 1i64) {
                    lbase.dorgqr((m - 1i64), (m - 1i64), (m - 1i64), a[0usize..], lda, tau[0usize..], work[0usize..], (-1i64), &iinfo)
                }
            }
        } else {
            if (k < n) {
                lbase.dorglq(m, n, k, a[0usize..], lda, tau[0usize..], work[0usize..], (-1i64), &iinfo)
            } else {
                if (n > 1i64) {
                    lbase.dorglq((n - 1i64), (n - 1i64), (n - 1i64), a[0usize..], lda, tau[0usize..], work[0usize..], (-1i64), &iinfo)
                }
            }
        }
        lwkopt = i64(work[usize((1i64 - 1i64))])
        lwkopt = lbase.i_max(lwkopt, mn)
    }
    if (info != 0i64) {
        *info_ref = info
        ret
    } else if lquery {
        work[usize((1i64 - 1i64))] = f64(lwkopt)
        *info_ref = info
        ret
    }
    if ((m == 0i64) || (n == 0i64)) {
        work[usize((1i64 - 1i64))] = 1.0f64
        *info_ref = info
        ret
    }
    if wantq {
        if (m >= k) {
            lbase.dorgqr(m, n, k, a[0usize..], lda, tau[0usize..], work[0usize..], lwork, &iinfo)
        } else {
            j = m
            zs2 = (-1i64)
            zc1 = ((2i64 - j) + zs2) / zs2
            while zc1 > 0i64 {
                a[usize((1i64 - 1i64) + (j - 1i64) * lda)] = 0.0f64
                i = (j + 1i64)
                zc3 = (m - i) + 1i64
                while zc3 > 0i64 {
                    a[usize((i - 1i64) + (j - 1i64) * lda)] = a[usize((i - 1i64) + ((j - 1i64) - 1i64) * lda)]
                    i = i + 1i64
                    zc3 = zc3 - 1i64
                }
                j = j + zs2
                zc1 = zc1 - 1i64
            }
            a[usize((1i64 - 1i64) + (1i64 - 1i64) * lda)] = 1.0f64
            i = 2i64
            zc4 = (m - i) + 1i64
            while zc4 > 0i64 {
                a[usize((i - 1i64) + (1i64 - 1i64) * lda)] = 0.0f64
                i = i + 1i64
                zc4 = zc4 - 1i64
            }
            if (m > 1i64) {
                lbase.dorgqr((m - 1i64), (m - 1i64), (m - 1i64), lbase.sl[f64](a[0usize..], usize((2i64 - 1i64) + (2i64 - 1i64) * lda)), lda, tau[0usize..], work[0usize..], lwork, &iinfo)
            }
        }
    } else {
        if (k < n) {
            lbase.dorglq(m, n, k, a[0usize..], lda, tau[0usize..], work[0usize..], lwork, &iinfo)
        } else {
            a[usize((1i64 - 1i64) + (1i64 - 1i64) * lda)] = 1.0f64
            i = 2i64
            zc5 = (n - i) + 1i64
            while zc5 > 0i64 {
                a[usize((i - 1i64) + (1i64 - 1i64) * lda)] = 0.0f64
                i = i + 1i64
                zc5 = zc5 - 1i64
            }
            j = 2i64
            zc6 = (n - j) + 1i64
            while zc6 > 0i64 {
                i = (j - 1i64)
                zs8 = (-1i64)
                zc7 = ((2i64 - i) + zs8) / zs8
                while zc7 > 0i64 {
                    a[usize((i - 1i64) + (j - 1i64) * lda)] = a[usize(((i - 1i64) - 1i64) + (j - 1i64) * lda)]
                    i = i + zs8
                    zc7 = zc7 - 1i64
                }
                a[usize((1i64 - 1i64) + (j - 1i64) * lda)] = 0.0f64
                j = j + 1i64
                zc6 = zc6 - 1i64
            }
            if (n > 1i64) {
                lbase.dorglq((n - 1i64), (n - 1i64), (n - 1i64), lbase.sl[f64](a[0usize..], usize((2i64 - 1i64) + (2i64 - 1i64) * lda)), lda, tau[0usize..], work[0usize..], lwork, &iinfo)
            }
        }
    }
    work[usize((1i64 - 1i64))] = f64(lwkopt)
    *info_ref = info
    ret
}

fn dormbr(vect: str, side: str, trans: str, m: i64, n: i64, k: i64, a: []f64, lda: i64, tau: []f64, c: []f64, ldc: i64, work: []f64, lwork: i64, info_ref: *i64) {
    var info = *info_ref
    var applyq: bool = false
    var left: bool = false
    var lquery: bool = false
    var notran: bool = false
    var transt: str = ""
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
    applyq = lbase.lsame(vect, "Q")
    left = lbase.lsame(side, "L")
    notran = lbase.lsame(trans, "N")
    lquery = ((lwork == (-1i64)))
    if left {
        nq = m
        nw = lbase.i_max(1i64, n)
    } else {
        nq = n
        nw = lbase.i_max(1i64, m)
    }
    if ((!applyq) && (!lbase.lsame(vect, "P"))) {
        info = (-1i64)
    } else if ((!left) && (!lbase.lsame(side, "R"))) {
        info = (-2i64)
    } else if ((!notran) && (!lbase.lsame(trans, "T"))) {
        info = (-3i64)
    } else if (m < 0i64) {
        info = (-4i64)
    } else if (n < 0i64) {
        info = (-5i64)
    } else if (k < 0i64) {
        info = (-6i64)
    } else if (((applyq && (lda < lbase.i_max(1i64, nq)))) || (((!applyq) && (lda < lbase.i_max(1i64, lbase.i_min(nq, k)))))) {
        info = (-8i64)
    } else if (ldc < lbase.i_max(1i64, m)) {
        info = (-11i64)
    } else if ((lwork < nw) && (!lquery)) {
        info = (-13i64)
    }
    if (info == 0i64) {
        if applyq {
            if left {
                nb = lbase.ilaenv(1i64, "DORMQR", side, (m - 1i64), n, (m - 1i64), (-1i64))
            } else {
                nb = lbase.ilaenv(1i64, "DORMQR", side, m, (n - 1i64), (n - 1i64), (-1i64))
            }
        } else {
            if left {
                nb = lbase.ilaenv(1i64, "DORMLQ", side, (m - 1i64), n, (m - 1i64), (-1i64))
            } else {
                nb = lbase.ilaenv(1i64, "DORMLQ", side, m, (n - 1i64), (n - 1i64), (-1i64))
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
    work[usize((1i64 - 1i64))] = 1.0f64
    if ((m == 0i64) || (n == 0i64)) {
        *info_ref = info
        ret
    }
    if applyq {
        if (nq >= k) {
            lbase.dormqr(side, trans, m, n, k, a[0usize..], lda, tau[0usize..], c[0usize..], ldc, work[0usize..], lwork, &iinfo)
        } else if (nq > 1i64) {
            if left {
                mi = (m - 1i64)
                ni = n
                i1 = 2i64
                i2 = 1i64
            } else {
                mi = m
                ni = (n - 1i64)
                i1 = 1i64
                i2 = 2i64
            }
            lbase.dormqr(side, trans, mi, ni, (nq - 1i64), lbase.sl[f64](a[0usize..], usize((2i64 - 1i64) + (1i64 - 1i64) * lda)), lda, tau[0usize..], lbase.sl[f64](c[0usize..], usize((i1 - 1i64) + (i2 - 1i64) * ldc)), ldc, work[0usize..], lwork, &iinfo)
        }
    } else {
        if notran {
            transt = "T"
        } else {
            transt = "N"
        }
        if (nq > k) {
            lbase.dormlq(side, transt, m, n, k, a[0usize..], lda, tau[0usize..], c[0usize..], ldc, work[0usize..], lwork, &iinfo)
        } else if (nq > 1i64) {
            if left {
                mi = (m - 1i64)
                ni = n
                i1 = 2i64
                i2 = 1i64
            } else {
                mi = m
                ni = (n - 1i64)
                i1 = 1i64
                i2 = 2i64
            }
            lbase.dormlq(side, transt, mi, ni, (nq - 1i64), lbase.sl[f64](a[0usize..], usize((1i64 - 1i64) + (2i64 - 1i64) * lda)), lda, tau[0usize..], lbase.sl[f64](c[0usize..], usize((i1 - 1i64) + (i2 - 1i64) * ldc)), ldc, work[0usize..], lwork, &iinfo)
        }
    }
    work[usize((1i64 - 1i64))] = f64(lwkopt)
    *info_ref = info
    ret
}

fn dbdsdc(uplo: str, compq: str, n: i64, d: []f64, e: []f64, u: []f64, ldu: i64, vt: []f64, ldvt: i64, q: []f64, iq: []i64, work: []f64, iwork: []i64, info_ref: *i64) {
    var info = *info_ref
    var difl: i64 = 0i64
    var difr: i64 = 0i64
    var givcol: i64 = 0i64
    var givnum: i64 = 0i64
    var givptr: i64 = 0i64
    var i: i64 = 0i64
    var ic: i64 = 0i64
    var icompq: i64 = 0i64
    var ierr: i64 = 0i64
    var ii: i64 = 0i64
    var is: i64 = 0i64
    var iu: i64 = 0i64
    var iuplo: i64 = 0i64
    var ivt: i64 = 0i64
    var j: i64 = 0i64
    var k: i64 = 0i64
    var kk: i64 = 0i64
    var mlvl: i64 = 0i64
    var nm1: i64 = 0i64
    var nsize: i64 = 0i64
    var perm: i64 = 0i64
    var poles: i64 = 0i64
    var qstart: i64 = 0i64
    var smlsiz: i64 = 0i64
    var smlszp: i64 = 0i64
    var sqre: i64 = 0i64
    var start: i64 = 0i64
    var wstart: i64 = 0i64
    var z: i64 = 0i64
    var cs: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var orgnrm: f64 = 0.0f64
    var p: f64 = 0.0f64
    var r: f64 = 0.0f64
    var sn: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            iuplo = 0i64
            if lbase.lsame(uplo, "U") {
                iuplo = 1i64
            }
            if lbase.lsame(uplo, "L") {
                iuplo = 2i64
            }
            if lbase.lsame(compq, "N") {
                icompq = 0i64
            } else if lbase.lsame(compq, "P") {
                icompq = 1i64
            } else if lbase.lsame(compq, "I") {
                icompq = 2i64
            } else {
                icompq = (-1i64)
            }
            if (iuplo == 0i64) {
                info = (-1i64)
            } else if (icompq < 0i64) {
                info = (-2i64)
            } else if (n < 0i64) {
                info = (-3i64)
            } else if (((ldu < 1i64)) || ((((icompq == 2i64)) && ((ldu < n))))) {
                info = (-7i64)
            } else if (((ldvt < 1i64)) || ((((icompq == 2i64)) && ((ldvt < n))))) {
                info = (-9i64)
            }
            if (info != 0i64) {
                *info_ref = info
                ret
            }
            if (n == 0i64) {
                *info_ref = info
                ret
            }
            smlsiz = lbase.ilaenv(9i64, "DBDSDC", " ", 0i64, 0i64, 0i64, 0i64)
            if (n == 1i64) {
                if (icompq == 1i64) {
                    q[usize((1i64 - 1i64))] = lbase.f_sign(1.0f64, d[usize((1i64 - 1i64))])
                    q[usize(((1i64 + (smlsiz * n)) - 1i64))] = 1.0f64
                } else if (icompq == 2i64) {
                    u[usize((1i64 - 1i64) + (1i64 - 1i64) * ldu)] = lbase.f_sign(1.0f64, d[usize((1i64 - 1i64))])
                    vt[usize((1i64 - 1i64) + (1i64 - 1i64) * ldvt)] = 1.0f64
                }
                d[usize((1i64 - 1i64))] = math.abs[f64](d[usize((1i64 - 1i64))])
                *info_ref = info
                ret
            }
            nm1 = (n - 1i64)
            wstart = 1i64
            qstart = 3i64
            if (icompq == 1i64) {
                lbase.dcopy(n, d[0usize..], 1i64, lbase.sl[f64](q[0usize..], usize((1i64 - 1i64))), 1i64)
                lbase.dcopy((n - 1i64), e[0usize..], 1i64, lbase.sl[f64](q[0usize..], usize(((n + 1i64) - 1i64))), 1i64)
            }
            if (iuplo == 2i64) {
                qstart = 5i64
                if (icompq == 2i64) {
                    wstart = ((2i64 * n) - 1i64)
                }
                i = 1i64
                zc1 = ((n - 1i64) - i) + 1i64
                while zc1 > 0i64 {
                    lbase.dlartg(d[usize((i - 1i64))], e[usize((i - 1i64))], &cs, &sn, &r)
                    d[usize((i - 1i64))] = r
                    e[usize((i - 1i64))] = (sn * d[usize(((i + 1i64) - 1i64))])
                    d[usize(((i + 1i64) - 1i64))] = (cs * d[usize(((i + 1i64) - 1i64))])
                    if (icompq == 1i64) {
                        q[usize(((i + (2i64 * n)) - 1i64))] = cs
                        q[usize(((i + (3i64 * n)) - 1i64))] = sn
                    } else if (icompq == 2i64) {
                        work[usize((i - 1i64))] = cs
                        work[usize(((nm1 + i) - 1i64))] = (-sn)
                    }
                    i = i + 1i64
                    zc1 = zc1 - 1i64
                }
            }
            if !(icompq == 0i64) {
                pc = 2i64
                continue
            }
            dlasdq("U", 0i64, n, 0i64, 0i64, 0i64, d[0usize..], e[0usize..], vt[0usize..], ldvt, u[0usize..], ldu, u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), &info)
            pc = 3i64
            continue
        }
        if pc == 2i64 {
            pc = 1i64
        }
        if pc == 1i64 {
            if !(n <= smlsiz) {
                pc = 5i64
                continue
            }
            if (icompq == 2i64) {
                lbase.dlaset("A", n, n, 0.0f64, 1.0f64, u[0usize..], ldu)
                lbase.dlaset("A", n, n, 0.0f64, 1.0f64, vt[0usize..], ldvt)
                dlasdq("U", 0i64, n, n, n, 0i64, d[0usize..], e[0usize..], vt[0usize..], ldvt, u[0usize..], ldu, u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((wstart - 1i64))), &info)
            } else if (icompq == 1i64) {
                iu = 1i64
                ivt = (iu + n)
                lbase.dlaset("A", n, n, 0.0f64, 1.0f64, lbase.sl[f64](q[0usize..], usize(((iu + (((qstart - 1i64)) * n)) - 1i64))), n)
                lbase.dlaset("A", n, n, 0.0f64, 1.0f64, lbase.sl[f64](q[0usize..], usize(((ivt + (((qstart - 1i64)) * n)) - 1i64))), n)
                dlasdq("U", 0i64, n, n, n, 0i64, d[0usize..], e[0usize..], lbase.sl[f64](q[0usize..], usize(((ivt + (((qstart - 1i64)) * n)) - 1i64))), n, lbase.sl[f64](q[0usize..], usize(((iu + (((qstart - 1i64)) * n)) - 1i64))), n, lbase.sl[f64](q[0usize..], usize(((iu + (((qstart - 1i64)) * n)) - 1i64))), n, lbase.sl[f64](work[0usize..], usize((wstart - 1i64))), &info)
            }
            pc = 3i64
            continue
        }
        if pc == 5i64 {
            pc = 4i64
        }
        if pc == 4i64 {
            if (icompq == 2i64) {
                lbase.dlaset("A", n, n, 0.0f64, 1.0f64, u[0usize..], ldu)
                lbase.dlaset("A", n, n, 0.0f64, 1.0f64, vt[0usize..], ldvt)
            }
            orgnrm = lbase.dlanst("M", n, d[0usize..], e[0usize..])
            if (orgnrm == 0.0f64) {
                *info_ref = info
                ret
            }
            lbase.dlascl("G", 0i64, 0i64, orgnrm, 1.0f64, n, 1i64, d[0usize..], n, &ierr)
            lbase.dlascl("G", 0i64, 0i64, orgnrm, 1.0f64, nm1, 1i64, e[0usize..], nm1, &ierr)
            eps = ((0.9f64) * 1.1102230246251565e-16f64)
            mlvl = (i64((math.log[f64]((f64(n) / f64((smlsiz + 1i64)))) / math.log[f64](2.0f64))) + 1i64)
            smlszp = (smlsiz + 1i64)
            if (icompq == 1i64) {
                iu = 1i64
                ivt = (1i64 + smlsiz)
                difl = (ivt + smlszp)
                difr = (difl + mlvl)
                z = (difr + (mlvl * 2i64))
                ic = (z + mlvl)
                is = (ic + 1i64)
                poles = (is + 1i64)
                givnum = (poles + (2i64 * mlvl))
                k = 1i64
                givptr = 2i64
                perm = 3i64
                givcol = (perm + mlvl)
            }
            i = 1i64
            zc2 = (n - i) + 1i64
            while zc2 > 0i64 {
                if (math.abs[f64](d[usize((i - 1i64))]) < eps) {
                    d[usize((i - 1i64))] = lbase.f_sign(eps, d[usize((i - 1i64))])
                }
                i = i + 1i64
                zc2 = zc2 - 1i64
            }
            start = 1i64
            sqre = 0i64
            i = 1i64
            zc3 = (nm1 - i) + 1i64
            while zc3 > 0i64 {
                if (((math.abs[f64](e[usize((i - 1i64))]) < eps)) || ((i == nm1))) {
                    if (i < nm1) {
                        nsize = ((i - start) + 1i64)
                    } else if (math.abs[f64](e[usize((i - 1i64))]) >= eps) {
                        nsize = ((n - start) + 1i64)
                    } else {
                        nsize = ((i - start) + 1i64)
                        if (icompq == 2i64) {
                            u[usize((n - 1i64) + (n - 1i64) * ldu)] = lbase.f_sign(1.0f64, d[usize((n - 1i64))])
                            vt[usize((n - 1i64) + (n - 1i64) * ldvt)] = 1.0f64
                        } else if (icompq == 1i64) {
                            q[usize(((n + (((qstart - 1i64)) * n)) - 1i64))] = lbase.f_sign(1.0f64, d[usize((n - 1i64))])
                            q[usize(((n + ((((smlsiz + qstart) - 1i64)) * n)) - 1i64))] = 1.0f64
                        }
                        d[usize((n - 1i64))] = math.abs[f64](d[usize((n - 1i64))])
                    }
                    if (icompq == 2i64) {
                        dlasd0(nsize, sqre, lbase.sl[f64](d[0usize..], usize((start - 1i64))), lbase.sl[f64](e[0usize..], usize((start - 1i64))), lbase.sl[f64](u[0usize..], usize((start - 1i64) + (start - 1i64) * ldu)), ldu, lbase.sl[f64](vt[0usize..], usize((start - 1i64) + (start - 1i64) * ldvt)), ldvt, smlsiz, iwork[0usize..], lbase.sl[f64](work[0usize..], usize((wstart - 1i64))), &info)
                    } else {
                        dlasda(icompq, smlsiz, nsize, sqre, lbase.sl[f64](d[0usize..], usize((start - 1i64))), lbase.sl[f64](e[0usize..], usize((start - 1i64))), lbase.sl[f64](q[0usize..], usize(((start + ((((iu + qstart) - 2i64)) * n)) - 1i64))), n, lbase.sl[f64](q[0usize..], usize(((start + ((((ivt + qstart) - 2i64)) * n)) - 1i64))), lbase.sl[i64](iq[0usize..], usize(((start + (k * n)) - 1i64))), lbase.sl[f64](q[0usize..], usize(((start + ((((difl + qstart) - 2i64)) * n)) - 1i64))), lbase.sl[f64](q[0usize..], usize(((start + ((((difr + qstart) - 2i64)) * n)) - 1i64))), lbase.sl[f64](q[0usize..], usize(((start + ((((z + qstart) - 2i64)) * n)) - 1i64))), lbase.sl[f64](q[0usize..], usize(((start + ((((poles + qstart) - 2i64)) * n)) - 1i64))), lbase.sl[i64](iq[0usize..], usize(((start + (givptr * n)) - 1i64))), lbase.sl[i64](iq[0usize..], usize(((start + (givcol * n)) - 1i64))), n, lbase.sl[i64](iq[0usize..], usize(((start + (perm * n)) - 1i64))), lbase.sl[f64](q[0usize..], usize(((start + ((((givnum + qstart) - 2i64)) * n)) - 1i64))), lbase.sl[f64](q[0usize..], usize(((start + ((((ic + qstart) - 2i64)) * n)) - 1i64))), lbase.sl[f64](q[0usize..], usize(((start + ((((is + qstart) - 2i64)) * n)) - 1i64))), lbase.sl[f64](work[0usize..], usize((wstart - 1i64))), iwork[0usize..], &info)
                    }
                    if (info != 0i64) {
                        *info_ref = info
                        ret
                    }
                    start = (i + 1i64)
                }
                i = i + 1i64
                zc3 = zc3 - 1i64
            }
            lbase.dlascl("G", 0i64, 0i64, 1.0f64, orgnrm, n, 1i64, d[0usize..], n, &ierr)
            pc = 3i64
        }
        if pc == 3i64 {
            ii = 2i64
            zc4 = (n - ii) + 1i64
            while zc4 > 0i64 {
                i = (ii - 1i64)
                kk = i
                p = d[usize((i - 1i64))]
                j = ii
                zc5 = (n - j) + 1i64
                while zc5 > 0i64 {
                    if (d[usize((j - 1i64))] > p) {
                        kk = j
                        p = d[usize((j - 1i64))]
                    }
                    j = j + 1i64
                    zc5 = zc5 - 1i64
                }
                if (kk != i) {
                    d[usize((kk - 1i64))] = d[usize((i - 1i64))]
                    d[usize((i - 1i64))] = p
                    if (icompq == 1i64) {
                        iq[usize((i - 1i64))] = kk
                    } else if (icompq == 2i64) {
                        lbase.dswap(n, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldu)), 1i64, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (kk - 1i64) * ldu)), 1i64)
                        lbase.dswap(n, lbase.sl[f64](vt[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldvt)), ldvt, lbase.sl[f64](vt[0usize..], usize((kk - 1i64) + (1i64 - 1i64) * ldvt)), ldvt)
                    }
                } else if (icompq == 1i64) {
                    iq[usize((i - 1i64))] = i
                }
                ii = ii + 1i64
                zc4 = zc4 - 1i64
            }
            if (icompq == 1i64) {
                if (iuplo == 1i64) {
                    iq[usize((n - 1i64))] = 1i64
                } else {
                    iq[usize((n - 1i64))] = 0i64
                }
            }
            if (((iuplo == 2i64)) && ((icompq == 2i64))) {
                dlasr("L", "V", "B", n, n, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((n - 1i64))), u[0usize..], ldu)
            }
            *info_ref = info
            ret
        }
    }
}

fn dbdsqr(uplo: str, n: i64, ncvt: i64, nru: i64, ncc: i64, d: []f64, e: []f64, vt: []f64, ldvt: i64, u: []f64, ldu: i64, c: []f64, ldc: i64, work: []f64, info_ref: *i64) {
    var info = *info_ref
    var lower: bool = false
    var rotate: bool = false
    var i: i64 = 0i64
    var idir: i64 = 0i64
    var isub: i64 = 0i64
    var iter: i64 = 0i64
    var iterdivn: i64 = 0i64
    var j: i64 = 0i64
    var ll: i64 = 0i64
    var lll: i64 = 0i64
    var m: i64 = 0i64
    var maxitdivn: i64 = 0i64
    var nm1: i64 = 0i64
    var nm12: i64 = 0i64
    var nm13: i64 = 0i64
    var oldll: i64 = 0i64
    var oldm: i64 = 0i64
    var abse: f64 = 0.0f64
    var abss: f64 = 0.0f64
    var cosl: f64 = 0.0f64
    var cosr: f64 = 0.0f64
    var cs: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var f: f64 = 0.0f64
    var g: f64 = 0.0f64
    var h: f64 = 0.0f64
    var mu: f64 = 0.0f64
    var oldcs: f64 = 0.0f64
    var oldsn: f64 = 0.0f64
    var r: f64 = 0.0f64
    var shift: f64 = 0.0f64
    var sigmn: f64 = 0.0f64
    var sigmx: f64 = 0.0f64
    var sinl: f64 = 0.0f64
    var sinr: f64 = 0.0f64
    var sll: f64 = 0.0f64
    var smax: f64 = 0.0f64
    var smin: f64 = 0.0f64
    var sminoa: f64 = 0.0f64
    var sn: f64 = 0.0f64
    var thresh: f64 = 0.0f64
    var tol: f64 = 0.0f64
    var tolmul: f64 = 0.0f64
    var unfl: f64 = 0.0f64
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
    var zs11: i64 = 0i64
    var zc12: i64 = 0i64
    var zc13: i64 = 0i64
    var zs14: i64 = 0i64
    var zc15: i64 = 0i64
    var zc16: i64 = 0i64
    var zc17: i64 = 0i64
    var zc18: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            lower = lbase.lsame(uplo, "L")
            if ((!lbase.lsame(uplo, "U")) && (!lower)) {
                info = (-1i64)
            } else if (n < 0i64) {
                info = (-2i64)
            } else if (ncvt < 0i64) {
                info = (-3i64)
            } else if (nru < 0i64) {
                info = (-4i64)
            } else if (ncc < 0i64) {
                info = (-5i64)
            } else if ((((ncvt == 0i64) && (ldvt < 1i64))) || (((ncvt > 0i64) && (ldvt < lbase.i_max(1i64, n))))) {
                info = (-9i64)
            } else if (ldu < lbase.i_max(1i64, nru)) {
                info = (-11i64)
            } else if ((((ncc == 0i64) && (ldc < 1i64))) || (((ncc > 0i64) && (ldc < lbase.i_max(1i64, n))))) {
                info = (-13i64)
            }
            if (info != 0i64) {
                *info_ref = info
                ret
            }
            if (n == 0i64) {
                *info_ref = info
                ret
            }
            if !(n == 1i64) {
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
            rotate = ((((ncvt > 0i64)) || ((nru > 0i64))) || ((ncc > 0i64)))
            if (!rotate) {
                lsyevr.dlasq1(n, d[0usize..], e[0usize..], work[0usize..], &info)
                if (info != 2i64) {
                    *info_ref = info
                    ret
                }
                info = 0i64
            }
            nm1 = (n - 1i64)
            nm12 = (nm1 + nm1)
            nm13 = (nm12 + nm1)
            idir = 0i64
            eps = 1.1102230246251565e-16f64
            unfl = 2.2250738585072014e-308f64
            if lower {
                i = 1i64
                zc1 = ((n - 1i64) - i) + 1i64
                while zc1 > 0i64 {
                    lbase.dlartg(d[usize((i - 1i64))], e[usize((i - 1i64))], &cs, &sn, &r)
                    d[usize((i - 1i64))] = r
                    e[usize((i - 1i64))] = (sn * d[usize(((i + 1i64) - 1i64))])
                    d[usize(((i + 1i64) - 1i64))] = (cs * d[usize(((i + 1i64) - 1i64))])
                    work[usize((i - 1i64))] = cs
                    work[usize(((nm1 + i) - 1i64))] = sn
                    i = i + 1i64
                    zc1 = zc1 - 1i64
                }
                if (nru > 0i64) {
                    dlasr("R", "V", "F", nru, n, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((n - 1i64))), u[0usize..], ldu)
                }
                if (ncc > 0i64) {
                    dlasr("L", "V", "F", n, ncc, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((n - 1i64))), c[0usize..], ldc)
                }
            }
            tolmul = lbase.f_max(10.0f64, lbase.f_min(100.0f64, math.pow[f64](eps, (-0.125f64))))
            tol = (tolmul * eps)
            smax = 0.0f64
            i = 1i64
            zc2 = (n - i) + 1i64
            while zc2 > 0i64 {
                smax = lbase.f_max(smax, math.abs[f64](d[usize((i - 1i64))]))
                i = i + 1i64
                zc2 = zc2 - 1i64
            }
            i = 1i64
            zc3 = ((n - 1i64) - i) + 1i64
            while zc3 > 0i64 {
                smax = lbase.f_max(smax, math.abs[f64](e[usize((i - 1i64))]))
                i = i + 1i64
                zc3 = zc3 - 1i64
            }
            smin = 0.0f64
            if !(tol >= 0.0f64) {
                pc = 5i64
                continue
            }
            sminoa = math.abs[f64](d[usize((1i64 - 1i64))])
            if !(sminoa == 0.0f64) {
                pc = 7i64
                continue
            }
            pc = 8i64
            continue
        }
        if pc == 7i64 {
            pc = 6i64
        }
        if pc == 6i64 {
            mu = sminoa
            i = 2i64
            zc4 = (n - i) + 1i64
            pc = 9i64
        }
        if pc == 9i64 {
            if zc4 <= 0i64 {
                pc = 10i64
                continue
            }
            mu = (math.abs[f64](d[usize((i - 1i64))]) * ((mu / ((mu + math.abs[f64](e[usize(((i - 1i64) - 1i64))]))))))
            sminoa = lbase.f_min(sminoa, mu)
            if !(sminoa == 0.0f64) {
                pc = 12i64
                continue
            }
            pc = 8i64
            continue
        }
        if pc == 12i64 {
            pc = 11i64
        }
        if pc == 11i64 {
            i = i + 1i64
            zc4 = zc4 - 1i64
            pc = 9i64
            continue
        }
        if pc == 10i64 {
            pc = 8i64
        }
        if pc == 8i64 {
            sminoa = (sminoa / math.sqrt[f64](f64(n)))
            thresh = lbase.f_max((tol * sminoa), (6.0f64 * ((f64(n) * ((f64(n) * unfl))))))
            pc = 4i64
            continue
        }
        if pc == 5i64 {
            thresh = lbase.f_max((math.abs[f64](tol) * smax), (6.0f64 * ((f64(n) * ((f64(n) * unfl))))))
            pc = 4i64
            continue
        }
        if pc == 4i64 {
            maxitdivn = (6i64 * n)
            iterdivn = 0i64
            iter = (-1i64)
            oldll = (-1i64)
            oldm = (-1i64)
            m = n
            pc = 13i64
        }
        if pc == 13i64 {
            if !(m <= 1i64) {
                pc = 15i64
                continue
            }
            pc = 3i64
            continue
        }
        if pc == 15i64 {
            pc = 14i64
        }
        if pc == 14i64 {
            if !(iter >= n) {
                pc = 17i64
                continue
            }
            iter = (iter - n)
            iterdivn = (iterdivn + 1i64)
            if !(iterdivn >= maxitdivn) {
                pc = 19i64
                continue
            }
            pc = 20i64
            continue
        }
        if pc == 19i64 {
            pc = 18i64
        }
        if pc == 18i64 {
            pc = 16i64
            continue
        }
        if pc == 17i64 {
            pc = 16i64
        }
        if pc == 16i64 {
            if ((tol < 0.0f64) && (math.abs[f64](d[usize((m - 1i64))]) <= thresh)) {
                d[usize((m - 1i64))] = 0.0f64
            }
            smax = math.abs[f64](d[usize((m - 1i64))])
            lll = 1i64
            zc5 = ((m - 1i64) - lll) + 1i64
            pc = 21i64
        }
        if pc == 21i64 {
            if zc5 <= 0i64 {
                pc = 22i64
                continue
            }
            ll = (m - lll)
            abss = math.abs[f64](d[usize((ll - 1i64))])
            abse = math.abs[f64](e[usize((ll - 1i64))])
            if ((tol < 0.0f64) && (abss <= thresh)) {
                d[usize((ll - 1i64))] = 0.0f64
            }
            if !(abse <= thresh) {
                pc = 24i64
                continue
            }
            pc = 25i64
            continue
        }
        if pc == 24i64 {
            pc = 23i64
        }
        if pc == 23i64 {
            smax = lbase.f_max(lbase.f_max(smax, abss), abse)
            lll = lll + 1i64
            zc5 = zc5 - 1i64
            pc = 21i64
            continue
        }
        if pc == 22i64 {
            ll = 0i64
            pc = 26i64
            continue
        }
        if pc == 25i64 {
            e[usize((ll - 1i64))] = 0.0f64
            if !(ll == (m - 1i64)) {
                pc = 28i64
                continue
            }
            m = (m - 1i64)
            pc = 13i64
            continue
        }
        if pc == 28i64 {
            pc = 27i64
        }
        if pc == 27i64 {
            pc = 26i64
        }
        if pc == 26i64 {
            ll = (ll + 1i64)
            if !(ll == (m - 1i64)) {
                pc = 30i64
                continue
            }
            lbase.dlasv2(d[usize(((m - 1i64) - 1i64))], e[usize(((m - 1i64) - 1i64))], d[usize((m - 1i64))], &sigmn, &sigmx, &sinr, &cosr, &sinl, &cosl)
            d[usize(((m - 1i64) - 1i64))] = sigmx
            e[usize(((m - 1i64) - 1i64))] = 0.0f64
            d[usize((m - 1i64))] = sigmn
            if (ncvt > 0i64) {
                lbase.drot(ncvt, lbase.sl[f64](vt[0usize..], usize(((m - 1i64) - 1i64) + (1i64 - 1i64) * ldvt)), ldvt, lbase.sl[f64](vt[0usize..], usize((m - 1i64) + (1i64 - 1i64) * ldvt)), ldvt, cosr, sinr)
            }
            if (nru > 0i64) {
                lbase.drot(nru, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + ((m - 1i64) - 1i64) * ldu)), 1i64, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (m - 1i64) * ldu)), 1i64, cosl, sinl)
            }
            if (ncc > 0i64) {
                lbase.drot(ncc, lbase.sl[f64](c[0usize..], usize(((m - 1i64) - 1i64) + (1i64 - 1i64) * ldc)), ldc, lbase.sl[f64](c[0usize..], usize((m - 1i64) + (1i64 - 1i64) * ldc)), ldc, cosl, sinl)
            }
            m = (m - 2i64)
            pc = 13i64
            continue
        }
        if pc == 30i64 {
            pc = 29i64
        }
        if pc == 29i64 {
            if ((ll > oldm) || (m < oldll)) {
                if (math.abs[f64](d[usize((ll - 1i64))]) >= math.abs[f64](d[usize((m - 1i64))])) {
                    idir = 1i64
                } else {
                    idir = 2i64
                }
            }
            if !(idir == 1i64) {
                pc = 32i64
                continue
            }
            if !((math.abs[f64](e[usize(((m - 1i64) - 1i64))]) <= (math.abs[f64](tol) * math.abs[f64](d[usize((m - 1i64))]))) || (((tol < 0.0f64) && (math.abs[f64](e[usize(((m - 1i64) - 1i64))]) <= thresh)))) {
                pc = 34i64
                continue
            }
            e[usize(((m - 1i64) - 1i64))] = 0.0f64
            pc = 13i64
            continue
        }
        if pc == 34i64 {
            pc = 33i64
        }
        if pc == 33i64 {
            if !(tol >= 0.0f64) {
                pc = 36i64
                continue
            }
            mu = math.abs[f64](d[usize((ll - 1i64))])
            smin = mu
            lll = ll
            zc6 = ((m - 1i64) - lll) + 1i64
            pc = 37i64
        }
        if pc == 37i64 {
            if zc6 <= 0i64 {
                pc = 38i64
                continue
            }
            if !(math.abs[f64](e[usize((lll - 1i64))]) <= (tol * mu)) {
                pc = 40i64
                continue
            }
            e[usize((lll - 1i64))] = 0.0f64
            pc = 13i64
            continue
        }
        if pc == 40i64 {
            pc = 39i64
        }
        if pc == 39i64 {
            mu = (math.abs[f64](d[usize(((lll + 1i64) - 1i64))]) * ((mu / ((mu + math.abs[f64](e[usize((lll - 1i64))]))))))
            smin = lbase.f_min(smin, mu)
            lll = lll + 1i64
            zc6 = zc6 - 1i64
            pc = 37i64
            continue
        }
        if pc == 38i64 {
            pc = 35i64
            continue
        }
        if pc == 36i64 {
            pc = 35i64
        }
        if pc == 35i64 {
            pc = 31i64
            continue
        }
        if pc == 32i64 {
            if !((math.abs[f64](e[usize((ll - 1i64))]) <= (math.abs[f64](tol) * math.abs[f64](d[usize((ll - 1i64))]))) || (((tol < 0.0f64) && (math.abs[f64](e[usize((ll - 1i64))]) <= thresh)))) {
                pc = 42i64
                continue
            }
            e[usize((ll - 1i64))] = 0.0f64
            pc = 13i64
            continue
        }
        if pc == 42i64 {
            pc = 41i64
        }
        if pc == 41i64 {
            if !(tol >= 0.0f64) {
                pc = 44i64
                continue
            }
            mu = math.abs[f64](d[usize((m - 1i64))])
            smin = mu
            lll = (m - 1i64)
            zs8 = (-1i64)
            zc7 = ((ll - lll) + zs8) / zs8
            pc = 45i64
        }
        if pc == 45i64 {
            if zc7 <= 0i64 {
                pc = 46i64
                continue
            }
            if !(math.abs[f64](e[usize((lll - 1i64))]) <= (tol * mu)) {
                pc = 48i64
                continue
            }
            e[usize((lll - 1i64))] = 0.0f64
            pc = 13i64
            continue
        }
        if pc == 48i64 {
            pc = 47i64
        }
        if pc == 47i64 {
            mu = (math.abs[f64](d[usize((lll - 1i64))]) * ((mu / ((mu + math.abs[f64](e[usize((lll - 1i64))]))))))
            smin = lbase.f_min(smin, mu)
            lll = lll + zs8
            zc7 = zc7 - 1i64
            pc = 45i64
            continue
        }
        if pc == 46i64 {
            pc = 43i64
            continue
        }
        if pc == 44i64 {
            pc = 43i64
        }
        if pc == 43i64 {
            pc = 31i64
            continue
        }
        if pc == 31i64 {
            oldll = ll
            oldm = m
            if ((tol >= 0.0f64) && (((f64(n) * tol) * ((smin / smax))) <= lbase.f_max(eps, (0.01f64 * tol)))) {
                shift = 0.0f64
            } else {
                if (idir == 1i64) {
                    sll = math.abs[f64](d[usize((ll - 1i64))])
                    lbase.dlas2(d[usize(((m - 1i64) - 1i64))], e[usize(((m - 1i64) - 1i64))], d[usize((m - 1i64))], &shift, &r)
                } else {
                    sll = math.abs[f64](d[usize((m - 1i64))])
                    lbase.dlas2(d[usize((ll - 1i64))], e[usize((ll - 1i64))], d[usize(((ll + 1i64) - 1i64))], &shift, &r)
                }
                if (sll > 0.0f64) {
                    if (((((shift / sll))) * (((shift / sll)))) < eps) {
                        shift = 0.0f64
                    }
                }
            }
            iter = ((iter + m) - ll)
            if (shift == 0.0f64) {
                if (idir == 1i64) {
                    cs = 1.0f64
                    oldcs = 1.0f64
                    i = ll
                    zc9 = ((m - 1i64) - i) + 1i64
                    while zc9 > 0i64 {
                        lbase.dlartg((d[usize((i - 1i64))] * cs), e[usize((i - 1i64))], &cs, &sn, &r)
                        if (i > ll) {
                            e[usize(((i - 1i64) - 1i64))] = (oldsn * r)
                        }
                        lbase.dlartg((oldcs * r), (d[usize(((i + 1i64) - 1i64))] * sn), &oldcs, &oldsn, &d[usize((i - 1i64))])
                        work[usize((((i - ll) + 1i64) - 1i64))] = cs
                        work[usize(((((i - ll) + 1i64) + nm1) - 1i64))] = sn
                        work[usize(((((i - ll) + 1i64) + nm12) - 1i64))] = oldcs
                        work[usize(((((i - ll) + 1i64) + nm13) - 1i64))] = oldsn
                        i = i + 1i64
                        zc9 = zc9 - 1i64
                    }
                    h = (d[usize((m - 1i64))] * cs)
                    d[usize((m - 1i64))] = (h * oldcs)
                    e[usize(((m - 1i64) - 1i64))] = (h * oldsn)
                    if (ncvt > 0i64) {
                        dlasr("L", "V", "F", ((m - ll) + 1i64), ncvt, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((n - 1i64))), lbase.sl[f64](vt[0usize..], usize((ll - 1i64) + (1i64 - 1i64) * ldvt)), ldvt)
                    }
                    if (nru > 0i64) {
                        dlasr("R", "V", "F", nru, ((m - ll) + 1i64), lbase.sl[f64](work[0usize..], usize(((nm12 + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize(((nm13 + 1i64) - 1i64))), lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (ll - 1i64) * ldu)), ldu)
                    }
                    if (ncc > 0i64) {
                        dlasr("L", "V", "F", ((m - ll) + 1i64), ncc, lbase.sl[f64](work[0usize..], usize(((nm12 + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize(((nm13 + 1i64) - 1i64))), lbase.sl[f64](c[0usize..], usize((ll - 1i64) + (1i64 - 1i64) * ldc)), ldc)
                    }
                    if (math.abs[f64](e[usize(((m - 1i64) - 1i64))]) <= thresh) {
                        e[usize(((m - 1i64) - 1i64))] = 0.0f64
                    }
                } else {
                    cs = 1.0f64
                    oldcs = 1.0f64
                    i = m
                    zs11 = (-1i64)
                    zc10 = (((ll + 1i64) - i) + zs11) / zs11
                    while zc10 > 0i64 {
                        lbase.dlartg((d[usize((i - 1i64))] * cs), e[usize(((i - 1i64) - 1i64))], &cs, &sn, &r)
                        if (i < m) {
                            e[usize((i - 1i64))] = (oldsn * r)
                        }
                        lbase.dlartg((oldcs * r), (d[usize(((i - 1i64) - 1i64))] * sn), &oldcs, &oldsn, &d[usize((i - 1i64))])
                        work[usize(((i - ll) - 1i64))] = cs
                        work[usize((((i - ll) + nm1) - 1i64))] = (-sn)
                        work[usize((((i - ll) + nm12) - 1i64))] = oldcs
                        work[usize((((i - ll) + nm13) - 1i64))] = (-oldsn)
                        i = i + zs11
                        zc10 = zc10 - 1i64
                    }
                    h = (d[usize((ll - 1i64))] * cs)
                    d[usize((ll - 1i64))] = (h * oldcs)
                    e[usize((ll - 1i64))] = (h * oldsn)
                    if (ncvt > 0i64) {
                        dlasr("L", "V", "B", ((m - ll) + 1i64), ncvt, lbase.sl[f64](work[0usize..], usize(((nm12 + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize(((nm13 + 1i64) - 1i64))), lbase.sl[f64](vt[0usize..], usize((ll - 1i64) + (1i64 - 1i64) * ldvt)), ldvt)
                    }
                    if (nru > 0i64) {
                        dlasr("R", "V", "B", nru, ((m - ll) + 1i64), lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((n - 1i64))), lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (ll - 1i64) * ldu)), ldu)
                    }
                    if (ncc > 0i64) {
                        dlasr("L", "V", "B", ((m - ll) + 1i64), ncc, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((n - 1i64))), lbase.sl[f64](c[0usize..], usize((ll - 1i64) + (1i64 - 1i64) * ldc)), ldc)
                    }
                    if (math.abs[f64](e[usize((ll - 1i64))]) <= thresh) {
                        e[usize((ll - 1i64))] = 0.0f64
                    }
                }
            } else {
                if (idir == 1i64) {
                    f = (((math.abs[f64](d[usize((ll - 1i64))]) - shift)) * ((lbase.f_sign(1.0f64, d[usize((ll - 1i64))]) + (shift / d[usize((ll - 1i64))]))))
                    g = e[usize((ll - 1i64))]
                    i = ll
                    zc12 = ((m - 1i64) - i) + 1i64
                    while zc12 > 0i64 {
                        lbase.dlartg(f, g, &cosr, &sinr, &r)
                        if (i > ll) {
                            e[usize(((i - 1i64) - 1i64))] = r
                        }
                        f = ((cosr * d[usize((i - 1i64))]) + (sinr * e[usize((i - 1i64))]))
                        e[usize((i - 1i64))] = ((cosr * e[usize((i - 1i64))]) - (sinr * d[usize((i - 1i64))]))
                        g = (sinr * d[usize(((i + 1i64) - 1i64))])
                        d[usize(((i + 1i64) - 1i64))] = (cosr * d[usize(((i + 1i64) - 1i64))])
                        lbase.dlartg(f, g, &cosl, &sinl, &r)
                        d[usize((i - 1i64))] = r
                        f = ((cosl * e[usize((i - 1i64))]) + (sinl * d[usize(((i + 1i64) - 1i64))]))
                        d[usize(((i + 1i64) - 1i64))] = ((cosl * d[usize(((i + 1i64) - 1i64))]) - (sinl * e[usize((i - 1i64))]))
                        if (i < (m - 1i64)) {
                            g = (sinl * e[usize(((i + 1i64) - 1i64))])
                            e[usize(((i + 1i64) - 1i64))] = (cosl * e[usize(((i + 1i64) - 1i64))])
                        }
                        work[usize((((i - ll) + 1i64) - 1i64))] = cosr
                        work[usize(((((i - ll) + 1i64) + nm1) - 1i64))] = sinr
                        work[usize(((((i - ll) + 1i64) + nm12) - 1i64))] = cosl
                        work[usize(((((i - ll) + 1i64) + nm13) - 1i64))] = sinl
                        i = i + 1i64
                        zc12 = zc12 - 1i64
                    }
                    e[usize(((m - 1i64) - 1i64))] = f
                    if (ncvt > 0i64) {
                        dlasr("L", "V", "F", ((m - ll) + 1i64), ncvt, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((n - 1i64))), lbase.sl[f64](vt[0usize..], usize((ll - 1i64) + (1i64 - 1i64) * ldvt)), ldvt)
                    }
                    if (nru > 0i64) {
                        dlasr("R", "V", "F", nru, ((m - ll) + 1i64), lbase.sl[f64](work[0usize..], usize(((nm12 + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize(((nm13 + 1i64) - 1i64))), lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (ll - 1i64) * ldu)), ldu)
                    }
                    if (ncc > 0i64) {
                        dlasr("L", "V", "F", ((m - ll) + 1i64), ncc, lbase.sl[f64](work[0usize..], usize(((nm12 + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize(((nm13 + 1i64) - 1i64))), lbase.sl[f64](c[0usize..], usize((ll - 1i64) + (1i64 - 1i64) * ldc)), ldc)
                    }
                    if (math.abs[f64](e[usize(((m - 1i64) - 1i64))]) <= thresh) {
                        e[usize(((m - 1i64) - 1i64))] = 0.0f64
                    }
                } else {
                    f = (((math.abs[f64](d[usize((m - 1i64))]) - shift)) * ((lbase.f_sign(1.0f64, d[usize((m - 1i64))]) + (shift / d[usize((m - 1i64))]))))
                    g = e[usize(((m - 1i64) - 1i64))]
                    i = m
                    zs14 = (-1i64)
                    zc13 = (((ll + 1i64) - i) + zs14) / zs14
                    while zc13 > 0i64 {
                        lbase.dlartg(f, g, &cosr, &sinr, &r)
                        if (i < m) {
                            e[usize((i - 1i64))] = r
                        }
                        f = ((cosr * d[usize((i - 1i64))]) + (sinr * e[usize(((i - 1i64) - 1i64))]))
                        e[usize(((i - 1i64) - 1i64))] = ((cosr * e[usize(((i - 1i64) - 1i64))]) - (sinr * d[usize((i - 1i64))]))
                        g = (sinr * d[usize(((i - 1i64) - 1i64))])
                        d[usize(((i - 1i64) - 1i64))] = (cosr * d[usize(((i - 1i64) - 1i64))])
                        lbase.dlartg(f, g, &cosl, &sinl, &r)
                        d[usize((i - 1i64))] = r
                        f = ((cosl * e[usize(((i - 1i64) - 1i64))]) + (sinl * d[usize(((i - 1i64) - 1i64))]))
                        d[usize(((i - 1i64) - 1i64))] = ((cosl * d[usize(((i - 1i64) - 1i64))]) - (sinl * e[usize(((i - 1i64) - 1i64))]))
                        if (i > (ll + 1i64)) {
                            g = (sinl * e[usize(((i - 2i64) - 1i64))])
                            e[usize(((i - 2i64) - 1i64))] = (cosl * e[usize(((i - 2i64) - 1i64))])
                        }
                        work[usize(((i - ll) - 1i64))] = cosr
                        work[usize((((i - ll) + nm1) - 1i64))] = (-sinr)
                        work[usize((((i - ll) + nm12) - 1i64))] = cosl
                        work[usize((((i - ll) + nm13) - 1i64))] = (-sinl)
                        i = i + zs14
                        zc13 = zc13 - 1i64
                    }
                    e[usize((ll - 1i64))] = f
                    if (math.abs[f64](e[usize((ll - 1i64))]) <= thresh) {
                        e[usize((ll - 1i64))] = 0.0f64
                    }
                    if (ncvt > 0i64) {
                        dlasr("L", "V", "B", ((m - ll) + 1i64), ncvt, lbase.sl[f64](work[0usize..], usize(((nm12 + 1i64) - 1i64))), lbase.sl[f64](work[0usize..], usize(((nm13 + 1i64) - 1i64))), lbase.sl[f64](vt[0usize..], usize((ll - 1i64) + (1i64 - 1i64) * ldvt)), ldvt)
                    }
                    if (nru > 0i64) {
                        dlasr("R", "V", "B", nru, ((m - ll) + 1i64), lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((n - 1i64))), lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (ll - 1i64) * ldu)), ldu)
                    }
                    if (ncc > 0i64) {
                        dlasr("L", "V", "B", ((m - ll) + 1i64), ncc, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((n - 1i64))), lbase.sl[f64](c[0usize..], usize((ll - 1i64) + (1i64 - 1i64) * ldc)), ldc)
                    }
                }
            }
            pc = 13i64
            continue
        }
        if pc == 3i64 {
            i = 1i64
            zc15 = (n - i) + 1i64
            while zc15 > 0i64 {
                if (d[usize((i - 1i64))] == 0.0f64) {
                    d[usize((i - 1i64))] = 0.0f64
                }
                if (d[usize((i - 1i64))] < 0.0f64) {
                    d[usize((i - 1i64))] = (-d[usize((i - 1i64))])
                    if (ncvt > 0i64) {
                        lbase.dscal(ncvt, (-1.0f64), lbase.sl[f64](vt[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldvt)), ldvt)
                    }
                }
                i = i + 1i64
                zc15 = zc15 - 1i64
            }
            i = 1i64
            zc16 = ((n - 1i64) - i) + 1i64
            while zc16 > 0i64 {
                isub = 1i64
                smin = d[usize((1i64 - 1i64))]
                j = 2i64
                zc17 = (((n + 1i64) - i) - j) + 1i64
                while zc17 > 0i64 {
                    if (d[usize((j - 1i64))] <= smin) {
                        isub = j
                        smin = d[usize((j - 1i64))]
                    }
                    j = j + 1i64
                    zc17 = zc17 - 1i64
                }
                if (isub != ((n + 1i64) - i)) {
                    d[usize((isub - 1i64))] = d[usize((((n + 1i64) - i) - 1i64))]
                    d[usize((((n + 1i64) - i) - 1i64))] = smin
                    if (ncvt > 0i64) {
                        lbase.dswap(ncvt, lbase.sl[f64](vt[0usize..], usize((isub - 1i64) + (1i64 - 1i64) * ldvt)), ldvt, lbase.sl[f64](vt[0usize..], usize((((n + 1i64) - i) - 1i64) + (1i64 - 1i64) * ldvt)), ldvt)
                    }
                    if (nru > 0i64) {
                        lbase.dswap(nru, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (isub - 1i64) * ldu)), 1i64, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (((n + 1i64) - i) - 1i64) * ldu)), 1i64)
                    }
                    if (ncc > 0i64) {
                        lbase.dswap(ncc, lbase.sl[f64](c[0usize..], usize((isub - 1i64) + (1i64 - 1i64) * ldc)), ldc, lbase.sl[f64](c[0usize..], usize((((n + 1i64) - i) - 1i64) + (1i64 - 1i64) * ldc)), ldc)
                    }
                }
                i = i + 1i64
                zc16 = zc16 - 1i64
            }
            pc = 49i64
            continue
        }
        if pc == 20i64 {
            info = 0i64
            i = 1i64
            zc18 = ((n - 1i64) - i) + 1i64
            while zc18 > 0i64 {
                if (e[usize((i - 1i64))] != 0.0f64) {
                    info = (info + 1i64)
                }
                i = i + 1i64
                zc18 = zc18 - 1i64
            }
            pc = 49i64
        }
        if pc == 49i64 {
            *info_ref = info
            ret
        }
    }
}

fn dlasdq(uplo: str, sqre: i64, n: i64, ncvt: i64, nru: i64, ncc: i64, d: []f64, e: []f64, vt: []f64, ldvt: i64, u: []f64, ldu: i64, c: []f64, ldc: i64, work: []f64, info_ref: *i64) {
    var info = *info_ref
    var rotate: bool = false
    var i: i64 = 0i64
    var isub: i64 = 0i64
    var iuplo: i64 = 0i64
    var j: i64 = 0i64
    var np1: i64 = 0i64
    var sqre1: i64 = 0i64
    var cs: f64 = 0.0f64
    var r: f64 = 0.0f64
    var smin: f64 = 0.0f64
    var sn: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    info = 0i64
    iuplo = 0i64
    if lbase.lsame(uplo, "U") {
        iuplo = 1i64
    }
    if lbase.lsame(uplo, "L") {
        iuplo = 2i64
    }
    if (iuplo == 0i64) {
        info = (-1i64)
    } else if (((sqre < 0i64)) || ((sqre > 1i64))) {
        info = (-2i64)
    } else if (n < 0i64) {
        info = (-3i64)
    } else if (ncvt < 0i64) {
        info = (-4i64)
    } else if (nru < 0i64) {
        info = (-5i64)
    } else if (ncc < 0i64) {
        info = (-6i64)
    } else if ((((ncvt == 0i64) && (ldvt < 1i64))) || (((ncvt > 0i64) && (ldvt < lbase.i_max(1i64, n))))) {
        info = (-10i64)
    } else if (ldu < lbase.i_max(1i64, nru)) {
        info = (-12i64)
    } else if ((((ncc == 0i64) && (ldc < 1i64))) || (((ncc > 0i64) && (ldc < lbase.i_max(1i64, n))))) {
        info = (-14i64)
    }
    if (info != 0i64) {
        *info_ref = info
        ret
    }
    if (n == 0i64) {
        *info_ref = info
        ret
    }
    rotate = ((((ncvt > 0i64)) || ((nru > 0i64))) || ((ncc > 0i64)))
    np1 = (n + 1i64)
    sqre1 = sqre
    if (((iuplo == 1i64)) && ((sqre1 == 1i64))) {
        i = 1i64
        zc1 = ((n - 1i64) - i) + 1i64
        while zc1 > 0i64 {
            lbase.dlartg(d[usize((i - 1i64))], e[usize((i - 1i64))], &cs, &sn, &r)
            d[usize((i - 1i64))] = r
            e[usize((i - 1i64))] = (sn * d[usize(((i + 1i64) - 1i64))])
            d[usize(((i + 1i64) - 1i64))] = (cs * d[usize(((i + 1i64) - 1i64))])
            if rotate {
                work[usize((i - 1i64))] = cs
                work[usize(((n + i) - 1i64))] = sn
            }
            i = i + 1i64
            zc1 = zc1 - 1i64
        }
        lbase.dlartg(d[usize((n - 1i64))], e[usize((n - 1i64))], &cs, &sn, &r)
        d[usize((n - 1i64))] = r
        e[usize((n - 1i64))] = 0.0f64
        if rotate {
            work[usize((n - 1i64))] = cs
            work[usize(((n + n) - 1i64))] = sn
        }
        iuplo = 2i64
        sqre1 = 0i64
        if (ncvt > 0i64) {
            dlasr("L", "V", "F", np1, ncvt, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((np1 - 1i64))), vt[0usize..], ldvt)
        }
    }
    if (iuplo == 2i64) {
        i = 1i64
        zc2 = ((n - 1i64) - i) + 1i64
        while zc2 > 0i64 {
            lbase.dlartg(d[usize((i - 1i64))], e[usize((i - 1i64))], &cs, &sn, &r)
            d[usize((i - 1i64))] = r
            e[usize((i - 1i64))] = (sn * d[usize(((i + 1i64) - 1i64))])
            d[usize(((i + 1i64) - 1i64))] = (cs * d[usize(((i + 1i64) - 1i64))])
            if rotate {
                work[usize((i - 1i64))] = cs
                work[usize(((n + i) - 1i64))] = sn
            }
            i = i + 1i64
            zc2 = zc2 - 1i64
        }
        if (sqre1 == 1i64) {
            lbase.dlartg(d[usize((n - 1i64))], e[usize((n - 1i64))], &cs, &sn, &r)
            d[usize((n - 1i64))] = r
            if rotate {
                work[usize((n - 1i64))] = cs
                work[usize(((n + n) - 1i64))] = sn
            }
        }
        if (nru > 0i64) {
            if (sqre1 == 0i64) {
                dlasr("R", "V", "F", nru, n, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((np1 - 1i64))), u[0usize..], ldu)
            } else {
                dlasr("R", "V", "F", nru, np1, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((np1 - 1i64))), u[0usize..], ldu)
            }
        }
        if (ncc > 0i64) {
            if (sqre1 == 0i64) {
                dlasr("L", "V", "F", n, ncc, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((np1 - 1i64))), c[0usize..], ldc)
            } else {
                dlasr("L", "V", "F", np1, ncc, lbase.sl[f64](work[0usize..], usize((1i64 - 1i64))), lbase.sl[f64](work[0usize..], usize((np1 - 1i64))), c[0usize..], ldc)
            }
        }
    }
    dbdsqr("U", n, ncvt, nru, ncc, d[0usize..], e[0usize..], vt[0usize..], ldvt, u[0usize..], ldu, c[0usize..], ldc, work[0usize..], &info)
    i = 1i64
    zc3 = (n - i) + 1i64
    while zc3 > 0i64 {
        isub = i
        smin = d[usize((i - 1i64))]
        j = (i + 1i64)
        zc4 = (n - j) + 1i64
        while zc4 > 0i64 {
            if (d[usize((j - 1i64))] < smin) {
                isub = j
                smin = d[usize((j - 1i64))]
            }
            j = j + 1i64
            zc4 = zc4 - 1i64
        }
        if (isub != i) {
            d[usize((isub - 1i64))] = d[usize((i - 1i64))]
            d[usize((i - 1i64))] = smin
            if (ncvt > 0i64) {
                lbase.dswap(ncvt, lbase.sl[f64](vt[0usize..], usize((isub - 1i64) + (1i64 - 1i64) * ldvt)), ldvt, lbase.sl[f64](vt[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldvt)), ldvt)
            }
            if (nru > 0i64) {
                lbase.dswap(nru, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (isub - 1i64) * ldu)), 1i64, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldu)), 1i64)
            }
            if (ncc > 0i64) {
                lbase.dswap(ncc, lbase.sl[f64](c[0usize..], usize((isub - 1i64) + (1i64 - 1i64) * ldc)), ldc, lbase.sl[f64](c[0usize..], usize((i - 1i64) + (1i64 - 1i64) * ldc)), ldc)
            }
        }
        i = i + 1i64
        zc3 = zc3 - 1i64
    }
    *info_ref = info
    ret
}

fn dlasd0(n: i64, sqre: i64, d: []f64, e: []f64, u: []f64, ldu: i64, vt: []f64, ldvt: i64, smlsiz: i64, iwork: []i64, work: []f64, info_ref: *i64) {
    var info = *info_ref
    var i: i64 = 0i64
    var i1: i64 = 0i64
    var ic: i64 = 0i64
    var idxq: i64 = 0i64
    var idxqc: i64 = 0i64
    var im1: i64 = 0i64
    var inode: i64 = 0i64
    var itemp: i64 = 0i64
    var iwk: i64 = 0i64
    var j: i64 = 0i64
    var lf: i64 = 0i64
    var ll: i64 = 0i64
    var lvl: i64 = 0i64
    var m: i64 = 0i64
    var ncc: i64 = 0i64
    var nd: i64 = 0i64
    var ndb1: i64 = 0i64
    var ndiml: i64 = 0i64
    var ndimr: i64 = 0i64
    var nl: i64 = 0i64
    var nlf: i64 = 0i64
    var nlp1: i64 = 0i64
    var nlvl: i64 = 0i64
    var nr: i64 = 0i64
    var nrf: i64 = 0i64
    var nrp1: i64 = 0i64
    var sqrei: i64 = 0i64
    var alpha: f64 = 0.0f64
    var beta: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zs5: i64 = 0i64
    var zc6: i64 = 0i64
    info = 0i64
    if (n < 0i64) {
        info = (-1i64)
    } else if (((sqre < 0i64)) || ((sqre > 1i64))) {
        info = (-2i64)
    }
    m = (n + sqre)
    if (ldu < n) {
        info = (-6i64)
    } else if (ldvt < m) {
        info = (-8i64)
    } else if (smlsiz < 3i64) {
        info = (-9i64)
    }
    if (info != 0i64) {
        *info_ref = info
        ret
    }
    if (n <= smlsiz) {
        dlasdq("U", sqre, n, m, n, 0i64, d[0usize..], e[0usize..], vt[0usize..], ldvt, u[0usize..], ldu, u[0usize..], ldu, work[0usize..], &info)
        *info_ref = info
        ret
    }
    inode = 1i64
    ndiml = (inode + n)
    ndimr = (ndiml + n)
    idxq = (ndimr + n)
    iwk = (idxq + n)
    dlasdt(n, &nlvl, &nd, lbase.sl[i64](iwork[0usize..], usize((inode - 1i64))), lbase.sl[i64](iwork[0usize..], usize((ndiml - 1i64))), lbase.sl[i64](iwork[0usize..], usize((ndimr - 1i64))), smlsiz)
    ndb1 = (((nd + 1i64)) / 2i64)
    ncc = 0i64
    i = ndb1
    zc1 = (nd - i) + 1i64
    while zc1 > 0i64 {
        i1 = (i - 1i64)
        ic = iwork[usize(((inode + i1) - 1i64))]
        nl = iwork[usize(((ndiml + i1) - 1i64))]
        nlp1 = (nl + 1i64)
        nr = iwork[usize(((ndimr + i1) - 1i64))]
        nrp1 = (nr + 1i64)
        nlf = (ic - nl)
        nrf = (ic + 1i64)
        sqrei = 1i64
        dlasdq("U", sqrei, nl, nlp1, nl, ncc, lbase.sl[f64](d[0usize..], usize((nlf - 1i64))), lbase.sl[f64](e[0usize..], usize((nlf - 1i64))), lbase.sl[f64](vt[0usize..], usize((nlf - 1i64) + (nlf - 1i64) * ldvt)), ldvt, lbase.sl[f64](u[0usize..], usize((nlf - 1i64) + (nlf - 1i64) * ldu)), ldu, lbase.sl[f64](u[0usize..], usize((nlf - 1i64) + (nlf - 1i64) * ldu)), ldu, work[0usize..], &info)
        if (info != 0i64) {
            *info_ref = info
            ret
        }
        itemp = ((idxq + nlf) - 2i64)
        j = 1i64
        zc2 = (nl - j) + 1i64
        while zc2 > 0i64 {
            iwork[usize(((itemp + j) - 1i64))] = j
            j = j + 1i64
            zc2 = zc2 - 1i64
        }
        if (i == nd) {
            sqrei = sqre
        } else {
            sqrei = 1i64
        }
        nrp1 = (nr + sqrei)
        dlasdq("U", sqrei, nr, nrp1, nr, ncc, lbase.sl[f64](d[0usize..], usize((nrf - 1i64))), lbase.sl[f64](e[0usize..], usize((nrf - 1i64))), lbase.sl[f64](vt[0usize..], usize((nrf - 1i64) + (nrf - 1i64) * ldvt)), ldvt, lbase.sl[f64](u[0usize..], usize((nrf - 1i64) + (nrf - 1i64) * ldu)), ldu, lbase.sl[f64](u[0usize..], usize((nrf - 1i64) + (nrf - 1i64) * ldu)), ldu, work[0usize..], &info)
        if (info != 0i64) {
            *info_ref = info
            ret
        }
        itemp = (idxq + ic)
        j = 1i64
        zc3 = (nr - j) + 1i64
        while zc3 > 0i64 {
            iwork[usize((((itemp + j) - 1i64) - 1i64))] = j
            j = j + 1i64
            zc3 = zc3 - 1i64
        }
        i = i + 1i64
        zc1 = zc1 - 1i64
    }
    lvl = nlvl
    zs5 = (-1i64)
    zc4 = ((1i64 - lvl) + zs5) / zs5
    while zc4 > 0i64 {
        if (lvl == 1i64) {
            lf = 1i64
            ll = 1i64
        } else {
            lf = lbase.i_pow(2i64, ((lvl - 1i64)))
            ll = ((2i64 * lf) - 1i64)
        }
        i = lf
        zc6 = (ll - i) + 1i64
        while zc6 > 0i64 {
            im1 = (i - 1i64)
            ic = iwork[usize(((inode + im1) - 1i64))]
            nl = iwork[usize(((ndiml + im1) - 1i64))]
            nr = iwork[usize(((ndimr + im1) - 1i64))]
            nlf = (ic - nl)
            if (((sqre == 0i64)) && ((i == ll))) {
                sqrei = sqre
            } else {
                sqrei = 1i64
            }
            idxqc = ((idxq + nlf) - 1i64)
            alpha = d[usize((ic - 1i64))]
            beta = e[usize((ic - 1i64))]
            dlasd1(nl, nr, sqrei, lbase.sl[f64](d[0usize..], usize((nlf - 1i64))), &alpha, &beta, lbase.sl[f64](u[0usize..], usize((nlf - 1i64) + (nlf - 1i64) * ldu)), ldu, lbase.sl[f64](vt[0usize..], usize((nlf - 1i64) + (nlf - 1i64) * ldvt)), ldvt, lbase.sl[i64](iwork[0usize..], usize((idxqc - 1i64))), lbase.sl[i64](iwork[0usize..], usize((iwk - 1i64))), work[0usize..], &info)
            if (info != 0i64) {
                *info_ref = info
                ret
            }
            i = i + 1i64
            zc6 = zc6 - 1i64
        }
        lvl = lvl + zs5
        zc4 = zc4 - 1i64
    }
    *info_ref = info
    ret
}

fn dlasd1(nl: i64, nr: i64, sqre: i64, d: []f64, alpha_ref: *f64, beta_ref: *f64, u: []f64, ldu: i64, vt: []f64, ldvt: i64, idxq: []i64, iwork: []i64, work: []f64, info_ref: *i64) {
    var alpha = *alpha_ref
    var beta = *beta_ref
    var info = *info_ref
    var coltyp: i64 = 0i64
    var i: i64 = 0i64
    var idx: i64 = 0i64
    var idxc: i64 = 0i64
    var idxp: i64 = 0i64
    var iq: i64 = 0i64
    var isigma: i64 = 0i64
    var iu2: i64 = 0i64
    var ivt2: i64 = 0i64
    var iz: i64 = 0i64
    var k: i64 = 0i64
    var ldq: i64 = 0i64
    var ldu2: i64 = 0i64
    var ldvt2: i64 = 0i64
    var m: i64 = 0i64
    var n: i64 = 0i64
    var n1: i64 = 0i64
    var n2: i64 = 0i64
    var orgnrm: f64 = 0.0f64
    var zc1: i64 = 0i64
    info = 0i64
    if (nl < 1i64) {
        info = (-1i64)
    } else if (nr < 1i64) {
        info = (-2i64)
    } else if (((sqre < 0i64)) || ((sqre > 1i64))) {
        info = (-3i64)
    }
    if (info != 0i64) {
        *alpha_ref = alpha
        *beta_ref = beta
        *info_ref = info
        ret
    }
    n = ((nl + nr) + 1i64)
    m = (n + sqre)
    ldu2 = n
    ldvt2 = m
    iz = 1i64
    isigma = (iz + m)
    iu2 = (isigma + n)
    ivt2 = (iu2 + (ldu2 * n))
    iq = (ivt2 + (ldvt2 * m))
    idx = 1i64
    idxc = (idx + n)
    coltyp = (idxc + n)
    idxp = (coltyp + n)
    orgnrm = lbase.f_max(math.abs[f64](alpha), math.abs[f64](beta))
    d[usize(((nl + 1i64) - 1i64))] = 0.0f64
    i = 1i64
    zc1 = (n - i) + 1i64
    while zc1 > 0i64 {
        if (math.abs[f64](d[usize((i - 1i64))]) > orgnrm) {
            orgnrm = math.abs[f64](d[usize((i - 1i64))])
        }
        i = i + 1i64
        zc1 = zc1 - 1i64
    }
    lbase.dlascl("G", 0i64, 0i64, orgnrm, 1.0f64, n, 1i64, d[0usize..], n, &info)
    alpha = (alpha / orgnrm)
    beta = (beta / orgnrm)
    dlasd2(nl, nr, sqre, &k, d[0usize..], lbase.sl[f64](work[0usize..], usize((iz - 1i64))), alpha, beta, u[0usize..], ldu, vt[0usize..], ldvt, lbase.sl[f64](work[0usize..], usize((isigma - 1i64))), lbase.sl[f64](work[0usize..], usize((iu2 - 1i64))), ldu2, lbase.sl[f64](work[0usize..], usize((ivt2 - 1i64))), ldvt2, lbase.sl[i64](iwork[0usize..], usize((idxp - 1i64))), lbase.sl[i64](iwork[0usize..], usize((idx - 1i64))), lbase.sl[i64](iwork[0usize..], usize((idxc - 1i64))), idxq[0usize..], lbase.sl[i64](iwork[0usize..], usize((coltyp - 1i64))), &info)
    ldq = k
    dlasd3(nl, nr, sqre, k, d[0usize..], lbase.sl[f64](work[0usize..], usize((iq - 1i64))), ldq, lbase.sl[f64](work[0usize..], usize((isigma - 1i64))), u[0usize..], ldu, lbase.sl[f64](work[0usize..], usize((iu2 - 1i64))), ldu2, vt[0usize..], ldvt, lbase.sl[f64](work[0usize..], usize((ivt2 - 1i64))), ldvt2, lbase.sl[i64](iwork[0usize..], usize((idxc - 1i64))), lbase.sl[i64](iwork[0usize..], usize((coltyp - 1i64))), lbase.sl[f64](work[0usize..], usize((iz - 1i64))), &info)
    if (info != 0i64) {
        *alpha_ref = alpha
        *beta_ref = beta
        *info_ref = info
        ret
    }
    lbase.dlascl("G", 0i64, 0i64, 1.0f64, orgnrm, n, 1i64, d[0usize..], n, &info)
    n1 = k
    n2 = (n - k)
    lbase.dlamrg(n1, n2, d[0usize..], 1i64, (-1i64), idxq[0usize..])
    *alpha_ref = alpha
    *beta_ref = beta
    *info_ref = info
    ret
}

fn dlasd2(nl: i64, nr: i64, sqre: i64, k_ref: *i64, d: []f64, z: []f64, alpha: f64, beta: f64, u: []f64, ldu: i64, vt: []f64, ldvt: i64, dsigma: []f64, u2: []f64, ldu2: i64, vt2: []f64, ldvt2: i64, idxp: []i64, idx: []i64, idxc: []i64, idxq: []i64, coltyp: []i64, info_ref: *i64) {
    var k = *k_ref
    var info = *info_ref
    var ctot: [4]i64 = zero
    var psm: [4]i64 = zero
    var ct: i64 = 0i64
    var i: i64 = 0i64
    var idxi: i64 = 0i64
    var idxj: i64 = 0i64
    var idxjp: i64 = 0i64
    var j: i64 = 0i64
    var jp: i64 = 0i64
    var jprev: i64 = 0i64
    var k2: i64 = 0i64
    var m: i64 = 0i64
    var n: i64 = 0i64
    var nlp1: i64 = 0i64
    var nlp2: i64 = 0i64
    var c: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var hlftol: f64 = 0.0f64
    var s: f64 = 0.0f64
    var tau: f64 = 0.0f64
    var tol: f64 = 0.0f64
    var z1: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zs2: i64 = 0i64
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
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            if (nl < 1i64) {
                info = (-1i64)
            } else if (nr < 1i64) {
                info = (-2i64)
            } else if (((sqre != 1i64)) && ((sqre != 0i64))) {
                info = (-3i64)
            }
            n = ((nl + nr) + 1i64)
            m = (n + sqre)
            if (ldu < n) {
                info = (-10i64)
            } else if (ldvt < m) {
                info = (-12i64)
            } else if (ldu2 < n) {
                info = (-15i64)
            } else if (ldvt2 < m) {
                info = (-17i64)
            }
            if (info != 0i64) {
                *k_ref = k
                *info_ref = info
                ret
            }
            nlp1 = (nl + 1i64)
            nlp2 = (nl + 2i64)
            z1 = (alpha * vt[usize((nlp1 - 1i64) + (nlp1 - 1i64) * ldvt)])
            z[usize((1i64 - 1i64))] = z1
            i = nl
            zs2 = (-1i64)
            zc1 = ((1i64 - i) + zs2) / zs2
            while zc1 > 0i64 {
                z[usize(((i + 1i64) - 1i64))] = (alpha * vt[usize((i - 1i64) + (nlp1 - 1i64) * ldvt)])
                d[usize(((i + 1i64) - 1i64))] = d[usize((i - 1i64))]
                idxq[usize(((i + 1i64) - 1i64))] = (idxq[usize((i - 1i64))] + 1i64)
                i = i + zs2
                zc1 = zc1 - 1i64
            }
            i = nlp2
            zc3 = (m - i) + 1i64
            while zc3 > 0i64 {
                z[usize((i - 1i64))] = (beta * vt[usize((i - 1i64) + (nlp2 - 1i64) * ldvt)])
                i = i + 1i64
                zc3 = zc3 - 1i64
            }
            i = 2i64
            zc4 = (nlp1 - i) + 1i64
            while zc4 > 0i64 {
                coltyp[usize((i - 1i64))] = 1i64
                i = i + 1i64
                zc4 = zc4 - 1i64
            }
            i = nlp2
            zc5 = (n - i) + 1i64
            while zc5 > 0i64 {
                coltyp[usize((i - 1i64))] = 2i64
                i = i + 1i64
                zc5 = zc5 - 1i64
            }
            i = nlp2
            zc6 = (n - i) + 1i64
            while zc6 > 0i64 {
                idxq[usize((i - 1i64))] = (idxq[usize((i - 1i64))] + nlp1)
                i = i + 1i64
                zc6 = zc6 - 1i64
            }
            i = 2i64
            zc7 = (n - i) + 1i64
            while zc7 > 0i64 {
                dsigma[usize((i - 1i64))] = d[usize((idxq[usize((i - 1i64))] - 1i64))]
                u2[usize((i - 1i64) + (1i64 - 1i64) * ldu2)] = z[usize((idxq[usize((i - 1i64))] - 1i64))]
                idxc[usize((i - 1i64))] = coltyp[usize((idxq[usize((i - 1i64))] - 1i64))]
                i = i + 1i64
                zc7 = zc7 - 1i64
            }
            lbase.dlamrg(nl, nr, lbase.sl[f64](dsigma[0usize..], usize((2i64 - 1i64))), 1i64, 1i64, lbase.sl[i64](idx[0usize..], usize((2i64 - 1i64))))
            i = 2i64
            zc8 = (n - i) + 1i64
            while zc8 > 0i64 {
                idxi = (1i64 + idx[usize((i - 1i64))])
                d[usize((i - 1i64))] = dsigma[usize((idxi - 1i64))]
                z[usize((i - 1i64))] = u2[usize((idxi - 1i64) + (1i64 - 1i64) * ldu2)]
                coltyp[usize((i - 1i64))] = idxc[usize((idxi - 1i64))]
                i = i + 1i64
                zc8 = zc8 - 1i64
            }
            eps = 1.1102230246251565e-16f64
            tol = lbase.f_max(math.abs[f64](alpha), math.abs[f64](beta))
            tol = ((8.0f64 * eps) * lbase.f_max(math.abs[f64](d[usize((n - 1i64))]), tol))
            k = 1i64
            k2 = (n + 1i64)
            j = 2i64
            zc9 = (n - j) + 1i64
            pc = 1i64
        }
        if pc == 1i64 {
            if zc9 <= 0i64 {
                pc = 2i64
                continue
            }
            if !(math.abs[f64](z[usize((j - 1i64))]) <= tol) {
                pc = 4i64
                continue
            }
            k2 = (k2 - 1i64)
            idxp[usize((k2 - 1i64))] = j
            coltyp[usize((j - 1i64))] = 4i64
            if !(j == n) {
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
            pc = 3i64
            continue
        }
        if pc == 4i64 {
            jprev = j
            pc = 8i64
            continue
        }
        if pc == 3i64 {
            j = j + 1i64
            zc9 = zc9 - 1i64
            pc = 1i64
            continue
        }
        if pc == 2i64 {
            pc = 8i64
        }
        if pc == 8i64 {
            j = jprev
            pc = 9i64
        }
        if pc == 9i64 {
            j = (j + 1i64)
            if !(j > n) {
                pc = 11i64
                continue
            }
            pc = 12i64
            continue
        }
        if pc == 11i64 {
            pc = 10i64
        }
        if pc == 10i64 {
            if (math.abs[f64](z[usize((j - 1i64))]) <= tol) {
                k2 = (k2 - 1i64)
                idxp[usize((k2 - 1i64))] = j
                coltyp[usize((j - 1i64))] = 4i64
            } else {
                if (math.abs[f64]((d[usize((j - 1i64))] - d[usize((jprev - 1i64))])) <= tol) {
                    s = z[usize((jprev - 1i64))]
                    c = z[usize((j - 1i64))]
                    tau = lbase.dlapy2(c, s)
                    c = (c / tau)
                    s = (-(s / tau))
                    z[usize((j - 1i64))] = tau
                    z[usize((jprev - 1i64))] = 0.0f64
                    idxjp = idxq[usize(((idx[usize((jprev - 1i64))] + 1i64) - 1i64))]
                    idxj = idxq[usize(((idx[usize((j - 1i64))] + 1i64) - 1i64))]
                    if (idxjp <= nlp1) {
                        idxjp = (idxjp - 1i64)
                    }
                    if (idxj <= nlp1) {
                        idxj = (idxj - 1i64)
                    }
                    lbase.drot(n, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (idxjp - 1i64) * ldu)), 1i64, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (idxj - 1i64) * ldu)), 1i64, c, s)
                    lbase.drot(m, lbase.sl[f64](vt[0usize..], usize((idxjp - 1i64) + (1i64 - 1i64) * ldvt)), ldvt, lbase.sl[f64](vt[0usize..], usize((idxj - 1i64) + (1i64 - 1i64) * ldvt)), ldvt, c, s)
                    if (coltyp[usize((j - 1i64))] != coltyp[usize((jprev - 1i64))]) {
                        coltyp[usize((j - 1i64))] = 3i64
                    }
                    coltyp[usize((jprev - 1i64))] = 4i64
                    k2 = (k2 - 1i64)
                    idxp[usize((k2 - 1i64))] = jprev
                    jprev = j
                } else {
                    k = (k + 1i64)
                    u2[usize((k - 1i64) + (1i64 - 1i64) * ldu2)] = z[usize((jprev - 1i64))]
                    dsigma[usize((k - 1i64))] = d[usize((jprev - 1i64))]
                    idxp[usize((k - 1i64))] = jprev
                    jprev = j
                }
            }
            pc = 9i64
            continue
        }
        if pc == 12i64 {
            k = (k + 1i64)
            u2[usize((k - 1i64) + (1i64 - 1i64) * ldu2)] = z[usize((jprev - 1i64))]
            dsigma[usize((k - 1i64))] = d[usize((jprev - 1i64))]
            idxp[usize((k - 1i64))] = jprev
            pc = 7i64
        }
        if pc == 7i64 {
            j = 1i64
            zc10 = (4i64 - j) + 1i64
            while zc10 > 0i64 {
                ctot[usize((j - 1i64))] = 0i64
                j = j + 1i64
                zc10 = zc10 - 1i64
            }
            j = 2i64
            zc11 = (n - j) + 1i64
            while zc11 > 0i64 {
                ct = coltyp[usize((j - 1i64))]
                ctot[usize((ct - 1i64))] = (ctot[usize((ct - 1i64))] + 1i64)
                j = j + 1i64
                zc11 = zc11 - 1i64
            }
            psm[usize((1i64 - 1i64))] = 2i64
            psm[usize((2i64 - 1i64))] = (2i64 + ctot[usize((1i64 - 1i64))])
            psm[usize((3i64 - 1i64))] = (psm[usize((2i64 - 1i64))] + ctot[usize((2i64 - 1i64))])
            psm[usize((4i64 - 1i64))] = (psm[usize((3i64 - 1i64))] + ctot[usize((3i64 - 1i64))])
            j = 2i64
            zc12 = (n - j) + 1i64
            while zc12 > 0i64 {
                jp = idxp[usize((j - 1i64))]
                ct = coltyp[usize((jp - 1i64))]
                idxc[usize((psm[usize((ct - 1i64))] - 1i64))] = j
                psm[usize((ct - 1i64))] = (psm[usize((ct - 1i64))] + 1i64)
                j = j + 1i64
                zc12 = zc12 - 1i64
            }
            j = 2i64
            zc13 = (n - j) + 1i64
            while zc13 > 0i64 {
                jp = idxp[usize((j - 1i64))]
                dsigma[usize((j - 1i64))] = d[usize((jp - 1i64))]
                idxj = idxq[usize(((idx[usize((idxp[usize((idxc[usize((j - 1i64))] - 1i64))] - 1i64))] + 1i64) - 1i64))]
                if (idxj <= nlp1) {
                    idxj = (idxj - 1i64)
                }
                lbase.dcopy(n, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (idxj - 1i64) * ldu)), 1i64, lbase.sl[f64](u2[0usize..], usize((1i64 - 1i64) + (j - 1i64) * ldu2)), 1i64)
                lbase.dcopy(m, lbase.sl[f64](vt[0usize..], usize((idxj - 1i64) + (1i64 - 1i64) * ldvt)), ldvt, lbase.sl[f64](vt2[0usize..], usize((j - 1i64) + (1i64 - 1i64) * ldvt2)), ldvt2)
                j = j + 1i64
                zc13 = zc13 - 1i64
            }
            dsigma[usize((1i64 - 1i64))] = 0.0f64
            hlftol = (tol / 2.0f64)
            if (math.abs[f64](dsigma[usize((2i64 - 1i64))]) <= hlftol) {
                dsigma[usize((2i64 - 1i64))] = hlftol
            }
            if (m > n) {
                z[usize((1i64 - 1i64))] = lbase.dlapy2(z1, z[usize((m - 1i64))])
                if (z[usize((1i64 - 1i64))] <= tol) {
                    c = 1.0f64
                    s = 0.0f64
                    z[usize((1i64 - 1i64))] = tol
                } else {
                    c = (z1 / z[usize((1i64 - 1i64))])
                    s = (z[usize((m - 1i64))] / z[usize((1i64 - 1i64))])
                }
            } else {
                if (math.abs[f64](z1) <= tol) {
                    z[usize((1i64 - 1i64))] = tol
                } else {
                    z[usize((1i64 - 1i64))] = z1
                }
            }
            lbase.dcopy((k - 1i64), lbase.sl[f64](u2[0usize..], usize((2i64 - 1i64) + (1i64 - 1i64) * ldu2)), 1i64, lbase.sl[f64](z[0usize..], usize((2i64 - 1i64))), 1i64)
            lbase.dlaset("A", n, 1i64, 0.0f64, 0.0f64, u2[0usize..], ldu2)
            u2[usize((nlp1 - 1i64) + (1i64 - 1i64) * ldu2)] = 1.0f64
            if (m > n) {
                i = 1i64
                zc14 = (nlp1 - i) + 1i64
                while zc14 > 0i64 {
                    vt[usize((m - 1i64) + (i - 1i64) * ldvt)] = (-(s * vt[usize((nlp1 - 1i64) + (i - 1i64) * ldvt)]))
                    vt2[usize((1i64 - 1i64) + (i - 1i64) * ldvt2)] = (c * vt[usize((nlp1 - 1i64) + (i - 1i64) * ldvt)])
                    i = i + 1i64
                    zc14 = zc14 - 1i64
                }
                i = nlp2
                zc15 = (m - i) + 1i64
                while zc15 > 0i64 {
                    vt2[usize((1i64 - 1i64) + (i - 1i64) * ldvt2)] = (s * vt[usize((m - 1i64) + (i - 1i64) * ldvt)])
                    vt[usize((m - 1i64) + (i - 1i64) * ldvt)] = (c * vt[usize((m - 1i64) + (i - 1i64) * ldvt)])
                    i = i + 1i64
                    zc15 = zc15 - 1i64
                }
            } else {
                lbase.dcopy(m, lbase.sl[f64](vt[0usize..], usize((nlp1 - 1i64) + (1i64 - 1i64) * ldvt)), ldvt, lbase.sl[f64](vt2[0usize..], usize((1i64 - 1i64) + (1i64 - 1i64) * ldvt2)), ldvt2)
            }
            if (m > n) {
                lbase.dcopy(m, lbase.sl[f64](vt[0usize..], usize((m - 1i64) + (1i64 - 1i64) * ldvt)), ldvt, lbase.sl[f64](vt2[0usize..], usize((m - 1i64) + (1i64 - 1i64) * ldvt2)), ldvt2)
            }
            if (n > k) {
                lbase.dcopy((n - k), lbase.sl[f64](dsigma[0usize..], usize(((k + 1i64) - 1i64))), 1i64, lbase.sl[f64](d[0usize..], usize(((k + 1i64) - 1i64))), 1i64)
                lbase.dlacpy("A", n, (n - k), lbase.sl[f64](u2[0usize..], usize((1i64 - 1i64) + ((k + 1i64) - 1i64) * ldu2)), ldu2, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + ((k + 1i64) - 1i64) * ldu)), ldu)
                lbase.dlacpy("A", (n - k), m, lbase.sl[f64](vt2[0usize..], usize(((k + 1i64) - 1i64) + (1i64 - 1i64) * ldvt2)), ldvt2, lbase.sl[f64](vt[0usize..], usize(((k + 1i64) - 1i64) + (1i64 - 1i64) * ldvt)), ldvt)
            }
            j = 1i64
            zc16 = (4i64 - j) + 1i64
            while zc16 > 0i64 {
                coltyp[usize((j - 1i64))] = ctot[usize((j - 1i64))]
                j = j + 1i64
                zc16 = zc16 - 1i64
            }
            *k_ref = k
            *info_ref = info
            ret
        }
    }
}

fn dlasd3(nl: i64, nr: i64, sqre: i64, k: i64, d: []f64, q: []f64, ldq: i64, dsigma: []f64, u: []f64, ldu: i64, u2: []f64, ldu2: i64, vt: []f64, ldvt: i64, vt2: []f64, ldvt2: i64, idxc: []i64, ctot: []i64, z: []f64, info_ref: *i64) {
    var info = *info_ref
    var ctemp: i64 = 0i64
    var i: i64 = 0i64
    var j: i64 = 0i64
    var jc: i64 = 0i64
    var ktemp: i64 = 0i64
    var m: i64 = 0i64
    var n: i64 = 0i64
    var nlp1: i64 = 0i64
    var nlp2: i64 = 0i64
    var nrp1: i64 = 0i64
    var rho: f64 = 0.0f64
    var temp: f64 = 0.0f64
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
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            if (nl < 1i64) {
                info = (-1i64)
            } else if (nr < 1i64) {
                info = (-2i64)
            } else if (((sqre != 1i64)) && ((sqre != 0i64))) {
                info = (-3i64)
            }
            n = ((nl + nr) + 1i64)
            m = (n + sqre)
            nlp1 = (nl + 1i64)
            nlp2 = (nl + 2i64)
            if (((k < 1i64)) || ((k > n))) {
                info = (-4i64)
            } else if (ldq < k) {
                info = (-7i64)
            } else if (ldu < n) {
                info = (-10i64)
            } else if (ldu2 < n) {
                info = (-12i64)
            } else if (ldvt < m) {
                info = (-14i64)
            } else if (ldvt2 < m) {
                info = (-16i64)
            }
            if (info != 0i64) {
                *info_ref = info
                ret
            }
            if (k == 1i64) {
                d[usize((1i64 - 1i64))] = math.abs[f64](z[usize((1i64 - 1i64))])
                lbase.dcopy(m, lbase.sl[f64](vt2[0usize..], usize((1i64 - 1i64) + (1i64 - 1i64) * ldvt2)), ldvt2, lbase.sl[f64](vt[0usize..], usize((1i64 - 1i64) + (1i64 - 1i64) * ldvt)), ldvt)
                if (z[usize((1i64 - 1i64))] > 0.0f64) {
                    lbase.dcopy(n, lbase.sl[f64](u2[0usize..], usize((1i64 - 1i64) + (1i64 - 1i64) * ldu2)), 1i64, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (1i64 - 1i64) * ldu)), 1i64)
                } else {
                    i = 1i64
                    zc1 = (n - i) + 1i64
                    while zc1 > 0i64 {
                        u[usize((i - 1i64) + (1i64 - 1i64) * ldu)] = (-u2[usize((i - 1i64) + (1i64 - 1i64) * ldu2)])
                        i = i + 1i64
                        zc1 = zc1 - 1i64
                    }
                }
                *info_ref = info
                ret
            }
            lbase.dcopy(k, z[0usize..], 1i64, q[0usize..], 1i64)
            rho = lbase.dnrm2(k, z[0usize..], 1i64)
            lbase.dlascl("G", 0i64, 0i64, rho, 1.0f64, k, 1i64, z[0usize..], k, &info)
            rho = (rho * rho)
            j = 1i64
            zc2 = (k - j) + 1i64
            while zc2 > 0i64 {
                dlasd4(k, j, dsigma[0usize..], z[0usize..], lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (j - 1i64) * ldu)), rho, &d[usize((j - 1i64))], lbase.sl[f64](vt[0usize..], usize((1i64 - 1i64) + (j - 1i64) * ldvt)), &info)
                if (info != 0i64) {
                    *info_ref = info
                    ret
                }
                j = j + 1i64
                zc2 = zc2 - 1i64
            }
            i = 1i64
            zc3 = (k - i) + 1i64
            while zc3 > 0i64 {
                z[usize((i - 1i64))] = (u[usize((i - 1i64) + (k - 1i64) * ldu)] * vt[usize((i - 1i64) + (k - 1i64) * ldvt)])
                j = 1i64
                zc4 = ((i - 1i64) - j) + 1i64
                while zc4 > 0i64 {
                    z[usize((i - 1i64))] = (z[usize((i - 1i64))] * ((((u[usize((i - 1i64) + (j - 1i64) * ldu)] * vt[usize((i - 1i64) + (j - 1i64) * ldvt)]) / ((dsigma[usize((i - 1i64))] - dsigma[usize((j - 1i64))]))) / ((dsigma[usize((i - 1i64))] + dsigma[usize((j - 1i64))])))))
                    j = j + 1i64
                    zc4 = zc4 - 1i64
                }
                j = i
                zc5 = ((k - 1i64) - j) + 1i64
                while zc5 > 0i64 {
                    z[usize((i - 1i64))] = (z[usize((i - 1i64))] * ((((u[usize((i - 1i64) + (j - 1i64) * ldu)] * vt[usize((i - 1i64) + (j - 1i64) * ldvt)]) / ((dsigma[usize((i - 1i64))] - dsigma[usize(((j + 1i64) - 1i64))]))) / ((dsigma[usize((i - 1i64))] + dsigma[usize(((j + 1i64) - 1i64))])))))
                    j = j + 1i64
                    zc5 = zc5 - 1i64
                }
                z[usize((i - 1i64))] = lbase.f_sign(math.sqrt[f64](math.abs[f64](z[usize((i - 1i64))])), q[usize((i - 1i64) + (1i64 - 1i64) * ldq)])
                i = i + 1i64
                zc3 = zc3 - 1i64
            }
            i = 1i64
            zc6 = (k - i) + 1i64
            while zc6 > 0i64 {
                vt[usize((1i64 - 1i64) + (i - 1i64) * ldvt)] = ((z[usize((1i64 - 1i64))] / u[usize((1i64 - 1i64) + (i - 1i64) * ldu)]) / vt[usize((1i64 - 1i64) + (i - 1i64) * ldvt)])
                u[usize((1i64 - 1i64) + (i - 1i64) * ldu)] = (-1.0f64)
                j = 2i64
                zc7 = (k - j) + 1i64
                while zc7 > 0i64 {
                    vt[usize((j - 1i64) + (i - 1i64) * ldvt)] = ((z[usize((j - 1i64))] / u[usize((j - 1i64) + (i - 1i64) * ldu)]) / vt[usize((j - 1i64) + (i - 1i64) * ldvt)])
                    u[usize((j - 1i64) + (i - 1i64) * ldu)] = (dsigma[usize((j - 1i64))] * vt[usize((j - 1i64) + (i - 1i64) * ldvt)])
                    j = j + 1i64
                    zc7 = zc7 - 1i64
                }
                temp = lbase.dnrm2(k, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldu)), 1i64)
                q[usize((1i64 - 1i64) + (i - 1i64) * ldq)] = (u[usize((1i64 - 1i64) + (i - 1i64) * ldu)] / temp)
                j = 2i64
                zc8 = (k - j) + 1i64
                while zc8 > 0i64 {
                    jc = idxc[usize((j - 1i64))]
                    q[usize((j - 1i64) + (i - 1i64) * ldq)] = (u[usize((jc - 1i64) + (i - 1i64) * ldu)] / temp)
                    j = j + 1i64
                    zc8 = zc8 - 1i64
                }
                i = i + 1i64
                zc6 = zc6 - 1i64
            }
            if !(k == 2i64) {
                pc = 2i64
                continue
            }
            lbase.dgemm("N", "N", n, k, k, 1.0f64, u2[0usize..], ldu2, q[0usize..], ldq, 0.0f64, u[0usize..], ldu)
            pc = 3i64
            continue
        }
        if pc == 2i64 {
            pc = 1i64
        }
        if pc == 1i64 {
            if (ctot[usize((1i64 - 1i64))] > 0i64) {
                lbase.dgemm("N", "N", nl, k, ctot[usize((1i64 - 1i64))], 1.0f64, lbase.sl[f64](u2[0usize..], usize((1i64 - 1i64) + (2i64 - 1i64) * ldu2)), ldu2, lbase.sl[f64](q[0usize..], usize((2i64 - 1i64) + (1i64 - 1i64) * ldq)), ldq, 0.0f64, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (1i64 - 1i64) * ldu)), ldu)
                if (ctot[usize((3i64 - 1i64))] > 0i64) {
                    ktemp = ((2i64 + ctot[usize((1i64 - 1i64))]) + ctot[usize((2i64 - 1i64))])
                    lbase.dgemm("N", "N", nl, k, ctot[usize((3i64 - 1i64))], 1.0f64, lbase.sl[f64](u2[0usize..], usize((1i64 - 1i64) + (ktemp - 1i64) * ldu2)), ldu2, lbase.sl[f64](q[0usize..], usize((ktemp - 1i64) + (1i64 - 1i64) * ldq)), ldq, 1.0f64, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (1i64 - 1i64) * ldu)), ldu)
                }
            } else if (ctot[usize((3i64 - 1i64))] > 0i64) {
                ktemp = ((2i64 + ctot[usize((1i64 - 1i64))]) + ctot[usize((2i64 - 1i64))])
                lbase.dgemm("N", "N", nl, k, ctot[usize((3i64 - 1i64))], 1.0f64, lbase.sl[f64](u2[0usize..], usize((1i64 - 1i64) + (ktemp - 1i64) * ldu2)), ldu2, lbase.sl[f64](q[0usize..], usize((ktemp - 1i64) + (1i64 - 1i64) * ldq)), ldq, 0.0f64, lbase.sl[f64](u[0usize..], usize((1i64 - 1i64) + (1i64 - 1i64) * ldu)), ldu)
            } else {
                lbase.dlacpy("F", nl, k, u2[0usize..], ldu2, u[0usize..], ldu)
            }
            lbase.dcopy(k, lbase.sl[f64](q[0usize..], usize((1i64 - 1i64) + (1i64 - 1i64) * ldq)), ldq, lbase.sl[f64](u[0usize..], usize((nlp1 - 1i64) + (1i64 - 1i64) * ldu)), ldu)
            ktemp = (2i64 + ctot[usize((1i64 - 1i64))])
            ctemp = (ctot[usize((2i64 - 1i64))] + ctot[usize((3i64 - 1i64))])
            lbase.dgemm("N", "N", nr, k, ctemp, 1.0f64, lbase.sl[f64](u2[0usize..], usize((nlp2 - 1i64) + (ktemp - 1i64) * ldu2)), ldu2, lbase.sl[f64](q[0usize..], usize((ktemp - 1i64) + (1i64 - 1i64) * ldq)), ldq, 0.0f64, lbase.sl[f64](u[0usize..], usize((nlp2 - 1i64) + (1i64 - 1i64) * ldu)), ldu)
            pc = 3i64
        }
        if pc == 3i64 {
            i = 1i64
            zc9 = (k - i) + 1i64
            while zc9 > 0i64 {
                temp = lbase.dnrm2(k, lbase.sl[f64](vt[0usize..], usize((1i64 - 1i64) + (i - 1i64) * ldvt)), 1i64)
                q[usize((i - 1i64) + (1i64 - 1i64) * ldq)] = (vt[usize((1i64 - 1i64) + (i - 1i64) * ldvt)] / temp)
                j = 2i64
                zc10 = (k - j) + 1i64
                while zc10 > 0i64 {
                    jc = idxc[usize((j - 1i64))]
                    q[usize((i - 1i64) + (j - 1i64) * ldq)] = (vt[usize((jc - 1i64) + (i - 1i64) * ldvt)] / temp)
                    j = j + 1i64
                    zc10 = zc10 - 1i64
                }
                i = i + 1i64
                zc9 = zc9 - 1i64
            }
            if (k == 2i64) {
                lbase.dgemm("N", "N", k, m, k, 1.0f64, q[0usize..], ldq, vt2[0usize..], ldvt2, 0.0f64, vt[0usize..], ldvt)
                *info_ref = info
                ret
            }
            ktemp = (1i64 + ctot[usize((1i64 - 1i64))])
            lbase.dgemm("N", "N", k, nlp1, ktemp, 1.0f64, lbase.sl[f64](q[0usize..], usize((1i64 - 1i64) + (1i64 - 1i64) * ldq)), ldq, lbase.sl[f64](vt2[0usize..], usize((1i64 - 1i64) + (1i64 - 1i64) * ldvt2)), ldvt2, 0.0f64, lbase.sl[f64](vt[0usize..], usize((1i64 - 1i64) + (1i64 - 1i64) * ldvt)), ldvt)
            ktemp = ((2i64 + ctot[usize((1i64 - 1i64))]) + ctot[usize((2i64 - 1i64))])
            if (ktemp <= ldvt2) {
                lbase.dgemm("N", "N", k, nlp1, ctot[usize((3i64 - 1i64))], 1.0f64, lbase.sl[f64](q[0usize..], usize((1i64 - 1i64) + (ktemp - 1i64) * ldq)), ldq, lbase.sl[f64](vt2[0usize..], usize((ktemp - 1i64) + (1i64 - 1i64) * ldvt2)), ldvt2, 1.0f64, lbase.sl[f64](vt[0usize..], usize((1i64 - 1i64) + (1i64 - 1i64) * ldvt)), ldvt)
            }
            ktemp = (ctot[usize((1i64 - 1i64))] + 1i64)
            nrp1 = (nr + sqre)
            if (ktemp > 1i64) {
                i = 1i64
                zc11 = (k - i) + 1i64
                while zc11 > 0i64 {
                    q[usize((i - 1i64) + (ktemp - 1i64) * ldq)] = q[usize((i - 1i64) + (1i64 - 1i64) * ldq)]
                    i = i + 1i64
                    zc11 = zc11 - 1i64
                }
                i = nlp2
                zc12 = (m - i) + 1i64
                while zc12 > 0i64 {
                    vt2[usize((ktemp - 1i64) + (i - 1i64) * ldvt2)] = vt2[usize((1i64 - 1i64) + (i - 1i64) * ldvt2)]
                    i = i + 1i64
                    zc12 = zc12 - 1i64
                }
            }
            ctemp = ((1i64 + ctot[usize((2i64 - 1i64))]) + ctot[usize((3i64 - 1i64))])
            lbase.dgemm("N", "N", k, nrp1, ctemp, 1.0f64, lbase.sl[f64](q[0usize..], usize((1i64 - 1i64) + (ktemp - 1i64) * ldq)), ldq, lbase.sl[f64](vt2[0usize..], usize((ktemp - 1i64) + (nlp2 - 1i64) * ldvt2)), ldvt2, 0.0f64, lbase.sl[f64](vt[0usize..], usize((1i64 - 1i64) + (nlp2 - 1i64) * ldvt)), ldvt)
            *info_ref = info
            ret
        }
    }
}

fn dlasd4(n: i64, i: i64, d: []f64, z: []f64, delta: []f64, rho: f64, sigma_ref: *f64, work: []f64, info_ref: *i64) {
    var sigma = *sigma_ref
    var info = *info_ref
    var orgati: bool = false
    var swtch: bool = false
    var swtch3: bool = false
    var geomavg: bool = false
    var ii: i64 = 0i64
    var iim1: i64 = 0i64
    var iip1: i64 = 0i64
    var ip1: i64 = 0i64
    var iter: i64 = 0i64
    var j: i64 = 0i64
    var niter: i64 = 0i64
    var a: f64 = 0.0f64
    var b: f64 = 0.0f64
    var c: f64 = 0.0f64
    var delsq: f64 = 0.0f64
    var delsq2: f64 = 0.0f64
    var sq2: f64 = 0.0f64
    var dphi: f64 = 0.0f64
    var dpsi: f64 = 0.0f64
    var dtiim: f64 = 0.0f64
    var dtiip: f64 = 0.0f64
    var dtipsq: f64 = 0.0f64
    var dtisq: f64 = 0.0f64
    var dtnsq: f64 = 0.0f64
    var dtnsq1: f64 = 0.0f64
    var dw: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var erretm: f64 = 0.0f64
    var eta: f64 = 0.0f64
    var phi: f64 = 0.0f64
    var prew: f64 = 0.0f64
    var psi: f64 = 0.0f64
    var rhoinv: f64 = 0.0f64
    var sglb: f64 = 0.0f64
    var sgub: f64 = 0.0f64
    var tau: f64 = 0.0f64
    var tau2: f64 = 0.0f64
    var temp: f64 = 0.0f64
    var temp1: f64 = 0.0f64
    var temp2: f64 = 0.0f64
    var w: f64 = 0.0f64
    var dd: [3]f64 = zero
    var zz: [3]f64 = zero
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
    var zs13: i64 = 0i64
    var zc14: i64 = 0i64
    var zc15: i64 = 0i64
    var zc16: i64 = 0i64
    var zs17: i64 = 0i64
    var zc18: i64 = 0i64
    var zc19: i64 = 0i64
    var zc20: i64 = 0i64
    var zs21: i64 = 0i64
    var zc22: i64 = 0i64
    var zc23: i64 = 0i64
    var zc24: i64 = 0i64
    var zc25: i64 = 0i64
    var zs26: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            if (n == 1i64) {
                sigma = math.sqrt[f64](((d[usize((1i64 - 1i64))] * d[usize((1i64 - 1i64))]) + ((rho * z[usize((1i64 - 1i64))]) * z[usize((1i64 - 1i64))])))
                delta[usize((1i64 - 1i64))] = 1.0f64
                work[usize((1i64 - 1i64))] = 1.0f64
                *sigma_ref = sigma
                *info_ref = info
                ret
            }
            if (n == 2i64) {
                dlasd5(i, d[0usize..], z[0usize..], delta[0usize..], rho, &sigma, work[0usize..])
                *sigma_ref = sigma
                *info_ref = info
                ret
            }
            eps = 1.1102230246251565e-16f64
            rhoinv = (1.0f64 / rho)
            tau2 = 0.0f64
            if !(i == n) {
                pc = 2i64
                continue
            }
            ii = (n - 1i64)
            niter = 1i64
            temp = (rho / 2.0f64)
            temp1 = (temp / ((d[usize((n - 1i64))] + math.sqrt[f64](((d[usize((n - 1i64))] * d[usize((n - 1i64))]) + temp)))))
            j = 1i64
            zc1 = (n - j) + 1i64
            while zc1 > 0i64 {
                work[usize((j - 1i64))] = ((d[usize((j - 1i64))] + d[usize((n - 1i64))]) + temp1)
                delta[usize((j - 1i64))] = (((d[usize((j - 1i64))] - d[usize((n - 1i64))])) - temp1)
                j = j + 1i64
                zc1 = zc1 - 1i64
            }
            psi = 0.0f64
            j = 1i64
            zc2 = ((n - 2i64) - j) + 1i64
            while zc2 > 0i64 {
                psi = (psi + ((z[usize((j - 1i64))] * z[usize((j - 1i64))]) / ((delta[usize((j - 1i64))] * work[usize((j - 1i64))]))))
                j = j + 1i64
                zc2 = zc2 - 1i64
            }
            c = (rhoinv + psi)
            w = ((c + ((z[usize((ii - 1i64))] * z[usize((ii - 1i64))]) / ((delta[usize((ii - 1i64))] * work[usize((ii - 1i64))])))) + ((z[usize((n - 1i64))] * z[usize((n - 1i64))]) / ((delta[usize((n - 1i64))] * work[usize((n - 1i64))]))))
            if (w <= 0.0f64) {
                temp1 = math.sqrt[f64](((d[usize((n - 1i64))] * d[usize((n - 1i64))]) + rho))
                temp = (((z[usize(((n - 1i64) - 1i64))] * z[usize(((n - 1i64) - 1i64))]) / ((((d[usize(((n - 1i64) - 1i64))] + temp1)) * (((d[usize((n - 1i64))] - d[usize(((n - 1i64) - 1i64))]) + (rho / ((d[usize((n - 1i64))] + temp1)))))))) + ((z[usize((n - 1i64))] * z[usize((n - 1i64))]) / rho))
                if (c <= temp) {
                    tau = rho
                } else {
                    delsq = (((d[usize((n - 1i64))] - d[usize(((n - 1i64) - 1i64))])) * ((d[usize((n - 1i64))] + d[usize(((n - 1i64) - 1i64))])))
                    a = (((-(c * delsq)) + (z[usize(((n - 1i64) - 1i64))] * z[usize(((n - 1i64) - 1i64))])) + (z[usize((n - 1i64))] * z[usize((n - 1i64))]))
                    b = ((z[usize((n - 1i64))] * z[usize((n - 1i64))]) * delsq)
                    if (a < 0.0f64) {
                        tau2 = ((2.0f64 * b) / ((math.sqrt[f64](((a * a) + ((4.0f64 * b) * c))) - a)))
                    } else {
                        tau2 = (((a + math.sqrt[f64](((a * a) + ((4.0f64 * b) * c))))) / ((2.0f64 * c)))
                    }
                    tau = (tau2 / ((d[usize((n - 1i64))] + math.sqrt[f64](((d[usize((n - 1i64))] * d[usize((n - 1i64))]) + tau2)))))
                }
            } else {
                delsq = (((d[usize((n - 1i64))] - d[usize(((n - 1i64) - 1i64))])) * ((d[usize((n - 1i64))] + d[usize(((n - 1i64) - 1i64))])))
                a = (((-(c * delsq)) + (z[usize(((n - 1i64) - 1i64))] * z[usize(((n - 1i64) - 1i64))])) + (z[usize((n - 1i64))] * z[usize((n - 1i64))]))
                b = ((z[usize((n - 1i64))] * z[usize((n - 1i64))]) * delsq)
                if (a < 0.0f64) {
                    tau2 = ((2.0f64 * b) / ((math.sqrt[f64](((a * a) + ((4.0f64 * b) * c))) - a)))
                } else {
                    tau2 = (((a + math.sqrt[f64](((a * a) + ((4.0f64 * b) * c))))) / ((2.0f64 * c)))
                }
                tau = (tau2 / ((d[usize((n - 1i64))] + math.sqrt[f64](((d[usize((n - 1i64))] * d[usize((n - 1i64))]) + tau2)))))
            }
            sigma = (d[usize((n - 1i64))] + tau)
            j = 1i64
            zc3 = (n - j) + 1i64
            while zc3 > 0i64 {
                delta[usize((j - 1i64))] = (((d[usize((j - 1i64))] - d[usize((n - 1i64))])) - tau)
                work[usize((j - 1i64))] = ((d[usize((j - 1i64))] + d[usize((n - 1i64))]) + tau)
                j = j + 1i64
                zc3 = zc3 - 1i64
            }
            dpsi = 0.0f64
            psi = 0.0f64
            erretm = 0.0f64
            j = 1i64
            zc4 = (ii - j) + 1i64
            while zc4 > 0i64 {
                temp = (z[usize((j - 1i64))] / ((delta[usize((j - 1i64))] * work[usize((j - 1i64))])))
                psi = (psi + (z[usize((j - 1i64))] * temp))
                dpsi = (dpsi + (temp * temp))
                erretm = (erretm + psi)
                j = j + 1i64
                zc4 = zc4 - 1i64
            }
            erretm = math.abs[f64](erretm)
            temp = (z[usize((n - 1i64))] / ((delta[usize((n - 1i64))] * work[usize((n - 1i64))])))
            phi = (z[usize((n - 1i64))] * temp)
            dphi = (temp * temp)
            erretm = ((((8.0f64 * (((-phi) - psi))) + erretm) - phi) + rhoinv)
            w = ((rhoinv + phi) + psi)
            if !(math.abs[f64](w) <= (eps * erretm)) {
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
            niter = (niter + 1i64)
            dtnsq1 = (work[usize(((n - 1i64) - 1i64))] * delta[usize(((n - 1i64) - 1i64))])
            dtnsq = (work[usize((n - 1i64))] * delta[usize((n - 1i64))])
            c = ((w - (dtnsq1 * dpsi)) - (dtnsq * dphi))
            a = ((((dtnsq + dtnsq1)) * w) - ((dtnsq * dtnsq1) * ((dpsi + dphi))))
            b = ((dtnsq * dtnsq1) * w)
            if (c < 0.0f64) {
                c = math.abs[f64](c)
            }
            if (c == 0.0f64) {
                eta = (rho - (sigma * sigma))
            } else if (a >= 0.0f64) {
                eta = (((a + math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))) / ((2.0f64 * c)))
            } else {
                eta = ((2.0f64 * b) / ((a - math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))))
            }
            if ((w * eta) > 0.0f64) {
                eta = (-(w / ((dpsi + dphi))))
            }
            temp = (eta - dtnsq)
            if (temp > rho) {
                eta = (rho + dtnsq)
            }
            eta = (eta / ((sigma + math.sqrt[f64]((eta + (sigma * sigma))))))
            tau = (tau + eta)
            sigma = (sigma + eta)
            j = 1i64
            zc5 = (n - j) + 1i64
            while zc5 > 0i64 {
                delta[usize((j - 1i64))] = (delta[usize((j - 1i64))] - eta)
                work[usize((j - 1i64))] = (work[usize((j - 1i64))] + eta)
                j = j + 1i64
                zc5 = zc5 - 1i64
            }
            dpsi = 0.0f64
            psi = 0.0f64
            erretm = 0.0f64
            j = 1i64
            zc6 = (ii - j) + 1i64
            while zc6 > 0i64 {
                temp = (z[usize((j - 1i64))] / ((work[usize((j - 1i64))] * delta[usize((j - 1i64))])))
                psi = (psi + (z[usize((j - 1i64))] * temp))
                dpsi = (dpsi + (temp * temp))
                erretm = (erretm + psi)
                j = j + 1i64
                zc6 = zc6 - 1i64
            }
            erretm = math.abs[f64](erretm)
            tau2 = (work[usize((n - 1i64))] * delta[usize((n - 1i64))])
            temp = (z[usize((n - 1i64))] / tau2)
            phi = (z[usize((n - 1i64))] * temp)
            dphi = (temp * temp)
            erretm = ((((8.0f64 * (((-phi) - psi))) + erretm) - phi) + rhoinv)
            w = ((rhoinv + phi) + psi)
            iter = (niter + 1i64)
            niter = iter
            zc7 = (400i64 - niter) + 1i64
            pc = 6i64
        }
        if pc == 6i64 {
            if zc7 <= 0i64 {
                pc = 7i64
                continue
            }
            if !(math.abs[f64](w) <= (eps * erretm)) {
                pc = 9i64
                continue
            }
            pc = 5i64
            continue
        }
        if pc == 9i64 {
            pc = 8i64
        }
        if pc == 8i64 {
            dtnsq1 = (work[usize(((n - 1i64) - 1i64))] * delta[usize(((n - 1i64) - 1i64))])
            dtnsq = (work[usize((n - 1i64))] * delta[usize((n - 1i64))])
            c = ((w - (dtnsq1 * dpsi)) - (dtnsq * dphi))
            a = ((((dtnsq + dtnsq1)) * w) - ((dtnsq1 * dtnsq) * ((dpsi + dphi))))
            b = ((dtnsq1 * dtnsq) * w)
            if (a >= 0.0f64) {
                eta = (((a + math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))) / ((2.0f64 * c)))
            } else {
                eta = ((2.0f64 * b) / ((a - math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))))
            }
            if ((w * eta) > 0.0f64) {
                eta = (-(w / ((dpsi + dphi))))
            }
            temp = (eta - dtnsq)
            if (temp <= 0.0f64) {
                eta = (eta / 2.0f64)
            }
            eta = (eta / ((sigma + math.sqrt[f64]((eta + (sigma * sigma))))))
            tau = (tau + eta)
            sigma = (sigma + eta)
            j = 1i64
            zc8 = (n - j) + 1i64
            while zc8 > 0i64 {
                delta[usize((j - 1i64))] = (delta[usize((j - 1i64))] - eta)
                work[usize((j - 1i64))] = (work[usize((j - 1i64))] + eta)
                j = j + 1i64
                zc8 = zc8 - 1i64
            }
            dpsi = 0.0f64
            psi = 0.0f64
            erretm = 0.0f64
            j = 1i64
            zc9 = (ii - j) + 1i64
            while zc9 > 0i64 {
                temp = (z[usize((j - 1i64))] / ((work[usize((j - 1i64))] * delta[usize((j - 1i64))])))
                psi = (psi + (z[usize((j - 1i64))] * temp))
                dpsi = (dpsi + (temp * temp))
                erretm = (erretm + psi)
                j = j + 1i64
                zc9 = zc9 - 1i64
            }
            erretm = math.abs[f64](erretm)
            tau2 = (work[usize((n - 1i64))] * delta[usize((n - 1i64))])
            temp = (z[usize((n - 1i64))] / tau2)
            phi = (z[usize((n - 1i64))] * temp)
            dphi = (temp * temp)
            erretm = ((((8.0f64 * (((-phi) - psi))) + erretm) - phi) + rhoinv)
            w = ((rhoinv + phi) + psi)
            niter = niter + 1i64
            zc7 = zc7 - 1i64
            pc = 6i64
            continue
        }
        if pc == 7i64 {
            info = 1i64
            pc = 5i64
            continue
        }
        if pc == 2i64 {
            niter = 1i64
            ip1 = (i + 1i64)
            delsq = (((d[usize((ip1 - 1i64))] - d[usize((i - 1i64))])) * ((d[usize((ip1 - 1i64))] + d[usize((i - 1i64))])))
            delsq2 = (delsq / 2.0f64)
            sq2 = math.sqrt[f64](((((d[usize((i - 1i64))] * d[usize((i - 1i64))]) + (d[usize((ip1 - 1i64))] * d[usize((ip1 - 1i64))]))) / 2.0f64))
            temp = (delsq2 / ((d[usize((i - 1i64))] + sq2)))
            j = 1i64
            zc10 = (n - j) + 1i64
            while zc10 > 0i64 {
                work[usize((j - 1i64))] = ((d[usize((j - 1i64))] + d[usize((i - 1i64))]) + temp)
                delta[usize((j - 1i64))] = (((d[usize((j - 1i64))] - d[usize((i - 1i64))])) - temp)
                j = j + 1i64
                zc10 = zc10 - 1i64
            }
            psi = 0.0f64
            j = 1i64
            zc11 = ((i - 1i64) - j) + 1i64
            while zc11 > 0i64 {
                psi = (psi + ((z[usize((j - 1i64))] * z[usize((j - 1i64))]) / ((work[usize((j - 1i64))] * delta[usize((j - 1i64))]))))
                j = j + 1i64
                zc11 = zc11 - 1i64
            }
            phi = 0.0f64
            j = n
            zs13 = (-1i64)
            zc12 = (((i + 2i64) - j) + zs13) / zs13
            while zc12 > 0i64 {
                phi = (phi + ((z[usize((j - 1i64))] * z[usize((j - 1i64))]) / ((work[usize((j - 1i64))] * delta[usize((j - 1i64))]))))
                j = j + zs13
                zc12 = zc12 - 1i64
            }
            c = ((rhoinv + psi) + phi)
            w = ((c + ((z[usize((i - 1i64))] * z[usize((i - 1i64))]) / ((work[usize((i - 1i64))] * delta[usize((i - 1i64))])))) + ((z[usize((ip1 - 1i64))] * z[usize((ip1 - 1i64))]) / ((work[usize((ip1 - 1i64))] * delta[usize((ip1 - 1i64))]))))
            geomavg = false
            if (w > 0.0f64) {
                orgati = true
                ii = i
                sglb = 0.0f64
                sgub = (delsq2 / ((d[usize((i - 1i64))] + sq2)))
                a = (((c * delsq) + (z[usize((i - 1i64))] * z[usize((i - 1i64))])) + (z[usize((ip1 - 1i64))] * z[usize((ip1 - 1i64))]))
                b = ((z[usize((i - 1i64))] * z[usize((i - 1i64))]) * delsq)
                if (a > 0.0f64) {
                    tau2 = ((2.0f64 * b) / ((a + math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))))
                } else {
                    tau2 = (((a - math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))) / ((2.0f64 * c)))
                }
                tau = (tau2 / ((d[usize((i - 1i64))] + math.sqrt[f64](((d[usize((i - 1i64))] * d[usize((i - 1i64))]) + tau2)))))
                temp = math.sqrt[f64](eps)
                if ((((d[usize((i - 1i64))] <= (temp * d[usize((ip1 - 1i64))]))) && ((math.abs[f64](z[usize((i - 1i64))]) <= temp))) && ((d[usize((i - 1i64))] > 0.0f64))) {
                    tau = lbase.f_min((10.0f64 * d[usize((i - 1i64))]), sgub)
                    geomavg = true
                }
            } else {
                orgati = false
                ii = ip1
                sglb = (-(delsq2 / ((d[usize((ii - 1i64))] + sq2))))
                sgub = 0.0f64
                a = (((c * delsq) - (z[usize((i - 1i64))] * z[usize((i - 1i64))])) - (z[usize((ip1 - 1i64))] * z[usize((ip1 - 1i64))]))
                b = ((z[usize((ip1 - 1i64))] * z[usize((ip1 - 1i64))]) * delsq)
                if (a < 0.0f64) {
                    tau2 = ((2.0f64 * b) / ((a - math.sqrt[f64](math.abs[f64](((a * a) + ((4.0f64 * b) * c)))))))
                } else {
                    tau2 = (-(((a + math.sqrt[f64](math.abs[f64](((a * a) + ((4.0f64 * b) * c)))))) / ((2.0f64 * c))))
                }
                tau = (tau2 / ((d[usize((ip1 - 1i64))] + math.sqrt[f64](math.abs[f64](((d[usize((ip1 - 1i64))] * d[usize((ip1 - 1i64))]) + tau2))))))
            }
            sigma = (d[usize((ii - 1i64))] + tau)
            j = 1i64
            zc14 = (n - j) + 1i64
            while zc14 > 0i64 {
                work[usize((j - 1i64))] = ((d[usize((j - 1i64))] + d[usize((ii - 1i64))]) + tau)
                delta[usize((j - 1i64))] = (((d[usize((j - 1i64))] - d[usize((ii - 1i64))])) - tau)
                j = j + 1i64
                zc14 = zc14 - 1i64
            }
            iim1 = (ii - 1i64)
            iip1 = (ii + 1i64)
            dpsi = 0.0f64
            psi = 0.0f64
            erretm = 0.0f64
            j = 1i64
            zc15 = (iim1 - j) + 1i64
            while zc15 > 0i64 {
                temp = (z[usize((j - 1i64))] / ((work[usize((j - 1i64))] * delta[usize((j - 1i64))])))
                psi = (psi + (z[usize((j - 1i64))] * temp))
                dpsi = (dpsi + (temp * temp))
                erretm = (erretm + psi)
                j = j + 1i64
                zc15 = zc15 - 1i64
            }
            erretm = math.abs[f64](erretm)
            dphi = 0.0f64
            phi = 0.0f64
            j = n
            zs17 = (-1i64)
            zc16 = ((iip1 - j) + zs17) / zs17
            while zc16 > 0i64 {
                temp = (z[usize((j - 1i64))] / ((work[usize((j - 1i64))] * delta[usize((j - 1i64))])))
                phi = (phi + (z[usize((j - 1i64))] * temp))
                dphi = (dphi + (temp * temp))
                erretm = (erretm + phi)
                j = j + zs17
                zc16 = zc16 - 1i64
            }
            w = ((rhoinv + phi) + psi)
            swtch3 = false
            if orgati {
                if (w < 0.0f64) {
                    swtch3 = true
                }
            } else {
                if (w > 0.0f64) {
                    swtch3 = true
                }
            }
            if ((ii == 1i64) || (ii == n)) {
                swtch3 = false
            }
            temp = (z[usize((ii - 1i64))] / ((work[usize((ii - 1i64))] * delta[usize((ii - 1i64))])))
            dw = ((dpsi + dphi) + (temp * temp))
            temp = (z[usize((ii - 1i64))] * temp)
            w = (w + temp)
            erretm = ((((8.0f64 * ((phi - psi))) + erretm) + (2.0f64 * rhoinv)) + (3.0f64 * math.abs[f64](temp)))
            if !(math.abs[f64](w) <= (eps * erretm)) {
                pc = 11i64
                continue
            }
            pc = 5i64
            continue
        }
        if pc == 11i64 {
            pc = 10i64
        }
        if pc == 10i64 {
            if (w <= 0.0f64) {
                sglb = lbase.f_max(sglb, tau)
            } else {
                sgub = lbase.f_min(sgub, tau)
            }
            niter = (niter + 1i64)
            if (!swtch3) {
                dtipsq = (work[usize((ip1 - 1i64))] * delta[usize((ip1 - 1i64))])
                dtisq = (work[usize((i - 1i64))] * delta[usize((i - 1i64))])
                if orgati {
                    c = ((w - (dtipsq * dw)) + (delsq * ((((z[usize((i - 1i64))] / dtisq))) * (((z[usize((i - 1i64))] / dtisq))))))
                } else {
                    c = ((w - (dtisq * dw)) - (delsq * ((((z[usize((ip1 - 1i64))] / dtipsq))) * (((z[usize((ip1 - 1i64))] / dtipsq))))))
                }
                a = ((((dtipsq + dtisq)) * w) - ((dtipsq * dtisq) * dw))
                b = ((dtipsq * dtisq) * w)
                if (c == 0.0f64) {
                    if (a == 0.0f64) {
                        if orgati {
                            a = ((z[usize((i - 1i64))] * z[usize((i - 1i64))]) + ((dtipsq * dtipsq) * ((dpsi + dphi))))
                        } else {
                            a = ((z[usize((ip1 - 1i64))] * z[usize((ip1 - 1i64))]) + ((dtisq * dtisq) * ((dpsi + dphi))))
                        }
                    }
                    eta = (b / a)
                } else if (a <= 0.0f64) {
                    eta = (((a - math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))) / ((2.0f64 * c)))
                } else {
                    eta = ((2.0f64 * b) / ((a + math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))))
                }
            } else {
                dtiim = (work[usize((iim1 - 1i64))] * delta[usize((iim1 - 1i64))])
                dtiip = (work[usize((iip1 - 1i64))] * delta[usize((iip1 - 1i64))])
                temp = ((rhoinv + psi) + phi)
                if orgati {
                    temp1 = (z[usize((iim1 - 1i64))] / dtiim)
                    temp1 = (temp1 * temp1)
                    c = (((temp - (dtiip * ((dpsi + dphi))))) - ((((d[usize((iim1 - 1i64))] - d[usize((iip1 - 1i64))])) * ((d[usize((iim1 - 1i64))] + d[usize((iip1 - 1i64))]))) * temp1))
                    zz[usize((1i64 - 1i64))] = (z[usize((iim1 - 1i64))] * z[usize((iim1 - 1i64))])
                    if (dpsi < temp1) {
                        zz[usize((3i64 - 1i64))] = ((dtiip * dtiip) * dphi)
                    } else {
                        zz[usize((3i64 - 1i64))] = ((dtiip * dtiip) * ((((dpsi - temp1)) + dphi)))
                    }
                } else {
                    temp1 = (z[usize((iip1 - 1i64))] / dtiip)
                    temp1 = (temp1 * temp1)
                    c = (((temp - (dtiim * ((dpsi + dphi))))) - ((((d[usize((iip1 - 1i64))] - d[usize((iim1 - 1i64))])) * ((d[usize((iim1 - 1i64))] + d[usize((iip1 - 1i64))]))) * temp1))
                    if (dphi < temp1) {
                        zz[usize((1i64 - 1i64))] = ((dtiim * dtiim) * dpsi)
                    } else {
                        zz[usize((1i64 - 1i64))] = ((dtiim * dtiim) * ((dpsi + ((dphi - temp1)))))
                    }
                    zz[usize((3i64 - 1i64))] = (z[usize((iip1 - 1i64))] * z[usize((iip1 - 1i64))])
                }
                zz[usize((2i64 - 1i64))] = (z[usize((ii - 1i64))] * z[usize((ii - 1i64))])
                dd[usize((1i64 - 1i64))] = dtiim
                dd[usize((2i64 - 1i64))] = (delta[usize((ii - 1i64))] * work[usize((ii - 1i64))])
                dd[usize((3i64 - 1i64))] = dtiip
                dlaed6(niter, orgati, c, dd[0usize..], zz[0usize..], w, &eta, &info)
                if (info != 0i64) {
                    swtch3 = false
                    info = 0i64
                    dtipsq = (work[usize((ip1 - 1i64))] * delta[usize((ip1 - 1i64))])
                    dtisq = (work[usize((i - 1i64))] * delta[usize((i - 1i64))])
                    if orgati {
                        c = ((w - (dtipsq * dw)) + (delsq * ((((z[usize((i - 1i64))] / dtisq))) * (((z[usize((i - 1i64))] / dtisq))))))
                    } else {
                        c = ((w - (dtisq * dw)) - (delsq * ((((z[usize((ip1 - 1i64))] / dtipsq))) * (((z[usize((ip1 - 1i64))] / dtipsq))))))
                    }
                    a = ((((dtipsq + dtisq)) * w) - ((dtipsq * dtisq) * dw))
                    b = ((dtipsq * dtisq) * w)
                    if (c == 0.0f64) {
                        if (a == 0.0f64) {
                            if orgati {
                                a = ((z[usize((i - 1i64))] * z[usize((i - 1i64))]) + ((dtipsq * dtipsq) * ((dpsi + dphi))))
                            } else {
                                a = ((z[usize((ip1 - 1i64))] * z[usize((ip1 - 1i64))]) + ((dtisq * dtisq) * ((dpsi + dphi))))
                            }
                        }
                        eta = (b / a)
                    } else if (a <= 0.0f64) {
                        eta = (((a - math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))) / ((2.0f64 * c)))
                    } else {
                        eta = ((2.0f64 * b) / ((a + math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))))
                    }
                }
            }
            if ((w * eta) >= 0.0f64) {
                eta = (-(w / dw))
            }
            eta = (eta / ((sigma + math.sqrt[f64](((sigma * sigma) + eta)))))
            temp = (tau + eta)
            if ((temp > sgub) || (temp < sglb)) {
                if (w < 0.0f64) {
                    eta = (((sgub - tau)) / 2.0f64)
                } else {
                    eta = (((sglb - tau)) / 2.0f64)
                }
                if geomavg {
                    if (w < 0.0f64) {
                        if (tau > 0.0f64) {
                            eta = (math.sqrt[f64]((sgub * tau)) - tau)
                        }
                    } else {
                        if (sglb > 0.0f64) {
                            eta = (math.sqrt[f64]((sglb * tau)) - tau)
                        }
                    }
                }
            }
            prew = w
            tau = (tau + eta)
            sigma = (sigma + eta)
            j = 1i64
            zc18 = (n - j) + 1i64
            while zc18 > 0i64 {
                work[usize((j - 1i64))] = (work[usize((j - 1i64))] + eta)
                delta[usize((j - 1i64))] = (delta[usize((j - 1i64))] - eta)
                j = j + 1i64
                zc18 = zc18 - 1i64
            }
            dpsi = 0.0f64
            psi = 0.0f64
            erretm = 0.0f64
            j = 1i64
            zc19 = (iim1 - j) + 1i64
            while zc19 > 0i64 {
                temp = (z[usize((j - 1i64))] / ((work[usize((j - 1i64))] * delta[usize((j - 1i64))])))
                psi = (psi + (z[usize((j - 1i64))] * temp))
                dpsi = (dpsi + (temp * temp))
                erretm = (erretm + psi)
                j = j + 1i64
                zc19 = zc19 - 1i64
            }
            erretm = math.abs[f64](erretm)
            dphi = 0.0f64
            phi = 0.0f64
            j = n
            zs21 = (-1i64)
            zc20 = ((iip1 - j) + zs21) / zs21
            while zc20 > 0i64 {
                temp = (z[usize((j - 1i64))] / ((work[usize((j - 1i64))] * delta[usize((j - 1i64))])))
                phi = (phi + (z[usize((j - 1i64))] * temp))
                dphi = (dphi + (temp * temp))
                erretm = (erretm + phi)
                j = j + zs21
                zc20 = zc20 - 1i64
            }
            tau2 = (work[usize((ii - 1i64))] * delta[usize((ii - 1i64))])
            temp = (z[usize((ii - 1i64))] / tau2)
            dw = ((dpsi + dphi) + (temp * temp))
            temp = (z[usize((ii - 1i64))] * temp)
            w = (((rhoinv + phi) + psi) + temp)
            erretm = ((((8.0f64 * ((phi - psi))) + erretm) + (2.0f64 * rhoinv)) + (3.0f64 * math.abs[f64](temp)))
            swtch = false
            if orgati {
                if ((-w) > (math.abs[f64](prew) / 10.0f64)) {
                    swtch = true
                }
            } else {
                if (w > (math.abs[f64](prew) / 10.0f64)) {
                    swtch = true
                }
            }
            iter = (niter + 1i64)
            niter = iter
            zc22 = (400i64 - niter) + 1i64
            pc = 12i64
        }
        if pc == 12i64 {
            if zc22 <= 0i64 {
                pc = 13i64
                continue
            }
            if !(math.abs[f64](w) <= (eps * erretm)) {
                pc = 15i64
                continue
            }
            pc = 5i64
            continue
        }
        if pc == 15i64 {
            pc = 14i64
        }
        if pc == 14i64 {
            if (w <= 0.0f64) {
                sglb = lbase.f_max(sglb, tau)
            } else {
                sgub = lbase.f_min(sgub, tau)
            }
            if (!swtch3) {
                dtipsq = (work[usize((ip1 - 1i64))] * delta[usize((ip1 - 1i64))])
                dtisq = (work[usize((i - 1i64))] * delta[usize((i - 1i64))])
                if (!swtch) {
                    if orgati {
                        c = ((w - (dtipsq * dw)) + (delsq * ((((z[usize((i - 1i64))] / dtisq))) * (((z[usize((i - 1i64))] / dtisq))))))
                    } else {
                        c = ((w - (dtisq * dw)) - (delsq * ((((z[usize((ip1 - 1i64))] / dtipsq))) * (((z[usize((ip1 - 1i64))] / dtipsq))))))
                    }
                } else {
                    temp = (z[usize((ii - 1i64))] / ((work[usize((ii - 1i64))] * delta[usize((ii - 1i64))])))
                    if orgati {
                        dpsi = (dpsi + (temp * temp))
                    } else {
                        dphi = (dphi + (temp * temp))
                    }
                    c = ((w - (dtisq * dpsi)) - (dtipsq * dphi))
                }
                a = ((((dtipsq + dtisq)) * w) - ((dtipsq * dtisq) * dw))
                b = ((dtipsq * dtisq) * w)
                if (c == 0.0f64) {
                    if (a == 0.0f64) {
                        if (!swtch) {
                            if orgati {
                                a = ((z[usize((i - 1i64))] * z[usize((i - 1i64))]) + ((dtipsq * dtipsq) * ((dpsi + dphi))))
                            } else {
                                a = ((z[usize((ip1 - 1i64))] * z[usize((ip1 - 1i64))]) + ((dtisq * dtisq) * ((dpsi + dphi))))
                            }
                        } else {
                            a = (((dtisq * dtisq) * dpsi) + ((dtipsq * dtipsq) * dphi))
                        }
                    }
                    eta = (b / a)
                } else if (a <= 0.0f64) {
                    eta = (((a - math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))) / ((2.0f64 * c)))
                } else {
                    eta = ((2.0f64 * b) / ((a + math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))))
                }
            } else {
                dtiim = (work[usize((iim1 - 1i64))] * delta[usize((iim1 - 1i64))])
                dtiip = (work[usize((iip1 - 1i64))] * delta[usize((iip1 - 1i64))])
                temp = ((rhoinv + psi) + phi)
                if swtch {
                    c = ((temp - (dtiim * dpsi)) - (dtiip * dphi))
                    zz[usize((1i64 - 1i64))] = ((dtiim * dtiim) * dpsi)
                    zz[usize((3i64 - 1i64))] = ((dtiip * dtiip) * dphi)
                } else {
                    if orgati {
                        temp1 = (z[usize((iim1 - 1i64))] / dtiim)
                        temp1 = (temp1 * temp1)
                        temp2 = ((((d[usize((iim1 - 1i64))] - d[usize((iip1 - 1i64))])) * ((d[usize((iim1 - 1i64))] + d[usize((iip1 - 1i64))]))) * temp1)
                        c = ((temp - (dtiip * ((dpsi + dphi)))) - temp2)
                        zz[usize((1i64 - 1i64))] = (z[usize((iim1 - 1i64))] * z[usize((iim1 - 1i64))])
                        if (dpsi < temp1) {
                            zz[usize((3i64 - 1i64))] = ((dtiip * dtiip) * dphi)
                        } else {
                            zz[usize((3i64 - 1i64))] = ((dtiip * dtiip) * ((((dpsi - temp1)) + dphi)))
                        }
                    } else {
                        temp1 = (z[usize((iip1 - 1i64))] / dtiip)
                        temp1 = (temp1 * temp1)
                        temp2 = ((((d[usize((iip1 - 1i64))] - d[usize((iim1 - 1i64))])) * ((d[usize((iim1 - 1i64))] + d[usize((iip1 - 1i64))]))) * temp1)
                        c = ((temp - (dtiim * ((dpsi + dphi)))) - temp2)
                        if (dphi < temp1) {
                            zz[usize((1i64 - 1i64))] = ((dtiim * dtiim) * dpsi)
                        } else {
                            zz[usize((1i64 - 1i64))] = ((dtiim * dtiim) * ((dpsi + ((dphi - temp1)))))
                        }
                        zz[usize((3i64 - 1i64))] = (z[usize((iip1 - 1i64))] * z[usize((iip1 - 1i64))])
                    }
                }
                dd[usize((1i64 - 1i64))] = dtiim
                dd[usize((2i64 - 1i64))] = (delta[usize((ii - 1i64))] * work[usize((ii - 1i64))])
                dd[usize((3i64 - 1i64))] = dtiip
                dlaed6(niter, orgati, c, dd[0usize..], zz[0usize..], w, &eta, &info)
                if (info != 0i64) {
                    swtch3 = false
                    info = 0i64
                    dtipsq = (work[usize((ip1 - 1i64))] * delta[usize((ip1 - 1i64))])
                    dtisq = (work[usize((i - 1i64))] * delta[usize((i - 1i64))])
                    if (!swtch) {
                        if orgati {
                            c = ((w - (dtipsq * dw)) + (delsq * ((((z[usize((i - 1i64))] / dtisq))) * (((z[usize((i - 1i64))] / dtisq))))))
                        } else {
                            c = ((w - (dtisq * dw)) - (delsq * ((((z[usize((ip1 - 1i64))] / dtipsq))) * (((z[usize((ip1 - 1i64))] / dtipsq))))))
                        }
                    } else {
                        temp = (z[usize((ii - 1i64))] / ((work[usize((ii - 1i64))] * delta[usize((ii - 1i64))])))
                        if orgati {
                            dpsi = (dpsi + (temp * temp))
                        } else {
                            dphi = (dphi + (temp * temp))
                        }
                        c = ((w - (dtisq * dpsi)) - (dtipsq * dphi))
                    }
                    a = ((((dtipsq + dtisq)) * w) - ((dtipsq * dtisq) * dw))
                    b = ((dtipsq * dtisq) * w)
                    if (c == 0.0f64) {
                        if (a == 0.0f64) {
                            if (!swtch) {
                                if orgati {
                                    a = ((z[usize((i - 1i64))] * z[usize((i - 1i64))]) + ((dtipsq * dtipsq) * ((dpsi + dphi))))
                                } else {
                                    a = ((z[usize((ip1 - 1i64))] * z[usize((ip1 - 1i64))]) + ((dtisq * dtisq) * ((dpsi + dphi))))
                                }
                            } else {
                                a = (((dtisq * dtisq) * dpsi) + ((dtipsq * dtipsq) * dphi))
                            }
                        }
                        eta = (b / a)
                    } else if (a <= 0.0f64) {
                        eta = (((a - math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))) / ((2.0f64 * c)))
                    } else {
                        eta = ((2.0f64 * b) / ((a + math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))))
                    }
                }
            }
            if ((w * eta) >= 0.0f64) {
                eta = (-(w / dw))
            }
            eta = (eta / ((sigma + math.sqrt[f64](((sigma * sigma) + eta)))))
            temp = (tau + eta)
            if ((temp > sgub) || (temp < sglb)) {
                if (w < 0.0f64) {
                    eta = (((sgub - tau)) / 2.0f64)
                } else {
                    eta = (((sglb - tau)) / 2.0f64)
                }
                if geomavg {
                    if (w < 0.0f64) {
                        if (tau > 0.0f64) {
                            eta = (math.sqrt[f64]((sgub * tau)) - tau)
                        }
                    } else {
                        if (sglb > 0.0f64) {
                            eta = (math.sqrt[f64]((sglb * tau)) - tau)
                        }
                    }
                }
            }
            prew = w
            tau = (tau + eta)
            sigma = (sigma + eta)
            j = 1i64
            zc23 = (n - j) + 1i64
            while zc23 > 0i64 {
                work[usize((j - 1i64))] = (work[usize((j - 1i64))] + eta)
                delta[usize((j - 1i64))] = (delta[usize((j - 1i64))] - eta)
                j = j + 1i64
                zc23 = zc23 - 1i64
            }
            dpsi = 0.0f64
            psi = 0.0f64
            erretm = 0.0f64
            j = 1i64
            zc24 = (iim1 - j) + 1i64
            while zc24 > 0i64 {
                temp = (z[usize((j - 1i64))] / ((work[usize((j - 1i64))] * delta[usize((j - 1i64))])))
                psi = (psi + (z[usize((j - 1i64))] * temp))
                dpsi = (dpsi + (temp * temp))
                erretm = (erretm + psi)
                j = j + 1i64
                zc24 = zc24 - 1i64
            }
            erretm = math.abs[f64](erretm)
            dphi = 0.0f64
            phi = 0.0f64
            j = n
            zs26 = (-1i64)
            zc25 = ((iip1 - j) + zs26) / zs26
            while zc25 > 0i64 {
                temp = (z[usize((j - 1i64))] / ((work[usize((j - 1i64))] * delta[usize((j - 1i64))])))
                phi = (phi + (z[usize((j - 1i64))] * temp))
                dphi = (dphi + (temp * temp))
                erretm = (erretm + phi)
                j = j + zs26
                zc25 = zc25 - 1i64
            }
            tau2 = (work[usize((ii - 1i64))] * delta[usize((ii - 1i64))])
            temp = (z[usize((ii - 1i64))] / tau2)
            dw = ((dpsi + dphi) + (temp * temp))
            temp = (z[usize((ii - 1i64))] * temp)
            w = (((rhoinv + phi) + psi) + temp)
            erretm = ((((8.0f64 * ((phi - psi))) + erretm) + (2.0f64 * rhoinv)) + (3.0f64 * math.abs[f64](temp)))
            if (((w * prew) > 0.0f64) && (math.abs[f64](w) > (math.abs[f64](prew) / 10.0f64))) {
                swtch = (!swtch)
            }
            niter = niter + 1i64
            zc22 = zc22 - 1i64
            pc = 12i64
            continue
        }
        if pc == 13i64 {
            info = 1i64
            pc = 1i64
            continue
        }
        if pc == 1i64 {
            pc = 5i64
        }
        if pc == 5i64 {
            *sigma_ref = sigma
            *info_ref = info
            ret
        }
    }
}

fn dlasd5(i: i64, d: []f64, z: []f64, delta: []f64, rho: f64, dsigma_ref: *f64, work: []f64) {
    var dsigma = *dsigma_ref
    var b: f64 = 0.0f64
    var c: f64 = 0.0f64
    var del: f64 = 0.0f64
    var delsq: f64 = 0.0f64
    var tau: f64 = 0.0f64
    var w: f64 = 0.0f64
    del = (d[usize((2i64 - 1i64))] - d[usize((1i64 - 1i64))])
    delsq = (del * ((d[usize((2i64 - 1i64))] + d[usize((1i64 - 1i64))])))
    if (i == 1i64) {
        w = (1.0f64 + (((4.0f64 * rho) * ((((z[usize((2i64 - 1i64))] * z[usize((2i64 - 1i64))]) / ((d[usize((1i64 - 1i64))] + (3.0f64 * d[usize((2i64 - 1i64))])))) - ((z[usize((1i64 - 1i64))] * z[usize((1i64 - 1i64))]) / (((3.0f64 * d[usize((1i64 - 1i64))]) + d[usize((2i64 - 1i64))])))))) / del))
        if (w > 0.0f64) {
            b = (delsq + (rho * (((z[usize((1i64 - 1i64))] * z[usize((1i64 - 1i64))]) + (z[usize((2i64 - 1i64))] * z[usize((2i64 - 1i64))])))))
            c = (((rho * z[usize((1i64 - 1i64))]) * z[usize((1i64 - 1i64))]) * delsq)
            tau = ((2.0f64 * c) / ((b + math.sqrt[f64](math.abs[f64](((b * b) - (4.0f64 * c)))))))
            tau = (tau / ((d[usize((1i64 - 1i64))] + math.sqrt[f64](((d[usize((1i64 - 1i64))] * d[usize((1i64 - 1i64))]) + tau)))))
            dsigma = (d[usize((1i64 - 1i64))] + tau)
            delta[usize((1i64 - 1i64))] = (-tau)
            delta[usize((2i64 - 1i64))] = (del - tau)
            work[usize((1i64 - 1i64))] = ((2.0f64 * d[usize((1i64 - 1i64))]) + tau)
            work[usize((2i64 - 1i64))] = (((d[usize((1i64 - 1i64))] + tau)) + d[usize((2i64 - 1i64))])
        } else {
            b = ((-delsq) + (rho * (((z[usize((1i64 - 1i64))] * z[usize((1i64 - 1i64))]) + (z[usize((2i64 - 1i64))] * z[usize((2i64 - 1i64))])))))
            c = (((rho * z[usize((2i64 - 1i64))]) * z[usize((2i64 - 1i64))]) * delsq)
            if (b > 0.0f64) {
                tau = (-((2.0f64 * c) / ((b + math.sqrt[f64](((b * b) + (4.0f64 * c)))))))
            } else {
                tau = (((b - math.sqrt[f64](((b * b) + (4.0f64 * c))))) / 2.0f64)
            }
            tau = (tau / ((d[usize((2i64 - 1i64))] + math.sqrt[f64](math.abs[f64](((d[usize((2i64 - 1i64))] * d[usize((2i64 - 1i64))]) + tau))))))
            dsigma = (d[usize((2i64 - 1i64))] + tau)
            delta[usize((1i64 - 1i64))] = (-((del + tau)))
            delta[usize((2i64 - 1i64))] = (-tau)
            work[usize((1i64 - 1i64))] = ((d[usize((1i64 - 1i64))] + tau) + d[usize((2i64 - 1i64))])
            work[usize((2i64 - 1i64))] = ((2.0f64 * d[usize((2i64 - 1i64))]) + tau)
        }
    } else {
        b = ((-delsq) + (rho * (((z[usize((1i64 - 1i64))] * z[usize((1i64 - 1i64))]) + (z[usize((2i64 - 1i64))] * z[usize((2i64 - 1i64))])))))
        c = (((rho * z[usize((2i64 - 1i64))]) * z[usize((2i64 - 1i64))]) * delsq)
        if (b > 0.0f64) {
            tau = (((b + math.sqrt[f64](((b * b) + (4.0f64 * c))))) / 2.0f64)
        } else {
            tau = ((2.0f64 * c) / (((-b) + math.sqrt[f64](((b * b) + (4.0f64 * c))))))
        }
        tau = (tau / ((d[usize((2i64 - 1i64))] + math.sqrt[f64](((d[usize((2i64 - 1i64))] * d[usize((2i64 - 1i64))]) + tau)))))
        dsigma = (d[usize((2i64 - 1i64))] + tau)
        delta[usize((1i64 - 1i64))] = (-((del + tau)))
        delta[usize((2i64 - 1i64))] = (-tau)
        work[usize((1i64 - 1i64))] = ((d[usize((1i64 - 1i64))] + tau) + d[usize((2i64 - 1i64))])
        work[usize((2i64 - 1i64))] = ((2.0f64 * d[usize((2i64 - 1i64))]) + tau)
    }
    *dsigma_ref = dsigma
    ret
}

fn dlasdt(n: i64, lvl_ref: *i64, nd_ref: *i64, inode: []i64, ndiml: []i64, ndimr: []i64, msub: i64) {
    var lvl = *lvl_ref
    var nd = *nd_ref
    var i: i64 = 0i64
    var il: i64 = 0i64
    var ir: i64 = 0i64
    var llst: i64 = 0i64
    var maxn: i64 = 0i64
    var ncrnt: i64 = 0i64
    var nlvl: i64 = 0i64
    var temp: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    maxn = lbase.i_max(1i64, n)
    temp = (math.log[f64]((f64(maxn) / f64((msub + 1i64)))) / math.log[f64](2.0f64))
    lvl = (i64(temp) + 1i64)
    i = (n / 2i64)
    inode[usize((1i64 - 1i64))] = (i + 1i64)
    ndiml[usize((1i64 - 1i64))] = i
    ndimr[usize((1i64 - 1i64))] = ((n - i) - 1i64)
    il = 0i64
    ir = 1i64
    llst = 1i64
    nlvl = 1i64
    zc1 = ((lvl - 1i64) - nlvl) + 1i64
    while zc1 > 0i64 {
        i = 0i64
        zc2 = ((llst - 1i64) - i) + 1i64
        while zc2 > 0i64 {
            il = (il + 2i64)
            ir = (ir + 2i64)
            ncrnt = (llst + i)
            ndiml[usize((il - 1i64))] = (ndiml[usize((ncrnt - 1i64))] / 2i64)
            ndimr[usize((il - 1i64))] = ((ndiml[usize((ncrnt - 1i64))] - ndiml[usize((il - 1i64))]) - 1i64)
            inode[usize((il - 1i64))] = ((inode[usize((ncrnt - 1i64))] - ndimr[usize((il - 1i64))]) - 1i64)
            ndiml[usize((ir - 1i64))] = (ndimr[usize((ncrnt - 1i64))] / 2i64)
            ndimr[usize((ir - 1i64))] = ((ndimr[usize((ncrnt - 1i64))] - ndiml[usize((ir - 1i64))]) - 1i64)
            inode[usize((ir - 1i64))] = ((inode[usize((ncrnt - 1i64))] + ndiml[usize((ir - 1i64))]) + 1i64)
            i = i + 1i64
            zc2 = zc2 - 1i64
        }
        llst = (llst * 2i64)
        nlvl = nlvl + 1i64
        zc1 = zc1 - 1i64
    }
    nd = ((llst * 2i64) - 1i64)
    *lvl_ref = lvl
    *nd_ref = nd
    ret
}

fn dlasr(side: str, pivot: str, direct: str, m: i64, n: i64, c: []f64, s: []f64, a: []f64, lda: i64) {
    var i: i64 = 0i64
    var info: i64 = 0i64
    var j: i64 = 0i64
    var ctemp: f64 = 0.0f64
    var stemp: f64 = 0.0f64
    var temp: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zs4: i64 = 0i64
    var zc5: i64 = 0i64
    var zc6: i64 = 0i64
    var zc7: i64 = 0i64
    var zc8: i64 = 0i64
    var zs9: i64 = 0i64
    var zc10: i64 = 0i64
    var zc11: i64 = 0i64
    var zc12: i64 = 0i64
    var zc13: i64 = 0i64
    var zs14: i64 = 0i64
    var zc15: i64 = 0i64
    var zc16: i64 = 0i64
    var zc17: i64 = 0i64
    var zc18: i64 = 0i64
    var zs19: i64 = 0i64
    var zc20: i64 = 0i64
    var zc21: i64 = 0i64
    var zc22: i64 = 0i64
    var zc23: i64 = 0i64
    var zs24: i64 = 0i64
    var zc25: i64 = 0i64
    var zc26: i64 = 0i64
    var zc27: i64 = 0i64
    var zc28: i64 = 0i64
    var zs29: i64 = 0i64
    var zc30: i64 = 0i64
    info = 0i64
    if (!((lbase.lsame(side, "L") || lbase.lsame(side, "R")))) {
        info = 1i64
    } else if (!(((lbase.lsame(pivot, "V") || lbase.lsame(pivot, "T")) || lbase.lsame(pivot, "B")))) {
        info = 2i64
    } else if (!((lbase.lsame(direct, "F") || lbase.lsame(direct, "B")))) {
        info = 3i64
    } else if (m < 0i64) {
        info = 4i64
    } else if (n < 0i64) {
        info = 5i64
    } else if (lda < lbase.i_max(1i64, m)) {
        info = 9i64
    }
    if (info != 0i64) {
        ret
    }
    if (((m == 0i64)) || ((n == 0i64))) {
        ret
    }
    if lbase.lsame(side, "L") {
        if lbase.lsame(pivot, "V") {
            if lbase.lsame(direct, "F") {
                j = 1i64
                zc1 = ((m - 1i64) - j) + 1i64
                while zc1 > 0i64 {
                    ctemp = c[usize((j - 1i64))]
                    stemp = s[usize((j - 1i64))]
                    if (((ctemp != 1.0f64)) || ((stemp != 0.0f64))) {
                        i = 1i64
                        zc2 = (n - i) + 1i64
                        while zc2 > 0i64 {
                            temp = a[usize(((j + 1i64) - 1i64) + (i - 1i64) * lda)]
                            a[usize(((j + 1i64) - 1i64) + (i - 1i64) * lda)] = ((ctemp * temp) - (stemp * a[usize((j - 1i64) + (i - 1i64) * lda)]))
                            a[usize((j - 1i64) + (i - 1i64) * lda)] = ((stemp * temp) + (ctemp * a[usize((j - 1i64) + (i - 1i64) * lda)]))
                            i = i + 1i64
                            zc2 = zc2 - 1i64
                        }
                    }
                    j = j + 1i64
                    zc1 = zc1 - 1i64
                }
            } else if lbase.lsame(direct, "B") {
                j = (m - 1i64)
                zs4 = (-1i64)
                zc3 = ((1i64 - j) + zs4) / zs4
                while zc3 > 0i64 {
                    ctemp = c[usize((j - 1i64))]
                    stemp = s[usize((j - 1i64))]
                    if (((ctemp != 1.0f64)) || ((stemp != 0.0f64))) {
                        i = 1i64
                        zc5 = (n - i) + 1i64
                        while zc5 > 0i64 {
                            temp = a[usize(((j + 1i64) - 1i64) + (i - 1i64) * lda)]
                            a[usize(((j + 1i64) - 1i64) + (i - 1i64) * lda)] = ((ctemp * temp) - (stemp * a[usize((j - 1i64) + (i - 1i64) * lda)]))
                            a[usize((j - 1i64) + (i - 1i64) * lda)] = ((stemp * temp) + (ctemp * a[usize((j - 1i64) + (i - 1i64) * lda)]))
                            i = i + 1i64
                            zc5 = zc5 - 1i64
                        }
                    }
                    j = j + zs4
                    zc3 = zc3 - 1i64
                }
            }
        } else if lbase.lsame(pivot, "T") {
            if lbase.lsame(direct, "F") {
                j = 2i64
                zc6 = (m - j) + 1i64
                while zc6 > 0i64 {
                    ctemp = c[usize(((j - 1i64) - 1i64))]
                    stemp = s[usize(((j - 1i64) - 1i64))]
                    if (((ctemp != 1.0f64)) || ((stemp != 0.0f64))) {
                        i = 1i64
                        zc7 = (n - i) + 1i64
                        while zc7 > 0i64 {
                            temp = a[usize((j - 1i64) + (i - 1i64) * lda)]
                            a[usize((j - 1i64) + (i - 1i64) * lda)] = ((ctemp * temp) - (stemp * a[usize((1i64 - 1i64) + (i - 1i64) * lda)]))
                            a[usize((1i64 - 1i64) + (i - 1i64) * lda)] = ((stemp * temp) + (ctemp * a[usize((1i64 - 1i64) + (i - 1i64) * lda)]))
                            i = i + 1i64
                            zc7 = zc7 - 1i64
                        }
                    }
                    j = j + 1i64
                    zc6 = zc6 - 1i64
                }
            } else if lbase.lsame(direct, "B") {
                j = m
                zs9 = (-1i64)
                zc8 = ((2i64 - j) + zs9) / zs9
                while zc8 > 0i64 {
                    ctemp = c[usize(((j - 1i64) - 1i64))]
                    stemp = s[usize(((j - 1i64) - 1i64))]
                    if (((ctemp != 1.0f64)) || ((stemp != 0.0f64))) {
                        i = 1i64
                        zc10 = (n - i) + 1i64
                        while zc10 > 0i64 {
                            temp = a[usize((j - 1i64) + (i - 1i64) * lda)]
                            a[usize((j - 1i64) + (i - 1i64) * lda)] = ((ctemp * temp) - (stemp * a[usize((1i64 - 1i64) + (i - 1i64) * lda)]))
                            a[usize((1i64 - 1i64) + (i - 1i64) * lda)] = ((stemp * temp) + (ctemp * a[usize((1i64 - 1i64) + (i - 1i64) * lda)]))
                            i = i + 1i64
                            zc10 = zc10 - 1i64
                        }
                    }
                    j = j + zs9
                    zc8 = zc8 - 1i64
                }
            }
        } else if lbase.lsame(pivot, "B") {
            if lbase.lsame(direct, "F") {
                j = 1i64
                zc11 = ((m - 1i64) - j) + 1i64
                while zc11 > 0i64 {
                    ctemp = c[usize((j - 1i64))]
                    stemp = s[usize((j - 1i64))]
                    if (((ctemp != 1.0f64)) || ((stemp != 0.0f64))) {
                        i = 1i64
                        zc12 = (n - i) + 1i64
                        while zc12 > 0i64 {
                            temp = a[usize((j - 1i64) + (i - 1i64) * lda)]
                            a[usize((j - 1i64) + (i - 1i64) * lda)] = ((stemp * a[usize((m - 1i64) + (i - 1i64) * lda)]) + (ctemp * temp))
                            a[usize((m - 1i64) + (i - 1i64) * lda)] = ((ctemp * a[usize((m - 1i64) + (i - 1i64) * lda)]) - (stemp * temp))
                            i = i + 1i64
                            zc12 = zc12 - 1i64
                        }
                    }
                    j = j + 1i64
                    zc11 = zc11 - 1i64
                }
            } else if lbase.lsame(direct, "B") {
                j = (m - 1i64)
                zs14 = (-1i64)
                zc13 = ((1i64 - j) + zs14) / zs14
                while zc13 > 0i64 {
                    ctemp = c[usize((j - 1i64))]
                    stemp = s[usize((j - 1i64))]
                    if (((ctemp != 1.0f64)) || ((stemp != 0.0f64))) {
                        i = 1i64
                        zc15 = (n - i) + 1i64
                        while zc15 > 0i64 {
                            temp = a[usize((j - 1i64) + (i - 1i64) * lda)]
                            a[usize((j - 1i64) + (i - 1i64) * lda)] = ((stemp * a[usize((m - 1i64) + (i - 1i64) * lda)]) + (ctemp * temp))
                            a[usize((m - 1i64) + (i - 1i64) * lda)] = ((ctemp * a[usize((m - 1i64) + (i - 1i64) * lda)]) - (stemp * temp))
                            i = i + 1i64
                            zc15 = zc15 - 1i64
                        }
                    }
                    j = j + zs14
                    zc13 = zc13 - 1i64
                }
            }
        }
    } else if lbase.lsame(side, "R") {
        if lbase.lsame(pivot, "V") {
            if lbase.lsame(direct, "F") {
                j = 1i64
                zc16 = ((n - 1i64) - j) + 1i64
                while zc16 > 0i64 {
                    ctemp = c[usize((j - 1i64))]
                    stemp = s[usize((j - 1i64))]
                    if (((ctemp != 1.0f64)) || ((stemp != 0.0f64))) {
                        i = 1i64
                        zc17 = (m - i) + 1i64
                        while zc17 > 0i64 {
                            temp = a[usize((i - 1i64) + ((j + 1i64) - 1i64) * lda)]
                            a[usize((i - 1i64) + ((j + 1i64) - 1i64) * lda)] = ((ctemp * temp) - (stemp * a[usize((i - 1i64) + (j - 1i64) * lda)]))
                            a[usize((i - 1i64) + (j - 1i64) * lda)] = ((stemp * temp) + (ctemp * a[usize((i - 1i64) + (j - 1i64) * lda)]))
                            i = i + 1i64
                            zc17 = zc17 - 1i64
                        }
                    }
                    j = j + 1i64
                    zc16 = zc16 - 1i64
                }
            } else if lbase.lsame(direct, "B") {
                j = (n - 1i64)
                zs19 = (-1i64)
                zc18 = ((1i64 - j) + zs19) / zs19
                while zc18 > 0i64 {
                    ctemp = c[usize((j - 1i64))]
                    stemp = s[usize((j - 1i64))]
                    if (((ctemp != 1.0f64)) || ((stemp != 0.0f64))) {
                        i = 1i64
                        zc20 = (m - i) + 1i64
                        while zc20 > 0i64 {
                            temp = a[usize((i - 1i64) + ((j + 1i64) - 1i64) * lda)]
                            a[usize((i - 1i64) + ((j + 1i64) - 1i64) * lda)] = ((ctemp * temp) - (stemp * a[usize((i - 1i64) + (j - 1i64) * lda)]))
                            a[usize((i - 1i64) + (j - 1i64) * lda)] = ((stemp * temp) + (ctemp * a[usize((i - 1i64) + (j - 1i64) * lda)]))
                            i = i + 1i64
                            zc20 = zc20 - 1i64
                        }
                    }
                    j = j + zs19
                    zc18 = zc18 - 1i64
                }
            }
        } else if lbase.lsame(pivot, "T") {
            if lbase.lsame(direct, "F") {
                j = 2i64
                zc21 = (n - j) + 1i64
                while zc21 > 0i64 {
                    ctemp = c[usize(((j - 1i64) - 1i64))]
                    stemp = s[usize(((j - 1i64) - 1i64))]
                    if (((ctemp != 1.0f64)) || ((stemp != 0.0f64))) {
                        i = 1i64
                        zc22 = (m - i) + 1i64
                        while zc22 > 0i64 {
                            temp = a[usize((i - 1i64) + (j - 1i64) * lda)]
                            a[usize((i - 1i64) + (j - 1i64) * lda)] = ((ctemp * temp) - (stemp * a[usize((i - 1i64) + (1i64 - 1i64) * lda)]))
                            a[usize((i - 1i64) + (1i64 - 1i64) * lda)] = ((stemp * temp) + (ctemp * a[usize((i - 1i64) + (1i64 - 1i64) * lda)]))
                            i = i + 1i64
                            zc22 = zc22 - 1i64
                        }
                    }
                    j = j + 1i64
                    zc21 = zc21 - 1i64
                }
            } else if lbase.lsame(direct, "B") {
                j = n
                zs24 = (-1i64)
                zc23 = ((2i64 - j) + zs24) / zs24
                while zc23 > 0i64 {
                    ctemp = c[usize(((j - 1i64) - 1i64))]
                    stemp = s[usize(((j - 1i64) - 1i64))]
                    if (((ctemp != 1.0f64)) || ((stemp != 0.0f64))) {
                        i = 1i64
                        zc25 = (m - i) + 1i64
                        while zc25 > 0i64 {
                            temp = a[usize((i - 1i64) + (j - 1i64) * lda)]
                            a[usize((i - 1i64) + (j - 1i64) * lda)] = ((ctemp * temp) - (stemp * a[usize((i - 1i64) + (1i64 - 1i64) * lda)]))
                            a[usize((i - 1i64) + (1i64 - 1i64) * lda)] = ((stemp * temp) + (ctemp * a[usize((i - 1i64) + (1i64 - 1i64) * lda)]))
                            i = i + 1i64
                            zc25 = zc25 - 1i64
                        }
                    }
                    j = j + zs24
                    zc23 = zc23 - 1i64
                }
            }
        } else if lbase.lsame(pivot, "B") {
            if lbase.lsame(direct, "F") {
                j = 1i64
                zc26 = ((n - 1i64) - j) + 1i64
                while zc26 > 0i64 {
                    ctemp = c[usize((j - 1i64))]
                    stemp = s[usize((j - 1i64))]
                    if (((ctemp != 1.0f64)) || ((stemp != 0.0f64))) {
                        i = 1i64
                        zc27 = (m - i) + 1i64
                        while zc27 > 0i64 {
                            temp = a[usize((i - 1i64) + (j - 1i64) * lda)]
                            a[usize((i - 1i64) + (j - 1i64) * lda)] = ((stemp * a[usize((i - 1i64) + (n - 1i64) * lda)]) + (ctemp * temp))
                            a[usize((i - 1i64) + (n - 1i64) * lda)] = ((ctemp * a[usize((i - 1i64) + (n - 1i64) * lda)]) - (stemp * temp))
                            i = i + 1i64
                            zc27 = zc27 - 1i64
                        }
                    }
                    j = j + 1i64
                    zc26 = zc26 - 1i64
                }
            } else if lbase.lsame(direct, "B") {
                j = (n - 1i64)
                zs29 = (-1i64)
                zc28 = ((1i64 - j) + zs29) / zs29
                while zc28 > 0i64 {
                    ctemp = c[usize((j - 1i64))]
                    stemp = s[usize((j - 1i64))]
                    if (((ctemp != 1.0f64)) || ((stemp != 0.0f64))) {
                        i = 1i64
                        zc30 = (m - i) + 1i64
                        while zc30 > 0i64 {
                            temp = a[usize((i - 1i64) + (j - 1i64) * lda)]
                            a[usize((i - 1i64) + (j - 1i64) * lda)] = ((stemp * a[usize((i - 1i64) + (n - 1i64) * lda)]) + (ctemp * temp))
                            a[usize((i - 1i64) + (n - 1i64) * lda)] = ((ctemp * a[usize((i - 1i64) + (n - 1i64) * lda)]) - (stemp * temp))
                            i = i + 1i64
                            zc30 = zc30 - 1i64
                        }
                    }
                    j = j + zs29
                    zc28 = zc28 - 1i64
                }
            }
        }
    }
    ret
}

fn dlaed6(kniter: i64, orgati: bool, rho: f64, d: []f64, z: []f64, finit: f64, tau_ref: *f64, info_ref: *i64) {
    var tau = *tau_ref
    var info = *info_ref
    var dscale: [3]f64 = zero
    var zscale: [3]f64 = zero
    var scale: bool = false
    var i: i64 = 0i64
    var iter: i64 = 0i64
    var niter: i64 = 0i64
    var a: f64 = 0.0f64
    var b: f64 = 0.0f64
    var base: f64 = 0.0f64
    var c: f64 = 0.0f64
    var ddf: f64 = 0.0f64
    var df: f64 = 0.0f64
    var eps: f64 = 0.0f64
    var erretm: f64 = 0.0f64
    var eta: f64 = 0.0f64
    var f: f64 = 0.0f64
    var fc: f64 = 0.0f64
    var sclfac: f64 = 0.0f64
    var sclinv: f64 = 0.0f64
    var small1: f64 = 0.0f64
    var small2: f64 = 0.0f64
    var sminv1: f64 = 0.0f64
    var sminv2: f64 = 0.0f64
    var temp: f64 = 0.0f64
    var temp1: f64 = 0.0f64
    var temp2: f64 = 0.0f64
    var temp3: f64 = 0.0f64
    var temp4: f64 = 0.0f64
    var lbd: f64 = 0.0f64
    var ubd: f64 = 0.0f64
    var zc1: i64 = 0i64
    var zc2: i64 = 0i64
    var zc3: i64 = 0i64
    var zc4: i64 = 0i64
    var zc5: i64 = 0i64
    var pc = 0i64
    while true {
        if pc == 0i64 {
            info = 0i64
            if orgati {
                lbd = d[usize((2i64 - 1i64))]
                ubd = d[usize((3i64 - 1i64))]
            } else {
                lbd = d[usize((1i64 - 1i64))]
                ubd = d[usize((2i64 - 1i64))]
            }
            if (finit < 0.0f64) {
                lbd = 0.0f64
            } else {
                ubd = 0.0f64
            }
            niter = 1i64
            tau = 0.0f64
            if (kniter == 2i64) {
                if orgati {
                    temp = (((d[usize((3i64 - 1i64))] - d[usize((2i64 - 1i64))])) / 2.0f64)
                    c = (rho + (z[usize((1i64 - 1i64))] / ((((d[usize((1i64 - 1i64))] - d[usize((2i64 - 1i64))])) - temp))))
                    a = (((c * ((d[usize((2i64 - 1i64))] + d[usize((3i64 - 1i64))]))) + z[usize((2i64 - 1i64))]) + z[usize((3i64 - 1i64))])
                    b = ((((c * d[usize((2i64 - 1i64))]) * d[usize((3i64 - 1i64))]) + (z[usize((2i64 - 1i64))] * d[usize((3i64 - 1i64))])) + (z[usize((3i64 - 1i64))] * d[usize((2i64 - 1i64))]))
                } else {
                    temp = (((d[usize((1i64 - 1i64))] - d[usize((2i64 - 1i64))])) / 2.0f64)
                    c = (rho + (z[usize((3i64 - 1i64))] / ((((d[usize((3i64 - 1i64))] - d[usize((2i64 - 1i64))])) - temp))))
                    a = (((c * ((d[usize((1i64 - 1i64))] + d[usize((2i64 - 1i64))]))) + z[usize((1i64 - 1i64))]) + z[usize((2i64 - 1i64))])
                    b = ((((c * d[usize((1i64 - 1i64))]) * d[usize((2i64 - 1i64))]) + (z[usize((1i64 - 1i64))] * d[usize((2i64 - 1i64))])) + (z[usize((2i64 - 1i64))] * d[usize((1i64 - 1i64))]))
                }
                temp = lbase.f_max(lbase.f_max(math.abs[f64](a), math.abs[f64](b)), math.abs[f64](c))
                a = (a / temp)
                b = (b / temp)
                c = (c / temp)
                if (c == 0.0f64) {
                    tau = (b / a)
                } else if (a <= 0.0f64) {
                    tau = (((a - math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))) / ((2.0f64 * c)))
                } else {
                    tau = ((2.0f64 * b) / ((a + math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))))
                }
                if ((tau < lbd) || (tau > ubd)) {
                    tau = (((lbd + ubd)) / 2.0f64)
                }
                if (((d[usize((1i64 - 1i64))] == tau) || (d[usize((2i64 - 1i64))] == tau)) || (d[usize((3i64 - 1i64))] == tau)) {
                    tau = 0.0f64
                } else {
                    temp = (((finit + ((tau * z[usize((1i64 - 1i64))]) / ((d[usize((1i64 - 1i64))] * ((d[usize((1i64 - 1i64))] - tau)))))) + ((tau * z[usize((2i64 - 1i64))]) / ((d[usize((2i64 - 1i64))] * ((d[usize((2i64 - 1i64))] - tau)))))) + ((tau * z[usize((3i64 - 1i64))]) / ((d[usize((3i64 - 1i64))] * ((d[usize((3i64 - 1i64))] - tau))))))
                    if (temp <= 0.0f64) {
                        lbd = tau
                    } else {
                        ubd = tau
                    }
                    if (math.abs[f64](finit) <= math.abs[f64](temp)) {
                        tau = 0.0f64
                    }
                }
            }
            eps = 1.1102230246251565e-16f64
            base = 2.0f64
            small1 = lbase.f_powi(base, (i64(((math.log[f64](2.2250738585072014e-308f64) / math.log[f64](base)) / 3.0f64))))
            sminv1 = (1.0f64 / small1)
            small2 = (small1 * small1)
            sminv2 = (sminv1 * sminv1)
            if orgati {
                temp = lbase.f_min(math.abs[f64]((d[usize((2i64 - 1i64))] - tau)), math.abs[f64]((d[usize((3i64 - 1i64))] - tau)))
            } else {
                temp = lbase.f_min(math.abs[f64]((d[usize((1i64 - 1i64))] - tau)), math.abs[f64]((d[usize((2i64 - 1i64))] - tau)))
            }
            scale = false
            if (temp <= small1) {
                scale = true
                if (temp <= small2) {
                    sclfac = sminv2
                    sclinv = small2
                } else {
                    sclfac = sminv1
                    sclinv = small1
                }
                i = 1i64
                zc1 = (3i64 - i) + 1i64
                while zc1 > 0i64 {
                    dscale[usize((i - 1i64))] = (d[usize((i - 1i64))] * sclfac)
                    zscale[usize((i - 1i64))] = (z[usize((i - 1i64))] * sclfac)
                    i = i + 1i64
                    zc1 = zc1 - 1i64
                }
                tau = (tau * sclfac)
                lbd = (lbd * sclfac)
                ubd = (ubd * sclfac)
            } else {
                i = 1i64
                zc2 = (3i64 - i) + 1i64
                while zc2 > 0i64 {
                    dscale[usize((i - 1i64))] = d[usize((i - 1i64))]
                    zscale[usize((i - 1i64))] = z[usize((i - 1i64))]
                    i = i + 1i64
                    zc2 = zc2 - 1i64
                }
            }
            fc = 0.0f64
            df = 0.0f64
            ddf = 0.0f64
            i = 1i64
            zc3 = (3i64 - i) + 1i64
            while zc3 > 0i64 {
                temp = (1.0f64 / ((dscale[usize((i - 1i64))] - tau)))
                temp1 = (zscale[usize((i - 1i64))] * temp)
                temp2 = (temp1 * temp)
                temp3 = (temp2 * temp)
                fc = (fc + (temp1 / dscale[usize((i - 1i64))]))
                df = (df + temp2)
                ddf = (ddf + temp3)
                i = i + 1i64
                zc3 = zc3 - 1i64
            }
            f = (finit + (tau * fc))
            if !(math.abs[f64](f) <= 0.0f64) {
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
            if (f <= 0.0f64) {
                lbd = tau
            } else {
                ubd = tau
            }
            iter = (niter + 1i64)
            niter = iter
            zc4 = (40i64 - niter) + 1i64
            pc = 4i64
        }
        if pc == 4i64 {
            if zc4 <= 0i64 {
                pc = 5i64
                continue
            }
            if orgati {
                temp1 = (dscale[usize((2i64 - 1i64))] - tau)
                temp2 = (dscale[usize((3i64 - 1i64))] - tau)
            } else {
                temp1 = (dscale[usize((1i64 - 1i64))] - tau)
                temp2 = (dscale[usize((2i64 - 1i64))] - tau)
            }
            a = ((((temp1 + temp2)) * f) - ((temp1 * temp2) * df))
            b = ((temp1 * temp2) * f)
            c = ((f - (((temp1 + temp2)) * df)) + ((temp1 * temp2) * ddf))
            temp = lbase.f_max(lbase.f_max(math.abs[f64](a), math.abs[f64](b)), math.abs[f64](c))
            a = (a / temp)
            b = (b / temp)
            c = (c / temp)
            if (c == 0.0f64) {
                eta = (b / a)
            } else if (a <= 0.0f64) {
                eta = (((a - math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))) / ((2.0f64 * c)))
            } else {
                eta = ((2.0f64 * b) / ((a + math.sqrt[f64](math.abs[f64](((a * a) - ((4.0f64 * b) * c)))))))
            }
            if ((f * eta) >= 0.0f64) {
                eta = (-(f / df))
            }
            tau = (tau + eta)
            if ((tau < lbd) || (tau > ubd)) {
                tau = (((lbd + ubd)) / 2.0f64)
            }
            fc = 0.0f64
            erretm = 0.0f64
            df = 0.0f64
            ddf = 0.0f64
            i = 1i64
            zc5 = (3i64 - i) + 1i64
            pc = 6i64
        }
        if pc == 6i64 {
            if zc5 <= 0i64 {
                pc = 7i64
                continue
            }
            if !(((dscale[usize((i - 1i64))] - tau)) != 0.0f64) {
                pc = 9i64
                continue
            }
            temp = (1.0f64 / ((dscale[usize((i - 1i64))] - tau)))
            temp1 = (zscale[usize((i - 1i64))] * temp)
            temp2 = (temp1 * temp)
            temp3 = (temp2 * temp)
            temp4 = (temp1 / dscale[usize((i - 1i64))])
            fc = (fc + temp4)
            erretm = (erretm + math.abs[f64](temp4))
            df = (df + temp2)
            ddf = (ddf + temp3)
            pc = 8i64
            continue
        }
        if pc == 9i64 {
            pc = 3i64
            continue
        }
        if pc == 8i64 {
            i = i + 1i64
            zc5 = zc5 - 1i64
            pc = 6i64
            continue
        }
        if pc == 7i64 {
            f = (finit + (tau * fc))
            erretm = ((8.0f64 * ((math.abs[f64](finit) + (math.abs[f64](tau) * erretm)))) + (math.abs[f64](tau) * df))
            if !(((math.abs[f64](f) <= ((4.0f64 * eps) * erretm))) || ((((ubd - lbd)) <= ((4.0f64 * eps) * math.abs[f64](tau))))) {
                pc = 11i64
                continue
            }
            pc = 3i64
            continue
        }
        if pc == 11i64 {
            pc = 10i64
        }
        if pc == 10i64 {
            if (f <= 0.0f64) {
                lbd = tau
            } else {
                ubd = tau
            }
            niter = niter + 1i64
            zc4 = zc4 - 1i64
            pc = 4i64
            continue
        }
        if pc == 5i64 {
            info = 1i64
            pc = 3i64
        }
        if pc == 3i64 {
            if scale {
                tau = (tau * sclinv)
            }
            *tau_ref = tau
            *info_ref = info
            ret
        }
    }
}

fn dlasda(icompq: i64, smlsiz: i64, n: i64, sqre: i64, d: []f64, e: []f64, u: []f64, ldu: i64, vt: []f64, k: []i64, difl: []f64, difr: []f64, z: []f64, poles: []f64, givptr: []i64, givcol: []i64, ldgcol: i64, perm: []i64, givnum: []f64, c: []f64, s: []f64, work: []f64, iwork: []i64, info_ref: *i64) {
    var info = *info_ref
    var i: i64 = 0i64
    var i1: i64 = 0i64
    var ic: i64 = 0i64
    var idxq: i64 = 0i64
    var idxqi: i64 = 0i64
    var im1: i64 = 0i64
    var inode: i64 = 0i64
    var itemp: i64 = 0i64
    var iwk: i64 = 0i64
    var j: i64 = 0i64
    var lf: i64 = 0i64
    var ll: i64 = 0i64
    var lvl: i64 = 0i64
    var lvl2: i64 = 0i64
    var m: i64 = 0i64
    var ncc: i64 = 0i64
    var nd: i64 = 0i64
    var ndb1: i64 = 0i64
    var ndiml: i64 = 0i64
    var ndimr: i64 = 0i64
    var nl: i64 = 0i64
    var nlf: i64 = 0i64
    var nlp1: i64 = 0i64
    var nlvl: i64 = 0i64
    var nr: i64 = 0i64
    var nrf: i64 = 0i64
    var nrp1: i64 = 0i64
    var nru: i64 = 0i64
    var nwork1: i64 = 0i64
    var nwork2: i64 = 0i64
    var smlszp: i64 = 0i64
    var sqrei: i64 = 0i64
    var vf: i64 = 0i64
    var vfi: i64 = 0i64
    var vl: i64 = 0i64
    var vli: i64 = 0i64
    var alpha: f64 = 0.0f64
    var beta: f64 = 0.0f64
    info = (-999i64)
    *info_ref = info
    ret
}

// R's La.svd(x) with nu = nv = min(nr, nc): x is nr by nc column-major; s gets min(nr, nc) singular values descending,
// u is nr by k column-major, vt is k by nc column-major (k = min(nr, nc)); the right singular vectors are the rows of vt.
fn svd_all(a: *mem.Arena, x: []const f64, nr: usize, nc: usize, s: []f64, u: []f64, vt: []f64) -> err {
    var k = nr
    if nc < nr { k = nc }
    let (aa, e1) = mem.alloc[f64](a, nr * nc)
    let (iwork, e2) = mem.alloc[i64](a, 8usize * k)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < nr * nc {
        aa[i] = x[i]
        i += 1usize
    }
    var info = 0i64
    var wk: [1]f64 = zero
    dgesdd("S", i64(nr), i64(nc), aa[0usize..], i64(nr), s, u, i64(nr), vt, i64(k), wk[0usize..], -1i64, iwork[0usize..], &info)
    if info != 0i64 { ret mem.Full }
    let lwork = usize(i64(wk[0usize]))
    let (work, e3) = mem.alloc[f64](a, lwork)
    if e3 != ok { ret mem.Full }
    dgesdd("S", i64(nr), i64(nc), aa[0usize..], i64(nr), s, u, i64(nr), vt, i64(k), work[0usize..], i64(lwork), iwork[0usize..], &info)
    if info != 0i64 { ret mem.Full }
    ret ok
}
