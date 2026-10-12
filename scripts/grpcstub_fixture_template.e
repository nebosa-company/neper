// `e.net.grpcstub` and `e.fmt.protomsg` against Python's protobuf: scripts/grpcstub_vectors.py builds descriptors (proto3
// kitchen-sink messages with every scalar type, packed and unpacked lists, enums, recursive and nested messages, maps,
// oneofs, proto3 optional, a service of every shape; a proto2 file with required, optional and packed fields), has the
// generator write `kitchen.e` (compiled with this fixture), and serialises random instances with Python's own message
// classes. Each is decoded by the generated `*_decode` and re-encoded by `*_encode` to the same bytes; some fixed
// messages are read field by field; unknown fields and fields of another wire type are skipped; a message nested 105
// deep is refused; the generator's output equals the module compiled here; the service paths, the routing function and the enum constants
// are the descriptor's. Generated; do not edit.
use e.fmt.json as json
use e.fmt.protobuf as pb
use e.fmt.protodesc as desc
use e.io
use e.mem
use e.net.grpcstub as stub
use e.os
use e.str
use kitchen

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(a: *mem.Arena, h: str) -> []u8 {
    let (out, e) = mem.alloc[u8](a, h.len / 2usize + 1usize)
    if e != ok { os.exit(80) }
    var i = 0usize
    while i + 1usize < h.len {
        out[i / 2usize] = nibble(h[i]) * 16u8 + nibble(h[i + 1usize])
        i += 2usize
    }
    ret out[0usize..h.len / 2usize]
}

fn hex_of(a: *mem.Arena, b: []const u8) -> str {
    let (out, e) = mem.alloc[u8](a, b.len * 2usize + 1usize)
    if e != ok { os.exit(81) }
    var i = 0usize
    while i < b.len {
        let hi = b[i] / 16u8
        let lo = b[i] % 16u8
        if hi < 10u8 { out[i * 2usize] = 48u8 + hi } else { out[i * 2usize] = 87u8 + hi }
        if lo < 10u8 { out[i * 2usize + 1usize] = 48u8 + lo } else { out[i * 2usize + 1usize] = 87u8 + lo }
        i += 1usize
    }
    ret out[0usize..b.len * 2usize]
}

fn same(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// Decode, re-encode and compare, for the message named `name`; 0 when the bytes come back identical.
fn round_trip(a: *mem.Arena, name: str, raw: []const u8) -> u8 {
@@DISPATCH@@    ret 9u8
}

fn run_line(a: *mem.Arena, line: str) -> u8 {
    var name = ""
    var data = ""
    var tab = 0usize
    while tab < line.len && line[tab] != 9u8 { tab += 1usize }
    if tab >= line.len { ret 90u8 }
    name = line[0usize..tab]
    data = line[tab + 1usize..line.len]
    ret round_trip(a, name, unhex(a, data))
}

fn fixed_checks(a: *mem.Arena) -> i32 {
    // Scalars
    let (sc, sce) = kitchen.ks_v1_scalars_decode(a, unhex(a, "@@FIXED_SCALARS@@"))
    if sce != ok { ret 1i32 }
    if sc.d != 2.5f64 || sc.f != 0.5f32 || sc.i32 != -7i32 || sc.i64 != -9000000000i64 || sc.u32 != 4000000000u32 { ret 2i32 }
    if sc.u64 != 9223372036854775813u64 || sc.s32 != -300i32 || sc.s64 != -1099511627776i64 || sc.x32 != 77u32 { ret 3i32 }
    if sc.x64 != 1125899906842624u64 || sc.sx32 != -1i32 || sc.sx64 != -8589934592i64 || !sc.b { ret 4i32 }
    if !str.eq(sc.s, "hi \xC3\xA9") || sc.by.len != 2usize || sc.by[0] != 1u8 || sc.by[1] != 2u8 || sc.color != -5i32 { ret 5i32 }
    // Repeats
    let (rp, rpe) = kitchen.ks_v1_repeats_decode(a, unhex(a, "@@FIXED_REPEATS@@"))
    if rpe != ok { ret 10i32 }
    if rp.ints.len != 3usize || rp.ints[0] != 1i32 || rp.ints[1] != -1i32 || rp.ints[2] != 300i32 { ret 11i32 }
    if rp.sints.len != 2usize || rp.sints[0] != -3i64 || rp.sints[1] != 4i64 { ret 12i32 }
    if rp.doubles.len != 2usize || rp.doubles[0] != 0.25f64 || rp.doubles[1] != -1.0f64 { ret 13i32 }
    if rp.strs.len != 3usize || !str.eq(rp.strs[0], "a") || rp.strs[1].len != 0usize || !str.eq(rp.strs[2], "ccc") { ret 14i32 }
    if rp.blobs.len != 2usize || rp.blobs[0].len != 1usize || rp.blobs[1].len != 0usize { ret 15i32 }
    if rp.flags.len != 3usize || !rp.flags[0] || rp.flags[1] || !rp.flags[2] { ret 16i32 }
    if rp.colors.len != 3usize || rp.colors[1] != 7i32 || rp.colors[2] != -5i32 { ret 17i32 }
    if rp.fx.len != 2usize || rp.fx[1] != 6u32 || rp.items.len != 1usize || rp.items[0].i32 != 9i32 { ret 18i32 }
    if rp.unpacked.len != 3usize || rp.unpacked[2] != 6i64 || rp.floats.len != 2usize || rp.floats[1] != 2.5f32 { ret 19i32 }
    if rp.sfx.len != 2usize || rp.sfx[0] != -1i64 || rp.sfx[1] != 1i64 { ret 20i32 }
    // Node: recursion, maps as entry lists, oneof members and proto3 optional with presence
    let (nd, nde) = kitchen.ks_v1_node_decode(a, unhex(a, "@@FIXED_NODE@@"))
    if nde != ok { ret 30i32 }
    if !str.eq(nd.name, "root") || nd.child == nil || !str.eq(nd.child.name, "kid") { ret 31i32 }
    if nd.kids.len != 2usize || !str.eq(nd.kids[0].name, "k1") || !str.eq(nd.kids[1].name, "k2") { ret 32i32 }
    if nd.counts.len != 2usize || nd.by_id.len != 1usize || nd.by_id[0].key != 7i32 || nd.by_id[0].value == nil || !str.eq(nd.by_id[0].value.s, "seven") { ret 33i32 }
    if !nd.has_maybe || nd.maybe != 0i32 || !nd.has_number || nd.number != 99i64 || nd.c != 2i32 || nd.has_text || nd.rec != nil { ret 34i32 }
    // proto2: required and optional fields carry presence, an explicitly set default is still written
    let (lg, lge) = kitchen.ks_legacy_legacy_decode(a, unhex(a, "@@FIXED_LEGACY@@"))
    if lge != ok { ret 40i32 }
    if !lg.has_id || lg.id != -1i32 || !lg.has_name || !str.eq(lg.name, "old") || lg.packed_list.len != 3usize || lg.plain.len != 2usize { ret 41i32 }
    if !lg.has_flag || lg.flag || !lg.has_ratio || lg.ratio != 0.0f64 || !lg.has_blob || lg.blob.len != 0usize || !lg.has_who || lg.who != 7u64 { ret 42i32 }
    // keyword field names get a trailing underscore
    let (kw, kwe) = kitchen.ks_v1_keywords_decode(a, unhex(a, "@@FIXED_KEYWORDS@@"))
    if kwe != ok { ret 50i32 }
    if kw.type_ != 5i32 || !str.eq(kw.in_, "inside") || !kw.error_ || kw.zero_ != 1.25f64 { ret 51i32 }
    // unknown fields and a field of another wire type are skipped
    let skipped = unhex(a, "9806050a0107" )
    let (sk, ske) = kitchen.ks_v1_scalars_decode(a, skipped)
    if ske != ok || sk.i32 != 0i32 { ret 60i32 }
    let (sk2, ske2) = kitchen.ks_v1_scalars_decode(a, unhex(a, "1a0107" ))
    if ske2 != ok || sk2.i32 != 0i32 { ret 61i32 }
    // a message nested 105 deep
    let (deep, deepe) = kitchen.ks_v1_node_decode(a, unhex(a, "@@DEEP@@"))
    if deepe == ok { ret 62i32 }
    // paths, routing and enum constants
    if !str.eq(kitchen.ks_v1_kitchen_unary_path(), "/ks.v1.Kitchen/Unary") { ret 70i32 }
    if !str.eq(kitchen.ks_v1_kitchen_server_stream_path(), "/ks.v1.Kitchen/ServerStream") { ret 71i32 }
    if !str.eq(kitchen.ks_v1_kitchen_http_ping_path(), "/ks.v1.Kitchen/HTTPPing") { ret 72i32 }
    if kitchen.ks_v1_kitchen_method_index("/ks.v1.Kitchen/Bidi") != 3i32 { ret 73i32 }
    if kitchen.ks_v1_kitchen_method_index("/ks.v1.Kitchen/HTTPPing") != 4i32 { ret 74i32 }
    if kitchen.ks_v1_kitchen_method_index("/ks.v1.Kitchen/Missing") != -1i32 { ret 75i32 }
    if kitchen.KS_V1_COLOR_DEEP_BLUE != 7i32 || kitchen.KS_V1_COLOR_NEGATIVE != -5i32 || kitchen.KS_V1_COLOR_RED != 1i32 { ret 76i32 }
    ret 0i32
}

fn golden() -> str {
    ret r#"@@GOLDEN@@"#
}

fn main(a: *mem.Arena, args: []str) -> err {
    // the generator reproduces the module compiled here
    let (set, parse_error) = desc.parse_set(a, unhex(a, "@@SET@@"))
    if parse_error != ok { os.exit(1) }
    let (text, generate_error) = stub.generate(a, set)
    if generate_error != ok { os.exit(2) }
    if !str.eq(text, golden()) { os.exit(3) }
    let fixed = fixed_checks(a)
    if fixed != 0i32 { os.exit(100 + fixed) }
    let table = "@@VECTORS@@"
    var start = 0usize
    var at = 0usize
    var count = 0usize
    while at < table.len {
        if table[at] == 10u8 {
            let mark = mem.mark(a)
            let code = run_line(a, table[start..at])
            if code != 0u8 {
                let shown = io.print(table[start..at])
                os.exit(200 + i32(code))
            }
            mem.reset(a, mark)
            count += 1usize
            start = at + 1usize
        }
        at += 1usize
    }
    if count != @@COUNT@@usize { os.exit(4) }
    try io.print("net grpcstub ok")
    ret ok
}
