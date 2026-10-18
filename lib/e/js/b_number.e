// Number, Boolean, Math and the numeric global functions (browser tracker 5.7).

use e.data.list as list
use e.js.bigint as bigint
use e.js.interp as js
use e.math
use e.mem
use e.str

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

// --- Boolean

fn boolean_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let b = js.to_boolean(arg(args, 0usize))
    if !it.has_new_target { ret (js.bool_value(b), ok) }
    let nto = js.as_object(it.new_target)
    let (proto, pe) = js.proto_value_of(it, nto, it.protos.boolean)
    if pe != ok { ret (js.undefv(), pe) }
    let o = js.new_obj(it, js.C_BOOLEAN, proto)
    o.prim = js.bool_value(b)
    ret (js.obj_value(o), ok)
}

fn this_boolean(it: *js.Interp, v: js.Value) -> (bool, err) {
    switch v {
    case .Bool as b:
        ret (b, ok)
    case .Obj as o:
        if o.class == js.C_BOOLEAN {
            switch o.prim {
            case .Bool as b2:
                ret (b2, ok)
            default:
                ret (false, ok)
            }
        }
        ret (false, js.throw_type(it, "Boolean.prototype method called on incompatible receiver"))
    default:
        ret (false, js.throw_type(it, "Boolean.prototype method called on incompatible receiver"))
    }
    ret (false, ok)
}

fn boolean_to_string(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, e) = this_boolean(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    if b { ret (js.str_value("true"), ok) }
    ret (js.str_value("false"), ok)
}

fn boolean_value_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, e) = this_boolean(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(b), ok)
}

// --- Number

fn number_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    var n = 0.0f64
    if args.len > 0usize {
        let (pv, pe0) = js.to_numeric(it, args[0usize])
        if pe0 != ok { ret (js.undefv(), pe0) }
        if js.is_bigint(pv) { n = bigint.to_f64(js.big_of(pv)) } else { n = js.num_of(pv) }
    }
    if !it.has_new_target { ret (js.num_value(n), ok) }
    let nto = js.as_object(it.new_target)
    let (proto, pe) = js.proto_value_of(it, nto, it.protos.number)
    if pe != ok { ret (js.undefv(), pe) }
    let o = js.new_obj(it, js.C_NUMBER, proto)
    o.prim = js.num_value(n)
    ret (js.obj_value(o), ok)
}

fn this_number(it: *js.Interp, v: js.Value) -> (f64, err) {
    switch v {
    case .Num as n:
        ret (n, ok)
    case .Obj as o:
        if o.class == js.C_NUMBER { ret (js.num_of(o.prim), ok) }
        ret (0.0f64, js.throw_type(it, "Number.prototype method called on incompatible receiver"))
    default:
        ret (0.0f64, js.throw_type(it, "Number.prototype method called on incompatible receiver"))
    }
    ret (0.0f64, ok)
}

fn digit_char(d: u32) -> u8 {
    if d < 10u32 { ret u8(48u32 + d) }
    ret u8(87u32 + d)
}

fn radix_string(it: *js.Interp, x: f64, radix: u32) -> str {
    if js.is_nan(x) { ret "NaN" }
    if x == 0.0f64 { ret "0" }
    if js.is_infinite(x) {
        if x < 0.0f64 { ret "-Infinity" }
        ret "Infinity"
    }
    var neg = false
    var v = x
    if v < 0.0f64 {
        neg = true
        v = -v
    }
    var ipart = js.floor(v)
    var frac = v - ipart
    // Integer digits, least significant first.
    var digits: [1100]u8 = zero
    var n = 0usize
    if ipart == 0.0f64 {
        digits[0usize] = 48u8
        n = 1usize
    }
    let r = f64(radix)
    while ipart > 0.0f64 && n < 1100usize {
        let q = js.floor(ipart / r)
        var rem = ipart - q * r
        if rem < 0.0f64 { rem = 0.0f64 }
        digits[n] = digit_char(u32(i64(rem)))
        n += 1usize
        ipart = q
    }
    let (b, be) = str.builder(it.a, n + 64usize)
    if be != ok { ret "" }
    var out = b
    if neg { let pn = str.push_byte(&out, 45u8) }
    var i = n
    while i > 0usize {
        i -= 1usize
        let pd = str.push_byte(&out, digits[i])
    }
    if frac > 0.0f64 {
        let pp = str.push_byte(&out, 46u8)
        // Digits until the value is exact, bounded by the precision of a double.
        var delta = 0.5f64 * (math.pow(2.0f64, -52.0f64) * v)
        if delta < 5e-324 { delta = 5e-324 }
        var guard = 0u32
        while guard < 1100u32 {
            guard += 1u32
            frac = frac * r
            delta = delta * r
            let d = js.floor(frac)
            let pf = str.push_byte(&out, digit_char(u32(i64(d))))
            frac = frac - d
            if frac < delta { break }
            if frac > 0.5f64 || (frac == 0.5f64) {
                if frac > 1.0f64 - delta { break }
            }
        }
    }
    ret str.done(&out)
}

fn number_to_string_m(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = this_number(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    var radix = 10u32
    if !js.is_undefined(arg(args, 0usize)) {
        let (rn, rne) = js.to_number(it, args[0usize])
        if rne != ok { ret (js.undefv(), rne) }
        let ri = js.to_integer(rn)
        if ri < 2.0f64 || ri > 36.0f64 { ret (js.undefv(), js.throw_range(it, "toString() radix must be between 2 and 36")) }
        radix = u32(i64(ri))
    }
    if radix == 10u32 { ret (js.str_value(js.number_to_string(it.a, x)), ok) }
    ret (js.str_value(radix_string(it, x, radix)), ok)
}

fn number_value_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = this_number(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.num_value(x), ok)
}

fn number_to_locale_string(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = this_number(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.str_value(js.number_to_string(it.a, x)), ok)
}

// The exact-ish decimal digits of |x| rounded half up to `sig` significant digits: (digits, exponent e where value = 0.d1d2.. x
// 10^(e+1), i.e. d1 is the 10^e place).
fn sig_digits(it: *js.Interp, x: f64, sig: usize) -> (str, i64) {
    var ax = x
    if ax < 0.0f64 { ax = -ax }
    let (b, be) = str.builder(it.a, 400usize)
    if be != ok { ret ("", 0i64) }
    var out = b
    var e10 = 0i64
    if ax < 1e21f64 {
        let pe = str.push_f64_fixed(&out, ax, 99u8)
    } else {
        let pe2 = str.push_f64(&out, ax)
    }
    let text = str.done(&out)
    // Collect all digits and the position of the decimal point.
    let (db, dbe) = str.builder(it.a, text.len + 4usize)
    if dbe != ok { ret ("", 0i64) }
    var digs = db
    var point = -1i64
    var count = 0i64
    var exp_part = 0i64
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if c >= 48u8 && c <= 57u8 {
            let pd = str.push_byte(&digs, c)
            count += 1i64
        } else if c == 46u8 {
            point = count
        } else if c == 101u8 || c == 69u8 {
            var j = i + 1usize
            var neg = false
            if j < text.len && (text[j] == 43u8 || text[j] == 45u8) {
                neg = text[j] == 45u8
                j += 1usize
            }
            var ev = 0i64
            while j < text.len && text[j] >= 48u8 && text[j] <= 57u8 {
                ev = ev * 10i64 + i64(text[j] - 48u8)
                j += 1usize
            }
            if neg { ev = -ev }
            exp_part = ev
            break
        }
        i += 1usize
    }
    let all = str.done(&digs)
    if point < 0i64 { point = count }
    point = point + exp_part
    // Skip leading zeros.
    var lead = 0usize
    while lead < all.len && all[lead] == 48u8 { lead += 1usize }
    if lead >= all.len {
        // zero
        let (zb, zbe) = str.builder(it.a, sig + 2usize)
        if zbe != ok { ret ("", 0i64) }
        var zo = zb
        var zi = 0usize
        while zi < sig {
            let pz = str.push_byte(&zo, 48u8)
            zi += 1usize
        }
        ret (str.done(&zo), 0i64)
    }
    e10 = point - i64(lead) - 1i64
    let sig_all = all[lead..]
    // Round half up at `sig` digits.
    let (rb, rbe) = str.builder(it.a, sig + 4usize)
    if rbe != ok { ret ("", 0i64) }
    var res = rb
    var buf: [128]u8 = zero
    var n = 0usize
    var k = 0usize
    while k < sig && k < 127usize {
        if k < sig_all.len { buf[k] = sig_all[k] } else { buf[k] = 48u8 }
        n += 1usize
        k += 1usize
    }
    var round_up = false
    if sig < sig_all.len && sig_all[sig] >= 53u8 { round_up = true }
    if round_up {
        var p = n
        while p > 0usize {
            p -= 1usize
            if buf[p] == 57u8 {
                buf[p] = 48u8
                if p == 0usize {
                    // carry out: 999 -> 1000 -> digits "100", exponent + 1
                    var sh = n
                    while sh > 1usize {
                        buf[sh - 1usize] = buf[sh - 2usize]
                        sh -= 1usize
                    }
                    buf[0usize] = 49u8
                    e10 += 1i64
                }
            } else {
                buf[p] = buf[p] + 1u8
                break
            }
        }
    }
    var w = 0usize
    while w < n {
        let pw = str.push_byte(&res, buf[w])
        w += 1usize
    }
    ret (str.done(&res), e10)
}

fn number_to_fixed(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = this_number(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    let (fn_, fe) = js.to_number(it, arg(args, 0usize))
    if fe != ok { ret (js.undefv(), fe) }
    let f = js.to_integer(fn_)
    if f < 0.0f64 || f > 100.0f64 { ret (js.undefv(), js.throw_range(it, "toFixed() digits argument must be between 0 and 100")) }
    if !js.is_finite(x) { ret (js.str_value(js.number_to_string(it.a, x)), ok) }
    if x >= 1e21f64 || x <= -1e21f64 { ret (js.str_value(js.number_to_string(it.a, x)), ok) }
    // Round half up on the exact value: take extra digits then round the digit string.
    let (digits, e10) = sig_digits_fixed(it, x, usize(f))
    ret (js.str_value(digits), ok)
}

// toFixed: digits of |x| with `frac` decimals, rounded half up, sign kept (-0 prints without a sign).
fn sig_digits_fixed(it: *js.Interp, x: f64, frac: usize) -> (str, i64) {
    var ax = x
    var neg = false
    if ax < 0.0f64 {
        neg = true
        ax = -ax
    }
    let (b, be) = str.builder(it.a, 300usize)
    if be != ok { ret ("", 0i64) }
    var out = b
    let pe = str.push_f64_fixed(&out, ax, 99u8)
    let text = str.done(&out)
    var point = 0usize
    while point < text.len && text[point] != 46u8 { point += 1usize }
    let int_part = text[0usize..point]
    var frac_part = ""
    if point < text.len { frac_part = text[point + 1usize..] }
    // Digit buffer: integer digits then `frac` fraction digits.
    var buf: [400]u8 = zero
    var n = 0usize
    var i = 0usize
    while i < int_part.len && n < 390usize {
        buf[n] = int_part[i]
        n += 1usize
        i += 1usize
    }
    let int_len = n
    var j = 0usize
    while j < frac && n < 395usize {
        if j < frac_part.len { buf[n] = frac_part[j] } else { buf[n] = 48u8 }
        n += 1usize
        j += 1usize
    }
    var round_up = false
    if frac < frac_part.len && frac_part[frac] >= 53u8 { round_up = true }
    var lead_one = false
    if round_up {
        var p = n
        var carried = true
        while p > 0usize && carried {
            p -= 1usize
            if buf[p] == 57u8 {
                buf[p] = 48u8
            } else {
                buf[p] = buf[p] + 1u8
                carried = false
            }
        }
        if carried { lead_one = true }
    }
    let (rb, rbe) = str.builder(it.a, n + 8usize)
    if rbe != ok { ret ("", 0i64) }
    var res = rb
    var all_zero = true
    var q = 0usize
    while q < n {
        if buf[q] != 48u8 { all_zero = false }
        q += 1usize
    }
    if neg && !(all_zero && !lead_one) && x < 0.0f64 { let pn = str.push_byte(&res, 45u8) }
    if lead_one { let pl = str.push_byte(&res, 49u8) }
    var w = 0usize
    while w < n {
        if w == int_len && frac > 0usize { let pp = str.push_byte(&res, 46u8) }
        let pw = str.push_byte(&res, buf[w])
        w += 1usize
    }
    if int_len == 0usize { }
    ret (str.done(&res), 0i64)
}

fn number_to_exponential(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = this_number(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    let (fn_, fe) = js.to_number(it, arg(args, 0usize))
    if fe != ok { ret (js.undefv(), fe) }
    let f = js.to_integer(fn_)
    if !js.is_finite(x) { ret (js.str_value(js.number_to_string(it.a, x)), ok) }
    if f < 0.0f64 || f > 100.0f64 { ret (js.undefv(), js.throw_range(it, "toExponential() argument must be between 0 and 100")) }
    var digits = ""
    var e10 = 0i64
    if js.is_undefined(arg(args, 0usize)) {
        // As many digits as needed: take the shortest representation's digits.
        let s = js.number_to_string(it.a, x)
        let (d, ee) = shortest_digits(it, x)
        digits = d
        e10 = ee
    } else {
        let (d2, ee2) = sig_digits(it, x, usize(f) + 1usize)
        digits = d2
        e10 = ee2
    }
    let (b, be) = str.builder(it.a, 64usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var out = b
    if x < 0.0f64 { let pn = str.push_byte(&out, 45u8) }
    let p0 = str.push_byte(&out, digits[0usize])
    if digits.len > 1usize {
        let pd = str.push_byte(&out, 46u8)
        let pr = str.push(&out, digits[1usize..])
    }
    let pe = str.push_byte(&out, 101u8)
    if e10 >= 0i64 { let ps = str.push_byte(&out, 43u8) } else { let pm = str.push_byte(&out, 45u8) }
    var ev = e10
    if ev < 0i64 { ev = -ev }
    let pi = str.push_i64(&out, ev)
    ret (js.str_value(str.done(&out)), ok)
}

fn shortest_digits(it: *js.Interp, x: f64) -> (str, i64) {
    let s = js.number_to_string(it.a, x)
    // Digits of the decimal rendering without sign, point or exponent; exponent from the position.
    let (b, be) = str.builder(it.a, s.len + 4usize)
    if be != ok { ret ("", 0i64) }
    var digs = b
    var point = -1i64
    var count = 0i64
    var exp_part = 0i64
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c >= 48u8 && c <= 57u8 {
            let pd = str.push_byte(&digs, c)
            count += 1i64
        } else if c == 46u8 {
            point = count
        } else if c == 101u8 {
            var j = i + 1usize
            var neg = false
            if j < s.len && (s[j] == 43u8 || s[j] == 45u8) {
                neg = s[j] == 45u8
                j += 1usize
            }
            var ev = 0i64
            while j < s.len && s[j] >= 48u8 && s[j] <= 57u8 {
                ev = ev * 10i64 + i64(s[j] - 48u8)
                j += 1usize
            }
            if neg { ev = -ev }
            exp_part = ev
            break
        }
        i += 1usize
    }
    let all = str.done(&digs)
    if point < 0i64 { point = count }
    var lead = 0usize
    while lead + 1usize < all.len && all[lead] == 48u8 { lead += 1usize }
    var tail = all.len
    while tail > lead + 1usize && all[tail - 1usize] == 48u8 { tail -= 1usize }
    ret (all[lead..tail], point + exp_part - i64(lead) - 1i64)
}

fn number_to_precision(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = this_number(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    if js.is_undefined(arg(args, 0usize)) { ret (js.str_value(js.number_to_string(it.a, x)), ok) }
    let (pn, pe) = js.to_number(it, args[0usize])
    if pe != ok { ret (js.undefv(), pe) }
    let p = js.to_integer(pn)
    if !js.is_finite(x) { ret (js.str_value(js.number_to_string(it.a, x)), ok) }
    if p < 1.0f64 || p > 100.0f64 { ret (js.undefv(), js.throw_range(it, "toPrecision() argument must be between 1 and 100")) }
    let prec = usize(p)
    let (digits, e10) = sig_digits(it, x, prec)
    let (b, be) = str.builder(it.a, 160usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var out = b
    if x < 0.0f64 { let pn2 = str.push_byte(&out, 45u8) }
    if e10 < -6i64 || e10 >= i64(prec) {
        let p0 = str.push_byte(&out, digits[0usize])
        if prec > 1usize {
            let pd = str.push_byte(&out, 46u8)
            let pr = str.push(&out, digits[1usize..])
        }
        let pe2 = str.push_byte(&out, 101u8)
        if e10 >= 0i64 { let ps = str.push_byte(&out, 43u8) } else { let pm = str.push_byte(&out, 45u8) }
        var ev = e10
        if ev < 0i64 { ev = -ev }
        let pi = str.push_i64(&out, ev)
    } else if e10 >= 0i64 {
        let int_len = usize(e10) + 1usize
        let pa = str.push(&out, digits[0usize..int_len])
        if int_len < prec {
            let pd2 = str.push_byte(&out, 46u8)
            let pb = str.push(&out, digits[int_len..])
        }
    } else {
        let pz = str.push(&out, "0.")
        var z = 0i64
        while z < -(e10 + 1i64) {
            let pzz = str.push_byte(&out, 48u8)
            z += 1i64
        }
        let pc = str.push(&out, digits)
    }
    ret (js.str_value(str.done(&out)), ok)
}

fn number_is_integer(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let v = arg(args, 0usize)
    if !js.is_number(v) { ret (js.bool_value(false), ok) }
    let n = js.num_of(v)
    ret (js.bool_value(js.is_finite(n) && js.to_integer(n) == n), ok)
}

fn number_is_safe_integer(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let v = arg(args, 0usize)
    if !js.is_number(v) { ret (js.bool_value(false), ok) }
    let n = js.num_of(v)
    ret (js.bool_value(js.is_finite(n) && js.to_integer(n) == n && n >= -9007199254740991.0f64 && n <= 9007199254740991.0f64), ok)
}

fn number_is_finite(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let v = arg(args, 0usize)
    if !js.is_number(v) { ret (js.bool_value(false), ok) }
    ret (js.bool_value(js.is_finite(js.num_of(v))), ok)
}

fn number_is_nan(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let v = arg(args, 0usize)
    if !js.is_number(v) { ret (js.bool_value(false), ok) }
    ret (js.bool_value(js.is_nan(js.num_of(v))), ok)
}

fn global_is_nan(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (n, e) = js.to_number(it, arg(args, 0usize))
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(js.is_nan(n)), ok)
}

fn global_is_finite(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (n, e) = js.to_number(it, arg(args, 0usize))
    if e != ok { ret (js.undefv(), e) }
    ret (js.bool_value(js.is_finite(n)), ok)
}

fn parse_float_fn(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s0, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let s = js.trim_js(s0)
    var i = 0usize
    if i < s.len && (s[i] == 43u8 || s[i] == 45u8) { i += 1usize }
    if s.len - i >= 8usize && str.starts_with(s[i..], "Infinity") {
        if s[0usize] == 45u8 { ret (js.num_value(-js.infinity()), ok) }
        ret (js.num_value(js.infinity()), ok)
    }
    let start = 0usize
    var digits = 0usize
    while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
        i += 1usize
        digits += 1usize
    }
    if i < s.len && s[i] == 46u8 {
        i += 1usize
        while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
            i += 1usize
            digits += 1usize
        }
    }
    if digits == 0usize { ret (js.num_value(js.nan()), ok) }
    var end = i
    if i < s.len && (s[i] == 101u8 || s[i] == 69u8) {
        var j = i + 1usize
        if j < s.len && (s[j] == 43u8 || s[j] == 45u8) { j += 1usize }
        var ed = 0usize
        while j < s.len && s[j] >= 48u8 && s[j] <= 57u8 {
            j += 1usize
            ed += 1usize
        }
        if ed > 0usize { end = j }
    }
    ret (js.num_value(js.string_to_number(it.a, s[start..end])), ok)
}

fn parse_int_fn(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s0, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (rn, rne) = js.to_int32(it, arg(args, 1usize))
    if rne != ok { ret (js.undefv(), rne) }
    var s = js.trim_js(s0)
    var neg = false
    if s.len > 0usize && (s[0usize] == 43u8 || s[0usize] == 45u8) {
        neg = s[0usize] == 45u8
        s = s[1usize..]
    }
    var radix = i32(rn)
    var strip = true
    if radix != 0i32 {
        if radix < 2i32 || radix > 36i32 { ret (js.num_value(js.nan()), ok) }
        if radix != 16i32 { strip = false }
    } else {
        radix = 10i32
    }
    if strip && s.len >= 2usize && s[0usize] == 48u8 && (s[1usize] == 120u8 || s[1usize] == 88u8) {
        s = s[2usize..]
        radix = 16i32
    }
    var v = 0.0f64
    var any = false
    var i = 0usize
    while i < s.len {
        let d = js.digit_value(s[i])
        if d < 0i32 || d >= radix { break }
        v = v * f64(radix) + f64(d)
        any = true
        i += 1usize
    }
    if !any { ret (js.num_value(js.nan()), ok) }
    // Long decimal strings lose precision accumulating; reparse as a float.
    if radix == 10i32 && i > 15usize { v = js.string_to_number(it.a, s[0usize..i]) }
    if neg { v = -v }
    ret (js.num_value(v), ok)
}

fn install_number(it: *js.Interp) {
    let bp = it.protos.boolean
    let bctor = js.make_native(it, "Boolean", 1u32, boolean_ctor)
    bctor.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, bctor, js.key_of("prototype"), js.obj_value(bp), 0u8)
    let e2 = js.define_data(it, bp, js.key_of("constructor"), js.obj_value(bctor), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of("Boolean"), js.obj_value(bctor), js.P_HIDDEN)
    js.add_method(it, it.protos.boolean, "toString", 0u32, boolean_to_string)
    js.add_method(it, it.protos.boolean, "valueOf", 0u32, boolean_value_of)
    let ctor = js.make_native(it, "Number", 1u32, number_ctor)
    ctor.ctor_kind = js.K_BASE
    let e4 = js.define_data(it, ctor, js.key_of("prototype"), js.obj_value(it.protos.number), 0u8)
    let e5 = js.define_data(it, it.protos.number, js.key_of("constructor"), js.obj_value(ctor), js.P_HIDDEN)
    let e6 = js.define_data(it, it.global, js.key_of("Number"), js.obj_value(ctor), js.P_HIDDEN)
    it.last = ctor
    js.add_method(it, it.protos.number, "toString", 1u32, number_to_string_m)
    js.add_method(it, it.protos.number, "toLocaleString", 0u32, number_to_locale_string)
    js.add_method(it, it.protos.number, "valueOf", 0u32, number_value_of)
    js.add_method(it, it.protos.number, "toFixed", 1u32, number_to_fixed)
    js.add_method(it, it.protos.number, "toExponential", 1u32, number_to_exponential)
    js.add_method(it, it.protos.number, "toPrecision", 1u32, number_to_precision)
    js.add_method(it, it.last, "isInteger", 1u32, number_is_integer)
    js.add_method(it, it.last, "isSafeInteger", 1u32, number_is_safe_integer)
    js.add_method(it, it.last, "isFinite", 1u32, number_is_finite)
    js.add_method(it, it.last, "isNaN", 1u32, number_is_nan)
    let ef = js.define_data(it, it.last, js.key_of("MAX_SAFE_INTEGER"), js.num_value(9007199254740991.0f64), 0u8)
    let ef2 = js.define_data(it, it.last, js.key_of("MIN_SAFE_INTEGER"), js.num_value(-9007199254740991.0f64), 0u8)
    let ef3 = js.define_data(it, it.last, js.key_of("MAX_VALUE"), js.num_value(1.7976931348623157e308f64), 0u8)
    let ef4 = js.define_data(it, it.last, js.key_of("MIN_VALUE"), js.num_value(5e-324f64), 0u8)
    let ef5 = js.define_data(it, it.last, js.key_of("EPSILON"), js.num_value(2.220446049250313e-16f64), 0u8)
    let ef6 = js.define_data(it, it.last, js.key_of("POSITIVE_INFINITY"), js.num_value(js.infinity()), 0u8)
    let ef7 = js.define_data(it, it.last, js.key_of("NEGATIVE_INFINITY"), js.num_value(-js.infinity()), 0u8)
    let ef8 = js.define_data(it, it.last, js.key_of("NaN"), js.num_value(js.nan()), 0u8)
    let pf = js.make_native(it, "parseFloat", 1u32, parse_float_fn)
    let pi = js.make_native(it, "parseInt", 2u32, parse_int_fn)
    let g1 = js.define_data(it, it.global, js.key_of("parseFloat"), js.obj_value(pf), js.P_HIDDEN)
    let g2 = js.define_data(it, it.global, js.key_of("parseInt"), js.obj_value(pi), js.P_HIDDEN)
    let g3 = js.define_data(it, it.last, js.key_of("parseFloat"), js.obj_value(pf), js.P_HIDDEN)
    let g4 = js.define_data(it, it.last, js.key_of("parseInt"), js.obj_value(pi), js.P_HIDDEN)
    js.add_method(it, it.global, "isNaN", 1u32, global_is_nan)
    js.add_method(it, it.global, "isFinite", 1u32, global_is_finite)
}

// --- Math

fn m1(it: *js.Interp, args: []const js.Value) -> (f64, err) {
    let (n, e) = js.to_number(it, arg(args, 0usize))
    ret (n, e)
}

fn math_abs(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if x < 0.0f64 || js.is_neg_zero(x) { ret (js.num_value(-x), ok) }
    ret (js.num_value(x), ok)
}

fn math_floor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    ret (js.num_value(js.floor(x)), ok)
}

fn math_ceil(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if !js.is_finite(x) { ret (js.num_value(x), ok) }
    var r = -js.floor(-x)
    if r == 0.0f64 && (x < 0.0f64 || js.is_neg_zero(x)) { r = -0.0f64 }
    ret (js.num_value(r), ok)
}

fn math_round(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if !js.is_finite(x) || x == 0.0f64 { ret (js.num_value(x), ok) }
    if x >= -0.5f64 && x < 0.0f64 { ret (js.num_value(-0.0f64), ok) }
    if x >= 4503599627370496.0f64 || x <= -4503599627370496.0f64 { ret (js.num_value(x), ok) }
    let fl = js.floor(x)
    var r = fl
    if x - fl >= 0.5f64 { r = fl + 1.0f64 }
    ret (js.num_value(r), ok)
}

fn math_trunc(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if x == 0.0f64 { ret (js.num_value(x), ok) }
    let t = js.trunc(x)
    if t == 0.0f64 && x < 0.0f64 { ret (js.num_value(-0.0f64), ok) }
    ret (js.num_value(t), ok)
}

fn math_sign(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) || x == 0.0f64 { ret (js.num_value(x), ok) }
    if x > 0.0f64 { ret (js.num_value(1.0f64), ok) }
    ret (js.num_value(-1.0f64), ok)
}

fn math_sqrt(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) || x < 0.0f64 { ret (js.num_value(js.nan()), ok) }
    if x == 0.0f64 || js.is_infinite(x) { ret (js.num_value(x), ok) }
    ret (js.num_value(math.sqrt[f64](x)), ok)
}

fn math_cbrt(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if !js.is_finite(x) || x == 0.0f64 { ret (js.num_value(x), ok) }
    var ax = x
    if ax < 0.0f64 { ax = -ax }
    var r = math.pow(ax, 1.0f64 / 3.0f64)
    // One Newton step polishes the result.
    r = r - (r * r * r - ax) / (3.0f64 * r * r)
    if x < 0.0f64 { r = -r }
    ret (js.num_value(r), ok)
}

fn math_pow(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = js.to_number(it, arg(args, 0usize))
    if e != ok { ret (js.undefv(), e) }
    let (y, e2) = js.to_number(it, arg(args, 1usize))
    if e2 != ok { ret (js.undefv(), e2) }
    ret (js.num_value(js.arith(it, 15u8, x, y)), ok)
}

fn math_exp(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) { ret (js.num_value(x), ok) }
    if js.is_infinite(x) {
        if x < 0.0f64 { ret (js.num_value(0.0f64), ok) }
        ret (js.num_value(x), ok)
    }
    ret (js.num_value(math.exp(x)), ok)
}

fn math_expm1(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) || x == 0.0f64 { ret (js.num_value(x), ok) }
    if js.is_infinite(x) {
        if x < 0.0f64 { ret (js.num_value(-1.0f64), ok) }
        ret (js.num_value(x), ok)
    }
    if x > -1e-5f64 && x < 1e-5f64 { ret (js.num_value(x + x * x / 2.0f64 + x * x * x / 6.0f64), ok) }
    ret (js.num_value(math.exp(x) - 1.0f64), ok)
}

fn math_log(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) || x < 0.0f64 { ret (js.num_value(js.nan()), ok) }
    if x == 0.0f64 { ret (js.num_value(-js.infinity()), ok) }
    if js.is_infinite(x) { ret (js.num_value(x), ok) }
    ret (js.num_value(math.log(x)), ok)
}

fn math_log2(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) || x < 0.0f64 { ret (js.num_value(js.nan()), ok) }
    if x == 0.0f64 { ret (js.num_value(-js.infinity()), ok) }
    if js.is_infinite(x) { ret (js.num_value(x), ok) }
    ret (js.num_value(math.log2(x)), ok)
}

fn math_log10(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) || x < 0.0f64 { ret (js.num_value(js.nan()), ok) }
    if x == 0.0f64 { ret (js.num_value(-js.infinity()), ok) }
    if js.is_infinite(x) { ret (js.num_value(x), ok) }
    ret (js.num_value(math.log10(x)), ok)
}

fn math_log1p(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) || x < -1.0f64 { ret (js.num_value(js.nan()), ok) }
    if x == -1.0f64 { ret (js.num_value(-js.infinity()), ok) }
    if x == 0.0f64 || js.is_infinite(x) { ret (js.num_value(x), ok) }
    if x > -1e-5f64 && x < 1e-5f64 { ret (js.num_value(x - x * x / 2.0f64 + x * x * x / 3.0f64), ok) }
    ret (js.num_value(math.log(1.0f64 + x)), ok)
}

fn math_sin(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if !js.is_finite(x) { ret (js.num_value(js.nan()), ok) }
    if x == 0.0f64 { ret (js.num_value(x), ok) }
    ret (js.num_value(math.sin(x)), ok)
}

fn math_cos(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if !js.is_finite(x) { ret (js.num_value(js.nan()), ok) }
    ret (js.num_value(math.cos(x)), ok)
}

fn math_tan(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if !js.is_finite(x) { ret (js.num_value(js.nan()), ok) }
    if x == 0.0f64 { ret (js.num_value(x), ok) }
    ret (js.num_value(math.tan(x)), ok)
}

fn math_asin(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) || x > 1.0f64 || x < -1.0f64 { ret (js.num_value(js.nan()), ok) }
    if x == 0.0f64 { ret (js.num_value(x), ok) }
    ret (js.num_value(math.asin(x)), ok)
}

fn math_acos(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) || x > 1.0f64 || x < -1.0f64 { ret (js.num_value(js.nan()), ok) }
    ret (js.num_value(math.acos(x)), ok)
}

fn math_atan(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) || x == 0.0f64 { ret (js.num_value(x), ok) }
    ret (js.num_value(math.atan(x)), ok)
}

fn math_atan2(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (y, e) = js.to_number(it, arg(args, 0usize))
    if e != ok { ret (js.undefv(), e) }
    let (x, e2) = js.to_number(it, arg(args, 1usize))
    if e2 != ok { ret (js.undefv(), e2) }
    if js.is_nan(x) || js.is_nan(y) { ret (js.num_value(js.nan()), ok) }
    if x == js.infinity() && js.is_finite(y) {
        if y < 0.0f64 || (y == 0.0f64 && 1.0f64 / y < 0.0f64) { ret (js.num_value(-0.0f64), ok) }
        ret (js.num_value(0.0f64), ok)
    }
    ret (js.num_value(math.atan2(y, x)), ok)
}

fn math_sinh(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if !js.is_finite(x) || x == 0.0f64 { ret (js.num_value(x), ok) }
    if x > -1e-5f64 && x < 1e-5f64 { ret (js.num_value(x + x * x * x / 6.0f64), ok) }
    ret (js.num_value((math.exp(x) - math.exp(-x)) / 2.0f64), ok)
}

fn math_cosh(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) { ret (js.num_value(x), ok) }
    if js.is_infinite(x) { ret (js.num_value(js.infinity()), ok) }
    ret (js.num_value((math.exp(x) + math.exp(-x)) / 2.0f64), ok)
}

fn math_tanh(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) || x == 0.0f64 { ret (js.num_value(x), ok) }
    if x > 20.0f64 { ret (js.num_value(1.0f64), ok) }
    if x < -20.0f64 { ret (js.num_value(-1.0f64), ok) }
    if x > -1e-5f64 && x < 1e-5f64 { ret (js.num_value(x - x * x * x / 3.0f64), ok) }
    let a = math.exp(x)
    let b = math.exp(-x)
    ret (js.num_value((a - b) / (a + b)), ok)
}

fn math_asinh(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if !js.is_finite(x) || x == 0.0f64 { ret (js.num_value(x), ok) }
    var ax = x
    if ax < 0.0f64 { ax = -ax }
    var r = 0.0f64
    if ax < 1e-5f64 { r = ax - ax * ax * ax / 6.0f64 } else { r = math.log(ax + math.sqrt[f64](ax * ax + 1.0f64)) }
    if x < 0.0f64 { r = -r }
    ret (js.num_value(r), ok)
}

fn math_acosh(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) || x < 1.0f64 { ret (js.num_value(js.nan()), ok) }
    if js.is_infinite(x) { ret (js.num_value(x), ok) }
    ret (js.num_value(math.log(x + math.sqrt[f64](x * x - 1.0f64))), ok)
}

fn math_atanh(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    if js.is_nan(x) || x > 1.0f64 || x < -1.0f64 { ret (js.num_value(js.nan()), ok) }
    if x == 0.0f64 { ret (js.num_value(x), ok) }
    if x == 1.0f64 { ret (js.num_value(js.infinity()), ok) }
    if x == -1.0f64 { ret (js.num_value(-js.infinity()), ok) }
    if x > -1e-5f64 && x < 1e-5f64 { ret (js.num_value(x + x * x * x / 3.0f64), ok) }
    ret (js.num_value(0.5f64 * math.log((1.0f64 + x) / (1.0f64 - x))), ok)
}

fn math_hypot(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    var sum = 0.0f64
    var has_nan = false
    var has_inf = false
    var biggest = 0.0f64
    let (cell, ce) = mem.alloc[f64](it.a, args.len + 1usize)
    if ce != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var i = 0usize
    while i < args.len {
        let (n, e) = js.to_number(it, args[i])
        if e != ok { ret (js.undefv(), e) }
        var a = n
        if a < 0.0f64 { a = -a }
        cell[i] = a
        if js.is_nan(a) { has_nan = true }
        if js.is_infinite(a) { has_inf = true }
        if a > biggest { biggest = a }
        i += 1usize
    }
    if has_inf { ret (js.num_value(js.infinity()), ok) }
    if has_nan { ret (js.num_value(js.nan()), ok) }
    if biggest == 0.0f64 { ret (js.num_value(0.0f64), ok) }
    var k = 0usize
    while k < args.len {
        let r = cell[k] / biggest
        sum += r * r
        k += 1usize
    }
    ret (js.num_value(math.sqrt[f64](sum) * biggest), ok)
}

fn math_max(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    var r = -js.infinity()
    var has_nan = false
    var i = 0usize
    while i < args.len {
        let (n, e) = js.to_number(it, args[i])
        if e != ok { ret (js.undefv(), e) }
        if js.is_nan(n) { has_nan = true }
        if n > r || (n == 0.0f64 && r == 0.0f64 && !js.is_neg_zero(n)) { r = n }
        i += 1usize
    }
    if has_nan { ret (js.num_value(js.nan()), ok) }
    ret (js.num_value(r), ok)
}

fn math_min(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    var r = js.infinity()
    var has_nan = false
    var i = 0usize
    while i < args.len {
        let (n, e) = js.to_number(it, args[i])
        if e != ok { ret (js.undefv(), e) }
        if js.is_nan(n) { has_nan = true }
        if n < r || (n == 0.0f64 && r == 0.0f64 && js.is_neg_zero(n)) { r = n }
        i += 1usize
    }
    if has_nan { ret (js.num_value(js.nan()), ok) }
    ret (js.num_value(r), ok)
}

fn math_random(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    // xorshift64* seeded from the interpreter's step counter and symbol counter; not cryptographic.
    var x = it.rng_state
    if x == 0u64 { x = 88172645463325252u64 +% u64(it.next_symbol) }
    x = x ^ (x >> 12u64)
    x = x ^ (x << 25u64)
    x = x ^ (x >> 27u64)
    it.rng_state = x
    let r = (x *% 2685821657736338717u64) >> 11u64
    ret (js.num_value(f64(r) / 9007199254740992.0f64), ok)
}

fn math_fround(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    ret (js.num_value(f64(f32(x))), ok)
}

fn math_f16round(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (x, e) = m1(it, args)
    if e != ok { ret (js.undefv(), e) }
    ret (js.num_value(js.f16_to_f64(js.f64_to_f16(x))), ok)
}

fn math_clz32(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (u, e) = js.to_uint32(it, arg(args, 0usize))
    if e != ok { ret (js.undefv(), e) }
    if u == 0u32 { ret (js.num_value(32.0f64), ok) }
    var n = 0u32
    var v = u
    while (v & 2147483648u32) == 0u32 {
        n += 1u32
        v = v << 1u32
    }
    ret (js.num_value(f64(n)), ok)
}

fn math_imul(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (a, e) = js.to_int32(it, arg(args, 0usize))
    if e != ok { ret (js.undefv(), e) }
    let (b, e2) = js.to_int32(it, arg(args, 1usize))
    if e2 != ok { ret (js.undefv(), e2) }
    let p = i64(a) * i64(b)
    ret (js.num_value(f64(js.to_int32_value(f64(p & 4294967295i64)))), ok)
}

fn install_math(it: *js.Interp) {
    let m = js.new_plain(it)
    let e0 = js.define_data(it, it.global, js.key_of("Math"), js.obj_value(m), js.P_HIDDEN)
    let e1 = js.define_data(it, m, js.key_of_symbol(it.sym_to_string_tag), js.str_value("Math"), js.P_CONFIGURABLE)
    it.last = m
    let c1 = js.define_data(it, it.last, js.key_of("PI"), js.num_value(3.141592653589793f64), 0u8)
    let c2 = js.define_data(it, it.last, js.key_of("E"), js.num_value(2.718281828459045f64), 0u8)
    let c3 = js.define_data(it, it.last, js.key_of("LN2"), js.num_value(0.6931471805599453f64), 0u8)
    let c4 = js.define_data(it, it.last, js.key_of("LN10"), js.num_value(2.302585092994046f64), 0u8)
    let c5 = js.define_data(it, it.last, js.key_of("LOG2E"), js.num_value(1.4426950408889634f64), 0u8)
    let c6 = js.define_data(it, it.last, js.key_of("LOG10E"), js.num_value(0.4342944819032518f64), 0u8)
    let c7 = js.define_data(it, it.last, js.key_of("SQRT2"), js.num_value(1.4142135623730951f64), 0u8)
    let c8 = js.define_data(it, it.last, js.key_of("SQRT1_2"), js.num_value(0.7071067811865476f64), 0u8)
    js.add_method(it, it.last, "abs", 1u32, math_abs)
    js.add_method(it, it.last, "floor", 1u32, math_floor)
    js.add_method(it, it.last, "ceil", 1u32, math_ceil)
    js.add_method(it, it.last, "round", 1u32, math_round)
    js.add_method(it, it.last, "trunc", 1u32, math_trunc)
    js.add_method(it, it.last, "sign", 1u32, math_sign)
    js.add_method(it, it.last, "sqrt", 1u32, math_sqrt)
    js.add_method(it, it.last, "cbrt", 1u32, math_cbrt)
    js.add_method(it, it.last, "pow", 2u32, math_pow)
    js.add_method(it, it.last, "exp", 1u32, math_exp)
    js.add_method(it, it.last, "expm1", 1u32, math_expm1)
    js.add_method(it, it.last, "log", 1u32, math_log)
    js.add_method(it, it.last, "log2", 1u32, math_log2)
    js.add_method(it, it.last, "log10", 1u32, math_log10)
    js.add_method(it, it.last, "log1p", 1u32, math_log1p)
    js.add_method(it, it.last, "sin", 1u32, math_sin)
    js.add_method(it, it.last, "cos", 1u32, math_cos)
    js.add_method(it, it.last, "tan", 1u32, math_tan)
    js.add_method(it, it.last, "asin", 1u32, math_asin)
    js.add_method(it, it.last, "acos", 1u32, math_acos)
    js.add_method(it, it.last, "atan", 1u32, math_atan)
    js.add_method(it, it.last, "atan2", 2u32, math_atan2)
    js.add_method(it, it.last, "sinh", 1u32, math_sinh)
    js.add_method(it, it.last, "cosh", 1u32, math_cosh)
    js.add_method(it, it.last, "tanh", 1u32, math_tanh)
    js.add_method(it, it.last, "asinh", 1u32, math_asinh)
    js.add_method(it, it.last, "acosh", 1u32, math_acosh)
    js.add_method(it, it.last, "atanh", 1u32, math_atanh)
    js.add_method(it, it.last, "hypot", 2u32, math_hypot)
    js.add_method(it, it.last, "max", 2u32, math_max)
    js.add_method(it, it.last, "min", 2u32, math_min)
    js.add_method(it, it.last, "random", 0u32, math_random)
    js.add_method(it, it.last, "fround", 1u32, math_fround)
    js.add_method(it, it.last, "f16round", 1u32, math_f16round)
    js.add_method(it, it.last, "clz32", 1u32, math_clz32)
    js.add_method(it, it.last, "imul", 2u32, math_imul)
}
