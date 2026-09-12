// `e.fmt.msgpack`: every value family written in its smallest form and matched byte
// for byte against the specification, read back through the tree reader, the depth
// limit and the reserved byte refused, and a struct through the typed codec both ways.
// Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.msgpack as msgpack

type Record = struct { name: str, count: u32, ratio: f64, enabled: bool, delta: i16 }

fn bytes_equal(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var items: [11]msgpack.Value = zero
    items[0] = .Nil
    items[1] = msgpack.Value{ Bool: true }
    items[2] = msgpack.Value{ I64: -1i64 }
    items[3] = msgpack.Value{ I64: -200i64 }
    items[4] = msgpack.Value{ U64: 300u64 }
    items[5] = msgpack.Value{ U64: 18446744073709551615u64 }
    items[6] = msgpack.Value{ F64: 1.5 }
    items[7] = msgpack.Value{ String: "hello" }
    var blob: [3]u8 = [3]u8{ 1, 2, 3 }
    items[8] = msgpack.Value{ Binary: blob[0..] }
    var pairs: [1]msgpack.Pair = zero
    pairs[0].key = msgpack.Value{ String: "k" }
    pairs[0].value = msgpack.Value{ I64: 7i64 }
    items[9] = msgpack.Value{ Map: pairs[0..] }
    var ext: msgpack.Ext = zero
    ext.kind = -1i8
    var stamp: [4]u8 = [4]u8{ 0, 0, 1, 0 }
    ext.data = stamp[0..]
    items[10] = msgpack.Value{ Ext: ext }
    let root = msgpack.Value{ Array: items[0..] }
    var sink_bytes: [256]u8 = zero
    var sink_state: io.SliceWriter = zero
    sink_state.data = sink_bytes[0..]
    var writer = io.slice_writer(&sink_state)
    if msgpack.write(&writer, &root) != ok { os.exit(1) }
    let encoded = sink_bytes[..sink_state.off]
    let want: [42]u8 = [42]u8{ 155, 192, 195, 255, 209, 255, 56, 205, 1, 44, 207, 255, 255, 255, 255, 255, 255, 255, 255, 203, 63, 248, 0, 0, 0, 0, 0, 0, 165, 104, 101, 108, 108, 111, 196, 3, 1, 2, 3, 129, 161, 107 }
    if encoded.len != 49usize || !bytes_equal(encoded[..42], want[0..]) { os.exit(2) }
    if encoded[42] != 7u8 || encoded[43] != 214u8 || encoded[44] != 255u8 || encoded[47] != 1u8 || encoded[48] != 0u8 { os.exit(3) }
    var source_state: io.SliceReader = zero
    source_state.data = encoded
    let (r0, reader_error) = msgpack.reader(a, io.slice_reader(&source_state), 8u16)
    if reader_error != ok { os.exit(4) }
    var r = r0
    let (back, read_error) = msgpack.read_value(a, &r)
    if read_error != ok { os.exit(5) }
    var read_items: []const msgpack.Value = zero
    switch back {
    case .Array as found:
        read_items = found
    default:
        os.exit(6)
    }
    if read_items.len != 11usize { os.exit(7) }
    switch read_items[3] {
    case .I64 as v:
        if v != -200i64 { os.exit(8) }
    default:
        os.exit(8)
    }
    switch read_items[5] {
    case .U64 as v:
        if v != 18446744073709551615u64 { os.exit(9) }
    default:
        os.exit(9)
    }
    switch read_items[6] {
    case .F64 as v:
        if v != 1.5 { os.exit(10) }
    default:
        os.exit(10)
    }
    switch read_items[7] {
    case .String as v:
        if !str.eq(v, "hello") { os.exit(11) }
    default:
        os.exit(11)
    }
    switch read_items[10] {
    case .Ext as v:
        if v.kind != -1i8 || v.data.len != 4usize || v.data[2] != 1u8 { os.exit(12) }
    default:
        os.exit(12)
    }
    var deep_state: io.SliceReader = zero
    let deep: [4]u8 = [4]u8{ 145, 145, 145, 192 }
    deep_state.data = deep[0..]
    let (d0, _) = msgpack.reader(a, io.slice_reader(&deep_state), 2u16)
    var d = d0
    let (_, deep_error) = msgpack.read_value(a, &d)
    if deep_error != msgpack.TooDeep { os.exit(13) }
    var bad_state: io.SliceReader = zero
    let bad: [1]u8 = [1]u8{ 193 }
    bad_state.data = bad[0..]
    let (b0, _) = msgpack.reader(a, io.slice_reader(&bad_state), 8u16)
    var b = b0
    let (_, bad_error) = msgpack.read_value(a, &b)
    if bad_error != msgpack.Invalid { os.exit(14) }
    var record: Record = zero
    record.name = "widget"
    record.count = 70000u32
    record.ratio = 0.25
    record.enabled = true
    record.delta = -5i16
    var packed_bytes: [256]u8 = zero
    var packed_state: io.SliceWriter = zero
    packed_state.data = packed_bytes[0..]
    var packer = io.slice_writer(&packed_state)
    if msgpack.encode[Record](&packer, &record) != ok { os.exit(15) }
    let packed = packed_bytes[..packed_state.off]
    if packed.len == 0usize || packed[0] != 133u8 { os.exit(16) }
    var unpack_state: io.SliceReader = zero
    unpack_state.data = packed
    let (decoded, decode_error) = msgpack.decode[Record](a, io.slice_reader(&unpack_state), 8u16)
    if decode_error != ok { os.exit(17) }
    if !str.eq(decoded.name, "widget") || decoded.count != 70000u32 || decoded.ratio != 0.25 || !decoded.enabled || decoded.delta != -5i16 { os.exit(18) }
    os.exit(0)
    ret ok
}
