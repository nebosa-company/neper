// Protocol Buffers wire format, the primitives generated message code is built on:
// keys, varints in the three signednesses, the fixed widths and length-delimited
// fields, read from a `bytes.Reader` over the source and written to an `io.Writer`.
// A varint over ten bytes, a key of wire type 3, 4 or above 5, and a field number
// outside 1..536870911 or inside 19000..19999 are `Invalid`; bytes past the source
// are `Invalid` too, and a length that no encoding reaches is `TooLarge`. Cardinality,
// required fields, depth, packing and oneofs are the generated code's to enforce.
use e.bytes
use e.io

type WireType = enum u8 { Varint, Fixed64, Bytes, Fixed32 }
type Key = struct { number: u32, wire: WireType }
type Reader = struct { input: bytes.Reader }
error Invalid
error TooLarge

fn reader(source: []const u8) -> Reader {
    ret Reader { input: bytes.reader(source) }
}

fn number_legal(number: u32) -> bool {
    if number < 1u32 || number > 536870911u32 { ret false }
    if number >= 19000u32 && number <= 19999u32 { ret false }
    ret true
}

fn wire_code(wire: WireType) -> u32 {
    if wire == .Fixed64 { ret 1u32 }
    if wire == .Bytes { ret 2u32 }
    if wire == .Fixed32 { ret 5u32 }
    ret 0u32
}

// The next field key; `false` at the end of the source.
fn reader_next_err(r: *Reader) -> (Key, bool, err) {
    if bytes.remaining_reader(&r.input) == 0usize { ret (zero, false, ok) }
    let (raw, raw_error) = read_u64(r)
    if raw_error != ok { ret (zero, false, raw_error) }
    if raw > 4294967295u64 { ret (zero, false, Invalid) }
    let code = u32(raw & 7u64)
    let number = u32(raw >> 3u32)
    if !number_legal(number) { ret (zero, false, Invalid) }
    var key: Key = zero
    key.number = number
    if code == 0u32 { key.wire = .Varint }
    if code == 1u32 { key.wire = .Fixed64 }
    if code == 2u32 { key.wire = .Bytes }
    if code == 5u32 { key.wire = .Fixed32 }
    if code == 3u32 || code == 4u32 || code > 5u32 { ret (zero, false, Invalid) }
    ret (key, true, ok)
}

fn read_u64(r: *Reader) -> (u64, err) {
    var value = 0u64
    var shift = 0u32
    var count = 0usize
    while true {
        if count == 10usize { ret (0u64, Invalid) }
        let (piece, piece_error) = bytes.read_bytes(&r.input, 1usize)
        if piece_error != ok { ret (0u64, Invalid) }
        let byte = piece[0]
        if count == 9usize && byte > 1u8 { ret (0u64, Invalid) }
        value = value | (u64(byte & 127u8) << shift)
        count += 1usize
        if byte & 128u8 == 0u8 { break }
        shift += 7u32
    }
    ret (value, ok)
}

fn read_i64(r: *Reader) -> (i64, err) {
    let (raw, raw_error) = read_u64(r)
    ret (twos_complement(raw), raw_error)
}

fn twos_complement(raw: u64) -> i64 {
    // Two's complement through the wrapping subtraction, no bitcast needed.
    if raw < 9223372036854775808u64 { ret i64(raw) }
    ret 0i64 - i64(18446744073709551615u64 - raw) - 1i64
}

fn read_sint64(r: *Reader) -> (i64, err) {
    let (raw, raw_error) = read_u64(r)
    if raw_error != ok { ret (0i64, raw_error) }
    let magnitude = i64(raw >> 1u32)
    if raw & 1u64 == 1u64 { ret (0i64 - magnitude - 1i64, ok) }
    ret (magnitude, ok)
}

fn read_fixed32(r: *Reader) -> (u32, err) {
    let (value, read_error) = bytes.read[u32](&r.input, .Little)
    if read_error != ok { ret (0u32, Invalid) }
    ret (value, ok)
}

fn read_fixed64(r: *Reader) -> (u64, err) {
    let (value, read_error) = bytes.read[u64](&r.input, .Little)
    if read_error != ok { ret (0u64, Invalid) }
    ret (value, ok)
}

fn read_bytes(r: *Reader) -> ([]const u8, err) {
    let (length, length_error) = read_u64(r)
    if length_error != ok { ret (zero, length_error) }
    if length > u64(bytes.remaining_reader(&r.input)) { ret (zero, Invalid) }
    let (taken, taken_error) = bytes.read_bytes(&r.input, usize(length))
    if taken_error != ok { ret (zero, Invalid) }
    ret (taken, ok)
}

fn skip(r: *Reader, wire: WireType) -> err {
    if wire == .Varint {
        let (value, value_error) = read_u64(r)
        ret value_error
    }
    if wire == .Bytes {
        let (data, data_error) = read_bytes(r)
        ret data_error
    }
    var width = 4usize
    if wire == .Fixed64 { width = 8usize }
    if bytes.skip(&r.input, width) != ok { ret Invalid }
    ret ok
}

fn size_varint(value: u64) -> usize {
    var count = 1usize
    var v = value >> 7u32
    while v > 0u64 {
        count += 1usize
        v = v >> 7u32
    }
    ret count
}

fn size_key(number: u32, wire: WireType) -> (usize, err) {
    if !number_legal(number) { ret (0usize, Invalid) }
    ret (size_varint(u64(number) << 3u32), ok)
}

fn size_bytes(n: usize) -> (usize, err) {
    if n > 2147483647usize { ret (0usize, TooLarge) }
    ret (size_varint(u64(n)) + n, ok)
}

fn write_u64(w: *io.Writer, value: u64) -> err {
    var raw: [10]u8 = zero
    var count = 0usize
    var v = value
    while v >= 128u64 {
        raw[count] = u8(v & 127u64) | 128u8
        v = v >> 7u32
        count += 1usize
    }
    raw[count] = u8(v)
    count += 1usize
    ret io.write_all(w, raw[..count])
}

fn write_key(w: *io.Writer, number: u32, wire: WireType) -> err {
    if !number_legal(number) { ret Invalid }
    ret write_u64(w, (u64(number) << 3u32) | u64(wire_code(wire)))
}

fn write_i64(w: *io.Writer, value: i64) -> err {
    if value >= 0i64 { ret write_u64(w, u64(value)) }
    // The ten-byte two's complement form.
    ret write_u64(w, 18446744073709551615u64 - u64(0i64 - value - 1i64))
}

fn write_sint64(w: *io.Writer, value: i64) -> err {
    if value >= 0i64 { ret write_u64(w, u64(value) << 1u32) }
    ret write_u64(w, (u64(0i64 - value - 1i64) << 1u32) | 1u64)
}

fn write_fixed32(w: *io.Writer, value: u32) -> err {
    var raw: [4]u8 = zero
    var i = 0usize
    while i < 4usize {
        raw[i] = u8((value >> u32(i * 8usize)) & 255u32)
        i += 1usize
    }
    ret io.write_all(w, raw[0..])
}

fn write_fixed64(w: *io.Writer, value: u64) -> err {
    var raw: [8]u8 = zero
    var i = 0usize
    while i < 8usize {
        raw[i] = u8((value >> u32(i * 8usize)) & 255u64)
        i += 1usize
    }
    ret io.write_all(w, raw[0..])
}

fn write_bytes(w: *io.Writer, value: []const u8) -> err {
    if value.len > 2147483647usize { ret TooLarge }
    try write_u64(w, u64(value.len))
    ret io.write_all(w, value)
}

// --- The planned name `decode`: a schema-less walk of the top-level fields into
// caller storage, each as its number, wire type and raw value -- the varint as it
// came (`decode_zigzag` for sint fields), a fixed width in `fixed`, the bytes of a
// length-delimited field (a nested message stays bytes) -- and `encode` writing such
// a list back. More fields than `fields` holds is `io.TooSmall`.

type Field = struct { number: u32, wire: WireType, varint: u64, fixed: u64, data: []const u8 }

fn decode(source: []const u8, fields: []Field) -> (usize, err) {
    var r = reader(source)
    var count = 0usize
    while true {
        let (key, more, key_error) = reader_next_err(&r)
        if key_error != ok { ret (count, key_error) }
        if !more { ret (count, ok) }
        if count >= fields.len { ret (count, io.TooSmall) }
        var field: Field = zero
        field.number = key.number
        field.wire = key.wire
        if key.wire == .Varint {
            let (value, value_error) = read_u64(&r)
            if value_error != ok { ret (count, value_error) }
            field.varint = value
        }
        if key.wire == .Fixed32 {
            let (value, value_error) = read_fixed32(&r)
            if value_error != ok { ret (count, value_error) }
            field.fixed = u64(value)
        }
        if key.wire == .Fixed64 {
            let (value, value_error) = read_fixed64(&r)
            if value_error != ok { ret (count, value_error) }
            field.fixed = value
        }
        if key.wire == .Bytes {
            let (data, data_error) = read_bytes(&r)
            if data_error != ok { ret (count, data_error) }
            field.data = data
        }
        fields[count] = field
        count += 1usize
    }
}

// One varint from the front of `source`: its value and the bytes it took.
fn decode_varint(source: []const u8) -> (u64, usize, err) {
    var r = reader(source)
    let (value, value_error) = read_u64(&r)
    if value_error != ok { ret (0u64, 0usize, value_error) }
    ret (value, source.len - bytes.remaining_reader(&r.input), ok)
}

// The zigzag mapping undone: 0, 1, 2, 3 are 0, -1, 1, -2.
fn decode_zigzag(raw: u64) -> i64 {
    let magnitude = i64(raw >> 1u32)
    if raw & 1u64 == 1u64 { ret 0i64 - magnitude - 1i64 }
    ret magnitude
}

fn encode_zigzag(value: i64) -> u64 {
    if value >= 0i64 { ret u64(value) << 1u32 }
    ret (u64(0i64 - value - 1i64) << 1u32) | 1u64
}

fn encode(w: *io.Writer, fields: []const Field) -> err {
    var i = 0usize
    while i < fields.len {
        let f = fields[i]
        try write_key(w, f.number, f.wire)
        if f.wire == .Varint { try write_u64(w, f.varint) }
        if f.wire == .Fixed32 {
            if f.fixed > 4294967295u64 { ret Invalid }
            try write_fixed32(w, u32(f.fixed))
        }
        if f.wire == .Fixed64 { try write_fixed64(w, f.fixed) }
        if f.wire == .Bytes { try write_bytes(w, f.data) }
        i += 1usize
    }
    ret ok
}
