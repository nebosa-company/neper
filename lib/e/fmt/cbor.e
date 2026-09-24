// CBOR (RFC 8949) both ways over caller storage. An `Encoder` appends items to a `[]u8`, every
// argument in its shortest form (the preferred serialization); a `Decoder` reads heads one at a
// time from a `[]const u8`, so nesting is the caller's loop and nothing is allocated.
//
// `decode_head` is the whole grammar: an initial byte and its 0/1/2/4/8-byte argument. The typed
// helpers are that plus a check of the major type, and for byte and text strings the payload,
// borrowed from the input. Indefinite-length arrays and maps are `begin_*` ... `encode_break`
// on the way out and `indefinite` on the `Item` plus `at_break` on the way in.

use e.mem

type Encoder = struct { out: []u8, len: usize }

type Decoder = struct { data: []const u8, at: usize }

// One head. `value` is the argument: the integer for majors 0/1 (major 1 means `-1 - value`),
// the length for 2..5, the tag number for 6, and the simple value or the float's raw bits for 7.
type Item = struct { major: u8, info: u8, value: u64, indefinite: bool }

error Invalid
error Truncated
error TooSmall
error Mismatch

const MAJOR_UINT: u8 = 0u8
const MAJOR_NEGATIVE: u8 = 1u8
const MAJOR_BYTES: u8 = 2u8
const MAJOR_TEXT: u8 = 3u8
const MAJOR_ARRAY: u8 = 4u8
const MAJOR_MAP: u8 = 5u8
const MAJOR_TAG: u8 = 6u8
const MAJOR_SIMPLE: u8 = 7u8

const SIMPLE_FALSE: u64 = 20u64
const SIMPLE_TRUE: u64 = 21u64
const SIMPLE_NULL: u64 = 22u64
const SIMPLE_UNDEFINED: u64 = 23u64
const INFO_INDEFINITE: u8 = 31u8
const BREAK: u8 = 255u8

// --- Encoding.

fn encoder(out: []u8) -> Encoder {
    var e: Encoder = zero
    e.out = out
    ret e
}

// What has been written so far.
fn encoded(e: *const Encoder) -> []const u8 {
    ret e.out[0usize..e.len]
}

fn put(e: *Encoder, b: u8) -> err {
    if e.len >= e.out.len { ret TooSmall }
    e.out[e.len] = b
    e.len += 1usize
    ret ok
}

fn put_all(e: *Encoder, data: []const u8) -> err {
    var at = 0usize
    while at < data.len {
        try put(e, data[at])
        at += 1usize
    }
    ret ok
}

fn put_be(e: *Encoder, value: u64, width: usize) -> err {
    var at = 0usize
    while at < width {
        try put(e, u8((value >> u32((width - 1usize - at) * 8usize)) & 255u64))
        at += 1usize
    }
    ret ok
}

// A head in its shortest form: the argument in the initial byte when it fits, else 1, 2, 4 or
// 8 bytes after it.
fn encode_head(e: *Encoder, major: u8, value: u64) -> err {
    let base = major << 5u32
    if value < 24u64 { ret put(e, base | u8(value)) }
    if value < 256u64 {
        try put(e, base | 24u8)
        ret put_be(e, value, 1usize)
    }
    if value < 65536u64 {
        try put(e, base | 25u8)
        ret put_be(e, value, 2usize)
    }
    if value < 4294967296u64 {
        try put(e, base | 26u8)
        ret put_be(e, value, 4usize)
    }
    try put(e, base | 27u8)
    ret put_be(e, value, 8usize)
}

fn encode_uint(e: *Encoder, value: u64) -> err {
    ret encode_head(e, MAJOR_UINT, value)
}

// A signed integer: non-negative as major 0, negative as major 1 carrying `-1 - value`.
fn encode_int(e: *Encoder, value: i64) -> err {
    if value >= 0i64 { ret encode_head(e, MAJOR_UINT, u64(value)) }
    ret encode_head(e, MAJOR_NEGATIVE, ~u64.trunc(value))
}

// A negative integer below `i64`: major 1 with the argument given directly, `-1 - argument`.
fn encode_negative(e: *Encoder, argument: u64) -> err {
    ret encode_head(e, MAJOR_NEGATIVE, argument)
}

fn encode_bytes(e: *Encoder, data: []const u8) -> err {
    try encode_head(e, MAJOR_BYTES, u64(data.len))
    ret put_all(e, data)
}

fn encode_text(e: *Encoder, text: str) -> err {
    try encode_head(e, MAJOR_TEXT, u64(text.len))
    ret put_all(e, text)
}

// The head of an array of `count` items, which the caller then encodes.
fn encode_array(e: *Encoder, count: usize) -> err {
    ret encode_head(e, MAJOR_ARRAY, u64(count))
}

// The head of a map of `count` pairs: the caller encodes each key, then its value.
fn encode_map(e: *Encoder, count: usize) -> err {
    ret encode_head(e, MAJOR_MAP, u64(count))
}

// A tag; the item it tags follows.
fn encode_tag(e: *Encoder, tag: u64) -> err {
    ret encode_head(e, MAJOR_TAG, tag)
}

fn encode_bool(e: *Encoder, value: bool) -> err {
    if value { ret encode_head(e, MAJOR_SIMPLE, SIMPLE_TRUE) }
    ret encode_head(e, MAJOR_SIMPLE, SIMPLE_FALSE)
}

fn encode_null(e: *Encoder) -> err {
    ret encode_head(e, MAJOR_SIMPLE, SIMPLE_NULL)
}

fn encode_undefined(e: *Encoder) -> err {
    ret encode_head(e, MAJOR_SIMPLE, SIMPLE_UNDEFINED)
}

// A simple value other than the four above: 0..19 and 32..255 (24..31 are not well-formed).
fn encode_simple(e: *Encoder, value: u8) -> err {
    if value >= 24u8 && value < 32u8 { ret Invalid }
    ret encode_head(e, MAJOR_SIMPLE, u64(value))
}

// ponytail: a float is written at the width given, never narrowed. The preferred serialization
// picks the shortest of f16/f32/f64 that round-trips; add a `encode_f64_shortest` when a
// consumer compares bytes rather than values.
fn encode_f64(e: *Encoder, value: f64) -> err {
    try put(e, (MAJOR_SIMPLE << 5u32) | 27u8)
    ret put_be(e, mem.bitcast[u64](value), 8usize)
}

fn encode_f32(e: *Encoder, value: f32) -> err {
    try put(e, (MAJOR_SIMPLE << 5u32) | 26u8)
    ret put_be(e, u64(mem.bitcast[u32](value)), 4usize)
}

fn begin_array(e: *Encoder) -> err {
    ret put(e, (MAJOR_ARRAY << 5u32) | INFO_INDEFINITE)
}

fn begin_map(e: *Encoder) -> err {
    ret put(e, (MAJOR_MAP << 5u32) | INFO_INDEFINITE)
}

// Ends an indefinite-length array or map.
fn encode_break(e: *Encoder) -> err {
    ret put(e, BREAK)
}

// --- Decoding.

fn decoder(data: []const u8) -> Decoder {
    var d: Decoder = zero
    d.data = data
    ret d
}

fn remaining(d: *const Decoder) -> usize {
    ret d.data.len - d.at
}

fn take(d: *Decoder) -> (u8, err) {
    if d.at >= d.data.len { ret (0u8, Truncated) }
    let b = d.data[d.at]
    d.at += 1usize
    ret (b, ok)
}

fn take_be(d: *Decoder, width: usize) -> (u64, err) {
    if d.data.len - d.at < width { ret (0u64, Truncated) }
    var value = 0u64
    var at = 0usize
    while at < width {
        value = (value << 8u32) | u64(d.data[d.at + at])
        at += 1usize
    }
    d.at += width
    ret (value, ok)
}

// The next head, consumed. A string's payload and a container's items are left in place. The
// break code arrives as major 7 with `info` 31; `at_break` peeks for it without consuming.
fn decode_head(d: *Decoder) -> (Item, err) {
    var item: Item = zero
    let (initial, initial_error) = take(d)
    if initial_error != ok { ret (item, initial_error) }
    item.major = initial >> 5u32
    item.info = initial & 31u8
    if item.info < 24u8 {
        item.value = u64(item.info)
        ret (item, ok)
    }
    if item.info == INFO_INDEFINITE {
        if item.major < MAJOR_BYTES || item.major == MAJOR_TAG { ret (item, Invalid) }
        item.indefinite = item.major != MAJOR_SIMPLE
        ret (item, ok)
    }
    if item.info > 27u8 { ret (item, Invalid) }
    let (value, value_error) = take_be(d, 1usize << u32(item.info - 24u8))
    if value_error != ok { ret (item, value_error) }
    // A two-byte simple value below 32 has a one-byte spelling and is not well-formed.
    if item.major == MAJOR_SIMPLE && item.info == 24u8 && value < 32u64 { ret (item, Invalid) }
    item.value = value
    ret (item, ok)
}

fn at_break(d: *const Decoder) -> bool {
    ret d.at < d.data.len && d.data[d.at] == BREAK
}

fn expect(d: *Decoder, major: u8) -> (Item, err) {
    let (item, head_error) = decode_head(d)
    if head_error != ok { ret (item, head_error) }
    if item.major != major { ret (item, Mismatch) }
    ret (item, ok)
}

fn decode_uint(d: *Decoder) -> (u64, err) {
    let (item, head_error) = expect(d, MAJOR_UINT)
    if head_error != ok { ret (0u64, head_error) }
    ret (item.value, ok)
}

// Major 0 or 1 as an `i64`; an argument past the signed range is `Mismatch`.
fn decode_int(d: *Decoder) -> (i64, err) {
    let (item, head_error) = decode_head(d)
    if head_error != ok { ret (0i64, head_error) }
    if item.major > MAJOR_NEGATIVE { ret (0i64, Mismatch) }
    if item.value > 9223372036854775807u64 { ret (0i64, Mismatch) }
    if item.major == MAJOR_UINT { ret (i64(item.value), ok) }
    ret (-1i64 - i64(item.value), ok)
}

// A definite-length string's payload, borrowed from the input. ponytail: an indefinite-length
// string is chunks to concatenate, which needs storage this helper has none of; it answers
// `Mismatch`, and `skip` still walks past one.
fn payload(d: *Decoder, major: u8) -> ([]const u8, err) {
    let (item, head_error) = expect(d, major)
    if head_error != ok { ret (zero, head_error) }
    if item.indefinite { ret (zero, Mismatch) }
    if u64(d.data.len - d.at) < item.value { ret (zero, Truncated) }
    let count = usize(item.value)
    let out = d.data[d.at..d.at + count]
    d.at += count
    ret (out, ok)
}

fn decode_bytes(d: *Decoder) -> ([]const u8, err) {
    let (out, payload_error) = payload(d, MAJOR_BYTES)
    ret (out, payload_error)
}

fn decode_text(d: *Decoder) -> (str, err) {
    let (out, payload_error) = payload(d, MAJOR_TEXT)
    ret (out, payload_error)
}

// The item count, and whether the array is indefinite (then the count is 0 and the caller reads
// until `at_break`, consuming the break with `decode_head`).
fn decode_array_len(d: *Decoder) -> (usize, bool, err) {
    let (item, head_error) = expect(d, MAJOR_ARRAY)
    if head_error != ok { ret (0usize, false, head_error) }
    ret (usize(item.value), item.indefinite, ok)
}

// The pair count, likewise.
fn decode_map_len(d: *Decoder) -> (usize, bool, err) {
    let (item, head_error) = expect(d, MAJOR_MAP)
    if head_error != ok { ret (0usize, false, head_error) }
    ret (usize(item.value), item.indefinite, ok)
}

fn decode_tag(d: *Decoder) -> (u64, err) {
    let (item, head_error) = expect(d, MAJOR_TAG)
    if head_error != ok { ret (0u64, head_error) }
    ret (item.value, ok)
}

fn decode_bool(d: *Decoder) -> (bool, err) {
    let (item, head_error) = expect(d, MAJOR_SIMPLE)
    if head_error != ok { ret (false, head_error) }
    if item.info < 24u8 && item.value == SIMPLE_TRUE { ret (true, ok) }
    if item.info < 24u8 && item.value == SIMPLE_FALSE { ret (false, ok) }
    ret (false, Mismatch)
}

fn decode_null(d: *Decoder) -> err {
    let (item, head_error) = expect(d, MAJOR_SIMPLE)
    if head_error != ok { ret head_error }
    if item.info < 24u8 && item.value == SIMPLE_NULL { ret ok }
    ret Mismatch
}

fn pow2(exponent: i64) -> f64 {
    ret mem.bitcast[f64](u64(exponent + 1023i64) << 52u32)
}

// IEEE binary16 bits to `f64`, exactly: every half is representable.
fn f16_to_f64(bits: u64) -> f64 {
    let exponent = (bits >> 10u32) & 31u64
    let fraction = bits & 1023u64
    var magnitude = 0.0f64
    if exponent == 0u64 {
        magnitude = f64(fraction) * pow2(-24i64)
    } else {
        if exponent == 31u64 {
            if fraction == 0u64 {
                magnitude = mem.bitcast[f64](9218868437227405312u64)
            } else {
                magnitude = mem.bitcast[f64](9221120237041090560u64)
            }
        } else {
            magnitude = f64(fraction + 1024u64) * pow2(i64(exponent) - 25i64)
        }
    }
    ret mem.bitcast[f64](mem.bitcast[u64](magnitude) | ((bits & 32768u64) << 48u32))
}

// A float of any of the three widths as `f64`.
fn decode_f64(d: *Decoder) -> (f64, err) {
    let (item, head_error) = expect(d, MAJOR_SIMPLE)
    if head_error != ok { ret (0.0f64, head_error) }
    if item.info == 25u8 { ret (f16_to_f64(item.value), ok) }
    if item.info == 26u8 { ret (f64(mem.bitcast[f32](u32(item.value))), ok) }
    if item.info == 27u8 { ret (mem.bitcast[f64](item.value), ok) }
    ret (0.0f64, Mismatch)
}

// Past one whole item, nested or indefinite, without interpreting it. The same 128-level
// ceiling as the tree decoder keeps hostile nesting off the process stack.
fn skip_depth(d: *Decoder, depth: u16) -> err {
    let (item, head_error) = decode_head(d)
    if head_error != ok { ret head_error }
    if item.major == MAJOR_BYTES || item.major == MAJOR_TEXT {
        if !item.indefinite {
            if u64(d.data.len - d.at) < item.value { ret Truncated }
            d.at += usize(item.value)
            ret ok
        }
        while !at_break(d) {
            let (chunk, chunk_error) = expect(d, item.major)
            if chunk_error != ok { ret chunk_error }
            if chunk.indefinite { ret Invalid }
            if u64(d.data.len - d.at) < chunk.value { ret Truncated }
            d.at += usize(chunk.value)
        }
        d.at += 1usize
        ret ok
    }
    if item.major == MAJOR_ARRAY || item.major == MAJOR_MAP {
        if depth == 0u16 { ret Invalid }
        if item.indefinite {
            while !at_break(d) { try skip_depth(d, depth - 1u16) }
            d.at += 1usize
            ret ok
        }
        var count = item.value
        if item.major == MAJOR_MAP { count = count * 2u64 }
        var at = 0u64
        while at < count {
            try skip_depth(d, depth - 1u16)
            at += 1u64
        }
        ret ok
    }
    if item.major == MAJOR_TAG {
        if depth == 0u16 { ret Invalid }
        ret skip_depth(d, depth - 1u16)
    }
    ret ok
}

fn skip(d: *Decoder) -> err { ret skip_depth(d, 128u16) }

// --- A value model, canonically encoded and decoded whole.
//
// `Value` is one item with its nesting. `encode` writes it in the preferred serialization of
// RFC 8949 section 4.2: shortest heads, the shortest float that reads back exactly, no
// indefinite lengths, and map keys in the order of their encodings (shorter first, then
// bytewise). `decode` reads one back through the typed helpers above; its arrays, maps and
// tagged items live in the arena, its strings borrow from the input.

type Pair = struct { key: Value, value: Value }
// `items` holds exactly the one item the tag applies to; a slice so the type needs no pointer.
type Tagged = struct { tag: u64, items: []const Value }
type Value = union enum u8 { Null, Undefined, Bool: bool, Uint: u64, Int: i64, Float: f64, Bytes: []const u8, Text: str, Array: []const Value, Map: []const Pair, Tagged: Tagged }

// `value` as binary16 bits when that reads back to the same bits, else `false`.
fn f16_of(value: f64) -> (u64, bool) {
    let bits = mem.bitcast[u64](value)
    let sign = (bits >> 48u32) & 32768u64
    let exponent = i64((bits >> 52u32) & 2047u64) - 1023i64
    let mantissa = bits & 4503599627370495u64
    if (bits & 9223372036854775807u64) == 0u64 { ret (sign, true) }
    if exponent == 1024i64 {
        if mantissa == 0u64 { ret (sign | 31744u64, true) }
        ret (32256u64, true)
    }
    var candidate = 0u64
    if exponent >= -14i64 && exponent <= 15i64 {
        candidate = sign | (u64(exponent + 15i64) << 10u32) | (mantissa >> 42u32)
    } else {
        if exponent < -14i64 && exponent >= -24i64 {
            candidate = sign | ((mantissa | 4503599627370496u64) >> u32(42i64 + (-14i64 - exponent)))
        } else {
            ret (0u64, false)
        }
    }
    ret (candidate, mem.bitcast[u64](f16_to_f64(candidate)) == bits)
}

// The shortest of the three float widths that round-trips `value` exactly; a NaN is the
// canonical half-precision one.
fn encode_float_shortest(e: *Encoder, value: f64) -> err {
    let (half, fits_half) = f16_of(value)
    if fits_half {
        try put(e, (MAJOR_SIMPLE << 5u32) | 25u8)
        ret put_be(e, half, 2usize)
    }
    let single = f32(value)
    if mem.bitcast[u64](f64(single)) == mem.bitcast[u64](value) { ret encode_f32(e, single) }
    ret encode_f64(e, value)
}

fn key_less(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret x.len < y.len }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret x[i] < y[i] }
        i += 1usize
    }
    ret false
}

fn reverse_bytes(dst: []u8, lo: usize, hi: usize) {
    var i = lo
    var j = hi
    while i + 1usize < j {
        j -= 1usize
        let t = dst[i]
        dst[i] = dst[j]
        dst[j] = t
        i += 1usize
    }
}

// The pairs written at `e.out[start..e.len]` put into canonical key order, in place.
// ponytail: a bubble sort that re-walks the pairs with `skip` after every swap, O(n^2) walks
// over the encoded bytes; it keeps the caller's buffer the only storage, and a map with
// thousands of keys is what a sorted index is for.
fn sort_pairs(e: *Encoder, start: usize) -> err {
    var swapped = true
    while swapped {
        swapped = false
        var d = decoder(e.out[start..e.len])
        var previous_start = 0usize
        var previous_key_end = 0usize
        var previous_end = 0usize
        var has_previous = false
        while d.at < d.data.len {
            let pair_start = d.at
            try skip(&d)
            let key_end = d.at
            try skip(&d)
            let pair_end = d.at
            if has_previous && key_less(d.data[pair_start..key_end], d.data[previous_start..previous_key_end]) {
                reverse_bytes(e.out, start + previous_start, start + previous_end)
                reverse_bytes(e.out, start + pair_start, start + pair_end)
                reverse_bytes(e.out, start + previous_start, start + pair_end)
                swapped = true
                break
            }
            has_previous = true
            previous_start = pair_start
            previous_key_end = key_end
            previous_end = pair_end
        }
    }
    ret ok
}

// One value, canonically. ponytail: recursive on nesting depth with no cap, like `skip`.
fn encode(e: *Encoder, value: *const Value) -> err {
    switch *value {
    case .Null:
        ret encode_null(e)
    case .Undefined:
        ret encode_undefined(e)
    case .Bool as flag:
        ret encode_bool(e, flag)
    case .Uint as unsigned:
        ret encode_uint(e, unsigned)
    case .Int as signed:
        ret encode_int(e, signed)
    case .Float as number:
        ret encode_float_shortest(e, number)
    case .Bytes as data:
        ret encode_bytes(e, data)
    case .Text as text:
        ret encode_text(e, text)
    case .Array as items:
        try encode_array(e, items.len)
        var at = 0usize
        while at < items.len {
            try encode(e, &items[at])
            at += 1usize
        }
        ret ok
    case .Map as pairs:
        try encode_map(e, pairs.len)
        let start = e.len
        var at = 0usize
        while at < pairs.len {
            try encode(e, &pairs[at].key)
            try encode(e, &pairs[at].value)
            at += 1usize
        }
        ret sort_pairs(e, start)
    case .Tagged as tagged:
        if tagged.items.len != 1usize { ret Invalid }
        try encode_tag(e, tagged.tag)
        ret encode(e, &tagged.items[0])
    }
}

// The items of an indefinite-length container, counted by skipping a copy of the decoder.
fn count_until_break(d: *const Decoder) -> (usize, err) {
    var probe = decoder(d.data)
    probe.at = d.at
    var count = 0usize
    while !at_break(&probe) {
        if probe.at >= probe.data.len { ret (0usize, Truncated) }
        let skip_error = skip(&probe)
        if skip_error != ok { ret (0usize, skip_error) }
        count += 1usize
    }
    ret (count, ok)
}

// One whole item as a `Value`. An integer is `Uint` when it is major 0 and `Int` when it is
// major 1 and fits; a negative below `i64` is `Mismatch`, an indefinite string too (see
// `payload`).
fn decode(a: *mem.Arena, d: *Decoder, max_depth: u16) -> (Value, err) {
    var none: Value = .Null
    if max_depth == 0u16 { ret (none, Invalid) }
    if d.at >= d.data.len { ret (none, Truncated) }
    let major = d.data[d.at] >> 5u32
    if major == MAJOR_UINT {
        let (unsigned, unsigned_error) = decode_uint(d)
        ret (Value{ Uint: unsigned }, unsigned_error)
    }
    if major == MAJOR_NEGATIVE {
        let (signed, signed_error) = decode_int(d)
        ret (Value{ Int: signed }, signed_error)
    }
    if major == MAJOR_BYTES {
        let (data, data_error) = decode_bytes(d)
        ret (Value{ Bytes: data }, data_error)
    }
    if major == MAJOR_TEXT {
        let (text, text_error) = decode_text(d)
        ret (Value{ Text: text }, text_error)
    }
    if major == MAJOR_TAG {
        let (tag, tag_error) = decode_tag(d)
        if tag_error != ok { ret (none, tag_error) }
        let (items, items_error) = mem.alloc[Value](a, 1usize)
        if items_error != ok { ret (none, items_error) }
        let (inner, inner_error) = decode(a, d, max_depth - 1u16)
        if inner_error != ok { ret (none, inner_error) }
        items[0] = inner
        ret (Value{ Tagged: Tagged { tag: tag, items: items[0usize..] } }, ok)
    }
    if major == MAJOR_ARRAY || major == MAJOR_MAP {
        let (item, head_error) = decode_head(d)
        if head_error != ok { ret (none, head_error) }
        var count = usize(item.value)
        if item.indefinite {
            let (counted, count_error) = count_until_break(d)
            if count_error != ok { ret (none, count_error) }
            count = counted
            if major == MAJOR_MAP {
                if count % 2usize != 0usize { ret (none, Invalid) }
                count = count / 2usize
            }
        }
        if major == MAJOR_ARRAY {
            let (items, items_error) = mem.alloc[Value](a, count)
            if items_error != ok { ret (none, items_error) }
            var at = 0usize
            while at < count {
                let (inner, inner_error) = decode(a, d, max_depth - 1u16)
                if inner_error != ok { ret (none, inner_error) }
                items[at] = inner
                at += 1usize
            }
            if item.indefinite { d.at += 1usize }
            ret (Value{ Array: items[0usize..] }, ok)
        }
        let (pairs, pairs_error) = mem.alloc[Pair](a, count)
        if pairs_error != ok { ret (none, pairs_error) }
        var at = 0usize
        while at < count {
            let (key, key_error) = decode(a, d, max_depth - 1u16)
            if key_error != ok { ret (none, key_error) }
            let (inner, inner_error) = decode(a, d, max_depth - 1u16)
            if inner_error != ok { ret (none, inner_error) }
            pairs[at] = Pair { key: key, value: inner }
            at += 1usize
        }
        if item.indefinite { d.at += 1usize }
        ret (Value{ Map: pairs[0usize..] }, ok)
    }
    let (item, head_error) = decode_head(d)
    if head_error != ok { ret (none, head_error) }
    if item.info >= 25u8 && item.info <= 27u8 {
        if item.info == 25u8 { ret (Value{ Float: f16_to_f64(item.value) }, ok) }
        if item.info == 26u8 { ret (Value{ Float: f64(mem.bitcast[f32](u32(item.value))) }, ok) }
        ret (Value{ Float: mem.bitcast[f64](item.value) }, ok)
    }
    if item.info == INFO_INDEFINITE { ret (none, Invalid) }
    if item.value == SIMPLE_TRUE { ret (Value{ Bool: true }, ok) }
    if item.value == SIMPLE_FALSE { ret (Value{ Bool: false }, ok) }
    if item.value == SIMPLE_NULL { ret (none, ok) }
    if item.value == SIMPLE_UNDEFINED { ret (.Undefined, ok) }
    ret (none, Mismatch)
}
