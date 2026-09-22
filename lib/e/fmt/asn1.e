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

// --- A value model: DER out through `der_encode`, BER in through `ber_decode`.
//
// `Item` is the handful of types an X.509-shaped document is made of. `der_encode` writes it
// into caller storage under the DER rules (definite shortest lengths, minimal integers, a SET
// sorted by its members' encodings). `ber_decode` reads the same model from BER, which is what
// the strict reader above refuses: indefinite lengths closed by two zero bytes, constructed
// strings joined from their segments, lengths and integers with padding, any non-zero boolean.

type BitString = struct { unused: u8, data: []const u8 }
type Context = struct { number: u32, items: []const Item }
type Item = union enum u8 { Null, Bool: bool, Integer: i64, BitString: BitString, OctetString: []const u8, Oid: []const u32, Utf8String: str, Sequence: []const Item, Set: []const Item, Context: Context }

fn tag_len(number: u32) -> usize {
    if number < 31u32 { ret 1usize }
    var count = 2usize
    var n = number >> 7u32
    while n > 0u32 {
        n = n >> 7u32
        count += 1usize
    }
    ret count
}

fn arc_len(arc: u32) -> usize {
    var count = 1usize
    var n = arc >> 7u32
    while n > 0u32 {
        n = n >> 7u32
        count += 1usize
    }
    ret count
}

fn oid_len(arcs: []const u32) -> (usize, err) {
    if arcs.len < 2usize || arcs[0] > 2u32 || (arcs[0] < 2u32 && arcs[1] > 39u32) { ret (0usize, Invalid) }
    var total = arc_len(arcs[0] * 40u32 + arcs[1])
    var i = 2usize
    while i < arcs.len {
        total += arc_len(arcs[i])
        i += 1usize
    }
    ret (total, ok)
}

fn items_len(items: []const Item) -> (usize, err) {
    var total = 0usize
    var i = 0usize
    while i < items.len {
        let (one, one_error) = item_len(&items[i])
        if one_error != ok { ret (0usize, one_error) }
        total += one
        i += 1usize
    }
    ret (total, ok)
}

// The content octets of one item.
fn item_content_len(item: *const Item) -> (usize, err) {
    switch *item {
    case .Null:
        ret (0usize, ok)
    case .Bool as flag:
        ret (1usize, ok)
    case .Integer as number:
        ret (integer_len(number), ok)
    case .BitString as bits:
        if bits.unused > 7u8 || (bits.unused > 0u8 && bits.data.len == 0usize) { ret (0usize, Invalid) }
        ret (1usize + bits.data.len, ok)
    case .OctetString as data:
        ret (data.len, ok)
    case .Oid as arcs:
        let (total, total_error) = oid_len(arcs)
        ret (total, total_error)
    case .Utf8String as text:
        ret (text.len, ok)
    case .Sequence as members:
        let (total, total_error) = items_len(members)
        ret (total, total_error)
    case .Set as members:
        let (total, total_error) = items_len(members)
        ret (total, total_error)
    case .Context as tagged:
        let (total, total_error) = items_len(tagged.items)
        ret (total, total_error)
    }
}

fn item_tag(item: *const Item) -> u32 {
    switch *item {
    case .Null:
        ret 5u32
    case .Bool as flag:
        ret 1u32
    case .Integer as number:
        ret 2u32
    case .BitString as bits:
        ret 3u32
    case .OctetString as data:
        ret 4u32
    case .Oid as arcs:
        ret 6u32
    case .Utf8String as text:
        ret 12u32
    case .Sequence as members:
        ret 16u32
    case .Set as members:
        ret 17u32
    case .Context as tagged:
        ret tagged.number
    }
}

// The first tag byte's class and constructed bits.
fn item_first(item: *const Item) -> u8 {
    switch *item {
    case .Sequence as members:
        ret 32u8
    case .Set as members:
        ret 32u8
    case .Context as tagged:
        ret 160u8
    default:
        ret 0u8
    }
}

// The whole encoding of one item: tag, length and content.
fn item_len(item: *const Item) -> (usize, err) {
    let (content, content_error) = item_content_len(item)
    if content_error != ok { ret (0usize, content_error) }
    ret (tag_len(item_tag(item)) + length_len(content) + content, ok)
}

fn put_tag(dst: []u8, at: usize, first: u8, number: u32) -> usize {
    if number < 31u32 {
        dst[at] = first | u8(number)
        ret at + 1usize
    }
    dst[at] = first | 31u8
    ret put_base128(dst, at + 1usize, number)
}

fn put_base128(dst: []u8, at: usize, value: u32) -> usize {
    var out = at
    var shift = (arc_len(value) - 1usize) * 7usize
    while true {
        var byte = u8((value >> u32(shift)) & 127u32)
        if shift > 0usize { byte = byte | 128u8 }
        dst[out] = byte
        out += 1usize
        if shift == 0usize { break }
        shift -= 7usize
    }
    ret out
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

fn bytes_less(x: []const u8, y: []const u8) -> bool {
    var i = 0usize
    while i < x.len && i < y.len {
        if x[i] != y[i] { ret x[i] < y[i] }
        i += 1usize
    }
    ret x.len < y.len
}

// The encodings in `dst[start..end]` sorted as octet strings (X.690 11.6), which is the DER
// order of a SET OF and, for single-byte tags, the tag order of a SET as well.
// ponytail: a bubble sort that re-walks the members with the reader after every swap, so it is
// O(n^2) walks; a SET is a few members long and this keeps the caller's storage the only storage.
fn sort_set(dst: []u8, start: usize, end: usize) {
    var swapped = true
    while swapped {
        swapped = false
        var r = reader(dst[start..end], 1u16)
        var previous_start = 0usize
        var previous_end = 0usize
        var has_previous = false
        while true {
            let (member, present, member_error) = reader_next_err(&r)
            if member_error != ok || !present { break }
            let member_end = start + r.off
            let member_start = member_end - member.encoded.len
            if has_previous && bytes_less(dst[member_start..member_end], dst[previous_start..previous_end]) {
                reverse_bytes(dst, previous_start, previous_end)
                reverse_bytes(dst, member_start, member_end)
                reverse_bytes(dst, previous_start, member_end)
                swapped = true
                break
            }
            has_previous = true
            previous_start = member_start
            previous_end = member_end
        }
    }
}

fn put_items(dst: []u8, at: usize, items: []const Item) -> (usize, err) {
    var out = at
    var i = 0usize
    while i < items.len {
        let (next_at, put_error) = put_item(dst, out, &items[i])
        if put_error != ok { ret (out, put_error) }
        out = next_at
        i += 1usize
    }
    ret (out, ok)
}

fn put_item(dst: []u8, at: usize, item: *const Item) -> (usize, err) {
    let (content, content_error) = item_content_len(item)
    if content_error != ok { ret (at, content_error) }
    let after_tag = put_tag(dst, at, item_first(item), item_tag(item))
    // `put_header` writes a one-byte tag and then the length; here the tag is already down, so
    // it is handed the last tag byte to rewrite in place.
    var out = put_header(dst, after_tag - 1usize, dst[after_tag - 1usize], content)
    let content_start = out
    switch *item {
    case .Null:
        ret (out, ok)
    case .Bool as flag:
        if flag { dst[out] = 255u8 } else { dst[out] = 0u8 }
        ret (out + 1usize, ok)
    case .Integer as number:
        var i = content
        while i > 0usize {
            i -= 1usize
            dst[out] = u8((number >> u32(i * 8usize)) & 255i64)
            out += 1usize
        }
        ret (out, ok)
    case .BitString as bits:
        dst[out] = bits.unused
        mem.copy[u8](dst[out + 1usize..out + 1usize + bits.data.len], bits.data)
        ret (out + 1usize + bits.data.len, ok)
    case .OctetString as data:
        mem.copy[u8](dst[out..out + data.len], data)
        ret (out + data.len, ok)
    case .Oid as arcs:
        out = put_base128(dst, out, arcs[0] * 40u32 + arcs[1])
        var i = 2usize
        while i < arcs.len {
            out = put_base128(dst, out, arcs[i])
            i += 1usize
        }
        ret (out, ok)
    case .Utf8String as text:
        mem.copy[u8](dst[out..out + text.len], text)
        ret (out + text.len, ok)
    case .Sequence as members:
        let (next_at, put_error) = put_items(dst, out, members)
        ret (next_at, put_error)
    case .Set as members:
        let (next_at, put_error) = put_items(dst, out, members)
        if put_error != ok { ret (next_at, put_error) }
        sort_set(dst, content_start, next_at)
        ret (next_at, ok)
    case .Context as tagged:
        let (next_at, put_error) = put_items(dst, out, tagged.items)
        ret (next_at, put_error)
    }
}

// The DER encoding of `item` into `dst`; `TooLarge` when it does not fit.
fn der_encode(dst: []u8, item: *const Item) -> ([]u8, err) {
    let (needed, needed_error) = item_len(item)
    if needed_error != ok { ret (zero, needed_error) }
    if needed > dst.len { ret (zero, TooLarge) }
    let (end, put_error) = put_item(dst, 0usize, item)
    if put_error != ok { ret (zero, put_error) }
    ret (dst[0usize..end], ok)
}

// --- BER.

// A BER header at `at`: the tag, the content length (0 with `indefinite` for the 0x80 form),
// and where the content starts. Nothing about the spelling has to be minimal.
fn ber_header(data: []const u8, at: usize) -> (Tag, usize, bool, usize, err) {
    var tag: Tag = zero
    if at >= data.len { ret (tag, 0usize, false, at, Invalid) }
    var cursor = at
    let first = data[cursor]
    cursor += 1usize
    tag.class = class_of(first)
    tag.constructed = first & 32u8 != 0u8
    tag.number = u32(first & 31u8)
    if tag.number == 31u32 {
        var number = 0u32
        var count = 0usize
        while true {
            if cursor >= data.len { ret (tag, 0usize, false, cursor, Invalid) }
            if count == 5usize { ret (tag, 0usize, false, cursor, TooLarge) }
            let byte = data[cursor]
            cursor += 1usize
            count += 1usize
            number = (number << 7u32) | u32(byte & 127u8)
            if byte & 128u8 == 0u8 { break }
        }
        tag.number = number
    }
    if cursor >= data.len { ret (tag, 0usize, false, cursor, Invalid) }
    let length_first = data[cursor]
    cursor += 1usize
    if length_first == 128u8 {
        if !tag.constructed { ret (tag, 0usize, false, cursor, Invalid) }
        ret (tag, 0usize, true, cursor, ok)
    }
    if length_first < 128u8 {
        if usize(length_first) > data.len - cursor { ret (tag, 0usize, false, cursor, Invalid) }
        ret (tag, usize(length_first), false, cursor, ok)
    }
    let count = usize(length_first & 127u8)
    if cursor + count > data.len { ret (tag, 0usize, false, cursor, Invalid) }
    var length = 0usize
    var i = 0usize
    while i < count {
        if length > 72057594037927935usize { ret (tag, 0usize, false, cursor, TooLarge) }
        length = (length << 8u32) | usize(data[cursor + i])
        i += 1usize
    }
    cursor += count
    if length > data.len - cursor { ret (tag, 0usize, false, cursor, Invalid) }
    ret (tag, length, false, cursor, ok)
}

// A BER INTEGER with any amount of sign padding.
fn ber_integer(c: []const u8) -> (i64, err) {
    if c.len == 0usize { ret (0i64, Invalid) }
    var start = 0usize
    while start + 1usize < c.len && ((c[start] == 0u8 && c[start + 1usize] & 128u8 == 0u8) || (c[start] == 255u8 && c[start + 1usize] & 128u8 != 0u8)) { start += 1usize }
    if c.len - start > 8usize { ret (0i64, TooLarge) }
    var acc = 0u64
    if c[start] & 128u8 != 0u8 { acc = 18446744073709551615u64 }
    var i = start
    while i < c.len {
        acc = (acc << 8u32) | u64(c[i])
        i += 1usize
    }
    ret (mem.bitcast[i64](acc), ok)
}

fn ber_oid(a: *mem.Arena, c: []const u8) -> ([]const u32, err) {
    if c.len == 0usize || c[c.len - 1usize] & 128u8 != 0u8 { ret (zero, Invalid) }
    var count = 1usize
    var i = 0usize
    while i < c.len {
        if c[i] & 128u8 == 0u8 { count += 1usize }
        i += 1usize
    }
    let (arcs, arcs_error) = mem.alloc[u32](a, count)
    if arcs_error != ok { ret (zero, arcs_error) }
    var filled = 0usize
    var arc = 0u32
    i = 0usize
    while i < c.len {
        if arc > 33554431u32 { ret (zero, TooLarge) }
        arc = (arc << 7u32) | u32(c[i] & 127u8)
        if c[i] & 128u8 == 0u8 {
            if filled == 0usize {
                if arc < 80u32 {
                    arcs[0] = arc / 40u32
                    arcs[1] = arc % 40u32
                } else {
                    arcs[0] = 2u32
                    arcs[1] = arc - 80u32
                }
                filled = 2usize
            } else {
                arcs[filled] = arc
                filled += 1usize
            }
            arc = 0u32
        }
        i += 1usize
    }
    ret (arcs[0usize..filled], ok)
}

// The bytes of the string segments in `items`, joined: (bytes, unused bits of the last).
fn ber_join(a: *mem.Arena, items: []const Item) -> ([]u8, u8, err) {
    var total = 0usize
    var unused = 0u8
    var i = 0usize
    while i < items.len {
        switch items[i] {
        case .OctetString as data:
            total += data.len
        case .Utf8String as text:
            total += text.len
        case .BitString as bits:
            total += bits.data.len
            unused = bits.unused
        default:
            ret (zero, 0u8, Invalid)
        }
        i += 1usize
    }
    let (out, out_error) = mem.alloc[u8](a, total)
    if out_error != ok { ret (zero, 0u8, out_error) }
    var at = 0usize
    i = 0usize
    while i < items.len {
        switch items[i] {
        case .OctetString as data:
            mem.copy[u8](out[at..at + data.len], data)
            at += data.len
        case .Utf8String as text:
            mem.copy[u8](out[at..at + text.len], text)
            at += text.len
        case .BitString as bits:
            mem.copy[u8](out[at..at + bits.data.len], bits.data)
            at += bits.data.len
        default:
            ret (zero, 0u8, Invalid)
        }
        i += 1usize
    }
    ret (out, unused, ok)
}

// The items of a constructed value's content: to the end of `data`, or, when `indefinite`, to
// the end-of-contents pair, which is consumed. ponytail: at most 64 members per constructed
// value are gathered on the stack before the copy into the arena; `TooLarge` past that.
fn ber_items(a: *mem.Arena, data: []const u8, at: usize, indefinite: bool, depth: u16) -> ([]const Item, usize, err) {
    var gathered: [64]Item = zero
    var count = 0usize
    var cursor = at
    while true {
        if indefinite {
            if cursor + 1usize >= data.len { ret (zero, cursor, Invalid) }
            if data[cursor] == 0u8 && data[cursor + 1usize] == 0u8 {
                cursor += 2usize
                break
            }
        } else {
            if cursor >= data.len { break }
        }
        if count == 64usize { ret (zero, cursor, TooLarge) }
        let (member, next_at, member_error) = ber_item(a, data, cursor, depth)
        if member_error != ok { ret (zero, cursor, member_error) }
        gathered[count] = member
        count += 1usize
        cursor = next_at
    }
    let (copy, copy_error) = mem.alloc[Item](a, count)
    if copy_error != ok { ret (zero, cursor, copy_error) }
    mem.copy[Item](copy, gathered[0usize..count])
    ret (copy[0usize..], cursor, ok)
}

fn ber_item(a: *mem.Arena, data: []const u8, at: usize, depth: u16) -> (Item, usize, err) {
    var none: Item = .Null
    if depth == 0u16 { ret (none, at, TooDeep) }
    let (tag, length, indefinite, content_at, header_error) = ber_header(data, at)
    if header_error != ok { ret (none, at, header_error) }
    let content = data[content_at..content_at + length]
    var next_at = content_at + length
    var members: []const Item = zero
    if tag.constructed {
        if indefinite {
            let (items, items_end, items_error) = ber_items(a, data, content_at, true, depth - 1u16)
            if items_error != ok { ret (none, at, items_error) }
            members = items
            next_at = items_end
        } else {
            let (items, items_end, items_error) = ber_items(a, content, 0usize, false, depth - 1u16)
            if items_error != ok { ret (none, at, items_error) }
            members = items
        }
    }
    if tag.class == .Context {
        if !tag.constructed { ret (none, at, Invalid) }
        ret (Item{ Context: Context { number: tag.number, items: members } }, next_at, ok)
    }
    if tag.class != .Universal { ret (none, at, Invalid) }
    if tag.number == 16u32 && tag.constructed { ret (Item{ Sequence: members }, next_at, ok) }
    if tag.number == 17u32 && tag.constructed { ret (Item{ Set: members }, next_at, ok) }
    if tag.constructed {
        // A constructed string: its segments joined.
        let (joined, unused, join_error) = ber_join(a, members)
        if join_error != ok { ret (none, at, join_error) }
        if tag.number == 4u32 { ret (Item{ OctetString: joined }, next_at, ok) }
        if tag.number == 12u32 { ret (Item{ Utf8String: joined }, next_at, ok) }
        if tag.number == 3u32 { ret (Item{ BitString: BitString { unused: unused, data: joined } }, next_at, ok) }
        ret (none, at, Invalid)
    }
    if tag.number == 5u32 {
        if content.len != 0usize { ret (none, at, Invalid) }
        ret (none, next_at, ok)
    }
    if tag.number == 1u32 {
        if content.len != 1usize { ret (none, at, Invalid) }
        ret (Item{ Bool: content[0] != 0u8 }, next_at, ok)
    }
    if tag.number == 2u32 {
        let (number, number_error) = ber_integer(content)
        if number_error != ok { ret (none, at, number_error) }
        ret (Item{ Integer: number }, next_at, ok)
    }
    if tag.number == 6u32 {
        let (arcs, arcs_error) = ber_oid(a, content)
        if arcs_error != ok { ret (none, at, arcs_error) }
        ret (Item{ Oid: arcs }, next_at, ok)
    }
    if tag.number == 3u32 {
        if content.len == 0usize || content[0] > 7u8 { ret (none, at, Invalid) }
        ret (Item{ BitString: BitString { unused: content[0], data: content[1usize..] } }, next_at, ok)
    }
    if tag.number == 4u32 { ret (Item{ OctetString: content }, next_at, ok) }
    if tag.number == 12u32 || tag.number == 19u32 || tag.number == 22u32 { ret (Item{ Utf8String: content }, next_at, ok) }
    ret (none, at, Invalid)
}

// One BER value spanning the whole of `source`, as an `Item`; strings borrow from `source`
// unless they were constructed, and containers are copied into the arena.
fn ber_decode(a: *mem.Arena, source: []const u8, max_depth: u16) -> (Item, err) {
    let (item, end, item_error) = ber_item(a, source, 0usize, max_depth)
    if item_error != ok { ret (item, item_error) }
    if end != source.len { ret (item, Invalid) }
    ret (item, ok)
}
