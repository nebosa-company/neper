// R polspline lspec: log-spline spectral density estimation. A port of the package's lspecall.c (the stepwise
// addition and deletion of knots and atoms on the periodogram, Newton-Raphson on the Whittle-type likelihood, Rao
// statistics for candidate knots) with the LINPACK dsifa, dsisl and dsidi it calls (Bunch-Kaufman on the upper
// triangle, in the same operation order), and the package's evaluators dlspec, plspec and clspec.
//
// `lspec` takes the periodogram vector exactly as the C routine receives it (for lspec(data=) that is
// Mod(fft(data))^2 / (ny 2 pi) over the first floor((ny + 2) / 2) frequencies; `periodogram` computes it by a
// direct transform). Not here: rlspec (random generation), plot.lspec.

use e.math
use e.math.fft
use e.math.nmath as nm
use e.mem

const NB: usize = 70usize
const W1: usize = 71usize
const CS: usize = 75usize
const C2: usize = 72usize

fn pil() -> f64 { ret 3.141592653589793116f64 }

// --- LINPACK on a column-major array, A(r, c) = a[(c - 1) lda + (r - 1)]

fn aix(lda: usize, r: usize, c: usize) -> usize { ret (c - 1usize) * lda + (r - 1usize) }

fn idamax_col(a: []f64, lda: usize, col: usize, n: usize) -> usize {
    var best = 1usize
    var dm = math.abs[f64](a[aix(lda, 1usize, col)])
    var i = 2usize
    while i <= n {
        let v = math.abs[f64](a[aix(lda, i, col)])
        if v > dm {
            dm = v
            best = i
        }
        i += 1usize
    }
    ret best
}

fn daxpy_c(n: usize, da: f64, a: []f64, xo: usize, yo: usize) {
    if da == 0.0f64 { ret }
    var i = 0usize
    while i < n {
        a[yo + i] = a[yo + i] + da * a[xo + i]
        i += 1usize
    }
}

fn dswap_c(n: usize, a: []f64, xo: usize, yo: usize) {
    var i = 0usize
    while i < n {
        let t = a[xo + i]
        a[xo + i] = a[yo + i]
        a[yo + i] = t
        i += 1usize
    }
}

fn ddot_aa(n: usize, a: []f64, xo: usize, yo: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s = s + a[xo + i] * a[yo + i]
        i += 1usize
    }
    ret s
}

fn ddot_aw(n: usize, a: []f64, xo: usize, w: []f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s = s + a[xo + i] * w[i]
        i += 1usize
    }
    ret s
}

fn iabs(x: i64) -> usize {
    if x < 0 { ret usize(0 - x) }
    ret usize(x)
}

// symmetric indefinite factorisation of the upper triangle; kpvt is 1-based pivot information stored 0-based
fn dsifa(a: []f64, lda: usize, n: usize, kpvt: []i64) -> usize {
    let alpha = (1.0f64 + math.sqrt[f64](17.0f64)) / 8.0f64
    var info = 0usize
    var k = n
    while k != 0usize {
        if k == 1usize {
            kpvt[0usize] = 1
            if a[aix(lda, 1usize, 1usize)] == 0.0f64 { info = 1usize }
            ret info
        }
        let km1 = k - 1usize
        let absakk = math.abs[f64](a[aix(lda, k, k)])
        let imax = idamax_col(a, lda, k, k - 1usize)
        let colmax = math.abs[f64](a[aix(lda, imax, k)])
        var kstep = 1usize
        var swap = false
        if absakk < alpha * colmax {
            var rowmax = 0.0f64
            var j = imax + 1usize
            while j <= k {
                rowmax = math.max[f64](rowmax, math.abs[f64](a[aix(lda, imax, j)]))
                j += 1usize
            }
            if imax != 1usize {
                let jmax = idamax_col(a, lda, imax, imax - 1usize)
                rowmax = math.max[f64](rowmax, math.abs[f64](a[aix(lda, jmax, imax)]))
            }
            if math.abs[f64](a[aix(lda, imax, imax)]) < alpha * rowmax {
                if absakk < alpha * colmax * (colmax / rowmax) {
                    kstep = 2usize
                    swap = imax != km1
                } else {
                    kstep = 1usize
                    swap = false
                }
            } else {
                kstep = 1usize
                swap = true
            }
        }
        if math.max[f64](absakk, colmax) == 0.0f64 {
            kpvt[k - 1usize] = i64(k)
            info = k
        } else {
            if kstep == 1usize {
                if swap {
                    dswap_c(imax, a, aix(lda, 1usize, imax), aix(lda, 1usize, k))
                    var jj = imax
                    while jj <= k {
                        let j = k + imax - jj
                        let t = a[aix(lda, j, k)]
                        a[aix(lda, j, k)] = a[aix(lda, imax, j)]
                        a[aix(lda, imax, j)] = t
                        jj += 1usize
                    }
                }
                var jj = 1usize
                while jj <= km1 {
                    let j = k - jj
                    let mulk = 0.0f64 - a[aix(lda, j, k)] / a[aix(lda, k, k)]
                    daxpy_c(j, mulk, a, aix(lda, 1usize, k), aix(lda, 1usize, j))
                    a[aix(lda, j, k)] = mulk
                    jj += 1usize
                }
                kpvt[k - 1usize] = i64(k)
                if swap { kpvt[k - 1usize] = i64(imax) }
            } else {
                if swap {
                    dswap_c(imax, a, aix(lda, 1usize, imax), aix(lda, 1usize, k - 1usize))
                    var jj = imax
                    while jj <= km1 {
                        let j = km1 + imax - jj
                        let t = a[aix(lda, j, k - 1usize)]
                        a[aix(lda, j, k - 1usize)] = a[aix(lda, imax, j)]
                        a[aix(lda, imax, j)] = t
                        jj += 1usize
                    }
                    let t2 = a[aix(lda, k - 1usize, k)]
                    a[aix(lda, k - 1usize, k)] = a[aix(lda, imax, k)]
                    a[aix(lda, imax, k)] = t2
                }
                let km2 = k - 2usize
                if km2 != 0usize {
                    let ak = a[aix(lda, k, k)] / a[aix(lda, k - 1usize, k)]
                    let akm1 = a[aix(lda, k - 1usize, k - 1usize)] / a[aix(lda, k - 1usize, k)]
                    let denom = 1.0f64 - ak * akm1
                    var jj = 1usize
                    while jj <= km2 {
                        let j = km1 - jj
                        let bk = a[aix(lda, j, k)] / a[aix(lda, k - 1usize, k)]
                        let bkm1 = a[aix(lda, j, k - 1usize)] / a[aix(lda, k - 1usize, k)]
                        let mulk = (akm1 * bk - bkm1) / denom
                        let mulkm1 = (ak * bkm1 - bk) / denom
                        daxpy_c(j, mulk, a, aix(lda, 1usize, k), aix(lda, 1usize, j))
                        daxpy_c(j, mulkm1, a, aix(lda, 1usize, k - 1usize), aix(lda, 1usize, j))
                        a[aix(lda, j, k)] = mulk
                        a[aix(lda, j, k - 1usize)] = mulkm1
                        jj += 1usize
                    }
                }
                kpvt[k - 1usize] = 1 - i64(k)
                if swap { kpvt[k - 1usize] = 0 - i64(imax) }
                kpvt[k - 2usize] = kpvt[k - 1usize]
            }
        }
        k = k - kstep
    }
    ret info
}

// solves A x = b with the factors from dsifa; b is overwritten
fn dsisl(a: []f64, lda: usize, n: usize, kpvt: []i64, b: []f64) {
    var k = n
    while k != 0usize {
        if kpvt[k - 1usize] >= 0 {
            if k != 1usize {
                let kp = usize(kpvt[k - 1usize])
                if kp != k {
                    let t = b[k - 1usize]
                    b[k - 1usize] = b[kp - 1usize]
                    b[kp - 1usize] = t
                }
                let col = aix(lda, 1usize, k)
                let da = b[k - 1usize]
                var i = 0usize
                if da != 0.0f64 {
                    while i < k - 1usize {
                        b[i] = b[i] + da * a[col + i]
                        i += 1usize
                    }
                }
            }
            b[k - 1usize] = b[k - 1usize] / a[aix(lda, k, k)]
            k = k - 1usize
        } else {
            if k != 2usize {
                let kp = iabs(kpvt[k - 1usize])
                if kp != k - 1usize {
                    let t = b[k - 2usize]
                    b[k - 2usize] = b[kp - 1usize]
                    b[kp - 1usize] = t
                }
                let c1 = aix(lda, 1usize, k)
                let d1 = b[k - 1usize]
                var i = 0usize
                if d1 != 0.0f64 {
                    while i < k - 2usize {
                        b[i] = b[i] + d1 * a[c1 + i]
                        i += 1usize
                    }
                }
                let c2 = aix(lda, 1usize, k - 1usize)
                let d2 = b[k - 2usize]
                i = 0usize
                if d2 != 0.0f64 {
                    while i < k - 2usize {
                        b[i] = b[i] + d2 * a[c2 + i]
                        i += 1usize
                    }
                }
            }
            let ak = a[aix(lda, k, k)] / a[aix(lda, k - 1usize, k)]
            let akm1 = a[aix(lda, k - 1usize, k - 1usize)] / a[aix(lda, k - 1usize, k)]
            let bk = b[k - 1usize] / a[aix(lda, k - 1usize, k)]
            let bkm1 = b[k - 2usize] / a[aix(lda, k - 1usize, k)]
            let denom = ak * akm1 - 1.0f64
            b[k - 1usize] = (akm1 * bk - bkm1) / denom
            b[k - 2usize] = (ak * bkm1 - bk) / denom
            k = k - 2usize
        }
    }
    k = 1usize
    while k <= n {
        if kpvt[k - 1usize] >= 0 {
            if k != 1usize {
                b[k - 1usize] = b[k - 1usize] + ddot_aw(k - 1usize, a, aix(lda, 1usize, k), b)
                let kp = usize(kpvt[k - 1usize])
                if kp != k {
                    let t = b[k - 1usize]
                    b[k - 1usize] = b[kp - 1usize]
                    b[kp - 1usize] = t
                }
            }
            k += 1usize
        } else {
            if k != 1usize {
                b[k - 1usize] = b[k - 1usize] + ddot_aw(k - 1usize, a, aix(lda, 1usize, k), b)
                b[k] = b[k] + ddot_aw(k - 1usize, a, aix(lda, 1usize, k + 1usize), b)
                let kp = iabs(kpvt[k - 1usize])
                if kp != k {
                    let t = b[k - 1usize]
                    b[k - 1usize] = b[kp - 1usize]
                    b[kp - 1usize] = t
                }
            }
            k += 2usize
        }
    }
}

// the inverse (job = 1) of the matrix factored by dsifa, in the upper triangle; work has n elements
fn dsidi_inv(a: []f64, lda: usize, n: usize, kpvt: []i64, work: []f64) {
    var k = 1usize
    while k <= n {
        let km1 = k - 1usize
        var kstep = 1usize
        if kpvt[k - 1usize] >= 0 {
            a[aix(lda, k, k)] = 1.0f64 / a[aix(lda, k, k)]
            if km1 >= 1usize {
                var i = 0usize
                while i < km1 {
                    work[i] = a[aix(lda, 1usize, k) + i]
                    i += 1usize
                }
                var j = 1usize
                while j <= km1 {
                    a[aix(lda, j, k)] = ddot_aw(j, a, aix(lda, 1usize, j), work)
                    let da = work[j - 1usize]
                    if da != 0.0f64 {
                        var q = 0usize
                        while q < j - 1usize {
                            a[aix(lda, 1usize, k) + q] = a[aix(lda, 1usize, k) + q] + da * a[aix(lda, 1usize, j) + q]
                            q += 1usize
                        }
                    }
                    j += 1usize
                }
                a[aix(lda, k, k)] = a[aix(lda, k, k)] + ddot_aw(km1, a, aix(lda, 1usize, k), work)
            }
            kstep = 1usize
        } else {
            let t = math.abs[f64](a[aix(lda, k, k + 1usize)])
            let ak = a[aix(lda, k, k)] / t
            let akp1 = a[aix(lda, k + 1usize, k + 1usize)] / t
            let akkp1 = a[aix(lda, k, k + 1usize)] / t
            let d = t * (ak * akp1 - 1.0f64)
            a[aix(lda, k, k)] = akp1 / d
            a[aix(lda, k + 1usize, k + 1usize)] = ak / d
            a[aix(lda, k, k + 1usize)] = (0.0f64 - akkp1) / d
            if km1 >= 1usize {
                var i = 0usize
                while i < km1 {
                    work[i] = a[aix(lda, 1usize, k + 1usize) + i]
                    i += 1usize
                }
                var j = 1usize
                while j <= km1 {
                    a[aix(lda, j, k + 1usize)] = ddot_aw(j, a, aix(lda, 1usize, j), work)
                    let da = work[j - 1usize]
                    if da != 0.0f64 {
                        var q = 0usize
                        while q < j - 1usize {
                            a[aix(lda, 1usize, k + 1usize) + q] = a[aix(lda, 1usize, k + 1usize) + q] + da * a[aix(lda, 1usize, j) + q]
                            q += 1usize
                        }
                    }
                    j += 1usize
                }
                a[aix(lda, k + 1usize, k + 1usize)] = a[aix(lda, k + 1usize, k + 1usize)] + ddot_aw(km1, a, aix(lda, 1usize, k + 1usize), work)
                a[aix(lda, k, k + 1usize)] = a[aix(lda, k, k + 1usize)] + ddot_aa(km1, a, aix(lda, 1usize, k), aix(lda, 1usize, k + 1usize))
                i = 0usize
                while i < km1 {
                    work[i] = a[aix(lda, 1usize, k) + i]
                    i += 1usize
                }
                j = 1usize
                while j <= km1 {
                    a[aix(lda, j, k)] = ddot_aw(j, a, aix(lda, 1usize, j), work)
                    let da = work[j - 1usize]
                    if da != 0.0f64 {
                        var q = 0usize
                        while q < j - 1usize {
                            a[aix(lda, 1usize, k) + q] = a[aix(lda, 1usize, k) + q] + da * a[aix(lda, 1usize, j) + q]
                            q += 1usize
                        }
                    }
                    j += 1usize
                }
                a[aix(lda, k, k)] = a[aix(lda, k, k)] + ddot_aw(km1, a, aix(lda, 1usize, k), work)
            }
            kstep = 2usize
        }
        let ks = iabs(kpvt[k - 1usize])
        if ks != k {
            dswap_c(ks, a, aix(lda, 1usize, ks), aix(lda, 1usize, k))
            var jb = ks
            while jb <= k {
                let j = k + ks - jb
                let tmp = a[aix(lda, j, k)]
                a[aix(lda, j, k)] = a[aix(lda, ks, j)]
                a[aix(lda, ks, j)] = tmp
                jb += 1usize
            }
            if kstep != 1usize {
                let tmp = a[aix(lda, ks, k + 1usize)]
                a[aix(lda, ks, k + 1usize)] = a[aix(lda, k, k + 1usize)]
                a[aix(lda, k, k + 1usize)] = tmp
            }
        }
        k = k + kstep
    }
}

// --- the fitter's state (lspecall.c keeps these as statics and per-call allocations)

type W = struct {
    nx: usize, nk: usize, ns: usize, er: i64, mass: f64,
    data: []f64, xx: []f64, zz: []f64, nothere: []usize,
    ika: []usize, mm: []f64, aa: []f64, aax: []f64, ww: []f64, vv1: []f64, vv2: []f64, betan: []f64, cumul: []f64,
    info: []f64, score: []f64, beta: []f64, coef: []f64, coef2: []f64, basis: []f64, fl: []usize, kts: []f64, spk: []usize, bb: []f64,
    knots: []f64, atoms: []usize, logs: []f64, theta: []f64, ad: []i64,
    la: []f64, lkp: []i64, lw: []f64, uu: []f64, vv: []f64, ev: []f64, nev: usize
}

fn ev3(w: *W, k: f64, x: f64, y: f64) {
    if w.nev + 3usize <= w.ev.len {
        w.ev[w.nev] = k
        w.ev[w.nev + 1usize] = x
        w.ev[w.nev + 2usize] = y
        w.nev += 3usize
    }
}

// a solve through dsifa and dsisl on the n by n matrix a (stride W1), b overwritten
fn tslusolve(w: *W, a: []f64, n: usize, b: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            w.la[j * 75usize + i] = a[j * W1 + i]
            j += 1usize
        }
        w.lw[i] = b[i]
        i += 1usize
    }
    let _ = dsifa(w.la, 75usize, n, w.lkp)
    dsisl(w.la, 75usize, n, w.lkp, w.lw)
    i = 0usize
    while i < n {
        b[i] = w.lw[i]
        i += 1usize
    }
}

// inverts the symmetric n by n matrix a (stride W1) in place
fn tsluinverse(w: *W, a: []f64, n: usize) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            w.la[j * 75usize + i] = a[j * W1 + i]
            j += 1usize
        }
        i += 1usize
    }
    let _ = dsifa(w.la, 75usize, n, w.lkp)
    dsidi_inv(w.la, 75usize, n, w.lkp, w.lw)
    i = 0usize
    while i < n {
        var j = 0usize
        while j < i {
            a[i * W1 + j] = w.la[i * 75usize + j]
            j += 1usize
        }
        j = i
        while j < n {
            a[i * W1 + j] = w.la[j * 75usize + i]
            j += 1usize
        }
        i += 1usize
    }
}

fn tsintsum(rr: []f64, k0: usize, k1: usize, f: f64) {
    let l0 = f64(k0) * (f64(k0) + 1.0f64)
    let l1 = f64(k1) * (f64(k1) + 1.0f64)
    let m0 = 2.0f64 * f64(k0) + 1.0f64
    let m1 = 2.0f64 * f64(k1) + 1.0f64
    rr[0usize] = f64(k1) - f64(k0)
    rr[1usize] = f * (l1 - l0) / 2.0f64
    var ff = f * f
    rr[2usize] = ff * (l1 * m1 - l0 * m0) / 6.0f64
    ff = ff * f
    rr[3usize] = ff * (l1 * l1 - l0 * l0) / 4.0f64
    ff = ff * f
    rr[4usize] = ff * (l1 * m1 * (3.0f64 * l1 - 1.0f64) - l0 * m0 * (3.0f64 * l0 - 1.0f64)) / 30.0f64
    ff = ff * f
    rr[5usize] = ff * (l1 * l1 * (2.0f64 * l1 - 1.0f64) - l0 * l0 * (2.0f64 * l0 - 1.0f64)) / 12.0f64
    let a1 = f64(k1)
    let a0 = f64(k0)
    rr[6usize] = ff * f * (l1 * m1 * (1.0f64 - 3.0f64 * a1 * (1.0f64 - a1 * a1 * (2.0f64 + a1))) - l0 * m0 * (1.0f64 - 3.0f64 * a0 * (1.0f64 - a0 * a0 * (2.0f64 + a0)))) / 42.0f64
}

// --- basis functions (coef has stride CS)

fn tsb5(w: *W, col: usize, row: usize, i: usize) {
    let kk = w.kts
    var uu: []f64 = w.uu
    var vv: []f64 = w.vv
    uu[0usize] = 1.0f64
    uu[4usize] = 0.0f64
    uu[2usize] = (kk[i + 1usize] - kk[i]) * (kk[i + 3usize] - kk[i]) / ((kk[i + 2usize] - kk[i + 1usize]) * (kk[i + 3usize] - kk[i + 2usize]))
    uu[3usize] = (kk[i + 1usize] - kk[i]) * (kk[i] - kk[i + 2usize]) / ((kk[i + 3usize] - kk[i + 1usize]) * (kk[i + 3usize] - kk[i + 2usize]))
    uu[1usize] = -1.0f64 - uu[3usize] - uu[2usize]
    var r0 = 0.0f64
    var j = 0usize
    while j < 4usize {
        r0 = r0 + uu[j] * (kk[i + 4usize] - kk[i + j]) * (kk[i + 4usize] - kk[i + j]) * (kk[i + 4usize] - kk[i + j])
        j += 1usize
    }
    vv[1usize] = 1.0f64
    vv[0usize] = 0.0f64
    vv[3usize] = (kk[i + 2usize] - kk[i + 1usize]) * (kk[i + 4usize] - kk[i + 1usize]) / ((kk[i + 3usize] - kk[i + 2usize]) * (kk[i + 4usize] - kk[i + 3usize]))
    vv[4usize] = (kk[i + 2usize] - kk[i + 1usize]) * (kk[i + 1usize] - kk[i + 3usize]) / ((kk[i + 4usize] - kk[i + 2usize]) * (kk[i + 4usize] - kk[i + 3usize]))
    vv[2usize] = -1.0f64 - vv[3usize] - vv[4usize]
    var r1 = 0.0f64
    j = 1usize
    while j < 5usize {
        r1 = r1 + vv[j] * (kk[i + 4usize] - kk[i + j]) * (kk[i + 4usize] - kk[i + j]) * (kk[i + 4usize] - kk[i + j])
        j += 1usize
    }
    j = 0usize
    while j < 5usize {
        w.coef[row * CS + col + j] = uu[j] - r0 / r1 * vv[j]
        j += 1usize
    }
}

fn tsb2(w: *W, col: usize, row: usize, i: usize) {
    let kk = w.kts
    let p = pil()
    w.coef[row * CS + 2usize] = 1.0f64
    w.coef[row * CS + col] = 2.0f64 * p / (3.0f64 * ((p - kk[i + 1usize]) * (p - kk[i + 1usize]) - (p - kk[i]) * (p - kk[i])))
    w.coef[row * CS + col + 1usize] = -w.coef[row * CS + col]
}

fn tsb3(w: *W, col: usize, row: usize, i: usize) {
    let kk = w.kts
    let p = pil()
    let o = row * CS
    w.coef[o] = 1.0f64
    w.coef[o + col + 1usize] = p / (3.0f64 * (kk[i + 1usize] - kk[i]))
    w.coef[o + col] = -w.coef[o + col + 1usize]
    w.coef[o + 2usize] = w.coef[o + col + 1usize] * (p - kk[i + 1usize]) * (p - kk[i + 1usize])
    w.coef[o + 2usize] = w.coef[o + 2usize] + w.coef[o + col] * (p - kk[i]) * (p - kk[i])
    w.coef[o + 2usize] = -(w.coef[o + 2usize] * 3.0f64) / (2.0f64 * p)
    let r = 1.0f64 + p * p * w.coef[o + 2usize] + w.coef[o + col] * (p - kk[i]) * (p - kk[i]) * (p - kk[i]) + w.coef[o + col + 1usize] * (p - kk[i + 1usize]) * (p - kk[i + 1usize]) * (p - kk[i + 1usize])
    w.coef[o + col + 1usize] = w.coef[o + col + 1usize] / (1.0f64 - r)
    w.coef[o + col] = w.coef[o + col] / (1.0f64 - r)
    w.coef[o + 2usize] = w.coef[o + 2usize] / (1.0f64 - r)
}

fn tsb4(w: *W, col: usize, row: usize, i: usize) {
    let kk = w.kts
    let o = row * CS
    w.coef[o + col] = 1.0f64
    w.coef[o + col + 2usize] = (kk[i + 1usize] - kk[i]) * (kk[i + 3usize] - kk[i]) / ((kk[i + 2usize] - kk[i + 1usize]) * (kk[i + 3usize] - kk[i + 2usize]))
    w.coef[o + col + 3usize] = (kk[i + 1usize] - kk[i]) * (kk[i] - kk[i + 2usize]) / ((kk[i + 3usize] - kk[i + 1usize]) * (kk[i + 3usize] - kk[i + 2usize]))
    w.coef[o + col + 1usize] = -1.0f64 - w.coef[o + col + 3usize] - w.coef[o + col + 2usize]
}

// the continuous basis for the current knots: basis (nx rows, stride W1), coef2 (4 by nb by nb + 1), fl
fn tsbasis(w: *W) {
    let n = w.nx
    let nb = w.nk
    let kk = w.kts
    let xx = w.xx
    let p = pil()
    var i = 0usize
    while i < NB {
        var j = 0usize
        while j < NB + 4usize {
            w.coef[i * CS + j] = 0.0f64
            j += 1usize
        }
        i += 1usize
    }
    w.coef[0usize] = 1.0f64
    if nb > 1usize { tsb2(w, nb + 2usize, 1usize, nb - 2usize) }
    if nb > 2usize { tsb3(w, 4usize, 2usize, 0usize) }
    if nb > 3usize { tsb4(w, nb, 3usize, nb - 4usize) }
    i = 5usize
    while i <= nb {
        tsb5(w, i - 1usize, i - 1usize, i - 5usize)
        i += 1usize
    }
    i = 0usize
    while i < n {
        w.basis[i * W1] = 1.0f64
        var j = 1usize
        while j < nb {
            w.basis[i * W1 + j] = w.coef[j * CS] + xx[i] * xx[i] * w.coef[j * CS + 2usize]
            j += 1usize
        }
        i += 1usize
    }
    var k = 4usize
    while k < nb + 4usize {
        var q = n
        while q > 0usize {
            let ii = q - 1usize
            if xx[ii] > kk[k - 4usize] {
                let r1 = (xx[ii] - kk[k - 4usize]) * (xx[ii] - kk[k - 4usize]) * (xx[ii] - kk[k - 4usize])
                var j = 1usize
                while j < nb {
                    w.basis[ii * W1 + j] = w.basis[ii * W1 + j] + w.coef[j * CS + k] * r1
                    j += 1usize
                }
                q -= 1usize
            } else {
                q = 0usize
            }
        }
        k += 1usize
    }
    i = 0usize
    while i < nb {
        w.fl[2usize * i] = 1usize
        w.fl[2usize * i + 1usize] = n
        if i >= 4usize {
            let v = i64(kk[i - 4usize] * f64(n) / p) - 1
            if v < 1 { w.fl[2usize * i] = 1usize } else { w.fl[2usize * i] = usize(v) }
            w.fl[2usize * i + 1usize] = n
        }
        i += 1usize
    }
    i = 0usize
    while i < nb {
        var j = 0usize
        while j < nb + 1usize {
            var k2 = 0usize
            while k2 < 4usize {
                w.coef2[(k2 * W1 + i) * C2 + j] = 0.0f64
                k2 += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nb {
        var j = 0usize
        while j <= nb {
            w.coef2[(0usize * W1 + i) * C2 + j] = w.coef2[(0usize * W1 + i) * C2 + j] + w.coef[i * CS]
            w.coef2[(2usize * W1 + i) * C2 + j] = w.coef2[(2usize * W1 + i) * C2 + j] + w.coef[i * CS + 2usize]
            var q = 0usize
            while q < j {
                let c = w.coef[i * CS + q + 4usize]
                w.coef2[(0usize * W1 + i) * C2 + j] = w.coef2[(0usize * W1 + i) * C2 + j] + (-c * kk[q] * kk[q] * kk[q])
                w.coef2[(1usize * W1 + i) * C2 + j] = w.coef2[(1usize * W1 + i) * C2 + j] + 3.0f64 * c * kk[q] * kk[q]
                w.coef2[(2usize * W1 + i) * C2 + j] = w.coef2[(2usize * W1 + i) * C2 + j] + (-3.0f64 * c * kk[q])
                w.coef2[(3usize * W1 + i) * C2 + j] = w.coef2[(3usize * W1 + i) * C2 + j] + c
                q += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
}

// log-likelihood; what 1 also score and information, 2 also the cumulative sums used by the next addition
fn tslogall(w: *W, beta: []f64, what: usize) -> f64 {
    let n = w.nx
    let nk = w.nk
    let nd = nk + w.ns
    let bb = w.bb
    let basis = w.basis
    let info = w.info
    let score = w.score
    let xx = w.xx
    let data = w.data
    let cs = n + 1usize
    let b1 = basis[(n - 1usize) * W1 + 1usize]
    let b3 = basis[(n - 1usize) * W1 + 3usize]
    var logl = 0.0f64
    if what > 0usize {
        var i = 0usize
        while i < nd {
            score[i] = 0.0f64
            var j = 0usize
            while j < nd {
                info[i * W1 + j] = 0.0f64
                j += 1usize
            }
            i += 1usize
        }
    }
    var k = 1usize
    while k < n {
        bb[k] = 0.0f64
        var i = 0usize
        while i < nk {
            bb[k] = bb[k] + beta[i] * basis[k * W1 + i]
            i += 1usize
        }
        k += 1usize
    }
    k = nk
    while k < nd {
        bb[w.spk[k - nk]] = bb[w.spk[k - nk]] + beta[k]
        k += 1usize
    }
    k = 1usize
    while k < n {
        logl = logl - bb[k]
        bb[k] = data[k] * math.exp[f64](-bb[k])
        logl = logl - bb[k]
        k += 1usize
    }
    if xx[n - 1usize] >= 3.1415926f64 {
        logl = logl + 0.5f64 * (bb[n - 1usize] - math.log[f64](bb[n - 1usize] / data[n - 1usize]))
    }
    if what == 2usize {
        k = n - 1usize
        while k > 0usize {
            var r1 = bb[k]
            w.cumul[k - 1usize] = w.cumul[k] + bb[k]
            var j = 1usize
            while j < 7usize {
                r1 = r1 * xx[k]
                w.cumul[j * cs + k - 1usize] = w.cumul[j * cs + k] + r1
                j += 1usize
            }
            k -= 1usize
        }
    }
    if what > 0usize {
        var i = 0usize
        while i < nk {
            k = w.fl[2usize * i]
            while k < w.fl[2usize * i + 1usize] {
                score[i] = score[i] - basis[k * W1 + i] * (1.0f64 - bb[k])
                k += 1usize
            }
            var j = 0usize
            while j <= i {
                var kb = w.fl[2usize * i]
                if w.fl[2usize * j] > kb { kb = w.fl[2usize * j] }
                var uu = w.fl[2usize * i + 1usize]
                if w.fl[2usize * j + 1usize] > uu { uu = w.fl[2usize * j + 1usize] }
                k = kb
                while k < uu {
                    info[i * W1 + j] = info[i * W1 + j] - basis[k * W1 + i] * bb[k] * basis[k * W1 + j]
                    k += 1usize
                }
                j += 1usize
            }
            i += 1usize
        }
        if xx[n - 1usize] >= 3.1415926f64 {
            bb[n - 1usize] = 0.5f64 * bb[n - 1usize]
            score[0usize] = score[0usize] + (0.5f64 - bb[n - 1usize])
            info[0usize] = info[0usize] + bb[n - 1usize]
            if nk > 1usize {
                score[1usize] = score[1usize] + b1 * (0.5f64 - bb[n - 1usize])
                info[W1] = info[W1] + b1 * bb[n - 1usize]
                info[W1 + 1usize] = info[W1 + 1usize] + b1 * b1 * bb[n - 1usize]
                if nk > 3usize {
                    score[3usize] = score[3usize] + b3 * (0.5f64 - bb[n - 1usize])
                    info[3usize * W1] = info[3usize * W1] + b3 * bb[n - 1usize]
                    info[3usize * W1 + 1usize] = info[3usize * W1 + 1usize] + b3 * b1 * bb[n - 1usize]
                    info[3usize * W1 + 3usize] = info[3usize * W1 + 3usize] + b3 * b3 * bb[n - 1usize]
                }
            }
            bb[n - 1usize] = 2.0f64 * bb[n - 1usize]
        }
        i = 0usize
        while i < nk {
            var j = i + 1usize
            while j < nk {
                info[i * W1 + j] = info[j * W1 + i]
                j += 1usize
            }
            i += 1usize
        }
        i = nk
        while i < nd {
            let s = w.spk[i - nk]
            score[i] = 1.0f64 - bb[s]
            info[i * W1 + i] = -bb[s]
            i += 1usize
        }
        i = nk
        while i < nd {
            let s = w.spk[i - nk]
            var j = 0usize
            while j < nk {
                info[i * W1 + j] = -bb[s] * basis[s * W1 + j]
                info[j * W1 + i] = info[i * W1 + j]
                j += 1usize
            }
            i += 1usize
        }
        if w.ns > 0usize {
            if w.spk[w.ns - 1usize] == n - 1usize && xx[n - 1usize] >= 3.1415926f64 {
                let l = nd - 1usize
                score[l] = 0.5f64 * score[l]
                info[l * W1 + l] = 0.5f64 * info[l * W1 + l]
                info[l] = 0.5f64 * info[l]
                info[l * W1] = info[l]
                if nk > 1usize {
                    info[W1 + l] = 0.5f64 * info[W1 + l]
                    info[l * W1 + 1usize] = info[W1 + l]
                    if nk > 3usize {
                        info[3usize * W1 + l] = 0.5f64 * info[3usize * W1 + l]
                        info[l * W1 + 3usize] = info[3usize * W1 + l]
                    }
                }
            }
        }
    }
    ret logl
}

// Newton-Raphson for the current model; w.er is set (0 fine, 1 step halving failed, 2 no convergence, -1 an atom too small)
fn tsnew(w: *W) -> f64 {
    let n = w.nx
    let nk = w.nk
    let nd = nk + w.ns
    let xx = w.xx
    let zz = w.zz
    let kk = w.kts
    let beta = w.beta
    let info = w.info
    let uu = w.uu
    let vv = w.vv
    w.er = 0
    var i = 0usize
    while i < nd {
        beta[i] = 0.0f64
        var j = 0usize
        while j <= i {
            info[i * W1 + j] = 0.0f64
            j += 1usize
        }
        i += 1usize
    }
    var k2 = 0usize
    var k1 = 0usize
    var k3 = 0usize
    var j = 0usize
    while j < 4usize {
        vv[j] = 0.0f64
        j += 1usize
    }
    if math.abs[f64](xx[0usize] - kk[0usize]) < 1.0e-20f64 { k1 = 1usize }
    var k = 1usize
    while k < n {
        vv[0usize] = vv[0usize] + zz[k]
        vv[1usize] = vv[1usize] + zz[k] * xx[k]
        vv[2usize] = vv[2usize] + zz[k] * xx[k] * xx[k]
        vv[3usize] = vv[3usize] + zz[k] * xx[k] * xx[k] * xx[k]
        var hit = k == n - 1usize
        if !hit { hit = xx[k + 1usize] >= kk[k1] && k1 < nk }
        if hit { k3 = k }
        if k3 > 0usize {
            i = 0usize
            while i < nk {
                j = 0usize
                while j < 4usize {
                    beta[i] = beta[i] + w.coef2[(j * W1 + i) * C2 + k1] * vv[j]
                    j += 1usize
                }
                i += 1usize
            }
            tsintsum(uu, k2, k3, xx[1usize])
            i = 0usize
            while i < nk {
                j = 0usize
                while j <= i {
                    var l = 0usize
                    while l < 4usize {
                        var l2 = 0usize
                        while l2 < 4usize {
                            info[i * W1 + j] = info[i * W1 + j] + w.coef2[(l * W1 + i) * C2 + k1] * w.coef2[(l2 * W1 + j) * C2 + k1] * uu[l + l2]
                            l2 += 1usize
                        }
                        l += 1usize
                    }
                    j += 1usize
                }
                i += 1usize
            }
            k1 += 1usize
            j = 0usize
            while j < 4usize {
                vv[j] = 0.0f64
                j += 1usize
            }
            k3 = 0usize
            k2 = k
        }
        k += 1usize
    }
    i = nk
    while i < nd {
        beta[i] = zz[w.spk[i - nk]]
        info[i * W1 + i] = 1.0f64
        j = 0usize
        while j < nk {
            info[i * W1 + j] = w.basis[w.spk[i - nk] * W1 + j]
            info[j * W1 + i] = w.basis[w.spk[i - nk] * W1 + j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nd {
        j = i + 1usize
        while j < nd {
            info[i * W1 + j] = info[j * W1 + i]
            j += 1usize
        }
        i += 1usize
    }
    tslusolve(w, info, nd, beta)
    var it = 0usize
    var logold = 0.0f64
    while it < 100usize {
        logold = tslogall(w, beta, 1usize)
        tslusolve(w, info, nd, w.score)
        j = 0usize
        while j < nd {
            w.betan[j] = beta[j] - w.score[j]
            j += 1usize
        }
        var lognew = tslogall(w, w.betan, 0usize)
        var zerror = lognew - logold
        if lognew < logold - 1.0e-7f64 {
            zerror = 1.0f64
            var r = 1.0f64
            var go = true
            while go {
                if r < 0.000001f64 {
                    w.er = 1
                    ret logold
                }
                r = r / 2.0f64
                j = 0usize
                while j < nd {
                    w.betan[j] = beta[j] - w.score[j] * r
                    j += 1usize
                }
                lognew = tslogall(w, w.betan, 0usize)
                go = lognew < logold - 1.0e-7f64
            }
        }
        j = 0usize
        while j < nd {
            beta[j] = w.betan[j]
            j += 1usize
        }
        if zerror < 0.000001f64 {
            lognew = tslogall(w, beta, 2usize)
            j = nk
            while j < nd {
                var xz = 0.0f64
                var i1 = 0usize
                while i1 < nk {
                    xz = xz + beta[i1] * w.basis[w.spk[j - nk] * W1 + i1]
                    i1 += 1usize
                }
                beta[j] = math.exp[f64](xz + beta[j]) - math.exp[f64](xz)
                j += 1usize
            }
            j = nk
            while j < nd {
                if beta[j] < w.mass {
                    w.nothere[w.spk[j - nk]] = 1usize
                    w.nothere[0usize] = w.nothere[0usize] + 1usize
                    var jj = j
                    while jj + 1usize < nd {
                        w.spk[jj - nk] = w.spk[jj + 1usize - nk]
                        jj += 1usize
                    }
                    w.er = 0 - 1
                    ret 0.0f64
                }
                j += 1usize
            }
            ret lognew
        }
        it += 1usize
    }
    w.er = 2
    ret logold
}

// Rao statistic of an atom at loc
fn tsraod(w: *W, loc: usize, nd: usize) -> f64 {
    let n = w.nx
    let nk = w.nk
    let vv = w.vv1
    let mm = w.mm
    let bb = w.bb
    var bbn = 1.0f64 - bb[loc]
    vv[nd] = -bb[loc]
    var i = 0usize
    while i < nk {
        vv[i] = -bb[loc] * w.basis[loc * W1 + i]
        i += 1usize
    }
    i = nk
    while i < nd {
        vv[i] = 0.0f64
        i += 1usize
    }
    if loc == n - 1usize && w.xx[n - 1usize] >= 3.1415926f64 {
        bbn = 0.5f64 * bbn
        vv[nd] = 0.5f64 * vv[nd]
        vv[0usize] = 0.5f64 * vv[0usize]
        if nk > 1usize {
            vv[1usize] = 0.5f64 * vv[1usize]
            if nk > 3usize { vv[3usize] = 0.5f64 * vv[3usize] }
        }
    }
    var r1 = 0.0f64
    i = 0usize
    while i < nd {
        var j = 0usize
        while j < i {
            r1 = r1 - vv[i] * vv[j] * mm[i * W1 + j]
            j += 1usize
        }
        i += 1usize
    }
    r1 = r1 * 2.0f64
    i = 0usize
    while i < nd {
        r1 = r1 - vv[i] * vv[i] * mm[i * W1 + i]
        i += 1usize
    }
    r1 = r1 + vv[nd]
    bbn = -bbn * bbn / r1
    ret bbn
}

// Rao statistic of a continuous knot at loc (n stands for pi); ika is the index of the first knot
fn tsraoc(w: *W, loc: usize, nd: usize, ika: usize) -> f64 {
    let n = w.nx
    let nk = w.nk
    let p = pil()
    let cs = n + 1usize
    let cum = w.cumul
    let aa = w.aa
    let aax = w.aax
    let ww = w.ww
    let vv = w.vv2
    let kts = w.kts
    let xx = w.xx
    let mm = w.mm
    var bbpi = w.bb[n - 1usize]
    let b1pi = w.basis[(n - 1usize) * W1 + 1usize]
    let b3pi = w.basis[(n - 1usize) * W1 + 3usize]
    var i = 0usize
    while i < nk {
        vv[i] = ww[i]
        i += 1usize
    }
    vv[nd] = 0.0f64
    var xlc = p
    if loc != n { xlc = xx[loc] }
    aa[1usize] = (3.0f64 * ((p - kts[0usize]) * (p - kts[0usize]) - (p - xlc) * (p - xlc))) / (2.0f64 * p)
    aa[3usize] = 3.0f64 * xlc
    aa[5usize] = aa[3usize] * xlc
    aa[7usize] = aa[5usize] * xlc / 3.0f64
    var bbn = ww[NB] + aa[1usize] * (cum[2usize * cs] - cum[9usize * cs]) + cum[3usize * cs + loc] - cum[10usize * cs + loc] - aa[3usize] * (cum[2usize * cs + loc] - cum[9usize * cs + loc]) + aa[5usize] * (cum[1usize * cs + loc] - cum[8usize * cs + loc]) - aa[7usize] * (cum[loc] - cum[7usize * cs + loc])
    var j = 0usize
    while j < nk {
        let r = 13usize + j * 4usize
        vv[j] = vv[j] + (-aa[1usize] * cum[r * cs] - cum[(1usize + r) * cs + loc] + aa[3usize] * cum[r * cs + loc] - aa[5usize] * cum[(r - 1usize) * cs + loc] + aa[7usize] * cum[(r - 2usize) * cs + loc])
        j += 1usize
    }
    var b1 = 0.0f64
    var b2 = 0.0f64
    if xlc > kts[0usize] {
        vv[nd] = (cum[4usize * cs + ika] - cum[4usize * cs]) * aa[1usize] * aa[1usize]
        aax[3usize] = aa[1usize] + aa[2usize] - aa[3usize]
        aax[5usize] = aa[5usize] - aa[4usize]
        aax[7usize] = aa[6usize] - aa[7usize]
        aax[2usize] = aa[1usize] + aa[2usize]
        i = 0usize
        while i < 7usize {
            if i > 3usize {
                if i == 6usize {
                    b1 = 1.0f64
                } else {
                    if i == 5usize {
                        b1 = -2.0f64 * aax[2usize]
                    } else {
                        b1 = 2.0f64 * aa[4usize] + aax[2usize] * aax[2usize]
                        b2 = aax[3usize] * aax[3usize]
                    }
                }
            } else {
                if i > 1usize {
                    if i == 3usize {
                        b1 = -2.0f64 * aa[6usize] - 2.0f64 * aax[2usize] * aa[4usize]
                        b2 = 2.0f64 * aax[3usize] * aax[5usize]
                    } else {
                        b1 = aa[4usize] * aa[4usize] + 2.0f64 * aa[6usize] * aax[2usize]
                        b2 = aax[5usize] * aax[5usize] + 2.0f64 * aax[7usize] * aax[3usize]
                    }
                } else {
                    if i == 1usize {
                        b1 = -2.0f64 * aa[4usize] * aa[6usize]
                        b2 = 2.0f64 * aax[5usize] * aax[7usize]
                    } else {
                        b1 = aa[6usize] * aa[6usize]
                        b2 = aax[7usize] * aax[7usize]
                    }
                }
            }
            vv[nd] = vv[nd] + b1 * (cum[i * cs + loc] - cum[i * cs + ika])
            if i < 5usize { vv[nd] = vv[nd] - b2 * cum[i * cs + loc] }
            i += 1usize
        }
    } else {
        vv[nd] = (cum[4usize * cs + loc] - cum[4usize * cs]) * aa[1usize] * aa[1usize]
        aax[2usize] = aa[1usize] + aa[2usize] - aa[3usize]
        aax[4usize] = aa[5usize] - aa[4usize]
        aax[6usize] = aa[6usize] - aa[7usize]
        aax[3usize] = aa[1usize] - aa[3usize]
        i = 0usize
        while i < 7usize {
            if i > 3usize {
                if i == 6usize {
                    b1 = 1.0f64
                } else {
                    if i == 5usize {
                        b1 = 2.0f64 * aax[3usize]
                    } else {
                        b1 = 2.0f64 * aa[5usize] + aax[3usize] * aax[3usize]
                        b2 = aax[2usize] * aax[2usize]
                    }
                }
            } else {
                if i > 1usize {
                    if i == 3usize {
                        b1 = -2.0f64 * aa[7usize] + 2.0f64 * aax[3usize] * aa[5usize]
                        b2 = 2.0f64 * aax[2usize] * aax[4usize]
                    } else {
                        b1 = aa[5usize] * aa[5usize] - 2.0f64 * aa[7usize] * aax[3usize]
                        b2 = aax[4usize] * aax[4usize] + 2.0f64 * aax[6usize] * aax[2usize]
                    }
                } else {
                    if i == 1usize {
                        b1 = -2.0f64 * aa[5usize] * aa[7usize]
                        b2 = 2.0f64 * aax[4usize] * aax[6usize]
                    } else {
                        b1 = aa[7usize] * aa[7usize]
                        b2 = aax[6usize] * aax[6usize]
                    }
                }
            }
            vv[nd] = vv[nd] + b1 * (cum[i * cs + ika] - cum[i * cs + loc])
            if i < 5usize { vv[nd] = vv[nd] - b2 * cum[i * cs + ika] }
            i += 1usize
        }
    }
    if xx[n - 1usize] > 3.1415926f64 {
        var bsx = p - kts[0usize]
        bsx = (aa[1usize] * p * p + (p - xlc) * (p - xlc) * (p - xlc) - bsx * bsx * bsx) / 2.0f64
        bbn = bbn + bsx * (1.0f64 - bbpi)
        bbpi = bsx * bbpi
        vv[nd] = vv[nd] + bsx * bbpi * 2.0f64
        vv[0usize] = vv[0usize] + bbpi
        if nk > 1usize {
            vv[1usize] = vv[1usize] + bbpi * b1pi
            if nk > 3usize { vv[3usize] = vv[3usize] + bbpi * b3pi }
        }
    }
    i = nk
    while i < nd {
        let x = xx[w.spk[i - nk]]
        var y = aa[1usize] * x * x
        if x > xlc { y = y + (x - xlc) * (x - xlc) * (x - xlc) }
        if x > kts[0usize] { y = y - (x - kts[0usize]) * (x - kts[0usize]) * (x - kts[0usize]) }
        vv[i] = -w.bb[w.spk[i - nk]] * y
        if x > 3.1415926f64 { vv[i] = 0.5f64 * vv[i] }
        i += 1usize
    }
    var r1 = 0.0f64
    i = 0usize
    while i < nd {
        j = 0usize
        while j < i {
            r1 = r1 - vv[i] * vv[j] * mm[i * W1 + j]
            j += 1usize
        }
        i += 1usize
    }
    r1 = r1 * 2.0f64
    i = 0usize
    while i < nd {
        r1 = r1 - vv[i] * vv[i] * mm[i * W1 + i]
        i += 1usize
    }
    r1 = r1 + vv[nd]
    bbn = -bbn * bbn / r1
    ret bbn
}

// adds a knot or an atom (the better Rao statistic); returns the new dimension or -100 when nothing can be added
fn tsadd(w: *W, nd0: usize, mind: usize, cank: usize, cans: usize) -> i64 {
    let n = w.nx
    var nd = nd0
    let p = pil()
    let cs = n + 1usize
    let cum = w.cumul
    let kts = w.kts
    let xx = w.xx
    let ika = w.ika
    let aa = w.aa
    let ww = w.ww
    if w.nk == 0usize {
        w.nk = 1usize
        kts[0usize] = 0.0f64
        ret i64(nd) + 1
    }
    aa[2usize] = 3.0f64 * kts[0usize]
    aa[4usize] = aa[2usize] * kts[0usize]
    aa[6usize] = aa[4usize] * kts[0usize] / 3.0f64
    var i = 0usize
    while i < nd {
        var j = 0usize
        while j < nd {
            w.mm[i * W1 + j] = w.info[i * W1 + j]
            j += 1usize
        }
        i += 1usize
    }
    tsluinverse(w, w.mm, nd)
    var bestloc: i64 = 0 - 1
    var bestlod: i64 = 0 - 1
    var bestraoc = -1.0f64
    var bestraod = -1.0f64
    if cank > 0usize {
        i = n - 1usize
        while i > 0usize {
            var j = 0usize
            while j < w.nk {
                let k = 11usize + 4usize * j
                var r1 = w.basis[i * W1 + j] * w.bb[i]
                cum[k * cs + i - 1usize] = cum[k * cs + i] + r1
                r1 = r1 * xx[i]
                cum[(k + 1usize) * cs + i - 1usize] = cum[(k + 1usize) * cs + i] + r1
                r1 = r1 * xx[i]
                cum[(k + 2usize) * cs + i - 1usize] = cum[(k + 2usize) * cs + i] + r1
                r1 = r1 * xx[i]
                cum[(k + 3usize) * cs + i - 1usize] = cum[(k + 3usize) * cs + i] + r1
                j += 1usize
            }
            i -= 1usize
        }
        var j = 0usize
        i = 0usize
        while i < n - 1usize && j < w.nk {
            if kts[j] < (xx[i] + xx[i + 1usize]) / 2.0f64 {
                ika[j] = i
                j += 1usize
            }
            i += 1usize
        }
        if j < w.nk { ika[j] = n - 1usize }
        ika[w.nk] = n + mind
        if ika[0usize] == 1usize { ika[0usize] = 2usize }
        let i0 = ika[0usize]
        ww[NB] = cum[10usize * cs + i0] - cum[3usize * cs + i0]
        ww[NB] = ww[NB] + aa[2usize] * (cum[2usize * cs + i0] - cum[9usize * cs + i0])
        ww[NB] = ww[NB] - aa[4usize] * (cum[1usize * cs + i0] - cum[8usize * cs + i0])
        ww[NB] = ww[NB] + aa[6usize] * (cum[i0] - cum[7usize * cs + i0])
        j = 0usize
        while j < w.nk {
            let r = 13usize + j * 4usize
            ww[j] = cum[(1usize + r) * cs + i0] - aa[2usize] * cum[r * cs + i0] + aa[4usize] * cum[(r - 1usize) * cs + i0] - aa[6usize] * cum[(r - 2usize) * cs + i0]
            j += 1usize
        }
        bestraoc = -1.0f64
        j = 0usize
        i = 1usize
        if ika[0usize] <= mind {
            i = ika[0usize] + mind + 1usize
            if ika[0usize] == 0usize { i += 1usize }
            j = 1usize
        }
        while i < n {
            if i + mind < ika[j] {
                let nowrao = tsraoc(w, i, nd, ika[0usize])
                if nowrao > bestraoc {
                    bestraoc = nowrao
                    bestloc = i64(i)
                }
            } else {
                i = ika[j] + mind
                j += 1usize
            }
            i += 1usize
        }
    }
    if cans > 0usize {
        var j = 0usize
        w.spk[w.ns] = n + 1usize
        i = 1usize
        while i < n {
            if i == w.spk[j] {
                j += 1usize
            } else {
                if w.bb[i] > 1.0f64 && w.nothere[i] == 0usize {
                    let nowrao = tsraod(w, i, nd)
                    if nowrao > bestraod {
                        bestraod = nowrao
                        bestlod = i64(i)
                    }
                }
            }
            i += 1usize
        }
    }
    if bestloc < 0 && bestlod < 0 { ret 0 - 100 }
    if bestraoc > bestraod {
        if usize(bestloc) < n { kts[w.nk] = xx[usize(bestloc)] } else { kts[w.nk] = p }
        ev3(w, 1.0f64, kts[w.nk], bestraoc)
        i = w.nk
        while i > 0usize {
            if kts[i] < kts[i - 1usize] {
                let t = kts[i - 1usize]
                kts[i - 1usize] = kts[i]
                kts[i] = t
            }
            i -= 1usize
        }
        w.nk += 1usize
        if cank == 2usize {
            kts[0usize] = kts[1usize]
            w.nk = 1usize
            nd -= 1usize
        }
    } else {
        w.spk[w.ns] = usize(bestlod)
        ev3(w, 2.0f64, f64(bestlod), bestraod)
        i = w.ns
        while i > 0usize {
            if w.spk[i] < w.spk[i - 1usize] {
                let t = w.spk[i - 1usize]
                w.spk[i - 1usize] = w.spk[i]
                w.spk[i] = t
            }
            i -= 1usize
        }
        w.ns += 1usize
    }
    ret i64(nd) + 1
}

// removes the knot or atom with the smallest |coefficient| / s.e. ratio; returns the new dimension
fn tsrem(w: *W, nd: usize) -> usize {
    let info = w.info
    let beta = w.beta
    if nd == 2usize {
        w.nk = 1usize
        w.ns = 0usize
        ret 1usize
    }
    tsluinverse(w, info, nd)
    var irmax = 4usize
    var ratmax = 0.0f64
    let nk = w.nk
    if nk > 1usize {
        var i = 0usize
        while i < nk {
            var phi = 0.0f64
            var se = 0.0f64
            var j = 0usize
            while j < nk {
                phi = phi + beta[j] * w.coef[j * CS + i + 4usize]
                var k = 0usize
                while k < nk {
                    se = se - w.coef[j * CS + i + 4usize] * w.coef[k * CS + i + 4usize] * info[j * W1 + k]
                    k += 1usize
                }
                j += 1usize
            }
            phi = math.abs[f64](phi)
            if se > 0.0f64 { se = math.sqrt[f64](se) } else { se = 0.0f64 }
            if se > phi * ratmax {
                ratmax = se / phi
                irmax = i
            }
            i += 1usize
        }
    }
    var i = nk
    while i < nd {
        let phi = math.abs[f64](beta[i])
        var se = -info[i * W1 + i]
        if se > 0.0f64 { se = math.sqrt[f64](se) } else { se = 0.0f64 }
        if se > phi * ratmax {
            ratmax = se / phi
            irmax = i
        }
        i += 1usize
    }
    ev3(w, 3.0f64, f64(irmax), ratmax)
    if irmax < nk {
        var j = irmax
        while j + 1usize < nk {
            w.kts[j] = w.kts[j + 1usize]
            j += 1usize
        }
        w.nk -= 1usize
    } else {
        let ir = irmax - nk
        var j = ir
        while j + 1usize < w.ns {
            w.spk[j] = w.spk[j + 1usize]
            j += 1usize
        }
        w.ns -= 1usize
    }
    ret nd - 1usize
}

// dims: 0 nx, 1 maxdim, 2 dimatt, 3 maxknots, 4 ktsatt, 5 nknots, 6 maxatoms, 7 spkatt, 8 natoms, 9 odd, 10 repeat, 11 error, 12 mind
fn tspsps2(w: *W, d: []i64, alpha: f64) {
    let nx = usize(d[0usize])
    let maxd = d[1usize]
    let atd = d[2usize]
    let maxk = d[3usize]
    let atk = d[4usize]
    var nk = usize(d[5usize])
    let maxs = d[6usize]
    let ats = d[7usize]
    var ns = usize(d[8usize])
    let mind = usize(d[12usize])
    var nd = nk + ns
    let id = nk
    var add: i64 = 0
    let cs = nx + 1usize
    let cum = w.cumul
    var i = 0usize
    while i < w.info.len {
        w.info[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < w.score.len {
        w.score[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < w.beta.len {
        w.beta[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < w.kts.len {
        w.kts[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < w.spk.len {
        w.spk[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < w.fl.len {
        w.fl[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < w.bb.len {
        w.bb[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < w.coef.len {
        w.coef[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < w.coef2.len {
        w.coef2[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < w.basis.len {
        w.basis[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < cum.len {
        cum[i] = 0.0f64
        i += 1usize
    }
    i = nx - 1usize
    while i > 0usize {
        cum[7usize * cs + i - 1usize] = cum[7usize * cs + i] + 1.0f64
        cum[8usize * cs + i - 1usize] = cum[8usize * cs + i] + w.xx[i]
        cum[9usize * cs + i - 1usize] = cum[9usize * cs + i] + w.xx[i] * w.xx[i]
        cum[10usize * cs + i - 1usize] = cum[10usize * cs + i] + w.xx[i] * w.xx[i] * w.xx[i]
        i -= 1usize
    }
    i = 0usize
    while i < NB {
        w.ad[i] = 2
        w.logs[i] = 0.0f64
        w.theta[i] = 0.0f64
        i += 1usize
    }
    var aicmn = 1.0e300f64
    w.nk = nk
    w.ns = ns
    if nk > 0usize { add = 7 }
    i = 0usize
    while i < ns {
        w.spk[i] = w.atoms[i]
        i += 1usize
    }
    i = 0usize
    while i < nk {
        w.kts[i] = w.knots[i]
        i += 1usize
    }
    var go = true
    while go {
        if add == 1 {
            nd = tsrem(w, nd)
            nk = w.nk
            ns = w.ns
        }
        if add == 0 {
            if nk == 1usize && id == 0usize && w.kts[0usize] < 0.000000001f64 {
                let r = tsadd(w, nd, mind, 2usize, 0usize)
                nd = usize(r)
                nk = w.nk
                ns = w.ns
            }
            var cank = 1usize
            var cans = 1usize
            if nk == 0usize { cans = 0usize }
            if i64(nk) == maxk && atk == 1 { cank = 0usize }
            if i64(ns) == maxs && ats == 1 { cans = 0usize }
            if i64(nk) + maxs == maxd && ats == 1 { cans = 0usize }
            if i64(ns) + maxk == maxd && atk == 1 { cank = 0usize }
            if w.nothere[0usize] >= 10usize { cans = 0usize }
            let r2 = tsadd(w, nd, mind, cank, cans)
            nk = w.nk
            ns = w.ns
            if r2 > 0 - 10 { nd = usize(r2) } else { add = 1 }
        }
        if add == 7 { add = 0 }
        tsbasis(w)
        var again = true
        var logl = 0.0f64
        while again {
            logl = tsnew(w)
            ns = w.ns
            if w.er < 0 {
                ns = ns - 1usize
                w.ns = ns
                nd -= 1usize
            }
            again = w.er < 0
        }
        ev3(w, 4.0f64, logl, f64(nd))
        if w.er == 0 {
            if w.ad[nd - 1usize] == 2 || logl > w.logs[nd - 1usize] {
                w.ad[nd - 1usize] = add
                if nd == 1usize { w.ad[nd - 1usize] = 0 }
                w.logs[nd - 1usize] = logl
            }
            let aic = f64(nd) * alpha - 2.0f64 * logl
            if aic < aicmn {
                aicmn = aic
                i = 0usize
                while i < nk {
                    w.knots[i] = w.kts[i]
                    i += 1usize
                }
                i = 0usize
                while i < ns {
                    w.atoms[i] = w.spk[i]
                    i += 1usize
                }
                i = 0usize
                while i < nk + 4usize {
                    w.theta[i] = 0.0f64
                    var j = 0usize
                    while j < nk {
                        w.theta[i] = w.theta[i] + w.beta[j] * w.coef[j * CS + i]
                        j += 1usize
                    }
                    i += 1usize
                }
                i = nk
                while i < nd {
                    w.theta[i + 4usize] = w.beta[i]
                    i += 1usize
                }
                d[5usize] = i64(nk)
                d[8usize] = i64(ns)
            }
            if add == 1 && (aic - aicmn >= alpha * f64(nd - 1usize) || nd == 1usize) { add = 3 }
            if add == 0 {
                if i64(nd) == maxd { add = 1 }
                if i64(nk) == maxk && i64(ns) == maxs && atk == 1 && ats == 1 { add = 1 }
            }
            if add == 0 && (atd == 0 || atk * ats == 0) {
                i = 2usize
                while i + 2usize < nd {
                    if w.logs[nd - 1usize] - w.logs[i - 1usize] < (f64(nd) - f64(i)) / 2.0f64 - 0.5f64 && w.ad[i - 1usize] != 2 {
                        add = 1
                        d[1usize] = i64(nd)
                    }
                    i += 1usize
                }
            }
        } else {
            add = 3
            d[11usize] = w.er
        }
        go = add == 0 || add == 1
    }
}

fn dcopy_range(src: []i64, dst: []i64, lo: usize, hi: usize) {
    var i = lo
    while i < hi {
        dst[i] = src[i]
        i += 1usize
    }
}

// the up and down controller; d as in tspsps2 (13 elements), the arrays in w are the in/out arguments of the C routine
fn tspsps(w: *W, d: []i64, cd: []i64, xkts: []f64, xspk: []usize, alpha: f64) {
    let nx = usize(d[0usize])
    let p = pil()
    var er2 = 0usize
    var yy = 0.0f64
    var zzz = 0.0f64
    d[11usize] = 0
    if d[10usize] < 1 { d[10usize] = 1 }
    var i = 0usize
    if d[9usize] == 0 {
        while i < nx {
            w.xx[i] = p * f64(i) / f64(nx - 1usize)
            i += 1usize
        }
    } else {
        while i < nx {
            w.xx[i] = p * f64(i) / (f64(nx) - 0.5f64)
            i += 1usize
        }
    }
    i = 0usize
    while i < nx {
        w.nothere[i] = 0usize
        i += 1usize
    }
    d[12usize] = 1
    i = 0usize
    while i < nx {
        w.zz[i] = math.log[f64](w.data[i])
        i += 1usize
    }
    dcopy_range(d, cd, 0usize, 13usize)
    var j: i64 = 0
    while j <= d[10usize] {
        i = 0usize
        while i < nx {
            xkts[i] = w.knots[i]
            xspk[i] = w.atoms[i]
            i += 1usize
        }
        dcopy_range(d, cd, 2usize, 13usize)
        var again = true
        while again {
            i = 0usize
            while i < nx {
                w.knots[i] = xkts[i]
                w.atoms[i] = xspk[i]
                i += 1usize
            }
            dcopy_range(cd, d, 0usize, 13usize)
            if j == 0 {
                if d[10usize] > 1 && d[7usize] == 0 {
                    d[6usize] = 0
                    d[7usize] = 1
                } else {
                    j = 1
                }
            }
            tspsps2(w, d, alpha)
            if d[11usize] != 0 {
                er2 += 1usize
                if er2 == 1usize {
                    i = 0usize
                    while i < nx {
                        zzz = zzz + w.data[i]
                        i += 1usize
                    }
                    i = 0usize
                    while i < nx {
                        w.data[i] = w.data[i] + 0.000001f64 * zzz / f64(nx)
                        i += 1usize
                    }
                    i = 0usize
                    while i < nx {
                        w.zz[i] = math.log[f64](w.data[i])
                        i += 1usize
                    }
                } else {
                    d[12usize] = d[12usize] + 1
                    cd[12usize] = cd[12usize] + 1
                }
            }
            if j > 0 && d[5usize] + d[8usize] > cd[1usize] - 5 && d[2usize] == 0 {
                cd[1usize] = d[5usize] + d[8usize] + 5
                if cd[1usize] > i64(NB) - 5 { cd[1usize] = i64(NB) - 5 }
            }
            if j == 0 && d[5usize] + d[8usize] > cd[1usize] - 1 && d[2usize] == 0 {
                cd[1usize] = d[5usize] + d[8usize] + 1
                if cd[1usize] > i64(NB) - 5 { cd[1usize] = i64(NB) - 1 }
            }
            again = d[11usize] != 0 && d[12usize] < 6
        }
        if j == 0 {
            d[7usize] = 0
            d[6usize] = 0 - 1
        }
        if d[10usize] == 1 { d[10usize] = 0 }
        if d[10usize] == 0 || d[11usize] != 0 { ret }
        dcopy_range(d, cd, 3usize, 13usize)
        if j > 0 {
            let at = usize(d[5usize] + d[8usize])
            if math.abs[f64](yy - w.logs[at]) < 1.0e-20f64 || w.ad[at] == 0 {
                if d[5usize] + d[8usize] != d[1usize] {
                    d[10usize] = 0 - j
                } else {
                    yy = w.logs[at]
                }
            } else {
                yy = w.logs[at]
            }
        }
        j += 1
    }
    if d[10usize] < 0 && d[5usize] + d[8usize] > 1 {
        d[1usize] = d[5usize] + d[8usize]
        d[2usize] = 0
        d[4usize] = 0
        d[7usize] = 0
        tspsps2(w, d, alpha)
    }
    d[10usize] = 0 - d[10usize]
}

// --- the R wrapper

type LSpec = struct {
    thetap: []f64, nknots: usize, knots: []f64, thetak: []f64, natoms: usize, atoms: []f64, mass: []f64,
    penalty: f64, minmass: f64, sample: usize, logl: f64, updown: i64, ev: []f64, nev: usize
}

error Invalid
error Numerical
error NoConvergence

// the periodogram lspec(data) computes: Mod(fft(data))^2 / (ny 2 pi) at the first floor((ny + 2) / 2) frequencies
fn periodogram(a: *mem.Arena, data: []const f64) -> ([]f64, err) {
    let ny = data.len
    let m = (ny + 2usize) / 2usize
    let (out, e) = mem.alloc[f64](a, m)
    if e != ok { ret (out, e) }
    let p = pil()
    var k = 0usize
    while k < m {
        var re = 0.0f64
        var im = 0.0f64
        var t = 0usize
        while t < ny {
            let ang = 2.0f64 * p * f64((k * t) % ny) / f64(ny)
            re = re + data[t] * math.cos[f64](ang)
            im = im - data[t] * math.sin[f64](ang)
            t += 1usize
        }
        out[k] = (re * re + im * im) / (f64(ny) * 2.0f64 * p)
        k += 1usize
    }
    ret (out, ok)
}

// lspec as R calls it. `period` is the vector handed to the C routine (length nx), ny the series length (2 nx or 2 nx + odd - 1...,
// as R computes), odd whether it is odd. penalty < 0 means log(nx - 1); maxknots, maxatoms < 0 and maxdim <= 0 mean missing;
// knots_in and atoms_in (frequencies) may be empty. minmass is on the user's scale.
fn lspec(a: *mem.Arena, period: []const f64, ny: usize, odd: bool, penalty0: f64, minmass0: f64, knots_in: []const f64, atoms_in: []const f64, maxknots0: i64, maxatoms0: i64, maxdim0: i64, updown: i64) -> (LSpec, err) {
    var fit: LSpec = zero
    let nx = period.len
    let p = pil()
    if nx < 10usize { ret (fit, Invalid) }
    var q = 0usize
    while q < nx {
        if period[q] <= 0.0f64 { ret (fit, Invalid) }
        q += 1usize
    }
    var penalty = penalty0
    if penalty < 0.0f64 { penalty = math.log[f64](f64(nx) - 1.0f64) }
    var dimatt: i64 = 0
    var ktsatt: i64 = 1
    var spkatt: i64 = 1
    var maxknots = maxknots0
    var maxatoms = maxatoms0
    if maxknots >= 0 {
        if maxknots < 1 { maxknots = 1 }
    } else {
        maxknots = 0 - 1
        ktsatt = 0
    }
    if maxatoms >= 0 {
        if maxatoms < 0 { maxatoms = 0 }
    } else {
        maxatoms = 0 - 1
        spkatt = 0
    }
    let minmass = minmass0 * f64(ny) / (2.0f64 * p)
    let nknots = knots_in.len
    let natoms = atoms_in.len
    let lg = 70usize
    let (knots, e1) = mem.alloc[f64](a, lg + nx + 16usize)
    let (atoms, e2) = mem.alloc[usize](a, lg + nx + 16usize)
    if e1 != ok || e2 != ok { ret (fit, mem.Full) }
    q = 0usize
    while q < lg + nx + 16usize {
        knots[q] = 0.0f64
        atoms[q] = 0usize
        q += 1usize
    }
    if nknots > 0usize {
        q = 1usize
        while q < nknots {
            if knots_in[q] - knots_in[q - 1usize] <= 0.0f64 { ret (fit, Invalid) }
            q += 1usize
        }
        if knots_in[0usize] < 0.0f64 || knots_in[nknots - 1usize] > p { ret (fit, Invalid) }
        q = 0usize
        while q < nknots {
            knots[q] = knots_in[q]
            q += 1usize
        }
        if ktsatt * maxknots < ktsatt * i64(nknots) { ret (fit, Invalid) }
    }
    if natoms > 0usize {
        q = 0usize
        while q < natoms {
            let r = nm.rint(atoms_in[q] * f64(ny) / (2.0f64 * p))
            if r < 1.0f64 { ret (fit, Invalid) }
            atoms[q] = usize(r)
            q += 1usize
        }
        if f64(atoms[natoms - 1usize]) > f64(ny) / 2.0f64 { ret (fit, Invalid) }
        if spkatt * maxatoms < spkatt * i64(natoms) { ret (fit, Invalid) }
    }
    var u1 = i64(nknots)
    if u1 < 1 { u1 = 1 }
    if maxknots > u1 { u1 = maxknots }
    var u2 = i64(natoms)
    if maxatoms > u2 { u2 = maxatoms }
    u1 = u1 + u2
    if u1 > i64(lg) - 5 { ret (fit, Invalid) }
    var maxdim = maxdim0
    if maxdim0 > 0 {
        dimatt = 1
        if u1 > maxdim0 { ret (fit, Invalid) }
        if maxdim0 > i64(lg) - 5 { ret (fit, Invalid) }
    } else {
        var md = 4.0f64 * math.pow[f64](f64(nx), 0.2f64)
        if md < 15.0f64 { md = 15.0f64 }
        if f64(u1) > md { md = f64(u1) }
        maxdim = i64(md)
    }
    var oddi: i64 = 0
    if odd { oddi = 1 }
    let (d, ed) = mem.alloc[i64](a, 13usize)
    let (cd, ecd) = mem.alloc[i64](a, 13usize)
    if ed != ok || ecd != ok { ret (fit, mem.Full) }
    d[0usize] = i64(nx)
    d[1usize] = maxdim
    d[2usize] = dimatt
    d[3usize] = maxknots
    d[4usize] = ktsatt
    d[5usize] = i64(nknots)
    d[6usize] = maxatoms
    d[7usize] = spkatt
    d[8usize] = i64(natoms)
    d[9usize] = oddi
    d[10usize] = updown
    d[11usize] = 0
    d[12usize] = 0
    // storage
    let (w, ew) = makew(a, nx, period, knots, atoms, minmass)
    if ew != ok { ret (fit, ew) }
    let (xkts, e3) = mem.alloc[f64](a, nx + 1usize)
    let (xspk, e4) = mem.alloc[usize](a, nx + 1usize)
    if e3 != ok || e4 != ok { ret (fit, mem.Full) }
    var ww = w
    tspsps(&ww, d, cd, xkts, xspk, penalty)
    if d[11usize] == 1 { ret (fit, Numerical) }
    if d[11usize] == 2 { ret (fit, NoConvergence) }
    let nkf = usize(d[5usize])
    let nsf = usize(d[8usize])
    let (thetap, e5) = mem.alloc[f64](a, 4usize)
    let (kn, e6) = mem.alloc[f64](a, nkf + 1usize)
    let (thk, e7) = mem.alloc[f64](a, nkf + 1usize)
    let (at, e8) = mem.alloc[f64](a, nsf + 1usize)
    let (ms, e9) = mem.alloc[f64](a, nsf + 1usize)
    if e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (fit, mem.Full) }
    q = 0usize
    while q < 4usize {
        thetap[q] = ww.theta[q]
        q += 1usize
    }
    q = 0usize
    while q < nkf {
        kn[q] = ww.knots[q]
        thk[q] = ww.theta[4usize + q]
        q += 1usize
    }
    q = 0usize
    while q < nsf {
        ms[q] = ww.theta[nkf + 4usize + q] * 2.0f64 * p / f64(ny)
        at[q] = f64(ww.atoms[q]) * 2.0f64 * p / f64(ny)
        q += 1usize
    }
    var lg2 = 0.0f64
    let li = nkf + nsf - 1usize
    lg2 = ww.logs[li]
    if math.abs[f64](lg2) < 1.0e-100f64 { lg2 = 0.0f64 }
    if ww.ad[li] == 2 { lg2 = 0.0f64 }
    fit.thetap = thetap
    fit.nknots = nkf
    fit.knots = kn
    fit.thetak = thk
    fit.natoms = nsf
    fit.atoms = at
    fit.mass = ms
    fit.penalty = penalty
    fit.minmass = minmass / (f64(ny) / (2.0f64 * p))
    fit.sample = ny
    fit.logl = lg2
    fit.updown = d[10usize]
    fit.ev = ww.ev
    fit.nev = ww.nev
    ret (fit, ok)
}

fn zf(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < n {
        s[i] = 0.0f64
        i += 1usize
    }
    ret (s, ok)
}

fn makew(a: *mem.Arena, nx: usize, period: []const f64, knots: []f64, atoms: []usize, minmass: f64) -> (W, err) {
    var w: W = zero
    w.nx = nx
    w.mass = minmass
    let (data, e1) = zf(a, nx + 2usize)
    let (xx, e2) = zf(a, nx + 2usize)
    let (zz, e3) = zf(a, nx + 2usize)
    let (nothere, e4) = mem.alloc[usize](a, nx + 2usize)
    let (ika, e5) = mem.alloc[usize](a, NB + 4usize)
    let (mm, e6) = zf(a, W1 * W1 + 8usize)
    let (aa, e7) = zf(a, 12usize)
    let (aax, e8) = zf(a, 12usize)
    let (ww, e9) = zf(a, NB + 4usize)
    let (vv1, e10) = zf(a, NB + 4usize)
    let (vv2, e11) = zf(a, NB + 4usize)
    let (betan, e12) = zf(a, NB + 12usize)
    let (cumul, e13) = zf(a, (11usize + NB * 4usize + 2usize) * (nx + 1usize))
    let (info, e14) = zf(a, W1 * W1 + 8usize)
    let (score, e15) = zf(a, NB + 4usize)
    let (beta, e16) = zf(a, NB + 4usize)
    let (coef, e17) = zf(a, (NB + 2usize) * CS)
    let (coef2, e18) = zf(a, 5usize * W1 * C2)
    let (basis, e19) = zf(a, (nx + 1usize) * W1)
    let (fl, e20) = mem.alloc[usize](a, 2usize * NB + 8usize)
    let (kts, e21) = zf(a, NB + 4usize)
    let (spk, e22) = mem.alloc[usize](a, NB + 4usize)
    let (bb, e23) = zf(a, nx + 2usize)
    let (logs, e24) = zf(a, NB + 8usize)
    let (theta, e25) = zf(a, NB + 16usize)
    let (ad, e26) = mem.alloc[i64](a, NB + 8usize)
    let (la, e27) = zf(a, 75usize * 75usize)
    let (lkp, e28) = mem.alloc[i64](a, 80usize)
    let (lw, e29) = zf(a, 80usize)
    let (uu, e30) = zf(a, 12usize)
    let (vv, e31) = zf(a, 12usize)
    let (evb, e32) = zf(a, 30000usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok || e20 != ok || e21 != ok || e22 != ok || e23 != ok || e24 != ok || e25 != ok || e26 != ok || e27 != ok || e28 != ok || e29 != ok || e30 != ok || e31 != ok || e32 != ok { ret (w, mem.Full) }
    var i = 0usize
    while i < nx {
        data[i] = period[i]
        nothere[i] = 0usize
        i += 1usize
    }
    nothere[nx] = 0usize
    nothere[nx + 1usize] = 0usize
    i = 0usize
    while i < NB + 4usize {
        ika[i] = 0usize
        spk[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < 2usize * NB + 8usize {
        fl[i] = 0usize
        i += 1usize
    }
    w.data = data
    w.xx = xx
    w.zz = zz
    w.nothere = nothere
    w.ika = ika
    w.mm = mm
    w.aa = aa
    w.aax = aax
    w.ww = ww
    w.vv1 = vv1
    w.vv2 = vv2
    w.betan = betan
    w.cumul = cumul
    w.info = info
    w.score = score
    w.beta = beta
    w.coef = coef
    w.coef2 = coef2
    w.basis = basis
    w.fl = fl
    w.kts = kts
    w.spk = spk
    w.bb = bb
    w.knots = knots
    w.atoms = atoms
    w.logs = logs
    w.theta = theta
    w.ad = ad
    w.la = la
    w.lkp = lkp
    w.lw = lw
    w.uu = uu
    w.vv = vv
    w.ev = evb
    ret (w, ok)
}

// --- evaluators

// the log density of the smooth part at freq (folded into [0, pi]) and its exponential
fn dlspec(m: *const LSpec, freq0: f64) -> f64 {
    let p = pil()
    var f = freq0 - math.floor[f64](freq0 / (2.0f64 * p)) * 2.0f64 * p
    if f > p { f = 2.0f64 * p - f }
    var y = m.thetap[0usize] + f * m.thetap[1usize]
    y = y + f * f * m.thetap[2usize] + f * f * f * m.thetap[3usize]
    var i = 0usize
    while i < m.nknots {
        let z = f - m.knots[i]
        if z > 0.0f64 { y = y + z * z * z * m.thetak[i] }
        i += 1usize
    }
    ret math.exp[f64](y)
}

// the atom mass at the Fourier frequency freq falls on, 0 when there is none, NaN where R gives NA
fn dlspec_mass(m: *const LSpec, freq0: f64) -> f64 {
    let p = pil()
    var f = freq0 - math.floor[f64](freq0 / (2.0f64 * p)) * 2.0f64 * p
    if f > p { f = 2.0f64 * p - f }
    let mf = nm.rint(f * f64(m.sample) / (2.0f64 * p))
    let len = nm.rint(f64(m.sample) / 2.0f64) + 2.0f64
    if mf < 1.0f64 || mf > len { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < m.natoms {
        if nm.rint(m.atoms[i] * f64(m.sample) / (2.0f64 * p)) == mf { ret m.mass[i] }
        i += 1usize
    }
    ret 0.0f64
}

// the cumulative table plspec builds: ss[0..mm + 3)
fn plspec_table(a: *mem.Arena, m: *const LSpec, mm: usize) -> ([]f64, err) {
    let p = pil()
    let (ss, e) = zf(a, mm + 3usize)
    if e != ok { ret (ss, e) }
    var cum = 0.0f64
    var i = 1usize
    while i <= mm {
        let u = (f64(i) - 0.5f64) * p / f64(mm)
        cum = cum + dlspec(m, u)
        ss[i + 1usize] = cum / f64(mm) * p
        i += 1usize
    }
    ss[mm + 2usize] = ss[mm + 1usize]
    ret (ss, ok)
}

fn plspec_default_mm(m: *const LSpec) -> usize {
    var v = 4096.0f64
    if f64(m.sample) > v { v = f64(m.sample) }
    ret usize(math.exp[f64](math.floor[f64](math.log[f64](v - 0.1f64) / math.log[f64](2.0f64)) * math.log[f64](2.0f64)) + 0.5f64)
}

// plspec at a frequency in [-pi, pi]
fn plspec(m: *const LSpec, ss: []const f64, mm: usize, freq: f64) -> f64 {
    let p = pil()
    var tt0 = 0.0f64
    var tt1 = 0.0f64
    var h = 0usize
    while h < 2usize {
        var g = p
        if h == 0usize { g = math.abs[f64](freq) }
        var t = g * f64(mm) / p
        let v = math.floor[f64](t)
        t = t - v
        let vi = usize(v)
        var r = (1.0f64 - t) * ss[vi + 1usize] + t * ss[vi + 2usize]
        var i = 0usize
        while i < m.natoms {
            if g >= m.atoms[i] { r = r + m.mass[i] }
            i += 1usize
        }
        if h == 0usize { tt0 = r } else { tt1 = r }
        h += 1usize
    }
    var s = tt0 + tt1
    if freq < 0.0f64 { s = 2.0f64 * tt1 - s }
    var i = 0usize
    while i < m.natoms {
        if freq == -m.atoms[i] { s = s + m.mass[i] }
        i += 1usize
    }
    ret s
}

// clspec for the integer lags lags[]; cov false divides by the lag 0 value
fn clspec(a: *mem.Arena, m: *const LSpec, lags: []const f64, cov: bool, mm0: usize, out: []f64) -> err {
    let p = pil()
    var mm = mm0
    var mx = 1.0f64
    var i = 0usize
    while i < lags.len {
        let l = math.abs[f64](lags[i]) + 1.0f64
        if l > mx { mx = l }
        i += 1usize
    }
    if mm == 0usize {
        var v = 1024.0f64
        if f64(m.sample) > v { v = f64(m.sample) }
        if mx > v { v = mx }
        let e2 = math.floor[f64](math.log[f64](v - 0.1f64) / math.log[f64](2.0f64))
        mm = usize(math.exp[f64](e2 * math.log[f64](2.0f64)) + 0.5f64) * 2usize
    }
    let (re, e1) = zf(a, 2usize * mm)
    let (im, e2) = zf(a, 2usize * mm)
    if e1 != ok || e2 != ok { ret mem.Full }
    i = 0usize
    while i <= mm {
        re[i] = dlspec(m, f64(i) * p / f64(mm))
        i += 1usize
    }
    i = 1usize
    while i < mm {
        re[mm + i] = re[mm - i]
        i += 1usize
    }
    let e3 = fft.fft(re, im)
    if e3 != ok { ret e3 }
    var base = 0.0f64
    i = 0usize
    while i < lags.len {
        var r = re[usize(math.abs[f64](lags[i]))] * p / f64(mm)
        var j = 0usize
        while j < m.natoms {
            r = r + 2.0f64 * math.cos[f64](lags[i] * m.atoms[j]) * m.mass[j]
            j += 1usize
        }
        out[i] = r
        i += 1usize
    }
    if !cov {
        base = out[0usize]
        i = 0usize
        while i < lags.len {
            out[i] = out[i] / base
            i += 1usize
        }
    }
    ret ok
}
