// R's nlminb for an unbounded problem: the PORT library (Gay, 1983) as src/library/stats/src/portsrc.f carries it, driven the way src/library/stats/src/port.c drives it.
// Without a gradient the routine path is drmnf, which finite-differences the gradient with ds7grd (Stewart's scheme) and takes the steps of drmng (double dogleg and a BFGS secant update
// of a Cholesky factor, assessed by da7sst); with one it is drmng itself. The reverse-communication state machines keep the labels of the Fortran, and iv and v keep its layout (1-based).
// The scale d is 1 and the iteration summary is off, as nlminb leaves them. dnrm2 is the Blue accumulation of LAPACK 3.10, ddot the reference sum.
//
// Not ported: bounds (drmnfb, drmngb, dg7itb), the Hessian drivers (drmnh, drmnhb) and the NaN warning of port.c. One function call on the final return that port.c makes and discards is not made.

use e.math
use e.mem

const I_TOOBIG: usize = 2usize
const I_VNEED: usize = 4usize
const I_MODEL: usize = 5usize
const I_NFCALL: usize = 6usize
const I_NFGCAL: usize = 7usize
const I_RADINC: usize = 8usize
const I_RESTOR: usize = 9usize
const I_STAGE: usize = 10usize
const I_STGLIM: usize = 11usize
const I_SWITCH: usize = 12usize
const I_XIRC: usize = 13usize
const I_MXFCAL: usize = 17usize
const I_MXITER: usize = 18usize
const I_INITH: usize = 25usize
const I_G: usize = 28usize
const I_IRC: usize = 29usize
const I_NGCALL: usize = 30usize
const I_NITER: usize = 31usize
const I_MLSTGD: usize = 32usize
const I_KAGQT: usize = 33usize
const I_NWTSTP: usize = 34usize
const I_MODE: usize = 35usize
const I_DG: usize = 37usize
const I_STEP: usize = 40usize
const I_STLSTG: usize = 41usize
const I_LMAT: usize = 42usize
const I_X0: usize = 43usize
const I_NEXTV: usize = 47usize
const I_G0: usize = 48usize
const I_CNVCOD: usize = 55usize
const I_SGIRC: usize = 57usize

const V_DGNORM: usize = 1usize
const V_DSTNRM: usize = 2usize
const V_DST0: usize = 3usize
const V_GTSTEP: usize = 4usize
const V_STPPAR: usize = 5usize
const V_NREDUC: usize = 6usize
const V_PREDUC: usize = 7usize
const V_RADIUS: usize = 8usize
const V_RAD0: usize = 9usize
const V_F: usize = 10usize
const V_FDIF: usize = 11usize
const V_FLSTGD: usize = 12usize
const V_F0: usize = 13usize
const V_GTSLST: usize = 14usize
const V_PLSTGD: usize = 15usize
const V_RADFAC: usize = 16usize
const V_RELDX: usize = 17usize
const V_DSTSAV: usize = 18usize
const V_DECFAC: usize = 22usize
const V_INCFAC: usize = 23usize
const V_RDFCMN: usize = 24usize
const V_RDFCMX: usize = 25usize
const V_TUNER1: usize = 26usize
const V_TUNER2: usize = 27usize
const V_TUNER3: usize = 28usize
const V_TUNER4: usize = 29usize
const V_TUNER5: usize = 30usize
const V_AFCTOL: usize = 31usize
const V_RFCTOL: usize = 32usize
const V_XCTOL: usize = 33usize
const V_XFTOL: usize = 34usize
const V_LMAX0: usize = 35usize
const V_LMAXS: usize = 36usize
const V_SCTOL: usize = 37usize
const V_DINIT: usize = 38usize
const V_ETA0: usize = 42usize
const V_BIAS: usize = 43usize
const V_GTHG: usize = 44usize
const V_GRDFAC: usize = 45usize
const V_NWTFAC: usize = 46usize

// the workspace: iv and v are 1-based (element 0 unused); d, x and the supplied gradient sit in v after the PORT part, at the 1-based offsets d0, x0 and g0
type Port = struct { iv: []i64, v: []f64, n: usize, fx: f64, d0: usize, x0: usize }

// objective: the value of the objective at the answer; code: iv(1) (3 to 6 are convergence, 9 and 10 the evaluation and iteration limits, others failures); iterations: iv(31); fevals: iv(6); gevals: iv(30)
type Nlminb = struct { objective: f64, code: i64, iterations: usize, fevals: usize, gevals: usize }

fn machep() -> f64 { ret 2.220446049250313e-16f64 }

fn p2(e: i64) -> f64 { ret mem.bitcast[f64](u64(1023i64 + e) << 52u64) }

// DD7TPR (BLAS ddot): the sum of the products of n elements from the 1-based offsets x and y
fn dd7tpr(v: []f64, n: usize, x: usize, y: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += v[x + i] * v[y + i]
        i += 1usize
    }
    ret s
}

// DV2NRM (BLAS dnrm2, LAPACK 3.10): the 2-norm by Blue's three accumulators
fn dv2nrm(v: []f64, n: usize, x: usize) -> f64 {
    let tsml = p2(0i64 - 511i64)
    let tbig = p2(486i64)
    let ssml = p2(537i64)
    let sbig = p2(0i64 - 538i64)
    let maxn = 1.7976931348623157e308f64
    var abig = 0.0f64
    var amed = 0.0f64
    var asml = 0.0f64
    var notbig = true
    var i = 0usize
    while i < n {
        let ax = math.abs[f64](v[x + i])
        if ax > tbig {
            let t = ax * sbig
            abig += t * t
            notbig = false
        } else if ax < tsml {
            if notbig {
                let t = ax * ssml
                asml += t * t
            }
        } else {
            amed += ax * ax
        }
        i += 1usize
    }
    var scl = 1.0f64
    var sumsq = 0.0f64
    if abig > 0.0f64 {
        if amed > 0.0f64 || amed > maxn || amed != amed {
            abig += (amed * sbig) * sbig
        }
        scl = 1.0f64 / sbig
        sumsq = abig
    } else if asml > 0.0f64 {
        if amed > 0.0f64 || amed > maxn || amed != amed {
            amed = math.sqrt[f64](amed)
            asml = math.sqrt[f64](asml) / ssml
            var ymin = asml
            var ymax = amed
            if asml > amed {
                ymin = amed
                ymax = asml
            }
            scl = 1.0f64
            let q = ymin / ymax
            sumsq = ymax * ymax * (1.0f64 + q * q)
        } else {
            scl = 1.0f64 / ssml
            sumsq = asml
        }
    } else {
        scl = 1.0f64
        sumsq = amed
    }
    ret scl * math.sqrt[f64](sumsq)
}

fn dv7cpy(v: []f64, n: usize, dest: usize, src: usize) {
    var i = 0usize
    while i < n {
        v[dest + i] = v[src + i]
        i += 1usize
    }
}

fn dv7scp(v: []f64, n: usize, dest: usize, c: f64) {
    var i = 0usize
    while i < n {
        v[dest + i] = c
        i += 1usize
    }
}

// w = a * x + y
fn dv2axy(v: []f64, n: usize, w: usize, a: f64, x: usize, y: usize) {
    var i = 0usize
    while i < n {
        v[w + i] = a * v[x + i] + v[y + i]
        i += 1usize
    }
}

// x = y * z^k for k = 1 or -1
fn dv7vmp(v: []f64, n: usize, x: usize, y: usize, z: usize, k: i64) {
    var i = 0usize
    while i < n {
        if k < 0i64 { v[x + i] = v[y + i] / v[z + i] } else { v[x + i] = v[y + i] * v[z + i] }
        i += 1usize
    }
}

// x = L y for L lower triangular stored by rows; x and y may be one storage
fn dl7vml(v: []f64, n: usize, x: usize, l: usize, y: usize) {
    var i0 = n * (n + 1usize) / 2usize
    var ii = 1usize
    while ii <= n {
        let i = n + 1usize - ii
        i0 -= i
        var t = 0.0f64
        var j = 1usize
        while j <= i {
            t += v[l + i0 + j - 1usize] * v[y + j - 1usize]
            j += 1usize
        }
        v[x + i - 1usize] = t
        ii += 1usize
    }
}

// x = L^T y
fn dl7tvm(v: []f64, n: usize, x: usize, l: usize, y: usize) {
    var i0 = 0usize
    var i = 1usize
    while i <= n {
        let yi = v[y + i - 1usize]
        v[x + i - 1usize] = 0.0f64
        var j = 1usize
        while j <= i {
            v[x + j - 1usize] = v[x + j - 1usize] + yi * v[l + i0 + j - 1usize]
            j += 1usize
        }
        i0 += i
        i += 1usize
    }
}

// solve L^T x = y
fn dl7itv(v: []f64, n: usize, x: usize, l: usize, y: usize) {
    var i = 1usize
    while i <= n {
        v[x + i - 1usize] = v[y + i - 1usize]
        i += 1usize
    }
    var i0 = n * (n + 1usize) / 2usize
    var ii = 1usize
    while ii <= n {
        let i2 = n + 1usize - ii
        let xi = v[x + i2 - 1usize] / v[l + i0 - 1usize]
        v[x + i2 - 1usize] = xi
        if i2 <= 1usize { ret }
        i0 -= i2
        if xi != 0.0f64 {
            var j = 1usize
            while j < i2 {
                v[x + j - 1usize] = v[x + j - 1usize] - xi * v[l + i0 + j - 1usize]
                j += 1usize
            }
        }
        ii += 1usize
    }
}

// solve L x = y
fn dl7ivm(v: []f64, n: usize, x: usize, l: usize, y: usize) {
    var k = 1usize
    while k <= n && v[y + k - 1usize] == 0.0f64 {
        v[x + k - 1usize] = 0.0f64
        k += 1usize
    }
    if k > n { ret }
    var j = k * (k + 1usize) / 2usize
    v[x + k - 1usize] = v[y + k - 1usize] / v[l + j - 1usize]
    if k >= n { ret }
    k += 1usize
    var i = k
    while i <= n {
        let t = dd7tpr(v, i - 1usize, l + j, x)
        j += i
        v[x + i - 1usize] = (v[y + i - 1usize] - t) / v[l + j - 1usize]
        i += 1usize
    }
}

// the secant update of L: lplus = the factor of L (I + z w^T)(I + w z^T) L^T; beta, gamma, lambda are scratch, w and z are destroyed
fn dl7upd(v: []f64, beta: usize, gamma: usize, l: usize, lambda: usize, lplus: usize, n: usize, w: usize, z: usize) {
    var nu = 1.0f64
    var eta = 0.0f64
    if n > 1usize {
        let nm1 = n - 1usize
        var s = 0.0f64
        var i = 1usize
        while i <= nm1 {
            let j = n - i
            let wj1 = v[w + j]
            s += wj1 * wj1
            v[lambda + j - 1usize] = s
            i += 1usize
        }
        var j = 1usize
        while j <= nm1 {
            let wj = v[w + j - 1usize]
            let a = nu * v[z + j - 1usize] - eta * wj
            let theta = 1.0f64 + a * wj
            s = a * v[lambda + j - 1usize]
            var lj = math.sqrt[f64](theta * theta + a * s)
            if theta > 0.0f64 { lj = 0.0f64 - lj }
            v[lambda + j - 1usize] = lj
            let b = theta * wj + s
            v[gamma + j - 1usize] = b * nu / lj
            v[beta + j - 1usize] = (a - b * eta) / lj
            nu = (0.0f64 - nu) / lj
            eta = (0.0f64 - (eta + (a * a) / (theta - lj))) / lj
            j += 1usize
        }
    }
    v[lambda + n - 1usize] = 1.0f64 + (nu * v[z + n - 1usize] - eta * v[w + n - 1usize]) * v[w + n - 1usize]
    var jj = n * (n + 1usize) / 2usize
    var k = 1usize
    while k <= n {
        let j = n + 1usize - k
        let lj = v[lambda + j - 1usize]
        let ljj = v[l + jj - 1usize]
        v[lplus + jj - 1usize] = lj * ljj
        let wj = v[w + j - 1usize]
        v[w + j - 1usize] = ljj * wj
        let zj = v[z + j - 1usize]
        v[z + j - 1usize] = ljj * zj
        if k != 1usize {
            let bj = v[beta + j - 1usize]
            let gj = v[gamma + j - 1usize]
            var ij = jj + j
            var i = j + 1usize
            while i <= n {
                let lij = v[l + ij - 1usize]
                v[lplus + ij - 1usize] = lj * lij + bj * v[w + i - 1usize] + gj * v[z + i - 1usize]
                v[w + i - 1usize] = v[w + i - 1usize] + lij * wj
                v[z + i - 1usize] = v[z + i - 1usize] + lij * zj
                ij += i
                i += 1usize
            }
        }
        jj -= j
        k += 1usize
    }
}

// w and z for dl7upd that correspond to the BFGS update (a damped one when y.s is under a tenth of s.H.s)
fn dw7zbf(v: []f64, l: usize, n: usize, s: usize, w: usize, y: usize, z: usize) {
    dl7tvm(v, n, w, l, s)
    let shs = dd7tpr(v, n, w, w)
    let ys = dd7tpr(v, n, y, s)
    var cy = 0.0f64
    var cs = 0.0f64
    if ys >= 0.1f64 * shs {
        cy = 1.0f64 / (math.sqrt[f64](ys) * math.sqrt[f64](shs))
        cs = 1.0f64 / shs
    } else {
        let theta = (1.0f64 - 0.1f64) * shs / (shs - ys)
        let epsrt = math.sqrt[f64](0.1f64)
        cy = theta / (shs * epsrt)
        cs = (1.0f64 + (theta - 1.0f64) / epsrt) / shs
    }
    dl7ivm(v, n, z, l, y)
    var i = 1usize
    while i <= n {
        v[z + i - 1usize] = cy * v[z + i - 1usize] - cs * v[w + i - 1usize]
        i += 1usize
    }
}

// the relative difference between x and x0, scaled by d
fn drldst(v: []f64, n: usize, d: usize, x: usize, x0: usize) -> f64 {
    var emax = 0.0f64
    var xmax = 0.0f64
    var i = 0usize
    while i < n {
        var t = math.abs[f64](v[d + i] * (v[x + i] - v[x0 + i]))
        if emax < t { emax = t }
        t = v[d + i] * (math.abs[f64](v[x + i]) + math.abs[f64](v[x0 + i]))
        if xmax < t { xmax = t }
        i += 1usize
    }
    var r = 0.0f64
    if xmax > 0.0f64 { r = emax / xmax }
    ret r
}

// the double dogleg step between the Cauchy and the Newton step inside the trust region of radius v(radius)
fn dd7dog(v: []f64, dig: usize, n: usize, nwtstp: usize, step: usize) {
    let nwtnrm = v[V_DST0]
    var rlambd = 1.0f64
    if nwtnrm > 0.0f64 { rlambd = v[V_RADIUS] / nwtnrm }
    let gnorm = v[V_DGNORM]
    let ghinvg = 2.0f64 * v[V_NREDUC]
    v[V_GRDFAC] = 0.0f64
    v[V_NWTFAC] = 0.0f64
    var i = 0usize
    if rlambd >= 1.0f64 {
        v[V_STPPAR] = 0.0f64
        v[V_DSTNRM] = nwtnrm
        v[V_GTSTEP] = 0.0f64 - ghinvg
        v[V_PREDUC] = v[V_NREDUC]
        v[V_NWTFAC] = 0.0f64 - 1.0f64
        while i < n {
            v[step + i] = 0.0f64 - v[nwtstp + i]
            i += 1usize
        }
        ret
    }
    v[V_DSTNRM] = v[V_RADIUS]
    let q = gnorm / v[V_GTHG]
    let cfact = q * q
    let cnorm = gnorm * cfact
    let relax = 1.0f64 - v[V_BIAS] * (1.0f64 - gnorm * cnorm / ghinvg)
    if rlambd >= relax {
        v[V_STPPAR] = 1.0f64 - (rlambd - relax) / (1.0f64 - relax)
        let t = 0.0f64 - rlambd
        v[V_GTSTEP] = t * ghinvg
        v[V_PREDUC] = rlambd * (1.0f64 - 0.5f64 * rlambd) * ghinvg
        v[V_NWTFAC] = t
        while i < n {
            v[step + i] = t * v[nwtstp + i]
            i += 1usize
        }
        ret
    }
    if cnorm >= v[V_RADIUS] {
        let t = (0.0f64 - v[V_RADIUS]) / gnorm
        v[V_GRDFAC] = t
        v[V_STPPAR] = 1.0f64 + cnorm / v[V_RADIUS]
        v[V_GTSTEP] = (0.0f64 - v[V_RADIUS]) * gnorm
        let r2 = v[V_GTHG] / gnorm
        v[V_PREDUC] = v[V_RADIUS] * (gnorm - 0.5f64 * v[V_RADIUS] * (r2 * r2))
        while i < n {
            v[step + i] = t * v[dig + i]
            i += 1usize
        }
        ret
    }
    let ctrnwt = cfact * relax * ghinvg / gnorm
    var t1 = ctrnwt - gnorm * (cfact * cfact)
    let t2a = v[V_RADIUS] * (v[V_RADIUS] / gnorm) - gnorm * (cfact * cfact)
    var t = relax * nwtnrm
    let femnsq = (t / gnorm) * t - ctrnwt - t1
    t = t2a / (t1 + math.sqrt[f64](t1 * t1 + femnsq * t2a))
    t1 = (t - 1.0f64) * cfact
    v[V_GRDFAC] = t1
    let t2 = (0.0f64 - t) * relax
    v[V_NWTFAC] = t2
    v[V_STPPAR] = 2.0f64 - t
    v[V_GTSTEP] = t1 * (gnorm * gnorm) + t2 * ghinvg
    let hp = v[V_GTHG] * t1
    v[V_PREDUC] = (0.0f64 - t1) * gnorm * ((t2 + 1.0f64) * gnorm) - t2 * (1.0f64 + 0.5f64 * t2) * ghinvg - 0.5f64 * (hp * hp)
    while i < n {
        v[step + i] = t1 * v[dig + i] + t2 * v[nwtstp + i]
        i += 1usize
    }
}

// Stewart's finite-difference gradient by reverse communication: the return code is iv(sgirc), zero when g is done, else x has been perturbed and f(x) is wanted in p.fx
fn ds7grd(p: *Port, alpha: usize, g: usize, w: usize) {
    let v = p.v
    let iv = p.iv
    let n = p.n
    let d = p.d0
    let x = p.x0
    let eta0 = v[V_ETA0]
    var irc = iv[I_SGIRC]
    var pc = 0i64
    if irc < 0i64 { pc = 140i64 } else if irc > 0i64 {
        pc = 210i64
    } else {
        v[w] = machep()
        v[w + 1usize] = math.sqrt[f64](v[w])
        v[w + 3usize] = p.fx
        pc = 110i64
    }
    var i = 0usize
    var h = 0.0f64
    var axibar = 0.0f64
    var alphai = 0.0f64
    var gi = 0.0f64
    var aai = 0.0f64
    var agi = 0.0f64
    var afxeta = 0.0f64
    var h0 = 0.0f64
    while true {
        if pc == 110i64 {
            var air = irc
            if air < 0i64 { air = 0i64 - air }
            i = usize(air) + 1usize
            if i > n {
                p.fx = v[w + 3usize]
                irc = 0i64
                iv[I_SGIRC] = irc
                ret
            }
            irc = i64(i)
            let afx = math.abs[f64](v[w + 3usize])
            let me = v[w]
            h0 = v[w + 1usize]
            let hmin = 50.0f64 * me
            v[w + 5usize] = v[x + i - 1usize]
            let axi = math.abs[f64](v[x + i - 1usize])
            axibar = math.max[f64](axi, 1.0f64 / v[d + i - 1usize])
            gi = v[g + i - 1usize]
            agi = math.abs[f64](gi)
            var eta = math.abs[f64](eta0)
            if afx > 0.0f64 { eta = math.max[f64](eta, agi * axi * me / afx) }
            alphai = v[alpha + i - 1usize]
            if alphai == 0.0f64 {
                pc = 170i64
            } else if gi == 0.0f64 || p.fx == 0.0f64 {
                pc = 180i64
            } else {
                afxeta = afx * eta
                aai = math.abs[f64](alphai)
                if gi * gi <= afxeta * aai {
                    h = 2.0f64 * math.pow[f64](afxeta * agi, 1.0f64 / 3.0f64) * math.pow[f64](aai, (0.0f64 - 2.0f64) / 3.0f64)
                    h = h * (1.0f64 - 2.0f64 * agi / (3.0f64 * aai * h + 4.0f64 * agi))
                } else {
                    h = 2.0f64 * math.sqrt[f64](afxeta / aai)
                    h = h * (1.0f64 - aai * h / (3.0f64 * aai * h + 4.0f64 * agi))
                }
                h = math.max[f64](h, hmin * axibar)
                if aai * h <= 0.002f64 * agi {
                    pc = 160i64
                } else {
                    let discon = 2000.0f64 * afxeta
                    h = discon / (agi + math.sqrt[f64](gi * gi + aai * discon))
                    h = math.max[f64](h, hmin * axibar)
                    if h >= 0.02f64 * axibar { h = axibar * math.pow[f64](h0, 2.0f64 / 3.0f64) }
                    irc = 0i64 - i64(i)
                    pc = 200i64
                }
            }
        }
        if pc == 140i64 {
            h = 0.0f64 - v[w + 4usize]
            var air = irc
            if air < 0i64 { air = 0i64 - air }
            i = usize(air)
            if h > 0.0f64 {
                v[g + i - 1usize] = (v[w + 2usize] - p.fx) / (2.0f64 * h)
                v[x + i - 1usize] = v[w + 5usize]
                pc = 110i64
            } else {
                v[w + 2usize] = p.fx
                pc = 200i64
            }
        }
        if pc == 160i64 {
            if h >= 0.02f64 * axibar { h = h0 * axibar }
            if alphai * gi < 0.0f64 { h = 0.0f64 - h }
            pc = 200i64
        }
        if pc == 170i64 {
            h = axibar
            pc = 200i64
        }
        if pc == 180i64 {
            h = h0 * axibar
            pc = 200i64
        }
        if pc == 200i64 {
            v[x + i - 1usize] = v[w + 5usize] + h
            v[w + 4usize] = h
            iv[I_SGIRC] = irc
            ret
        }
        if pc == 210i64 {
            let ir = usize(irc)
            v[g + ir - 1usize] = (p.fx - v[w + 3usize]) / v[w + 4usize]
            v[x + ir - 1usize] = v[w + 5usize]
            pc = 110i64
        }
    }
}

// DA7SST: assess the candidate step and set the return code iv(irc)
fn da7sst(p: *Port) {
    let v = p.v
    let iv = p.iv
    var nfc = iv[I_NFCALL]
    iv[I_SWITCH] = 0i64
    iv[I_RESTOR] = 0i64
    var rfac1 = 1.0f64
    var goodx = true
    var i = iv[I_IRC]
    var emax = 0.0f64
    var emaxs = 0.0f64
    var pc = 0i64
    if i >= 1i64 && i <= 12i64 {
        if i == 1i64 {
            pc = 20i64
        } else if i == 2i64 {
            pc = 30i64
        } else if i == 3i64 || i == 4i64 {
            pc = 10i64
        } else if i == 5i64 {
            pc = 40i64
        } else if i == 6i64 {
            pc = 280i64
        } else if i == 12i64 {
            pc = 170i64
        } else {
            pc = 220i64
        }
    } else {
        iv[I_IRC] = 13i64
        ret
    }
    while true {
        if pc == 10i64 {
            iv[I_STAGE] = 1i64
            iv[I_RADINC] = 0i64
            v[V_FLSTGD] = v[V_F0]
            if iv[I_TOOBIG] == 0i64 {
                pc = 110i64
            } else {
                iv[I_STAGE] = 0i64 - 1i64
                iv[I_XIRC] = i
                pc = 60i64
            }
        }
        if pc == 20i64 {
            if iv[I_MODEL] != iv[I_MLSTGD] {
                pc = 30i64
            } else {
                iv[I_STAGE] = iv[I_STGLIM]
                iv[I_RADINC] = 0i64 - 1i64
                pc = 110i64
            }
        }
        if pc == 30i64 {
            iv[I_STAGE] += 1i64
            pc = 40i64
        }
        if pc == 40i64 {
            if iv[I_STAGE] > 0i64 {
                pc = 50i64
            } else if iv[I_TOOBIG] != 0i64 {
                pc = 60i64
            } else {
                iv[I_STAGE] = 0i64 - iv[I_STAGE]
                i = iv[I_XIRC]
                if i == 1i64 {
                    pc = 20i64
                } else if i == 2i64 {
                    pc = 30i64
                } else if i == 3i64 || i == 4i64 {
                    pc = 110i64
                } else if i == 5i64 {
                    pc = 70i64
                } else {
                    pc = 50i64
                }
            }
        }
        if pc == 50i64 {
            if iv[I_TOOBIG] == 0i64 {
                pc = 70i64
            } else {
                iv[I_TOOBIG] = 0i64
                if iv[I_RADINC] > 0i64 {
                    pc = 80i64
                } else {
                    iv[I_STAGE] = 0i64 - iv[I_STAGE]
                    iv[I_XIRC] = iv[I_IRC]
                    pc = 60i64
                }
            }
        }
        if pc == 60i64 {
            iv[I_TOOBIG] = 0i64
            v[V_RADFAC] = v[V_DECFAC]
            iv[I_RADINC] = iv[I_RADINC] - 1i64
            iv[I_IRC] = 5i64
            iv[I_RESTOR] = 1i64
            v[V_F] = v[V_FLSTGD]
            ret
        }
        if pc == 70i64 {
            if v[V_F] < v[V_FLSTGD] {
                pc = 110i64
            } else {
                if iv[I_MODEL] != iv[I_MLSTGD] {
                    iv[I_MODEL] = iv[I_MLSTGD]
                    iv[I_SWITCH] = 1i64
                }
                pc = 80i64
            }
        }
        if pc == 80i64 {
            if v[V_FLSTGD] >= v[V_F0] {
                pc = 110i64
            } else {
                if iv[I_STAGE] < iv[I_STGLIM] {
                    goodx = false
                } else if nfc < iv[I_NFGCAL] + iv[I_STGLIM] + 2i64 {
                    goodx = false
                } else if iv[I_SWITCH] != 0i64 {
                    goodx = false
                }
                iv[I_RESTOR] = 3i64
                v[V_F] = v[V_FLSTGD]
                v[V_PREDUC] = v[V_PLSTGD]
                v[V_GTSTEP] = v[V_GTSLST]
                if iv[I_SWITCH] == 0i64 { rfac1 = v[V_DSTNRM] / v[V_DSTSAV] }
                v[V_DSTNRM] = v[V_DSTSAV]
                if goodx {
                    v[V_FDIF] = v[V_F0] - v[V_F]
                    iv[I_IRC] = 4i64
                    v[V_RADFAC] = rfac1
                    ret
                }
                nfc = iv[I_NFGCAL]
                pc = 110i64
            }
        }
        if pc == 110i64 {
            v[V_FDIF] = v[V_F0] - v[V_F]
            if v[V_FDIF] > v[V_TUNER2] * v[V_PREDUC] || iv[I_RADINC] > 0i64 {
                pc = 140i64
            } else {
                if v[V_F] < v[V_F0] {
                    iv[I_NFGCAL] = nfc
                } else {
                    iv[I_MLSTGD] = iv[I_MODEL]
                    v[V_FLSTGD] = v[V_F]
                    v[V_F] = v[V_F0]
                    iv[I_RESTOR] = 1i64
                }
                iv[I_IRC] = 1i64
                if iv[I_STAGE] >= iv[I_STGLIM] {
                    iv[I_IRC] = 5i64
                    iv[I_RADINC] = iv[I_RADINC] - 1i64
                }
                pc = 160i64
            }
        }
        if pc == 140i64 {
            iv[I_NFGCAL] = nfc
            rfac1 = 1.0f64
            v[V_DSTSAV] = v[V_DSTNRM]
            if v[V_FDIF] > v[V_PREDUC] * v[V_TUNER1] {
                pc = 190i64
            } else {
                if iv[I_STAGE] >= iv[I_STGLIM] { iv[I_IRC] = 4i64 } else { iv[I_IRC] = 2i64 }
                pc = 160i64
            }
        }
        if pc == 160i64 {
            iv[I_XIRC] = iv[I_IRC]
            emax = v[V_GTSTEP] + v[V_FDIF]
            v[V_RADFAC] = 0.5f64 * rfac1
            if emax < v[V_GTSTEP] { v[V_RADFAC] = rfac1 * math.max[f64](v[V_RDFCMN], 0.5f64 * v[V_GTSTEP] / emax) }
            pc = 170i64
        }
        if pc == 170i64 {
            if v[V_RELDX] <= v[V_XFTOL] {
                pc = 180i64
            } else {
                iv[I_IRC] = iv[I_XIRC]
                if v[V_F] < v[V_F0] { pc = 200i64 } else { pc = 230i64 }
            }
        }
        if pc == 180i64 {
            iv[I_IRC] = 12i64
            pc = 240i64
        }
        if pc == 190i64 {
            if v[V_FDIF] < (0.0f64 - v[V_TUNER3]) * v[V_GTSTEP] || iv[I_RADINC] < 0i64 || iv[I_RESTOR] == 1i64 || iv[I_RESTOR] == 3i64 {
                pc = 210i64
            } else {
                v[V_RADFAC] = v[V_RDFCMX]
                let gts = v[V_GTSTEP]
                if v[V_FDIF] < (0.5f64 / v[V_RADFAC] - 1.0f64) * gts { v[V_RADFAC] = math.max[f64](v[V_INCFAC], 0.5f64 * gts / (gts + v[V_FDIF])) }
                iv[I_IRC] = 4i64
                if v[V_STPPAR] == 0.0f64 {
                    pc = 230i64
                } else if v[V_DST0] >= 0.0f64 && (v[V_DST0] < 2.0f64 * v[V_DSTNRM] || v[V_NREDUC] < 1.2f64 * v[V_FDIF]) {
                    pc = 230i64
                } else {
                    iv[I_IRC] = 5i64
                    iv[I_RADINC] = iv[I_RADINC] + 1i64
                    pc = 200i64
                }
            }
        }
        if pc == 200i64 {
            v[V_FLSTGD] = v[V_F]
            iv[I_MLSTGD] = iv[I_MODEL]
            if iv[I_RESTOR] == 0i64 { iv[I_RESTOR] = 2i64 }
            v[V_DSTSAV] = v[V_DSTNRM]
            iv[I_NFGCAL] = nfc
            v[V_PLSTGD] = v[V_PREDUC]
            v[V_GTSLST] = v[V_GTSTEP]
            pc = 230i64
        }
        if pc == 210i64 {
            v[V_RADFAC] = 1.0f64
            iv[I_IRC] = 3i64
            pc = 230i64
        }
        if pc == 220i64 {
            iv[I_IRC] = iv[I_XIRC]
            if v[V_DSTSAV] < 0.0f64 { iv[I_IRC] = 12i64 }
            pc = 240i64
        }
        if pc == 230i64 {
            iv[I_XIRC] = iv[I_IRC]
            pc = 240i64
        }
        if pc == 240i64 {
            if iv[I_RESTOR] == 1i64 && v[V_FLSTGD] < v[V_F0] { iv[I_RESTOR] = 3i64 }
            if math.abs[f64](v[V_F]) < v[V_AFCTOL] { iv[I_IRC] = 10i64 }
            if 0.5f64 * v[V_FDIF] > v[V_PREDUC] { ret }
            emax = v[V_RFCTOL] * math.abs[f64](v[V_F0])
            emaxs = v[V_SCTOL] * math.abs[f64](v[V_F0])
            if v[V_PREDUC] <= emaxs && (v[V_DSTNRM] > v[V_LMAXS] || v[V_STPPAR] == 0.0f64) { iv[I_IRC] = 11i64 }
            if v[V_DST0] >= 0.0f64 {
                i = 0i64
                if (v[V_NREDUC] > 0.0f64 && v[V_NREDUC] <= emax) || (v[V_NREDUC] == 0.0f64 && v[V_PREDUC] == 0.0f64) { i = 2i64 }
                if v[V_STPPAR] == 0.0f64 && v[V_RELDX] <= v[V_XCTOL] && goodx { i = i + 1i64 }
                if i > 0i64 { iv[I_IRC] = i + 6i64 }
            }
            pc = 250i64
        }
        if pc == 250i64 {
            if iv[I_IRC] > 5i64 && iv[I_IRC] != 12i64 { ret }
            if v[V_STPPAR] == 0.0f64 { ret }
            if v[V_DSTNRM] > v[V_LMAXS] {
                pc = 260i64
            } else {
                if v[V_PREDUC] >= emaxs { ret }
                if v[V_DST0] > 0.0f64 {
                    if 0.5f64 * v[V_DST0] <= v[V_LMAXS] { ret }
                }
                pc = 270i64
            }
        }
        if pc == 260i64 {
            if 0.5f64 * v[V_DSTNRM] <= v[V_LMAXS] { ret }
            let xmax = v[V_LMAXS] / v[V_DSTNRM]
            if xmax * (2.0f64 - xmax) * v[V_PREDUC] >= emaxs { ret }
            pc = 270i64
        }
        if pc == 270i64 {
            if v[V_NREDUC] < 0.0f64 {
                pc = 290i64
            } else {
                v[V_GTSLST] = v[V_GTSTEP]
                v[V_DSTSAV] = v[V_DSTNRM]
                if iv[I_IRC] == 12i64 { v[V_DSTSAV] = 0.0f64 - v[V_DSTSAV] }
                v[V_PLSTGD] = v[V_PREDUC]
                i = iv[I_RESTOR]
                iv[I_RESTOR] = 2i64
                if i == 3i64 { iv[I_RESTOR] = 0i64 }
                iv[I_IRC] = 6i64
                ret
            }
        }
        if pc == 280i64 {
            v[V_GTSTEP] = v[V_GTSLST]
            v[V_DSTNRM] = math.abs[f64](v[V_DSTSAV])
            iv[I_IRC] = iv[I_XIRC]
            if v[V_DSTSAV] <= 0.0f64 { iv[I_IRC] = 12i64 }
            v[V_NREDUC] = 0.0f64 - v[V_PREDUC]
            v[V_PREDUC] = v[V_PLSTGD]
            iv[I_RESTOR] = 3i64
            pc = 290i64
        }
        if pc == 290i64 {
            if (0.0f64 - v[V_NREDUC]) <= v[V_SCTOL] * math.abs[f64](v[V_F0]) { iv[I_IRC] = 11i64 }
            ret
        }
    }
}

// DRMNG: the iterations of the double-dogleg BFGS method by reverse communication. iv(1) is 1 on return when f(x) is wanted (in p.fx), 2 when g (at the 1-based offset g) is wanted, 3 and up when finished
fn drmng(p: *Port, g: usize) {
    let v = p.v
    let iv = p.iv
    let n = p.n
    let d = p.d0
    let x = p.x0
    let nn = i64(n)
    var pc = 0i64
    var i = iv[1usize]
    var k = 0i64
    var rstrst = 0i64
    var dg1 = 0usize
    var g01 = 0usize
    var x01 = 0usize
    var step1 = 0usize
    var temp1 = 0usize
    var lstgst = 0usize
    var nwtst1 = 0usize
    var l = 0usize
    if i == 1i64 {
        pc = 50i64
    } else if i == 2i64 {
        pc = 60i64
    } else {
        if iv[1usize] == 12i64 || iv[1usize] == 13i64 { iv[I_VNEED] = iv[I_VNEED] + nn * (nn + 13i64) / 2i64 }
        if iv[1usize] == 12i64 || iv[1usize] == 13i64 { iv[I_NEXTV] = iv[I_LMAT] }
        i = iv[1usize] - 2i64
        if i > 12i64 { ret }
        if i >= 1i64 && i <= 6i64 {
            pc = 190i64
        } else if i == 7i64 || i == 9i64 {
            pc = 120i64
        } else if i == 8i64 {
            pc = 90i64
        } else if i == 10i64 || i == 11i64 {
            pc = 10i64
        } else if i == 12i64 {
            pc = 20i64
        } else {
            ret
        }
    }
    while true {
        if pc == 10i64 {
            l = usize(iv[I_LMAT])
            iv[I_X0] = i64(l + n * (n + 1usize) / 2usize)
            iv[I_STEP] = iv[I_X0] + nn
            iv[I_STLSTG] = iv[I_STEP] + nn
            iv[I_G0] = iv[I_STLSTG] + nn
            iv[I_NWTSTP] = iv[I_G0] + nn
            iv[I_DG] = iv[I_NWTSTP] + nn
            iv[I_NEXTV] = iv[I_DG] + nn
            if iv[1usize] != 13i64 {
                pc = 20i64
            } else {
                iv[1usize] = 14i64
                ret
            }
        }
        if pc == 20i64 {
            iv[I_NITER] = 0i64
            iv[I_NFCALL] = 1i64
            iv[I_NGCALL] = 1i64
            iv[I_NFGCAL] = 1i64
            iv[I_MODE] = 0i64 - 1i64
            iv[I_MODEL] = 1i64
            iv[I_STGLIM] = 1i64
            iv[I_TOOBIG] = 0i64
            iv[I_CNVCOD] = 0i64
            iv[I_RADINC] = 0i64
            v[V_RAD0] = 0.0f64
            if v[V_DINIT] >= 0.0f64 { dv7scp(v, n, d, v[V_DINIT]) }
            if iv[I_INITH] == 1i64 {
                l = usize(iv[I_LMAT])
                dv7scp(v, n * (n + 1usize) / 2usize, l, 0.0f64)
                var kk = l - 1usize
                var ii = 1usize
                while ii <= n {
                    kk += ii
                    var t = v[d + ii - 1usize]
                    if t <= 0.0f64 { t = 1.0f64 }
                    v[kk] = t
                    ii += 1usize
                }
            }
            pc = 40i64
        }
        if pc == 40i64 {
            iv[1usize] = 1i64
            ret
        }
        if pc == 50i64 {
            v[V_F] = p.fx
            if iv[I_MODE] >= 0i64 {
                pc = 190i64
            } else {
                v[V_F0] = p.fx
                iv[1usize] = 2i64
                if iv[I_TOOBIG] == 0i64 { ret }
                iv[1usize] = 63i64
                pc = 350i64
            }
        }
        if pc == 60i64 {
            if iv[I_TOOBIG] != 0i64 {
                iv[1usize] = 65i64
                pc = 350i64
            } else {
                pc = 70i64
            }
        }
        if pc == 70i64 {
            dg1 = usize(iv[I_DG])
            dv7vmp(v, n, dg1, g, d, 0i64 - 1i64)
            v[V_DGNORM] = dv2nrm(v, n, dg1)
            if iv[I_CNVCOD] != 0i64 {
                pc = 340i64
            } else if iv[I_MODE] == 0i64 {
                pc = 300i64
            } else {
                v[V_RADIUS] = v[V_LMAX0]
                iv[I_MODE] = 0i64
                pc = 90i64
            }
        }
        if pc == 90i64 {
            k = iv[I_NITER]
            if k < iv[I_MXITER] {
                pc = 100i64
            } else {
                iv[1usize] = 10i64
                pc = 350i64
            }
        }
        if pc == 100i64 {
            iv[I_NITER] = k + 1i64
            if k > 0i64 { v[V_RADIUS] = v[V_RADFAC] * v[V_DSTNRM] }
            g01 = usize(iv[I_G0])
            x01 = usize(iv[I_X0])
            v[V_F0] = v[V_F]
            iv[I_IRC] = 4i64
            iv[I_KAGQT] = 0i64 - 1i64
            dv7cpy(v, n, x01, x)
            dv7cpy(v, n, g01, g)
            pc = 130i64
        }
        if pc == 120i64 {
            if v[V_F] >= v[V_F0] {
                pc = 130i64
            } else {
                v[V_RADFAC] = 1.0f64
                k = iv[I_NITER]
                pc = 100i64
            }
        }
        if pc == 130i64 {
            if iv[I_NFCALL] < iv[I_MXFCAL] {
                pc = 150i64
            } else {
                iv[1usize] = 9i64
                pc = 140i64
            }
        }
        if pc == 140i64 {
            if v[V_F] >= v[V_F0] {
                pc = 350i64
            } else {
                iv[I_CNVCOD] = iv[1usize]
                pc = 290i64
            }
        }
        if pc == 150i64 {
            step1 = usize(iv[I_STEP])
            dg1 = usize(iv[I_DG])
            nwtst1 = usize(iv[I_NWTSTP])
            if iv[I_KAGQT] < 0i64 {
                l = usize(iv[I_LMAT])
                dl7ivm(v, n, nwtst1, l, g)
                v[V_NREDUC] = 0.5f64 * dd7tpr(v, n, nwtst1, nwtst1)
                dl7itv(v, n, nwtst1, l, nwtst1)
                dv7vmp(v, n, step1, nwtst1, d, 1i64)
                v[V_DST0] = dv2nrm(v, n, step1)
                dv7vmp(v, n, dg1, dg1, d, 0i64 - 1i64)
                dl7tvm(v, n, step1, l, dg1)
                v[V_GTHG] = dv2nrm(v, n, step1)
                iv[I_KAGQT] = 0i64
            }
            dd7dog(v, dg1, n, nwtst1, step1)
            if iv[I_IRC] != 6i64 {
                pc = 170i64
            } else if iv[I_RESTOR] != 2i64 {
                pc = 190i64
            } else {
                rstrst = 2i64
                pc = 200i64
            }
        }
        if pc == 170i64 {
            iv[I_TOOBIG] = 0i64
            if v[V_DSTNRM] <= 0.0f64 {
                pc = 190i64
            } else if iv[I_IRC] != 5i64 || v[V_RADFAC] <= 1.0f64 || v[V_PREDUC] > 1.2f64 * v[V_FDIF] {
                pc = 180i64
            } else if iv[I_RESTOR] != 2i64 {
                pc = 190i64
            } else {
                rstrst = 0i64
                pc = 200i64
            }
        }
        if pc == 180i64 {
            x01 = usize(iv[I_X0])
            step1 = usize(iv[I_STEP])
            dv2axy(v, n, x, 1.0f64, step1, x01)
            iv[I_NFCALL] = iv[I_NFCALL] + 1i64
            iv[1usize] = 1i64
            ret
        }
        if pc == 190i64 {
            rstrst = 3i64
            pc = 200i64
        }
        if pc == 200i64 {
            x01 = usize(iv[I_X0])
            v[V_RELDX] = drldst(v, n, d, x, x01)
            da7sst(p)
            step1 = usize(iv[I_STEP])
            lstgst = usize(iv[I_STLSTG])
            i = iv[I_RESTOR] + 1i64
            if i == 2i64 {
                dv7cpy(v, n, x, x01)
            } else if i == 3i64 {
                dv7cpy(v, n, lstgst, step1)
            } else if i == 4i64 {
                dv7cpy(v, n, step1, lstgst)
                dv2axy(v, n, x, 1.0f64, step1, x01)
                v[V_RELDX] = drldst(v, n, d, x, x01)
                iv[I_RESTOR] = rstrst
            }
            k = iv[I_IRC]
            if k == 1i64 || k == 5i64 {
                pc = 250i64
            } else if k >= 2i64 && k <= 4i64 {
                pc = 280i64
            } else if k == 6i64 {
                pc = 260i64
            } else if k >= 7i64 && k <= 12i64 {
                pc = 270i64
            } else if k == 13i64 {
                pc = 330i64
            } else {
                pc = 300i64
            }
        }
        if pc == 250i64 {
            v[V_RADIUS] = v[V_RADFAC] * v[V_DSTNRM]
            pc = 130i64
        }
        if pc == 260i64 {
            v[V_RADIUS] = v[V_LMAXS]
            pc = 150i64
        }
        if pc == 270i64 {
            iv[I_CNVCOD] = k - 4i64
            if v[V_F] >= v[V_F0] {
                pc = 340i64
            } else if iv[I_XIRC] == 14i64 {
                pc = 340i64
            } else {
                iv[I_XIRC] = 14i64
                pc = 280i64
            }
        }
        if pc == 280i64 {
            if iv[I_IRC] == 3i64 {
                step1 = usize(iv[I_STEP])
                temp1 = usize(iv[I_STLSTG])
                l = usize(iv[I_LMAT])
                dl7tvm(v, n, temp1, l, step1)
                dl7vml(v, n, temp1, l, temp1)
            }
            pc = 290i64
        }
        if pc == 290i64 {
            iv[I_NGCALL] = iv[I_NGCALL] + 1i64
            iv[1usize] = 2i64
            ret
        }
        if pc == 300i64 {
            g01 = usize(iv[I_G0])
            dv2axy(v, n, g01, 0.0f64 - 1.0f64, g01, g)
            step1 = usize(iv[I_STEP])
            temp1 = usize(iv[I_STLSTG])
            if iv[I_IRC] == 3i64 {
                dv2axy(v, n, temp1, 0.0f64 - 1.0f64, g01, temp1)
                dv7vmp(v, n, temp1, temp1, d, 0i64 - 1i64)
                if dv2nrm(v, n, temp1) <= v[V_DGNORM] * v[V_TUNER4] {
                    v[V_RADFAC] = v[V_INCFAC]
                } else if dd7tpr(v, n, g, step1) >= v[V_GTSTEP] * v[V_TUNER5] {
                    pc = 320i64
                } else {
                    v[V_RADFAC] = v[V_INCFAC]
                }
            }
            pc = 320i64
        }
        if pc == 320i64 {
            let w = usize(iv[I_NWTSTP])
            let z = usize(iv[I_X0])
            l = usize(iv[I_LMAT])
            dw7zbf(v, l, n, step1, w, g01, z)
            dl7upd(v, temp1, step1, l, g01, l, n, w, z)
            iv[1usize] = 2i64
            pc = 90i64
        }
        if pc == 330i64 {
            iv[1usize] = 64i64
            pc = 350i64
        }
        if pc == 340i64 {
            iv[1usize] = iv[I_CNVCOD]
            iv[I_CNVCOD] = 0i64
            pc = 350i64
        }
        if pc == 350i64 { ret }
    }
}

// DRMNF: drmng with the gradient by finite differences (ds7grd); every return with iv(1) 1 or 2 wants f at x
fn drmnf(p: *Port) {
    let v = p.v
    let iv = p.iv
    let n = p.n
    let nn = i64(n)
    let iv1 = iv[1usize]
    var g1 = 0usize
    var pc = 0i64
    if iv1 == 1i64 {
        pc = 10i64
    } else if iv1 == 2i64 {
        pc = 50i64
    } else {
        if iv1 == 12i64 || iv1 == 13i64 { iv[I_VNEED] = iv[I_VNEED] + 2i64 * nn + 6i64 }
        if iv1 == 14i64 {
            pc = 10i64
        } else if iv1 > 2i64 && iv1 < 12i64 {
            pc = 10i64
        } else {
            g1 = 1usize
            if iv1 == 12i64 { iv[1usize] = 13i64 }
            pc = 20i64
        }
    }
    while true {
        if pc == 10i64 {
            g1 = usize(iv[I_G])
            pc = 20i64
        }
        if pc == 20i64 {
            drmng(p, g1)
            if iv[1usize] < 2i64 { ret }
            if iv[1usize] > 2i64 {
                pc = 70i64
            } else {
                if iv[I_NITER] == 0i64 { dv7scp(v, n, g1, 0.0f64) }
                var j = usize(iv[I_LMAT])
                var k = g1 - n
                var i = 1usize
                while i <= n {
                    v[k] = dd7tpr(v, i, j, j)
                    k += 1usize
                    j += i
                    i += 1usize
                }
                iv[I_NGCALL] = iv[I_NGCALL] - 1i64
                iv[I_SGIRC] = 0i64
                p.fx = v[V_F]
                pc = 60i64
            }
        }
        if pc == 50i64 {
            if iv[I_TOOBIG] != 0i64 { pc = 10i64 } else { pc = 60i64 }
        }
        if pc == 60i64 {
            g1 = usize(iv[I_G])
            let alpha = g1 - n
            ds7grd(p, alpha, g1, alpha - 6usize)
            if iv[I_SGIRC] == 0i64 {
                pc = 10i64
            } else {
                iv[I_NGCALL] = iv[I_NGCALL] + 1i64
                ret
            }
        }
        if pc == 70i64 {
            if iv[1usize] != 14i64 { ret }
            iv[I_G] = iv[I_NEXTV] + nn + 6i64
            iv[I_NEXTV] = iv[I_G] + nn
            if iv1 != 13i64 {
                pc = 10i64
            } else {
                ret
            }
        }
    }
}

// minimise f from par (the answer replaces it). ctl holds nlminb's control list in the order eval.max, iter.max, abs.tol, rel.tol, x.tol, xf.tol, step.min, step.max, sing.tol, a NaN
// (or a shorter list) leaving R's default (200, 150, 0, 1e-10, 1.5e-8, 2.2e-14, 1, 1, 1e-10). With use_gr the routine is drmng and gr(ctx, x, g) fills the gradient. R turns a NaN
// objective into Inf; a NaN gradient ends the run with code 99
fn nlminb[Ctx: type](a: *mem.Arena, c: *Ctx, f: fn(*Ctx, []const f64) -> f64, gr: fn(*Ctx, []const f64, []f64), use_gr: bool, par: []f64, ctl: []const f64) -> Nlminb {
    let n = par.len
    let liv = 78usize + 3usize * n
    let lv = 130usize + n * (n + 27usize) / 2usize
    let total = lv + 1usize + 3usize * n
    let (iv, e1) = mem.alloc[i64](a, liv + 1usize)
    let (v, e2) = mem.alloc[f64](a, total)
    var res = Nlminb { objective: 0.0f64 / 0.0f64, code: 0i64 - 1i64, iterations: 0usize, fevals: 0usize, gevals: 0usize }
    if e1 != ok || e2 != ok || n < 1usize { ret res }
    var i = 0usize
    while i <= liv {
        iv[i] = 0i64
        i += 1usize
    }
    i = 0usize
    while i < total {
        v[i] = 0.0f64
        i += 1usize
    }
    let me = machep()
    iv[1usize] = 12i64
    iv[I_LMAT] = 72i64
    iv[I_MXFCAL] = 200i64
    iv[I_MXITER] = 150i64
    iv[I_INITH] = 1i64
    v[V_AFCTOL] = 0.0f64
    v[V_DECFAC] = 0.5f64
    v[V_INCFAC] = 2.0f64
    v[V_LMAX0] = 1.0f64
    v[V_LMAXS] = 1.0f64
    v[V_RDFCMN] = 0.1f64
    v[V_RDFCMX] = 4.0f64
    v[V_RFCTOL] = 1.0e-10f64
    v[V_SCTOL] = 1.0e-10f64
    v[V_TUNER1] = 0.1f64
    v[V_TUNER2] = 1.0e-4f64
    v[V_TUNER3] = 0.75f64
    v[V_TUNER4] = 0.5f64
    v[V_TUNER5] = 0.75f64
    v[V_XCTOL] = math.sqrt[f64](me)
    v[V_XFTOL] = 100.0f64 * me
    v[V_BIAS] = 0.8f64
    v[V_DINIT] = 0.0f64 - 1.0f64
    v[V_ETA0] = 1000.0f64 * me
    if ctl.len > 0usize && ctl[0usize] == ctl[0usize] { iv[I_MXFCAL] = i64(ctl[0usize]) }
    if ctl.len > 1usize && ctl[1usize] == ctl[1usize] { iv[I_MXITER] = i64(ctl[1usize]) }
    if ctl.len > 2usize && ctl[2usize] == ctl[2usize] { v[V_AFCTOL] = ctl[2usize] }
    if ctl.len > 3usize && ctl[3usize] == ctl[3usize] { v[V_RFCTOL] = ctl[3usize] }
    if ctl.len > 4usize && ctl[4usize] == ctl[4usize] { v[V_XCTOL] = ctl[4usize] }
    if ctl.len > 5usize && ctl[5usize] == ctl[5usize] { v[V_XFTOL] = ctl[5usize] }
    if ctl.len > 6usize && ctl[6usize] == ctl[6usize] { v[V_LMAX0] = ctl[6usize] }
    if ctl.len > 7usize && ctl[7usize] == ctl[7usize] { v[V_LMAXS] = ctl[7usize] }
    if ctl.len > 8usize && ctl[8usize] == ctl[8usize] { v[V_SCTOL] = ctl[8usize] }
    let d0 = lv + 1usize
    let x0 = d0 + n
    let g0 = x0 + n
    i = 0usize
    while i < n {
        v[d0 + i] = 1.0f64
        v[x0 + i] = par[i]
        i += 1usize
    }
    var p = Port { iv: iv, v: v, n: n, fx: 1.0f64 / 0.0f64, d0: d0, x0: x0 }
    var go = true
    while go {
        if use_gr { drmng(&p, g0) } else { drmnf(&p) }
        let code = iv[1usize]
        if code >= 3i64 {
            go = false
        } else if use_gr && code == 2i64 {
            gr(c, v[x0..x0 + n], v[g0..g0 + n])
            i = 0usize
            while i < n {
                if v[g0 + i] != v[g0 + i] {
                    iv[1usize] = 99i64
                    go = false
                }
                i += 1usize
            }
        } else {
            var fx = f(c, v[x0..x0 + n])
            if fx != fx { fx = 1.0f64 / 0.0f64 }
            p.fx = fx
        }
    }
    i = 0usize
    while i < n {
        par[i] = v[x0 + i]
        i += 1usize
    }
    res.objective = v[V_F]
    res.code = iv[1usize]
    res.iterations = usize(iv[I_NITER])
    res.fevals = usize(iv[I_NFCALL])
    res.gevals = usize(iv[I_NGCALL])
    ret res
}
