// `e.fmt.asn1`: a hand-computed DER SEQUENCE walked with the reader and `children`,
// decoded into a struct and encoded back byte for byte, a 200-byte OCTET STRING for
// the long length form, and the refusals: a non-minimal length, a non-minimal
// INTEGER, a BOOLEAN of 0x01, a length past the data, a depth limit of zero, and a
// missing field. Every check has its own exit code.
use e.os
use e.mem
use e.fmt.asn1 as asn1

type Record = struct { count: i32, flag: bool, name: str, delta: i64 }
type Wide = struct { data: []const u8 }

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
    let der: [17]u8 = [17]u8{ 48, 15, 2, 2, 1, 2, 1, 1, 255, 4, 2, 104, 105, 2, 2, 255, 127 }
    // The reader.
    var r = asn1.reader(der[0..], 4u16)
    let (root, present, e1) = asn1.reader_next_err(&r)
    if e1 != ok || !present { os.exit(1) }
    if root.tag.class != .Universal || root.tag.number != 16u32 || !root.tag.constructed { os.exit(2) }
    if root.content.len != 15usize || root.encoded.len != 17usize { os.exit(3) }
    let (none, more, e2) = asn1.reader_next_err(&r)
    if e2 != ok || more { os.exit(4) }
    let (inner0, e3) = asn1.children(root, 4u16)
    if e3 != ok { os.exit(5) }
    var inner = inner0
    let (first, p1, e4) = asn1.reader_next_err(&inner)
    if e4 != ok || !p1 || first.tag.number != 2u32 || first.content.len != 2usize || first.content[1] != 2u8 { os.exit(6) }
    let (second, p2, e5) = asn1.reader_next_err(&inner)
    if e5 != ok || !p2 || second.tag.number != 1u32 { os.exit(7) }
    let (bad_children, e6) = asn1.children(second, 4u16)
    if e6 != asn1.Invalid { os.exit(8) }
    let (no_depth, e7) = asn1.children(root, 0u16)
    if e7 != asn1.TooDeep { os.exit(9) }
    // Typed decode and encode.
    let (record, e8) = asn1.decode[Record](a, der[0..], 4u16)
    if e8 != ok { os.exit(10) }
    if record.count != 258 || !record.flag || record.delta != -129i64 { os.exit(11) }
    if record.name.len != 2usize || record.name[0] != 104u8 { os.exit(12) }
    let (needed, e9) = asn1.encoded_len[Record](&record)
    if e9 != ok || needed != 17usize { os.exit(13) }
    var out: [64]u8 = zero
    let (encoded, e10) = asn1.encode[Record](out[0..], &record)
    if e10 != ok { os.exit(14) }
    if !same(encoded, der[0..]) { os.exit(15) }
    var small: [16]u8 = zero
    let (too_small, e11) = asn1.encode[Record](small[0..], &record)
    if e11 != asn1.TooLarge { os.exit(16) }
    // The long length form: 200 bytes inside a 206-byte sequence.
    var payload: [200]u8 = zero
    var i = 0usize
    while i < 200usize {
        payload[i] = u8(i)
        i += 1usize
    }
    var wide: Wide = zero
    wide.data = payload[0..]
    var wide_out: [256]u8 = zero
    let (wide_encoded, e12) = asn1.encode[Wide](wide_out[0..], &wide)
    if e12 != ok || wide_encoded.len != 206usize { os.exit(17) }
    if wide_encoded[1] != 129u8 || wide_encoded[2] != 203u8 || wide_encoded[4] != 129u8 || wide_encoded[5] != 200u8 { os.exit(18) }
    let (wide_back, e13) = asn1.decode[Wide](a, wide_encoded, 4u16)
    if e13 != ok || wide_back.data.len != 200usize || wide_back.data[199] != 199u8 { os.exit(19) }
    // Refusals.
    let long_zero: [4]u8 = [4]u8{ 4, 129, 2, 104 }
    var r2 = asn1.reader(long_zero[0..], 4u16)
    let (v2, q2, e14) = asn1.reader_next_err(&r2)
    if e14 != asn1.NonCanonical { os.exit(20) }
    let padded_int: [12]u8 = [12]u8{ 48, 10, 2, 2, 0, 1, 1, 1, 255, 4, 0, 2 }
    let (bad_record, e15) = asn1.decode[Record](a, padded_int[0..], 4u16)
    if e15 != asn1.NonCanonical { os.exit(21) }
    let odd_bool: [17]u8 = [17]u8{ 48, 15, 2, 2, 1, 2, 1, 1, 1, 4, 2, 104, 105, 2, 2, 255, 127 }
    let (bad_bool, e16) = asn1.decode[Record](a, odd_bool[0..], 4u16)
    if e16 != asn1.NonCanonical { os.exit(22) }
    let short: [3]u8 = [3]u8{ 4, 5, 1 }
    var r3 = asn1.reader(short[0..], 4u16)
    let (v3, q3, e17) = asn1.reader_next_err(&r3)
    if e17 != asn1.Invalid { os.exit(23) }
    let (deep, e18) = asn1.decode[Record](a, der[0..], 0u16)
    if e18 != asn1.TooDeep { os.exit(24) }
    let missing: [11]u8 = [11]u8{ 48, 9, 2, 2, 1, 2, 1, 1, 255, 4, 0 }
    let (partial, e19) = asn1.decode[Record](a, missing[0..], 4u16)
    if e19 != asn1.Invalid { os.exit(25) }
    ret ok
}
