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
type NarrowSigned = struct { value: i8 }
type NarrowUnsigned = struct { value: u8 }

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
    // A child reader carries the nesting depth forward instead of resetting it at every descent.
    let nested_der: [6]u8 = [6]u8{ 48u8, 4u8, 48u8, 2u8, 48u8, 0u8 }
    var nested_reader = asn1.reader(nested_der[..], 1u16)
    let (nested_root, nested_root_present, nested_root_error) = asn1.reader_next_err(&nested_reader)
    if nested_root_error != ok || !nested_root_present { os.exit(40) }
    let (nested_children0, nested_children_error) = asn1.children(nested_root, 1u16)
    if nested_children_error != ok { os.exit(41) }
    var nested_children = nested_children0
    let (nested_value, nested_value_present, nested_value_error) = asn1.reader_next_err(&nested_children)
    if nested_value_error != ok || !nested_value_present { os.exit(42) }
    let (too_deep_reader, too_deep_error) = asn1.children(nested_value, 1u16)
    if too_deep_error != asn1.TooDeep { os.exit(43) }
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
    // The first OBJECT IDENTIFIER subidentifier can exceed u32 even though every exposed arc
    // fits in u32. It must round-trip rather than wrapping to a different OID.
    let huge_arcs: [2]u32 = [2]u32{ 2u32, 4294967295u32 }
    let huge_oid = asn1.Item{ Oid: huge_arcs[0..] }
    let huge_oid_want: [7]u8 = [7]u8{ 6u8, 5u8, 144u8, 128u8, 128u8, 128u8, 79u8 }
    var huge_oid_out: [16]u8 = zero
    let (huge_oid_der, huge_oid_error) = asn1.der_encode(huge_oid_out[..], &huge_oid)
    if huge_oid_error != ok || !same(huge_oid_der, huge_oid_want[..]) { os.exit(26) }
    let (huge_oid_back, huge_oid_back_error) = asn1.ber_decode(a, huge_oid_der, 4u16)
    if huge_oid_back_error != ok { os.exit(27) }
    switch huge_oid_back {
    case .Oid as arcs:
        if arcs.len != 2usize || arcs[0] != 2u32 || arcs[1] != 4294967295u32 { os.exit(28) }
    default:
        os.exit(29)
    }
    // Five base-128 tag octets may represent a number beyond Tag's u32 range.
    let high_tag: [7]u8 = [7]u8{ 31u8, 144u8, 128u8, 128u8, 128u8, 31u8, 0u8 }
    var high_reader = asn1.reader(high_tag[..], 4u16)
    let (high_value, high_present, high_error) = asn1.reader_next_err(&high_reader)
    if high_error != asn1.TooLarge { os.exit(30) }
    let high_context: [7]u8 = [7]u8{ 191u8, 144u8, 128u8, 128u8, 128u8, 31u8, 0u8 }
    let (high_context_value, high_context_error) = asn1.ber_decode(a, high_context[..], 4u16)
    if high_context_error != asn1.TooLarge { os.exit(31) }
    // BIT STRING padding and constructed segments must preserve the ASN.1 bit value.
    let dirty_bits: [1]u8 = [1]u8{ 255u8 }
    let dirty_bit_string = asn1.Item{ BitString: asn1.BitString { unused: 1u8, data: dirty_bits[..] } }
    var dirty_out: [8]u8 = zero
    let (dirty_der, dirty_error) = asn1.der_encode(dirty_out[..], &dirty_bit_string)
    if dirty_error != asn1.Invalid { os.exit(32) }
    let empty_unused: [3]u8 = [3]u8{ 3u8, 1u8, 1u8 }
    let (empty_unused_value, empty_unused_error) = asn1.ber_decode(a, empty_unused[..], 4u16)
    if empty_unused_error != asn1.Invalid { os.exit(33) }
    let dirty_unused: [4]u8 = [4]u8{ 3u8, 2u8, 1u8, 255u8 }
    let (dirty_unused_value, dirty_unused_error) = asn1.ber_decode(a, dirty_unused[..], 4u16)
    if dirty_unused_error != asn1.Invalid { os.exit(34) }
    let broken_segments: [12]u8 = [12]u8{ 35u8, 128u8, 3u8, 2u8, 1u8, 128u8, 3u8, 2u8, 0u8, 170u8, 0u8, 0u8 }
    let (broken_segments_value, broken_segments_error) = asn1.ber_decode(a, broken_segments[..], 4u16)
    if broken_segments_error != asn1.Invalid { os.exit(35) }
    let mixed_segments: [7]u8 = [7]u8{ 35u8, 128u8, 4u8, 1u8, 170u8, 0u8, 0u8 }
    let (mixed_segments_value, mixed_segments_error) = asn1.ber_decode(a, mixed_segments[..], 4u16)
    if mixed_segments_error != asn1.Invalid { os.exit(36) }
    let valid_segments: [12]u8 = [12]u8{ 35u8, 128u8, 3u8, 2u8, 0u8, 170u8, 3u8, 2u8, 1u8, 128u8, 0u8, 0u8 }
    let (valid_segments_value, valid_segments_error) = asn1.ber_decode(a, valid_segments[..], 4u16)
    if valid_segments_error != ok { os.exit(37) }
    switch valid_segments_value {
    case .BitString as bits:
        if bits.unused != 1u8 || bits.data.len != 2usize || bits.data[0] != 170u8 || bits.data[1] != 128u8 { os.exit(38) }
    default:
        os.exit(39)
    }
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
    // A huge eight-octet DER length must not wrap through wasm32's `usize` and
    // appear to be the one byte that follows it.
    let wrapping_length: [11]u8 = [11]u8{ 4u8, 136u8, 1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8, 0u8 }
    var wrapping_reader = asn1.reader(wrapping_length[..], 4u16)
    let (wrapping_value, wrapping_present, wrapping_error) = asn1.reader_next_err(&wrapping_reader)
    if wrapping_error != asn1.Invalid { os.exit(44) }
    let (deep, e18) = asn1.decode[Record](a, der[0..], 0u16)
    if e18 != asn1.TooDeep { os.exit(24) }
    let missing: [11]u8 = [11]u8{ 48, 9, 2, 2, 1, 2, 1, 1, 255, 4, 0 }
    let (partial, e19) = asn1.decode[Record](a, missing[0..], 4u16)
    if e19 != asn1.Invalid { os.exit(25) }
    let too_wide_signed: [6]u8 = [6]u8{ 48u8, 4u8, 2u8, 2u8, 0u8, 128u8 }
    let (_, too_wide_signed_error) = asn1.decode[NarrowSigned](a, too_wide_signed[..], 4u16)
    if too_wide_signed_error != asn1.Invalid { os.exit(45) }
    let negative_unsigned: [5]u8 = [5]u8{ 48u8, 3u8, 2u8, 1u8, 255u8 }
    let (_, negative_unsigned_error) = asn1.decode[NarrowUnsigned](a, negative_unsigned[..], 4u16)
    if negative_unsigned_error != asn1.Invalid { os.exit(46) }
    ret ok
}
