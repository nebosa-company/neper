// `e.net.quic`: the RFC 9001 A.1 client Initial header decodes and
// re-encodes, a short header round-trips, the RFC 9000 A.1 varints decode
// and encode, the migration frames (NEW_CONNECTION_ID, ACK with ranges and
// ECN, CONNECTION_CLOSE, PADDING, PING) match the Python replica byte for
// byte, and a scripted migration (two issued CIDs, a padded PATH_CHALLENGE,
// a stray then a matching PATH_RESPONSE, RETIRE_CONNECTION_ID for the old
// CID, a timed-out second migration, NoCid, the amplification limit and
// PATH_RESPONSE answers) agrees with the replica. Each check exits with its
// own code.

use e.io
use e.mem
use e.net.quic
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: RFC 9001 A.1 client Initial (header bytes, payload zeroed to 1200).
    var initial: [1200]u8 = zero
    let initial_header: [18]u8 = [18]u8{ 192, 0, 0, 0, 1, 8, 131, 148, 200, 240, 62, 81, 87, 8, 0, 0, 68, 158 }
    var i = 0usize
    while i < 18usize {
        initial[i] = initial_header[i]
        i += 1usize
    }
    let (h1, e1) = quic.header_decode(initial[0..], 0usize)
    if e1 != ok || !h1.long || h1.kind != quic.KIND_INITIAL || h1.version != 1u32 { os.exit(1i32) }
    if h1.dcid.len != 8usize || !quic.bytes_equal(h1.dcid, initial_header[6usize..14usize]) || h1.scid.len != 0usize || h1.token.len != 0usize { os.exit(1i32) }
    if h1.payload_offset != 18usize || h1.length != 1182u64 { os.exit(1i32) }
    var buf: [1300]u8 = zero
    let (n1, e1b) = quic.header_encode_long(buf[0..], quic.KIND_INITIAL, 1u32, h1.dcid, initial[0..0usize], initial[0..0usize], 1182u64)
    if e1b != ok || n1 != 18usize || !quic.bytes_equal(buf[..18usize], initial_header[0..]) { os.exit(1i32) }
    let (_, e1c) = quic.header_decode(initial[..18usize], 0usize)
    if e1c != quic.Malformed { os.exit(1i32) }
    let (_, e1d) = quic.header_decode(initial[..10usize], 0usize)
    if e1d != quic.TooSmall { os.exit(1i32) }

    // 2: a short header round trip.
    let dcid: [8]u8 = [8]u8{ 17, 34, 51, 68, 85, 102, 119, 136 }
    let (n2, e2) = quic.header_encode_short(buf[0..], dcid[0..], true, true)
    if e2 != ok || n2 != 9usize || buf[0] != 100u8 { os.exit(2i32) }
    buf[9] = 1u8
    buf[10] = 2u8
    let (h2, e2b) = quic.header_decode(buf[..11usize], 8usize)
    if e2b != ok || h2.long || !h2.spin || !h2.key_phase || !quic.bytes_equal(h2.dcid, dcid[0..]) || h2.payload_offset != 9usize || h2.length != 2u64 { os.exit(2i32) }
    let (_, e2c) = quic.header_encode_short(buf[..5usize], dcid[0..], false, false)
    if e2c != quic.TooSmall { os.exit(2i32) }
    var bad: [1]u8 = zero
    let (_, e2d) = quic.header_decode(bad[0..], 0usize)
    if e2d != quic.Malformed { os.exit(2i32) }

    // 3: RFC 9000 A.1 varints.
    let v8: [8]u8 = [8]u8{ 194, 25, 124, 94, 255, 20, 232, 140 }
    let v4: [4]u8 = [4]u8{ 157, 127, 62, 125 }
    let v2: [2]u8 = [2]u8{ 123, 189 }
    let v1: [1]u8 = [1]u8{ 37 }
    let (x8, c8, e3a) = quic.varint_decode(v8[0..])
    if e3a != ok || x8 != 151288809941952652u64 || c8 != 8usize { os.exit(3i32) }
    let (x4, c4, e3b) = quic.varint_decode(v4[0..])
    if e3b != ok || x4 != 494878333u64 || c4 != 4usize { os.exit(3i32) }
    let (x2, c2, e3c) = quic.varint_decode(v2[0..])
    if e3c != ok || x2 != 15293u64 || c2 != 2usize { os.exit(3i32) }
    let (x1, c1, e3d) = quic.varint_decode(v1[0..])
    if e3d != ok || x1 != 37u64 || c1 != 1usize { os.exit(3i32) }
    let (w8, e3e) = quic.varint_encode(buf[0..], x8)
    if e3e != ok || w8 != 8usize || !quic.bytes_equal(buf[..8usize], v8[0..]) { os.exit(3i32) }
    let (w4, e3f) = quic.varint_encode(buf[0..], x4)
    if e3f != ok || w4 != 4usize || !quic.bytes_equal(buf[..4usize], v4[0..]) { os.exit(3i32) }
    let (w2, e3g) = quic.varint_encode(buf[0..], x2)
    if e3g != ok || w2 != 2usize || !quic.bytes_equal(buf[..2usize], v2[0..]) { os.exit(3i32) }
    let (w1, e3h) = quic.varint_encode(buf[0..], x1)
    if e3h != ok || w1 != 1usize || buf[0] != 37u8 { os.exit(3i32) }
    let (_, e3i) = quic.varint_encode(buf[0..], 1u64 << 62u32)
    if e3i != quic.Invalid { os.exit(3i32) }
    let (_, _, e3j) = quic.varint_decode(v8[..3usize])
    if e3j != quic.TooSmall { os.exit(3i32) }

    // 4: frames against the replica bytes.
    let ncid_b: [28]u8 = [28]u8{ 24, 1, 0, 8, 176, 177, 178, 179, 180, 181, 182, 183, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }
    let ncid_c: [25]u8 = [25]u8{ 24, 2, 0, 5, 192, 193, 194, 195, 196, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31 }
    let (fb, used_b, e4a) = quic.frame_decode(ncid_b[0..])
    if e4a != ok || used_b != 28usize || fb.kind != quic.FRAME_NEW_CONNECTION_ID || fb.seq != 1u64 || fb.retire_prior_to != 0u64 { os.exit(4i32) }
    if !quic.bytes_equal(fb.cid, ncid_b[4usize..12usize]) || !quic.bytes_equal(fb.token, ncid_b[12usize..28usize]) { os.exit(4i32) }
    let (n4, e4b) = quic.frame_encode_new_connection_id(buf[0..], 1u64, 0u64, fb.cid, fb.token)
    if e4b != ok || n4 != 28usize || !quic.bytes_equal(buf[..28usize], ncid_b[0..]) { os.exit(4i32) }
    let (fc, used_c, e4c) = quic.frame_decode(ncid_c[0..])
    if e4c != ok || used_c != 25usize || fc.seq != 2u64 || fc.cid.len != 5usize || fc.token[0] != 16u8 { os.exit(4i32) }
    let ack: [10]u8 = [10]u8{ 2, 67, 232, 50, 2, 10, 8, 10, 13, 5 }
    let lo: [3]u64 = [3]u64{ 990, 970, 950 }
    let hi: [3]u64 = [3]u64{ 1000, 980, 955 }
    var no_ecn: [3]u64 = zero
    let (n4b, e4d) = quic.frame_encode_ack(buf[0..], 50u64, lo[0..], hi[0..], false, no_ecn)
    if e4d != ok || n4b != 10usize || !quic.bytes_equal(buf[..10usize], ack[0..]) { os.exit(4i32) }
    let (fa, used_a, e4e) = quic.frame_decode(ack[0..])
    if e4e != ok || used_a != 10usize || fa.kind != quic.FRAME_ACK || fa.largest != 1000u64 || fa.delay != 50u64 || fa.range_count != 2u64 { os.exit(4i32) }
    var rlo: [4]u64 = zero
    var rhi: [4]u64 = zero
    let (ranges, e4f) = quic.ack_ranges(&fa, rlo[0..], rhi[0..])
    if e4f != ok || ranges != 3usize { os.exit(4i32) }
    i = 0usize
    while i < 3usize {
        if rlo[i] != lo[i] || rhi[i] != hi[i] { os.exit(4i32) }
        i += 1usize
    }
    let (_, e4g) = quic.ack_ranges(&fa, rlo[..2usize], rhi[..2usize])
    if e4g != quic.TooSmall { os.exit(4i32) }
    let ack_ecn: [11]u8 = [11]u8{ 3, 128, 1, 17, 112, 3, 0, 0, 1, 2, 3 }
    let (fe, used_e, e4h) = quic.frame_decode(ack_ecn[0..])
    if e4h != ok || used_e != 11usize || fe.kind != quic.FRAME_ACK_ECN || fe.largest != 70000u64 || fe.delay != 3u64 || fe.range_count != 0u64 { os.exit(4i32) }
    if fe.ecn[0] != 1u64 || fe.ecn[1] != 2u64 || fe.ecn[2] != 3u64 { os.exit(4i32) }
    let (ranges_e, e4i) = quic.ack_ranges(&fe, rlo[0..], rhi[0..])
    if e4i != ok || ranges_e != 1usize || rlo[0] != 70000u64 || rhi[0] != 70000u64 { os.exit(4i32) }
    let ecn_counts: [3]u64 = [3]u64{ 1, 2, 3 }
    let (n4c, e4j) = quic.frame_encode_ack(buf[0..], 3u64, rlo[..1usize], rhi[..1usize], true, ecn_counts)
    if e4j != ok || n4c != 11usize || !quic.bytes_equal(buf[..11usize], ack_ecn[0..]) { os.exit(4i32) }
    let close: [7]u8 = [7]u8{ 28, 10, 24, 3, 98, 121, 101 }
    let (fx, used_x, e4k) = quic.frame_decode(close[0..])
    if e4k != ok || used_x != 7usize || fx.kind != quic.FRAME_CONNECTION_CLOSE || fx.error_code != 10u64 || fx.frame_type != 24u64 || !quic.bytes_equal(fx.reason, "bye") { os.exit(4i32) }
    let (n4d, e4l) = quic.frame_encode_connection_close(buf[0..], quic.FRAME_CONNECTION_CLOSE, 10u64, 24u64, "bye")
    if e4l != ok || n4d != 7usize || !quic.bytes_equal(buf[..7usize], close[0..]) { os.exit(4i32) }
    let run: [6]u8 = [6]u8{ 0, 0, 0, 0, 0, 1 }
    let (fp, used_p, e4m) = quic.frame_decode(run[0..])
    if e4m != ok || fp.kind != quic.FRAME_PADDING || used_p != 5usize { os.exit(4i32) }
    let (fq, used_q, e4n) = quic.frame_decode(run[5usize..])
    if e4n != ok || fq.kind != quic.FRAME_PING || used_q != 1usize { os.exit(4i32) }
    let unknown: [1]u8 = [1]u8{ 6 }
    let (_, _, e4o) = quic.frame_decode(unknown[0..])
    if e4o != quic.Invalid { os.exit(4i32) }
    let (_, _, e4p) = quic.frame_decode(ncid_b[..20usize])
    if e4p != quic.TooSmall { os.exit(4i32) }
    let (n4e, e4q) = quic.frame_encode_retire_connection_id(buf[0..], 300u64)
    if e4q != ok || n4e != 3usize || buf[0] != 25u8 || buf[1] != 65u8 || buf[2] != 44u8 { os.exit(4i32) }

    // 5: the migration script.
    var peer_seq: [4]u64 = zero
    var peer_cid: [80]u8 = zero
    var peer_len: [4]u8 = zero
    var peer_token: [64]u8 = zero
    var peer_active: [4]u8 = zero
    let (peer, e5a) = quic.cid_set(peer_seq[0..], peer_cid[0..], peer_len[0..], peer_token[0..], peer_active[0..])
    if e5a != ok { os.exit(5i32) }
    var own_seq: [2]u64 = zero
    var own_cid: [40]u8 = zero
    var own_len: [2]u8 = zero
    var own_token: [32]u8 = zero
    var own_active: [2]u8 = zero
    let (own, e5b) = quic.cid_set(own_seq[0..], own_cid[0..], own_len[0..], own_token[0..], own_active[0..])
    if e5b != ok { os.exit(5i32) }
    let (_, e5c) = quic.cid_set(peer_seq[0..], peer_cid[..79usize], peer_len[0..], peer_token[0..], peer_active[0..])
    if e5c != quic.TooSmall { os.exit(5i32) }
    var cid_a: [8]u8 = zero
    i = 0usize
    while i < 8usize {
        cid_a[i] = 160u8 + u8(i)
        i += 1usize
    }
    var zero_token: [16]u8 = zero
    var peer_set = peer
    if quic.cids_insert(&peer_set, 0u64, 0u64, cid_a[0..], zero_token[0..]) != ok { os.exit(5i32) }
    var paths: [4]quic.Path = zero
    let addr_a = quic.ipv4(10u8, 0u8, 0u8, 1u8, 5000u16)
    let addr_b = quic.ipv4(10u8, 0u8, 0u8, 2u8, 5001u16)
    let addr_c = quic.ipv4(10u8, 0u8, 0u8, 3u8, 5002u16)
    let addr_d = quic.ipv4(10u8, 0u8, 0u8, 4u8, 5003u16)
    let (conn0, e5d) = quic.connection(paths[0..], own, peer_set, quic.ipv4(192u8, 168u8, 0u8, 9u8, 4000u16), addr_a, 0usize)
    if e5d != ok { os.exit(5i32) }
    var conn = conn0
    if conn.path_count != 1usize || conn.active_path != 0u32 || conn.paths[0].state != .Validated || peer_active[0] != quic.CID_IN_USE { os.exit(5i32) }
    if quic.cids_add(&conn.peer_cids, &fb) != ok || quic.cids_add(&conn.peer_cids, &fc) != ok { os.exit(5i32) }
    if quic.cids_add(&conn.peer_cids, &fb) != ok { os.exit(5i32) }
    if quic.cids_insert(&conn.peer_cids, 1u64, 0u64, fc.cid, fb.token) != quic.Invalid { os.exit(5i32) }
    if quic.cids_insert(&conn.peer_cids, 3u64, 4u64, fc.cid, fb.token) != quic.Malformed { os.exit(5i32) }
    if quic.cids_add(&conn.peer_cids, &fa) != quic.Invalid { os.exit(5i32) }
    if conn.peer_cids.count != 3usize || quic.cids_active_count(&conn.peer_cids) != 3usize { os.exit(5i32) }
    let (unused0, found0) = quic.cids_pick_unused(&conn.peer_cids)
    if !found0 || unused0 != 1usize { os.exit(5i32) }
    let challenge: [8]u8 = [8]u8{ 90, 1, 2, 3, 4, 5, 6, 165 }
    var probe: [1200]u8 = zero
    let (probe_len, e5e) = quic.migrate(&conn, addr_b, 100u64, challenge, probe[0..])
    if e5e != ok || probe_len != 1200usize { os.exit(5i32) }
    let probe_head: [18]u8 = [18]u8{ 64, 176, 177, 178, 179, 180, 181, 182, 183, 26, 90, 1, 2, 3, 4, 5, 6, 165 }
    if !quic.bytes_equal(probe[..18usize], probe_head[0..]) { os.exit(5i32) }
    i = 18usize
    while i < 1200usize {
        if probe[i] != 0u8 { os.exit(5i32) }
        i += 1usize
    }
    if conn.active_path != 0u32 || conn.path_count != 2usize || conn.paths[1].state != .Validating || conn.paths[1].dcid_index != 1u32 || conn.paths[1].bytes_sent != 1200u64 { os.exit(5i32) }
    if !quic.address_equal(conn.paths[1].remote, addr_b) || !quic.address_equal(conn.paths[1].local, conn.paths[0].local) { os.exit(5i32) }
    let (unused1, found1) = quic.cids_pick_unused(&conn.peer_cids)
    if !found1 || unused1 != 2usize { os.exit(5i32) }
    let (_, e5f) = quic.migrate(&conn, addr_b, 100u64, challenge, probe[..100usize])
    if e5f != quic.TooSmall { os.exit(5i32) }
    var stray: [8]u8 = zero
    let (matched0, e5g) = quic.on_path_response(&conn, stray, 150u64)
    if e5g != ok || matched0 || conn.active_path != 0u32 { os.exit(5i32) }
    let (matched1, e5h) = quic.on_path_response(&conn, challenge, 150u64)
    if e5h != ok || !matched1 || conn.active_path != 1u32 || conn.paths[1].state != .Validated || conn.previous_path != 0u32 { os.exit(5i32) }
    let (retire_len, e5i) = quic.retire_old(&conn, buf[0..])
    if e5i != ok || retire_len != 2usize || buf[0] != 25u8 || buf[1] != 0u8 { os.exit(5i32) }
    if quic.cids_active_count(&conn.peer_cids) != 2usize || peer_active[0] != quic.CID_RETIRED { os.exit(5i32) }
    let (retire_again, e5j) = quic.retire_old(&conn, buf[0..])
    if e5j != ok || retire_again != 0usize { os.exit(5i32) }
    let (_, e5k) = quic.migrate(&conn, addr_b, 200u64, challenge, probe[0..])
    if e5k != quic.Invalid { os.exit(5i32) }
    let challenge2: [8]u8 = [8]u8{ 9, 8, 7, 6, 5, 4, 3, 2 }
    let (probe2_len, e5l) = quic.migrate(&conn, addr_c, 200u64, challenge2, probe[0..])
    if e5l != ok || probe2_len != 1200usize { os.exit(5i32) }
    let probe2_head: [15]u8 = [15]u8{ 64, 192, 193, 194, 195, 196, 26, 9, 8, 7, 6, 5, 4, 3, 2 }
    if !quic.bytes_equal(probe[..15usize], probe2_head[0..]) || conn.paths[2].dcid_index != 2u32 { os.exit(5i32) }
    if quic.path_timeout(&conn, 289u64, 30u64) || conn.paths[2].state != .Validating { os.exit(5i32) }
    if !quic.path_timeout(&conn, 290u64, 30u64) || conn.paths[2].state != .Failed || conn.active_path != 1u32 { os.exit(5i32) }
    let (_, e5m) = quic.migrate(&conn, addr_d, 300u64, challenge2, probe[0..])
    if e5m != quic.NoCid { os.exit(5i32) }
    // A fourth CID lets one more path open; a fifth path has no slot.
    var cid_d: [4]u8 = [4]u8{ 1, 2, 3, 4 }
    if quic.cids_insert(&conn.peer_cids, 3u64, 0u64, cid_d[0..], zero_token[0..]) != ok { os.exit(5i32) }
    let (_, e5n) = quic.migrate(&conn, addr_d, 300u64, challenge2, probe[0..])
    if e5n != ok || conn.path_count != 4usize { os.exit(5i32) }
    if quic.cids_insert(&conn.peer_cids, 4u64, 0u64, cid_d[..3usize], zero_token[0..]) != quic.Full { os.exit(5i32) }
    // retire_prior_to sweeps the earlier slots.
    var sweep_seq: [4]u64 = zero
    var sweep_cid: [80]u8 = zero
    var sweep_len: [4]u8 = zero
    var sweep_token: [64]u8 = zero
    var sweep_active: [4]u8 = zero
    let (sweep0, _) = quic.cid_set(sweep_seq[0..], sweep_cid[0..], sweep_len[0..], sweep_token[0..], sweep_active[0..])
    var sweep = sweep0
    if quic.cids_insert(&sweep, 0u64, 0u64, cid_a[0..], zero_token[0..]) != ok || quic.cids_insert(&sweep, 1u64, 0u64, fb.cid, fb.token) != ok { os.exit(5i32) }
    if quic.cids_insert(&sweep, 2u64, 2u64, fc.cid, fc.token) != ok || quic.cids_active_count(&sweep) != 1usize || sweep.retire_prior_to != 2u64 { os.exit(5i32) }
    if quic.cids_insert(&sweep, 1u64, 0u64, cid_d[0..], zero_token[0..]) != quic.Invalid { os.exit(5i32) }
    if quic.cids_retire(&sweep, 0u64) || !quic.cids_retire(&sweep, 2u64) || quic.cids_active_count(&sweep) != 0usize { os.exit(5i32) }

    // 6: the amplification limit and PATH_RESPONSE answers.
    var server_path: quic.Path = zero
    server_path.state = .Unvalidated
    server_path.bytes_received = 100u64
    if quic.amplification_allowance(&server_path) != 300u64 || !quic.can_send(&server_path, 300u64) || quic.can_send(&server_path, 301u64) { os.exit(6i32) }
    server_path.bytes_sent = 250u64
    if quic.amplification_allowance(&server_path) != 50u64 { os.exit(6i32) }
    server_path.bytes_received = 10u64
    if quic.amplification_allowance(&server_path) != 0u64 || quic.can_send(&server_path, 1u64) { os.exit(6i32) }
    server_path.state = .Validated
    if !quic.can_send(&server_path, 1u64 << 40u32) { os.exit(6i32) }
    let peer_challenge: [8]u8 = [8]u8{ 1, 2, 3, 4, 5, 6, 7, 8 }
    let (resp_len, e6a) = quic.on_path_challenge(&conn, peer_challenge, 1usize, probe[0..])
    if e6a != ok || resp_len != 1200usize { os.exit(6i32) }
    let resp_head: [18]u8 = [18]u8{ 64, 176, 177, 178, 179, 180, 181, 182, 183, 27, 1, 2, 3, 4, 5, 6, 7, 8 }
    if !quic.bytes_equal(probe[..18usize], resp_head[0..]) || probe[18] != 0u8 { os.exit(6i32) }
    quic.path_received(&conn, 2usize, 100u64)
    let (resp2_len, e6b) = quic.on_path_challenge(&conn, peer_challenge, 2usize, probe[0..])
    if e6b != ok || resp2_len != 15usize || probe[0] != 64u8 || probe[1] != 192u8 || probe[6] != 27u8 || probe[14] != 8u8 { os.exit(6i32) }
    if conn.paths[2].bytes_sent != 1215u64 || conn.paths[2].bytes_received != 100u64 { os.exit(6i32) }
    let (_, e6c) = quic.on_path_challenge(&conn, peer_challenge, 7usize, probe[0..])
    if e6c != quic.Invalid { os.exit(6i32) }

    try io.print("net quic ok\n")
    ret ok
}
