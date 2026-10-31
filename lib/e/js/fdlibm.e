// fdlibm (Sun Microsystems, 1993) ports of expm1, log1p and the hyperbolic functions, exact to the bits the specification's tests probe.
// The constants are the published decimals stored as their bits.

use e.math
use e.mem

fn k(bits: u64) -> f64 { ret mem.bitcast[f64](bits) }
fn hw(x: f64) -> u32 { ret u32(mem.bitcast[u64](x) >> 32u32) }
fn lw(x: f64) -> u32 { ret u32(mem.bitcast[u64](x) & 4294967295u64) }
fn whw(x: f64, high: u32) -> f64 { ret mem.bitcast[f64]((u64(high) << 32u32) | (mem.bitcast[u64](x) & 4294967295u64)) }
fn nan_f64() -> f64 { ret k(9221120237041090560u64) }
fn inf_f64() -> f64 { ret k(9218868437227405312u64) }

fn c_o_threshold() -> f64 { ret k(4649454530587146735u64) }
fn c_ln2_hi() -> f64 { ret k(4604418534311723008u64) }
fn c_ln2_lo() -> f64 { ret k(4461442080421002358u64) }
fn c_invln2() -> f64 { ret k(4609176140021203710u64) }
fn c_ln2() -> f64 { ret k(4604418534313441775u64) }
fn c_two54() -> f64 { ret k(4850376798678024192u64) }

fn expm1_64(x0: f64) -> f64 {
    var x = x0
    let hx0 = hw(x)
    let xsb = hx0 >> 31u32
    let hx = hx0 & 2147483647u32
    var kk = 0i64
    var c = 0.0f64
    if hx >= 1078159482u32 {
        if hx >= 1082535490u32 {
            if hx >= 2146435072u32 {
                if ((hx & 1048575u32) | lw(x)) != 0u32 { ret x + x }
                if xsb == 0u32 { ret x }
                ret -1.0f64
            }
            if x > c_o_threshold() { ret inf_f64() }
        }
        if xsb != 0u32 { ret -1.0f64 }
    }
    if hx > 1071001154u32 {
        var hi = 0.0f64
        var lo = 0.0f64
        if hx < 1072734898u32 {
            if xsb == 0u32 {
                hi = x - c_ln2_hi()
                lo = c_ln2_lo()
                kk = 1i64
            } else {
                hi = x + c_ln2_hi()
                lo = -c_ln2_lo()
                kk = -1i64
            }
        } else {
            var half = 0.5f64
            if xsb != 0u32 { half = -0.5f64 }
            kk = i64(c_invln2() * x + half)
            let t = f64(kk)
            hi = x - t * c_ln2_hi()
            lo = t * c_ln2_lo()
        }
        x = hi - lo
        c = (hi - x) - lo
    } else if hx < 1016070144u32 {
        ret x
    }
    let hfx = 0.5f64 * x
    let hxs = x * hfx
    let r1 = 1.0f64 + hxs * (k(13808336697493098740u64) + hxs * (k(4564962959435912581u64) + hxs * (k(13768856570209950647u64) + hxs * (k(4526346094260933177u64) + hxs * k(13730065378259354413u64)))))
    var t = 3.0f64 - r1 * hfx
    var e = hxs * ((r1 - t) / (6.0f64 - x * t))
    if kk == 0i64 { ret x - (x * e - hxs) }
    e = x * (e - c) - c
    e = e - hxs
    if kk == -1i64 { ret 0.5f64 * (x - e) - 0.5f64 }
    if kk == 1i64 {
        if x < -0.25f64 { ret -2.0f64 * (e - (x + 0.5f64)) }
        ret 1.0f64 + 2.0f64 * (x - e)
    }
    var y = 0.0f64
    if kk <= -2i64 || kk > 56i64 {
        y = 1.0f64 - (e - x)
        y = whw(y, u32(i64(hw(y)) + kk * 1048576i64))
        ret y - 1.0f64
    }
    t = 1.0f64
    if kk < 20i64 {
        t = whw(t, 1072693248u32 - (2097152u32 >> u32(kk)))
        y = t - (e - x)
        y = whw(y, u32(i64(hw(y)) + kk * 1048576i64))
    } else {
        t = whw(t, u32((1023i64 - kk) * 1048576i64))
        y = x - (e + t)
        y = y + 1.0f64
        y = whw(y, u32(i64(hw(y)) + kk * 1048576i64))
    }
    ret y
}

fn log1p_64(x: f64) -> f64 {
    let hx0 = hw(x)
    let hx = i64(hx0 & 2147483647u32)
    let hxs = i64(hx0) - (i64(hx0 >> 31u32) * 4294967296i64)
    var kk = 1i64
    var f = 0.0f64
    var hu = 0u32
    var c = 0.0f64
    if hxs < i64(1071284858u32) {
        if hx >= i64(1072693248u32) {
            if x == -1.0f64 { ret -inf_f64() }
            ret nan_f64()
        }
        if hx < i64(1042284544u32) {
            if hx < i64(1016070144u32) { ret x }
            ret x - x * x * 0.5f64
        }
        if hxs > 0i64 || hxs <= i64(3218259651u32) - 4294967296i64 {
            kk = 0i64
            f = x
            hu = 1u32
        }
    }
    if hx >= i64(2146435072u32) { ret x + x }
    if kk != 0i64 {
        var u = 0.0f64
        if hx < i64(1128267776u32) {
            u = 1.0f64 + x
            hu = hw(u)
            kk = i64(hu >> 20u32) - 1023i64
            if kk > 0i64 { c = 1.0f64 - (u - x) } else { c = x - (u - 1.0f64) }
            c = c / u
        } else {
            u = x
            hu = hw(u)
            kk = i64(hu >> 20u32) - 1023i64
            c = 0.0f64
        }
        hu = hu & 1048575u32
        if hu < 434334u32 {
            u = whw(u, hu | 1072693248u32)
        } else {
            kk = kk + 1i64
            u = whw(u, hu | 1071644672u32)
            hu = (1048576u32 - hu) >> 2u32
        }
        f = u - 1.0f64
    }
    let hfsq = 0.5f64 * f * f
    let kf = f64(kk)
    if hu == 0u32 {
        if f == 0.0f64 {
            if kk == 0i64 { ret 0.0f64 }
            c = c + kf * c_ln2_lo()
            ret kf * c_ln2_hi() + c
        }
        let rr = hfsq * (1.0f64 - k(4604180019048437077u64) * f)
        if kk == 0i64 { ret f - rr }
        ret kf * c_ln2_hi() - ((rr - (kf * c_ln2_lo() + c)) - f)
    }
    let s = f / (2.0f64 + f)
    let z = s * s
    let r = z * (k(4604180019048437139u64) + z * (k(4600877379321592324u64) + z * (k(4598818590951641945u64) + z * (k(4597174411056806063u64) + z * (k(4595719342595441630u64) + z * (k(4594685411790997151u64) + z * k(4594499633228436036u64)))))))
    if kk == 0i64 { ret f - (hfsq - s * (hfsq + r)) }
    ret kf * c_ln2_hi() - ((hfsq - (s * (hfsq + r) + (kf * c_ln2_lo() + c))) - f)
}

fn sinh64(x: f64) -> f64 {
    let jx = hw(x)
    let ix = jx & 2147483647u32
    if ix >= 2146435072u32 { ret x + x }
    var h = 0.5f64
    if (jx >> 31u32) != 0u32 { h = -0.5f64 }
    let ax = math.abs[f64](x)
    if ix < 1077280768u32 {
        if ix < 1043333120u32 { ret x }
        let t = expm1_64(ax)
        if ix < 1072693248u32 { ret h * (2.0f64 * t - t * t / (t + 1.0f64)) }
        ret h * (t + t / (t + 1.0f64))
    }
    if ix < 1082535490u32 { ret h * math.exp(ax) }
    if ix < 1082536910u32 || (ix == 1082536910u32 && lw(x) <= 2411329661u32) {
        let w = math.exp(0.5f64 * ax)
        let t = h * w
        ret t * w
    }
    ret x * 1.0e307f64
}

fn cosh64(x: f64) -> f64 {
    let ix = hw(x) & 2147483647u32
    if ix >= 2146435072u32 { ret x * x }
    let ax = math.abs[f64](x)
    if ix < 1071001155u32 {
        let t = expm1_64(ax)
        let w = 1.0f64 + t
        if ix < 1015021568u32 { ret w }
        ret 1.0f64 + (t * t) / (w + w)
    }
    if ix < 1077280768u32 {
        let t = math.exp(ax)
        ret 0.5f64 * t + 0.5f64 / t
    }
    if ix < 1082535490u32 { ret 0.5f64 * math.exp(ax) }
    if ix < 1082536910u32 || (ix == 1082536910u32 && lw(x) <= 2411329661u32) {
        let w = math.exp(0.5f64 * ax)
        let t = 0.5f64 * w
        ret t * w
    }
    ret inf_f64()
}

fn tanh64(x: f64) -> f64 {
    let jx = hw(x)
    let ix = jx & 2147483647u32
    if ix >= 2146435072u32 {
        if (jx >> 31u32) == 0u32 { ret 1.0f64 / x + 1.0f64 }
        ret 1.0f64 / x - 1.0f64
    }
    let ax = math.abs[f64](x)
    var z = 0.0f64
    if ix < 1077280768u32 {
        if ix < 1015021568u32 { ret x * (1.0f64 + x) }
        if ix >= 1072693248u32 {
            let t = expm1_64(2.0f64 * ax)
            z = 1.0f64 - 2.0f64 / (t + 2.0f64)
        } else {
            let t = expm1_64(-2.0f64 * ax)
            z = -t / (t + 2.0f64)
        }
    } else {
        z = 1.0f64
    }
    if (jx >> 31u32) == 0u32 { ret z }
    ret -z
}

fn asinh64(x: f64) -> f64 {
    let hx = hw(x)
    let ix = hx & 2147483647u32
    if ix >= 2146435072u32 { ret x + x }
    if ix < 1043333120u32 { ret x }
    let ax = math.abs[f64](x)
    var w = 0.0f64
    if ix > 1102053376u32 {
        w = math.log(ax) + c_ln2()
    } else if ix > 1073741824u32 {
        w = math.log(2.0f64 * ax + 1.0f64 / (math.sqrt[f64](x * x + 1.0f64) + ax))
    } else {
        let t = x * x
        w = log1p_64(ax + t / (1.0f64 + math.sqrt[f64](1.0f64 + t)))
    }
    if (hx >> 31u32) == 0u32 { ret w }
    ret -w
}

fn acosh64(x: f64) -> f64 {
    let hx = hw(x)
    if (hx >> 31u32) != 0u32 { ret nan_f64() }
    if hx >= 1102053376u32 {
        if hx >= 2146435072u32 { ret x + x }
        ret math.log(x) + c_ln2()
    }
    if hx < 1072693248u32 { ret nan_f64() }
    if x == 1.0f64 { ret 0.0f64 }
    if hx > 1073741824u32 {
        let t = x * x
        ret math.log(2.0f64 * x - 1.0f64 / (x + math.sqrt[f64](t - 1.0f64)))
    }
    let t = x - 1.0f64
    ret log1p_64(t + math.sqrt[f64](2.0f64 * t + t * t))
}

fn atanh64(x: f64) -> f64 {
    let hx = hw(x)
    let ix = hx & 2147483647u32
    let lx = lw(x)
    if ix > 1072693248u32 || (ix == 1072693248u32 && lx != 0u32) { ret nan_f64() }
    if ix == 1072693248u32 {
        if (hx >> 31u32) == 0u32 { ret inf_f64() }
        ret -inf_f64()
    }
    if ix < 1043333120u32 { ret x }
    let ax = math.abs[f64](x)
    var t = 0.0f64
    if ix < 1071644672u32 {
        t = ax + ax
        t = 0.5f64 * log1p_64(t + t * ax / (1.0f64 - ax))
    } else {
        t = 0.5f64 * log1p_64((ax + ax) / (1.0f64 - ax))
    }
    if (hx >> 31u32) == 0u32 { ret t }
    ret -t
}

