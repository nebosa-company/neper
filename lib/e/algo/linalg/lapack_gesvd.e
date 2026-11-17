// Reference LAPACK 3.12.1 dgesvd for a square n by n matrix (path 10: M at least N but not much larger, n >= 2), the routine the compiled mclust calls
// (dgesvd('N', 'O') for the orientation matrices of EEV, VEV and EVV, ('A', 'A') and ('O', 'N') elsewhere). Its sign convention differs from dgesdd's
// (lapack_gesdd.svd_all), which is why mclust's orientation matrices need this one. dgebrd, dorgbr and dbdsqr are the ones of lapack_gesdd.
// No scaling of a matrix with a tiny or huge norm (dgesvd scales it first).

use e.mem
use e.str
use e.algo.linalg.lapack_base as lbase
use e.algo.linalg.lapack_gesdd as lg

// jobu, jobvt in {"N", "A", "O"} with at most one "O". a (n by n, column-major) is overwritten; s gets the singular values, u / vt the vectors for "A".
// "O" puts the left (right) singular vectors into a: the columns of U (the rows of V**T). Returns dgesvd's info (0 on success).
fn dgesvd_sq(jobu: str, jobvt: str, n: i64, a: []f64, s: []f64, u: []f64, vt: []f64, work: []f64) -> i64 {
    let m = n
    let lda = n
    let wntuas = str.eq(jobu, "A")
    let wntuo = str.eq(jobu, "O")
    let wntun = str.eq(jobu, "N")
    let wntvas = str.eq(jobvt, "A")
    let wntvo = str.eq(jobvt, "O")
    let wntvn = str.eq(jobvt, "N")
    let ie = 0i64
    let itauq = ie + n
    let itaup = itauq + n
    let iwork0 = itaup + n
    var ierr = 0i64
    let lw = 3i64 * n + 4i64 * n * 64i64
    lg.dgebrd(m, n, a[0usize..], lda, s[0usize..], work[usize(ie)..], work[usize(itauq)..], work[usize(itaup)..], work[usize(iwork0)..], lw - iwork0, &ierr)
    if wntuas {
        lbase.dlacpy("L", m, n, a[0usize..], lda, u[0usize..], n)
        lg.dorgbr("Q", m, m, n, u[0usize..], n, work[usize(itauq)..], work[usize(iwork0)..], lw - iwork0, &ierr)
    }
    if wntvas {
        lbase.dlacpy("U", n, n, a[0usize..], lda, vt[0usize..], n)
        lg.dorgbr("P", n, n, n, vt[0usize..], n, work[usize(itaup)..], work[usize(iwork0)..], lw - iwork0, &ierr)
    }
    if wntuo {
        lg.dorgbr("Q", m, n, n, a[0usize..], lda, work[usize(itauq)..], work[usize(iwork0)..], lw - iwork0, &ierr)
    }
    if wntvo {
        lg.dorgbr("P", n, n, n, a[0usize..], lda, work[usize(itaup)..], work[usize(iwork0)..], lw - iwork0, &ierr)
    }
    let iwork = ie + n
    var nru = 0i64
    var ncvt = 0i64
    if wntuas || wntuo { nru = m }
    if wntvas || wntvo { ncvt = n }
    var dum: [1]f64 = zero
    var info = 0i64
    if !wntuo && !wntvo {
        lg.dbdsqr("U", n, ncvt, nru, 0i64, s[0usize..], work[usize(ie)..], vt[0usize..], n, u[0usize..], n, dum[0usize..], 1i64, work[usize(iwork)..], &info)
    } else if !wntuo && wntvo {
        lg.dbdsqr("U", n, ncvt, nru, 0i64, s[0usize..], work[usize(ie)..], a[0usize..], lda, u[0usize..], n, dum[0usize..], 1i64, work[usize(iwork)..], &info)
    } else {
        lg.dbdsqr("U", n, ncvt, nru, 0i64, s[0usize..], work[usize(ie)..], vt[0usize..], n, a[0usize..], lda, dum[0usize..], 1i64, work[usize(iwork)..], &info)
    }
    if wntun && wntvn { ret info }
    ret info
}

// the orientation of the Fortran mseevv family: dgesvd('N', 'O') of the p by p matrix x; vt (p by p, column-major) receives V**T (rows = right singular vectors) and s the singular values
fn gesvd_no(a: *mem.Arena, x: []const f64, p: usize, s: []f64, vt: []f64) -> err {
    let n = i64(p)
    let (aa, e1) = mem.alloc[f64](a, p * p)
    let (work, e2) = mem.alloc[f64](a, 3usize * p + 4usize * p * 64usize + 8usize * p)
    let (uu, e3) = mem.alloc[f64](a, 1usize)
    let (vv, e4) = mem.alloc[f64](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var i = 0usize
    while i < p * p {
        aa[i] = x[i]
        i += 1usize
    }
    let info = dgesvd_sq("N", "O", n, aa, s, uu, vv, work)
    if info != 0i64 { ret mem.Full }
    i = 0usize
    while i < p * p {
        vt[i] = aa[i]
        i += 1usize
    }
    ret ok
}
