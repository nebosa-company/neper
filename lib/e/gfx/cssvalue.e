// CSS value microsyntax (L039), after Vaper's `vaper_css_values/lib/src/value.dart`: lengths with `calc()`, `min()`,
// `max()`, `clamp()`, `abs()`, `hypot()`, `mod()`, `rem()` and `round()` reduced to a pixel offset plus at most one
// relative unit, numeric math expressions (`sin`, `sqrt`, `pow`, ...), angles and times, `light-dark()`, and colours: named,
// hex, `rgb()`, `hsl()`, `hwb()`, `lab()`, `lch()`, `oklab()`, `oklch()`, `color()` over the predefined RGB and XYZ
// spaces, relative colour syntax, `color-mix()` and `contrast-color()`; plus 2D transform lists reduced to one affine
// `[a, b, c, d, e, f]`, a transform origin and the percentage part of a translate.
//
// Text is read as ASCII for case and whitespace (CSS keywords are ASCII); a colour is a 32-bit ARGB. A parse that Vaper
// answers with null answers `false` here. Rounding is Dart's, a half going away from zero.
//
// Memory: the arena is retained; every string and list lives in it.

use e.data.list as list
use e.fmt.json as json
use e.math
use e.mem
use e.str

type LengthUnit = enum u8 { Px, Pt, Em, Rem, Ex, Percent, Vw, Vh, Vmin, Vmax }

type LengthOp = enum u8 { None, Min, Max, Clamp, Abs, Hypot, Mod, Rem, RoundNearest, RoundUp, RoundDown, RoundToZero }

// A length: a value in a unit plus a constant `px_offset` (what a `calc()` could fold), or a math function of terms.
type CssLength = struct { value: f64, unit: LengthUnit, px_offset: f64, op: LengthOp, terms: []const CssLength }

// The bases a relative unit resolves against; a base that is not present leaves its units indefinite.
type Bases = struct { has_em: bool, em: f64, has_rem: bool, rem: f64, has_percent: bool, percent: f64, has_viewport_width: bool, viewport_width: f64, has_viewport_height: bool, viewport_height: f64 }

fn no_bases() -> Bases {
    ret Bases { has_em: false, em: 0.0f64, has_rem: false, rem: 0.0f64, has_percent: false, percent: 0.0f64, has_viewport_width: false, viewport_width: 0.0f64, has_viewport_height: false, viewport_height: 0.0f64 }
}

fn pi() -> f64 { ret 3.141592653589793f64 }

fn e_const() -> f64 { ret 2.718281828459045f64 }

fn nan() -> f64 { ret mem.bitcast[f64](9221120237041090560u64) }

fn infinity() -> f64 { ret mem.bitcast[f64](9218868437227405312u64) }

fn is_nan(x: f64) -> bool { ret x != x }

fn is_infinite(x: f64) -> bool { ret x == infinity() || x == -infinity() }

// --- text helpers ------------------------------------------------------------------------------------------------------

fn is_space(c: u8) -> bool { ret c == 32u8 || (c >= 9u8 && c <= 13u8) }

fn trim_ws(s: str) -> str {
    var start = 0usize
    var end = s.len
    while start < end && is_space(s[start]) { start += 1usize }
    while end > start && is_space(s[end - 1usize]) { end -= 1usize }
    ret s[start..end]
}

fn lower(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var at = 0usize
    while at < s.len {
        var c = s[at]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        out[at] = c
        at += 1usize
    }
    ret out[0usize..s.len]
}

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { ret "" }
    ret out
}

fn index_of(s: str, needle: str) -> i64 {
    let (at, found) = str.find(s, needle)
    if !found { ret -1i64 }
    ret i64(at)
}

fn last_index_of_byte(s: str, byte: u8) -> i64 {
    var at = i64(s.len) - 1i64
    while at >= 0i64 {
        if s[usize(at)] == byte { ret at }
        at -= 1i64
    }
    ret -1i64
}

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn round_half_away(x: f64) -> f64 {
    if !(math.abs[f64](x) < 4503599627370496.0f64) { ret x }
    let t = math.trunc[f64](x)
    if math.abs[f64](x - t) >= 0.5f64 { ret t + math.copysign[f64](1.0f64, x) }
    ret t
}

// Dart's `double.round().clamp(0, 255)`.
fn clamp255(x: f64) -> i64 {
    if is_nan(x) { ret 0i64 }
    let r = round_half_away(x)
    if r < 0.0f64 { ret 0i64 }
    if r > 255.0f64 { ret 255i64 }
    ret i64(r)
}

fn clamp_f(x: f64, lo: f64, hi: f64) -> f64 {
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

// Dart's `double.tryParse`: surrounding whitespace, an optional sign, digits with an optional point (`5.`, `.5`,
// `1.e5`), an optional exponent, or `Infinity`.
fn try_parse(a: *mem.Arena, input: str) -> (f64, bool) {
    let s = trim_ws(input)
    if s.len == 0usize { ret (0.0f64, false) }
    var at = 0usize
    var negative = false
    if s[0] == 45u8 {
        negative = true
        at = 1usize
    } else if s[0] == 43u8 {
        at = 1usize
    }
    if str.eq(s[at..], "Infinity") {
        if negative { ret (-infinity(), true) }
        ret (infinity(), true)
    }
    let int_start = at
    while at < s.len && is_digit(s[at]) { at += 1usize }
    let int_digits = s[int_start..at]
    var frac_digits = ""
    var has_point = false
    if at < s.len && s[at] == 46u8 {
        has_point = true
        at += 1usize
        let frac_start = at
        while at < s.len && is_digit(s[at]) { at += 1usize }
        frac_digits = s[frac_start..at]
    }
    if int_digits.len == 0usize && frac_digits.len == 0usize { ret (0.0f64, false) }
    var exp_text = ""
    if at < s.len && (s[at] == 101u8 || s[at] == 69u8) {
        var j = at + 1usize
        var exp_negative = false
        if j < s.len && (s[j] == 43u8 || s[j] == 45u8) {
            exp_negative = s[j] == 45u8
            j += 1usize
        }
        let exp_start = j
        while j < s.len && is_digit(s[j]) { j += 1usize }
        if j == exp_start { ret (0.0f64, false) }
        if exp_negative { exp_text = cat(a, "e-", s[exp_start..j]) } else { exp_text = cat(a, "e", s[exp_start..j]) }
        at = j
    }
    if at != s.len { ret (0.0f64, false) }
    var text = ""
    if negative { text = "-" }
    if int_digits.len == 0usize { text = cat(a, text, "0") } else { text = cat(a, text, int_digits) }
    if frac_digits.len > 0usize { text = cat(a, cat(a, text, "."), frac_digits) }
    text = cat(a, text, exp_text)
    let (value, e) = str.parse_f64(text)
    if e != ok { ret (0.0f64, false) }
    ret (value, true)
}

// `double.tryParse(s) ?? fallback`.
fn parse_or(a: *mem.Arena, s: str, fallback: f64) -> f64 {
    let (v, good) = try_parse(a, s)
    if good { ret v }
    ret fallback
}

// A double printed as Dart prints it, for splicing into an expression: `255` as `255.0`.
fn dart_text(a: *mem.Arena, x: f64) -> str {
    if is_nan(x) { ret "NaN" }
    if x == infinity() { ret "Infinity" }
    if x == -infinity() { ret "-Infinity" }
    let (n, e) = json.number_from_f64(a, x)
    if e != ok { ret "0.0" }
    var t = n.lexeme
    if index_of(t, ".") < 0i64 && index_of(t, "e") < 0i64 { t = cat(a, t, ".0") }
    if str.eq(t, "-0") { t = "-0.0" }
    ret t
}

fn strings_list(a: *mem.Arena) -> list.List[str] {
    let (l, e) = list.init[str](a, 4usize)
    if e != ok { ret list.List[str] { items: zero, len: 0usize, arena: a } }
    ret l
}

fn push_str(l: *list.List[str], s: str) {
    let e = list.push[str](l, s)
}

// Split on top-level commas (depth counted over parentheses only), keeping empty pieces.
fn split_top_level_commas(a: *mem.Arena, s: str) -> []const str {
    var out = strings_list(a)
    var depth = 0i64
    var start = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 40u8 {
            depth += 1i64
        } else if c == 41u8 {
            if depth > 0i64 { depth -= 1i64 }
        } else if c == 44u8 && depth == 0i64 {
            push_str(&out, s[start..i])
            start = i + 1usize
        }
        i += 1usize
    }
    push_str(&out, s[start..])
    ret list.slice_const[str](&out)
}

// Split on top-level spaces, tabs and newlines, dropping empty pieces.
fn split_top_level_spaces(a: *mem.Arena, s: str) -> []const str {
    var out = strings_list(a)
    var depth = 0i64
    var start = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 40u8 {
            depth += 1i64
        } else if c == 41u8 {
            if depth > 0i64 { depth -= 1i64 }
        } else if depth == 0i64 && (c == 32u8 || c == 9u8 || c == 10u8) {
            if i > start { push_str(&out, s[start..i]) }
            start = i + 1usize
        }
        i += 1usize
    }
    if start < s.len { push_str(&out, s[start..]) }
    ret list.slice_const[str](&out)
}

// As above, each piece trimmed and empty ones dropped (`_splitTopLevelSpace`).
fn split_top_level_space(a: *mem.Arena, s: str) -> []const str {
    var out = strings_list(a)
    var depth = 0i64
    var start = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 40u8 {
            depth += 1i64
        } else if c == 41u8 {
            if depth > 0i64 { depth -= 1i64 }
        } else if depth == 0i64 && (c == 32u8 || c == 9u8 || c == 10u8) {
            if i > start {
                let piece = trim_ws(s[start..i])
                if piece.len > 0usize { push_str(&out, piece) }
            }
            start = i + 1usize
        }
        i += 1usize
    }
    if start < s.len {
        let piece = trim_ws(s[start..])
        if piece.len > 0usize { push_str(&out, piece) }
    }
    ret list.slice_const[str](&out)
}

// Split on runs of separator bytes and drop the empty pieces. Mode 0 is `[,/ ]`, mode 1 `[,/\s]`, mode 2 `[\s,]`.
fn split_on_mode(a: *mem.Arena, s: str, mode: u8) -> []const str {
    var out = strings_list(a)
    var start = 0usize
    var i = 0usize
    while i <= s.len {
        var sep = i == s.len
        if !sep {
            let c = s[i]
            if mode == 0u8 { sep = c == 44u8 || c == 47u8 || c == 32u8 }
            if mode == 1u8 { sep = c == 44u8 || c == 47u8 || is_space(c) }
            if mode == 2u8 { sep = c == 44u8 || is_space(c) }
        }
        if sep {
            if i > start { push_str(&out, s[start..i]) }
            start = i + 1usize
        }
        i += 1usize
    }
    ret list.slice_const[str](&out)
}

fn top_level_index_of(s: str, ch: u8) -> i64 {
    var depth = 0i64
    var i = 0usize
    while i < s.len {
        if s[i] == 40u8 {
            depth += 1i64
        } else if s[i] == 41u8 {
            if depth > 0i64 { depth -= 1i64 }
        } else if depth == 0i64 && s[i] == ch {
            ret i64(i)
        }
        i += 1usize
    }
    ret -1i64
}

// --- calc terms and numeric expressions ----------------------------------------------------------------------------------

type Term = struct { sign: f64, text: str }

fn split_calc_terms(a: *mem.Arena, expr: str) -> ([]const Term, bool) {
    let (made, e) = list.init[Term](a, 4usize)
    if e != ok { ret (zero, false) }
    var out = made
    var depth = 0i64
    var start = 0usize
    var sign = 1.0f64
    var i = 0usize
    while i < expr.len {
        let ch = expr[i]
        if ch == 40u8 {
            depth += 1i64
        } else if ch == 41u8 {
            depth -= 1i64
        } else if depth == 0i64 && (ch == 43u8 || ch == 45u8) && i > 0usize {
            let prev = trim_end_ws(expr[0usize..i])
            if prev.len > 0usize {
                let term = trim_ws(expr[start..i])
                if term.len > 0usize {
                    let pushed = list.push[Term](&out, Term { sign: sign, text: term })
                }
                if ch == 43u8 { sign = 1.0f64 } else { sign = -1.0f64 }
                start = i + 1usize
            }
        }
        i += 1usize
    }
    let last = trim_ws(expr[start..])
    if last.len > 0usize {
        let pushed = list.push[Term](&out, Term { sign: sign, text: last })
    }
    if out.len == 0usize { ret (zero, false) }
    ret (list.slice_const[Term](&out), true)
}

fn trim_end_ws(s: str) -> str {
    var end = s.len
    while end > 0usize && is_space(s[end - 1usize]) { end -= 1usize }
    ret s[0usize..end]
}

fn eval_number(a: *mem.Arena, expr: str) -> (f64, bool) {
    let (v, good) = num_add(a, trim_ws(expr))
    if !good || is_nan(v) || is_infinite(v) { ret (0.0f64, false) }
    ret (v, true)
}

fn num_add(a: *mem.Arena, s: str) -> (f64, bool) {
    let (terms, good) = split_calc_terms(a, s)
    if !good { ret (0.0f64, false) }
    var acc = 0.0f64
    var i = 0usize
    while i < terms.len {
        let (v, ok_term) = num_mul(a, trim_ws(terms[i].text))
        if !ok_term { ret (0.0f64, false) }
        acc = acc + terms[i].sign * v
        i += 1usize
    }
    ret (acc, true)
}

fn num_mul(a: *mem.Arena, s: str) -> (f64, bool) {
    var depth = 0i64
    var ops = list.List[usize] { items: zero, len: 0usize, arena: a }
    let (made, e) = list.init[usize](a, 4usize)
    if e != ok { ret (0.0f64, false) }
    ops = made
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 40u8 {
            depth += 1i64
        } else if c == 41u8 {
            depth -= 1i64
        } else if depth == 0i64 && (c == 42u8 || c == 47u8) {
            let pushed = list.push[usize](&ops, i)
        }
        i += 1usize
    }
    if ops.len == 0usize {
        let (r0, r1) = num_atom(a, trim_ws(s))
        ret (r0, r1)
    }
    let (first, first_ok) = num_atom(a, trim_ws(s[0usize..ops.items[0]]))
    if !first_ok { ret (0.0f64, false) }
    var acc = first
    var k = 0usize
    while k < ops.len {
        var end = s.len
        if k + 1usize < ops.len { end = ops.items[k + 1usize] }
        let (operand, operand_ok) = num_atom(a, trim_ws(s[ops.items[k] + 1usize..end]))
        if !operand_ok { ret (0.0f64, false) }
        if s[ops.items[k]] == 42u8 {
            acc = acc * operand
        } else {
            if operand == 0.0f64 { ret (0.0f64, false) }
            acc = acc / operand
        }
        k += 1usize
    }
    ret (acc, true)
}

fn num_atom(a: *mem.Arena, s: str) -> (f64, bool) {
    if s.len == 0usize { ret (0.0f64, false) }
    if s[0] == 45u8 {
        let (v, good) = num_atom(a, trim_ws(s[1usize..]))
        if !good { ret (0.0f64, false) }
        ret (-v, true)
    }
    if s[0] == 43u8 {
        let (r0, r1) = num_atom(a, trim_ws(s[1usize..]))
        ret (r0, r1)
    }
    if s[0] == 40u8 && s[s.len - 1usize] == 41u8 {
        let (r0, r1) = num_add(a, s[1usize..s.len - 1usize])
        ret (r0, r1)
    }
    if str.starts_with(s, "calc(") && s[s.len - 1usize] == 41u8 {
        let (r0, r1) = num_add(a, s[5usize..s.len - 1usize])
        ret (r0, r1)
    }
    let low = lower(a, s)
    if str.eq(low, "pi") { ret (pi(), true) }
    if str.eq(low, "e") { ret (e_const(), true) }
    let paren = index_of(s, "(")
    if paren > 0i64 && s[s.len - 1usize] == 41u8 {
        let name = lower(a, trim_ws(s[0usize..usize(paren)]))
        let args = split_top_level_commas(a, s[usize(paren) + 1usize..s.len - 1usize])
        let (r0, r1) = apply_num_fn(a, name, args)
        ret (r0, r1)
    }
    let (r0, r1) = angle_or_number(a, low)
    ret (r0, r1)
}

fn angle_or_number(a: *mem.Arena, s: str) -> (f64, bool) {
    if str.ends_with(s, "deg") {
        let (v, good) = try_parse(a, s[0usize..s.len - 3usize])
        if !good { ret (0.0f64, false) }
        ret (v * pi() / 180.0f64, true)
    }
    if str.ends_with(s, "grad") {
        let (v, good) = try_parse(a, s[0usize..s.len - 4usize])
        if !good { ret (0.0f64, false) }
        ret (v * pi() / 200.0f64, true)
    }
    if str.ends_with(s, "turn") {
        let (v, good) = try_parse(a, s[0usize..s.len - 4usize])
        if !good { ret (0.0f64, false) }
        ret (v * 2.0f64 * pi(), true)
    }
    if str.ends_with(s, "rad") {
        let (v, good) = try_parse(a, s[0usize..s.len - 3usize])
        if !good { ret (0.0f64, false) }
        ret (v, true)
    }
    let (r0, r1) = try_parse(a, s)
    ret (r0, r1)
}

fn arg_value(a: *mem.Arena, args: []const str, i: usize) -> (f64, bool) {
    if i >= args.len { ret (0.0f64, false) }
    let (r0, r1) = num_add(a, trim_ws(args[i]))
    ret (r0, r1)
}

fn apply_num_fn(a: *mem.Arena, name: str, args: []const str) -> (f64, bool) {
    if str.eq(name, "sin") || str.eq(name, "cos") || str.eq(name, "tan") || str.eq(name, "asin") || str.eq(name, "acos") || str.eq(name, "atan") || str.eq(name, "exp") || str.eq(name, "sign") || str.eq(name, "abs") {
        if args.len != 1usize { ret (0.0f64, false) }
        let (x, good) = arg_value(a, args, 0usize)
        if !good { ret (0.0f64, false) }
        if str.eq(name, "sin") { ret (math.sin[f64](x), true) }
        if str.eq(name, "cos") { ret (math.cos[f64](x), true) }
        if str.eq(name, "tan") { ret (math.tan[f64](x), true) }
        if str.eq(name, "asin") { ret (math.asin[f64](x), true) }
        if str.eq(name, "acos") { ret (math.acos[f64](x), true) }
        if str.eq(name, "atan") { ret (math.atan[f64](x), true) }
        if str.eq(name, "exp") { ret (math.exp[f64](x), true) }
        if str.eq(name, "sign") {
            if x > 0.0f64 { ret (1.0f64, true) }
            if x < 0.0f64 { ret (-1.0f64, true) }
            ret (0.0f64, true)
        }
        ret (math.abs[f64](x), true)
    }
    if str.eq(name, "sqrt") {
        if args.len != 1usize { ret (0.0f64, false) }
        let (x, good) = arg_value(a, args, 0usize)
        if !good || x < 0.0f64 { ret (0.0f64, false) }
        ret (math.sqrt[f64](x), true)
    }
    if str.eq(name, "atan2") {
        if args.len != 2usize { ret (0.0f64, false) }
        let (y, y_ok) = arg_value(a, args, 0usize)
        let (x, x_ok) = arg_value(a, args, 1usize)
        if !y_ok || !x_ok { ret (0.0f64, false) }
        ret (math.atan2[f64](y, x), true)
    }
    if str.eq(name, "pow") {
        if args.len != 2usize { ret (0.0f64, false) }
        let (b, b_ok) = arg_value(a, args, 0usize)
        let (ex, ex_ok) = arg_value(a, args, 1usize)
        if !b_ok || !ex_ok { ret (0.0f64, false) }
        ret (math.pow[f64](b, ex), true)
    }
    if str.eq(name, "log") {
        let (x, good) = arg_value(a, args, 0usize)
        if !good || x <= 0.0f64 { ret (0.0f64, false) }
        if args.len == 1usize { ret (math.log[f64](x), true) }
        if args.len == 2usize {
            let (base, base_ok) = arg_value(a, args, 1usize)
            if !base_ok || base <= 0.0f64 { ret (0.0f64, false) }
            ret (math.log[f64](x) / math.log[f64](base), true)
        }
        ret (0.0f64, false)
    }
    if str.eq(name, "hypot") {
        if args.len == 0usize { ret (0.0f64, false) }
        var sum = 0.0f64
        var i = 0usize
        while i < args.len {
            let (v, good) = num_add(a, trim_ws(args[i]))
            if !good { ret (0.0f64, false) }
            sum = sum + v * v
            i += 1usize
        }
        ret (math.sqrt[f64](sum), true)
    }
    if str.eq(name, "min") || str.eq(name, "max") {
        if args.len == 0usize { ret (0.0f64, false) }
        var acc = 0.0f64
        var i = 0usize
        while i < args.len {
            let (v, good) = num_add(a, trim_ws(args[i]))
            if !good { ret (0.0f64, false) }
            if i == 0usize {
                acc = v
            } else if str.eq(name, "min") {
                acc = dart_min(acc, v)
            } else {
                acc = dart_max(acc, v)
            }
            i += 1usize
        }
        ret (acc, true)
    }
    if str.eq(name, "clamp") {
        if args.len != 3usize { ret (0.0f64, false) }
        let (lo, lo_ok) = arg_value(a, args, 0usize)
        let (val, val_ok) = arg_value(a, args, 1usize)
        let (hi, hi_ok) = arg_value(a, args, 2usize)
        if !lo_ok || !val_ok || !hi_ok { ret (0.0f64, false) }
        ret (dart_max(lo, dart_min(val, hi)), true)
    }
    if str.eq(name, "mod") || str.eq(name, "rem") {
        if args.len != 2usize { ret (0.0f64, false) }
        let (x, x_ok) = arg_value(a, args, 0usize)
        let (y, y_ok) = arg_value(a, args, 1usize)
        if !x_ok || !y_ok || y == 0.0f64 { ret (0.0f64, false) }
        if str.eq(name, "mod") { ret (x - y * math.floor[f64](x / y), true) }
        ret (x - y * math.trunc[f64](x / y), true)
    }
    if str.eq(name, "round") {
        let (r0, r1) = num_round(a, args)
        ret (r0, r1)
    }
    ret (0.0f64, false)
}

fn dart_min(x: f64, y: f64) -> f64 {
    if x != x || y != y { ret nan() }
    if x < y { ret x }
    ret y
}

fn dart_max(x: f64, y: f64) -> f64 {
    if x != x || y != y { ret nan() }
    if x > y { ret x }
    ret y
}

fn num_round(a: *mem.Arena, args: []const str) -> (f64, bool) {
    if args.len == 0usize { ret (0.0f64, false) }
    var strat = "nearest"
    var start = 0usize
    let head = lower(a, trim_ws(args[0]))
    if str.eq(head, "nearest") || str.eq(head, "up") || str.eq(head, "down") || str.eq(head, "to-zero") {
        strat = head
        start = 1usize
    }
    if args.len - start != 2usize { ret (0.0f64, false) }
    let (x, x_ok) = num_add(a, trim_ws(args[start]))
    let (y, y_ok) = num_add(a, trim_ws(args[start + 1usize]))
    if !x_ok || !y_ok || y == 0.0f64 { ret (0.0f64, false) }
    let q = x / y
    var r = round_half_away(q)
    if str.eq(strat, "up") { r = math.ceil[f64](q) }
    if str.eq(strat, "down") { r = math.floor[f64](q) }
    if str.eq(strat, "to-zero") { r = math.trunc[f64](q) }
    ret (r * y, true)
}

// A number or a numeric math expression.
fn parse_css_number(a: *mem.Arena, raw: str) -> (f64, bool) {
    let s = trim_ws(raw)
    if s.len == 0usize { ret (0.0f64, false) }
    let (v, good) = try_parse(a, s)
    if good { ret (v, true) }
    let (r0, r1) = eval_number(a, s)
    ret (r0, r1)
}

// The inner text of `light-dark(...)` for the chosen scheme, absent for anything else.
fn pick_light_dark(a: *mem.Arena, raw: str, dark: bool) -> (str, bool) {
    let s = trim_ws(raw)
    if !str.starts_with(lower(a, s), "light-dark(") || s[s.len - 1usize] != 41u8 { ret ("", false) }
    let inner = s[11usize..s.len - 1usize]
    let parts = split_top_level_commas(a, inner)
    var kept = strings_list(a)
    var i = 0usize
    while i < parts.len {
        let p = trim_ws(parts[i])
        if p.len > 0usize { push_str(&kept, p) }
        i += 1usize
    }
    if kept.len != 2usize { ret ("", false) }
    if dark { ret (kept.items[1], true) }
    ret (kept.items[0], true)
}

// An angle in radians (`calc()`, turn, grad, deg, rad; a bare number is degrees).
fn parse_css_angle_radians(a: *mem.Arena, raw: str) -> (f64, bool) {
    let s = lower(a, trim_ws(raw))
    if s.len == 0usize { ret (0.0f64, false) }
    if str.starts_with(s, "calc(") && s[s.len - 1usize] == 41u8 {
        let (r0, r1) = eval_number(a, s[5usize..s.len - 1usize])
        ret (r0, r1)
    }
    if str.ends_with(s, "turn") {
        let (v, good) = try_parse(a, s[0usize..s.len - 4usize])
        if !good { ret (0.0f64, false) }
        ret (v * 2.0f64 * pi(), true)
    }
    if str.ends_with(s, "grad") {
        let (v, good) = try_parse(a, s[0usize..s.len - 4usize])
        if !good { ret (0.0f64, false) }
        ret (v * pi() / 200.0f64, true)
    }
    if str.ends_with(s, "deg") {
        let (v, good) = try_parse(a, s[0usize..s.len - 3usize])
        if !good { ret (0.0f64, false) }
        ret (v * pi() / 180.0f64, true)
    }
    if str.ends_with(s, "rad") {
        let (v, good) = try_parse(a, s[0usize..s.len - 3usize])
        if !good { ret (0.0f64, false) }
        ret (v, true)
    }
    let (n, good) = try_parse(a, s)
    if !good { ret (0.0f64, false) }
    ret (n * pi() / 180.0f64, true)
}

// --- times ---------------------------------------------------------------------------------------------------------------

fn parse_css_time_seconds(a: *mem.Arena, raw: str) -> (f64, bool) {
    let s = lower(a, trim_ws(raw))
    if s.len == 0usize { ret (0.0f64, false) }
    let (r0, r1) = time_add(a, s)
    ret (r0, r1)
}

fn time_add(a: *mem.Arena, s: str) -> (f64, bool) {
    let (terms, good) = split_calc_terms(a, s)
    if !good { ret (0.0f64, false) }
    var acc = 0.0f64
    var i = 0usize
    while i < terms.len {
        let (v, ok_term) = time_mul(a, trim_ws(terms[i].text))
        if !ok_term { ret (0.0f64, false) }
        acc = acc + terms[i].sign * v
        i += 1usize
    }
    ret (acc, true)
}

fn time_mul(a: *mem.Arena, s: str) -> (f64, bool) {
    var depth = 0i64
    let (made, e) = list.init[usize](a, 4usize)
    if e != ok { ret (0.0f64, false) }
    var ops = made
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 40u8 {
            depth += 1i64
        } else if c == 41u8 {
            depth -= 1i64
        } else if depth == 0i64 && (c == 42u8 || c == 47u8) {
            let pushed = list.push[usize](&ops, i)
        }
        i += 1usize
    }
    if ops.len == 0usize {
        let (r0, r1) = time_atom(a, trim_ws(s))
        ret (r0, r1)
    }
    var have_time = false
    var time_val = 0.0f64
    var scalar = 1.0f64
    var k = 0usize
    while k <= ops.len {
        var op = 42u8
        var tok = ""
        if k == 0usize {
            tok = trim_ws(s[0usize..ops.items[0]])
        } else {
            op = s[ops.items[k - 1usize]]
            var end = s.len
            if k < ops.len { end = ops.items[k] }
            tok = trim_ws(s[ops.items[k - 1usize] + 1usize..end])
        }
        let (t, is_time) = time_atom(a, tok)
        if is_time {
            if have_time || op == 47u8 { ret (0.0f64, false) }
            have_time = true
            time_val = t
        } else {
            let (n, n_ok) = eval_number(a, tok)
            if !n_ok { ret (0.0f64, false) }
            if op == 47u8 {
                if n == 0.0f64 { ret (0.0f64, false) }
                scalar = scalar / n
            } else {
                scalar = scalar * n
            }
        }
        k += 1usize
    }
    if !have_time { ret (0.0f64, false) }
    ret (time_val * scalar, true)
}

fn time_atom(a: *mem.Arena, s: str) -> (f64, bool) {
    if s.len == 0usize { ret (0.0f64, false) }
    if s[0] == 40u8 && s[s.len - 1usize] == 41u8 {
        let (r0, r1) = time_add(a, s[1usize..s.len - 1usize])
        ret (r0, r1)
    }
    if str.starts_with(s, "calc(") && s[s.len - 1usize] == 41u8 {
        let (r0, r1) = time_add(a, s[5usize..s.len - 1usize])
        ret (r0, r1)
    }
    let paren = index_of(s, "(")
    if paren > 0i64 && s[s.len - 1usize] == 41u8 {
        let name = s[0usize..usize(paren)]
        let args = split_top_level_commas(a, s[usize(paren) + 1usize..s.len - 1usize])
        let (made, e) = list.init[f64](a, 4usize)
        if e != ok { ret (0.0f64, false) }
        var vals = made
        var i = 0usize
        while i < args.len {
            let (v, good) = time_add(a, trim_ws(args[i]))
            if !good { ret (0.0f64, false) }
            let pushed = list.push[f64](&vals, v)
            i += 1usize
        }
        if vals.len == 0usize { ret (0.0f64, false) }
        if str.eq(name, "min") || str.eq(name, "max") {
            var acc = vals.items[0]
            var k = 1usize
            while k < vals.len {
                if str.eq(name, "min") { acc = dart_min(acc, vals.items[k]) } else { acc = dart_max(acc, vals.items[k]) }
                k += 1usize
            }
            ret (acc, true)
        }
        if str.eq(name, "clamp") {
            if vals.len != 3usize { ret (0.0f64, false) }
            ret (dart_max(vals.items[0], dart_min(vals.items[1], vals.items[2])), true)
        }
        ret (0.0f64, false)
    }
    if str.ends_with(s, "ms") {
        let (v, good) = try_parse(a, s[0usize..s.len - 2usize])
        if !good { ret (0.0f64, false) }
        ret (v / 1000.0f64, true)
    }
    if str.ends_with(s, "s") {
        let (v, good) = try_parse(a, s[0usize..s.len - 1usize])
        if !good { ret (0.0f64, false) }
        ret (v, true)
    }
    if str.eq(s, "0") { ret (0.0f64, true) }
    ret (0.0f64, false)
}

// --- lengths -----------------------------------------------------------------------------------------------------------

fn plain_length(value: f64, unit: LengthUnit) -> CssLength {
    ret CssLength { value: value, unit: unit, px_offset: 0.0f64, op: .None, terms: zero }
}

fn function_length(op: LengthOp, terms: []const CssLength) -> CssLength {
    ret CssLength { value: 0.0f64, unit: .Px, px_offset: 0.0f64, op: op, terms: terms }
}

fn zero_length() -> CssLength { ret plain_length(0.0f64, .Px) }

// A length in pixels against the given bases; absent when a needed base is missing or a function is indefinite.
fn to_px(l: CssLength, b: Bases) -> (f64, bool) {
    if l.op != .None {
        var r: [16]f64 = zero
        var n = 0usize
        var i = 0usize
        while i < l.terms.len && n < 16usize {
            let (px, good) = to_px(l.terms[i], b)
            if !good { ret (0.0f64, false) }
            r[n] = px
            n += 1usize
            i += 1usize
        }
        if n == 0usize { ret (0.0f64, false) }
        switch l.op {
        case .Min:
            var acc = r[0]
            var k = 1usize
            while k < n {
                acc = dart_min(acc, r[k])
                k += 1usize
            }
            ret (acc, true)
        case .Max:
            var acc = r[0]
            var k = 1usize
            while k < n {
                acc = dart_max(acc, r[k])
                k += 1usize
            }
            ret (acc, true)
        case .Clamp:
            if n < 3usize { ret (0.0f64, false) }
            ret (dart_max(r[0], dart_min(r[1], r[2])), true)
        case .Abs:
            ret (math.abs[f64](r[0]), true)
        case .Hypot:
            var sum = 0.0f64
            var k = 0usize
            while k < n {
                sum = sum + r[k] * r[k]
                k += 1usize
            }
            ret (math.sqrt[f64](sum), true)
        case .Mod:
            if n < 2usize || r[1] == 0.0f64 { ret (0.0f64, false) }
            ret (r[0] - r[1] * math.floor[f64](r[0] / r[1]), true)
        case .Rem:
            if n < 2usize || r[1] == 0.0f64 { ret (0.0f64, false) }
            ret (r[0] - r[1] * math.trunc[f64](r[0] / r[1]), true)
        case .RoundNearest:
            if n < 2usize || r[1] == 0.0f64 { ret (0.0f64, false) }
            ret (round_half_away(r[0] / r[1]) * r[1], true)
        case .RoundUp:
            if n < 2usize || r[1] == 0.0f64 { ret (0.0f64, false) }
            ret (math.ceil[f64](r[0] / r[1]) * r[1], true)
        case .RoundDown:
            if n < 2usize || r[1] == 0.0f64 { ret (0.0f64, false) }
            ret (math.floor[f64](r[0] / r[1]) * r[1], true)
        case .RoundToZero:
            if n < 2usize || r[1] == 0.0f64 { ret (0.0f64, false) }
            ret (math.trunc[f64](r[0] / r[1]) * r[1], true)
        default:
            ret (0.0f64, false)
        }
    }
    var base = 0.0f64
    var have = true
    switch l.unit {
    case .Px:
        base = l.value
    case .Pt:
        base = l.value * 96.0f64 / 72.0f64
    case .Em:
        if b.has_em { base = l.value * b.em } else { have = false }
    case .Rem:
        if b.has_rem { base = l.value * b.rem } else { have = false }
    case .Ex:
        if b.has_em { base = l.value * b.em * 0.5f64 } else { have = false }
    case .Percent:
        if b.has_percent { base = l.value / 100.0f64 * b.percent } else { have = false }
    case .Vw:
        if b.has_viewport_width { base = l.value / 100.0f64 * b.viewport_width } else { have = false }
    case .Vh:
        if b.has_viewport_height { base = l.value / 100.0f64 * b.viewport_height } else { have = false }
    case .Vmin:
        if b.has_viewport_width && b.has_viewport_height { base = l.value / 100.0f64 * dart_min(b.viewport_width, b.viewport_height) } else { have = false }
    case .Vmax:
        if b.has_viewport_width && b.has_viewport_height { base = l.value / 100.0f64 * dart_max(b.viewport_width, b.viewport_height) } else { have = false }
    }
    if !have { ret (0.0f64, false) }
    ret (base + l.px_offset, true)
}

// The `[+-]?\d*\.?\d+` number and its unit, whole-string: absent when the text is not exactly that.
fn match_length(s: str) -> (str, str, bool) {
    var at = 0usize
    if at < s.len && (s[at] == 43u8 || s[at] == 45u8) { at += 1usize }
    let digits_start = at
    while at < s.len && is_digit(s[at]) { at += 1usize }
    var end_number = at
    if at < s.len && s[at] == 46u8 {
        var j = at + 1usize
        let frac_start = j
        while j < s.len && is_digit(s[j]) { j += 1usize }
        if j == frac_start { ret ("", "", false) }
        end_number = j
        at = j
    } else if at == digits_start {
        ret ("", "", false)
    }
    let unit = s[end_number..]
    if unit.len == 0usize { ret (s[0usize..end_number], "", true) }
    if length_unit_known(unit) { ret (s[0usize..end_number], unit, true) }
    ret ("", "", false)
}

fn length_unit_known(u: str) -> bool {
    ret str.eq(u, "px") || str.eq(u, "pt") || str.eq(u, "pc") || str.eq(u, "em") || str.eq(u, "rem") || str.eq(u, "ex") || str.eq(u, "ch") || str.eq(u, "vw") || str.eq(u, "vh") || str.eq(u, "vmin") || str.eq(u, "vmax") || str.eq(u, "dvh") || str.eq(u, "svh") || str.eq(u, "lvh") || str.eq(u, "dvw") || str.eq(u, "svw") || str.eq(u, "lvw") || str.eq(u, "vi") || str.eq(u, "vb") || str.eq(u, "cm") || str.eq(u, "mm") || str.eq(u, "in") || str.eq(u, "q") || str.eq(u, "%")
}

fn unit_length(value: f64, unit: str) -> (CssLength, bool) {
    if str.eq(unit, "") {
        if value == 0.0f64 { ret (zero_length(), true) }
        ret (zero_length(), false)
    }
    if str.eq(unit, "px") { ret (plain_length(value, .Px), true) }
    if str.eq(unit, "pt") { ret (plain_length(value, .Pt), true) }
    if str.eq(unit, "em") { ret (plain_length(value, .Em), true) }
    if str.eq(unit, "rem") { ret (plain_length(value, .Rem), true) }
    if str.eq(unit, "ex") { ret (plain_length(value, .Ex), true) }
    if str.eq(unit, "ch") { ret (plain_length(value * 0.5f64, .Em), true) }
    if str.eq(unit, "in") { ret (plain_length(value * 96.0f64, .Px), true) }
    if str.eq(unit, "cm") { ret (plain_length(value * 96.0f64 / 2.54f64, .Px), true) }
    if str.eq(unit, "mm") { ret (plain_length(value * 96.0f64 / 25.4f64, .Px), true) }
    if str.eq(unit, "q") { ret (plain_length(value * 96.0f64 / 25.4f64 / 4.0f64, .Px), true) }
    if str.eq(unit, "pc") { ret (plain_length(value * 16.0f64, .Px), true) }
    if str.eq(unit, "%") { ret (plain_length(value, .Percent), true) }
    if str.eq(unit, "vw") || str.eq(unit, "dvw") || str.eq(unit, "svw") || str.eq(unit, "lvw") || str.eq(unit, "vi") { ret (plain_length(value, .Vw), true) }
    if str.eq(unit, "vh") || str.eq(unit, "dvh") || str.eq(unit, "svh") || str.eq(unit, "lvh") || str.eq(unit, "vb") { ret (plain_length(value, .Vh), true) }
    if str.eq(unit, "vmin") { ret (plain_length(value, .Vmin), true) }
    if str.eq(unit, "vmax") { ret (plain_length(value, .Vmax), true) }
    ret (zero_length(), false)
}

fn parse_plain_length(a: *mem.Arena, raw: str) -> (CssLength, bool) {
    let (num, unit, matched) = match_length(lower(a, trim_ws(raw)))
    if !matched { ret (zero_length(), false) }
    let (value, good) = try_parse(a, num)
    if !good { ret (zero_length(), false) }
    let (r0, r1) = unit_length(value, unit)
    ret (r0, r1)
}

fn parse_length_fn(a: *mem.Arena, args: str, op: LengthOp) -> (CssLength, bool) {
    let parts = split_top_level_commas(a, args)
    if parts.len == 0usize { ret (zero_length(), false) }
    var arity = -1i64
    if op == .Clamp { arity = 3i64 }
    if op == .Abs { arity = 1i64 }
    if op == .Mod || op == .Rem { arity = 2i64 }
    if arity != -1i64 && i64(parts.len) != arity { ret (zero_length(), false) }
    let (made, e) = list.init[CssLength](a, 4usize)
    if e != ok { ret (zero_length(), false) }
    var terms = made
    var i = 0usize
    while i < parts.len {
        let (len, good) = parse_length(a, trim_ws(parts[i]), no_bases())
        if !good { ret (zero_length(), false) }
        let pushed = list.push[CssLength](&terms, len)
        i += 1usize
    }
    ret (function_length(op, list.slice_const[CssLength](&terms)), true)
}

fn parse_round_fn(a: *mem.Arena, args: str) -> (CssLength, bool) {
    let parts = split_top_level_commas(a, args)
    if parts.len == 0usize { ret (zero_length(), false) }
    var op: LengthOp = .RoundNearest
    var start = 0usize
    let head = lower(a, trim_ws(parts[0]))
    if str.eq(head, "nearest") {
        op = .RoundNearest
        start = 1usize
    } else if str.eq(head, "up") {
        op = .RoundUp
        start = 1usize
    } else if str.eq(head, "down") {
        op = .RoundDown
        start = 1usize
    } else if str.eq(head, "to-zero") {
        op = .RoundToZero
        start = 1usize
    }
    if parts.len - start != 2usize { ret (zero_length(), false) }
    let (made, e) = list.init[CssLength](a, 2usize)
    if e != ok { ret (zero_length(), false) }
    var terms = made
    var i = start
    while i < parts.len {
        let (len, good) = parse_length(a, trim_ws(parts[i]), no_bases())
        if !good { ret (zero_length(), false) }
        let pushed = list.push[CssLength](&terms, len)
        i += 1usize
    }
    ret (function_length(op, list.slice_const[CssLength](&terms)), true)
}

// The first `separator` at index 1 or later with a non-empty remainder: `(left, right)` trimmed, as the regex
// `^(.+?)\s*SEP\s*(.+)$` gives; absent when the token holds a line break or has no such separator.
fn split_operator(s: str, sep: u8) -> (str, str, bool) {
    var i = 0usize
    while i < s.len {
        if s[i] == 10u8 || s[i] == 13u8 { ret ("", "", false) }
        i += 1usize
    }
    var p = 1usize
    while p < s.len {
        if s[p] == sep && p + 1usize < s.len {
            var rest = p + 1usize
            while rest < s.len && is_space(s[rest]) { rest += 1usize }
            if rest < s.len {
                ret (trim_ws(s[0usize..p]), trim_ws(s[rest..]), true)
            }
            // all whitespace after the operator: the final character stands for `(.+)`
            ret (trim_ws(s[0usize..p]), trim_ws(s[s.len - 1usize..]), true)
        }
        p += 1usize
    }
    ret ("", "", false)
}

type Product = struct { coeff: f64, has_length: bool, length: CssLength }

fn parse_calc_product(a: *mem.Arena, token: str) -> (Product, bool) {
    let none = Product { coeff: 0.0f64, has_length: false, length: zero_length() }
    let (ml, mr, mul) = split_operator(token, 42u8)
    if mul {
        let (a_num, a_ok) = scalar_or_eval(a, ml)
        let (b_num, b_ok) = scalar_or_eval(a, mr)
        if a_ok {
            let (b_len, b_len_ok) = parse_length(a, mr, no_bases())
            if b_len_ok { ret (Product { coeff: a_num, has_length: true, length: b_len }, true) }
            if b_ok { ret (Product { coeff: a_num * b_num, has_length: false, length: zero_length() }, true) }
        } else if b_ok {
            let (a_len, a_len_ok) = parse_length(a, ml, no_bases())
            if a_len_ok { ret (Product { coeff: b_num, has_length: true, length: a_len }, true) }
        }
        ret (none, false)
    }
    let (dl, dr, div) = split_operator(token, 47u8)
    if div {
        let (divisor, d_ok) = scalar_or_eval(a, dr)
        if !d_ok || divisor == 0.0f64 { ret (none, false) }
        let (a_len, a_len_ok) = parse_length(a, dl, no_bases())
        if a_len_ok { ret (Product { coeff: 1.0f64 / divisor, has_length: true, length: a_len }, true) }
        ret (none, false)
    }
    let (n, n_ok) = try_parse(a, token)
    if n_ok { ret (Product { coeff: n, has_length: false, length: zero_length() }, true) }
    let (plain, plain_ok) = parse_plain_length(a, token)
    if plain_ok { ret (Product { coeff: 1.0f64, has_length: true, length: plain }, true) }
    let (fn_len, fn_ok) = parse_length(a, token, no_bases())
    if fn_ok { ret (Product { coeff: 1.0f64, has_length: true, length: fn_len }, true) }
    let (ev, ev_ok) = eval_number(a, token)
    if ev_ok { ret (Product { coeff: ev, has_length: false, length: zero_length() }, true) }
    ret (none, false)
}

fn scalar_or_eval(a: *mem.Arena, s: str) -> (f64, bool) {
    let (v, good) = try_parse(a, s)
    if good { ret (v, true) }
    let (r0, r1) = eval_number(a, s)
    ret (r0, r1)
}

fn parse_calc(a: *mem.Arena, expr: str, b: Bases) -> (CssLength, bool) {
    let (terms, good) = split_calc_terms(a, expr)
    if !good { ret (zero_length(), false) }
    var px_acc = 0.0f64
    var rel_value = 0.0f64
    var have_rel = false
    var rel_unit: LengthUnit = .Px
    var i = 0usize
    while i < terms.len {
        let (prod, prod_ok) = parse_calc_product(a, trim_ws(terms[i].text))
        if !prod_ok { ret (zero_length(), false) }
        let signed = terms[i].sign * prod.coeff
        if prod.has_length && prod.length.op != .None {
            let (px, px_ok) = to_px(prod.length, Bases { has_em: b.has_em, em: b.em, has_rem: b.has_rem, rem: b.rem, has_percent: false, percent: 0.0f64, has_viewport_width: b.has_viewport_width, viewport_width: b.viewport_width, has_viewport_height: b.has_viewport_height, viewport_height: b.viewport_height })
            if !px_ok { ret (zero_length(), false) }
            px_acc = px_acc + signed * px
        } else if !prod.has_length {
            px_acc = px_acc + signed
        } else if prod.length.unit == .Px {
            px_acc = px_acc + signed * prod.length.value + prod.length.px_offset
        } else if prod.length.unit == .Pt {
            px_acc = px_acc + signed * prod.length.value * (96.0f64 / 72.0f64)
        } else {
            var px = 0.0f64
            var px_ok = false
            if prod.length.unit != .Percent {
                let (v, v_ok) = to_px(prod.length, Bases { has_em: b.has_em, em: b.em, has_rem: b.has_rem, rem: b.rem, has_percent: false, percent: 0.0f64, has_viewport_width: b.has_viewport_width, viewport_width: b.viewport_width, has_viewport_height: b.has_viewport_height, viewport_height: b.viewport_height })
                px = v
                px_ok = v_ok
            }
            if px_ok {
                px_acc = px_acc + signed * px
            } else {
                if have_rel && rel_unit != prod.length.unit { ret (zero_length(), false) }
                rel_value = rel_value + signed * prod.length.value
                have_rel = true
                rel_unit = prod.length.unit
                px_acc = px_acc + signed * prod.length.px_offset
            }
        }
        i += 1usize
    }
    if !have_rel { ret (plain_length(px_acc, .Px), true) }
    ret (CssLength { value: rel_value, unit: rel_unit, px_offset: px_acc, op: .None, terms: zero }, true)
}

// A CSS length: a number with a unit, `calc()`, or one of the comparison and stepped functions. `bases` let a `calc()`
// fold the units it can (em, rem, viewport) so only a percentage stays relative.
fn parse_length(a: *mem.Arena, raw: str, bases: Bases) -> (CssLength, bool) {
    let s = lower(a, trim_ws(raw))
    if s.len == 0usize { ret (zero_length(), false) }
    let closes = s[s.len - 1usize] == 41u8
    if str.starts_with(s, "calc(") && closes {
        let (r0, r1) = parse_calc(a, trim_ws(s[5usize..s.len - 1usize]), bases)
        ret (r0, r1)
    }
    if str.starts_with(s, "min(") && closes {
        let (r0, r1) = parse_length_fn(a, s[4usize..s.len - 1usize], .Min)
        ret (r0, r1)
    }
    if str.starts_with(s, "max(") && closes {
        let (r0, r1) = parse_length_fn(a, s[4usize..s.len - 1usize], .Max)
        ret (r0, r1)
    }
    if str.starts_with(s, "clamp(") && closes {
        let (r0, r1) = parse_length_fn(a, s[6usize..s.len - 1usize], .Clamp)
        ret (r0, r1)
    }
    if str.starts_with(s, "abs(") && closes {
        let (r0, r1) = parse_length_fn(a, s[4usize..s.len - 1usize], .Abs)
        ret (r0, r1)
    }
    if str.starts_with(s, "hypot(") && closes {
        let (r0, r1) = parse_length_fn(a, s[6usize..s.len - 1usize], .Hypot)
        ret (r0, r1)
    }
    if str.starts_with(s, "mod(") && closes {
        let (r0, r1) = parse_length_fn(a, s[4usize..s.len - 1usize], .Mod)
        ret (r0, r1)
    }
    if str.starts_with(s, "rem(") && closes {
        let (r0, r1) = parse_length_fn(a, s[4usize..s.len - 1usize], .Rem)
        ret (r0, r1)
    }
    if str.starts_with(s, "round(") && closes {
        let (r0, r1) = parse_round_fn(a, s[6usize..s.len - 1usize])
        ret (r0, r1)
    }
    let (num, unit, matched) = match_length(s)
    if !matched { ret (zero_length(), false) }
    let (value, good) = try_parse(a, num)
    if !good { ret (zero_length(), false) }
    let (r0, r1) = unit_length(value, unit)
    ret (r0, r1)
}

// --- colours -----------------------------------------------------------------------------------------------------------

fn argb(a: i64, r: i64, g: i64, b: i64) -> u32 {
    ret (u32(a) << 24u32) | (u32(r) << 16u32) | (u32(g) << 8u32) | u32(b)
}

fn euclid_mod(x: f64, m: f64) -> f64 {
    var r = x - m * math.trunc[f64](x / m)
    if r < 0.0f64 { r = r + m }
    ret r
}

fn parse_alpha(a: *mem.Arena, p: str) -> f64 {
    if str.ends_with(p, "%") { ret clamp_f(parse_or(a, p[0usize..p.len - 1usize], 100.0f64) / 100.0f64, 0.0f64, 1.0f64) }
    ret clamp_f(parse_or(a, p, 1.0f64), 0.0f64, 1.0f64)
}

fn parse_hue(a: *mem.Arena, p: str) -> f64 {
    if str.ends_with(p, "grad") { ret parse_or(a, p[0usize..p.len - 4usize], 0.0f64) * 0.9f64 }
    if str.ends_with(p, "turn") { ret parse_or(a, p[0usize..p.len - 4usize], 0.0f64) * 360.0f64 }
    if str.ends_with(p, "rad") { ret parse_or(a, p[0usize..p.len - 3usize], 0.0f64) * 180.0f64 / 3.141592653589793f64 }
    if str.ends_with(p, "deg") { ret parse_or(a, p[0usize..p.len - 3usize], 0.0f64) }
    ret parse_or(a, p, 0.0f64)
}

fn hex_digit_value(c: u8) -> i64 {
    if c >= 48u8 && c <= 57u8 { ret i64(c - 48u8) }
    if c >= 97u8 && c <= 102u8 { ret i64(c - 97u8) + 10i64 }
    if c >= 65u8 && c <= 70u8 { ret i64(c - 65u8) + 10i64 }
    ret -1i64
}

fn parse_hex(a: *mem.Arena, input: str) -> (u32, bool) {
    var hex = input
    if hex.len == 3usize || hex.len == 4usize {
        let (out, e) = mem.alloc[u8](a, hex.len * 2usize)
        if e != ok { ret (0u32, false) }
        var i = 0usize
        while i < hex.len {
            out[i * 2usize] = hex[i]
            out[i * 2usize + 1usize] = hex[i]
            i += 1usize
        }
        hex = out[0usize..hex.len * 2usize]
    }
    if hex.len != 6usize && hex.len != 8usize { ret (0u32, false) }
    var value = 0i64
    var i = 0usize
    while i < hex.len {
        let d = hex_digit_value(hex[i])
        if d < 0i64 { ret (0u32, false) }
        value = value * 16i64 + d
        i += 1usize
    }
    let v = u32(value)
    if hex.len == 8usize { ret (argb(i64(v & 255u32), i64((v >> 24u32) & 255u32), i64((v >> 16u32) & 255u32), i64((v >> 8u32) & 255u32)), true) }
    ret (argb(255i64, i64((v >> 16u32) & 255u32), i64((v >> 8u32) & 255u32), i64(v & 255u32)), true)
}

fn rgb_channel(a: *mem.Arena, p: str) -> i64 {
    if str.ends_with(p, "%") { ret clamp255(parse_or(a, p[0usize..p.len - 1usize], 0.0f64) / 100.0f64 * 255.0f64) }
    ret clamp255(parse_or(a, p, 0.0f64))
}

fn parse_rgb(a: *mem.Arena, s: str) -> (u32, bool) {
    let open = index_of(s, "(")
    let close = index_of(s, ")")
    if open == -1i64 || close == -1i64 || close < open { ret (0u32, false) }
    let parts = split_on_mode(a, s[usize(open) + 1usize..usize(close)], 0u8)
    if parts.len < 3usize { ret (0u32, false) }
    let r = rgb_channel(a, parts[0])
    let g = rgb_channel(a, parts[1])
    let b = rgb_channel(a, parts[2])
    var al = 255i64
    if parts.len >= 4usize { al = clamp255(parse_alpha(a, parts[3]) * 255.0f64) }
    ret (argb(al, r, g, b), true)
}

fn rgb_to_hsl(r: f64, g: f64, b: f64) -> (f64, f64, f64) {
    let mx = dart_max(r, dart_max(g, b))
    let mn = dart_min(r, dart_min(g, b))
    let l = (mx + mn) / 2.0f64
    if mx == mn { ret (0.0f64, 0.0f64, l) }
    let d = mx - mn
    var s = d / (mx + mn)
    if l > 0.5f64 { s = d / (2.0f64 - mx - mn) }
    var h = 0.0f64
    if mx == r {
        h = (g - b) / d
        if g < b { h = h + 6.0f64 }
    } else if mx == g {
        h = (b - r) / d + 2.0f64
    } else {
        h = (r - g) / d + 4.0f64
    }
    ret (h * 60.0f64, s, l)
}

fn hue_to_rgb(hue: f64) -> (f64, f64, f64) {
    var h = euclid_mod(hue, 360.0f64)
    if h < 0.0f64 { h = h + 360.0f64 }
    let x = 1.0f64 - math.abs[f64](euclid_mod(h / 60.0f64, 2.0f64) - 1.0f64)
    if h < 60.0f64 { ret (1.0f64, x, 0.0f64) }
    if h < 120.0f64 { ret (x, 1.0f64, 0.0f64) }
    if h < 180.0f64 { ret (0.0f64, 1.0f64, x) }
    if h < 240.0f64 { ret (0.0f64, x, 1.0f64) }
    if h < 300.0f64 { ret (x, 0.0f64, 1.0f64) }
    ret (1.0f64, 0.0f64, x)
}

fn hsl_to_argb(hue: f64, s: f64, l: f64, al: f64) -> u32 {
    var h = euclid_mod(hue, 360.0f64)
    if h < 0.0f64 { h = h + 360.0f64 }
    let c = (1.0f64 - math.abs[f64](2.0f64 * l - 1.0f64)) * s
    let x = c * (1.0f64 - math.abs[f64](euclid_mod(h / 60.0f64, 2.0f64) - 1.0f64))
    let m = l - c / 2.0f64
    var r = 0.0f64
    var g = 0.0f64
    var b = 0.0f64
    if h < 60.0f64 {
        r = c
        g = x
    } else if h < 120.0f64 {
        r = x
        g = c
    } else if h < 180.0f64 {
        g = c
        b = x
    } else if h < 240.0f64 {
        g = x
        b = c
    } else if h < 300.0f64 {
        r = x
        b = c
    } else {
        r = c
        b = x
    }
    ret argb(clamp255(al * 255.0f64), clamp255((r + m) * 255.0f64), clamp255((g + m) * 255.0f64), clamp255((b + m) * 255.0f64))
}

fn strip_percent(a: *mem.Arena, s: str) -> str {
    let (out, e) = str.replace(a, s, "%", "")
    if e != ok { ret s }
    ret out
}

fn parse_hsl(a: *mem.Arena, s: str) -> (u32, bool) {
    let open = index_of(s, "(")
    let close = index_of(s, ")")
    if open == -1i64 || close == -1i64 || close < open { ret (0u32, false) }
    let parts = split_on_mode(a, s[usize(open) + 1usize..usize(close)], 1u8)
    if parts.len < 3usize { ret (0u32, false) }
    let h = parse_hue(a, parts[0])
    let sp = parse_or(a, strip_percent(a, parts[1]), 0.0f64) / 100.0f64
    let l = parse_or(a, strip_percent(a, parts[2]), 0.0f64) / 100.0f64
    var al = 1.0f64
    if parts.len >= 4usize { al = parse_alpha(a, parts[3]) }
    ret (hsl_to_argb(h, sp, l, al), true)
}

fn hwb_to_argb(h: f64, w: f64, bl: f64, ai: i64) -> u32 {
    if w + bl >= 1.0f64 {
        let gray = clamp255((w / (w + bl)) * 255.0f64)
        ret argb(ai, gray, gray, gray)
    }
    let (r, g, b) = hue_to_rgb(h)
    let k = 1.0f64 - w - bl
    ret argb(ai, clamp255((r * k + w) * 255.0f64), clamp255((g * k + w) * 255.0f64), clamp255((b * k + w) * 255.0f64))
}

fn parse_hwb(a: *mem.Arena, s: str) -> (u32, bool) {
    let open = index_of(s, "(")
    let close = index_of(s, ")")
    if open == -1i64 || close == -1i64 || close < open { ret (0u32, false) }
    let parts = split_on_mode(a, s[usize(open) + 1usize..usize(close)], 1u8)
    if parts.len < 3usize { ret (0u32, false) }
    let h = parse_hue(a, parts[0])
    let w = clamp_f(parse_or(a, strip_percent(a, parts[1]), 0.0f64) / 100.0f64, 0.0f64, 1.0f64)
    let bl = clamp_f(parse_or(a, strip_percent(a, parts[2]), 0.0f64) / 100.0f64, 0.0f64, 1.0f64)
    var al = 1.0f64
    if parts.len >= 4usize { al = parse_alpha(a, parts[3]) }
    ret (hwb_to_argb(h, w, bl, clamp255(al * 255.0f64)), true)
}

// Variables of a relative colour: up to six names with their values, in the order Vaper's map holds them.
type Vars = struct { names: [8]str, values: [8]f64, count: usize }

fn vars_add(v: *Vars, name: str, value: f64) {
    v.names[v.count] = name
    v.values[v.count] = value
    v.count += 1usize
}

fn vars_get(v: *const Vars, name: str) -> (f64, bool) {
    var at = 0usize
    while at < v.count {
        if str.eq(v.names[at], name) { ret (v.values[at], true) }
        at += 1usize
    }
    ret (0.0f64, false)
}

fn is_lower_alpha(c: u8) -> bool { ret c >= 97u8 && c <= 122u8 }

// `s.replaceAll(RegExp('(?<![a-z])name(?![a-z])'), replacement)`.
fn replace_word(a: *mem.Arena, s: str, name: str, replacement: str) -> str {
    var out = ""
    var start = 0usize
    var i = 0usize
    while i + name.len <= s.len {
        if str.eq(s[i..i + name.len], name) && (i == 0usize || !is_lower_alpha(s[i - 1usize])) && (i + name.len == s.len || !is_lower_alpha(s[i + name.len])) {
            out = cat(a, cat(a, out, s[start..i]), replacement)
            i += name.len
            start = i
        } else {
            i += 1usize
        }
    }
    ret cat(a, out, s[start..])
}

fn substitute_vars(a: *mem.Arena, t: str, v: *const Vars) -> str {
    var expr = t
    var at = 0usize
    while at < v.count {
        expr = replace_word(a, expr, v.names[at], dart_text(a, v.values[at]))
        at += 1usize
    }
    ret expr
}

fn resolve_rel_channel(a: *mem.Arena, tok: str, v: *const Vars, pct_ref: f64) -> (f64, bool) {
    let t = trim_ws(tok)
    if t.len == 0usize { ret (0.0f64, false) }
    let (known, have) = vars_get(v, t)
    if have { ret (known, true) }
    if str.eq(t, "none") { ret (0.0f64, true) }
    let expr = substitute_vars(a, t, v)
    if str.ends_with(expr, "%") {
        let inner = expr[0usize..expr.len - 1usize]
        var n = 0.0f64
        var good = false
        let (p, p_ok) = try_parse(a, inner)
        if p_ok {
            n = p
            good = true
        } else {
            let (e2, e_ok) = eval_number(a, inner)
            n = e2
            good = e_ok
        }
        if !good { ret (0.0f64, false) }
        ret (n / 100.0f64 * pct_ref, true)
    }
    let (p, p_ok) = try_parse(a, expr)
    if p_ok { ret (p, true) }
    let (r0, r1) = eval_number(a, expr)
    ret (r0, r1)
}

fn resolve_rel_hue(a: *mem.Arena, tok: str, v: *const Vars) -> (f64, bool) {
    let t = trim_ws(tok)
    let (known, have) = vars_get(v, t)
    if have { ret (known, true) }
    if str.eq(t, "none") { ret (0.0f64, true) }
    let expr = substitute_vars(a, t, v)
    if index_of(expr, "(") >= 0i64 {
        let (r0, r1) = eval_number(a, expr)
        ret (r0, r1)
    }
    ret (parse_hue(a, expr), true)
}

// `(origin, rest)` of the text after `from `: the first colour token (a function with its parentheses, or a word).
fn first_color_token(body: str) -> (str, str, bool) {
    let b = trim_ws(body)
    if b.len == 0usize { ret ("", "", false) }
    let sp = index_of(b, " ")
    let paren = index_of(b, "(")
    if paren >= 0i64 && (sp < 0i64 || paren < sp) {
        var depth = 0i64
        var i = usize(paren)
        while i < b.len {
            if b[i] == 40u8 {
                depth += 1i64
            } else if b[i] == 41u8 {
                depth -= 1i64
                if depth == 0i64 { ret (b[0usize..i + 1usize], trim_ws(b[i + 1usize..]), true) }
            }
            i += 1usize
        }
        ret ("", "", false)
    }
    if sp < 0i64 { ret (b, "", true) }
    ret (b[0usize..usize(sp)], trim_ws(b[usize(sp) + 1usize..]), true)
}

type RelParts = struct { good: bool, base: u32, rest: str, has_alpha: bool, alpha_tok: str }

// The shared head of a relative colour: the origin colour, the channel text and the optional `/ alpha` token.
fn relative_head(a: *mem.Arena, s: str) -> RelParts {
    let none = RelParts { good: false, base: 0u32, rest: "", has_alpha: false, alpha_tok: "" }
    let open = index_of(s, "(")
    if open < 0i64 || s[s.len - 1usize] != 41u8 { ret none }
    var body = trim_ws(s[usize(open) + 1usize..s.len - 1usize])
    if !str.starts_with(body, "from ") { ret none }
    body = trim_ws(body[5usize..])
    var alpha_tok = ""
    var has_alpha = false
    let slash = top_level_index_of(body, 47u8)
    if slash >= 0i64 {
        alpha_tok = trim_ws(body[usize(slash) + 1usize..])
        has_alpha = true
        body = trim_ws(body[0usize..usize(slash)])
    }
    let (origin, rest, good) = first_color_token(body)
    if !good { ret none }
    let (base, base_ok) = parse_color(a, origin)
    if !base_ok { ret none }
    ret RelParts { good: true, base: base, rest: rest, has_alpha: has_alpha, alpha_tok: alpha_tok }
}

fn channel_r(c: u32) -> i64 { ret i64((c >> 16u32) & 255u32) }

fn channel_g(c: u32) -> i64 { ret i64((c >> 8u32) & 255u32) }

fn channel_b(c: u32) -> i64 { ret i64(c & 255u32) }

fn channel_a(c: u32) -> i64 { ret i64((c >> 24u32) & 255u32) }

fn parse_relative_rgb(a: *mem.Arena, s: str) -> (u32, bool) {
    let h = relative_head(a, s)
    if !h.good { ret (0u32, false) }
    var vars = Vars { names: zero, values: zero, count: 0usize }
    vars_add(&vars, "r", f64(channel_r(h.base)))
    vars_add(&vars, "g", f64(channel_g(h.base)))
    vars_add(&vars, "b", f64(channel_b(h.base)))
    vars_add(&vars, "alpha", f64(channel_a(h.base)) / 255.0f64)
    let chans = split_top_level_space(a, h.rest)
    if chans.len != 3usize { ret (0u32, false) }
    var comp: [3]i64 = zero
    var i = 0usize
    while i < 3usize {
        let (v, good) = resolve_rel_channel(a, chans[i], &vars, 255.0f64)
        if good { comp[i] = clamp255(v) } else { comp[i] = 0i64 }
        i += 1usize
    }
    var ai = channel_a(h.base)
    if h.has_alpha {
        let (v, good) = resolve_rel_channel(a, h.alpha_tok, &vars, 1.0f64)
        var al = f64(channel_a(h.base)) / 255.0f64
        if good { al = v }
        ai = clamp255(clamp_f(al, 0.0f64, 1.0f64) * 255.0f64)
    }
    var ai_clamped = ai
    if ai_clamped < 0i64 { ai_clamped = 0i64 }
    if ai_clamped > 255i64 { ai_clamped = 255i64 }
    ret (argb(ai_clamped, comp[0], comp[1], comp[2]), true)
}

fn parse_relative_hsl(a: *mem.Arena, s: str) -> (u32, bool) {
    let h = relative_head(a, s)
    if !h.good { ret (0u32, false) }
    let (h0, s0, l0) = rgb_to_hsl(f64(channel_r(h.base)) / 255.0f64, f64(channel_g(h.base)) / 255.0f64, f64(channel_b(h.base)) / 255.0f64)
    var vars = Vars { names: zero, values: zero, count: 0usize }
    vars_add(&vars, "h", h0)
    vars_add(&vars, "s", s0 * 100.0f64)
    vars_add(&vars, "l", l0 * 100.0f64)
    vars_add(&vars, "alpha", f64(channel_a(h.base)) / 255.0f64)
    let chans = split_top_level_space(a, h.rest)
    if chans.len != 3usize { ret (0u32, false) }
    let (hv, h_ok) = resolve_rel_hue(a, chans[0], &vars)
    let (sv_raw, s_ok) = resolve_rel_channel(a, chans[1], &vars, 100.0f64)
    let (lv_raw, l_ok) = resolve_rel_channel(a, chans[2], &vars, 100.0f64)
    var sv = 0.0f64
    if s_ok { sv = clamp_f(sv_raw, 0.0f64, 100.0f64) }
    var lv = 0.0f64
    if l_ok { lv = clamp_f(lv_raw, 0.0f64, 100.0f64) }
    if !h_ok { ret (0u32, false) }
    var av = f64(channel_a(h.base)) / 255.0f64
    if h.has_alpha {
        let (v, good) = resolve_rel_channel(a, h.alpha_tok, &vars, 1.0f64)
        var al = vars.values[3]
        if good { al = v }
        av = clamp_f(al, 0.0f64, 1.0f64)
    }
    ret (hsl_to_argb(hv, sv / 100.0f64, lv / 100.0f64, av), true)
}

fn parse_relative_hwb(a: *mem.Arena, s: str) -> (u32, bool) {
    let h = relative_head(a, s)
    if !h.good { ret (0u32, false) }
    let r01 = f64(channel_r(h.base)) / 255.0f64
    let g01 = f64(channel_g(h.base)) / 255.0f64
    let b01 = f64(channel_b(h.base)) / 255.0f64
    let (h0, ignore_s, ignore_l) = rgb_to_hsl(r01, g01, b01)
    let mx = dart_max(r01, dart_max(g01, b01))
    let mn = dart_min(r01, dart_min(g01, b01))
    var vars = Vars { names: zero, values: zero, count: 0usize }
    vars_add(&vars, "h", h0)
    vars_add(&vars, "w", mn * 100.0f64)
    vars_add(&vars, "b", (1.0f64 - mx) * 100.0f64)
    vars_add(&vars, "alpha", f64(channel_a(h.base)) / 255.0f64)
    let chans = split_top_level_space(a, h.rest)
    if chans.len != 3usize { ret (0u32, false) }
    let (hv, h_ok) = resolve_rel_hue(a, chans[0], &vars)
    let (wv_raw, w_ok) = resolve_rel_channel(a, chans[1], &vars, 100.0f64)
    let (bv_raw, b_ok) = resolve_rel_channel(a, chans[2], &vars, 100.0f64)
    var wv = 0.0f64
    if w_ok { wv = clamp_f(wv_raw, 0.0f64, 100.0f64) }
    var bv = 0.0f64
    if b_ok { bv = clamp_f(bv_raw, 0.0f64, 100.0f64) }
    if !h_ok { ret (0u32, false) }
    var av = f64(channel_a(h.base)) / 255.0f64
    if h.has_alpha {
        let (v, good) = resolve_rel_channel(a, h.alpha_tok, &vars, 1.0f64)
        var al = vars.values[3]
        if good { al = v }
        av = clamp_f(al, 0.0f64, 1.0f64)
    }
    ret (hwb_to_argb(hv, wv / 100.0f64, bv / 100.0f64, clamp255(av * 255.0f64)), true)
}

// --- wide-gamut colour spaces ----------------------------------------------------------------------------------------

fn cbrt_of(x: f64) -> f64 {
    if x < 0.0f64 { ret -math.pow[f64](-x, 1.0f64 / 3.0f64) }
    ret math.pow[f64](x, 1.0f64 / 3.0f64)
}

fn srgb_to_linear(c: f64) -> f64 {
    var sign = 1.0f64
    if c < 0.0f64 { sign = -1.0f64 }
    let av = math.abs[f64](c)
    if av <= 0.04045f64 { ret c / 12.92f64 }
    ret sign * math.pow[f64]((av + 0.055f64) / 1.055f64, 2.4f64)
}

fn linear_to_srgb(c: f64) -> f64 {
    var sign = 1.0f64
    if c < 0.0f64 { sign = -1.0f64 }
    let av = math.abs[f64](c)
    if av <= 0.0031308f64 { ret c * 12.92f64 }
    ret sign * (1.055f64 * math.pow[f64](av, 1.0f64 / 2.4f64) - 0.055f64)
}

type Vec3 = struct { x: f64, y: f64, z: f64 }

type Mat3 = struct { m: [9]f64 }

fn mat_vec(m: Mat3, v: Vec3) -> Vec3 {
    ret Vec3 { x: m.m[0] * v.x + m.m[1] * v.y + m.m[2] * v.z, y: m.m[3] * v.x + m.m[4] * v.y + m.m[5] * v.z, z: m.m[6] * v.x + m.m[7] * v.y + m.m[8] * v.z }
}

fn mat(a0: f64, a1: f64, a2: f64, a3: f64, a4: f64, a5: f64, a6: f64, a7: f64, a8: f64) -> Mat3 {
    var out: [9]f64 = zero
    out[0] = a0
    out[1] = a1
    out[2] = a2
    out[3] = a3
    out[4] = a4
    out[5] = a5
    out[6] = a6
    out[7] = a7
    out[8] = a8
    ret Mat3 { m: out }
}

fn lin_srgb_to_xyz() -> Mat3 { ret mat(0.41239079926595934f64, 0.357584339383878f64, 0.1804807884018343f64, 0.21263900587151027f64, 0.715168678767756f64, 0.07219231536073371f64, 0.01933081871559182f64, 0.11919477979462598f64, 0.9505321522496607f64) }

fn xyz_to_lin_srgb() -> Mat3 { ret mat(3.2409699419045226f64, -1.537383177570094f64, -0.4986107602930034f64, -0.9692436362808796f64, 1.8759675015077202f64, 0.04155505740717559f64, 0.05563007969699366f64, -0.20397695888897652f64, 1.0569715142428786f64) }

fn d65_to_d50() -> Mat3 { ret mat(1.0479298208405488f64, 0.022946793341019088f64, -0.05019222954313557f64, 0.029627815688159344f64, 0.990434484573249f64, -0.01707382502938514f64, -0.009243058152591178f64, 0.015055144896577895f64, 0.7518742899580008f64) }

fn d50_to_d65() -> Mat3 { ret mat(0.9554734527042182f64, -0.023098536874261423f64, 0.0632593086610217f64, -0.028369706963208136f64, 1.0099954580058226f64, 0.021041398966943008f64, 0.012314001688319899f64, -0.020507696433477912f64, 1.3303659366080753f64) }

fn xyz_to_lms() -> Mat3 { ret mat(0.8190224379967030f64, 0.3619062600528904f64, -0.1288737815209879f64, 0.0329836539323885f64, 0.9292868615863434f64, 0.0361446663506424f64, 0.0481771893596242f64, 0.2642395317527308f64, 0.6335478284694309f64) }

fn lms_to_oklab() -> Mat3 { ret mat(0.2104542683093140f64, 0.7936177747023054f64, -0.0040720430116193f64, 1.9779985324311684f64, -2.4285922420485799f64, 0.4505937096174110f64, 0.0259040424655478f64, 0.7827717124575296f64, -0.8086757549230774f64) }

fn oklab_to_lms() -> Mat3 { ret mat(1.0f64, 0.3963377773761749f64, 0.2158037573099136f64, 1.0f64, -0.1055613458156586f64, -0.0638541728258133f64, 1.0f64, -0.0894841775298119f64, -1.2914855480194092f64) }

fn lms_to_xyz() -> Mat3 { ret mat(1.2268798758459243f64, -0.5578149944602171f64, 0.2813910456659647f64, -0.0405757452148008f64, 1.1122868032803170f64, -0.0717110580655164f64, -0.0763729366746601f64, -0.4214933324022432f64, 1.5869240198367816f64) }

fn p3_to_xyz() -> Mat3 { ret mat(0.4865709486482162f64, 0.26566769316909306f64, 0.19821728523436247f64, 0.2289745640697488f64, 0.6917385218365064f64, 0.079286914093745f64, 0.0f64, 0.04511338185890264f64, 1.043944368900976f64) }

fn a98_to_xyz() -> Mat3 { ret mat(0.5766690429101305f64, 0.1855582379065463f64, 0.1882286462349947f64, 0.29734497525053605f64, 0.6273635662554661f64, 0.07529145849399788f64, 0.02703136138641234f64, 0.07068885253582723f64, 0.9913375368376388f64) }

fn rec2020_to_xyz() -> Mat3 { ret mat(0.6369580483012914f64, 0.14461690358620832f64, 0.16888097516417205f64, 0.2627002120112671f64, 0.6779980715188708f64, 0.05930171646986196f64, 0.0f64, 0.028072693049087428f64, 1.060985057710791f64) }

fn prophoto_to_xyz() -> Mat3 { ret mat(0.7977666449006423f64, 0.13518129740053308f64, 0.0313477341283922f64, 0.2880748288194013f64, 0.711835234241873f64, 0.00008993693872564f64, 0.0f64, 0.0f64, 0.8251046025104602f64) }

fn argb_to_xyz_d65(c: u32) -> Vec3 {
    let lin = Vec3 { x: srgb_to_linear(f64(channel_r(c)) / 255.0f64), y: srgb_to_linear(f64(channel_g(c)) / 255.0f64), z: srgb_to_linear(f64(channel_b(c)) / 255.0f64) }
    ret mat_vec(lin_srgb_to_xyz(), lin)
}

fn unit_channel(v: f64) -> i64 { ret clamp255(clamp_f(v, 0.0f64, 1.0f64) * 255.0f64) }

fn xyz_d65_to_argb(xyz: Vec3, alpha: f64) -> u32 {
    let lin = mat_vec(xyz_to_lin_srgb(), xyz)
    ret argb(clamp255(alpha * 255.0f64), unit_channel(linear_to_srgb(lin.x)), unit_channel(linear_to_srgb(lin.y)), unit_channel(linear_to_srgb(lin.z)))
}

fn lab_wx() -> f64 { ret 0.3457f64 / 0.3585f64 }

fn lab_wz() -> f64 { ret (1.0f64 - 0.3457f64 - 0.3585f64) / 0.3585f64 }

fn lab_e() -> f64 { ret 216.0f64 / 24389.0f64 }

fn lab_k() -> f64 { ret 24389.0f64 / 27.0f64 }

fn lab_f(t: f64) -> f64 {
    if t > lab_e() { ret cbrt_of(t) }
    ret (lab_k() * t + 16.0f64) / 116.0f64
}

fn xyz_d50_to_lab(xyz: Vec3) -> Vec3 {
    let fx = lab_f(xyz.x / lab_wx())
    let fy = lab_f(xyz.y / 1.0f64)
    let fz = lab_f(xyz.z / lab_wz())
    ret Vec3 { x: 116.0f64 * fy - 16.0f64, y: 500.0f64 * (fx - fy), z: 200.0f64 * (fy - fz) }
}

fn lab_to_xyz_d50(lab: Vec3) -> Vec3 {
    let fy = (lab.x + 16.0f64) / 116.0f64
    let fx = lab.y / 500.0f64 + fy
    let fz = fy - lab.z / 200.0f64
    var x = (116.0f64 * fx - 16.0f64) / lab_k()
    if fx * fx * fx > lab_e() { x = fx * fx * fx }
    var y = lab.x / lab_k()
    if lab.x > lab_k() * lab_e() { y = fy * fy * fy }
    var z = (116.0f64 * fz - 16.0f64) / lab_k()
    if fz * fz * fz > lab_e() { z = fz * fz * fz }
    ret Vec3 { x: x * lab_wx(), y: y * 1.0f64, z: z * lab_wz() }
}

fn lab_to_lch(lab: Vec3) -> Vec3 {
    let c = math.sqrt[f64](lab.y * lab.y + lab.z * lab.z)
    var h = math.atan2[f64](lab.z, lab.y) * 180.0f64 / pi()
    if h < 0.0f64 { h = h + 360.0f64 }
    ret Vec3 { x: lab.x, y: c, z: h }
}

fn lch_to_lab(lch: Vec3) -> Vec3 {
    let hr = lch.z * pi() / 180.0f64
    ret Vec3 { x: lch.x, y: lch.y * math.cos[f64](hr), z: lch.y * math.sin[f64](hr) }
}

fn xyz_d65_to_oklab(xyz: Vec3) -> Vec3 {
    let lms = mat_vec(xyz_to_lms(), xyz)
    ret mat_vec(lms_to_oklab(), Vec3 { x: cbrt_of(lms.x), y: cbrt_of(lms.y), z: cbrt_of(lms.z) })
}

fn oklab_to_xyz_d65(lab: Vec3) -> Vec3 {
    let lms = mat_vec(oklab_to_lms(), lab)
    ret mat_vec(lms_to_xyz(), Vec3 { x: lms.x * lms.x * lms.x, y: lms.y * lms.y * lms.y, z: lms.z * lms.z * lms.z })
}

type Coords = struct { v: Vec3, alpha: f64 }

fn to_space_coords(c: u32, space: str) -> (Coords, bool) {
    let alpha = f64(channel_a(c)) / 255.0f64
    let none = Coords { v: Vec3 { x: 0.0f64, y: 0.0f64, z: 0.0f64 }, alpha: 0.0f64 }
    if str.eq(space, "srgb") { ret (Coords { v: Vec3 { x: f64(channel_r(c)) / 255.0f64, y: f64(channel_g(c)) / 255.0f64, z: f64(channel_b(c)) / 255.0f64 }, alpha: alpha }, true) }
    if str.eq(space, "srgb-linear") { ret (Coords { v: Vec3 { x: srgb_to_linear(f64(channel_r(c)) / 255.0f64), y: srgb_to_linear(f64(channel_g(c)) / 255.0f64), z: srgb_to_linear(f64(channel_b(c)) / 255.0f64) }, alpha: alpha }, true) }
    let xyz = argb_to_xyz_d65(c)
    if str.eq(space, "xyz") || str.eq(space, "xyz-d65") { ret (Coords { v: xyz, alpha: alpha }, true) }
    if str.eq(space, "xyz-d50") { ret (Coords { v: mat_vec(d65_to_d50(), xyz), alpha: alpha }, true) }
    if str.eq(space, "lab") { ret (Coords { v: xyz_d50_to_lab(mat_vec(d65_to_d50(), xyz)), alpha: alpha }, true) }
    if str.eq(space, "lch") { ret (Coords { v: lab_to_lch(xyz_d50_to_lab(mat_vec(d65_to_d50(), xyz))), alpha: alpha }, true) }
    if str.eq(space, "oklab") { ret (Coords { v: xyz_d65_to_oklab(xyz), alpha: alpha }, true) }
    if str.eq(space, "oklch") { ret (Coords { v: lab_to_lch(xyz_d65_to_oklab(xyz)), alpha: alpha }, true) }
    ret (none, false)
}

fn from_space_coords(c: Coords, space: str) -> u32 {
    let alpha = c.alpha
    if str.eq(space, "srgb") { ret argb(clamp255(alpha * 255.0f64), unit_channel(c.v.x), unit_channel(c.v.y), unit_channel(c.v.z)) }
    if str.eq(space, "srgb-linear") { ret argb(clamp255(alpha * 255.0f64), unit_channel(linear_to_srgb(c.v.x)), unit_channel(linear_to_srgb(c.v.y)), unit_channel(linear_to_srgb(c.v.z))) }
    if str.eq(space, "xyz") || str.eq(space, "xyz-d65") { ret xyz_d65_to_argb(c.v, alpha) }
    if str.eq(space, "xyz-d50") { ret xyz_d65_to_argb(mat_vec(d50_to_d65(), c.v), alpha) }
    if str.eq(space, "lab") { ret xyz_d65_to_argb(mat_vec(d50_to_d65(), lab_to_xyz_d50(c.v)), alpha) }
    if str.eq(space, "lch") { ret xyz_d65_to_argb(mat_vec(d50_to_d65(), lab_to_xyz_d50(lch_to_lab(c.v))), alpha) }
    if str.eq(space, "oklab") { ret xyz_d65_to_argb(oklab_to_xyz_d65(c.v), alpha) }
    if str.eq(space, "oklch") { ret xyz_d65_to_argb(oklab_to_xyz_d65(lch_to_lab(c.v)), alpha) }
    ret 0u32
}

fn hue_index(space: str) -> i64 {
    if str.eq(space, "lch") || str.eq(space, "oklch") { ret 2i64 }
    ret -1i64
}

fn is_xyz_space(space: str) -> bool { ret str.eq(space, "xyz") || str.eq(space, "xyz-d65") || str.eq(space, "xyz-d50") }

fn parse_relative_color_fn(a: *mem.Arena, s: str) -> (u32, bool) {
    let h = relative_head(a, s)
    if !h.good { ret (0u32, false) }
    let toks = split_top_level_space(a, h.rest)
    if toks.len != 4usize { ret (0u32, false) }
    let space = toks[0]
    let (coords, have) = to_space_coords(h.base, space)
    if !have { ret (0u32, false) }
    var vars = Vars { names: zero, values: zero, count: 0usize }
    if is_xyz_space(space) {
        vars_add(&vars, "x", coords.v.x)
        vars_add(&vars, "y", coords.v.y)
        vars_add(&vars, "z", coords.v.z)
    } else {
        vars_add(&vars, "r", coords.v.x)
        vars_add(&vars, "g", coords.v.y)
        vars_add(&vars, "b", coords.v.z)
    }
    vars_add(&vars, "alpha", coords.alpha)
    var resolved: [3]f64 = zero
    var i = 0usize
    while i < 3usize {
        let (v, good) = resolve_rel_channel(a, toks[i + 1usize], &vars, 1.0f64)
        if !good { ret (0u32, false) }
        resolved[i] = v
        i += 1usize
    }
    var av = coords.alpha
    if h.has_alpha {
        let (v, good) = resolve_rel_channel(a, h.alpha_tok, &vars, 1.0f64)
        var al = coords.alpha
        if good { al = v }
        av = clamp_f(al, 0.0f64, 1.0f64)
    }
    ret (from_space_coords(Coords { v: Vec3 { x: resolved[0], y: resolved[1], z: resolved[2] }, alpha: av }, space), true)
}

fn parse_relative_color_space(a: *mem.Arena, s: str, space: str, n0: str, n1: str, n2: str) -> (u32, bool) {
    let h = relative_head(a, s)
    if !h.good { ret (0u32, false) }
    let (coords, have) = to_space_coords(h.base, space)
    if !have { ret (0u32, false) }
    var vars = Vars { names: zero, values: zero, count: 0usize }
    vars_add(&vars, n0, coords.v.x)
    vars_add(&vars, n1, coords.v.y)
    vars_add(&vars, n2, coords.v.z)
    vars_add(&vars, "alpha", coords.alpha)
    let chans = split_top_level_space(a, h.rest)
    if chans.len != 3usize { ret (0u32, false) }
    let hue_idx = hue_index(space)
    var resolved: [3]f64 = zero
    var i = 0usize
    while i < 3usize {
        var v = 0.0f64
        var good = false
        if i64(i) == hue_idx {
            let (hv, h_ok) = resolve_rel_hue(a, chans[i], &vars)
            v = hv
            good = h_ok
        } else {
            let (cv, c_ok) = resolve_rel_channel(a, chans[i], &vars, 1.0f64)
            v = cv
            good = c_ok
        }
        if !good { ret (0u32, false) }
        resolved[i] = v
        i += 1usize
    }
    var av = coords.alpha
    if h.has_alpha {
        let (v, good) = resolve_rel_channel(a, h.alpha_tok, &vars, 1.0f64)
        var al = coords.alpha
        if good { al = v }
        av = clamp_f(al, 0.0f64, 1.0f64)
    }
    ret (from_space_coords(Coords { v: Vec3 { x: resolved[0], y: resolved[1], z: resolved[2] }, alpha: av }, space), true)
}

fn interp_hue(h1: f64, h2: f64, w1: f64, w2: f64) -> f64 {
    var x = euclid_mod(h1, 360.0f64)
    if x < 0.0f64 { x = x + 360.0f64 }
    var y = euclid_mod(h2, 360.0f64)
    if y < 0.0f64 { y = y + 360.0f64 }
    let dh = y - x
    if dh > 180.0f64 {
        y = y - 360.0f64
    } else if dh < -180.0f64 {
        y = y + 360.0f64
    }
    ret x * w1 + y * w2
}

fn mix_in_space(c1: u32, c2: u32, w1: f64, w2: f64, space: str) -> (u32, bool) {
    let (ca, a_ok) = to_space_coords(c1, space)
    let (cb, b_ok) = to_space_coords(c2, space)
    if !a_ok || !b_ok { ret (0u32, false) }
    let hue_idx = hue_index(space)
    var out = Vec3 { x: 0.0f64, y: 0.0f64, z: 0.0f64 }
    if hue_idx == 0i64 { out.x = interp_hue(ca.v.x, cb.v.x, w1, w2) } else { out.x = ca.v.x * w1 + cb.v.x * w2 }
    if hue_idx == 1i64 { out.y = interp_hue(ca.v.y, cb.v.y, w1, w2) } else { out.y = ca.v.y * w1 + cb.v.y * w2 }
    if hue_idx == 2i64 { out.z = interp_hue(ca.v.z, cb.v.z, w1, w2) } else { out.z = ca.v.z * w1 + cb.v.z * w2 }
    ret (from_space_coords(Coords { v: out, alpha: ca.alpha * w1 + cb.alpha * w2 }, space), true)
}

fn component(a: *mem.Arena, t: str, pct_ref: f64) -> f64 {
    if str.eq(t, "none") { ret 0.0f64 }
    if str.ends_with(t, "%") { ret parse_or(a, t[0usize..t.len - 1usize], 0.0f64) / 100.0f64 * pct_ref }
    ret parse_or(a, t, 0.0f64)
}

fn angle_of(a: *mem.Arena, t: str) -> f64 {
    if str.eq(t, "none") { ret 0.0f64 }
    ret parse_hue(a, t)
}

type Components = struct { good: bool, toks: []const str, alpha: f64 }

fn func_components(a: *mem.Arena, s: str) -> Components {
    let open = index_of(s, "(")
    let close = last_index_of_byte(s, 41u8)
    if open < 0i64 || close < 0i64 || close < open { ret Components { good: false, toks: zero, alpha: 1.0f64 } }
    var body = trim_ws(s[usize(open) + 1usize..usize(close)])
    var alpha = 1.0f64
    let slash = index_of(body, "/")
    if slash >= 0i64 {
        alpha = parse_alpha(a, trim_ws(body[usize(slash) + 1usize..]))
        body = trim_ws(body[0usize..usize(slash)])
    }
    ret Components { good: true, toks: split_on_mode(a, body, 2u8), alpha: alpha }
}

fn parse_lab_lch(a: *mem.Arena, s: str, space: str) -> (u32, bool) {
    let comps = func_components(a, s)
    if !comps.good || comps.toks.len < 3usize { ret (0u32, false) }
    let ok_space = str.eq(space, "oklab") || str.eq(space, "oklch")
    var l_ref = 100.0f64
    if ok_space { l_ref = 1.0f64 }
    let l = component(a, comps.toks[0], l_ref)
    if str.eq(space, "lab") { ret (from_space_coords(Coords { v: Vec3 { x: l, y: component(a, comps.toks[1], 125.0f64), z: component(a, comps.toks[2], 125.0f64) }, alpha: comps.alpha }, "lab"), true) }
    if str.eq(space, "lch") { ret (from_space_coords(Coords { v: Vec3 { x: l, y: component(a, comps.toks[1], 150.0f64), z: angle_of(a, comps.toks[2]) }, alpha: comps.alpha }, "lch"), true) }
    if str.eq(space, "oklab") { ret (from_space_coords(Coords { v: Vec3 { x: l, y: component(a, comps.toks[1], 0.4f64), z: component(a, comps.toks[2], 0.4f64) }, alpha: comps.alpha }, "oklab"), true) }
    if str.eq(space, "oklch") { ret (from_space_coords(Coords { v: Vec3 { x: l, y: component(a, comps.toks[1], 0.4f64), z: angle_of(a, comps.toks[2]) }, alpha: comps.alpha }, "oklch"), true) }
    ret (0u32, false)
}

fn a98_to_linear(v: f64) -> f64 {
    var sign = 1.0f64
    if v < 0.0f64 { sign = -1.0f64 }
    ret sign * math.pow[f64](math.abs[f64](v), 563.0f64 / 256.0f64)
}

fn rec2020_to_linear(v: f64) -> f64 {
    let ka = 1.09929682680944f64
    let kb = 0.018053968510807f64
    var sign = 1.0f64
    if v < 0.0f64 { sign = -1.0f64 }
    let av = math.abs[f64](v)
    if av < kb * 4.5f64 { ret v / 4.5f64 }
    ret sign * math.pow[f64]((av + ka - 1.0f64) / ka, 1.0f64 / 0.45f64)
}

fn prophoto_to_linear(v: f64) -> f64 {
    let et = 1.0f64 / 512.0f64
    var sign = 1.0f64
    if v < 0.0f64 { sign = -1.0f64 }
    let av = math.abs[f64](v)
    if av <= et * 16.0f64 { ret v / 16.0f64 }
    ret sign * math.pow[f64](av, 1.8f64)
}

fn map_v3(v: Vec3, which: u8) -> Vec3 {
    if which == 0u8 { ret Vec3 { x: srgb_to_linear(v.x), y: srgb_to_linear(v.y), z: srgb_to_linear(v.z) } }
    if which == 1u8 { ret Vec3 { x: a98_to_linear(v.x), y: a98_to_linear(v.y), z: a98_to_linear(v.z) } }
    if which == 2u8 { ret Vec3 { x: rec2020_to_linear(v.x), y: rec2020_to_linear(v.y), z: rec2020_to_linear(v.z) } }
    ret Vec3 { x: prophoto_to_linear(v.x), y: prophoto_to_linear(v.y), z: prophoto_to_linear(v.z) }
}

fn parse_color_function(a: *mem.Arena, s: str) -> (u32, bool) {
    let comps = func_components(a, s)
    if !comps.good || comps.toks.len == 0usize { ret (0u32, false) }
    let space = comps.toks[0]
    var c = Vec3 { x: 0.0f64, y: 0.0f64, z: 0.0f64 }
    if comps.toks.len > 1usize { c.x = component(a, comps.toks[1], 1.0f64) }
    if comps.toks.len > 2usize { c.y = component(a, comps.toks[2], 1.0f64) }
    if comps.toks.len > 3usize { c.z = component(a, comps.toks[3], 1.0f64) }
    if str.eq(space, "srgb") { ret (from_space_coords(Coords { v: c, alpha: comps.alpha }, "srgb"), true) }
    var xyz = Vec3 { x: 0.0f64, y: 0.0f64, z: 0.0f64 }
    if str.eq(space, "srgb-linear") {
        xyz = mat_vec(lin_srgb_to_xyz(), c)
    } else if str.eq(space, "display-p3") {
        xyz = mat_vec(p3_to_xyz(), map_v3(c, 0u8))
    } else if str.eq(space, "a98-rgb") {
        xyz = mat_vec(a98_to_xyz(), map_v3(c, 1u8))
    } else if str.eq(space, "rec2020") {
        xyz = mat_vec(rec2020_to_xyz(), map_v3(c, 2u8))
    } else if str.eq(space, "prophoto-rgb") {
        xyz = mat_vec(d50_to_d65(), mat_vec(prophoto_to_xyz(), map_v3(c, 3u8)))
    } else if str.eq(space, "xyz") || str.eq(space, "xyz-d65") {
        xyz = c
    } else if str.eq(space, "xyz-d50") {
        xyz = mat_vec(d50_to_d65(), c)
    } else {
        ret (0u32, false)
    }
    ret (xyz_d65_to_argb(xyz, comps.alpha), true)
}

fn named_color(name: str) -> (u32, bool) {
    if str.eq(name, "black") { ret (0xFF000000u32, true) }
    if str.eq(name, "white") { ret (0xFFFFFFFFu32, true) }
    if str.eq(name, "red") { ret (0xFFFF0000u32, true) }
    if str.eq(name, "green") { ret (0xFF008000u32, true) }
    if str.eq(name, "lime") { ret (0xFF00FF00u32, true) }
    if str.eq(name, "blue") { ret (0xFF0000FFu32, true) }
    if str.eq(name, "yellow") { ret (0xFFFFFF00u32, true) }
    if str.eq(name, "cyan") || str.eq(name, "aqua") { ret (0xFF00FFFFu32, true) }
    if str.eq(name, "magenta") || str.eq(name, "fuchsia") { ret (0xFFFF00FFu32, true) }
    if str.eq(name, "silver") { ret (0xFFC0C0C0u32, true) }
    if str.eq(name, "gray") || str.eq(name, "grey") { ret (0xFF808080u32, true) }
    if str.eq(name, "maroon") { ret (0xFF800000u32, true) }
    if str.eq(name, "olive") { ret (0xFF808000u32, true) }
    if str.eq(name, "purple") { ret (0xFF800080u32, true) }
    if str.eq(name, "teal") { ret (0xFF008080u32, true) }
    if str.eq(name, "navy") { ret (0xFF000080u32, true) }
    if str.eq(name, "orange") { ret (0xFFFFA500u32, true) }
    if str.eq(name, "pink") { ret (0xFFFFC0CBu32, true) }
    if str.eq(name, "brown") { ret (0xFFA52A2Au32, true) }
    if str.eq(name, "gold") { ret (0xFFFFD700u32, true) }
    if str.eq(name, "indigo") { ret (0xFF4B0082u32, true) }
    if str.eq(name, "violet") { ret (0xFFEE82EEu32, true) }
    if str.eq(name, "plum") { ret (0xFFDDA0DDu32, true) }
    if str.eq(name, "lightgray") || str.eq(name, "lightgrey") { ret (0xFFD3D3D3u32, true) }
    if str.eq(name, "darkgray") || str.eq(name, "darkgrey") { ret (0xFFA9A9A9u32, true) }
    if str.eq(name, "lightblue") { ret (0xFFADD8E6u32, true) }
    if str.eq(name, "lightgreen") { ret (0xFF90EE90u32, true) }
    if str.eq(name, "dodgerblue") { ret (0xFF1E90FFu32, true) }
    if str.eq(name, "steelblue") { ret (0xFF4682B4u32, true) }
    if str.eq(name, "tomato") { ret (0xFFFF6347u32, true) }
    if str.eq(name, "crimson") { ret (0xFFDC143Cu32, true) }
    if str.eq(name, "coral") { ret (0xFFFF7F50u32, true) }
    if str.eq(name, "salmon") { ret (0xFFFA8072u32, true) }
    if str.eq(name, "khaki") { ret (0xFFF0E68Cu32, true) }
    if str.eq(name, "whitesmoke") { ret (0xFFF5F5F5u32, true) }
    if str.eq(name, "gainsboro") { ret (0xFFDCDCDCu32, true) }
    if str.eq(name, "rebeccapurple") { ret (0xFF663399u32, true) }
    if str.eq(name, "ivory") { ret (0xFFFFFFF0u32, true) }
    if str.eq(name, "aliceblue") { ret (0xFFF0F8FFu32, true) }
    if str.eq(name, "mistyrose") { ret (0xFFFFE4E1u32, true) }
    if str.eq(name, "lightyellow") { ret (0xFFFFFFE0u32, true) }
    if str.eq(name, "palegreen") { ret (0xFF98FB98u32, true) }
    if str.eq(name, "darkblue") { ret (0xFF00008Bu32, true) }
    ret (0u32, false)
}

// Remove `/* ... */` comments (a space in their place), the way the regex `/\*.*?\*/` with dotAll does.
fn strip_comments(a: *mem.Arena, s: str) -> str {
    var out = ""
    var start = 0usize
    var i = 0usize
    while i + 1usize < s.len {
        if s[i] == 47u8 && s[i + 1usize] == 42u8 {
            var j = i + 2usize
            var closed = false
            while j + 1usize < s.len && !closed {
                if s[j] == 42u8 && s[j + 1usize] == 47u8 { closed = true } else { j += 1usize }
            }
            if closed {
                out = cat(a, cat(a, out, s[start..i]), " ")
                i = j + 2usize
                start = i
            } else {
                i += 1usize
            }
        } else {
            i += 1usize
        }
    }
    ret cat(a, out, s[start..])
}

// A colour as a 32-bit ARGB; `currentcolor` and unknown text are absent.
fn parse_color(a: *mem.Arena, raw: str) -> (u32, bool) {
    var s = lower(a, trim_ws(raw))
    if index_of(s, "/*") >= 0i64 { s = trim_ws(strip_comments(a, s)) }
    if s.len == 0usize || str.eq(s, "currentcolor") { ret (0u32, false) }
    if str.eq(s, "transparent") { ret (0u32, true) }
    let (named, is_named) = named_color(s)
    if is_named { ret (named, true) }
    let relative = index_of(s, "(from ") >= 0i64
    if str.starts_with(s, "#") {
        let (r0, r1) = parse_hex(a, s[1usize..])
        ret (r0, r1)
    }
    if str.starts_with(s, "rgb") {
        if relative {
            let (r0, r1) = parse_relative_rgb(a, s)
            ret (r0, r1)
        }
        let (r0, r1) = parse_rgb(a, s)
        ret (r0, r1)
    }
    if str.starts_with(s, "hsl") {
        if relative {
            let (r0, r1) = parse_relative_hsl(a, s)
            ret (r0, r1)
        }
        let (r0, r1) = parse_hsl(a, s)
        ret (r0, r1)
    }
    if str.starts_with(s, "hwb(") {
        if relative {
            let (r0, r1) = parse_relative_hwb(a, s)
            ret (r0, r1)
        }
        let (r0, r1) = parse_hwb(a, s)
        ret (r0, r1)
    }
    if str.starts_with(s, "lab(") {
        if relative {
            let (r0, r1) = parse_relative_color_space(a, s, "lab", "l", "a", "b")
            ret (r0, r1)
        }
        let (r0, r1) = parse_lab_lch(a, s, "lab")
        ret (r0, r1)
    }
    if str.starts_with(s, "lch(") {
        if relative {
            let (r0, r1) = parse_relative_color_space(a, s, "lch", "l", "c", "h")
            ret (r0, r1)
        }
        let (r0, r1) = parse_lab_lch(a, s, "lch")
        ret (r0, r1)
    }
    if str.starts_with(s, "oklab(") {
        if relative {
            let (r0, r1) = parse_relative_color_space(a, s, "oklab", "l", "a", "b")
            ret (r0, r1)
        }
        let (r0, r1) = parse_lab_lch(a, s, "oklab")
        ret (r0, r1)
    }
    if str.starts_with(s, "oklch(") {
        if relative {
            let (r0, r1) = parse_relative_color_space(a, s, "oklch", "l", "c", "h")
            ret (r0, r1)
        }
        let (r0, r1) = parse_lab_lch(a, s, "oklch")
        ret (r0, r1)
    }
    if str.starts_with(s, "color(") {
        if relative {
            let (r0, r1) = parse_relative_color_fn(a, s)
            ret (r0, r1)
        }
        let (r0, r1) = parse_color_function(a, s)
        ret (r0, r1)
    }
    ret (0u32, false)
}

fn mix_space_known(space: str) -> bool {
    ret str.eq(space, "srgb") || str.eq(space, "srgb-linear") || str.eq(space, "lab") || str.eq(space, "lch") || str.eq(space, "oklab") || str.eq(space, "oklch") || str.eq(space, "xyz") || str.eq(space, "xyz-d65") || str.eq(space, "xyz-d50")
}

type Stop = struct { good: bool, color: u32, has_pct: bool, pct: f64 }

fn color_stop(a: *mem.Arena, s: str, has_current: bool, current: u32) -> Stop {
    var has_pct = false
    var pct = 0.0f64
    var color_parts = strings_list(a)
    let toks = split_top_level_spaces(a, trim_ws(s))
    var i = 0usize
    while i < toks.len {
        let t = toks[i]
        var is_pct = false
        if str.ends_with(t, "%") {
            let (v, good) = try_parse(a, t[0usize..t.len - 1usize])
            if good {
                pct = v
                has_pct = true
                is_pct = true
            }
        }
        if !is_pct { push_str(&color_parts, t) }
        i += 1usize
    }
    var joined = ""
    var k = 0usize
    while k < color_parts.len {
        if k > 0usize { joined = cat(a, joined, " ") }
        joined = cat(a, joined, color_parts.items[k])
        k += 1usize
    }
    let low = lower(a, joined)
    var color = 0u32
    var good = false
    if str.eq(low, "currentcolor") {
        color = current
        good = has_current
    } else if str.starts_with(low, "color-mix(") {
        let (c, c_ok) = parse_color_mix(a, joined, has_current, current)
        color = c
        good = c_ok
    } else {
        let (c, c_ok) = parse_color(a, joined)
        color = c
        good = c_ok
    }
    ret Stop { good: good, color: color, has_pct: has_pct, pct: pct }
}

// `color-mix(in <space>, <colour> [p%], <colour> [p%])`.
fn parse_color_mix(a: *mem.Arena, raw: str, has_current: bool, current: u32) -> (u32, bool) {
    var s = trim_ws(raw)
    if index_of(s, "/*") >= 0i64 { s = trim_ws(strip_comments(a, s)) }
    let low = lower(a, s)
    if !str.starts_with(low, "color-mix(") || s[s.len - 1usize] != 41u8 { ret (0u32, false) }
    let parts = split_top_level_commas(a, s[10usize..s.len - 1usize])
    if parts.len != 3usize { ret (0u32, false) }
    var head = strings_list(a)
    let head_text = lower(a, trim_ws(parts[0]))
    var start = 0usize
    var i = 0usize
    while i <= head_text.len {
        if i == head_text.len || is_space(head_text[i]) {
            if i > start { push_str(&head, head_text[start..i]) }
            start = i + 1usize
        }
        i += 1usize
    }
    if head.len < 2usize || !str.eq(head.items[0], "in") { ret (0u32, false) }
    let space = head.items[1]
    if !mix_space_known(space) { ret (0u32, false) }
    let s1 = color_stop(a, trim_ws(parts[1]), has_current, current)
    let s2 = color_stop(a, trim_ws(parts[2]), has_current, current)
    if !s1.good || !s2.good { ret (0u32, false) }
    var pct1 = 0.0f64
    var pct2 = 0.0f64
    if !s1.has_pct && !s2.has_pct {
        pct1 = 50.0f64
        pct2 = 50.0f64
    } else if !s1.has_pct {
        pct2 = s2.pct
        pct1 = 100.0f64 - s2.pct
    } else if !s2.has_pct {
        pct1 = s1.pct
        pct2 = 100.0f64 - s1.pct
    } else {
        pct1 = s1.pct
        pct2 = s2.pct
    }
    let total = pct1 + pct2
    if total <= 0.0f64 { ret (0u32, false) }
    let w1 = pct1 / total
    let w2 = pct2 / total
    let (mixed, mixed_ok) = mix_in_space(s1.color, s2.color, w1, w2, space)
    if !mixed_ok { ret (0u32, false) }
    if total < 100.0f64 {
        let al = clamp255(f64(channel_a(mixed)) * total / 100.0f64)
        ret ((mixed & 0x00FFFFFFu32) | (u32(al) << 24u32), true)
    }
    ret (mixed, true)
}

fn relative_luminance(c: u32) -> f64 {
    let r = srgb_to_linear(f64(channel_r(c)) / 255.0f64)
    let g = srgb_to_linear(f64(channel_g(c)) / 255.0f64)
    let b = srgb_to_linear(f64(channel_b(c)) / 255.0f64)
    ret 0.2126f64 * r + 0.7152f64 * g + 0.0722f64 * b
}

// `contrast-color(<colour>)`: white over a dark colour, black over a light one.
fn parse_contrast_color(a: *mem.Arena, raw: str, has_current: bool, current: u32) -> (u32, bool) {
    var s = trim_ws(raw)
    if index_of(s, "/*") >= 0i64 { s = trim_ws(strip_comments(a, s)) }
    let low = lower(a, s)
    if !str.starts_with(low, "contrast-color(") || s[s.len - 1usize] != 41u8 { ret (0u32, false) }
    let inner = trim_ws(s[15usize..s.len - 1usize])
    let inner_low = lower(a, inner)
    var base = 0u32
    var good = false
    if str.eq(inner_low, "currentcolor") {
        base = current
        good = has_current
    } else if str.starts_with(inner_low, "color-mix(") {
        let (c, c_ok) = parse_color_mix(a, inner, has_current, current)
        base = c
        good = c_ok
    } else {
        let (c, c_ok) = parse_color(a, inner)
        base = c
        good = c_ok
    }
    if !good { ret (0u32, false) }
    if relative_luminance(base) < 0.17913f64 { ret (0xFFFFFFFFu32, true) }
    ret (0xFF000000u32, true)
}

// --- transforms --------------------------------------------------------------------------------------------------------

type Func = struct { name: str, args: []const str }

fn is_name_char(c: u8) -> bool { ret (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) }

fn transform_functions(a: *mem.Arena, s: str) -> []const Func {
    let (made, e) = list.init[Func](a, 4usize)
    if e != ok { ret zero }
    var out = made
    var i = 0usize
    while i < s.len {
        if !is_name_char(s[i]) {
            i += 1usize
        } else {
            var end = i
            while end < s.len && is_name_char(s[end]) { end += 1usize }
            if end >= s.len || s[end] != 40u8 {
                i = end
            } else {
                var depth = 0i64
                var k = end
                var found = false
                while k < s.len && !found {
                    if s[k] == 40u8 {
                        depth += 1i64
                    } else if s[k] == 41u8 {
                        depth -= 1i64
                        if depth == 0i64 { found = true }
                    }
                    if !found { k += 1usize }
                }
                if !found { ret list.slice_const[Func](&out) }
                let raw_args = split_top_level_commas(a, s[end + 1usize..k])
                var args = strings_list(a)
                var j = 0usize
                while j < raw_args.len {
                    let t = trim_ws(raw_args[j])
                    if t.len > 0usize { push_str(&args, t) }
                    j += 1usize
                }
                let pushed = list.push[Func](&out, Func { name: s[i..end], args: list.slice_const[str](&args) })
                i = k + 1usize
            }
        }
    }
    ret list.slice_const[Func](&out)
}

fn identity() -> [6]f64 {
    var m: [6]f64 = zero
    m[0] = 1.0f64
    m[3] = 1.0f64
    ret m
}

fn affine_mul(m: [6]f64, n: [6]f64) -> [6]f64 {
    var out: [6]f64 = zero
    out[0] = m[0] * n[0] + m[2] * n[1]
    out[1] = m[1] * n[0] + m[3] * n[1]
    out[2] = m[0] * n[2] + m[2] * n[3]
    out[3] = m[1] * n[2] + m[3] * n[3]
    out[4] = m[0] * n[4] + m[2] * n[5] + m[4]
    out[5] = m[1] * n[4] + m[3] * n[5] + m[5]
    ret out
}

fn six(a0: f64, a1: f64, a2: f64, a3: f64, a4: f64, a5: f64) -> [6]f64 {
    var m: [6]f64 = zero
    m[0] = a0
    m[1] = a1
    m[2] = a2
    m[3] = a3
    m[4] = a4
    m[5] = a5
    ret m
}

fn len_px(a: *mem.Arena, s: str) -> f64 {
    if str.ends_with(s, "%") { ret 0.0f64 }
    var body = s
    if str.ends_with(s, "px") { body = s[0usize..s.len - 2usize] }
    let (v, good) = try_parse(a, body)
    if good { ret v }
    let (l, l_ok) = parse_length(a, s, no_bases())
    if l_ok {
        let (px, px_ok) = to_px(l, no_bases())
        if px_ok { ret px }
    }
    ret 0.0f64
}

fn num_of(a: *mem.Arena, s: str) -> f64 {
    let (v, good) = parse_css_number(a, s)
    if good { ret v }
    ret 0.0f64
}

fn rad_of(a: *mem.Arena, s: str) -> f64 {
    if index_of(s, "(") >= 0i64 {
        let (ev, good) = eval_number(a, s)
        if good { ret ev }
    }
    ret parse_hue(a, s) * pi() / 180.0f64
}

fn arg_at(args: []const str, i: usize) -> str {
    if i < args.len { ret args[i] }
    ret ""
}

fn transform_func(a: *mem.Arena, name: str, args: []const str) -> ([6]f64, bool) {
    let none = identity()
    if args.len == 0usize && !str.eq(name, "matrix") { ret (none, false) }
    if str.eq(name, "translate") {
        var ty = 0.0f64
        if args.len > 1usize { ty = len_px(a, arg_at(args, 1usize)) }
        ret (six(1.0f64, 0.0f64, 0.0f64, 1.0f64, len_px(a, arg_at(args, 0usize)), ty), true)
    }
    if str.eq(name, "translatex") { ret (six(1.0f64, 0.0f64, 0.0f64, 1.0f64, len_px(a, arg_at(args, 0usize)), 0.0f64), true) }
    if str.eq(name, "translatey") { ret (six(1.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, len_px(a, arg_at(args, 0usize))), true) }
    if str.eq(name, "scale") {
        let sx = num_of(a, arg_at(args, 0usize))
        var sy = sx
        if args.len > 1usize { sy = num_of(a, arg_at(args, 1usize)) }
        ret (six(sx, 0.0f64, 0.0f64, sy, 0.0f64, 0.0f64), true)
    }
    if str.eq(name, "scalex") { ret (six(num_of(a, arg_at(args, 0usize)), 0.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64), true) }
    if str.eq(name, "scaley") { ret (six(1.0f64, 0.0f64, 0.0f64, num_of(a, arg_at(args, 0usize)), 0.0f64, 0.0f64), true) }
    if str.eq(name, "rotate") {
        let r = rad_of(a, arg_at(args, 0usize))
        let c = math.cos[f64](r)
        let s = math.sin[f64](r)
        ret (six(c, s, -s, c, 0.0f64, 0.0f64), true)
    }
    if str.eq(name, "skewx") { ret (six(1.0f64, 0.0f64, math.tan[f64](rad_of(a, arg_at(args, 0usize))), 1.0f64, 0.0f64, 0.0f64), true) }
    if str.eq(name, "skewy") { ret (six(1.0f64, math.tan[f64](rad_of(a, arg_at(args, 0usize))), 0.0f64, 1.0f64, 0.0f64, 0.0f64), true) }
    if str.eq(name, "skew") {
        var sy = 0.0f64
        if args.len > 1usize { sy = math.tan[f64](rad_of(a, arg_at(args, 1usize))) }
        ret (six(1.0f64, sy, math.tan[f64](rad_of(a, arg_at(args, 0usize))), 1.0f64, 0.0f64, 0.0f64), true)
    }
    if str.eq(name, "matrix") {
        if args.len < 6usize { ret (none, false) }
        ret (six(num_of(a, args[0]), num_of(a, args[1]), num_of(a, args[2]), num_of(a, args[3]), num_of(a, args[4]), num_of(a, args[5])), true)
    }
    ret (none, false)
}

// A transform list reduced to one affine `[a, b, c, d, e, f]`; absent for `none`, empty or nothing recognised.
fn parse_transform(a: *mem.Arena, raw: str) -> ([6]f64, bool) {
    let s = lower(a, trim_ws(raw))
    if s.len == 0usize || str.eq(s, "none") { ret (identity(), false) }
    var m = identity()
    var any = false
    let funcs = transform_functions(a, s)
    var i = 0usize
    while i < funcs.len {
        let (f, good) = transform_func(a, funcs[i].name, funcs[i].args)
        if good {
            m = affine_mul(m, f)
            any = true
        }
        i += 1usize
    }
    ret (m, any)
}

fn pct_of(a: *mem.Arena, s: str) -> f64 {
    if str.ends_with(s, "%") { ret parse_or(a, s[0usize..s.len - 1usize], 0.0f64) / 100.0f64 }
    ret 0.0f64
}

// The fraction of the box a percentage `translate*()` moves by: `(x, y)`.
fn parse_translate_percent(a: *mem.Arena, raw: str) -> (f64, f64) {
    let s = lower(a, trim_ws(raw))
    if s.len == 0usize || str.eq(s, "none") || index_of(s, "%") < 0i64 { ret (0.0f64, 0.0f64) }
    var fx = 0.0f64
    var fy = 0.0f64
    let funcs = transform_functions(a, s)
    var i = 0usize
    while i < funcs.len {
        let f = funcs[i]
        if str.eq(f.name, "translate") {
            if f.args.len > 0usize { fx = fx + pct_of(a, f.args[0]) }
            if f.args.len > 1usize { fy = fy + pct_of(a, f.args[1]) }
        } else if str.eq(f.name, "translatex") {
            if f.args.len > 0usize { fx = fx + pct_of(a, f.args[0]) }
        } else if str.eq(f.name, "translatey") {
            if f.args.len > 0usize { fy = fy + pct_of(a, f.args[0]) }
        }
        i += 1usize
    }
    ret (fx, fy)
}

// `transform-origin` as fractions of the box; `(0.5, 0.5)` when empty.
fn parse_transform_origin(a: *mem.Arena, raw: str) -> (f64, f64) {
    let text = lower(a, trim_ws(raw))
    var toks = strings_list(a)
    var start = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || is_space(text[i]) {
            if i > start { push_str(&toks, text[start..i]) }
            start = i + 1usize
        }
        i += 1usize
    }
    if toks.len == 0usize { ret (0.5f64, 0.5f64) }
    var x = 0.0f64
    var have_x = false
    var y = 0.0f64
    var have_y = false
    var k = 0usize
    while k < toks.len {
        let t = toks.items[k]
        if str.eq(t, "left") {
            x = 0.0f64
            have_x = true
        } else if str.eq(t, "right") {
            x = 1.0f64
            have_x = true
        } else if str.eq(t, "top") {
            y = 0.0f64
            have_y = true
        } else if str.eq(t, "bottom") {
            y = 1.0f64
            have_y = true
        } else if !str.eq(t, "center") {
            var frac = 0.5f64
            if str.ends_with(t, "%") { frac = parse_or(a, t[0usize..t.len - 1usize], 50.0f64) / 100.0f64 }
            if !have_x {
                x = frac
                have_x = true
            } else {
                y = frac
                have_y = true
            }
        }
        k += 1usize
    }
    if !have_x { x = 0.5f64 }
    if !have_y { y = 0.5f64 }
    ret (x, y)
}
