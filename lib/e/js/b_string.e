// String (browser tracker 5.7): the constructor, `fromCharCode`/`fromCodePoint`/`raw` and the prototype methods that work on
// plain string patterns. The RegExp-driven methods (`match`, `replace` with a pattern, `split` with a pattern, `search`) call
// the pattern's own `Symbol.match`/`replace`/`split`/`search` methods, which `e.js.b_regexp` installs.

use e.data.list as list
use e.js.interp as js
use e.mem
use e.str
use e.text.normalize as norm
use e.js.casing_data as cdata
use e.text.unicode as unicode

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

// The string a method works on: RequireObjectCoercible(this) then ToString.
fn this_str(it: *js.Interp, this_val: js.Value) -> (str, err) {
    if js.is_nullish(this_val) { ret ("", js.throw_type(it, "String.prototype method called on null or undefined")) }
    let (s, e) = js.to_string(it, this_val)
    ret (s, e)
}

fn string_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    var s = ""
    if args.len > 0usize {
        switch args[0usize] {
        case .Sym as sy:
            if !it.has_new_target {
                ret (js.str_value(js.str_concat3(it, "Symbol(", sy.description, ")")), ok)
            }
            ret (js.undefv(), js.throw_type(it, "Cannot convert a Symbol value to a string"))
        default:
            let (v, e) = js.to_string(it, args[0usize])
            if e != ok { ret (js.undefv(), e) }
            s = v
        }
    }
    if !it.has_new_target { ret (js.str_value(s), ok) }
    let nto = js.as_object(it.new_target)
    let (proto, pe) = js.proto_value_of(it, nto, it.protos.string)
    if pe != ok { ret (js.undefv(), pe) }
    let o = js.new_obj(it, js.C_STRING, proto)
    o.prim = js.str_value(s)
    ret (js.obj_value(o), ok)
}

fn this_string_value(it: *js.Interp, v: js.Value) -> (str, err) {
    switch v {
    case .Str as s:
        ret (s, ok)
    case .Obj as o:
        if o.class == js.C_STRING { ret (js.prim_string(o), ok) }
        ret ("", js.throw_type(it, "String.prototype.valueOf requires that 'this' be a String"))
    default:
        ret ("", js.throw_type(it, "String.prototype.valueOf requires that 'this' be a String"))
    }
    ret ("", ok)
}

fn string_to_string(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, e) = this_string_value(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.str_value(s), ok)
}

fn from_char_code(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    var i = 0usize
    // Units are collected first (a builder must stay on top of the arena, and the coercions run script), then paired up.
    var units_buf: [64]u32 = zero
    var n = 0usize
    var pending: u32 = 0u32
    var has_pending = false
    while i < args.len && n < 64usize {
        let (u, ue) = js.to_uint32(it, args[i])
        if ue != ok { ret (js.undefv(), ue) }
        units_buf[n] = u & 65535u32
        n += 1usize
        i += 1usize
    }
    let (b, be) = str.builder(it.a, args.len * 3usize + 4usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var out = b
    var k = 0usize
    while k < n {
        let u2 = units_buf[k]
        k += 1usize
        if u2 >= 55296u32 && u2 <= 56319u32 && k < n && units_buf[k] >= 56320u32 && units_buf[k] <= 57343u32 {
            js.put_cp(&out, 65536u32 + ((u2 - 55296u32) << 10u32) + (units_buf[k] - 56320u32))
            k += 1usize
        } else {
            js.put_cp(&out, u2)
        }
    }
    ret (js.str_value(str.done(&out)), ok)
}

fn from_code_point(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (b, be) = str.builder(it.a, args.len * 4usize + 4usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var out = b
    var cps: [64]u32 = zero
    var n = 0usize
    var i = 0usize
    while i < args.len && n < 64usize {
        let (num, ne) = js.to_number(it, args[i])
        if ne != ok { ret (js.undefv(), ne) }
        if num != js.to_integer(num) || num < 0.0f64 || num > 1114111.0f64 || js.is_nan(num) { ret (js.undefv(), js.throw_range(it, "Invalid code point")) }
        cps[n] = u32(i64(num))
        n += 1usize
        i += 1usize
    }
    var k = 0usize
    while k < n {
        js.put_cp(&out, cps[k])
        k += 1usize
    }
    ret (js.str_value(str.done(&out)), ok)
}

fn string_raw(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (cooked, ce) = js.to_object(it, arg(args, 0usize))
    if ce != ok { ret (js.undefv(), ce) }
    let (rv, re) = js.get_prop(it, cooked, js.key_of("raw"), js.obj_value(cooked))
    if re != ok { ret (js.undefv(), re) }
    let (raw, rawe) = js.to_object(it, rv)
    if rawe != ok { ret (js.undefv(), rawe) }
    let (len, le) = js.length_of(it, raw)
    if le != ok { ret (js.undefv(), le) }
    let (pl, ple) = list.init[str](it.a, usize(len) * 2usize + 1usize)
    var parts = pl
    var i = 0.0f64
    while i < len {
        let (seg, se) = js.get_index(it, raw, i)
        if se != ok { ret (js.undefv(), se) }
        let (ss, sse) = js.to_string(it, seg)
        if sse != ok { ret (js.undefv(), sse) }
        try list.push[str](&parts, ss)
        if i + 1.0f64 < len && usize(i) + 1usize < args.len {
            let (sub, sube) = js.to_string(it, args[usize(i) + 1usize])
            if sube != ok { ret (js.undefv(), sube) }
            try list.push[str](&parts, sub)
        }
        i += 1.0f64
    }
    var total = 0usize
    var q = 0usize
    while q < parts.len {
        total += parts.items[q].len
        q += 1usize
    }
    let (b, be) = str.builder(it.a, total + 1usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var out = b
    var k = 0usize
    while k < parts.len {
        let pe = str.push(&out, parts.items[k])
        k += 1usize
    }
    ret (js.str_value(str.done(&out)), ok)
}

fn char_at(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let pos = js.to_integer(n)
    if pos < 0.0f64 || pos >= f64(js.units(s)) { ret (js.str_value(""), ok) }
    ret (js.str_value(js.substring_units(it.a, s, usize(pos), usize(pos) + 1usize)), ok)
}

fn char_code_at(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let pos = js.to_integer(n)
    if pos < 0.0f64 || pos >= f64(js.units(s)) { ret (js.num_value(js.nan()), ok) }
    let (u, has) = js.unit_at(s, usize(pos))
    ret (js.num_value(f64(u)), ok)
}

fn code_point_at(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let pos = js.to_integer(n)
    if pos < 0.0f64 || pos >= f64(js.units(s)) { ret (js.undefv(), ok) }
    let (u, has) = js.unit_at(s, usize(pos))
    if u >= 55296u32 && u <= 56319u32 {
        let (u2, has2) = js.unit_at(s, usize(pos) + 1usize)
        if has2 && u2 >= 56320u32 && u2 <= 57343u32 { ret (js.num_value(f64(65536u32 + ((u - 55296u32) << 10u32) + (u2 - 56320u32))), ok) }
    }
    ret (js.num_value(f64(u)), ok)
}

fn string_at(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let len = f64(js.units(s))
    var k = js.to_integer(n)
    if k < 0.0f64 { k = len + k }
    if k < 0.0f64 || k >= len { ret (js.undefv(), ok) }
    ret (js.str_value(js.substring_units(it.a, s, usize(k), usize(k) + 1usize)), ok)
}

// Unit index of `needle` in `s` at or after unit `from` (-1 when absent).
fn index_of_units(it: *js.Interp, s: str, needle: str, from: usize) -> f64 {
    let start = js.byte_of_unit(s, from)
    if start > s.len { ret -1.0f64 }
    let (at, found) = str.find_from(s, needle, start)
    if !found { ret -1.0f64 }
    ret f64(js.units(s[0usize..at]))
}

fn string_index_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let (needle, ne) = js.to_string(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let (pn, pe) = js.to_number(it, arg(args, 1usize))
    if pe != ok { ret (js.undefv(), pe) }
    let len = f64(js.units(s))
    var pos = js.to_integer(pn)
    if pos < 0.0f64 { pos = 0.0f64 }
    if pos > len { pos = len }
    ret (js.num_value(index_of_units(it, s, needle, usize(pos))), ok)
}

fn string_last_index_of(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let (needle, ne) = js.to_string(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let (pn, pe) = js.to_number(it, arg(args, 1usize))
    if pe != ok { ret (js.undefv(), pe) }
    let len = f64(js.units(s))
    var pos = len
    if !js.is_nan(pn) { pos = js.to_integer(pn) }
    if pos < 0.0f64 { pos = 0.0f64 }
    if pos > len { pos = len }
    var last = -1.0f64
    var k = 0.0f64
    while k <= pos {
        let r = index_of_units(it, s, needle, usize(k))
        if r < 0.0f64 || r > pos { break }
        last = r
        k = r + 1.0f64
    }
    ret (js.num_value(last), ok)
}

fn is_regexp_value(it: *js.Interp, v: js.Value) -> (bool, err) {
    if !js.is_object(v) { ret (false, ok) }
    let (m, me) = js.get_prop(it, js.as_object(v), js.key_of_symbol(it.sym_match), v)
    if me != ok { ret (false, me) }
    if !js.is_undefined(m) { ret (js.to_boolean(m), ok) }
    ret (js.as_object(v).class == js.C_REGEXP, ok)
}

fn string_includes(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let (isre, ire) = is_regexp_value(it, arg(args, 0usize))
    if ire != ok { ret (js.undefv(), ire) }
    if isre { ret (js.undefv(), js.throw_type(it, "First argument to String.prototype.includes must not be a regular expression")) }
    let (needle, ne) = js.to_string(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let (pn, pe) = js.to_number(it, arg(args, 1usize))
    if pe != ok { ret (js.undefv(), pe) }
    var pos = js.to_integer(pn)
    let len = f64(js.units(s))
    if pos < 0.0f64 { pos = 0.0f64 }
    if pos > len { pos = len }
    ret (js.bool_value(index_of_units(it, s, needle, usize(pos)) >= 0.0f64), ok)
}

fn string_starts_with(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let (isre, ire) = is_regexp_value(it, arg(args, 0usize))
    if ire != ok { ret (js.undefv(), ire) }
    if isre { ret (js.undefv(), js.throw_type(it, "First argument to String.prototype.startsWith must not be a regular expression")) }
    let (needle, ne) = js.to_string(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let (pn, pe) = js.to_number(it, arg(args, 1usize))
    if pe != ok { ret (js.undefv(), pe) }
    var pos = js.to_integer(pn)
    let len = f64(js.units(s))
    if pos < 0.0f64 { pos = 0.0f64 }
    if pos > len { pos = len }
    let start = js.byte_of_unit(s, usize(pos))
    ret (js.bool_value(str.starts_with(s[start..], needle)), ok)
}

fn string_ends_with(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let (isre, ire) = is_regexp_value(it, arg(args, 0usize))
    if ire != ok { ret (js.undefv(), ire) }
    if isre { ret (js.undefv(), js.throw_type(it, "First argument to String.prototype.endsWith must not be a regular expression")) }
    let (needle, ne) = js.to_string(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let len = f64(js.units(s))
    var end = len
    if !js.is_undefined(arg(args, 1usize)) {
        let (en, ene) = js.to_number(it, args[1usize])
        if ene != ok { ret (js.undefv(), ene) }
        end = js.to_integer(en)
    }
    if end < 0.0f64 { end = 0.0f64 }
    if end > len { end = len }
    let end_byte = js.byte_of_unit(s, usize(end))
    ret (js.bool_value(str.ends_with(s[0usize..end_byte], needle)), ok)
}

fn clamp_index(it: *js.Interp, v: js.Value, len: f64, default_value: f64) -> (f64, err) {
    if js.is_undefined(v) { ret (default_value, ok) }
    let (n, e) = js.to_number(it, v)
    if e != ok { ret (0.0f64, e) }
    let i = js.to_integer(n)
    if i < 0.0f64 { ret (0.0f64, ok) }
    if i > len { ret (len, ok) }
    ret (i, ok)
}

fn string_slice(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let len = f64(js.units(s))
    var from = 0.0f64
    var to = len
    let (fn_, fe) = js.to_number(it, arg(args, 0usize))
    if fe != ok { ret (js.undefv(), fe) }
    from = js.to_integer(fn_)
    if from < 0.0f64 { from = len + from }
    if from < 0.0f64 { from = 0.0f64 }
    if from > len { from = len }
    if !js.is_undefined(arg(args, 1usize)) {
        let (tn, te) = js.to_number(it, args[1usize])
        if te != ok { ret (js.undefv(), te) }
        to = js.to_integer(tn)
        if to < 0.0f64 { to = len + to }
        if to < 0.0f64 { to = 0.0f64 }
        if to > len { to = len }
    }
    if from >= to { ret (js.str_value(""), ok) }
    ret (js.str_value(js.substring_units(it.a, s, usize(from), usize(to))), ok)
}

fn string_substring(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let len = f64(js.units(s))
    let (a0, ae) = clamp_index(it, arg(args, 0usize), len, 0.0f64)
    if ae != ok { ret (js.undefv(), ae) }
    let (a1, ae1) = clamp_index(it, arg(args, 1usize), len, len)
    if ae1 != ok { ret (js.undefv(), ae1) }
    var lo = a0
    var hi = a1
    if lo > hi {
        lo = a1
        hi = a0
    }
    ret (js.str_value(js.substring_units(it.a, s, usize(lo), usize(hi))), ok)
}

fn string_substr(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let len = f64(js.units(s))
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    var start = js.to_integer(n)
    if start < 0.0f64 { start = len + start }
    if start < 0.0f64 { start = 0.0f64 }
    if start > len { start = len }
    var count = len - start
    if !js.is_undefined(arg(args, 1usize)) {
        let (cn, cne) = js.to_number(it, args[1usize])
        if cne != ok { ret (js.undefv(), cne) }
        count = js.to_integer(cn)
        if count < 0.0f64 { count = 0.0f64 }
        if count > len - start { count = len - start }
    }
    if count <= 0.0f64 { ret (js.str_value(""), ok) }
    ret (js.str_value(js.substring_units(it.a, s, usize(start), usize(start + count))), ok)
}

fn is_cased(cp: u32) -> bool {
    let c = unicode.category(cp)
    ret c == unicode.Category.Lu || c == unicode.Category.Ll || c == unicode.Category.Lt
}

fn is_case_ignorable(cp: u32) -> bool {
    let c = unicode.category(cp)
    if c == unicode.Category.Mn || c == unicode.Category.Me || c == unicode.Category.Cf || c == unicode.Category.Lm || c == unicode.Category.Sk { ret true }
    ret cp == 39u32 || cp == 46u32 || cp == 58u32 || cp == 94u32 || cp == 96u32 || cp == 168u32 || cp == 173u32 || cp == 175u32 || cp == 180u32 || cp == 183u32 || cp == 184u32 || cp == 8216u32 || cp == 8217u32 || cp == 8228u32 || cp == 8231u32
}

// Whether the sigma at [start, end) is a final sigma (Unicode SpecialCasing, Final_Sigma): a cased letter before it and none after,
// with case-ignorable characters skipped on both sides.
fn sigma_is_final(s: str, start: usize, end: usize) -> bool {
    var before = false
    var i = start
    while i > 0usize {
        var j = i - 1usize
        while j > 0usize && (s[j] & 192u8) == 128u8 { j -= 1usize }
        let (cp, l) = js.decode_at(s, j)
        i = j
        if is_case_ignorable(cp) { continue }
        before = is_cased(cp)
        break
    }
    if !before { ret false }
    var k = end
    while k < s.len {
        let (cp2, l2) = js.decode_at(s, k)
        k += l2
        if is_case_ignorable(cp2) { continue }
        ret !is_cased(cp2)
    }
    ret true
}

fn map_case(it: *js.Interp, s: str, upper: bool) -> str {
    let (b, be) = str.builder(it.a, s.len * 2usize + 4usize)
    if be != ok { ret s }
    var out = b
    var i = 0usize
    while i < s.len {
        let (cp, l) = js.decode_at(s, i)
        i += l
        if upper {
            let (u1, u2, u3, un) = cdata.upper_special(cp)
            if un > 0usize {
                js.put_cp(&out, u1)
                if un > 1usize { js.put_cp(&out, u2) }
                if un > 2usize { js.put_cp(&out, u3) }
            } else {
                js.put_cp(&out, unicode.to_upper_simple(cp))
            }
        } else {
            if cp == 931u32 {
                // Final sigma: preceded by a cased letter and not followed by one, skipping case-ignorable characters.
                if sigma_is_final(s, i - l, i) { js.put_cp(&out, 962u32) } else { js.put_cp(&out, 963u32) }
            } else if cp == 304u32 {
                js.put_cp(&out, 105u32)
                js.put_cp(&out, 775u32)
            } else {
                js.put_cp(&out, unicode.to_lower_simple(cp))
            }
        }
    }
    ret str.done(&out)
}

fn string_to_upper(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    ret (js.str_value(map_case(it, s, true)), ok)
}

fn string_to_lower(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    ret (js.str_value(map_case(it, s, false)), ok)
}

fn string_trim(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    ret (js.str_value(js.trim_js(s)), ok)
}

fn trim_start_str(s: str) -> str {
    var start = 0usize
    while start < s.len {
        let n = js.space_len(s, start)
        if n == 0usize { break }
        start += n
    }
    ret s[start..]
}

fn trim_end_str(s: str) -> str {
    let both = js.trim_js(s)
    // Keep the leading whitespace: find where the trimmed text starts.
    var start = 0usize
    while start < s.len {
        let n = js.space_len(s, start)
        if n == 0usize { break }
        start += n
    }
    if both.len == 0usize { ret "" }
    ret s[0usize..start + both.len]
}

fn string_trim_start(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    ret (js.str_value(trim_start_str(s)), ok)
}

fn string_trim_end(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    ret (js.str_value(trim_end_str(s)), ok)
}

fn pad(it: *js.Interp, this_val: js.Value, args: []const js.Value, at_start: bool) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let (ln, lne) = js.to_length(it, arg(args, 0usize))
    if lne != ok { ret (js.undefv(), lne) }
    let cur = f64(js.units(s))
    if ln <= cur { ret (js.str_value(s), ok) }
    var filler = " "
    if !js.is_undefined(arg(args, 1usize)) {
        let (f, fe) = js.to_string(it, args[1usize])
        if fe != ok { ret (js.undefv(), fe) }
        filler = f
    }
    if filler.len == 0usize { ret (js.str_value(s), ok) }
    var need = ln - cur
    if need > 536870888.0f64 { ret (js.undefv(), js.throw_range(it, "Invalid string length")) }
    let fl = f64(js.units(filler))
    let (b, be) = str.builder(it.a, usize(need) * filler.len + 8usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var out = b
    var made = 0.0f64
    while made + fl <= need {
        let pe = str.push(&out, filler)
        made += fl
    }
    let padding_full = str.done(&out)
    var padding = padding_full
    if made < need { padding = js.str_concat(it, padding_full, js.substring_units(it.a, filler, 0usize, usize(need - made))) }
    if at_start { ret (js.str_value(js.str_concat(it, padding, s)), ok) }
    ret (js.str_value(js.str_concat(it, s, padding)), ok)
}

fn string_pad_start(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = pad(it, this_val, args, true)
    ret (r, e) }
fn string_pad_end(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = pad(it, this_val, args, false)
    ret (r, e) }

fn string_repeat(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    let count = js.to_integer(n)
    if count < 0.0f64 || js.is_infinite(count) { ret (js.undefv(), js.throw_range(it, "Invalid count value")) }
    if count == 0.0f64 || s.len == 0usize { ret (js.str_value(""), ok) }
    if count * f64(s.len) > 536870888.0f64 { ret (js.undefv(), js.throw_range(it, "Invalid string length")) }
    let (b, be) = str.builder(it.a, usize(count) * s.len + 4usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var out = b
    var i = 0usize
    while f64(i) < count {
        let pe = str.push(&out, s)
        i += 1usize
    }
    ret (js.str_value(str.done(&out)), ok)
}

fn string_concat_m(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    var acc = s
    var i = 0usize
    while i < args.len {
        let (t, te) = js.to_string(it, args[i])
        if te != ok { ret (js.undefv(), te) }
        acc = js.str_concat(it, acc, t)
        i += 1usize
    }
    ret (js.str_value(acc), ok)
}

fn string_split(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if js.is_nullish(this_val) { ret (js.undefv(), js.throw_type(it, "String.prototype.split called on null or undefined")) }
    let sep = arg(args, 0usize)
    if js.is_object(sep) {
        let (splitter, se0) = js.get_value(it, sep, js.key_of_symbol(it.sym_split))
        if se0 != ok { ret (js.undefv(), se0) }
        if !js.is_nullish(splitter) {
            let (r, re) = js.call_function(it, splitter, sep, js.two_args(it, this_val, arg(args, 1usize)))
            ret (r, re)
        }
    }
    let (s, se) = js.to_string(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    var lim = 4294967295u32
    if !js.is_undefined(arg(args, 1usize)) {
        let (l, le) = js.to_uint32(it, args[1usize])
        if le != ok { ret (js.undefv(), le) }
        lim = l
    }
    let (r_str, rse) = js.to_string(it, sep)
    if rse != ok { ret (js.undefv(), rse) }
    let out = js.new_array(it)
    if lim == 0u32 { ret (js.obj_value(out), ok) }
    if js.is_undefined(sep) {
        try js.array_push(it, out, js.str_value(s))
        ret (js.obj_value(out), ok)
    }
    if s.len == 0usize {
        if r_str.len > 0usize { try js.array_push(it, out, js.str_value(s)) }
        ret (js.obj_value(out), ok)
    }
    if r_str.len == 0usize {
        // Split into UTF-16 code units.
        let n = js.units(s)
        var k = 0usize
        while k < n && u32(k) < lim {
            try js.array_push(it, out, js.str_value(js.substring_units(it.a, s, k, k + 1usize)))
            k += 1usize
        }
        ret (js.obj_value(out), ok)
    }
    var pos = 0usize
    while true {
        let (at, found) = str.find_from(s, r_str, pos)
        if !found { break }
        try js.array_push(it, out, js.str_value(s[pos..at]))
        if u32(out.elems.len) >= lim { ret (js.obj_value(out), ok) }
        pos = at + r_str.len
    }
    try js.array_push(it, out, js.str_value(s[pos..]))
    ret (js.obj_value(out), ok)
}

fn string_locale_compare(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let (t, te) = js.to_string(it, arg(args, 0usize))
    if te != ok { ret (js.undefv(), te) }
    // Canonically equivalent strings compare equal: both are compared in decomposed form.
    var sa = s
    var ta = t
    let (sn, sne) = norm.normalize(it.a, s, norm.Form.Nfd)
    let (tn, tne) = norm.normalize(it.a, t, norm.Form.Nfd)
    if sne == ok && tne == ok {
        sa = sn
        ta = tn
    }
    let c = js.compare_utf16(sa, ta)
    if c < 0i32 { ret (js.num_value(-1.0f64), ok) }
    if c > 0i32 { ret (js.num_value(1.0f64), ok) }
    ret (js.num_value(0.0f64), ok)
}

fn string_normalize(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    var form = "NFC"
    if !js.is_undefined(arg(args, 0usize)) {
        let (f, fe) = js.to_string(it, args[0usize])
        if fe != ok { ret (js.undefv(), fe) }
        form = f
    }
    if !(str.eq(form, "NFC") || str.eq(form, "NFD") || str.eq(form, "NFKC") || str.eq(form, "NFKD")) { ret (js.undefv(), js.throw_range(it, "The normalization form should be one of NFC, NFD, NFKC, NFKD.")) }
    var nf = norm.Form.Nfc
    if str.eq(form, "NFD") { nf = norm.Form.Nfd } else if str.eq(form, "NFKC") { nf = norm.Form.Nfkc } else if str.eq(form, "NFKD") { nf = norm.Form.Nfkd }
    let (out, ne) = norm.normalize(it.a, s, nf)
    // A string with a lone surrogate is not valid text for the normalizer; it passes through unchanged.
    if ne != ok { ret (js.str_value(s), ok) }
    ret (js.str_value(out), ok)
}

// Replacement string expansion: $$, $&, $`, $', $n, $<name>.
fn expand_replacement(it: *js.Interp, matched: str, s: str, position: usize, captures: []const js.Value, replacement: str) -> str {
    let (b, be) = str.builder(it.a, replacement.len + matched.len + 8usize)
    if be != ok { ret replacement }
    var out = b
    var i = 0usize
    while i < replacement.len {
        let c = replacement[i]
        if c == 36u8 && i + 1usize < replacement.len {
            let d = replacement[i + 1usize]
            if d == 36u8 {
                let pe = str.push_byte(&out, 36u8)
                i += 2usize
                continue
            }
            if d == 38u8 {
                let pe2 = str.push(&out, matched)
                i += 2usize
                continue
            }
            if d == 96u8 {
                let pe3 = str.push(&out, s[0usize..position])
                i += 2usize
                continue
            }
            if d == 39u8 {
                let tail = position + matched.len
                if tail < s.len { let pe4 = str.push(&out, s[tail..]) }
                i += 2usize
                continue
            }
            if d >= 48u8 && d <= 57u8 {
                var idx = usize(d - 48u8)
                var used = 2usize
                if i + 2usize < replacement.len && replacement[i + 2usize] >= 48u8 && replacement[i + 2usize] <= 57u8 {
                    let two = idx * 10usize + usize(replacement[i + 2usize] - 48u8)
                    if two >= 1usize && two <= captures.len {
                        idx = two
                        used = 3usize
                    }
                }
                if idx >= 1usize && idx <= captures.len {
                    let cv = captures[idx - 1usize]
                    if !js.is_undefined(cv) {
                        let (cs, cse) = js.to_string(it, cv)
                        if cse == ok { let pe5 = str.push(&out, cs) }
                    }
                    i += used
                    continue
                }
            }
        }
        let pe6 = str.push_byte(&out, c)
        i += 1usize
    }
    ret str.done(&out)
}

fn replace_impl(it: *js.Interp, this_val: js.Value, args: []const js.Value, all: bool) -> (js.Value, err) {
    if js.is_nullish(this_val) { ret (js.undefv(), js.throw_type(it, "String.prototype.replace called on null or undefined")) }
    let search = arg(args, 0usize)
    let rep = arg(args, 1usize)
    if js.is_object(search) {
        if all {
            let (isre, ire) = is_regexp_value(it, search)
            if ire != ok { ret (js.undefv(), ire) }
            if isre {
                let (fl, fle) = js.get_value(it, search, js.key_of("flags"))
                if fle != ok { ret (js.undefv(), fle) }
                if js.is_nullish(fl) { ret (js.undefv(), js.throw_type(it, "flags is undefined")) }
                let (fls, flse) = js.to_string(it, fl)
                if flse != ok { ret (js.undefv(), flse) }
                if !str.contains(fls, "g") { ret (js.undefv(), js.throw_type(it, "replaceAll must be called with a global RegExp")) }
            }
        }
        let (replacer, re0) = js.get_value(it, search, js.key_of_symbol(it.sym_replace))
        if re0 != ok { ret (js.undefv(), re0) }
        if !js.is_nullish(replacer) {
            let (r, re) = js.call_function(it, replacer, search, js.two_args(it, this_val, rep))
            ret (r, re)
        }
    }
    let (s, se) = js.to_string(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let (pat, pe) = js.to_string(it, search)
    if pe != ok { ret (js.undefv(), pe) }
    var rep_str = ""
    let callable = js.is_callable(rep)
    if !callable {
        let (rs, rse) = js.to_string(it, rep)
        if rse != ok { ret (js.undefv(), rse) }
        rep_str = rs
    }
    let (pl, ple) = list.init[str](it.a, 8usize)
    var parts = pl
    var pos = 0usize
    var search_from = 0usize
    while true {
        var at = 0usize
        var found = false
        if pat.len == 0usize {
            if search_from <= s.len {
                at = search_from
                found = true
            }
        } else {
            let (a2, f2) = str.find_from(s, pat, search_from)
            at = a2
            found = f2
        }
        if !found { break }
        try list.push[str](&parts, s[pos..at])
        var replacement = ""
        if callable {
            let (rv, rve) = js.call_function(it, rep, js.undefv(), three_args(it, js.str_value(pat), js.num_value(f64(js.units(s[0usize..at]))), js.str_value(s)))
            if rve != ok { ret (js.undefv(), rve) }
            let (rvs, rvse) = js.to_string(it, rv)
            if rvse != ok { ret (js.undefv(), rvse) }
            replacement = rvs
        } else {
            replacement = expand_replacement(it, pat, s, at, js.zero_args(), rep_str)
        }
        try list.push[str](&parts, replacement)
        pos = at + pat.len
        if !all { break }
        if pat.len == 0usize {
            if at >= s.len { break }
            let (cp, cl) = js.decode_at(s, at)
            search_from = at + cl
            try list.push[str](&parts, s[at..at + cl])
            pos = at + cl
        } else {
            search_from = pos
        }
    }
    if pos < s.len { try list.push[str](&parts, s[pos..]) }
    var total = 0usize
    var q = 0usize
    while q < parts.len {
        total += parts.items[q].len
        q += 1usize
    }
    let (b, be) = str.builder(it.a, total + 1usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var out = b
    var k = 0usize
    while k < parts.len {
        let pe2 = str.push(&out, parts.items[k])
        k += 1usize
    }
    ret (js.str_value(str.done(&out)), ok)
}

fn three_args(it: *js.Interp, x: js.Value, y: js.Value, z: js.Value) -> []const js.Value {
    let (cell, ce) = mem.alloc[js.Value](it.a, 3usize)
    if ce != ok { ret js.zero_args() }
    cell[0usize] = x
    cell[1usize] = y
    cell[2usize] = z
    ret cell[0usize..3usize]
}

fn string_replace(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = replace_impl(it, this_val, args, false)
    ret (r, e) }
fn string_replace_all(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = replace_impl(it, this_val, args, true)
    ret (r, e) }

// match / matchAll / search delegate to the pattern's symbol method; a non-pattern is turned into a RegExp first.
fn delegate(it: *js.Interp, this_val: js.Value, args: []const js.Value, sym: *js.Sym, extra_flags: str) -> (js.Value, err) {
    if js.is_nullish(this_val) { ret (js.undefv(), js.throw_type(it, "String.prototype method called on null or undefined")) }
    let pat = arg(args, 0usize)
    if js.is_object(pat) {
        let (m, me) = js.get_value(it, pat, js.key_of_symbol(sym))
        if me != ok { ret (js.undefv(), me) }
        if !js.is_nullish(m) {
            let (r, re) = js.call_function(it, m, pat, js.one_arg(it, this_val))
            ret (r, re)
        }
    }
    let (s, se) = js.to_string(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    var src = ""
    if !js.is_undefined(pat) {
        let (ps, pse) = js.to_string(it, pat)
        if pse != ok { ret (js.undefv(), pse) }
        src = ps
    }
    let (rx, rxe) = js.make_regexp(it, src, extra_flags)
    if rxe != ok { ret (js.undefv(), rxe) }
    let (m2, m2e) = js.get_value(it, rx, js.key_of_symbol(sym))
    if m2e != ok { ret (js.undefv(), m2e) }
    let (r2, r2e) = js.call_function(it, m2, rx, js.one_arg(it, js.str_value(s)))
    ret (r2, r2e)
}

fn string_match(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = delegate(it, this_val, args, it.sym_match, "")
    ret (r, e) }
fn string_match_all(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let pat = arg(args, 0usize)
    if !js.is_nullish(pat) {
        let (isre, ire) = is_regexp_value(it, pat)
        if ire != ok { ret (js.undefv(), ire) }
        if isre {
            let (fl, fle) = js.get_value(it, pat, js.key_of("flags"))
            if fle != ok { ret (js.undefv(), fle) }
            if js.is_nullish(fl) { ret (js.undefv(), js.throw_type(it, "flags is undefined")) }
            let (fls, flse) = js.to_string(it, fl)
            if flse != ok { ret (js.undefv(), flse) }
            if !str.contains(fls, "g") { ret (js.undefv(), js.throw_type(it, "String.prototype.matchAll called with a non-global RegExp argument")) }
        }
    }
    let (r, e) = delegate(it, this_val, args, it.sym_match_all, "g")
    ret (r, e)
}
fn string_search(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = delegate(it, this_val, args, it.sym_search, "")
    ret (r, e) }

// --- iterator

fn string_iterator(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = this_str(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    let iter = js.new_obj(it, js.C_ITERATOR, it.str_iter_proto)
    iter.text = "string"
    iter.prim = js.str_value(s)
    iter.num = 0.0f64
    ret (js.obj_value(iter), ok)
}

fn string_iterator_next(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) || js.as_object(this_val).class != js.C_ITERATOR || !str.eq(js.as_object(this_val).text, "string") {
        ret (js.undefv(), js.throw_type(it, "next method called on incompatible receiver"))
    }
    let iter = js.as_object(this_val)
    let s = js.value_str(iter.prim)
    let at = usize(iter.num)
    if at >= s.len { ret (js.obj_value(result_object(it, js.undefv(), true)), ok) }
    let (cp, l) = js.decode_at(s, at)
    iter.num = f64(at + l)
    ret (js.obj_value(result_object(it, js.str_value(s[at..at + l]), false)), ok)
}

fn result_object(it: *js.Interp, v: js.Value, done: bool) -> *js.Obj {
    let r = js.new_plain(it)
    let e1 = js.set_named(it, r, "value", v)
    let e2 = js.set_named(it, r, "done", js.bool_value(done))
    ret r
}

fn install_string(it: *js.Interp) {
    // %StringIteratorPrototype%
    it.str_iter_proto = js.new_obj(it, js.C_OBJECT, it.protos.iterator)
    js.add_method(it, it.str_iter_proto, "next", 0u32, string_iterator_next)
    let eti = js.define_data(it, it.str_iter_proto, js.key_of_symbol(it.sym_to_string_tag), js.str_value("String Iterator"), js.P_CONFIGURABLE)
    let proto = it.protos.string
    let ctor = js.make_native(it, "String", 1u32, string_ctor)
    ctor.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, ctor, js.key_of("prototype"), js.obj_value(proto), 0u8)
    let e2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(ctor), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of("String"), js.obj_value(ctor), js.P_HIDDEN)
    it.last = ctor
    js.add_method(it, it.last, "fromCharCode", 1u32, from_char_code)
    js.add_method(it, it.last, "fromCodePoint", 1u32, from_code_point)
    js.add_method(it, it.last, "raw", 1u32, string_raw)
    js.add_method(it, it.protos.string, "toString", 0u32, string_to_string)
    js.add_method(it, it.protos.string, "valueOf", 0u32, string_to_string)
    js.add_method(it, it.protos.string, "charAt", 1u32, char_at)
    js.add_method(it, it.protos.string, "charCodeAt", 1u32, char_code_at)
    js.add_method(it, it.protos.string, "codePointAt", 1u32, code_point_at)
    js.add_method(it, it.protos.string, "at", 1u32, string_at)
    js.add_method(it, it.protos.string, "indexOf", 1u32, string_index_of)
    js.add_method(it, it.protos.string, "lastIndexOf", 1u32, string_last_index_of)
    js.add_method(it, it.protos.string, "includes", 1u32, string_includes)
    js.add_method(it, it.protos.string, "startsWith", 1u32, string_starts_with)
    js.add_method(it, it.protos.string, "endsWith", 1u32, string_ends_with)
    js.add_method(it, it.protos.string, "slice", 2u32, string_slice)
    js.add_method(it, it.protos.string, "substring", 2u32, string_substring)
    js.add_method(it, it.protos.string, "substr", 2u32, string_substr)
    js.add_method(it, it.protos.string, "toUpperCase", 0u32, string_to_upper)
    js.add_method(it, it.protos.string, "toLowerCase", 0u32, string_to_lower)
    js.add_method(it, it.protos.string, "toLocaleUpperCase", 0u32, string_to_upper)
    js.add_method(it, it.protos.string, "toLocaleLowerCase", 0u32, string_to_lower)
    js.add_method(it, it.protos.string, "trim", 0u32, string_trim)
    js.add_method(it, it.protos.string, "trimStart", 0u32, string_trim_start)
    js.add_method(it, it.protos.string, "trimEnd", 0u32, string_trim_end)
    js.add_method(it, it.protos.string, "padStart", 1u32, string_pad_start)
    js.add_method(it, it.protos.string, "padEnd", 1u32, string_pad_end)
    js.add_method(it, it.protos.string, "repeat", 1u32, string_repeat)
    js.add_method(it, it.protos.string, "concat", 1u32, string_concat_m)
    js.add_method(it, it.protos.string, "split", 2u32, string_split)
    js.add_method(it, it.protos.string, "localeCompare", 1u32, string_locale_compare)
    js.add_method(it, it.protos.string, "normalize", 0u32, string_normalize)
    js.add_method(it, it.protos.string, "replace", 2u32, string_replace)
    js.add_method(it, it.protos.string, "replaceAll", 2u32, string_replace_all)
    js.add_method(it, it.protos.string, "match", 1u32, string_match)
    js.add_method(it, it.protos.string, "matchAll", 1u32, string_match_all)
    js.add_method(it, it.protos.string, "search", 1u32, string_search)
    let iter_fn = js.make_native(it, "[Symbol.iterator]", 0u32, string_iterator)
    let e4 = js.define_data(it, it.protos.string, js.key_of_symbol(it.sym_iterator), js.obj_value(iter_fn), js.P_HIDDEN)
}
