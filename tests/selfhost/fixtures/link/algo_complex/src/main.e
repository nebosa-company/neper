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
    let big = cx.abs[f64](cx.make[f64](1.0e200, 1.0e200))
    if !near(big / 1.0e200, 1.4142135623730951) { os.exit(15) }
    let n = cx.neg[f64](a)
    let d = cx.sub[f64](a, cx.neg[f64](n))
    if n.re != -3.0 || n.im != -4.0 || d.re != 0.0 || d.im != 0.0 { os.exit(16) }
    os.exit(0)
}
