// The incomplete beta function ratio I_x(a, b) of TOMS 708 (Didonato and Morris), as R's nmath
// ports it: `bratio` returns the lower and upper tail (optionally logarithms) and an error code.
// The subroutines follow the C line for line (fpser, apser, bpser, bup, bfrac, bgrat, grat_r,
// basym, brcomp, brcmp1 and the gamma helpers gam1, gamln1, gamln, algdiv, bcorr, betaln, psi,
// rexpm1, rlog1, alnrel, erf, erfc1, esum, exparg).

use e.math
use e.math.dist as dist

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn inf() -> f64 { ret 1.0f64 / 0.0f64 }

fn finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn min2(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}

fn max2(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

fn dexp(z: f64, lg: bool) -> f64 {
    if lg { ret z }
    ret math.exp[f64](z)
}

fn exparg(l: i64) -> f64 {
    let lnb = 0.69314718055995f64
    var m = 1024i64
    if l != 0i64 { m = -1022i64 }
    ret f64(m) * lnb * 0.99999f64
}

fn esum(mu: i64, x: f64, give_log: bool) -> f64 {
    if give_log { ret x + f64(mu) }
    var w = 0.0f64
    if x > 0.0f64 {
        if mu > 0i64 { ret math.exp[f64](f64(mu)) * math.exp[f64](x) }
        w = f64(mu) + x
        if w < 0.0f64 { ret math.exp[f64](f64(mu)) * math.exp[f64](x) }
    } else {
        if mu < 0i64 { ret math.exp[f64](f64(mu)) * math.exp[f64](x) }
        w = f64(mu) + x
        if w > 0.0f64 { ret math.exp[f64](f64(mu)) * math.exp[f64](x) }
    }
    ret math.exp[f64](w)
}

fn rexpm1(x: f64) -> f64 {
    let p1 = 9.14041914819518e-10f64
    let p2 = 0.0238082361044469f64
    let q1 = -0.499999999085958f64
    let q2 = 0.107141568980644f64
    let q3 = -0.0119041179760821f64
    let q4 = 5.95130811860248e-4f64
    if abs_of(x) <= 0.15f64 {
        ret x * (((p2 * x + p1) * x + 1.0f64) / ((((q4 * x + q3) * x + q2) * x + q1) * x + 1.0f64))
    }
    let w = math.exp[f64](x)
    if x > 0.0f64 { ret w * (0.5f64 - 1.0f64 / w + 0.5f64) }
    ret w - 0.5f64 - 0.5f64
}

fn alnrel(a: f64) -> f64 {
    if abs_of(a) > 0.375f64 { ret math.log[f64](1.0f64 + a) }
    let p1 = -1.29418923021993f64
    let p2 = 0.405303492862024f64
    let p3 = -0.0178874546012214f64
    let q1 = -1.62752256355323f64
    let q2 = 0.747811014037616f64
    let q3 = -0.0845104217945565f64
    let t = a / (a + 2.0f64)
    let t2 = t * t
    let w = (((p3 * t2 + p2) * t2 + p1) * t2 + 1.0f64) / (((q3 * t2 + q2) * t2 + q1) * t2 + 1.0f64)
    ret t * 2.0f64 * w
}

fn rlog1(x: f64) -> f64 {
    let a = 0.0566749439387324f64
    let b = 0.0456512608815524f64
    let p0 = 0.333333333333333f64
    let p1 = -0.224696413112536f64
    let p2 = 0.00620886815375787f64
    let q1 = -1.27408923933623f64
    let q2 = 0.354508718369557f64
    var h = 0.0f64
    var w1 = 0.0f64
    if x < -0.39f64 || x > 0.57f64 {
        let w = x + 0.5f64 + 0.5f64
        ret x - math.log[f64](w)
    }
    if x < -0.18f64 {
        h = x + 0.3f64
        h = h / 0.7f64
        w1 = a - h * 0.3f64
    } else if x > 0.18f64 {
        h = x * 0.75f64 - 0.25f64
        w1 = b + h / 3.0f64
    } else {
        h = x
        w1 = 0.0f64
    }
    let r = h / (h + 2.0f64)
    let t = r * r
    let w = ((p2 * t + p1) * t + p0) / ((q2 * t + q1) * t + 1.0f64)
    ret t * 2.0f64 * (1.0f64 / (1.0f64 - r) - r * w) + w1
}

fn erf_(x: f64) -> f64 {
    let c = 0.564189583547756f64
    var a: [5]f64 = zero
    a[0usize] = 7.7105849500132e-5f64
    a[1usize] = -0.00133733772997339f64
    a[2usize] = 0.0323076579225834f64
    a[3usize] = 0.0479137145607681f64
    a[4usize] = 0.128379167095513f64
    var b: [3]f64 = zero
    b[0usize] = 0.00301048631703895f64
    b[1usize] = 0.0538971687740286f64
    b[2usize] = 0.375795757275549f64
    var p: [8]f64 = zero
    p[0usize] = -1.36864857382717e-7f64
    p[1usize] = 0.564195517478974f64
    p[2usize] = 7.21175825088309f64
    p[3usize] = 43.1622272220567f64
    p[4usize] = 152.98928504694f64
    p[5usize] = 339.320816734344f64
    p[6usize] = 451.918953711873f64
    p[7usize] = 300.459261020162f64
    var q: [8]f64 = zero
    q[0usize] = 1.0f64
    q[1usize] = 12.7827273196294f64
    q[2usize] = 77.0001529352295f64
    q[3usize] = 277.585444743988f64
    q[4usize] = 638.980264465631f64
    q[5usize] = 931.35409485061f64
    q[6usize] = 790.950925327898f64
    q[7usize] = 300.459260956983f64
    var r: [5]f64 = zero
    r[0usize] = 2.10144126479064f64
    r[1usize] = 26.2370141675169f64
    r[2usize] = 21.3688200555087f64
    r[3usize] = 4.6580782871847f64
    r[4usize] = 0.282094791773523f64
    var s: [4]f64 = zero
    s[0usize] = 94.153775055546f64
    s[1usize] = 187.11481179959f64
    s[2usize] = 99.0191814623914f64
    s[3usize] = 18.0124575948747f64
    let ax = abs_of(x)
    if ax <= 0.5f64 {
        let t = x * x
        let top = (((a[0usize] * t + a[1usize]) * t + a[2usize]) * t + a[3usize]) * t + a[4usize] + 1.0f64
        let bot = ((b[0usize] * t + b[1usize]) * t + b[2usize]) * t + 1.0f64
        ret x * (top / bot)
    }
    if ax <= 4.0f64 {
        let top = ((((((p[0usize] * ax + p[1usize]) * ax + p[2usize]) * ax + p[3usize]) * ax + p[4usize]) * ax + p[5usize]) * ax + p[6usize]) * ax + p[7usize]
        let bot = ((((((q[0usize] * ax + q[1usize]) * ax + q[2usize]) * ax + q[3usize]) * ax + q[4usize]) * ax + q[5usize]) * ax + q[6usize]) * ax + q[7usize]
        let rr = 0.5f64 - math.exp[f64](0.0f64 - x * x) * top / bot + 0.5f64
        if x < 0.0f64 { ret 0.0f64 - rr }
        ret rr
    }
    if ax >= 5.8f64 {
        if x > 0.0f64 { ret 1.0f64 }
        ret -1.0f64
    }
    let x2 = x * x
    var t = 1.0f64 / x2
    let top = (((r[0usize] * t + r[1usize]) * t + r[2usize]) * t + r[3usize]) * t + r[4usize]
    let bot = (((s[0usize] * t + s[1usize]) * t + s[2usize]) * t + s[3usize]) * t + 1.0f64
    t = (c - top / (x2 * bot)) / ax
    let rr = 0.5f64 - math.exp[f64](0.0f64 - x2) * t + 0.5f64
    if x < 0.0f64 { ret 0.0f64 - rr }
    ret rr
}

fn erfc1(ind: i64, x: f64) -> f64 {
    let c = 0.564189583547756f64
    var a: [5]f64 = zero
    a[0usize] = 7.7105849500132e-5f64
    a[1usize] = -0.00133733772997339f64
    a[2usize] = 0.0323076579225834f64
    a[3usize] = 0.0479137145607681f64
    a[4usize] = 0.128379167095513f64
    var b: [3]f64 = zero
    b[0usize] = 0.00301048631703895f64
    b[1usize] = 0.0538971687740286f64
    b[2usize] = 0.375795757275549f64
    var p: [8]f64 = zero
    p[0usize] = -1.36864857382717e-7f64
    p[1usize] = 0.564195517478974f64
    p[2usize] = 7.21175825088309f64
    p[3usize] = 43.1622272220567f64
    p[4usize] = 152.98928504694f64
    p[5usize] = 339.320816734344f64
    p[6usize] = 451.918953711873f64
    p[7usize] = 300.459261020162f64
    var q: [8]f64 = zero
    q[0usize] = 1.0f64
    q[1usize] = 12.7827273196294f64
    q[2usize] = 77.0001529352295f64
    q[3usize] = 277.585444743988f64
    q[4usize] = 638.980264465631f64
    q[5usize] = 931.35409485061f64
    q[6usize] = 790.950925327898f64
    q[7usize] = 300.459260956983f64
    var r: [5]f64 = zero
    r[0usize] = 2.10144126479064f64
    r[1usize] = 26.2370141675169f64
    r[2usize] = 21.3688200555087f64
    r[3usize] = 4.6580782871847f64
    r[4usize] = 0.282094791773523f64
    var s: [4]f64 = zero
    s[0usize] = 94.153775055546f64
    s[1usize] = 187.11481179959f64
    s[2usize] = 99.0191814623914f64
    s[3usize] = 18.0124575948747f64
    var ret_val = 0.0f64
    let ax = abs_of(x)
    if ax <= 0.5f64 {
        let t = x * x
        let top = (((a[0usize] * t + a[1usize]) * t + a[2usize]) * t + a[3usize]) * t + a[4usize] + 1.0f64
        let bot = ((b[0usize] * t + b[1usize]) * t + b[2usize]) * t + 1.0f64
        ret_val = 0.5f64 - x * (top / bot) + 0.5f64
        if ind != 0i64 { ret_val = math.exp[f64](t) * ret_val }
        ret ret_val
    }
    if ax <= 4.0f64 {
        let top = ((((((p[0usize] * ax + p[1usize]) * ax + p[2usize]) * ax + p[3usize]) * ax + p[4usize]) * ax + p[5usize]) * ax + p[6usize]) * ax + p[7usize]
        let bot = ((((((q[0usize] * ax + q[1usize]) * ax + q[2usize]) * ax + q[3usize]) * ax + q[4usize]) * ax + q[5usize]) * ax + q[6usize]) * ax + q[7usize]
        ret_val = top / bot
    } else {
        if x <= -5.6f64 {
            ret_val = 2.0f64
            if ind != 0i64 { ret_val = math.exp[f64](x * x) * 2.0f64 }
            ret ret_val
        }
        if ind == 0i64 && (x > 100.0f64 || x * x > 0.0f64 - exparg(1i64)) { ret 0.0f64 }
        let t = 1.0f64 / (x * x)
        let top = (((r[0usize] * t + r[1usize]) * t + r[2usize]) * t + r[3usize]) * t + r[4usize]
        let bot = (((s[0usize] * t + s[1usize]) * t + s[2usize]) * t + s[3usize]) * t + 1.0f64
        ret_val = (c - t * top / bot) / ax
    }
    if ind != 0i64 {
        if x < 0.0f64 { ret_val = math.exp[f64](x * x) * 2.0f64 - ret_val }
    } else {
        let w = x * x
        let t = w
        let e = w - t
        ret_val = (0.5f64 - e + 0.5f64) * math.exp[f64](0.0f64 - t) * ret_val
        if x < 0.0f64 { ret_val = 2.0f64 - ret_val }
    }
    ret ret_val
}

fn gam1(a: f64) -> f64 {
    let d = a - 0.5f64
    var t = a
    if d > 0.0f64 { t = d - 0.5f64 }
    if t < 0.0f64 {
        var r: [9]f64 = zero
        r[0usize] = -0.422784335098468f64
        r[1usize] = -0.771330383816272f64
        r[2usize] = -0.244757765222226f64
        r[3usize] = 0.118378989872749f64
        r[4usize] = 9.30357293360349e-4f64
        r[5usize] = -0.0118290993445146f64
        r[6usize] = 0.00223047661158249f64
        r[7usize] = 2.66505979058923e-4f64
        r[8usize] = -1.32674909766242e-4f64
        let s1 = 0.273076135303957f64
        let s2 = 0.0559398236957378f64
        let top = (((((((r[8usize] * t + r[7usize]) * t + r[6usize]) * t + r[5usize]) * t + r[4usize]) * t + r[3usize]) * t + r[2usize]) * t + r[1usize]) * t + r[0usize]
        let bot = (s2 * t + s1) * t + 1.0f64
        let w = top / bot
        if d > 0.0f64 { ret t * w / a }
        ret a * (w + 0.5f64 + 0.5f64)
    }
    if t == 0.0f64 { ret 0.0f64 }
    var p: [7]f64 = zero
    p[0usize] = 0.577215664901533f64
    p[1usize] = -0.409078193005776f64
    p[2usize] = -0.230975380857675f64
    p[3usize] = 0.0597275330452234f64
    p[4usize] = 0.0076696818164949f64
    p[5usize] = -0.00514889771323592f64
    p[6usize] = 5.89597428611429e-4f64
    var q: [5]f64 = zero
    q[0usize] = 1.0f64
    q[1usize] = 0.427569613095214f64
    q[2usize] = 0.158451672430138f64
    q[3usize] = 0.0261132021441447f64
    q[4usize] = 0.00423244297896961f64
    let top = (((((p[6usize] * t + p[5usize]) * t + p[4usize]) * t + p[3usize]) * t + p[2usize]) * t + p[1usize]) * t + p[0usize]
    let bot = (((q[4usize] * t + q[3usize]) * t + q[2usize]) * t + q[1usize]) * t + 1.0f64
    let w = top / bot
    if d > 0.0f64 { ret t / a * (w - 0.5f64 - 0.5f64) }
    ret a * w
}

fn gamln1(a: f64) -> f64 {
    if a < 0.6f64 {
        let p0 = 0.577215664901533f64
        let p1 = 0.844203922187225f64
        let p2 = -0.168860593646662f64
        let p3 = -0.780427615533591f64
        let p4 = -0.402055799310489f64
        let p5 = -0.0673562214325671f64
        let p6 = -0.00271935708322958f64
        let q1 = 2.88743195473681f64
        let q2 = 3.12755088914843f64
        let q3 = 1.56875193295039f64
        let q4 = 0.361951990101499f64
        let q5 = 0.0325038868253937f64
        let q6 = 6.67465618796164e-4f64
        let w = ((((((p6 * a + p5) * a + p4) * a + p3) * a + p2) * a + p1) * a + p0) / ((((((q6 * a + q5) * a + q4) * a + q3) * a + q2) * a + q1) * a + 1.0f64)
        ret 0.0f64 - a * w
    }
    let r0 = 0.422784335098467f64
    let r1 = 0.848044614534529f64
    let r2 = 0.565221050691933f64
    let r3 = 0.156513060486551f64
    let r4 = 0.017050248402265f64
    let r5 = 4.97958207639485e-4f64
    let s1 = 1.24313399877507f64
    let s2 = 0.548042109832463f64
    let s3 = 0.10155218743983f64
    let s4 = 0.00713309612391f64
    let s5 = 1.16165475989616e-4f64
    let x = a - 0.5f64 - 0.5f64
    let w = (((((r5 * x + r4) * x + r3) * x + r2) * x + r1) * x + r0) / (((((s5 * x + s4) * x + s3) * x + s2) * x + s1) * x + 1.0f64)
    ret x * w
}

fn psi(x0: f64) -> f64 {
    let piov4 = 0.785398163397448f64
    let dx0 = 1.461632144968362341262659542325721325f64
    var p1: [7]f64 = zero
    p1[0usize] = 0.0089538502298197f64
    p1[1usize] = 4.77762828042627f64
    p1[2usize] = 142.441585084029f64
    p1[3usize] = 1186.45200713425f64
    p1[4usize] = 3633.51846806499f64
    p1[5usize] = 4138.10161269013f64
    p1[6usize] = 1305.60269827897f64
    var q1: [6]f64 = zero
    q1[0usize] = 44.8452573429826f64
    q1[1usize] = 520.752771467162f64
    q1[2usize] = 2210.0079924783f64
    q1[3usize] = 3641.27349079381f64
    q1[4usize] = 1908.310765963f64
    q1[5usize] = 6.91091682714533e-6f64
    var p2: [4]f64 = zero
    p2[0usize] = -2.12940445131011f64
    p2[1usize] = -7.01677227766759f64
    p2[2usize] = -4.48616543918019f64
    p2[3usize] = -0.648157123766197f64
    var q2: [4]f64 = zero
    q2[0usize] = 32.2703493791143f64
    q2[1usize] = 89.2920700481861f64
    q2[2usize] = 54.6117738103215f64
    q2[3usize] = 7.77788548522962f64
    var x = x0
    var xmax1 = 2147483647.0f64
    let d2 = 0.5f64 / 2.220446049250313e-16f64
    if xmax1 > d2 { xmax1 = d2 }
    let xsmall = 1e-9f64
    var aug = 0.0f64
    if x < 0.5f64 {
        if abs_of(x) <= xsmall {
            if x == 0.0f64 { ret 0.0f64 }
            aug = -1.0f64 / x
        } else {
            var w = 0.0f64 - x
            var sgn = piov4
            if w <= 0.0f64 {
                w = 0.0f64 - w
                sgn = 0.0f64 - sgn
            }
            if w >= xmax1 { ret 0.0f64 }
            var nq = i64(w)
            w = w - f64(nq)
            nq = i64(w * 4.0f64)
            w = (w - f64(nq) * 0.25f64) * 4.0f64
            var n = nq / 2i64
            if n + n != nq { w = 1.0f64 - w }
            let z = piov4 * w
            var m = n / 2i64
            if m + m != n { sgn = 0.0f64 - sgn }
            n = (nq + 1i64) / 2i64
            m = n / 2i64
            m = m + m
            if m == n {
                if z == 0.0f64 { ret 0.0f64 }
                aug = sgn * (math.cos[f64](z) / math.sin[f64](z) * 4.0f64)
            } else {
                aug = sgn * (math.sin[f64](z) / math.cos[f64](z) * 4.0f64)
            }
        }
        x = 1.0f64 - x
    }
    if x <= 3.0f64 {
        var den = x
        var upper = p1[0usize] * x
        var i = 1usize
        while i <= 5usize {
            den = (den + q1[i - 1usize]) * x
            upper = (upper + p1[i]) * x
            i += 1usize
        }
        den = (upper + p1[6usize]) / (den + q1[5usize])
        let xmx0 = x - dx0
        ret den * xmx0 + aug
    }
    if x < xmax1 {
        let w = 1.0f64 / (x * x)
        var den = w
        var upper = p2[0usize] * w
        var i = 1usize
        while i <= 3usize {
            den = (den + q2[i - 1usize]) * w
            upper = (upper + p2[i]) * w
            i += 1usize
        }
        aug = upper / (den + q2[3usize]) - 0.5f64 / x + aug
    }
    ret aug + math.log[f64](x)
}

fn gamln(a: f64) -> f64 {
    let d = 0.418938533204673f64
    let c0 = 0.0833333333333333f64
    let c1 = -0.00277777777760991f64
    let c2 = 7.9365066682539e-4f64
    let c3 = -5.9520293135187e-4f64
    let c4 = 8.37308034031215e-4f64
    let c5 = -0.00165322962780713f64
    if a <= 0.8f64 { ret gamln1(a) - math.log[f64](a) }
    if a <= 2.25f64 { ret gamln1(a - 0.5f64 - 0.5f64) }
    if a < 10.0f64 {
        let n = i64(a - 1.25f64)
        var t = a
        var w = 1.0f64
        var i = 1i64
        while i <= n {
            t += -1.0f64
            w = w * t
            i += 1i64
        }
        ret gamln1(t - 1.0f64) + math.log[f64](w)
    }
    let t = 1.0f64 / (a * a)
    let w = (((((c5 * t + c4) * t + c3) * t + c2) * t + c1) * t + c0) / a
    ret d + w + (a - 0.5f64) * (math.log[f64](a) - 1.0f64)
}

fn bcorr(a0: f64, b0: f64) -> f64 {
    let c0 = 0.0833333333333333f64
    let c1 = -0.00277777777760991f64
    let c2 = 7.9365066682539e-4f64
    let c3 = -5.9520293135187e-4f64
    let c4 = 8.37308034031215e-4f64
    let c5 = -0.00165322962780713f64
    let a = min2(a0, b0)
    let b = max2(a0, b0)
    let h = a / b
    let c = h / (h + 1.0f64)
    let x = 1.0f64 / (h + 1.0f64)
    let x2 = x * x
    let s3 = x + x2 + 1.0f64
    let s5 = x + x2 * s3 + 1.0f64
    let s7 = x + x2 * s5 + 1.0f64
    let s9 = x + x2 * s7 + 1.0f64
    let s11 = x + x2 * s9 + 1.0f64
    var t = 1.0f64 / b
    t = t * t
    var w = ((((c5 * s11 * t + c4 * s9) * t + c3 * s7) * t + c2 * s5) * t + c1 * s3) * t + c0
    w = w * (c / b)
    t = 1.0f64 / a
    t = t * t
    ret (((((c5 * t + c4) * t + c3) * t + c2) * t + c1) * t + c0) / a + w
}

fn algdiv(a: f64, b: f64) -> f64 {
    let c0 = 0.0833333333333333f64
    let c1 = -0.00277777777760991f64
    let c2 = 7.9365066682539e-4f64
    let c3 = -5.9520293135187e-4f64
    let c4 = 8.37308034031215e-4f64
    let c5 = -0.00165322962780713f64
    var c = 0.0f64
    var d = 0.0f64
    var h = 0.0f64
    var x = 0.0f64
    if a > b {
        h = b / a
        c = 1.0f64 / (h + 1.0f64)
        x = h / (h + 1.0f64)
        d = a + (b - 0.5f64)
    } else {
        h = a / b
        c = h / (h + 1.0f64)
        x = 1.0f64 / (h + 1.0f64)
        d = b + (a - 0.5f64)
    }
    let x2 = x * x
    let s3 = x + x2 + 1.0f64
    let s5 = x + x2 * s3 + 1.0f64
    let s7 = x + x2 * s5 + 1.0f64
    let s9 = x + x2 * s7 + 1.0f64
    let s11 = x + x2 * s9 + 1.0f64
    let t = 1.0f64 / (b * b)
    var w = ((((c5 * s11 * t + c4 * s9) * t + c3 * s7) * t + c2 * s5) * t + c1 * s3) * t + c0
    w = w * (c / b)
    let u = d * alnrel(a / b)
    let v = a * (math.log[f64](b) - 1.0f64)
    if u > v { ret w - v - u }
    ret w - u - v
}

fn gsumln(a: f64, b: f64) -> f64 {
    let x = a + b - 2.0f64
    if x <= 0.25f64 { ret gamln1(x + 1.0f64) }
    if x <= 1.25f64 { ret gamln1(x) + alnrel(x) }
    ret gamln1(x - 1.0f64) + math.log[f64](x * (x + 1.0f64))
}

fn betaln(a0: f64, b0: f64) -> f64 {
    var a = min2(a0, b0)
    var b = max2(a0, b0)
    if a < 8.0f64 {
        if a < 1.0f64 {
            if b < 8.0f64 { ret gamln(a) + (gamln(b) - gamln(a + b)) }
            ret gamln(a) + algdiv(a, b)
        }
        var w = 0.0f64
        var go40 = false
        if a < 2.0f64 {
            if b <= 2.0f64 { ret gamln(a) + gamln(b) - gsumln(a, b) }
            if b < 8.0f64 {
                w = 0.0f64
                go40 = true
            } else {
                ret gamln(a) + algdiv(a, b)
            }
        }
        if !go40 {
            if b <= 1e3f64 {
                let n = i64(a - 1.0f64)
                w = 1.0f64
                var i = 1i64
                while i <= n {
                    a += -1.0f64
                    let h = a / b
                    w = w * (h / (h + 1.0f64))
                    i += 1i64
                }
                w = math.log[f64](w)
                if b >= 8.0f64 { ret w + gamln(a) + algdiv(a, b) }
            } else {
                let n = i64(a - 1.0f64)
                w = 1.0f64
                var i = 1i64
                while i <= n {
                    a += -1.0f64
                    w = w * (a / (a / b + 1.0f64))
                    i += 1i64
                }
                ret math.log[f64](w) - f64(n) * math.log[f64](b) + (gamln(a) + algdiv(a, b))
            }
        }
        let n = i64(b - 1.0f64)
        var z = 1.0f64
        var i = 1i64
        while i <= n {
            b += -1.0f64
            z = z * (b / (a + b))
            i += 1i64
        }
        ret w + math.log[f64](z) + (gamln(a) + (gamln(b) - gsumln(a, b)))
    }
    let e = 0.918938533204673f64
    let w = bcorr(a, b)
    let h = a / b
    let u = 0.0f64 - (a - 0.5f64) * math.log[f64](h / (h + 1.0f64))
    let v = b * alnrel(h)
    if u > v { ret math.log[f64](b) * -0.5f64 + e + w - v - u }
    ret math.log[f64](b) * -0.5f64 + e + w - u - v
}

fn fpser(a: f64, b: f64, x: f64, eps: f64, lg: bool) -> f64 {
    var ans = 0.0f64
    if lg {
        ans = a * math.log[f64](x)
    } else if a > eps * 0.001f64 {
        let t = a * math.log[f64](x)
        if t < exparg(1i64) { ret 0.0f64 }
        ans = math.exp[f64](t)
    } else {
        ans = 1.0f64
    }
    if lg { ans += math.log[f64](b) - math.log[f64](a) } else { ans = ans * (b / a) }
    let tol = eps / a
    var an = a + 1.0f64
    var t = x
    var s = t / an
    var go = true
    while go {
        an += 1.0f64
        t = x * t
        let c = t / an
        s += c
        go = abs_of(c) > tol
    }
    if lg { ans += dist.log1p(a * s) } else { ans = ans * (a * s + 1.0f64) }
    ret ans
}

fn apser(a: f64, b: f64, x: f64, eps: f64) -> f64 {
    let g = 0.577215664901533f64
    let bx = b * x
    var t = x - bx
    var c = 0.0f64
    if b * eps <= 0.02f64 {
        c = math.log[f64](x) + psi(b) + g + t
    } else {
        c = math.log[f64](bx) + g + t
    }
    let tol = eps * 5.0f64 * abs_of(c)
    var j = 1.0f64
    var s = 0.0f64
    var go = true
    while go {
        j += 1.0f64
        t = t * (x - bx / j)
        let aj = t / j
        s += aj
        go = abs_of(aj) > tol
    }
    ret 0.0f64 - a * (c + s)
}

fn bpser(a: f64, b: f64, x: f64, eps: f64, lg: bool) -> f64 {
    if x == 0.0f64 { ret dist.d0(lg) }
    var ans = 0.0f64
    var c = 0.0f64
    var z = 0.0f64
    let a0 = min2(a, b)
    if a0 >= 1.0f64 {
        z = a * math.log[f64](x) - betaln(a, b)
        if lg { ans = z - math.log[f64](a) } else { ans = math.exp[f64](z) / a }
    } else {
        var b0 = max2(a, b)
        if b0 < 8.0f64 {
            if b0 <= 1.0f64 {
                if lg {
                    ans = a * math.log[f64](x)
                } else {
                    ans = math.pow[f64](x, a)
                    if ans == 0.0f64 { ret ans }
                }
                let apb = a + b
                if apb > 1.0f64 {
                    let u = a + b - 1.0f64
                    z = (gam1(u) + 1.0f64) / apb
                } else {
                    z = gam1(apb) + 1.0f64
                }
                c = (gam1(a) + 1.0f64) * (gam1(b) + 1.0f64) / z
                if lg { ans += math.log[f64](c * (b / apb)) } else { ans = ans * (c * (b / apb)) }
            } else {
                var u = gamln1(a0)
                let m = i64(b0 - 1.0f64)
                if m >= 1i64 {
                    c = 1.0f64
                    var i = 1i64
                    while i <= m {
                        b0 += -1.0f64
                        c = c * (b0 / (a0 + b0))
                        i += 1i64
                    }
                    u += math.log[f64](c)
                }
                z = a * math.log[f64](x) - u
                b0 += -1.0f64
                let apb = a0 + b0
                var t = 0.0f64
                if apb > 1.0f64 {
                    u = a0 + b0 - 1.0f64
                    t = (gam1(u) + 1.0f64) / apb
                } else {
                    t = gam1(apb) + 1.0f64
                }
                if lg {
                    ans = z + math.log[f64](a0 / a) + dist.log1p(gam1(b0)) - math.log[f64](t)
                } else {
                    ans = math.exp[f64](z) * (a0 / a) * (gam1(b0) + 1.0f64) / t
                }
            }
        } else {
            let u = gamln1(a0) + algdiv(a0, b0)
            z = a * math.log[f64](x) - u
            if lg { ans = z + math.log[f64](a0 / a) } else { ans = a0 / a * math.exp[f64](z) }
        }
    }
    if ans == dist.d0(lg) || (!lg && a <= eps * 0.1f64) { ret ans }
    let tol = eps / a
    var n = 0.0f64
    var sum = 0.0f64
    var w = 0.0f64
    c = 1.0f64
    var go = true
    while go {
        n += 1.0f64
        c = c * ((0.5f64 - b / n + 0.5f64) * x)
        w = c / (a + n)
        sum += w
        go = n < 1e7f64 && abs_of(w) > tol
    }
    if lg {
        if a * sum > -1.0f64 {
            ans += dist.log1p(a * sum)
        } else {
            ans = 0.0f64 - inf()
        }
    } else if a * sum > -1.0f64 {
        ans = ans * (a * sum + 1.0f64)
    } else {
        ans = 0.0f64
    }
    ret ans
}

fn brcmp1(mu: i64, a: f64, b: f64, x: f64, y: f64, give_log: bool) -> f64 {
    let a0 = min2(a, b)
    if a0 < 8.0f64 {
        var lnx = 0.0f64
        var lny = 0.0f64
        if x <= 0.375f64 {
            lnx = math.log[f64](x)
            lny = alnrel(0.0f64 - x)
        } else if y > 0.375f64 {
            lnx = math.log[f64](x)
            lny = math.log[f64](y)
        } else {
            lnx = alnrel(0.0f64 - y)
            lny = math.log[f64](y)
        }
        var z = a * lnx + b * lny
        if a0 >= 1.0f64 {
            z -= betaln(a, b)
            ret esum(mu, z, give_log)
        }
        var b0 = max2(a, b)
        if b0 >= 8.0f64 {
            let u = gamln1(a0) + algdiv(a0, b0)
            if give_log { ret math.log[f64](a0) + esum(mu, z - u, true) }
            ret a0 * esum(mu, z - u, false)
        } else if b0 <= 1.0f64 {
            let ans = esum(mu, z, give_log)
            var zero_ans = 0.0f64
            if give_log { zero_ans = 0.0f64 - inf() }
            if ans == zero_ans { ret ans }
            let apb = a + b
            var zz = 0.0f64
            if apb > 1.0f64 {
                zz = (gam1(apb - 1.0f64) + 1.0f64) / apb
            } else {
                zz = gam1(apb) + 1.0f64
            }
            if give_log {
                let c = dist.log1p(gam1(a)) + dist.log1p(gam1(b)) - math.log[f64](zz)
                ret ans + math.log[f64](a0) + c - dist.log1p(a0 / b0)
            }
            let c = (gam1(a) + 1.0f64) * (gam1(b) + 1.0f64) / zz
            ret ans * (a0 * c) / (a0 / b0 + 1.0f64)
        }
        var u = gamln1(a0)
        let n = i64(b0 - 1.0f64)
        if n >= 1i64 {
            var c = 1.0f64
            var i = 1i64
            while i <= n {
                b0 += -1.0f64
                c = c * (b0 / (a0 + b0))
                i += 1i64
            }
            u += math.log[f64](c)
        }
        z -= u
        b0 += -1.0f64
        let apb = a0 + b0
        var t = 0.0f64
        if apb > 1.0f64 {
            t = (gam1(apb - 1.0f64) + 1.0f64) / apb
        } else {
            t = gam1(apb) + 1.0f64
        }
        if give_log { ret math.log[f64](a0) + esum(mu, z, true) + dist.log1p(gam1(b0)) - math.log[f64](t) }
        ret a0 * esum(mu, z, false) * (gam1(b0) + 1.0f64) / t
    }
    let const_ = 0.398942280401433f64
    let apb = a + b
    var lambda = a * y - b * x
    if finite(apb) {
        if a <= b { lambda = a - apb * x } else { lambda = apb * y - b }
    }
    var h = 0.0f64
    var x0 = 0.0f64
    var y0 = 0.0f64
    if a > b {
        h = b / a
        x0 = 1.0f64 / (h + 1.0f64)
        y0 = h / (h + 1.0f64)
    } else {
        h = a / b
        x0 = h / (h + 1.0f64)
        y0 = 1.0f64 / (h + 1.0f64)
    }
    let lx0 = 0.0f64 - dist.log1p(b / a)
    var e = 0.0f64 - lambda / a
    var u = 0.0f64
    var v = 0.0f64
    if abs_of(e) > 0.6f64 { u = e - math.log[f64](x / x0) } else { u = rlog1(e) }
    e = lambda / b
    if abs_of(e) > 0.6f64 { v = e - math.log[f64](y / y0) } else { v = rlog1(e) }
    let z = esum(mu, 0.0f64 - (a * u + b * v), give_log)
    if give_log { ret math.log[f64](const_) + (math.log[f64](b) + lx0) / 2.0f64 + z - bcorr(a, b) }
    ret const_ * math.sqrt[f64](b * x0) * z * math.exp[f64](0.0f64 - bcorr(a, b))
}

fn brcomp(a: f64, b: f64, x: f64, y: f64, lg: bool) -> f64 {
    if x == 0.0f64 || y == 0.0f64 { ret dist.d0(lg) }
    let a0 = min2(a, b)
    if a0 < 8.0f64 {
        var lnx = 0.0f64
        var lny = 0.0f64
        if x <= 0.375f64 {
            lnx = math.log[f64](x)
            lny = alnrel(0.0f64 - x)
        } else if y > 0.375f64 {
            lnx = math.log[f64](x)
            lny = math.log[f64](y)
        } else {
            lnx = alnrel(0.0f64 - y)
            lny = math.log[f64](y)
        }
        var z = a * lnx + b * lny
        if a0 >= 1.0f64 {
            z -= betaln(a, b)
            ret dexp(z, lg)
        }
        var b0 = max2(a, b)
        if b0 >= 8.0f64 {
            let u = gamln1(a0) + algdiv(a0, b0)
            if lg { ret math.log[f64](a0) + (z - u) }
            ret a0 * math.exp[f64](z - u)
        }
        if b0 <= 1.0f64 {
            let e_z = dexp(z, lg)
            if !lg && e_z == 0.0f64 { ret 0.0f64 }
            let apb = a + b
            var zz = 0.0f64
            if apb > 1.0f64 {
                zz = (gam1(apb - 1.0f64) + 1.0f64) / apb
            } else {
                zz = gam1(apb) + 1.0f64
            }
            let c = (gam1(a) + 1.0f64) * (gam1(b) + 1.0f64) / zz
            if lg { ret e_z + math.log[f64](a0 * c) - dist.log1p(a0 / b0) }
            ret e_z * (a0 * c) / (a0 / b0 + 1.0f64)
        }
        var u = gamln1(a0)
        let n = i64(b0 - 1.0f64)
        if n >= 1i64 {
            var c = 1.0f64
            var i = 1i64
            while i <= n {
                b0 += -1.0f64
                c = c * (b0 / (a0 + b0))
                i += 1i64
            }
            u = math.log[f64](c) + u
        }
        z -= u
        b0 += -1.0f64
        let apb = a0 + b0
        var t = 0.0f64
        if apb > 1.0f64 {
            u = a0 + b0 - 1.0f64
            t = (gam1(u) + 1.0f64) / apb
        } else {
            t = gam1(apb) + 1.0f64
        }
        if lg { ret math.log[f64](a0) + z + dist.log1p(gam1(b0)) - math.log[f64](t) }
        ret a0 * math.exp[f64](z) * (gam1(b0) + 1.0f64) / t
    }
    let const_ = 0.398942280401433f64
    let apb = a + b
    var lambda = a * y - b * x
    if finite(apb) {
        if a <= b { lambda = a - apb * x } else { lambda = apb * y - b }
    }
    var h = 0.0f64
    var x0 = 0.0f64
    var y0 = 0.0f64
    if a <= b {
        h = a / b
        x0 = h / (h + 1.0f64)
        y0 = 1.0f64 / (h + 1.0f64)
    } else {
        h = b / a
        x0 = 1.0f64 / (h + 1.0f64)
        y0 = h / (h + 1.0f64)
    }
    var e = 0.0f64 - lambda / a
    var u = 0.0f64
    var v = 0.0f64
    if abs_of(e) > 0.6f64 { u = e - math.log[f64](x / x0) } else { u = rlog1(e) }
    e = lambda / b
    if abs_of(e) <= 0.6f64 { v = rlog1(e) } else { v = e - math.log[f64](y / y0) }
    var zz = 0.0f64
    if lg { zz = 0.0f64 - (a * u + b * v) } else { zz = math.exp[f64](0.0f64 - (a * u + b * v)) }
    if lg { ret -0.918938533204672741780329736406f64 + 0.5f64 * math.log[f64](b * x0) + zz - bcorr(a, b) }
    ret const_ * math.sqrt[f64](b * x0) * zz * math.exp[f64](0.0f64 - bcorr(a, b))
}

fn bup(a: f64, b: f64, x: f64, y: f64, n: i64, eps: f64, give_log: bool) -> f64 {
    let apb = a + b
    let ap1 = a + 1.0f64
    var mu = 0i64
    var d = 1.0f64
    if n > 1i64 && a >= 1.0f64 && apb >= ap1 * 1.1f64 {
        mu = i64(abs_of(exparg(1i64)))
        let k0 = i64(exparg(0i64))
        if mu > k0 { mu = k0 }
        d = math.exp[f64](0.0f64 - f64(mu))
    }
    var ret_val = 0.0f64
    if give_log {
        ret_val = brcmp1(mu, a, b, x, y, true) - math.log[f64](a)
    } else {
        ret_val = brcmp1(mu, a, b, x, y, false) / a
    }
    if n == 1i64 || (give_log && ret_val == 0.0f64 - inf()) || (!give_log && ret_val == 0.0f64) { ret ret_val }
    let nm1 = n - 1i64
    var w = d
    var k = 0i64
    if b > 1.0f64 {
        if y > 1e-4f64 {
            let r = (b - 1.0f64) * x / y - a
            if r >= 1.0f64 {
                if r < f64(nm1) { k = i64(r) } else { k = nm1 }
            }
        } else {
            k = nm1
        }
        var i = 0i64
        while i < k {
            let l = f64(i)
            d = d * ((apb + l) / (ap1 + l) * x)
            w += d
            i += 1i64
        }
    }
    var i = k
    var stop = false
    while i < nm1 && !stop {
        let l = f64(i)
        d = d * ((apb + l) / (ap1 + l) * x)
        w += d
        if d <= eps * w { stop = true }
        i += 1i64
    }
    if give_log { ret_val += math.log[f64](w) } else { ret_val = ret_val * w }
    ret ret_val
}

fn bfrac(a: f64, b: f64, x: f64, y: f64, lambda: f64, eps: f64, lg: bool) -> f64 {
    if !finite(lambda) { ret nan() }
    let brc = brcomp(a, b, x, y, lg)
    if brc != brc { ret nan() }
    if !lg && brc == 0.0f64 { ret 0.0f64 }
    let c = lambda + 1.0f64
    let c0 = b / a
    let c1 = 1.0f64 / a + 1.0f64
    let yp1 = y + 1.0f64
    var n = 0.0f64
    var p = 1.0f64
    var s = a + 1.0f64
    var an = 0.0f64
    var bn = 1.0f64
    var anp1 = 1.0f64
    var bnp1 = c / c1
    var r = c1 / c
    var r0 = 0.0f64
    var go = true
    while go {
        n += 1.0f64
        var w = n * x * (b - n)
        let rescale = !finite(w)
        if rescale { w = n * x * ((b - n) * 9.5367431640625e-7f64) }
        var t = n / a
        let e0 = a / s
        let alpha = p * (p + c0) * e0 * e0 * (w * x)
        let e = (t + 1.0f64) / (c1 + t + t)
        var beta = 0.0f64
        if rescale {
            beta = w / s + (n + e * (c + n * yp1)) * 9.5367431640625e-7f64
        } else {
            beta = w / s + (n + e * (c + n * yp1))
        }
        p = t + 1.0f64
        s += 2.0f64
        t = alpha * an + beta * anp1
        an = anp1
        anp1 = t
        t = alpha * bn + beta * bnp1
        bn = bnp1
        bnp1 = t
        r0 = r
        r = anp1 / bnp1
        if abs_of(r - r0) <= eps * r {
            go = false
        } else {
            an = an / bnp1
            bn = bn / bnp1
            anp1 = r
            bnp1 = 1.0f64
            go = n < 1000.0f64
        }
    }
    if lg { ret brc + math.log[f64](r) }
    ret brc * r
}

fn grat_r(a: f64, x: f64, log_r: f64, eps: f64) -> f64 {
    if a * x == 0.0f64 {
        if x <= a { ret math.exp[f64](0.0f64 - log_r) }
        ret 0.0f64
    }
    if a == 0.5f64 {
        if x < 0.25f64 {
            let p = erf_(math.sqrt[f64](x))
            ret (0.5f64 - p + 0.5f64) * math.exp[f64](0.0f64 - log_r)
        }
        let sx = math.sqrt[f64](x)
        ret erfc1(1i64, sx) / sx * 1.772453850905516027298167483341f64
    }
    if x < 1.1f64 {
        var an = 3.0f64
        var c = x
        var sum = x / (a + 3.0f64)
        let tol = eps * 0.1f64 / (a + 1.0f64)
        var t = 0.0f64
        var go = true
        while go {
            an += 1.0f64
            c = c * (0.0f64 - x / an)
            t = c / (a + an)
            sum += t
            go = abs_of(t) > tol
        }
        let j = a * x * ((sum / 6.0f64 - 0.5f64 / (a + 2.0f64)) * x + 1.0f64 / (a + 1.0f64))
        let z = a * math.log[f64](x)
        let h = gam1(a)
        let g = h + 1.0f64
        if (x >= 0.25f64 && a < x / 2.59f64) || z > -0.13394f64 {
            let l = rexpm1(z)
            let q = ((l + 0.5f64 + 0.5f64) * j - l) * g - h
            if q <= 0.0f64 { ret 0.0f64 }
            ret q * math.exp[f64](0.0f64 - log_r)
        }
        let p = math.exp[f64](z) * g * (0.5f64 - j + 0.5f64)
        ret (0.5f64 - p + 0.5f64) * math.exp[f64](0.0f64 - log_r)
    }
    var a2n_1 = 1.0f64
    var a2n = 1.0f64
    var b2n_1 = x
    var b2n = x + (1.0f64 - a)
    var c = 1.0f64
    var am0 = 0.0f64
    var an0 = 0.0f64
    var go = true
    while go {
        a2n_1 = x * a2n + c * a2n_1
        b2n_1 = x * b2n + c * b2n_1
        am0 = a2n_1 / b2n_1
        c += 1.0f64
        let c_a = c - a
        a2n = a2n_1 + c_a * a2n
        b2n = b2n_1 + c_a * b2n
        an0 = a2n / b2n
        go = abs_of(an0 - am0) >= eps * an0
    }
    ret an0
}

// bgrat: asymptotic expansion for large a, small b; (w, ierr) with w updated.
fn bgrat(a: f64, b: f64, x: f64, y: f64, w0: f64, eps: f64, log_w: bool) -> (f64, i64) {
    var c: [30]f64 = zero
    var d: [30]f64 = zero
    var w = w0
    let bm1 = b - 0.5f64 - 0.5f64
    let nu = a + bm1 * 0.5f64
    var lnx = alnrel(0.0f64 - y)
    if y > 0.375f64 { lnx = math.log[f64](x) }
    let z = 0.0f64 - nu * lnx
    if b * z == 0.0f64 { ret (w, 1i64) }
    let log_r = math.log[f64](b) + dist.log1p(gam1(b)) + b * math.log[f64](z) + nu * lnx
    let log_u = log_r - (algdiv(b, a) + b * math.log[f64](nu))
    let u = math.exp[f64](log_u)
    if log_u == 0.0f64 - inf() { ret (w, 2i64) }
    let u_0 = u == 0.0f64
    var l = 0.0f64
    if log_w {
        if w != 0.0f64 - inf() { l = math.exp[f64](w - log_u) }
    } else {
        if w != 0.0f64 { l = math.exp[f64](math.log[f64](w) - log_u) }
    }
    let q_r = grat_r(b, z, log_r, eps)
    let v = 0.25f64 / (nu * nu)
    let t2 = lnx * 0.25f64 * lnx
    var j = q_r
    var sum = j
    var t = 1.0f64
    var cn = 1.0f64
    var n2 = 0.0f64
    var ierr = 0i64
    var n = 1i64
    var stop = false
    while n <= 30i64 && !stop {
        let bp2n = b + n2
        j = (bp2n * (bp2n + 1.0f64) * j + (z + bp2n + 1.0f64) * t) * v
        n2 += 2.0f64
        t = t * t2
        cn = cn / (n2 * (n2 + 1.0f64))
        let nm1 = n - 1i64
        c[usize(nm1)] = cn
        var s = 0.0f64
        if n > 1i64 {
            var coef = b - f64(n)
            var i = 1i64
            while i <= nm1 {
                s += coef * c[usize(i - 1i64)] * d[usize(nm1 - i)]
                coef += b
                i += 1i64
            }
        }
        d[usize(nm1)] = bm1 * cn + s / f64(n)
        let dj = d[usize(nm1)] * j
        sum += dj
        if sum <= 0.0f64 {
            ierr = 3i64
            ret (w, ierr)
        }
        if abs_of(dj) <= eps * (sum + l) {
            ierr = 0i64
            stop = true
        } else if n == 30i64 {
            ierr = 4i64
        }
        n += 1i64
    }
    if log_w {
        // logspace_add(w, log_u + log(sum))
        let lx = w
        let ly = log_u + math.log[f64](sum)
        w = max2(lx, ly) + dist.log1p(math.exp[f64](0.0f64 - abs_of(lx - ly)))
    } else {
        if u_0 { w = w + math.exp[f64](log_u + math.log[f64](sum)) } else { w = w + u * sum }
    }
    ret (w, ierr)
}

fn basym(a: f64, b: f64, lambda: f64, eps: f64, lg: bool) -> f64 {
    let e0 = 1.12837916709551f64
    let e1 = 0.353553390593274f64
    let ln_e0 = 0.120782237635245f64
    var a0: [21]f64 = zero
    var b0: [21]f64 = zero
    var c: [21]f64 = zero
    var d: [21]f64 = zero
    let f = a * rlog1(0.0f64 - lambda / a) + b * rlog1(lambda / b)
    var t = 0.0f64
    if lg {
        t = 0.0f64 - f
    } else {
        t = math.exp[f64](0.0f64 - f)
        if t == 0.0f64 { ret 0.0f64 }
    }
    let z0 = math.sqrt[f64](f)
    let z = z0 / e1 * 0.5f64
    let z2 = f + f
    var h = 0.0f64
    var r0 = 0.0f64
    var r1 = 0.0f64
    var w0 = 0.0f64
    if a < b {
        h = a / b
        r0 = 1.0f64 / (h + 1.0f64)
        r1 = (b - a) / b
        w0 = 1.0f64 / math.sqrt[f64](a * (h + 1.0f64))
    } else {
        h = b / a
        r0 = 1.0f64 / (h + 1.0f64)
        r1 = (b - a) / a
        w0 = 1.0f64 / math.sqrt[f64](b * (h + 1.0f64))
    }
    a0[0usize] = r1 * 0.66666666666666663f64
    c[0usize] = a0[0usize] * -0.5f64
    d[0usize] = 0.0f64 - c[0usize]
    var j0 = 0.5f64 / e0 * erfc1(1i64, z0)
    var j1 = e1
    var sum = j0 + d[0usize] * w0 * j1
    var s = 1.0f64
    let h2 = h * h
    var hn = 1.0f64
    var w = w0
    var znm1 = z
    var zn = z2
    var n = 2i64
    var stop = false
    while n <= 20i64 && !stop {
        hn = hn * h2
        a0[usize(n - 1i64)] = r0 * 2.0f64 * (h * hn + 1.0f64) / (f64(n) + 2.0f64)
        let np1 = n + 1i64
        s += hn
        a0[usize(np1 - 1i64)] = r1 * 2.0f64 * s / (f64(n) + 3.0f64)
        var i = n
        while i <= np1 {
            let r = (f64(i) + 1.0f64) * -0.5f64
            b0[0usize] = r * a0[0usize]
            var m = 2i64
            while m <= i {
                var bsum = 0.0f64
                var jj = 1i64
                while jj <= m - 1i64 {
                    let mmj = m - jj
                    bsum += (f64(jj) * r - f64(mmj)) * a0[usize(jj - 1i64)] * b0[usize(mmj - 1i64)]
                    jj += 1i64
                }
                b0[usize(m - 1i64)] = r * a0[usize(m - 1i64)] + bsum / f64(m)
                m += 1i64
            }
            c[usize(i - 1i64)] = b0[usize(i - 1i64)] / (f64(i) + 1.0f64)
            var dsum = 0.0f64
            var jj = 1i64
            while jj <= i - 1i64 {
                dsum += d[usize(i - jj - 1i64)] * c[usize(jj - 1i64)]
                jj += 1i64
            }
            d[usize(i - 1i64)] = 0.0f64 - (dsum + c[usize(i - 1i64)])
            i += 1i64
        }
        j0 = e1 * znm1 + (f64(n) - 1.0f64) * j0
        j1 = e1 * zn + f64(n) * j1
        znm1 = z2 * znm1
        zn = z2 * zn
        w = w * w0
        let t0 = d[usize(n - 1i64)] * w * j0
        w = w * w0
        let t1 = d[usize(np1 - 1i64)] * w * j1
        sum += t0 + t1
        if abs_of(t0) + abs_of(t1) <= eps * sum { stop = true }
        n += 2i64
    }
    if lg { ret ln_e0 + t - bcorr(a, b) + math.log[f64](sum) }
    let u = math.exp[f64](0.0f64 - bcorr(a, b))
    ret e0 * t * u * sum
}

// bratio(a, b, x, y, log_p): (w, w1, ierr).
fn bratio(a: f64, b: f64, x: f64, y: f64, lg: bool) -> (f64, f64, i64) {
    var w = dist.d0(lg)
    var w1 = dist.d0(lg)
    var ierr = 0i64
    var eps = 2.0f64 * 1.1102230246251565e-16f64
    if x != x || y != y || a != a || b != b { ret (w, w1, 9i64) }
    if a < 0.0f64 || b < 0.0f64 { ret (w, w1, 1i64) }
    if a == 0.0f64 && b == 0.0f64 { ret (w, w1, 2i64) }
    if x < 0.0f64 || x > 1.0f64 { ret (w, w1, 3i64) }
    if y < 0.0f64 || y > 1.0f64 { ret (w, w1, 4i64) }
    let z = x + y - 0.5f64 - 0.5f64
    if abs_of(z) > eps * 3.0f64 { ret (w, w1, 5i64) }
    if x == 0.0f64 {
        if a == 0.0f64 { ret (w, w1, 6i64) }
        ret (dist.d0(lg), dist.d1(lg), 0i64)
    }
    if y == 0.0f64 {
        if b == 0.0f64 { ret (w, w1, 7i64) }
        ret (dist.d1(lg), dist.d0(lg), 0i64)
    }
    if a == 0.0f64 { ret (dist.d1(lg), dist.d0(lg), 0i64) }
    if b == 0.0f64 { ret (dist.d0(lg), dist.d1(lg), 0i64) }
    eps = max2(eps, 1e-15f64)
    let a_lt_b = a < b
    var big = a
    if a_lt_b { big = b }
    if big < eps * 0.001f64 {
        if lg {
            if a_lt_b {
                w = dist.log1p(0.0f64 - a / (a + b))
                w1 = math.log[f64](a / (a + b))
            } else {
                w = math.log[f64](b / (a + b))
                w1 = dist.log1p(0.0f64 - b / (a + b))
            }
        } else {
            w = b / (a + b)
            w1 = a / (a + b)
        }
        ret (w, w1, 0i64)
    }
    // labels: 1 w_bpser, 2 w1_bpser, 3 bfrac, 4 L140, 5 end_from_w, 6 end_from_w1, 7 end_from_w1_log, 8 end, 9 L131
    var lab = 0i64
    var do_swap = false
    var a0 = a
    var b0 = b
    var x0 = x
    var y0 = y
    var lambda = 0.0f64
    var n = 0i64
    var did_bup = false
    if min2(a, b) <= 1.0f64 {
        do_swap = x > 0.5f64
        if do_swap {
            a0 = b
            x0 = y
            b0 = a
            y0 = x
        }
        if b0 < min2(eps, eps * a0) {
            w = fpser(a0, b0, x0, eps, lg)
            if lg { w1 = dist.log1_exp(w) } else { w1 = 0.5f64 - w + 0.5f64 }
            lab = 8i64
        } else if a0 < min2(eps, eps * b0) && b0 * x0 <= 1.0f64 {
            w1 = apser(a0, b0, x0, eps)
            lab = 6i64
        } else {
            if max2(a0, b0) > 1.0f64 {
                if b0 <= 1.0f64 {
                    lab = 1i64
                } else if x0 >= 0.29f64 {
                    lab = 2i64
                } else if x0 < 0.1f64 && math.pow[f64](x0 * b0, a0) <= 0.7f64 {
                    lab = 1i64
                } else if b0 > 15.0f64 {
                    w1 = 0.0f64
                    lab = 9i64
                }
            } else {
                if a0 >= min2(0.2f64, b0) {
                    lab = 1i64
                } else if math.pow[f64](x0, a0) <= 0.9f64 {
                    lab = 1i64
                } else if x0 >= 0.3f64 {
                    lab = 2i64
                }
            }
            if lab == 0i64 {
                n = 20i64
                w1 = bup(b0, a0, y0, x0, n, eps, false)
                did_bup = true
                b0 += f64(n)
                lab = 9i64
            }
            if lab == 9i64 {
                let (nw1, ie1) = bgrat(b0, a0, y0, x0, w1, 15.0f64 * eps, false)
                w1 = nw1
                var ierr1 = ie1
                if w1 == 0.0f64 || (0.0f64 < w1 && w1 < 2.2250738585072014e-308f64) {
                    if did_bup {
                        w1 = bup(b0 - f64(n), a0, y0, x0, n, eps, true)
                    } else {
                        w1 = 0.0f64 - inf()
                    }
                    let (nw2, ie2) = bgrat(b0, a0, y0, x0, w1, 15.0f64 * eps, true)
                    w1 = nw2
                    ierr1 = ie2
                    if ierr1 != 0i64 { ierr = 10i64 + ierr1 }
                    lab = 7i64
                } else {
                    if ierr1 != 0i64 { ierr = 10i64 + ierr1 }
                    lab = 6i64
                }
            }
        }
    } else {
        lambda = a * y - b * x
        if finite(a + b) {
            if a > b { lambda = (a + b) * y - b } else { lambda = a - (a + b) * x }
        }
        do_swap = lambda < 0.0f64
        if do_swap {
            lambda = 0.0f64 - lambda
            a0 = b
            x0 = y
            b0 = a
            y0 = x
        }
        if b0 < 40.0f64 {
            if b0 * x0 <= 0.7f64 || (lg && lambda > 650.0f64) { lab = 1i64 } else { lab = 4i64 }
        } else if a0 > b0 {
            if b0 <= 100.0f64 || lambda > b0 * 0.03f64 { lab = 3i64 }
        } else if a0 <= 100.0f64 {
            lab = 3i64
        } else if lambda > a0 * 0.03f64 {
            lab = 3i64
        }
        if lab == 0i64 {
            w = basym(a0, b0, lambda, eps * 100.0f64, lg)
            if lg { w1 = dist.log1_exp(w) } else { w1 = 0.5f64 - w + 0.5f64 }
            lab = 8i64
        }
    }
    if lab == 1i64 {
        w = bpser(a0, b0, x0, eps, lg)
        if lg { w1 = dist.log1_exp(w) } else { w1 = 0.5f64 - w + 0.5f64 }
        lab = 8i64
    } else if lab == 2i64 {
        w1 = bpser(b0, a0, y0, eps, lg)
        if lg { w = dist.log1_exp(w1) } else { w = 0.5f64 - w1 + 0.5f64 }
        lab = 8i64
    } else if lab == 3i64 {
        w = bfrac(a0, b0, x0, y0, lambda, eps * 15.0f64, lg)
        if lg { w1 = dist.log1_exp(w) } else { w1 = 0.5f64 - w + 0.5f64 }
        lab = 8i64
    } else if lab == 4i64 {
        n = i64(b0)
        b0 -= f64(n)
        if b0 == 0.0f64 {
            n -= 1i64
            b0 = 1.0f64
        }
        w = bup(b0, a0, y0, x0, n, eps, false)
        if w < 2.2250738585072014e-308f64 && lg {
            b0 += f64(n)
            w = bpser(a0, b0, x0, eps, lg)
            if lg { w1 = dist.log1_exp(w) } else { w1 = 0.5f64 - w + 0.5f64 }
            lab = 8i64
        } else if x0 <= 0.7f64 {
            w += bpser(a0, b0, x0, eps, false)
            lab = 5i64
        } else {
            if a0 <= 15.0f64 {
                n = 20i64
                w += bup(a0, b0, x0, y0, n, eps, false)
                a0 += f64(n)
            }
            let (nw, ie) = bgrat(a0, b0, x0, y0, w, 15.0f64 * eps, false)
            w = nw
            if ie != 0i64 { ierr = 10i64 + ie }
            lab = 5i64
        }
    }
    if lab == 5i64 {
        if lg {
            w1 = dist.log1p(0.0f64 - w)
            w = math.log[f64](w)
        } else {
            w1 = 0.5f64 - w + 0.5f64
        }
    } else if lab == 6i64 {
        if lg {
            w = dist.log1p(0.0f64 - w1)
            w1 = math.log[f64](w1)
        } else {
            w = 0.5f64 - w1 + 0.5f64
        }
    } else if lab == 7i64 {
        if lg {
            w = dist.log1_exp(w1)
        } else {
            w = 0.0f64 - dist.expm1(w1)
            w1 = math.exp[f64](w1)
        }
    }
    if do_swap {
        let t = w
        w = w1
        w1 = t
    }
    ret (w, w1, ierr)
}
