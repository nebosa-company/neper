// A bincode-style compact binary codec: no field names, no type tags, the schema lives in
// the code that writes and reads. Two configurations, the two bincode ships:
//
// - `legacy()` is bincode 1's default: fixed-width integers, little endian, lengths and
//   enum variant indexes as u64 and u32.
// - `standard()` is bincode 2's `config::standard()`: little endian with variable-length
//   integers. An unsigned value under 251 is one byte; otherwise a marker byte (251 u16,
//   252 u32, 253 u64) and that many bytes. Signed values are zigzag-mapped first. `u8`/`i8`
//   are always one byte, bool one byte, floats fixed width.
//
// `big` selects big-endian bytes for fixed fields and variable-length payloads. A string
// or byte run is its length (as a u64 in the configuration's integer encoding) then the
// bytes; an option is a 0/1 byte then the value; an enum is its u32 variant index then the
// variant's fields. Struct and tuple fields are written back to back.
//
// A `Writer` into a too-small buffer, or a `Reader` past its end or on a bad tag, sets
// `bad` and every later call is a no-op returning zero, so a whole record can be written
// or read and checked once. Variable-length decoding accepts any marker width (overlong
// forms included), as bincode does.

use e.mem

type Config = struct { varint: bool, big: bool }
type Writer = struct { dst: []u8, n: usize, cfg: Config, bad: bool }
type Reader = struct { src: []const u8, at: usize, cfg: Config, bad: bool }
error Short
error Invalid

fn legacy() -> Config {
    var c: Config = zero
    ret c
}

fn standard() -> Config {
    var c: Config = zero
    c.varint = true
    ret c
}

fn writer(dst: []u8, cfg: Config) -> Writer {
    var w: Writer = zero
    w.dst = dst
    w.cfg = cfg
    ret w
}

fn reader(src: []const u8, cfg: Config) -> Reader {
    var r: Reader = zero
    r.src = src
    r.cfg = cfg
    ret r
}

fn written(w: *const Writer) -> []const u8 { ret w.dst[..w.n] }

fn failed(w: *const Writer) -> err {
    if w.bad { ret Short }
    ret ok
}

fn read_failed(r: *const Reader) -> err {
    if r.bad { ret Short }
    ret ok
}

fn put_byte(w: *Writer, b: u8) {
    if w.bad || w.n >= w.dst.len {
        w.bad = true
        ret
    }
    w.dst[w.n] = b
    w.n += 1usize
}

fn put_raw(w: *Writer, v: u64, width: usize) {
    var i = 0usize
    while i < width {
        var shift = u64(i) * 8u64
        if w.cfg.big { shift = u64(width - 1usize - i) * 8u64 }
        put_byte(w, u8((v >> shift) & 255u64))
        i += 1usize
    }
}

fn put_uvar(w: *Writer, v: u64) {
    if v < 251u64 {
        put_byte(w, u8(v))
    } else if v <= 65535u64 {
        put_byte(w, 251u8)
        put_raw(w, v, 2usize)
    } else if v <= 4294967295u64 {
        put_byte(w, 252u8)
        put_raw(w, v, 4usize)
    } else {
        put_byte(w, 253u8)
        put_raw(w, v, 8usize)
    }
}

fn zigzag(v: i64) -> u64 {
    if v >= 0i64 { ret u64(v) * 2u64 }
    ret u64(0i64 - (v + 1i64)) * 2u64 + 1u64
}

fn unzigzag(u: u64) -> i64 {
    if u % 2u64 == 0u64 { ret i64(u / 2u64) }
    ret 0i64 - i64(u / 2u64) - 1i64
}

fn put_u8(w: *Writer, v: u8) { put_byte(w, v) }

fn put_bool(w: *Writer, v: bool) {
    if v {
        put_byte(w, 1u8)
    } else {
        put_byte(w, 0u8)
    }
}

fn put_i8(w: *Writer, v: i8) {
    var b = 0u8
    if v >= 0i8 {
        b = u8(v)
    } else {
        b = u8(256i64 + i64(v))
    }
    put_byte(w, b)
}

fn put_u16(w: *Writer, v: u16) {
    if w.cfg.varint {
        put_uvar(w, u64(v))
    } else {
        put_raw(w, u64(v), 2usize)
    }
}

fn put_u32(w: *Writer, v: u32) {
    if w.cfg.varint {
        put_uvar(w, u64(v))
    } else {
        put_raw(w, u64(v), 4usize)
    }
}

fn put_u64(w: *Writer, v: u64) {
    if w.cfg.varint {
        put_uvar(w, v)
    } else {
        put_raw(w, v, 8usize)
    }
}

fn put_signed(w: *Writer, v: i64, width: usize) {
    if w.cfg.varint {
        put_uvar(w, zigzag(v))
        ret
    }
    var raw = 0u64
    if v >= 0i64 {
        raw = u64(v)
    } else if width == 8usize {
        raw = u64(0i64 - (v + 1i64)) ^ 18446744073709551615u64
    } else {
        // two's complement at `width` bytes
        raw = (1u64 << (u64(width) * 8u64)) - u64(0i64 - v)
    }
    put_raw(w, raw, width)
}

fn put_i16(w: *Writer, v: i16) { put_signed(w, i64(v), 2usize) }

fn put_i32(w: *Writer, v: i32) { put_signed(w, i64(v), 4usize) }

fn put_i64(w: *Writer, v: i64) { put_signed(w, v, 8usize) }

fn put_f32(w: *Writer, v: f32) { put_raw(w, u64(mem.bitcast[u32](v)), 4usize) }

fn put_f64(w: *Writer, v: f64) { put_raw(w, mem.bitcast[u64](v), 8usize) }

fn put_len(w: *Writer, n: usize) { put_u64(w, u64(n)) }

fn put_bytes(w: *Writer, b: []const u8) {
    put_len(w, b.len)
    var i = 0usize
    while i < b.len {
        put_byte(w, b[i])
        i += 1usize
    }
}

fn put_str(w: *Writer, s: str) {
    put_len(w, s.len)
    var i = 0usize
    while i < s.len {
        put_byte(w, s[i])
        i += 1usize
    }
}

fn put_option(w: *Writer, some: bool) { put_bool(w, some) }

fn put_variant(w: *Writer, index: u32) { put_u32(w, index) }

// ---- reading ----

fn get_byte(r: *Reader) -> u8 {
    if r.bad || r.at >= r.src.len {
        r.bad = true
        ret 0u8
    }
    let b = r.src[r.at]
    r.at += 1usize
    ret b
}

fn get_raw(r: *Reader, width: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < width {
        let b = u64(get_byte(r))
        if r.cfg.big {
            v = v * 256u64 + b
        } else {
            v = v + (b << (u64(i) * 8u64))
        }
        i += 1usize
    }
    ret v
}

fn get_uvar(r: *Reader) -> u64 {
    let tag = get_byte(r)
    if tag < 251u8 { ret u64(tag) }
    if tag == 251u8 { ret get_raw(r, 2usize) }
    if tag == 252u8 { ret get_raw(r, 4usize) }
    if tag == 253u8 { ret get_raw(r, 8usize) }
    r.bad = true
    ret 0u64
}

fn get_u8(r: *Reader) -> u8 { ret get_byte(r) }

fn get_bool(r: *Reader) -> bool {
    let b = get_byte(r)
    if b > 1u8 { r.bad = true }
    ret b == 1u8
}

fn get_i8(r: *Reader) -> i8 {
    let b = get_byte(r)
    if b < 128u8 { ret i8(b) }
    ret i8(i64(b) - 256i64)
}

fn get_u16(r: *Reader) -> u16 {
    var v = 0u64
    if r.cfg.varint {
        v = get_uvar(r)
    } else {
        v = get_raw(r, 2usize)
    }
    if v > 65535u64 {
        r.bad = true
        ret 0u16
    }
    ret u16(v)
}

fn get_u32(r: *Reader) -> u32 {
    var v = 0u64
    if r.cfg.varint {
        v = get_uvar(r)
    } else {
        v = get_raw(r, 4usize)
    }
    if v > 4294967295u64 {
        r.bad = true
        ret 0u32
    }
    ret u32(v)
}

fn get_u64(r: *Reader) -> u64 {
    if r.cfg.varint { ret get_uvar(r) }
    ret get_raw(r, 8usize)
}

fn get_signed(r: *Reader, width: usize) -> i64 {
    if r.cfg.varint { ret unzigzag(get_uvar(r)) }
    let raw = get_raw(r, width)
    if width == 8usize {
        if raw < 9223372036854775808u64 { ret i64(raw) }
        ret 0i64 - i64(18446744073709551615u64 - raw) - 1i64
    }
    let half = 1u64 << (u64(width) * 8u64 - 1u64)
    if raw < half { ret i64(raw) }
    ret i64(raw) - i64(half * 2u64)
}

fn get_i16(r: *Reader) -> i16 {
    let v = get_signed(r, 2usize)
    if v < -32768i64 || v > 32767i64 {
        r.bad = true
        ret 0i16
    }
    ret i16(v)
}

fn get_i32(r: *Reader) -> i32 {
    let v = get_signed(r, 4usize)
    if v < -2147483648i64 || v > 2147483647i64 {
        r.bad = true
        ret 0i32
    }
    ret i32(v)
}

fn get_i64(r: *Reader) -> i64 { ret get_signed(r, 8usize) }

fn get_f32(r: *Reader) -> f32 { ret mem.bitcast[f32](u32(get_raw(r, 4usize))) }

fn get_f64(r: *Reader) -> f64 { ret mem.bitcast[f64](get_raw(r, 8usize)) }

fn get_len(r: *Reader) -> usize {
    let n = get_u64(r)
    if n > u64(r.src.len - r.at) {
        r.bad = true
        ret 0usize
    }
    ret usize(n)
}

// The next run's bytes, borrowed from the input (valid as long as it is).
fn get_bytes(r: *Reader) -> []const u8 {
    let n = get_len(r)
    if r.bad { ret r.src[0usize..0usize] }
    let out = r.src[r.at..r.at + n]
    r.at += n
    ret out
}

fn get_str(r: *Reader) -> str {
    let n = get_len(r)
    if r.bad { ret "" }
    let out = r.src[r.at..r.at + n]
    r.at += n
    ret out
}

fn get_option(r: *Reader) -> bool { ret get_bool(r) }

fn get_variant(r: *Reader) -> u32 { ret get_u32(r) }

fn at_end(r: *const Reader) -> bool { ret r.at == r.src.len }
