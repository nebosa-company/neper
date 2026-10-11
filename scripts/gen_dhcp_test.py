#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/net_dhcp/src/main.e (L137): e.net.dhcp against packets built here with
struct by an independent encoder (the BOOTP layout of RFC 2131 and the options of RFC 2132)."""
import struct
from pathlib import Path

MAC = bytes([0x02, 0x00, 0x5E, 0x10, 0x20, 0x30])


def bootp(op, xid, flags, ciaddr, yiaddr, siaddr, giaddr, mac, options):
    head = struct.pack("!BBBBIHH4s4s4s4s16s", op, 1, 6, 0, xid, 0, flags, ciaddr, yiaddr, siaddr, giaddr, mac.ljust(16, b"\0"))
    body = head + bytes(192) + bytes([99, 130, 83, 99])
    for code, value in options:
        if code == 0:
            body += b"\0"
        else:
            body += bytes([code, len(value)]) + value
    body += b"\xff"
    return body.ljust(300, b"\0")


def ip(text):
    return bytes(int(p) for p in text.split("."))


ZERO = bytes(4)
DISCOVER = bootp(1, 0xCAFEF00D, 0x8000, ZERO, ZERO, ZERO, ZERO, MAC,
                 [(53, b"\x01"), (61, b"\x01" + MAC), (55, bytes([1, 3, 6, 51]))])
REQUEST = bootp(1, 0xCAFEF00D, 0x8000, ZERO, ZERO, ZERO, ZERO, MAC,
                [(53, b"\x03"), (61, b"\x01" + MAC), (50, ip("192.168.7.42")), (54, ip("192.168.7.1")), (55, bytes([1, 3, 6, 51]))])
OFFER = bootp(2, 0xCAFEF00D, 0x8000, ZERO, ip("192.168.7.42"), ip("192.168.7.1"), ZERO, MAC,
              [(53, b"\x02"), (54, ip("192.168.7.1")), (51, struct.pack("!I", 86400)), (1, ip("255.255.255.0")),
               (0, b""), (3, ip("192.168.7.1") + ip("192.168.7.2")), (6, ip("8.8.8.8") + ip("1.1.1.1")),
               (66, b"tftp.example"), (12, b"phone")])
ACK = bootp(2, 0xCAFEF00D, 0x0000, ZERO, ip("192.168.7.42"), ip("192.168.7.1"), ZERO, MAC,
            [(53, b"\x05"), (54, ip("192.168.7.1")), (51, struct.pack("!I", 3600)), (1, ip("255.255.0.0")), (3, ip("10.0.0.1"))])
NAK = bootp(2, 0xCAFEF00D, 0x0000, ZERO, ZERO, ZERO, ZERO, MAC, [(53, b"\x06"), (54, ip("192.168.7.1"))])
BAD_MAGIC = bytearray(OFFER)
BAD_MAGIC[236] = 0
# An option whose length runs past the end of a 250-byte message.
SHORT = OFFER[:240] + bytes([53, 9, 1, 2])


def array(name, data):
    return "    let %s: [%d]u8 = [%d]u8{ %s }\n" % (name, len(data), len(data), ", ".join(str(b) for b in data))


def main():
    out = ["// `e.net.dhcp`: a DISCOVER and a REQUEST built by the library are byte-for-byte the packets of an independent\n",
           "// struct encoder; an OFFER (with a pad, an unknown option and a host name), an ACK and a NAK decode to their\n",
           "// fields; bad magic, a short message and an option running past the end are refused. Written by\n",
           "// scripts/gen_dhcp_test.py. Every check has its own exit code.\n",
           "use e.os\nuse e.mem\nuse e.net.dhcp as dhcp\n\n",
           "fn same(a: []const u8, b: []const u8, n: usize) -> bool {\n",
           "    var i = 0usize\n    while i < n {\n        if a[i] != b[i] { ret false }\n        i += 1usize\n    }\n    ret true\n}\n\n",
           "fn main(a: *mem.Arena, args: []str) -> err {\n"]
    for name, data in (("want_discover", DISCOVER), ("want_request", REQUEST), ("offer", OFFER), ("ack", ACK), ("nak", NAK),
                       ("bad_magic", bytes(BAD_MAGIC)), ("short", SHORT)):
        out.append(array(name, data))
    out.append("    let mac: [6]u8 = [6]u8{ 2u8, 0u8, 94u8, 16u8, 32u8, 48u8 }\n")
    out.append("    var buf: [400]u8 = zero\n")
    checks = []

    def check(cond):
        checks.append(cond)
        out.append("    if %s { os.exit(%d) }\n" % (cond, len(checks)))

    out.append("    var m = dhcp.discover(mac, 3405705229u32)\n")
    out.append("    let (n1, e1) = dhcp.encode(&m, buf[0..])\n")
    check("e1 != ok || n1 != 300usize || !same(buf[0..], want_discover[0..], 300usize)")
    out.append("    var r = dhcp.request(mac, 3405705229u32, [4]u8{ 192u8, 168u8, 7u8, 42u8 }, [4]u8{ 192u8, 168u8, 7u8, 1u8 })\n")
    out.append("    let (n2, e2) = dhcp.encode(&r, buf[0..])\n")
    check("e2 != ok || n2 != 300usize || !same(buf[0..], want_request[0..], 300usize)")
    out.append("    let (o, oe) = dhcp.decode(offer[0..])\n")
    check("oe != ok")
    check("o.op != dhcp.OP_REPLY || o.message_type != dhcp.OFFER || o.xid != 3405705229u32")
    check("o.yiaddr[0] != 192u8 || o.yiaddr[1] != 168u8 || o.yiaddr[2] != 7u8 || o.yiaddr[3] != 42u8")
    check("!o.has_server_id || o.server_id[3] != 1u8 || o.siaddr[3] != 1u8")
    check("dhcp.lease_time(o) != 86400u32")
    check("!o.has_subnet || o.subnet_mask[0] != 255u8 || o.subnet_mask[3] != 0u8")
    check("!o.has_router || o.router[3] != 1u8")
    check("o.dns_count != 2usize || o.dns[0] != 8u8 || o.dns[4] != 1u8 || o.dns[7] != 1u8")
    check("o.hostname_len != 5usize || o.hostname[0] != 112u8 || o.hostname[4] != 101u8")
    check("o.flags != 32768u16 || o.chaddr[0] != 2u8 || o.chaddr[5] != 48u8")
    out.append("    let (k, ke) = dhcp.decode(ack[0..])\n")
    check("ke != ok || k.message_type != dhcp.ACK || dhcp.lease_time(k) != 3600u32 || k.router[0] != 10u8")
    check("k.subnet_mask[1] != 255u8 || k.subnet_mask[2] != 0u8")
    out.append("    let (x, xe) = dhcp.decode(nak[0..])\n")
    check("xe != ok || x.message_type != dhcp.NAK || x.has_lease || dhcp.lease_time(x) != 0u32")
    out.append("    let (bm, bme) = dhcp.decode(bad_magic[0..])\n")
    check("bme != dhcp.BadMagic")
    out.append("    let (sh, she) = dhcp.decode(short[0..])\n")
    check("she != dhcp.BadOption")
    out.append("    let (tr, tre) = dhcp.decode(offer[0..100])\n")
    check("tre != dhcp.Truncated")
    out.append("    var small: [100]u8 = zero\n    let (sm, sme) = dhcp.encode(&m, small[0..])\n")
    check("sme != dhcp.TooSmall")
    out.append("    ret ok\n}\n")
    target = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/net_dhcp/src/main.e"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("".join(out), encoding="utf-8", newline="\n")
    print("wrote", target, "checks", len(checks))


main()
