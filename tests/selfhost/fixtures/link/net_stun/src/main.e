// `e.net.stun`: the RFC 5769 sample request decodes attribute by attribute
// and its fingerprint and message integrity verify; the IPv4 and IPv6
// responses give the RFC's addresses; our own encoded request and response
// round-trip; candidate gathering, the server-reflexive candidate, the
// redundancy rule, sorting, pair priorities and pruned pairs agree with the
// Python replica. Each check exits with its own code.

use e.io
use e.mem
use e.net.stun
use e.os

fn same(left: []const u8, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let req: [108]u8 = [108]u8{ 0, 1, 0, 88, 33, 18, 164, 66, 183, 231, 167, 1, 188, 52, 214, 134, 250, 135, 223, 174, 128, 34, 0, 16, 83, 84, 85, 78, 32, 116, 101, 115, 116, 32, 99, 108, 105, 101, 110, 116, 0, 36, 0, 4, 110, 0, 1, 255, 128, 41, 0, 8, 147, 47, 249, 177, 81, 38, 59, 54, 0, 6, 0, 9, 101, 118, 116, 106, 58, 104, 54, 118, 89, 32, 32, 32, 0, 8, 0, 20, 154, 234, 167, 12, 191, 216, 203, 86, 120, 30, 242, 181, 178, 211, 242, 73, 193, 181, 113, 162, 128, 40, 0, 4, 229, 122, 59, 207 }
    let resp4: [80]u8 = [80]u8{ 1, 1, 0, 60, 33, 18, 164, 66, 183, 231, 167, 1, 188, 52, 214, 134, 250, 135, 223, 174, 128, 34, 0, 11, 116, 101, 115, 116, 32, 118, 101, 99, 116, 111, 114, 32, 0, 32, 0, 8, 0, 1, 161, 71, 225, 18, 166, 67, 0, 8, 0, 20, 43, 145, 245, 153, 253, 158, 144, 195, 140, 116, 137, 249, 42, 249, 186, 83, 240, 107, 231, 215, 128, 40, 0, 4, 192, 125, 76, 150 }
    let resp6: [92]u8 = [92]u8{ 1, 1, 0, 72, 33, 18, 164, 66, 183, 231, 167, 1, 188, 52, 214, 134, 250, 135, 223, 174, 128, 34, 0, 11, 116, 101, 115, 116, 32, 118, 101, 99, 116, 111, 114, 32, 0, 32, 0, 20, 0, 2, 161, 71, 1, 19, 169, 250, 165, 211, 241, 121, 188, 37, 244, 181, 190, 210, 185, 217, 0, 8, 0, 20, 163, 130, 149, 78, 75, 230, 123, 241, 23, 132, 201, 124, 130, 146, 194, 117, 191, 227, 237, 65, 128, 40, 0, 4, 200, 251, 11, 76 }
    let password = "VOkJxbRl1RmTxUk/WvJxBt"

    // 1: the RFC 5769 §2.1 request.
    let (h, decode_error) = stun.decode(req[0..])
    if decode_error != ok || h.kind != 1u16 || h.length != 88u16 || h.txid[0] != 183u8 || h.txid[11] != 174u8 { os.exit(1i32) }
    if stun.message_class(h.kind) != 0u8 || stun.message_method(h.kind) != 1u16 { os.exit(1i32) }
    var pos = 20usize
    var more = true
    var seen = 0usize
    while more {
        let (kind, value, rest, attribute_error) = stun.attribute_next(req[0..], &pos)
        if attribute_error != ok { os.exit(1i32) }
        if seen == 0usize && (kind != 32802u16 || !same(value, "STUN test client")) { os.exit(1i32) }
        if seen == 1usize && (kind != 36u16 || value.len != 4usize || (u32(value[0]) << 24u32) + (u32(value[1]) << 16u32) + (u32(value[2]) << 8u32) + u32(value[3]) != 1845494271u32) { os.exit(1i32) }
        if seen == 2usize && (kind != 32809u16 || value.len != 8usize) { os.exit(1i32) }
        if seen == 3usize && (kind != 6u16 || !same(value, "evtj:h6vY")) { os.exit(1i32) }
        if seen == 4usize && (kind != 8u16 || value.len != 20usize || value[0] != 154u8) { os.exit(1i32) }
        if seen == 5usize && (kind != 32808u16 || value.len != 4usize || rest) { os.exit(1i32) }
        seen += 1usize
        more = rest
    }
    if seen != 6usize || pos != 108usize { os.exit(1i32) }
    if !stun.verify_fingerprint(req[0..]) { os.exit(1i32) }
    if !stun.verify_message_integrity(req[0..], password) { os.exit(1i32) }
    if stun.verify_message_integrity(req[0..], "wrong") { os.exit(1i32) }
    var broken: [108]u8 = req
    broken[30] = 0u8
    if stun.verify_fingerprint(broken[0..]) || stun.verify_message_integrity(broken[0..], password) { os.exit(1i32) }
    let (_, cookie_error) = stun.decode(broken[..4usize])
    if cookie_error != stun.TooSmall { os.exit(1i32) }
    broken[4] = 0u8
    let (_, bad_cookie) = stun.decode(broken[0..])
    if bad_cookie != stun.Malformed { os.exit(1i32) }
    broken[4] = 33u8
    broken[0] = 192u8
    let (_, bad_bits) = stun.decode(broken[0..])
    if bad_bits != stun.Malformed { os.exit(1i32) }

    // 2: the §2.2 IPv4 and §2.3 IPv6 responses.
    let (h4, decode4_error) = stun.decode(resp4[0..])
    if decode4_error != ok || h4.kind != 257u16 || stun.message_class(h4.kind) != 2u8 { os.exit(2i32) }
    if !stun.verify_fingerprint(resp4[0..]) || !stun.verify_message_integrity(resp4[0..], password) { os.exit(2i32) }
    let (xor4, _, has4) = stun.find_attribute(resp4[0..], 32u16)
    if !has4 { os.exit(2i32) }
    let (addr4, addr4_error) = stun.xor_mapped_address(xor4, h4.txid)
    if addr4_error != ok || addr4.family != 1u8 || addr4.port != 32853u16 { os.exit(2i32) }
    if addr4.ip[0] != 192u8 || addr4.ip[1] != 0u8 || addr4.ip[2] != 2u8 || addr4.ip[3] != 1u8 { os.exit(2i32) }
    let (h6, decode6_error) = stun.decode(resp6[0..])
    if decode6_error != ok || !stun.verify_fingerprint(resp6[0..]) || !stun.verify_message_integrity(resp6[0..], password) { os.exit(2i32) }
    let (xor6, _, has6) = stun.find_attribute(resp6[0..], 32u16)
    if !has6 { os.exit(2i32) }
    let (addr6, addr6_error) = stun.xor_mapped_address(xor6, h6.txid)
    if addr6_error != ok || addr6.family != 2u8 || addr6.port != 32853u16 { os.exit(2i32) }
    let want6: [16]u8 = [16]u8{ 32, 1, 13, 184, 18, 52, 86, 120, 0, 17, 34, 51, 68, 85, 102, 119 }
    var i = 0usize
    while i < 16usize {
        if addr6.ip[i] != want6[i] { os.exit(2i32) }
        i += 1usize
    }

    // 3: our own request and response round-trip.
    var dst: [128]u8 = zero
    let (request_len, request_error) = stun.encode_binding_request(dst[0..], h.txid, "neper", true)
    if request_error != ok || request_len != 40usize { os.exit(3i32) }
    let (ours, ours_error) = stun.decode(dst[..request_len])
    if ours_error != ok || ours.kind != 1u16 || ours.length != 20u16 || ours.txid[5] != h.txid[5] { os.exit(3i32) }
    if !stun.verify_fingerprint(dst[..request_len]) { os.exit(3i32) }
    if (u32(dst[36]) << 24u32) + (u32(dst[37]) << 16u32) + (u32(dst[38]) << 8u32) + u32(dst[39]) != 976384005u32 { os.exit(3i32) }
    let (_, small_error) = stun.encode_binding_request(dst[..30usize], h.txid, "neper", true)
    if small_error != stun.TooSmall { os.exit(3i32) }
    let mapped = stun.ipv4(192u8, 0u8, 2u8, 1u8, 32853u16)
    let (response_len, response_error) = stun.encode_binding_response(dst[0..], h.txid, mapped, true)
    if response_error != ok || response_len != 32usize { os.exit(3i32) }
    i = 0usize
    while i < 8usize {
        if dst[24usize + i] != resp4[40usize + i] { os.exit(3i32) }
        i += 1usize
    }
    var used = response_len
    if stun.add_message_integrity(dst[0..], &used, password) != ok || used != 56usize { os.exit(3i32) }
    if stun.add_fingerprint(dst[0..], &used) != ok || used != 64usize { os.exit(3i32) }
    if !stun.verify_message_integrity(dst[..used], password) || !stun.verify_fingerprint(dst[..used]) { os.exit(3i32) }
    if stun.verify_message_integrity(dst[..used], "VOkJxbRl1RmTxUk/WvJxBu") { os.exit(3i32) }
    let (plain_len, plain_error) = stun.encode_binding_response(dst[0..], h.txid, mapped, false)
    if plain_error != ok || plain_len != 32usize { os.exit(3i32) }
    let (plain_value, _, has_plain) = stun.find_attribute(dst[..plain_len], 1u16)
    if !has_plain { os.exit(3i32) }
    let (plain_addr, plain_addr_error) = stun.mapped_address(plain_value)
    if plain_addr_error != ok || !stun.address_equal(plain_addr, mapped) { os.exit(3i32) }

    // 4: gathering.
    var locals: [2]stun.Address = zero
    locals[0] = stun.ipv4(10u8, 0u8, 0u8, 5u8, 5000u16)
    locals[1] = stun.ipv4(192u8, 168u8, 1u8, 7u8, 5001u16)
    var out: [8]stun.Candidate = zero
    var (count, gather_error) = stun.gather_candidates(locals[0..], 2u8, out[0..])
    if gather_error != ok || count != 4usize { os.exit(4i32) }
    let want_priority: [4]u32 = [4]u32{ 2130706431, 2130706430, 2130706175, 2130706174 }
    let want_foundation: [4]u32 = [4]u32{ 3188024653, 3188024653, 3997946878, 3997946878 }
    i = 0usize
    while i < 4usize {
        if out[i].kind != 0u8 || out[i].priority != want_priority[i] || out[i].foundation != want_foundation[i] { os.exit(4i32) }
        if out[i].component != u8(i % 2usize) + 1u8 || !stun.address_equal(out[i].base, locals[i / 2usize]) { os.exit(4i32) }
        i += 1usize
    }
    let server = stun.ipv4(198u8, 51u8, 100u8, 1u8, 3478u16)
    if stun.gather_reflexive(out[0..], &count, 0usize, server, resp4[0..]) != ok || count != 5usize { os.exit(4i32) }
    if out[4].kind != 1u8 || out[4].priority != 1694498815u32 || out[4].foundation != 3917053541u32 || out[4].component != 1u8 { os.exit(4i32) }
    if !stun.address_equal(out[4].address, mapped) || !stun.address_equal(out[4].base, locals[0]) { os.exit(4i32) }
    let (redundant_len, redundant_error) = stun.encode_binding_response(dst[0..], h.txid, locals[0], true)
    if redundant_error != ok { os.exit(4i32) }
    if stun.gather_reflexive(out[0..], &count, 0usize, server, dst[..redundant_len]) != ok || count != 5usize { os.exit(4i32) }
    if stun.gather_reflexive(out[0..], &count, 0usize, server, resp4[0..]) != ok || count != 5usize { os.exit(4i32) }
    if stun.gather_reflexive(out[0..], &count, 0usize, server, req[0..]) != stun.Invalid { os.exit(4i32) }
    var twice: [2]stun.Address = zero
    twice[0] = locals[0]
    twice[1] = locals[0]
    var dedup: [4]stun.Candidate = zero
    let (dedup_count, dedup_error) = stun.gather_candidates(twice[0..], 2u8, dedup[0..])
    if dedup_error != ok || dedup_count != 2usize { os.exit(4i32) }
    let (_, room_error) = stun.gather_candidates(locals[0..], 2u8, dedup[..3usize])
    if room_error != stun.TooSmall { os.exit(4i32) }
    var shuffled: [5]stun.Candidate = zero
    shuffled[0] = out[4]
    shuffled[1] = out[3]
    shuffled[2] = out[1]
    shuffled[3] = out[2]
    shuffled[4] = out[0]
    stun.sort_candidates(shuffled[0..])
    i = 0usize
    while i < 5usize {
        if shuffled[i].priority != out[i].priority { os.exit(4i32) }
        i += 1usize
    }

    // 5: pair priorities and pruned pairs.
    if stun.pair_priority(2130706431u32, 1694498815u32) != 7277816997797167103u64 { os.exit(5i32) }
    if stun.pair_priority(1694498815u32, 2130706431u32) != 7277816997797167102u64 { os.exit(5i32) }
    var remote: [3]stun.Candidate = zero
    let remote_host = stun.ipv4(203u8, 0u8, 113u8, 9u8, 6000u16)
    remote[0] = stun.Candidate { kind: 0u8, address: remote_host, base: remote_host, priority: stun.priority(0u8, 65535u16, 1u8), foundation: 0u32, component: 1u8 }
    remote[1] = stun.Candidate { kind: 1u8, address: stun.ipv4(203u8, 0u8, 113u8, 10u8, 6001u16), base: remote_host, priority: stun.priority(1u8, 65535u16, 1u8), foundation: 0u32, component: 1u8 }
    let remote_host2 = stun.ipv4(203u8, 0u8, 113u8, 9u8, 6002u16)
    remote[2] = stun.Candidate { kind: 0u8, address: remote_host2, base: remote_host2, priority: stun.priority(0u8, 65535u16, 2u8), foundation: 0u32, component: 2u8 }
    var pairs: [16]stun.Pair = zero
    let pair_count = stun.candidate_pairs(out[..count], remote[0..], true, pairs[0..])
    if pair_count != 6usize { os.exit(5i32) }
    let want_pair: [6]u64 = [6]u64{ 9151314442783293438, 9151314438488326140, 9151313343271665662, 9151313338976698364, 7277816997797167103, 7277816997797166591 }
    let want_local: [6]u32 = [6]u32{ 0, 1, 2, 3, 0, 2 }
    let want_remote: [6]u32 = [6]u32{ 0, 2, 0, 2, 1, 1 }
    i = 0usize
    while i < 6usize {
        if pairs[i].priority != want_pair[i] || pairs[i].local != want_local[i] || pairs[i].remote != want_remote[i] { os.exit(5i32) }
        i += 1usize
    }
    let controlled_count = stun.candidate_pairs(out[..count], remote[0..], false, pairs[0..])
    if controlled_count != 6usize || pairs[4].priority != 7277816997797167102u64 { os.exit(5i32) }

    try io.print("net stun ok\n")
    ret ok
}
