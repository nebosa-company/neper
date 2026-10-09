// The random/hash/encode, array, reference and extraction function groups of the formula library (L027):
// RANDOM, UUID, MD5, SHA1, SHA256, CRC32, BASE64, URLENCODE, GENERATEPASSWORD; MAP, FILTER, REDUCE, SORT, ANY, ALL,
// JOIN, FLAT, UNIQUE, COMPACT, COLLECT, GET, FIRST, LAST, SPLIT, SLICE; ROW, ROWID, TABLEID, APPID, REALMID, USERID,
// CREATEDON, UPDATEDON, CREATEDBY, UPDATEDBY, BROWSERAGENT, CURRENTUSER, GETRECORDS, GETFIELDVALUES, CHILDREN, ISNEW,
// ISCHANGED, PRIORVALUE, ANCESTORS, NAME, PROPERTY, PROPERTIES; JSONQUERY and XMLQUERY. Each follows appdor's
// `src/formula/{random-hash-encode,array,reference,extraction}.js` with the same names, aliases, arities and messages.
//
// Differences: the random functions draw from the evaluator's own generator (seeded by `Context.random_seed`), not
// from Mersenne Twister; GETRECORDS, GETFIELDVALUES, CHILDREN and ANCESTORS have no host callbacks to call and
// answer `#N/A` as appdor's do without one; XML white space is the ASCII set.

use e.algo.formula as f
use e.algo.formula.text as tx
use e.algo.hash as ahash
use e.bytes
use e.crypto.hash as hash
use e.fmt.json as json
use e.math
use e.mem
use e.str
use e.text.utf8 as utf8

// --- helpers ----------------------------------------------------------------------------------------------------

// The elements of an array value; a blank is none and any other value is one element.
fn items_of(a: *mem.Arena, v: f.Value) -> []const f.Value {
    if v.kind == .Array { ret v.items }
    if f.is_blank(v) { ret f.zero_items() }
    let (cell, e) = mem.alloc[f.Value](a, 1usize)
    if e != ok { ret f.zero_items() }
    cell[0usize] = v
    ret cell[0usize..1usize]
}

fn values_of(a: *mem.Arena, count: usize) -> []f.Value {
    var none: []f.Value = zero
    if count == 0usize { ret none }
    let (out, e) = mem.alloc[f.Value](a, count)
    if e != ok { ret none }
    ret out
}

fn array_of(out: []f.Value, n: usize) -> f.Value {
    if n == 0usize { ret f.array(f.zero_items()) }
    ret f.array(out[0usize..n])
}

// JavaScript's `Number(value)`.
fn js_number(a: *mem.Arena, v: f.Value) -> f64 {
    if v.kind == .Number || v.kind == .Date || v.kind == .Bool { ret v.n }
    if v.kind == .Blank { ret 0.0f64 }
    if v.kind == .Text {
        let t = str.trim(v.s)
        if t.len == 0usize { ret 0.0f64 }
        let (n, good) = f.parse_number_text(t)
        if good { ret n }
        ret f.nan()
    }
    if v.kind == .Array {
        if v.items.len == 0usize { ret 0.0f64 }
        if v.items.len > 1usize { ret f.nan() }
        let one = v.items[0usize]
        if one.kind == .Bool || one.kind == .Date || one.kind == .Record || one.kind == .Error { ret f.nan() }
        ret js_number(a, one)
    }
    ret f.nan()
}

// A text in JavaScript's `trim`: every white space code point at both ends.
fn js_trim(s: str) -> str {
    var from = 0usize
    var to = s.len
    var go = true
    while go && from < to {
        var it = utf8.iterator(s[from..to])
        let (scalar, got) = utf8.iterator_next(&it)
        if got && tx.js_space(scalar) {
            if scalar < 128u32 {
                from += 1usize
            } else if scalar < 2048u32 {
                from += 2usize
            } else {
                from += 3usize
            }
        } else {
            go = false
        }
    }
    go = true
    while go && to > from {
        // the last scalar: walk back over continuation bytes
        var k = to - 1usize
        while k > from && (s[k] & 192u8) == 128u8 { k -= 1usize }
        var it = utf8.iterator(s[k..to])
        let (scalar, got) = utf8.iterator_next(&it)
        if got && tx.js_space(scalar) {
            to = k
        } else {
            go = false
        }
    }
    ret s[from..to]
}

fn hex_of(a: *mem.Arena, digest: []const u8) -> str {
    let (out, e) = mem.alloc[u8](a, digest.len * 2usize + 1usize)
    if e != ok { ret "" }
    let (s, he) = bytes.hex_encode(out, digest, false)
    ret s
}

// --- random, hash and encoding ---------------------------------------------------------------------------------

fn h_random(c: *f.Call) -> f.Value {
    var lo = 0.0f64
    var hi = 1.0f64
    if c.args.len > 0usize {
        let n = f.to_number(c.a, c.args[0usize])
        if f.is_error(n) { ret n }
        if n.kind != .Blank { lo = n.n }
    }
    if c.args.len > 1usize {
        let n = f.to_number(c.a, c.args[1usize])
        if f.is_error(n) { ret n }
        if n.kind != .Blank { hi = n.n }
    }
    ret f.number(lo + f.random(c.ev) * (hi - lo))
}

fn hex_digit(v: u64) -> u8 {
    if v < 10u64 { ret u8(48u64 + v) }
    ret u8(87u64 + v)
}

fn h_uuid(c: *f.Call) -> f.Value {
    let (out, e) = mem.alloc[u8](c.a, 36usize)
    if e != ok { ret f.generic_error("Out of memory") }
    let template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    var i = 0usize
    while i < 36usize {
        let t = template[i]
        if t == 120u8 || t == 121u8 {
            let r = u64(math.trunc[f64](f.random(c.ev) * 16.0f64))
            var v = r
            if t == 121u8 { v = (r & 3u64) | 8u64 }
            out[i] = hex_digit(v)
        } else {
            out[i] = t
        }
        i += 1usize
    }
    ret f.text(out[0usize..36usize])
}

fn h_md5(c: *f.Call) -> f.Value {
    let s = tx.text_arg(c, 0usize)
    var d = hash.legacy_md5(s)
    ret f.text(hex_of(c.a, d[0usize..16usize]))
}

fn h_sha1(c: *f.Call) -> f.Value {
    let s = tx.text_arg(c, 0usize)
    var d = hash.legacy_sha1(s)
    ret f.text(hex_of(c.a, d[0usize..20usize]))
}

fn h_sha256(c: *f.Call) -> f.Value {
    let s = tx.text_arg(c, 0usize)
    var d = hash.sha256(s)
    ret f.text(hex_of(c.a, d[0usize..32usize]))
}

fn h_crc32(c: *f.Call) -> f.Value {
    let s = tx.text_arg(c, 0usize)
    ret f.number(f64(ahash.crc32(s)))
}

// The second argument of BASE64 and URLENCODE: whether it spells "decode" in any case.
fn decode_mode(c: *f.Call) -> bool {
    if c.args.len < 2usize { ret false }
    ret str.eq(f.lower_text(c.a, tx.text_arg(c, 1usize)), "decode")
}

// The marker of a missing sextet; as bits it is JavaScript's -1.
fn sextet_none() -> u32 { ret 4294967295u32 }

fn b64_index(b: u8) -> u32 {
    if b >= 65u8 && b <= 90u8 { ret u32(b) - 65u32 }
    if b >= 97u8 && b <= 122u8 { ret u32(b) - 71u32 }
    if b >= 48u8 && b <= 57u8 { ret u32(b) + 4u32 }
    if b == 43u8 { ret 62u32 }
    if b == 47u8 { ret 63u32 }
    ret sextet_none()
}

// The byte at `i` as appdor's decoder reads it: a missing one is 0.
fn byte_at(vals: []const u32, i: usize) -> u32 {
    if i >= vals.len { ret 0u32 }
    ret vals[i]
}

// appdor's base64 reader: characters outside the alphabet are dropped, a short group yields what it can, and
// the bytes are read as UTF-8 by a decoder that accepts any lead byte, giving UTF-16 units.
fn base64_decode(c: *f.Call, s: str) -> f.Value {
    let none = sextet_none()
    let (clean, ce) = mem.alloc[u8](c.a, s.len + 1usize)
    if ce != ok { ret f.generic_error("Out of memory") }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if b64_index(s[i]) != none {
            clean[n] = s[i]
            n += 1usize
        }
        i += 1usize
    }
    let (vals, ve) = mem.alloc[u32](c.a, n / 4usize * 3usize + 4usize)
    if ve != ok { ret f.generic_error("Out of memory") }
    var count = 0usize
    i = 0usize
    while i < n {
        let n0 = b64_index(clean[i])
        var n1 = none
        var n2 = none
        var n3 = none
        if i + 1usize < n { n1 = b64_index(clean[i + 1usize]) }
        if i + 2usize < n { n2 = b64_index(clean[i + 2usize]) }
        if i + 3usize < n { n3 = b64_index(clean[i + 3usize]) }
        if n1 == none {
            vals[count] = none
        } else {
            vals[count] = (n0 << 2u32) | (n1 >> 4u32)
        }
        count += 1usize
        if n2 != none {
            vals[count] = ((n1 & 15u32) << 4u32) | (n2 >> 2u32)
            count += 1usize
        }
        if n3 != none {
            vals[count] = ((n2 & 3u32) << 6u32) | n3
            count += 1usize
        }
        i += 4usize
    }
    let (units, ue) = mem.alloc[u16](c.a, count * 2usize + 1usize)
    if ue != ok { ret f.generic_error("Out of memory") }
    let seen = vals[0usize..count]
    var w = 0usize
    var at = 0usize
    while at < count {
        let lead = vals[at]
        at += 1usize
        if lead == none {
            units[w] = 65535u16
            w += 1usize
        } else if lead < 128u32 {
            units[w] = u16(lead)
            w += 1usize
        } else if lead < 224u32 {
            let b1 = byte_at(seen, at)
            at += 1usize
            units[w] = u16(((lead & 31u32) << 6u32) | (b1 & 63u32))
            w += 1usize
        } else if lead < 240u32 {
            let b1 = byte_at(seen, at)
            let b2 = byte_at(seen, at + 1usize)
            at += 2usize
            units[w] = u16(((lead & 15u32) << 12u32) | ((b1 & 63u32) << 6u32) | (b2 & 63u32))
            w += 1usize
        } else {
            let b1 = byte_at(seen, at)
            let b2 = byte_at(seen, at + 1usize)
            let b3 = byte_at(seen, at + 2usize)
            at += 3usize
            let cp = ((lead & 7u32) << 18u32) | ((b1 & 63u32) << 12u32) | ((b2 & 63u32) << 6u32) | (b3 & 63u32)
            if cp > 1114111u32 {
                ret f.generic_error(f.join(c.a, "Invalid code point ", f.number_text(c.a, f64(cp))))
            }
            if cp >= 65536u32 {
                units[w] = u16(55296u32 + ((cp - 65536u32) >> 10u32))
                units[w + 1usize] = u16(56320u32 + ((cp - 65536u32) & 1023u32))
                w += 2usize
            } else {
                units[w] = u16(cp)
                w += 1usize
            }
        }
    }
    ret f.text(tx.text_of_units(c.a, units[0usize..w]))
}

fn h_base64(c: *f.Call) -> f.Value {
    let s = tx.text_arg(c, 0usize)
    if decode_mode(c) { ret base64_decode(c, s) }
    let (dst, e) = mem.alloc[u8](c.a, (s.len + 2usize) / 3usize * 4usize + 1usize)
    if e != ok { ret f.generic_error("Out of memory") }
    let (out, ee) = bytes.base64_encode(dst, s, .Standard, true)
    if ee != ok { ret f.generic_error("BASE64 failed") }
    ret f.text(out)
}

fn upper_digit(v: u8) -> u8 {
    if v < 10u8 { ret 48u8 + v }
    ret 55u8 + v
}

// `encodeURIComponent`.
fn encode_component(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len * 3usize + 1usize)
    if e != ok { ret "" }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let b = s[i]
        let plain = (b >= 48u8 && b <= 57u8) || (b >= 65u8 && b <= 90u8) || (b >= 97u8 && b <= 122u8) || b == 45u8 || b == 95u8 || b == 46u8 || b == 33u8 || b == 126u8 || b == 42u8 || b == 39u8 || b == 40u8 || b == 41u8
        if plain {
            out[n] = b
            n += 1usize
        } else {
            out[n] = 37u8
            out[n + 1usize] = upper_digit(b >> 4u8)
            out[n + 2usize] = upper_digit(b & 15u8)
            n += 3usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn h_urlencode(c: *f.Call) -> f.Value {
    let s = tx.text_arg(c, 0usize)
    if decode_mode(c) {
        let (decoded, good) = tx.decode_component(c.a, s)
        if !good { ret f.value_error("Malformed URL component") }
        ret f.text(decoded)
    }
    ret f.text(encode_component(c.a, s))
}

fn h_generatepassword(c: *f.Call) -> f.Value {
    var length = 16.0f64
    if c.args.len > 0usize && !f.is_blank(c.args[0usize]) {
        let n = f.to_number(c.a, c.args[0usize])
        if f.is_error(n) {
            length = f.nan()
        } else if n.kind == .Blank {
            length = 16.0f64
        } else {
            length = math.trunc[f64](n.n)
        }
    }
    var alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%^&*"
    if c.args.len > 1usize && !f.is_blank(c.args[1usize]) { alphabet = tx.text_arg(c, 1usize) }
    if length != length { ret f.text("") }
    if length < 1.0f64 { length = 1.0f64 }
    if length > 1000000.0f64 { ret f.limit_error("GENERATEPASSWORD length is too large") }
    let count = usize(length)
    var scalars = 0usize
    var it = utf8.iterator(alphabet)
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if got { scalars += 1usize } else { more = false }
    }
    if scalars == 0usize {
        // `alphabet[NaN]` is undefined and `out += undefined` spells it
        var out = ""
        var k = 0usize
        while k < count && k < 1000usize {
            out = f.join(c.a, out, "undefined")
            k += 1usize
        }
        ret f.text(out)
    }
    let (out, e) = mem.alloc[u8](c.a, count * 4usize + 1usize)
    if e != ok { ret f.generic_error("Out of memory") }
    var w = 0usize
    var k = 0usize
    while k < count {
        let pick = usize(math.trunc[f64](f.random(c.ev) * f64(scalars)))
        var walk = utf8.iterator(alphabet)
        var j = 0usize
        var found = false
        while !found {
            let (scalar, got) = utf8.iterator_next(&walk)
            if !got {
                found = true
            } else if j == pick {
                var piece: [4]u8 = zero
                let (width, we) = utf8.encode(scalar, piece[0..])
                var q = 0usize
                while q < usize(width) {
                    out[w] = piece[q]
                    w += 1usize
                    q += 1usize
                }
                found = true
            }
            j += 1usize
        }
        k += 1usize
    }
    ret f.text(out[0usize..w])
}

// --- arrays ------------------------------------------------------------------------------------------------------

// A scope with `current`, `value` and `index` bound for one element (and `accumulator`/`acc` when given).
fn element_scope(c: *f.Call, element: f.Value, index: usize, with_acc: bool, acc: f.Value) -> *const f.Scope {
    var s = f.bind(c.a, c.scope, c.has_scope, "current", element)
    s = f.bind(c.a, s, true, "value", element)
    s = f.bind(c.a, s, true, "index", f.number(f64(index)))
    if with_acc {
        s = f.bind(c.a, s, true, "accumulator", acc)
        s = f.bind(c.a, s, true, "acc", acc)
    }
    ret s
}

fn eval_element(c: *f.Call, node: f.Node, element: f.Value, index: usize) -> f.Value {
    ret f.eval(c.ev, node, element_scope(c, element, index, false, f.blank()), true)
}

fn h_map(c: *f.Call) -> f.Value {
    let arr = f.eval_node(c, c.nodes[0usize])
    if f.is_error(arr) { ret arr }
    let items = items_of(c.a, arr)
    let out = values_of(c.a, items.len)
    var i = 0usize
    while i < items.len {
        let v = eval_element(c, c.nodes[1usize], items[i], i)
        if f.is_error(v) { ret v }
        out[i] = v
        i += 1usize
    }
    ret array_of(out, items.len)
}

fn h_filter(c: *f.Call) -> f.Value {
    let arr = f.eval_node(c, c.nodes[0usize])
    if f.is_error(arr) { ret arr }
    let items = items_of(c.a, arr)
    let out = values_of(c.a, items.len)
    var n = 0usize
    var i = 0usize
    while i < items.len {
        let keep = eval_element(c, c.nodes[1usize], items[i], i)
        if f.is_error(keep) { ret keep }
        if f.to_bool(keep) {
            out[n] = items[i]
            n += 1usize
        }
        i += 1usize
    }
    ret array_of(out, n)
}

fn h_reduce(c: *f.Call) -> f.Value {
    let arr = f.eval_node(c, c.nodes[0usize])
    if f.is_error(arr) { ret arr }
    let items = items_of(c.a, arr)
    var acc = f.blank()
    var start = 0usize
    if c.nodes.len > 2usize {
        acc = f.eval_node(c, c.nodes[2usize])
        if f.is_error(acc) { ret acc }
    } else {
        if items.len == 0usize { ret f.blank() }
        acc = items[0usize]
        start = 1usize
    }
    var i = start
    while i < items.len {
        acc = f.eval(c.ev, c.nodes[1usize], element_scope(c, items[i], i, true, acc), true)
        if f.is_error(acc) { ret acc }
        i += 1usize
    }
    ret acc
}

// The comparator of SORT as JavaScript's sort sees it: a number, 0 when the keys cannot be compared.
fn sort_order(a: *mem.Arena, x: f.Value, y: f.Value, desc: bool) -> f64 {
    let r = f.compare_values(a, x, y)
    if r.kind == .Error { ret 0.0f64 }
    var n = r.n
    if n != n { ret 0.0f64 }
    if desc { n = 0.0f64 - n }
    ret n
}

// V8's TimSort for fewer than 64 elements: the leading run (reversed when strictly descending), then binary
// insertion of the rest. Longer arrays use a stable merge sort, which agrees with it for a consistent order.
fn sort_small(a: *mem.Arena, order: []usize, keys: []const f.Value, desc: bool) {
    let n = order.len
    if n < 2usize { ret }
    var run = 2usize
    let descending = sort_order(a, keys[order[1usize]], keys[order[0usize]], desc) < 0.0f64
    var previous = order[1usize]
    var idx = 2usize
    var stop = false
    while idx < n && !stop {
        let current = order[idx]
        let r = sort_order(a, keys[current], keys[previous], desc)
        if descending {
            if r >= 0.0f64 { stop = true }
        } else {
            if r < 0.0f64 { stop = true }
        }
        if !stop {
            previous = current
            run += 1usize
            idx += 1usize
        }
    }
    if descending {
        var lo = 0usize
        var hi = run - 1usize
        while lo < hi {
            let t = order[lo]
            order[lo] = order[hi]
            order[hi] = t
            lo += 1usize
            hi -= 1usize
        }
    }
    var start = run
    while start < n {
        var left = 0usize
        var right = start
        let pivot = order[start]
        while left < right {
            let mid = left + ((right - left) >> 1usize)
            if sort_order(a, keys[pivot], keys[order[mid]], desc) < 0.0f64 {
                right = mid
            } else {
                left = mid + 1usize
            }
        }
        var p = start
        while p > left {
            order[p] = order[p - 1usize]
            p -= 1usize
        }
        order[left] = pivot
        start += 1usize
    }
}

fn merge_sort(a: *mem.Arena, order: []usize, tmp: []usize, keys: []const f.Value, desc: bool, lo: usize, hi: usize) {
    if hi - lo < 2usize { ret }
    let mid = lo + (hi - lo) / 2usize
    merge_sort(a, order, tmp, keys, desc, lo, mid)
    merge_sort(a, order, tmp, keys, desc, mid, hi)
    var i = lo
    var j = mid
    var k = lo
    while i < mid && j < hi {
        // take from the right only when it is strictly smaller (stable)
        if sort_order(a, keys[order[j]], keys[order[i]], desc) < 0.0f64 {
            tmp[k] = order[j]
            j += 1usize
        } else {
            tmp[k] = order[i]
            i += 1usize
        }
        k += 1usize
    }
    while i < mid {
        tmp[k] = order[i]
        i += 1usize
        k += 1usize
    }
    while j < hi {
        tmp[k] = order[j]
        j += 1usize
        k += 1usize
    }
    k = lo
    while k < hi {
        order[k] = tmp[k]
        k += 1usize
    }
}

fn h_sort(c: *f.Call) -> f.Value {
    let arr = f.eval_node(c, c.nodes[0usize])
    if f.is_error(arr) { ret arr }
    let items = items_of(c.a, arr)
    var desc = false
    var has_key = false
    var key_node = c.nodes[0usize]
    if c.nodes.len == 2usize && c.nodes[1usize].kind == .Bool {
        desc = c.nodes[1usize].b
    } else {
        if c.nodes.len >= 2usize {
            key_node = c.nodes[1usize]
            has_key = true
        }
        if c.nodes.len >= 3usize {
            let d = f.eval_node(c, c.nodes[2usize])
            if f.is_error(d) { ret d }
            desc = f.to_bool(d)
        }
    }
    let n = items.len
    if n == 0usize { ret f.array(f.zero_items()) }
    let keys = values_of(c.a, n)
    var i = 0usize
    while i < n {
        if has_key {
            keys[i] = eval_element(c, key_node, items[i], i)
        } else {
            keys[i] = items[i]
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        if f.is_error(keys[i]) { ret keys[i] }
        i += 1usize
    }
    let (order, oe) = mem.alloc[usize](c.a, n)
    if oe != ok { ret f.generic_error("Out of memory") }
    i = 0usize
    while i < n {
        order[i] = i
        i += 1usize
    }
    if n < 64usize {
        sort_small(c.a, order, keys, desc)
    } else {
        let (tmp, te) = mem.alloc[usize](c.a, n)
        if te != ok { ret f.generic_error("Out of memory") }
        merge_sort(c.a, order, tmp, keys, desc, 0usize, n)
    }
    let out = values_of(c.a, n)
    i = 0usize
    while i < n {
        out[i] = items[order[i]]
        i += 1usize
    }
    ret array_of(out, n)
}

fn h_any(c: *f.Call) -> f.Value {
    let arr = f.eval_node(c, c.nodes[0usize])
    if f.is_error(arr) { ret arr }
    let items = items_of(c.a, arr)
    var i = 0usize
    while i < items.len {
        var test = items[i]
        if c.nodes.len > 1usize { test = eval_element(c, c.nodes[1usize], items[i], i) }
        if f.is_error(test) { ret test }
        if f.to_bool(test) { ret f.boolean(true) }
        i += 1usize
    }
    ret f.boolean(false)
}

fn h_all(c: *f.Call) -> f.Value {
    let arr = f.eval_node(c, c.nodes[0usize])
    if f.is_error(arr) { ret arr }
    let items = items_of(c.a, arr)
    var i = 0usize
    while i < items.len {
        var test = items[i]
        if c.nodes.len > 1usize { test = eval_element(c, c.nodes[1usize], items[i], i) }
        if f.is_error(test) { ret test }
        if !f.to_bool(test) { ret f.boolean(false) }
        i += 1usize
    }
    ret f.boolean(true)
}

// The pieces joined with `delim` between them.
fn join_parts(a: *mem.Arena, parts: []const str, delim: str) -> str {
    if parts.len == 0usize { ret "" }
    var total = delim.len * (parts.len - 1usize)
    var i = 0usize
    while i < parts.len {
        total += parts[i].len
        i += 1usize
    }
    let (out, e) = mem.alloc[u8](a, total + 1usize)
    if e != ok { ret "" }
    var w = 0usize
    i = 0usize
    while i < parts.len {
        if i > 0usize {
            var k = 0usize
            while k < delim.len {
                out[w] = delim[k]
                w += 1usize
                k += 1usize
            }
        }
        var k = 0usize
        while k < parts[i].len {
            out[w] = parts[i][k]
            w += 1usize
            k += 1usize
        }
        i += 1usize
    }
    ret out[0usize..w]
}

fn h_join(c: *f.Call) -> f.Value {
    let items = items_of(c.a, c.args[0usize])
    var delim = ","
    if c.args.len > 1usize {
        let d = f.to_text(c.a, c.args[1usize])
        if f.is_error(d) { ret d }
        delim = d.s
    }
    if items.len == 0usize { ret f.text("") }
    let (parts, e) = mem.alloc[str](c.a, items.len)
    if e != ok { ret f.generic_error("Out of memory") }
    var i = 0usize
    while i < items.len {
        parts[i] = ""
        if !f.is_blank(items[i]) {
            let piece = f.to_text(c.a, items[i])
            if f.is_error(piece) {
                parts[i] = f.code_text(piece.code)
            } else {
                parts[i] = piece.s
            }
        }
        i += 1usize
    }
    ret f.text(join_parts(c.a, parts, delim))
}

fn h_flat(c: *f.Call) -> f.Value {
    let total = f.flatten_values(c.args, f.zero_items_mut(), 0usize)
    let out = values_of(c.a, total)
    let n = f.flatten_values(c.args, out, 0usize)
    ret array_of(out, n)
}

// The elements an array function works on: the one array argument's, or the arguments themselves.
fn operands(c: *f.Call) -> []const f.Value {
    if c.args.len == 1usize { ret items_of(c.a, c.args[0usize]) }
    ret c.args
}

fn h_unique(c: *f.Call) -> f.Value {
    let items = operands(c)
    let out = values_of(c.a, items.len)
    var n = 0usize
    var i = 0usize
    while i < items.len {
        var seen = false
        var k = 0usize
        while k < n && !seen {
            if f.loose_equals(c.a, out[k], items[i]) { seen = true }
            k += 1usize
        }
        if !seen {
            out[n] = items[i]
            n += 1usize
        }
        i += 1usize
    }
    ret array_of(out, n)
}

fn h_compact(c: *f.Call) -> f.Value {
    let items = operands(c)
    let out = values_of(c.a, items.len)
    var n = 0usize
    var i = 0usize
    while i < items.len {
        if !f.is_blank(items[i]) && !f.is_error(items[i]) {
            out[n] = items[i]
            n += 1usize
        }
        i += 1usize
    }
    ret array_of(out, n)
}

fn is_ws_byte(b: u8) -> bool { ret b == 32u8 || (b >= 9u8 && b <= 13u8) }

fn is_line_break(b: u8) -> bool { ret b == 10u8 || b == 13u8 }

// Whether a COLLECT criterion text is `<op> operand`; the operator and the operand text when it is.
fn criterion(s: str) -> (str, str, bool) {
    var i = 0usize
    while i < s.len && is_ws_byte(s[i]) { i += 1usize }
    var op = ""
    if i + 1usize < s.len {
        let two = s[i..i + 2usize]
        if str.eq(two, "<=") || str.eq(two, ">=") || str.eq(two, "<>") || str.eq(two, "!=") { op = two }
    }
    if op.len == 0usize && i < s.len {
        let one = s[i..i + 1usize]
        if str.eq(one, "=") || str.eq(one, "<") || str.eq(one, ">") { op = one }
    }
    if op.len == 0usize { ret ("", "", false) }
    i += op.len
    while i < s.len && is_ws_byte(s[i]) && !is_line_break(s[i]) { i += 1usize }
    // `(.*)$` cannot cross a line break
    var k = i
    while k < s.len {
        if is_line_break(s[k]) { ret ("", "", false) }
        k += 1usize
    }
    ret (op, s[i..s.len], true)
}

fn h_collect(c: *f.Call) -> f.Value {
    let range = items_of(c.a, c.args[0usize])
    let crange = items_of(c.a, c.args[1usize])
    let crit = c.args[2usize]
    let out = values_of(c.a, range.len)
    var n = 0usize
    var op = ""
    var rhs = f.blank()
    var structured = false
    if crit.kind == .Text {
        let (o, operand, good) = criterion(crit.s)
        if good {
            structured = true
            op = o
            let t = str.trim(operand)
            rhs = f.text(operand)
            if t.len > 0usize {
                let (num, ok_num) = f.parse_number_text(t)
                if ok_num { rhs = f.number(num) }
            }
        }
    }
    var i = 0usize
    while i < range.len {
        var value = f.blank()
        if i < crange.len { value = crange[i] }
        var take = false
        if !structured {
            take = f.loose_equals(c.a, value, crit)
        } else if str.eq(op, "=") {
            take = f.loose_equals(c.a, value, rhs)
        } else if str.eq(op, "<>") || str.eq(op, "!=") {
            take = !f.loose_equals(c.a, value, rhs)
        } else {
            let cmp = f.compare_values(c.a, value, rhs)
            if cmp.kind != .Error {
                if str.eq(op, "<") { take = cmp.n < 0.0f64 }
                if str.eq(op, "<=") { take = cmp.n <= 0.0f64 }
                if str.eq(op, ">") { take = cmp.n > 0.0f64 }
                if str.eq(op, ">=") { take = cmp.n >= 0.0f64 }
            }
        }
        if take {
            out[n] = range[i]
            n += 1usize
        }
        i += 1usize
    }
    ret array_of(out, n)
}

fn h_get(c: *f.Call) -> f.Value {
    let items = items_of(c.a, c.args[0usize])
    let x = js_number(c.a, c.args[1usize])
    if x != x || x - x != 0.0f64 { ret f.blank() }
    let n = math.trunc[f64](x)
    if n == 0.0f64 { ret f.blank() }
    var at = n - 1.0f64
    if n < 0.0f64 { at = f64(items.len) + n }
    if at < 0.0f64 || at >= f64(items.len) { ret f.blank() }
    ret items[usize(at)]
}

fn h_first(c: *f.Call) -> f.Value {
    let items = items_of(c.a, c.args[0usize])
    if items.len == 0usize { ret f.blank() }
    ret items[0usize]
}

fn h_last(c: *f.Call) -> f.Value {
    let items = items_of(c.a, c.args[0usize])
    if items.len == 0usize { ret f.blank() }
    ret items[items.len - 1usize]
}

fn h_split(c: *f.Call) -> f.Value {
    var source = ""
    if !f.is_blank(c.args[0usize]) {
        let t = f.to_text(c.a, c.args[0usize])
        if f.is_error(t) { ret t }
        source = t.s
    }
    var delim = ","
    if c.args.len > 1usize && !f.is_blank(c.args[1usize]) {
        let d = f.to_text(c.a, c.args[1usize])
        if f.is_error(d) { ret d }
        delim = d.s
    }
    var trim = true
    if c.args.len > 2usize { trim = f.to_bool(c.args[2usize]) }
    if delim.len == 0usize {
        // one piece per UTF-16 unit; a half of an astral character reads as U+FFFD
        if source.len == 0usize { ret f.array(f.zero_items()) }
        let units = tx.utf16_len(source)
        let out = values_of(c.a, units)
        var n = 0usize
        var it = utf8.iterator(source)
        var more = true
        while more {
            let (scalar, got) = utf8.iterator_next(&it)
            if !got {
                more = false
            } else if scalar >= 65536u32 {
                out[n] = f.text("\xEF\xBF\xBD")
                out[n + 1usize] = f.text("\xEF\xBF\xBD")
                n += 2usize
            } else {
                var piece: [4]u8 = zero
                let (width, we) = utf8.encode(scalar, piece[0..])
                let (cell, ce) = mem.alloc[u8](c.a, usize(width))
                if ce == ok {
                    var q = 0usize
                    while q < usize(width) {
                        cell[q] = piece[q]
                        q += 1usize
                    }
                    var one: str = cell[0usize..usize(width)]
                    if trim { one = js_trim(one) }
                    out[n] = f.text(one)
                }
                n += 1usize
            }
        }
        ret array_of(out, n)
    }
    // count the pieces, then cut
    var pieces = 1usize
    var at = 0usize
    while at + delim.len <= source.len {
        if str.eq(source[at..at + delim.len], delim) {
            pieces += 1usize
            at += delim.len
        } else {
            at += 1usize
        }
    }
    let out = values_of(c.a, pieces)
    var n = 0usize
    var from = 0usize
    at = 0usize
    while at + delim.len <= source.len {
        if str.eq(source[at..at + delim.len], delim) {
            var p = source[from..at]
            if trim { p = js_trim(p) }
            out[n] = f.text(p)
            n += 1usize
            at += delim.len
            from = at
        } else {
            at += 1usize
        }
    }
    var last = source[from..source.len]
    if trim { last = js_trim(last) }
    out[n] = f.text(last)
    n += 1usize
    ret array_of(out, n)
}

// SLICE's position: 1-based, negative from the end, 0 or non-numeric the fallback.
fn slice_position(a: *mem.Arena, raw: f.Value, len: usize, fallback: f64) -> f64 {
    let x = js_number(a, raw)
    if x != x || x - x != 0.0f64 { ret fallback }
    let n = math.trunc[f64](x)
    if n == 0.0f64 { ret fallback }
    if n < 0.0f64 { ret f64(len) + n }
    ret n - 1.0f64
}

fn h_slice(c: *f.Call) -> f.Value {
    let items = items_of(c.a, c.args[0usize])
    let len = items.len
    let start = slice_position(c.a, c.args[1usize], len, 0.0f64)
    var end = f64(len) - 1.0f64
    if c.args.len > 2usize { end = slice_position(c.a, c.args[2usize], len, f64(len) - 1.0f64) }
    var s = start
    if s < 0.0f64 { s = 0.0f64 }
    var e = end + 1.0f64
    if e < 0.0f64 { e = 0.0f64 }
    if s > f64(len) { s = f64(len) }
    if e > f64(len) { e = f64(len) }
    if s >= e { ret f.array(f.zero_items()) }
    ret f.array(items[usize(s)..usize(e)])
}

// --- references --------------------------------------------------------------------------------------------------

// A named host value; false when the host did not supply it.
fn host_value(c: *f.Call, key: str) -> (f.Value, bool) {
    var i = 0usize
    while i < c.ev.ctx.host.len {
        if str.eq(c.ev.ctx.host[i].name, key) { ret (c.ev.ctx.host[i].value, true) }
        i += 1usize
    }
    ret (f.blank(), false)
}

fn host_or_blank(c: *f.Call, key: str) -> f.Value {
    let (v, found) = host_value(c, key)
    if !found { ret f.blank() }
    ret v
}

fn h_row(c: *f.Call) -> f.Value { ret host_or_blank(c, "rowId") }
fn h_tableid(c: *f.Call) -> f.Value { ret host_or_blank(c, "tableId") }
fn h_appid(c: *f.Call) -> f.Value { ret host_or_blank(c, "appId") }
fn h_realmid(c: *f.Call) -> f.Value { ret host_or_blank(c, "realmId") }
fn h_userid(c: *f.Call) -> f.Value { ret host_or_blank(c, "userId") }
fn h_createdon(c: *f.Call) -> f.Value { ret host_or_blank(c, "createdOn") }
fn h_updatedon(c: *f.Call) -> f.Value { ret host_or_blank(c, "updatedOn") }
fn h_createdby(c: *f.Call) -> f.Value { ret host_or_blank(c, "createdBy") }
fn h_updatedby(c: *f.Call) -> f.Value { ret host_or_blank(c, "updatedBy") }
fn h_browseragent(c: *f.Call) -> f.Value { ret host_or_blank(c, "browserAgent") }

// `ctx.currentUser ?? ctx.userName ?? ctx.userId ?? null`.
fn h_currentuser(c: *f.Call) -> f.Value {
    let (a, ha) = host_value(c, "currentUser")
    if ha && a.kind != .Blank { ret a }
    let (b, hb) = host_value(c, "userName")
    if hb && b.kind != .Blank { ret b }
    let (u, hu) = host_value(c, "userId")
    if hu && u.kind != .Blank { ret u }
    ret f.blank()
}

fn h_getrecords(c: *f.Call) -> f.Value { ret f.na_error("GetRecords requires a host relationship context") }
fn h_getfieldvalues(c: *f.Call) -> f.Value { ret f.na_error("GetFieldValues requires a host relationship context") }
fn h_children(c: *f.Call) -> f.Value { ret f.na_error("CHILDREN requires a host hierarchy context") }
fn h_ancestors(c: *f.Call) -> f.Value { ret f.na_error("ANCESTORS requires a host hierarchy context") }
fn h_isnew(c: *f.Call) -> f.Value { ret f.boolean(c.ev.ctx.is_new) }

fn named(fields: []const f.Field, name: str) -> f.Value {
    var i = 0usize
    while i < fields.len {
        if str.eq(fields[i].name, name) { ret fields[i].value }
        i += 1usize
    }
    ret f.blank()
}

fn h_ischanged(c: *f.Call) -> f.Value {
    let ctx = c.ev.ctx
    let name = tx.text_arg(c, 0usize)
    if ctx.has_prior {
        ret f.boolean(!f.loose_equals(c.a, named(ctx.fields, name), named(ctx.prior, name)))
    }
    if ctx.has_changed {
        var i = 0usize
        while i < ctx.changed.len {
            if str.eq(ctx.changed[i], name) { ret f.boolean(true) }
            i += 1usize
        }
    }
    ret f.boolean(false)
}

fn h_priorvalue(c: *f.Call) -> f.Value {
    let ctx = c.ev.ctx
    if !ctx.has_prior { ret f.blank() }
    ret named(ctx.prior, tx.text_arg(c, 0usize))
}

// The field a node names, when it is a reference.
fn field_name_of(node: f.Node) -> (str, bool) {
    if node.kind == .Field || node.kind == .Name { ret (node.s, true) }
    ret ("", false)
}

fn h_name(c: *f.Call) -> f.Value {
    let (name, good) = field_name_of(c.nodes[0usize])
    if !good { ret f.na_error("NAME expects a field reference") }
    ret f.text(name)
}

// The configured properties of the field a node names; false without host metadata.
fn meta_for(c: *f.Call, node: f.Node) -> ([]const f.Field, bool) {
    var none: []const f.Field = zero
    let (name, good) = field_name_of(node)
    if !good { ret (none, false) }
    var i = 0usize
    while i < c.ev.ctx.meta.len {
        if str.eq(c.ev.ctx.meta[i].field, name) { ret (c.ev.ctx.meta[i].props, true) }
        i += 1usize
    }
    ret (none, false)
}

fn h_property(c: *f.Call) -> f.Value {
    let (props, good) = meta_for(c, c.nodes[0usize])
    if !good { ret f.na_error("PROPERTY requires a field reference and host field metadata") }
    let k = f.to_text(c.a, f.eval_node(c, c.nodes[1usize]))
    var key = k.s
    if f.is_error(k) { key = f.code_text(k.code) }
    var i = 0usize
    while i < props.len {
        if str.eq(props[i].name, key) { ret props[i].value }
        i += 1usize
    }
    ret f.na_error(f.join3(c.a, "No property \"", key, "\" on that field"))
}

fn h_properties(c: *f.Call) -> f.Value {
    let (props, good) = meta_for(c, c.nodes[0usize])
    if !good { ret f.na_error("PROPERTIES requires a field reference and host field metadata") }
    let out = values_of(c.a, props.len)
    var i = 0usize
    while i < props.len {
        let pair = values_of(c.a, 2usize)
        pair[0usize] = f.text(props[i].name)
        pair[1usize] = props[i].value
        out[i] = f.array(pair[0usize..2usize])
        i += 1usize
    }
    ret array_of(out, props.len)
}

// --- extraction --------------------------------------------------------------------------------------------------

fn from_json(a: *mem.Arena, v: json.Value) -> f.Value {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        ret f.number(x)
    case .String as s:
        ret f.text(s)
    case .Bool as b:
        ret f.boolean(b)
    case .Array as items:
        let out = values_of(a, items.len)
        var i = 0usize
        while i < items.len {
            out[i] = from_json(a, items[i])
            i += 1usize
        }
        ret array_of(out, items.len)
    case .Object as members:
        let out = values_of(a, members.len)
        var i = 0usize
        while i < members.len {
            out[i] = from_json(a, members[i].value)
            i += 1usize
        }
        if members.len == 0usize { ret f.record(f.zero_items()) }
        ret f.record(out[0usize..members.len])
    default:
        ret f.blank()
    }
}

fn is_digit(b: u8) -> bool { ret b >= 48u8 && b <= 57u8 }

// One step of a JSONPath-class walk: `[n]` counts, `["k"]`, `['k']` and a bare run name keys.
type Step = struct { key: str, index: f64, numeric: bool }

fn path_steps(a: *mem.Arena, path: str) -> []Step {
    var none: []Step = zero
    let (steps, e) = mem.alloc[Step](a, path.len + 1usize)
    if e != ok { ret none }
    var from = 0usize
    if path.len > 0usize && path[0usize] == 36u8 {
        from = 1usize
        if path.len > 1usize && path[1usize] == 46u8 { from = 2usize }
    }
    let p = path[from..path.len]
    var n = 0usize
    var i = 0usize
    while i < p.len {
        var taken = 0usize
        if p[i] == 91u8 {
            // [digits]
            var q = i + 1usize
            while q < p.len && is_digit(p[q]) { q += 1usize }
            if q > i + 1usize && q < p.len && p[q] == 93u8 {
                let (v, pe) = str.parse_f64(p[i + 1usize..q])
                steps[n] = Step { key: "", index: v, numeric: true }
                n += 1usize
                taken = q + 1usize - i
            } else if i + 1usize < p.len && (p[i + 1usize] == 34u8 || p[i + 1usize] == 39u8) {
                let quote = p[i + 1usize]
                var r = i + 2usize
                while r < p.len && p[r] != quote { r += 1usize }
                if r + 1usize < p.len && p[r + 1usize] == 93u8 {
                    steps[n] = Step { key: p[i + 2usize..r], index: 0.0f64, numeric: false }
                    n += 1usize
                    taken = r + 2usize - i
                }
            }
        } else if p[i] != 46u8 && p[i] != 93u8 {
            var q = i
            while q < p.len && p[q] != 46u8 && p[q] != 91u8 && p[q] != 93u8 { q += 1usize }
            steps[n] = Step { key: p[i..q], index: 0.0f64, numeric: false }
            n += 1usize
            taken = q - i
        }
        if taken == 0usize { taken = 1usize }
        i += taken
    }
    ret steps[0usize..n]
}

fn h_jsonquery(c: *f.Call) -> f.Value {
    if f.is_blank(c.args[0usize]) { ret f.blank() }
    let source = tx.text_arg(c, 0usize)
    let (root, pe) = json.parse(c.a, source, json.Options { allow_duplicate_keys: true, max_depth: 255u16 })
    if pe != ok { ret f.value_error("jsonquery: invalid JSON input") }
    let steps = path_steps(c.a, tx.text_arg(c, 1usize))
    var cur = root
    var i = 0usize
    while i < steps.len {
        var next: json.Value = .Null
        var found = false
        switch cur {
        case .Array as items:
            if steps[i].numeric && steps[i].index < f64(items.len) {
                next = items[usize(steps[i].index)]
                found = true
            }
        case .Object as members:
            if !steps[i].numeric {
                var k = members.len
                while k > 0usize && !found {
                    k -= 1usize
                    if str.eq(members[k].key, steps[i].key) {
                        next = members[k].value
                        found = true
                    }
                }
            }
        default:
            found = false
        }
        if !found { ret f.blank() }
        cur = next
        i += 1usize
    }
    ret from_json(c.a, cur)
}

// The XML a formula queries, flat: nodes in document order with their parent, attributes and text runs.
type Xml = struct {
    src: str,
    at: usize,
    tags: []str,
    parent: []usize,
    attr_from: []usize,
    attr_count: []usize,
    run_first: []usize,
    run_last: []usize,
    count: usize,
    attr_names: []str,
    attr_values: []str,
    attr_total: usize,
    run_from: []usize,
    run_to: []usize,
    run_next: []usize,
    run_total: usize,
    depth: usize,
    failed: bool,
}

fn xml_ws(b: u8) -> bool { ret b == 32u8 || (b >= 9u8 && b <= 13u8) }

fn xml_starts(x: *Xml, lit: str) -> bool {
    if x.at + lit.len > x.src.len { ret false }
    ret str.eq(x.src[x.at..x.at + lit.len], lit)
}

fn xml_skip_ws(x: *Xml) {
    while x.at < x.src.len && xml_ws(x.src[x.at]) { x.at += 1usize }
}

// Move to the byte after `needle`, or to the end when there is none.
fn xml_past(x: *Xml, needle: str) {
    let (at, found) = str.find_from(x.src, needle, x.at)
    if found { x.at = at + needle.len } else { x.at = x.src.len }
}

fn xml_push_run(x: *Xml, node: usize, from: usize, to: usize) {
    let r = x.run_total
    x.run_total += 1usize
    x.run_from[r] = from
    x.run_to[r] = to
    x.run_next[r] = 0usize
    if x.run_first[node] == 0usize {
        x.run_first[node] = r + 1usize
    } else {
        x.run_next[x.run_last[node] - 1usize] = r + 1usize
    }
    x.run_last[node] = r + 1usize
}

// One element; the index plus one of its node, or 0 when the text is not at an element.
fn xml_node(x: *Xml, parent: usize, has_parent: bool) -> usize {
    let n = x.src.len
    xml_skip_ws(x)
    while xml_starts(x, "<?") || xml_starts(x, "<!") {
        if xml_starts(x, "<!--") { xml_past(x, "-->") } else { xml_past(x, ">") }
        xml_skip_ws(x)
    }
    if x.at >= n || x.src[x.at] != 60u8 { ret 0usize }
    if x.depth > 400usize {
        x.failed = true
        ret 0usize
    }
    x.at += 1usize
    let me = x.count
    x.count += 1usize
    x.parent[me] = parent
    if !has_parent { x.parent[me] = 18446744073709551615usize }
    x.run_first[me] = 0usize
    x.run_last[me] = 0usize
    let tag_from = x.at
    while x.at < n && !xml_ws(x.src[x.at]) && x.src[x.at] != 47u8 && x.src[x.at] != 62u8 { x.at += 1usize }
    x.tags[me] = x.src[tag_from..x.at]
    x.attr_from[me] = x.attr_total
    var attrs = 0usize
    var more = true
    while more && x.at < n && x.src[x.at] != 62u8 && x.src[x.at] != 47u8 {
        xml_skip_ws(x)
        if x.at < n && (x.src[x.at] == 62u8 || x.src[x.at] == 47u8) {
            more = false
        } else {
            let name_from = x.at
            while x.at < n && !xml_ws(x.src[x.at]) && x.src[x.at] != 61u8 && x.src[x.at] != 47u8 && x.src[x.at] != 62u8 { x.at += 1usize }
            let name = x.src[name_from..x.at]
            xml_skip_ws(x)
            var value = ""
            if x.at < n && x.src[x.at] == 61u8 {
                x.at += 1usize
                xml_skip_ws(x)
                if x.at < n && (x.src[x.at] == 34u8 || x.src[x.at] == 39u8) {
                    let q = x.src[x.at]
                    x.at += 1usize
                    let value_from = x.at
                    while x.at < n && x.src[x.at] != q { x.at += 1usize }
                    value = x.src[value_from..x.at]
                    x.at += 1usize
                }
            }
            if name.len > 0usize {
                x.attr_names[x.attr_total] = name
                x.attr_values[x.attr_total] = value
                x.attr_total += 1usize
                attrs += 1usize
            }
        }
    }
    x.attr_count[me] = attrs
    if x.at < n && x.src[x.at] == 47u8 {
        x.at += 2usize
        ret me + 1usize
    }
    x.at += 1usize
    x.depth += 1usize
    var run_open = false
    var run_from = 0usize
    var done = false
    while x.at < n && !done {
        if xml_starts(x, "</") {
            if run_open { xml_push_run(x, me, run_from, x.at) }
            run_open = false
            x.at += 2usize
            while x.at < n && x.src[x.at] != 62u8 { x.at += 1usize }
            x.at += 1usize
            done = true
        } else if x.src[x.at] == 60u8 {
            if run_open { xml_push_run(x, me, run_from, x.at) }
            run_open = false
            let child = xml_node(x, me, true)
            if x.failed { done = true }
        } else {
            if !run_open {
                run_open = true
                run_from = x.at
            }
            x.at += 1usize
        }
    }
    if run_open { xml_push_run(x, me, run_from, x.at) }
    x.depth -= 1usize
    ret me + 1usize
}

// The trimmed text of a node: its text runs, joined.
fn xml_text(a: *mem.Arena, x: *Xml, node: usize) -> str {
    var total = 0usize
    var r = x.run_first[node]
    while r != 0usize {
        total += x.run_to[r - 1usize] - x.run_from[r - 1usize]
        r = x.run_next[r - 1usize]
    }
    let (out, e) = mem.alloc[u8](a, total + 1usize)
    if e != ok { ret "" }
    var w = 0usize
    r = x.run_first[node]
    while r != 0usize {
        var k = x.run_from[r - 1usize]
        while k < x.run_to[r - 1usize] {
            out[w] = x.src[k]
            w += 1usize
            k += 1usize
        }
        r = x.run_next[r - 1usize]
    }
    ret js_trim(out[0usize..w])
}

type Seg = struct { tag: str, index: f64, indexed: bool }

// `name` or `name[digits]`; anything else is a tag name of its own.
fn xml_seg(s: str) -> Seg {
    var ok_shape = false
    var cut = 0usize
    while cut < s.len && s[cut] != 91u8 { cut += 1usize }
    if cut > 0usize {
        if cut == s.len {
            ok_shape = true
        } else if s.len > cut + 2usize && s[s.len - 1usize] == 93u8 {
            var all_digits = true
            var k = cut + 1usize
            while k < s.len - 1usize {
                if !is_digit(s[k]) { all_digits = false }
                k += 1usize
            }
            if all_digits { ok_shape = true }
        }
    }
    if !ok_shape { ret Seg { tag: s, index: 0.0f64, indexed: false } }
    if cut == s.len { ret Seg { tag: s, index: 0.0f64, indexed: false } }
    let (v, e) = str.parse_f64(s[cut + 1usize..s.len - 1usize])
    ret Seg { tag: s[0usize..cut], index: v, indexed: true }
}

fn h_xmlquery(c: *f.Call) -> f.Value {
    if f.is_blank(c.args[0usize]) { ret f.blank() }
    let source = tx.text_arg(c, 0usize)
    let path = tx.text_arg(c, 1usize)
    let cap = source.len + 2usize
    var x: Xml = zero
    x.src = source
    let (tags, e1) = mem.alloc[str](c.a, cap)
    let (parent, e2) = mem.alloc[usize](c.a, cap)
    let (attr_from, e3) = mem.alloc[usize](c.a, cap)
    let (attr_count, e4) = mem.alloc[usize](c.a, cap)
    let (run_first, e5) = mem.alloc[usize](c.a, cap)
    let (run_last, e6) = mem.alloc[usize](c.a, cap)
    let (attr_names, e7) = mem.alloc[str](c.a, cap)
    let (attr_values, e8) = mem.alloc[str](c.a, cap)
    let (run_from, e9) = mem.alloc[usize](c.a, cap)
    let (run_to, e10) = mem.alloc[usize](c.a, cap)
    let (run_next, e11) = mem.alloc[usize](c.a, cap)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok {
        ret f.generic_error("Out of memory")
    }
    x.tags = tags
    x.parent = parent
    x.attr_from = attr_from
    x.attr_count = attr_count
    x.run_first = run_first
    x.run_last = run_last
    x.attr_names = attr_names
    x.attr_values = attr_values
    x.run_from = run_from
    x.run_to = run_to
    x.run_next = run_next
    let root = xml_node(&x, 0usize, false)
    if root == 0usize || x.failed { ret f.value_error("xmlquery: invalid XML input") }
    // the path: no leading slash, non-empty segments
    var p = path
    if p.len > 0usize && p[0usize] == 47u8 { p = p[1usize..p.len] }
    let (segs, se) = mem.alloc[str](c.a, p.len + 1usize)
    if se != ok { ret f.generic_error("Out of memory") }
    var count = 0usize
    var from = 0usize
    var i = 0usize
    while i <= p.len {
        if i == p.len || p[i] == 47u8 {
            if i > from {
                segs[count] = p[from..i]
                count += 1usize
            }
            from = i + 1usize
        }
        i += 1usize
    }
    if count == 0usize { ret f.blank() }
    var attr = ""
    var has_attr = false
    let last = segs[count - 1usize]
    if last.len > 1usize && last[0usize] == 64u8 {
        var plain = true
        var k = 1usize
        while k < last.len {
            if is_line_break(last[k]) { plain = false }
            k += 1usize
        }
        if plain {
            attr = last[1usize..last.len]
            has_attr = true
            count -= 1usize
        }
    }
    if count == 0usize {
        ret f.generic_error("Cannot read properties of undefined (reading 'match')")
    }
    let first = xml_seg(segs[0usize])
    if !str.eq(x.tags[0usize], first.tag) { ret f.blank() }
    let (current, ce) = mem.alloc[usize](c.a, x.count + 1usize)
    let (next, ne) = mem.alloc[usize](c.a, x.count + 1usize)
    if ce != ok || ne != ok { ret f.generic_error("Out of memory") }
    var current_n = 0usize
    if !first.indexed || first.index == 0.0f64 {
        current[0usize] = 0usize
        current_n = 1usize
    }
    var s = 1usize
    while s < count {
        let seg = xml_seg(segs[s])
        var next_n = 0usize
        var j = 0usize
        while j < current_n {
            var seen = 0.0f64
            var q = 1usize
            while q < x.count {
                if x.parent[q] == current[j] && str.eq(x.tags[q], seg.tag) {
                    if seg.indexed {
                        if seen == seg.index {
                            next[next_n] = q
                            next_n += 1usize
                        }
                        seen += 1.0f64
                    } else {
                        next[next_n] = q
                        next_n += 1usize
                    }
                }
                q += 1usize
            }
            j += 1usize
        }
        var m = 0usize
        while m < next_n {
            current[m] = next[m]
            m += 1usize
        }
        current_n = next_n
        s += 1usize
    }
    if current_n == 0usize { ret f.blank() }
    let out = values_of(c.a, current_n)
    var n = 0usize
    var j = 0usize
    while j < current_n {
        if has_attr {
            var found = false
            var value = ""
            var k = x.attr_count[current[j]]
            while k > 0usize && !found {
                k -= 1usize
                let slot = x.attr_from[current[j]] + k
                if str.eq(x.attr_names[slot], attr) {
                    value = x.attr_values[slot]
                    found = true
                }
            }
            if found {
                out[n] = f.text(value)
                n += 1usize
            }
        } else {
            out[n] = f.text(xml_text(c.a, &x, current[j]))
            n += 1usize
        }
        j += 1usize
    }
    if n == 0usize { ret f.blank() }
    if n == 1usize { ret out[0usize] }
    ret array_of(out, n)
}

// --- registration ------------------------------------------------------------------------------------------------

fn add(r: *f.Registry, a: *mem.Arena, name: str, aliases: []const str, category: str, lazy: bool, once: bool, volatile_fn: bool, low: i32, high: i32, handler: f.Handler) -> err {
    ret f.register(r, a, f.Entry { name: name, key: "", aliases: aliases, category: category, lazy: lazy, pass_errors: false, volatile_fn: volatile_fn, generate_once: once, min_args: low, max_args: high, handler: handler })
}

fn alias1(a: *mem.Arena, x: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 1usize)
    s[0usize] = x
    ret s
}

fn alias2(a: *mem.Arena, x: str, y: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 2usize)
    s[0usize] = x
    s[1usize] = y
    ret s
}

fn alias3(a: *mem.Arena, x: str, y: str, z: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 3usize)
    s[0usize] = x
    s[1usize] = y
    s[2usize] = z
    ret s
}

fn alias4(a: *mem.Arena, x: str, y: str, z: str, w: str) -> []const str {
    let (s, e) = mem.alloc[str](a, 4usize)
    s[0usize] = x
    s[1usize] = y
    s[2usize] = z
    s[3usize] = w
    ret s
}

// Register the random/hash/encode, array, reference and extraction functions.
fn register(r: *f.Registry, a: *mem.Arena) -> err {
    var none: []const str = zero
    let reh = "random-hash-encode"
    try add(r, a, "RANDOM", alias1(a, "RAND"), reh, false, true, false, 0i32, 2i32, h_random)
    try add(r, a, "UUID", alias1(a, "GUID"), reh, false, true, false, 0i32, 0i32, h_uuid)
    try add(r, a, "MD5", none, reh, false, false, false, 1i32, 1i32, h_md5)
    try add(r, a, "SHA1", none, reh, false, false, false, 1i32, 1i32, h_sha1)
    try add(r, a, "SHA256", none, reh, false, false, false, 1i32, 1i32, h_sha256)
    try add(r, a, "CRC32", none, reh, false, false, false, 1i32, 1i32, h_crc32)
    try add(r, a, "BASE64", none, reh, false, false, false, 1i32, 2i32, h_base64)
    try add(r, a, "URLENCODE", alias4(a, "ENCODE_URL", "ENCODEURL", "URL_ENCODE", "ENCODE_URL_COMPONENT"), reh, false, false, false, 1i32, 2i32, h_urlencode)
    try add(r, a, "GENERATEPASSWORD", alias1(a, "GENERATE_PASSWORD"), reh, false, true, false, 0i32, 2i32, h_generatepassword)
    try add(r, a, "MAP", alias1(a, "SELECT"), "array", true, false, false, 2i32, 2i32, h_map)
    try add(r, a, "FILTER", none, "array", true, false, false, 2i32, 2i32, h_filter)
    try add(r, a, "REDUCE", none, "array", true, false, false, 2i32, 3i32, h_reduce)
    try add(r, a, "SORT", none, "array", true, false, false, 1i32, 3i32, h_sort)
    try add(r, a, "ANY", alias1(a, "SOME"), "array", true, false, false, 1i32, 2i32, h_any)
    try add(r, a, "ALL", alias1(a, "EVERY"), "array", true, false, false, 1i32, 2i32, h_all)
    try add(r, a, "JOIN", alias1(a, "ARRAYJOIN"), "array", false, false, false, 1i32, 2i32, h_join)
    try add(r, a, "FLAT", alias2(a, "FLATTEN", "FLATTERN"), "array", false, false, false, 1i32, -1i32, h_flat)
    try add(r, a, "UNIQUE", alias1(a, "ARRAYUNIQUE"), "array", false, false, false, 1i32, -1i32, h_unique)
    try add(r, a, "COMPACT", alias1(a, "ARRAYCOMPACT"), "array", false, false, false, 1i32, -1i32, h_compact)
    try add(r, a, "COLLECT", none, "array", false, false, false, 3i32, 3i32, h_collect)
    try add(r, a, "GET", alias1(a, "NTH"), "array", false, false, false, 2i32, 2i32, h_get)
    try add(r, a, "FIRST", none, "array", false, false, false, 1i32, 1i32, h_first)
    try add(r, a, "LAST", none, "array", false, false, false, 1i32, 1i32, h_last)
    try add(r, a, "SPLIT", none, "array", false, false, false, 1i32, 3i32, h_split)
    try add(r, a, "SLICE", alias1(a, "ARRAYSLICE"), "array", false, false, false, 2i32, 3i32, h_slice)
    let rf = "reference"
    try add(r, a, "ROW", none, rf, false, false, false, 0i32, 0i32, h_row)
    try add(r, a, "ROWID", alias2(a, "RECORD_ID", "RECORDID"), rf, false, false, false, 0i32, 0i32, h_row)
    try add(r, a, "TABLEID", none, rf, false, false, false, 0i32, 0i32, h_tableid)
    try add(r, a, "APPID", none, rf, false, false, false, 0i32, 0i32, h_appid)
    try add(r, a, "REALMID", none, rf, false, false, false, 0i32, 0i32, h_realmid)
    try add(r, a, "USERID", none, rf, false, false, false, 0i32, 0i32, h_userid)
    try add(r, a, "CREATEDON", alias3(a, "CREATED_ON", "CREATED_TIME", "CREATEDTIME"), rf, false, false, false, 0i32, 0i32, h_createdon)
    try add(r, a, "UPDATEDON", alias4(a, "UPDATED_ON", "MODIFIEDON", "LAST_MODIFIED_TIME", "LASTMODIFIEDTIME"), rf, false, false, false, 0i32, 0i32, h_updatedon)
    try add(r, a, "CREATEDBY", alias1(a, "CREATED_BY"), rf, false, false, false, 0i32, 0i32, h_createdby)
    try add(r, a, "UPDATEDBY", alias2(a, "UPDATED_BY", "MODIFIEDBY"), rf, false, false, false, 0i32, 0i32, h_updatedby)
    try add(r, a, "BROWSERAGENT", alias1(a, "USERAGENT"), rf, false, false, false, 0i32, 0i32, h_browseragent)
    try add(r, a, "CURRENTUSER", alias3(a, "CURRENT_USER", "USER", "USERNAME"), rf, false, false, true, 0i32, 0i32, h_currentuser)
    try add(r, a, "GETRECORDS", none, rf, false, false, false, 1i32, 2i32, h_getrecords)
    try add(r, a, "GETFIELDVALUES", none, rf, false, false, false, 2i32, 3i32, h_getfieldvalues)
    try add(r, a, "CHILDREN", none, rf, false, false, false, 0i32, 1i32, h_children)
    try add(r, a, "ISNEW", none, rf, false, false, false, 0i32, 0i32, h_isnew)
    try add(r, a, "ISCHANGED", none, rf, false, false, false, 1i32, 1i32, h_ischanged)
    try add(r, a, "PRIORVALUE", alias1(a, "PRIOR_VALUE"), rf, false, false, false, 1i32, 1i32, h_priorvalue)
    try add(r, a, "ANCESTORS", none, rf, false, false, false, 0i32, 1i32, h_ancestors)
    try add(r, a, "NAME", none, rf, true, false, false, 1i32, 1i32, h_name)
    try add(r, a, "PROPERTY", none, rf, true, false, false, 2i32, 2i32, h_property)
    try add(r, a, "PROPERTIES", none, rf, true, false, false, 1i32, 1i32, h_properties)
    try add(r, a, "JSONQUERY", alias1(a, "JSON_QUERY"), "extraction", false, false, false, 2i32, 2i32, h_jsonquery)
    try add(r, a, "XMLQUERY", alias1(a, "XML_QUERY"), "extraction", false, false, false, 2i32, 2i32, h_xmlquery)
    ret ok
}
