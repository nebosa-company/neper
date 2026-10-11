// `e.net.snmp`: requests built by the library equal an independent BER encoder's bytes (a v1 Get, a v2c
// GetNext with a large request id and a multi-byte arc, a Set of text and of a negative integer); a response with
// text, TimeTicks above 2^31, a negative integer, Counter32, IpAddress, an OID, NULL and an exception decodes
// to its values; a 200-byte value (long-form length), an error status, nine bindings, a truncation and a bad
// version are handled. Written by scripts/gen_snmp_test.py. Every check has its own exit code.
use e.os
use e.mem
use e.net.snmp as snmp

fn same(a: []const u8, b: []const u8, n: usize) -> bool {
    var i = 0usize
    while i < n {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let want_get: [40]u8 = [40]u8{ 48, 38, 2, 1, 0, 4, 6, 112, 117, 98, 108, 105, 99, 160, 25, 2, 1, 1, 2, 1, 0, 2, 1, 0, 48, 14, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 5, 0 }
    let want_next: [47]u8 = [47]u8{ 48, 45, 2, 1, 1, 4, 7, 112, 114, 105, 118, 97, 116, 101, 161, 31, 2, 4, 18, 52, 86, 120, 2, 1, 0, 2, 1, 0, 48, 17, 48, 15, 6, 11, 43, 6, 1, 2, 1, 2, 2, 1, 2, 135, 104, 5, 0 }
    let want_set_text: [47]u8 = [47]u8{ 48, 45, 2, 1, 1, 4, 5, 119, 114, 105, 116, 101, 163, 33, 2, 1, 77, 2, 1, 0, 2, 1, 0, 48, 22, 48, 20, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 4, 8, 114, 111, 117, 116, 101, 114, 45, 55 }
    let want_set_neg: [41]u8 = [41]u8{ 48, 39, 2, 1, 0, 4, 5, 119, 114, 105, 116, 101, 163, 27, 2, 2, 1, 44, 2, 1, 0, 2, 1, 0, 48, 15, 48, 13, 6, 7, 43, 6, 1, 4, 1, 99, 1, 2, 2, 255, 127 }
    let response: [186]u8 = [186]u8{ 48, 129, 183, 2, 1, 1, 4, 6, 112, 117, 98, 108, 105, 99, 162, 129, 169, 2, 4, 18, 52, 86, 120, 2, 1, 0, 2, 1, 0, 48, 129, 154, 48, 28, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 4, 16, 78, 101, 112, 101, 114, 32, 116, 101, 115, 116, 32, 97, 103, 101, 110, 116, 48, 17, 6, 8, 43, 6, 1, 2, 1, 1, 3, 0, 67, 5, 0, 238, 107, 40, 0, 48, 13, 6, 8, 43, 6, 1, 2, 1, 2, 1, 0, 2, 1, 251, 48, 17, 6, 10, 43, 6, 1, 2, 1, 2, 2, 1, 10, 1, 65, 3, 1, 226, 64, 48, 17, 6, 9, 43, 6, 1, 2, 1, 4, 20, 1, 1, 64, 4, 10, 0, 0, 1, 48, 22, 6, 8, 43, 6, 1, 2, 1, 1, 2, 0, 6, 10, 43, 6, 1, 4, 1, 191, 8, 3, 2, 10, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 4, 0, 5, 0, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 9, 9, 129, 0 }
    let long: [245]u8 = [245]u8{ 48, 129, 242, 2, 1, 0, 4, 6, 112, 117, 98, 108, 105, 99, 162, 129, 228, 2, 1, 5, 2, 1, 0, 2, 1, 0, 48, 129, 216, 48, 129, 213, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 4, 129, 200, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82 }
    let failure: [40]u8 = [40]u8{ 48, 38, 2, 1, 1, 4, 6, 112, 117, 98, 108, 105, 99, 162, 25, 2, 1, 9, 2, 1, 2, 2, 1, 1, 48, 14, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 5, 0 }
    let many: [154]u8 = [154]u8{ 48, 129, 151, 2, 1, 1, 4, 6, 112, 117, 98, 108, 105, 99, 162, 129, 137, 2, 1, 9, 2, 1, 0, 2, 1, 0, 48, 126, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 5, 0, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 5, 0, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 5, 0, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 5, 0, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 5, 0, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 5, 0, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 5, 0, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 5, 0, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 5, 0 }
    let bad_version: [40]u8 = [40]u8{ 48, 38, 2, 1, 3, 4, 6, 112, 117, 98, 108, 105, 99, 160, 25, 2, 1, 1, 2, 1, 0, 2, 1, 0, 48, 14, 48, 12, 6, 8, 43, 6, 1, 2, 1, 1, 1, 0, 5, 0 }
    let sys_descr = [9]u32{ 1u32, 3u32, 6u32, 1u32, 2u32, 1u32, 1u32, 1u32, 0u32 }
    let if_descr = [11]u32{ 1u32, 3u32, 6u32, 1u32, 2u32, 1u32, 2u32, 2u32, 1u32, 2u32, 1000u32 }
    let private_arcs = [8]u32{ 1u32, 3u32, 6u32, 1u32, 4u32, 1u32, 99u32, 1u32 }
    var buf: [512]u8 = zero
    let (n1, e1) = snmp.build_request(buf[0..], snmp.V1, "public", snmp.GET, 1i64, sys_descr[0..], false, "", 0i64)
    if e1 != ok || n1 != 40usize || !same(buf[0..], want_get[0..], n1) { os.exit(1) }
    let (n2, e2) = snmp.build_request(buf[0..], snmp.V2C, "private", snmp.GET_NEXT, 305419896i64, if_descr[0..], false, "", 0i64)
    if e2 != ok || n2 != 47usize || !same(buf[0..], want_next[0..], n2) { os.exit(2) }
    let (n3, e3) = snmp.build_request(buf[0..], snmp.V2C, "write", snmp.SET, 77i64, sys_descr[0..], true, "router-7", 0i64)
    if e3 != ok || n3 != 47usize || !same(buf[0..], want_set_text[0..], n3) { os.exit(3) }
    let (n4, e4) = snmp.build_request(buf[0..], snmp.V1, "write", snmp.SET, 300i64, private_arcs[0..], false, "", 0i64 - 129i64)
    if e4 != ok || n4 != 41usize || !same(buf[0..], want_set_neg[0..], n4) { os.exit(4) }
    var tiny: [8]u8 = zero
    let (n5, e5) = snmp.build_request(tiny[0..], snmp.V1, "public", snmp.GET, 1i64, sys_descr[0..], false, "", 0i64)
    if e5 != snmp.TooSmall { os.exit(5) }
    let (m, me) = snmp.decode(response[0..])
    if me != ok || m.version != snmp.V2C || m.pdu != snmp.RESPONSE || m.request_id != 305419896i64 || m.count != 8usize { os.exit(6) }
    if m.community_len != 6usize || m.community[0] != 112u8 || m.community[5] != 99u8 { os.exit(7) }
    if m.error_status != 0i64 || m.error_index != 0i64 { os.exit(8) }
    if m.oid_len[0] != 9usize || m.oid_arcs[0] != 1u32 || m.oid_arcs[1] != 3u32 || m.oid_arcs[8] != 0u32 { os.exit(9) }
    if m.kind[0] != snmp.T_OCTETS || m.bytes_len[0] != 16usize || m.bytes[m.bytes_at[0]] != 78u8 { os.exit(10) }
    if m.kind[1] != snmp.T_TIMETICKS || m.number[1] != 4000000000i64 { os.exit(11) }
    if m.kind[2] != snmp.T_INTEGER || m.number[2] != 0i64 - 5i64 { os.exit(12) }
    if m.kind[3] != snmp.T_COUNTER32 || m.number[3] != 123456i64 || m.oid_len[3] != 11usize || m.oid_arcs[3 * 16 + 9] != 10u32 { os.exit(13) }
    if m.kind[4] != snmp.T_IPADDRESS || m.bytes_len[4] != 4usize || m.bytes[m.bytes_at[4]] != 10u8 || m.bytes[m.bytes_at[4] + 3usize] != 1u8 { os.exit(14) }
    if m.kind[5] != snmp.T_OID || m.bytes_len[5] != 10usize { os.exit(15) }
    if m.kind[6] != snmp.T_NULL { os.exit(16) }
    if m.kind[7] != snmp.T_NO_SUCH_INSTANCE { os.exit(17) }
    let (g, ge) = snmp.decode(want_get[0..])
    if ge != ok || g.pdu != snmp.GET || g.version != snmp.V1 || g.count != 1usize || g.kind[0] != snmp.T_NULL { os.exit(18) }
    let (s, se) = snmp.decode(want_set_neg[0..])
    if se != ok || s.pdu != snmp.SET || s.number[0] != 0i64 - 129i64 || s.oid_arcs[6] != 99u32 { os.exit(19) }
    let (lg, lge) = snmp.decode(long[0..])
    if lge != ok || lg.bytes_len[0] != 200usize || lg.bytes[199] != 82u8 { os.exit(20) }
    let (f, fe) = snmp.decode(failure[0..])
    if fe != ok || f.error_status != 2i64 || f.error_index != 1i64 { os.exit(21) }
    let (tm, tme) = snmp.decode(many[0..])
    if tme != snmp.TooMany { os.exit(22) }
    let (bv, bve) = snmp.decode(bad_version[0..])
    if bve != snmp.Malformed { os.exit(23) }
    let (tr, tre) = snmp.decode(response[0..40])
    if tre != snmp.Malformed { os.exit(24) }
    ret ok
}
