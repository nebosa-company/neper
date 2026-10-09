// The conversion function group of the formula library (L027): TOTEXT (TEXT, STR_VALUE, STRVALUE), TONUMBER
// (VALUE, NUMBER, DECIMAL), TODATE (PARSEDATE) and DATETIME_FORMAT (FORMAT, DATETIMEFORMAT, FORMATDATE), after
// appdor's `src/formula/convertion.js`. `to_fixed` is JavaScript's `Number.prototype.toFixed`.

use e.algo.formula as f
use e.algo.formula.datetime as dt
use e.math
use e.mem
use e.str

// `x.toFixed(digits)`: the exact decimal expansion rounded half up (a tie goes to the larger magnitude), with a
// minus sign for any negative value, and `String(x)` from 1e21 up.
fn to_fixed(a: *mem.Arena, x: f64, digits: usize) -> str {
    if x != x { ret "NaN" }
    var v = x
    var negative = false
    if v < 0.0f64 {
        negative = true
        v = 0.0f64 - v
    }
    if v >= 1.0e21f64 {
        let t = f.number_text(a, v)
        if negative { ret f.join(a, "-", t) }
        ret t
    }
    if v - v != 0.0f64 {
        if negative { ret "-Infinity" }
        ret "Infinity"
    }
    // the exact digits to `digits + 25` places, then rounded by looking at the next digit
    let extra = digits + 25usize
    let (b, be) = str.builder(a, 400usize)
    if be != ok { ret "0" }
    var builder = b
    if str.push_f64_fixed(&builder, v, u8(extra)) != ok { ret "0" }
    let exact = str.done(&builder)
    var point = exact.len
    var i = 0usize
    while i < exact.len {
        if exact[i] == 46u8 {
            point = i
            i = exact.len
        } else {
            i += 1usize
        }
    }
    let whole = exact[0usize..point]
    var frac = ""
    if point < exact.len { frac = exact[point + 1usize..exact.len] }
    // digits of whole + the first `digits` fraction digits, as a mutable decimal string
    let total = whole.len + digits
    let (cells, ce) = mem.alloc[u8](a, total + 1usize)
    if ce != ok { ret "0" }
    var w = 1usize
    cells[0usize] = 48u8
    var k = 0usize
    while k < whole.len {
        cells[w] = whole[k]
        w += 1usize
        k += 1usize
    }
    k = 0usize
    while k < digits {
        if k < frac.len { cells[w] = frac[k] } else { cells[w] = 48u8 }
        w += 1usize
        k += 1usize
    }
    var next = 48u8
    if digits < frac.len { next = frac[digits] }
    if next >= 53u8 {
        var p = w
        var carry = true
        while carry && p > 0usize {
            p -= 1usize
            if cells[p] == 57u8 {
                cells[p] = 48u8
            } else {
                cells[p] += 1u8
                carry = false
            }
        }
    }
    // cells[0] is the carry digit; skip it when zero
    var start = 0usize
    if cells[0usize] == 48u8 { start = 1usize }
    let int_len = whole.len + 1usize - start
    let (out, oe) = mem.alloc[u8](a, w + 3usize)
    if oe != ok { ret "0" }
    var n = 0usize
    if negative {
        out[n] = 45u8
        n += 1usize
    }
    var q = start
    var written = 0usize
    while q < w {
        if written == int_len && digits > 0usize {
            out[n] = 46u8
            n += 1usize
        }
        out[n] = cells[q]
        n += 1usize
        written += 1usize
        q += 1usize
    }
    ret out[0usize..n]
}

fn h_totext(c: *f.Call) -> f.Value {
    let v = c.args[0usize]
    if f.is_error(v) { ret v }
    if c.args.len > 1usize && !f.is_blank(c.args[1usize]) {
        let fmt_value = f.to_text(c.a, c.args[1usize])
        var fmt = ""
        if f.is_error(fmt_value) { fmt = f.code_text(fmt_value.code) } else { fmt = fmt_value.s }
        if v.kind == .Date { ret f.text(dt.format_date(c.a, v.n, fmt)) }
        // /0\.(0+)/
        var i = 0usize
        var zeros = 0usize
        while i + 2usize < fmt.len && zeros == 0usize {
            if fmt[i] == 48u8 && fmt[i + 1usize] == 46u8 && fmt[i + 2usize] == 48u8 {
                var q = i + 2usize
                while q < fmt.len && fmt[q] == 48u8 {
                    zeros += 1usize
                    q += 1usize
                }
            }
            i += 1usize
        }
        if zeros > 0usize {
            let n = f.to_number(c.a, v)
            if f.is_error(n) { ret n }
            if n.kind == .Blank { ret f.text("") }
            if zeros > 100usize { ret f.generic_error("toFixed() digits argument must be between 0 and 100") }
            ret f.text(to_fixed(c.a, n.n, zeros))
        }
    }
    if f.is_blank(v) { ret f.text("") }
    ret f.to_text(c.a, v)
}

fn h_tonumber(c: *f.Call) -> f.Value {
    let n = f.to_number(c.a, c.args[0usize])
    if f.is_error(n) { ret n }
    if n.kind == .Blank { ret f.number(0.0f64) }
    ret n
}

fn h_todate(c: *f.Call) -> f.Value {
    if f.is_blank(c.args[0usize]) { ret f.blank() }
    if c.args.len > 1usize && !f.is_blank(c.args[1usize]) {
        let t = f.to_text(c.a, c.args[0usize])
        let fmt = f.to_text(c.a, c.args[1usize])
        var text_value = ""
        if f.is_error(t) { text_value = f.code_text(t.code) } else { text_value = t.s }
        var fmt_value = ""
        if f.is_error(fmt) { fmt_value = f.code_text(fmt.code) } else { fmt_value = fmt.s }
        let (ms, good) = dt.parse_date_with_format(c.a, text_value, fmt_value)
        if good { ret f.date(ms) }
        ret f.value_error("TODATE could not read that text in that format")
    }
    ret f.to_date(c.a, c.args[0usize])
}

fn h_datetime_format(c: *f.Call) -> f.Value {
    if f.is_blank(c.args[0usize]) { ret f.text("") }
    let d = f.to_date(c.a, c.args[0usize])
    if f.is_error(d) { ret d }
    if d.kind != .Date { ret f.value_error("FORMAT expects a date") }
    let fmt = f.to_text(c.a, c.args[1usize])
    var fmt_value = ""
    if f.is_error(fmt) { fmt_value = f.code_text(fmt.code) } else { fmt_value = fmt.s }
    ret f.text(dt.format_date(c.a, d.n, fmt_value))
}

fn add(r: *f.Registry, a: *mem.Arena, name: str, aliases: []const str, low: i32, high: i32, handler: f.Handler) -> err {
    ret f.register(r, a, f.Entry { name: name, key: "", aliases: aliases, category: "convertion", lazy: false, pass_errors: false, volatile_fn: false, generate_once: false, min_args: low, max_args: high, handler: handler })
}

fn aliases3(a: *mem.Arena, x: str, y: str, z: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 3usize)
    s[0usize] = x
    s[1usize] = y
    s[2usize] = z
    ret s
}

fn aliases4(a: *mem.Arena, x: str, y: str, z: str, w: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 4usize)
    s[0usize] = x
    s[1usize] = y
    s[2usize] = z
    s[3usize] = w
    ret s
}

fn aliases1(a: *mem.Arena, x: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 1usize)
    s[0usize] = x
    ret s
}

// Register the conversion functions.
fn register(r: *f.Registry, a: *mem.Arena) -> err {
    try add(r, a, "TOTEXT", aliases3(a, "TEXT", "STR_VALUE", "STRVALUE"), 1i32, 2i32, h_totext)
    try add(r, a, "TONUMBER", aliases3(a, "VALUE", "NUMBER", "DECIMAL"), 1i32, 1i32, h_tonumber)
    try add(r, a, "TODATE", aliases1(a, "PARSEDATE"), 1i32, 2i32, h_todate)
    try add(r, a, "DATETIME_FORMAT", aliases3(a, "FORMAT", "DATETIMEFORMAT", "FORMATDATE"), 2i32, 2i32, h_datetime_format)
    ret ok
}
