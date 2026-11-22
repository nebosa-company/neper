// R locfit's confidence bands for one predictor: the tube-formula critical value crit() (gaussian and t process,
// two-sided) and the tube constant kappa0 of a local fit, ported from the package's C source (scb_crit.c, scb_cons.c,
// scb.c, prob.c and dbinom.c), so scb() gives the same simultaneous band. The fits themselves are e.algo.stat.locfitpkg.
//
// Not here: more than one predictor, the unif process, the corrected bands (type 2 to 5) and the likelihood bands,
// kernels without a derivative of the weight function (quqt, 6cub, minimax), Monte Carlo and the other integrators.

use e.math
use e.math.nmath as nm
use e.mem
use e.algo.stat.locfitpkg as lf

fn halves(i: usize) -> f64 {
    let t = [31]f64{
        0.0f64, 0.1534264097200273452913848f64, 0.0810614667953272582196702f64, 0.0548141210519176538961390f64,
        0.0413406959554092940938221f64, 0.03316287351993628748511048f64, 0.02767792568499833914878929f64,
        0.02374616365629749597132920f64, 0.02079067210376509311152277f64, 0.01848845053267318523077934f64,
        0.01664469118982119216319487f64, 0.01513497322191737887351255f64, 0.01387612882307074799874573f64,
        0.01281046524292022692424986f64, 0.01189670994589177009505572f64, 0.01110455975820691732662991f64,
        0.010411265261972096497478567f64, 0.009799416126158803298389475f64, 0.009255462182712732917728637f64,
        0.008768700134139385462952823f64, 0.008330563433362871256469318f64, 0.007934114564314020547248100f64,
        0.007573675487951840794972024f64, 0.007244554301320383179543912f64, 0.006942840107209529865664152f64,
        0.006665247032707682442354394f64, 0.006408994188004207068439631f64, 0.006171712263039457647532867f64,
        0.005951370112758847735624416f64, 0.005746216513010115682023589f64, 0.005554733551962801371038690f64
    }
    ret t[i]
}

// log(n!) - log(sqrt(2 pi n) (n/e)^n)
fn stirlerr(n: f64) -> f64 {
    if n < 15.0f64 {
        let nn = 2.0f64 * n
        if nn == math.floor[f64](nn) { ret halves(usize(nn)) }
        ret nm.lgammafn(n + 1.0f64) - (n + 0.5f64) * math.log[f64](n) + n - 0.918938533204672741780329736406f64
    }
    let s0 = 0.083333333333333333333f64
    let s1 = 0.00277777777777777777778f64
    let s2 = 0.00079365079365079365079365f64
    let s3 = 0.000595238095238095238095238f64
    let s4 = 0.0008417508417508417508417508f64
    let nn = n * n
    if n > 500.0f64 { ret (s0 - s1 / nn) / n }
    if n > 80.0f64 { ret (s0 - (s1 - s2 / nn) / nn) / n }
    if n > 35.0f64 { ret (s0 - (s1 - (s2 - s3 / nn) / nn) / nn) / n }
    ret (s0 - (s1 - (s2 - (s3 - s4 / nn) / nn) / nn) / nn) / n
}

fn bd0(x: f64, np: f64) -> f64 {
    if math.abs[f64](x - np) < 0.1f64 * (x + np) {
        var s = (x - np) * (x - np) / (x + np)
        var v = (x - np) / (x + np)
        var ej = 2.0f64 * x * v
        v = v * v
        var j = 1usize
        var go = true
        while go {
            ej = ej * v
            let s1 = s + ej / f64(2usize * j + 1usize)
            if s1 == s { ret s1 }
            s = s1
            j += 1usize
        }
    }
    ret x * math.log[f64](x / np) + np - x
}

fn d0(lg: bool) -> f64 {
    if lg { ret 0.0f64 - 1.0e100f64 }
    ret 0.0f64
}

fn d1(lg: bool) -> f64 {
    if lg { ret 0.0f64 }
    ret 1.0f64
}

fn dexp(x: f64, lg: bool) -> f64 {
    if lg { ret x }
    ret math.exp[f64](x)
}

fn fexp(f: f64, x: f64, lg: bool) -> f64 {
    if lg { ret 0.0f64 - 0.5f64 * math.log[f64](f) + x }
    ret math.exp[f64](x) / math.sqrt[f64](f)
}

fn dbinom_raw(x: f64, n: f64, p: f64, q: f64, lg: bool) -> f64 {
    if p == 0.0f64 {
        if x == 0.0f64 { ret d1(lg) }
        ret d0(lg)
    }
    if q == 0.0f64 {
        if x == n { ret d1(lg) }
        ret d0(lg)
    }
    if x == 0.0f64 {
        var lc = n * math.log[f64](q)
        if p < 0.1f64 { lc = 0.0f64 - bd0(n, n * q) - n * p }
        ret dexp(lc, lg)
    }
    if x == n {
        var lc = n * math.log[f64](p)
        if q < 0.1f64 { lc = 0.0f64 - bd0(n, n * p) - n * q }
        ret dexp(lc, lg)
    }
    if x < 0.0f64 || x > n { ret d0(lg) }
    let lc = stirlerr(n) - stirlerr(x) - stirlerr(n - x) - bd0(x, n * p) - bd0(n - x, n * q)
    let f = (6.283185307179586476925286f64 * x * (n - x)) / n
    ret fexp(f, lc, lg)
}

fn dpois_raw(x: f64, lambda: f64, lg: bool) -> f64 {
    if lambda == 0.0f64 {
        if x == 0.0f64 { ret d1(lg) }
        ret d0(lg)
    }
    if x == 0.0f64 { ret dexp(0.0f64 - lambda, lg) }
    if x < 0.0f64 { ret d0(lg) }
    ret fexp(6.283185307179586476925286f64 * x, 0.0f64 - stirlerr(x) - bd0(x, lambda), lg)
}

fn dbeta(x: f64, a: f64, b: f64, lg: bool) -> f64 {
    if a <= 0.0f64 || b <= 0.0f64 { ret 0.0f64 }
    if x <= 0.0f64 || x >= 1.0f64 { ret d0(lg) }
    var f = 0.0f64
    var p = 0.0f64
    if a < 1.0f64 {
        if b < 1.0f64 {
            f = a * b / ((a + b) * x * (1.0f64 - x))
            p = dbinom_raw(a, a + b, x, 1.0f64 - x, lg)
        } else {
            f = a / x
            p = dbinom_raw(a, a + b - 1.0f64, x, 1.0f64 - x, lg)
        }
    } else {
        if b < 1.0f64 {
            f = b / (1.0f64 - x)
            p = dbinom_raw(a - 1.0f64, a + b - 1.0f64, x, 1.0f64 - x, lg)
        } else {
            f = a + b - 1.0f64
            p = dbinom_raw(a - 1.0f64, (a - 1.0f64) + (b - 1.0f64), x, 1.0f64 - x, lg)
        }
    }
    if lg { ret p + math.log[f64](f) }
    ret p * f
}

fn df(x: f64, m: f64, n: f64, lg: bool) -> f64 {
    if m <= 0.0f64 || n <= 0.0f64 { ret 0.0f64 }
    if x <= 0.0f64 { ret d0(lg) }
    var f = 1.0f64 / (n + x * m)
    let q = n * f
    let p = x * m * f
    var dens = 0.0f64
    if m >= 2.0f64 {
        f = m * q / 2.0f64
        dens = dbinom_raw((m - 2.0f64) / 2.0f64, (m + n - 2.0f64) / 2.0f64, p, q, lg)
    } else {
        f = m * m * q / (2.0f64 * p * (m + n))
        dens = dbinom_raw(m / 2.0f64, (m + n) / 2.0f64, p, q, lg)
    }
    if lg { ret math.log[f64](f) + dens }
    ret f * dens
}

fn dgamma(x: f64, r: f64, lambda: f64, lg: bool) -> f64 {
    if r <= 0.0f64 || lambda < 0.0f64 { ret 0.0f64 }
    if x <= 0.0f64 { ret d0(lg) }
    if r < 1.0f64 {
        let pr = dpois_raw(r, lambda * x, lg)
        if lg { ret pr + math.log[f64](r / x) }
        ret pr * r / x
    }
    let pr = dpois_raw(r - 1.0f64, lambda * x, lg)
    if lg { ret pr + math.log[f64](lambda) }
    ret lambda * pr
}

fn dchisq(x: f64, dfree: f64, lg: bool) -> f64 { ret dgamma(x, dfree / 2.0f64, 0.5f64, lg) }

// the regularised incomplete beta function, continued fraction
fn ibeta(x0: f64, a0: f64, b0: f64) -> f64 {
    if x0 <= 0.0f64 { ret 0.0f64 }
    if x0 >= 1.0f64 { ret 1.0f64 }
    var x = x0
    var a = a0
    var b = b0
    var flipped = false
    if (a + b + 1.0f64) * x > (a + 1.0f64) {
        flipped = true
        let t = a
        a = b
        b = t
        x = 1.0f64 - x
    }
    var pna = [6]f64{ 0.0f64, 1.0f64, 1.0f64, 1.0f64, 0.0f64, 0.0f64 }
    let pn = pna[0usize..6usize]
    var count = 1usize
    let val = x / (1.0f64 - x)
    let bk = 1.0f64
    var next = 1.0f64
    var prev = 0.0f64
    var go = true
    while go {
        count += 1usize
        let k = f64(count / 2usize)
        prev = next
        var ak = 0.0f64
        if count % 2usize == 0usize {
            ak = 0.0f64 - ((a + k - 1.0f64) * (b - k) * val) / ((a + 2.0f64 * k - 2.0f64) * (a + 2.0f64 * k - 1.0f64))
        } else {
            ak = ((a + b + k - 1.0f64) * k * val) / ((a + 2.0f64 * k) * (a + 2.0f64 * k - 1.0f64))
        }
        pn[4usize] = bk * pn[2usize] + ak * pn[0usize]
        pn[5usize] = bk * pn[3usize] + ak * pn[1usize]
        next = pn[4usize] / pn[5usize]
        var i = 0usize
        while i <= 3usize {
            pn[i] = pn[i + 2usize]
            i += 1usize
        }
        if math.abs[f64](pn[4usize]) >= 1.0e30f64 {
            i = 0usize
            while i <= 3usize {
                pn[i] = pn[i] / 1.0e30f64
                i += 1usize
            }
        }
        if math.abs[f64](pn[4usize]) <= 1.0e-30f64 {
            i = 0usize
            while i <= 3usize {
                pn[i] = pn[i] / 1.0e-30f64
                i += 1usize
            }
        }
        go = math.abs[f64](next - prev) > 2.2204460492503131e-16f64 * prev
    }
    let factor = dbeta(x, a, b, true) + math.log[f64](x / a)
    let r = math.exp[f64](factor) * next
    if flipped { ret 1.0f64 - r }
    ret r
}

// int_0^x u^(df-1) e^-u du / Gamma(df)
fn igamma(x: f64, dfree: f64) -> f64 {
    if x <= 0.0f64 { ret 0.0f64 }
    if dfree < 1.0f64 { ret dgamma(x, dfree + 1.0f64, 1.0f64, false) + igamma(x, dfree + 1.0f64) }
    let factor = x * dgamma(x, dfree, 1.0f64, false)
    let ep = 2.2204460492503131e-16f64
    var gint = 0.0f64
    if x > 1.0f64 && x >= dfree {
        var pna = [6]f64{ 0.0f64, 1.0f64, 1.0f64, x, 0.0f64, 0.0f64 }
        let pn = pna[0usize..6usize]
        var count = 1usize
        var rn = 1.0f64 / x
        var go = true
        while go {
            count += 1usize
            let k = count / 2usize
            gint = rn
            var bk = x
            var ak = f64(k)
            if count % 2usize == 0usize {
                bk = 1.0f64
                ak = f64(k) - dfree
            }
            pn[4usize] = bk * pn[2usize] + ak * pn[0usize]
            pn[5usize] = bk * pn[3usize] + ak * pn[1usize]
            rn = pn[4usize] / pn[5usize]
            var i = 0usize
            while i < 4usize {
                pn[i] = pn[i + 2usize]
                i += 1usize
            }
            if pn[4usize] > 1.0e30f64 {
                i = 0usize
                while i < 4usize {
                    pn[i] = pn[i] / 1.0e30f64
                    i += 1usize
                }
            }
            go = math.abs[f64](gint - rn) > ep * rn
        }
        gint = 1.0f64 - factor * rn
    } else {
        gint = 1.0f64
        var term = 1.0f64
        var rn = dfree
        var go = true
        while go {
            rn += 1.0f64
            term = term * x / rn
            gint += term
            go = term > ep * gint
        }
        gint = gint * factor / dfree
    }
    ret gint
}

fn pchisq(x: f64, dfree: f64) -> f64 { ret igamma(x / 2.0f64, dfree / 2.0f64) }

fn pf(q: f64, df1: f64, df2: f64) -> f64 { ret ibeta(q * df1 / (df2 + q * df1), df1 / 2.0f64, df2 / 2.0f64) }

// the surface area of the unit sphere in R^d, d < 10
fn area(d: usize) -> f64 {
    let t = [10]f64{
        1.0f64, 2.0f64, 6.2831853071795864770f64, 12.566370614359172954f64, 19.739208802178717238f64,
        26.318945069571622985f64, 31.006276680299820177f64, 33.073361792319808190f64, 32.469697011334145747f64,
        29.686580124648361825f64
    }
    ret t[d]
}

// the two-sided tail probability (tproc: the t process with nu degrees of freedom, else gaussian)
fn tailp(c: f64, k0: []const f64, m: usize, d: usize, nu: f64, tproc: bool) -> f64 {
    var p = 0.0f64
    var i = 0usize
    while i < m {
        if k0[i] != 0.0f64 {
            let dd = f64(d + 1usize - i)
            if tproc {
                p += k0[i] * (1.0f64 - pf(c * c / dd, dd, nu)) / area(d + 1usize - i)
            } else {
                p += k0[i] * (1.0f64 - pchisq(c * c, dd)) / area(d + 1usize - i)
            }
        }
        i += 1usize
    }
    ret 2.0f64 * p
}

// the derivative in c of the tail probability
fn taild(c: f64, k0: []const f64, m: usize, d: usize, nu: f64, tproc: bool) -> f64 {
    var p = 0.0f64
    var i = 0usize
    while i < m {
        if k0[i] != 0.0f64 {
            let dd = f64(d + 1usize - i)
            if tproc {
                p += k0[i] * 2.0f64 * c * df(c * c / dd, dd, nu, false) / (dd * area(d + 1usize - i))
            } else {
                p += k0[i] * 2.0f64 * c * dchisq(c * c, dd, false) / area(d + 1usize - i)
            }
        }
        i += 1usize
    }
    ret 2.0f64 * p
}

// crit(): the critical value of a two-sided simultaneous band at level alpha from the tube constants k0[0..m]
// for d predictors; rdf > 0 uses the t process. Newton with bisection safeguards, as the package.
fn critval(alpha: f64, k0: []const f64, m0: usize, d: usize, nu: f64) -> f64 {
    var m = m0
    if m > d + 1usize { m = d + 1usize }
    var one = [1]f64{ 1.0f64 }
    var dd = d
    var kk = k0
    if m == 0usize {
        dd = 0usize
        kk = one[0usize..1usize]
        m = 1usize
    }
    let tproc = nu != 0.0f64
    var c = 2.0f64
    var c0 = 0.0f64
    var c1 = 0.0f64
    var j = 0usize
    while j < 20usize {
        let tp = tailp(c, kk, m, dd, nu, tproc) - alpha
        let td = taild(c, kk, m, dd, nu, tproc)
        if tp > 0.0f64 { c0 = c }
        if tp < 0.0f64 { c1 = c }
        var cn = c + tp / td
        if cn < c0 { cn = (c + c0) / 2.0f64 }
        if c1 > 0.0f64 && cn > c1 { cn = (c + c1) / 2.0f64 }
        c = cn
        if math.abs[f64](tp / alpha) < 1.0e-10f64 { ret c }
        j += 1usize
    }
    ret c
}

// the tube constant k0 of the fit sp over the data range, by Simpson's rule on mg intervals (rounded up to even):
// the integral of ||l'(x) orthogonal to l(x)|| / ||l(x)|| for the weight diagram l(x) of the local fit at x
error InvalidKernel

fn kappa0(a: *mem.Arena, x: []const f64, y: []const f64, sp: []const f64, pc: *lf.Pc, mg0: usize) -> (f64, err) {
    // R's Wd, which the tube constant differentiates, is defined for epan, bisq, tcub, triw and gauss only
    let kn = usize(sp[0usize])
    if kn != 2usize && kn != 3usize && kn != 4usize && kn != 5usize && kn != 6usize { ret (0.0f64, InvalidKernel) }
    let n = x.len
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 1usize
    while i < n {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    var mg = mg0
    if mg % 2usize == 1usize { mg += 1usize }
    let delta = (hi - lo) / (3.0f64 * f64(mg))
    var out = [17]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    let o = out[0usize..17usize]
    var dt = [1]f64{ 0.0f64 }
    let det = dt[0usize..1usize]
    var sum = 0.0f64
    var k = 0usize
    while k <= mg {
        var xv = lo
        if k > 0usize { xv = lo + 3.0f64 * delta * f64(k) }
        let start = mem.mark(a)
        let e = lf.vertex(a, x, y, sp, pc, xv, o, det)
        mem.reset(a, start)
        if e != ok { ret (0.0f64, e) }
        var wt = 4.0f64
        if k % 2usize == 0usize { wt -= 2.0f64 }
        if k == 0usize { wt -= 1.0f64 }
        if k == mg { wt -= 1.0f64 }
        sum += wt * det[0usize]
        k += 1usize
    }
    ret (sum * delta, ok)
}
