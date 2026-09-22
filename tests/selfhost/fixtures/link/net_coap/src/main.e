// `e.net.coap`: a GET /temperature request is the RFC 7252 worked example
// byte for byte and a two-segment POST hashes like the Python replica; a
// message with a token, four options (a delta of 48 and a 300-byte value,
// both extension forms) and a payload round-trips through encode/decode
// and re-iterates the same options; Malformed on nibble 15, truncation,
// version 0, a 9-byte token and a bare payload marker; Invalid on options
// out of order; the exchange retransmits on the 3 s, 9 s, 21 s, 45 s
// schedule and times out at 93 s, an ack by id stops it and a separate
// response by token completes it; RFC 7959 block values. Each check exits
// with its own code.

use e.io
use e.mem
use e.net.coap
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

fn main(a: *mem.Arena, args: []str) -> err {
    var dst: [512]u8 = zero
    var none: []const u8 = zero

    // 1: the worked example and the replica's POST.
    var segs: [2]str = zero
    segs[0usize] = "temperature"
    var queries: [1]str = zero
    let (n1, e1) = coap.request(dst[..], coap.code_get(), segs[..1usize], queries[..0usize], none, 0x7d34u16, true, none, -1i32)
    if e1 != ok || n1 != 16usize { os.exit(1i32) }
    let want: [16]u8 = [16]u8{ 0x40, 0x01, 0x7d, 0x34, 0xbb, 0x74, 0x65, 0x6d, 0x70, 0x65, 0x72, 0x61, 0x74, 0x75, 0x72, 0x65 }
    var i = 0usize
    while i < 16usize {
        if dst[i] != want[i] { os.exit(1i32) }
        i += 1usize
    }
    segs[0usize] = "a"
    segs[1usize] = "bc"
    queries[0usize] = "q=1"
    let tok: [2]u8 = [2]u8{ 0xab, 0xcd }
    let (n1b, e1b) = coap.request(dst[..], coap.code_post(), segs[..], queries[..], tok[..], 0x1234u16, false, "{}", 50i32)
    if e1b != ok || hash(dst[..n1b]) != 6231451826367481260u64 { os.exit(1i32) }
    let (_, e1c) = coap.request(dst[..10usize], coap.code_post(), segs[..], queries[..], tok[..], 0x1234u16, false, "{}", 50i32)
    if e1c != coap.TooSmall { os.exit(1i32) }

    // 2: token, four options with both extension forms, payload; round-trip.
    var big: [300]u8 = zero
    i = 0usize
    while i < 300usize {
        big[i] = u8((i * 7usize + 3usize) & 255usize)
        i += 1usize
    }
    var opts: [320]u8 = zero
    var used = 0usize
    var last = 0u16
    if coap.options_add(opts[..], &used, &last, coap.opt_uri_host(), "h") != ok { os.exit(2i32) }
    if coap.options_add(opts[..], &used, &last, coap.opt_uri_path(), "p") != ok { os.exit(2i32) }
    if coap.options_add_uint(opts[..], &used, &last, coap.opt_content_format(), 0u32) != ok { os.exit(2i32) }
    if coap.options_add(opts[..], &used, &last, coap.opt_size1(), big[..]) != ok { os.exit(2i32) }
    if used != 309usize { os.exit(2i32) }
    let tok3: [3]u8 = [3]u8{ 1, 2, 3 }
    let m2 = coap.Message { kind: coap.kind_con(), code: coap.code_content(), id: 0xbeefu16, token: tok3[..], options: opts[..used], payload: "payload!" }
    let (n2, e2) = coap.encode(dst[..], &m2)
    if e2 != ok || n2 != 325usize || hash(dst[..n2]) != 18340860045456773628u64 { os.exit(2i32) }
    let (d2, e2d) = coap.decode(dst[..n2])
    if e2d != ok || d2.kind != coap.kind_con() || d2.code != coap.code_content() || d2.id != 0xbeefu16 { os.exit(2i32) }
    if coap.code_class(d2.code) != 2u8 || coap.code_detail(d2.code) != 5u8 { os.exit(2i32) }
    if d2.token.len != 3usize || d2.token[2usize] != 3u8 || d2.payload.len != 8usize || d2.payload[7usize] != 33u8 { os.exit(2i32) }
    if d2.options.len != used { os.exit(2i32) }
    var pos = 0usize
    last = 0u16
    let (o1, v1, more1, oe1) = coap.option_next(d2.options, &pos, &last)
    if oe1 != ok || o1 != 3u16 || v1.len != 1usize || v1[0usize] != 104u8 || !more1 { os.exit(2i32) }
    let (o2, v2, more2, oe2) = coap.option_next(d2.options, &pos, &last)
    if oe2 != ok || o2 != 11u16 || v2.len != 1usize || v2[0usize] != 112u8 || !more2 { os.exit(2i32) }
    let (o3, v3, more3, oe3) = coap.option_next(d2.options, &pos, &last)
    if oe3 != ok || o3 != 12u16 || v3.len != 0usize || !more3 { os.exit(2i32) }
    let (cf, cfe) = coap.option_uint(v3)
    if cfe != ok || cf != 0u32 { os.exit(2i32) }
    let (o4, v4, more4, oe4) = coap.option_next(d2.options, &pos, &last)
    if oe4 != ok || o4 != 60u16 || v4.len != 300usize || more4 { os.exit(2i32) }
    i = 0usize
    while i < 300usize {
        if v4[i] != big[i] { os.exit(2i32) }
        i += 1usize
    }
    let (o5, _, more5, oe5) = coap.option_next(d2.options, &pos, &last)
    if oe5 != ok || o5 != 0u16 || more5 { os.exit(2i32) }
    let (_, e2s) = coap.encode(dst[..324usize], &m2)
    if e2s != coap.TooSmall { os.exit(2i32) }

    // 3: Malformed inputs.
    let bad_delta: [5]u8 = [5]u8{ 0x40, 0x01, 0x00, 0x01, 0xf0 }
    let (_, e3a) = coap.decode(bad_delta[..])
    if e3a != coap.Malformed { os.exit(3i32) }
    let bad_len: [5]u8 = [5]u8{ 0x40, 0x01, 0x00, 0x01, 0x0f }
    let (_, e3b) = coap.decode(bad_len[..])
    if e3b != coap.Malformed { os.exit(3i32) }
    let truncated: [5]u8 = [5]u8{ 0x40, 0x01, 0x00, 0x01, 0xd1 }
    let (_, e3c) = coap.decode(truncated[..])
    if e3c != coap.Malformed { os.exit(3i32) }
    let short_value: [6]u8 = [6]u8{ 0x40, 0x01, 0x00, 0x01, 0x12, 0x61 }
    let (_, e3d) = coap.decode(short_value[..])
    if e3d != coap.Malformed { os.exit(3i32) }
    let version0: [4]u8 = [4]u8{ 0x00, 0x01, 0x00, 0x01 }
    let (_, e3e) = coap.decode(version0[..])
    if e3e != coap.Malformed { os.exit(3i32) }
    let long_token: [5]u8 = [5]u8{ 0x49, 0x01, 0x00, 0x01, 0x00 }
    let (_, e3f) = coap.decode(long_token[..])
    if e3f != coap.Malformed { os.exit(3i32) }
    let bare_marker: [5]u8 = [5]u8{ 0x40, 0x01, 0x00, 0x01, 0xff }
    let (_, e3g) = coap.decode(bare_marker[..])
    if e3g != coap.Malformed { os.exit(3i32) }
    let (_, e3h) = coap.decode(bad_delta[..3usize])
    if e3h != coap.Malformed { os.exit(3i32) }
    let (empty, e3i) = coap.decode(version0[..0usize])
    if e3i != coap.Malformed || empty.token.len != 0usize { os.exit(3i32) }
    let ack_only: [4]u8 = [4]u8{ 0x60, 0x00, 0x7d, 0x34 }
    let (a4, e3j) = coap.decode(ack_only[..])
    if e3j != ok || a4.kind != coap.kind_ack() || a4.code != 0u8 || a4.id != 0x7d34u16 || a4.options.len != 0usize || a4.payload.len != 0usize { os.exit(3i32) }

    // 4: options out of order.
    used = 0usize
    last = 0u16
    if coap.options_add_uint(opts[..], &used, &last, coap.opt_content_format(), 50u32) != ok { os.exit(4i32) }
    if coap.options_add(opts[..], &used, &last, coap.opt_uri_path(), "x") != coap.Invalid { os.exit(4i32) }
    if coap.options_add(opts[..], &used, &last, coap.opt_content_format(), "x") != ok { os.exit(4i32) }
    if coap.options_add(opts[..4usize], &used, &last, coap.opt_accept(), "yy") != coap.TooSmall { os.exit(4i32) }
    if used != 4usize || opts[0usize] != 0xc1u8 || opts[1usize] != 50u8 || opts[2usize] != 0x01u8 { os.exit(4i32) }

    // 5: the exchange table.
    var xs: [2]coap.Exchange = zero
    xs[0usize] = coap.exchange()
    xs[1usize] = coap.exchange()
    let tok_a: [1]u8 = [1]u8{ 0xaa }
    let tok_b: [1]u8 = [1]u8{ 0xbb }
    coap.exchange_send(&xs[0usize], 0u64, 0x1111u16, tok_a[..], true, 1.0f64)
    coap.exchange_send(&xs[1usize], 0u64, 0x2222u16, tok_b[..], true, 1.0f64)
    var ids: [4]u16 = zero
    let (t0, te0) = coap.exchange_timeouts(xs[..], 2999u64, ids[..])
    if te0 != ok || t0 != 0usize { os.exit(5i32) }
    let (t1, te1) = coap.exchange_timeouts(xs[..], 3000u64, ids[..])
    if te1 != ok || t1 != 2usize || ids[0usize] != 0x1111u16 || ids[1usize] != 0x2222u16 { os.exit(5i32) }
    // an ack with the wrong id does not match; the right one stops retransmission
    let wrong_ack = coap.Message { kind: coap.kind_ack(), code: 0u8, id: 0x2223u16, token: none, options: none, payload: none }
    let (matched_w, reply_w, re_w) = coap.exchange_receive(&xs[1usize], &wrong_ack)
    if re_w != ok || matched_w || reply_w != .None { os.exit(5i32) }
    let right_ack = coap.Message { kind: coap.kind_ack(), code: 0u8, id: 0x2222u16, token: none, options: none, payload: none }
    let (matched_r, reply_r, re_r) = coap.exchange_receive(&xs[1usize], &right_ack)
    if re_r != ok || !matched_r || reply_r != .EmptyAck || xs[1usize].state != .Acked { os.exit(5i32) }
    let (t2, te2) = coap.exchange_timeouts(xs[..], 9000u64, ids[..])
    if te2 != ok || t2 != 1usize || ids[0usize] != 0x1111u16 { os.exit(5i32) }
    let (t3, te3) = coap.exchange_timeouts(xs[..], 20999u64, ids[..])
    if te3 != ok || t3 != 0usize { os.exit(5i32) }
    let (t4, te4) = coap.exchange_timeouts(xs[..], 21000u64, ids[..])
    if te4 != ok || t4 != 1usize { os.exit(5i32) }
    let (t5, te5) = coap.exchange_timeouts(xs[..], 45000u64, ids[..])
    if te5 != ok || t5 != 1usize || xs[0usize].retries != 4u32 { os.exit(5i32) }
    let (t6, te6) = coap.exchange_timeouts(xs[..], 92999u64, ids[..])
    if te6 != ok || t6 != 0usize { os.exit(5i32) }
    let (t7, te7) = coap.exchange_timeouts(xs[..], 93000u64, ids[..])
    if te7 != coap.Timeout || t7 != 0usize || xs[0usize].state != .Failed { os.exit(5i32) }
    // a separate response by token completes the acked exchange
    let other_token = coap.Message { kind: coap.kind_con(), code: coap.code_content(), id: 0x0001u16, token: tok_a[..], options: none, payload: "x" }
    let (matched_o, _, _) = coap.exchange_receive(&xs[1usize], &other_token)
    if matched_o { os.exit(5i32) }
    let separate = coap.Message { kind: coap.kind_con(), code: coap.code_content(), id: 0x0002u16, token: tok_b[..], options: none, payload: "x" }
    let (matched_s, reply_s, re_s) = coap.exchange_receive(&xs[1usize], &separate)
    if re_s != ok || !matched_s || reply_s != .Separate || xs[1usize].state != .Done { os.exit(5i32) }
    // piggybacked, reset, and the jitter 0.5 schedule
    coap.exchange_send(&xs[0usize], 100u64, 0x3333u16, tok_a[..], true, 0.5f64)
    let (t8, te8) = coap.exchange_timeouts(xs[..], 2599u64, ids[..])
    if te8 != ok || t8 != 0usize { os.exit(5i32) }
    let (t9, te9) = coap.exchange_timeouts(xs[..], 2600u64, ids[..])
    if te9 != ok || t9 != 1usize || ids[0usize] != 0x3333u16 { os.exit(5i32) }
    let piggy = coap.Message { kind: coap.kind_ack(), code: coap.code_not_found(), id: 0x3333u16, token: tok_a[..], options: none, payload: none }
    let (matched_p, reply_p, _) = coap.exchange_receive(&xs[0usize], &piggy)
    if !matched_p || reply_p != .Piggybacked || xs[0usize].state != .Done { os.exit(5i32) }
    coap.exchange_send(&xs[1usize], 0u64, 0x4444u16, tok_b[..], false, 0.0f64)
    if xs[1usize].state != .Acked { os.exit(5i32) }
    let (t10, te10) = coap.exchange_timeouts(xs[..], 100000u64, ids[..])
    if te10 != ok || t10 != 0usize { os.exit(5i32) }
    let reset = coap.Message { kind: coap.kind_rst(), code: 0u8, id: 0x4444u16, token: none, options: none, payload: none }
    let (matched_x, reply_x, _) = coap.exchange_receive(&xs[1usize], &reset)
    if !matched_x || reply_x != .Reset || xs[1usize].state != .Failed { os.exit(5i32) }

    // 6: RFC 7959 block values.
    if coap.block_encode(3u32, true, 6u8) != 0x3eu32 { os.exit(6i32) }
    if coap.block_encode(0u32, true, 6u8) != 0x0eu32 || coap.block_encode(1u32, true, 6u8) != 0x1eu32 || coap.block_encode(2u32, false, 6u8) != 0x26u32 { os.exit(6i32) }
    if coap.block_encode(0u32, false, 2u8) != 0x02u32 || coap.block_encode(1u32, true, 4u8) != 0x1cu32 || coap.block_encode(4096u32, true, 6u8) != 0x1000eu32 { os.exit(6i32) }
    let (bn, bm, bs) = coap.block_decode(0x1000eu32)
    if bn != 4096u32 || !bm || bs != 6u8 || coap.block_size(bs) != 1024usize { os.exit(6i32) }
    let (bn2, bm2, bs2) = coap.block_decode(0x26u32)
    if bn2 != 2u32 || bm2 || bs2 != 6u8 || coap.block_size(0u8) != 16usize { os.exit(6i32) }
    var bopts: [8]u8 = zero
    used = 0usize
    last = 0u16
    if coap.options_add_uint(bopts[..], &used, &last, coap.opt_block2(), 0x1000eu32) != ok || used != 5usize || bopts[0usize] != 0xd3u8 || bopts[1usize] != 10u8 { os.exit(6i32) }

    try io.print("net coap ok\n")
    ret ok
}
