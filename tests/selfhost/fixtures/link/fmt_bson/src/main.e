// `e.fmt.bson`: a Python-built document with every carried tag parsed and walked,
// sized and written back byte for byte, a struct decoded from it and encoded into the
// int64/double form, and the refusals: a length past the data, a missing terminator,
// an unknown tag, a bool of 2, a depth limit hit. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.bson as bson

type Rec = struct { name: str, count: i32, ratio: f64, flag: bool }

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let doc: [131]u8 = [131]u8{ 131, 0, 0, 0, 2, 110, 97, 109, 101, 0, 6, 0, 0, 0, 110, 101, 112, 101, 114, 0, 16, 99, 111, 117, 110, 116, 0, 249, 255, 255, 255, 18, 98, 105, 103, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 114, 97, 116, 105, 111, 0, 0, 0, 0, 0, 0, 0, 248, 63, 8, 102, 108, 97, 103, 0, 1, 10, 110, 111, 110, 101, 0, 5, 98, 108, 111, 98, 0, 3, 0, 0, 0, 128, 1, 2, 3, 3, 115, 117, 98, 0, 12, 0, 0, 0, 16, 120, 0, 1, 0, 0, 0, 0, 4, 108, 105, 115, 116, 0, 21, 0, 0, 0, 16, 48, 0, 10, 0, 0, 0, 2, 49, 0, 2, 0, 0, 0, 98, 0, 0, 0 }
    let typed: [58]u8 = [58]u8{ 58, 0, 0, 0, 2, 110, 97, 109, 101, 0, 6, 0, 0, 0, 110, 101, 112, 101, 114, 0, 18, 99, 111, 117, 110, 116, 0, 249, 255, 255, 255, 255, 255, 255, 255, 1, 114, 97, 116, 105, 111, 0, 0, 0, 0, 0, 0, 0, 248, 63, 8, 102, 108, 97, 103, 0, 1, 0 }
    let (root, e1) = bson.parse(a, doc[0..], 4u16)
    if e1 != ok { os.exit(1) }
    var elements: []const bson.Element = zero
    switch root {
    case .Document as found:
        elements = found
    default:
        os.exit(2)
    }
    if elements.len != 9usize { os.exit(3) }
    if !str.eq(elements[0].key, "name") { os.exit(4) }
    switch elements[0].value {
    case .String as text:
        if !str.eq(text, "neper") { os.exit(5) }
    default:
        os.exit(6)
    }
    switch elements[1].value {
    case .I32 as narrow:
        if narrow != -7 { os.exit(7) }
    default:
        os.exit(8)
    }
    switch elements[2].value {
    case .I64 as wide:
        if wide != 1099511627776i64 { os.exit(9) }
    default:
        os.exit(10)
    }
    switch elements[3].value {
    case .Double as number:
        if number != 1.5 { os.exit(11) }
    default:
        os.exit(12)
    }
    switch elements[4].value {
    case .Bool as flag:
        if !flag { os.exit(13) }
    default:
        os.exit(14)
    }
    var is_null = false
    switch elements[5].value {
    case .Null:
        is_null = true
    default:
        is_null = false
    }
    if !is_null { os.exit(15) }
    switch elements[6].value {
    case .Binary as binary:
        if binary.subtype != 128u8 || binary.data.len != 3usize || binary.data[2] != 3u8 { os.exit(16) }
    default:
        os.exit(17)
    }
    switch elements[7].value {
    case .Document as sub:
        if sub.len != 1usize || !str.eq(sub[0].key, "x") { os.exit(18) }
    default:
        os.exit(19)
    }
    switch elements[8].value {
    case .Array as items:
        if items.len != 2usize { os.exit(20) }
        switch items[1] {
        case .String as text:
            if !str.eq(text, "b") { os.exit(21) }
        default:
            os.exit(22)
        }
    default:
        os.exit(23)
    }
    // Size and write back.
    let (total, e2) = bson.size(&root)
    if e2 != ok || total != 131usize { os.exit(24) }
    var out_buffer: [256]u8 = zero
    var out_state = io.SliceWriter { data: out_buffer[..], off: 0usize }
    var out = io.slice_writer(&out_state)
    if bson.write(&out, &root) != ok { os.exit(25) }
    if !same(out_buffer[..out_state.off], doc[0..]) { os.exit(26) }
    // Typed.
    let (rec, e3) = bson.decode[Rec](a, doc[0..], 4u16)
    if e3 != ok { os.exit(27) }
    if !str.eq(rec.name, "neper") || rec.count != -7 || rec.ratio != 1.5 || !rec.flag { os.exit(28) }
    var typed_state = io.SliceWriter { data: out_buffer[..], off: 0usize }
    var typed_out = io.slice_writer(&typed_state)
    if bson.encode[Rec](&typed_out, &rec) != ok { os.exit(29) }
    if !same(out_buffer[..typed_state.off], typed[0..]) { os.exit(30) }
    let (rec2, e4) = bson.decode[Rec](a, typed[0..], 4u16)
    if e4 != ok || rec2.count != -7 || !str.eq(rec2.name, "neper") { os.exit(31) }
    // Refusals.
    let (r5, e5) = bson.parse(a, doc[0..130], 4u16)
    if e5 != bson.Invalid { os.exit(32) }
    var no_end = doc
    no_end[130] = 1u8
    let (r6, e6) = bson.parse(a, no_end[0..], 4u16)
    if e6 != bson.Invalid { os.exit(33) }
    var odd_tag = doc
    odd_tag[4] = 7u8
    let (r7, e7) = bson.parse(a, odd_tag[0..], 4u16)
    if e7 != bson.Invalid { os.exit(34) }
    var odd_bool = doc
    odd_bool[64] = 2u8
    let (r8, e8) = bson.parse(a, odd_bool[0..], 4u16)
    if e8 != bson.Invalid { os.exit(35) }
    let (r9, e9) = bson.parse(a, doc[0..], 1u16)
    if e9 != bson.TooDeep { os.exit(36) }
    ret ok
}
