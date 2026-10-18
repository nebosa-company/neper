// JSON (browser tracker 5.7): `JSON.parse` with a reviver and `JSON.stringify` with replacer, indent and `toJSON`.

use e.data.list as list
use e.js.interp as js
use e.mem
use e.str

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

// --- parse

type P = struct { s: str, i: usize, want: bool, recs: list.List[Rec], last: usize }

// A parse record (for the reviver's `context`): the parsed value, its source text when it is a primitive, and its children.
type Rec = struct { value: js.Value, source: str, kids: list.List[usize], keys: list.List[str] }

const NO_REC: usize = 18446744073709551615usize

fn add_rec(it: *js.Interp, p: *P, v: js.Value, source: str, kids: list.List[usize], keys: list.List[str]) -> err {
    try list.push[Rec](&p.recs, Rec { value: v, source: source, kids: kids, keys: keys })
    p.last = p.recs.len - 1usize
    ret ok
}

fn skip_ws(p: *P) {
    while p.i < p.s.len && (p.s[p.i] == 32u8 || p.s[p.i] == 9u8 || p.s[p.i] == 10u8 || p.s[p.i] == 13u8) { p.i += 1usize }
}

fn syntax(it: *js.Interp, p: *P) -> err {
    if p.i >= p.s.len { ret js.throw_syntax(it, "Unexpected end of JSON input") }
    ret js.throw_syntax(it, js.str_concat(it, "Unexpected token in JSON at position ", js.number_to_string(it.a, f64(p.i))))
}

fn parse_string(it: *js.Interp, p: *P) -> (str, err) {
    p.i += 1usize
    var start = p.i
    var plain = true
    while p.i < p.s.len && p.s[p.i] != 34u8 {
        if p.s[p.i] < 32u8 { ret ("", syntax(it, p)) }
        if p.s[p.i] == 92u8 {
            plain = false
            p.i += 2usize
        } else {
            p.i += 1usize
        }
    }
    if p.i >= p.s.len { ret ("", syntax(it, p)) }
    let raw = p.s[start..p.i]
    p.i += 1usize
    if plain { ret (raw, ok) }
    let (b, be) = str.builder(it.a, raw.len + 4usize)
    if be != ok { ret ("", js.throw_range(it, "out of memory")) }
    var out = b
    var k = 0usize
    while k < raw.len {
        let c = raw[k]
        if c != 92u8 {
            let pe = str.push_byte(&out, c)
            k += 1usize
            continue
        }
        k += 1usize
        if k >= raw.len { ret ("", syntax(it, p)) }
        let e = raw[k]
        k += 1usize
        if e == 110u8 { let q = str.push_byte(&out, 10u8) } else if e == 116u8 { let q2 = str.push_byte(&out, 9u8) } else if e == 114u8 { let q3 = str.push_byte(&out, 13u8) } else if e == 98u8 { let q4 = str.push_byte(&out, 8u8) } else if e == 102u8 { let q5 = str.push_byte(&out, 12u8) } else if e == 34u8 || e == 92u8 || e == 47u8 { let q6 = str.push_byte(&out, e) } else if e == 117u8 {
            if k + 4usize > raw.len { ret ("", syntax(it, p)) }
            var v = 0u32
            var j = 0usize
            while j < 4usize {
                let h = js.digit_value(raw[k + j])
                if h < 0i32 || h > 15i32 { ret ("", syntax(it, p)) }
                v = v * 16u32 + u32(h)
                j += 1usize
            }
            k += 4usize
            if v >= 55296u32 && v <= 56319u32 && k + 6usize <= raw.len && raw[k] == 92u8 && raw[k + 1usize] == 117u8 {
                var lo = 0u32
                var jj = 0usize
                var good = true
                while jj < 4usize {
                    let h2 = js.digit_value(raw[k + 2usize + jj])
                    if h2 < 0i32 || h2 > 15i32 { good = false }
                    if good { lo = lo * 16u32 + u32(h2) }
                    jj += 1usize
                }
                if good && lo >= 56320u32 && lo <= 57343u32 {
                    js.put_cp(&out, 65536u32 + ((v - 55296u32) << 10u32) + (lo - 56320u32))
                    k += 6usize
                    continue
                }
            }
            if v >= 55296u32 && v <= 57343u32 { js.put_cp(&out, 65533u32) } else { js.put_cp(&out, v) }
        } else {
            ret ("", syntax(it, p))
        }
    }
    ret (str.done(&out), ok)
}

fn parse_value(it: *js.Interp, p: *P, depth: u32) -> (js.Value, err) {
    if depth > 200u32 { ret (js.undefv(), js.throw_range(it, "JSON nesting too deep")) }
    skip_ws(p)
    if p.i >= p.s.len { ret (js.undefv(), syntax(it, p)) }
    let c = p.s[p.i]
    if c == 123u8 {
        p.i += 1usize
        let o = js.new_plain(it)
        var okids: list.List[usize] = zero
        var okeys: list.List[str] = zero
        if p.want {
            let (kl, kle) = list.init[usize](it.a, 4usize)
            let (nl2, nle) = list.init[str](it.a, 4usize)
            okids = kl
            okeys = nl2
        }
        skip_ws(p)
        if p.i < p.s.len && p.s[p.i] == 125u8 {
            p.i += 1usize
            if p.want { try add_rec(it, p, js.obj_value(o), "", okids, okeys) }
            ret (js.obj_value(o), ok)
        }
        while true {
            skip_ws(p)
            if p.i >= p.s.len || p.s[p.i] != 34u8 { ret (js.undefv(), syntax(it, p)) }
            let (k, ke) = parse_string(it, p)
            if ke != ok { ret (js.undefv(), ke) }
            skip_ws(p)
            if p.i >= p.s.len || p.s[p.i] != 58u8 { ret (js.undefv(), syntax(it, p)) }
            p.i += 1usize
            let (v, ve) = parse_value(it, p, depth + 1u32)
            if ve != ok { ret (js.undefv(), ve) }
            if p.want {
                try list.push[usize](&okids, p.last)
                try list.push[str](&okeys, k)
            }
            let (done, de) = js.define_own(it, o, js.key_of(k), js.data_desc(v, js.P_DEFAULT))
            if de != ok { ret (js.undefv(), de) }
            skip_ws(p)
            if p.i < p.s.len && p.s[p.i] == 44u8 {
                p.i += 1usize
            } else if p.i < p.s.len && p.s[p.i] == 125u8 {
                p.i += 1usize
                break
            } else {
                ret (js.undefv(), syntax(it, p))
            }
        }
        if p.want { try add_rec(it, p, js.obj_value(o), "", okids, okeys) }
        ret (js.obj_value(o), ok)
    }
    if c == 91u8 {
        p.i += 1usize
        let a = js.new_array(it)
        var akids: list.List[usize] = zero
        var akeys: list.List[str] = zero
        if p.want {
            let (kl2, kle2) = list.init[usize](it.a, 4usize)
            akids = kl2
        }
        skip_ws(p)
        if p.i < p.s.len && p.s[p.i] == 93u8 {
            p.i += 1usize
            if p.want { try add_rec(it, p, js.obj_value(a), "", akids, akeys) }
            ret (js.obj_value(a), ok)
        }
        while true {
            let (v2, ve2) = parse_value(it, p, depth + 1u32)
            if ve2 != ok { ret (js.undefv(), ve2) }
            if p.want { try list.push[usize](&akids, p.last) }
            try js.array_push(it, a, v2)
            skip_ws(p)
            if p.i < p.s.len && p.s[p.i] == 44u8 {
                p.i += 1usize
            } else if p.i < p.s.len && p.s[p.i] == 93u8 {
                p.i += 1usize
                break
            } else {
                ret (js.undefv(), syntax(it, p))
            }
        }
        if p.want { try add_rec(it, p, js.obj_value(a), "", akids, akeys) }
        ret (js.obj_value(a), ok)
    }
    let src_start = p.i
    if c == 34u8 {
        let (s, se) = parse_string(it, p)
        if se != ok { ret (js.undefv(), se) }
        if p.want { try add_rec(it, p, js.str_value(s), p.s[src_start..p.i], zero, zero) }
        ret (js.str_value(s), ok)
    }
    if str.starts_with(p.s[p.i..], "true") {
        p.i += 4usize
        if p.want { try add_rec(it, p, js.bool_value(true), p.s[src_start..p.i], zero, zero) }
        ret (js.bool_value(true), ok)
    }
    if str.starts_with(p.s[p.i..], "false") {
        p.i += 5usize
        if p.want { try add_rec(it, p, js.bool_value(false), p.s[src_start..p.i], zero, zero) }
        ret (js.bool_value(false), ok)
    }
    if str.starts_with(p.s[p.i..], "null") {
        p.i += 4usize
        if p.want { try add_rec(it, p, js.null_value(), p.s[src_start..p.i], zero, zero) }
        ret (js.null_value(), ok)
    }
    if c == 45u8 || (c >= 48u8 && c <= 57u8) {
        let start = p.i
        if p.s[p.i] == 45u8 { p.i += 1usize }
        if p.i >= p.s.len { ret (js.undefv(), syntax(it, p)) }
        if p.s[p.i] == 48u8 {
            p.i += 1usize
        } else if p.s[p.i] >= 49u8 && p.s[p.i] <= 57u8 {
            while p.i < p.s.len && p.s[p.i] >= 48u8 && p.s[p.i] <= 57u8 { p.i += 1usize }
        } else {
            ret (js.undefv(), syntax(it, p))
        }
        if p.i < p.s.len && p.s[p.i] == 46u8 {
            p.i += 1usize
            let fs = p.i
            while p.i < p.s.len && p.s[p.i] >= 48u8 && p.s[p.i] <= 57u8 { p.i += 1usize }
            if p.i == fs { ret (js.undefv(), syntax(it, p)) }
        }
        if p.i < p.s.len && (p.s[p.i] == 101u8 || p.s[p.i] == 69u8) {
            p.i += 1usize
            if p.i < p.s.len && (p.s[p.i] == 43u8 || p.s[p.i] == 45u8) { p.i += 1usize }
            let es = p.i
            while p.i < p.s.len && p.s[p.i] >= 48u8 && p.s[p.i] <= 57u8 { p.i += 1usize }
            if p.i == es { ret (js.undefv(), syntax(it, p)) }
        }
        let nv = js.num_value(js.string_to_number(it.a, p.s[start..p.i]))
        if p.want { try add_rec(it, p, nv, p.s[start..p.i], zero, zero) }
        ret (nv, ok)
    }
    ret (js.undefv(), syntax(it, p))
}

fn three_args(it: *js.Interp, x: js.Value, y: js.Value, z: js.Value) -> []const js.Value {
    let (cell, ce) = mem.alloc[js.Value](it.a, 3usize)
    if ce != ok { ret js.zero_args() }
    cell[0usize] = x
    cell[1usize] = y
    cell[2usize] = z
    ret cell[0usize..3usize]
}

fn revive(it: *js.Interp, p: *P, rec_in: usize, holder: *js.Obj, key: js.Key, reviver: js.Value) -> (js.Value, err) {
    let (val, ve) = js.get_prop(it, holder, key, js.obj_value(holder))
    if ve != ok { ret (js.undefv(), ve) }
    // The record only describes the value that was parsed: a replaced value has no source and no child records.
    var rec = NO_REC
    if rec_in != NO_REC && js.same_value(p.recs.items[rec_in].value, val) { rec = rec_in }
    let context = js.new_plain(it)
    if rec != NO_REC && !js.is_object(val) {
        let ce0 = js.define_data(it, context, js.key_of("source"), js.str_value(p.recs.items[rec].source), js.P_DEFAULT)
    }
    if js.is_object(val) {
        let vo = js.as_object(val)
        let (val_is_array, vae) = js.is_array_e(it, val)
        if vae != ok { ret (js.undefv(), vae) }
        if val_is_array {
            let (len, le) = js.length_of(it, vo)
            if le != ok { ret (js.undefv(), le) }
            var i = 0.0f64
            while i < len {
                let ik = js.key_of(js.number_to_string(it.a, i))
                var child = NO_REC
                if rec != NO_REC && usize(i) < p.recs.items[rec].kids.len { child = p.recs.items[rec].kids.items[usize(i)] }
                let (nv, ne) = revive(it, p, child, vo, ik, reviver)
                if ne != ok { ret (js.undefv(), ne) }
                if js.is_undefined(nv) {
                    let (dd, dde) = js.delete_prop_e(it, vo, ik)
                    if dde != ok { ret (js.undefv(), dde) }
                } else {
                    let (done, de) = js.define_own(it, vo, ik, js.data_desc(nv, js.P_DEFAULT))
                    if de != ok { ret (js.undefv(), de) }
                }
                i += 1.0f64
            }
        } else {
            let (all_keys, ke) = js.own_keys(it, vo)
            if ke != ok { ret (js.undefv(), ke) }
            // EnumerableOwnProperties first, then the values are revived one by one.
            let (kl, kle) = list.init[js.Key](it.a, all_keys.len + 1usize)
            var enum_list = kl
            var ai = 0usize
            while ai < all_keys.len {
                let ak = all_keys[ai]
                ai += 1usize
                if js.is_symbol_key(ak) { continue }
                let (apr, afound, age) = js.get_own_e(it, vo, ak)
                if age != ok { ret (js.undefv(), age) }
                if afound && (apr.flags & js.P_ENUMERABLE) != 0u8 { try list.push[js.Key](&enum_list, ak) }
            }
            let keys = list.slice_const[js.Key](&enum_list)
            var k = 0usize
            while k < keys.len {
                let found = true
                if found {
                    var child2 = NO_REC
                    if rec != NO_REC && !js.is_symbol_key(keys[k]) {
                        var q = p.recs.items[rec].keys.len
                        while q > 0usize {
                            q -= 1usize
                            if str.eq(p.recs.items[rec].keys.items[q], keys[k].name) {
                                child2 = p.recs.items[rec].kids.items[q]
                                break
                            }
                        }
                    }
                    let (nv2, ne2) = revive(it, p, child2, vo, keys[k], reviver)
                    if ne2 != ok { ret (js.undefv(), ne2) }
                    if js.is_undefined(nv2) {
                        let (dd2, dde2) = js.delete_prop_e(it, vo, keys[k])
                        if dde2 != ok { ret (js.undefv(), dde2) }
                    } else {
                        let (done2, de2) = js.define_own(it, vo, keys[k], js.data_desc(nv2, js.P_DEFAULT))
                        if de2 != ok { ret (js.undefv(), de2) }
                    }
                }
                k += 1usize
            }
        }
    }
    let (r, re) = js.call_function(it, reviver, js.obj_value(holder), three_args(it, js.key_to_value(key), val, js.obj_value(context)))
    ret (r, re)
}

fn json_parse(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (text, te) = js.to_string(it, arg(args, 0usize))
    if te != ok { ret (js.undefv(), te) }
    let reviver = arg(args, 1usize)
    var p = P { s: text, i: 0usize, want: js.is_callable(reviver), recs: zero, last: NO_REC }
    if p.want {
        let (rl, rle) = list.init[Rec](it.a, 16usize)
        p.recs = rl
    }
    let (v, ve) = parse_value(it, &p, 0u32)
    if ve != ok { ret (js.undefv(), ve) }
    skip_ws(&p)
    if p.i < p.s.len { ret (js.undefv(), syntax(it, &p)) }
    if js.is_callable(reviver) {
        let root = js.new_plain(it)
        let (done, de) = js.define_own(it, root, js.key_of(""), js.data_desc(v, js.P_DEFAULT))
        if de != ok { ret (js.undefv(), de) }
        let (r, re) = revive(it, &p, p.last, root, js.key_of(""), reviver)
        ret (r, re)
    }
    ret (v, ok)
}

fn is_raw_json(v: js.Value) -> bool {
    ret js.is_object(v) && js.as_object(v).class == js.C_OBJECT && str.eq(js.as_object(v).text, "rawJSON")
}

fn json_is_raw_json(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    ret (js.bool_value(is_raw_json(arg(args, 0usize))), ok)
}

fn json_raw_json(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let (text, te) = js.to_string(it, arg(args, 0usize))
    if te != ok { ret (js.undefv(), te) }
    if text.len == 0usize { ret (js.undefv(), js.throw_syntax(it, "JSON.rawJSON: empty text")) }
    let first = text[0usize]
    let last = text[text.len - 1usize]
    if first == 9u8 || first == 10u8 || first == 13u8 || first == 32u8 || last == 9u8 || last == 10u8 || last == 13u8 || last == 32u8 {
        ret (js.undefv(), js.throw_syntax(it, "JSON.rawJSON: text starts or ends with whitespace"))
    }
    if first == 123u8 || first == 91u8 { ret (js.undefv(), js.throw_syntax(it, "JSON.rawJSON: text must be a primitive")) }
    var p = P { s: text, i: 0usize, want: false, recs: zero, last: NO_REC }
    let (v, ve) = parse_value(it, &p, 0u32)
    if ve != ok { ret (js.undefv(), ve) }
    skip_ws(&p)
    if p.i < p.s.len { ret (js.undefv(), syntax(it, &p)) }
    let o = js.new_obj(it, js.C_OBJECT, js.null_obj())
    let de = js.define_data(it, o, js.key_of("rawJSON"), js.str_value(text), js.P_ENUMERABLE)
    o.extensible = false
    o.text = "rawJSON"
    ret (js.obj_value(o), ok)
}

// --- stringify

type S = struct {
    parts: list.List[str], stack: list.List[*js.Obj], indent: str, gap_stack: list.List[str], replacer: js.Value, has_replacer: bool,
    allow: list.List[js.Key], has_allow: bool
}

fn quote(it: *js.Interp, s: str) -> str {
    let (b, be) = str.builder(it.a, s.len + 8usize)
    if be != ok { ret s }
    var out = b
    let q0 = str.push_byte(&out, 34u8)
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 34u8 { let a1 = str.push(&out, "\\\"") } else if c == 92u8 { let a2 = str.push(&out, "\\\\") } else if c == 8u8 { let a3 = str.push(&out, "\\b") } else if c == 12u8 { let a4 = str.push(&out, "\\f") } else if c == 10u8 { let a5 = str.push(&out, "\\n") } else if c == 13u8 { let a6 = str.push(&out, "\\r") } else if c == 9u8 { let a7 = str.push(&out, "\\t") } else if c < 32u8 {
            let a8 = str.push(&out, "\\u00")
            let hex = "0123456789abcdef"
            let a9 = str.push_byte(&out, hex[usize(c >> 4u8)])
            let a10 = str.push_byte(&out, hex[usize(c & 15u8)])
        } else if c == 237u8 && i + 2usize < s.len && s[i + 1usize] >= 160u8 {
            let u = (u32(s[i + 1usize] & 15u8) << 6u32) | u32(s[i + 2usize] & 63u8) | 55296u32 | (u32(s[i + 1usize] & 16u8) << 6u32)
            let hex2 = "0123456789abcdef"
            let a12 = str.push(&out, "\\u")
            let a13 = str.push_byte(&out, hex2[usize((u >> 12u32) & 15u32)])
            let a14 = str.push_byte(&out, hex2[usize((u >> 8u32) & 15u32)])
            let a15 = str.push_byte(&out, hex2[usize((u >> 4u32) & 15u32)])
            let a16 = str.push_byte(&out, hex2[usize(u & 15u32)])
            i += 3usize
            continue
        } else {
            let a11 = str.push_byte(&out, c)
        }
        i += 1usize
    }
    let q1 = str.push_byte(&out, 34u8)
    ret str.done(&out)
}

fn ser(it: *js.Interp, st: *S, holder: *js.Obj, key: js.Key, value_in: js.Value, indent: str) -> (str, bool, err) {
    // (text, produced a value, error)
    var value = value_in
    if js.is_object(value) || js.is_bigint(value) {
        let (tj, tje) = js.get_value(it, value, js.key_of("toJSON"))
        if tje != ok { ret ("", false, tje) }
        if js.is_callable(tj) {
            let (r, re) = js.call_function(it, tj, value, js.one_arg(it, js.key_to_value(key)))
            if re != ok { ret ("", false, re) }
            value = r
        }
    }
    if st.has_replacer {
        let (r2, re2) = js.call_function(it, st.replacer, js.obj_value(holder), js.two_args(it, js.key_to_value(key), value))
        if re2 != ok { ret ("", false, re2) }
        value = r2
    }
    if js.is_object(value) {
        let o = js.as_object(value)
        if o.class == js.C_NUMBER {
            let (n, ne) = js.to_number(it, value)
            if ne != ok { ret ("", false, ne) }
            value = js.num_value(n)
        } else if o.class == js.C_STRING {
            let (s, se) = js.to_string(it, value)
            if se != ok { ret ("", false, se) }
            value = js.str_value(s)
        } else if o.class == js.C_BOOLEAN || o.class == js.C_BIGINT {
            value = o.prim
        }
    }
    if is_raw_json(value) {
        let (rv, rve) = js.get_value(it, value, js.key_of("rawJSON"))
        if rve != ok { ret ("", false, rve) }
        let (rs, rse) = js.to_string(it, rv)
        if rse != ok { ret ("", false, rse) }
        ret (rs, true, ok)
    }
    switch value {
    case .Big as bigv:
        ret ("", false, js.throw_type(it, "Do not know how to serialize a BigInt"))
    case .Null:
        ret ("null", true, ok)
    case .Bool as b:
        if b { ret ("true", true, ok) }
        ret ("false", true, ok)
    case .Str as s:
        ret (quote(it, s), true, ok)
    case .Num as n:
        if js.is_finite(n) { ret (js.number_to_string(it.a, n), true, ok) }
        ret ("null", true, ok)
    case .Obj as o:
        if js.is_callable(value) { ret ("", false, ok) }
        // Cycle check.
        var i = 0usize
        while i < st.stack.len {
            if st.stack.items[i] == o { ret ("", false, js.throw_type(it, "Converting circular structure to JSON")) }
            i += 1usize
        }
        try list.push[*js.Obj](&st.stack, o)
        var inner = indent
        let step = st.indent
        inner = js.str_concat(it, indent, step)
        let (pl, ple) = list.init[str](it.a, 8usize)
        var items = pl
        let (is_arr, arr_e) = js.is_array_e(it, value)
        if arr_e != ok { ret ("", false, arr_e) }
        if is_arr {
            let (len, le) = js.length_of(it, o)
            if le != ok { ret ("", false, le) }
            var k = 0.0f64
            while k < len {
                let ik = js.key_of(js.number_to_string(it.a, k))
                let (ev, eve) = js.get_prop(it, o, ik, value)
                if eve != ok { ret ("", false, eve) }
                let (t, has, se2) = ser(it, st, o, ik, ev, inner)
                if se2 != ok { ret ("", false, se2) }
                if has { try list.push[str](&items, t) } else { try list.push[str](&items, "null") }
                k += 1.0f64
            }
            st.stack.len -= 1usize
            if items.len == 0usize { ret ("[]", true, ok) }
            ret (join_items(it, items, "[", "]", indent, inner, step), true, ok)
        }
        var keys: []const js.Key = zero
        if st.has_allow {
            keys = list.slice_const[js.Key](&st.allow)
        } else {
            // The enumerable own string keys are fixed before any value is read (or replaced).
            let (own, oke) = js.own_keys(it, o)
            if oke != ok { ret ("", false, oke) }
            let (kl, kle) = list.init[js.Key](it.a, own.len + 1usize)
            var enum_keys = kl
            var ei = 0usize
            while ei < own.len {
                let ek = own[ei]
                ei += 1usize
                if js.is_symbol_key(ek) { continue }
                let (pr, found, ge) = js.get_own_e(it, o, ek)
                if ge != ok { ret ("", false, ge) }
                if !found || (pr.flags & js.P_ENUMERABLE) == 0u8 { continue }
                try list.push[js.Key](&enum_keys, ek)
            }
            keys = list.slice_const[js.Key](&enum_keys)
        }
        var k2 = 0usize
        while k2 < keys.len {
            let kk = keys[k2]
            k2 += 1usize
            if js.is_symbol_key(kk) { continue }
            let (pv, pve) = js.get_prop(it, o, kk, value)
            if pve != ok { ret ("", false, pve) }
            let (t2, has2, se3) = ser(it, st, o, kk, pv, inner)
            if se3 != ok { ret ("", false, se3) }
            if has2 {
                var sep = ":"
                if step.len > 0usize { sep = ": " }
                try list.push[str](&items, js.str_concat3(it, quote(it, kk.name), sep, t2))
            }
        }
        st.stack.len -= 1usize
        if items.len == 0usize { ret ("{}", true, ok) }
        ret (join_items(it, items, "{", "}", indent, inner, step), true, ok)
    default:
        ret ("", false, ok)
    }
    ret ("", false, ok)
}

fn join_items(it: *js.Interp, items: list.List[str], open: str, close: str, indent: str, inner: str, step: str) -> str {
    var total = open.len + close.len + 8usize
    var i = 0usize
    while i < items.len {
        total += items.items[i].len + inner.len + 4usize
        i += 1usize
    }
    let (b, be) = str.builder(it.a, total)
    if be != ok { ret "" }
    var out = b
    let p0 = str.push(&out, open)
    var k = 0usize
    while k < items.len {
        if k > 0usize { let pc = str.push_byte(&out, 44u8) }
        if step.len > 0usize {
            let pn = str.push_byte(&out, 10u8)
            let pi = str.push(&out, inner)
        }
        let pt = str.push(&out, items.items[k])
        k += 1usize
    }
    if step.len > 0usize {
        let pn2 = str.push_byte(&out, 10u8)
        let pi2 = str.push(&out, indent)
    }
    let p1 = str.push(&out, close)
    ret str.done(&out)
}

fn json_stringify(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    var st: S = zero
    let (pl, ple) = list.init[str](it.a, 4usize)
    st.parts = pl
    let (sl, sle) = list.init[*js.Obj](it.a, 8usize)
    st.stack = sl
    let (al, ale) = list.init[js.Key](it.a, 4usize)
    st.allow = al
    let rep = arg(args, 1usize)
    var rep_is_array = false
    if js.is_object(rep) && !js.is_callable(rep) {
        let (ra, rae) = js.is_array_e(it, rep)
        if rae != ok { ret (js.undefv(), rae) }
        rep_is_array = ra
    }
    if js.is_callable(rep) {
        st.replacer = rep
        st.has_replacer = true
    } else if rep_is_array {
        st.has_allow = true
        let ro = js.as_object(rep)
        let (len, le) = js.length_of(it, ro)
        if le != ok { ret (js.undefv(), le) }
        var i = 0.0f64
        while i < len {
            let (item, ie) = js.get_index(it, ro, i)
            if ie != ok { ret (js.undefv(), ie) }
            var name = ""
            var take = false
            switch item {
            case .Str as s:
                name = s
                take = true
            case .Num as n:
                name = js.number_to_string(it.a, n)
                take = true
            case .Obj as o:
                if o.class == js.C_STRING || o.class == js.C_NUMBER {
                    let (s2, se) = js.to_string(it, item)
                    if se != ok { ret (js.undefv(), se) }
                    name = s2
                    take = true
                }
            default:
                take = false
            }
            if take {
                var dup = false
                var d = 0usize
                while d < st.allow.len {
                    if str.eq(st.allow.items[d].name, name) { dup = true }
                    d += 1usize
                }
                if !dup { try list.push[js.Key](&st.allow, js.key_of(name)) }
            }
            i += 1.0f64
        }
    }
    var space = arg(args, 2usize)
    if js.is_object(space) {
        let so = js.as_object(space)
        if so.class == js.C_NUMBER {
            let (n, ne) = js.to_number(it, space)
            if ne != ok { ret (js.undefv(), ne) }
            space = js.num_value(n)
        } else if so.class == js.C_STRING {
            let (s, se) = js.to_string(it, space)
            if se != ok { ret (js.undefv(), se) }
            space = js.str_value(s)
        }
    }
    st.indent = ""
    switch space {
    case .Num as n:
        var k = js.to_integer(n)
        if k > 10.0f64 { k = 10.0f64 }
        if k >= 1.0f64 {
            let (b, be) = str.builder(it.a, 16usize)
            if be != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
            var out = b
            var j = 0.0f64
            while j < k {
                let pe = str.push_byte(&out, 32u8)
                j += 1.0f64
            }
            st.indent = str.done(&out)
        }
    case .Str as s2:
        var cut = js.units(s2)
        if cut > 10usize { cut = 10usize }
        st.indent = js.substring_units(it.a, s2, 0usize, cut)
    default:
        st.indent = ""
    }
    let wrapper = js.new_plain(it)
    let (done, de) = js.define_own(it, wrapper, js.key_of(""), js.data_desc(arg(args, 0usize), js.P_DEFAULT))
    if de != ok { ret (js.undefv(), de) }
    let (text, has, se2) = ser(it, &st, wrapper, js.key_of(""), arg(args, 0usize), "")
    if se2 != ok { ret (js.undefv(), se2) }
    if !has { ret (js.undefv(), ok) }
    ret (js.str_value(text), ok)
}

fn install_json(it: *js.Interp) {
    let j = js.new_plain(it)
    let e0 = js.define_data(it, it.global, js.key_of("JSON"), js.obj_value(j), js.P_HIDDEN)
    let e1 = js.define_data(it, j, js.key_of_symbol(it.sym_to_string_tag), js.str_value("JSON"), js.P_CONFIGURABLE)
    it.last = j
    js.add_method(it, it.last, "rawJSON", 1u32, json_raw_json)
    js.add_method(it, it.last, "isRawJSON", 1u32, json_is_raw_json)
    js.add_method(it, it.last, "parse", 2u32, json_parse)
    js.add_method(it, it.last, "stringify", 3u32, json_stringify)
}
