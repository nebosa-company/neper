// ASN.1 DER: a reader that walks the TLVs of one level, `children` that descends a
// constructed value one level deeper under a depth limit, and typed `decode` /
// `encode` over a flat struct as a SEQUENCE of its fields in order -- integers as
// INTEGER, booleans as BOOLEAN, strings and byte slices as OCTET STRING (a UTF8String
// or PrintableString is accepted on the way in). Everything is validated as DER:
// definite lengths in their shortest form, minimal tag numbers, minimal two's
// complement integers, booleans of 0x00 or 0xff; anything else is `NonCanonical`, a
// length past the data is `Invalid`, one past 8 bytes is `TooLarge`.
use e.mem
use e.meta

type Class = enum u8 { Universal, Application, Context, Private }
type Tag = struct { class: Class, number: u32, constructed: bool }
type Value = struct { tag: Tag, content: []const u8, encoded: []const u8 }
type Reader = struct { data: []const u8, off: usize, depth: u16, max_depth: u16 }
error Invalid
error NonCanonical
error TooDeep
error TooLarge

fn reader(data: []const u8, max_depth: u16) -> Reader {
    ret Reader { data: data, off: 0usize, depth: 0u16, max_depth: max_depth }
}

fn class_of(first: u8) -> Class {
    let bits = first >> 6u8
    if bits == 1u8 { ret .Application }
    if bits == 2u8 { ret .Context }
    if bits == 3u8 { ret .Private }
    ret .Universal
}

// The next value at the reader's offset; `false` once the data is exhausted.
fn reader_next_err(source_reader: *Reader) -> (Value, bool, err) {
    var r = source_reader
    let data = r.data
    if r.off >= data.len { ret (zero, false, ok) }
    let start = r.off
    var at = start
    let first = data[at]
    at += 1usize
    var tag: Tag = zero
    tag.class = class_of(first)
    tag.constructed = first & 32u8 != 0u8
    let low = u32(first & 31u8)
    if low < 31u32 {
        tag.number = low
    } else {
        // High tag number: base 128, minimal, at least 31.
        if at >= data.len { ret (zero, false, Invalid) }
        if data[at] == 128u8 { ret (zero, false, NonCanonical) }
        var number = 0u32
        var count = 0usize
        while true {
            if at >= data.len { ret (zero, false, Invalid) }
            if count == 5usize { ret (zero, false, TooLarge) }
            let byte = data[at]
            at += 1usize
            count += 1usize
            number = (number << 7u32) | u32(byte & 127u8)
            if byte & 128u8 == 0u8 { break }
        }
        if number < 31u32 { ret (zero, false, NonCanonical) }
        tag.number = number
    }
    // The length.
    if at >= data.len { ret (zero, false, Invalid) }
    let length_first = data[at]
    at += 1usize
    var length = 0usize
    if length_first < 128u8 {
        length = usize(length_first)
    } else {
        let count = usize(length_first & 127u8)
        if count == 0usize { ret (zero, false, NonCanonical) }
        if count > 8usize { ret (zero, false, TooLarge) }
        if at + count > data.len { ret (zero, false, Invalid) }
        if data[at] == 0u8 { ret (zero, false, NonCanonical) }
        var i = 0usize
        while i < count {
            length = (length << 8u32) | usize(data[at + i])
            i += 1usize
        }
        if length < 128usize { ret (zero, false, NonCanonical) }
        at += count
    }
    if length > data.len - at { ret (zero, false, Invalid) }
    var value: Value = zero
    value.tag = tag
    value.content = data[at..at + length]
    value.encoded = data[start..at + length]
    r.off = at + length
    ret (value, true, ok)
}

fn children(value: Value, max_depth: u16) -> (Reader, err) {
    if !value.tag.constructed { ret (zero, Invalid) }
    if max_depth == 0u16 { ret (zero, TooDeep) }
    ret (Reader { data: value.content, off: 0usize, depth: 1u16, max_depth: max_depth }, ok)
}

fn is_universal(value: Value, number: u32, constructed: bool) -> bool {
    ret value.tag.class == .Universal && value.tag.number == number && value.tag.constructed == constructed
}

// A DER INTEGER as a signed 64-bit value; minimal encoding required.
fn integer_of(value: Value) -> (i64, err) {
    let c = value.content
    if c.len == 0usize { ret (0i64, NonCanonical) }
    if c.len > 1usize {
        if c[0] == 0u8 && c[1] & 128u8 == 0u8 { ret (0i64, NonCanonical) }
        if c[0] == 255u8 && c[1] & 128u8 != 0u8 { ret (0i64, NonCanonical) }
    }
    if c.len > 8usize { ret (0i64, TooLarge) }
    var acc = 0u64
    if c[0] & 128u8 != 0u8 { acc = 18446744073709551615u64 }
    var i = 0usize
    while i < c.len {
        acc = (acc << 8u32) | u64(c[i])
        i += 1usize
    }
    ret (mem.bitcast[i64](acc), ok)
}

fn boolean_of(value: Value) -> (bool, err) {
    if value.content.len != 1usize { ret (false, NonCanonical) }
    if value.content[0] == 0u8 { ret (false, ok) }
    if value.content[0] == 255u8 { ret (true, ok) }
    ret (false, NonCanonical)
}

fn decode[T: type](a: *mem.Arena, source: []const u8, max_depth: u16) -> (T, err) {
    var out: T = zero
    var top = reader(source, max_depth)
    let (root, present, root_error) = reader_next_err(&top)
    if root_error != ok { ret (out, root_error) }
    if !present || top.off != source.len { ret (out, Invalid) }
    if !is_universal(root, 16u32, true) { ret (out, Invalid) }
    let (inner0, inner_error) = children(root, max_depth)
    if inner_error != ok { ret (out, inner_error) }
    var inner = inner0
    for f in meta.fields[T]() {
        let (field, has_field, field_error) = reader_next_err(&inner)
        if field_error != ok { ret (out, field_error) }
        if !has_field { ret (out, Invalid) }
        if meta.kind[f.ty]() == .Slice {
            if !is_universal(field, 4u32, false) && !is_universal(field, 12u32, false) && !is_universal(field, 19u32, false) { ret (out, Invalid) }
            let (copy, copy_error) = mem.alloc[u8](a, field.content.len)
            if copy_error != ok { ret (out, copy_error) }
            var i = 0usize
            while i < field.content.len {
                copy[i] = field.content[i]
                i += 1usize
            }
            var slot: f.ty = zero
            slot = copy
            meta.set[f, T](&out, slot)
        } else {
        if meta.kind[f.ty]() == .Bool {
            if !is_universal(field, 1u32, false) { ret (out, Invalid) }
            let (flag, flag_error) = boolean_of(field)
            if flag_error != ok { ret (out, flag_error) }
            meta.set[f, T](&out, flag)
        } else {
        if meta.kind[f.ty]() == .Int {
            if !is_universal(field, 2u32, false) { ret (out, Invalid) }
            let (number, number_error) = integer_of(field)
            if number_error != ok { ret (out, number_error) }
            var slot: f.ty = zero
            slot = f.ty(number)
            meta.set[f, T](&out, slot)
        } else {
            ret (out, Invalid)
        }
        }
        }
    }
    let (extra, has_extra, extra_error) = reader_next_err(&inner)
    if extra_error != ok { ret (out, extra_error) }
    if has_extra { ret (out, Invalid) }
    ret (out, ok)
}

// The minimal two's complement byte count of a signed value.
fn integer_len(value: i64) -> usize {
    var count = 1usize
    var v = value
    while v > 127i64 || v < -128i64 {
        v = v >> 8u32
        count += 1usize
    }
    ret count
}

fn length_len(length: usize) -> usize {
    if length < 128usize { ret 1usize }
    var count = 1usize
    var l = length
    while l > 0usize {
        l = l >> 8u32
        count += 1usize
    }
    ret count
}

fn contents_len[T: type](value: *const T) -> usize {
    var total = 0usize
    for f in meta.fields[T]() {
        var slot: f.ty = zero
        slot = meta.get[f, T](value)
        var content = 0usize
        if meta.kind[f.ty]() == .Slice {
            content = slot.len
        } else {
        if meta.kind[f.ty]() == .Bool {
            content = 1usize
        } else {
            content = integer_len(i64(slot))
        }
        }
        total += 1usize + length_len(content) + content
    }
    ret total
}

fn encoded_len[T: type](value: *const T) -> (usize, err) {
    for f in meta.fields[T]() {
        if meta.kind[f.ty]() == .Slice {
        } else {
        if meta.kind[f.ty]() == .Bool {
        } else {
        if meta.kind[f.ty]() == .Int {
        } else {
            ret (0usize, Invalid)
        }
        }
        }
    }
    let inner = contents_len[T](value)
    ret (1usize + length_len(inner) + inner, ok)
}

fn put_header(dst: []u8, at: usize, tag: u8, length: usize) -> usize {
    var out = at
    dst[out] = tag
    out += 1usize
    if length < 128usize {
        dst[out] = u8(length)
        ret out + 1usize
    }
    let count = length_len(length) - 1usize
    dst[out] = 128u8 | u8(count)
    out += 1usize
    var i = count
    while i > 0usize {
        i -= 1usize
        dst[out] = u8((length >> u32(i * 8usize)) & 255usize)
        out += 1usize
    }
    ret out
}

fn encode[T: type](dst: []u8, value: *const T) -> ([]u8, err) {
    let (needed, needed_error) = encoded_len[T](value)
    if needed_error != ok { ret (zero, needed_error) }
    if needed > dst.len { ret (zero, TooLarge) }
    var at = put_header(dst, 0usize, 48u8, contents_len[T](value))
    for f in meta.fields[T]() {
        var slot: f.ty = zero
        slot = meta.get[f, T](value)
        if meta.kind[f.ty]() == .Slice {
            at = put_header(dst, at, 4u8, slot.len)
            var i = 0usize
            while i < slot.len {
                dst[at] = slot[i]
                at += 1usize
                i += 1usize
            }
        } else {
        if meta.kind[f.ty]() == .Bool {
            at = put_header(dst, at, 1u8, 1usize)
            if slot { dst[at] = 255u8 } else { dst[at] = 0u8 }
            at += 1usize
        } else {
            let number = i64(slot)
            let count = integer_len(number)
            at = put_header(dst, at, 2u8, count)
            var i = count
            while i > 0usize {
                i -= 1usize
                dst[at] = u8((number >> u32(i * 8usize)) & 255i64)
                at += 1usize
            }
        }
        }
    }
    ret (dst[0usize..at], ok)
}
