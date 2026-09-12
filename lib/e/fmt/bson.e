// BSON: documents parsed from a byte slice into an arena-owned `Value` tree bounded by
// `max_depth`, sized and written back over `e.io`, and the typed codec of the other
// codecs: a struct is a document of its fields walked by `meta.fields`, flat records
// only. The element tags carried are double (0x01), string (0x02), document (0x03),
// array (0x04), binary (0x05), bool (0x08), null (0x0A), int32 (0x10) and int64
// (0x12); any other tag is `Invalid`, so JavaScript, regex and the deprecated tags
// never reach the value model. Array keys are not checked against their positions
// on the way in and are written as "0", "1", ... on the way out.
use e.io
use e.mem
use e.meta

type Element = struct { key: str, value: Value }
type Binary = struct { subtype: u8, data: []const u8 }
type Value = union enum u8 { Double: f64, String: str, Document: []const Element, Array: []const Value, Binary: Binary, Bool: bool, Null, I32: i32, I64: i64 }
error Invalid
error TooDeep
error TooLarge

fn read_le32(source: []const u8, at: usize) -> u32 {
    ret u32(source[at]) | (u32(source[at + 1usize]) << 8u32) | (u32(source[at + 2usize]) << 16u32) | (u32(source[at + 3usize]) << 24u32)
}

fn read_le64(source: []const u8, at: usize) -> u64 {
    ret u64(read_le32(source, at)) | (u64(read_le32(source, at + 4usize)) << 32u32)
}

// A document's length prefix checked against the bytes that hold it.
fn document_span(source: []const u8, at: usize) -> (usize, err) {
    if source.len - at < 5usize { ret (0usize, Invalid) }
    let length = usize(read_le32(source, at))
    if length < 5usize || length > source.len - at { ret (0usize, Invalid) }
    if source[at + length - 1usize] != 0u8 { ret (0usize, Invalid) }
    ret (length, ok)
}

fn cstring_end(source: []const u8, at: usize, limit: usize) -> (usize, err) {
    var end = at
    while end < limit && source[end] != 0u8 { end += 1usize }
    if end >= limit { ret (0usize, Invalid) }
    ret (end, ok)
}

// The elements of the document at `at`, whose span was already checked.
fn parse_document(a: *mem.Arena, source: []const u8, at: usize, length: usize, depth: u16, max_depth: u16) -> ([]const Element, err) {
    if depth >= max_depth { ret (zero, TooDeep) }
    let limit = at + length - 1usize
    // Count first, then fill.
    var count = 0usize
    var cursor = at + 4usize
    while cursor < limit {
        let (key_end, key_error) = cstring_end(source, cursor + 1usize, limit)
        if key_error != ok { ret (zero, key_error) }
        let (span, span_error) = value_span(source, source[cursor], key_end + 1usize, limit)
        if span_error != ok { ret (zero, span_error) }
        cursor = key_end + 1usize + span
        count += 1usize
    }
    if cursor != limit { ret (zero, Invalid) }
    let (elements, elements_error) = mem.alloc[Element](a, count)
    if elements_error != ok { ret (zero, elements_error) }
    var index = 0usize
    cursor = at + 4usize
    while index < count {
        let tag = source[cursor]
        let (key_end, key_error) = cstring_end(source, cursor + 1usize, limit)
        if key_error != ok { ret (zero, key_error) }
        elements[index].key = source[cursor + 1usize..key_end]
        let (value, span, value_error) = parse_value(a, source, tag, key_end + 1usize, limit, depth, max_depth)
        if value_error != ok { ret (zero, value_error) }
        elements[index].value = value
        cursor = key_end + 1usize + span
        index += 1usize
    }
    ret (elements[0..], ok)
}

// How many bytes the value of `tag` at `at` takes, bounded by `limit`.
fn value_span(source: []const u8, tag: u8, at: usize, limit: usize) -> (usize, err) {
    let room = limit - at
    if tag == 1u8 || tag == 18u8 {
        if room < 8usize { ret (0usize, Invalid) }
        ret (8usize, ok)
    }
    if tag == 16u8 {
        if room < 4usize { ret (0usize, Invalid) }
        ret (4usize, ok)
    }
    if tag == 8u8 {
        if room < 1usize { ret (0usize, Invalid) }
        if source[at] > 1u8 { ret (0usize, Invalid) }
        ret (1usize, ok)
    }
    if tag == 10u8 { ret (0usize, ok) }
    if tag == 2u8 {
        if room < 5usize { ret (0usize, Invalid) }
        let length = usize(read_le32(source, at))
        if length < 1usize || length > room - 4usize { ret (0usize, Invalid) }
        if source[at + 4usize + length - 1usize] != 0u8 { ret (0usize, Invalid) }
        ret (4usize + length, ok)
    }
    if tag == 5u8 {
        if room < 5usize { ret (0usize, Invalid) }
        let length = usize(read_le32(source, at))
        if length > room - 5usize { ret (0usize, Invalid) }
        ret (5usize + length, ok)
    }
    if tag == 3u8 || tag == 4u8 {
        let (length, length_error) = document_span(source[..limit], at)
        if length_error != ok { ret (0usize, length_error) }
        ret (length, ok)
    }
    ret (0usize, Invalid)
}

fn parse_value(a: *mem.Arena, source: []const u8, tag: u8, at: usize, limit: usize, depth: u16, max_depth: u16) -> (Value, usize, err) {
    var none: Value = .Null
    let (span, span_error) = value_span(source, tag, at, limit)
    if span_error != ok { ret (none, 0usize, span_error) }
    if tag == 1u8 { ret (Value{ Double: mem.bitcast[f64](read_le64(source, at)) }, span, ok) }
    if tag == 18u8 { ret (Value{ I64: mem.bitcast[i64](read_le64(source, at)) }, span, ok) }
    if tag == 16u8 { ret (Value{ I32: mem.bitcast[i32](read_le32(source, at)) }, span, ok) }
    if tag == 8u8 { ret (Value{ Bool: source[at] == 1u8 }, span, ok) }
    if tag == 10u8 { ret (none, span, ok) }
    if tag == 2u8 { ret (Value{ String: source[at + 4usize..at + span - 1usize] }, span, ok) }
    if tag == 5u8 {
        var binary: Binary = zero
        binary.subtype = source[at + 4usize]
        binary.data = source[at + 5usize..at + span]
        ret (Value{ Binary: binary }, span, ok)
    }
    let (elements, elements_error) = parse_document(a, source, at, span, depth + 1u16, max_depth)
    if elements_error != ok { ret (none, 0usize, elements_error) }
    if tag == 3u8 { ret (Value{ Document: elements }, span, ok) }
    let (items, items_error) = mem.alloc[Value](a, elements.len)
    if items_error != ok { ret (none, 0usize, items_error) }
    var index = 0usize
    while index < elements.len {
        items[index] = elements[index].value
        index += 1usize
    }
    ret (Value{ Array: items[0..] }, span, ok)
}

fn parse(a: *mem.Arena, source: []const u8, max_depth: u16) -> (Value, err) {
    var none: Value = .Null
    let (length, length_error) = document_span(source, 0usize)
    if length_error != ok { ret (none, length_error) }
    if length != source.len { ret (none, Invalid) }
    let (elements, elements_error) = parse_document(a, source, 0usize, length, 0u16, max_depth)
    if elements_error != ok { ret (none, elements_error) }
    ret (Value{ Document: elements }, ok)
}

// The decimal digits of an array index, into a stack buffer.
fn index_key(index: usize, out: []u8) -> []u8 {
    var digits = 0usize
    var v = index
    var scratch: [20]u8 = zero
    if v == 0usize {
        scratch[0] = 48u8
        digits = 1usize
    }
    while v > 0usize {
        scratch[digits] = 48u8 + u8(v % 10usize)
        v = v / 10usize
        digits += 1usize
    }
    var i = 0usize
    while i < digits {
        out[i] = scratch[digits - 1usize - i]
        i += 1usize
    }
    ret out[0usize..digits]
}

fn elements_size(elements: []const Element) -> (usize, err) {
    var total = 5usize
    var index = 0usize
    while index < elements.len {
        let (inner, inner_error) = size(&elements[index].value)
        if inner_error != ok { ret (0usize, inner_error) }
        total += 2usize + elements[index].key.len + inner
        index += 1usize
    }
    if total > 2147483647usize { ret (0usize, TooLarge) }
    ret (total, ok)
}

fn size(value: *const Value) -> (usize, err) {
    switch *value {
    case .Double as number:
        ret (8usize, ok)
    case .I64 as wide:
        ret (8usize, ok)
    case .I32 as narrow:
        ret (4usize, ok)
    case .Bool as flag:
        ret (1usize, ok)
    case .Null:
        ret (0usize, ok)
    case .String as text:
        if text.len > 2147483646usize { ret (0usize, TooLarge) }
        ret (5usize + text.len, ok)
    case .Binary as binary:
        if binary.data.len > 2147483647usize { ret (0usize, TooLarge) }
        ret (5usize + binary.data.len, ok)
    case .Document as elements:
        let (total, total_error) = elements_size(elements)
        ret (total, total_error)
    case .Array as items:
        var total = 5usize
        var index = 0usize
        var key: [20]u8 = zero
        while index < items.len {
            let (inner, inner_error) = size(&items[index])
            if inner_error != ok { ret (0usize, inner_error) }
            total += 2usize + index_key(index, key[0..]).len + inner
            index += 1usize
        }
        if total > 2147483647usize { ret (0usize, TooLarge) }
        ret (total, ok)
    }
}

fn write_le(writer: *io.Writer, value: u64, width: usize) -> err {
    var raw: [8]u8 = zero
    var at = 0usize
    while at < width {
        raw[at] = u8((value >> u32(at * 8usize)) & 255u64)
        at += 1usize
    }
    ret io.write_all(writer, raw[..width])
}

fn write_byte(writer: *io.Writer, value: u8) -> err {
    var one: [1]u8 = zero
    one[0] = value
    ret io.write_all(writer, one[0..])
}

fn tag_of(value: *const Value) -> u8 {
    switch *value {
    case .Double as number:
        ret 1u8
    case .String as text:
        ret 2u8
    case .Document as elements:
        ret 3u8
    case .Array as items:
        ret 4u8
    case .Binary as binary:
        ret 5u8
    case .Bool as flag:
        ret 8u8
    case .Null:
        ret 10u8
    case .I32 as narrow:
        ret 16u8
    case .I64 as wide:
        ret 18u8
    }
}

fn write_element(writer: *io.Writer, key: []const u8, value: *const Value) -> err {
    try write_byte(writer, tag_of(value))
    try io.write_all(writer, key)
    try write_byte(writer, 0u8)
    ret write(writer, value)
}

fn write(writer: *io.Writer, value: *const Value) -> err {
    switch *value {
    case .Double as number:
        ret write_le(writer, mem.bitcast[u64](number), 8usize)
    case .I64 as wide:
        ret write_le(writer, mem.bitcast[u64](wide), 8usize)
    case .I32 as narrow:
        ret write_le(writer, u64(mem.bitcast[u32](narrow)), 4usize)
    case .Bool as flag:
        if flag { ret write_byte(writer, 1u8) }
        ret write_byte(writer, 0u8)
    case .Null:
        ret ok
    case .String as text:
        if text.len > 2147483646usize { ret TooLarge }
        try write_le(writer, u64(text.len + 1usize), 4usize)
        try io.write_all(writer, text)
        ret write_byte(writer, 0u8)
    case .Binary as binary:
        if binary.data.len > 2147483647usize { ret TooLarge }
        try write_le(writer, u64(binary.data.len), 4usize)
        try write_byte(writer, binary.subtype)
        ret io.write_all(writer, binary.data)
    case .Document as elements:
        let (total, total_error) = elements_size(elements)
        if total_error != ok { ret total_error }
        try write_le(writer, u64(total), 4usize)
        var index = 0usize
        while index < elements.len {
            try write_element(writer, elements[index].key, &elements[index].value)
            index += 1usize
        }
        ret write_byte(writer, 0u8)
    case .Array as items:
        let (total, total_error) = size(value)
        if total_error != ok { ret total_error }
        try write_le(writer, u64(total), 4usize)
        var index = 0usize
        var key: [20]u8 = zero
        while index < items.len {
            try write_element(writer, index_key(index, key[0..]), &items[index])
            index += 1usize
        }
        ret write_byte(writer, 0u8)
    }
}

// The typed codec: a struct is a document keyed by field name; a missing key keeps its
// zero, an unknown key is skipped, a field of a kind without an arm is `Invalid`.
fn element_of(elements: []const Element, name: str) -> (Value, bool) {
    var none: Value = .Null
    var index = 0usize
    while index < elements.len {
        if elements[index].key.len == name.len {
            var same = true
            var i = 0usize
            while i < name.len {
                if elements[index].key[i] != name[i] { same = false }
                i += 1usize
            }
            if same { ret (elements[index].value, true) }
        }
        index += 1usize
    }
    ret (none, false)
}

fn integer_of(value: Value) -> (i64, bool) {
    switch value {
    case .I32 as narrow:
        ret (i64(narrow), true)
    case .I64 as wide:
        ret (wide, true)
    default:
        ret (0i64, false)
    }
}

fn float_of(value: Value) -> (f64, bool) {
    switch value {
    case .Double as number:
        ret (number, true)
    case .I32 as narrow:
        ret (f64(narrow), true)
    case .I64 as wide:
        ret (f64(wide), true)
    default:
        ret (0.0, false)
    }
}

fn decode[T: type](a: *mem.Arena, source: []const u8, max_depth: u16) -> (T, err) {
    var out: T = zero
    let (root, parse_error) = parse(a, source, max_depth)
    if parse_error != ok { ret (out, parse_error) }
    var elements: []const Element = zero
    switch root {
    case .Document as found:
        elements = found
    default:
        ret (out, Invalid)
    }
    for f in meta.fields[T]() {
        let (found, present) = element_of(elements, f.name)
        if present {
            if meta.kind[f.ty]() == .Slice {
                var text = ""
                switch found {
                case .String as written:
                    text = written
                default:
                    ret (out, Invalid)
                }
                meta.set[f, T](&out, text)
            } else {
            if meta.kind[f.ty]() == .Bool {
                var flag = false
                switch found {
                case .Bool as written:
                    flag = written
                default:
                    ret (out, Invalid)
                }
                meta.set[f, T](&out, flag)
            } else {
            if meta.kind[f.ty]() == .Int {
                let (number, is_integer) = integer_of(found)
                if !is_integer { ret (out, Invalid) }
                var slot: f.ty = zero
                slot = f.ty(number)
                meta.set[f, T](&out, slot)
            } else {
            if meta.kind[f.ty]() == .Float {
                let (number, is_number) = float_of(found)
                if !is_number { ret (out, Invalid) }
                var slot: f.ty = zero
                slot = f.ty(number)
                meta.set[f, T](&out, slot)
            } else {
                ret (out, Invalid)
            }
            }
            }
            }
        }
    }
    ret (out, ok)
}

fn encode[T: type](writer: *io.Writer, value: *const T) -> err {
    // Integers go as int64, floats as double, strings as string, bools as bool.
    var total = 5usize
    for f in meta.fields[T]() {
        var slot: f.ty = zero
        slot = meta.get[f, T](value)
        total += 2usize + f.name.len
        if meta.kind[f.ty]() == .Slice {
            total += 5usize + slot.len
        } else {
        if meta.kind[f.ty]() == .Bool {
            total += 1usize
        } else {
        if meta.kind[f.ty]() == .Int {
            total += 8usize
        } else {
        if meta.kind[f.ty]() == .Float {
            total += 8usize
        } else {
            ret Invalid
        }
        }
        }
        }
    }
    if total > 2147483647usize { ret TooLarge }
    try write_le(writer, u64(total), 4usize)
    for f in meta.fields[T]() {
        var slot: f.ty = zero
        slot = meta.get[f, T](value)
        if meta.kind[f.ty]() == .Slice {
            let item: Value = Value{ String: slot }
            try write_element(writer, f.name, &item)
        } else {
        if meta.kind[f.ty]() == .Bool {
            let item: Value = Value{ Bool: slot }
            try write_element(writer, f.name, &item)
        } else {
        if meta.kind[f.ty]() == .Int {
            let item: Value = Value{ I64: i64(slot) }
            try write_element(writer, f.name, &item)
        } else {
            let item: Value = Value{ Double: f64(slot) }
            try write_element(writer, f.name, &item)
        }
        }
        }
    }
    ret write_byte(writer, 0u8)
}
