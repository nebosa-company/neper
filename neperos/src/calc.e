// Calc (D2205, D2206), the first full app screen of the UI (ux/calculator.jpg): cream cards on a
// dark ground, three tabs -- Basic, Scientific and Convert -- over one display and keypad, driven by
// taps the compositor routes to it (appkit.e). A tap on the bar at the bottom of the screen leaves the
// app and the shell redraws Home.
//   Basic       digits, a decimal point, + - x /, =, C, +/-, sqrt and DEL, on the usual
//               immediate-execution model.
//   Scientific  the same, plus sin, cos, tan (degrees, or radians when the DEG tag is tapped), log,
//               ln, exp, pi and x^y.
//   Convert     the units of Android's converter -- length, area, volume, mass, temperature, time,
//               speed, data, energy and angle; tap a unit to step through the category's units,
//               SWAP to exchange them.
// Started by the shell with the five fonts as args[1..5].
use e.mem
use e.os
use e.math
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use appkit
use text

const BASIC: usize = 0usize
const SCIENTIFIC: usize = 1usize
const CONVERT: usize = 2usize

fn say(line: str) {
    let (written, write_error) = os.write(os.stdout(), line)
}

// Print a string that lives in the arena: the console call reads the program's own window only, so
// the bytes go through a buffer on the stack.
fn say_text(value: str) {
    var buffer: [40]u8 = zero
    var n = 0usize
    while n < value.len && n < 40usize {
        buffer[n] = value[n]
        n += 1usize
    }
    say(buffer[0usize..n])
}

// ----------------------------------------------------------------------------------------------
// Number text.

// `value` as text into `out`: up to eight decimals with trailing zeros trimmed, or scientific
// (1.5e-7) when it is very large or very small. Returns the length.
fn format_value(value: f64, out: []u8) -> usize {
    var n = 0usize
    var v = value
    if v < 0.0f64 {
        out[n] = 45u8
        n += 1usize
        v = 0.0f64 - v
    }
    if v == 0.0f64 {
        out[n] = 48u8
        ret n + 1usize
    }
    if v >= 1000000000000.0f64 || v < 0.000001f64 {
        var exponent = i64(math.log10[f64](v))
        if math.log10[f64](v) < 0.0f64 && f64(exponent) != math.log10[f64](v) { exponent = exponent - 1i64 }
        var mantissa = v / math.pow[f64](10.0f64, f64(exponent))
        if mantissa >= 10.0f64 {
            mantissa = mantissa / 10.0f64
            exponent = exponent + 1i64
        }
        if mantissa < 1.0f64 {
            mantissa = mantissa * 10.0f64
            exponent = exponent - 1i64
        }
        n += format_fixed(mantissa, 5usize, out, n)
        out[n] = 101u8
        n += 1usize
        var e = exponent
        if e < 0i64 {
            out[n] = 45u8
            n += 1usize
            e = 0i64 - e
        }
        var digits: [4]u8 = zero
        var count = 0usize
        var open = true
        while open {
            digits[count] = u8(e % 10i64) + 48u8
            count += 1usize
            e = e / 10i64
            if e == 0i64 { open = false }
        }
        while count > 0usize {
            count -= 1usize
            out[n] = digits[count]
            n += 1usize
        }
        ret n
    }
    n += format_fixed(v, 8usize, out, n)
    ret n
}

// A non-negative value in fixed notation into `out` at `at`: the whole part, then up to `decimals`
// decimals with trailing zeros trimmed. Returns how many bytes it wrote.
fn format_fixed(value: f64, decimals: usize, out: []u8, at: usize) -> usize {
    var n = at
    let whole = i64(value)
    var digits: [20]u8 = zero
    var count = 0usize
    var rest = whole
    var open = true
    while open {
        digits[count] = u8(rest % 10i64) + 48u8
        count += 1usize
        rest = rest / 10i64
        if rest == 0i64 { open = false }
    }
    while count > 0usize {
        count -= 1usize
        out[n] = digits[count]
        n += 1usize
    }
    var scale = 1.0f64
    var d = 0usize
    while d < decimals {
        scale = scale * 10.0f64
        d += 1usize
    }
    var scaled = i64((value - f64(whole)) * scale + 0.5f64)
    if scaled >= i64(scale) {
        // Rounding carried into the whole part (0.999999999 -> 1): redo with the next whole.
        n = at
        ret format_fixed(f64(whole + 1i64), decimals, out, at) + 0usize
    }
    if scaled > 0i64 {
        var fraction: [8]u8 = zero
        var f = decimals
        while f > 0usize {
            f -= 1usize
            fraction[f] = u8(scaled % 10i64) + 48u8
            scaled = scaled / 10i64
        }
        var last = decimals
        while last > 0usize && fraction[last - 1usize] == 48u8 { last -= 1usize }
        if last > 0usize {
            out[n] = 46u8
            n += 1usize
            var i = 0usize
            while i < last {
                out[n] = fraction[i]
                n += 1usize
                i += 1usize
            }
        }
    }
    ret n - at
}

// A typed number (digits, one point, an optional leading minus, or a formatted result with an
// exponent) as a value.
fn parse_value(text_in: []const u8, length: usize) -> f64 {
    var value = 0.0f64
    var scale = 1.0f64
    var after_point = false
    var negative = false
    var exponent = 0i64
    var exponent_negative = false
    var in_exponent = false
    var i = 0usize
    while i < length {
        let ch = text_in[i]
        if in_exponent {
            if ch == 45u8 {
                exponent_negative = true
            } else {
                exponent = exponent * 10i64 + i64(ch - 48u8)
            }
        } else if ch == 101u8 {
            in_exponent = true
        } else if ch == 45u8 {
            negative = true
        } else if ch == 46u8 {
            after_point = true
        } else if after_point {
            scale = scale / 10.0f64
            value = value + f64(ch - 48u8) * scale
        } else {
            value = value * 10.0f64 + f64(ch - 48u8)
        }
        i += 1usize
    }
    if in_exponent {
        var power = exponent
        if exponent_negative { power = 0i64 - exponent }
        value = value * math.pow[f64](10.0f64, f64(power))
    }
    if negative { value = 0.0f64 - value }
    ret value
}

// ----------------------------------------------------------------------------------------------
// The calculator engine (Basic and Scientific).

type Calc = struct { acc: f64, result: f64, from_result: bool, entry: [24]u8, entry_len: usize, op: u8, pending: bool, fresh: bool, failed: bool, expr: [64]u8, expr_len: usize, radians: bool }

fn is_digit(key: u8) -> bool {
    ret key >= 48u8 && key <= 57u8
}

fn is_operator(key: u8) -> bool {
    ret key == 43u8 || key == 45u8 || key == 42u8 || key == 47u8 || key == 94u8
}

// The functions of the scientific pad: sin, cos, tan, log (base 10), ln, exp and pi.
fn is_function(key: u8) -> bool {
    ret key == 115u8 || key == 99u8 || key == 116u8 || key == 108u8 || key == 110u8 || key == 101u8 || key == 112u8
}

fn expr_add(c: *Calc, byte: u8) {
    if c.expr_len < 64usize {
        c.expr[c.expr_len] = byte
        c.expr_len += 1usize
    }
}

// The UTF-8 of an operator, for the expression line.
fn expr_operator(c: *Calc, op: u8) {
    expr_add(c, 32u8)
    if op == 42u8 {
        expr_add(c, 195u8)
        expr_add(c, 151u8)
    } else if op == 47u8 {
        expr_add(c, 195u8)
        expr_add(c, 183u8)
    } else if op == 45u8 {
        expr_add(c, 226u8)
        expr_add(c, 136u8)
        expr_add(c, 146u8)
    } else {
        expr_add(c, op)
    }
    expr_add(c, 32u8)
}

fn expr_entry(c: *Calc) {
    var i = 0usize
    while i < c.entry_len {
        expr_add(c, c.entry[i])
        i += 1usize
    }
}

// The value on the display: a result kept exactly, else the typed number, else the accumulator.
fn shown_value(c: *Calc) -> f64 {
    if c.entry_len > 0usize {
        if c.from_result { ret c.result }
        ret parse_value(c.entry[0usize..], c.entry_len)
    }
    ret c.acc
}

fn clear(c: *Calc) {
    c.acc = 0.0f64
    c.result = 0.0f64
    c.from_result = false
    c.entry_len = 0usize
    c.op = 0u8
    c.pending = false
    c.fresh = false
    c.failed = false
    c.expr_len = 0usize
}

// Put a computed value on the display (kept exact for the next operation).
fn set_result(c: *Calc, value: f64) {
    if value != value || value > 1.0e300f64 || value < -1.0e300f64 {
        c.failed = true
        c.entry_len = 0usize
        ret
    }
    c.result = value
    c.from_result = true
    var buffer: [24]u8 = zero
    let n = format_value(value, buffer[0usize..])
    var i = 0usize
    while i < n {
        c.entry[i] = buffer[i]
        i += 1usize
    }
    c.entry_len = n
}

fn apply(c: *Calc, left: f64, op: u8, right: f64) -> f64 {
    if op == 43u8 { ret left + right }
    if op == 45u8 { ret left - right }
    if op == 42u8 { ret left * right }
    if op == 94u8 { ret math.pow[f64](left, right) }
    if right == 0.0f64 {
        c.failed = true
        ret 0.0f64
    }
    ret left / right
}

fn degrees_to_radians(c: *Calc, v: f64) -> f64 {
    if c.radians { ret v }
    ret v * 0.017453292519943295f64
}

// One key press.
fn press(c: *Calc, key: u8) {
    if key == 67u8 {
        clear(c)
        ret
    }
    if c.failed { clear(c) }
    if is_digit(key) || key == 46u8 {
        if c.fresh || c.from_result {
            clear(c)
        }
        if key == 46u8 {
            var has_point = false
            var i = 0usize
            while i < c.entry_len {
                if c.entry[i] == 46u8 { has_point = true }
                i += 1usize
            }
            if has_point { ret }
            if c.entry_len == 0usize {
                c.entry[0usize] = 48u8
                c.entry_len = 1usize
            }
        }
        if c.entry_len < 14usize {
            c.entry[c.entry_len] = key
            c.entry_len += 1usize
        }
        ret
    }
    if key == 68u8 {
        if c.from_result {
            c.entry_len = 0usize
            c.from_result = false
        } else if c.entry_len > 0usize {
            c.entry_len -= 1usize
        }
        ret
    }
    if key == 78u8 {
        if c.entry_len > 0usize {
            if c.from_result {
                set_result(c, 0.0f64 - c.result)
            } else if c.entry[0usize] == 45u8 {
                var i = 1usize
                while i < c.entry_len {
                    c.entry[i - 1usize] = c.entry[i]
                    i += 1usize
                }
                c.entry_len -= 1usize
            } else if c.entry_len < 16usize {
                var i = c.entry_len
                while i > 0usize {
                    c.entry[i] = c.entry[i - 1usize]
                    i -= 1usize
                }
                c.entry[0usize] = 45u8
                c.entry_len += 1usize
            }
        } else {
            c.acc = 0.0f64 - c.acc
        }
        ret
    }
    if key == 82u8 || is_function(key) {
        let v = shown_value(c)
        var out = 0.0f64
        if key == 82u8 {
            if v < 0.0f64 {
                c.failed = true
                ret
            }
            out = math.sqrt[f64](v)
        } else if key == 115u8 {
            out = math.sin[f64](degrees_to_radians(c, v))
        } else if key == 99u8 {
            out = math.cos[f64](degrees_to_radians(c, v))
        } else if key == 116u8 {
            out = math.tan[f64](degrees_to_radians(c, v))
        } else if key == 108u8 {
            if v <= 0.0f64 {
                c.failed = true
                ret
            }
            out = math.log10[f64](v)
        } else if key == 110u8 {
            if v <= 0.0f64 {
                c.failed = true
                ret
            }
            out = math.log[f64](v)
        } else if key == 101u8 {
            out = math.exp[f64](v)
        } else {
            out = 3.141592653589793f64
        }
        // A tidy zero for sin(180) and cos(90), whose exact value rounds off the unit circle.
        if out < 0.000000000001f64 && out > -0.000000000001f64 { out = 0.0f64 }
        c.fresh = false
        set_result(c, out)
        ret
    }
    if is_operator(key) {
        if c.entry_len > 0usize {
            let typed = shown_value(c)
            if c.pending {
                c.acc = apply(c, c.acc, c.op, typed)
            } else {
                c.acc = typed
            }
            if c.fresh {
                c.expr_len = 0usize
            }
            expr_entry(c)
        } else if !c.pending && c.expr_len == 0usize {
            expr_add(c, 48u8)
        }
        c.entry_len = 0usize
        c.from_result = false
        c.fresh = false
        c.op = key
        c.pending = true
        expr_operator(c, key)
        ret
    }
    if key == 61u8 {
        if c.pending && c.entry_len > 0usize {
            let typed = shown_value(c)
            expr_entry(c)
            expr_add(c, 32u8)
            expr_add(c, 61u8)
            let result = apply(c, c.acc, c.op, typed)
            c.pending = false
            c.acc = result
            set_result(c, result)
            c.fresh = true
        }
        ret
    }
}

// The display's main line: "Error" after a failure, the typed number, else the accumulator.
fn display_text(a: *mem.Arena, c: *Calc) -> str {
    if c.failed { ret "Error" }
    var buffer: [24]u8 = zero
    var n = 0usize
    if c.entry_len > 0usize {
        var i = 0usize
        while i < c.entry_len {
            buffer[i] = c.entry[i]
            i += 1usize
        }
        n = c.entry_len
    } else {
        n = format_value(c.acc, buffer[0usize..])
    }
    let (copy, copy_error) = mem.alloc[u8](a, n)
    if copy_error != ok { ret "0" }
    var i = 0usize
    while i < n {
        copy[i] = buffer[i]
        i += 1usize
    }
    ret copy[0usize..n]
}

// ----------------------------------------------------------------------------------------------
// The converter.

type Conv = struct { category: usize, from: usize, to: usize, entry: [16]u8, entry_len: usize }

fn category_count() -> usize {
    ret 10usize
}

// The categories of Android's unit converter, less currency (which needs a network).
fn category_name(category: usize) -> str {
    if category == 0usize { ret "Length" }
    if category == 1usize { ret "Area" }
    if category == 2usize { ret "Volume" }
    if category == 3usize { ret "Mass" }
    if category == 4usize { ret "Temp" }
    if category == 5usize { ret "Time" }
    if category == 6usize { ret "Speed" }
    if category == 7usize { ret "Data" }
    if category == 8usize { ret "Energy" }
    ret "Angle"
}

fn unit_count(category: usize) -> usize {
    if category == 0usize { ret 8usize }
    if category == 1usize { ret 7usize }
    if category == 2usize { ret 8usize }
    if category == 3usize { ret 6usize }
    if category == 4usize { ret 3usize }
    if category == 5usize { ret 7usize }
    if category == 6usize { ret 5usize }
    if category == 7usize { ret 6usize }
    if category == 8usize { ret 6usize }
    ret 4usize
}

fn unit_name(category: usize, unit: usize) -> str {
    if category == 0usize {
        if unit == 0usize { ret "m" }
        if unit == 1usize { ret "km" }
        if unit == 2usize { ret "cm" }
        if unit == 3usize { ret "mm" }
        if unit == 4usize { ret "mi" }
        if unit == 5usize { ret "yd" }
        if unit == 6usize { ret "ft" }
        ret "in"
    }
    if category == 1usize {
        if unit == 0usize { ret "m\xC2\xB2" }
        if unit == 1usize { ret "km\xC2\xB2" }
        if unit == 2usize { ret "cm\xC2\xB2" }
        if unit == 3usize { ret "ha" }
        if unit == 4usize { ret "ft\xC2\xB2" }
        if unit == 5usize { ret "in\xC2\xB2" }
        ret "acre"
    }
    if category == 2usize {
        if unit == 0usize { ret "L" }
        if unit == 1usize { ret "mL" }
        if unit == 2usize { ret "m\xC2\xB3" }
        if unit == 3usize { ret "gal" }
        if unit == 4usize { ret "qt" }
        if unit == 5usize { ret "pt" }
        if unit == 6usize { ret "cup" }
        ret "fl oz"
    }
    if category == 3usize {
        if unit == 0usize { ret "kg" }
        if unit == 1usize { ret "g" }
        if unit == 2usize { ret "mg" }
        if unit == 3usize { ret "t" }
        if unit == 4usize { ret "lb" }
        ret "oz"
    }
    if category == 4usize {
        if unit == 0usize { ret "\xC2\xB0C" }
        if unit == 1usize { ret "\xC2\xB0F" }
        ret "K"
    }
    if category == 5usize {
        if unit == 0usize { ret "s" }
        if unit == 1usize { ret "ms" }
        if unit == 2usize { ret "min" }
        if unit == 3usize { ret "h" }
        if unit == 4usize { ret "day" }
        if unit == 5usize { ret "week" }
        ret "year"
    }
    if category == 6usize {
        if unit == 0usize { ret "m/s" }
        if unit == 1usize { ret "km/h" }
        if unit == 2usize { ret "mph" }
        if unit == 3usize { ret "knot" }
        ret "ft/s"
    }
    if category == 7usize {
        if unit == 0usize { ret "bit" }
        if unit == 1usize { ret "B" }
        if unit == 2usize { ret "KB" }
        if unit == 3usize { ret "MB" }
        if unit == 4usize { ret "GB" }
        ret "TB"
    }
    if category == 8usize {
        if unit == 0usize { ret "J" }
        if unit == 1usize { ret "kJ" }
        if unit == 2usize { ret "cal" }
        if unit == 3usize { ret "kcal" }
        if unit == 4usize { ret "Wh" }
        ret "kWh"
    }
    if unit == 0usize { ret "deg" }
    if unit == 1usize { ret "rad" }
    if unit == 2usize { ret "grad" }
    ret "turn"
}

// How many of the category's base unit (m, m2, L, kg, s, m/s, B, J, deg) one of this unit is; not
// used for temperature.
fn unit_factor(category: usize, unit: usize) -> f64 {
    if category == 0usize {
        if unit == 0usize { ret 1.0f64 }
        if unit == 1usize { ret 1000.0f64 }
        if unit == 2usize { ret 0.01f64 }
        if unit == 3usize { ret 0.001f64 }
        if unit == 4usize { ret 1609.344f64 }
        if unit == 5usize { ret 0.9144f64 }
        if unit == 6usize { ret 0.3048f64 }
        ret 0.0254f64
    }
    if category == 1usize {
        if unit == 0usize { ret 1.0f64 }
        if unit == 1usize { ret 1000000.0f64 }
        if unit == 2usize { ret 0.0001f64 }
        if unit == 3usize { ret 10000.0f64 }
        if unit == 4usize { ret 0.09290304f64 }
        if unit == 5usize { ret 0.00064516f64 }
        ret 4046.8564224f64
    }
    if category == 2usize {
        if unit == 0usize { ret 1.0f64 }
        if unit == 1usize { ret 0.001f64 }
        if unit == 2usize { ret 1000.0f64 }
        if unit == 3usize { ret 3.785411784f64 }
        if unit == 4usize { ret 0.946352946f64 }
        if unit == 5usize { ret 0.473176473f64 }
        if unit == 6usize { ret 0.2365882365f64 }
        ret 0.0295735295625f64
    }
    if category == 3usize {
        if unit == 0usize { ret 1.0f64 }
        if unit == 1usize { ret 0.001f64 }
        if unit == 2usize { ret 0.000001f64 }
        if unit == 3usize { ret 1000.0f64 }
        if unit == 4usize { ret 0.45359237f64 }
        ret 0.028349523125f64
    }
    if category == 5usize {
        if unit == 0usize { ret 1.0f64 }
        if unit == 1usize { ret 0.001f64 }
        if unit == 2usize { ret 60.0f64 }
        if unit == 3usize { ret 3600.0f64 }
        if unit == 4usize { ret 86400.0f64 }
        if unit == 5usize { ret 604800.0f64 }
        ret 31557600.0f64
    }
    if category == 6usize {
        if unit == 0usize { ret 1.0f64 }
        if unit == 1usize { ret 0.2777777777777778f64 }
        if unit == 2usize { ret 0.44704f64 }
        if unit == 3usize { ret 0.5144444444444445f64 }
        ret 0.3048f64
    }
    if category == 7usize {
        if unit == 0usize { ret 0.125f64 }
        if unit == 1usize { ret 1.0f64 }
        if unit == 2usize { ret 1000.0f64 }
        if unit == 3usize { ret 1000000.0f64 }
        if unit == 4usize { ret 1000000000.0f64 }
        ret 1000000000000.0f64
    }
    if category == 8usize {
        if unit == 0usize { ret 1.0f64 }
        if unit == 1usize { ret 1000.0f64 }
        if unit == 2usize { ret 4.184f64 }
        if unit == 3usize { ret 4184.0f64 }
        if unit == 4usize { ret 3600.0f64 }
        ret 3600000.0f64
    }
    if unit == 0usize { ret 1.0f64 }
    if unit == 1usize { ret 57.29577951308232f64 }
    if unit == 2usize { ret 0.9f64 }
    ret 360.0f64
}

fn convert_value(category: usize, from: usize, to: usize, value: f64) -> f64 {
    if category == 4usize {
        var celsius = value
        if from == 1usize { celsius = (value - 32.0f64) * 5.0f64 / 9.0f64 }
        if from == 2usize { celsius = value - 273.15f64 }
        if to == 1usize { ret celsius * 9.0f64 / 5.0f64 + 32.0f64 }
        if to == 2usize { ret celsius + 273.15f64 }
        ret celsius
    }
    ret value * unit_factor(category, from) / unit_factor(category, to)
}

fn conv_press(v: *Conv, key: u8) {
    if key == 67u8 {
        v.entry_len = 0usize
        ret
    }
    if key == 68u8 {
        if v.entry_len > 0usize { v.entry_len -= 1usize }
        ret
    }
    if key == 83u8 {
        let was = v.from
        v.from = v.to
        v.to = was
        ret
    }
    if key == 78u8 {
        if v.entry_len > 0usize {
            if v.entry[0usize] == 45u8 {
                var i = 1usize
                while i < v.entry_len {
                    v.entry[i - 1usize] = v.entry[i]
                    i += 1usize
                }
                v.entry_len -= 1usize
            } else if v.entry_len < 14usize {
                var i = v.entry_len
                while i > 0usize {
                    v.entry[i] = v.entry[i - 1usize]
                    i -= 1usize
                }
                v.entry[0usize] = 45u8
                v.entry_len += 1usize
            }
        }
        ret
    }
    if key == 46u8 {
        var has_point = false
        var i = 0usize
        while i < v.entry_len {
            if v.entry[i] == 46u8 { has_point = true }
            i += 1usize
        }
        if has_point { ret }
        if v.entry_len == 0usize {
            v.entry[0usize] = 48u8
            v.entry_len = 1usize
        }
    }
    if v.entry_len < 12usize && (is_digit(key) || key == 46u8) {
        v.entry[v.entry_len] = key
        v.entry_len += 1usize
    }
}

fn conv_value(v: *Conv) -> f64 {
    if v.entry_len == 0usize { ret 0.0f64 }
    ret parse_value(v.entry[0usize..], v.entry_len)
}

// ----------------------------------------------------------------------------------------------
// Layout (dp). The same functions draw and hit-test.

fn pad_top(mode: usize) -> f32 {
    if mode == BASIC { ret 290.0 }
    if mode == SCIENTIFIC { ret 414.0 }
    ret 440.0
}

fn pad_rows(mode: usize) -> usize {
    if mode == CONVERT { ret 4usize }
    ret 5usize
}

// The key at a place on the keypad of `mode`: its character code.
fn key_at(mode: usize, row: usize, col: usize) -> u8 {
    if mode == CONVERT {
        if row == 0usize {
            if col == 0usize { ret 55u8 }
            if col == 1usize { ret 56u8 }
            if col == 2usize { ret 57u8 }
            ret 67u8
        }
        if row == 1usize {
            if col == 0usize { ret 52u8 }
            if col == 1usize { ret 53u8 }
            if col == 2usize { ret 54u8 }
            ret 68u8
        }
        if row == 2usize {
            if col == 0usize { ret 49u8 }
            if col == 1usize { ret 50u8 }
            if col == 2usize { ret 51u8 }
            ret 78u8
        }
        if col == 0usize { ret 48u8 }
        if col == 1usize { ret 46u8 }
        if col == 2usize { ret 83u8 }
        ret 0u8
    }
    if row == 0usize {
        if col == 0usize { ret 67u8 }
        if col == 1usize { ret 78u8 }
        if col == 2usize { ret 82u8 }
        ret 47u8
    }
    if row == 1usize {
        if col == 0usize { ret 55u8 }
        if col == 1usize { ret 56u8 }
        if col == 2usize { ret 57u8 }
        ret 42u8
    }
    if row == 2usize {
        if col == 0usize { ret 52u8 }
        if col == 1usize { ret 53u8 }
        if col == 2usize { ret 54u8 }
        ret 45u8
    }
    if row == 3usize {
        if col == 0usize { ret 49u8 }
        if col == 1usize { ret 50u8 }
        if col == 2usize { ret 51u8 }
        ret 43u8
    }
    if col == 0usize { ret 48u8 }
    if col == 1usize { ret 46u8 }
    if col == 2usize { ret 68u8 }
    ret 61u8
}

// The scientific pad's two rows of four function keys.
fn func_at(row: usize, col: usize) -> u8 {
    if row == 0usize {
        if col == 0usize { ret 115u8 }
        if col == 1usize { ret 99u8 }
        if col == 2usize { ret 116u8 }
        ret 108u8
    }
    if col == 0usize { ret 110u8 }
    if col == 1usize { ret 101u8 }
    if col == 2usize { ret 112u8 }
    ret 94u8
}

fn key_label(key: u8) -> str {
    if key == 67u8 { ret "C" }
    if key == 78u8 { ret "\xC2\xB1" }
    if key == 82u8 { ret "sqrt" }
    if key == 47u8 { ret "\xC3\xB7" }
    if key == 42u8 { ret "\xC3\x97" }
    if key == 45u8 { ret "\xE2\x88\x92" }
    if key == 43u8 { ret "+" }
    if key == 61u8 { ret "=" }
    if key == 68u8 { ret "DEL" }
    if key == 46u8 { ret "." }
    if key == 83u8 { ret "SWAP" }
    if key == 115u8 { ret "sin" }
    if key == 99u8 { ret "cos" }
    if key == 116u8 { ret "tan" }
    if key == 108u8 { ret "log" }
    if key == 110u8 { ret "ln" }
    if key == 101u8 { ret "exp" }
    if key == 112u8 { ret "pi" }
    if key == 94u8 { ret "x^y" }
    ret ""
}

// The tab under a tap, or 99.
fn tab_at(x: f32, y: f32) -> usize {
    if y < 122.0 || y >= 158.0 || x < 36.0 || x >= 376.0 { ret 99usize }
    let tab = usize((x - 36.0) / 116.0)
    if (x - 36.0) - f32(tab) * 116.0 >= 108.0 || tab > 2usize { ret 99usize }
    ret tab
}

fn tab_name(tab: usize) -> str {
    if tab == 0usize { ret "Basic" }
    if tab == 1usize { ret "Scientific" }
    ret "Convert"
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn cream(alpha: f32) -> paint.Color {
    ret paint.Color { red: 0.92, green: 0.90, blue: 0.86, alpha: alpha }
}

fn ink() -> paint.Color {
    ret paint.Color { red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0 }
}

fn muted() -> paint.Color {
    ret paint.Color { red: 0.36, green: 0.35, blue: 0.34, alpha: 1.0 }
}

fn card(a: *mem.Arena, builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.rect_path(a, x, y, w, h, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

// One key: a soft shadow, the cap and its label centred.
fn draw_key(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, x: f32, y: f32, w: f32, h: f32, label: str, fill: paint.Color, size: f32) -> err {
    try card(a, builder, x, y + 3.0, w, h, 12.0, paint.Color { red: 0.25, green: 0.24, blue: 0.22, alpha: 0.28 })
    try card(a, builder, x, y, w, h, 12.0, fill)
    let width = text.measure(a, faces.grotesk, size, label)
    let (box, draw_error) = text.draw(a, builder, faces.grotesk, size, label, x + w / 2.0 - width / 2.0, y + h / 2.0 - size * 0.62, 0.0, 0u32, layout.Align.Start, ink())
    if draw_error != ok { ret draw_error }
    ret ok
}

fn key_fill(key: u8) -> paint.Color {
    if key == 61u8 { ret paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 } }
    if is_operator(key) { ret paint.Color { red: 0.66, green: 0.66, blue: 0.67, alpha: 1.0 } }
    if key == 67u8 || key == 78u8 || key == 82u8 || key == 68u8 || key == 83u8 { ret paint.Color { red: 0.80, green: 0.79, blue: 0.78, alpha: 1.0 } }
    if is_function(key) { ret paint.Color { red: 0.78, green: 0.82, blue: 0.88, alpha: 1.0 } }
    ret paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 }
}

// A digit's one-character label, in the arena.
fn digit_label(a: *mem.Arena, key: u8) -> str {
    let (digit, digit_error) = mem.alloc[u8](a, 1usize)
    if digit_error != ok { ret "0" }
    digit[0usize] = key
    ret digit[0usize..1usize]
}

fn label_of(a: *mem.Arena, key: u8) -> str {
    if is_digit(key) { ret digit_label(a, key) }
    ret key_label(key)
}

fn draw_chrome(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, mode: usize) -> err {
    let faces = kit.faces
    // The backdrop's alpha alternates by 0.2% each frame (invisible): the renderer redraws only the
    // box of what changed, and left a changed text box without the cards under it, so a frame that
    // always differs in its first command is drawn whole.
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0 - f32(kit.frame % 2usize) * 0.002 } } } })
    try card(a, builder, 20.0, 40.0, 372.0, 56.0, 14.0, cream(0.96))
    let (t0, e0) = text.draw(a, builder, faces.sora, 22.0, "CALC", 36.0, 53.0, 0.0, 0u32, layout.Align.Start, ink())
    if e0 != ok { ret e0 }
    try card(a, builder, 20.0, 108.0, 372.0, 730.0, 16.0, cream(0.92))
    // The tabs.
    var tab = 0usize
    while tab < 3usize {
        let x = 36.0 + f32(tab) * 116.0
        var fill = paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }
        if tab == mode { fill = paint.Color { red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0 } }
        try card(a, builder, x, 122.0, 108.0, 34.0, 17.0, fill)
        var ink_color = muted()
        if tab == mode { ink_color = paint.Color { red: 0.95, green: 0.94, blue: 0.92, alpha: 1.0 } }
        let name = tab_name(tab)
        let width = text.measure(a, faces.jost, 15.0, name)
        let (box, draw_error) = text.draw(a, builder, faces.jost, 15.0, name, x + 54.0 - width / 2.0, 130.0, 0.0, 0u32, layout.Align.Start, ink_color)
        if draw_error != ok { ret draw_error }
        tab += 1usize
    }
    // The home bar.
    try card(a, builder, 156.0, 876.0, 100.0, 6.0, 3.0, paint.Color { red: 0.9, green: 0.9, blue: 0.92, alpha: 0.85 })
    ret ok
}

fn draw_calculator(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, mode: usize, c: *Calc) -> err {
    let faces = kit.faces
    // The display: the expression above the result, and the angle unit in the scientific mode.
    try card(a, builder, 36.0, 166.0, 340.0, 112.0, 10.0, paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 })
    if mode == SCIENTIFIC {
        var unit = "DEG"
        if c.radians { unit = "RAD" }
        let (tu, eu) = text.draw(a, builder, faces.grotesk, 14.0, unit, 48.0, 176.0, 0.0, 0u32, layout.Align.Start, muted())
        if eu != ok { ret eu }
    }
    if c.expr_len > 0usize {
        let (expr, expr_error) = mem.alloc[u8](a, c.expr_len)
        if expr_error != ok { ret expr_error }
        var i = 0usize
        while i < c.expr_len {
            expr[i] = c.expr[i]
            i += 1usize
        }
        let shown = expr[0usize..c.expr_len]
        let (t2, e2) = text.draw(a, builder, faces.grotesk, 16.0, shown, 364.0 - text.measure(a, faces.grotesk, 16.0, shown), 176.0, 0.0, 0u32, layout.Align.Start, paint.Color { red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0 })
        if e2 != ok { ret e2 }
    }
    let result_text = display_text(a, c)
    var size: f32 = 52.0
    if text.measure(a, faces.jost, size, result_text) > 316.0 { size = 36.0 }
    let (t3, e3) = text.draw(a, builder, faces.jost, size, result_text, 364.0 - text.measure(a, faces.jost, size, result_text), 214.0, 0.0, 0u32, layout.Align.Start, ink())
    if e3 != ok { ret e3 }
    // The scientific function keys.
    if mode == SCIENTIFIC {
        var row = 0usize
        while row < 2usize {
            var col = 0usize
            while col < 4usize {
                let key = func_at(row, col)
                try draw_key(a, builder, faces, 36.0 + f32(col) * 88.0, 290.0 + f32(row) * 62.0, 76.0, 50.0, key_label(key), key_fill(key), 20.0)
                col += 1usize
            }
            row += 1usize
        }
    }
    // The keypad.
    var row = 0usize
    while row < pad_rows(mode) {
        var col = 0usize
        while col < 4usize {
            let key = key_at(mode, row, col)
            try draw_key(a, builder, faces, 36.0 + f32(col) * 88.0, pad_top(mode) + f32(row) * 80.0, 76.0, 70.0, label_of(a, key), key_fill(key), 26.0)
            col += 1usize
        }
        row += 1usize
    }
    // The status card of the basic mode.
    if mode == BASIC {
        try card(a, builder, 36.0, 704.0, 340.0, 104.0, 12.0, paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 })
        let (s1, se1) = text.draw(a, builder, faces.exo, 15.0, "STATUS", 52.0, 716.0, 0.0, 0u32, layout.Align.Start, ink())
        if se1 != ok { ret se1 }
        let (s2, se2) = text.draw(a, builder, faces.exo, 15.0, "MODE: BASIC", 52.0, 742.0, 0.0, 0u32, layout.Align.Start, paint.Color { red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0 })
        if se2 != ok { ret se2 }
        let (s3, se3) = text.draw(a, builder, faces.exo, 15.0, "PRECISION: 8 DECIMALS", 52.0, 766.0, 0.0, 0u32, layout.Align.Start, paint.Color { red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0 })
        if se3 != ok { ret se3 }
    }
    ret ok
}

fn conv_result_text(a: *mem.Arena, v: *Conv) -> str {
    var buffer: [24]u8 = zero
    let n = format_value(convert_value(v.category, v.from, v.to, conv_value(v)), buffer[0usize..])
    let (copy, copy_error) = mem.alloc[u8](a, n)
    if copy_error != ok { ret "0" }
    var i = 0usize
    while i < n {
        copy[i] = buffer[i]
        i += 1usize
    }
    ret copy[0usize..n]
}

fn conv_entry_text(a: *mem.Arena, v: *Conv) -> str {
    if v.entry_len == 0usize { ret "0" }
    let (copy, copy_error) = mem.alloc[u8](a, v.entry_len)
    if copy_error != ok { ret "0" }
    var i = 0usize
    while i < v.entry_len {
        copy[i] = v.entry[i]
        i += 1usize
    }
    ret copy[0usize..v.entry_len]
}

// One side of the converter: a card with its unit pill and the value.
fn draw_side(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, y: f32, caption: str, unit: str, value: str) -> err {
    try card(a, builder, 36.0, y, 340.0, 86.0, 12.0, paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 })
    let (c1, ce1) = text.draw(a, builder, faces.exo, 13.0, caption, 52.0, y + 8.0, 0.0, 0u32, layout.Align.Start, muted())
    if ce1 != ok { ret ce1 }
    try card(a, builder, 48.0, y + 30.0, 100.0, 44.0, 22.0, paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 })
    let pill_width = text.measure(a, faces.grotesk, 20.0, unit)
    let (c2, ce2) = text.draw(a, builder, faces.grotesk, 20.0, unit, 98.0 - pill_width / 2.0, y + 41.0, 0.0, 0u32, layout.Align.Start, ink())
    if ce2 != ok { ret ce2 }
    var size: f32 = 40.0
    if text.measure(a, faces.jost, size, value) > 190.0 { size = 28.0 }
    let (c3, ce3) = text.draw(a, builder, faces.jost, size, value, 364.0 - text.measure(a, faces.jost, size, value), y + 26.0, 0.0, 0u32, layout.Align.Start, ink())
    if ce3 != ok { ret ce3 }
    ret ok
}

fn draw_converter(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, v: *Conv) -> err {
    let faces = kit.faces
    // The categories: two rows of five.
    var cat = 0usize
    while cat < category_count() {
        let x = 36.0 + f32(cat % 5usize) * 69.5
        let y = 168.0 + f32(cat / 5usize) * 36.0
        var fill = paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }
        if cat == v.category { fill = paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 } }
        try card(a, builder, x, y, 62.0, 28.0, 14.0, fill)
        let name = category_name(cat)
        let width = text.measure(a, faces.jost, 13.0, name)
        let (box, draw_error) = text.draw(a, builder, faces.jost, 13.0, name, x + 31.0 - width / 2.0, y + 5.0, 0.0, 0u32, layout.Align.Start, ink())
        if draw_error != ok { ret draw_error }
        cat += 1usize
    }
    try draw_side(a, builder, faces, 244.0, "FROM", unit_name(v.category, v.from), conv_entry_text(a, v))
    try draw_side(a, builder, faces, 338.0, "TO", unit_name(v.category, v.to), conv_result_text(a, v))
    var row = 0usize
    while row < 4usize {
        var col = 0usize
        while col < 4usize {
            let key = key_at(CONVERT, row, col)
            if key != 0u8 {
                try draw_key(a, builder, faces, 36.0 + f32(col) * 88.0, pad_top(CONVERT) + f32(row) * 80.0, 76.0, 70.0, label_of(a, key), key_fill(key), 24.0)
            }
            col += 1usize
        }
        row += 1usize
    }
    try card(a, builder, 36.0, 764.0, 340.0, 44.0, 12.0, paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 })
    let (h1, he1) = text.draw(a, builder, faces.exo, 14.0, "Tap a unit to step to the next one.", 52.0, 776.0, 300.0, 1u32, layout.Align.Start, paint.Color { red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0 })
    if he1 != ok { ret he1 }
    ret ok
}

// ----------------------------------------------------------------------------------------------

type State = struct { mode: usize, calc: Calc, conv: Conv }

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    try draw_chrome(a, builder, kit, s.mode)
    if s.mode == CONVERT {
        try draw_converter(a, builder, kit, &s.conv)
    } else {
        try draw_calculator(a, builder, kit, s.mode, &s.calc)
    }
    ret ok
}

// Redraw and present; the compositor takes the frame as its answer. False when it could not.
fn show(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> bool {
    let (next, next_error) = appkit.begin(a, kit)
    if next_error != ok { ret false }
    var builder = next
    if draw(a, &builder, kit, s) != ok { ret false }
    ret appkit.present(kit, &builder)
}

// What a tap did: true when something on the screen changed.
fn handle_tap(s: *State, x: f32, y: f32) -> bool {
    let tab = tab_at(x, y)
    if tab < 3usize {
        if tab == s.mode { ret false }
        s.mode = tab
        ret true
    }
    if s.mode == CONVERT {
        // The categories, the two unit pills, then the keypad.
        if y >= 168.0 && y < 232.0 && x >= 36.0 {
            let col = usize((x - 36.0) / 69.5)
            let row = usize((y - 168.0) / 36.0)
            let cat = row * 5usize + col
            if col < 5usize && row < 2usize && (x - 36.0) - f32(col) * 69.5 < 62.0 && (y - 168.0) - f32(row) * 36.0 < 28.0 && cat < category_count() {
                if cat != s.conv.category {
                    s.conv.category = cat
                    s.conv.from = 0usize
                    s.conv.to = 1usize
                    ret true
                }
            }
            ret false
        }
        if x >= 48.0 && x < 148.0 && y >= 274.0 && y < 318.0 {
            s.conv.from = (s.conv.from + 1usize) % unit_count(s.conv.category)
            ret true
        }
        if x >= 48.0 && x < 148.0 && y >= 368.0 && y < 412.0 {
            s.conv.to = (s.conv.to + 1usize) % unit_count(s.conv.category)
            ret true
        }
        let top = pad_top(CONVERT)
        if y >= top && x >= 36.0 {
            let row = usize((y - top) / 80.0)
            let col = usize((x - 36.0) / 88.0)
            if row < 4usize && col < 4usize && (y - top) - f32(row) * 80.0 < 70.0 && (x - 36.0) - f32(col) * 88.0 < 76.0 {
                let key = key_at(CONVERT, row, col)
                if key != 0u8 {
                    conv_press(&s.conv, key)
                    ret true
                }
            }
        }
        ret false
    }
    // Basic and scientific: the DEG tag, the function keys, the keypad.
    if s.mode == SCIENTIFIC {
        if x >= 40.0 && x < 100.0 && y >= 170.0 && y < 200.0 {
            s.calc.radians = !s.calc.radians
            ret true
        }
        if y >= 290.0 && y < 402.0 && x >= 36.0 {
            let frow = usize((y - 290.0) / 62.0)
            let fcol = usize((x - 36.0) / 88.0)
            if frow < 2usize && fcol < 4usize && (y - 290.0) - f32(frow) * 62.0 < 50.0 && (x - 36.0) - f32(fcol) * 88.0 < 76.0 {
                press(&s.calc, func_at(frow, fcol))
                ret true
            }
        }
    }
    let top = pad_top(s.mode)
    if y >= top && x >= 36.0 {
        let row = usize((y - top) / 80.0)
        let col = usize((x - 36.0) / 88.0)
        if row < 5usize && col < 4usize && (y - top) - f32(row) * 80.0 < 70.0 && (x - 36.0) - f32(col) * 88.0 < 76.0 {
            press(&s.calc, key_at(s.mode, row, col))
            ret true
        }
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "calc")
    if kit_error != ok {
        say("calc open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("calc fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.conv.to = 1usize
    if !show(a, &kit, &s) {
        say("calc present failed\n")
        ret ok
    }
    say("calc shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 850.0 {
            say("calc home\n")
            appkit.leave()
            running = false
        } else if handle_tap(&s, tap.x, tap.y) {
            if !show(a, &kit, &s) {
                say("calc present failed\n")
                appkit.answer(appkit.ANSWER_NONE)
            }
            if s.mode == CONVERT {
                say("calc converts ")
                say_text(conv_entry_text(a, &s.conv))
                say(" ")
                say_text(unit_name(s.conv.category, s.conv.from))
                say(" = ")
                say_text(conv_result_text(a, &s.conv))
                say(" ")
                say_text(unit_name(s.conv.category, s.conv.to))
                say("\n")
            } else if s.mode == SCIENTIFIC {
                say("calc scientific ")
                say_text(display_text(a, &s.calc))
                say("\n")
            } else {
                say("calc shows ")
                say_text(display_text(a, &s.calc))
                say("\n")
            }
        } else {
            appkit.answer(appkit.ANSWER_NONE)
        }
    }
    ret ok
}
