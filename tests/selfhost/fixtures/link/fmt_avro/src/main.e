// `e.fmt.avro`: zigzag and primitive vectors from fastavro; a writer record
// {id int, name string, score float, tags array<string>, meta map<int>, kind
// enum[A,B,C], extra long} resolved into a reader record with reordered fields,
// id long, score double, extra dropped, level int defaulted to 7 and an enum
// defaulting to B, re-encoded byte for byte as fastavro does; unions reindexed;
// `Mismatch` for int vs string and an undefaulted enum; `Malformed` on truncation.
// Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.avro as avro

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn node(s: *avro.Schema, i: usize, k: avro.Kind, name: str, start: usize, count: usize) {
    s.kind[i] = k
    s.name[i] = name
    s.child_start[i] = start
    s.child_count[i] = count
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: zigzag and primitives.
    let longs: [21]u8 = [21]u8{ 0, 1, 2, 3, 128, 128, 128, 128, 16, 255, 255, 255, 255, 255, 255, 255, 255, 255, 1, 0, 0 }
    var d1 = avro.decoder(longs[..19])
    let (l0, e0) = avro.read_long(&d1)
    let (l1, e1) = avro.read_long(&d1)
    let (l2, e2) = avro.read_long(&d1)
    let (l3, e3) = avro.read_long(&d1)
    let (l4, e4) = avro.read_long(&d1)
    let (l5, e5) = avro.read_long(&d1)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(1i32) }
    if l0 != 0i64 || l1 != -1i64 || l2 != 1i64 || l3 != -2i64 || l4 != 2147483648i64 { os.exit(2i32) }
    if l5 != 0i64 - 9223372036854775807i64 - 1i64 || d1.pos != 19usize { os.exit(3i32) }
    let (l6, e6) = avro.read_long(&d1)
    if e6 != avro.Malformed { os.exit(4i32) }
    if avro.decode_zigzag(4294967295u64) != -2147483648i64 || avro.encode_zigzag(-2147483648i64) != 4294967295u64 { os.exit(5i32) }
    let prims: [18]u8 = [18]u8{ 0, 0, 0, 0, 0, 0, 6, 64, 0, 0, 192, 191, 1, 10, 110, 101, 112, 101 }
    var d2 = avro.decoder(prims[0..])
    let (dbl, e7) = avro.read_double(&d2)
    let (flt, e8) = avro.read_float(&d2)
    let (bl, e9) = avro.read_boolean(&d2)
    if e7 != ok || e8 != ok || e9 != ok || dbl != 2.75f64 || flt != -1.5f32 || !bl { os.exit(6i32) }
    let (s1, e10) = avro.read_string(&d2)
    if e10 != avro.Malformed { os.exit(7i32) }
    var d3 = avro.decoder(prims[13..])
    let (i1, e11) = avro.read_int(&d3)
    if e11 != ok || i1 != 5i32 { os.exit(8i32) }
    // Writer schema: 0 Rec, 1..7 fields, 8 tags item, 9 meta value, 10..12 symbols.
    var wk: [13]avro.Kind = zero
    var wname: [13]str = zero
    var wstart: [13]usize = zero
    var wcount: [13]usize = zero
    var wsize: [13]usize = zero
    var wdef: [13]str = zero
    var wchildren: [12]u32 = [12]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }
    var w = avro.Schema { kind: wk[..], name: wname[..], child_start: wstart[..], child_count: wcount[..], children: wchildren[..], size: wsize[..], fallback: wdef[..] }
    node(&w, 0usize, .Record, "Rec", 0usize, 7usize)
    node(&w, 1usize, .Int, "id", 0usize, 0usize)
    node(&w, 2usize, .String, "name", 0usize, 0usize)
    node(&w, 3usize, .Float, "score", 0usize, 0usize)
    node(&w, 4usize, .Array, "tags", 7usize, 1usize)
    node(&w, 5usize, .Map, "meta", 8usize, 1usize)
    node(&w, 6usize, .Enum, "K", 9usize, 3usize)
    node(&w, 7usize, .Long, "extra", 0usize, 0usize)
    node(&w, 8usize, .String, "", 0usize, 0usize)
    node(&w, 9usize, .Int, "", 0usize, 0usize)
    node(&w, 10usize, .Null, "A", 0usize, 0usize)
    node(&w, 11usize, .Null, "B", 0usize, 0usize)
    node(&w, 12usize, .Null, "C", 0usize, 0usize)
    // Reader schema: 0 Rec, 1..7 fields, 8..9 symbols, 10 meta value, 11 tags item.
    var rk: [12]avro.Kind = zero
    var rname: [12]str = zero
    var rstart: [12]usize = zero
    var rcount: [12]usize = zero
    var rsize: [12]usize = zero
    var rdef: [12]str = zero
    var rchildren: [11]u32 = [11]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
    var r = avro.Schema { kind: rk[..], name: rname[..], child_start: rstart[..], child_count: rcount[..], children: rchildren[..], size: rsize[..], fallback: rdef[..] }
    node(&r, 0usize, .Record, "Rec", 0usize, 7usize)
    node(&r, 1usize, .Int, "level", 0usize, 0usize)
    node(&r, 2usize, .Enum, "K", 7usize, 2usize)
    node(&r, 3usize, .Double, "score", 0usize, 0usize)
    node(&r, 4usize, .String, "name", 0usize, 0usize)
    node(&r, 5usize, .Map, "meta", 9usize, 1usize)
    node(&r, 6usize, .Array, "tags", 10usize, 1usize)
    node(&r, 7usize, .Long, "id", 0usize, 0usize)
    node(&r, 8usize, .Null, "A", 0usize, 0usize)
    node(&r, 9usize, .Null, "B", 0usize, 0usize)
    node(&r, 10usize, .Int, "", 0usize, 0usize)
    node(&r, 11usize, .String, "", 0usize, 0usize)
    rdef[1] = "\x0e"
    rdef[2] = "\x02"
    // 2: the record, resolved and re-encoded.
    let written: [33]u8 = [33]u8{ 9, 10, 110, 101, 112, 101, 114, 0, 0, 48, 64, 4, 2, 120, 4, 121, 121, 0, 4, 2, 97, 2, 2, 98, 3, 0, 4, 168, 232, 200, 233, 151, 7 }
    let expected: [32]u8 = [32]u8{ 14, 2, 0, 0, 0, 0, 0, 0, 6, 64, 10, 110, 101, 112, 101, 114, 4, 2, 97, 2, 2, 98, 3, 0, 4, 2, 120, 4, 121, 121, 0, 9 }
    if avro.resolve(&w, 0u32, &r, 0u32) != ok { os.exit(9i32) }
    var d4 = avro.decoder(written[0..])
    if avro.skip(&w, 0u32, &d4) != ok || d4.pos != 33usize { os.exit(10i32) }
    var buffer: [64]u8 = zero
    var o = avro.sink(buffer[..])
    var d5 = avro.decoder(written[0..])
    if avro.decode_resolved(&w, 0u32, &r, 0u32, &d5, &o) != ok { os.exit(11i32) }
    if d5.pos != 33usize || !same(buffer[..o.used], expected[0..]) { os.exit(12i32) }
    // 3: unions. Writer ["null","string"], reader ["string","null"].
    var uk: [3]avro.Kind = zero
    var uname: [3]str = zero
    var ustart: [3]usize = zero
    var ucount: [3]usize = zero
    var usize_: [3]usize = zero
    var udef: [3]str = zero
    var uchildren: [2]u32 = [2]u32{ 1, 2 }
    var u = avro.Schema { kind: uk[..], name: uname[..], child_start: ustart[..], child_count: ucount[..], children: uchildren[..], size: usize_[..], fallback: udef[..] }
    node(&u, 0usize, .Union, "", 0usize, 2usize)
    node(&u, 1usize, .Null, "", 0usize, 0usize)
    node(&u, 2usize, .String, "", 0usize, 0usize)
    var vk: [3]avro.Kind = zero
    var vname: [3]str = zero
    var vstart: [3]usize = zero
    var vcount: [3]usize = zero
    var vsize: [3]usize = zero
    var vdef: [3]str = zero
    var vchildren: [2]u32 = [2]u32{ 1, 2 }
    var v = avro.Schema { kind: vk[..], name: vname[..], child_start: vstart[..], child_count: vcount[..], children: vchildren[..], size: vsize[..], fallback: vdef[..] }
    node(&v, 0usize, .Union, "", 0usize, 2usize)
    node(&v, 1usize, .String, "", 0usize, 0usize)
    node(&v, 2usize, .Null, "", 0usize, 0usize)
    let union_written: [4]u8 = [4]u8{ 2, 4, 104, 105 }
    let union_expected: [4]u8 = [4]u8{ 0, 4, 104, 105 }
    var o2 = avro.sink(buffer[..])
    var d6 = avro.decoder(union_written[0..])
    if avro.resolve(&u, 0u32, &v, 0u32) != ok { os.exit(13i32) }
    if avro.decode_resolved(&u, 0u32, &v, 0u32, &d6, &o2) != ok || !same(buffer[..o2.used], union_expected[0..]) { os.exit(14i32) }
    var o3 = avro.sink(buffer[..])
    var d7 = avro.decoder(union_written[1..])
    if avro.decode_resolved(&u, 2u32, &v, 0u32, &d7, &o3) != ok || !same(buffer[..o3.used], union_expected[0..]) { os.exit(15i32) }
    // Union writer against a non-union reader: the string branch resolves to string.
    var o4 = avro.sink(buffer[..])
    var d8 = avro.decoder(union_written[0..])
    if avro.decode_resolved(&u, 0u32, &v, 1u32, &d8, &o4) != ok || !same(buffer[..o4.used], union_written[1..]) { os.exit(16i32) }
    // 4: mismatches.
    if avro.resolve(&w, 1u32, &w, 2u32) != avro.Mismatch { os.exit(17i32) }
    rdef[2] = ""
    if avro.resolve(&w, 6u32, &r, 2u32) != avro.Mismatch { os.exit(18i32) }
    let symbol_c: [1]u8 = [1]u8{ 4 }
    var o5 = avro.sink(buffer[..])
    var d9 = avro.decoder(symbol_c[0..])
    if avro.decode_resolved(&w, 6u32, &r, 2u32, &d9, &o5) != avro.Mismatch { os.exit(19i32) }
    rdef[1] = ""
    if avro.resolve(&w, 0u32, &r, 0u32) != avro.Mismatch { os.exit(20i32) }
    rdef[1] = "\x0e"
    rdef[2] = "\x02"
    // 5: truncation and a full sink.
    var o6 = avro.sink(buffer[..])
    var d10 = avro.decoder(written[..30])
    if avro.decode_resolved(&w, 0u32, &r, 0u32, &d10, &o6) != avro.Malformed { os.exit(21i32) }
    var o7 = avro.sink(buffer[..8])
    var d11 = avro.decoder(written[0..])
    if avro.decode_resolved(&w, 0u32, &r, 0u32, &d11, &o7) != avro.TooSmall { os.exit(22i32) }
    try io.print("fmt avro ok\n")
    ret ok
}
