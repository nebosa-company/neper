// `e.algo.complex`: the arithmetic, Smith's division, the scaled modulus, the principal
// square root on both sides of the cut, exp, log, pow, and the trigonometric functions
// against closed forms. Every check has its own exit code.
use e.os
use e.mem
use e.algo.complex as cx

fn near(got: f64, want: f64) -> bool {
    var d = got - want
    if d < 0.0 { d = 0.0 - d }
    ret d <= 0.000000001
}

fn finite(v: f64) -> bool { ret v - v == 0.0 }

fn main() {
    let a = cx.make[f64](3.0, 4.0)
    let b = cx.make[f64](1.0, -2.0)
    let s = cx.add[f64](a, b)
    let p = cx.mul[f64](a, b)
    let q = cx.div[f64](a, b)
    if s.re != 4.0 || s.im != 2.0 { os.exit(1) }
    if p.re != 11.0 || p.im != -2.0 { os.exit(2) }
    if !near(q.re, -1.0) || !near(q.im, 2.0) { os.exit(3) }
    if cx.abs[f64](a) != 5.0 || !near(cx.arg[f64](cx.make[f64](0.0, 1.0)), 1.5707963267948966) { os.exit(4) }
    let r = cx.sqrt[f64](cx.make[f64](-4.0, 0.0))
    if !near(r.re, 0.0) || !near(r.im, 2.0) { os.exit(5) }
    let rn = cx.sqrt[f64](cx.make[f64](-4.0, -0.0))
    if !near(rn.re, 0.0) || !near(rn.im, -2.0) { os.exit(6) }
    let e = cx.exp[f64](cx.make[f64](0.0, 3.141592653589793))
    if !near(e.re, -1.0) || !near(e.im, 0.0) { os.exit(7) }
    let l = cx.log[f64](cx.make[f64](-1.0, 0.0))
    if !near(l.re, 0.0) || !near(l.im, 3.141592653589793) { os.exit(8) }
    let w = cx.pow[f64](cx.make[f64](0.0, 1.0), cx.make[f64](2.0, 0.0))
    if !near(w.re, -1.0) || !near(w.im, 0.0) { os.exit(9) }
    let sn = cx.sin[f64](cx.make[f64](0.0, 1.0))
    if !near(sn.re, 0.0) || !near(sn.im, 1.1752011936438014) { os.exit(10) }
    let cs = cx.cos[f64](cx.make[f64](0.0, 1.0))
    if !near(cs.re, 1.5430806348152437) || !near(cs.im, 0.0) { os.exit(11) }
    let tn = cx.tan[f64](cx.make[f64](1.0, 1.0))
    if !near(tn.re, 0.2717525853195118) || !near(tn.im, 1.0839233273386946) { os.exit(12) }
    let f = cx.mul[f32](cx.make[f32](1.5, 2.0), cx.conj[f32](cx.make[f32](1.5, 2.0)))
    if f.re != 6.25 || f.im != 0.0 { os.exit(13) }
    let z0 = cx.pow[f64](cx.make[f64](0.0, 0.0), cx.make[f64](0.0, 0.0))
    if z0.re != 1.0 { os.exit(14) }
    let inverse_zero = cx.pow[f64](cx.make[f64](0.0, 0.0), cx.make[f64](-1.0, 0.0))
    if inverse_zero.re != inverse_zero.re || inverse_zero.re <= 1.0e308 || inverse_zero.im != 0.0 { os.exit(17) }
    let inverse_zero32 = cx.pow[f32](cx.make[f32](0.0f32, 0.0f32), cx.make[f32](-1.0f32, 0.0f32))
    if inverse_zero32.re != inverse_zero32.re || inverse_zero32.re <= 1.0e30f32 || inverse_zero32.im != 0.0f32 { os.exit(17) }
    // Near the real axis, the hyperbolic helpers must retain the tiny
    // imaginary terms used by sin, cos, and tan rather than cancel them away.
    let tiny_im = 0.000000000001f64
    let near_axis_sin = cx.sin[f64](cx.make[f64](1.0, tiny_im))
    let near_axis_cos = cx.cos[f64](cx.make[f64](1.0, tiny_im))
    let near_axis_tan = cx.tan[f64](cx.make[f64](1.0, tiny_im))
    if !near(near_axis_sin.im / tiny_im, 0.5403023058681398) { os.exit(19) }
    if !near(near_axis_cos.im / tiny_im, -0.8414709848078965) { os.exit(19) }
    if !near(near_axis_tan.im / tiny_im, 3.425518820814759) { os.exit(19) }
    // 0^w with a non-real exponent or zero real exponent has no finite
    // principal value; it must not be reported as a harmless zero.
    let imaginary_zero_power = cx.pow[f64](cx.make[f64](0.0, 0.0), cx.make[f64](0.0, 1.0))
    if imaginary_zero_power.re == imaginary_zero_power.re || imaginary_zero_power.im == imaginary_zero_power.im { os.exit(20) }
    let nonreal_reciprocal = cx.pow[f64](cx.make[f64](0.0, 0.0), cx.make[f64](-1.0, 1.0))
    if nonreal_reciprocal.re == nonreal_reciprocal.re || nonreal_reciprocal.im == nonreal_reciprocal.im { os.exit(20) }
    let big = cx.abs[f64](cx.make[f64](1.0e200, 1.0e200))
    if !near(big / 1.0e200, 1.4142135623730951) { os.exit(15) }
    // #1082: sinh/cosh at 710 remain finite, even though exp(710) does not.
    let large_sin = cx.sin[f64](cx.make[f64](0.0, 710.0))
    let negative_large_sin = cx.sin[f64](cx.make[f64](0.0, -710.0))
    let large_cos = cx.cos[f64](cx.make[f64](0.0, 710.0))
    if large_sin.re != 0.0 || !finite(large_sin.im) || large_sin.im < 1.0e307 || !finite(negative_large_sin.im) || negative_large_sin.im > -1.0e307 || !finite(large_cos.re) || large_cos.re < 1.0e307 { os.exit(18) }
    let large_sin32 = cx.sin[f32](cx.make[f32](0.0f32, 89.0f32))
    if large_sin32.re != 0.0f32 || large_sin32.im != large_sin32.im || large_sin32.im < 1.0e37f32 { os.exit(18) }
    // #1574: keep finite self-division finite after normalizing the divisor, and
    // preserve zero signs instead of evaluating exact-zero times overflowing sinh/cosh.
    let huge = cx.make[f64](1.0e308, 1.0e308)
    let huge_self = cx.div[f64](huge, huge)
    if huge_self.re != 1.0 || mem.bitcast[u64](huge_self.im) != 0u64 { os.exit(21) }
    let overflowing_sin = cx.sin[f64](cx.make[f64](0.0, 720.0))
    let overflowing_sin_negative_zero = cx.sin[f64](cx.make[f64](-0.0, 720.0))
    let overflowing_cos = cx.cos[f64](cx.make[f64](0.0, 720.0))
    let overflowing_cos_negative_zero = cx.cos[f64](cx.make[f64](-0.0, 720.0))
    if overflowing_sin.re != overflowing_sin.re || overflowing_sin.im != overflowing_sin.im || mem.bitcast[u64](overflowing_sin.re) != 0u64 { os.exit(22) }
    if overflowing_sin_negative_zero.re != overflowing_sin_negative_zero.re || mem.bitcast[u64](overflowing_sin_negative_zero.re) != 9223372036854775808u64 { os.exit(23) }
    if overflowing_cos.re != overflowing_cos.re || overflowing_cos.im != overflowing_cos.im || mem.bitcast[u64](overflowing_cos.im) != 9223372036854775808u64 { os.exit(24) }
    if overflowing_cos_negative_zero.im != overflowing_cos_negative_zero.im || mem.bitcast[u64](overflowing_cos_negative_zero.im) != 0u64 { os.exit(25) }
    let n = cx.neg[f64](a)
    let d = cx.sub[f64](a, cx.neg[f64](n))
    if n.re != -3.0 || n.im != -4.0 || d.re != 0.0 || d.im != 0.0 { os.exit(16) }
    os.exit(0)
}
