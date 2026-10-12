// What generated protocol buffer message code stands on (L164): a growing output buffer that the generated `*_write`
// functions append keyed fields to, and the conversions between a varint's or fixed width's raw bits and the typed
// values a message struct holds. `e.net.grpcstub` writes code against this; reading uses `e.fmt.protobuf`'s reader
// directly.
//
// A nested message is written into its own `Out` and appended as one length-delimited field, so no size pass is needed;
// a packed list is the same with the raw values of `raw_*` and a key of its own. Field numbers are checked by the
// generator, not here.
//
// Memory: an `Out` grows by doubling inside its arena, which is retained; the bytes `out_bytes` answers are a view.
use e.mem

error TooLarge
error Invalid

type Out = struct { a: *mem.Arena, data: []u8, len: usize }

fn out_new(a: *mem.Arena) -> Out {
    let (data, e) = mem.alloc[u8](a, 64usize)
    if e != ok { ret Out { a: a, data: zero, len: 0usize } }
    ret Out { a: a, data: data, len: 0usize }
}

// The bytes written so far, as a view into the buffer.
fn out_bytes(o: *Out) -> []const u8 { ret o.data[0usize..o.len] }

fn reserve(o: *Out, extra: usize) -> err {
    if o.len + extra <= o.data.len { ret ok }
    var cap = o.data.len
    if cap < 64usize { cap = 64usize }
    while cap < o.len + extra {
        cap = cap * 2usize
        if cap > 2147483647usize { ret TooLarge }
    }
    let (grown, e) = mem.alloc[u8](o.a, cap)
    if e != ok { ret e }
    var i = 0usize
    while i < o.len {
        grown[i] = o.data[i]
        i += 1usize
    }
    o.data = grown
    ret ok
}

fn push_byte(o: *Out, v: u8) -> err {
    try reserve(o, 1usize)
    o.data[o.len] = v
    o.len += 1usize
    ret ok
}

fn push_bytes(o: *Out, v: []const u8) -> err {
    try reserve(o, v.len)
    var i = 0usize
    while i < v.len {
        o.data[o.len + i] = v[i]
        i += 1usize
    }
    o.len += v.len
    ret ok
}

// --- raw values (no key) ---------------------------------------------------------------------------------------------

fn raw_varint(o: *Out, value: u64) -> err {
    var v = value
    while v >= 128u64 {
        try push_byte(o, u8(v & 127u64) | 128u8)
        v = v >> 7u32
    }
    ret push_byte(o, u8(v))
}

// A signed value as int32, int64 or enum: negatives take ten bytes (two's complement).
fn raw_int(o: *Out, value: i64) -> err {
    if value >= 0i64 { ret raw_varint(o, u64(value)) }
    ret raw_varint(o, 18446744073709551615u64 - u64(0i64 - (value + 1i64)))
}

fn zigzag(value: i64) -> u64 {
    if value >= 0i64 { ret u64(value) << 1u32 }
    ret (u64(0i64 - (value + 1i64)) << 1u32) | 1u64
}

fn raw_sint(o: *Out, value: i64) -> err { ret raw_varint(o, zigzag(value)) }

fn raw_fixed32(o: *Out, value: u32) -> err {
    var i = 0u32
    while i < 4u32 {
        try push_byte(o, u8((value >> (i * 8u32)) & 255u32))
        i += 1u32
    }
    ret ok
}

fn raw_fixed64(o: *Out, value: u64) -> err {
    var i = 0u32
    while i < 8u32 {
        try push_byte(o, u8((value >> (i * 8u32)) & 255u64))
        i += 1u32
    }
    ret ok
}

// --- conversions -----------------------------------------------------------------------------------------------------

fn bits_f32(v: u32) -> f32 { ret mem.bitcast[f32](v) }

fn bits_f64(v: u64) -> f64 { ret mem.bitcast[f64](v) }

fn f32_bits(v: f32) -> u32 { ret mem.bitcast[u32](v) }

fn f64_bits(v: f64) -> u64 { ret mem.bitcast[u64](v) }

// The low 32 bits of a varint as a signed 32-bit value.
fn trunc_i32(raw: u64) -> i32 {
    let low = raw & 4294967295u64
    if low < 2147483648u64 { ret i32(low) }
    ret i32(0i64 - i64(4294967296u64 - low))
}

fn trunc_u32(raw: u64) -> u32 { ret u32(raw & 4294967295u64) }

fn from_zigzag(raw: u64) -> i64 {
    let magnitude = i64(raw >> 1u32)
    if raw & 1u64 == 1u64 { ret 0i64 - magnitude - 1i64 }
    ret magnitude
}

fn i32_from_bits(v: u32) -> i32 {
    if v < 2147483648u32 { ret i32(v) }
    ret i32(0i64 - i64(4294967296u64 - u64(v)))
}

fn i64_from_bits(v: u64) -> i64 {
    if v < 9223372036854775808u64 { ret i64(v) }
    ret 0i64 - i64(18446744073709551615u64 - v) - 1i64
}

fn bits_from_i32(v: i32) -> u32 {
    if v >= 0i32 { ret u32(v) }
    ret u32(4294967296i64 + i64(v))
}

fn bits_from_i64(v: i64) -> u64 {
    if v >= 0i64 { ret u64(v) }
    ret 18446744073709551615u64 - u64(0i64 - (v + 1i64))
}

// --- fields (key and value) ------------------------------------------------------------------------------------------

fn put_key(o: *Out, number: u32, wire: u32) -> err { ret raw_varint(o, (u64(number) << 3u32) | u64(wire)) }

fn put_varint(o: *Out, number: u32, value: u64) -> err {
    try put_key(o, number, 0u32)
    ret raw_varint(o, value)
}

fn put_int(o: *Out, number: u32, value: i64) -> err {
    try put_key(o, number, 0u32)
    ret raw_int(o, value)
}

fn put_sint(o: *Out, number: u32, value: i64) -> err {
    try put_key(o, number, 0u32)
    ret raw_sint(o, value)
}

fn put_bool(o: *Out, number: u32, value: bool) -> err {
    try put_key(o, number, 0u32)
    if value { ret push_byte(o, 1u8) }
    ret push_byte(o, 0u8)
}

fn put_fixed32(o: *Out, number: u32, value: u32) -> err {
    try put_key(o, number, 5u32)
    ret raw_fixed32(o, value)
}

fn put_fixed64(o: *Out, number: u32, value: u64) -> err {
    try put_key(o, number, 1u32)
    ret raw_fixed64(o, value)
}

fn put_bytes(o: *Out, number: u32, value: []const u8) -> err {
    if value.len > 2147483647usize { ret TooLarge }
    try put_key(o, number, 2u32)
    try raw_varint(o, u64(value.len))
    ret push_bytes(o, value)
}

// A nested message (or a packed list) written into `child` as a length-delimited field.
fn put_message(o: *Out, number: u32, child: *const Out) -> err {
    try put_key(o, number, 2u32)
    try raw_varint(o, u64(child.len))
    ret push_bytes(o, child.data[0usize..child.len])
}

// --- reading ---------------------------------------------------------------------------------------------------------

// The `length` bytes at the reader's position as a view of `source`, given how many bytes were left (a function of
// values only, so the views a decoder keeps are not tied to the reader it goes on mutating). The caller skips them.
fn view_of(source: []const u8, remaining: usize, length: u64) -> ([]const u8, err) {
    if length > u64(remaining) { ret (zero, Invalid) }
    let from = source.len - remaining
    ret (source[from..from + usize(length)], ok)
}
