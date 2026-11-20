// Binary S-PLUS object reader as foreign::read.S reads it: the 8 bytes "\0S data\1", an int code and an int length, then the data. Codes 1 logical, 2 integer
// (both int32), 3 single, 4 double, 5 character (a byte count, then the null-terminated strings), 6 list (the names as a character block, then int arrays of
// the element codes, lengths and absolute file offsets), 21 structure (a list whose .Data, .Dim and .Label members make the object). The byte order is little-endian
// unless the first code is out of range (0 to 65535), when it is big-endian, and an error when it is out of range both ways.
//
// parse() gives the same summary as e.fmt.sdump (length, sum, position-weighted sum, NAs, levels, dim, names, type). Code 7 is complex (two doubles each), codes
// 257 to 321 the S language modes (built as sdump builds them), an element code of 0 or less a name, and a code R does not know the message string R answers
// with. A .Tsp member is an attribute here, as in read.S. Duplicate member names are refused with Unsupported.

use e.fmt.sdump as sd
use e.mem
use e.str

error Malformed
error Unsupported

type R = struct { t: str, be: bool, bad: u8 }

fn u32_at(r: *R, at: usize) -> i64 {
    if at + 4usize > r.t.len {
        r.bad = 1u8
        ret 0i64
    }
    var u = 0u64
    var k = 0usize
    while k < 4usize {
        var b = r.t[at + k]
        if r.be { b = r.t[at + 3usize - k] }
        u = u | (u64(b) << u64(8usize * k))
        k += 1usize
    }
    var v = i64(u)
    if v >= 2147483648i64 { v = v - 4294967296i64 }
    ret v
}

fn u64_at(r: *R, at: usize) -> u64 {
    if at + 8usize > r.t.len {
        r.bad = 1u8
        ret 0u64
    }
    var v = 0u64
    var k = 0usize
    while k < 8usize {
        var b = r.t[at + k]
        if r.be { b = r.t[at + 7usize - k] }
        v = v | (u64(b) << u64(8usize * k))
        k += 1usize
    }
    ret v
}

fn fail(r: *R, why: u8) -> sd.Item {
    var it: sd.Item = zero
    if r.bad == 0u8 { r.bad = why }
    ret it
}

fn code_sum(x: str) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += f64(x[i])
        i += 1usize
    }
    ret s
}

// the strings of a character block at `at`: the offset after them, and count of strings; the strings go to out when it is not empty
fn chars(r: *R, at: usize, len: usize, out: []str) -> usize {
    let size = u32_at(r, at)
    if r.bad != 0u8 || size < 0i64 { ret 0usize }
    var p = at + 4usize
    var k = 0usize
    while k < len {
        var e = p
        while e < r.t.len && r.t[e] != 0u8 { e += 1usize }
        if e >= r.t.len {
            r.bad = 1u8
            ret 0usize
        }
        if k < out.len { out[k] = r.t[p..e] }
        p = e + 1usize
        k += 1usize
    }
    ret at + 4usize + usize(size)
}

// an atomic object of code 1 to 4 (logical, integer, single, double) or 7 (complex) at `at`
fn atomic(r: *R, at: usize, code: i64, len: usize) -> sd.Item {
    var it: sd.Item = zero
    it.len = len
    it.prod = 1.0f64
    if code == 7i64 { it.ty = 1u8 }
    var i = 0usize
    while i < len && r.bad == 0u8 {
        var na = false
        var v = 0.0f64
        var iv = 0.0f64
        if code == 1i64 || code == 2i64 {
            let x = u32_at(r, at + 4usize * i)
            if x == 0i64 - 2147483648i64 {
                na = true
            } else if code == 1i64 {
                if x != 0i64 { v = 1.0f64 }
            } else {
                v = f64(x)
            }
        } else if code == 3i64 {
            let bits = u32_at(r, at + 4usize * i)
            var ub = bits
            if ub < 0i64 { ub = ub + 4294967296i64 }
            v = f64(mem.bitcast[f32](u32(ub)))
            if v != v { na = true }
        } else if code == 4i64 {
            v = mem.bitcast[f64](u64_at(r, at + 8usize * i))
            if v != v { na = true }
        } else {
            v = mem.bitcast[f64](u64_at(r, at + 16usize * i))
            iv = mem.bitcast[f64](u64_at(r, at + 16usize * i + 8usize))
            if v != v || iv != iv { na = true }
        }
        if na {
            it.nna += 1usize
        } else {
            it.sum += v
            it.wsum += v * f64(i + 1usize)
            it.isum += iv
            it.prod = it.prod * v
        }
        i += 1usize
    }
    ret it
}

// the character object at `at`: its summary and its first string
fn char_obj(r: *R, a: *mem.Arena, len: usize, at: usize) -> (sd.Item, str) {
    var it: sd.Item = zero
    it.kind = 1u8
    it.len = len
    let (ss, se) = mem.alloc[str](a, len + 1usize)
    if se != ok {
        r.bad = 2u8
        ret (it, "")
    }
    let _ = chars(r, at, len, ss[0usize..len])
    if r.bad != 0u8 {
        r.bad = 1u8
        ret (it, "")
    }
    var i = 0usize
    while i < len {
        it.sum += code_sum(ss[i])
        it.wsum += code_sum(ss[i]) * f64(i + 1usize)
        i += 1usize
    }
    var first = ""
    if len > 0usize { first = ss[0usize] }
    ret (it, first)
}

// what ReadSObj answers for a code it does not know: the message as a one-string character vector
fn unknown_mode(r: *R, a: *mem.Arena, code: i64) -> sd.Item {
    var it: sd.Item = zero
    let (b, e) = str.builder(a, 64usize)
    if e != ok {
        r.bad = 2u8
        ret it
    }
    var bb = b
    let _ = str.push(&bb, "Unrecognized S mode ")
    let _ = str.push_i64(&bb, code)
    let _ = str.push(&bb, " not supported")
    let msg = str.done(&bb)
    it.kind = 1u8
    it.len = 1usize
    it.sum = code_sum(msg)
    it.wsum = it.sum
    ret it
}

fn read_obj(r: *R, a: *mem.Arena, code: i64, len: usize, at: usize) -> sd.Item {
    if (code >= 1i64 && code <= 4i64) || code == 7i64 { ret atomic(r, at, code, len) }
    if code == 5i64 {
        let (it, _) = char_obj(r, a, len, at)
        ret it
    }
    var lang = false
    var smode = ""
    if code >= 257i64 && code <= 321i64 {
        lang = true
        smode = sd.smode_name(usize(code - 257i64))
    }
    if code != 6i64 && code != 21i64 && !lang { ret unknown_mode(r, a, code) }
    if lang && (str.eq(smode, "name") || str.eq(smode, "missing")) {
        let (it, first) = char_obj(r, a, len, at)
        if r.bad != 0u8 { ret it }
        if str.eq(smode, "missing") { ret sd.mk("", 4u8, 2usize) }
        if len == 0usize || first.len == 0usize { ret it }
        ret sd.mk("", 2u8, 1usize)
    }
    let (names, ne) = mem.alloc[str](a, len + 1usize)
    if ne != ok { ret fail(r, 2u8) }
    let after = chars(r, at, len, names[0usize..len])
    if r.bad != 0u8 { ret fail(r, 1u8) }
    let (kids, ke) = mem.alloc[sd.Item](a, len + 1usize)
    if ke != ok { ret fail(r, 2u8) }
    let codes_at = after
    let lens_at = after + 4usize * len
    let offs_at = after + 8usize * len
    var i = 0usize
    while i < len && r.bad == 0u8 {
        let ec = u32_at(r, codes_at + 4usize * i)
        let el = u32_at(r, lens_at + 4usize * i)
        let eo = u32_at(r, offs_at + 4usize * i)
        if r.bad != 0u8 { break }
        if ec <= 0i64 {
            // as.name(names[i]); an empty name stops R
            if names[i].len == 0usize { ret fail(r, 1u8) }
            kids[i] = sd.mk(names[i], 2u8, 1usize)
        } else {
            if el < 0i64 || eo < 0i64 { ret fail(r, 1u8) }
            kids[i] = read_obj(r, a, ec, usize(el), usize(eo))
            kids[i].name = names[i]
        }
        i += 1usize
    }
    if r.bad != 0u8 { ret fail(r, 1u8) }
    let (lv, ls) = sd.list_value(a, kids[0usize..len])
    if ls != 0u8 { ret fail(r, ls) }
    if code == 6i64 { ret sd.list_item("", lv) }
    var res: sd.Item = zero
    var st = 0u8
    if code == 21i64 {
        let (x, s2) = sd.structure_value(a, "", lv, false)
        res = x
        st = s2
    } else {
        let (x, s2) = sd.apply_code("", smode, lv)
        res = x
        st = s2
    }
    if st != 0u8 { ret fail(r, st) }
    ret res
}

fn parse(a: *mem.Arena, t: str) -> (sd.Item, err) {
    var out: sd.Item = zero
    var r: R = zero
    r.t = t
    if t.len < 16usize { ret (out, Malformed) }
    // "\0S data\1"
    if t[0usize] != 0u8 || t[1usize] != 83u8 || t[2usize] != 32u8 || t[3usize] != 100u8 || t[4usize] != 97u8 || t[5usize] != 116u8 || t[6usize] != 97u8 || t[7usize] != 1u8 { ret (out, Malformed) }
    var code = u32_at(&r, 8usize)
    if code < 0i64 || code > 65535i64 {
        r.be = true
        code = u32_at(&r, 8usize)
        if code < 0i64 || code > 65535i64 { ret (out, Malformed) }
    }
    let len = u32_at(&r, 12usize)
    if r.bad != 0u8 || len < 0i64 { ret (out, Malformed) }
    out = read_obj(&r, a, code, usize(len), 16usize)
    if r.bad == 1u8 { ret (out, Malformed) }
    if r.bad != 0u8 { ret (out, Unsupported) }
    ret (out, ok)
}
