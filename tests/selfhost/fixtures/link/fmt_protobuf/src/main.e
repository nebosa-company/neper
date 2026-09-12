// `e.fmt.protobuf`: a Python-built message with a varint, a length-delimited field,
// a zigzag sint64, both fixed widths, a negative int64 in its ten-byte form and the
// highest field number, read field by field with one skipped, then written back byte
// for byte with the sizes agreeing; refusals for an eleven-byte varint, wire type 3,
// field number 0 and a truncated length-delimited field. Every check has its own
// exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.protobuf as pb

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
    let msg: [45]u8 = [45]u8{ 8, 150, 1, 18, 7, 116, 101, 115, 116, 105, 110, 103, 24, 3, 37, 239, 190, 173, 222, 41, 0, 0, 0, 0, 0, 1, 0, 0, 48, 255, 255, 255, 255, 255, 255, 255, 255, 255, 1, 248, 255, 255, 255, 15, 0 }
    var r = pb.reader(msg[0..])
    let (k1, p1, e1) = pb.reader_next_err(&r)
    if e1 != ok || !p1 || k1.number != 1u32 || k1.wire != .Varint { os.exit(1) }
    let (v1, e2) = pb.read_u64(&r)
    if e2 != ok || v1 != 150u64 { os.exit(2) }
    let (k2, p2, e3) = pb.reader_next_err(&r)
    if e3 != ok || k2.number != 2u32 || k2.wire != .Bytes { os.exit(3) }
    let (v2, e4) = pb.read_bytes(&r)
    if e4 != ok || !str.eq(v2, "testing") { os.exit(4) }
    let (k3, p3, e5) = pb.reader_next_err(&r)
    if e5 != ok || k3.number != 3u32 { os.exit(5) }
    let (v3, e6) = pb.read_sint64(&r)
    if e6 != ok || v3 != -2i64 { os.exit(6) }
    let (k4, p4, e7) = pb.reader_next_err(&r)
    if e7 != ok || k4.wire != .Fixed32 { os.exit(7) }
    let (v4, e8) = pb.read_fixed32(&r)
    if e8 != ok || v4 != 3735928559u32 { os.exit(8) }
    let (k5, p5, e9) = pb.reader_next_err(&r)
    if e9 != ok || k5.wire != .Fixed64 { os.exit(9) }
    if pb.skip(&r, k5.wire) != ok { os.exit(10) }
    let (k6, p6, e10) = pb.reader_next_err(&r)
    if e10 != ok || k6.number != 6u32 { os.exit(11) }
    let (v6, e11) = pb.read_i64(&r)
    if e11 != ok || v6 != -1i64 { os.exit(12) }
    let (k7, p7, e12) = pb.reader_next_err(&r)
    if e12 != ok || k7.number != 536870911u32 { os.exit(13) }
    let (v7, e13) = pb.read_u64(&r)
    if e13 != ok || v7 != 0u64 { os.exit(14) }
    let (k8, p8, e14) = pb.reader_next_err(&r)
    if e14 != ok || p8 { os.exit(15) }
    // Write it back.
    var out_buffer: [64]u8 = zero
    var out_state = io.SliceWriter { data: out_buffer[..], off: 0usize }
    var w = io.slice_writer(&out_state)
    if pb.write_key(&w, 1u32, .Varint) != ok || pb.write_u64(&w, 150u64) != ok { os.exit(16) }
    if pb.write_key(&w, 2u32, .Bytes) != ok || pb.write_bytes(&w, "testing") != ok { os.exit(17) }
    if pb.write_key(&w, 3u32, .Varint) != ok || pb.write_sint64(&w, -2i64) != ok { os.exit(18) }
    if pb.write_key(&w, 4u32, .Fixed32) != ok || pb.write_fixed32(&w, 3735928559u32) != ok { os.exit(19) }
    if pb.write_key(&w, 5u32, .Fixed64) != ok || pb.write_fixed64(&w, 1099511627776u64) != ok { os.exit(20) }
    if pb.write_key(&w, 6u32, .Varint) != ok || pb.write_i64(&w, -1i64) != ok { os.exit(21) }
    if pb.write_key(&w, 536870911u32, .Varint) != ok || pb.write_u64(&w, 0u64) != ok { os.exit(22) }
    if !same(out_buffer[..out_state.off], msg[0..]) { os.exit(23) }
    // Sizes.
    if pb.size_varint(150u64) != 2usize || pb.size_varint(0u64) != 1usize || pb.size_varint(18446744073709551615u64) != 10usize { os.exit(24) }
    let (ks, e15) = pb.size_key(536870911u32, .Varint)
    if e15 != ok || ks != 5usize { os.exit(25) }
    let (ks0, e16) = pb.size_key(19500u32, .Varint)
    if e16 != pb.Invalid { os.exit(26) }
    let (bs, e17) = pb.size_bytes(7usize)
    if e17 != ok || bs != 8usize { os.exit(27) }
    if pb.write_key(&w, 0u32, .Varint) != pb.Invalid { os.exit(28) }
    // Refusals.
    let long_varint: [11]u8 = [11]u8{ 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 1 }
    var r2 = pb.reader(long_varint[0..])
    let (v9, e18) = pb.read_u64(&r2)
    if e18 != pb.Invalid { os.exit(29) }
    let wire3: [2]u8 = [2]u8{ 11, 0 }
    var r3 = pb.reader(wire3[0..])
    let (k9, p9, e19) = pb.reader_next_err(&r3)
    if e19 != pb.Invalid { os.exit(30) }
    let number0: [2]u8 = [2]u8{ 0, 0 }
    var r4 = pb.reader(number0[0..])
    let (k10, p10, e20) = pb.reader_next_err(&r4)
    if e20 != pb.Invalid { os.exit(31) }
    let short: [4]u8 = [4]u8{ 18, 7, 116, 101 }
    var r5 = pb.reader(short[0..])
    let (k11, p11, e21) = pb.reader_next_err(&r5)
    if e21 != ok { os.exit(32) }
    let (v11, e22) = pb.read_bytes(&r5)
    if e22 != pb.Invalid { os.exit(33) }
    ret ok
}
