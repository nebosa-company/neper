// Smaller builtins (browser tracker 5.7): the URI functions, `escape`/`unescape`, AggregateError, the copying Array methods
// (`toSorted`, `toReversed`, `toSpliced`, `with`), `Object.groupBy`, and the Annex B String HTML methods.

use e.data.list as list
use e.js.b_array as barr
use e.js.interp as js
use e.mem
use e.str

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

// --- URI

fn hex_digit(v: u8) -> u8 {
    if v < 10u8 { ret 48u8 + v }
    ret 55u8 + v
}

fn in_set(c: u8, set: str) -> bool {
    var i = 0usize
    while i < set.len {
        if set[i] == c { ret true }
        i += 1usize
    }
    ret false
}

fn is_alnum(c: u8) -> bool { ret (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) }

fn uri_encode(it: *js.Interp, s: str, unescaped_extra: str) -> (str, err) {
    let (b, be) = str.builder(it.a, s.len * 3usize + 4usize)
    if be != ok { ret ("", js.throw_range(it, "out of memory")) }
    var out = b
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if is_alnum(c) || in_set(c, "-_.!~*'()") || in_set(c, unescaped_extra) {
            let pe = str.push_byte(&out, c)
            i += 1usize
            continue
        }
        // A character is percent-encoded byte by byte over its UTF-8 form.
        var n = 1usize
        if c >= 192u8 { n = 2usize }
        if c >= 224u8 { n = 3usize }
        if c >= 240u8 { n = 4usize }
        var k = 0usize
        while k < n && i + k < s.len {
            let bb = s[i + k]
            let p1 = str.push_byte(&out, 37u8)
            let p2 = str.push_byte(&out, hex_digit(bb >> 4u8))
            let p3 = str.push_byte(&out, hex_digit(bb & 15u8))
            k += 1usize
        }
        i += n
    }
    ret (str.done(&out), ok)
}

fn encode_uri(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (r, re) = uri_encode(it, s, ";/?:@&=+$,#")
    if re != ok { ret (js.undefv(), re) }
    ret (js.str_value(r), ok)
}

fn encode_uri_component(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (r, re) = uri_encode(it, s, "")
    if re != ok { ret (js.undefv(), re) }
    ret (js.str_value(r), ok)
}

fn hex_val(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret i32(c) - 48i32 }
    if c >= 97u8 && c <= 102u8 { ret i32(c) - 87i32 }
    if c >= 65u8 && c <= 70u8 { ret i32(c) - 55i32 }
    ret -1i32
}

fn uri_decode(it: *js.Interp, s: str, reserved: str) -> (str, err) {
    let (b, be) = str.builder(it.a, s.len + 4usize)
    if be != ok { ret ("", js.throw_range(it, "out of memory")) }
    var out = b
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c != 37u8 {
            let pe = str.push_byte(&out, c)
            i += 1usize
            continue
        }
        let start = i
        if i + 2usize >= s.len + 0usize && i + 2usize > s.len - 1usize { ret ("", js.throw_value(it, js.make_error(it, it.protos.uri_error, "URI malformed"))) }
        let h1 = hex_val(s[i + 1usize])
        let h2 = hex_val(s[i + 2usize])
        if h1 < 0i32 || h2 < 0i32 { ret ("", js.throw_value(it, js.make_error(it, it.protos.uri_error, "URI malformed"))) }
        let byte = u8(h1 * 16i32 + h2)
        i += 3usize
        if byte < 128u8 {
            if in_set(byte, reserved) {
                let p1 = str.push(&out, s[start..i])
            } else {
                let p2 = str.push_byte(&out, byte)
            }
            continue
        }
        // A multi-byte UTF-8 sequence spread over %XX escapes.
        var n = 0usize
        if byte >= 192u8 && byte < 224u8 { n = 2usize } else if byte >= 224u8 && byte < 240u8 { n = 3usize } else if byte >= 240u8 && byte < 248u8 { n = 4usize } else { ret ("", js.throw_value(it, js.make_error(it, it.protos.uri_error, "URI malformed"))) }
        var bytes: [4]u8 = zero
        bytes[0usize] = byte
        var k = 1usize
        while k < n {
            if i + 2usize >= s.len + 0usize && i + 2usize > s.len - 1usize { ret ("", js.throw_value(it, js.make_error(it, it.protos.uri_error, "URI malformed"))) }
            if s[i] != 37u8 { ret ("", js.throw_value(it, js.make_error(it, it.protos.uri_error, "URI malformed"))) }
            let g1 = hex_val(s[i + 1usize])
            let g2 = hex_val(s[i + 2usize])
            if g1 < 0i32 || g2 < 0i32 { ret ("", js.throw_value(it, js.make_error(it, it.protos.uri_error, "URI malformed"))) }
            let cont = u8(g1 * 16i32 + g2)
            if (cont & 192u8) != 128u8 { ret ("", js.throw_value(it, js.make_error(it, it.protos.uri_error, "URI malformed"))) }
            bytes[k] = cont
            k += 1usize
            i += 3usize
        }
        // Reject overlong forms, surrogates and values past U+10FFFF.
        var cp = 0u32
        if n == 2usize { cp = ((u32(bytes[0usize]) & 31u32) << 6u32) | (u32(bytes[1usize]) & 63u32) } else if n == 3usize { cp = ((u32(bytes[0usize]) & 15u32) << 12u32) | ((u32(bytes[1usize]) & 63u32) << 6u32) | (u32(bytes[2usize]) & 63u32) } else { cp = ((u32(bytes[0usize]) & 7u32) << 18u32) | ((u32(bytes[1usize]) & 63u32) << 12u32) | ((u32(bytes[2usize]) & 63u32) << 6u32) | (u32(bytes[3usize]) & 63u32) }
        if (n == 2usize && cp < 128u32) || (n == 3usize && cp < 2048u32) || (n == 4usize && cp < 65536u32) || (cp >= 55296u32 && cp <= 57343u32) || cp > 1114111u32 { ret ("", js.throw_value(it, js.make_error(it, it.protos.uri_error, "URI malformed"))) }
        js.put_cp(&out, cp)
    }
    ret (str.done(&out), ok)
}

fn decode_uri(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (r, re) = uri_decode(it, s, ";/?:@&=+$,#")
    if re != ok { ret (js.undefv(), re) }
    ret (js.str_value(r), ok)
}

fn decode_uri_component(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (r, re) = uri_decode(it, s, "")
    if re != ok { ret (js.undefv(), re) }
    ret (js.str_value(r), ok)
}

// escape / unescape over UTF-16 units.
fn js_escape(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let n = js.units(s)
    let (b, be) = str.builder(it.a, n * 6usize + 4usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var out = b
    var us: [256]u32 = zero
    var count = 0usize
    var i = 0usize
    while i < n && count < 256usize {
        let (u, has) = js.unit_at(s, i)
        us[count] = u
        count += 1usize
        i += 1usize
    }
    var k = 0usize
    while k < count {
        let u2 = us[k]
        if u2 < 128u32 && (is_alnum(u8(u2)) || in_set(u8(u2), "@*_+-./")) {
            let p0 = str.push_byte(&out, u8(u2))
        } else if u2 < 256u32 {
            let p1 = str.push_byte(&out, 37u8)
            let p2 = str.push_byte(&out, hex_digit(u8(u2 >> 4u32)))
            let p3 = str.push_byte(&out, hex_digit(u8(u2 & 15u32)))
        } else {
            let p4 = str.push(&out, "%u")
            let p5 = str.push_byte(&out, hex_digit(u8((u2 >> 12u32) & 15u32)))
            let p6 = str.push_byte(&out, hex_digit(u8((u2 >> 8u32) & 15u32)))
            let p7 = str.push_byte(&out, hex_digit(u8((u2 >> 4u32) & 15u32)))
            let p8 = str.push_byte(&out, hex_digit(u8(u2 & 15u32)))
        }
        k += 1usize
    }
    ret (js.str_value(str.done(&out)), ok)
}

fn js_unescape(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (s, se) = js.to_string(it, arg(args, 0usize))
    if se != ok { ret (js.undefv(), se) }
    let (b, be) = str.builder(it.a, s.len + 4usize)
    if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    var out = b
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 37u8 {
            if i + 5usize < s.len + 0usize && s[i + 1usize] == 117u8 {
                let a1 = hex_val(s[i + 2usize])
                let a2 = hex_val(s[i + 3usize])
                let a3 = hex_val(s[i + 4usize])
                let a4 = hex_val(s[i + 5usize])
                if a1 >= 0i32 && a2 >= 0i32 && a3 >= 0i32 && a4 >= 0i32 {
                    js.put_cp(&out, u32(((a1 * 16i32 + a2) * 16i32 + a3) * 16i32 + a4))
                    i += 6usize
                    continue
                }
            }
            if i + 2usize < s.len {
                let h1 = hex_val(s[i + 1usize])
                let h2 = hex_val(s[i + 2usize])
                if h1 >= 0i32 && h2 >= 0i32 {
                    js.put_cp(&out, u32(h1 * 16i32 + h2))
                    i += 3usize
                    continue
                }
            }
        }
        let pe = str.push_byte(&out, c)
        i += 1usize
    }
    ret (js.str_value(str.done(&out)), ok)
}

// --- AggregateError

fn aggregate_error_ctor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    var proto = it.protos.aggregate_error
    if it.has_new_target {
        let nto = js.as_object(it.new_target)
        let (p, pe) = js.proto_value_of(it, nto, it.protos.aggregate_error)
        if pe != ok { ret (js.undefv(), pe) }
        proto = p
    }
    let o = js.new_obj(it, js.C_ERROR, proto)
    let msg = arg(args, 1usize)
    if !js.is_undefined(msg) {
        let (s, se) = js.to_string(it, msg)
        if se != ok { ret (js.undefv(), se) }
        let e = js.define_data(it, o, js.key_of("message"), js.str_value(s), js.P_HIDDEN)
    }
    let opts = arg(args, 2usize)
    if js.is_object(opts) && js.has_property(it, js.as_object(opts), js.key_of("cause")) {
        let (cv, ce) = js.get_prop(it, js.as_object(opts), js.key_of("cause"), opts)
        if ce != ok { ret (js.undefv(), ce) }
        let e2 = js.define_data(it, o, js.key_of("cause"), cv, js.P_HIDDEN)
    }
    let (vals, ie) = js.iterate_to_list(it, arg(args, 0usize))
    if ie != ok { ret (js.undefv(), ie) }
    let arr = js.array_from(it, list.slice_const[js.Value](&vals))
    let e3 = js.define_data(it, o, js.key_of("errors"), js.obj_value(arr), js.P_HIDDEN)
    ret (js.obj_value(o), ok)
}

// --- copying Array methods

fn array_to_reversed(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = js.length_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    if len > 4294967295.0f64 { ret (js.undefv(), js.throw_range(it, "Invalid array length")) }
    let out = js.new_array(it)
    var k = 0.0f64
    while k < len {
        try js.tick(it)
        let (v, ve) = js.get_index(it, o, len - 1.0f64 - k)
        if ve != ok { ret (js.undefv(), ve) }
        try js.array_push(it, out, v)
        k += 1.0f64
    }
    ret (js.obj_value(out), ok)
}

fn array_to_sorted(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let cmp = arg(args, 0usize)
    if !js.is_undefined(cmp) && !js.is_callable(cmp) { ret (js.undefv(), js.throw_type(it, "The comparison function must be either a function or undefined")) }
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = js.length_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    if len > 4294967295.0f64 { ret (js.undefv(), js.throw_range(it, "Invalid array length")) }
    let out = js.new_array(it)
    var k = 0.0f64
    while k < len {
        try js.tick(it)
        let (v, ve) = js.get_index(it, o, k)
        if ve != ok { ret (js.undefv(), ve) }
        try js.array_push(it, out, v)
        k += 1.0f64
    }
    let (r, re) = barr.array_sort(it, js.obj_value(out), args)
    ret (r, re)
}

fn array_with(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = js.length_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    let (n, ne) = js.to_number(it, arg(args, 0usize))
    if ne != ok { ret (js.undefv(), ne) }
    var rel = js.to_integer(n)
    if rel < 0.0f64 { rel = len + rel }
    if rel < 0.0f64 || rel >= len { ret (js.undefv(), js.throw_range(it, "Invalid index")) }
    if len > 4294967295.0f64 { ret (js.undefv(), js.throw_range(it, "Invalid array length")) }
    let out = js.new_array(it)
    var k = 0.0f64
    while k < len {
        try js.tick(it)
        var v = js.undefv()
        if k == rel {
            v = arg(args, 1usize)
        } else {
            let (gv, gve) = js.get_index(it, o, k)
            if gve != ok { ret (js.undefv(), gve) }
            v = gv
        }
        try js.array_push(it, out, v)
        k += 1.0f64
    }
    ret (js.obj_value(out), ok)
}

fn array_to_spliced(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (o, oe) = js.to_object(it, this_val)
    if oe != ok { ret (js.undefv(), oe) }
    let (len, le) = js.length_of(it, o)
    if le != ok { ret (js.undefv(), le) }
    let (start, se) = barr.rel_index(it, arg(args, 0usize), len, 0.0f64)
    if se != ok { ret (js.undefv(), se) }
    var skip = 0.0f64
    if args.len == 1usize {
        skip = len - start
    } else if args.len > 1usize {
        let (dn, dne) = js.to_number(it, args[1usize])
        if dne != ok { ret (js.undefv(), dne) }
        skip = js.to_integer(dn)
        if skip < 0.0f64 { skip = 0.0f64 }
        if skip > len - start { skip = len - start }
    }
    var items: []const js.Value = js.zero_args()
    if args.len > 2usize { items = args[2usize..] }
    let new_len = len + f64(items.len) - skip
    if new_len > 9007199254740991.0f64 { ret (js.undefv(), js.throw_type(it, "Invalid array length")) }
    if new_len > 4294967295.0f64 { ret (js.undefv(), js.throw_range(it, "Invalid array length")) }
    let out = js.new_array(it)
    var i = 0.0f64
    while i < start {
        try js.tick(it)
        let (v, ve) = js.get_index(it, o, i)
        if ve != ok { ret (js.undefv(), ve) }
        try js.array_push(it, out, v)
        i += 1.0f64
    }
    var j = 0usize
    while j < items.len {
        try js.array_push(it, out, items[j])
        j += 1usize
    }
    var r = start + skip
    while r < len {
        try js.tick(it)
        let (v2, ve2) = js.get_index(it, o, r)
        if ve2 != ok { ret (js.undefv(), ve2) }
        try js.array_push(it, out, v2)
        r += 1.0f64
    }
    ret (js.obj_value(out), ok)
}

// --- Object.groupBy

fn object_group_by(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let cb = arg(args, 1usize)
    if !js.is_callable(cb) { ret (js.undefv(), js.throw_type(it, "callback is not a function")) }
    let src = arg(args, 0usize)
    if js.is_nullish(src) { ret (js.undefv(), js.throw_type(it, "Object.groupBy called on null or undefined")) }
    let out = js.new_obj(it, js.C_OBJECT, js.null_obj())
    let (items, ie) = js.iterate_to_list(it, src)
    if ie != ok { ret (js.undefv(), ie) }
    var i = 0usize
    while i < items.len {
        let (kv, ke) = js.call_function(it, cb, js.undefv(), js.two_args(it, items.items[i], js.num_value(f64(i))))
        if ke != ok { ret (js.undefv(), ke) }
        let (key, pke) = js.to_property_key(it, kv)
        if pke != ok { ret (js.undefv(), pke) }
        let (p, found) = js.get_own(it, out, key)
        if found {
            let ga = js.as_object(p.value)
            try js.array_push(it, ga, items.items[i])
        } else {
            let ga2 = js.new_array(it)
            try js.array_push(it, ga2, items.items[i])
            let (done, de) = js.define_own(it, out, key, js.data_desc(js.obj_value(ga2), js.P_DEFAULT))
            if de != ok { ret (js.undefv(), de) }
        }
        i += 1usize
    }
    ret (js.obj_value(out), ok)
}

// --- Annex B String HTML methods

fn html_method(it: *js.Interp, this_val: js.Value, args: []const js.Value, tag: str, attr: str) -> (js.Value, err) {
    if js.is_nullish(this_val) { ret (js.undefv(), js.throw_type(it, "String.prototype method called on null or undefined")) }
    let (s, se) = js.to_string(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    var open = js.str_concat(it, "<", tag)
    if attr.len > 0usize {
        let (v, ve) = js.to_string(it, arg(args, 0usize))
        if ve != ok { ret (js.undefv(), ve) }
        // Quotes in the value become &quot;.
        let (escaped, ee) = str.replace(it.a, v, "\"", "&quot;")
        if ee != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
        open = js.str_concat(it, js.str_concat(it, js.str_concat(it, open, " "), attr), js.str_concat3(it, "=\"", escaped, "\""))
    }
    ret (js.str_value(js.str_concat(it, js.str_concat(it, js.str_concat(it, open, ">"), s), js.str_concat3(it, "</", tag, ">"))), ok)
}

fn h_anchor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = html_method(it, this_val, args, "a", "name")
    ret (r, e) }
fn h_big(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = html_method(it, this_val, args, "big", "")
    ret (r, e) }
fn h_blink(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = html_method(it, this_val, args, "blink", "")
    ret (r, e) }
fn h_bold(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = html_method(it, this_val, args, "b", "")
    ret (r, e) }
fn h_fixed(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = html_method(it, this_val, args, "tt", "")
    ret (r, e) }
fn h_fontcolor(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = html_method(it, this_val, args, "font", "color")
    ret (r, e) }
fn h_fontsize(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = html_method(it, this_val, args, "font", "size")
    ret (r, e) }
fn h_italics(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = html_method(it, this_val, args, "i", "")
    ret (r, e) }
fn h_link(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = html_method(it, this_val, args, "a", "href")
    ret (r, e) }
fn h_small(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = html_method(it, this_val, args, "small", "")
    ret (r, e) }
fn h_strike(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = html_method(it, this_val, args, "strike", "")
    ret (r, e) }
fn h_sub(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = html_method(it, this_val, args, "sub", "")
    ret (r, e) }
fn h_sup(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) { let (r, e) = html_method(it, this_val, args, "sup", "")
    ret (r, e) }

fn string_is_well_formed(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if js.is_nullish(this_val) { ret (js.undefv(), js.throw_type(it, "String.prototype.isWellFormed called on null or undefined")) }
    let (s, se) = js.to_string(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    ret (js.bool_value(true), ok)
}

fn string_to_well_formed(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    if js.is_nullish(this_val) { ret (js.undefv(), js.throw_type(it, "String.prototype.toWellFormed called on null or undefined")) }
    let (s, se) = js.to_string(it, this_val)
    if se != ok { ret (js.undefv(), se) }
    ret (js.str_value(s), ok)
}

fn install_misc(it: *js.Interp) {
    js.add_method(it, it.global, "encodeURI", 1u32, encode_uri)
    js.add_method(it, it.global, "encodeURIComponent", 1u32, encode_uri_component)
    js.add_method(it, it.global, "decodeURI", 1u32, decode_uri)
    js.add_method(it, it.global, "decodeURIComponent", 1u32, decode_uri_component)
    js.add_method(it, it.global, "escape", 1u32, js_escape)
    js.add_method(it, it.global, "unescape", 1u32, js_unescape)
    // AggregateError.
    it.protos.aggregate_error = js.new_obj(it, js.C_OBJECT, it.protos.error_proto)
    let ae = js.make_native(it, "AggregateError", 2u32, aggregate_error_ctor)
    ae.ctor_kind = js.K_BASE
    let (errc, errce) = js.get_prop(it, it.global, js.key_of("Error"), js.obj_value(it.global))
    if errce == ok && js.is_object(errc) {
        ae.proto = js.as_object(errc)
        ae.has_proto = true
    }
    let e1 = js.define_data(it, ae, js.key_of("prototype"), js.obj_value(it.protos.aggregate_error), 0u8)
    let e2 = js.define_data(it, it.protos.aggregate_error, js.key_of("constructor"), js.obj_value(ae), js.P_HIDDEN)
    let e3 = js.define_data(it, it.protos.aggregate_error, js.key_of("name"), js.str_value("AggregateError"), js.P_HIDDEN)
    let e4 = js.define_data(it, it.protos.aggregate_error, js.key_of("message"), js.str_value(""), js.P_HIDDEN)
    let e5 = js.define_data(it, it.global, js.key_of("AggregateError"), js.obj_value(ae), js.P_HIDDEN)
    // Copying array methods.
    js.add_method(it, it.protos.array, "toReversed", 0u32, array_to_reversed)
    js.add_method(it, it.protos.array, "toSorted", 1u32, array_to_sorted)
    js.add_method(it, it.protos.array, "toSpliced", 2u32, array_to_spliced)
    js.add_method(it, it.protos.array, "with", 2u32, array_with)
    // Object.groupBy.
    let (oc, oce) = js.get_prop(it, it.global, js.key_of("Object"), js.obj_value(it.global))
    if oce == ok && js.is_object(oc) { js.add_method(it, js.as_object(oc), "groupBy", 2u32, object_group_by) }
    // String HTML methods and well-formedness.
    js.add_method(it, it.protos.string, "anchor", 1u32, h_anchor)
    js.add_method(it, it.protos.string, "big", 0u32, h_big)
    js.add_method(it, it.protos.string, "blink", 0u32, h_blink)
    js.add_method(it, it.protos.string, "bold", 0u32, h_bold)
    js.add_method(it, it.protos.string, "fixed", 0u32, h_fixed)
    js.add_method(it, it.protos.string, "fontcolor", 1u32, h_fontcolor)
    js.add_method(it, it.protos.string, "fontsize", 1u32, h_fontsize)
    js.add_method(it, it.protos.string, "italics", 0u32, h_italics)
    js.add_method(it, it.protos.string, "link", 1u32, h_link)
    js.add_method(it, it.protos.string, "small", 0u32, h_small)
    js.add_method(it, it.protos.string, "strike", 0u32, h_strike)
    js.add_method(it, it.protos.string, "sub", 0u32, h_sub)
    js.add_method(it, it.protos.string, "sup", 0u32, h_sup)
    js.add_method(it, it.protos.string, "isWellFormed", 0u32, string_is_well_formed)
    js.add_method(it, it.protos.string, "toWellFormed", 0u32, string_to_well_formed)
}
