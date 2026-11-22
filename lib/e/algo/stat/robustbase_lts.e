// R robustbase ltsReg (alpha < 1, adjust = FALSE, n < 600): rfltsreg.f step for step (rfstatis scaling, the elemental subsets drawn with unif_rand or enumerated when n <= replow(p),
// two concentration steps per start, the ten best candidates refined up to 100 steps) and the R side of ltsReg.default (raw and reweighted fit, scales, finite sample factors, R squared).
// Matrices are column-major inside; the caller passes x row-major without the intercept column.

use e.math
use e.math.dist as dist
use e.algo.rand.r as rng
use e.algo.linalg.decomp as dc
use e.algo.stat.robustbase as rb
use e.mem

error LtsFail

fn gh(v: []const f64, i: i64) -> f64 { ret v[usize(i - 1i64)] }
fn sh(v: []f64, i: i64, x: f64) { v[usize(i - 1i64)] = x }

fn fabs(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

// rfmatnv with na = k, nb = 1 on the k by (k+1) column-major h (nvmax = k): Gauss-Jordan inversion with the extra column carrying the solution
fn lts_matnv(an: []f64, k: i64, jmiss: []i64) {
    let n = k
    let jdm = k
    let nma = n - 1i64
    let npnb = n + 1i64
    var jdelc = 1i64 - jdm
    var ldel = 0i64
    var jhfd = 1i64
    while jhfd <= n {
        var turn = 0.0f64
        jdelc = jdelc + jdm
        let jdla = jdelc + jhfd - 1i64
        let jdlb = jdelc + nma
        var jncb = jdla
        while jncb <= jdlb {
            if fabs(gh(an, jncb)) > fabs(turn) {
                turn = gh(an, jncb)
                ldel = jncb
            }
            jncb += 1i64
        }
        if turn == 0.0f64 { ret }
        var jpaal = ldel - jdelc + 1i64
        jmiss[usize(jhfd - 1i64)] = jpaal
        if jpaal > jhfd {
            jpaal = jpaal - jdm
            var jncd = jhfd - jdm
            var jnc = 1i64
            while jnc <= npnb {
                jpaal = jpaal + jdm
                jncd = jncd + jdm
                let sw = gh(an, jncd)
                sh(an, jncd, gh(an, jpaal))
                sh(an, jpaal, sw)
                jnc += 1i64
            }
        }
        turn = 1.0f64 / turn
        var jncd2 = jdelc + nma
        var jnc2 = jdelc
        while jnc2 <= jncd2 {
            sh(an, jnc2, (0.0f64 - gh(an, jnc2)) * turn)
            jnc2 += 1i64
        }
        sh(an, jdla, turn)
        jncb = jhfd - jdm
        jpaal = 1i64 - jdm
        var jnc3 = 1i64
        while jnc3 <= npnb {
            jpaal = jpaal + jdm
            jncb = jncb + jdm
            if jnc3 != jhfd {
                let jcl = jpaal + nma
                let sw = gh(an, jncb)
                var jncd3 = jdelc - 1i64
                var jncc = jpaal
                while jncc <= jcl {
                    jncd3 = jncd3 + 1i64
                    sh(an, jncc, gh(an, jncc) + sw * gh(an, jncd3))
                    jncc += 1i64
                }
                sh(an, jncb, sw * turn)
            }
            jnc3 += 1i64
        }
        jhfd += 1i64
    }
    var jb = 1i64
    while jb <= n {
        let jh = n + 1i64 - jb
        let ld = jmiss[usize(jh - 1i64)]
        if ld != jh {
            let jp = (ld - 1i64) * jdm + 1i64
            let jcl = jp + nma
            let jd = (jh - 1i64) * jdm + 1i64 - jp
            var jncc = jp
            while jncc <= jcl {
                let jncd = jncc + jd
                let sw = gh(an, jncc)
                sh(an, jncc, gh(an, jncd))
                sh(an, jncd, sw)
                jncc += 1i64
            }
        }
        jb += 1i64
    }
}

// rfequat with na = k, nb = 1 on the k by (k+1) column-major am; returns nerr (0, or -1 for a pivot of at most 1e-8)
fn lts_equat(am: []f64, k: i64) -> i64 {
    let jdm = k
    let n = k
    let jmat = n + 1i64
    let nznde = n - 1i64
    var lclpl = 0i64 - jdm
    var ldel = 0i64
    var jhfd = 1i64
    while jhfd <= n {
        var turn = 0.0f64
        lclpl = lclpl + jdm + 1i64
        let jdel = lclpl + n - jhfd
        var jncb = lclpl
        while jncb <= jdel {
            if fabs(gh(am, jncb)) > fabs(turn) {
                turn = gh(am, jncb)
                ldel = jncb
            }
            jncb += 1i64
        }
        if fabs(turn) <= 1.0e-8f64 { ret 0i64 - 1i64 }
        if ldel != lclpl {
            ldel = ldel - jdm
            jncb = lclpl - jdm
            var jncc = jhfd
            while jncc <= jmat {
                ldel = ldel + jdm
                jncb = jncb + jdm
                let sw = gh(am, jncb)
                sh(am, jncb, gh(am, ldel))
                sh(am, ldel, sw)
                jncc += 1i64
            }
        }
        if jhfd != n {
            turn = 1.0f64 / turn
            jncb = lclpl + 1i64
            var jncc = jncb
            while jncc <= jdel {
                sh(am, jncc, gh(am, jncc) * turn)
                jncc += 1i64
            }
            var jncd = lclpl
            let jrow = jhfd + 1i64
            jncb = jrow
            while jncb <= n {
                jncd = jncd + 1i64
                var jnce = lclpl
                var jncf = jncd
                jncc = jrow
                while jncc <= jmat {
                    jnce = jnce + jdm
                    jncf = jncf + jdm
                    sh(am, jncf, gh(am, jncf) - gh(am, jnce) * gh(am, jncd))
                    jncc += 1i64
                }
                jncb += 1i64
            }
        }
        jhfd += 1i64
    }
    let neqa = n + 1i64
    var jbegx = nznde * jdm + 1i64
    var jnc = neqa
    while jnc <= jmat {
        jbegx = jbegx + jdm
        var jendx = jbegx + n
        var jbegc = n * jdm + 1i64
        var jendc = jbegc + nznde
        var jncb = 1i64
        while jncb <= nznde {
            jendx = jendx - 1i64
            jbegc = jbegc - jdm
            jendc = jendc - jdm - 1i64
            sh(am, jendx, gh(am, jendx) / gh(am, jendc + 1i64))
            let sw = gh(am, jendx)
            var jncd = jbegx - 1i64
            var jncc = jbegc
            while jncc <= jendc {
                jncd = jncd + 1i64
                sh(am, jncd, gh(am, jncd) - gh(am, jncc) * sw)
                jncc += 1i64
            }
            jncb += 1i64
        }
        sh(am, jbegx, gh(am, jbegx) / gh(am, 1i64))
        jnc += 1i64
    }
    var jn = 0i64 - jdm
    jbegx = nznde * jdm + 1i64
    var jendx2 = jbegx + nznde
    var jb = neqa
    while jb <= jmat {
        jbegx = jbegx + jdm
        jendx2 = jendx2 + jdm
        jn = jn + jdm
        var jncd = jn
        var jncc = jbegx
        while jncc <= jendx2 {
            jncd = jncd + 1i64
            sh(am, jncd, gh(am, jncc))
            jncc += 1i64
        }
        jb += 1i64
    }
    ret 0i64
}

// rfamdan: the median of aa[0..n] (partially sorted in place)
fn lts_amdan(aa: []f64, n: usize, index: []usize) -> f64 {
    let jndl = n / 2usize
    if n % 2usize == 0usize {
        let a1 = rb.mcd_findq(aa, n, jndl, index)
        let a2 = rb.mcd_findq(aa, n, jndl + 1usize, index)
        ret (a1 + a2) / 2.0f64
    }
    ret rb.mcd_findq(aa, n, jndl + 1usize, index)
}

type LtsWork = struct {
    n: usize,
    p: usize,
    nhalf: usize,
    dat: []f64,
    datt: []f64,
    a: []f64,
    h: []f64,
    jmiss: []i64,
    residu: []f64,
    index2: []usize,
    temp: []usize,
    object: f64,
    objfct: f64,
    inbest: []usize
}

// residuals y - X a on the scaled data, then their absolute values
fn lts_resid(m: *LtsWork) {
    var jnc = 0usize
    while jnc < m.n {
        var s = 0.0f64
        var j = 0usize
        while j < m.p {
            s = s + m.a[j] * m.dat[j * m.n + jnc]
            j += 1usize
        }
        m.residu[jnc] = m.dat[m.p * m.n + jnc] - s
        jnc += 1usize
    }
}

fn lts_abs(m: *LtsWork) {
    var jnc = 0usize
    while jnc < m.n {
        m.residu[jnc] = fabs(m.residu[jnc])
        jnc += 1usize
    }
}

// the LS fit on the nhalf rows listed in temp (rflsreg with unit weights); the result replaces a
fn lts_lsreg(m: *LtsWork) {
    let k = m.p
    let kp = k + 1usize
    var i = 0usize
    while i < k * kp {
        m.h[i] = 0.0f64
        i += 1usize
    }
    var jnc = 0usize
    while jnc < m.nhalf {
        let row = m.temp[jnc]
        var ka = 0usize
        while ka < k {
            let dfka = m.dat[ka * m.n + row]
            let dyj = m.dat[k * m.n + row]
            m.h[k * k + ka] = m.h[k * k + ka] + 1.0f64 * dfka * dyj
            var l = 0usize
            while l <= ka {
                m.h[l * k + ka] = m.h[l * k + ka] + 1.0f64 * dfka * m.dat[l * m.n + row]
                l += 1usize
            }
            ka += 1usize
        }
        jnc += 1usize
    }
    var j = 0usize
    while j < k {
        var c = 0usize
        while c <= j {
            m.h[j * k + c] = m.h[c * k + j]
            c += 1usize
        }
        j += 1usize
    }
    lts_matnv(m.h, i64(k), m.jmiss)
    j = 0usize
    while j < k {
        m.a[j] = m.h[k * k + j]
        j += 1usize
    }
}

// the concentration steps of one start; returns the criterion of the last step
fn lts_steps(m: *LtsWork, kstep: usize, fin: bool, it: usize) -> f64 {
    lts_resid(m)
    lts_abs(m)
    let _ = rb.mcd_findq(m.residu, m.n, m.nhalf, m.index2)
    var fckw = 0.0f64
    var fckwi = 0.0f64
    var fckw1 = 0.0f64
    var step = 1usize
    while step <= kstep {
        var j = 0usize
        while j < m.nhalf {
            m.temp[j] = m.index2[j]
            j += 1usize
        }
        rb.mcd_sort_usize(m.temp, m.nhalf)
        lts_lsreg(m)
        lts_resid(m)
        lts_abs(m)
        let _q = rb.mcd_findq(m.residu, m.n, m.nhalf, m.index2)
        fckw = 0.0f64
        j = 0usize
        while j < m.nhalf {
            fckw = fckw + m.residu[j] * m.residu[j]
            j += 1usize
        }
        if step >= 2usize && fckw == fckw1 { break }
        fckw1 = fckwi
        fckwi = fckw
        if fin && ((it == 1usize && step == 1usize) || fckw < m.object) {
            m.object = fckw
            m.objfct = fckw
            j = 0usize
            while j < m.nhalf {
                m.inbest[j] = m.index2[j] + 1usize
                j += 1usize
            }
        }
        step += 1usize
    }
    ret fckw
}

fn lts_replow(k: usize) -> usize {
    if k == 1usize { ret 500usize }
    if k == 2usize { ret 50usize }
    if k == 3usize { ret 22usize }
    if k == 4usize { ret 17usize }
    if k == 5usize { ret 15usize }
    if k == 6usize { ret 14usize }
    ret 0usize
}

fn lts_ncomb(k: usize, n: usize) -> usize {
    var comb = 1.0f64
    var j = 1usize
    while j <= k {
        let fact = f64(n - j + 1usize) / f64(k - j + 1usize)
        comb = comb * fact
        j += 1usize
    }
    ret usize(comb + 0.5f64)
}

// .fastlts: x is n by p column-major (the intercept column last), y has n entries, h = nhalff. inbest (h entries, 1-based) and the criterion (scaled units) come back.
fn fastlts(a: *mem.Arena, g: *rng.Rng, x: []const f64, y: []const f64, n: usize, p: usize, h: usize, krep: usize, intercept: bool, inbest: []usize) -> (f64, err) {
    if n >= 600usize { ret (0.0f64, LtsFail) }
    let nvad = p + 1usize
    let (dat, e0) = mem.alloc[f64](a, n * nvad)
    let (datt, e1) = mem.alloc[f64](a, n * nvad)
    let (av, e2) = mem.alloc[f64](a, p)
    let (hm, e3) = mem.alloc[f64](a, p * nvad)
    let (jm, e4) = mem.alloc[i64](a, nvad)
    let (residu, e5) = mem.alloc[f64](a, n)
    let (index2, e6) = mem.alloc[usize](a, n)
    let (temp, e7) = mem.alloc[usize](a, n)
    let (aw2, e8) = mem.alloc[f64](a, n)
    let (xmed, e9) = mem.alloc[f64](a, nvad)
    let (xmad, e10) = mem.alloc[f64](a, nvad)
    let (index1, e11) = mem.alloc[i64](a, p + 2usize)
    let (cm, e12) = mem.alloc[f64](a, p * nvad)
    let (mstock, e13) = mem.alloc[f64](a, 10usize * p)
    let (mval, e14) = mem.alloc[f64](a, 10usize)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (0.0f64, e0) }
    if e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret (0.0f64, e8) }
    var i = 0usize
    while i < n * p {
        dat[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        dat[p * n + i] = y[i]
        i += 1usize
    }
    // rfstatis
    let madeps = 1.0e-6f64
    let c1 = f64(f32(1.4826f64))
    let c2 = f64(f32(1.2533f64))
    var j = 0usize
    if !intercept {
        while j < nvad {
            xmed[j] = 0.0f64
            i = 0usize
            while i < n {
                aw2[i] = fabs(dat[j * n + i])
                i += 1usize
            }
            xmad[j] = lts_amdan(aw2, n, index2) * c1
            if fabs(xmad[j]) <= madeps {
                xmad[j] = 0.0f64
                i = 0usize
                while i < n {
                    xmad[j] = xmad[j] + aw2[i]
                    i += 1usize
                }
                xmad[j] = (xmad[j] / f64(n)) * c2
                if fabs(xmad[j]) <= madeps { ret (0.0f64 - 1.0f64, LtsFail) }
            }
            i = 0usize
            while i < n {
                dat[j * n + i] = dat[j * n + i] / xmad[j]
                i += 1usize
            }
            j += 1usize
        }
    } else {
        xmed[p - 1usize] = 0.0f64
        xmad[p - 1usize] = 1.0f64
        while j < nvad {
            if j != p - 1usize {
                i = 0usize
                while i < n {
                    aw2[i] = dat[j * n + i]
                    i += 1usize
                }
                xmed[j] = lts_amdan(aw2, n, index2)
                i = 0usize
                while i < n {
                    aw2[i] = fabs(aw2[i] - xmed[j])
                    i += 1usize
                }
                xmad[j] = lts_amdan(aw2, n, index2) * c1
                if fabs(xmad[j]) <= madeps {
                    xmad[j] = 0.0f64
                    i = 0usize
                    while i < n {
                        xmad[j] = xmad[j] + aw2[i]
                        i += 1usize
                    }
                    xmad[j] = (xmad[j] / f64(n)) * c2
                    if fabs(xmad[j]) <= madeps { ret (0.0f64 - 1.0f64, LtsFail) }
                }
                i = 0usize
                while i < n {
                    dat[j * n + i] = (dat[j * n + i] - xmed[j]) / xmad[j]
                    i += 1usize
                }
            }
            j += 1usize
        }
    }
    var m: LtsWork = zero
    m.n = n
    m.p = p
    m.nhalf = h
    m.dat = dat
    m.datt = datt
    m.a = av
    m.h = hm
    m.jmiss = jm
    m.residu = residu
    m.index2 = index2
    m.temp = temp
    m.object = 1.0e25f64
    m.objfct = 0.0f64 - 1.0f64
    m.inbest = inbest
    // first stage: the random or exhaustive starts
    let exh = krep == 0usize || n <= lts_replow(p)
    var nrep = krep
    if exh { nrep = lts_ncomb(p, n) }
    var k = 0usize
    while k < 10usize {
        mval[k] = 1.0e25f64
        var jj = 0usize
        while jj < p {
            mstock[k * p + jj] = 1000000.0f64
            jj += 1usize
        }
        k += 1usize
    }
    let nsel = p
    i = 1usize
    while i < nsel {
        index1[i] = i64(i)
        i += 1usize
    }
    index1[nsel] = i64(nsel) - 1i64
    var it = 1usize
    while it <= nrep {
        var skip = false
        var again = true
        while again {
            again = false
            if exh {
                var kk = nsel
                index1[kk] = index1[kk] + 1i64
                while !(kk == 1usize || index1[kk] <= i64(n) - i64(nsel - kk)) {
                    kk -= 1usize
                    index1[kk] = index1[kk] + 1i64
                    var ii = kk + 1usize
                    while ii <= nsel {
                        index1[ii] = index1[ii - 1usize] + 1i64
                        ii += 1usize
                    }
                }
            } else {
                var di = 1usize
                while di <= nsel {
                    var rep = true
                    var num = 0i64
                    while rep {
                        num = i64(rng.unif(g) * f64(n)) + 1i64
                        rep = false
                        var dj = 1usize
                        while dj < di {
                            if index1[dj] == num { rep = true }
                            dj += 1usize
                        }
                    }
                    index1[di] = num
                    di += 1usize
                }
            }
            var jr = 0usize
            while jr < p {
                var mc = 0usize
                while mc < nvad {
                    cm[mc * p + jr] = dat[mc * n + usize(index1[jr + 1usize] - 1i64)]
                    mc += 1usize
                }
                jr += 1usize
            }
            if p > 1usize {
                if lts_equat(cm, i64(p)) < 0i64 {
                    if !exh && it > 2usize {
                        again = true
                    } else {
                        skip = true
                    }
                }
            } else {
                if cm[0usize] != 0.0f64 { cm[0usize] = cm[1usize] / cm[0usize] }
            }
        }
        if !skip {
            var jn = 0usize
            while jn < p {
                av[jn] = cm[jn]
                jn += 1usize
            }
            let fckw = lts_steps(&m, 2usize, false, it)
            // keep the ten best
            var jj = 0usize
            var done = false
            while jj < 10usize && !done {
                if fckw <= mval[jj] {
                    var insert = false
                    if fckw != mval[jj] {
                        insert = true
                    } else {
                        var kk = jj
                        while kk < 10usize && !insert {
                            if fckw == mval[kk] {
                                var jx = 0usize
                                while jx < p {
                                    if av[jx] != mstock[kk * p + jx] { insert = true }
                                    jx += 1usize
                                }
                            }
                            kk += 1usize
                        }
                    }
                    if insert {
                        var kk = 9usize
                        while kk > jj {
                            var jx = 0usize
                            while jx < p {
                                mstock[kk * p + jx] = mstock[(kk - 1usize) * p + jx]
                                jx += 1usize
                            }
                            mval[kk] = mval[kk - 1usize]
                            kk -= 1usize
                        }
                        var jx = 0usize
                        while jx < p {
                            mstock[jj * p + jx] = av[jx]
                            jx += 1usize
                        }
                        mval[jj] = fckw
                    }
                    done = true
                }
                jj += 1usize
            }
        }
        it += 1usize
    }
    // final stage: the ten best candidates, up to 100 steps each
    var kstep = 100usize
    if n * p > 100000usize { kstep = 1usize }
    it = 1usize
    while it <= 10usize {
        if mstock[(it - 1usize) * p] == 1000000.0f64 { break }
        var jx = 0usize
        while jx < p {
            av[jx] = mstock[(it - 1usize) * p + jx]
            jx += 1usize
        }
        let _f = lts_steps(&m, kstep, true, it)
        it += 1usize
    }
    ret (m.objfct * 1.0f64, ok)
}

// ---- the R side ----

// least squares by qr on the rows with positive weight (lm.wfit); x is n by p column-major; coef gets p values, resid the unweighted residuals of all rows
fn wls_fit(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, n: usize, p: usize, coef: []f64, resid: []f64) -> err {
    var m = 0usize
    var i = 0usize
    while i < n {
        if w[i] > 0.0f64 { m += 1usize }
        i += 1usize
    }
    let (xs, e0) = mem.alloc[f64](a, m * p + 1usize)
    let (ys, e1) = mem.alloc[f64](a, m + 1usize)
    if e0 != ok { ret e0 }
    if e1 != ok { ret e1 }
    var r = 0usize
    i = 0usize
    while i < n {
        if w[i] > 0.0f64 {
            let sw = math.sqrt[f64](w[i])
            var j = 0usize
            while j < p {
                xs[j * m + r] = x[j * n + i] * sw
                j += 1usize
            }
            ys[r] = y[i] * sw
            r += 1usize
        }
        i += 1usize
    }
    let (q, qe) = rb.dqrdc2_blue(a, xs[0usize..m * p], m, p, 1.0e-7f64)
    if qe != ok { ret qe }
    dc.qr_qty(&q, ys[0usize..m])
    var jj = p
    while jj > 0usize {
        jj -= 1usize
        var s = ys[jj]
        var k = jj + 1usize
        while k < p {
            s = s - q.qr[k * m + jj] * coef[k]
            k += 1usize
        }
        coef[jj] = s / q.qr[jj * m + jj]
    }
    i = 0usize
    while i < n {
        var f = 0.0f64
        var j = 0usize
        while j < p {
            f = f + x[j * n + i] * coef[j]
            j += 1usize
        }
        resid[i] = y[i] - f
        i += 1usize
    }
    ret ok
}

// LTScnp2 (rew = false) and LTScnp2.rew (rew = true)
fn lts_cnp2(pp: usize, intercept: bool, n: f64, alpha: f64, rew: bool) -> f64 {
    var p = f64(pp)
    if intercept { p = p - 1.0f64 }
    var f5 = 0.0f64
    var f875 = 0.0f64
    if p == 0.0f64 {
        if !rew {
            f5 = 1.0f64 - math.exp[f64](0.262024211897096f64) / math.pow[f64](n, 0.604756680630497f64)
            f875 = 1.0f64 - math.exp[f64](0.0f64 - 0.351584646688712f64) / math.pow[f64](n, 1.01646567502486f64)
        } else {
            f5 = 1.0f64 - math.exp[f64](1.11098143415027f64) / math.pow[f64](n, 1.5182890270453f64)
            f875 = 1.0f64 - math.exp[f64](0.0f64 - 0.66046776772861f64) / math.pow[f64](n, 0.88939595831888f64)
        }
        var fa = f5 + (f875 - f5) / 0.375f64 * (alpha - 0.5f64)
        if alpha > 0.875f64 { fa = f875 + (1.0f64 - f875) / 0.125f64 * (alpha - 0.875f64) }
        ret 1.0f64 / math.sqrt[f64](fa)
    }
    if p == 1.0f64 {
        if !rew {
            if intercept {
                f5 = 1.0f64 - math.exp[f64](0.630869217886906f64) / math.pow[f64](n, 0.650789250442946f64)
                f875 = 1.0f64 - math.exp[f64](0.565065391014791f64) / math.pow[f64](n, 1.03044199012509f64)
            } else {
                f5 = 1.0f64 - math.exp[f64](0.0f64 - 0.0181777452315321f64) / math.pow[f64](n, 0.697629772271099f64)
                f875 = 1.0f64 - math.exp[f64](0.0f64 - 0.310122738776431f64) / math.pow[f64](n, 1.06241615923172f64)
            }
        } else {
            if intercept {
                f5 = 1.0f64 - math.exp[f64](1.58609654199605f64) / math.pow[f64](n, 1.46340162526468f64)
                f875 = 1.0f64 - math.exp[f64](0.391653958727332f64) / math.pow[f64](n, 1.03167487483316f64)
            } else {
                f5 = 1.0f64 - math.exp[f64](0.6329852387657f64) / math.pow[f64](n, 1.40361879788014f64)
                f875 = 1.0f64 - math.exp[f64](0.0f64 - 0.642240988645469f64) / math.pow[f64](n, 0.926325452943084f64)
            }
        }
    } else {
        var a8a = 0.0f64
        var a8b = 0.0f64
        var b8a = 0.0f64
        var b8b = 0.0f64
        var a5a = 0.0f64
        var a5b = 0.0f64
        var b5a = 0.0f64
        var b5b = 0.0f64
        if !rew {
            if intercept {
                a8a = 0.0f64 - 0.458580153984614f64
                a8b = 0.0f64 - 0.267178168108996f64
                b8a = 1.12236071104403f64
                b8b = 1.1022478781154f64
                a5a = 0.0f64 - 0.746945886714663f64
                a5b = 0.0f64 - 0.535478048924724f64
                b5a = 0.56264937192689f64
                b5b = 0.543323462033445f64
            } else {
                a8a = 0.0f64 - 0.251778730491252f64
                a8b = 0.0f64 - 0.146660023184295f64
                b8a = 0.883966931611758f64
                b8b = 0.86292940340761f64
                a5a = 0.0f64 - 0.487338281979106f64
                a5b = 0.0f64 - 0.340762058011f64
                b5a = 0.405511279418594f64
                b5b = 0.37972360544988f64
            }
        } else {
            if intercept {
                a8a = 0.0f64 - 0.474174840843602f64
                a8b = 0.0f64 - 0.276640353112907f64
                b8a = 1.39681715704956f64
                b8b = 1.42543242287677f64
                a5a = 0.0f64 - 0.773365715932083f64
                a5b = 0.0f64 - 0.337571678986723f64
                b5a = 2.02013996406346f64
                b5b = 2.02037467454833f64
            } else {
                a8a = 0.0f64 - 0.267522855927958f64
                a8b = 0.0f64 - 0.161200683014406f64
                b8a = 1.17559984533974f64
                b8b = 1.21675019853961f64
                a5a = 0.0f64 - 0.417574780492848f64
                a5b = 0.0f64 - 0.175753709374146f64
                b5a = 1.83958876341367f64
                b5b = 1.8313809497999f64
            }
        }
        let (c50, c51) = lts_solve2(a5a, a5b, b5a, b5b, p)
        let (c80, c81) = lts_solve2(a8a, a8b, b8a, b8b, p)
        f5 = 1.0f64 - math.exp[f64](c50) / math.pow[f64](n, c51)
        f875 = 1.0f64 - math.exp[f64](c80) / math.pow[f64](n, c81)
    }
    var fa = f5 + (f875 - f5) / 0.375f64 * (alpha - 0.5f64)
    if alpha > 0.875f64 { fa = f875 + (1.0f64 - f875) / 0.125f64 * (alpha - 0.875f64) }
    ret 1.0f64 / fa
}

// solve(cbind(1, -log(q p^2)), log(-alfa / p^beta)) for q = 3, 5
fn lts_solve2(al0: f64, al1: f64, be0: f64, be1: f64, p: f64) -> (f64, f64) {
    let y1 = math.log[f64](0.0f64 - al0 / math.pow[f64](p, be0))
    let y2 = math.log[f64](0.0f64 - al1 / math.pow[f64](p, be1))
    let a12 = 0.0f64 - math.log[f64](3.0f64 * p * p)
    let a22 = 0.0f64 - math.log[f64](5.0f64 * p * p)
    let u22 = a22 - a12
    let c2 = (y2 - y1) / u22
    let c1 = y1 - a12 * c2
    ret (c1, c2)
}

fn mean_r(v: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += v[i]
        i += 1usize
    }
    s = s / f64(n)
    var t = 0.0f64
    i = 0usize
    while i < n {
        t += v[i] - s
        i += 1usize
    }
    ret s + t / f64(n)
}

// the sum of the h smallest values of v (v is copied and sorted)
fn smallest_sum(a: *mem.Arena, v: []const f64, n: usize, h: usize, out: []f64) -> err {
    let (s, e) = rb.sort_copy(a, v[0usize..n])
    if e != ok { ret e }
    var i = 0usize
    while i < h {
        out[i] = s[i]
        i += 1usize
    }
    ret ok
}

// rfmcduni: the smallest-variance h consecutive sorted values; returns sqrt(sqmin / h)
fn lts_mcduni_std(w: []const f64, ncas: usize, jqu: usize) -> f64 {
    var sq = 0.0f64
    var sqmin = 0.0f64
    var aw_prev2 = 0.0f64
    var jint = 1usize
    while jint <= ncas - jqu + 1usize {
        var aw = 0.0f64
        var j = 1usize
        while j <= jqu {
            aw = aw + w[j + jint - 2usize]
            if jint == 1usize { sq = sq + w[j - 1usize] * w[j - 1usize] }
            j += 1usize
        }
        let aw2 = aw * aw / f64(jqu)
        if jint == 1usize {
            sq = sq - aw2
            sqmin = sq
        } else {
            sq = sq - w[jint - 2usize] * w[jint - 2usize] + w[jint + jqu - 2usize] * w[jint + jqu - 2usize] - aw2 + aw_prev2
            if sq < sqmin { sqmin = sq }
        }
        aw_prev2 = aw2
        jint += 1usize
    }
    ret math.sqrt[f64](sqmin / f64(jqu))
}

// ltsReg(x, y, intercept, alpha, nsamp) with the default 01.original weights, use.correction = TRUE, adjust = FALSE, mcd = FALSE. x is n by pp row-major WITHOUT the intercept column.
// out = raw.coefficients (p, intercept first), coefficients (p), raw.scale, scale, crit, rsquared, quan, raw.weights (n), lts.wt (n), residuals (n), best (quan, sorted, 1-based), where p = pp + intercept
fn lts_reg(a: *mem.Arena, g: *rng.Rng, x: []const f64, y: []const f64, n: usize, pp: usize, intercept: bool, alpha: f64, nsamp: usize, out: []f64) -> err {
    var p = pp
    if intercept { p = pp + 1usize }
    let (xc, e0) = mem.alloc[f64](a, n * p)
    if e0 != ok { ret e0 }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < pp {
            xc[j * n + i] = x[i * pp + j]
            j += 1usize
        }
        if intercept { xc[pp * n + i] = 1.0f64 }
        i += 1usize
    }
    let n2 = (n + p + 1usize) / 2usize
    let h = usize(math.floor[f64](2.0f64 * f64(n2) - f64(n) + 2.0f64 * f64(n - n2) * alpha))
    let (inbest, e1) = mem.alloc[usize](a, h + 1usize)
    if e1 != ok { ret e1 }
    let (crit, fe) = fastlts(a, g, xc, y, n, p, h, nsamp, intercept, inbest)
    if fe != ok { ret fe }
    if crit < 0.0f64 { ret LtsFail }
    let (w, e2) = mem.alloc[f64](a, n)
    let (cf, e3) = mem.alloc[f64](a, p)
    let (resid, e4) = mem.alloc[f64](a, n)
    let (sq, e5) = mem.alloc[f64](a, n)
    let (cf1, e6) = mem.alloc[f64](a, p)
    let (resid1, e7) = mem.alloc[f64](a, n)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret e2 }
    i = 0usize
    while i < n {
        w[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < h {
        w[inbest[i] - 1usize] = 1.0f64
        i += 1usize
    }
    let we = wls_fit(a, xc, y, w, n, p, cf, resid)
    if we != ok { ret we }
    // best, sorted
    rb.mcd_sort_usize(inbest, h)
    // raw scale
    i = 0usize
    while i < n {
        sq[i] = resid[i] * resid[i]
        i += 1usize
    }
    let (ss, e8) = mem.alloc[f64](a, h + 1usize)
    if e8 != ok { ret e8 }
    let se = smallest_sum(a, sq, n, h, ss)
    if se != ok { ret se }
    let correct = lts_cnp2(p, intercept, f64(n), alpha, false)
    let s0raw = math.sqrt[f64](mean_r(ss, h))
    let qnq = dist.qnorm((f64(h) + f64(n)) / (2.0f64 * f64(n)), 0.0f64, 1.0f64, true, false)
    let s0 = s0raw / math.sqrt[f64](1.0f64 - (2.0f64 * f64(n)) / (f64(h) / qnq) * dist.dnorm(qnq, 0.0f64, 1.0f64, false)) * correct
    let cw = dist.qnorm(0.9875f64, 0.0f64, 1.0f64, true, false)
    var scale = 0.0f64
    var finalw = 0.0f64
    // raw.weights, lts.wt, residuals
    let rwo = 2usize * p + 5usize
    let lwo = rwo + n
    let reo = lwo + n
    let beo = reo + n
    var cfo = 0usize
    while cfo < p {
        out[cfo] = cf[cfo]
        out[p + cfo] = cf[cfo]
        cfo += 1usize
    }
    var rsq = 0.0f64
    if fabs(s0) < 1.0e-7f64 {
        i = 0usize
        while i < n {
            var wv = 0.0f64
            if fabs(resid[i]) <= 1.0e-7f64 { wv = 1.0f64 }
            out[rwo + i] = wv
            out[lwo + i] = wv
            out[reo + i] = resid[i]
            i += 1usize
        }
        out[2usize * p] = 0.0f64
        out[2usize * p + 1usize] = 0.0f64
        scale = 0.0f64
    } else {
        var sumw = 0.0f64
        i = 0usize
        while i < n {
            var wv = 0.0f64
            if fabs(resid[i] / s0) <= cw { wv = 1.0f64 }
            out[rwo + i] = wv
            w[i] = wv
            sumw += wv
            i += 1usize
        }
        let we2 = wls_fit(a, xc, y, w, n, p, cf1, resid1)
        if we2 != ok { ret we2 }
        var sr = 0.0f64
        i = 0usize
        while i < n {
            sr = sr + w[i] * resid1[i] * resid1[i]
            i += 1usize
        }
        scale = math.sqrt[f64](sr / (sumw - 1.0f64))
        if sumw != f64(n) {
            let qnw = dist.qnorm((sumw + f64(n)) / (2.0f64 * f64(n)), 0.0f64, 1.0f64, true, false)
            let cdelta = 1.0f64 / math.sqrt[f64](1.0f64 - (2.0f64 * f64(n)) / (sumw / qnw) * dist.dnorm(qnw, 0.0f64, 1.0f64, false))
            let correctrew = lts_cnp2(p, intercept, f64(n), alpha, true)
            scale = scale * cdelta * correctrew
        }
        cfo = 0usize
        while cfo < p {
            out[p + cfo] = cf1[cfo]
            cfo += 1usize
        }
        i = 0usize
        while i < n {
            var wv = 0.0f64
            if fabs(resid1[i] / scale) <= cw { wv = 1.0f64 }
            out[lwo + i] = wv
            out[reo + i] = resid1[i]
            i += 1usize
        }
        out[2usize * p] = s0
        out[2usize * p + 1usize] = scale
        // R squared
        i = 0usize
        while i < n {
            sq[i] = resid1[i] * resid1[i]
            i += 1usize
        }
        var iR2 = 0.0f64
        if intercept {
            let (ys, e9) = rb.sort_copy(a, y[0usize..n])
            if e9 != ok { ret e9 }
            let shv = lts_mcduni_std(ys, n, h)
            iR2 = (s0raw / shv) * (s0raw / shv)
        } else {
            let se1 = smallest_sum(a, sq, n, h, ss)
            if se1 != ok { ret se1 }
            var s1 = 0.0f64
            i = 0usize
            while i < h {
                s1 += ss[i]
                i += 1usize
            }
            i = 0usize
            while i < n {
                sq[i] = y[i] * y[i]
                i += 1usize
            }
            let se2 = smallest_sum(a, sq, n, h, ss)
            if se2 != ok { ret se2 }
            var sy = 0.0f64
            i = 0usize
            while i < h {
                sy += ss[i]
                i += 1usize
            }
            iR2 = s1 / sy
        }
        rsq = 0.0f64
        if iR2 == iR2 && iR2 - iR2 == 0.0f64 {
            rsq = 1.0f64 - iR2
            if rsq > 1.0f64 { rsq = 1.0f64 }
            if rsq < 0.0f64 { rsq = 0.0f64 }
        }
    }
    out[2usize * p + 2usize] = crit
    out[2usize * p + 3usize] = rsq
    out[2usize * p + 4usize] = f64(h)
    i = 0usize
    while i < h {
        out[beo + i] = f64(inbest[i])
        i += 1usize
    }
    // coefficients: intercept first
    if p > 1usize && intercept {
        let (tmp, e10) = mem.alloc[f64](a, 2usize * p)
        if e10 != ok { ret e10 }
        i = 0usize
        while i < 2usize * p {
            tmp[i] = out[i]
            i += 1usize
        }
        var blk = 0usize
        while blk < 2usize {
            out[blk * p] = tmp[blk * p + p - 1usize]
            var j = 1usize
            while j < p {
                out[blk * p + j] = tmp[blk * p + j - 1usize]
                j += 1usize
            }
            blk += 1usize
        }
    }
    ret ok
}
