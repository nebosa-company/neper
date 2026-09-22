// `e.net.http3`: the four RFC 9000 A.1 varints both ways and TooSmall; a
// stream of SETTINGS, HEADERS, DATA, a reserved frame and a partial DATA
// frame splits into 4 frames with the replica's consumed count and an
// Incomplete tail that names its full length; frame type 0x06 is Invalid;
// settings round-trip and a duplicate id is refused; six request headers
// encode to the replica's 59 QPACK bytes (indexed, name reference, literal)
// and decode back, a Huffman-flagged literal is Unsupported; GOAWAY and the
// unidirectional stream types. Each check exits with its own code.

use e.io
use e.mem
use e.net.http3 as h3
use e.os

fn fnv(h: u64, v: u64) -> u64 { ret (h ^ v) *% 1099511628211u64 }

fn hash(bytes: []const u8) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    while i < bytes.len {
        h = fnv(h, u64(bytes[i]))
        i += 1usize
    }
    ret h
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var buf: [256]u8 = zero

    // 1: RFC 9000 A.1 varints.
    let v8: [8]u8 = [8]u8{ 0xc2, 0x19, 0x7c, 0x5e, 0xff, 0x14, 0xe8, 0x8c }
    let v4: [4]u8 = [4]u8{ 0x9d, 0x7f, 0x3e, 0x7d }
    let v2: [2]u8 = [2]u8{ 0x7b, 0xbd }
    let v1: [1]u8 = [1]u8{ 0x25 }
    let (d8, n8, e8) = h3.varint_decode(v8[..])
    if e8 != ok || n8 != 8usize || d8 != 151288809941952652u64 { os.exit(1i32) }
    let (d4, n4, e4) = h3.varint_decode(v4[..])
    if e4 != ok || n4 != 4usize || d4 != 494878333u64 { os.exit(1i32) }
    let (d2, n2, e2) = h3.varint_decode(v2[..])
    if e2 != ok || n2 != 2usize || d2 != 15293u64 { os.exit(1i32) }
    let (d1, n1, e1) = h3.varint_decode(v1[..])
    if e1 != ok || n1 != 1usize || d1 != 37u64 { os.exit(1i32) }
    let (w8, we8) = h3.varint_encode(buf[..], 151288809941952652u64)
    if we8 != ok || w8 != 8usize || hash(buf[..8usize]) != hash(v8[..]) { os.exit(1i32) }
    let (w4, we4) = h3.varint_encode(buf[..], 494878333u64)
    if we4 != ok || w4 != 4usize || hash(buf[..4usize]) != hash(v4[..]) { os.exit(1i32) }
    let (w2, we2) = h3.varint_encode(buf[..], 15293u64)
    if we2 != ok || w2 != 2usize || buf[0usize] != 0x7bu8 || buf[1usize] != 0xbdu8 { os.exit(1i32) }
    let (w1, we1) = h3.varint_encode(buf[..], 37u64)
    if we1 != ok || w1 != 1usize || buf[0usize] != 0x25u8 { os.exit(1i32) }
    if h3.varint_len(63u64) != 1usize || h3.varint_len(64u64) != 2usize || h3.varint_len(16383u64) != 2usize || h3.varint_len(16384u64) != 4usize || h3.varint_len(1073741824u64) != 8usize { os.exit(1i32) }
    let (_, ets) = h3.varint_encode(buf[..3usize], 494878333u64)
    if ets != h3.TooSmall { os.exit(1i32) }
    let (_, einv) = h3.varint_encode(buf[..], 1u64 << 62u32)
    if einv != h3.Invalid { os.exit(1i32) }
    let (_, _, einc) = h3.varint_decode(v4[..3usize])
    if einc != h3.Incomplete { os.exit(1i32) }

    // 2: a stream of frames with a partial tail.
    var names: [6]str = zero
    var values: [6]str = zero
    names[0usize] = ":method"
    values[0usize] = "GET"
    names[1usize] = ":scheme"
    values[1usize] = "https"
    names[2usize] = ":path"
    values[2usize] = "/index.html"
    names[3usize] = ":authority"
    values[3usize] = "www.example.com"
    names[4usize] = "user-agent"
    values[4usize] = "curl/8.0"
    names[5usize] = "x-custom"
    values[5usize] = "yes"
    var hb: [128]u8 = zero
    let (hn, he) = h3.headers_encode(hb[..], names[..], values[..])
    if he != ok || hn != 59usize || hash(hb[..hn]) != 300463869378788766u64 { os.exit(2i32) }
    let ids: [2]u64 = [2]u64{ 1, 7 }
    let vals: [2]u64 = [2]u64{ 4096, 100 }
    var sb: [16]u8 = zero
    let (sn, se) = h3.settings_encode(sb[..], ids[..], vals[..])
    if se != ok || sn != 6usize || hash(sb[..sn]) != 16872031278735394293u64 { os.exit(2i32) }
    var stream: [128]u8 = zero
    var p = 0usize
    let (f1, fe1) = h3.frame_encode(stream[p..], h3.frame_settings(), sb[..sn])
    if fe1 != ok { os.exit(2i32) }
    p += f1
    let (f2, fe2) = h3.frame_encode(stream[p..], h3.frame_headers(), hb[..hn])
    if fe2 != ok { os.exit(2i32) }
    p += f2
    let (f3, fe3) = h3.frame_encode(stream[p..], h3.frame_data(), "hello http3")
    if fe3 != ok { os.exit(2i32) }
    p += f3
    let rbytes: [2]u8 = [2]u8{ 0xaa, 0xbb }
    let (f4, fe4) = h3.frame_encode(stream[p..], 126u64, rbytes[..])
    if fe4 != ok || !h3.frame_reserved(126u64) || h3.frame_reserved(125u64) { os.exit(2i32) }
    p += f4
    let (f5, fe5) = h3.frame_encode(stream[p..], h3.frame_data(), "0123456789")
    if fe5 != ok || f5 != 12usize { os.exit(2i32) }
    p += f5 - 4usize
    if p != 95usize || hash(stream[..p]) != 8841706955222782476u64 { os.exit(2i32) }
    var out: [8]h3.Frame = zero
    let (count, consumed, ce) = h3.frames(stream[..p], out[..])
    if ce != h3.Incomplete || count != 4usize || consumed != 87usize { os.exit(2i32) }
    if out[0usize].kind != h3.frame_settings() || out[0usize].payload.len != 6usize { os.exit(2i32) }
    if out[1usize].kind != h3.frame_headers() || out[1usize].payload.len != 59usize || hash(out[1usize].payload) != 300463869378788766u64 { os.exit(2i32) }
    if out[2usize].kind != h3.frame_data() || out[2usize].payload.len != 11usize || out[2usize].payload[0usize] != 104u8 { os.exit(2i32) }
    if out[3usize].kind != 126u64 || out[3usize].payload.len != 2usize || out[3usize].payload[1usize] != 0xbbu8 { os.exit(2i32) }
    let (_, need, te) = h3.frame_decode(stream[consumed..p])
    if te != h3.Incomplete || need != 12usize { os.exit(2i32) }
    let (_, need0, te0) = h3.frame_decode(stream[consumed..consumed + 1usize])
    if te0 != h3.Incomplete || need0 != 0usize { os.exit(2i32) }
    let (count2, consumed2, ce2) = h3.frames(stream[..consumed], out[..])
    if ce2 != ok || count2 != 4usize || consumed2 != 87usize { os.exit(2i32) }
    let (count3, _, ce3) = h3.frames(stream[..consumed], out[..2usize])
    if ce3 != h3.TooSmall || count3 != 2usize { os.exit(2i32) }
    let forbidden: [2]u8 = [2]u8{ 0x06, 0x00 }
    let (_, _, fe) = h3.frame_decode(forbidden[..])
    if fe != h3.Invalid { os.exit(2i32) }
    let (_, fee) = h3.frame_encode(buf[..], 0x06u64, "x")
    if fee != h3.Invalid { os.exit(2i32) }
    let (_, small) = h3.frame_encode(buf[..12usize], h3.frame_data(), "hello http3")
    if small != h3.TooSmall { os.exit(2i32) }

    // 3: settings round trip, duplicate and HTTP/2 ids refused.
    var ids_out: [4]u64 = zero
    var vals_out: [4]u64 = zero
    let (sc, sde) = h3.settings_decode(sb[..sn], ids_out[..], vals_out[..])
    if sde != ok || sc != 2usize || ids_out[0usize] != 1u64 || vals_out[0usize] != 4096u64 || ids_out[1usize] != 7u64 || vals_out[1usize] != 100u64 { os.exit(3i32) }
    let dup_ids: [2]u64 = [2]u64{ 7, 7 }
    let (_, dupe) = h3.settings_encode(buf[..], dup_ids[..], vals[..])
    if dupe != h3.Invalid { os.exit(3i32) }
    let dup_bytes: [4]u8 = [4]u8{ 0x07, 0x01, 0x07, 0x02 }
    let (_, dupd) = h3.settings_decode(dup_bytes[..], ids_out[..], vals_out[..])
    if dupd != h3.Invalid { os.exit(3i32) }
    let h2_bytes: [2]u8 = [2]u8{ 0x03, 0x01 }
    let (_, h2e) = h3.settings_decode(h2_bytes[..], ids_out[..], vals_out[..])
    if h2e != h3.Invalid { os.exit(3i32) }
    let (_, trunc) = h3.settings_decode(sb[..sn - 1usize], ids_out[..], vals_out[..])
    if trunc != h3.Malformed { os.exit(3i32) }

    // 4: QPACK static-only header block, both ways.
    if hb[0usize] != 0u8 || hb[1usize] != 0u8 || hb[2usize] != 0xd1u8 || hb[3usize] != 0xd7u8 || hb[4usize] != 0x51u8 || hb[5usize] != 0x0bu8 { os.exit(4i32) }
    var names_out: [8]str = zero
    var values_out: [8]str = zero
    var scratch: [128]u8 = zero
    let (hc, hde) = h3.headers_decode(hb[..hn], names_out[..], values_out[..], scratch[..])
    if hde != ok || hc != 6usize { os.exit(4i32) }
    var i = 0usize
    while i < 6usize {
        if !same(names_out[i], names[i]) || !same(values_out[i], values[i]) { os.exit(4i32) }
        i += 1usize
    }
    let huff: [6]u8 = [6]u8{ 0x00, 0x00, 0x51, 0x82, 0xaa, 0xbb }
    let (_, huffe) = h3.headers_decode(huff[..], names_out[..], values_out[..], scratch[..])
    if huffe != h3.Unsupported { os.exit(4i32) }
    let dyn: [3]u8 = [3]u8{ 0x00, 0x00, 0x80 }
    let (_, dyne) = h3.headers_decode(dyn[..], names_out[..], values_out[..], scratch[..])
    if dyne != h3.Unsupported { os.exit(4i32) }
    let ric: [3]u8 = [3]u8{ 0x05, 0x00, 0xd1 }
    let (_, rice) = h3.headers_decode(ric[..], names_out[..], values_out[..], scratch[..])
    if rice != h3.Unsupported { os.exit(4i32) }
    let (_, cut) = h3.headers_decode(hb[..10usize], names_out[..], values_out[..], scratch[..])
    if cut != h3.Malformed { os.exit(4i32) }
    let (_, hsmall) = h3.headers_encode(buf[..20usize], names[..], values[..])
    if hsmall != h3.TooSmall { os.exit(4i32) }
    if h3.static_count() != 99usize || !same(h3.static_name(98usize), "x-frame-options") || !same(h3.static_value(58usize), "max-age=31536000; includesubdomains; preload") { os.exit(4i32) }
    // RFC 7541 C.1 prefix integers.
    let (pn, pe) = h3.prefix_int_encode(buf[..], 0u8, 5u32, 1337u64)
    if pe != ok || pn != 3usize || buf[0usize] != 31u8 || buf[1usize] != 154u8 || buf[2usize] != 10u8 { os.exit(4i32) }
    let (pv, pc, pde) = h3.prefix_int_decode(buf[..3usize], 5u32)
    if pde != ok || pv != 1337u64 || pc != 3usize { os.exit(4i32) }

    // 5: GOAWAY and stream types.
    let (gn, ge) = h3.goaway_encode(buf[..], 0x1234u64)
    if ge != ok || gn != 2usize || buf[0usize] != 0x52u8 || buf[1usize] != 0x34u8 { os.exit(5i32) }
    let (gid, gde) = h3.goaway_decode(buf[..2usize])
    if gde != ok || gid != 0x1234u64 { os.exit(5i32) }
    let (_, gbad) = h3.goaway_decode(buf[..3usize])
    if gbad != h3.Malformed { os.exit(5i32) }
    let (gf, gfe) = h3.frame_encode(buf[..], h3.frame_goaway(), buf[..0usize])
    if gfe != ok || gf != 2usize || buf[0usize] != 0x07u8 || buf[1usize] != 0x00u8 { os.exit(5i32) }
    let (tn, tee) = h3.stream_type_encode(buf[..], h3.stream_qpack_decoder())
    if tee != ok || tn != 1usize || buf[0usize] != 0x03u8 { os.exit(5i32) }
    let (tk, tc, tde) = h3.stream_type_decode(buf[..1usize])
    if tde != ok || tk != 3u64 || tc != 1usize { os.exit(5i32) }
    if h3.stream_control() != 0u64 || h3.stream_push() != 1u64 || h3.stream_qpack_encoder() != 2u64 { os.exit(5i32) }

    try io.print("net http3 ok\n")
    ret ok
}
