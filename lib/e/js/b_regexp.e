// RegExp (browser tracker 5.10): the constructor, `exec`/`test`/`toString`, the flag accessors and the `Symbol.match`,
// `matchAll`, `replace`, `search` and `split` methods over the engine in `e.js.regex`.

use e.data.list as list
use e.js.interp as js
use e.js.regex as rx
use e.mem
use e.str

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

type Compiled = struct { re: rx.Regex, source: str, flags: str }

fn compiled_of(o: *js.Obj) -> *Compiled { ret mem.cast[*Compiled](o.data) }

fn is_regexp_obj(v: js.Value) -> bool { ret js.is_object(v) && js.as_object(v).class == js.C_REGEXP && js.as_object(v).data != zero_ptr() }

fn zero_ptr() -> *void {
    var p: *void = zero
    ret p
}

// The UTF-16 units of `s`.
fn to_units(a: *mem.Arena, s: str) -> []const u16 {
    let n = js.units(s)
    let (cell, ce) = mem.alloc[u16](a, n + 1usize)
    if ce != ok {
        var none: []const u16 = zero
        ret none
    }
    var i = 0usize
    var k = 0usize
    while i < s.len {
        if s[i] < 128u8 {
            cell[k] = u16(s[i])
            k += 1usize
            i += 1usize
        } else {
            let (cp, l) = js.decode_at(s, i)
            if cp >= 65536u32 {
                let v = cp - 65536u32
                cell[k] = u16(55296u32 + (v >> 10u32))
                cell[k + 1usize] = u16(56320u32 + (v & 1023u32))
                k += 2usize
            } else {
                cell[k] = u16(cp)
                k += 1usize
            }
            i += l
        }
    }
    ret cell[0usize..k]
}

// The UTF-8 string for UTF-16 `units[from..to]`.
fn from_units(it: *js.Interp, units: []const u16, from: usize, to: usize) -> str {
    let (b, be) = str.builder(it.a, (to - from) * 3usize + 4usize)
    if be != ok { ret "" }
    var out = b
    var i = from
    while i < to {
        let u = u32(units[i])
        if u >= 55296u32 && u <= 56319u32 && i + 1usize < to {
            let lo = u32(units[i + 1usize])
            if lo >= 56320u32 && lo <= 57343u32 {
                js.put_cp(&out, 65536u32 + ((u - 55296u32) << 10u32) + (lo - 56320u32))
                i += 2usize
                continue
            }
        }
        if u >= 55296u32 && u <= 57343u32 { js.put_cp(&out, 65533u32) } else { js.put_cp(&out, u) }
        i += 1usize
    }
    ret str.done(&out)
}

fn escape_source(it: *js.Interp, src: str) -> str {
    if src.len == 0usize { ret "(?:)" }
    let (b, be) = str.builder(it.a, src.len * 2usize + 4usize)
    if be != ok { ret src }
    var out = b
    var in_class = false
    var i = 0usize
    while i < src.len {
        let c = src[i]
        if c == 92u8 && i + 1usize < src.len {
            let pe = str.push_byte(&out, c)
            let pe2 = str.push_byte(&out, src[i + 1usize])
            i += 2usize
            continue
        }
        if c == 91u8 { in_class = true }
        if c == 93u8 { in_class = false }
        if c == 47u8 && !in_class {
            let pe3 = str.push(&out, "\\/")
        } else if c == 10u8 {
            let pe4 = str.push(&out, "\\n")
        } else if c == 13u8 {
            let pe5 = str.push(&out, "\\r")
        } else if c == 226u8 && i + 2usize < src.len && src[i + 1usize] == 128u8 && (src[i + 2usize] == 168u8 || src[i + 2usize] == 169u8) {
            if src[i + 2usize] == 168u8 { let pe6 = str.push(&out, "\\u2028") } else { let pe7 = str.push(&out, "\\u2029") }
            i += 3usize
            continue
        } else {
            let pe8 = str.push_byte(&out, c)
        }
        i += 1usize
    }
    ret str.done(&out)
}

// Builds a RegExp object for `source`/`flags` with the given prototype.
fn regexp_create(it: *js.Interp, proto: *js.Obj, source: str, flags: str) -> (js.Value, err) {
    let units = to_units(it.a, source)
    let (re, msg, ce) = rx.compile(it.a, units, flags)
    if ce != ok { ret (js.undefv(), js.throw_syntax(it, js.str_concat3(it, "Invalid regular expression: /", source, js.str_concat(it, "/: ", msg)))) }
    let o = js.new_obj(it, js.C_REGEXP, proto)
    let (cell, me) = mem.alloc[Compiled](it.a, 1usize)
    if me != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    cell[0usize] = Compiled { re: re, source: source, flags: flags }
    o.data = mem.cast[*void](&cell[0usize])
    let pe = js.define_data(it, o, js.key_of("lastIndex"), js.num_value(0.0f64), js.P_WRITABLE)
    ret (js.obj_value(o), ok)
}

fn regexp_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let pattern = arg(args, 0usize)
    let flags_arg = arg(args, 1usize)
    var pattern_is_regexp = false
    if js.is_object(pattern) {
        let (m, me) = js.get_prop(it, js.as_object(pattern), js.key_of_symbol(it.sym_match), pattern)
        if me != ok { ret (js.undefv(), me) }
        if !js.is_undefined(m) { pattern_is_regexp = js.to_boolean(m) } else { pattern_is_regexp = is_regexp_obj(pattern) }
    }
    if !it.has_new_target {
        if pattern_is_regexp && js.is_undefined(flags_arg) {
            let (pc, pce) = js.get_prop(it, js.as_object(pattern), js.key_of("constructor"), pattern)
            if pce != ok { ret (js.undefv(), pce) }
            if js.is_object(pc) && js.as_object(pc) == it.callee { ret (pattern, ok) }
        }
    }
    var source = ""
    var flags = ""
    if is_regexp_obj(pattern) {
        let c = compiled_of(js.as_object(pattern))
        source = c.source
        if js.is_undefined(flags_arg) { flags = c.flags }
    } else if pattern_is_regexp {
        let (sv, se) = js.get_prop(it, js.as_object(pattern), js.key_of("source"), pattern)
        if se != ok { ret (js.undefv(), se) }
        let (ss, sse) = js.to_string(it, sv)
        if sse != ok { ret (js.undefv(), sse) }
        source = ss
        if js.is_undefined(flags_arg) {
            let (fv, fe) = js.get_prop(it, js.as_object(pattern), js.key_of("flags"), pattern)
            if fe != ok { ret (js.undefv(), fe) }
            let (fs, fse) = js.to_string(it, fv)
            if fse != ok { ret (js.undefv(), fse) }
            flags = fs
        }
    } else if !js.is_undefined(pattern) {
        let (ps, pse) = js.to_string(it, pattern)
        if pse != ok { ret (js.undefv(), pse) }
        source = ps
    }
    if !js.is_undefined(flags_arg) {
        let (fs2, fse2) = js.to_string(it, flags_arg)
        if fse2 != ok { ret (js.undefv(), fse2) }
        flags = fs2
    }
    var proto = it.protos.regexp
    if it.has_new_target {
        let nto = js.as_object(it.new_target)
        let (p, pe) = js.proto_value_of(it, nto, it.protos.regexp)
        if pe != ok { ret (js.undefv(), pe) }
        proto = p
    }
    let (r, re) = regexp_create(it, proto, source, flags)
    ret (r, re)
}

fn this_regexp(it: *js.Interp, v: js.Value) -> (*Compiled, err) {
    if is_regexp_obj(v) { ret (compiled_of(js.as_object(v)), ok) }
    var none: *Compiled = zero
    ret (none, js.throw_type(it, "Method called on incompatible receiver"))
}

fn advance_index(s: str, units_len: usize, index: f64, unicode: bool) -> f64 {
    if !unicode { ret index + 1.0f64 }
    if index + 1.0f64 >= f64(units_len) { ret index + 1.0f64 }
    let (u, has) = js.unit_at(s, usize(index))
    if u >= 55296u32 && u <= 56319u32 {
        let (u2, has2) = js.unit_at(s, usize(index) + 1usize)
        if has2 && u2 >= 56320u32 && u2 <= 57343u32 { ret index + 2.0f64 }
    }
    ret index + 1.0f64
}

// RegExpBuiltinExec.
fn builtin_exec(it: *js.Interp, r: *js.Obj, s: str) -> (js.Value, err) {
    let c = compiled_of(r)
    let (li, lie) = js.get_prop(it, r, js.key_of("lastIndex"), js.obj_value(r))
    if lie != ok { ret (js.undefv(), lie) }
    let (lin, line) = js.to_length(it, li)
    if line != ok { ret (js.undefv(), line) }
    var last_index = lin
    let global = c.re.global
    let sticky = c.re.sticky
    if !global && !sticky { last_index = 0.0f64 }
    let units = to_units(it.a, s)
    if last_index > f64(units.len) {
        if global || sticky {
            let pe = js.put(it, js.obj_value(r), js.key_of("lastIndex"), js.num_value(0.0f64), true)
            if pe != ok { ret (js.undefv(), pe) }
        }
        ret (js.null_value(), ok)
    }
    let m = rx.exec(it.a, &c.re, units, usize(last_index), sticky)
    if m.aborted { ret (js.undefv(), js.throw_range(it, "regular expression is too complex")) }
    if !m.found {
        if global || sticky {
            let pe2 = js.put(it, js.obj_value(r), js.key_of("lastIndex"), js.num_value(0.0f64), true)
            if pe2 != ok { ret (js.undefv(), pe2) }
        }
        ret (js.null_value(), ok)
    }
    let start = usize(m.caps[0usize])
    let end = usize(m.caps[1usize])
    if global || sticky {
        let pe3 = js.put(it, js.obj_value(r), js.key_of("lastIndex"), js.num_value(f64(end)), true)
        if pe3 != ok { ret (js.undefv(), pe3) }
    }
    let arr = js.new_array(it)
    let e1 = js.set_named(it, arr, "index", js.num_value(f64(start)))
    let e2 = js.set_named(it, arr, "input", js.str_value(s))
    var g = 0usize
    let ngroups = usize(c.re.groups)
    while g <= ngroups {
        let cs = m.caps[g * 2usize]
        let ce = m.caps[g * 2usize + 1usize]
        if cs < 0i64 || ce < 0i64 {
            try js.array_push(it, arr, js.undefv())
        } else {
            try js.array_push(it, arr, js.str_value(from_units(it, units, usize(cs), usize(ce))))
        }
        g += 1usize
    }
    // Named groups.
    var groups_val = js.undefv()
    var has_names = false
    var n = 0usize
    while n < c.re.names.len {
        if c.re.names[n].len > 0usize { has_names = true }
        n += 1usize
    }
    if has_names {
        let go = js.new_obj(it, js.C_OBJECT, js.null_obj())
        var k = 0usize
        while k < c.re.names.len {
            if c.re.names[k].len > 0usize {
                let gv = arr.elems.items[k + 1usize]
                let (done, de) = js.define_own(it, go, js.key_of(c.re.names[k]), js.data_desc(gv, js.P_DEFAULT))
                if de != ok { ret (js.undefv(), de) }
            }
            k += 1usize
        }
        groups_val = js.obj_value(go)
    }
    let e3 = js.set_named(it, arr, "groups", groups_val)
    if c.re.has_indices {
        let ind = js.new_array(it)
        var g2 = 0usize
        while g2 <= ngroups {
            let cs2 = m.caps[g2 * 2usize]
            let ce2 = m.caps[g2 * 2usize + 1usize]
            if cs2 < 0i64 || ce2 < 0i64 {
                try js.array_push(it, ind, js.undefv())
            } else {
                let pair = js.array_from(it, js.two_args(it, js.num_value(f64(cs2)), js.num_value(f64(ce2))))
                try js.array_push(it, ind, js.obj_value(pair))
            }
            g2 += 1usize
        }
        var ig = js.undefv()
        if has_names {
            let igo = js.new_obj(it, js.C_OBJECT, js.null_obj())
            var k2 = 0usize
            while k2 < c.re.names.len {
                if c.re.names[k2].len > 0usize {
                    let iv = ind.elems.items[k2 + 1usize]
                    let (done2, de2) = js.define_own(it, igo, js.key_of(c.re.names[k2]), js.data_desc(iv, js.P_DEFAULT))
                    if de2 != ok { ret (js.undefv(), de2) }
                }
                k2 += 1usize
            }
            ig = js.obj_value(igo)
        }
        let e4 = js.set_named(it, ind, "groups", ig)
        let e5 = js.set_named(it, arr, "indices", js.obj_value(ind))
    }
    ret (js.obj_value(arr), ok)
}

fn regexp_exec_m(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !is_regexp_obj(this_val) { ret (js.undefv(), js.throw_type(it, "RegExp.prototype.exec called on incompatible receiver")) }
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (r, re) = builtin_exec(it, js.as_object(this_val), s)
    ret (r, re)
}

// RegExpExec: the object's own `exec` when callable, else the builtin.
fn regexp_exec(it: *js.Interp, r: js.Value, s: str) -> (js.Value, err) {
    let (ex, ee) = js.get_value(it, r, js.key_of("exec"))
    if ee != ok { ret (js.undefv(), ee) }
    if js.is_callable(ex) {
        let (res, re) = js.call_function(it, ex, r, js.one_arg(it, js.str_value(s)))
        if re != ok { ret (js.undefv(), re) }
        if !js.is_object(res) && !js.is_null(res) { ret (js.undefv(), js.throw_type(it, "exec result must be an object or null")) }
        ret (res, ok)
    }
    if !is_regexp_obj(r) { ret (js.undefv(), js.throw_type(it, "RegExp exec method called on incompatible receiver")) }
    let (b, be) = builtin_exec(it, js.as_object(r), s)
    ret (b, be)
}

fn regexp_test(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) { ret (js.undefv(), js.throw_type(it, "RegExp.prototype.test called on incompatible receiver")) }
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (r, re) = regexp_exec(it, this_val, s)
    if re != ok { ret (js.undefv(), re) }
    ret (js.bool_value(!js.is_null(r)), ok)
}

fn regexp_to_string(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) { ret (js.undefv(), js.throw_type(it, "RegExp.prototype.toString called on incompatible receiver")) }
    let (sv, se) = js.get_value(it, this_val, js.key_of("source"))
    if se != ok { ret (js.undefv(), se) }
    let (ss, sse) = js.to_string(it, sv)
    if sse != ok { ret (js.undefv(), sse) }
    let (fv, fe) = js.get_value(it, this_val, js.key_of("flags"))
    if fe != ok { ret (js.undefv(), fe) }
    let (fs, fse) = js.to_string(it, fv)
    if fse != ok { ret (js.undefv(), fse) }
    ret (js.str_value(js.str_concat(it, js.str_concat3(it, "/", ss, "/"), fs)), ok)
}

fn regexp_source(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if js.is_object(this_val) && js.as_object(this_val) == it.protos.regexp { ret (js.str_value("(?:)"), ok) }
    let (c, e) = this_regexp(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    ret (js.str_value(escape_source(it, c.source)), ok)
}

fn regexp_flags_getter(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) { ret (js.undefv(), js.throw_type(it, "RegExp.prototype.flags getter called on non-object")) }
    let o = js.as_object(this_val)
    let names = "dgimsuvy"
    let props = "hasIndices|global|ignoreCase|multiline|dotAll|unicode|unicodeSets|sticky|"
    var out = ""
    var start = 0usize
    var k = 0usize
    var idx = 0usize
    while idx < props.len && k < 8usize {
        if props[idx] == 124u8 {
            let (v, ve) = js.get_prop(it, o, js.key_of(props[start..idx]), this_val)
            if ve != ok { ret (js.undefv(), ve) }
            if js.to_boolean(v) { out = js.str_concat(it, out, names[k..k + 1usize]) }
            start = idx + 1usize
            k += 1usize
        }
        idx += 1usize
    }
    ret (js.str_value(out), ok)
}

fn flag_getter(it: *js.Interp, this_val: js.Value, which: u8) -> (js.Value, err) {
    if js.is_object(this_val) && js.as_object(this_val) == it.protos.regexp { ret (js.undefv(), ok) }
    let (c, e) = this_regexp(it, this_val)
    if e != ok { ret (js.undefv(), e) }
    var r = false
    if which == 0u8 { r = c.re.has_indices } else if which == 1u8 { r = c.re.global } else if which == 2u8 { r = c.re.ignore_case } else if which == 3u8 { r = c.re.multiline } else if which == 4u8 { r = c.re.dot_all } else if which == 5u8 { r = c.re.unicode && !c.re.unicode_sets } else if which == 6u8 { r = c.re.unicode_sets } else { r = c.re.sticky }
    ret (js.bool_value(r), ok)
}

fn fg_indices(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = flag_getter(it, this_val, 0u8)
    ret (r, e) }
fn fg_global(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = flag_getter(it, this_val, 1u8)
    ret (r, e) }
fn fg_ignore_case(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = flag_getter(it, this_val, 2u8)
    ret (r, e) }
fn fg_multiline(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = flag_getter(it, this_val, 3u8)
    ret (r, e) }
fn fg_dot_all(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = flag_getter(it, this_val, 4u8)
    ret (r, e) }
fn fg_unicode(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = flag_getter(it, this_val, 5u8)
    ret (r, e) }
fn fg_unicode_sets(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = flag_getter(it, this_val, 6u8)
    ret (r, e) }
fn fg_sticky(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = flag_getter(it, this_val, 7u8)
    ret (r, e) }

fn flags_of(it: *js.Interp, rx_val: js.Value) -> (str, err) {
    let (fv, fe) = js.get_value(it, rx_val, js.key_of("flags"))
    if fe != ok { ret ("", fe) }
    let (fs, fse) = js.to_string(it, fv)
    ret (fs, fse)
}

fn set_last_index(it: *js.Interp, r: js.Value, v: f64) -> err { ret js.put(it, r, js.key_of("lastIndex"), js.num_value(v), true) }

fn get_last_index(it: *js.Interp, r: js.Value) -> (f64, err) {
    let (v, ve) = js.get_value(it, r, js.key_of("lastIndex"))
    if ve != ok { ret (0.0f64, ve) }
    let (n, ne) = js.to_length(it, v)
    ret (n, ne)
}

// --- Symbol.match

fn regexp_match(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) { ret (js.undefv(), js.throw_type(it, "RegExp.prototype[Symbol.match] called on non-object")) }
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (flags, fe) = flags_of(it, this_val)
    if fe != ok { ret (js.undefv(), fe) }
    if !str.contains(flags, "g") {
        let (r, re) = regexp_exec(it, this_val, s)
        ret (r, re)
    }
    let full_unicode = str.contains(flags, "u") || str.contains(flags, "v")
    let sl = set_last_index(it, this_val, 0.0f64)
    if sl != ok { ret (js.undefv(), sl) }
    let out = js.new_array(it)
    var n = 0usize
    let len = js.units(s)
    while true {
        let (res, re2) = regexp_exec(it, this_val, s)
        if re2 != ok { ret (js.undefv(), re2) }
        if js.is_null(res) {
            if n == 0usize { ret (js.null_value(), ok) }
            ret (js.obj_value(out), ok)
        }
        let (m0, m0e) = js.get_value(it, res, js.key_of("0"))
        if m0e != ok { ret (js.undefv(), m0e) }
        let (ms, mse) = js.to_string(it, m0)
        if mse != ok { ret (js.undefv(), mse) }
        try js.array_push(it, out, js.str_value(ms))
        if ms.len == 0usize {
            let (li, lie) = get_last_index(it, this_val)
            if lie != ok { ret (js.undefv(), lie) }
            let sl2 = set_last_index(it, this_val, advance_index(s, len, li, full_unicode))
            if sl2 != ok { ret (js.undefv(), sl2) }
        }
        n += 1usize
    }
    ret (js.undefv(), ok)
}

// --- Symbol.matchAll

fn regexp_match_all(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) { ret (js.undefv(), js.throw_type(it, "RegExp.prototype[Symbol.matchAll] called on non-object")) }
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (cv, ce) = js.get_value(it, this_val, js.key_of("constructor"))
    if ce != ok { ret (js.undefv(), ce) }
    var ctor = js.obj_value(it.regexp_ctor)
    if js.is_object(cv) {
        let (sp, spe) = js.get_prop(it, js.as_object(cv), js.key_of_symbol(it.sym_species), cv)
        if spe != ok { ret (js.undefv(), spe) }
        if !js.is_nullish(sp) {
            if !js.is_constructor(sp) { ret (js.undefv(), js.throw_type(it, "species is not a constructor")) }
            ctor = sp
        }
    } else if !js.is_undefined(cv) {
        ret (js.undefv(), js.throw_type(it, "constructor is not an object"))
    }
    let (flags, fe) = flags_of(it, this_val)
    if fe != ok { ret (js.undefv(), fe) }
    let (matcher, me) = js.construct(it, ctor, js.two_args(it, this_val, js.str_value(flags)), ctor)
    if me != ok { ret (js.undefv(), me) }
    let (li, lie) = get_last_index(it, this_val)
    if lie != ok { ret (js.undefv(), lie) }
    let sl = set_last_index(it, matcher, li)
    if sl != ok { ret (js.undefv(), sl) }
    let iter = js.new_obj(it, js.C_ITERATOR, it.protos.regexp_string_iterator)
    iter.text = "regexp-string"
    iter.prim = matcher
    iter.aux = js.new_plain(it)
    let e1 = js.define_data(it, iter.aux, js.key_of("s"), js.str_value(s), js.P_DEFAULT)
    let e2 = js.define_data(it, iter.aux, js.key_of("g"), js.bool_value(str.contains(flags, "g")), js.P_DEFAULT)
    let e3 = js.define_data(it, iter.aux, js.key_of("u"), js.bool_value(str.contains(flags, "u") || str.contains(flags, "v")), js.P_DEFAULT)
    let e4 = js.define_data(it, iter.aux, js.key_of("done"), js.bool_value(false), js.P_DEFAULT)
    ret (js.obj_value(iter), ok)
}

fn iter_result(it: *js.Interp, v: js.Value, done: bool) -> js.Value {
    let r = js.new_plain(it)
    let e1 = js.set_named(it, r, "value", v)
    let e2 = js.set_named(it, r, "done", js.bool_value(done))
    ret js.obj_value(r)
}

fn regexp_string_iterator_next(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) || js.as_object(this_val).class != js.C_ITERATOR || !str.eq(js.as_object(this_val).text, "regexp-string") {
        ret (js.undefv(), js.throw_type(it, "next method called on incompatible receiver"))
    }
    let iter = js.as_object(this_val)
    let st = iter.aux
    let (dv, de) = js.get_prop(it, st, js.key_of("done"), js.obj_value(st))
    if de != ok { ret (js.undefv(), de) }
    if js.to_boolean(dv) { ret (iter_result(it, js.undefv(), true), ok) }
    let (sv, sve) = js.get_prop(it, st, js.key_of("s"), js.obj_value(st))
    if sve != ok { ret (js.undefv(), sve) }
    let s = js.value_str(sv)
    let (gv, gve) = js.get_prop(it, st, js.key_of("g"), js.obj_value(st))
    if gve != ok { ret (js.undefv(), gve) }
    let (uv, uve) = js.get_prop(it, st, js.key_of("u"), js.obj_value(st))
    if uve != ok { ret (js.undefv(), uve) }
    let global = js.to_boolean(gv)
    let (res, re) = regexp_exec(it, iter.prim, s)
    if re != ok { ret (js.undefv(), re) }
    if js.is_null(res) {
        let e1 = js.put(it, js.obj_value(st), js.key_of("done"), js.bool_value(true), true)
        ret (iter_result(it, js.undefv(), true), ok)
    }
    if !global {
        let e2 = js.put(it, js.obj_value(st), js.key_of("done"), js.bool_value(true), true)
        ret (iter_result(it, res, false), ok)
    }
    let (m0, m0e) = js.get_value(it, res, js.key_of("0"))
    if m0e != ok { ret (js.undefv(), m0e) }
    let (ms, mse) = js.to_string(it, m0)
    if mse != ok { ret (js.undefv(), mse) }
    if ms.len == 0usize {
        let (li, lie) = get_last_index(it, iter.prim)
        if lie != ok { ret (js.undefv(), lie) }
        let sl = set_last_index(it, iter.prim, advance_index(s, js.units(s), li, js.to_boolean(uv)))
        if sl != ok { ret (js.undefv(), sl) }
    }
    ret (iter_result(it, res, false), ok)
}

// --- Symbol.search

fn regexp_search(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) { ret (js.undefv(), js.throw_type(it, "RegExp.prototype[Symbol.search] called on non-object")) }
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (prev, pe) = js.get_value(it, this_val, js.key_of("lastIndex"))
    if pe != ok { ret (js.undefv(), pe) }
    if !js.same_value(prev, js.num_value(0.0f64)) {
        let sl = set_last_index(it, this_val, 0.0f64)
        if sl != ok { ret (js.undefv(), sl) }
    }
    let (res, re) = regexp_exec(it, this_val, s)
    if re != ok { ret (js.undefv(), re) }
    let (cur, ce) = js.get_value(it, this_val, js.key_of("lastIndex"))
    if ce != ok { ret (js.undefv(), ce) }
    if !js.same_value(cur, prev) {
        let sl2 = js.put(it, this_val, js.key_of("lastIndex"), prev, true)
        if sl2 != ok { ret (js.undefv(), sl2) }
    }
    if js.is_null(res) { ret (js.num_value(-1.0f64), ok) }
    let (idx, ie) = js.get_value(it, res, js.key_of("index"))
    ret (idx, ie)
}

// --- Symbol.replace

fn get_substitution(it: *js.Interp, matched: str, s: str, position: usize, captures: []const js.Value, named: js.Value, replacement: str) -> (str, err) {
    // Byte offsets of the position and match end within `s`.
    let pos_byte = js.byte_of_unit(s, position)
    let end_byte = js.byte_of_unit(s, position + js.units(matched))
    let (b, be) = str.builder(it.a, replacement.len + matched.len + 16usize)
    if be != ok { ret (replacement, be) }
    // Named captures are read before the builder starts (reads may allocate): collect lazily instead via a second pass.
    var out = b
    var i = 0usize
    var pending_named: [64]str = zero
    var pending_count = 0usize
    while i < replacement.len {
        let c = replacement[i]
        if c == 36u8 && i + 1usize < replacement.len {
            let d = replacement[i + 1usize]
            if d == 36u8 {
                let p1 = str.push_byte(&out, 36u8)
                i += 2usize
                continue
            }
            if d == 38u8 {
                let p2 = str.push(&out, matched)
                i += 2usize
                continue
            }
            if d == 96u8 {
                let p3 = str.push(&out, s[0usize..pos_byte])
                i += 2usize
                continue
            }
            if d == 39u8 {
                if end_byte < s.len { let p4 = str.push(&out, s[end_byte..]) }
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
                    if js.is_string(cv) { let p5 = str.push(&out, js.value_str(cv)) }
                    i += used
                    continue
                }
            }
            if d == 60u8 && !js.is_undefined(named) {
                var j = i + 2usize
                while j < replacement.len && replacement[j] != 62u8 { j += 1usize }
                if j < replacement.len {
                    // Reading the group may run user code (a getter) -> do it outside the builder: handled by pre-resolving below.
                    let name = replacement[i + 2usize..j]
                    if pending_count < 64usize {
                        pending_named[pending_count] = name
                        pending_count += 1usize
                    }
                    let marker = "\x01"
                    let p6 = str.push(&out, marker)
                    i = j + 1usize
                    continue
                }
            }
        }
        let p7 = str.push_byte(&out, c)
        i += 1usize
    }
    let result = str.done(&out)
    if pending_count == 0usize { ret (result, ok) }
    // Substitute the markers with the named capture values.
    var acc = ""
    var seg = 0usize
    var at = 0usize
    var used_named = 0usize
    while at < result.len {
        if result[at] == 1u8 && used_named < pending_count {
            acc = js.str_concat(it, acc, result[seg..at])
            let (cv2, cve) = js.get_value(it, named, js.key_of(pending_named[used_named]))
            if cve != ok { ret ("", cve) }
            if !js.is_undefined(cv2) {
                let (cs, cse) = js.to_string(it, cv2)
                if cse != ok { ret ("", cse) }
                acc = js.str_concat(it, acc, cs)
            }
            used_named += 1usize
            seg = at + 1usize
        }
        at += 1usize
    }
    acc = js.str_concat(it, acc, result[seg..])
    ret (acc, ok)
}

fn regexp_replace(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) { ret (js.undefv(), js.throw_type(it, "RegExp.prototype[Symbol.replace] called on non-object")) }
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let len = js.units(s)
    var replace_value = arg(args, 1usize)
    let functional = js.is_callable(replace_value)
    var rep_str = ""
    if !functional {
        let (rs, rse) = js.to_string(it, replace_value)
        if rse != ok { ret (js.undefv(), rse) }
        rep_str = rs
    }
    let (flags, fe) = flags_of(it, this_val)
    if fe != ok { ret (js.undefv(), fe) }
    let global = str.contains(flags, "g")
    let full_unicode = str.contains(flags, "u") || str.contains(flags, "v")
    if global {
        let sl = set_last_index(it, this_val, 0.0f64)
        if sl != ok { ret (js.undefv(), sl) }
    }
    let (rl, rle) = list.init[js.Value](it.a, 4usize)
    var results = rl
    while true {
        let (res, re) = regexp_exec(it, this_val, s)
        if re != ok { ret (js.undefv(), re) }
        if js.is_null(res) { break }
        try list.push[js.Value](&results, res)
        if !global { break }
        let (m0, m0e) = js.get_value(it, res, js.key_of("0"))
        if m0e != ok { ret (js.undefv(), m0e) }
        let (ms, mse) = js.to_string(it, m0)
        if mse != ok { ret (js.undefv(), mse) }
        if ms.len == 0usize {
            let (li, lie) = get_last_index(it, this_val)
            if lie != ok { ret (js.undefv(), lie) }
            let sl2 = set_last_index(it, this_val, advance_index(s, len, li, full_unicode))
            if sl2 != ok { ret (js.undefv(), sl2) }
        }
    }
    let (pl, ple) = list.init[str](it.a, results.len * 2usize + 2usize)
    var parts = pl
    var next_pos = 0usize
    var k = 0usize
    while k < results.len {
        let res2 = results.items[k]
        k += 1usize
        let (rlen, rle2) = js.length_of(it, js.as_object(res2))
        if rle2 != ok { ret (js.undefv(), rle2) }
        var ncap = rlen - 1.0f64
        if ncap < 0.0f64 { ncap = 0.0f64 }
        let (m1, m1e) = js.get_value(it, res2, js.key_of("0"))
        if m1e != ok { ret (js.undefv(), m1e) }
        let (matched, mse2) = js.to_string(it, m1)
        if mse2 != ok { ret (js.undefv(), mse2) }
        let (iv, ive) = js.get_value(it, res2, js.key_of("index"))
        if ive != ok { ret (js.undefv(), ive) }
        let (inum, ine) = js.to_number(it, iv)
        if ine != ok { ret (js.undefv(), ine) }
        var position = js.to_integer(inum)
        if position < 0.0f64 { position = 0.0f64 }
        if position > f64(len) { position = f64(len) }
        let (cl, cle) = list.init[js.Value](it.a, usize(ncap) + 1usize)
        var captures = cl
        var n = 1.0f64
        while n <= ncap {
            let (cv, cve) = js.get_value(it, res2, js.key_of(js.number_to_string(it.a, n)))
            if cve != ok { ret (js.undefv(), cve) }
            if !js.is_undefined(cv) {
                let (cs, cse) = js.to_string(it, cv)
                if cse != ok { ret (js.undefv(), cse) }
                try list.push[js.Value](&captures, js.str_value(cs))
            } else {
                try list.push[js.Value](&captures, cv)
            }
            n += 1.0f64
        }
        let (named, ne) = js.get_value(it, res2, js.key_of("groups"))
        if ne != ok { ret (js.undefv(), ne) }
        var replacement = ""
        if functional {
            let (al, ale) = list.init[js.Value](it.a, captures.len + 5usize)
            var cargs = al
            try list.push[js.Value](&cargs, js.str_value(matched))
            var q = 0usize
            while q < captures.len {
                try list.push[js.Value](&cargs, captures.items[q])
                q += 1usize
            }
            try list.push[js.Value](&cargs, js.num_value(position))
            try list.push[js.Value](&cargs, js.str_value(s))
            if !js.is_undefined(named) { try list.push[js.Value](&cargs, named) }
            let (rv, rve) = js.call_function(it, replace_value, js.undefv(), list.slice_const[js.Value](&cargs))
            if rve != ok { ret (js.undefv(), rve) }
            let (rs2, rse2) = js.to_string(it, rv)
            if rse2 != ok { ret (js.undefv(), rse2) }
            replacement = rs2
        } else {
            var named_obj = named
            if !js.is_undefined(named) {
                let (no, noe) = js.to_object(it, named)
                if noe != ok { ret (js.undefv(), noe) }
                named_obj = js.obj_value(no)
            }
            let (gs, gse) = get_substitution(it, matched, s, usize(position), list.slice_const[js.Value](&captures), named_obj, rep_str)
            if gse != ok { ret (js.undefv(), gse) }
            replacement = gs
        }
        if usize(position) >= next_pos {
            try list.push[str](&parts, js.substring_units(it.a, s, next_pos, usize(position)))
            try list.push[str](&parts, replacement)
            next_pos = usize(position) + js.units(matched)
        }
    }
    if next_pos < len { try list.push[str](&parts, js.substring_units(it.a, s, next_pos, len)) }
    var total = 0usize
    var q2 = 0usize
    while q2 < parts.len {
        total += parts.items[q2].len
        q2 += 1usize
    }
    let (b, be) = str.builder(it.a, total + 1usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var out = b
    var w = 0usize
    while w < parts.len {
        let pe = str.push(&out, parts.items[w])
        w += 1usize
    }
    ret (js.str_value(str.done(&out)), ok)
}

// --- Symbol.split

fn regexp_split(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !js.is_object(this_val) { ret (js.undefv(), js.throw_type(it, "RegExp.prototype[Symbol.split] called on non-object")) }
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (cv, ce) = js.get_value(it, this_val, js.key_of("constructor"))
    if ce != ok { ret (js.undefv(), ce) }
    var ctor = js.obj_value(it.regexp_ctor)
    if js.is_object(cv) {
        let (sp, spe) = js.get_prop(it, js.as_object(cv), js.key_of_symbol(it.sym_species), cv)
        if spe != ok { ret (js.undefv(), spe) }
        if !js.is_nullish(sp) {
            if !js.is_constructor(sp) { ret (js.undefv(), js.throw_type(it, "species is not a constructor")) }
            ctor = sp
        }
    } else if !js.is_undefined(cv) {
        ret (js.undefv(), js.throw_type(it, "constructor is not an object"))
    }
    let (flags, fe) = flags_of(it, this_val)
    if fe != ok { ret (js.undefv(), fe) }
    let unicode_matching = str.contains(flags, "u") || str.contains(flags, "v")
    var new_flags = flags
    if !str.contains(flags, "y") { new_flags = js.str_concat(it, flags, "y") }
    let (splitter, me) = js.construct(it, ctor, js.two_args(it, this_val, js.str_value(new_flags)), ctor)
    if me != ok { ret (js.undefv(), me) }
    let out = js.new_array(it)
    var lim = 4294967295u32
    if !js.is_undefined(arg(args, 1usize)) {
        let (l, le) = js.to_uint32(it, args[1usize])
        if le != ok { ret (js.undefv(), le) }
        lim = l
    }
    if lim == 0u32 { ret (js.obj_value(out), ok) }
    let size = js.units(s)
    if size == 0usize {
        let (z, ze) = regexp_exec(it, splitter, s)
        if ze != ok { ret (js.undefv(), ze) }
        if js.is_null(z) { try js.array_push(it, out, js.str_value(s)) }
        ret (js.obj_value(out), ok)
    }
    var p = 0usize
    var q = 0usize
    while q < size {
        let sl = set_last_index(it, splitter, f64(q))
        if sl != ok { ret (js.undefv(), sl) }
        let (z2, ze2) = regexp_exec(it, splitter, s)
        if ze2 != ok { ret (js.undefv(), ze2) }
        if js.is_null(z2) {
            q = usize(advance_index(s, size, f64(q), unicode_matching))
            continue
        }
        let (le2, lee) = get_last_index(it, splitter)
        if lee != ok { ret (js.undefv(), lee) }
        var e = usize(le2)
        if e > size { e = size }
        if e == p {
            q = usize(advance_index(s, size, f64(q), unicode_matching))
            continue
        }
        try js.array_push(it, out, js.str_value(js.substring_units(it.a, s, p, q)))
        if u32(out.elems.len) == lim { ret (js.obj_value(out), ok) }
        p = e
        let (nc, nce) = js.length_of(it, js.as_object(z2))
        if nce != ok { ret (js.undefv(), nce) }
        var ncap = nc - 1.0f64
        if ncap < 0.0f64 { ncap = 0.0f64 }
        var i = 1.0f64
        while i <= ncap {
            let (cap, cape) = js.get_value(it, z2, js.key_of(js.number_to_string(it.a, i)))
            if cape != ok { ret (js.undefv(), cape) }
            try js.array_push(it, out, cap)
            if u32(out.elems.len) == lim { ret (js.obj_value(out), ok) }
            i += 1.0f64
        }
        q = p
    }
    try js.array_push(it, out, js.str_value(js.substring_units(it.a, s, p, size)))
    ret (js.obj_value(out), ok)
}

fn regexp_compile(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if !is_regexp_obj(this_val) { ret (js.undefv(), js.throw_type(it, "RegExp.prototype.compile called on incompatible receiver")) }
    let pattern = arg(args, 0usize)
    let flags_arg = arg(args, 1usize)
    var source = ""
    var flags = ""
    if is_regexp_obj(pattern) {
        if !js.is_undefined(flags_arg) { ret (js.undefv(), js.throw_type(it, "flags must be undefined when pattern is a RegExp")) }
        let c = compiled_of(js.as_object(pattern))
        source = c.source
        flags = c.flags
    } else {
        if !js.is_undefined(pattern) {
            let (ps, pse) = js.to_string(it, pattern)
            if pse != ok { ret (js.undefv(), pse) }
            source = ps
        }
        if !js.is_undefined(flags_arg) {
            let (fs, fse) = js.to_string(it, flags_arg)
            if fse != ok { ret (js.undefv(), fse) }
            flags = fs
        }
    }
    let units = to_units(it.a, source)
    let (re, msg, ce) = rx.compile(it.a, units, flags)
    if ce != ok { ret (js.undefv(), js.throw_syntax(it, js.str_concat(it, "Invalid regular expression: ", msg))) }
    let c2 = compiled_of(js.as_object(this_val))
    c2.re = re
    c2.source = source
    c2.flags = flags
    let sl = js.put(it, this_val, js.key_of("lastIndex"), js.num_value(0.0f64), true)
    if sl != ok { ret (js.undefv(), sl) }
    ret (this_val, ok)
}

fn species_self(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { ret (this_val, ok) }

fn install_regexp(it: *js.Interp) {
    let proto = it.protos.regexp
    let ctor = js.make_native(it, "RegExp", 2u32, regexp_ctor)
    ctor.ctor_kind = js.K_BASE
    let e1 = js.define_data(it, ctor, js.key_of("prototype"), js.obj_value(proto), 0u8)
    let e2 = js.define_data(it, proto, js.key_of("constructor"), js.obj_value(ctor), js.P_HIDDEN)
    let e3 = js.define_data(it, it.global, js.key_of("RegExp"), js.obj_value(ctor), js.P_HIDDEN)
    it.regexp_ctor = ctor
    it.last = ctor
    let sg = js.make_native(it, "get [Symbol.species]", 0u32, species_self)
    let e4 = js.define_accessor_raw(it, it.last, js.key_of_symbol(it.sym_species), sg, js.null_obj(), js.P_CONFIGURABLE)
    js.add_method(it, it.protos.regexp, "exec", 1u32, regexp_exec_m)
    js.add_method(it, it.protos.regexp, "test", 1u32, regexp_test)
    js.add_method(it, it.protos.regexp, "toString", 0u32, regexp_to_string)
    js.add_method(it, it.protos.regexp, "compile", 2u32, regexp_compile)
    js.add_getter(it, it.protos.regexp, "source", regexp_source)
    js.add_getter(it, it.protos.regexp, "flags", regexp_flags_getter)
    js.add_getter(it, it.protos.regexp, "hasIndices", fg_indices)
    js.add_getter(it, it.protos.regexp, "global", fg_global)
    js.add_getter(it, it.protos.regexp, "ignoreCase", fg_ignore_case)
    js.add_getter(it, it.protos.regexp, "multiline", fg_multiline)
    js.add_getter(it, it.protos.regexp, "dotAll", fg_dot_all)
    js.add_getter(it, it.protos.regexp, "unicode", fg_unicode)
    js.add_getter(it, it.protos.regexp, "unicodeSets", fg_unicode_sets)
    js.add_getter(it, it.protos.regexp, "sticky", fg_sticky)
    let m = js.make_native(it, "[Symbol.match]", 1u32, regexp_match)
    let e5 = js.define_data(it, it.protos.regexp, js.key_of_symbol(it.sym_match), js.obj_value(m), js.P_HIDDEN)
    let ma = js.make_native(it, "[Symbol.matchAll]", 1u32, regexp_match_all)
    let e6 = js.define_data(it, it.protos.regexp, js.key_of_symbol(it.sym_match_all), js.obj_value(ma), js.P_HIDDEN)
    let rp = js.make_native(it, "[Symbol.replace]", 2u32, regexp_replace)
    let e7 = js.define_data(it, it.protos.regexp, js.key_of_symbol(it.sym_replace), js.obj_value(rp), js.P_HIDDEN)
    let sr = js.make_native(it, "[Symbol.search]", 1u32, regexp_search)
    let e8 = js.define_data(it, it.protos.regexp, js.key_of_symbol(it.sym_search), js.obj_value(sr), js.P_HIDDEN)
    let sp = js.make_native(it, "[Symbol.split]", 2u32, regexp_split)
    let e9 = js.define_data(it, it.protos.regexp, js.key_of_symbol(it.sym_split), js.obj_value(sp), js.P_HIDDEN)
    it.protos.regexp_string_iterator = js.new_obj(it, js.C_OBJECT, it.protos.iterator)
    js.add_method(it, it.protos.regexp_string_iterator, "next", 0u32, regexp_string_iterator_next)
    let e10 = js.define_data(it, it.protos.regexp_string_iterator, js.key_of_symbol(it.sym_to_string_tag), js.str_value("RegExp String Iterator"), js.P_CONFIGURABLE)
}
