// Complex arithmetic over `e.math`, for `f32` and `f64`. The formulas are the textbook
// ones with the two classic guards: `abs` is scaled so that neither part overflows in
// the square, and `div` is Smith's, so a large divisor does not overflow either.
//
// ponytail: C99 Annex G's table of infinite and NaN operands is not reproduced; those
// operands flow through the real formulas and mostly come out NaN where Annex G names
// an infinity. Finite arguments, signed zeros and the branch cuts (the negative real
// axis for `log`, `sqrt`, `pow`) follow the Annex through `math.atan2`'s sign rules.

use e.math

type Complex[F: type] = struct { re: F, im: F }

fn zero_of[F: type]() -> F {
    var none: F = zero
    ret none
}

fn make[F: type](re: F, im: F) -> Complex[F] {
    var z: Complex[F] = zero
    z.re = re
    z.im = im
    ret z
}

fn add[F: type](a: Complex[F], b: Complex[F]) -> Complex[F] { ret make[F](a.re + b.re, a.im + b.im) }

fn sub[F: type](a: Complex[F], b: Complex[F]) -> Complex[F] { ret make[F](a.re - b.re, a.im - b.im) }

fn mul[F: type](a: Complex[F], b: Complex[F]) -> Complex[F] {
    ret make[F](a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re)
}

// Scale both operands by the largest divisor component before products can overflow.
fn div[F: type](a: Complex[F], b: Complex[F]) -> Complex[F] {
    var scale = math.abs[F](b.re)
    if math.abs[F](b.im) > scale { scale = math.abs[F](b.im) }
    let ar = a.re / scale
    let ai = a.im / scale
    let br = b.re / scale
    let bi = b.im / scale
    let denominator = br * br + bi * bi
    ret make[F]((ar * br + ai * bi) / denominator, (ai * br - ar * bi) / denominator)
}

fn neg[F: type](z: Complex[F]) -> Complex[F] { ret make[F](zero_of[F]() - z.re, zero_of[F]() - z.im) }

fn conj[F: type](z: Complex[F]) -> Complex[F] { ret make[F](z.re, zero_of[F]() - z.im) }

// |z| without squaring either part on its own.
fn abs[F: type](z: Complex[F]) -> F {
    let x = math.abs[F](z.re)
    let y = math.abs[F](z.im)
    var big = x
    var small = y
    if y > x {
        big = y
        small = x
    }
    if big == zero_of[F]() { ret zero_of[F]() }
    let ratio = small / big
    ret big * math.sqrt[F](F(1.0f64) + ratio * ratio)
}

fn arg[F: type](z: Complex[F]) -> F { ret math.atan2[F](z.im, z.re) }

fn exp[F: type](z: Complex[F]) -> Complex[F] {
    let scale = math.exp[F](z.re)
    ret make[F](scale * math.cos[F](z.im), scale * math.sin[F](z.im))
}

fn log[F: type](z: Complex[F]) -> Complex[F] { ret make[F](math.log[F](abs[F](z)), arg[F](z)) }

// The principal root, in the right half-plane, with the sign of the imaginary part
// carried across the cut on the negative real axis.
fn sqrt[F: type](z: Complex[F]) -> Complex[F] {
    let modulus = abs[F](z)
    if modulus == zero_of[F]() { ret make[F](zero_of[F](), z.im) }
    let t = math.sqrt[F]((math.abs[F](z.re) + modulus) * F(0.5f64))
    if z.re >= zero_of[F]() { ret make[F](t, z.im / (t + t)) }
    ret make[F](math.abs[F](z.im) / (t + t), math.copysign[F](t, z.im))
}

fn pow[F: type](z: Complex[F], w: Complex[F]) -> Complex[F] {
    if z.re == zero_of[F]() && z.im == zero_of[F]() {
        if w.re == zero_of[F]() && w.im == zero_of[F]() { ret make[F](F(1.0f64), zero_of[F]()) }
        // A zero base has a finite zero result only for positive real
        // exponents. A real reciprocal is infinite; zero-real and non-real
        // exponents have no finite principal value.
        if w.re > zero_of[F]() { ret make[F](zero_of[F](), zero_of[F]()) }
        if w.im == zero_of[F]() && w.re < zero_of[F]() { ret make[F](F(1.0f64) / zero_of[F](), zero_of[F]()) }
        let invalid = zero_of[F]() / zero_of[F]()
        ret make[F](invalid, invalid)
    }
    ret exp[F](mul[F](w, log[F](z)))
}

fn cosh_of[F: type](x: F) -> F {
    let ax = math.abs[F](x)
    if ax < F(0.5f64) {
        let x2 = x * x
        var tail = F(0.000000000011470745597729f64)
        tail = F(0.00000000208767569878681f64) + x2 * tail
        tail = F(0.0000002755731922398589f64) + x2 * tail
        tail = F(0.000024801587301587f64) + x2 * tail
        tail = F(0.001388888888888889f64) + x2 * tail
        tail = F(0.041666666666666666f64) + x2 * tail
        tail = F(0.5f64) + x2 * tail
        ret F(1.0f64) + x2 * tail
    }
    // Form each half before the final multiplication: exp(|x|) itself can
    // overflow although cosh(x) still fits.
    let half = math.exp[F](ax * F(0.5f64))
    let inverse = F(1.0f64) / half
    ret (half * F(0.5f64)) * half + (inverse * F(0.5f64)) * inverse
}

fn sinh_of[F: type](x: F) -> F {
    let ax = math.abs[F](x)
    if ax < F(0.5f64) {
        let x2 = x * x
        var tail = F(0.0000000000007647163731819816f64)
        tail = F(0.00000000016059043836821615f64) + x2 * tail
        tail = F(0.00000002505210838544172f64) + x2 * tail
        tail = F(0.0000027557319223985893f64) + x2 * tail
        tail = F(0.0001984126984126984f64) + x2 * tail
        tail = F(0.008333333333333333f64) + x2 * tail
        tail = F(0.16666666666666667f64) + x2 * tail
        ret x * (F(1.0f64) + x2 * tail)
    }
    let half = math.exp[F](ax * F(0.5f64))
    let inverse = F(1.0f64) / half
    let magnitude = (half * F(0.5f64)) * half - (inverse * F(0.5f64)) * inverse
    if x < zero_of[F]() { ret zero_of[F]() - magnitude }
    ret magnitude
}

// Multiplying an exact zero by an overflowing hyperbolic value would form NaN.
// Compose the two signs with finite units instead, so the analytic signed zero stays.
fn trigonometric_product[F: type](factor: F, hyperbolic: F) -> F {
    if factor != zero_of[F]() { ret factor * hyperbolic }
    let factor_sign = math.copysign[F](F(1.0f64), factor)
    let hyperbolic_sign = math.copysign[F](F(1.0f64), hyperbolic)
    ret math.copysign[F](zero_of[F](), factor_sign * hyperbolic_sign)
}

fn negative_trigonometric_product[F: type](factor: F, hyperbolic: F) -> F {
    if factor != zero_of[F]() { ret zero_of[F]() - factor * hyperbolic }
    let factor_sign = math.copysign[F](F(1.0f64), factor)
    let hyperbolic_sign = math.copysign[F](F(1.0f64), hyperbolic)
    ret math.copysign[F](zero_of[F](), zero_of[F]() - factor_sign * hyperbolic_sign)
}

fn sin[F: type](z: Complex[F]) -> Complex[F] {
    let sine = math.sin[F](z.re)
    let cosine = math.cos[F](z.re)
    ret make[F](trigonometric_product(sine, cosh_of[F](z.im)), trigonometric_product(cosine, sinh_of[F](z.im)))
}

fn cos[F: type](z: Complex[F]) -> Complex[F] {
    ret make[F](
        trigonometric_product(math.cos[F](z.re), cosh_of[F](z.im)),
        negative_trigonometric_product(math.sin[F](z.re), sinh_of[F](z.im)),
    )
}

fn tan[F: type](z: Complex[F]) -> Complex[F] { ret div[F](sin[F](z), cos[F](z)) }
