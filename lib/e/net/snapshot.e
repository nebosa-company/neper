// Bit-packed state under a quantised schema, whole or as a delta (D249).
//
// A snapshot is a byte array of game state plus a `Schema` saying how to read it: each
// field is an offset into that array, a range, and how many bits it is worth on the wire.
// Quantising is what makes replication affordable -- a position that matters to a tenth
// of a unit over a 512-unit map needs 13 bits, not 32 -- and doing it with integer
// arithmetic is what keeps two peers agreeing on the value they decoded.
//
// A delta writes one presence bit per field and then only the fields that changed against
// a baseline the peer has acknowledged. That is the whole trick: a game where most of the
// world is still costs a bit per still field rather than a field per still field.

use e.mem

// `offset` is where the field's i32 lives in the state array. `bits` is its width on the
// wire, and `lo`/`hi` the range it is quantised into.
type Field = struct {
    offset: usize,
    bits: u8,
    signed: bool,
    lo: i32,
    hi: i32,
}

type Schema = struct {
    fields: []const Field,
    state_bytes: usize,
}

type Writer = struct {
    bytes: []u8,
    bit: usize,
}

type Reader = struct {
    bytes: []const u8,
    bit: usize,
}

error Invalid
error Full

fn writer(bytes: []u8) -> Writer {
    ret Writer { bytes: bytes, bit: 0usize }
}

fn reader(bytes: []const u8) -> Reader {
    ret Reader { bytes: bytes, bit: 0usize }
}

fn bits_written(w: Writer) -> usize {
    ret w.bit
}

fn bytes_written(w: Writer) -> usize {
    ret (w.bit + 7usize) / 8usize
}

// Bits go out low end first within each byte, which makes the reader's shift the same
// shift and keeps the two halves impossible to get subtly out of step.
fn put_bits(w: *Writer, value: u32, count: u8) -> err {
    if count == 0u8 || count > 32u8 { ret Invalid }
    var at = 0u8
    while at < count {
        if w.bit / 8usize >= w.bytes.len { ret Full }
        let bit = (value >> u32(at)) & 1u32
        let index = w.bit / 8usize
        let shift = u32(w.bit % 8usize)
        if bit == 1u32 {
            w.bytes[index] = w.bytes[index] | (1u8 << shift)
        } else {
            w.bytes[index] = w.bytes[index] & ~(1u8 << shift)
        }
        w.bit = w.bit + 1usize
        at += 1u8
    }
    ret ok
}

fn get_bits(r: *Reader, count: u8) -> (u32, err) {
    if count == 0u8 || count > 32u8 { ret (0u32, Invalid) }
    var value = 0u32
    var at = 0u8
    while at < count {
        if r.bit / 8usize >= r.bytes.len { ret (0u32, Full) }
        let byte = r.bytes[r.bit / 8usize]
        let shift = u32(r.bit % 8usize)
        if ((byte >> shift) & 1u8) == 1u8 { value = value | (1u32 << u32(at)) }
        r.bit = r.bit + 1usize
        at += 1u8
    }
    ret (value, ok)
}

fn span(f: Field) -> i64 {
    ret i64(f.hi) - i64(f.lo)
}

fn steps(f: Field) -> i64 {
    if f.bits >= 32u8 { ret 4294967295i64 }
    ret (1i64 << u32(f.bits)) - 1i64
}

// Clamped, then scaled onto the field's step count. Rounding is to nearest so the error
// is half a step rather than a whole one, and it is the same rounding on both sides.
fn quantize(value: i32, f: Field) -> u32 {
    let range = span(f)
    if range <= 0i64 { ret 0u32 }
    var held = i64(value)
    if held < i64(f.lo) { held = i64(f.lo) }
    if held > i64(f.hi) { held = i64(f.hi) }
    let scale = steps(f)
    ret u32(((held - i64(f.lo)) * scale + range / 2i64) / range)
}

fn dequantize(code: u32, f: Field) -> i32 {
    let range = span(f)
    if range <= 0i64 { ret f.lo }
    let scale = steps(f)
    if scale == 0i64 { ret f.lo }
    ret i32(i64(f.lo) + (i64(code) * range + scale / 2i64) / scale)
}

// An i32 read from the state array, low byte first. A conversion in this language is
// range-checked, so reinterpreting a negative value's bits goes through i64 and an
// explicit mask -- `u32(-37)` traps rather than wrapping, which is the right default and
// the wrong tool here.
fn load(state: []const u8, offset: usize) -> i32 {
    if offset + 4usize > state.len { ret 0i32 }
    var value = 0i64
    value = value | i64(state[offset])
    value = value | (i64(state[offset + 1usize]) << 8u32)
    value = value | (i64(state[offset + 2usize]) << 16u32)
    value = value | (i64(state[offset + 3usize]) << 24u32)
    if value >= 2147483648i64 { value = value - 4294967296i64 }
    ret i32(value)
}

fn store(state: []u8, offset: usize, value: i32) {
    if offset + 4usize > state.len { ret }
    let bits = i64(value) & 4294967295i64
    state[offset] = u8(bits & 255i64)
    state[offset + 1usize] = u8((bits >> 8u32) & 255i64)
    state[offset + 2usize] = u8((bits >> 16u32) & 255i64)
    state[offset + 3usize] = u8((bits >> 24u32) & 255i64)
}

fn write_full(w: *Writer, s: Schema, state: []const u8) -> err {
    var at = 0usize
    while at < s.fields.len {
        let f = s.fields[at]
        try put_bits(w, quantize(load(state, f.offset), f), f.bits)
        at += 1usize
    }
    ret ok
}

fn read_full(r: *Reader, s: Schema, out: []u8) -> err {
    var at = 0usize
    while at < s.fields.len {
        let f = s.fields[at]
        let (code, code_error) = get_bits(r, f.bits)
        if code_error != ok { ret code_error }
        store(out, f.offset, dequantize(code, f))
        at += 1usize
    }
    ret ok
}

// One presence bit per field, then the changed ones. The comparison is on the quantised
// code, not the raw value: a change too small to survive quantisation is not a change,
// and sending it would cost a field to convey nothing.
fn write_delta(w: *Writer, s: Schema, baseline: []const u8, state: []const u8) -> err {
    var at = 0usize
    while at < s.fields.len {
        let f = s.fields[at]
        let was = quantize(load(baseline, f.offset), f)
        let now = quantize(load(state, f.offset), f)
        if was == now {
            try put_bits(w, 0u32, 1u8)
        } else {
            try put_bits(w, 1u32, 1u8)
            try put_bits(w, now, f.bits)
        }
        at += 1usize
    }
    ret ok
}

// A field the sender did not write keeps the baseline's value, which is what makes the
// delta lossless against that baseline rather than merely small.
fn read_delta(r: *Reader, s: Schema, baseline: []const u8, out: []u8) -> err {
    var at = 0usize
    while at < s.fields.len {
        let f = s.fields[at]
        let (present, present_error) = get_bits(r, 1u8)
        if present_error != ok { ret present_error }
        if present == 1u32 {
            let (code, code_error) = get_bits(r, f.bits)
            if code_error != ok { ret code_error }
            store(out, f.offset, dequantize(code, f))
        } else {
            store(out, f.offset, load(baseline, f.offset))
        }
        at += 1usize
    }
    ret ok
}
