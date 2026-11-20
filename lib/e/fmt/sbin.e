// Binary S-PLUS object reader as foreign::read.S reads it: the 8 bytes "\0S data\1", an int code and an int length, then the data. Codes 1 logical, 2 integer
// (both int32), 3 single, 4 double, 5 character (a byte count, then the null-terminated strings), 6 list (the names as a character block, then int arrays of
// the element codes, lengths and absolute file offsets), 21 structure (a list whose .Data, .Dim and .Label members make the object). The byte order is little-endian
// unless the first code is out of range (0 to 65535), when it is big-endian, and an error when it is out of range both ways.
//
// parse() gives the same summary as e.fmt.sdump (length, sum, position-weighted sum, NAs, levels, dim, names). Complex values, S language modes (codes 257 to 321),
// an element code of 0 or less (a name) and a code R does not know are refused with Unsupported (R returns a message for the last); duplicate member names too.

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

// an atomic object of code 1 to 4 at `at`
fn atomic(r: *R, at: usize, code: i64, len: usize) -> sd.Item {
    var it: sd.Item = zero
    it.len = len
    it.prod = 1.0f64
    var i = 0usize
    while i < len && r.bad == 0u8 {
        var na = false
        var v = 0.0f64
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
        } else {
            v = mem.bitcast[f64](u64_at(r, at + 8usize * i))
            if v != v { na = true }
        }
        if na {
            it.nna += 1usize
        } else {
            it.sum += v
            it.wsum += v * f64(i + 1usize)
            it.prod = it.prod * v
        }
        i += 1usize
    }
    ret it
}

fn read_obj(r: *R, a: *mem.Arena, code: i64, len: usize, at: usize) -> sd.Item {
    if code >= 1i64 && code <= 4i64 { ret atomic(r, at, code, len) }
    if code == 5i64 {
        var it: sd.Item = zero
        it.kind = 1u8
        it.len = len
        let (ss, se) = mem.alloc[str](a, len + 1usize)
        if se != ok { ret fail(r, 2u8) }
        let _ = chars(r, at, len, ss[0usize..len])
        if r.bad != 0u8 { ret fail(r, 1u8) }
        var i = 0usize
        while i < len {
            it.sum += code_sum(ss[i])
            it.wsum += code_sum(ss[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret it
    }
    if code != 6i64 && code != 21i64 {
        if code == 7i64 || (code >= 257i64 && code <= 321i64) { ret fail(r, 2u8) }
        ret fail(r, 2u8)
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
        if ec <= 0i64 { ret fail(r, 2u8) }
        if el < 0i64 || eo < 0i64 { ret fail(r, 1u8) }
        kids[i] = read_obj(r, a, ec, usize(el), usize(eo))
        kids[i].name = names[i]
        i += 1usize
    }
    if r.bad != 0u8 { ret fail(r, 1u8) }
    var named = false
    i = 0usize
    while i < len {
        if names[i].len > 0usize {
            named = true
            var j = 0usize
            while j < i {
                if str.eq(names[j], names[i]) { ret fail(r, 2u8) }
                j += 1usize
            }
        }
        i += 1usize
    }
    var it: sd.Item = zero
    if code == 6i64 {
        it.kind = 2u8
        it.len = len
        i = 0usize
        while i < len {
            it.sum += kids[i].sum
            it.wsum += kids[i].wsum
            it.nna += kids[i].nna
            if named { it.elh += code_sum(names[i]) * f64(i + 1usize) }
            i += 1usize
        }
        if named { it.nnames = len }
        ret it
    }
    var di = len
    var dim_i = len
    var lab_i = len
    i = 0usize
    while i < len {
        if str.eq(names[i], ".Data") { di = i }
        if str.eq(names[i], ".Dim") { dim_i = i }
        if str.eq(names[i], ".Label") { lab_i = i }
        if str.eq(names[i], ".Tsp") { ret fail(r, 2u8) }
        i += 1usize
    }
    if di == len { ret fail(r, 1u8) }
    it = kids[di]
    if lab_i < len {
        it.nlev = kids[lab_i].len
        it.levs = kids[lab_i].sum
    }
    if dim_i < len {
        let dm = kids[dim_i]
        if dm.nna > 0usize || dm.prod != f64(kids[di].len) { ret fail(r, 1u8) }
        it.ndim = dm.len
        it.dimprod = dm.prod
    }
    ret it
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
