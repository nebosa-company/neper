// R lmom `lmrq`: the L-moments (and trimmed L-moments) of a distribution from its quantile function by adaptive quadrature (QUADPACK's qags, the code lmom's
// own integrate() calls), for the quantile function of any of the lmomfull distribution kinds. The shifted Jacobi polynomials sjp, slp and sjp11 are lmom's.

use e.algo.stat.ksamples_steel as ks
use e.algo.stat.lmomfull as lf
use e.math
use e.math.nmath as nm
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// slp(u, m): the shifted Legendre polynomial
fn slp(u: f64, m: usize) -> f64 {
    if m == 0usize { ret 1.0f64 }
    if m == 1usize { ret 2.0f64 * u - 1.0f64 }
    if m == 2usize { ret 1.0f64 - 6.0f64 * u * (1.0f64 - u) }
    if m == 3usize { ret (1.0f64 - 10.0f64 * u * (1.0f64 - u)) * (2.0f64 * u - 1.0f64) }
    let z = u * (1.0f64 - u)
    if m == 4usize { ret 1.0f64 - z * (20.0f64 - 70.0f64 * z) }
    if m == 5usize { ret (1.0f64 - z * (28.0f64 - 126.0f64 * z)) * (2.0f64 * u - 1.0f64) }
    if m == 6usize { ret 1.0f64 - z * (42.0f64 - z * (378.0f64 - 924.0f64 * z)) }
    let x = 2.0f64 * u - 1.0f64
    var px = (1.0f64 - z * (28.0f64 - 126.0f64 * z)) * x
    var p = 1.0f64 - z * (42.0f64 - z * (378.0f64 - 924.0f64 * z))
    var r = 7usize
    while r <= m {
        let pxx = px
        px = p
        p = ((2.0f64 * f64(r) - 1.0f64) * x * px - (f64(r) - 1.0f64) * pxx) / f64(r)
        r += 1usize
    }
    ret p
}

fn sjp11(u: f64, m: usize) -> f64 {
    if m == 0usize { ret 1.0f64 }
    if m == 1usize { ret 2.0f64 * (2.0f64 * u - 1.0f64) }
    if m == 2usize { ret 3.0f64 * (1.0f64 - 5.0f64 * u * (1.0f64 - u)) }
    if m == 3usize { ret 4.0f64 * ((1.0f64 - 7.0f64 * u * (1.0f64 - u)) * (2.0f64 * u - 1.0f64)) }
    let z = u * (1.0f64 - u)
    if m == 4usize { ret 5.0f64 * (1.0f64 - z * (14.0f64 - 42.0f64 * z)) }
    if m == 5usize { ret 6.0f64 * ((1.0f64 - z * (18.0f64 - 66.0f64 * z)) * (2.0f64 * u - 1.0f64)) }
    if m == 6usize { ret 7.0f64 * (1.0f64 - z * (27.0f64 - z * (198.0f64 - 429.0f64 * z))) }
    let x = 2.0f64 * u - 1.0f64
    var px = (1.0f64 - z * (18.0f64 - 66.0f64 * z)) * x
    var p = 1.0f64 - z * (27.0f64 - z * (198.0f64 - 429.0f64 * z))
    var r = 7usize
    while r <= m {
        let pxx = px
        px = p
        p = ((2.0f64 * f64(r) + 1.0f64) * x * px - (f64(r) - 1.0f64) * pxx) / f64(r + 2usize)
        r += 1usize
    }
    ret p * f64(m + 1usize)
}

// sjp(u, m, a, b): the shifted Jacobi polynomial
fn sjp(u: f64, m: usize, a: f64, b: f64) -> f64 {
    if a == 0.0f64 && b == 0.0f64 { ret slp(u, m) }
    if a == 1.0f64 && b == 1.0f64 { ret sjp11(u, m) }
    var px = 1.0f64
    if m == 0usize { ret px }
    var p = (a + b + 2.0f64) * u - (1.0f64 + b)
    if m == 1usize { ret p }
    var r = 1usize
    while r <= m - 1usize {
        let pxx = px
        px = p
        let rf = f64(r)
        let rrab = rf + rf + a + b
        let aa = (rrab + 1.0f64) * (rrab + 2.0f64)
        let bb = (0.0f64 - 1.0f64) * (rrab + 1.0f64) * (2.0f64 * rf * (rf + 1.0f64) + (rf + rf + b + 1.0f64) * (a + b)) / rrab
        let cc = (rf + a) * (rf + b) * (rrab + 2.0f64) / rrab
        p = ((aa * u + bb) * px - cc * pxx) / ((rf + 1.0f64) * (rf + a + b + 1.0f64))
        r += 1usize
    }
    ret p
}

type QCtx = struct {
    kind: i32,
    para: [5]f64,
    med: f64,
    shift: bool,
    t1: f64,
    t2: f64,
    r: usize,
    mode: i32,
}

fn qval(c: *QCtx, u: f64) -> f64 {
    var v = lf.quax(c.kind, u, c.para[0usize..5usize])
    if c.shift { v = v - c.med }
    ret v
}

// mode 0: the lambda_2 integrand, 1: the lambda_1 integrand, 2: the order-r integrand
fn integrand(c: *QCtx, u: f64) -> f64 {
    let w = math.pow[f64](u, c.t1) * math.pow[f64](1.0f64 - u, c.t2)
    if c.mode == 0i32 { ret qval(c, u) * w * ((1.0f64 + c.t2) * u - (1.0f64 + c.t1) * (1.0f64 - u)) }
    if c.mode == 1i32 { ret qval(c, u) * w }
    ret qval(c, u) * w * sjp(u, c.r - 1usize, c.t2, c.t1)
}

fn mult_of(r: usize, t1: f64, t2: f64) -> f64 {
    let rf = f64(r)
    ret math.exp[f64](nm.lgammafn(rf) + nm.lgammafn(rf + t1 + t2 + 1.0f64) - nm.lgammafn(rf + t1) - nm.lgammafn(rf + t2)) / rf
}

fn fmax(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

// lmrq(qfunc of `kind` at para, symm, order = 1:maxord, ratios, trim = c(t1, t2), acc, subdiv): val[0 .. maxord] the (trimmed) L-moments or ratios, err the absolute error estimates;
// all NaN when lambda_2 comes out negative. The quantile function is lmomfull.quax at para (up to 5 parameters).
fn lmrq(a: *mem.Arena, kind: i32, para: []const f64, symm: bool, maxord: usize, ratios: bool, t1: f64, t2: f64, acc: f64, subdiv: usize, val: []f64, errv: []f64) -> err {
    var pz: [5]f64 = zero
    var c = QCtx { kind: kind, para: pz, med: 0.0f64, shift: false, t1: t1, t2: t2, r: 0usize, mode: 0i32 }
    var i = 0usize
    while i < para.len {
        c.para[i] = para[i]
        i += 1usize
    }
    var nn = maxord
    if nn < 2usize { nn = 2usize }
    i = 0usize
    while i < nn {
        val[i] = 0.0f64
        errv[i] = 0.0f64
        i += 1usize
    }
    let allsymm = symm && t1 == t2
    var upper = 1.0f64
    if allsymm {
        upper = 0.5f64
        c.med = lf.quax(kind, 0.5f64, c.para[0usize..5usize])
        c.shift = true
        val[0usize] = c.med
    }
    c.mode = 0i32
    let (int2, e1) = ks.qags[QCtx](a, &c, integrand, 0.0f64, upper, 0.0f64, acc / 2.0f64, subdiv)
    if e1 != ok { ret e1 }
    let m2 = mult_of(2usize, t1, t2)
    var denom = int2.result * m2
    let errdenom = int2.abserr * m2
    if denom < 0.0f64 && denom > 0.0f64 - errdenom { denom = 0.0f64 }
    val[1usize] = denom
    errv[1usize] = errdenom
    if allsymm {
        val[1usize] = 2.0f64 * denom
        errv[1usize] = 2.0f64 * errdenom
    }
    if denom < 0.0f64 {
        i = 0usize
        while i < nn {
            val[i] = nan()
            errv[i] = nan()
            i += 1usize
        }
        ret ok
    }
    if !allsymm {
        c.mode = 1i32
        let (int1, e2) = ks.qags[QCtx](a, &c, integrand, 0.0f64, 1.0f64, fmax(denom * acc / 2.0f64, errdenom), 0.0f64, subdiv)
        if e2 != ok { ret e2 }
        val[0usize] = int1.result * mult_of(1usize, t1, t2)
        errv[0usize] = int1.abserr * mult_of(1usize, t1, t2)
    }
    if int2.ier == 0i64 && math.abs[f64](denom) <= errv[1usize] {
        i = 2usize
        while i < maxord {
            if ratios {
                val[i] = nan()
                errv[i] = nan()
            } else {
                val[i] = 0.0f64
                errv[i] = nan()
            }
            i += 1usize
        }
        ret ok
    }
    var r = 3usize
    while r <= maxord {
        if !allsymm || r % 2usize == 0usize {
            c.mode = 2i32
            c.r = r
            let (ir, e3) = ks.qags[QCtx](a, &c, integrand, 0.0f64, upper, denom * acc / 2.0f64, 0.0f64, subdiv)
            if e3 != ok { ret e3 }
            val[r - 1usize] = ir.result * mult_of(r, t1, t2)
            errv[r - 1usize] = ir.abserr * mult_of(r, t1, t2)
            if allsymm {
                val[r - 1usize] = 2.0f64 * val[r - 1usize]
                errv[r - 1usize] = 2.0f64 * errv[r - 1usize]
            }
            if ratios {
                val[r - 1usize] = val[r - 1usize] / val[1usize]
                errv[r - 1usize] = (errv[r - 1usize] + math.abs[f64](val[r - 1usize]) * errv[1usize]) / val[1usize]
            }
        }
        r += 1usize
    }
    ret ok
}
