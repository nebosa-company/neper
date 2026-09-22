// `e.net.dns`: an EDNS/DO query for `example.com. A` equals the Python replica's
// bytes; a hand-built response with compression pointers decodes (header, A, AAAA,
// MX, TXT), a forward pointer is `Malformed`; the RFC 8080 Ed25519 DNSKEY has key
// tag 3613 and its DS digest; the MX RRset validates inside its window in mixed
// case, is `Expired` after, `BadSignature` flipped, `Invalid` with a wrong key tag;
// an algorithm 13 RRset validates; `chain_validate` from the DS; DoH GET/POST
// bytes and the response splitter; the DoT frame. Each check exits with its own code.

use e.io
use e.mem
use e.net.dns
use e.os

fn same(left: []const u8, right: []const u8) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let query_want: [40]u8 = [40]u8{ 18, 52, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0, 0, 1, 0, 1, 0, 0, 41, 16, 0, 0, 0, 128, 0, 0, 0 }
    let resp: [122]u8 = [122]u8{ 18, 52, 129, 128, 0, 1, 0, 2, 0, 0, 0, 2, 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0, 0, 1, 0, 1, 192, 12, 0, 1, 0, 1, 0, 0, 1, 44, 0, 4, 93, 184, 216, 34, 3, 119, 119, 119, 192, 12, 0, 28, 0, 1, 0, 0, 2, 88, 0, 16, 32, 1, 13, 184, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 192, 12, 0, 15, 0, 1, 0, 0, 0, 60, 0, 9, 0, 10, 4, 109, 97, 105, 108, 192, 12, 192, 12, 0, 16, 0, 1, 0, 0, 0, 5, 0, 12, 5, 104, 101, 108, 108, 111, 5, 119, 111, 114, 108, 100 }
    let bad: [34]u8 = [34]u8{ 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 192, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    let dnskey: [36]u8 = [36]u8{ 1, 1, 3, 15, 151, 77, 150, 162, 45, 34, 75, 192, 26, 219, 145, 80, 145, 71, 125, 68, 204, 217, 28, 154, 65, 161, 20, 48, 1, 1, 23, 213, 44, 89, 36, 14 }
    let rrsig: [95]u8 = [95]u8{ 0, 15, 15, 2, 0, 0, 14, 16, 85, 212, 252, 96, 85, 185, 76, 224, 14, 29, 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0, 160, 191, 100, 172, 155, 167, 239, 23, 193, 56, 133, 156, 24, 120, 187, 153, 168, 57, 254, 23, 89, 172, 165, 176, 215, 152, 207, 26, 177, 233, 141, 7, 145, 2, 244, 221, 179, 54, 143, 15, 228, 11, 179, 119, 241, 240, 14, 12, 221, 237, 183, 153, 22, 125, 86, 182, 233, 50, 120, 48, 114, 186, 141, 2 }
    let mx_rr: [43]u8 = [43]u8{ 7, 69, 120, 97, 109, 112, 108, 101, 3, 67, 79, 77, 0, 0, 15, 0, 1, 0, 0, 7, 8, 0, 20, 0, 10, 4, 77, 65, 73, 76, 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0 }
    let ds_want: [32]u8 = [32]u8{ 58, 165, 171, 55, 239, 206, 87, 247, 55, 252, 22, 39, 1, 63, 238, 7, 189, 242, 65, 189, 16, 243, 177, 150, 74, 181, 92, 120, 231, 154, 48, 75 }
    let dnskey13: [68]u8 = [68]u8{ 1, 1, 3, 13, 138, 71, 254, 71, 117, 56, 63, 151, 120, 186, 220, 229, 77, 88, 59, 232, 222, 142, 242, 107, 183, 82, 181, 107, 205, 95, 26, 252, 0, 177, 20, 58, 24, 157, 115, 97, 236, 119, 129, 181, 81, 40, 25, 95, 218, 20, 151, 21, 235, 96, 38, 74, 224, 87, 65, 46, 54, 212, 61, 56, 20, 111, 105, 1 }
    let rrsig13: [95]u8 = [95]u8{ 0, 15, 13, 2, 0, 0, 14, 16, 85, 212, 252, 96, 85, 185, 76, 224, 85, 218, 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0, 218, 223, 66, 219, 103, 187, 215, 49, 24, 138, 201, 29, 159, 202, 132, 238, 248, 158, 96, 194, 234, 123, 200, 91, 89, 213, 38, 133, 79, 205, 188, 24, 254, 79, 15, 183, 116, 230, 42, 196, 138, 43, 17, 65, 141, 38, 159, 38, 147, 219, 137, 199, 191, 0, 255, 44, 3, 1, 124, 234, 91, 56, 117, 221 }
    let rrsig_key: [95]u8 = [95]u8{ 0, 48, 15, 2, 0, 0, 14, 16, 85, 212, 252, 96, 85, 185, 76, 224, 14, 29, 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0, 7, 178, 162, 181, 98, 105, 149, 117, 228, 30, 162, 15, 26, 121, 227, 27, 93, 145, 189, 66, 81, 51, 58, 12, 199, 169, 31, 146, 214, 92, 11, 42, 110, 28, 15, 104, 59, 35, 246, 195, 154, 6, 247, 160, 250, 139, 131, 37, 177, 122, 23, 20, 197, 206, 69, 80, 133, 249, 96, 249, 46, 202, 234, 2 }
    let dnskey_rr: [59]u8 = [59]u8{ 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0, 0, 48, 0, 1, 0, 0, 14, 16, 0, 36, 1, 1, 3, 15, 151, 77, 150, 162, 45, 34, 75, 192, 26, 219, 145, 80, 145, 71, 125, 68, 204, 217, 28, 154, 65, 161, 20, 48, 1, 1, 23, 213, 44, 89, 36, 14 }
    let example_com: [13]u8 = [13]u8{ 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0 }
    let www_example_com: [17]u8 = [17]u8{ 3, 119, 119, 119, 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0 }
    let mail_example_com: [18]u8 = [18]u8{ 4, 109, 97, 105, 108, 7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0 }
    var buf: [512]u8 = zero
    var name: [255]u8 = zero
    var scratch: [1024]u8 = zero

    // 1: encode_query with EDNS and DO.
    let (query_len, query_error) = dns.encode_query(buf[0..], 4660u16, "example.com.", 1u16, 1u16, true, 4096u16, true)
    if query_error != ok || !same(buf[..query_len], query_want[0..]) { os.exit(1i32) }
    let (plain_len, plain_error) = dns.encode_query(buf[0..], 4660u16, "example.com", 1u16, 1u16, true, 0u16, false)
    if plain_error != ok || plain_len != 29usize || buf[11] != 0u8 || !same(buf[..11usize], query_want[..11usize]) || !same(buf[12usize..29usize], query_want[12usize..29usize]) { os.exit(1i32) }
    let (_, empty_label) = dns.encode_query(buf[0..], 1u16, "a..b", 1u16, 1u16, true, 0u16, false)
    if empty_label != dns.Invalid { os.exit(1i32) }
    let (_, small) = dns.encode_query(buf[..20usize], 1u16, "example.com.", 1u16, 1u16, true, 0u16, false)
    if small != dns.TooSmall { os.exit(1i32) }

    // 2: the response decodes through its compression pointers.
    let (h, header_error) = dns.decode_header(resp[0..])
    if header_error != ok || h.id != 4660u16 || h.flags != 33152u16 || h.qdcount != 1u16 || h.ancount != 2u16 || h.nscount != 0u16 || h.arcount != 2u16 { os.exit(2i32) }
    if !dns.header_is_response(h) || dns.header_rcode(h) != 0u8 || dns.header_authentic_data(h) || dns.header_truncated(h) { os.exit(2i32) }
    var pos = 12usize
    let (qname_len, qtype, qclass, question_error) = dns.decode_question(resp[0..], &pos, name[0..])
    if question_error != ok || qtype != 1u16 || qclass != 1u16 || !same(name[..qname_len], example_com[0..]) || pos != 29usize { os.exit(2i32) }
    let (r1, r1_error) = dns.decode_rr(resp[0..], &pos, name[0..])
    if r1_error != ok || r1.kind != 1u16 || r1.class != 1u16 || r1.ttl != 300u32 || !same(name[..r1.name_len], example_com[0..]) { os.exit(2i32) }
    let (a4, a4_error) = dns.rdata_a(r1.rdata)
    if a4_error != ok || a4[0] != 93u8 || a4[1] != 184u8 || a4[2] != 216u8 || a4[3] != 34u8 { os.exit(2i32) }
    let (r2, r2_error) = dns.decode_rr(resp[0..], &pos, name[0..])
    if r2_error != ok || r2.kind != 28u16 || r2.ttl != 600u32 || !same(name[..r2.name_len], www_example_com[0..]) { os.exit(2i32) }
    let (a6, a6_error) = dns.rdata_aaaa(r2.rdata)
    if a6_error != ok || a6[0] != 32u8 || a6[1] != 1u8 || a6[2] != 13u8 || a6[3] != 184u8 || a6[15] != 1u8 { os.exit(2i32) }
    let (text_len, text_error) = dns.name_text(name[..r2.name_len], buf[0..])
    if text_error != ok || !same(buf[..text_len], "www.example.com.") { os.exit(2i32) }
    let (r3, r3_error) = dns.decode_rr(resp[0..], &pos, name[0..])
    if r3_error != ok || r3.kind != 15u16 || r3.ttl != 60u32 { os.exit(2i32) }
    let (preference, exchange_len, mx_error) = dns.rdata_mx(resp[0..], r3, name[0..])
    if mx_error != ok || preference != 10u16 || !same(name[..exchange_len], mail_example_com[0..]) { os.exit(2i32) }
    let (r4, r4_error) = dns.decode_rr(resp[0..], &pos, name[0..])
    if r4_error != ok || r4.kind != 16u16 || pos != resp.len { os.exit(2i32) }
    var txt_pos = 0usize
    let (t1_len, t1_error) = dns.rdata_txt(r4.rdata, &txt_pos, buf[0..])
    if t1_error != ok || !same(buf[..t1_len], "hello") { os.exit(2i32) }
    let (t2_len, t2_error) = dns.rdata_txt(r4.rdata, &txt_pos, buf[0..])
    if t2_error != ok || !same(buf[..t2_len], "world") || txt_pos != r4.rdata.len { os.exit(2i32) }
    let (_, t3_error) = dns.rdata_txt(r4.rdata, &txt_pos, buf[0..])
    if t3_error != dns.Malformed { os.exit(2i32) }
    pos = 12usize
    let (_, forward_error) = dns.decode_name(bad[0..], &pos, name[0..])
    if forward_error != dns.Malformed { os.exit(2i32) }
    pos = 12usize
    if dns.skip_question(resp[0..], &pos) != ok || pos != 29usize { os.exit(2i32) }
    let (_, short_error) = dns.decode_header(resp[..11usize])
    if short_error != dns.TooSmall { os.exit(2i32) }

    // 3: RFC 8080 key tag and the DNSKEY/DS/RRSIG readers.
    if dns.key_tag(dnskey[0..]) != 3613u16 { os.exit(3i32) }
    let (k, k_error) = dns.rdata_dnskey(dnskey[0..])
    if k_error != ok || k.flags != 257u16 || k.protocol != 3u8 || k.algorithm != 15u8 || k.public_key.len != 32usize { os.exit(3i32) }
    let (s, s_error) = dns.rdata_rrsig(rrsig[0..])
    if s_error != ok || s.type_covered != 15u16 || s.algorithm != 15u8 || s.labels != 2u8 || s.original_ttl != 3600u32 { os.exit(3i32) }
    if s.expiration != 1440021600u32 || s.inception != 1438207200u32 || s.key_tag != 3613u16 || !same(s.signer, example_com[0..]) || s.signature.len != 64usize { os.exit(3i32) }

    // 4: the MX RRset validates in mixed case; window, flipped byte and key tag refusals.
    if dns.dnssec_validate(mx_rr[0..], rrsig[0..], dnskey[0..], 1439000000u32, scratch[0..]) != ok { os.exit(4i32) }
    if dns.dnssec_validate(mx_rr[0..], rrsig[0..], dnskey[0..], 1440021601u32, scratch[0..]) != dns.Expired { os.exit(4i32) }
    if dns.dnssec_validate(mx_rr[0..], rrsig[0..], dnskey[0..], 1438207199u32, scratch[0..]) != dns.NotYetValid { os.exit(4i32) }
    var flipped: [95]u8 = rrsig
    flipped[40] = flipped[40] ^ 1u8
    if dns.dnssec_validate(mx_rr[0..], flipped[0..], dnskey[0..], 1439000000u32, scratch[0..]) != dns.BadSignature { os.exit(4i32) }
    var tagged: [95]u8 = rrsig
    tagged[17] = tagged[17] ^ 1u8
    if dns.dnssec_validate(mx_rr[0..], tagged[0..], dnskey[0..], 1439000000u32, scratch[0..]) != dns.Invalid { os.exit(4i32) }
    var altered: [43]u8 = mx_rr
    altered[23] = 11u8
    if dns.dnssec_validate(altered[0..], rrsig[0..], dnskey[0..], 1439000000u32, scratch[0..]) != dns.BadSignature { os.exit(4i32) }
    if dns.dnssec_validate(mx_rr[0..], rrsig[0..], dnskey[0..], 1439000000u32, scratch[..100usize]) != dns.TooSmall { os.exit(4i32) }

    // 5: the DS digest against Python's hashlib.
    let (digest, digest_error) = dns.ds_digest(example_com[0..], dnskey[0..], 2u8)
    if digest_error != ok || !same(digest[0..], ds_want[0..]) { os.exit(5i32) }
    let (_, sha1_error) = dns.ds_digest(example_com[0..], dnskey[0..], 1u8)
    if sha1_error != dns.Unsupported { os.exit(5i32) }
    // A DS rdata for the key.
    var ds_rdata: [36]u8 = zero
    ds_rdata[0] = 14u8
    ds_rdata[1] = 29u8
    ds_rdata[2] = 15u8
    ds_rdata[3] = 2u8
    mem.copy[u8](ds_rdata[4usize..], ds_want[0..])
    let (d, d_error) = dns.rdata_ds(ds_rdata[0..])
    if d_error != ok || d.key_tag != 3613u16 || d.algorithm != 15u8 || d.digest_type != 2u8 || d.digest.len != 32usize { os.exit(5i32) }
    // chain_validate: the DS selects the SEP DNSKEY, and the DNSKEY RRset validates with the RRSIG over it (Python-signed with the RFC 8080 private key).
    if dns.chain_validate(ds_rdata[0..], dnskey_rr[0..], rrsig_key[0..], 1439000000u32, scratch[0..]) != ok { os.exit(5i32) }
    if dns.chain_validate(ds_rdata[0..], dnskey_rr[0..], rrsig[0..], 1439000000u32, scratch[0..]) != dns.Invalid { os.exit(5i32) }
    if dns.chain_validate(ds_rdata[0..], dnskey_rr[0..], rrsig_key[0..], 1440021601u32, scratch[0..]) != dns.Expired { os.exit(5i32) }
    ds_rdata[5] = 0u8
    if dns.chain_validate(ds_rdata[0..], dnskey_rr[0..], rrsig_key[0..], 1439000000u32, scratch[0..]) != dns.Invalid { os.exit(5i32) }

    // 6: DoH request bytes and the response splitter; the DoT frame.
    let (get_len, get_error) = dns.query_doh(buf[0..], "dns.example", "/dns-query", query_want[0..], true)
    if get_error != ok || !same(buf[..get_len], "GET /dns-query?dns=EjQBAAABAAAAAAABB2V4YW1wbGUDY29tAAABAAEAACkQAAAAgAAAAA HTTP/1.1\r\nHost: dns.example\r\nAccept: application/dns-message\r\n\r\n") { os.exit(6i32) }
    let (post_len, post_error) = dns.query_doh(buf[0..], "dns.example", "/dns-query", query_want[0..], false)
    if post_error != ok || post_len != 179 || !same(buf[..post_len - query_want.len], "POST /dns-query HTTP/1.1\r\nHost: dns.example\r\nAccept: application/dns-message\r\nContent-Type: application/dns-message\r\nContent-Length: 40\r\n\r\n") || !same(buf[post_len - query_want.len..post_len], query_want[0..]) { os.exit(6i32) }
    let (_, doh_small) = dns.query_doh(buf[..50usize], "dns.example", "/dns-query", query_want[0..], true)
    if doh_small != dns.TooSmall { os.exit(6i32) }
    let (body, body_error) = dns.doh_response_body("HTTP/1.1 200 OK\r\nContent-Type: application/dns-message\r\nContent-Length: 4\r\n\r\nabcdEXTRA")
    if body_error != ok || !same(body, "abcd") { os.exit(6i32) }
    let (body2, body2_error) = dns.doh_response_body("HTTP/1.1 200 OK\r\n\r\nxyz")
    if body2_error != ok || !same(body2, "xyz") { os.exit(6i32) }
    let (_, not_found) = dns.doh_response_body("HTTP/1.1 404 Not Found\r\n\r\n")
    if not_found != dns.Invalid { os.exit(6i32) }
    let (_, truncated) = dns.doh_response_body("HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\nabcd")
    if truncated != dns.TooSmall { os.exit(6i32) }
    let (_, no_blank) = dns.doh_response_body("HTTP/1.1 200 OK\r\nContent-Length: 9\r\n")
    if no_blank != dns.Malformed { os.exit(6i32) }
    let (frame_len, frame_error) = dns.query_dot_frame(buf[0..], query_want[0..])
    if frame_error != ok || frame_len != 40usize + 2usize || buf[0] != 0u8 || buf[1] != 40u8 || !same(buf[2usize..frame_len], query_want[0..]) { os.exit(6i32) }

    // 7: algorithm 13 (ECDSA P-256) with a signature whose r has the top bit set.
    if dns.dnssec_validate(mx_rr[0..], rrsig13[0..], dnskey13[0..], 1439000000u32, scratch[0..]) != ok { os.exit(7i32) }
    var flipped13: [95]u8 = rrsig13
    flipped13[60] = flipped13[60] ^ 1u8
    if dns.dnssec_validate(mx_rr[0..], flipped13[0..], dnskey13[0..], 1439000000u32, scratch[0..]) != dns.BadSignature { os.exit(7i32) }
    var rsa: [95]u8 = rrsig
    rsa[2] = 8u8
    var rsa_key: [36]u8 = dnskey
    rsa_key[3] = 8u8
    rsa[16] = u8(dns.key_tag(rsa_key[0..]) >> 8u32)
    rsa[17] = u8(dns.key_tag(rsa_key[0..]) & 255u16)
    if dns.dnssec_validate(mx_rr[0..], rsa[0..], rsa_key[0..], 1439000000u32, scratch[0..]) != dns.Unsupported { os.exit(7i32) }

    try io.print("net dns ok\n")
    ret ok
}
