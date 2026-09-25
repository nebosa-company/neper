// MessagePack: the whole format both ways over `e.io` streams -- nil, bools, the
// integer families (written in their smallest form), both floats, str, bin, arrays,
// maps and ext -- into an arena-owned `Value` tree bounded by `max_depth`, and the
// typed codec that `e.fmt.json` has: a struct is a map of its fields, walked by
// `meta.fields` with one arm per field kind, flat records only.
//
// A reader keeps a one-byte source for the format byte and reads each item's bytes
// exactly; nothing is buffered, so a stream can be read piecemeal by the caller.

use e.io
use e.mem
use e.meta
use e.str

type Pair = struct { key: Value, value: Value }
type Ext = struct { kind: i8, data: []const u8 }
type Value = union enum u8 { Nil, Bool: bool, I64: i64, U64: u64, F64: f64, String: str, Binary: []const u8, Array: []const Value, Map: []const Pair, Ext: Ext }
type Reader = struct { state: *void }
error Invalid
error TooDeep
error TooLarge

type State = struct { source: io.Reader, max_depth: u16 }

fn reader(a: *mem.Arena, source: io.Reader, max_depth: u16) -> (Reader, err) {
    let (storage, storage_error) = mem.alloc[State](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    storage[0].source = source
    storage[0].max_depth = max_depth
    var r: Reader = zero
    r.state = mem.cast[*void](&storage[0])
    ret (r, ok)
}

fn read_exact(s: *State, dst: []u8) -> err { ret io.read_exact(&s.source, dst) }

fn read_u8(s: *State) -> (u8, err) {
    var one: [1]u8 = zero
    let read_error = read_exact(s, one[0..])
    if read_error != ok { ret (0u8, read_error) }
    ret (one[0], ok)
}

fn read_be(s: *State, width: usize) -> (u64, err) {
    var raw: [8]u8 = zero
    let read_error = read_exact(s, raw[..width])
    if read_error != ok { ret (0u64, read_error) }
    var value = 0u64
    var at = 0usize
    while at < width {
        value = (value << 8u32) | u64(raw[at])
        at += 1usize
    }
    ret (value, ok)
}

fn read_bytes(a: *mem.Arena, s: *State, count: usize) -> ([]u8, err) {
    if count > 16777216usize { ret (zero, TooLarge) }
    let (out, out_error) = mem.alloc[u8](a, count)
    if out_error != ok { ret (zero, out_error) }
    let read_error = read_exact(s, out)
    if read_error != ok { ret (zero, read_error) }
    ret (out, ok)
}

fn sign_extend(value: u64, width: usize) -> i64 {
    let shift = u32(64usize - width * 8usize)
    ret i64.trunc(value << shift) >> shift
}

fn read_value(a: *mem.Arena, r: *Reader) -> (Value, err) {
    let s = mem.cast[*State](r.state)
    let (value, read_error) = read_depth(a, s, 0u16)
    ret (value, read_error)
}

fn read_depth(a: *mem.Arena, s: *State, depth: u16) -> (Value, err) {
    var nil_value: Value = .Nil
    let (format, format_error) = read_u8(s)
    if format_error != ok { ret (nil_value, format_error) }
    // Positive and negative fixint.
    if format < 128u8 { ret (Value{ I64: i64(format) }, ok) }
    if format >= 224u8 { ret (Value{ I64: i64(format) - 256i64 }, ok) }
    // fixstr, fixarray, fixmap.
    if format >= 160u8 && format <= 191u8 {
        let (text, text_error) = read_bytes(a, s, usize(format - 160u8))
        if text_error != ok { ret (nil_value, text_error) }
        ret (Value{ String: text[0..] }, ok)
    }
    if format >= 144u8 && format <= 159u8 {
        let (items, items_error) = read_array(a, s, usize(format - 144u8), depth)
        if items_error != ok { ret (nil_value, items_error) }
        ret (Value{ Array: items }, ok)
    }
    if format >= 128u8 && format <= 143u8 {
        let (pairs, pairs_error) = read_map(a, s, usize(format - 128u8), depth)
        if pairs_error != ok { ret (nil_value, pairs_error) }
        ret (Value{ Map: pairs }, ok)
    }
    if format == 192u8 { ret (nil_value, ok) }
    if format == 194u8 { ret (Value{ Bool: false }, ok) }
    if format == 195u8 { ret (Value{ Bool: true }, ok) }
    if format == 193u8 { ret (nil_value, Invalid) }
    // bin 8/16/32
    if format >= 196u8 && format <= 198u8 {
        let (count, count_error) = read_be(s, 1usize << u32(format - 196u8))
        if count_error != ok { ret (nil_value, count_error) }
        let (data, data_error) = read_bytes(a, s, usize(count))
        if data_error != ok { ret (nil_value, data_error) }
        ret (Value{ Binary: data[0..] }, ok)
    }
    // ext 8/16/32
    if format >= 199u8 && format <= 201u8 {
        let (count, count_error) = read_be(s, 1usize << u32(format - 199u8))
        if count_error != ok { ret (nil_value, count_error) }
        let (ext, ext_error) = read_ext(a, s, usize(count))
        if ext_error != ok { ret (nil_value, ext_error) }
        ret (Value{ Ext: ext }, ok)
    }
    if format == 202u8 {
        let (bits, bits_error) = read_be(s, 4usize)
        if bits_error != ok { ret (nil_value, bits_error) }
        ret (Value{ F64: f64(mem.bitcast[f32](u32(bits))) }, ok)
    }
    if format == 203u8 {
        let (bits, bits_error) = read_be(s, 8usize)
        if bits_error != ok { ret (nil_value, bits_error) }
        ret (Value{ F64: mem.bitcast[f64](bits) }, ok)
    }
    // uint 8/16/32/64
    if format >= 204u8 && format <= 207u8 {
        let (bits, bits_error) = read_be(s, 1usize << u32(format - 204u8))
        if bits_error != ok { ret (nil_value, bits_error) }
        ret (Value{ U64: bits }, ok)
    }
    // int 8/16/32/64
    if format >= 208u8 && format <= 211u8 {
        let width = 1usize << u32(format - 208u8)
        let (bits, bits_error) = read_be(s, width)
        if bits_error != ok { ret (nil_value, bits_error) }
        ret (Value{ I64: sign_extend(bits, width) }, ok)
    }
    // fixext 1/2/4/8/16
    if format >= 212u8 && format <= 216u8 {
        let (ext, ext_error) = read_ext(a, s, 1usize << u32(format - 212u8))
        if ext_error != ok { ret (nil_value, ext_error) }
        ret (Value{ Ext: ext }, ok)
    }
    // str 8/16/32
    if format >= 217u8 && format <= 219u8 {
        let (count, count_error) = read_be(s, 1usize << u32(format - 217u8))
        if count_error != ok { ret (nil_value, count_error) }
        let (text, text_error) = read_bytes(a, s, usize(count))
        if text_error != ok { ret (nil_value, text_error) }
        ret (Value{ String: text[0..] }, ok)
    }
    // array 16/32, map 16/32
    if format == 220u8 || format == 221u8 {
        let (count, count_error) = read_be(s, 2usize << u32(format - 220u8))
        if count_error != ok { ret (nil_value, count_error) }
        let (items, items_error) = read_array(a, s, usize(count), depth)
        if items_error != ok { ret (nil_value, items_error) }
        ret (Value{ Array: items }, ok)
    }
    if format == 222u8 || format == 223u8 {
        let (count, count_error) = read_be(s, 2usize << u32(format - 222u8))
        if count_error != ok { ret (nil_value, count_error) }
        let (pairs, pairs_error) = read_map(a, s, usize(count), depth)
        if pairs_error != ok { ret (nil_value, pairs_error) }
        ret (Value{ Map: pairs }, ok)
    }
    ret (nil_value, Invalid)
}

fn read_ext(a: *mem.Arena, s: *State, count: usize) -> (Ext, err) {
    let (kind, kind_error) = read_u8(s)
    if kind_error != ok { ret (zero, kind_error) }
    let (data, data_error) = read_bytes(a, s, count)
    if data_error != ok { ret (zero, data_error) }
    var e: Ext = zero
    e.kind = i8.trunc(kind)
    e.data = data[0..]
    ret (e, ok)
}

fn read_array(a: *mem.Arena, s: *State, count: usize, depth: u16) -> ([]const Value, err) {
    if depth >= s.max_depth { ret (zero, TooDeep) }
    if count > 16777216usize { ret (zero, TooLarge) }
    let (items, items_error) = mem.alloc[Value](a, count)
    if items_error != ok { ret (zero, items_error) }
    var at = 0usize
    while at < count {
        let (item, item_error) = read_depth(a, s, depth + 1u16)
        if item_error != ok { ret (zero, item_error) }
        items[at] = item
        at += 1usize
    }
    ret (items[0..], ok)
}

fn read_map(a: *mem.Arena, s: *State, count: usize, depth: u16) -> ([]const Pair, err) {
    if depth >= s.max_depth { ret (zero, TooDeep) }
    if count > 16777216usize { ret (zero, TooLarge) }
    let (pairs, pairs_error) = mem.alloc[Pair](a, count)
    if pairs_error != ok { ret (zero, pairs_error) }
    var at = 0usize
    while at < count {
        let (key, key_error) = read_depth(a, s, depth + 1u16)
        if key_error != ok { ret (zero, key_error) }
        let (value, value_error) = read_depth(a, s, depth + 1u16)
        if value_error != ok { ret (zero, value_error) }
        pairs[at].key = key
        pairs[at].value = value
        at += 1usize
    }
    ret (pairs[0..], ok)
}

fn write_be(writer: *io.Writer, value: u64, width: usize) -> err {
    var raw: [8]u8 = zero
    var at = 0usize
    while at < width {
        raw[at] = u8((value >> u32((width - 1usize - at) * 8usize)) & 255u64)
        at += 1usize
    }
    ret io.write_all(writer, raw[..width])
}

fn write_byte(writer: *io.Writer, value: u8) -> err {
    var one: [1]u8 = zero
    one[0] = value
    ret io.write_all(writer, one[0..])
}

// A length prefix with the smallest of three formats, `base` being the 8-bit one.
fn write_length(writer: *io.Writer, base: u8, count: usize) -> err {
    if count < 256usize {
        try write_byte(writer, base)
        ret write_be(writer, u64(count), 1usize)
    }
    if count < 65536usize {
        try write_byte(writer, base + 1u8)
        ret write_be(writer, u64(count), 2usize)
    }
    if count > 4294967295usize { ret TooLarge }
    try write_byte(writer, base + 2u8)
    ret write_be(writer, u64(count), 4usize)
}

fn write_i64(writer: *io.Writer, value: i64) -> err {
    if value >= 0i64 { ret write_u64(writer, u64(value)) }
    if value >= -32i64 { ret write_byte(writer, u8(i64(256i64) + value)) }
    if value >= -128i64 {
        try write_byte(writer, 208u8)
        ret write_be(writer, u64.trunc(value) & 255u64, 1usize)
    }
    if value >= -32768i64 {
        try write_byte(writer, 209u8)
        ret write_be(writer, u64.trunc(value) & 65535u64, 2usize)
    }
    if value >= -2147483648i64 {
        try write_byte(writer, 210u8)
        ret write_be(writer, u64.trunc(value) & 4294967295u64, 4usize)
    }
    try write_byte(writer, 211u8)
    ret write_be(writer, u64.trunc(value), 8usize)
}

fn write_u64(writer: *io.Writer, value: u64) -> err {
    if value < 128u64 { ret write_byte(writer, u8(value)) }
    if value < 256u64 {
        try write_byte(writer, 204u8)
        ret write_be(writer, value, 1usize)
    }
    if value < 65536u64 {
        try write_byte(writer, 205u8)
        ret write_be(writer, value, 2usize)
    }
    if value < 4294967296u64 {
        try write_byte(writer, 206u8)
        ret write_be(writer, value, 4usize)
    }
    try write_byte(writer, 207u8)
    ret write_be(writer, value, 8usize)
}

fn write_string(writer: *io.Writer, text: str) -> err {
    if text.len < 32usize {
        try write_byte(writer, 160u8 + u8(text.len))
    } else {
        try write_length(writer, 217u8, text.len)
    }
    ret io.write_all(writer, text)
}

fn write(writer: *io.Writer, value: *const Value) -> err {
    switch *value {
    case .Nil:
        ret write_byte(writer, 192u8)
    case .Bool as flag:
        if flag { ret write_byte(writer, 195u8) }
        ret write_byte(writer, 194u8)
    case .I64 as signed:
        ret write_i64(writer, signed)
    case .U64 as unsigned:
        ret write_u64(writer, unsigned)
    case .F64 as number:
        try write_byte(writer, 203u8)
        ret write_be(writer, mem.bitcast[u64](number), 8usize)
    case .String as text:
        ret write_string(writer, text)
    case .Binary as data:
        try write_length(writer, 196u8, data.len)
        ret io.write_all(writer, data)
    case .Array as items:
        if items.len < 16usize {
            try write_byte(writer, 144u8 + u8(items.len))
        } else {
            if items.len < 65536usize {
                try write_byte(writer, 220u8)
                try write_be(writer, u64(items.len), 2usize)
            } else {
                if items.len > 4294967295usize { ret TooLarge }
                try write_byte(writer, 221u8)
                try write_be(writer, u64(items.len), 4usize)
            }
        }
        var at = 0usize
        while at < items.len {
            try write(writer, &items[at])
            at += 1usize
        }
        ret ok
    case .Map as pairs:
        if pairs.len < 16usize {
            try write_byte(writer, 128u8 + u8(pairs.len))
        } else {
            if pairs.len < 65536usize {
                try write_byte(writer, 222u8)
                try write_be(writer, u64(pairs.len), 2usize)
            } else {
                if pairs.len > 4294967295usize { ret TooLarge }
                try write_byte(writer, 223u8)
                try write_be(writer, u64(pairs.len), 4usize)
            }
        }
        var at = 0usize
        while at < pairs.len {
            try write(writer, &pairs[at].key)
            try write(writer, &pairs[at].value)
            at += 1usize
        }
        ret ok
    case .Ext as ext:
        let n = ext.data.len
        if n == 1usize || n == 2usize || n == 4usize || n == 8usize || n == 16usize {
            var format = 212u8
            var size = 1usize
            while size < n {
                size = size * 2usize
                format += 1u8
            }
            try write_byte(writer, format)
        } else {
            try write_length(writer, 199u8, n)
        }
        try write_byte(writer, u8.trunc(ext.kind))
        ret io.write_all(writer, ext.data)
    }
}

// The typed codec: a struct is a map from field names to their values; a field missing
// from the map keeps its zero, an unknown key is skipped, and a field of a kind the
// codec has no arm for is `Invalid`.
fn pair_of(pairs: []const Pair, name: str) -> (Value, bool) {
    var none: Value = .Nil
    var at = 0usize
    while at < pairs.len {
        var matched = false
        switch pairs[at].key {
        case .String as key:
            matched = str.eq(key, name)
        default:
            matched = false
        }
        if matched { ret (pairs[at].value, true) }
        at += 1usize
    }
    ret (none, false)
}

fn integer_of(value: Value) -> (i64, u64, bool, bool) {
    switch value {
    case .I64 as signed:
        ret (signed, 0u64, true, true)
    case .U64 as unsigned:
        ret (0i64, unsigned, false, true)
    default:
        ret (0i64, 0u64, false, false)
    }
}

fn float_of(value: Value) -> (f64, bool) {
    switch value {
    case .F64 as number:
        ret (number, true)
    case .I64 as signed:
        ret (f64(signed), true)
    case .U64 as unsigned:
        ret (f64(unsigned), true)
    default:
        ret (0.0, false)
    }
}

fn decode[T: type](a: *mem.Arena, source: io.Reader, max_depth: u16) -> (T, err) {
    var out: T = zero
    let (r0, reader_error) = reader(a, source, max_depth)
    if reader_error != ok { ret (out, reader_error) }
    var r = r0
    let (root, read_error) = read_value(a, &r)
    if read_error != ok { ret (out, read_error) }
    var pairs: []const Pair = zero
    switch root {
    case .Map as found:
        pairs = found
    default:
        ret (out, Invalid)
    }
    for f in meta.fields[T]() {
        let (found, present) = pair_of(pairs, f.name)
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
                let (signed, unsigned, is_signed, is_integer) = integer_of(found)
                if !is_integer { ret (out, Invalid) }
                var slot: f.ty = zero
                if is_signed { slot = f.ty(signed) } else { slot = f.ty(unsigned) }
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
    var count = 0usize
    for f in meta.fields[T]() {
        count += 1usize
    }
    if count < 16usize {
        try write_byte(writer, 128u8 + u8(count))
    } else {
        try write_byte(writer, 222u8)
        try write_be(writer, u64(count), 2usize)
    }
    for f in meta.fields[T]() {
        try write_string(writer, f.name)
        var slot: f.ty = zero
        slot = meta.get[f, T](value)
        if meta.kind[f.ty]() == .Slice {
            try write_string(writer, slot)
        } else {
        if meta.kind[f.ty]() == .Bool {
            if slot { try write_byte(writer, 195u8) } else { try write_byte(writer, 194u8) }
        } else {
        if meta.kind[f.ty]() == .Int {
            if slot < 0 {
                try write_i64(writer, i64(slot))
            } else {
                try write_u64(writer, u64(slot))
            }
        } else {
        if meta.kind[f.ty]() == .Float {
            try write_byte(writer, 203u8)
            try write_be(writer, mem.bitcast[u64](f64(slot)), 8usize)
        } else {
            ret Invalid
        }
        }
        }
        }
    }
    ret ok
}
