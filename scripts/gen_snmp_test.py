#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/net_snmp/src/main.e (L137): e.net.snmp against messages built here by an
independent BER encoder (X.690 definite lengths, shortest integers, base-128 arcs)."""
from pathlib import Path


def length(n):
    if n < 128:
        return bytes([n])
    if n < 256:
        return bytes([0x81, n])
    return bytes([0x82, n >> 8, n & 255])


def tlv(tag, body):
    return bytes([tag]) + length(len(body)) + body


def integer(value, tag=2):
    n = 1
    while True:
        try:
            return tlv(tag, value.to_bytes(n, "big", signed=True))
        except OverflowError:
            n += 1


def unsigned(value, tag):
    body = value.to_bytes(max(1, (value.bit_length() + 7) // 8), "big")
    if body[0] & 0x80:
        body = b"\0" + body
    return tlv(tag, body)


def oid(arcs):
    body = bytes([arcs[0] * 40 + arcs[1]])
    for arc in arcs[2:]:
        chunk = [arc & 127]
        arc >>= 7
        while arc:
            chunk.append((arc & 127) | 128)
            arc >>= 7
        body += bytes(reversed(chunk))
    return tlv(6, body)


def octets(data, tag=4):
    return tlv(tag, data)


def message(version, community, pdu_tag, request_id, bindings, status=0, index=0):
    varbinds = b"".join(tlv(48, oid(o) + v) for o, v in bindings)
    pdu = integer(request_id) + integer(status) + integer(index) + tlv(48, varbinds)
    return tlv(48, integer(version) + octets(community.encode()) + tlv(pdu_tag, pdu))


SYS_DESCR = [1, 3, 6, 1, 2, 1, 1, 1, 0]
IF_DESCR = [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1000]
NULL = bytes([5, 0])

GET = message(0, "public", 0xA0, 1, [(SYS_DESCR, NULL)])
GETNEXT = message(1, "private", 0xA1, 305419896, [(IF_DESCR, NULL)])
SET_TEXT = message(1, "write", 0xA3, 77, [(SYS_DESCR, octets(b"router-7"))])
SET_NEG = message(0, "write", 0xA3, 300, [([1, 3, 6, 1, 4, 1, 99, 1], integer(-129))])
LONG_TEXT = bytes((65 + i % 26) for i in range(200))
RESPONSE = message(1, "public", 0xA2, 305419896, [
    (SYS_DESCR, octets(b"Neper test agent")),
    ([1, 3, 6, 1, 2, 1, 1, 3, 0], unsigned(4000000000, 0x43)),
    ([1, 3, 6, 1, 2, 1, 2, 1, 0], integer(-5)),
    ([1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 1], unsigned(123456, 0x41)),
    ([1, 3, 6, 1, 2, 1, 4, 20, 1, 1], octets(bytes([10, 0, 0, 1]), 0x40)),
    ([1, 3, 6, 1, 2, 1, 1, 2, 0], oid([1, 3, 6, 1, 4, 1, 8072, 3, 2, 10])),
    ([1, 3, 6, 1, 2, 1, 1, 4, 0], NULL),
    ([1, 3, 6, 1, 2, 1, 1, 9, 9], bytes([0x81, 0])),
])
LONG = message(0, "public", 0xA2, 5, [(SYS_DESCR, octets(LONG_TEXT))])
ERROR = message(1, "public", 0xA2, 9, [(SYS_DESCR, NULL)], status=2, index=1)
TOO_MANY = message(1, "public", 0xA2, 9, [(SYS_DESCR, NULL)] * 9)
BAD_VERSION = message(3, "public", 0xA0, 1, [(SYS_DESCR, NULL)])


def array(name, data):
    return "    let %s: [%d]u8 = [%d]u8{ %s }\n" % (name, len(data), len(data), ", ".join(str(b) for b in data))


def arcs_literal(arcs):
    return "[%d]u32{ %s }" % (len(arcs), ", ".join("%du32" % a for a in arcs))


def main():
    out = ["// `e.net.snmp`: requests built by the library equal an independent BER encoder's bytes (a v1 Get, a v2c\n",
           "// GetNext with a large request id and a multi-byte arc, a Set of text and of a negative integer); a response with\n",
           "// text, TimeTicks above 2^31, a negative integer, Counter32, IpAddress, an OID, NULL and an exception decodes\n",
           "// to its values; a 200-byte value (long-form length), an error status, nine bindings, a truncation and a bad\n",
           "// version are handled. Written by scripts/gen_snmp_test.py. Every check has its own exit code.\n",
           "use e.os\nuse e.mem\nuse e.net.snmp as snmp\n\n",
           "fn same(a: []const u8, b: []const u8, n: usize) -> bool {\n",
           "    var i = 0usize\n    while i < n {\n        if a[i] != b[i] { ret false }\n        i += 1usize\n    }\n    ret true\n}\n\n",
           "fn main(a: *mem.Arena, args: []str) -> err {\n"]
    for name, data in (("want_get", GET), ("want_next", GETNEXT), ("want_set_text", SET_TEXT), ("want_set_neg", SET_NEG),
                       ("response", RESPONSE), ("long", LONG), ("failure", ERROR), ("many", TOO_MANY), ("bad_version", BAD_VERSION)):
        out.append(array(name, data))
    out.append("    let sys_descr = " + arcs_literal(SYS_DESCR) + "\n")
    out.append("    let if_descr = " + arcs_literal(IF_DESCR) + "\n")
    out.append("    let private_arcs = " + arcs_literal([1, 3, 6, 1, 4, 1, 99, 1]) + "\n")
    out.append("    var buf: [512]u8 = zero\n")
    checks = []

    def check(cond):
        checks.append(cond)
        out.append("    if %s { os.exit(%d) }\n" % (cond, len(checks)))

    out.append("    let (n1, e1) = snmp.build_request(buf[0..], snmp.V1, \"public\", snmp.GET, 1i64, sys_descr[0..], false, \"\", 0i64)\n")
    check("e1 != ok || n1 != %dusize || !same(buf[0..], want_get[0..], n1)" % len(GET))
    out.append("    let (n2, e2) = snmp.build_request(buf[0..], snmp.V2C, \"private\", snmp.GET_NEXT, 305419896i64, if_descr[0..], false, \"\", 0i64)\n")
    check("e2 != ok || n2 != %dusize || !same(buf[0..], want_next[0..], n2)" % len(GETNEXT))
    out.append("    let (n3, e3) = snmp.build_request(buf[0..], snmp.V2C, \"write\", snmp.SET, 77i64, sys_descr[0..], true, \"router-7\", 0i64)\n")
    check("e3 != ok || n3 != %dusize || !same(buf[0..], want_set_text[0..], n3)" % len(SET_TEXT))
    out.append("    let (n4, e4) = snmp.build_request(buf[0..], snmp.V1, \"write\", snmp.SET, 300i64, private_arcs[0..], false, \"\", 0i64 - 129i64)\n")
    check("e4 != ok || n4 != %dusize || !same(buf[0..], want_set_neg[0..], n4)" % len(SET_NEG))
    out.append("    var tiny: [8]u8 = zero\n    let (n5, e5) = snmp.build_request(tiny[0..], snmp.V1, \"public\", snmp.GET, 1i64, sys_descr[0..], false, \"\", 0i64)\n")
    check("e5 != snmp.TooSmall")
    out.append("    let (m, me) = snmp.decode(response[0..])\n")
    check("me != ok || m.version != snmp.V2C || m.pdu != snmp.RESPONSE || m.request_id != 305419896i64 || m.count != 8usize")
    check("m.community_len != 6usize || m.community[0] != 112u8 || m.community[5] != 99u8")
    check("m.error_status != 0i64 || m.error_index != 0i64")
    check("m.oid_len[0] != 9usize || m.oid_arcs[0] != 1u32 || m.oid_arcs[1] != 3u32 || m.oid_arcs[8] != 0u32")
    check("m.kind[0] != snmp.T_OCTETS || m.bytes_len[0] != 16usize || m.bytes[m.bytes_at[0]] != 78u8")
    check("m.kind[1] != snmp.T_TIMETICKS || m.number[1] != 4000000000i64")
    check("m.kind[2] != snmp.T_INTEGER || m.number[2] != 0i64 - 5i64")
    check("m.kind[3] != snmp.T_COUNTER32 || m.number[3] != 123456i64 || m.oid_len[3] != 11usize || m.oid_arcs[3 * 16 + 9] != 10u32")
    check("m.kind[4] != snmp.T_IPADDRESS || m.bytes_len[4] != 4usize || m.bytes[m.bytes_at[4]] != 10u8 || m.bytes[m.bytes_at[4] + 3usize] != 1u8")
    check("m.kind[5] != snmp.T_OID || m.bytes_len[5] != 10usize")
    check("m.kind[6] != snmp.T_NULL")
    check("m.kind[7] != snmp.T_NO_SUCH_INSTANCE")
    out.append("    let (g, ge) = snmp.decode(want_get[0..])\n")
    check("ge != ok || g.pdu != snmp.GET || g.version != snmp.V1 || g.count != 1usize || g.kind[0] != snmp.T_NULL")
    out.append("    let (s, se) = snmp.decode(want_set_neg[0..])\n")
    check("se != ok || s.pdu != snmp.SET || s.number[0] != 0i64 - 129i64 || s.oid_arcs[6] != 99u32")
    out.append("    let (lg, lge) = snmp.decode(long[0..])\n")
    check("lge != ok || lg.bytes_len[0] != 200usize || lg.bytes[199] != %du8" % LONG_TEXT[199])
    out.append("    let (f, fe) = snmp.decode(failure[0..])\n")
    check("fe != ok || f.error_status != 2i64 || f.error_index != 1i64")
    out.append("    let (tm, tme) = snmp.decode(many[0..])\n")
    check("tme != snmp.TooMany")
    out.append("    let (bv, bve) = snmp.decode(bad_version[0..])\n")
    check("bve != snmp.Malformed")
    out.append("    let (tr, tre) = snmp.decode(response[0..40])\n")
    check("tre != snmp.Malformed")
    out.append("    ret ok\n}\n")
    target = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/net_snmp/src/main.e"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("".join(out), encoding="utf-8", newline="\n")
    print("wrote", target, "checks", len(checks))


main()
