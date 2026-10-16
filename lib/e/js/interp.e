// The JavaScript interpreter core (browser tracker 5.3/5.4/5.6): values, objects, environments and a tree-walking evaluator
// over the flat tree of `e.js.ast`.
//
// A `Value` is undefined, null, boolean, number (f64), string (UTF-8 `str`; length and indexing count UTF-16 code units, see
// `units`), symbol or object. Objects live in an arena and are never freed while their realm lives (there is no collector
// yet: a realm is discarded whole). An object keeps its own properties in insertion order in `props` (linear scan, plus a
// hash index once it grows), array elements in `elems`, and a class tag the builtins use to recognise their instances.
// Exceptions travel as the `Throw` error with the thrown value in `Interp.thrown`. Generators, async functions, proxies,
// modules and BigInt are not implemented yet.
//
// Builtins (`Object`, `Array`, ...) live in `e.js.realm`, which fills `Interp.protos` and the global object; this module
// only needs the intrinsics it reaches through `Interp`.

use e.data.list as list
use e.data.map as map
use e.js.ast as ast
use e.js.parser as jsparse
use e.math
use e.mem
use e.str
use e.sync
use e.thread

error Throw
error OutOfMemory
error Unsupported

// Object classes.
const C_OBJECT: u8 = 0u8
const C_ARRAY: u8 = 1u8
const C_FUNCTION: u8 = 2u8
const C_ERROR: u8 = 3u8
const C_BOOLEAN: u8 = 4u8
const C_NUMBER: u8 = 5u8
const C_STRING: u8 = 6u8
const C_SYMBOL: u8 = 7u8
const C_DATE: u8 = 8u8
const C_REGEXP: u8 = 9u8
const C_ARGUMENTS: u8 = 10u8
const C_MAP: u8 = 11u8
const C_SET: u8 = 12u8
const C_PROMISE: u8 = 13u8
const C_GENERATOR: u8 = 14u8
const C_BOUND: u8 = 15u8
const C_PROXY: u8 = 16u8
const C_WEAKMAP: u8 = 17u8
const C_WEAKSET: u8 = 18u8
const C_BIGINT: u8 = 19u8
const C_ARRAYBUFFER: u8 = 20u8
const C_TYPEDARRAY: u8 = 21u8
const C_DATAVIEW: u8 = 22u8
const C_ITERATOR: u8 = 23u8

// Property flags.
const P_WRITABLE: u8 = 1u8
const P_ENUMERABLE: u8 = 2u8
const P_CONFIGURABLE: u8 = 4u8
const P_ACCESSOR: u8 = 8u8
const P_DEFAULT: u8 = 7u8
const P_HIDDEN: u8 = 5u8

type Sym = struct { description: str, has_description: bool, id: u32, registered: bool, private: bool }

type Value = union enum u8 { Undefined, Null, Bool: bool, Num: f64, Str: str, Sym: *Sym, Obj: *Obj }

// A property key: a string name (`idx` >= 0 when it is a canonical array index) or a symbol.
type Key = struct { name: str, sym: *Sym, idx: i64 }

type Prop = struct { key: Key, value: Value, getter: *Obj, setter: *Obj, flags: u8 }

type NativeFn = fn(*Interp, Value, []const Value) -> (Value, err)

type Env = struct { vars: list.List[Binding], parent: *Env, with_obj: *Obj, has_with: bool }

// Binding flags.
const B_CONST: u8 = 1u8
const B_TDZ: u8 = 2u8
const B_STRICT_CONST: u8 = 4u8

type Binding = struct { name: str, value: Value, flags: u8 }

type Obj = struct {
    class: u8, proto: *Obj, has_proto: bool, extensible: bool,
    props: list.List[Prop], index: map.Map[str, usize], indexed: bool,
    elems: list.List[Value], holes: bool,
    // functions
    prog: *const ast.Program, node: u32, env: *Env, native: NativeFn, has_native: bool, ctor_kind: u8, home: *Obj, has_home: bool,
    fields: *Obj, has_fields: bool, this_val: Value, bound_target: *Obj, bound_this: Value, bound_args: []const Value,
    // primitive wrappers, dates, internal slots
    prim: Value, data: *void, num: f64, text: str, aux: *Obj, id: u64
}

// Constructor kinds of a function object.
const K_NONE: u8 = 0u8
const K_BASE: u8 = 1u8
const K_DERIVED: u8 = 2u8

type Protos = struct {
    object: *Obj, function: *Obj, array: *Obj, string: *Obj, number: *Obj, boolean: *Obj, symbol: *Obj, error_proto: *Obj,
    type_error: *Obj, range_error: *Obj, syntax_error: *Obj, reference_error: *Obj, eval_error: *Obj, uri_error: *Obj,
    iterator: *Obj, array_iterator: *Obj, generator: *Obj, promise: *Obj, regexp: *Obj, date: *Obj, map: *Obj, set: *Obj,
    bigint: *Obj, arguments: *Obj, gen_function: *Obj, async_function: *Obj, async_generator: *Obj, async_gen_function: *Obj, map_iterator: *Obj, set_iterator: *Obj, weakmap: *Obj, weakset: *Obj, regexp_string_iterator: *Obj, array_buffer: *Obj, typed_array: *Obj, data_view: *Obj, aggregate_error: *Obj
}

type Interp = struct {
    a: *mem.Arena, protos: Protos, global: *Obj, global_env: *Env, thrown: Value, depth: u32, max_depth: u32,
    next_symbol: u32, callee: *Obj, new_target: Value, has_new_target: bool, steps: u64, step_limit: u64,
    sym_iterator: *Sym, sym_has_instance: *Sym, sym_to_primitive: *Sym, sym_to_string_tag: *Sym, sym_species: *Sym,
    sym_async_iterator: *Sym, sym_is_concat_spreadable: *Sym, sym_unscopables: *Sym, sym_match: *Sym, sym_replace: *Sym,
    sym_search: *Sym, sym_split: *Sym, sym_match_all: *Sym, registry: list.List[*Sym], message: str, host: *void, hole: *Sym, eval_fn: *Obj, last: *Obj, rng_state: u64, next_object: u64, jobs: list.List[Job], promise_ctor: *Obj, regexp_ctor: *Obj, array_buffer_ctor: *Obj, last_abstract: *Obj, ta_ctors: [12]*Obj, ta_protos: [12]*Obj, last_print: str, quiet: bool
}

fn null_interp() -> *Interp {
    var none: *Interp = zero
    ret none
}

fn undefv() -> Value {
    var v: Value = .Undefined
    ret v
}
fn null_value() -> Value {
    var v: Value = .Null
    ret v
}
fn bool_value(b: bool) -> Value { ret Value { Bool: b } }
fn num_value(n: f64) -> Value { ret Value { Num: n } }
fn str_value(s: str) -> Value { ret Value { Str: s } }
fn obj_value(o: *Obj) -> Value { ret Value { Obj: o } }

fn is_undefined(v: Value) -> bool {
    switch v {
    case .Undefined:
        ret true
    default:
        ret false
    }
}

fn is_null(v: Value) -> bool {
    switch v {
    case .Null:
        ret true
    default:
        ret false
    }
}

fn is_nullish(v: Value) -> bool {
    switch v {
    case .Undefined:
        ret true
    case .Null:
        ret true
    default:
        ret false
    }
}

fn is_object(v: Value) -> bool {
    switch v {
    case .Obj as o:
        ret true
    default:
        ret false
    }
}

fn is_number(v: Value) -> bool {
    switch v {
    case .Num as n:
        ret true
    default:
        ret false
    }
}

fn is_string(v: Value) -> bool {
    switch v {
    case .Str as s:
        ret true
    default:
        ret false
    }
}

fn as_object(v: Value) -> *Obj {
    switch v {
    case .Obj as o:
        ret o
    default:
        var none: *Obj = zero
        ret none
    }
}

fn null_obj() -> *Obj {
    var none: *Obj = zero
    ret none
}

fn null_sym() -> *Sym {
    var none: *Sym = zero
    ret none
}

fn is_callable(v: Value) -> bool {
    switch v {
    case .Obj as o:
        ret o.class == C_FUNCTION || o.class == C_BOUND || (o.class == C_PROXY && o.num == 1.0f64)
    default:
        ret false
    }
}

fn is_array(v: Value) -> bool {
    switch v {
    case .Obj as o:
        ret o.class == C_ARRAY
    default:
        ret false
    }
}

// --- numbers

fn is_nan(x: f64) -> bool { ret x != x }

fn is_finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

fn is_infinite(x: f64) -> bool { ret x == x && x - x != 0.0f64 }

fn nan() -> f64 {
    var z = 0.0f64
    ret z / z
}

fn infinity() -> f64 {
    var z = 0.0f64
    ret 1.0f64 / z
}

fn is_neg_zero(x: f64) -> bool { ret x == 0.0f64 && 1.0f64 / x < 0.0f64 }

fn trunc(x: f64) -> f64 {
    if !is_finite(x) { ret x }
    if x >= 9007199254740992.0f64 || x <= -9007199254740992.0f64 { ret x }
    let t = f64(i64(x))
    if t == 0.0f64 && x < 0.0f64 { ret -0.0f64 }
    ret t
}

fn floor(x: f64) -> f64 {
    if !is_finite(x) { ret x }
    if x >= 9007199254740992.0f64 || x <= -9007199254740992.0f64 { ret x }
    var t = f64(i64(x))
    if t > x { t = t - 1.0f64 }
    if t == 0.0f64 && (x < 0.0f64 || is_neg_zero(x)) { ret -0.0f64 }
    ret t
}

// ToIntegerOrInfinity.
fn to_integer(x: f64) -> f64 {
    if is_nan(x) { ret 0.0f64 }
    let t = trunc(x)
    if t == 0.0f64 { ret 0.0f64 }
    ret t
}

// ToInt32 / ToUint32.
fn to_uint32_bits(x: f64) -> u32 {
    if !is_finite(x) { ret 0u32 }
    let t = trunc(x)
    var m = t - floor(t / 4294967296.0f64) * 4294967296.0f64
    if m < 0.0f64 { m = m + 4294967296.0f64 }
    ret u32(i64(m))
}

fn to_int32_value(x: f64) -> i32 {
    let u = to_uint32_bits(x)
    if u >= 2147483648u32 { ret i32(i64(u) - 4294967296i64) }
    ret i32(u)
}

// --- number to string (Number::toString(10))

fn push_digits(b: *str.Builder, s: str) {
    let e = str.push(b, s)
}

fn number_to_string(a: *mem.Arena, x: f64) -> str {
    if is_nan(x) { ret "NaN" }
    if x == 0.0f64 { ret "0" }
    if is_infinite(x) {
        if x < 0.0f64 { ret "-Infinity" }
        ret "Infinity"
    }
    let (b0, be) = str.builder(a, 48usize)
    if be != ok { ret "" }
    var raw = b0
    let pe = str.push_f64(&raw, x)
    let text = str.done(&raw)
    // Extract sign, the digit string and the decimal exponent n (value = 0.DIGITS x 10^n).
    var neg = false
    var at = 0usize
    if text.len > 0usize && text[0usize] == 45u8 {
        neg = true
        at = 1usize
    }
    let (db, dbe) = str.builder(a, text.len + 8usize)
    if dbe != ok { ret "" }
    var digits = db
    var point = -1i64
    var exp10 = 0i64
    var count = 0i64
    var i = at
    var seen_exp = false
    while i < text.len {
        let c = text[i]
        if seen_exp {
            // exponent digits
            i += 1usize
        } else if c >= 48u8 && c <= 57u8 {
            let de = str.push_byte(&digits, c)
            count += 1i64
            i += 1usize
        } else if c == 46u8 {
            point = count
            i += 1usize
        } else if c == 101u8 || c == 69u8 {
            seen_exp = true
            i += 1usize
            var eneg = false
            if i < text.len && (text[i] == 43u8 || text[i] == 45u8) {
                eneg = text[i] == 45u8
                i += 1usize
            }
            var ev = 0i64
            while i < text.len && text[i] >= 48u8 && text[i] <= 57u8 {
                ev = ev * 10i64 + i64(text[i] - 48u8)
                i += 1usize
            }
            if eneg { ev = -ev }
            exp10 = ev
        } else {
            i += 1usize
        }
    }
    var ds = str.done(&digits)
    if point < 0i64 { point = count }
    var n = point + exp10
    // Strip leading zeros (each lowers n) and trailing zeros.
    var lead = 0usize
    while lead + 1usize < ds.len && ds[lead] == 48u8 {
        lead += 1usize
        n -= 1i64
    }
    var tail = ds.len
    while tail > lead + 1usize && ds[tail - 1usize] == 48u8 { tail -= 1usize }
    ds = ds[lead..tail]
    let k = i64(ds.len)
    let (ob, obe) = str.builder(a, 40usize)
    if obe != ok { ret "" }
    var out = ob
    if neg { let pe2 = str.push_byte(&out, 45u8) }
    if k <= n && n <= 21i64 {
        push_digits(&out, ds)
        var z = n - k
        while z > 0i64 {
            let pz = str.push_byte(&out, 48u8)
            z -= 1i64
        }
    } else if 0i64 < n && n <= 21i64 {
        push_digits(&out, ds[0usize..usize(n)])
        let pd = str.push_byte(&out, 46u8)
        push_digits(&out, ds[usize(n)..])
    } else if -6i64 < n && n <= 0i64 {
        push_digits(&out, "0.")
        var z2 = -n
        while z2 > 0i64 {
            let pz2 = str.push_byte(&out, 48u8)
            z2 -= 1i64
        }
        push_digits(&out, ds)
    } else {
        let e = n - 1i64
        let pf = str.push_byte(&out, ds[0usize])
        if k > 1i64 {
            let pd2 = str.push_byte(&out, 46u8)
            push_digits(&out, ds[1usize..])
        }
        let pe3 = str.push_byte(&out, 101u8)
        if e >= 0i64 { let ps = str.push_byte(&out, 43u8) } else { let pm = str.push_byte(&out, 45u8) }
        var ev2 = e
        if ev2 < 0i64 { ev2 = -ev2 }
        let pi = str.push_i64(&out, ev2)
    }
    ret str.done(&out)
}

// StringToNumber.
fn is_js_space(c: u8) -> bool { ret c == 32u8 || (c >= 9u8 && c <= 13u8) }

// The whitespace byte length at the start of `s` (ASCII, NBSP, BOM, line/paragraph separators, other Zs), or 0.
fn space_len(s: str, at: usize) -> usize {
    if at >= s.len { ret 0usize }
    let c = s[at]
    if is_js_space(c) { ret 1usize }
    if c == 194u8 && at + 1usize < s.len && s[at + 1usize] == 160u8 { ret 2usize }
    if c == 239u8 && at + 2usize < s.len && s[at + 1usize] == 187u8 && s[at + 2usize] == 191u8 { ret 3usize }
    if c == 225u8 && at + 2usize < s.len && s[at + 1usize] == 154u8 && s[at + 2usize] == 128u8 { ret 3usize }
    if c == 226u8 && at + 2usize < s.len && s[at + 1usize] == 128u8 && ((s[at + 2usize] >= 128u8 && s[at + 2usize] <= 138u8) || s[at + 2usize] == 168u8 || s[at + 2usize] == 169u8 || s[at + 2usize] == 175u8) { ret 3usize }
    if c == 226u8 && at + 2usize < s.len && s[at + 1usize] == 129u8 && s[at + 2usize] == 159u8 { ret 3usize }
    if c == 227u8 && at + 2usize < s.len && s[at + 1usize] == 128u8 && s[at + 2usize] == 128u8 { ret 3usize }
    ret 0usize
}

fn trim_js(s: str) -> str {
    var start = 0usize
    while start < s.len {
        let n = space_len(s, start)
        if n == 0usize { break }
        start += n
    }
    var end = s.len
    while end > start {
        // Step back over one whitespace unit.
        var found = false
        var w = 1usize
        while w <= 3usize && w <= end - start {
            if space_len(s, end - w) == w {
                end -= w
                found = true
                break
            }
            w += 1usize
        }
        if !found { break }
    }
    ret s[start..end]
}

fn digit_value(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret i32(c) - 48i32 }
    if c >= 97u8 && c <= 122u8 { ret i32(c) - 87i32 }
    if c >= 65u8 && c <= 90u8 { ret i32(c) - 55i32 }
    ret -1i32
}

fn string_to_number(a: *mem.Arena, input: str) -> f64 {
    let s = trim_js(input)
    if s.len == 0usize { ret 0.0f64 }
    if s.len > 2usize && s[0usize] == 48u8 && (s[1usize] == 120u8 || s[1usize] == 88u8 || s[1usize] == 111u8 || s[1usize] == 79u8 || s[1usize] == 98u8 || s[1usize] == 66u8) {
        var radix = 16i32
        if s[1usize] == 111u8 || s[1usize] == 79u8 { radix = 8i32 }
        if s[1usize] == 98u8 || s[1usize] == 66u8 { radix = 2i32 }
        var v = 0.0f64
        var i = 2usize
        while i < s.len {
            let d = digit_value(s[i])
            if d < 0i32 || d >= radix { ret nan() }
            v = v * f64(radix) + f64(d)
            i += 1usize
        }
        ret v
    }
    var at = 0usize
    var neg = false
    if s[0usize] == 43u8 || s[0usize] == 45u8 {
        neg = s[0usize] == 45u8
        at = 1usize
    }
    let rest = s[at..]
    if str.eq(rest, "Infinity") {
        if neg { ret -infinity() }
        ret infinity()
    }
    // Decimal literal: digits [. digits] [e[+-]digits], at least one digit in the mantissa.
    var i2 = 0usize
    var mant = 0usize
    while i2 < rest.len && rest[i2] >= 48u8 && rest[i2] <= 57u8 {
        i2 += 1usize
        mant += 1usize
    }
    if i2 < rest.len && rest[i2] == 46u8 {
        i2 += 1usize
        while i2 < rest.len && rest[i2] >= 48u8 && rest[i2] <= 57u8 {
            i2 += 1usize
            mant += 1usize
        }
    }
    if mant == 0usize { ret nan() }
    if i2 < rest.len && (rest[i2] == 101u8 || rest[i2] == 69u8) {
        i2 += 1usize
        if i2 < rest.len && (rest[i2] == 43u8 || rest[i2] == 45u8) { i2 += 1usize }
        var ed = 0usize
        while i2 < rest.len && rest[i2] >= 48u8 && rest[i2] <= 57u8 {
            i2 += 1usize
            ed += 1usize
        }
        if ed == 0usize { ret nan() }
    }
    if i2 != rest.len { ret nan() }
    var text = rest
    if text[0usize] == 46u8 {
        let (fixed, fe) = str.concat(a, "0", text)
        if fe == ok { text = fixed }
    }
    let (dot_e, has_dot_e) = str.find(text, ".e")
    if has_dot_e {
        let (left, le) = str.concat(a, text[0usize..dot_e], text[dot_e + 1usize..])
        if le == ok { text = left }
    }
    let (dot_E, has_dot_E) = str.find(text, ".E")
    if has_dot_E {
        let (left2, le2) = str.concat(a, text[0usize..dot_E], text[dot_E + 1usize..])
        if le2 == ok { text = left2 }
    }
    if text.len > 0usize && text[text.len - 1usize] == 46u8 { text = text[0usize..text.len - 1usize] }
    // `parse_f64` spells the exponent marker with a lowercase `e` only.
    let (upper_e, has_upper_e) = str.find(text, "E")
    if has_upper_e {
        let (lb, lbe) = str.builder(a, text.len + 1usize)
        if lbe == ok {
            var lo = lb
            var li = 0usize
            while li < text.len {
                if text[li] == 69u8 { let pl = str.push_byte(&lo, 101u8) } else { let pl2 = str.push_byte(&lo, text[li]) }
                li += 1usize
            }
            text = str.done(&lo)
        }
    }
    var (v2, pe) = str.parse_f64(text)
    if pe != ok {
        let (epos, has_e) = str.find(text, "e")
        let (epos2, has_E) = str.find(text, "E")
        if !has_e && !has_E { ret nan() }
        var at_e = epos
        if !has_e { at_e = epos2 }
        if at_e + 1usize < text.len && text[at_e + 1usize] == 45u8 { v2 = 0.0f64 } else { v2 = infinity() }
    }
    if neg { ret -v2 }
    ret v2
}

// --- strings: UTF-16 view of a UTF-8 string

fn is_ascii(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        if s[i] >= 128u8 { ret false }
        i += 1usize
    }
    ret true
}

// The code point at byte `at` and its byte length.
fn decode_at(s: str, at: usize) -> (u32, usize) {
    let c = s[at]
    if c < 128u8 { ret (u32(c), 1usize) }
    if c >= 240u8 && at + 3usize < s.len { ret (((u32(c) & 7u32) << 18u32) | ((u32(s[at + 1usize]) & 63u32) << 12u32) | ((u32(s[at + 2usize]) & 63u32) << 6u32) | (u32(s[at + 3usize]) & 63u32), 4usize) }
    if c >= 224u8 && at + 2usize < s.len { ret (((u32(c) & 15u32) << 12u32) | ((u32(s[at + 1usize]) & 63u32) << 6u32) | (u32(s[at + 2usize]) & 63u32), 3usize) }
    if c >= 192u8 && at + 1usize < s.len { ret (((u32(c) & 31u32) << 6u32) | (u32(s[at + 1usize]) & 63u32), 2usize) }
    ret (65533u32, 1usize)
}

// Length in UTF-16 code units.
fn units(s: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] < 128u8 {
            n += 1usize
            i += 1usize
        } else {
            let (cp, l) = decode_at(s, i)
            if cp >= 65536u32 { n += 2usize } else { n += 1usize }
            i += l
        }
    }
    ret n
}

// The UTF-16 code unit at unit index `idx` (ok false past the end).
fn unit_at(s: str, idx: usize) -> (u32, bool) {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] < 128u8 {
            if n == idx { ret (u32(s[i]), true) }
            n += 1usize
            i += 1usize
        } else {
            let (cp, l) = decode_at(s, i)
            if cp >= 65536u32 {
                let v = cp - 65536u32
                if n == idx { ret (55296u32 + (v >> 10u32), true) }
                if n + 1usize == idx { ret (56320u32 + (v & 1023u32), true) }
                n += 2usize
            } else {
                if n == idx { ret (cp, true) }
                n += 1usize
            }
            i += l
        }
    }
    ret (0u32, false)
}

// The byte offset of unit index `idx` (s.len at the end; a unit inside a surrogate pair maps to the pair's start).
fn byte_of_unit(s: str, idx: usize) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if n >= idx { ret i }
        if s[i] < 128u8 {
            n += 1usize
            i += 1usize
        } else {
            let (cp, l) = decode_at(s, i)
            if cp >= 65536u32 { n += 2usize } else { n += 1usize }
            i += l
        }
    }
    ret s.len
}

fn put_cp(b: *str.Builder, c: u32) {
    var e: err = ok
    if c < 128u32 {
        e = str.push_byte(b, u8(c))
    } else if c < 2048u32 {
        e = str.push_byte(b, u8(192u32 | (c >> 6u32)))
        e = str.push_byte(b, u8(128u32 | (c & 63u32)))
    } else if c < 65536u32 {
        e = str.push_byte(b, u8(224u32 | (c >> 12u32)))
        e = str.push_byte(b, u8(128u32 | ((c >> 6u32) & 63u32)))
        e = str.push_byte(b, u8(128u32 | (c & 63u32)))
    } else {
        e = str.push_byte(b, u8(240u32 | (c >> 18u32)))
        e = str.push_byte(b, u8(128u32 | ((c >> 12u32) & 63u32)))
        e = str.push_byte(b, u8(128u32 | ((c >> 6u32) & 63u32)))
        e = str.push_byte(b, u8(128u32 | (c & 63u32)))
    }
}

// The substring covering UTF-16 units [from, to).
fn substring_units(a: *mem.Arena, s: str, from: usize, to: usize) -> str {
    if from >= to { ret "" }
    if is_ascii(s) {
        if to > s.len { ret s[from..] }
        ret s[from..to]
    }
    let (b, be) = str.builder(a, s.len + 4usize)
    if be != ok { ret "" }
    var out = b
    var n = 0usize
    var i = 0usize
    while i < s.len && n < to {
        let (cp, l) = decode_at(s, i)
        if cp >= 65536u32 {
            let v = cp - 65536u32
            if n >= from && n < to { put_cp(&out, 55296u32 + (v >> 10u32)) }
            if n + 1usize >= from && n + 1usize < to { put_cp(&out, 56320u32 + (v & 1023u32)) }
            n += 2usize
        } else {
            if n >= from && n < to { put_cp(&out, cp) }
            n += 1usize
        }
        i += l
    }
    ret str.done(&out)
}

// --- keys

// The canonical array index spelled by `s` (-1 when it is not one).
fn array_index_of(s: str) -> i64 {
    if s.len == 0usize || s.len > 10usize { ret -1i64 }
    if s[0usize] == 48u8 {
        if s.len == 1usize { ret 0i64 }
        ret -1i64
    }
    var v = 0i64
    var i = 0usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret -1i64 }
        v = v * 10i64 + i64(s[i] - 48u8)
        i += 1usize
    }
    if v >= 4294967295i64 { ret -1i64 }
    ret v
}

fn key_of(s: str) -> Key { ret Key { name: s, sym: null_sym(), idx: array_index_of(s) } }

fn key_of_symbol(s: *Sym) -> Key { ret Key { name: "", sym: s, idx: -1i64 } }

fn is_symbol_key(k: Key) -> bool {
    let z = null_sym()
    ret k.sym != z
}

fn keys_equal(x: Key, y: Key) -> bool {
    let z = null_sym()
    if x.sym != z || y.sym != z { ret x.sym == y.sym }
    ret str.eq(x.name, y.name)
}

// Strict equality of two values.
fn strict_equals(x: Value, y: Value) -> bool {
    switch x {
    case .Undefined:
        ret is_undefined(y)
    case .Null:
        ret is_null(y)
    case .Bool as bx:
        switch y {
        case .Bool as by:
            ret bx == by
        default:
            ret false
        }
    case .Num as nx:
        switch y {
        case .Num as ny:
            ret nx == ny
        default:
            ret false
        }
    case .Str as sx:
        switch y {
        case .Str as sy:
            ret str.eq(sx, sy)
        default:
            ret false
        }
    case .Sym as ysx:
        switch y {
        case .Sym as ysy:
            ret ysx == ysy
        default:
            ret false
        }
    case .Obj as ox:
        switch y {
        case .Obj as oy:
            ret ox == oy
        default:
            ret false
        }
    }
    ret false
}

// SameValueZero (`includes`, Map keys) and SameValue (`Object.is`).
fn same_value_zero(x: Value, y: Value) -> bool {
    switch x {
    case .Num as nx:
        switch y {
        case .Num as ny:
            if is_nan(nx) && is_nan(ny) { ret true }
            ret nx == ny
        default:
            ret false
        }
    default:
        ret strict_equals(x, y)
    }
}

fn same_value(x: Value, y: Value) -> bool {
    switch x {
    case .Num as nx:
        switch y {
        case .Num as ny:
            if is_nan(nx) && is_nan(ny) { ret true }
            if nx == 0.0f64 && ny == 0.0f64 { ret is_neg_zero(nx) == is_neg_zero(ny) }
            ret nx == ny
        default:
            ret false
        }
    default:
        ret strict_equals(x, y)
    }
}

fn to_boolean(v: Value) -> bool {
    switch v {
    case .Undefined:
        ret false
    case .Null:
        ret false
    case .Bool as b:
        ret b
    case .Num as n:
        ret !(n == 0.0f64 || is_nan(n))
    case .Str as s:
        ret s.len > 0usize
    case .Sym as sy:
        ret true
    case .Obj as o:
        ret true
    }
    ret false
}

fn type_of(v: Value) -> str {
    switch v {
    case .Undefined:
        ret "undefined"
    case .Null:
        ret "object"
    case .Bool as b:
        ret "boolean"
    case .Num as n:
        ret "number"
    case .Str as s:
        ret "string"
    case .Sym as sy:
        ret "symbol"
    case .Obj as o:
        if is_callable(v) { ret "function" }
        ret "object"
    }
    ret "undefined"
}

// --- errors

// Throws `v`: records it in the interpreter and answers the `Throw` error.
fn throw_value(it: *Interp, v: Value) -> err {
    it.thrown = v
    ret Throw
}

fn new_obj(it: *Interp, class: u8, proto: *Obj) -> *Obj {
    let (cell, ce) = mem.alloc[Obj](it.a, 1usize)
    if ce != ok {
        var none: *Obj = zero
        ret none
    }
    var blank: Obj = zero
    cell[0usize] = blank
    let o = &cell[0usize]
    o.class = class
    o.proto = proto
    it.next_object += 1u64
    o.id = it.next_object
    let z = null_obj()
    o.has_proto = proto != z
    o.extensible = true
    let (props, pe) = list.init[Prop](it.a, 0usize)
    o.props = props
    let (elems, ee) = list.init[Value](it.a, 0usize)
    o.elems = elems
    o.prim = undefv()
    o.this_val = undefv()
    o.bound_this = undefv()
    o.home = z
    o.bound_target = z
    o.fields = z
    o.aux = z
    ret o
}

fn new_plain(it: *Interp) -> *Obj { ret new_obj(it, C_OBJECT, it.protos.object) }

fn make_error(it: *Interp, proto: *Obj, message: str) -> Value {
    let o = new_obj(it, C_ERROR, proto)
    let z = null_obj()
    if o == z { ret undefv() }
    let key = key_of("message")
    let e = define_data(it, o, key, str_value(message), P_HIDDEN)
    ret obj_value(o)
}

fn throw_type(it: *Interp, message: str) -> err { ret throw_value(it, make_error(it, it.protos.type_error, message)) }
fn throw_range(it: *Interp, message: str) -> err { ret throw_value(it, make_error(it, it.protos.range_error, message)) }
fn throw_reference(it: *Interp, message: str) -> err { ret throw_value(it, make_error(it, it.protos.reference_error, message)) }
fn throw_syntax(it: *Interp, message: str) -> err { ret throw_value(it, make_error(it, it.protos.syntax_error, message)) }
fn throw_plain(it: *Interp, message: str) -> err { ret throw_value(it, make_error(it, it.protos.error_proto, message)) }

fn new_symbol(it: *Interp, description: str, has: bool) -> *Sym {
    let (cell, ce) = mem.alloc[Sym](it.a, 1usize)
    if ce != ok { ret null_sym() }
    var blank: Sym = zero
    cell[0usize] = blank
    let s = &cell[0usize]
    s.description = description
    s.has_description = has
    it.next_symbol += 1u32
    s.id = it.next_symbol
    ret s
}

fn hole_value(it: *Interp) -> Value { ret Value { Sym: it.hole } }

fn is_hole(it: *Interp, v: Value) -> bool {
    switch v {
    case .Sym as s:
        ret s == it.hole
    default:
        ret false
    }
}

// --- own properties

fn index_of_prop(o: *const Obj, key: Key) -> (usize, bool) {
    var i = 0usize
    if o.indexed && !is_symbol_key(key) {
        let (at, found) = map.get[str, usize](&o.index, key.name)
        if found { ret (at, true) }
        // Symbol-keyed and string-keyed properties share the list; the index only holds string keys.
        ret (0usize, false)
    }
    while i < o.props.len {
        if keys_equal(o.props.items[i].key, key) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn rebuild_index(it: *Interp, o: *Obj) {
    let (m, me) = map.init[str, usize](it.a, o.props.len * 2usize + 8usize)
    if me != ok { ret }
    o.index = m
    var i = 0usize
    while i < o.props.len {
        if !is_symbol_key(o.props.items[i].key) {
            let (r, pe) = map.put[str, usize](&o.index, o.props.items[i].key.name, i)
        }
        i += 1usize
    }
    o.indexed = true
}

fn append_prop(it: *Interp, o: *Obj, p: Prop) -> err {
    try list.push[Prop](&o.props, p)
    if o.indexed {
        if !is_symbol_key(p.key) {
            let (r, pe) = map.put[str, usize](&o.index, p.key.name, o.props.len - 1usize)
        }
    } else if o.props.len > 12usize {
        rebuild_index(it, o)
    }
    ret ok
}

fn remove_prop_at(it: *Interp, o: *Obj, at: usize) {
    var i = at
    while i + 1usize < o.props.len {
        o.props.items[i] = o.props.items[i + 1usize]
        i += 1usize
    }
    o.props.len -= 1usize
    if o.indexed { rebuild_index(it, o) }
}

// Defines (or overwrites) an own data property directly, with no checks.
fn define_data(it: *Interp, o: *Obj, key: Key, val: Value, flags: u8) -> err {
    let (at, found) = index_of_prop(o, key)
    let z = null_obj()
    if found {
        o.props.items[at].value = val
        o.props.items[at].flags = flags
        o.props.items[at].getter = z
        o.props.items[at].setter = z
        ret ok
    }
    let p = Prop { key: key, value: val, getter: z, setter: z, flags: flags }
    ret append_prop(it, o, p)
}

fn define_accessor_raw(it: *Interp, o: *Obj, key: Key, getter: *Obj, setter: *Obj, flags: u8) -> err {
    let (at, found) = index_of_prop(o, key)
    if found {
        o.props.items[at].value = undefv()
        o.props.items[at].getter = getter
        o.props.items[at].setter = setter
        o.props.items[at].flags = flags | P_ACCESSOR
        ret ok
    }
    let p = Prop { key: key, value: undefv(), getter: getter, setter: setter, flags: flags | P_ACCESSOR }
    ret append_prop(it, o, p)
}

fn set_named(it: *Interp, o: *Obj, name: str, val: Value) -> err { ret define_data(it, o, key_of(name), val, P_DEFAULT) }
fn set_hidden(it: *Interp, o: *Obj, name: str, val: Value) -> err { ret define_data(it, o, key_of(name), val, P_HIDDEN) }

// --- arrays

fn new_array(it: *Interp) -> *Obj {
    let o = new_obj(it, C_ARRAY, it.protos.array)
    ret o
}

fn array_length(o: *const Obj) -> f64 {
    if o.num < f64(o.elems.len) { ret f64(o.elems.len) }
    ret o.num
}

fn array_push(it: *Interp, o: *Obj, v: Value) -> err {
    try list.push[Value](&o.elems, v)
    if o.num < f64(o.elems.len) { o.num = f64(o.elems.len) }
    ret ok
}

fn array_from(it: *Interp, items: []const Value) -> *Obj {
    let o = new_array(it)
    var i = 0usize
    while i < items.len {
        let pe = array_push(it, o, items[i])
        i += 1usize
    }
    ret o
}

// Sets the array length, dropping elements at or past it.
fn array_set_length(it: *Interp, o: *Obj, len: f64) {
    if len < f64(o.elems.len) { o.elems.len = usize(len) }
    // Generic index properties at or past the new length go too.
    var i = 0usize
    while i < o.props.len {
        let k = o.props.items[i].key
        if k.idx >= 0i64 && f64(k.idx) >= len {
            remove_prop_at(it, o, i)
        } else {
            i += 1usize
        }
    }
    o.num = len
}

// The own property `key` of `o`, with exotic objects (arrays, strings, arguments) synthesised.
fn get_own(it: *Interp, o: *Obj, key: Key) -> (Prop, bool) {
    let z = null_obj()
    if o.class == C_ARRAY || o.class == C_ARGUMENTS {
        if key.idx >= 0i64 && key.idx < i64(o.elems.len) {
            let ev = o.elems.items[usize(key.idx)]
            if is_hole(it, ev) {
                ret (zero, false)
            }
            ret (Prop { key: key, value: ev, getter: z, setter: z, flags: P_DEFAULT }, true)
        }
        if o.class == C_ARRAY && !is_symbol_key(key) && str.eq(key.name, "length") {
            var lf = P_WRITABLE
            if o.text.len == 1usize { lf = 0u8 }
            ret (Prop { key: key, value: num_value(array_length(o)), getter: z, setter: z, flags: lf }, true)
        }
    }
    if o.class == C_TYPEDARRAY && !is_symbol_key(key) {
        let (is_num, nv) = numeric_index(it, key.name)
        if is_num {
            if ta_valid_index(o, nv) { ret (Prop { key: key, value: ta_get_index(it, o, usize(nv)), getter: z, setter: z, flags: P_DEFAULT }, true) }
            ret (zero, false)
        }
    }
    if o.class == C_STRING && !is_symbol_key(key) {
        let s = prim_string(o)
        if key.idx >= 0i64 {
            let (u, has) = unit_at(s, usize(key.idx))
            if has {
                let sub = substring_units(it.a, s, usize(key.idx), usize(key.idx) + 1usize)
                ret (Prop { key: key, value: str_value(sub), getter: z, setter: z, flags: P_ENUMERABLE }, true)
            }
        }
        if str.eq(key.name, "length") {
            ret (Prop { key: key, value: num_value(f64(units(s))), getter: z, setter: z, flags: 0u8 }, true)
        }
    }
    let (at, found) = index_of_prop(o, key)
    if found { ret (o.props.items[at], true) }
    ret (zero, false)
}

fn prim_string(o: *const Obj) -> str {
    switch o.prim {
    case .Str as s:
        ret s
    default:
        ret ""
    }
}

// --- property access with prototype chain, accessors and primitives

fn proto_of(o: *const Obj) -> (*Obj, bool) {
    if o.has_proto { ret (o.proto, true) }
    ret (null_obj(), false)
}

// [[Get]]: walks the prototype chain; accessors run with `receiver` as `this`.
fn get_prop(it: *Interp, o: *Obj, key: Key, receiver: Value) -> (Value, err) {
    it.steps += 1u64
    if it.step_limit != 0u64 && it.steps > it.step_limit { ret (undefv(), throw_range(it, "execution step limit exceeded")) }
    var cur = o
    var guard = 0u32
    while guard < 100000u32 {
        guard += 1u32
        let (p, found) = get_own(it, cur, key)
        if found {
            if (p.flags & P_ACCESSOR) != 0u8 {
                let z = null_obj()
                if p.getter == z { ret (undefv(), ok) }
                let (r, re) = call_function(it, obj_value(p.getter), receiver, zero_args())
                ret (r, re)
            }
            ret (p.value, ok)
        }
        if cur.class == C_PROXY {
            let (pr, pe) = proxy_get(it, cur, key, receiver)
            ret (pr, pe)
        }
        if cur.class == C_TYPEDARRAY && !is_symbol_key(key) {
            let (is_num, nv) = numeric_index(it, key.name)
            if is_num { ret (undefv(), ok) }
        }
        if !cur.has_proto { ret (undefv(), ok) }
        cur = cur.proto
    }
    ret (undefv(), ok)
}

fn zero_args() -> []const Value {
    var none: []const Value = zero
    ret none
}

fn get_named(it: *Interp, o: *Obj, name: str) -> (Value, err) {
    let (v, e) = get_prop(it, o, key_of(name), obj_value(o))
    ret (v, e)
}

fn proxy_get(it: *Interp, p: *Obj, key: Key, receiver: Value) -> (Value, err) {
    ret (undefv(), throw_type(it, "Proxy is not supported"))
}

// The object a primitive's property lookups start from.
fn proto_for_primitive(it: *Interp, v: Value) -> (*Obj, bool) {
    switch v {
    case .Bool as b:
        ret (it.protos.boolean, true)
    case .Num as n:
        ret (it.protos.number, true)
    case .Str as s:
        ret (it.protos.string, true)
    case .Sym as sy:
        ret (it.protos.symbol, true)
    default:
        ret (null_obj(), false)
    }
}

fn describe_key(it: *Interp, key: Key) -> str {
    if is_symbol_key(key) { ret "symbol" }
    ret key.name
}

// `base[key]` for any base value.
fn get_value(it: *Interp, base: Value, key: Key) -> (Value, err) {
    switch base {
    case .Obj as o:
        let (v, e) = get_prop(it, o, key, base)
        ret (v, e)
    case .Str as s:
        if !is_symbol_key(key) {
            if key.idx >= 0i64 {
                let (u, has) = unit_at(s, usize(key.idx))
                if has { ret (str_value(substring_units(it.a, s, usize(key.idx), usize(key.idx) + 1usize)), ok) }
            } else if str.eq(key.name, "length") {
                ret (num_value(f64(units(s))), ok)
            }
        }
        let (v2, e2) = get_prop(it, it.protos.string, key, base)
        ret (v2, e2)
    case .Undefined:
        ret (undefv(), throw_type(it, str_concat3(it, "Cannot read properties of undefined (reading '", describe_key(it, key), "')")))
    case .Null:
        ret (undefv(), throw_type(it, str_concat3(it, "Cannot read properties of null (reading '", describe_key(it, key), "')")))
    default:
        let (proto, has) = proto_for_primitive(it, base)
        if !has { ret (undefv(), ok) }
        let (v3, e3) = get_prop(it, proto, key, base)
        ret (v3, e3)
    }
    ret (undefv(), ok)
}

fn str_concat3(it: *Interp, x: str, y: str, z: str) -> str {
    let (a1, e1) = str.concat(it.a, x, y)
    if e1 != ok { ret x }
    let (a2, e2) = str.concat(it.a, a1, z)
    if e2 != ok { ret a1 }
    ret a2
}

fn str_concat(it: *Interp, x: str, y: str) -> str {
    if x.len == 0usize { ret y }
    if y.len == 0usize { ret x }
    let (r, e) = str.concat(it.a, x, y)
    if e != ok { ret x }
    ret r
}

// [[Set]]. Answers false when the assignment is rejected (read-only, no setter, frozen); the caller throws in strict code.
fn set_prop(it: *Interp, o: *Obj, key: Key, val: Value, receiver: Value) -> (bool, err) {
    var cur = o
    var guard = 0u32
    while guard < 100000u32 {
        guard += 1u32
        let (p, found) = get_own(it, cur, key)
        if found {
            if (p.flags & P_ACCESSOR) != 0u8 {
                let z = null_obj()
                if p.setter == z { ret (false, ok) }
                let args = one_arg(it, val)
                let (r, re) = call_function(it, obj_value(p.setter), receiver, args)
                if re != ok { ret (false, re) }
                ret (true, ok)
            }
            if (p.flags & P_WRITABLE) == 0u8 { ret (false, ok) }
            // Writable data property: set on the receiver.
            break
        }
        if !cur.has_proto { break }
        cur = cur.proto
    }
    switch receiver {
    case .Obj as ro:
        if ro.class == C_TYPEDARRAY && !is_symbol_key(key) {
            let (is_num2, nv2) = numeric_index(it, key.name)
            if is_num2 {
                let (nn, ne) = to_number(it, val)
                if ne != ok { ret (false, ne) }
                if ta_valid_index(ro, nv2) { ta_set_raw(it, ro, usize(nv2), value_to_raw(ta_of(ro).kind, nn)) }
                ret (true, ok)
            }
        }
        let (existing, has) = get_own(it, ro, key)
        if has {
            if (existing.flags & P_ACCESSOR) != 0u8 { ret (false, ok) }
            if (existing.flags & P_WRITABLE) == 0u8 { ret (false, ok) }
            let (okv, ee) = write_own_value(it, ro, key, val)
            ret (okv, ee)
        }
        if !ro.extensible { ret (false, ok) }
        let (cr, ce) = create_data(it, ro, key, val)
        ret (cr, ce)
    default:
        ret (false, ok)
    }
    ret (false, ok)
}

fn one_arg(it: *Interp, v: Value) -> []const Value {
    let (cell, ce) = mem.alloc[Value](it.a, 1usize)
    if ce != ok { ret zero_args() }
    cell[0usize] = v
    ret cell[0usize..1usize]
}

fn two_args(it: *Interp, x: Value, y: Value) -> []const Value {
    let (cell, ce) = mem.alloc[Value](it.a, 2usize)
    if ce != ok { ret zero_args() }
    cell[0usize] = x
    cell[1usize] = y
    ret cell[0usize..2usize]
}

// Writes the value of an existing own data property (array elements and `length` included).
fn write_own_value(it: *Interp, o: *Obj, key: Key, val: Value) -> (bool, err) {
    if o.class == C_ARRAY || o.class == C_ARGUMENTS {
        if key.idx >= 0i64 && key.idx < i64(o.elems.len) {
            o.elems.items[usize(key.idx)] = val
            ret (true, ok)
        }
        if o.class == C_ARRAY && !is_symbol_key(key) && str.eq(key.name, "length") {
            let (n, ne) = to_number(it, val)
            if ne != ok { ret (false, ne) }
            let len = to_uint32_bits(n)
            if f64(len) != n { ret (false, throw_range(it, "Invalid array length")) }
            if o.text.len == 1usize { ret (false, ok) }
            array_set_length(it, o, f64(len))
            ret (true, ok)
        }
    }
    let (at, found) = index_of_prop(o, key)
    if found {
        o.props.items[at].value = val
        ret (true, ok)
    }
    ret (false, ok)
}

// Creates a new own enumerable/writable/configurable data property (array growth handled).
fn create_data(it: *Interp, o: *Obj, key: Key, val: Value) -> (bool, err) {
    if o.class == C_ARRAY || o.class == C_ARGUMENTS {
        if key.idx >= 0i64 {
            let idx = usize(key.idx)
            if o.class == C_ARRAY && o.text.len == 1usize && f64(key.idx) >= array_length(o) { ret (false, ok) }
            if idx == o.elems.len {
                try list.push[Value](&o.elems, val)
                if o.class == C_ARRAY && o.num < f64(o.elems.len) { o.num = f64(o.elems.len) }
                ret (true, ok)
            }
            if idx > o.elems.len && idx < o.elems.len + 4096usize {
                while o.elems.len < idx { try list.push[Value](&o.elems, hole_value(it)) }
                try list.push[Value](&o.elems, val)
                if o.class == C_ARRAY && o.num < f64(o.elems.len) { o.num = f64(o.elems.len) }
                ret (true, ok)
            }
            if o.class == C_ARRAY && f64(key.idx) >= o.num { o.num = f64(key.idx) + 1.0f64 }
        }
    }
    let z = null_obj()
    try append_prop(it, o, Prop { key: key, value: val, getter: z, setter: z, flags: P_DEFAULT })
    ret (true, ok)
}

// `o[key] = val`, throwing a TypeError when rejected and `strict`.
fn put(it: *Interp, base: Value, key: Key, val: Value, strict: bool) -> err {
    switch base {
    case .Obj as o:
        let (done, e) = set_prop(it, o, key, val, base)
        if e != ok { ret e }
        if !done && strict { ret throw_type(it, str_concat3(it, "Cannot assign to read only property '", describe_key(it, key), "'")) }
        ret ok
    case .Undefined:
        ret throw_type(it, str_concat3(it, "Cannot set properties of undefined (setting '", describe_key(it, key), "')"))
    case .Null:
        ret throw_type(it, str_concat3(it, "Cannot set properties of null (setting '", describe_key(it, key), "')"))
    default:
        // A primitive: setters on the prototype chain still run.
        let (proto, has) = proto_for_primitive(it, base)
        if has {
            let (done2, e2) = set_prop(it, proto, key, val, base)
            if e2 != ok { ret e2 }
            if !done2 && strict { ret throw_type(it, "Cannot create property on a primitive") }
        }
        ret ok
    }
    ret ok
}

fn has_own(it: *Interp, o: *Obj, key: Key) -> bool {
    let (p, found) = get_own(it, o, key)
    ret found
}

fn has_property(it: *Interp, o: *Obj, key: Key) -> bool {
    var cur = o
    var guard = 0u32
    while guard < 100000u32 {
        guard += 1u32
        let (p, found) = get_own(it, cur, key)
        if found { ret true }
        if cur.class == C_TYPEDARRAY && !is_symbol_key(key) {
            let (is_num, nv) = numeric_index(it, key.name)
            if is_num { ret false }
        }
        if !cur.has_proto { ret false }
        cur = cur.proto
    }
    ret false
}

fn delete_prop(it: *Interp, o: *Obj, key: Key) -> bool {
    if o.class == C_TYPEDARRAY && !is_symbol_key(key) {
        let (is_num, nv) = numeric_index(it, key.name)
        if is_num { ret !ta_valid_index(o, nv) }
    }
    if o.class == C_ARRAY || o.class == C_ARGUMENTS {
        if key.idx >= 0i64 && key.idx < i64(o.elems.len) {
            if o.class == C_ARRAY && o.text.len == 1usize { ret false }
            if usize(key.idx) + 1usize == o.elems.len && o.class != C_ARRAY {
                o.elems.len -= 1usize
            } else {
                o.elems.items[usize(key.idx)] = hole_value(it)
            }
            ret true
        }
        if o.class == C_ARRAY && !is_symbol_key(key) && str.eq(key.name, "length") { ret false }
    }
    if o.class == C_STRING && !is_symbol_key(key) {
        let s = prim_string(o)
        if key.idx >= 0i64 && key.idx < i64(units(s)) { ret false }
        if str.eq(key.name, "length") { ret false }
    }
    let (at, found) = index_of_prop(o, key)
    if !found { ret true }
    if (o.props.items[at].flags & P_CONFIGURABLE) == 0u8 { ret false }
    remove_prop_at(it, o, at)
    ret true
}

// --- property descriptors

type Desc = struct {
    value: Value, has_value: bool, getter: Value, has_get: bool, setter: Value, has_set: bool,
    writable: bool, has_writable: bool, enumerable: bool, has_enumerable: bool, configurable: bool, has_configurable: bool
}

fn empty_desc() -> Desc {
    ret Desc { value: undefv(), has_value: false, getter: undefv(), has_get: false, setter: undefv(), has_set: false, writable: false, has_writable: false, enumerable: false, has_enumerable: false, configurable: false, has_configurable: false }
}

fn data_desc(val: Value, flags: u8) -> Desc {
    var d = empty_desc()
    d.value = val
    d.has_value = true
    d.writable = (flags & P_WRITABLE) != 0u8
    d.has_writable = true
    d.enumerable = (flags & P_ENUMERABLE) != 0u8
    d.has_enumerable = true
    d.configurable = (flags & P_CONFIGURABLE) != 0u8
    d.has_configurable = true
    ret d
}

fn prop_to_desc(p: Prop) -> Desc {
    var d = empty_desc()
    d.has_enumerable = true
    d.enumerable = (p.flags & P_ENUMERABLE) != 0u8
    d.has_configurable = true
    d.configurable = (p.flags & P_CONFIGURABLE) != 0u8
    if (p.flags & P_ACCESSOR) != 0u8 {
        let z = null_obj()
        d.has_get = true
        d.has_set = true
        if p.getter != z { d.getter = obj_value(p.getter) }
        if p.setter != z { d.setter = obj_value(p.setter) }
    } else {
        d.has_value = true
        d.value = p.value
        d.has_writable = true
        d.writable = (p.flags & P_WRITABLE) != 0u8
    }
    ret d
}

// ValidateAndApplyPropertyDescriptor over an ordinary or array object. Answers false when the change is not allowed.
fn define_own(it: *Interp, o: *Obj, key: Key, d: Desc) -> (bool, err) {
    let z = null_obj()
    if o.class == C_TYPEDARRAY && !is_symbol_key(key) {
        let (is_num, nv) = numeric_index(it, key.name)
        if is_num {
            if !ta_valid_index(o, nv) { ret (false, ok) }
            if d.has_configurable && !d.configurable { ret (false, ok) }
            if d.has_enumerable && !d.enumerable { ret (false, ok) }
            if d.has_get || d.has_set { ret (false, ok) }
            if d.has_writable && !d.writable { ret (false, ok) }
            if d.has_value {
                let (nn, ne) = to_number(it, d.value)
                if ne != ok { ret (false, ne) }
                if ta_valid_index(o, nv) { ta_set_raw(it, o, usize(nv), value_to_raw(ta_of(o).kind, nn)) }
            }
            ret (true, ok)
        }
    }
    // Array exotics: `length` and index growth.
    if o.class == C_ARRAY && !is_symbol_key(key) && str.eq(key.name, "length") {
        if d.has_get || d.has_set { ret (false, ok) }
        if d.has_configurable && d.configurable { ret (false, ok) }
        if d.has_enumerable && d.enumerable { ret (false, ok) }
        if d.has_value {
            let (n, ne) = to_number(it, d.value)
            if ne != ok { ret (false, ne) }
            let len = to_uint32_bits(n)
            if f64(len) != n { ret (false, throw_range(it, "Invalid array length")) }
            if o.text.len == 1usize && f64(len) != array_length(o) { ret (false, ok) }
            if o.text.len != 1usize { array_set_length(it, o, f64(len)) }
        }
        if d.has_writable {
            if d.writable && o.text.len == 1usize { ret (false, ok) }
            if !d.writable { o.text = "1" }
        }
        ret (true, ok)
    }
    let (cur, exists) = get_own(it, o, key)
    if !exists {
        if !o.extensible { ret (false, ok) }
        var flags = 0u8
        if d.has_enumerable && d.enumerable { flags = flags | P_ENUMERABLE }
        if d.has_configurable && d.configurable { flags = flags | P_CONFIGURABLE }
        if d.has_get || d.has_set {
            var g = z
            var s = z
            if d.has_get && is_object(d.getter) { g = as_object(d.getter) }
            if d.has_set && is_object(d.setter) { s = as_object(d.setter) }
            // Array element accessors move to generic properties.
            if (o.class == C_ARRAY || o.class == C_ARGUMENTS) && key.idx >= 0i64 {
                if !materialize_elements(it, o) { ret (false, ok) }
            }
            try define_accessor_raw(it, o, key, g, s, flags)
            if o.class == C_ARRAY && key.idx >= 0i64 && f64(key.idx) >= o.num { o.num = f64(key.idx) + 1.0f64 }
            ret (true, ok)
        }
        if d.has_writable && d.writable { flags = flags | P_WRITABLE }
        var val = undefv()
        if d.has_value { val = d.value }
        if (o.class == C_ARRAY || o.class == C_ARGUMENTS) && key.idx >= 0i64 {
            if flags != P_DEFAULT {
                if !materialize_elements(it, o) { ret (false, ok) }
            } else {
                let (cr, ce) = create_data(it, o, key, val)
                ret (cr, ce)
            }
            if o.class == C_ARRAY && f64(key.idx) >= o.num { o.num = f64(key.idx) + 1.0f64 }
        }
        try define_data(it, o, key, val, flags)
        ret (true, ok)
    }
    // Existing property.
    let cur_configurable = (cur.flags & P_CONFIGURABLE) != 0u8
    let cur_accessor = (cur.flags & P_ACCESSOR) != 0u8
    if !cur_configurable {
        if d.has_configurable && d.configurable { ret (false, ok) }
        if d.has_enumerable && d.enumerable != ((cur.flags & P_ENUMERABLE) != 0u8) { ret (false, ok) }
        let wants_accessor = d.has_get || d.has_set
        let wants_data = d.has_value || d.has_writable
        if wants_accessor && !cur_accessor { ret (false, ok) }
        if wants_data && cur_accessor { ret (false, ok) }
        if cur_accessor {
            if d.has_get {
                var cg = undefv()
                if cur.getter != z { cg = obj_value(cur.getter) }
                if !same_value(cg, d.getter) { ret (false, ok) }
            }
            if d.has_set {
                var cs = undefv()
                if cur.setter != z { cs = obj_value(cur.setter) }
                if !same_value(cs, d.setter) { ret (false, ok) }
            }
        } else if (cur.flags & P_WRITABLE) == 0u8 {
            if d.has_writable && d.writable { ret (false, ok) }
            if d.has_value && !same_value(d.value, cur.value) { ret (false, ok) }
        }
    }
    var flags2 = cur.flags & (P_ENUMERABLE | P_CONFIGURABLE)
    if d.has_enumerable {
        if d.enumerable { flags2 = flags2 | P_ENUMERABLE } else { flags2 = flags2 & (255u8 - P_ENUMERABLE) }
    }
    if d.has_configurable {
        if d.configurable { flags2 = flags2 | P_CONFIGURABLE } else { flags2 = flags2 & (255u8 - P_CONFIGURABLE) }
    }
    let to_accessor = d.has_get || d.has_set
    let to_data = d.has_value || d.has_writable
    if (o.class == C_ARRAY || o.class == C_ARGUMENTS) && key.idx >= 0i64 && key.idx < i64(o.elems.len) {
        // Plain element: keep it dense unless the new attributes differ from the defaults.
        var wr = true
        if d.has_writable { wr = d.writable }
        if !to_accessor && wr && flags2 == (P_ENUMERABLE | P_CONFIGURABLE) {
            if d.has_value { o.elems.items[usize(key.idx)] = d.value }
            ret (true, ok)
        }
        if !materialize_elements(it, o) { ret (false, ok) }
        let (cur2, ex2) = get_own(it, o, key)
        let (done_again, de) = define_own(it, o, key, d)
        ret (done_again, de)
    }
    if to_accessor {
        var g2 = z
        var s2 = z
        if cur_accessor {
            g2 = cur.getter
            s2 = cur.setter
        }
        if d.has_get { if is_object(d.getter) { g2 = as_object(d.getter) } else { g2 = z } }
        if d.has_set { if is_object(d.setter) { s2 = as_object(d.setter) } else { s2 = z } }
        try define_accessor_raw(it, o, key, g2, s2, flags2)
        ret (true, ok)
    }
    var w = (cur.flags & P_WRITABLE) != 0u8
    var val2 = cur.value
    if cur_accessor {
        w = false
        val2 = undefv()
    }
    if d.has_writable { w = d.writable }
    if d.has_value { val2 = d.value }
    if w { flags2 = flags2 | P_WRITABLE }
    if o.class == C_STRING && cur.flags == 0u8 { ret (true, ok) }
    try define_data(it, o, key, val2, flags2)
    ret (true, ok)
}

// Moves a dense array's elements into generic index properties so each can carry its own attributes.
fn materialize_elements(it: *Interp, o: *Obj) -> bool {
    var i = 0usize
    let z = null_obj()
    while i < o.elems.len {
        let ev = o.elems.items[i]
        if !is_hole(it, ev) {
            let k = key_of(index_string(it, i))
            let pe = append_prop(it, o, Prop { key: k, value: ev, getter: z, setter: z, flags: P_DEFAULT })
            if pe != ok { ret false }
        }
        i += 1usize
    }
    if o.class == C_ARRAY && o.num < f64(o.elems.len) { o.num = f64(o.elems.len) }
    o.elems.len = 0usize
    ret true
}

fn index_string(it: *Interp, i: usize) -> str {
    let (b, be) = str.builder(it.a, 12usize)
    if be != ok { ret "" }
    var out = b
    let pe = str.push_i64(&out, i64(i))
    ret str.done(&out)
}

// --- conversions

fn to_primitive(it: *Interp, v: Value, hint: str) -> (Value, err) {
    switch v {
    case .Obj as o:
        let (ex, ee) = get_prop(it, o, key_of_symbol(it.sym_to_primitive), v)
        if ee != ok { ret (undefv(), ee) }
        if !is_nullish(ex) {
            if !is_callable(ex) { ret (undefv(), throw_type(it, "@@toPrimitive is not callable")) }
            let (r, re) = call_function(it, ex, v, one_arg(it, str_value(hint)))
            if re != ok { ret (undefv(), re) }
            if is_object(r) { ret (undefv(), throw_type(it, "Cannot convert object to primitive value")) }
            ret (r, ok)
        }
        var first = "valueOf"
        var second = "toString"
        if str.eq(hint, "string") {
            first = "toString"
            second = "valueOf"
        }
        let (m1, e1) = get_prop(it, o, key_of(first), v)
        if e1 != ok { ret (undefv(), e1) }
        if is_callable(m1) {
            let (r1, re1) = call_function(it, m1, v, zero_args())
            if re1 != ok { ret (undefv(), re1) }
            if !is_object(r1) { ret (r1, ok) }
        }
        let (m2, e2) = get_prop(it, o, key_of(second), v)
        if e2 != ok { ret (undefv(), e2) }
        if is_callable(m2) {
            let (r2, re2) = call_function(it, m2, v, zero_args())
            if re2 != ok { ret (undefv(), re2) }
            if !is_object(r2) { ret (r2, ok) }
        }
        ret (undefv(), throw_type(it, "Cannot convert object to primitive value"))
    default:
        ret (v, ok)
    }
    ret (v, ok)
}

fn to_number(it: *Interp, v: Value) -> (f64, err) {
    switch v {
    case .Undefined:
        ret (nan(), ok)
    case .Null:
        ret (0.0f64, ok)
    case .Bool as b:
        if b { ret (1.0f64, ok) }
        ret (0.0f64, ok)
    case .Num as n:
        ret (n, ok)
    case .Str as s:
        ret (string_to_number(it.a, s), ok)
    case .Sym as sy:
        ret (0.0f64, throw_type(it, "Cannot convert a Symbol value to a number"))
    case .Obj as o:
        let (p, pe) = to_primitive(it, v, "number")
        if pe != ok { ret (0.0f64, pe) }
        let (n2, ne) = to_number(it, p)
        ret (n2, ne)
    }
    ret (0.0f64, ok)
}

fn to_string(it: *Interp, v: Value) -> (str, err) {
    switch v {
    case .Undefined:
        ret ("undefined", ok)
    case .Null:
        ret ("null", ok)
    case .Bool as b:
        if b { ret ("true", ok) }
        ret ("false", ok)
    case .Num as n:
        ret (number_to_string(it.a, n), ok)
    case .Str as s:
        ret (s, ok)
    case .Sym as sy:
        ret ("", throw_type(it, "Cannot convert a Symbol value to a string"))
    case .Obj as o:
        let (p, pe) = to_primitive(it, v, "string")
        if pe != ok { ret ("", pe) }
        let (s2, se) = to_string(it, p)
        ret (s2, se)
    }
    ret ("", ok)
}

fn to_object(it: *Interp, v: Value) -> (*Obj, err) {
    switch v {
    case .Obj as o:
        ret (o, ok)
    case .Undefined:
        ret (null_obj(), throw_type(it, "Cannot convert undefined to object"))
    case .Null:
        ret (null_obj(), throw_type(it, "Cannot convert null to object"))
    case .Bool as b:
        let w = new_obj(it, C_BOOLEAN, it.protos.boolean)
        w.prim = v
        ret (w, ok)
    case .Num as n:
        let w2 = new_obj(it, C_NUMBER, it.protos.number)
        w2.prim = v
        ret (w2, ok)
    case .Str as s:
        let w3 = new_obj(it, C_STRING, it.protos.string)
        w3.prim = v
        ret (w3, ok)
    case .Sym as sy:
        let w4 = new_obj(it, C_SYMBOL, it.protos.symbol)
        w4.prim = v
        ret (w4, ok)
    }
    ret (null_obj(), ok)
}

fn to_property_key(it: *Interp, v: Value) -> (Key, err) {
    switch v {
    case .Str as s:
        ret (key_of(s), ok)
    case .Sym as sy:
        ret (key_of_symbol(sy), ok)
    case .Num as n:
        ret (key_of(number_to_string(it.a, n)), ok)
    case .Obj as o:
        let (p, pe) = to_primitive(it, v, "string")
        if pe != ok { ret (key_of(""), pe) }
        let (k, ke) = to_property_key(it, p)
        ret (k, ke)
    default:
        let (s2, se) = to_string(it, v)
        ret (key_of(s2), se)
    }
    ret (key_of(""), ok)
}

fn to_length(it: *Interp, v: Value) -> (f64, err) {
    let (n, e) = to_number(it, v)
    if e != ok { ret (0.0f64, e) }
    let i = to_integer(n)
    if i <= 0.0f64 { ret (0.0f64, ok) }
    if i > 9007199254740991.0f64 { ret (9007199254740991.0f64, ok) }
    ret (i, ok)
}

fn to_int32(it: *Interp, v: Value) -> (i32, err) {
    let (n, e) = to_number(it, v)
    if e != ok { ret (0i32, e) }
    ret (to_int32_value(n), ok)
}

fn to_uint32(it: *Interp, v: Value) -> (u32, err) {
    let (n, e) = to_number(it, v)
    if e != ok { ret (0u32, e) }
    ret (to_uint32_bits(n), ok)
}

// `length` of an array-like.
fn length_of(it: *Interp, o: *Obj) -> (f64, err) {
    if o.class == C_ARRAY { ret (array_length(o), ok) }
    let (lv, le) = get_prop(it, o, key_of("length"), obj_value(o))
    if le != ok { ret (0.0f64, le) }
    let (n, ne) = to_length(it, lv)
    ret (n, ne)
}

fn get_index(it: *Interp, o: *Obj, i: f64) -> (Value, err) {
    if o.class == C_ARRAY && i >= 0.0f64 && i < f64(o.elems.len) {
        let ev = o.elems.items[usize(i)]
        if !is_hole(it, ev) { ret (ev, ok) }
    }
    let (v, e) = get_prop(it, o, key_of(number_to_string(it.a, i)), obj_value(o))
    ret (v, e)
}

fn set_index(it: *Interp, o: *Obj, i: f64, val: Value) -> err {
    let (done, e) = set_prop(it, o, key_of(number_to_string(it.a, i)), val, obj_value(o))
    if e != ok { ret e }
    if !done { ret throw_type(it, "Cannot assign to read only property") }
    ret ok
}

fn same_object(x: *Obj, y: *Obj) -> bool { ret x == y }

// OrdinaryHasInstance and `instanceof`.
fn instance_of(it: *Interp, v: Value, ctor: Value) -> (bool, err) {
    if !is_object(ctor) { ret (false, throw_type(it, "Right-hand side of 'instanceof' is not callable")) }
    let co = as_object(ctor)
    let (h, he) = get_prop(it, co, key_of_symbol(it.sym_has_instance), ctor)
    if he != ok { ret (false, he) }
    if !is_nullish(h) {
        let (r, re) = call_function(it, h, ctor, one_arg(it, v))
        if re != ok { ret (false, re) }
        ret (to_boolean(r), ok)
    }
    if !is_callable(ctor) { ret (false, throw_type(it, "Right-hand side of 'instanceof' is not callable")) }
    let (b, be) = ordinary_has_instance(it, ctor, v)
    ret (b, be)
}

fn ordinary_has_instance(it: *Interp, ctor: Value, v: Value) -> (bool, err) {
    if !is_callable(ctor) { ret (false, ok) }
    let co = as_object(ctor)
    if co.class == C_BOUND {
        let (r, re) = instance_of(it, v, obj_value(co.bound_target))
        ret (r, re)
    }
    if !is_object(v) { ret (false, ok) }
    let (pv, pe) = get_prop(it, co, key_of("prototype"), ctor)
    if pe != ok { ret (false, pe) }
    if !is_object(pv) { ret (false, throw_type(it, "Function has non-object prototype in instanceof check")) }
    let tgt = as_object(pv)
    var cur = as_object(v)
    var guard = 0u32
    while guard < 100000u32 {
        guard += 1u32
        if !cur.has_proto { ret (false, ok) }
        cur = cur.proto
        if cur == tgt { ret (true, ok) }
    }
    ret (false, ok)
}

// Abstract equality (`==`).
fn loose_equals(it: *Interp, x: Value, y: Value) -> (bool, err) {
    switch x {
    case .Undefined:
        ret (is_nullish(y), ok)
    case .Null:
        ret (is_nullish(y), ok)
    case .Num as nx:
        switch y {
        case .Num as ny:
            ret (nx == ny, ok)
        case .Str as sy:
            ret (nx == string_to_number(it.a, sy), ok)
        case .Bool as by:
            var bn = 0.0f64
            if by { bn = 1.0f64 }
            ret (nx == bn, ok)
        case .Obj as oy:
            let (py, pe) = to_primitive(it, y, "default")
            if pe != ok { ret (false, pe) }
            let (r, re) = loose_equals(it, x, py)
            ret (r, re)
        default:
            ret (false, ok)
        }
    case .Str as sx:
        switch y {
        case .Str as sy2:
            ret (str.eq(sx, sy2), ok)
        case .Num as ny2:
            ret (string_to_number(it.a, sx) == ny2, ok)
        case .Bool as by2:
            var bn2 = 0.0f64
            if by2 { bn2 = 1.0f64 }
            ret (string_to_number(it.a, sx) == bn2, ok)
        case .Obj as oy2:
            let (py2, pe2) = to_primitive(it, y, "default")
            if pe2 != ok { ret (false, pe2) }
            let (r2, re2) = loose_equals(it, x, py2)
            ret (r2, re2)
        default:
            ret (false, ok)
        }
    case .Bool as bx:
        var xn = 0.0f64
        if bx { xn = 1.0f64 }
        let (r3, re3) = loose_equals(it, num_value(xn), y)
        ret (r3, re3)
    case .Sym as symx:
        switch y {
        case .Sym as symy:
            ret (symx == symy, ok)
        case .Obj as oy3:
            let (py3, pe3) = to_primitive(it, y, "default")
            if pe3 != ok { ret (false, pe3) }
            ret (strict_equals(x, py3), ok)
        default:
            ret (false, ok)
        }
    case .Obj as ox:
        switch y {
        case .Obj as oy4:
            ret (ox == oy4, ok)
        case .Undefined:
            ret (false, ok)
        case .Null:
            ret (false, ok)
        default:
            let (px, pxe) = to_primitive(it, x, "default")
            if pxe != ok { ret (false, pxe) }
            let (r4, re4) = loose_equals(it, px, y)
            ret (r4, re4)
        }
    }
    ret (false, ok)
}

// --- environments

fn new_env(it: *Interp, parent: *Env) -> *Env {
    let (cell, ce) = mem.alloc[Env](it.a, 1usize)
    if ce != ok {
        var none: *Env = zero
        ret none
    }
    var blank: Env = zero
    cell[0usize] = blank
    let e = &cell[0usize]
    let (vars, ve) = list.init[Binding](it.a, 0usize)
    e.vars = vars
    e.parent = parent
    e.has_with = false
    e.with_obj = null_obj()
    ret e
}

fn null_env() -> *Env {
    var none: *Env = zero
    ret none
}

fn env_index(e: *const Env, name: str) -> (usize, bool) {
    var i = 0usize
    while i < e.vars.len {
        if str.eq(e.vars.items[i].name, name) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn declare(it: *Interp, e: *Env, name: str, val: Value, flags: u8) -> err {
    let (at, found) = env_index(e, name)
    if found {
        e.vars.items[at].value = val
        e.vars.items[at].flags = flags
        ret ok
    }
    ret list.push[Binding](&e.vars, Binding { name: name, value: val, flags: flags })
}

// A `var`/parameter-style declaration: leaves an existing binding's value alone.
fn declare_var(it: *Interp, e: *Env, name: str) -> err {
    let (at, found) = env_index(e, name)
    if found { ret ok }
    ret list.push[Binding](&e.vars, Binding { name: name, value: undefv(), flags: 0u8 })
}

type Frame = struct {
    prog: *const ast.Program, env: *Env, this_val: Value, has_this: bool, func: *Obj, has_func: bool, new_target: Value,
    strict: bool, home: *Obj, has_home: bool, args: []const Value, gen: *void, has_gen: bool
}

// Completion kinds.
const CK_NORMAL: u8 = 0u8
const CK_BREAK: u8 = 1u8
const CK_CONTINUE: u8 = 2u8
const CK_RETURN: u8 = 3u8

type Completion = struct { kind: u8, value: Value, label: str }

fn normal() -> Completion { ret Completion { kind: CK_NORMAL, value: undefv(), label: "" } }

// Finds the binding of `name` along the scope chain: (environment, index) or a `with` object or the global object.
fn lookup_value(it: *Interp, f: *Frame, name: str) -> (Value, err) {
    var e = f.env
    let z = null_env()
    while e != z {
        if e.has_with {
            let key = key_of(name)
            if has_property(it, e.with_obj, key) {
                let (wv, we) = get_prop(it, e.with_obj, key, obj_value(e.with_obj))
                ret (wv, we)
            }
        } else {
            let (at, found) = env_index(e, name)
            if found {
                let fl = e.vars.items[at].flags
                if (fl & B_TDZ) != 0u8 { ret (undefv(), throw_reference(it, str_concat3(it, "Cannot access '", name, "' before initialization"))) }
                ret (e.vars.items[at].value, ok)
            }
        }
        e = e.parent
    }
    let key2 = key_of(name)
    if has_property(it, it.global, key2) {
        let (gv, ge) = get_prop(it, it.global, key2, obj_value(it.global))
        ret (gv, ge)
    }
    ret (undefv(), throw_reference(it, str_concat(it, name, " is not defined")))
}

fn assign_name(it: *Interp, f: *Frame, name: str, val: Value) -> err {
    var e = f.env
    let z = null_env()
    while e != z {
        if e.has_with {
            let key = key_of(name)
            if has_property(it, e.with_obj, key) {
                let (done, se) = set_prop(it, e.with_obj, key, val, obj_value(e.with_obj))
                ret se
            }
        } else {
            let (at, found) = env_index(e, name)
            if found {
                let fl = e.vars.items[at].flags
                if (fl & B_TDZ) != 0u8 { ret throw_reference(it, str_concat3(it, "Cannot access '", name, "' before initialization")) }
                if (fl & B_CONST) != 0u8 {
                    if (fl & B_STRICT_CONST) != 0u8 || f.strict { ret throw_type(it, "Assignment to constant variable.") }
                    ret ok
                }
                e.vars.items[at].value = val
                ret ok
            }
        }
        e = e.parent
    }
    let key2 = key_of(name)
    if has_property(it, it.global, key2) {
        let (done2, se2) = set_prop(it, it.global, key2, val, obj_value(it.global))
        if se2 != ok { ret se2 }
        if !done2 && f.strict { ret throw_type(it, "Cannot assign to read only property") }
        ret ok
    }
    if f.strict { ret throw_reference(it, str_concat(it, name, " is not defined")) }
    let (cr, ce) = create_data(it, it.global, key2, val)
    ret ce
}

// Initialises a binding declared earlier (clears its TDZ).
fn init_binding(it: *Interp, e: *Env, name: str, val: Value) -> err {
    let (at, found) = env_index(e, name)
    if found {
        e.vars.items[at].value = val
        e.vars.items[at].flags = e.vars.items[at].flags & (255u8 - B_TDZ)
        ret ok
    }
    ret list.push[Binding](&e.vars, Binding { name: name, value: val, flags: 0u8 })
}

// --- functions

fn proto_value_of(it: *Interp, ctor: *Obj, fallback: *Obj) -> (*Obj, err) {
    let (pv, pe) = get_prop(it, ctor, key_of("prototype"), obj_value(ctor))
    if pe != ok { ret (fallback, pe) }
    if is_object(pv) { ret (as_object(pv), ok) }
    ret (fallback, ok)
}

fn count_params_length(f: *const Frame, fid: u32) -> f64 { ret f.prog.nodes[usize(fid)].num }

// Creates the function object for N_FUNC `fid` closed over `f.env`.
fn make_function(it: *Interp, f: *Frame, fid: u32) -> (*Obj, err) {
    let n = f.prog.nodes[usize(fid)]
    var fproto = it.protos.function
    if (n.flags & ast.F_GENERATOR) != 0u16 && it.protos.gen_function != null_obj() { fproto = it.protos.gen_function }
    if (n.flags & ast.F_GENERATOR) == 0u16 && (n.flags & ast.F_ASYNC) != 0u16 && it.protos.async_function != null_obj() { fproto = it.protos.async_function }
    if (n.flags & ast.F_GENERATOR) != 0u16 && (n.flags & ast.F_ASYNC) != 0u16 && it.protos.async_gen_function != null_obj() { fproto = it.protos.async_gen_function }
    let fo = new_obj(it, C_FUNCTION, fproto)
    fo.prog = f.prog
    fo.node = fid
    fo.env = f.env
    let is_arrow = (n.flags & ast.F_ARROW) != 0u16 && (n.flags & ast.F_METHOD) == 0u16
    let is_method = (n.flags & ast.F_METHOD) != 0u16
    let is_gen = (n.flags & ast.F_GENERATOR) != 0u16
    let is_async = (n.flags & ast.F_ASYNC) != 0u16
    if is_arrow {
        fo.this_val = f.this_val
        fo.bound_this = f.new_target
        fo.home = f.home
        fo.has_home = f.has_home
        if f.has_func { fo.bound_target = f.func }
    }
    fo.ctor_kind = K_NONE
    if !is_arrow && !is_method && !is_gen && !is_async { fo.ctor_kind = K_BASE }
    try define_data(it, fo, key_of("length"), num_value(n.num), P_CONFIGURABLE)
    try define_data(it, fo, key_of("name"), str_value(n.text), P_CONFIGURABLE)
    if fo.ctor_kind == K_BASE {
        let proto = new_plain(it)
        try define_data(it, proto, key_of("constructor"), obj_value(fo), P_HIDDEN)
        try define_data(it, fo, key_of("prototype"), obj_value(proto), P_WRITABLE)
    } else if is_gen {
        var gp_parent = it.protos.generator
        if is_async { gp_parent = it.protos.async_generator }
        let gproto = new_obj(it, C_OBJECT, gp_parent)
        try define_data(it, fo, key_of("prototype"), obj_value(gproto), P_WRITABLE)
    }
    ret (fo, ok)
}

fn make_native(it: *Interp, name: str, length: u32, native: NativeFn) -> *Obj {
    let fo = new_obj(it, C_FUNCTION, it.protos.function)
    fo.native = native
    fo.has_native = true
    let e1 = define_data(it, fo, key_of("length"), num_value(f64(length)), P_CONFIGURABLE)
    let e2 = define_data(it, fo, key_of("name"), str_value(name), P_CONFIGURABLE)
    ret fo
}

// Installs a native method on `o` (non-enumerable).
fn add_method(it: *Interp, o: *Obj, name: str, length: u32, native: NativeFn) {
    let fo = make_native(it, name, length, native)
    let e = define_data(it, o, key_of(name), obj_value(fo), P_HIDDEN)
}

fn add_getter(it: *Interp, o: *Obj, name: str, native: NativeFn) {
    let fo = make_native(it, str_concat(it, "get ", name), 0u32, native)
    let e = define_accessor_raw(it, o, key_of(name), fo, null_obj(), P_CONFIGURABLE)
}

fn add_value(it: *Interp, o: *Obj, name: str, val: Value) {
    let e = define_data(it, o, key_of(name), val, P_HIDDEN)
}

fn this_coerce(it: *Interp, v: Value) -> Value {
    switch v {
    case .Undefined:
        ret obj_value(it.global)
    case .Null:
        ret obj_value(it.global)
    case .Obj as o:
        ret v
    default:
        let (o2, e) = to_object(it, v)
        if e != ok { ret v }
        ret obj_value(o2)
    }
    ret v
}

fn call_function(it: *Interp, fv: Value, this_val: Value, args: []const Value) -> (Value, err) {
    switch fv {
    case .Obj as fo:
        if fo.class == C_BOUND {
            // Bound function: prepend the bound arguments.
            let total = fo.bound_args.len + args.len
            let (cell, ce) = mem.alloc[Value](it.a, total + 1usize)
            if ce != ok { ret (undefv(), throw_range(it, "out of memory")) }
            var i = 0usize
            while i < fo.bound_args.len {
                cell[i] = fo.bound_args[i]
                i += 1usize
            }
            var k = 0usize
            while k < args.len {
                cell[fo.bound_args.len + k] = args[k]
                k += 1usize
            }
            let (r, re) = call_function(it, obj_value(fo.bound_target), fo.bound_this, cell[0usize..total])
            ret (r, re)
        }
        if fo.class != C_FUNCTION { ret (undefv(), throw_type(it, "not a function")) }
        it.depth += 1u32
        if it.depth > it.max_depth {
            it.depth -= 1u32
            ret (undefv(), throw_range(it, "Maximum call stack size exceeded"))
        }
        if fo.has_native {
            let saved_callee = it.callee
            let saved_nt = it.new_target
            let saved_has = it.has_new_target
            it.callee = fo
            it.has_new_target = false
            it.new_target = undefv()
            let (r2, re2) = fo.native(it, this_val, args)
            it.callee = saved_callee
            it.new_target = saved_nt
            it.has_new_target = saved_has
            it.depth -= 1u32
            ret (r2, re2)
        }
        let (r3, re3) = call_js(it, fo, this_val, args, undefv(), false)
        it.depth -= 1u32
        ret (r3, re3)
    default:
        ret (undefv(), throw_type(it, "not a function"))
    }
    ret (undefv(), ok)
}

fn is_constructor(v: Value) -> bool {
    switch v {
    case .Obj as o:
        if o.class == C_BOUND { ret is_constructor(obj_value(o.bound_target)) }
        if o.class != C_FUNCTION { ret false }
        if o.has_native { ret o.ctor_kind != K_NONE }
        ret o.ctor_kind != K_NONE
    default:
        ret false
    }
}

fn construct(it: *Interp, fv: Value, args: []const Value, new_target: Value) -> (Value, err) {
    if !is_constructor(fv) { ret (undefv(), throw_type(it, "not a constructor")) }
    let fo = as_object(fv)
    if fo.class == C_BOUND {
        let total = fo.bound_args.len + args.len
        let (cell, ce) = mem.alloc[Value](it.a, total + 1usize)
        if ce != ok { ret (undefv(), throw_range(it, "out of memory")) }
        var i = 0usize
        while i < fo.bound_args.len {
            cell[i] = fo.bound_args[i]
            i += 1usize
        }
        var k = 0usize
        while k < args.len {
            cell[fo.bound_args.len + k] = args[k]
            k += 1usize
        }
        var nt = new_target
        if strict_equals(new_target, fv) { nt = obj_value(fo.bound_target) }
        let (r, re) = construct(it, obj_value(fo.bound_target), cell[0usize..total], nt)
        ret (r, re)
    }
    it.depth += 1u32
    if it.depth > it.max_depth {
        it.depth -= 1u32
        ret (undefv(), throw_range(it, "Maximum call stack size exceeded"))
    }
    if fo.has_native {
        let saved_callee = it.callee
        let saved_nt = it.new_target
        let saved_has = it.has_new_target
        it.callee = fo
        it.new_target = new_target
        it.has_new_target = true
        let (r2, re2) = fo.native(it, undefv(), args)
        it.callee = saved_callee
        it.new_target = saved_nt
        it.has_new_target = saved_has
        it.depth -= 1u32
        ret (r2, re2)
    }
    var this_val = undefv()
    if fo.ctor_kind == K_BASE {
        let nto = as_object(new_target)
        let (proto, pe) = proto_value_of(it, nto, it.protos.object)
        if pe != ok {
            it.depth -= 1u32
            ret (undefv(), pe)
        }
        let o = new_obj(it, C_OBJECT, proto)
        this_val = obj_value(o)
        let fe = init_fields(it, fo, o)
        if fe != ok {
            it.depth -= 1u32
            ret (undefv(), fe)
        }
    }
    let (r3, re3) = call_js(it, fo, this_val, args, new_target, true)
    it.depth -= 1u32
    ret (r3, re3)
}

// Runs a class constructor's field initialisers on a new instance.
fn init_fields(it: *Interp, ctor: *Obj, inst: *Obj) -> err {
    if !ctor.has_fields { ret ok }
    let list_obj = ctor.fields
    var i = 0usize
    while i < list_obj.elems.len {
        // Each entry is a [key, initialiser-or-undefined] array.
        let entry = as_object(list_obj.elems.items[i])
        let kv = entry.elems.items[0usize]
        let init_fn = entry.elems.items[1usize]
        var val = undefv()
        if is_object(init_fn) {
            let (r, re) = call_function(it, init_fn, obj_value(inst), zero_args())
            if re != ok { ret re }
            val = r
        }
        var key = key_of("")
        switch kv {
        case .Sym as ks:
            key = key_of_symbol(ks)
        case .Str as kstr:
            key = key_of(kstr)
        default:
            key = key_of("")
        }
        let fe = field_define(it, inst, key, val)
        if fe != ok { ret fe }
        i += 1usize
    }
    ret ok
}

fn field_define(it: *Interp, inst: *Obj, key: Key, val: Value) -> err {
    let (done, de) = define_own(it, inst, key, data_desc(val, P_DEFAULT))
    if de != ok { ret de }
    if !done { ret throw_type(it, "Cannot define class field") }
    ret ok
}

fn call_js(it: *Interp, fo: *Obj, this_in: Value, args: []const Value, new_target: Value, constructing: bool) -> (Value, err) {
    let n = fo.prog.nodes[usize(fo.node)]
    let is_arrow = (n.flags & ast.F_ARROW) != 0u16
    let is_class_ctor = fo.ctor_kind == K_DERIVED || (fo.ctor_kind == K_BASE && fo.num == 1.0f64)
    if is_class_ctor && !constructing { ret (undefv(), throw_type(it, "Class constructor cannot be invoked without 'new'")) }
    var f: Frame = zero
    f.prog = fo.prog
    f.env = new_env(it, fo.env)
    f.func = fo
    f.has_func = true
    f.args = args
    f.strict = (n.flags & ast.F_STRICT) != 0u16
    f.home = fo.home
    f.has_home = fo.has_home
    if is_arrow {
        f.this_val = fo.this_val
        f.has_this = true
        f.new_target = fo.bound_this
        if fo.has_home { f.home = fo.home }
        if fo.bound_target != null_obj() {
            f.func = fo.bound_target
        }
    } else {
        f.new_target = new_target
        if constructing && fo.ctor_kind == K_DERIVED {
            f.has_this = false
            f.this_val = undefv()
        } else {
            f.has_this = true
            if f.strict { f.this_val = this_in } else { f.this_val = this_coerce(it, this_in) }
        }
    }
    let be = bind_function(it, &f, fo, n, args)
    if (n.flags & ast.F_GENERATOR) != 0u16 || (n.flags & ast.F_ASYNC) != 0u16 {
        if be != ok {
            // An async function reports parameter errors through its promise.
            if (n.flags & ast.F_GENERATOR) == 0u16 && be == Throw {
                let (ap, ape) = new_promise(it)
                if ape != ok { ret (undefv(), ape) }
                let rj = promise_reject(it, ap, it.thrown)
                ret (obj_value(ap), ok)
            }
            ret (undefv(), be)
        }
        let (sr, se2) = make_suspendable(it, fo, f, n)
        ret (sr, se2)
    }
    if be != ok { ret (undefv(), be) }
    var result = undefv()
    if (n.flags & ast.F_EXPR_BODY) != 0u16 {
        let (v, ve) = eval(it, &f, n.c)
        if ve != ok { ret (undefv(), ve) }
        result = v
    } else {
        let (c, ce) = exec_body(it, &f, n.c)
        if ce != ok { ret (undefv(), ce) }
        if c.kind == CK_RETURN { result = c.value }
    }
    if constructing {
        if is_object(result) { ret (result, ok) }
        if fo.ctor_kind == K_DERIVED {
            if !is_undefined(result) { ret (undefv(), throw_type(it, "Derived constructors may only return object or undefined")) }
            if !f.has_this { ret (undefv(), throw_reference(it, "Must call super constructor in derived class before accessing 'this' or returning from derived constructor")) }
        }
        ret (f.this_val, ok)
    }
    ret (result, ok)
}

// Binds parameters, `arguments`, hoisted `var`s and function declarations of a call.
fn bind_function(it: *Interp, f: *Frame, fo: *Obj, n: ast.Node, args: []const Value) -> err {
    let is_arrow = (n.flags & ast.F_ARROW) != 0u16
    // Named function expressions see their own name.
    var i = 0usize
    var simple = true
    while i < usize(n.b) {
        let pk = f.prog.nodes[usize(f.prog.kids[usize(n.a) + i])].kind
        if pk != ast.N_IDENT { simple = false }
        i += 1usize
    }
    if (n.flags & ast.F_USES_ARGS) != 0u16 && !is_arrow {
        let ao = new_obj(it, C_ARGUMENTS, it.protos.arguments)
        var k = 0usize
        while k < args.len {
            let pe = list.push[Value](&ao.elems, args[k])
            k += 1usize
        }
        try define_data(it, ao, key_of("length"), num_value(f64(args.len)), P_HIDDEN)
        let (vals, ve) = get_prop(it, it.protos.array, key_of("values"), obj_value(it.protos.array))
        if ve == ok { try define_data(it, ao, key_of_symbol(it.sym_iterator), vals, P_HIDDEN) }
        if !f.strict { try define_data(it, ao, key_of("callee"), obj_value(fo), P_HIDDEN) }
        try declare(it, f.env, "arguments", obj_value(ao), 0u8)
    }
    i = 0usize
    while i < usize(n.b) {
        let pid = f.prog.kids[usize(n.a) + i]
        let pn = f.prog.nodes[usize(pid)]
        if pn.kind == ast.N_SPREAD {
            let rest = new_array(it)
            var r = i
            while r < args.len {
                try array_push(it, rest, args[r])
                r += 1usize
            }
            try bind_pattern(it, f, pn.a, obj_value(rest), 3u8)
        } else {
            var av = undefv()
            if i < args.len { av = args[i] }
            try bind_pattern(it, f, pid, av, 3u8)
        }
        i += 1usize
    }
    // Hoisted `var`s.
    var h = 0usize
    while h < usize(n.hoist_count) {
        let hid = f.prog.kids[usize(n.hoist_first) + h]
        try declare_var(it, f.env, f.prog.nodes[usize(hid)].text)
        h += 1usize
    }
    ret ok
}

// --- binding patterns
//
// `mode`: 0 assign (targets are references), 1 `var`, 2 `let`/`const` initialisation (const flag in 4), 3 parameter.

fn bind_name(it: *Interp, f: *Frame, name: str, val: Value, mode: u8) -> err {
    if mode == 0u8 { ret assign_name(it, f, name, val) }
    if mode == 1u8 {
        // `var`: assign to the hoisted binding.
        ret assign_name(it, f, name, val)
    }
    if mode == 3u8 { ret declare(it, f.env, name, val, 0u8) }
    if mode == 6u8 || mode == 7u8 {
        var fl = 0u8
        if mode == 7u8 { fl = B_CONST }
        let (at, found) = env_index(f.env, name)
        if found && (f.env.vars.items[at].flags & B_TDZ) == 0u8 && mode != 6u8 && false { ret ok }
        if found {
            f.env.vars.items[at].value = val
            f.env.vars.items[at].flags = fl
            ret ok
        }
        ret list.push[Binding](&f.env.vars, Binding { name: name, value: val, flags: fl })
    }
    ret ok
}

fn bind_pattern(it: *Interp, f: *Frame, pid: u32, val: Value, mode: u8) -> err {
    let pn = f.prog.nodes[usize(pid)]
    if pn.kind == ast.N_IDENT {
        ret bind_name(it, f, pn.text, val, mode)
    }
    if pn.kind == ast.N_ASSIGN {
        var v = val
        if is_undefined(v) {
            let (dv, de) = eval_named(it, f, pn.b, target_name(f, pn.a))
            if de != ok { ret de }
            v = dv
        }
        ret bind_pattern(it, f, pn.a, v, mode)
    }
    if pn.kind == ast.N_MEMBER {
        if mode != 0u8 { ret throw_syntax(it, "Invalid destructuring tgt") }
        let (base, be) = eval(it, f, pn.a)
        if be != ok { ret be }
        let (key, ke) = member_key(it, f, pn)
        if ke != ok { ret ke }
        ret put(it, base, key, val, f.strict)
    }
    if pn.kind == ast.N_ARRAY {
        if is_nullish(val) { ret throw_type(it, "undefined is not iterable") }
        let (iter, ie) = get_iterator(it, val)
        if ie != ok { ret ie }
        var done = false
        var i = 0usize
        while i < usize(pn.b) {
            let eid = f.prog.kids[usize(pn.a) + i]
            let en = f.prog.nodes[usize(eid)]
            i += 1usize
            if en.kind == ast.N_HOLE {
                if !done {
                    let (nv, nd, ne) = iterator_step(it, iter)
                    if ne != ok { ret ne }
                    if nd { done = true }
                }
                continue
            }
            if en.kind == ast.N_SPREAD {
                let rest = new_array(it)
                while !done {
                    let (sv, sd, se) = iterator_step(it, iter)
                    if se != ok { ret se }
                    if sd { done = true } else { try array_push(it, rest, sv) }
                }
                try bind_pattern(it, f, en.a, obj_value(rest), mode)
                continue
            }
            var ev = undefv()
            if !done {
                let (sv2, sd2, se2) = iterator_step(it, iter)
                if se2 != ok { ret se2 }
                if sd2 { done = true } else { ev = sv2 }
            }
            let be2 = bind_pattern(it, f, eid, ev, mode)
            if be2 != ok {
                let ce = iterator_close(it, iter)
                ret be2
            }
        }
        if !done { try iterator_close(it, iter) }
        ret ok
    }
    if pn.kind == ast.N_OBJECT {
        if is_nullish(val) { ret throw_type(it, "Cannot destructure undefined or null") }
        var used: [64]Key = zero
        var used_n = 0usize
        var i2 = 0usize
        while i2 < usize(pn.b) {
            let prop_id = f.prog.kids[usize(pn.a) + i2]
            let prop = f.prog.nodes[usize(prop_id)]
            i2 += 1usize
            if prop.op == ast.M_SPREAD {
                let rest_obj = new_plain(it)
                let (src, se3) = to_object(it, val)
                if se3 != ok { ret se3 }
                let (keys, ke3) = own_keys(it, src)
                if ke3 != ok { ret ke3 }
                var kk = 0usize
                while kk < keys.len {
                    var skip = false
                    var u = 0usize
                    while u < used_n {
                        if keys_equal(used[u], keys[kk]) { skip = true }
                        u += 1usize
                    }
                    if !skip {
                        let (kp, kfound) = get_own(it, src, keys[kk])
                        if kfound && (kp.flags & P_ENUMERABLE) != 0u8 {
                            let (kv, kve) = get_prop(it, src, keys[kk], obj_value(src))
                            if kve != ok { ret kve }
                            let (cr, ce2) = create_data(it, rest_obj, keys[kk], kv)
                            if ce2 != ok { ret ce2 }
                        }
                    }
                    kk += 1usize
                }
                try bind_pattern(it, f, prop.b, obj_value(rest_obj), mode)
                continue
            }
            var key = key_of("")
            if (prop.flags & ast.F_COMPUTED) != 0u16 {
                let (kv2, kve2) = eval(it, f, prop.a)
                if kve2 != ok { ret kve2 }
                let (k2, k2e) = to_property_key(it, kv2)
                if k2e != ok { ret k2e }
                key = k2
            } else {
                let kn = f.prog.nodes[usize(prop.a)]
                if kn.kind == ast.N_NUM {
                    key = key_of(number_to_string(it.a, kn.num))
                } else {
                    key = key_of(kn.text)
                }
            }
            if used_n < 64usize {
                used[used_n] = key
                used_n += 1usize
            }
            let (pv, pe) = get_value(it, val, key)
            if pe != ok { ret pe }
            try bind_pattern(it, f, prop.b, pv, mode)
        }
        ret ok
    }
    ret throw_syntax(it, "Invalid destructuring tgt")
}

fn target_name(f: *const Frame, id: u32) -> str {
    let n = f.prog.nodes[usize(id)]
    if n.kind == ast.N_IDENT { ret n.text }
    ret ""
}

// Evaluates `id`, naming an anonymous function or class `name`.
fn eval_named(it: *Interp, f: *Frame, id: u32, name: str) -> (Value, err) {
    let n = f.prog.nodes[usize(id)]
    if name.len > 0usize && (n.kind == ast.N_FUNC || n.kind == ast.N_CLASS) && n.text.len == 0usize {
        let (v, e) = eval(it, f, id)
        if e != ok { ret (undefv(), e) }
        set_function_name(it, v, name)
        ret (v, ok)
    }
    let (v2, e2) = eval(it, f, id)
    ret (v2, e2)
}

fn set_function_name(it: *Interp, v: Value, name: str) {
    if !is_object(v) { ret }
    let fo = as_object(v)
    if fo.class != C_FUNCTION { ret }
    let e = define_data(it, fo, key_of("name"), str_value(name), P_CONFIGURABLE)
}

// --- iteration

type Iter = struct { obj: Value, next: Value, array: *Obj, is_array: bool, pos: usize, sync_wrapped: bool }

// GetIterator: arrays take a fast path while their `Symbol.iterator` is the original `values`.
fn get_iterator(it: *Interp, v: Value) -> (Iter, err) {
    let (m, me) = get_value(it, v, key_of_symbol(it.sym_iterator))
    if me != ok { ret (zero, me) }
    if !is_callable(m) { ret (zero, throw_type(it, "object is not iterable")) }
    let (iobj, ie) = call_function(it, m, v, zero_args())
    if ie != ok { ret (zero, ie) }
    if !is_object(iobj) { ret (zero, throw_type(it, "Result of the Symbol.iterator method is not an object")) }
    let (nx, ne) = get_value(it, iobj, key_of("next"))
    if ne != ok { ret (zero, ne) }
    var iter: Iter = zero
    iter.obj = iobj
    iter.next = nx
    ret (iter, ok)
}

// One step: (value, done).
fn iterator_step(it: *Interp, iter: Iter) -> (Value, bool, err) {
    let (r, re) = call_function(it, iter.next, iter.obj, zero_args())
    if re != ok { ret (undefv(), true, re) }
    if !is_object(r) { ret (undefv(), true, throw_type(it, "Iterator result is not an object")) }
    let ro = as_object(r)
    let (dv, de) = get_prop(it, ro, key_of("done"), r)
    if de != ok { ret (undefv(), true, de) }
    if to_boolean(dv) { ret (undefv(), true, ok) }
    let (vv, ve) = get_prop(it, ro, key_of("value"), r)
    if ve != ok { ret (undefv(), true, ve) }
    ret (vv, false, ok)
}

fn iterator_close(it: *Interp, iter: Iter) -> err {
    let (rm, rme) = get_value(it, iter.obj, key_of("return"))
    if rme != ok { ret rme }
    if is_nullish(rm) { ret ok }
    let (r, re) = call_function(it, rm, iter.obj, zero_args())
    if re != ok { ret re }
    if !is_object(r) { ret throw_type(it, "iterator.return() did not return an object") }
    ret ok
}

// Collects an iterable's values.
fn iterate_to_list(it: *Interp, v: Value) -> (list.List[Value], err) {
    let (l, le) = list.init[Value](it.a, 8usize)
    var out = l
    if le != ok { ret (out, le) }
    let (iter, ie) = get_iterator(it, v)
    if ie != ok { ret (out, ie) }
    while true {
        let (sv, sd, se) = iterator_step(it, iter)
        if se != ok { ret (out, se) }
        if sd { break }
        try list.push[Value](&out, sv)
    }
    ret (out, ok)
}

// Own property keys in spec order: integer indices ascending, then strings, then symbols (private names excluded).
fn own_keys(it: *Interp, o: *Obj) -> ([]const Key, err) {
    let (l, le) = list.init[Key](it.a, o.props.len + o.elems.len + 4usize)
    var out = l
    if le != ok { ret (zero, le) }
    if o.class == C_TYPEDARRAY {
        let tn = ta_length(o)
        var t = 0usize
        while t < tn {
            try list.push[Key](&out, key_of(index_string(it, t)))
            t += 1usize
        }
    }
    if o.class == C_STRING {
        let n = units(prim_string(o))
        var s = 0usize
        while s < n {
            try list.push[Key](&out, key_of(index_string(it, s)))
            s += 1usize
        }
    }
    var i = 0usize
    while i < o.elems.len {
        if !is_hole(it, o.elems.items[i]) { try list.push[Key](&out, key_of(index_string(it, i))) }
        i += 1usize
    }
    // Index-like generic properties sorted ascending.
    var idx_keys: list.List[Key] = zero
    let (il, ile) = list.init[Key](it.a, 4usize)
    idx_keys = il
    var j = 0usize
    while j < o.props.len {
        let k = o.props.items[j].key
        if !is_symbol_key(k) && k.idx >= 0i64 { try list.push[Key](&idx_keys, k) }
        j += 1usize
    }
    // Insertion sort by index.
    var a1 = 1usize
    while a1 < idx_keys.len {
        let cur = idx_keys.items[a1]
        var b1 = a1
        while b1 > 0usize && idx_keys.items[b1 - 1usize].idx > cur.idx {
            idx_keys.items[b1] = idx_keys.items[b1 - 1usize]
            b1 -= 1usize
        }
        idx_keys.items[b1] = cur
        a1 += 1usize
    }
    var c1 = 0usize
    while c1 < idx_keys.len {
        try list.push[Key](&out, idx_keys.items[c1])
        c1 += 1usize
    }
    if o.class == C_ARRAY { try list.push[Key](&out, key_of("length")) }
    if o.class == C_STRING { try list.push[Key](&out, key_of("length")) }
    var j2 = 0usize
    while j2 < o.props.len {
        let k2 = o.props.items[j2].key
        if !is_symbol_key(k2) && k2.idx < 0i64 { try list.push[Key](&out, k2) }
        j2 += 1usize
    }
    var j3 = 0usize
    while j3 < o.props.len {
        let k3 = o.props.items[j3].key
        if is_symbol_key(k3) && !k3.sym.private { try list.push[Key](&out, k3) }
        j3 += 1usize
    }
    ret (list.slice_const[Key](&out), ok)
}

fn key_to_value(k: Key) -> Value {
    if is_symbol_key(k) { ret Value { Sym: k.sym } }
    ret str_value(k.name)
}

// --- members

fn member_key(it: *Interp, f: *Frame, n: ast.Node) -> (Key, err) {
    if (n.flags & ast.F_COMPUTED) != 0u16 {
        let (kv, ke) = eval(it, f, n.b)
        if ke != ok { ret (key_of(""), ke) }
        let (k, e) = to_property_key(it, kv)
        ret (k, e)
    }
    if n.b != ast.NONE {
        // A private name `#x`: a symbol bound in an enclosing class scope.
        let pn = f.prog.nodes[usize(n.b)]
        let (sv, se) = lookup_value(it, f, str_concat(it, "#", pn.text))
        if se != ok { ret (key_of(""), se) }
        switch sv {
        case .Sym as ps:
            ret (key_of_symbol(ps), ok)
        default:
            ret (key_of(""), throw_syntax(it, "Private field is not defined"))
        }
    }
    ret (key_of(n.text), ok)
}

// --- operators

fn fmod_js(x: f64, y: f64) -> f64 {
    if is_nan(x) || is_nan(y) || is_infinite(x) || y == 0.0f64 { ret nan() }
    if is_infinite(y) { ret x }
    if x == 0.0f64 { ret x }
    var ax = x
    if ax < 0.0f64 { ax = -ax }
    var ay = y
    if ay < 0.0f64 { ay = -ay }
    var r = ax
    if ax >= ay {
        // Reduce by repeated scaled subtraction, exact for doubles.
        var scaled = ay
        var guard = 0u32
        while scaled <= ax / 2.0f64 && guard < 2100u32 {
            scaled = scaled * 2.0f64
            guard += 1u32
        }
        while r >= ay {
            if r >= scaled { r = r - scaled }
            if scaled > ay { scaled = scaled / 2.0f64 } else if r >= ay { r = r - ay }
        }
    }
    if x < 0.0f64 {
        if r == 0.0f64 { ret -0.0f64 }
        ret -r
    }
    ret r
}

fn arith(it: *Interp, op: u8, x: f64, y: f64) -> f64 {
    if op == ast.O_ADD { ret x + y }
    if op == ast.O_SUB { ret x - y }
    if op == ast.O_MUL { ret x * y }
    if op == ast.O_DIV { ret x / y }
    if op == ast.O_MOD { ret fmod_js(x, y) }
    if op == ast.O_EXP {
        if is_nan(y) { ret nan() }
        if y == 0.0f64 { ret 1.0f64 }
        if (x == 1.0f64 || x == -1.0f64) && is_infinite(y) { ret nan() }
        ret math.pow(x, y)
    }
    if op == ast.O_SHL { ret f64(to_int32_value(x) << (to_uint32_bits(y) & 31u32)) }
    if op == ast.O_SHR { ret f64(to_int32_value(x) >> (to_uint32_bits(y) & 31u32)) }
    if op == ast.O_USHR { ret f64(to_uint32_bits(x) >> (to_uint32_bits(y) & 31u32)) }
    if op == ast.O_BITAND { ret f64(to_int32_value(x) & to_int32_value(y)) }
    if op == ast.O_BITOR { ret f64(to_int32_value(x) | to_int32_value(y)) }
    if op == ast.O_BITXOR { ret f64(to_int32_value(x) ^ to_int32_value(y)) }
    ret nan()
}

// Relational comparison: -1 false, 1 true, 0 undefined (NaN).
fn compare_values(it: *Interp, x: Value, y: Value, left_first: bool) -> (i32, bool, err) {
    // Result: (x < y as 1/0, undefined flag, err)
    var px = x
    var py = y
    if left_first {
        let (a1, e1) = to_primitive(it, x, "number")
        if e1 != ok { ret (0i32, false, e1) }
        px = a1
        let (b1, e2) = to_primitive(it, y, "number")
        if e2 != ok { ret (0i32, false, e2) }
        py = b1
    } else {
        let (b2, e3) = to_primitive(it, y, "number")
        if e3 != ok { ret (0i32, false, e3) }
        py = b2
        let (a2, e4) = to_primitive(it, x, "number")
        if e4 != ok { ret (0i32, false, e4) }
        px = a2
    }
    if is_string(px) && is_string(py) {
        let sx = value_str(px)
        let sy = value_str(py)
        if compare_utf16(sx, sy) < 0i32 { ret (1i32, false, ok) }
        ret (0i32, false, ok)
    }
    let (nx, ne1) = to_number(it, px)
    if ne1 != ok { ret (0i32, false, ne1) }
    let (ny, ne2) = to_number(it, py)
    if ne2 != ok { ret (0i32, false, ne2) }
    if is_nan(nx) || is_nan(ny) { ret (0i32, true, ok) }
    if nx < ny { ret (1i32, false, ok) }
    ret (0i32, false, ok)
}

fn num_of(v: Value) -> f64 {
    switch v {
    case .Num as n:
        ret n
    default:
        ret 0.0f64
    }
}

fn value_str(v: Value) -> str {
    switch v {
    case .Str as s:
        ret s
    default:
        ret ""
    }
}

// Compares by UTF-16 code units (surrogates sort below U+E000.. which UTF-8 byte order would not).
fn compare_utf16(x: str, y: str) -> i32 {
    var i = 0usize
    var j = 0usize
    while i < x.len && j < y.len {
        let (cx, lx) = decode_at(x, i)
        let (cy, ly) = decode_at(y, j)
        if cx != cy {
            var ux = cx
            var uy = cy
            if ux >= 65536u32 { ux = 55296u32 + ((ux - 65536u32) >> 10u32) }
            if uy >= 65536u32 { uy = 55296u32 + ((uy - 65536u32) >> 10u32) }
            if ux != uy {
                if ux < uy { ret -1i32 }
                ret 1i32
            }
            if cx < cy { ret -1i32 }
            ret 1i32
        }
        i += lx
        j += ly
    }
    if i < x.len { ret 1i32 }
    if j < y.len { ret -1i32 }
    ret 0i32
}

fn binary_op(it: *Interp, op: u8, x: Value, y: Value) -> (Value, err) {
    if op == ast.O_ADD {
        // Fast paths.
        if is_number(x) && is_number(y) { ret (num_value(num_of(x) + num_of(y)), ok) }
        let (px, e1) = to_primitive(it, x, "default")
        if e1 != ok { ret (undefv(), e1) }
        let (py, e2) = to_primitive(it, y, "default")
        if e2 != ok { ret (undefv(), e2) }
        if is_string(px) || is_string(py) {
            let (sx, e3) = to_string(it, px)
            if e3 != ok { ret (undefv(), e3) }
            let (sy, e4) = to_string(it, py)
            if e4 != ok { ret (undefv(), e4) }
            ret (str_value(str_concat(it, sx, sy)), ok)
        }
        let (nx2, e5) = to_number(it, px)
        if e5 != ok { ret (undefv(), e5) }
        let (ny2, e6) = to_number(it, py)
        if e6 != ok { ret (undefv(), e6) }
        ret (num_value(nx2 + ny2), ok)
    }
    if op == ast.O_SEQ { ret (bool_value(strict_equals(x, y)), ok) }
    if op == ast.O_SNE { ret (bool_value(!strict_equals(x, y)), ok) }
    if op == ast.O_EQ {
        let (r, re) = loose_equals(it, x, y)
        ret (bool_value(r), re)
    }
    if op == ast.O_NE {
        let (r2, re2) = loose_equals(it, x, y)
        ret (bool_value(!r2), re2)
    }
    if op == ast.O_LT {
        let (c, und, ce) = compare_values(it, x, y, true)
        if ce != ok { ret (undefv(), ce) }
        ret (bool_value(!und && c == 1i32), ok)
    }
    if op == ast.O_GT {
        let (c2, und2, ce2) = compare_values(it, y, x, false)
        if ce2 != ok { ret (undefv(), ce2) }
        ret (bool_value(!und2 && c2 == 1i32), ok)
    }
    if op == ast.O_LE {
        let (c3, und3, ce3) = compare_values(it, y, x, false)
        if ce3 != ok { ret (undefv(), ce3) }
        ret (bool_value(!und3 && c3 == 0i32), ok)
    }
    if op == ast.O_GE {
        let (c4, und4, ce4) = compare_values(it, x, y, true)
        if ce4 != ok { ret (undefv(), ce4) }
        ret (bool_value(!und4 && c4 == 0i32), ok)
    }
    if op == ast.O_INSTANCEOF {
        let (r3, re3) = instance_of(it, x, y)
        ret (bool_value(r3), re3)
    }
    if op == ast.O_IN {
        if !is_object(y) { ret (undefv(), throw_type(it, "Cannot use 'in' operator to search for a key in a non-object")) }
        let (k, ke) = to_property_key(it, x)
        if ke != ok { ret (undefv(), ke) }
        ret (bool_value(has_property(it, as_object(y), k)), ok)
    }
    // Arithmetic and bitwise.
    let (nx3, e7) = to_number(it, x)
    if e7 != ok { ret (undefv(), e7) }
    let (ny3, e8) = to_number(it, y)
    if e8 != ok { ret (undefv(), e8) }
    ret (num_value(arith(it, op, nx3, ny3)), ok)
}

// --- calls from the evaluator

fn eval_args(it: *Interp, f: *Frame, first: u32, count: u32) -> ([]const Value, err) {
    let (l, le) = list.init[Value](it.a, usize(count) + 1usize)
    var out = l
    if le != ok { ret (zero, le) }
    var i = 0usize
    while i < usize(count) {
        let aid = f.prog.kids[usize(first) + i]
        let an = f.prog.nodes[usize(aid)]
        if an.kind == ast.N_SPREAD {
            let (sv, se) = eval(it, f, an.a)
            if se != ok { ret (zero, se) }
            let (vals, ie) = iterate_to_list(it, sv)
            if ie != ok { ret (zero, ie) }
            var k = 0usize
            while k < vals.len {
                try list.push[Value](&out, vals.items[k])
                k += 1usize
            }
        } else {
            let (v, ve) = eval(it, f, aid)
            if ve != ok { ret (zero, ve) }
            try list.push[Value](&out, v)
        }
        i += 1usize
    }
    ret (list.slice_const[Value](&out), ok)
}

fn describe_callee(f: *const Frame, id: u32) -> str {
    let n = f.prog.nodes[usize(id)]
    if n.kind == ast.N_IDENT { ret n.text }
    if n.kind == ast.N_MEMBER && (n.flags & ast.F_COMPUTED) == 0u16 { ret n.text }
    ret "expression"
}

// Evaluates a callee, answering the function and its `this`.
fn eval_callee(it: *Interp, f: *Frame, id: u32) -> (Value, Value, err) {
    let n = f.prog.nodes[usize(id)]
    if n.kind == ast.N_MEMBER {
        if f.prog.nodes[usize(n.a)].kind == ast.N_SUPER {
            let (sv, se) = eval_super_member(it, f, n)
            ret (sv, f.this_val, se)
        }
        let (base, be) = eval(it, f, n.a)
        if be != ok { ret (undefv(), undefv(), be) }
        if (n.flags & ast.F_OPTIONAL) != 0u16 && is_nullish(base) { ret (undefv(), undefv(), OptShort) }
        let (key, ke) = member_key(it, f, n)
        if ke != ok { ret (undefv(), undefv(), ke) }
        let (fv, fe) = get_value(it, base, key)
        ret (fv, base, fe)
    }
    if n.kind == ast.N_OPTCHAIN {
        let (fv2, this2, e2) = eval_callee(it, f, n.a)
        if e2 == OptShort { ret (undefv(), undefv(), ok) }
        ret (fv2, this2, e2)
    }
    if n.kind == ast.N_IDENT {
        let (fv3, e3) = lookup_value(it, f, n.text)
        if e3 != ok { ret (undefv(), undefv(), e3) }
        // A `with` object supplies `this` for names it owns.
        var e = f.env
        let z = null_env()
        while e != z {
            if e.has_with && has_property(it, e.with_obj, key_of(n.text)) { ret (fv3, obj_value(e.with_obj), ok) }
            e = e.parent
        }
        ret (fv3, undefv(), ok)
    }
    let (fv4, e4) = eval(it, f, id)
    ret (fv4, undefv(), e4)
}

error OptShort

fn eval_super_member(it: *Interp, f: *Frame, n: ast.Node) -> (Value, err) {
    if !f.has_home { ret (undefv(), throw_syntax(it, "'super' keyword unexpected here")) }
    let (key, ke) = member_key(it, f, n)
    if ke != ok { ret (undefv(), ke) }
    if !f.home.has_proto { ret (undefv(), ok) }
    let (v, e) = get_prop(it, f.home.proto, key, f.this_val)
    ret (v, e)
}

fn eval_call(it: *Interp, f: *Frame, n: ast.Node) -> (Value, err) {
    let callee = f.prog.nodes[usize(n.a)]
    if callee.kind == ast.N_SUPER {
        // super(...): construct the parent with this frame's new.tgt.
        if !f.has_func { ret (undefv(), throw_syntax(it, "'super' keyword unexpected here")) }
        let ctor = f.func
        if !ctor.has_proto { ret (undefv(), throw_type(it, "Super constructor is not a constructor")) }
        let parent = obj_value(ctor.proto)
        if !is_constructor(parent) { ret (undefv(), throw_type(it, "Super constructor is not a constructor")) }
        let (args, ae) = eval_args(it, f, n.b, n.c)
        if ae != ok { ret (undefv(), ae) }
        let (r, re) = construct(it, parent, args, f.new_target)
        if re != ok { ret (undefv(), re) }
        if f.has_this { ret (undefv(), throw_reference(it, "Super constructor may only be called once")) }
        f.this_val = r
        f.has_this = true
        let fe = init_fields(it, ctor, as_object(r))
        if fe != ok { ret (undefv(), fe) }
        ret (r, ok)
    }
    let (fv, this_val, ce) = eval_callee(it, f, n.a)
    if ce != ok { ret (undefv(), ce) }
    if (n.flags & ast.F_OPTIONAL) != 0u16 && is_nullish(fv) { ret (undefv(), OptShort) }
    let (args2, ae2) = eval_args(it, f, n.b, n.c)
    if ae2 != ok { ret (undefv(), ae2) }
    if !is_callable(fv) { ret (undefv(), throw_type(it, str_concat(it, describe_callee(f, n.a), " is not a function"))) }
    // Direct eval sees the caller's scope.
    if callee.kind == ast.N_IDENT && str.eq(callee.text, "eval") && is_object(fv) && as_object(fv) == it.eval_fn {
        if args2.len == 0usize { ret (undefv(), ok) }
        let (r2, re2) = direct_eval(it, f, args2[0usize])
        ret (r2, re2)
    }
    let (r3, re3) = call_function(it, fv, this_val, args2)
    ret (r3, re3)
}

// --- the expression evaluator

fn tick(it: *Interp) -> err {
    it.steps += 1u64
    if it.step_limit != 0u64 && it.steps > it.step_limit { ret throw_range(it, "execution step limit exceeded") }
    ret ok
}

fn eval(it: *Interp, f: *Frame, id: u32) -> (Value, err) {
    let n = f.prog.nodes[usize(id)]
    let k = n.kind
    if k == ast.N_NUM { ret (num_value(n.num), ok) }
    if k == ast.N_STR { ret (str_value(n.text), ok) }
    if k == ast.N_IDENT {
        if str.eq(n.text, "undefined") {
            // `undefined` is a non-writable global; skip the lookup unless shadowed.
            var e = f.env
            let z = null_env()
            var shadowed = false
            while e != z {
                let (at, found) = env_index(e, "undefined")
                if found { shadowed = true }
                e = e.parent
            }
            if !shadowed { ret (undefv(), ok) }
        }
        let (v, e2) = lookup_value(it, f, n.text)
        ret (v, e2)
    }
    if k == ast.N_THIS {
        if !f.has_this { ret (undefv(), throw_reference(it, "Must call super constructor in derived class before accessing 'this'")) }
        ret (f.this_val, ok)
    }
    if k == ast.N_NULL { ret (null_value(), ok) }
    if k == ast.N_TRUE { ret (bool_value(true), ok) }
    if k == ast.N_FALSE { ret (bool_value(false), ok) }
    try tick(it)
    if k == ast.N_MEMBER {
        if f.prog.nodes[usize(n.a)].kind == ast.N_SUPER {
            let (sv, se) = eval_super_member(it, f, n)
            ret (sv, se)
        }
        let (base, be) = eval(it, f, n.a)
        if be != ok { ret (undefv(), be) }
        if (n.flags & ast.F_OPTIONAL) != 0u16 && is_nullish(base) { ret (undefv(), OptShort) }
        let (key, ke) = member_key(it, f, n)
        if ke != ok { ret (undefv(), ke) }
        let (v2, ve) = get_value(it, base, key)
        ret (v2, ve)
    }
    if k == ast.N_CALL {
        let (rt2, re2) = eval_call(it, f, n)
        ret (rt2, re2)
    }
    if k == ast.N_ASSIGN {
        let (rt3, re3) = eval_assign(it, f, n)
        ret (rt3, re3)
    }
    if k == ast.N_BINARY {
        let (l, le) = eval(it, f, n.a)
        if le != ok { ret (undefv(), le) }
        let (r, re) = eval(it, f, n.b)
        if re != ok { ret (undefv(), re) }
        let (v3, e3) = binary_op(it, n.op, l, r)
        ret (v3, e3)
    }
    if k == ast.N_LOGICAL {
        let (l2, le2) = eval(it, f, n.a)
        if le2 != ok { ret (undefv(), le2) }
        if n.op == ast.O_AND {
            if !to_boolean(l2) { ret (l2, ok) }
        } else if n.op == ast.O_OR {
            if to_boolean(l2) { ret (l2, ok) }
        } else {
            if !is_nullish(l2) { ret (l2, ok) }
        }
        let (r2, re2) = eval(it, f, n.b)
        ret (r2, re2)
    }
    if k == ast.N_UNARY {
        let (rt4, re4) = eval_unary(it, f, n)
        ret (rt4, re4)
    }
    if k == ast.N_UPDATE {
        let (rt5, re5) = eval_update(it, f, n)
        ret (rt5, re5)
    }
    if k == ast.N_COND {
        let (c, ce) = eval(it, f, n.a)
        if ce != ok { ret (undefv(), ce) }
        if to_boolean(c) {
            let (v4, e4) = eval(it, f, n.b)
            ret (v4, e4)
        }
        let (v5, e5) = eval(it, f, n.c)
        ret (v5, e5)
    }
    if k == ast.N_ARRAY {
        let arr = new_array(it)
        var i = 0usize
        while i < usize(n.b) {
            let eid = f.prog.kids[usize(n.a) + i]
            let en = f.prog.nodes[usize(eid)]
            i += 1usize
            if en.kind == ast.N_HOLE {
                try list.push[Value](&arr.elems, hole_value(it))
                arr.num = f64(arr.elems.len)
                continue
            }
            if en.kind == ast.N_SPREAD {
                let (sv2, se2) = eval(it, f, en.a)
                if se2 != ok { ret (undefv(), se2) }
                let (vals, ie) = iterate_to_list(it, sv2)
                if ie != ok { ret (undefv(), ie) }
                var j = 0usize
                while j < vals.len {
                    try array_push(it, arr, vals.items[j])
                    j += 1usize
                }
                continue
            }
            let (ev, ee) = eval(it, f, eid)
            if ee != ok { ret (undefv(), ee) }
            try array_push(it, arr, ev)
        }
        ret (obj_value(arr), ok)
    }
    if k == ast.N_OBJECT {
        let (rt6, re6) = eval_object(it, f, n)
        ret (rt6, re6)
    }
    if k == ast.N_FUNC {
        let (fo, fe) = make_function(it, f, id)
        if fe != ok { ret (undefv(), fe) }
        // A named function expression binds its own name in a scope of its own.
        if n.text.len > 0usize && (n.flags & ast.F_DECL) == 0u16 && (n.flags & ast.F_ARROW) == 0u16 && (n.flags & ast.F_METHOD) == 0u16 {
            let ne = new_env(it, f.env)
            try declare(it, ne, n.text, obj_value(fo), B_CONST)
            fo.env = ne
        }
        ret (obj_value(fo), ok)
    }
    if k == ast.N_CLASS {
        let (cv, ce2) = eval_class(it, f, n)
        ret (cv, ce2)
    }
    if k == ast.N_NEW {
        let (cv2, ce3) = eval(it, f, n.a)
        if ce3 != ok { ret (undefv(), ce3) }
        let (args, ae) = eval_args(it, f, n.b, n.c)
        if ae != ok { ret (undefv(), ae) }
        if !is_constructor(cv2) { ret (undefv(), throw_type(it, str_concat(it, describe_callee(f, n.a), " is not a constructor"))) }
        let (r3, re3) = construct(it, cv2, args, cv2)
        ret (r3, re3)
    }
    if k == ast.N_TEMPLATE {
        let (b0, be0) = str.builder(it.a, 64usize)
        if be0 != ok { ret (undefv(), throw_range(it, "out of memory")) }
        var parts: list.List[str] = zero
        let (pl, ple) = list.init[str](it.a, usize(n.b) * 2usize + 1usize)
        parts = pl
        var s = 0usize
        // Evaluate substitutions first (a builder must stay on top of the arena).
        while s < usize(n.b) {
            try list.push[str](&parts, f.prog.strs[usize(n.a) + s].cooked)
            if s < usize(n.d) {
                let (sv3, se3) = eval(it, f, f.prog.kids[usize(n.c) + s])
                if se3 != ok { ret (undefv(), se3) }
                if is_object(sv3) || is_symbol_value(sv3) {
                    let (ps, pse) = to_string(it, sv3)
                    if pse != ok { ret (undefv(), pse) }
                    try list.push[str](&parts, ps)
                } else {
                    let (ps2, pse2) = to_string(it, sv3)
                    if pse2 != ok { ret (undefv(), pse2) }
                    try list.push[str](&parts, ps2)
                }
            }
            s += 1usize
        }
        var total = 0usize
        var q = 0usize
        while q < parts.len {
            total += parts.items[q].len
            q += 1usize
        }
        let (b1, be1) = str.builder(it.a, total + 1usize)
        if be1 != ok { ret (undefv(), throw_range(it, "out of memory")) }
        var out = b1
        var r4 = 0usize
        while r4 < parts.len {
            let pe = str.push(&out, parts.items[r4])
            r4 += 1usize
        }
        ret (str_value(str.done(&out)), ok)
    }
    if k == ast.N_TAGGED {
        let (rt7, re7) = eval_tagged(it, f, n)
        ret (rt7, re7)
    }
    if k == ast.N_SEQ {
        var last = undefv()
        var i2 = 0usize
        while i2 < usize(n.b) {
            let (v6, e6) = eval(it, f, f.prog.kids[usize(n.a) + i2])
            if e6 != ok { ret (undefv(), e6) }
            last = v6
            i2 += 1usize
        }
        ret (last, ok)
    }
    if k == ast.N_OPTCHAIN {
        let (v7, e7) = eval(it, f, n.a)
        if e7 == OptShort { ret (undefv(), ok) }
        ret (v7, e7)
    }
    if k == ast.N_REGEX {
        let (rv, re4) = make_regexp(it, n.text, n.text2)
        ret (rv, re4)
    }
    if k == ast.N_SPREAD { ret (undefv(), throw_syntax(it, "unexpected spread")) }
    if k == ast.N_NEWTARGET {
        if !f.has_func && is_undefined(f.new_target) { ret (undefv(), ok) }
        ret (f.new_target, ok)
    }
    if k == ast.N_YIELD {
        var yv = undefv()
        if n.a != ast.NONE {
            let (ev, ee) = eval(it, f, n.a)
            if ee != ok { ret (undefv(), ee) }
            yv = ev
        }
        if (n.flags & ast.F_DELEGATE) != 0u16 {
            if f.has_gen && gen_state_of(f).kind == 2u8 {
                let (ar, are) = gen_yield_star_async(it, f, yv)
                ret (ar, are)
            }
            let (dr, de) = gen_yield_star(it, f, yv)
            ret (dr, de)
        }
        let (r5, re5) = gen_yield(it, f, yv)
        ret (r5, re5)
    }
    if k == ast.N_AWAIT {
        let (av, ae) = eval(it, f, n.a)
        if ae != ok { ret (undefv(), ae) }
        let (r6, re6) = await_value(it, f, av)
        ret (r6, re6)
    }
    if k == ast.N_IMPORT_CALL || k == ast.N_IMPORT_META { ret (undefv(), throw_syntax(it, "modules are not supported yet")) }
    if k == ast.N_PRIVATE { ret (undefv(), throw_syntax(it, "unexpected private name")) }
    if k == ast.N_SUPER { ret (undefv(), throw_syntax(it, "'super' keyword unexpected here")) }
    ret (undefv(), throw_syntax(it, "unsupported expression"))
}

fn is_symbol_value(v: Value) -> bool {
    switch v {
    case .Sym as s:
        ret true
    default:
        ret false
    }
}

// Builds a RegExp object through the realm's constructor (installed by the builtins).
fn make_regexp(it: *Interp, pattern: str, flags: str) -> (Value, err) {
    let (ctor, ce) = get_prop(it, it.global, key_of("RegExp"), obj_value(it.global))
    if ce != ok { ret (undefv(), ce) }
    if !is_constructor(ctor) { ret (undefv(), throw_syntax(it, "RegExp is not available")) }
    let (r, re) = construct(it, ctor, two_args(it, str_value(pattern), str_value(flags)), ctor)
    ret (r, re)
}

fn eval_tagged(it: *Interp, f: *Frame, n: ast.Node) -> (Value, err) {
    let tn = f.prog.nodes[usize(n.b)]
    let (fv, this_val, fe) = eval_callee(it, f, n.a)
    if fe != ok { ret (undefv(), fe) }
    // The strings array (cooked) with a frozen `raw` array, one per call site.
    let strings = new_array(it)
    let raw = new_array(it)
    var s = 0usize
    while s < usize(tn.b) {
        let ts = f.prog.strs[usize(tn.a) + s]
        if ts.valid { try array_push(it, strings, str_value(ts.cooked)) } else { try array_push(it, strings, undefv()) }
        try array_push(it, raw, str_value(ts.raw))
        s += 1usize
    }
    try define_data(it, strings, key_of("raw"), obj_value(raw), 0u8)
    freeze_object(it, raw)
    freeze_object(it, strings)
    let (l, le) = list.init[Value](it.a, usize(tn.d) + 1usize)
    var args = l
    if le != ok { ret (undefv(), le) }
    try list.push[Value](&args, obj_value(strings))
    var e = 0usize
    while e < usize(tn.d) {
        let (v, ve) = eval(it, f, f.prog.kids[usize(tn.c) + e])
        if ve != ok { ret (undefv(), ve) }
        try list.push[Value](&args, v)
        e += 1usize
    }
    if !is_callable(fv) { ret (undefv(), throw_type(it, "tag is not a function")) }
    let (r, re) = call_function(it, fv, this_val, list.slice_const[Value](&args))
    ret (r, re)
}

fn freeze_object(it: *Interp, o: *Obj) {
    if o.class == C_ARRAY { let m = materialize_elements(it, o) }
    var i = 0usize
    while i < o.props.len {
        o.props.items[i].flags = o.props.items[i].flags & (255u8 - P_CONFIGURABLE)
        if (o.props.items[i].flags & P_ACCESSOR) == 0u8 { o.props.items[i].flags = o.props.items[i].flags & (255u8 - P_WRITABLE) }
        i += 1usize
    }
    o.extensible = false
    if o.class == C_ARRAY { o.text = "1" }
}

fn eval_unary(it: *Interp, f: *Frame, n: ast.Node) -> (Value, err) {
    if n.op == ast.O_TYPEOF {
        let an = f.prog.nodes[usize(n.a)]
        if an.kind == ast.N_IDENT {
            // `typeof undeclared` is "undefined" rather than a ReferenceError.
            let (v, e) = lookup_value(it, f, an.text)
            if e != ok {
                if is_reference_error(it) { ret (str_value("undefined"), ok) }
                ret (undefv(), e)
            }
            ret (str_value(type_of(v)), ok)
        }
        let (v2, e2) = eval(it, f, n.a)
        if e2 != ok { ret (undefv(), e2) }
        ret (str_value(type_of(v2)), ok)
    }
    if n.op == ast.O_DELETE {
        let an2 = f.prog.nodes[usize(n.a)]
        if an2.kind == ast.N_MEMBER {
            let (base, be) = eval(it, f, an2.a)
            if be != ok { ret (undefv(), be) }
            let (key, ke) = member_key(it, f, an2)
            if ke != ok { ret (undefv(), ke) }
            let (bo, oe) = to_object(it, base)
            if oe != ok { ret (undefv(), oe) }
            let done = delete_prop(it, bo, key)
            if !done && f.strict { ret (undefv(), throw_type(it, "Cannot delete property")) }
            ret (bool_value(done), ok)
        }
        if an2.kind == ast.N_OPTCHAIN {
            let (r, re) = eval(it, f, n.a)
            if re == OptShort { ret (bool_value(true), ok) }
            ret (bool_value(true), re)
        }
        if an2.kind == ast.N_IDENT {
            // Variables are not deletable; globals created by assignment are.
            var e3 = f.env
            let z = null_env()
            while e3 != z {
                let (at, found) = env_index(e3, an2.text)
                if found { ret (bool_value(false), ok) }
                e3 = e3.parent
            }
            let done2 = delete_prop(it, it.global, key_of(an2.text))
            ret (bool_value(done2), ok)
        }
        let (v3, e4) = eval(it, f, n.a)
        if e4 != ok { ret (undefv(), e4) }
        ret (bool_value(true), ok)
    }
    let (v4, e5) = eval(it, f, n.a)
    if e5 != ok { ret (undefv(), e5) }
    if n.op == ast.O_NOT { ret (bool_value(!to_boolean(v4)), ok) }
    if n.op == ast.O_VOID { ret (undefv(), ok) }
    let (num, ne) = to_number(it, v4)
    if ne != ok { ret (undefv(), ne) }
    if n.op == ast.O_NEG { ret (num_value(-num), ok) }
    if n.op == ast.O_PLUS { ret (num_value(num), ok) }
    if n.op == ast.O_BITNOT { ret (num_value(f64(~to_int32_value(num))), ok) }
    ret (undefv(), ok)
}

// Reads the current value of an assignment tgt and answers a closure-free writer: (value, base, key).
fn eval_update(it: *Interp, f: *Frame, n: ast.Node) -> (Value, err) {
    let tn = f.prog.nodes[usize(n.a)]
    var delta = 1.0f64
    if n.op == ast.O_DEC { delta = -1.0f64 }
    let prefix = (n.flags & ast.F_PREFIX) != 0u16
    if tn.kind == ast.N_IDENT {
        let (old, oe) = lookup_value(it, f, tn.text)
        if oe != ok { ret (undefv(), oe) }
        let (num, ne) = to_number(it, old)
        if ne != ok { ret (undefv(), ne) }
        let nv = num + delta
        let ae = assign_name(it, f, tn.text, num_value(nv))
        if ae != ok { ret (undefv(), ae) }
        if prefix { ret (num_value(nv), ok) }
        ret (num_value(num), ok)
    }
    if tn.kind == ast.N_MEMBER {
        var base = f.this_val
        var key = key_of("")
        if f.prog.nodes[usize(tn.a)].kind == ast.N_SUPER {
            let (kk, kke) = member_key(it, f, tn)
            if kke != ok { ret (undefv(), kke) }
            key = kk
        } else {
            let (b, be) = eval(it, f, tn.a)
            if be != ok { ret (undefv(), be) }
            base = b
            let (k2, ke) = member_key(it, f, tn)
            if ke != ok { ret (undefv(), ke) }
            key = k2
        }
        let (old2, oe2) = get_value(it, base, key)
        if oe2 != ok { ret (undefv(), oe2) }
        let (num2, ne2) = to_number(it, old2)
        if ne2 != ok { ret (undefv(), ne2) }
        let nv2 = num2 + delta
        let pe = put(it, base, key, num_value(nv2), f.strict)
        if pe != ok { ret (undefv(), pe) }
        if prefix { ret (num_value(nv2), ok) }
        ret (num_value(num2), ok)
    }
    ret (undefv(), throw_syntax(it, "Invalid left-hand side expression in postfix operation"))
}

fn eval_assign(it: *Interp, f: *Frame, n: ast.Node) -> (Value, err) {
    let tn = f.prog.nodes[usize(n.a)]
    let logical = (n.flags & ast.F_OPTIONAL) != 0u16
    if n.op == ast.O_ASSIGN && !logical {
        if tn.kind == ast.N_IDENT {
            let (v, e) = eval_named(it, f, n.b, tn.text)
            if e != ok { ret (undefv(), e) }
            let ae = assign_name(it, f, tn.text, v)
            if ae != ok { ret (undefv(), ae) }
            ret (v, ok)
        }
        if tn.kind == ast.N_MEMBER {
            var base = f.this_val
            var key = key_of("")
            if f.prog.nodes[usize(tn.a)].kind == ast.N_SUPER {
                let (kk, kke) = member_key(it, f, tn)
                if kke != ok { ret (undefv(), kke) }
                key = kk
            } else {
                let (b, be) = eval(it, f, tn.a)
                if be != ok { ret (undefv(), be) }
                base = b
                let (k2, ke) = member_key(it, f, tn)
                if ke != ok { ret (undefv(), ke) }
                key = k2
            }
            let (v2, e2) = eval(it, f, n.b)
            if e2 != ok { ret (undefv(), e2) }
            let pe = put(it, base, key, v2, f.strict)
            if pe != ok { ret (undefv(), pe) }
            ret (v2, ok)
        }
        if tn.kind == ast.N_ARRAY || tn.kind == ast.N_OBJECT {
            let (v3, e3) = eval(it, f, n.b)
            if e3 != ok { ret (undefv(), e3) }
            let be2 = bind_pattern(it, f, n.a, v3, 0u8)
            if be2 != ok { ret (undefv(), be2) }
            ret (v3, ok)
        }
        ret (undefv(), throw_syntax(it, "Invalid left-hand side in assignment"))
    }
    // Compound and logical assignment: read, combine, write.
    if tn.kind == ast.N_IDENT {
        let (old, oe) = lookup_value(it, f, tn.text)
        if oe != ok { ret (undefv(), oe) }
        if logical {
            if n.op == ast.O_AND && !to_boolean(old) { ret (old, ok) }
            if n.op == ast.O_OR && to_boolean(old) { ret (old, ok) }
            if n.op == ast.O_NULLISH && !is_nullish(old) { ret (old, ok) }
            let (rv, re) = eval_named(it, f, n.b, tn.text)
            if re != ok { ret (undefv(), re) }
            let ae2 = assign_name(it, f, tn.text, rv)
            if ae2 != ok { ret (undefv(), ae2) }
            ret (rv, ok)
        }
        let (rhs, rhe) = eval(it, f, n.b)
        if rhe != ok { ret (undefv(), rhe) }
        let (res, ce) = binary_op(it, n.op, old, rhs)
        if ce != ok { ret (undefv(), ce) }
        let ae3 = assign_name(it, f, tn.text, res)
        if ae3 != ok { ret (undefv(), ae3) }
        ret (res, ok)
    }
    if tn.kind == ast.N_MEMBER {
        var base = f.this_val
        var key = key_of("")
        if f.prog.nodes[usize(tn.a)].kind == ast.N_SUPER {
            let (kk2, kke2) = member_key(it, f, tn)
            if kke2 != ok { ret (undefv(), kke2) }
            key = kk2
        } else {
            let (b2, be3) = eval(it, f, tn.a)
            if be3 != ok { ret (undefv(), be3) }
            base = b2
            let (k3, ke3) = member_key(it, f, tn)
            if ke3 != ok { ret (undefv(), ke3) }
            key = k3
        }
        let (old2, oe2) = get_value(it, base, key)
        if oe2 != ok { ret (undefv(), oe2) }
        if logical {
            if n.op == ast.O_AND && !to_boolean(old2) { ret (old2, ok) }
            if n.op == ast.O_OR && to_boolean(old2) { ret (old2, ok) }
            if n.op == ast.O_NULLISH && !is_nullish(old2) { ret (old2, ok) }
            let (rv2, re2) = eval(it, f, n.b)
            if re2 != ok { ret (undefv(), re2) }
            let pe2 = put(it, base, key, rv2, f.strict)
            if pe2 != ok { ret (undefv(), pe2) }
            ret (rv2, ok)
        }
        let (rhs2, rhe2) = eval(it, f, n.b)
        if rhe2 != ok { ret (undefv(), rhe2) }
        let (res2, ce2) = binary_op(it, n.op, old2, rhs2)
        if ce2 != ok { ret (undefv(), ce2) }
        let pe3 = put(it, base, key, res2, f.strict)
        if pe3 != ok { ret (undefv(), pe3) }
        ret (res2, ok)
    }
    ret (undefv(), throw_syntax(it, "Invalid left-hand side in assignment"))
}

fn eval_object(it: *Interp, f: *Frame, n: ast.Node) -> (Value, err) {
    let o = new_plain(it)
    var i = 0usize
    while i < usize(n.b) {
        let pid = f.prog.kids[usize(n.a) + i]
        let pn = f.prog.nodes[usize(pid)]
        i += 1usize
        if pn.op == ast.M_SPREAD {
            let (sv, se) = eval(it, f, pn.b)
            if se != ok { ret (undefv(), se) }
            let ce = copy_data_properties(it, o, sv, zero_keys())
            if ce != ok { ret (undefv(), ce) }
            continue
        }
        var key = key_of("")
        if (pn.flags & ast.F_COMPUTED) != 0u16 {
            let (kv, kve) = eval(it, f, pn.a)
            if kve != ok { ret (undefv(), kve) }
            let (k2, k2e) = to_property_key(it, kv)
            if k2e != ok { ret (undefv(), k2e) }
            key = k2
        } else {
            let kn = f.prog.nodes[usize(pn.a)]
            if kn.kind == ast.N_NUM { key = key_of(number_to_string(it.a, kn.num)) } else { key = key_of(kn.text) }
        }
        if pn.op == ast.M_INIT {
            let nm = key_name_for_function(it, key)
            let (v, ve) = eval_named(it, f, pn.b, nm)
            if ve != ok { ret (undefv(), ve) }
            // `__proto__: value` sets the prototype.
            if (pn.flags & ast.F_COMPUTED) == 0u16 && (pn.flags & ast.F_SHORTHAND) == 0u16 && !is_symbol_key(key) && str.eq(key.name, "__proto__") {
                if is_object(v) {
                    o.proto = as_object(v)
                    o.has_proto = true
                } else if is_null(v) {
                    o.has_proto = false
                    o.proto = null_obj()
                }
                continue
            }
            let (done, de) = define_own(it, o, key, data_desc(v, P_DEFAULT))
            if de != ok { ret (undefv(), de) }
            continue
        }
        // Methods and accessors.
        let (fo, fe) = make_function(it, f, pn.b)
        if fe != ok { ret (undefv(), fe) }
        fo.home = o
        fo.has_home = true
        if pn.op == ast.M_METHOD {
            set_function_name(it, obj_value(fo), key_name_for_function(it, key))
            let (done2, de2) = define_own(it, o, key, data_desc(obj_value(fo), P_DEFAULT))
            if de2 != ok { ret (undefv(), de2) }
        } else {
            var prefix = "get "
            if pn.op == ast.M_SET { prefix = "set " }
            set_function_name(it, obj_value(fo), str_concat(it, prefix, key_name_for_function(it, key)))
            var d = empty_desc()
            d.has_enumerable = true
            d.enumerable = true
            d.has_configurable = true
            d.configurable = true
            if pn.op == ast.M_GET {
                d.has_get = true
                d.getter = obj_value(fo)
            } else {
                d.has_set = true
                d.setter = obj_value(fo)
            }
            let (done3, de3) = define_own(it, o, key, d)
            if de3 != ok { ret (undefv(), de3) }
        }
    }
    ret (obj_value(o), ok)
}

fn zero_keys() -> []const Key {
    var none: []const Key = zero
    ret none
}

fn key_name_for_function(it: *Interp, key: Key) -> str {
    if is_symbol_key(key) {
        if key.sym.has_description { ret str_concat3(it, "[", key.sym.description, "]") }
        ret ""
    }
    ret key.name
}

// CopyDataProperties (object spread and rest).
fn copy_data_properties(it: *Interp, tgt: *Obj, source: Value, excluded: []const Key) -> err {
    if is_nullish(source) { ret ok }
    let (src, se) = to_object(it, source)
    if se != ok { ret se }
    let (keys, ke) = own_keys(it, src)
    if ke != ok { ret ke }
    var i = 0usize
    while i < keys.len {
        var skip = false
        var j = 0usize
        while j < excluded.len {
            if keys_equal(excluded[j], keys[i]) { skip = true }
            j += 1usize
        }
        if !skip {
            let (p, found) = get_own(it, src, keys[i])
            if found && (p.flags & P_ENUMERABLE) != 0u8 {
                let (v, ve) = get_prop(it, src, keys[i], obj_value(src))
                if ve != ok { ret ve }
                let (done, de) = define_own(it, tgt, keys[i], data_desc(v, P_DEFAULT))
                if de != ok { ret de }
            }
        }
        i += 1usize
    }
    ret ok
}

// --- classes

fn eval_class(it: *Interp, f: *Frame, n: ast.Node) -> (Value, err) {
    let class_env = new_env(it, f.env)
    let saved_env = f.env
    let saved_strict = f.strict
    f.env = class_env
    f.strict = true
    // Private names of this class.
    var m = 0usize
    while m < usize(n.c) {
        let mem_node = f.prog.nodes[usize(f.prog.kids[usize(n.b) + m])]
        if mem_node.op != ast.M_STATIC_BLOCK {
            let kn = f.prog.nodes[usize(mem_node.a)]
            if kn.kind == ast.N_PRIVATE {
                let (pn, found) = env_index(class_env, str_concat(it, "#", kn.text))
                if !found {
                    let sym = new_symbol(it, kn.text, true)
                    sym.private = true
                    let de = declare(it, class_env, str_concat(it, "#", kn.text), Value { Sym: sym }, 0u8)
                    if de != ok {
                        f.env = saved_env
                        f.strict = saved_strict
                        ret (undefv(), de)
                    }
                }
            }
        }
        m += 1usize
    }
    let (r, re) = eval_class_body(it, f, n, class_env)
    f.env = saved_env
    f.strict = saved_strict
    ret (r, re)
}

fn eval_class_body(it: *Interp, f: *Frame, n: ast.Node, class_env: *Env) -> (Value, err) {
    var proto_parent = it.protos.object
    var ctor_parent = it.protos.function
    var has_proto_parent = true
    if n.a != ast.NONE {
        let (sv, se) = eval(it, f, n.a)
        if se != ok { ret (undefv(), se) }
        if is_null(sv) {
            has_proto_parent = false
            proto_parent = null_obj()
        } else {
            if !is_constructor(sv) { ret (undefv(), throw_type(it, "Class extends value is not a constructor or null")) }
            let so = as_object(sv)
            let (pp, ppe) = get_prop(it, so, key_of("prototype"), sv)
            if ppe != ok { ret (undefv(), ppe) }
            if is_object(pp) {
                proto_parent = as_object(pp)
            } else if is_null(pp) {
                has_proto_parent = false
                proto_parent = null_obj()
            } else {
                ret (undefv(), throw_type(it, "Class extends value does not have valid prototype property"))
            }
            ctor_parent = so
        }
    }
    let proto = new_obj(it, C_OBJECT, proto_parent)
    if !has_proto_parent {
        proto.has_proto = false
        proto.proto = null_obj()
    }
    // The constructor: the `constructor` method or a synthesised default.
    var ctor_node = ast.NONE
    var i = 0usize
    while i < usize(n.c) {
        let mem_id = f.prog.kids[usize(n.b) + i]
        let mn = f.prog.nodes[usize(mem_id)]
        if mn.op == ast.M_METHOD && (mn.flags & ast.F_STATIC) == 0u16 && (mn.flags & ast.F_COMPUTED) == 0u16 {
            let kn = f.prog.nodes[usize(mn.a)]
            if kn.kind == ast.N_STR && str.eq(kn.text, "constructor") { ctor_node = mn.b }
        }
        i += 1usize
    }
    var ctor: *Obj = null_obj()
    if ctor_node != ast.NONE {
        let (co, ce) = make_function(it, f, ctor_node)
        if ce != ok { ret (undefv(), ce) }
        ctor = co
    } else {
        ctor = new_obj(it, C_FUNCTION, it.protos.function)
        ctor.prog = f.prog
        ctor.node = ast.NONE
        ctor.env = f.env
        ctor.native = default_constructor
        ctor.has_native = true
        let de = define_data(it, ctor, key_of("length"), num_value(0.0f64), P_CONFIGURABLE)
    }
    ctor.ctor_kind = K_BASE
    if n.a != ast.NONE { ctor.ctor_kind = K_DERIVED }
    ctor.num = 1.0f64
    ctor.text = n.text2
    ctor.proto = ctor_parent
    ctor.has_proto = true
    ctor.home = proto
    ctor.has_home = true
    let name = n.text
    try define_data(it, ctor, key_of("name"), str_value(name), P_CONFIGURABLE)
    try define_data(it, ctor, key_of("prototype"), obj_value(proto), 0u8)
    try define_data(it, proto, key_of("constructor"), obj_value(ctor), P_HIDDEN)
    if n.text.len > 0usize { try declare(it, class_env, n.text, undefv(), B_CONST | B_TDZ) }
    // Members.
    let (field_list, fle) = list.init[Value](it.a, 4usize)
    var fields = field_list
    let static_fields = new_array(it)
    var j = 0usize
    while j < usize(n.c) {
        let mem_id2 = f.prog.kids[usize(n.b) + j]
        let mn2 = f.prog.nodes[usize(mem_id2)]
        j += 1usize
        let is_static = (mn2.flags & ast.F_STATIC) != 0u16
        let tgt = ctor
        if mn2.op == ast.M_STATIC_BLOCK {
            let (sbf, sbe) = make_function(it, f, mn2.b)
            if sbe != ok { ret (undefv(), sbe) }
            sbf.home = ctor
            sbf.has_home = true
            let sbe2 = array_push(it, static_fields, obj_value(sbf))
            continue
        }
        var key = key_of("")
        let kn2 = f.prog.nodes[usize(mn2.a)]
        if (mn2.flags & ast.F_COMPUTED) != 0u16 {
            let (kv, kve) = eval(it, f, mn2.a)
            if kve != ok { ret (undefv(), kve) }
            let (k2, k2e) = to_property_key(it, kv)
            if k2e != ok { ret (undefv(), k2e) }
            key = k2
        } else if kn2.kind == ast.N_PRIVATE {
            let (sv2, sve) = lookup_value(it, f, str_concat(it, "#", kn2.text))
            if sve != ok { ret (undefv(), sve) }
            switch sv2 {
            case .Sym as ps:
                key = key_of_symbol(ps)
            default:
                key = key_of("")
            }
        } else if kn2.kind == ast.N_NUM {
            key = key_of(number_to_string(it.a, kn2.num))
        } else {
            key = key_of(kn2.text)
        }
        var holder = proto
        if is_static { holder = ctor }
        if mn2.op == ast.M_FIELD {
            // Instance fields are initialised per instance; static ones now.
            var init_fn = undefv()
            if mn2.b != ast.NONE {
                let (ff, ffe) = make_function(it, f, mn2.b)
                if ffe != ok { ret (undefv(), ffe) }
                ff.home = holder
                ff.has_home = true
                init_fn = obj_value(ff)
            }
            let entry = array_from(it, two_args(it, key_to_value(key), init_fn))
            if is_static {
                let pe = array_push(it, static_fields, obj_value(entry))
            } else {
                try list.push[Value](&fields, obj_value(entry))
            }
            continue
        }
        // Methods and accessors.
        if mn2.b == ast.NONE { continue }
        if ctor_node != ast.NONE && mn2.b == ctor_node { continue }
        let (fo, fe) = make_function(it, f, mn2.b)
        if fe != ok { ret (undefv(), fe) }
        fo.home = holder
        fo.has_home = true
        fo.ctor_kind = K_NONE
        if mn2.op == ast.M_METHOD {
            set_function_name(it, obj_value(fo), key_name_for_function(it, key))
            let (done, de) = define_own(it, holder, key, data_desc(obj_value(fo), P_HIDDEN))
            if de != ok { ret (undefv(), de) }
        } else {
            var prefix = "get "
            if mn2.op == ast.M_SET { prefix = "set " }
            set_function_name(it, obj_value(fo), str_concat(it, prefix, key_name_for_function(it, key)))
            var d = empty_desc()
            d.has_enumerable = true
            d.enumerable = false
            d.has_configurable = true
            d.configurable = true
            if mn2.op == ast.M_GET {
                d.has_get = true
                d.getter = obj_value(fo)
            } else {
                d.has_set = true
                d.setter = obj_value(fo)
            }
            let (done2, de2) = define_own(it, holder, key, d)
            if de2 != ok { ret (undefv(), de2) }
        }
    }
    if fields.len > 0usize {
        ctor.fields = array_from(it, list.slice_const[Value](&fields))
        ctor.has_fields = true
    }
    if n.text.len > 0usize { try init_binding(it, class_env, n.text, obj_value(ctor)) }
    // Static fields and blocks, in order, with `this` the class.
    var s = 0usize
    while s < static_fields.elems.len {
        let item = as_object(static_fields.elems.items[s])
        s += 1usize
        if item.class == C_FUNCTION {
            let (r, re) = call_function(it, obj_value(item), obj_value(ctor), zero_args())
            if re != ok { ret (undefv(), re) }
        } else {
            let kv2 = item.elems.items[0usize]
            let iv = item.elems.items[1usize]
            var val = undefv()
            if is_object(iv) {
                let (r2, re2) = call_function(it, iv, obj_value(ctor), zero_args())
                if re2 != ok { ret (undefv(), re2) }
                val = r2
            }
            var key3 = key_of("")
            switch kv2 {
            case .Sym as ks:
                key3 = key_of_symbol(ks)
            case .Str as kstr:
                key3 = key_of(kstr)
            default:
                key3 = key_of("")
            }
            let fe2 = field_define(it, ctor, key3, val)
            if fe2 != ok { ret (undefv(), fe2) }
        }
    }
    ret (obj_value(ctor), ok)
}

fn default_constructor(it: *Interp, this_val: Value, args: []const Value) -> (Value, err) {
    let ctor = it.callee
    if !it.has_new_target { ret (undefv(), throw_type(it, "Class constructor cannot be invoked without 'new'")) }
    if ctor.ctor_kind == K_DERIVED {
        let parent = obj_value(ctor.proto)
        if !is_constructor(parent) { ret (undefv(), throw_type(it, "Super constructor is not a constructor")) }
        let nt = it.new_target
        let (r, re) = construct(it, parent, args, nt)
        if re != ok { ret (undefv(), re) }
        let fe = init_fields(it, ctor, as_object(r))
        if fe != ok { ret (undefv(), fe) }
        ret (r, ok)
    }
    let nto = as_object(it.new_target)
    let (proto, pe) = proto_value_of(it, nto, it.protos.object)
    if pe != ok { ret (undefv(), pe) }
    let o = new_obj(it, C_OBJECT, proto)
    let fe2 = init_fields(it, ctor, o)
    if fe2 != ok { ret (undefv(), fe2) }
    ret (obj_value(o), ok)
}

// --- statements

fn is_lexical_decl(f: *const Frame, id: u32) -> bool {
    let n = f.prog.nodes[usize(id)]
    if n.kind == ast.N_VAR { ret n.op != ast.D_VAR }
    if n.kind == ast.N_CLASS { ret (n.flags & ast.F_DECL) != 0u16 }
    ret false
}

// Declares the lexical bindings (let/const/class/function) of a statement list in `f.env`: let/const/class start in their
// temporal dead zone, function declarations are created now.
fn hoist_declarations(it: *Interp, f: *Frame, first: u32, count: u32) -> err {
    var i = 0usize
    while i < usize(count) {
        let sid = f.prog.kids[usize(first) + i]
        let sn = f.prog.nodes[usize(sid)]
        i += 1usize
        if sn.kind == ast.N_VAR && sn.op != ast.D_VAR {
            var flags = B_TDZ
            if sn.op == ast.D_CONST { flags = flags | B_CONST }
            var d = 0usize
            while d < usize(sn.b) {
                let dn = f.prog.nodes[usize(f.prog.kids[usize(sn.a) + d])]
                try declare_pattern_names(it, f, dn.a, flags)
                d += 1usize
            }
        } else if sn.kind == ast.N_CLASS && (sn.flags & ast.F_DECL) != 0u16 {
            try declare(it, f.env, sn.text, undefv(), B_TDZ)
        } else if sn.kind == ast.N_FUNC && (sn.flags & ast.F_DECL) != 0u16 {
            let (fo, fe) = make_function(it, f, sid)
            if fe != ok { ret fe }
            try declare(it, f.env, sn.text, obj_value(fo), 0u8)
        } else if sn.kind == ast.N_LABELED {
            // A labelled function declaration.
            var inner = sn.a
            var guard = 0u32
            while f.prog.nodes[usize(inner)].kind == ast.N_LABELED && guard < 100u32 {
                inner = f.prog.nodes[usize(inner)].a
                guard += 1u32
            }
            let inn = f.prog.nodes[usize(inner)]
            if inn.kind == ast.N_FUNC && (inn.flags & ast.F_DECL) != 0u16 {
                let (fo2, fe2) = make_function(it, f, inner)
                if fe2 != ok { ret fe2 }
                try declare(it, f.env, inn.text, obj_value(fo2), 0u8)
            }
        }
    }
    ret ok
}

fn declare_pattern_names(it: *Interp, f: *Frame, pid: u32, flags: u8) -> err {
    if pid == ast.NONE { ret ok }
    let pn = f.prog.nodes[usize(pid)]
    if pn.kind == ast.N_IDENT { ret declare(it, f.env, pn.text, undefv(), flags) }
    if pn.kind == ast.N_ARRAY || pn.kind == ast.N_OBJECT {
        var i = 0usize
        while i < usize(pn.b) {
            try declare_pattern_names(it, f, f.prog.kids[usize(pn.a) + i], flags)
            i += 1usize
        }
        ret ok
    }
    if pn.kind == ast.N_PROP { ret declare_pattern_names(it, f, pn.b, flags) }
    if pn.kind == ast.N_ASSIGN { ret declare_pattern_names(it, f, pn.a, flags) }
    if pn.kind == ast.N_SPREAD { ret declare_pattern_names(it, f, pn.a, flags) }
    ret ok
}

fn has_lexical(f: *const Frame, first: u32, count: u32) -> bool {
    var i = 0usize
    while i < usize(count) {
        let sid = f.prog.kids[usize(first) + i]
        let sn = f.prog.nodes[usize(sid)]
        i += 1usize
        if sn.kind == ast.N_VAR && sn.op != ast.D_VAR { ret true }
        if sn.kind == ast.N_CLASS && (sn.flags & ast.F_DECL) != 0u16 { ret true }
        if sn.kind == ast.N_FUNC && (sn.flags & ast.F_DECL) != 0u16 { ret true }
        if sn.kind == ast.N_LABELED { ret true }
    }
    ret false
}

// The body of a function: declarations hoisted into the call's own scope.
fn exec_body(it: *Interp, f: *Frame, bid: u32) -> (Completion, err) {
    let bn = f.prog.nodes[usize(bid)]
    try hoist_declarations(it, f, bn.a, bn.b)
    var i = 0usize
    while i < usize(bn.b) {
        let (c, e) = exec(it, f, f.prog.kids[usize(bn.a) + i])
        if e != ok { ret (normal(), e) }
        if c.kind != CK_NORMAL { ret (c, ok) }
        i += 1usize
    }
    ret (normal(), ok)
}

fn exec_block(it: *Interp, f: *Frame, bn: ast.Node) -> (Completion, err) {
    var scoped = false
    let saved = f.env
    if has_lexical(f, bn.a, bn.b) {
        f.env = new_env(it, saved)
        scoped = true
        let he = hoist_declarations(it, f, bn.a, bn.b)
        if he != ok {
            f.env = saved
            ret (normal(), he)
        }
    }
    var result = normal()
    var i = 0usize
    while i < usize(bn.b) {
        let (c, e) = exec(it, f, f.prog.kids[usize(bn.a) + i])
        if e != ok {
            f.env = saved
            ret (normal(), e)
        }
        if c.kind != CK_NORMAL {
            result = c
            break
        }
        if !is_undefined(c.value) { result.value = c.value }
        i += 1usize
    }
    f.env = saved
    ret (result, ok)
}

fn label_matches(c: Completion, label: str) -> bool { ret str.eq(c.label, label) }

// Whether a break/continue completion terminates the loop whose labels are `labels`.
fn loop_exit(c: Completion, labels: []const str) -> (bool, bool) {
    // (exit loop, propagate)
    if c.kind == CK_BREAK {
        if c.label.len == 0usize { ret (true, false) }
        var i = 0usize
        while i < labels.len {
            if str.eq(labels[i], c.label) { ret (true, false) }
            i += 1usize
        }
        ret (true, true)
    }
    if c.kind == CK_CONTINUE {
        if c.label.len == 0usize { ret (false, false) }
        var j = 0usize
        while j < labels.len {
            if str.eq(labels[j], c.label) { ret (false, false) }
            j += 1usize
        }
        ret (true, true)
    }
    ret (true, true)
}

fn exec(it: *Interp, f: *Frame, id: u32) -> (Completion, err) {
    let (r, re) = exec_labeled(it, f, id, zero_labels())
    ret (r, re)
}

fn zero_labels() -> []const str {
    var none: []const str = zero
    ret none
}

fn exec_labeled(it: *Interp, f: *Frame, id: u32, labels: []const str) -> (Completion, err) {
    let n = f.prog.nodes[usize(id)]
    let k = n.kind
    try tick(it)
    if k == ast.N_EXPR_STMT {
        let (v, e) = eval(it, f, n.a)
        if e != ok { ret (normal(), e) }
        var c = normal()
        c.value = v
        ret (c, ok)
    }
    if k == ast.N_VAR {
        var i = 0usize
        while i < usize(n.b) {
            let dn = f.prog.nodes[usize(f.prog.kids[usize(n.a) + i])]
            i += 1usize
            var mode = 1u8
            if n.op == ast.D_LET { mode = 6u8 }
            if n.op == ast.D_CONST { mode = 7u8 }
            if dn.b == ast.NONE {
                if n.op == ast.D_VAR { continue }
                // `let x;` initialises to undefined.
                try bind_pattern(it, f, dn.a, undefv(), mode)
                continue
            }
            let (v, e) = eval_named(it, f, dn.b, target_name(f, dn.a))
            if e != ok { ret (normal(), e) }
            try bind_pattern(it, f, dn.a, v, mode)
        }
        ret (normal(), ok)
    }
    if k == ast.N_RETURN {
        var v2 = undefv()
        if n.a != ast.NONE {
            let (rv, re) = eval(it, f, n.a)
            if re != ok { ret (normal(), re) }
            v2 = rv
        }
        ret (Completion { kind: CK_RETURN, value: v2, label: "" }, ok)
    }
    if k == ast.N_IF {
        let (t, te) = eval(it, f, n.a)
        if te != ok { ret (normal(), te) }
        if to_boolean(t) {
            let (c2, e2) = exec(it, f, n.b)
            ret (c2, e2)
        }
        if n.c != ast.NONE {
            let (c3, e3) = exec(it, f, n.c)
            ret (c3, e3)
        }
        ret (normal(), ok)
    }
    if k == ast.N_BLOCK {
        let (c4, e4) = exec_block(it, f, n)
        ret (c4, e4)
    }
    if k == ast.N_FUNC || k == ast.N_EMPTY || k == ast.N_DEBUGGER { ret (normal(), ok) }
    if k == ast.N_CLASS {
        let (cv, ce) = eval_class(it, f, n)
        if ce != ok { ret (normal(), ce) }
        try init_binding(it, f.env, n.text, cv)
        ret (normal(), ok)
    }
    if k == ast.N_FOR {
        let (rt8, re8) = exec_for(it, f, n, labels)
        ret (rt8, re8)
    }
    if k == ast.N_WHILE {
        var last = undefv()
        while true {
            let (t2, te2) = eval(it, f, n.a)
            if te2 != ok { ret (normal(), te2) }
            if !to_boolean(t2) { break }
            let (bc, be) = exec(it, f, n.b)
            if be != ok { ret (normal(), be) }
            if !is_undefined(bc.value) { last = bc.value }
            if bc.kind != CK_NORMAL {
                let (leave, prop) = loop_exit(bc, labels)
                if prop { ret (bc, ok) }
                if leave { break }
            }
        }
        var res = normal()
        res.value = last
        ret (res, ok)
    }
    if k == ast.N_DOWHILE {
        var last2 = undefv()
        while true {
            let (bc2, be2) = exec(it, f, n.b)
            if be2 != ok { ret (normal(), be2) }
            if !is_undefined(bc2.value) { last2 = bc2.value }
            if bc2.kind != CK_NORMAL {
                let (leave2, prop2) = loop_exit(bc2, labels)
                if prop2 { ret (bc2, ok) }
                if leave2 { break }
            }
            let (t3, te3) = eval(it, f, n.a)
            if te3 != ok { ret (normal(), te3) }
            if !to_boolean(t3) { break }
        }
        var res2 = normal()
        res2.value = last2
        ret (res2, ok)
    }
    if k == ast.N_FORIN || k == ast.N_FOROF {
        let (rt9, re9) = exec_for_in_of(it, f, n, labels)
        ret (rt9, re9)
    }
    if k == ast.N_BREAK { ret (Completion { kind: CK_BREAK, value: undefv(), label: n.text }, ok) }
    if k == ast.N_CONTINUE { ret (Completion { kind: CK_CONTINUE, value: undefv(), label: n.text }, ok) }
    if k == ast.N_THROW {
        let (tv, tve) = eval(it, f, n.a)
        if tve != ok { ret (normal(), tve) }
        ret (normal(), throw_value(it, tv))
    }
    if k == ast.N_TRY {
        let (rt10, re10) = exec_try(it, f, n)
        ret (rt10, re10)
    }
    if k == ast.N_SWITCH {
        let (rt11, re11) = exec_switch(it, f, n, labels)
        ret (rt11, re11)
    }
    if k == ast.N_LABELED {
        // Collect the chain of labels, then run the labelled statement with them.
        var chain: [16]str = zero
        var count = 0usize
        var cur = id
        while f.prog.nodes[usize(cur)].kind == ast.N_LABELED && count < 16usize {
            chain[count] = f.prog.nodes[usize(cur)].text
            count += 1usize
            cur = f.prog.nodes[usize(cur)].a
        }
        let (lc, le) = exec_labeled(it, f, cur, chain[0usize..count])
        if le != ok { ret (normal(), le) }
        if lc.kind == CK_BREAK && lc.label.len > 0usize {
            var q = 0usize
            while q < count {
                if str.eq(chain[q], lc.label) { ret (normal(), ok) }
                q += 1usize
            }
        }
        ret (lc, ok)
    }
    if k == ast.N_WITH {
        let (wv, we) = eval(it, f, n.a)
        if we != ok { ret (normal(), we) }
        let (wo, woe) = to_object(it, wv)
        if woe != ok { ret (normal(), woe) }
        let saved = f.env
        let ne = new_env(it, saved)
        ne.has_with = true
        ne.with_obj = wo
        f.env = ne
        let (wc, wce) = exec(it, f, n.b)
        f.env = saved
        ret (wc, wce)
    }
    ret (normal(), throw_syntax(it, "unsupported statement"))
}

fn exec_for(it: *Interp, f: *Frame, n: ast.Node, labels: []const str) -> (Completion, err) {
    let saved = f.env
    var per_iteration = false
    var names: [16]str = zero
    var name_count = 0usize
    if n.a != ast.NONE {
        let init = f.prog.nodes[usize(n.a)]
        if init.kind == ast.N_VAR && init.op != ast.D_VAR {
            f.env = new_env(it, saved)
            var d = 0usize
            var flags = B_TDZ
            if init.op == ast.D_CONST { flags = flags | B_CONST }
            while d < usize(init.b) {
                let dn = f.prog.nodes[usize(f.prog.kids[usize(init.a) + d])]
                let de = declare_pattern_names(it, f, dn.a, flags)
                if de != ok {
                    f.env = saved
                    ret (normal(), de)
                }
                d += 1usize
            }
            if init.op == ast.D_LET {
                per_iteration = true
                var v = 0usize
                while v < f.env.vars.len && name_count < 16usize {
                    names[name_count] = f.env.vars.items[v].name
                    name_count += 1usize
                    v += 1usize
                }
            }
        }
        let (c, e) = exec(it, f, n.a)
        if e != ok {
            // An initialiser may also be an expression.
            f.env = saved
            ret (normal(), e)
        }
    }
    var last = undefv()
    while true {
        if per_iteration {
            // A fresh scope per iteration copies the loop variables.
            let fresh = new_env(it, saved)
            var v2 = 0usize
            while v2 < f.env.vars.len {
                let pe = list.push[Binding](&fresh.vars, f.env.vars.items[v2])
                v2 += 1usize
            }
            f.env = fresh
        }
        if n.b != ast.NONE {
            let (t, te) = eval(it, f, n.b)
            if te != ok {
                f.env = saved
                ret (normal(), te)
            }
            if !to_boolean(t) { break }
        }
        let (bc, be) = exec(it, f, n.d)
        if be != ok {
            f.env = saved
            ret (normal(), be)
        }
        if !is_undefined(bc.value) { last = bc.value }
        if bc.kind != CK_NORMAL {
            let (leave, prop) = loop_exit(bc, labels)
            if prop {
                f.env = saved
                ret (bc, ok)
            }
            if leave { break }
        }
        if per_iteration {
            let fresh2 = new_env(it, saved)
            var v3 = 0usize
            while v3 < f.env.vars.len {
                let pe2 = list.push[Binding](&fresh2.vars, f.env.vars.items[v3])
                v3 += 1usize
            }
            f.env = fresh2
        }
        if n.c != ast.NONE {
            let (u, ue) = eval(it, f, n.c)
            if ue != ok {
                f.env = saved
                ret (normal(), ue)
            }
        }
    }
    f.env = saved
    var res = normal()
    res.value = last
    ret (res, ok)
}

fn exec_for_in_of(it: *Interp, f: *Frame, n: ast.Node, labels: []const str) -> (Completion, err) {
    let saved = f.env
    let head = f.prog.nodes[usize(n.a)]
    var decl_mode = 0u8
    var lexical = false
    var target_id = n.a
    var flags = B_TDZ
    if head.kind == ast.N_VAR {
        target_id = f.prog.nodes[usize(f.prog.kids[usize(head.a)])].a
        if head.op == ast.D_VAR {
            decl_mode = 1u8
        } else if head.op == ast.D_LET {
            decl_mode = 6u8
            lexical = true
        } else {
            decl_mode = 7u8
            lexical = true
            flags = flags | B_CONST
        }
    }
    // The iterated expression is evaluated with the loop variables in their dead zone.
    if lexical {
        f.env = new_env(it, saved)
        let de = declare_pattern_names(it, f, target_id, flags)
        if de != ok {
            f.env = saved
            ret (normal(), de)
        }
    }
    let (coll, ce) = eval(it, f, n.b)
    f.env = saved
    if ce != ok { ret (normal(), ce) }
    var last = undefv()
    if n.kind == ast.N_FORIN {
        if is_nullish(coll) { ret (normal(), ok) }
        let (co, coe) = to_object(it, coll)
        if coe != ok { ret (normal(), coe) }
        // Enumerable string keys along the prototype chain, each name once.
        let (seen_l, sle) = list.init[Key](it.a, 8usize)
        var seen = seen_l
        var cur = co
        var guard = 0u32
        while guard < 10000u32 {
            guard += 1u32
            let (keys, ke) = own_keys(it, cur)
            if ke != ok { ret (normal(), ke) }
            var i = 0usize
            while i < keys.len {
                let key = keys[i]
                i += 1usize
                if is_symbol_key(key) { continue }
                var dup = false
                var s = 0usize
                while s < seen.len {
                    if keys_equal(seen.items[s], key) { dup = true }
                    s += 1usize
                }
                if dup { continue }
                let (p, found) = get_own(it, cur, key)
                if !found { continue }
                let pe = list.push[Key](&seen, key)
                if (p.flags & P_ENUMERABLE) == 0u8 { continue }
                let (bc, be) = for_body(it, f, n, target_id, str_value(key.name), decl_mode, lexical, flags, saved)
                if be != ok { ret (normal(), be) }
                if !is_undefined(bc.value) { last = bc.value }
                if bc.kind != CK_NORMAL {
                    let (leave, prop) = loop_exit(bc, labels)
                    if prop { ret (bc, ok) }
                    if leave {
                        var done = normal()
                        done.value = last
                        ret (done, ok)
                    }
                }
            }
            if !cur.has_proto { break }
            cur = cur.proto
        }
        var res = normal()
        res.value = last
        ret (res, ok)
    }
    if (n.flags & ast.F_ASYNC) != 0u16 {
        let (aiter, aie) = get_async_iterator(it, coll)
        if aie != ok { ret (normal(), aie) }
        while true {
            let (av, adone, ase) = async_iterator_step(it, f, aiter)
            if ase != ok { ret (normal(), ase) }
            if adone { break }
            let (abc, abe) = for_body(it, f, n, target_id, av, decl_mode, lexical, flags, saved)
            if abe != ok {
                let acl = async_iterator_close(it, f, aiter)
                ret (normal(), abe)
            }
            if !is_undefined(abc.value) { last = abc.value }
            if abc.kind != CK_NORMAL {
                let (aleave, aprop) = loop_exit(abc, labels)
                let acl2 = async_iterator_close(it, f, aiter)
                if acl2 != ok { ret (normal(), acl2) }
                if aprop { ret (abc, ok) }
                if aleave { break }
            }
        }
        var ares = normal()
        ares.value = last
        ret (ares, ok)
    }
    // for-of
    let (iter, ie) = get_iterator(it, coll)
    if ie != ok { ret (normal(), ie) }
    while true {
        let (v, done, se) = iterator_step(it, iter)
        if se != ok { ret (normal(), se) }
        if done { break }
        let (bc2, be2) = for_body(it, f, n, target_id, v, decl_mode, lexical, flags, saved)
        if be2 != ok {
            let cle = iterator_close(it, iter)
            ret (normal(), be2)
        }
        if !is_undefined(bc2.value) { last = bc2.value }
        if bc2.kind != CK_NORMAL {
            let (leave2, prop2) = loop_exit(bc2, labels)
            let cle2 = iterator_close(it, iter)
            if cle2 != ok { ret (normal(), cle2) }
            if prop2 { ret (bc2, ok) }
            if leave2 { break }
        }
    }
    var res2 = normal()
    res2.value = last
    ret (res2, ok)
}

fn for_body(it: *Interp, f: *Frame, n: ast.Node, target_id: u32, v: Value, decl_mode: u8, lexical: bool, flags: u8, saved: *Env) -> (Completion, err) {
    if lexical {
        f.env = new_env(it, saved)
        let de = declare_pattern_names(it, f, target_id, flags)
        if de != ok {
            f.env = saved
            ret (normal(), de)
        }
    }
    let be = bind_pattern(it, f, target_id, v, decl_mode)
    if be != ok {
        f.env = saved
        ret (normal(), be)
    }
    let (c, e) = exec(it, f, n.c)
    f.env = saved
    ret (c, e)
}

fn is_reference_error(it: *Interp) -> bool {
    if !is_object(it.thrown) { ret false }
    var cur = as_object(it.thrown)
    var guard = 0u32
    while guard < 1000u32 {
        guard += 1u32
        if !cur.has_proto { ret false }
        cur = cur.proto
        if cur == it.protos.reference_error { ret true }
    }
    ret false
}

fn exec_try(it: *Interp, f: *Frame, n: ast.Node) -> (Completion, err) {
    let saved_env = f.env
    let saved_depth = it.depth
    var (c, e) = exec(it, f, n.a)
    if e == Throw && n.b != ast.NONE {
        // Catch: bind the parameter in a fresh scope.
        let caught = it.thrown
        f.env = saved_env
        it.depth = saved_depth
        let cn = f.prog.nodes[usize(n.b)]
        let ce = new_env(it, saved_env)
        f.env = ce
        var pe: err = ok
        if cn.a != ast.NONE {
            let de = declare_pattern_names(it, f, cn.a, 0u8)
            if de != ok { pe = de } else { pe = bind_pattern(it, f, cn.a, caught, 6u8) }
        }
        if pe != ok {
            c = normal()
            e = pe
        } else {
            let (cb, cbe) = exec_block(it, f, f.prog.nodes[usize(cn.b)])
            c = cb
            e = cbe
        }
        f.env = saved_env
    }
    if n.c != ast.NONE {
        // finally: runs whatever happened; its own abrupt completion wins.
        let pending_thrown = it.thrown
        let saved_depth2 = it.depth
        f.env = saved_env
        it.depth = saved_depth
        let (fc, fe) = exec_block(it, f, f.prog.nodes[usize(n.c)])
        f.env = saved_env
        if fe != ok { ret (normal(), fe) }
        if fc.kind != CK_NORMAL { ret (fc, ok) }
        it.thrown = pending_thrown
    }
    ret (c, e)
}

fn exec_switch(it: *Interp, f: *Frame, n: ast.Node, labels: []const str) -> (Completion, err) {
    let (d, de) = eval(it, f, n.a)
    if de != ok { ret (normal(), de) }
    let saved = f.env
    f.env = new_env(it, saved)
    // Lexical declarations of every case share one scope.
    var ci = 0usize
    while ci < usize(n.c) {
        let cn = f.prog.nodes[usize(f.prog.kids[usize(n.b) + ci])]
        let he = hoist_declarations(it, f, cn.b, cn.c)
        if he != ok {
            f.env = saved
            ret (normal(), he)
        }
        ci += 1usize
    }
    var start = 0usize
    var matched = false
    var default_at = usize(n.c)
    var i = 0usize
    while i < usize(n.c) && !matched {
        let cn2 = f.prog.nodes[usize(f.prog.kids[usize(n.b) + i])]
        if cn2.a == ast.NONE {
            default_at = i
        } else {
            let (tv, te) = eval(it, f, cn2.a)
            if te != ok {
                f.env = saved
                ret (normal(), te)
            }
            if strict_equals(d, tv) {
                start = i
                matched = true
            }
        }
        i += 1usize
    }
    if !matched {
        if default_at == usize(n.c) {
            f.env = saved
            ret (normal(), ok)
        }
        start = default_at
    }
    var last = undefv()
    var j = start
    while j < usize(n.c) {
        let cn3 = f.prog.nodes[usize(f.prog.kids[usize(n.b) + j])]
        var s = 0usize
        while s < usize(cn3.c) {
            let (c, e) = exec(it, f, f.prog.kids[usize(cn3.b) + s])
            if e != ok {
                f.env = saved
                ret (normal(), e)
            }
            if !is_undefined(c.value) { last = c.value }
            if c.kind != CK_NORMAL {
                f.env = saved
                if c.kind == CK_BREAK && c.label.len == 0usize {
                    var out = normal()
                    out.value = last
                    ret (out, ok)
                }
                if c.kind == CK_BREAK {
                    var q = 0usize
                    while q < labels.len {
                        if str.eq(labels[q], c.label) { ret (normal(), ok) }
                        q += 1usize
                    }
                }
                ret (c, ok)
            }
            s += 1usize
        }
        j += 1usize
    }
    f.env = saved
    var res = normal()
    res.value = last
    ret (res, ok)
}

// --- programs

fn new_frame_global(it: *Interp, prog: *const ast.Program) -> Frame {
    var f: Frame = zero
    f.prog = prog
    f.env = it.global_env
    f.this_val = obj_value(it.global)
    f.has_this = true
    f.new_target = undefv()
    ret f
}

// Runs a parsed script in the global scope; answers the completion value of its last statement.
fn run_program(it: *Interp, prog: *const ast.Program) -> (Value, err) {
    let root = prog.nodes[usize(prog.root)]
    var f = new_frame_global(it, prog)
    f.strict = (root.flags & ast.F_STRICT) != 0u16
    // Top-level `var`s and functions become properties of the global object; let/const live in the global environment.
    var h = 0usize
    while h < usize(root.hoist_count) {
        let hid = prog.kids[usize(root.hoist_first) + h]
        let name = prog.nodes[usize(hid)].text
        if !has_own(it, it.global, key_of(name)) {
            try define_data(it, it.global, key_of(name), undefv(), P_WRITABLE | P_ENUMERABLE)
        }
        h += 1usize
    }
    var i = 0usize
    while i < usize(root.b) {
        let sid = prog.kids[usize(root.a) + i]
        let sn = prog.nodes[usize(sid)]
        i += 1usize
        if sn.kind == ast.N_FUNC && (sn.flags & ast.F_DECL) != 0u16 {
            let (fo, fe) = make_function(it, &f, sid)
            if fe != ok { ret (undefv(), fe) }
            try define_data(it, it.global, key_of(sn.text), obj_value(fo), P_WRITABLE | P_ENUMERABLE)
        }
    }
    try hoist_lexical_only(it, &f, root.a, root.b)
    var last = undefv()
    var k = 0usize
    while k < usize(root.b) {
        let (c, e) = exec(it, &f, prog.kids[usize(root.a) + k])
        if e != ok { ret (undefv(), e) }
        if !is_undefined(c.value) { last = c.value }
        k += 1usize
    }
    ret (last, ok)
}

// let/const/class of a script (functions were already created on the global object).
fn hoist_lexical_only(it: *Interp, f: *Frame, first: u32, count: u32) -> err {
    var i = 0usize
    while i < usize(count) {
        let sn = f.prog.nodes[usize(f.prog.kids[usize(first) + i])]
        i += 1usize
        if sn.kind == ast.N_VAR && sn.op != ast.D_VAR {
            var flags = B_TDZ
            if sn.op == ast.D_CONST { flags = flags | B_CONST }
            var d = 0usize
            while d < usize(sn.b) {
                let dn = f.prog.nodes[usize(f.prog.kids[usize(sn.a) + d])]
                try declare_pattern_names(it, f, dn.a, flags)
                d += 1usize
            }
        } else if sn.kind == ast.N_CLASS && (sn.flags & ast.F_DECL) != 0u16 {
            try declare(it, f.env, sn.text, undefv(), B_TDZ)
        }
    }
    ret ok
}

// Parses and runs `source` as a script. Syntax errors surface as a thrown SyntaxError.
fn eval_source(it: *Interp, source: str) -> (Value, err) {
    let (parsed, pe) = jsparse.parse_program(it.a, source)
    if pe != ok { ret (undefv(), throw_syntax(it, str_concat(it, "SyntaxError: ", parsed.message))) }
    let (cell, ce) = mem.alloc[ast.Program](it.a, 1usize)
    if ce != ok { ret (undefv(), throw_range(it, "out of memory")) }
    cell[0usize] = parsed.program
    let (rt1, re1) = run_program(it, &cell[0usize])
    ret (rt1, re1)
}

// `eval(source)` called directly: runs in the caller's scope (a fresh scope in strict code).
fn direct_eval(it: *Interp, f: *Frame, arg: Value) -> (Value, err) {
    if !is_string(arg) { ret (arg, ok) }
    let source = value_str(arg)
    let (parsed, pe) = jsparse.parse_program(it.a, source)
    if pe != ok { ret (undefv(), throw_syntax(it, str_concat(it, "SyntaxError: ", parsed.message))) }
    let (cell, ce) = mem.alloc[ast.Program](it.a, 1usize)
    if ce != ok { ret (undefv(), throw_range(it, "out of memory")) }
    cell[0usize] = parsed.program
    let prog = &cell[0usize]
    let root = prog.nodes[usize(prog.root)]
    var g: Frame = zero
    g.prog = prog
    g.env = new_env(it, f.env)
    g.this_val = f.this_val
    g.has_this = f.has_this
    g.func = f.func
    g.has_func = f.has_func
    g.new_target = f.new_target
    g.home = f.home
    g.has_home = f.has_home
    g.strict = f.strict || (root.flags & ast.F_STRICT) != 0u16
    var h = 0usize
    while h < usize(root.hoist_count) {
        let hid = prog.kids[usize(root.hoist_first) + h]
        let name = prog.nodes[usize(hid)].text
        // `var`s of sloppy direct eval land in the caller's variable scope.
        if g.strict {
            try declare_var(it, g.env, name)
        } else {
            var tgt = f.env
            let z = null_env()
            while tgt.parent != z && !env_is_var_scope(it, tgt) { tgt = tgt.parent }
            try declare_var(it, tgt, name)
        }
        h += 1usize
    }
    try hoist_declarations(it, &g, root.a, root.b)
    var last = undefv()
    var k = 0usize
    while k < usize(root.b) {
        let (c, e) = exec(it, &g, prog.kids[usize(root.a) + k])
        if e != ok { ret (undefv(), e) }
        if !is_undefined(c.value) { last = c.value }
        k += 1usize
    }
    ret (last, ok)
}

fn env_is_var_scope(it: *Interp, e: *Env) -> bool {
    // A function call's scope holds its parameters or `arguments`; the global scope has no parent.
    ret e.parent == it.global_env || e.parent == null_env()
}

// --- coroutines: generators and async functions
//
// A generator (and an async function) runs its body on a thread of its own that hands control back and forth with its caller
// through two events, so exactly one of them runs at any instant and the interpreter needs no locking. `gen_resume` switches
// into the body; `gen_yield` switches back out. An abandoned generator leaves its thread parked until the process ends.

error GenReturn

type GenState = struct {
    it: *Interp, frame: Frame, body: u32, expr_body: bool, kind: u8,
    state: u8, mode: u8, send: Value, out: Value, out_raw: bool, out_err: err, ret_val: Value,
    gen_ev: sync.Event, caller_ev: sync.Event, started: bool, saved_depth: u32,
    promise: *Obj, awaiting: bool, owner: *Obj, queue: list.List[AgRequest], busy: bool
}

// Generator states.
const GS_START: u8 = 0u8
const GS_SUSPENDED: u8 = 1u8
const GS_RUNNING: u8 = 2u8
const GS_DONE: u8 = 3u8

// Resume modes.
const RM_NEXT: u8 = 0u8
const RM_THROW: u8 = 1u8
const RM_RETURN: u8 = 2u8

fn gen_state_of(f: *const Frame) -> *GenState { ret mem.cast[*GenState](f.gen) }

fn gen_thread_main(gs: *GenState) {
    let it = gs.it
    gs.state = GS_RUNNING
    var result = undefv()
    var e: err = ok
    if gs.expr_body {
        let (v, ve) = eval(it, &gs.frame, gs.body)
        result = v
        e = ve
    } else {
        let (c, ce) = exec_body(it, &gs.frame, gs.body)
        e = ce
        if ce == ok && c.kind == CK_RETURN { result = c.value }
    }
    if e == GenReturn {
        result = gs.ret_val
        e = ok
    }
    gs.out = result
    gs.out_err = e
    gs.out_raw = false
    gs.state = GS_DONE
    sync.event_set(&gs.caller_ev)
}

// Switches into the coroutine with `mode`/`val`; answers (value, done, error).
fn gen_resume(it: *Interp, gs: *GenState, mode: u8, val: Value) -> (Value, bool, err) {
    if gs.state == GS_RUNNING { ret (undefv(), true, throw_type(it, "Generator is already running")) }
    if gs.state == GS_DONE {
        if mode == RM_THROW { ret (undefv(), true, throw_value(it, val)) }
        if mode == RM_RETURN { ret (val, true, ok) }
        ret (undefv(), true, ok)
    }
    if gs.state == GS_START {
        if mode == RM_THROW {
            gs.state = GS_DONE
            ret (undefv(), true, throw_value(it, val))
        }
        if mode == RM_RETURN {
            gs.state = GS_DONE
            ret (val, true, ok)
        }
    }
    let saved_depth = it.depth
    let saved_callee = it.callee
    let saved_nt = it.new_target
    let saved_has = it.has_new_target
    gs.mode = mode
    gs.send = val
    gs.state = GS_RUNNING
    if !gs.started {
        gs.started = true
        let (th, te) = thread.spawn[GenState](gen_thread_main, gs, 16777216usize)
        if te != ok {
            gs.state = GS_DONE
            ret (undefv(), true, throw_range(it, "cannot start generator thread"))
        }
        let de = thread.detach(th)
    } else {
        sync.event_set(&gs.gen_ev)
    }
    sync.event_wait(&gs.caller_ev)
    it.depth = saved_depth
    it.callee = saved_callee
    it.new_target = saved_nt
    it.has_new_target = saved_has
    if gs.state == GS_DONE {
        if gs.out_err != ok { ret (undefv(), true, gs.out_err) }
        ret (gs.out, true, ok)
    }
    ret (gs.out, false, ok)
}

// Called on the coroutine's thread: hands `v` to the resumer and waits to be resumed; answers (mode, sent value).
fn gen_suspend(it: *Interp, gs: *GenState, v: Value, raw: bool) -> (u8, Value) {
    gs.out = v
    gs.out_raw = raw
    gs.state = GS_SUSPENDED
    gs.saved_depth = it.depth
    sync.event_set(&gs.caller_ev)
    sync.event_wait(&gs.gen_ev)
    it.depth = gs.saved_depth
    ret (gs.mode, gs.send)
}

// `yield v` inside a generator body.
fn gen_yield(it: *Interp, f: *Frame, v: Value) -> (Value, err) {
    if !f.has_gen { ret (undefv(), throw_syntax(it, "yield outside a generator")) }
    let gs = gen_state_of(f)
    var yielded = v
    if gs.kind == 2u8 {
        let (av, ae) = await_value(it, f, v)
        if ae != ok { ret (undefv(), ae) }
        yielded = av
    }
    let (mode, sent) = gen_suspend(it, gs, yielded, false)
    if mode == RM_NEXT { ret (sent, ok) }
    if mode == RM_THROW { ret (undefv(), throw_value(it, sent)) }
    var rv = sent
    if gs.kind == 2u8 {
        let (rav, rae) = await_value(it, f, sent)
        if rae != ok { ret (undefv(), rae) }
        rv = rav
    }
    gs.ret_val = rv
    ret (undefv(), GenReturn)
}

fn gen_yield_star(it: *Interp, f: *Frame, iterable: Value) -> (Value, err) {
    if !f.has_gen { ret (undefv(), throw_syntax(it, "yield outside a generator")) }
    let gs = gen_state_of(f)
    let (iter, ie) = get_iterator(it, iterable)
    if ie != ok { ret (undefv(), ie) }
    var mode = RM_NEXT
    var received = undefv()
    while true {
        var r = undefv()
        if mode == RM_NEXT {
            let (rv, re) = call_function(it, iter.next, iter.obj, one_arg(it, received))
            if re != ok { ret (undefv(), re) }
            r = rv
        } else if mode == RM_THROW {
            let (tm, tme) = get_value(it, iter.obj, key_of("throw"))
            if tme != ok { ret (undefv(), tme) }
            if is_nullish(tm) {
                let ce = iterator_close(it, iter)
                if ce != ok { ret (undefv(), ce) }
                ret (undefv(), throw_type(it, "The iterator does not provide a 'throw' method"))
            }
            let (rv2, re2) = call_function(it, tm, iter.obj, one_arg(it, received))
            if re2 != ok { ret (undefv(), re2) }
            r = rv2
        } else {
            let (rm, rme) = get_value(it, iter.obj, key_of("return"))
            if rme != ok { ret (undefv(), rme) }
            if is_nullish(rm) {
                gs.ret_val = received
                ret (undefv(), GenReturn)
            }
            let (rv3, re3) = call_function(it, rm, iter.obj, one_arg(it, received))
            if re3 != ok { ret (undefv(), re3) }
            if !is_object(rv3) { ret (undefv(), throw_type(it, "iterator result is not an object")) }
            let (dv, de) = get_value(it, rv3, key_of("done"))
            if de != ok { ret (undefv(), de) }
            if to_boolean(dv) {
                let (vv, ve) = get_value(it, rv3, key_of("value"))
                if ve != ok { ret (undefv(), ve) }
                gs.ret_val = vv
                ret (undefv(), GenReturn)
            }
            let (m2, s2) = gen_suspend(it, gs, rv3, true)
            mode = m2
            received = s2
            continue
        }
        if !is_object(r) { ret (undefv(), throw_type(it, "iterator result is not an object")) }
        let (dn, dne) = get_value(it, r, key_of("done"))
        if dne != ok { ret (undefv(), dne) }
        if to_boolean(dn) {
            let (vv2, ve2) = get_value(it, r, key_of("value"))
            if ve2 != ok { ret (undefv(), ve2) }
            ret (vv2, ok)
        }
        let (m3, s3) = gen_suspend(it, gs, r, true)
        mode = m3
        received = s3
    }
    ret (undefv(), ok)
}

// Builds the generator object (or starts the async function) for a call whose frame is already bound.
fn make_suspendable(it: *Interp, fo: *Obj, f: Frame, n: ast.Node) -> (Value, err) {
    let is_gen = (n.flags & ast.F_GENERATOR) != 0u16
    let is_async = (n.flags & ast.F_ASYNC) != 0u16
    let (cell, ce) = mem.alloc[GenState](it.a, 1usize)
    if ce != ok { ret (undefv(), throw_range(it, "out of memory")) }
    var blank: GenState = zero
    cell[0usize] = blank
    let gs = &cell[0usize]
    gs.it = it
    gs.frame = f
    gs.body = n.c
    gs.expr_body = (n.flags & ast.F_EXPR_BODY) != 0u16
    gs.gen_ev = sync.event(false, false)
    gs.caller_ev = sync.event(false, false)
    gs.state = GS_START
    gs.send = undefv()
    gs.out = undefv()
    gs.ret_val = undefv()
    gs.frame.gen = mem.cast[*void](gs)
    gs.frame.has_gen = true
    if is_gen && is_async {
        gs.kind = 2u8
        let (ql, qle) = list.init[AgRequest](it.a, 2usize)
        gs.queue = ql
        var aproto = it.protos.async_generator
        let (apv, ape) = get_prop(it, fo, key_of("prototype"), obj_value(fo))
        if ape != ok { ret (undefv(), ape) }
        if is_object(apv) { aproto = as_object(apv) }
        let ag = new_obj(it, C_GENERATOR, aproto)
        ag.data = mem.cast[*void](gs)
        gs.owner = ag
        ret (obj_value(ag), ok)
    }
    if is_gen {
        gs.kind = 0u8
        var proto = it.protos.generator
        let (pv, pe) = get_prop(it, fo, key_of("prototype"), obj_value(fo))
        if pe != ok { ret (undefv(), pe) }
        if is_object(pv) { proto = as_object(pv) }
        let g = new_obj(it, C_GENERATOR, proto)
        g.data = mem.cast[*void](gs)
        gs.owner = g
        ret (obj_value(g), ok)
    }
    // Async function: the body runs eagerly up to its first await; the result is a promise.
    gs.kind = 1u8
    let (p, pe2) = new_promise(it)
    if pe2 != ok { ret (undefv(), pe2) }
    gs.promise = p
    async_step(it, gs, RM_NEXT, undefv())
    ret (obj_value(p), ok)
}

// `await v` inside an async function: suspends until the promise settles.
fn await_value(it: *Interp, f: *Frame, v: Value) -> (Value, err) {
    if !f.has_gen { ret (undefv(), throw_syntax(it, "await outside an async function")) }
    let gs = gen_state_of(f)
    gs.awaiting = true
    let (mode, sent) = gen_suspend(it, gs, v, false)
    gs.awaiting = false
    if mode == RM_THROW { ret (undefv(), throw_value(it, sent)) }
    ret (sent, ok)
}

// Resumes an async function and arranges for the next resumption when it awaits again.
fn async_step(it: *Interp, gs: *GenState, mode: u8, val: Value) {
    let (r, done, e) = gen_resume(it, gs, mode, val)
    if e != ok {
        if e == Throw {
            let rj = promise_reject(it, gs.promise, it.thrown)
        } else {
            let rj2 = promise_reject(it, gs.promise, make_error(it, it.protos.error_proto, "internal error"))
        }
        ret
    }
    if done {
        let rs = promise_resolve_with(it, gs.promise, r)
        ret
    }
    // Awaiting `r`: resolve it to a promise and continue on settlement.
    let (pr, pe) = promise_resolve_value(it, r)
    if pe != ok {
        async_step(it, gs, RM_THROW, it.thrown)
        ret
    }
    let onf = make_native(it, "", 1u32, async_fulfilled)
    onf.data = mem.cast[*void](gs)
    let onr = make_native(it, "", 1u32, async_rejected)
    onr.data = mem.cast[*void](gs)
    let te = promise_then_raw(it, pr, obj_value(onf), obj_value(onr))
}

fn async_fulfilled(it: *Interp, this_val: Value, args: []const Value) -> (Value, err) {
    let gs = mem.cast[*GenState](it.callee.data)
    var v = undefv()
    if args.len > 0usize { v = args[0usize] }
    async_step(it, gs, RM_NEXT, v)
    ret (undefv(), ok)
}

fn async_rejected(it: *Interp, this_val: Value, args: []const Value) -> (Value, err) {
    let gs = mem.cast[*GenState](it.callee.data)
    var v = undefv()
    if args.len > 0usize { v = args[0usize] }
    async_step(it, gs, RM_THROW, v)
    ret (undefv(), ok)
}

// --- promises

type Reaction = struct { is_reject: bool, handler: Value, cap_promise: Value, cap_resolve: Value, cap_reject: Value, has_cap: bool }

type PromiseState = struct { state: u8, result: Value, fulfill: list.List[Reaction], reject: list.List[Reaction], handled: bool }

type Job = struct { kind: u8, a: Value, b: Value, c: Value, d: Value, is_reject: bool }

fn promise_state_of(o: *Obj) -> *PromiseState { ret mem.cast[*PromiseState](o.data) }

fn new_promise_with_proto(it: *Interp, proto: *Obj) -> (*Obj, err) {
    let p = new_obj(it, C_PROMISE, proto)
    let (cell, ce) = mem.alloc[PromiseState](it.a, 1usize)
    if ce != ok { ret (p, throw_range(it, "out of memory")) }
    var blank: PromiseState = zero
    cell[0usize] = blank
    let st = &cell[0usize]
    st.result = undefv()
    let (fl, fe) = list.init[Reaction](it.a, 0usize)
    st.fulfill = fl
    let (rl, re) = list.init[Reaction](it.a, 0usize)
    st.reject = rl
    p.data = mem.cast[*void](st)
    ret (p, ok)
}

fn new_promise(it: *Interp) -> (*Obj, err) {
    let (p, e) = new_promise_with_proto(it, it.protos.promise)
    ret (p, e)
}

fn enqueue_job(it: *Interp, j: Job) {
    let pe = list.push[Job](&it.jobs, j)
}

fn trigger_reactions(it: *Interp, reactions: list.List[Reaction], arg: Value) {
    var i = 0usize
    while i < reactions.len {
        let r = reactions.items[i]
        enqueue_job(it, Job { kind: 1u8, a: r.handler, b: arg, c: r.cap_resolve, d: r.cap_reject, is_reject: r.is_reject })
        i += 1usize
    }
}

fn promise_fulfill(it: *Interp, p: *Obj, v: Value) {
    let st = promise_state_of(p)
    if st.state != 0u8 { ret }
    st.state = 1u8
    st.result = v
    trigger_reactions(it, st.fulfill, v)
    st.fulfill.len = 0usize
    st.reject.len = 0usize
}

fn promise_reject(it: *Interp, p: *Obj, v: Value) -> err {
    let st = promise_state_of(p)
    if st.state != 0u8 { ret ok }
    st.state = 2u8
    st.result = v
    trigger_reactions(it, st.reject, v)
    st.fulfill.len = 0usize
    st.reject.len = 0usize
    ret ok
}

// The promise's resolve function semantics.
fn promise_resolve_with(it: *Interp, p: *Obj, resolution: Value) -> err {
    if is_object(resolution) && as_object(resolution) == p {
        ret promise_reject(it, p, make_error(it, it.protos.type_error, "Chaining cycle detected for promise"))
    }
    if !is_object(resolution) {
        promise_fulfill(it, p, resolution)
        ret ok
    }
    let (th, te) = get_prop(it, as_object(resolution), key_of("then"), resolution)
    if te != ok {
        if te == Throw { ret promise_reject(it, p, it.thrown) }
        ret te
    }
    if !is_callable(th) {
        promise_fulfill(it, p, resolution)
        ret ok
    }
    enqueue_job(it, Job { kind: 2u8, a: obj_value(p), b: resolution, c: th, d: undefv(), is_reject: false })
    ret ok
}

type ResolveCell = struct { promise: *Obj, done: bool }

fn resolving_resolve(it: *Interp, this_val: Value, args: []const Value) -> (Value, err) {
    let cell = mem.cast[*ResolveCell](it.callee.data)
    if cell.done { ret (undefv(), ok) }
    cell.done = true
    var v = undefv()
    if args.len > 0usize { v = args[0usize] }
    let e = promise_resolve_with(it, cell.promise, v)
    if e != ok { ret (undefv(), e) }
    ret (undefv(), ok)
}

fn resolving_reject(it: *Interp, this_val: Value, args: []const Value) -> (Value, err) {
    let cell = mem.cast[*ResolveCell](it.callee.data)
    if cell.done { ret (undefv(), ok) }
    cell.done = true
    var v = undefv()
    if args.len > 0usize { v = args[0usize] }
    let e = promise_reject(it, cell.promise, v)
    if e != ok { ret (undefv(), e) }
    ret (undefv(), ok)
}

// CreateResolvingFunctions: (resolve, reject) sharing one `already resolved` flag.
fn create_resolving_functions(it: *Interp, p: *Obj) -> (*Obj, *Obj, err) {
    let (cell, ce) = mem.alloc[ResolveCell](it.a, 1usize)
    if ce != ok { ret (null_obj(), null_obj(), throw_range(it, "out of memory")) }
    cell[0usize] = ResolveCell { promise: p, done: false }
    let rs = make_native(it, "", 1u32, resolving_resolve)
    rs.data = mem.cast[*void](&cell[0usize])
    let rj = make_native(it, "", 1u32, resolving_reject)
    rj.data = mem.cast[*void](&cell[0usize])
    ret (rs, rj, ok)
}

type Capability = struct { promise: Value, resolve: Value, reject: Value }

fn capability_executor(it: *Interp, this_val: Value, args: []const Value) -> (Value, err) {
    let cap = it.callee.aux
    // The executor stores the resolving functions in slots of its own `aux` object.
    let (rv, re) = get_prop(it, cap, key_of("resolve"), obj_value(cap))
    if re != ok { ret (undefv(), re) }
    let (jv, je) = get_prop(it, cap, key_of("reject"), obj_value(cap))
    if je != ok { ret (undefv(), je) }
    if !is_undefined(rv) || !is_undefined(jv) { ret (undefv(), throw_type(it, "Promise executor has already been invoked with non-undefined arguments")) }
    var a0 = undefv()
    var a1 = undefv()
    if args.len > 0usize { a0 = args[0usize] }
    if args.len > 1usize { a1 = args[1usize] }
    let e1 = define_data(it, cap, key_of("resolve"), a0, P_DEFAULT)
    let e2 = define_data(it, cap, key_of("reject"), a1, P_DEFAULT)
    ret (undefv(), ok)
}

fn new_promise_capability(it: *Interp, ctor: Value) -> (Capability, err) {
    var cap: Capability = zero
    if is_object(ctor) && as_object(ctor) == it.promise_ctor {
        let (p, pe) = new_promise(it)
        if pe != ok { ret (cap, pe) }
        let (rs, rj, re) = create_resolving_functions(it, p)
        if re != ok { ret (cap, re) }
        cap.promise = obj_value(p)
        cap.resolve = obj_value(rs)
        cap.reject = obj_value(rj)
        ret (cap, ok)
    }
    if !is_constructor(ctor) { ret (cap, throw_type(it, "Promise capability constructor is not a constructor")) }
    let holder = new_plain(it)
    let ex = make_native(it, "", 2u32, capability_executor)
    ex.aux = holder
    let (pv, ce) = construct(it, ctor, one_arg(it, obj_value(ex)), ctor)
    if ce != ok { ret (cap, ce) }
    let (rv, rve) = get_prop(it, holder, key_of("resolve"), obj_value(holder))
    if rve != ok { ret (cap, rve) }
    let (jv, jve) = get_prop(it, holder, key_of("reject"), obj_value(holder))
    if jve != ok { ret (cap, jve) }
    if !is_callable(rv) || !is_callable(jv) { ret (cap, throw_type(it, "Promise resolve or reject function is not callable")) }
    cap.promise = pv
    cap.resolve = rv
    cap.reject = jv
    ret (cap, ok)
}

// PerformPromiseThen on `p` with an optional result capability.
fn perform_then(it: *Interp, p: *Obj, on_ful: Value, on_rej: Value, cap: Capability, has_cap: bool) {
    let st = promise_state_of(p)
    var fh = undefv()
    var rh = undefv()
    if is_callable(on_ful) { fh = on_ful }
    if is_callable(on_rej) { rh = on_rej }
    let fr = Reaction { is_reject: false, handler: fh, cap_promise: cap.promise, cap_resolve: cap.resolve, cap_reject: cap.reject, has_cap: has_cap }
    let rr = Reaction { is_reject: true, handler: rh, cap_promise: cap.promise, cap_resolve: cap.resolve, cap_reject: cap.reject, has_cap: has_cap }
    if st.state == 0u8 {
        let a1 = list.push[Reaction](&st.fulfill, fr)
        let a2 = list.push[Reaction](&st.reject, rr)
    } else if st.state == 1u8 {
        enqueue_job(it, Job { kind: 1u8, a: fh, b: st.result, c: cap.resolve, d: cap.reject, is_reject: false })
    } else {
        enqueue_job(it, Job { kind: 1u8, a: rh, b: st.result, c: cap.resolve, d: cap.reject, is_reject: true })
    }
    st.handled = true
}

fn promise_then_raw(it: *Interp, p: *Obj, on_ful: Value, on_rej: Value) -> err {
    var cap: Capability = zero
    cap.promise = undefv()
    cap.resolve = undefv()
    cap.reject = undefv()
    perform_then(it, p, on_ful, on_rej, cap, false)
    ret ok
}

// PromiseResolve(%Promise%, v).
fn promise_resolve_value(it: *Interp, v: Value) -> (*Obj, err) {
    if is_object(v) && as_object(v).class == C_PROMISE {
        let (c, ce) = get_prop(it, as_object(v), key_of("constructor"), v)
        if ce != ok { ret (null_obj(), ce) }
        if is_object(c) && as_object(c) == it.promise_ctor { ret (as_object(v), ok) }
    }
    let (p, pe) = new_promise(it)
    if pe != ok { ret (p, pe) }
    let re = promise_resolve_with(it, p, v)
    if re != ok { ret (p, re) }
    ret (p, ok)
}

fn run_job(it: *Interp, j: Job) -> err {
    if j.kind == 2u8 {
        // PromiseResolveThenableJob.
        let p = as_object(j.a)
        let (rs, rj, re) = create_resolving_functions(it, p)
        if re != ok { ret re }
        let (r, ce) = call_function(it, j.c, j.b, two_args(it, obj_value(rs), obj_value(rj)))
        if ce != ok {
            if ce != Throw { ret ce }
            let (r2, ce2) = call_function(it, obj_value(rj), undefv(), one_arg(it, it.thrown))
            if ce2 != ok { ret ce2 }
        }
        ret ok
    }
    // Reaction job.
    var handler_result = undefv()
    var failed = false
    if is_undefined(j.a) {
        if j.is_reject {
            failed = true
            handler_result = j.b
        } else {
            handler_result = j.b
        }
    } else {
        let (r3, ce3) = call_function(it, j.a, undefv(), one_arg(it, j.b))
        if ce3 != ok {
            if ce3 != Throw { ret ce3 }
            failed = true
            handler_result = it.thrown
        } else {
            handler_result = r3
        }
    }
    if is_undefined(j.c) { ret ok }
    var tgt = j.c
    if failed { tgt = j.d }
    let (r4, ce4) = call_function(it, tgt, undefv(), one_arg(it, handler_result))
    ret ce4
}

// Runs queued promise jobs until none are left.
fn run_jobs(it: *Interp) -> err {
    var i = 0usize
    while i < it.jobs.len {
        let j = it.jobs.items[i]
        i += 1usize
        let e = run_job(it, j)
        if e != ok { ret e }
    }
    it.jobs.len = 0usize
    ret ok
}

// --- async iteration and async generators

fn get_async_iterator(it: *Interp, v: Value) -> (Iter, err) {
    let (m, me) = get_value(it, v, key_of_symbol(it.sym_async_iterator))
    if me != ok { ret (zero, me) }
    var iter: Iter = zero
    if is_nullish(m) {
        // Falls back to the sync iterator; its values are awaited as they come.
        let (si, se) = get_iterator(it, v)
        if se != ok { ret (zero, se) }
        iter = si
        iter.sync_wrapped = true
        ret (iter, ok)
    }
    if !is_callable(m) { ret (zero, throw_type(it, "object is not async iterable")) }
    let (io2, ie) = call_function(it, m, v, zero_args())
    if ie != ok { ret (zero, ie) }
    if !is_object(io2) { ret (zero, throw_type(it, "Result of the Symbol.asyncIterator method is not an object")) }
    let (nx, ne) = get_value(it, io2, key_of("next"))
    if ne != ok { ret (zero, ne) }
    iter.obj = io2
    iter.next = nx
    ret (iter, ok)
}

// One step of `for await`: (value, done, error); the frame supplies `await`.
fn async_iterator_step(it: *Interp, f: *Frame, iter: Iter) -> (Value, bool, err) {
    let (r, re) = call_function(it, iter.next, iter.obj, zero_args())
    if re != ok { ret (undefv(), true, re) }
    var result = r
    if !iter.sync_wrapped {
        let (aw, awe) = await_value(it, f, r)
        if awe != ok { ret (undefv(), true, awe) }
        result = aw
    }
    if !is_object(result) { ret (undefv(), true, throw_type(it, "Iterator result is not an object")) }
    let ro = as_object(result)
    let (dv, de) = get_prop(it, ro, key_of("done"), result)
    if de != ok { ret (undefv(), true, de) }
    if to_boolean(dv) { ret (undefv(), true, ok) }
    let (vv, ve) = get_prop(it, ro, key_of("value"), result)
    if ve != ok { ret (undefv(), true, ve) }
    if iter.sync_wrapped {
        let (aw2, awe2) = await_value(it, f, vv)
        if awe2 != ok { ret (undefv(), true, awe2) }
        ret (aw2, false, ok)
    }
    ret (vv, false, ok)
}

fn async_iterator_close(it: *Interp, f: *Frame, iter: Iter) -> err {
    let (rm, rme) = get_value(it, iter.obj, key_of("return"))
    if rme != ok { ret rme }
    if is_nullish(rm) { ret ok }
    let (r, re) = call_function(it, rm, iter.obj, zero_args())
    if re != ok { ret re }
    if iter.sync_wrapped { ret ok }
    let (aw, awe) = await_value(it, f, r)
    if awe != ok { ret awe }
    if !is_object(aw) { ret throw_type(it, "iterator.return() did not return an object") }
    ret ok
}

type AgRequest = struct { mode: u8, val: Value, cap: Capability }

fn ag_iter_result(it: *Interp, v: Value, done: bool) -> Value {
    let r = new_plain(it)
    let e1 = set_named(it, r, "value", v)
    let e2 = set_named(it, r, "done", bool_value(done))
    ret obj_value(r)
}

// Pops the front request after settling it.
fn ag_settle(it: *Interp, gs: *GenState, ok_value: bool, v: Value, done: bool) {
    if gs.queue.len == 0usize { ret }
    let req = gs.queue.items[0usize]
    var i = 0usize
    while i + 1usize < gs.queue.len {
        gs.queue.items[i] = gs.queue.items[i + 1usize]
        i += 1usize
    }
    gs.queue.len -= 1usize
    if ok_value {
        let (r, re) = call_function(it, req.cap.resolve, undefv(), one_arg(it, ag_iter_result(it, v, done)))
    } else {
        let (r2, re2) = call_function(it, req.cap.reject, undefv(), one_arg(it, v))
    }
}

fn ag_continue(it: *Interp, gs: *GenState, mode: u8, val: Value) {
    gs.busy = false
    ag_resume(it, gs, mode, val)
    ag_drain(it, gs)
}

fn ag_await_fulfilled(it: *Interp, this_val: Value, args: []const Value) -> (Value, err) {
    let gs = mem.cast[*GenState](it.callee.data)
    var v = undefv()
    if args.len > 0usize { v = args[0usize] }
    ag_continue(it, gs, RM_NEXT, v)
    ret (undefv(), ok)
}

fn ag_await_rejected(it: *Interp, this_val: Value, args: []const Value) -> (Value, err) {
    let gs = mem.cast[*GenState](it.callee.data)
    var v = undefv()
    if args.len > 0usize { v = args[0usize] }
    ag_continue(it, gs, RM_THROW, v)
    ret (undefv(), ok)
}

// A return request on a finished generator: the value is awaited, then the request resolves.
fn ag_return_fulfilled(it: *Interp, this_val: Value, args: []const Value) -> (Value, err) {
    let gs = mem.cast[*GenState](it.callee.data)
    var v = undefv()
    if args.len > 0usize { v = args[0usize] }
    gs.busy = false
    ag_settle(it, gs, true, v, true)
    ag_drain(it, gs)
    ret (undefv(), ok)
}

fn ag_return_rejected(it: *Interp, this_val: Value, args: []const Value) -> (Value, err) {
    let gs = mem.cast[*GenState](it.callee.data)
    var v = undefv()
    if args.len > 0usize { v = args[0usize] }
    gs.busy = false
    ag_settle(it, gs, false, v, true)
    ag_drain(it, gs)
    ret (undefv(), ok)
}

// Resumes the body for the front request and handles how it comes back.
fn ag_resume(it: *Interp, gs: *GenState, mode: u8, val: Value) {
    let (r, done, e) = gen_resume(it, gs, mode, val)
    if e != ok {
        var reason = it.thrown
        if e != Throw { reason = make_error(it, it.protos.error_proto, "internal error") }
        ag_settle(it, gs, false, reason, true)
        ret
    }
    if done {
        ag_settle(it, gs, true, r, true)
        ret
    }
    if gs.awaiting {
        gs.busy = true
        let (pr, pe) = promise_resolve_value(it, r)
        if pe != ok {
            gs.busy = false
            ag_resume(it, gs, RM_THROW, it.thrown)
            ret
        }
        let onf = make_native(it, "", 1u32, ag_await_fulfilled)
        onf.data = mem.cast[*void](gs)
        let onr = make_native(it, "", 1u32, ag_await_rejected)
        onr.data = mem.cast[*void](gs)
        let te = promise_then_raw(it, pr, obj_value(onf), obj_value(onr))
        ret
    }
    ag_settle(it, gs, true, r, false)
}

fn ag_drain(it: *Interp, gs: *GenState) {
    while gs.queue.len > 0usize && !gs.busy && gs.state != GS_RUNNING && !gs.awaiting {
        let req = gs.queue.items[0usize]
        if gs.state == GS_DONE || (gs.state == GS_START && req.mode != RM_NEXT) {
            gs.state = GS_DONE
            if req.mode == RM_NEXT {
                ag_settle(it, gs, true, undefv(), true)
            } else if req.mode == RM_THROW {
                ag_settle(it, gs, false, req.val, true)
            } else {
                gs.busy = true
                let (pr, pe) = promise_resolve_value(it, req.val)
                if pe != ok {
                    gs.busy = false
                    ag_settle(it, gs, false, it.thrown, true)
                } else {
                    let onf = make_native(it, "", 1u32, ag_return_fulfilled)
                    onf.data = mem.cast[*void](gs)
                    let onr = make_native(it, "", 1u32, ag_return_rejected)
                    onr.data = mem.cast[*void](gs)
                    let te = promise_then_raw(it, pr, obj_value(onf), obj_value(onr))
                }
            }
        } else {
            ag_resume(it, gs, req.mode, req.val)
        }
    }
}

// AsyncGenerator.prototype.next/return/throw: queue the request and run the generator when idle.
fn ag_enqueue(it: *Interp, this_val: Value, mode: u8, val: Value) -> (Value, err) {
    let (cap, cape) = new_promise_capability(it, obj_value(it.promise_ctor))
    if cape != ok { ret (undefv(), cape) }
    if !is_object(this_val) || as_object(this_val).class != C_GENERATOR || mem.cast[*GenState](as_object(this_val).data).kind != 2u8 {
        let (r, re) = call_function(it, cap.reject, undefv(), one_arg(it, make_error(it, it.protos.type_error, "not an async generator")))
        ret (cap.promise, re)
    }
    let gs = mem.cast[*GenState](as_object(this_val).data)
    let pe = list.push[AgRequest](&gs.queue, AgRequest { mode: mode, val: val, cap: cap })
    ag_drain(it, gs)
    ret (cap.promise, ok)
}

// `yield*` inside an async generator: delegates through the async iterator protocol, awaiting each inner result.
fn gen_yield_star_async(it: *Interp, f: *Frame, iterable: Value) -> (Value, err) {
    let gs = gen_state_of(f)
    let (iter, ie) = get_async_iterator(it, iterable)
    if ie != ok { ret (undefv(), ie) }
    var mode = RM_NEXT
    var received = undefv()
    while true {
        var inner = undefv()
        if mode == RM_NEXT {
            let (rv, re) = call_function(it, iter.next, iter.obj, one_arg(it, received))
            if re != ok { ret (undefv(), re) }
            inner = rv
        } else if mode == RM_THROW {
            let (tm, tme) = get_value(it, iter.obj, key_of("throw"))
            if tme != ok { ret (undefv(), tme) }
            if is_nullish(tm) {
                let ce = async_iterator_close(it, f, iter)
                if ce != ok { ret (undefv(), ce) }
                ret (undefv(), throw_type(it, "The iterator does not provide a 'throw' method"))
            }
            let (rv2, re2) = call_function(it, tm, iter.obj, one_arg(it, received))
            if re2 != ok { ret (undefv(), re2) }
            inner = rv2
        } else {
            let (rm, rme) = get_value(it, iter.obj, key_of("return"))
            if rme != ok { ret (undefv(), rme) }
            if is_nullish(rm) {
                let (aw, awe) = await_value(it, f, received)
                if awe != ok { ret (undefv(), awe) }
                gs.ret_val = aw
                ret (undefv(), GenReturn)
            }
            let (rv3, re3) = call_function(it, rm, iter.obj, one_arg(it, received))
            if re3 != ok { ret (undefv(), re3) }
            inner = rv3
        }
        // Await the inner result (a sync iterator's result is not a promise).
        if !iter.sync_wrapped {
            let (aw2, awe2) = await_value(it, f, inner)
            if awe2 != ok { ret (undefv(), awe2) }
            inner = aw2
        }
        if !is_object(inner) { ret (undefv(), throw_type(it, "iterator result is not an object")) }
        let (dn, dne) = get_value(it, inner, key_of("done"))
        if dne != ok { ret (undefv(), dne) }
        var value = undefv()
        let (vv, ve) = get_value(it, inner, key_of("value"))
        if ve != ok { ret (undefv(), ve) }
        value = vv
        if iter.sync_wrapped {
            let (aw3, awe3) = await_value(it, f, value)
            if awe3 != ok { ret (undefv(), awe3) }
            value = aw3
        }
        if to_boolean(dn) {
            if mode == RM_RETURN {
                gs.ret_val = value
                ret (undefv(), GenReturn)
            }
            ret (value, ok)
        }
        let (m2, s2) = gen_suspend(it, gs, value, false)
        mode = m2
        received = s2
        if mode == RM_RETURN {
            // The resumption value of a return request is awaited before it reaches the inner iterator.
            let (aw4, awe4) = await_value(it, f, received)
            if awe4 != ok { ret (undefv(), awe4) }
            received = aw4
        }
    }
    ret (undefv(), ok)
}

// --- typed arrays (the integer-indexed exotic object) and their buffers

type Buf = struct { bytes: []u8, detached: bool }

type TArr = struct { buffer: *Obj, offset: usize, length: usize, kind: u8, tracking: bool }

fn buf_of(o: *Obj) -> *Buf { ret mem.cast[*Buf](o.data) }
fn ta_of(o: *Obj) -> *TArr { ret mem.cast[*TArr](o.data) }

fn ta_elem_size(kind: u8) -> usize {
    if kind == 1u8 || kind == 2u8 || kind == 3u8 { ret 1usize }
    if kind == 4u8 || kind == 5u8 { ret 2usize }
    if kind == 6u8 || kind == 7u8 || kind == 8u8 { ret 4usize }
    ret 8usize
}

// The current element count (a length-tracking view follows its buffer; a detached one is zero).
fn ta_length(o: *Obj) -> usize {
    let t = ta_of(o)
    let b = buf_of(t.buffer)
    if b.detached { ret 0usize }
    if t.tracking {
        if t.offset > b.bytes.len { ret 0usize }
        ret (b.bytes.len - t.offset) / ta_elem_size(t.kind)
    }
    if t.offset + t.length * ta_elem_size(t.kind) > b.bytes.len { ret 0usize }
    ret t.length
}

fn read_unit(bytes: []const u8, at: usize, size: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < size {
        v = v | (u64(bytes[at + i]) << u64(8usize * i))
        i += 1usize
    }
    ret v
}

fn raw_to_value(kind: u8, raw: u64) -> Value {
    if kind == 2u8 || kind == 3u8 { ret num_value(f64(raw & 255u64)) }
    if kind == 1u8 {
        var v = i64(raw & 255u64)
        if v >= 128i64 { v = v - 256i64 }
        ret num_value(f64(v))
    }
    if kind == 5u8 { ret num_value(f64(raw & 65535u64)) }
    if kind == 4u8 {
        var v2 = i64(raw & 65535u64)
        if v2 >= 32768i64 { v2 = v2 - 65536i64 }
        ret num_value(f64(v2))
    }
    if kind == 7u8 { ret num_value(f64(raw & 4294967295u64)) }
    if kind == 6u8 {
        var v3 = i64(raw & 4294967295u64)
        if v3 >= 2147483648i64 { v3 = v3 - 4294967296i64 }
        ret num_value(f64(v3))
    }
    if kind == 8u8 { ret num_value(f64(mem.bitcast[f32](u32(raw & 4294967295u64)))) }
    ret num_value(mem.bitcast[f64](raw))
}

fn value_to_raw(kind: u8, n: f64) -> u64 {
    if kind == 9u8 { ret mem.bitcast[u64](n) }
    if kind == 8u8 { ret u64(mem.bitcast[u32](f32(n))) }
    if kind == 3u8 {
        if js_is_nan_value(n) { ret 0u64 }
        if n <= 0.0f64 { ret 0u64 }
        if n >= 255.0f64 { ret 255u64 }
        // Round half to even.
        let f = floor(n)
        let diff = n - f
        var r = f
        if diff > 0.5f64 || (diff == 0.5f64 && fmod_js(f, 2.0f64) != 0.0f64) { r = f + 1.0f64 }
        ret u64(i64(r))
    }
    let u = to_uint32_bits(n)
    if kind == 1u8 || kind == 2u8 { ret u64(u & 255u32) }
    if kind == 4u8 || kind == 5u8 { ret u64(u & 65535u32) }
    ret u64(u)
}

fn js_is_nan_value(n: f64) -> bool { ret n != n }

fn ta_get_index(it: *Interp, o: *Obj, idx: usize) -> Value {
    let t = ta_of(o)
    let b = buf_of(t.buffer)
    let size = ta_elem_size(t.kind)
    ret raw_to_value(t.kind, read_unit(b.bytes, t.offset + idx * size, size))
}

fn ta_set_raw(it: *Interp, o: *Obj, idx: usize, raw: u64) {
    let t = ta_of(o)
    let b = buf_of(t.buffer)
    let size = ta_elem_size(t.kind)
    var i = 0usize
    while i < size {
        b.bytes[t.offset + idx * size + i] = u8((raw >> u64(8usize * i)) & 255u64)
        i += 1usize
    }
}

// CanonicalNumericIndexString: (is numeric, value).
fn numeric_index(it: *Interp, name: str) -> (bool, f64) {
    if name.len == 0usize { ret (false, 0.0f64) }
    if str.eq(name, "-0") { ret (true, -0.0f64) }
    let c = name[0usize]
    if !(c == 45u8 || (c >= 48u8 && c <= 57u8) || c == 73u8 || c == 78u8) { ret (false, 0.0f64) }
    let n = string_to_number(it.a, name)
    if str.eq(number_to_string(it.a, n), name) { ret (true, n) }
    ret (false, 0.0f64)
}

fn ta_valid_index(o: *Obj, n: f64) -> bool {
    if n != to_integer(n) { ret false }
    if is_neg_zero(n) { ret false }
    if n < 0.0f64 || n >= f64(ta_length(o)) { ret false }
    ret true
}
