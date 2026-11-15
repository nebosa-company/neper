// R's gamma-family building blocks and distributions, ported from nmath: `gammafn` and `lgammafn`
// (Chebyshev series, Stirling's error), `lgamma1p`, `log1pmx`, `bd0` and `ebd0` (the deviance term
// of the saddle-point density, with Welinder's table), `dpois_raw`, and the d and p functions of
// the gamma, chi-squared and Poisson distributions with `lower_tail` and `log_p` (pgamma's small-x
// series, upper series, continued fractions and the asymptotic expansion). Generated from
// scripts/nmath_template.e.txt, with the coefficient tables copied out of the C by
// scripts/gen_nmath.py.
//
// Not here: gamma and lgamma of a complex argument, the warnings R prints; the q functions are
// in e.math.nmath_q.

use e.math
use e.math.dist as dist
use e.math.nmath_tables as tables
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn inf() -> f64 { ret 1.0f64 / 0.0f64 }

fn finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn max2(a: f64, b: f64) -> f64 {
    if a != a || b != b { ret a + b }
    if a < b { ret b }
    ret a
}

// 2^n for a whole n.
fn pow2(n: i64) -> f64 {
    var m = n
    var r = 1.0f64
    while m > 1000i64 {
        r = r * 1.0715086071862673e301f64
        m -= 1000i64
    }
    while m < -1000i64 {
        r = r * 9.332636185032189e-302f64
        m += 1000i64
    }
    ret r * mem.bitcast[f64](u64(m + 1023i64) << 52u64)
}

fn ldexp(x: f64, n: i64) -> f64 {
    if n > 1000i64 { ret ldexp(x * pow2(1000i64), n - 1000i64) }
    if n < -1000i64 { ret ldexp(x * pow2(-1000i64), n + 1000i64) }
    ret x * pow2(n)
}

// frexp: (r, e) with x = r * 2^e and r in [0.5, 1).
fn frexp(x: f64) -> (f64, i64) {
    if x == 0.0f64 || !finite(x) { ret (x, 0i64) }
    let bits = mem.bitcast[u64](x)
    let be = i64((bits >> 52u64) & 2047u64)
    if be == 0i64 {
        let (r, e) = frexp(x * 18014398509481984.0f64)
        ret (r, e - 54i64)
    }
    let r = mem.bitcast[f64]((bits & 9227875636482146303u64) | (u64(1022i64) << 52u64))
    ret (r, be - 1022i64)
}

fn sinpi(x0: f64) -> f64 {
    var x = x0 - 2.0f64 * math.trunc[f64](x0 / 2.0f64)
    if x <= -1.0f64 { x += 2.0f64 } else if x > 1.0f64 { x -= 2.0f64 }
    if x == 0.0f64 || x == 1.0f64 { ret 0.0f64 }
    if x == 0.5f64 { ret 1.0f64 }
    if x == -0.5f64 { ret -1.0f64 }
    ret math.sin[f64](3.141592653589793238462643383280f64 * x)
}

fn chebyshev_eval(x: f64, a: []const f64, n: usize) -> f64 {
    let twox = x * 2.0f64
    var b2 = 0.0f64
    var b1 = 0.0f64
    var b0 = 0.0f64
    var i = 1usize
    while i <= n {
        b2 = b1
        b1 = b0
        b0 = twox * b1 - b2 + a[n - i]
        i += 1usize
    }
    ret (b0 - b2) * 0.5f64
}

// --- Stirling's error, lgammacor, gamma, lgamma

fn lgammacor(x: f64) -> f64 {
    var a: [5]f64 = zero
    a[0usize] = 0.1666389480451863247205729650822e+0f64
    a[1usize] = -0.1384948176067563840732986059135e-4f64
    a[2usize] = 0.9810825646924729426157171547487e-8f64
    a[3usize] = -0.1809129475572494194263306266719e-10f64
    a[4usize] = 0.6221098041892605227126015543416e-13f64
    if x < 10.0f64 { ret nan() }
    if x < 94906265.62425156f64 {
        let tmp = 10.0f64 / x
        ret chebyshev_eval(tmp * tmp * 2.0f64 - 1.0f64, a[0usize..5usize], 5usize) / x
    }
    ret 1.0f64 / (x * 12.0f64)
}

fn stirlerr(n: f64) -> f64 {
    let s0 = 0.083333333333333333333f64
    let s1 = 0.00277777777777777777778f64
    let s2 = 0.00079365079365079365079365f64
    let s3 = 0.000595238095238095238095238f64
    let s4 = 0.0008417508417508417508417508f64
    let s5 = 0.0019175269175269175269175262f64
    let s6 = 0.0064102564102564102564102561f64
    let s7 = 0.029550653594771241830065352f64
    let s8 = 0.17964437236883057316493850f64
    let s9 = 1.3924322169059011164274315f64
    let s10 = 13.402864044168391994478957f64
    let s11 = 156.84828462600201730636509f64
    let s12 = 2193.1033333333333333333333f64
    let s13 = 36108.771253724989357173269f64
    let s14 = 691472.26885131306710839498f64
    let s15 = 15238221.539407416192283370f64
    let s16 = 382900751.39141414141414141f64
    if n <= 23.5f64 {
        var nn = n + n
        if n <= 15.0f64 && nn == f64(i64(nn)) {
            var t: [31]f64 = zero
            t[0usize] = 0.0f64
            t[1usize] = 0.1534264097200273452913848f64
            t[2usize] = 0.0810614667953272582196702f64
            t[3usize] = 0.0548141210519176538961390f64
            t[4usize] = 0.0413406959554092940938221f64
            t[5usize] = 0.03316287351993628748511048f64
            t[6usize] = 0.02767792568499833914878929f64
            t[7usize] = 0.02374616365629749597132920f64
            t[8usize] = 0.02079067210376509311152277f64
            t[9usize] = 0.01848845053267318523077934f64
            t[10usize] = 0.01664469118982119216319487f64
            t[11usize] = 0.01513497322191737887351255f64
            t[12usize] = 0.01387612882307074799874573f64
            t[13usize] = 0.01281046524292022692424986f64
            t[14usize] = 0.01189670994589177009505572f64
            t[15usize] = 0.01110455975820691732662991f64
            t[16usize] = 0.010411265261972096497478567f64
            t[17usize] = 0.009799416126158803298389475f64
            t[18usize] = 0.009255462182712732917728637f64
            t[19usize] = 0.008768700134139385462952823f64
            t[20usize] = 0.008330563433362871256469318f64
            t[21usize] = 0.007934114564314020547248100f64
            t[22usize] = 0.007573675487951840794972024f64
            t[23usize] = 0.007244554301320383179543912f64
            t[24usize] = 0.006942840107209529865664152f64
            t[25usize] = 0.006665247032707682442354394f64
            t[26usize] = 0.006408994188004207068439631f64
            t[27usize] = 0.006171712263039457647532867f64
            t[28usize] = 0.005951370112758847735624416f64
            t[29usize] = 0.005746216513010115682023589f64
            t[30usize] = 0.005554733551962801371038690f64
            ret t[usize(i64(nn))]
        }
        if n <= 5.25f64 {
            if n >= 1.0f64 {
                let l_n = math.log[f64](n)
                ret lgammafn(n) + n * (1.0f64 - l_n) + (l_n - 1.837877066409345483560659472811f64) / 2.0f64
            }
            ret lgamma1p(n) - (n + 0.5f64) * math.log[f64](n) + n - 0.918938533204672741780329736406f64
        }
        nn = n * n
        if n > 12.8f64 { ret (s0 - (s1 - (s2 - (s3 - (s4 - (s5 - s6 / nn) / nn) / nn) / nn) / nn) / nn) / n }
        if n > 12.3f64 { ret (s0 - (s1 - (s2 - (s3 - (s4 - (s5 - (s6 - s7 / nn) / nn) / nn) / nn) / nn) / nn) / nn) / n }
        if n > 8.9f64 { ret (s0 - (s1 - (s2 - (s3 - (s4 - (s5 - (s6 - (s7 - s8 / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / n }
        if n > 7.3f64 { ret (s0 - (s1 - (s2 - (s3 - (s4 - (s5 - (s6 - (s7 - (s8 - (s9 - s10 / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / n }
        if n > 6.6f64 { ret (s0 - (s1 - (s2 - (s3 - (s4 - (s5 - (s6 - (s7 - (s8 - (s9 - (s10 - (s11 - s12 / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / n }
        if n > 6.1f64 { ret (s0 - (s1 - (s2 - (s3 - (s4 - (s5 - (s6 - (s7 - (s8 - (s9 - (s10 - (s11 - (s12 - (s13 - s14 / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / n }
        ret (s0 - (s1 - (s2 - (s3 - (s4 - (s5 - (s6 - (s7 - (s8 - (s9 - (s10 - (s11 - (s12 - (s13 - (s14 - (s15 - s16 / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / nn) / n
    }
    let nn = n * n
    if n > 15.7e6f64 { ret s0 / n }
    if n > 6180.0f64 { ret (s0 - s1 / nn) / n }
    if n > 205.0f64 { ret (s0 - (s1 - s2 / nn) / nn) / n }
    if n > 86.0f64 { ret (s0 - (s1 - (s2 - s3 / nn) / nn) / nn) / n }
    if n > 27.0f64 { ret (s0 - (s1 - (s2 - (s3 - s4 / nn) / nn) / nn) / nn) / n }
    ret (s0 - (s1 - (s2 - (s3 - (s4 - s5 / nn) / nn) / nn) / nn) / nn) / n
}

fn gammafn(x: f64) -> f64 {
    var g: [22]f64 = zero
    g[0usize] = 0.8571195590989331421920062399942e-2f64
    g[1usize] = 0.4415381324841006757191315771652e-2f64
    g[2usize] = 0.5685043681599363378632664588789e-1f64
    g[3usize] = -0.4219835396418560501012500186624e-2f64
    g[4usize] = 0.1326808181212460220584006796352e-2f64
    g[5usize] = -0.1893024529798880432523947023886e-3f64
    g[6usize] = 0.3606925327441245256578082217225e-4f64
    g[7usize] = -0.6056761904460864218485548290365e-5f64
    g[8usize] = 0.1055829546302283344731823509093e-5f64
    g[9usize] = -0.1811967365542384048291855891166e-6f64
    g[10usize] = 0.3117724964715322277790254593169e-7f64
    g[11usize] = -0.5354219639019687140874081024347e-8f64
    g[12usize] = 0.9193275519859588946887786825940e-9f64
    g[13usize] = -0.1577941280288339761767423273953e-9f64
    g[14usize] = 0.2707980622934954543266540433089e-10f64
    g[15usize] = -0.4646818653825730144081661058933e-11f64
    g[16usize] = 0.7973350192007419656460767175359e-12f64
    g[17usize] = -0.1368078209830916025799499172309e-12f64
    g[18usize] = 0.2347319486563800657233471771688e-13f64
    g[19usize] = -0.4027432614949066932766570534699e-14f64
    g[20usize] = 0.6910051747372100912138336975257e-15f64
    g[21usize] = -0.1185584500221992907052387126192e-15f64
    let xmin = -170.5674972726612f64
    let xmax = 171.61447887182298f64
    let xsml = 2.2474362225598545e-308f64
    let dxrel = 1.490116119384765696e-8f64
    if x != x { ret x }
    if x == 0.0f64 || (x < 0.0f64 && x == math.round[f64](x)) { ret nan() }
    var y = abs_of(x)
    if y <= 10.0f64 {
        var n = i64(x)
        if x < 0.0f64 { n -= 1i64 }
        y = x - f64(n)
        n -= 1i64
        var value = chebyshev_eval(y * 2.0f64 - 1.0f64, g[0usize..22usize], 22usize) + 0.9375f64
        if n == 0i64 { ret value }
        if n < 0i64 {
            if y < xsml {
                if x > 0.0f64 { ret inf() }
                ret 0.0f64 - inf()
            }
            n = 0i64 - n
            var i = 0i64
            while i < n {
                value = value / (x + f64(i))
                i += 1i64
            }
            ret value
        }
        var i = 1i64
        while i <= n {
            value = value * (y + f64(i))
            i += 1i64
        }
        ret value
    }
    if x > xmax { ret inf() }
    if x < xmin { ret 0.0f64 }
    var value = 1.0f64
    if y <= 50.0f64 && y == f64(i64(y)) {
        var i = 2i64
        while f64(i) < y {
            value = value * f64(i)
            i += 1i64
        }
    } else {
        value = math.exp[f64]((y - 0.5f64) * math.log[f64](y) - y + 0.918938533204672741780329736406f64 + stirlerr(y))
    }
    if x > 0.0f64 { ret value }
    let sinpiy = sinpi(y)
    if sinpiy == 0.0f64 { ret inf() }
    ret 0.0f64 - 3.141592653589793238462643383280f64 / (y * sinpiy * value)
}

fn lgammafn(x: f64) -> f64 {
    let xmax = 2.5327372760800758e+305f64
    let dxrel = 1.490116119384765625e-8f64
    if x != x { ret x }
    if x <= 0.0f64 && x == math.trunc[f64](x) { ret inf() }
    let y = abs_of(x)
    if y < 1e-306f64 { ret 0.0f64 - math.log[f64](y) }
    if y <= 10.0f64 { ret math.log[f64](abs_of(gammafn(x))) }
    if y > xmax { ret inf() }
    if x > 0.0f64 {
        if x > 1e17f64 { ret x * (math.log[f64](x) - 1.0f64) }
        if x > 4934720.0f64 { ret 0.918938533204672741780329736406f64 + (x - 0.5f64) * math.log[f64](x) - x }
        ret 0.918938533204672741780329736406f64 + (x - 0.5f64) * math.log[f64](x) - x + lgammacor(x)
    }
    let sinpiy = abs_of(sinpi(y))
    if sinpiy == 0.0f64 { ret nan() }
    ret 0.225791352644727432363097614947f64 + (x - 0.5f64) * math.log[f64](y) - x - math.log[f64](sinpiy) - lgammacor(y)
}

// --- log1pmx, lgamma1p

fn logcf(x: f64, i: f64, d: f64, eps: f64) -> f64 {
    let scalefactor = 1.157920892373162e77f64
    var c1 = 2.0f64 * d
    var c2 = i + d
    var c4 = c2 + d
    var a1 = c2
    var b1 = i * (c2 - i * x)
    var b2 = d * d * x
    var a2 = c4 * c2 - b2
    b2 = c4 * b1 - i * b2
    while abs_of(a2 * b1 - a1 * b2) > abs_of(eps * b1 * b2) {
        var c3 = c2 * c2 * x
        c2 += d
        c4 += d
        a1 = c4 * a2 - c3 * a1
        b1 = c4 * b2 - c3 * b1
        c3 = c1 * c1 * x
        c1 += d
        c4 += d
        a2 = c4 * a1 - c3 * a2
        b2 = c4 * b1 - c3 * b2
        if abs_of(b2) > scalefactor {
            a1 = a1 / scalefactor
            b1 = b1 / scalefactor
            a2 = a2 / scalefactor
            b2 = b2 / scalefactor
        } else if abs_of(b2) < 1.0f64 / scalefactor {
            a1 = a1 * scalefactor
            b1 = b1 * scalefactor
            a2 = a2 * scalefactor
            b2 = b2 * scalefactor
        }
    }
    ret a2 / b2
}

fn log1pmx(x: f64) -> f64 {
    if x > 1.0f64 || x < -0.79149064f64 { ret dist.log1p(x) - x }
    let r = x / (2.0f64 + x)
    let y = r * r
    if abs_of(x) < 1e-2f64 {
        let two = 2.0f64
        ret r * ((((two / 9.0f64 * y + two / 7.0f64) * y + two / 5.0f64) * y + two / 3.0f64) * y - x)
    }
    ret r * (2.0f64 * y * logcf(y, 3.0f64, 2.0f64, 1e-14f64) - x)
}

fn lgamma1p(a: f64) -> f64 {
    if abs_of(a) >= 0.5f64 { ret lgammafn(a + 1.0f64) }
    let eulers_const = 0.5772156649015328606065120900824024f64
    var c: [40]f64 = zero
    c[0usize] = 0.3224670334241132182362075833230126e-0f64
    c[1usize] = 0.6735230105319809513324605383715000e-1f64
    c[2usize] = 0.2058080842778454787900092413529198e-1f64
    c[3usize] = 0.7385551028673985266273097291406834e-2f64
    c[4usize] = 0.2890510330741523285752988298486755e-2f64
    c[5usize] = 0.1192753911703260977113935692828109e-2f64
    c[6usize] = 0.5096695247430424223356548135815582e-3f64
    c[7usize] = 0.2231547584535793797614188036013401e-3f64
    c[8usize] = 0.9945751278180853371459589003190170e-4f64
    c[9usize] = 0.4492623673813314170020750240635786e-4f64
    c[10usize] = 0.2050721277567069155316650397830591e-4f64
    c[11usize] = 0.9439488275268395903987425104415055e-5f64
    c[12usize] = 0.4374866789907487804181793223952411e-5f64
    c[13usize] = 0.2039215753801366236781900709670839e-5f64
    c[14usize] = 0.9551412130407419832857179772951265e-6f64
    c[15usize] = 0.4492469198764566043294290331193655e-6f64
    c[16usize] = 0.2120718480555466586923135901077628e-6f64
    c[17usize] = 0.1004322482396809960872083050053344e-6f64
    c[18usize] = 0.4769810169363980565760193417246730e-7f64
    c[19usize] = 0.2271109460894316491031998116062124e-7f64
    c[20usize] = 0.1083865921489695409107491757968159e-7f64
    c[21usize] = 0.5183475041970046655121248647057669e-8f64
    c[22usize] = 0.2483674543802478317185008663991718e-8f64
    c[23usize] = 0.1192140140586091207442548202774640e-8f64
    c[24usize] = 0.5731367241678862013330194857961011e-9f64
    c[25usize] = 0.2759522885124233145178149692816341e-9f64
    c[26usize] = 0.1330476437424448948149715720858008e-9f64
    c[27usize] = 0.6422964563838100022082448087644648e-10f64
    c[28usize] = 0.3104424774732227276239215783404066e-10f64
    c[29usize] = 0.1502138408075414217093301048780668e-10f64
    c[30usize] = 0.7275974480239079662504549924814047e-11f64
    c[31usize] = 0.3527742476575915083615072228655483e-11f64
    c[32usize] = 0.1711991790559617908601084114443031e-11f64
    c[33usize] = 0.8315385841420284819798357793954418e-12f64
    c[34usize] = 0.4042200525289440065536008957032895e-12f64
    c[35usize] = 0.1966475631096616490411045679010286e-12f64
    c[36usize] = 0.9573630387838555763782200936508615e-13f64
    c[37usize] = 0.4664076026428374224576492565974577e-13f64
    c[38usize] = 0.2273736960065972320633279596737272e-13f64
    c[39usize] = 0.1109139947083452201658320007192334e-13f64
    let cc = 0.2273736845824652515226821577978691e-12f64
    var lgam = cc * logcf(0.0f64 - a / 2.0f64, 42.0f64, 1.0f64, 1e-14f64)
    var i = 39i64
    while i >= 0i64 {
        lgam = c[usize(i)] - a * lgam
        i -= 1i64
    }
    ret (a * lgam - eulers_const) * a - log1pmx(a)
}

// --- bd0, ebd0, dpois_raw

fn bd0(x: f64, np: f64) -> f64 {
    if !finite(x) || !finite(np) || np == 0.0f64 { ret nan() }
    if abs_of(x - np) < 0.1f64 * (x + np) {
        let d = x - np
        var v = d / (x + np)
        if d != 0.0f64 && v == 0.0f64 {
            let x_ = x / 4.0f64
            let n_ = np / 4.0f64
            v = (x_ - n_) / (x_ + n_)
        }
        var s = d / 2.0f64 * v
        if abs_of(s * 2.0f64) < 2.2250738585072014e-308f64 { ret s * 2.0f64 }
        var ej = x * v
        v = v * v
        var j = 1i64
        while j < 1000i64 {
            ej = ej * v
            let s_ = s
            s = s + ej / f64(2i64 * j + 1i64)
            if s == s_ { ret s * 2.0f64 }
            j += 1i64
        }
    }
    var lg = 0.0f64
    if finite(x / np) { lg = math.log[f64](x / np) } else { lg = math.log[f64](x) - math.log[f64](np) }
    if x > np { ret x * (lg - 1.0f64) + np }
    ret x * lg + np - x
}

fn hexval(c: u8) -> u64 {
    if c >= 97u8 { ret u64(c - 87u8) }
    ret u64(c - 48u8)
}

// bd0_scale[i][j]
fn bd0_scale(i: usize, j: usize) -> f64 {
    let h = tables.bd0_scale_hex()
    let at = (i * 4usize + j) * 16usize
    var v = 0u64
    var k = 0usize
    while k < 16usize {
        v = (v << 4u64) | hexval(h[at + k])
        k += 1usize
    }
    ret mem.bitcast[f64](v)
}

// x * log(x / M) + (M - x), as (yh, yl).
fn ebd0(x: f64, mm: f64) -> (f64, f64) {
    let sb = 10i64
    let s = 1024.0f64
    let nn = 128.0f64
    var yh = 0.0f64
    var yl = 0.0f64
    if x == mm { ret (0.0f64, 0.0f64) }
    if x == 0.0f64 { ret (mm, 0.0f64) }
    if mm == 0.0f64 { ret (inf(), 0.0f64) }
    if mm / x == inf() { ret (mm, 0.0f64) }
    let (r, e) = frexp(mm / x)
    if 0.693147180559945309417232121458f64 * f64(0i64 - e) > 1.0f64 + 1.7976931348623157e308f64 / x { ret (inf(), 0.0f64) }
    let i = usize(i64(math.floor[f64]((r - 0.5f64) * (2.0f64 * nn) + 0.5f64)))
    let f = math.floor[f64](s / (0.5f64 + f64(i) / (2.0f64 * nn)) + 0.5f64)
    let fg = ldexp(f, 0i64 - (e + sb))
    if fg == inf() { ret (fg, 0.0f64) }
    var d = 0.0f64 - x * log1pmx((mm * fg - x) / x)
    var d1 = math.floor[f64](d + 0.5f64)
    yh += d1
    yl += d - d1
    if fg == 1.0f64 { ret (yh, yl) }
    var j = 0usize
    while j < 4usize {
        d = x * bd0_scale(i, j)
        d1 = math.floor[f64](d + 0.5f64)
        yh += d1
        yl += d - d1
        d = 0.0f64 - x * bd0_scale(0usize, j) * f64(e)
        d1 = math.floor[f64](d + 0.5f64)
        yh += d1
        yl += d - d1
        if !finite(yh) { ret (inf(), 0.0f64) }
        j += 1usize
    }
    d = mm
    d1 = math.floor[f64](d + 0.5f64)
    yh += d1
    yl += d - d1
    d = 0.0f64 - mm * fg
    d1 = math.floor[f64](d + 0.5f64)
    yh += d1
    yl += d - d1
    ret (yh, yl)
}

fn dpois_raw(x: f64, lambda: f64, lg: bool) -> f64 {
    let dbl_min = 2.2250738585072014e-308f64
    if lambda == 0.0f64 {
        if x == 0.0f64 { ret dist.d1(lg) }
        ret dist.d0(lg)
    }
    if !finite(lambda) { ret dist.d0(lg) }
    if x < 0.0f64 { ret dist.d0(lg) }
    if x <= lambda * dbl_min {
        if lg { ret 0.0f64 - lambda }
        ret math.exp[f64](0.0f64 - lambda)
    }
    if lambda < x * dbl_min {
        if !finite(x) { ret dist.d0(lg) }
        let v = 0.0f64 - lambda + x * math.log[f64](lambda) - lgammafn(x + 1.0f64)
        if lg { ret v }
        ret math.exp[f64](v)
    }
    let (yh, yl0) = ebd0(x, lambda)
    let yl = yl0 + stirlerr(x)
    let lrg = x >= 2.86111748575702815380240589208115399625e+307f64
    var r = 6.283185307179586476925286766559f64 * x
    if lrg { r = 2.50662827463100050241576528481104525301f64 * math.sqrt[f64](x) }
    if lg {
        var t = 0.0f64
        if lrg { t = math.log[f64](r) } else { t = 0.5f64 * math.log[f64](r) }
        ret 0.0f64 - yl - yh - t
    }
    var den = 0.0f64
    if lrg { den = r } else { den = math.sqrt[f64](r) }
    ret math.exp[f64](0.0f64 - yl) * math.exp[f64](0.0f64 - yh) / den
}

fn dpois(x0: f64, lambda: f64, lg: bool) -> f64 {
    if x0 != x0 || lambda != lambda { ret x0 + lambda }
    if lambda < 0.0f64 { ret nan() }
    if abs_of(x0 - math.round[f64](x0)) > 1e-9f64 * max2(1.0f64, abs_of(x0)) { ret dist.d0(lg) }
    if x0 < 0.0f64 || !finite(x0) { ret dist.d0(lg) }
    ret dpois_raw(math.round[f64](x0), lambda, lg)
}

fn dgamma(x: f64, shape: f64, scale: f64, lg: bool) -> f64 {
    if x != x || shape != shape || scale != scale { ret x + shape + scale }
    if shape < 0.0f64 || scale <= 0.0f64 { ret nan() }
    if x < 0.0f64 { ret dist.d0(lg) }
    if shape == 0.0f64 {
        if x == 0.0f64 { ret inf() }
        ret dist.d0(lg)
    }
    if x == 0.0f64 {
        if shape < 1.0f64 { ret inf() }
        if shape > 1.0f64 { ret dist.d0(lg) }
        if lg { ret 0.0f64 - math.log[f64](scale) }
        ret 1.0f64 / scale
    }
    if shape < 1.0f64 {
        let pr = dpois_raw(shape, x / scale, lg)
        if lg {
            if finite(shape / x) { ret pr + math.log[f64](shape / x) }
            ret pr + math.log[f64](shape) - math.log[f64](x)
        }
        ret pr * shape / x
    }
    let pr = dpois_raw(shape - 1.0f64, x / scale, lg)
    if lg { ret pr - math.log[f64](scale) }
    ret pr / scale
}

// --- pgamma

fn dpois_wrap(x_plus_1: f64, lambda: f64, lg: bool) -> f64 {
    let m_cutoff = 3.196577161300664e18f64
    if !finite(lambda) { ret dist.d0(lg) }
    if x_plus_1 > 1.0f64 { ret dpois_raw(x_plus_1 - 1.0f64, lambda, lg) }
    if lambda > abs_of(x_plus_1 - 1.0f64) * m_cutoff {
        let v = 0.0f64 - lambda - lgammafn(x_plus_1)
        if lg { ret v }
        ret math.exp[f64](v)
    }
    let d = dpois_raw(x_plus_1, lambda, lg)
    if lg { ret d + math.log[f64](x_plus_1 / lambda) }
    ret d * (x_plus_1 / lambda)
}

fn pgamma_smallx(x: f64, alph: f64, lower: bool, lg: bool) -> f64 {
    let eps = 2.220446049250313e-16f64
    var sum = 0.0f64
    var c = alph
    var n = 0.0f64
    var term = 0.0f64
    var go = true
    while go {
        n += 1.0f64
        c = c * (0.0f64 - x / n)
        term = c / (alph + n)
        sum = sum + term
        go = abs_of(term) > eps * abs_of(sum)
    }
    if lower {
        var f1 = 1.0f64 + sum
        if lg { f1 = dist.log1p(sum) }
        var f2 = 0.0f64
        if alph > 1.0f64 {
            f2 = dpois_raw(alph, x, lg)
            if lg { f2 = f2 + x } else { f2 = f2 * math.exp[f64](x) }
        } else if lg {
            f2 = alph * math.log[f64](x) - lgamma1p(alph)
        } else {
            f2 = math.pow[f64](x, alph) / math.exp[f64](lgamma1p(alph))
        }
        if lg { ret f1 + f2 }
        ret f1 * f2
    }
    let lf2 = alph * math.log[f64](x) - lgamma1p(alph)
    if lg { ret dist.log1_exp(dist.log1p(sum) + lf2) }
    let f1m1 = sum
    let f2m1 = dist.expm1(lf2)
    ret 0.0f64 - (f1m1 + f2m1 + f1m1 * f2m1)
}

fn pd_upper_series(x: f64, y0: f64, lg: bool) -> f64 {
    let eps = 2.220446049250313e-16f64
    var y = y0
    var term = x / y
    var sum = term
    var go = true
    while go {
        y += 1.0f64
        term = term * (x / y)
        sum = sum + term
        go = term > sum * eps
    }
    if lg { ret math.log[f64](sum) }
    ret sum
}

fn pd_lower_cf(y: f64, d: f64) -> f64 {
    let eps = 2.220446049250313e-16f64
    let scalefactor = 1.157920892373162e77f64
    var f = 0.0f64
    if y == 0.0f64 { ret 0.0f64 }
    var f0 = y / d
    if abs_of(y - 1.0f64) < abs_of(d) * eps { ret f0 }
    if f0 > 1.0f64 { f0 = 1.0f64 }
    var c2 = y
    var c4 = d
    var a1 = 0.0f64
    var b1 = 1.0f64
    var a2 = y
    var b2 = d
    while b2 > scalefactor {
        a1 = a1 / scalefactor
        b1 = b1 / scalefactor
        a2 = a2 / scalefactor
        b2 = b2 / scalefactor
    }
    var i = 0.0f64
    var of = -1.0f64
    while i < 200000.0f64 {
        i += 1.0f64
        c2 -= 1.0f64
        var c3 = i * c2
        c4 += 2.0f64
        a1 = c4 * a2 + c3 * a1
        b1 = c4 * b2 + c3 * b1
        i += 1.0f64
        c2 -= 1.0f64
        c3 = i * c2
        c4 += 2.0f64
        a2 = c4 * a1 + c3 * a2
        b2 = c4 * b1 + c3 * b2
        if b2 > scalefactor {
            a1 = a1 / scalefactor
            b1 = b1 / scalefactor
            a2 = a2 / scalefactor
            b2 = b2 / scalefactor
        }
        if b2 != 0.0f64 {
            f = a2 / b2
            if abs_of(f - of) <= eps * max2(f0, abs_of(f)) { ret f }
            of = f
        }
    }
    ret f
}

fn pd_lower_series(lambda: f64, y0: f64) -> f64 {
    let eps = 2.220446049250313e-16f64
    var y = y0
    var term = 1.0f64
    var sum = 0.0f64
    while y >= 1.0f64 && term > sum * eps {
        term = term * (y / lambda)
        sum = sum + term
        y -= 1.0f64
    }
    if y != math.floor[f64](y) {
        let f = pd_lower_cf(y, lambda + 1.0f64 - y)
        sum = sum + term * f
    }
    ret sum
}

fn dpnorm(x0: f64, lower0: bool, lp: f64) -> f64 {
    let eps = 2.220446049250313e-16f64
    var x = x0
    var lower = lower0
    if x < 0.0f64 {
        x = 0.0f64 - x
        lower = !lower
    }
    if x > 10.0f64 && !lower {
        var term = 1.0f64 / x
        var sum = term
        let x2 = x * x
        var i = 1.0f64
        var go = true
        while go {
            term = term * (0.0f64 - i / x2)
            sum = sum + term
            i += 2.0f64
            go = abs_of(term) > eps * sum
        }
        ret 1.0f64 / sum
    }
    let d = dist.dnorm(x, 0.0f64, 1.0f64, false)
    ret d / math.exp[f64](lp)
}

fn ppois_asymp(x: f64, lambda: f64, lower: bool, lg: bool) -> f64 {
    var ca: [8]f64 = zero
    ca[1usize] = 2.0f64 / 3.0f64
    ca[2usize] = -4.0f64 / 135.0f64
    ca[3usize] = 8.0f64 / 2835.0f64
    ca[4usize] = 16.0f64 / 8505.0f64
    ca[5usize] = -8992.0f64 / 12629925.0f64
    ca[6usize] = -334144.0f64 / 492567075.0f64
    ca[7usize] = 698752.0f64 / 1477701225.0f64
    var cb: [8]f64 = zero
    cb[1usize] = 1.0f64 / 12.0f64
    cb[2usize] = 1.0f64 / 288.0f64
    cb[3usize] = -139.0f64 / 51840.0f64
    cb[4usize] = -571.0f64 / 2488320.0f64
    cb[5usize] = 163879.0f64 / 209018880.0f64
    cb[6usize] = 5246819.0f64 / 75246796800.0f64
    cb[7usize] = -534703531.0f64 / 902961561600.0f64
    let dfm = lambda - x
    let pt_ = 0.0f64 - log1pmx(dfm / x)
    var s2pt = math.sqrt[f64](2.0f64 * x * pt_)
    if dfm < 0.0f64 { s2pt = 0.0f64 - s2pt }
    var res12 = 0.0f64
    var res1_term = math.sqrt[f64](x)
    var res1_ig = res1_term
    var res2_term = s2pt
    var res2_ig = res2_term
    var i = 1usize
    while i < 8usize {
        res12 = res12 + res1_ig * ca[i]
        res12 = res12 + res2_ig * cb[i]
        res1_term = res1_term * (pt_ / f64(i))
        res2_term = res2_term * (2.0f64 * pt_ / f64(2usize * i + 1usize))
        res1_ig = res1_ig / x + res1_term
        res2_ig = res2_ig / x + res2_term
        i += 1usize
    }
    var elfb = x
    var elfb_term = 1.0f64
    i = 1usize
    while i < 8usize {
        elfb = elfb + elfb_term * cb[i]
        elfb_term = elfb_term / x
        i += 1usize
    }
    if !lower { elfb = 0.0f64 - elfb }
    let f = res12 / elfb
    let np = dist.pnorm(s2pt, 0.0f64, 1.0f64, !lower, lg)
    if lg {
        let n_d_over_p = dpnorm(s2pt, !lower, np)
        ret np + dist.log1p(f * n_d_over_p)
    }
    let nd = dist.dnorm(s2pt, 0.0f64, 1.0f64, lg)
    ret np + f * nd
}

fn pgamma_raw(x: f64, alph: f64, lower: bool, lg: bool) -> f64 {
    let eps = 2.220446049250313e-16f64
    if x <= 0.0f64 { ret dist.dt0(lower, lg) }
    if x >= inf() { ret dist.dt1(lower, lg) }
    var res = 0.0f64
    if x < 1.0f64 {
        res = pgamma_smallx(x, alph, lower, lg)
    } else if x <= alph - 1.0f64 && x < 0.8f64 * (alph + 50.0f64) {
        let sum = pd_upper_series(x, alph, lg)
        let d = dpois_wrap(alph, x, lg)
        if !lower {
            if lg { res = dist.log1_exp(d + sum) } else { res = 1.0f64 - d * sum }
        } else {
            if lg { res = sum + d } else { res = sum * d }
        }
    } else if alph - 1.0f64 < x && alph < 0.8f64 * (x + 50.0f64) {
        var sum = 0.0f64
        let d = dpois_wrap(alph, x, lg)
        if alph < 1.0f64 {
            if x * eps > 1.0f64 - alph {
                sum = dist.d1(lg)
            } else {
                let f = pd_lower_cf(alph, x - (alph - 1.0f64)) * x / alph
                if lg { sum = math.log[f64](f) } else { sum = f }
            }
        } else {
            sum = pd_lower_series(x, alph - 1.0f64)
            if lg { sum = dist.log1p(sum) } else { sum = 1.0f64 + sum }
        }
        if !lower {
            if lg { res = sum + d } else { res = sum * d }
        } else {
            if lg { res = dist.log1_exp(d + sum) } else { res = 1.0f64 - d * sum }
        }
    } else {
        res = ppois_asymp(alph - 1.0f64, x, !lower, lg)
    }
    if !lg && res < 2.2250738585072014e-308f64 / eps {
        ret math.exp[f64](pgamma_raw(x, alph, lower, true))
    }
    ret res
}

fn pgamma(x0: f64, alph: f64, scale: f64, lower: bool, lg: bool) -> f64 {
    if x0 != x0 || alph != alph || scale != scale { ret x0 + alph + scale }
    if alph < 0.0f64 || scale <= 0.0f64 { ret nan() }
    let x = x0 / scale
    if x != x { ret x }
    if alph == 0.0f64 {
        if x <= 0.0f64 { ret dist.dt0(lower, lg) }
        ret dist.dt1(lower, lg)
    }
    ret pgamma_raw(x, alph, lower, lg)
}

fn dchisq(x: f64, df: f64, lg: bool) -> f64 { ret dgamma(x, df / 2.0f64, 2.0f64, lg) }

fn pchisq(x: f64, df: f64, lower: bool, lg: bool) -> f64 { ret pgamma(x, df / 2.0f64, 2.0f64, lower, lg) }

fn ppois(x0: f64, lambda: f64, lower: bool, lg: bool) -> f64 {
    if x0 != x0 || lambda != lambda { ret x0 + lambda }
    if lambda < 0.0f64 { ret nan() }
    if x0 < 0.0f64 { ret dist.dt0(lower, lg) }
    if lambda == 0.0f64 { ret dist.dt1(lower, lg) }
    if !finite(x0) { ret dist.dt1(lower, lg) }
    let x = math.floor[f64](x0 + 1e-7f64)
    ret pgamma(lambda, x + 1.0f64, 1.0f64, !lower, lg)
}

// --- q functions

fn rint(x: f64) -> f64 {
    let f = math.floor[f64](x)
    let d = x - f
    if d < 0.5f64 { ret f }
    if d > 0.5f64 { ret f + 1.0f64 }
    if (f - 2.0f64 * math.floor[f64](f / 2.0f64)) == 0.0f64 { ret f }
    ret f + 1.0f64
}

fn dt_log(p: f64, lower: bool, lg: bool) -> f64 {
    if lower { ret dist.dlog(p, lg) }
    ret dist.dlexp(p, lg)
}

fn qchisq_appr(p: f64, nu: f64, g: f64, lower: bool, lg: bool, tol: f64) -> f64 {
    let c7 = 4.67f64
    let c8 = 6.66f64
    let c9 = 6.73f64
    let c10 = 13.32f64
    if p != p || nu != nu { ret p + nu }
    if dist.bad_p(p, lg) { ret nan() }
    if nu <= 0.0f64 { ret nan() }
    let alpha = 0.5f64 * nu
    let c = alpha - 1.0f64
    var ch = 0.0f64
    var p1 = dt_log(p, lower, lg)
    if nu < -1.24f64 * p1 {
        var lgam1pa = math.log[f64](alpha) + g
        if alpha < 0.5f64 { lgam1pa = lgamma1p(alpha) }
        ch = math.exp[f64]((lgam1pa + p1) / alpha + 0.693147180559945309417232121458f64)
    } else if nu > 0.32f64 {
        let x = dist.qnorm(p, 0.0f64, 1.0f64, lower, lg)
        p1 = 2.0f64 / (9.0f64 * nu)
        let u = x * math.sqrt[f64](p1) + 1.0f64 - p1
        ch = nu * u * u * u
        if ch > 2.2f64 * nu + 6.0f64 {
            ch = -2.0f64 * (dist.dt_clog(p, lower, lg) - c * math.log[f64](0.5f64 * ch) + g)
        }
    } else {
        ch = 0.4f64
        let a = dist.dt_clog(p, lower, lg) + g + c * 0.693147180559945309417232121458f64
        var q = 0.0f64
        var go = true
        while go {
            q = ch
            let pp1 = 1.0f64 / (1.0f64 + ch * (c7 + ch))
            let p2 = ch * (c9 + ch * (c8 + ch))
            let t = -0.5f64 + (c7 + 2.0f64 * ch) * pp1 - (c9 + ch * (c10 + 3.0f64 * ch)) / p2
            ch = ch - (1.0f64 - math.exp[f64](a + 0.5f64 * ch) * p2 * pp1) / t
            go = abs_of(q - ch) > tol * abs_of(ch)
        }
    }
    ret ch
}

fn qgamma(p0: f64, alpha: f64, scale: f64, lower: bool, lg0: bool) -> f64 {
    let eps1 = 1e-2f64
    let eps2 = 5e-7f64
    let eps_n = 1e-15f64
    let maxit = 1000i64
    let pmin = 1e-100f64
    let pmax = 1.0f64 - 1e-14f64
    let i420 = 1.0f64 / 420.0f64
    let i2520 = 1.0f64 / 2520.0f64
    let i5040 = 1.0f64 / 5040.0f64
    var p = p0
    var lg = lg0
    if p != p || alpha != alpha || scale != scale { ret p + alpha + scale }
    if lg {
        if p > 0.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret inf() }
            ret 0.0f64
        }
        if p == 0.0f64 - inf() {
            if lower { ret 0.0f64 }
            ret inf()
        }
    } else {
        if p < 0.0f64 || p > 1.0f64 { ret nan() }
        if p == 0.0f64 {
            if lower { ret 0.0f64 }
            ret inf()
        }
        if p == 1.0f64 {
            if lower { ret inf() }
            ret 0.0f64
        }
    }
    if alpha < 0.0f64 || scale <= 0.0f64 { ret nan() }
    if alpha == 0.0f64 { ret 0.0f64 }
    var max_it_newton = 1i64
    if alpha < 1e-10f64 { max_it_newton = 7i64 }
    var p_ = dist.dt_qiv(p, lower, lg)
    var g = lgammafn(alpha)
    var ch = qchisq_appr(p, 2.0f64 * alpha, g, lower, lg, eps1)
    var skip = false
    if !finite(ch) {
        max_it_newton = 0i64
        skip = true
    } else if ch < eps2 {
        max_it_newton = 20i64
        skip = true
    } else if p_ > pmax || p_ < pmin {
        max_it_newton = 20i64
        skip = true
    }
    if !skip {
        let c = alpha - 1.0f64
        let s6 = (120.0f64 + c * (346.0f64 + 127.0f64 * c)) * i5040
        let ch0 = ch
        var i = 1i64
        var done = false
        while i <= maxit && !done {
            let q = ch
            let p1 = 0.5f64 * ch
            let p2 = p_ - pgamma_raw(p1, alpha, true, false)
            if !finite(p2) || ch <= 0.0f64 {
                ch = ch0
                max_it_newton = 27i64
                done = true
            } else {
                let t = p2 * math.exp[f64](alpha * 0.693147180559945309417232121458f64 + g + p1 - c * math.log[f64](ch))
                let b = t / ch
                let a = 0.5f64 * t - b * c
                let s1 = (210.0f64 + a * (140.0f64 + a * (105.0f64 + a * (84.0f64 + a * (70.0f64 + 60.0f64 * a))))) * i420
                let s2 = (420.0f64 + a * (735.0f64 + a * (966.0f64 + a * (1141.0f64 + 1278.0f64 * a)))) * i2520
                let s3 = (210.0f64 + a * (462.0f64 + a * (707.0f64 + 932.0f64 * a))) * i2520
                let s4 = (252.0f64 + a * (672.0f64 + 1182.0f64 * a) + c * (294.0f64 + a * (889.0f64 + 1740.0f64 * a))) * i5040
                let s5 = (84.0f64 + 2264.0f64 * a + c * (1175.0f64 + 606.0f64 * a)) * i2520
                ch = ch + t * (1.0f64 + 0.5f64 * t * s1 - b * c * (s1 - b * (s2 - b * (s3 - b * (s4 - b * (s5 - b * s6))))))
                if abs_of(q - ch) < eps2 * ch {
                    done = true
                } else if abs_of(q - ch) > 0.1f64 * ch {
                    if ch < q { ch = 0.9f64 * q } else { ch = 1.1f64 * q }
                }
            }
            i += 1i64
        }
    }
    var x = 0.5f64 * scale * ch
    if max_it_newton > 0i64 {
        if !lg {
            p = math.log[f64](p)
            lg = true
        }
        var stop = false
        if x == 0.0f64 {
            let one_p = 1.0f64 + 1e-7f64
            let one_m = 1.0f64 - 1e-7f64
            x = 2.2250738585072014e-308f64
            p_ = pgamma(x, alpha, scale, lower, lg)
            if (lower && p_ > p * one_p) || (!lower && p_ < p * one_m) { ret 0.0f64 }
        } else {
            p_ = pgamma(x, alpha, scale, lower, lg)
        }
        if p_ == 0.0f64 - inf() { ret 0.0f64 }
        var i = 1i64
        while i <= max_it_newton && !stop {
            let p1 = p_ - p
            if abs_of(p1) < abs_of(eps_n * p) {
                stop = true
            } else {
                g = dgamma(x, alpha, scale, lg)
                if g == dist.d0(lg) {
                    stop = true
                } else {
                    var t = 0.0f64
                    if lg { t = p1 * math.exp[f64](p_ - g) } else { t = p1 / g }
                    if lower { t = x - t } else { t = x + t }
                    p_ = pgamma(t, alpha, scale, lower, lg)
                    if abs_of(p_ - p) > abs_of(p1) || (i > 1i64 && abs_of(p_ - p) == abs_of(p1)) {
                        stop = true
                    } else {
                        x = t
                    }
                }
            }
            i += 1i64
        }
    }
    ret x
}

fn qchisq(p: f64, df: f64, lower: bool, lg: bool) -> f64 { ret qgamma(p, 0.5f64 * df, 2.0f64, lower, lg) }

fn do_search_pois(y0: f64, z: f64, p: f64, lambda: f64, incr: f64, lower: bool, lg: bool) -> (f64, f64) {
    var y = y0
    var zz = z
    var left = zz < p
    if lower { left = zz >= p }
    if left {
        var go = true
        while go {
            var newz = -1.0f64
            if y > 0.0f64 {
                newz = ppois(y - incr, lambda, lower, lg)
            } else if y < 0.0f64 {
                y = 0.0f64
            }
            var stop = y == 0.0f64 || newz != newz
            if !stop {
                if lower { stop = newz < p } else { stop = newz >= p }
            }
            if stop { ret (y, zz) }
            y = max2(0.0f64, y - incr)
            zz = newz
        }
    }
    while true {
        let prevy = y
        y += incr
        let newz = ppois(y, lambda, lower, lg)
        var stop = newz != newz
        if !stop {
            if lower { stop = newz >= p } else { stop = newz < p }
        }
        if stop {
            if incr <= 1.0f64 { ret (y, newz) }
            ret (prevy, zz)
        }
        zz = newz
    }
    ret (y, zz)
}

fn qpois(p0: f64, lambda: f64, lower: bool, lg: bool) -> f64 {
    var p = p0
    if p != p || lambda != lambda { ret p + lambda }
    if !finite(lambda) { ret nan() }
    if lambda < 0.0f64 { ret nan() }
    if dist.bad_p(p, lg) { ret nan() }
    if lambda == 0.0f64 { ret 0.0f64 }
    if p == dist.dt0(lower, lg) { ret 0.0f64 }
    if p == dist.dt1(lower, lg) { ret inf() }
    let mu = lambda
    let sigma = math.sqrt[f64](lambda)
    let gam = 1.0f64 / sigma
    let zq = dist.qnorm(p, 0.0f64, 1.0f64, lower, lg)
    var y = rint(mu + sigma * (zq + gam * (zq * zq - 1.0f64) / 6.0f64))
    if y < 0.0f64 { y = 0.0f64 }
    var z = ppois(y, lambda, lower, lg)
    let eps = 2.220446049250313e-16f64
    if lg {
        let e = 2.0f64 * eps
        if lower && p > -1.7976931348623157e308f64 { p = p * (1.0f64 + e) } else { p = p * (1.0f64 - e) }
    } else {
        let e = 8.0f64 * eps
        if lower {
            p = p * (1.0f64 - e)
        } else if 1.0f64 - p > 4.0f64 * e {
            p = p * (1.0f64 + e)
        }
    }
    if y < 4096.0f64 {
        let (yy, zz) = do_search_pois(y, z, p, lambda, 1.0f64, lower, lg)
        ret yy
    }
    var incr = math.floor[f64](y * (1.0f64 / 64.0f64))
    var oldincr = 0.0f64
    var go = true
    while go {
        oldincr = incr
        let (yy, zz) = do_search_pois(y, z, p, lambda, incr, lower, lg)
        y = yy
        z = zz
        incr = max2(1.0f64, math.floor[f64](incr / 8.0f64))
        go = oldincr > 1.0f64 && incr > y * 1e-15f64
    }
    ret y
}
