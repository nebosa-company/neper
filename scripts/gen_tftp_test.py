"""Generate tests/selfhost/fixtures/link/net_tftp/src/main.e (L152, D2802).

Codec reference: tftpy's packet classes (`TftpPacketRRQ/WRQ/DAT/ACK/ERR/OACK`): every
encoding the library produces is embedded as hex and must come out of `e.net.tftp`
byte for byte, and decode back to its fields. The transfer logic is exercised over real
loopback UDP sockets against a scripted RFC 1350/2347/2348 server thread written in the
fixture: a short file, an exact multiple of the block size (empty final block), a
negotiated block size (OACK), an upload, a remote error and a buffer too small.

    PYTHONPATH=<tftpy install dir> python scripts/gen_tftp_test.py
"""
import random
import sys
from pathlib import Path

from tftpy.TftpPacketTypes import (TftpPacketACK, TftpPacketDAT, TftpPacketERR, TftpPacketOACK,
                                   TftpPacketRRQ, TftpPacketWRQ)

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(154)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'net_tftp' / 'src' / 'main.e'


def hx(b):
    return b.hex() or '-'


lines = []
names = ['boot.img', 'a', 'dir/sub/file.bin', 'x' * 60]
for name in names:
    for mode in ('octet', 'netascii', 'mail'):
        for opts in ({}, {'blksize': '1024'}, {'blksize': '8', 'tsize': '0'}, {'tsize': '12345', 'timeout': '3'}):
            for cls, kind in ((TftpPacketRRQ, 'Q'), (TftpPacketWRQ, 'W')):
                p = cls()
                p.filename = name
                p.mode = mode.encode() if False else mode
                p.options = opts
                try:
                    data = p.encode().buffer
                except AssertionError:
                    continue
                o = ';'.join('%s=%s' % kv for kv in opts.items()) or '-'
                lines.append('%s %s %s %s => %s' % (kind, name, mode, o, hx(data)))
for block in (0, 1, 7, 255, 256, 65535):
    for n in (0, 1, 511, 512):
        p = TftpPacketDAT()
        p.blocknumber = block
        p.data = bytes(random.getrandbits(8) for _ in range(n))
        lines.append('D %d %s => %s' % (block, hx(p.data), hx(p.encode().buffer)))
    a = TftpPacketACK()
    a.blocknumber = block
    lines.append('A %d => %s' % (block, hx(a.encode().buffer)))
for code in sorted(TftpPacketERR().errmsgs):
    e = TftpPacketERR()
    e.errorcode = code
    msg = e.errmsgs[code]
    msg = msg if isinstance(msg, bytes) else msg.encode()
    lines.append('E %d %s => %s' % (code, msg.hex() or '-', hx(e.encode().buffer)))
# a message of the caller's own, in the RFC 1350 layout the library also decodes
lines.append('E 0 %s => %s' % (b'disk exploded'.hex(), hx(b'\x00\x05\x00\x00disk exploded\x00')))
for opts in ({'blksize': '512'}, {'blksize': '1428', 'tsize': '99999'}, {'timeout': '1'}, {}):
    o = TftpPacketOACK()
    o.options = opts
    lines.append('O %s => %s' % (';'.join('%s=%s' % kv for kv in opts.items()) or '-', hx(o.encode().buffer)))
# refusals decode must reject: truncated, bad opcodes, no terminators, odd option runs
bad = [b'', b'\x00', b'\x00\x01', b'\x00\x01a\x00', b'\x00\x01a\x00octet', b'\x00\x01\x00octet\x00', b'\x00\x03\x00', b'\x00\x04\x00', b'\x00\x04\x00\x01\x00',
       b'\x00\x05\x00\x01', b'\x00\x05\x00\x01msg', b'\x00\x07\x00\x00', b'\x00\x00', b'\x00\x06blksize', b'\x00\x06blksize\x00', b'\x00\x01a\x00octet\x00blksize\x00',
       b'\xff\xff\x00\x00']
for b in bad:
    lines.append('X %s' % hx(b))

vec, fnames = fc.vector_functions('v', lines)

CHECK = '''
fn hexval(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(s: str, out: []u8) -> usize {
    if s.len == 1usize && s[0usize] == 45u8 { ret 0usize }
    var i = 0usize
    while i + 1usize < s.len {
        out[i / 2usize] = hexval(s[i]) * 16u8 + hexval(s[i + 1usize])
        i += 2usize
    }
    ret s.len / 2usize
}

fn same_bytes(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// `a=1;b=2` into parallel name/value slices (slices of `line`); returns the count.
fn split_options(spec: str, names: []str, values: []str) -> usize {
    if spec.len == 1usize && spec[0usize] == 45u8 { ret 0usize }
    var count = 0usize
    var start = 0usize
    var i = 0usize
    while i <= spec.len {
        if i == spec.len || spec[i] == 59u8 {
            let item = spec[start..i]
            var eq = 0usize
            while eq < item.len && item[eq] != 61u8 { eq += 1usize }
            names[count] = item[0usize..eq]
            values[count] = item[eq + 1usize..item.len]
            count += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret count
}

fn check_line(line: str) -> u8 {
    var want: [1500]u8 = zero
    var got: [1500]u8 = zero
    var names: [4]str = zero
    var values: [4]str = zero
    let (kind, p0) = tok(line, 0usize)
    let k = kind[0usize]
    if k == 88u8 {
        let (h, p1) = tok(line, p0)
        let n = unhex(h, want[0usize..1500usize])
        let (p, e) = tftp.decode(want[0usize..n])
        if e == ok { ret 1u8 }
        ret 0u8
    }
    if k == 81u8 || k == 87u8 {
        let (name, p1) = tok(line, p0)
        let (mode, p2) = tok(line, p1)
        let (spec, p3) = tok(line, p2)
        let (arrow, p4) = tok(line, p3)
        let (h, p5) = tok(line, p4)
        let wn = unhex(h, want[0usize..1500usize])
        let count = split_options(spec, names[0usize..4usize], values[0usize..4usize])
        let (n, e) = tftp.encode_request(k == 87u8, name, mode, names[0usize..count], values[0usize..count], got[0usize..1500usize])
        if e != ok || !same_bytes(got[0usize..n], want[0usize..wn]) { ret 2u8 }
        let (p, de) = tftp.decode(want[0usize..wn])
        if de != ok || !text_is(p.text, name) || !text_is(p.mode, mode) { ret 3u8 }
        var at = 0usize
        var seen = 0usize
        while at < p.options.len {
            let (on, ov, next, good) = tftp.option_next(p.options, at)
            if !good || !text_is(on, names[seen]) || !text_is(ov, values[seen]) { ret 4u8 }
            at = next
            seen += 1usize
        }
        if seen != count { ret 5u8 }
        ret 0u8
    }
    if k == 68u8 {
        let (block, p1) = tok(line, p0)
        let (payload_hex, p2) = tok(line, p1)
        let (arrow, p3) = tok(line, p2)
        let (h, p4) = tok(line, p3)
        var payload: [600]u8 = zero
        let pn = unhex(payload_hex, payload[0usize..600usize])
        let wn = unhex(h, want[0usize..1500usize])
        let (n, e) = tftp.encode_data(u16(dec(block)), payload[0usize..pn], got[0usize..1500usize])
        if e != ok || !same_bytes(got[0usize..n], want[0usize..wn]) { ret 11u8 }
        let (p, de) = tftp.decode(want[0usize..wn])
        if de != ok || i64(p.block) != dec(block) || !same_bytes(p.data, payload[0usize..pn]) { ret 12u8 }
        ret 0u8
    }
    if k == 65u8 {
        let (block, p1) = tok(line, p0)
        let (arrow, p2) = tok(line, p1)
        let (h, p3) = tok(line, p2)
        let wn = unhex(h, want[0usize..1500usize])
        let (n, e) = tftp.encode_ack(u16(dec(block)), got[0usize..1500usize])
        if e != ok || !same_bytes(got[0usize..n], want[0usize..wn]) { ret 21u8 }
        let (p, de) = tftp.decode(want[0usize..wn])
        if de != ok || i64(p.block) != dec(block) { ret 22u8 }
        ret 0u8
    }
    if k == 69u8 {
        let (code, p1) = tok(line, p0)
        let (msg_hex, p2) = tok(line, p1)
        let (arrow, p3) = tok(line, p2)
        let (h, p4) = tok(line, p3)
        var msg: [64]u8 = zero
        let mn = unhex(msg_hex, msg[0usize..64usize])
        let wn = unhex(h, want[0usize..1500usize])
        let (n, e) = tftp.encode_error(u16(dec(code)), msg[0usize..mn], got[0usize..1500usize])
        if e != ok || !same_bytes(got[0usize..n], want[0usize..wn]) { ret 31u8 }
        let (p, de) = tftp.decode(want[0usize..wn])
        if de != ok || i64(p.error_code) != dec(code) || !same_bytes(p.text, msg[0usize..mn]) { ret 32u8 }
        ret 0u8
    }
    // O options => hex
    let (spec, p1) = tok(line, p0)
    let (arrow, p2) = tok(line, p1)
    let (h, p3) = tok(line, p2)
    let wn = unhex(h, want[0usize..1500usize])
    let count = split_options(spec, names[0usize..4usize], values[0usize..4usize])
    let (n, e) = tftp.encode_oack(names[0usize..count], values[0usize..count], got[0usize..1500usize])
    if e != ok || !same_bytes(got[0usize..n], want[0usize..wn]) { ret 41u8 }
    let (p, de) = tftp.decode(want[0usize..wn])
    if de != ok || p.opcode != 6u16 { ret 42u8 }
    ret 0u8
}

// ---- a scripted server for the loopback transfers ----

type Server = struct { listener: net.Socket, scenario: u32, file: []const u8, uploaded: []u8, uploaded_len: usize, blksize_cap: u16, failed: u32 }

fn loopback_endpoint(port: u16) -> net.Endpoint {
    let (ip, ip_error) = net.parse_ip("127.0.0.1")
    ret net.Endpoint { address: ip, port: port }
}

// Scenarios: 0 plain read, 1 read with option negotiation, 2 write, 3 write with options, 4 error reply.
fn serve(s: *Server) {
    var request: [600]u8 = zero
    var packet: [1500]u8 = zero
    var reply: [1500]u8 = zero
    let (n, client, recv_error) = net.receive_from(s.listener, request[0usize..600usize])
    if recv_error != ok {
        s.failed = 1u32
        ret
    }
    let (rq, decode_error) = tftp.decode(request[0usize..n])
    if decode_error != ok {
        s.failed = 2u32
        ret
    }
    let (tid, tid_error) = net.udp_bind(loopback_endpoint(0u16))
    if tid_error != ok {
        s.failed = 3u32
        ret
    }
    var blksize = 512u16
    var oack_names: [2]str = zero
    var oack_values: [2]str = zero
    var oack_count = 0usize
    var size_text: [8]u8 = zero
    var total_text: [20]u8 = zero
    // options the client asked for: honour blksize up to the server's cap
    var at = 0usize
    while at < rq.options.len {
        let (on, ov, next, good) = tftp.option_next(rq.options, at)
        at = next
        if good && text_is(on, "blksize") {
            var v = 0u16
            let (parsed, number_ok) = tftp.parse_number(ov)
            if number_ok {
                v = u16(parsed)
                if v > s.blksize_cap { v = s.blksize_cap }
                blksize = v
                oack_names[oack_count] = "blksize"
                oack_values[oack_count] = tftp.number_text(u64(v), size_text[0usize..8usize])
                oack_count += 1usize
            }
        }
    }
    if s.scenario == 4u32 {
        let (en, ee) = tftp.encode_error(1u16, "File not found", reply[0usize..1500usize])
        let (_, _) = net.send_to(tid, client, reply[0usize..en])
        let closed = net.close(tid)
        ret
    }
    if rq.opcode == tftp.op_rrq() {
        if oack_count > 0usize {
            oack_names[oack_count] = "tsize"
            oack_values[oack_count] = tftp.number_text(u64(s.file.len), total_text[0usize..20usize])
            oack_count += 1usize
            let (on, oe) = tftp.encode_oack(oack_names[0usize..oack_count], oack_values[0usize..oack_count], reply[0usize..1500usize])
            let (_, _) = net.send_to(tid, client, reply[0usize..on])
            // wait for ACK 0
            let (an, afrom, ae) = net.receive_from(tid, packet[0usize..1500usize])
            if ae != ok { s.failed = 4u32 }
        }
        var block = 1u16
        var offset = 0usize
        var final_sent = false
        while !final_sent && s.failed == 0u32 {
            var take = s.file.len - offset
            if take > usize(blksize) { take = usize(blksize) }
            let (dn, de) = tftp.encode_data(block, s.file[offset..offset + take], reply[0usize..1500usize])
            let (_, _) = net.send_to(tid, client, reply[0usize..dn])
            let (an, afrom, ae) = net.receive_from(tid, packet[0usize..1500usize])
            if ae != ok {
                s.failed = 5u32
            } else {
                let (ack, ack_error) = tftp.decode(packet[0usize..an])
                if ack_error != ok || ack.opcode != tftp.op_ack() || ack.block != block { s.failed = 6u32 }
            }
            offset += take
            if take < usize(blksize) { final_sent = true }
            block += 1u16
        }
    } else {
        // WRQ: OACK or ACK 0, then DATA until a short block
        if oack_count > 0usize {
            let (on, oe) = tftp.encode_oack(oack_names[0usize..oack_count], oack_values[0usize..oack_count], reply[0usize..1500usize])
            let (_, _) = net.send_to(tid, client, reply[0usize..on])
        } else {
            let (an, ae) = tftp.encode_ack(0u16, reply[0usize..1500usize])
            let (_, _) = net.send_to(tid, client, reply[0usize..an])
        }
        var expected = 1u16
        var finished = false
        while !finished && s.failed == 0u32 {
            let (dn, dfrom, de) = net.receive_from(tid, packet[0usize..1500usize])
            if de != ok {
                s.failed = 7u32
            } else {
                let (d, d_error) = tftp.decode(packet[0usize..dn])
                if d_error != ok || d.opcode != tftp.op_data() || d.block != expected {
                    s.failed = 8u32
                } else {
                    var i = 0usize
                    while i < d.data.len {
                        s.uploaded[s.uploaded_len + i] = d.data[i]
                        i += 1usize
                    }
                    s.uploaded_len += d.data.len
                    let (an, ae) = tftp.encode_ack(expected, reply[0usize..1500usize])
                    let (_, _) = net.send_to(tid, client, reply[0usize..an])
                    expected += 1u16
                    if d.data.len < usize(blksize) { finished = true }
                }
            }
        }
    }
    let closed = net.close(tid)
}

type Result = struct { n: usize, failure: err, error_code: u16 }

fn download(server_port: u16, blksize: u16, out: []u8) -> Result {
    var r: Result = zero
    let (sock, bind_error) = net.udp_bind(loopback_endpoint(0u16))
    if bind_error != ok {
        r.failure = bind_error
        ret r
    }
    defer let _ = net.close(sock)
    var t: tftp.Transfer = zero
    var request: [128]u8 = zero
    var packet: [1500]u8 = zero
    var reply: [64]u8 = zero
    let (rn, start_error) = tftp.read_start(&t, "boot.img", "octet", blksize, out, request[0usize..128usize])
    if start_error != ok {
        r.failure = start_error
        ret r
    }
    var peer = loopback_endpoint(server_port)
    let (_, _) = net.send_to(sock, peer, request[0usize..rn])
    var first = true
    var guard = 0usize
    while guard < 1000usize {
        guard += 1usize
        let (n, from, recv_error) = net.receive_from(sock, packet[0usize..1500usize])
        if recv_error != ok {
            r.failure = recv_error
            break
        }
        if first {
            peer = from
            first = false
        }
        let (step, step_error) = tftp.read_step(&t, packet[0usize..n], reply[0usize..64usize])
        if step_error != ok {
            r.failure = step_error
            r.error_code = t.error_code
            if step_error == tftp.TooLong {
                let (en, ee) = tftp.encode_error(3u16, "Disk full", reply[0usize..64usize])
                let (_, _) = net.send_to(sock, peer, reply[0usize..en])
            }
            break
        }
        if step.reply_len > 0usize {
            let (_, _) = net.send_to(sock, peer, reply[0usize..step.reply_len])
        }
        if step.finished { break }
    }
    r.n = t.written
    ret r
}

fn upload(server_port: u16, blksize: u16, data: []const u8) -> Result {
    var r: Result = zero
    let (sock, bind_error) = net.udp_bind(loopback_endpoint(0u16))
    if bind_error != ok {
        r.failure = bind_error
        ret r
    }
    defer let _ = net.close(sock)
    var t: tftp.Transfer = zero
    var request: [128]u8 = zero
    var packet: [1500]u8 = zero
    var reply: [1500]u8 = zero
    let (rn, start_error) = tftp.write_start(&t, "up.bin", "octet", blksize, data, request[0usize..128usize])
    if start_error != ok {
        r.failure = start_error
        ret r
    }
    var peer = loopback_endpoint(server_port)
    let (_, _) = net.send_to(sock, peer, request[0usize..rn])
    var first = true
    var guard = 0usize
    while guard < 1000usize {
        guard += 1usize
        let (n, from, recv_error) = net.receive_from(sock, packet[0usize..1500usize])
        if recv_error != ok {
            r.failure = recv_error
            break
        }
        if first {
            peer = from
            first = false
        }
        let (step, step_error) = tftp.write_step(&t, packet[0usize..n], reply[0usize..1500usize])
        if step_error != ok {
            r.failure = step_error
            r.error_code = t.error_code
            break
        }
        if step.reply_len > 0usize {
            let (_, _) = net.send_to(sock, peer, reply[0usize..step.reply_len])
        }
        if step.finished { break }
    }
    r.n = t.written
    ret r
}

fn pattern(buf: []u8, n: usize) {
    var i = 0usize
    while i < n {
        buf[i] = u8((i * 7usize + i / 251usize) % 256usize)
        i += 1usize
    }
}

// Runs one scenario: starts the server thread, runs `client`, joins.
fn make_server(a: *mem.Arena, scenario: u32, file: []const u8, cap: u16) -> (*Server, err) {
    let (srv, alloc_error) = mem.alloc[Server](a, 1usize)
    if alloc_error != ok { ret (zero, alloc_error) }
    let (up, up_error) = mem.alloc[u8](a, 8192usize)
    if up_error != ok { ret (zero, up_error) }
    let (listener, listen_error) = net.udp_bind(loopback_endpoint(0u16))
    if listen_error != ok { ret (zero, listen_error) }
    var s: Server = zero
    s.listener = listener
    s.scenario = scenario
    s.file = file
    s.blksize_cap = cap
    s.uploaded = up
    srv[0usize] = s
    ret (&srv[0usize], ok)
}

'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    var file: [3000]u8 = zero
    pattern(file[0usize..3000usize], 3000usize)
    var out: [4096]u8 = zero
    // 1: plain RFC 1350 read: 1300 bytes = 2 full blocks and a 276-byte tail
    let (s1, e1) = make_server(a, 0u32, file[0usize..1300usize], 512u16)
    if e1 != ok { os.exit(101i32) }
    defer let _ = net.close(s1.listener)
    let (port1, port1_error) = os.socket_local_address(s1.listener)
    let (th1, spawn1) = thread.spawn[Server](serve, s1, 0usize)
    if spawn1 != ok { os.exit(102i32) }
    if port1_error != ok { os.exit(102i32) }
    let r1 = download(port1.port, 0u16, out[0usize..4096usize])
    let j1 = thread.join(th1)
    if r1.failure != ok || r1.n != 1300usize || s1.failed != 0u32 { os.exit(103i32) }
    var i = 0usize
    while i < 1300usize {
        if out[i] != file[i] { os.exit(104i32) }
        i += 1usize
    }
    // 2: an exact multiple of the block size ends with an empty block
    let (s2, e2) = make_server(a, 0u32, file[0usize..1024usize], 512u16)
    if e2 != ok { os.exit(105i32) }
    defer let _ = net.close(s2.listener)
    let (port2, port2_error) = os.socket_local_address(s2.listener)
    let (th2, spawn2) = thread.spawn[Server](serve, s2, 0usize)
    if spawn2 != ok { os.exit(106i32) }
    if port2_error != ok { os.exit(106i32) }
    let r2 = download(port2.port, 0u16, out[0usize..4096usize])
    let j2 = thread.join(th2)
    if r2.failure != ok || r2.n != 1024usize || s2.failed != 0u32 { os.exit(107i32) }
    // 3: negotiated block size (OACK): the server caps 1400 to 1024
    let (s3, e3) = make_server(a, 1u32, file[0usize..3000usize], 1024u16)
    if e3 != ok { os.exit(108i32) }
    defer let _ = net.close(s3.listener)
    let (port3, port3_error) = os.socket_local_address(s3.listener)
    let (th3, spawn3) = thread.spawn[Server](serve, s3, 0usize)
    if spawn3 != ok { os.exit(109i32) }
    if port3_error != ok { os.exit(109i32) }
    let r3 = download(port3.port, 1400u16, out[0usize..4096usize])
    let j3 = thread.join(th3)
    if r3.failure != ok || r3.n != 3000usize || s3.failed != 0u32 { os.exit(110i32) }
    i = 0usize
    while i < 3000usize {
        if out[i] != file[i] { os.exit(111i32) }
        i += 1usize
    }
    // 4: upload, plain
    let (s4, e4) = make_server(a, 2u32, file[0usize..0usize], 512u16)
    if e4 != ok { os.exit(112i32) }
    defer let _ = net.close(s4.listener)
    let (port4, port4_error) = os.socket_local_address(s4.listener)
    let (th4, spawn4) = thread.spawn[Server](serve, s4, 0usize)
    if spawn4 != ok { os.exit(113i32) }
    if port4_error != ok { os.exit(113i32) }
    let r4 = upload(port4.port, 0u16, file[0usize..1200usize])
    let j4 = thread.join(th4)
    if r4.failure != ok || s4.failed != 0u32 || s4.uploaded_len != 1200usize { os.exit(114i32) }
    i = 0usize
    while i < 1200usize {
        if s4.uploaded[i] != file[i] { os.exit(115i32) }
        i += 1usize
    }
    // 5: upload with a negotiated block size, an exact multiple of it (empty final block)
    let (s5, e5) = make_server(a, 3u32, file[0usize..0usize], 1024u16)
    if e5 != ok { os.exit(116i32) }
    defer let _ = net.close(s5.listener)
    let (port5, port5_error) = os.socket_local_address(s5.listener)
    let (th5, spawn5) = thread.spawn[Server](serve, s5, 0usize)
    if spawn5 != ok { os.exit(117i32) }
    if port5_error != ok { os.exit(117i32) }
    let r5 = upload(port5.port, 1024u16, file[0usize..2048usize])
    let j5 = thread.join(th5)
    if r5.failure != ok || s5.failed != 0u32 || s5.uploaded_len != 2048usize { os.exit(118i32) }
    // 6: the server answers the request with an ERROR packet
    let (s6, e6) = make_server(a, 4u32, file[0usize..0usize], 512u16)
    if e6 != ok { os.exit(119i32) }
    defer let _ = net.close(s6.listener)
    let (port6, port6_error) = os.socket_local_address(s6.listener)
    let (th6, spawn6) = thread.spawn[Server](serve, s6, 0usize)
    if spawn6 != ok { os.exit(120i32) }
    if port6_error != ok { os.exit(120i32) }
    let r6 = download(port6.port, 0u16, out[0usize..4096usize])
    let j6 = thread.join(th6)
    if r6.failure != tftp.Remote || r6.error_code != 1u16 { os.exit(121i32) }
    // 7: a destination too small is TooLong, not a truncated success
    let (s7, e7) = make_server(a, 0u32, file[0usize..1300usize], 512u16)
    if e7 != ok { os.exit(122i32) }
    defer let _ = net.close(s7.listener)
    let (port7, port7_error) = os.socket_local_address(s7.listener)
    let (th7, spawn7) = thread.spawn[Server](serve, s7, 0usize)
    if spawn7 != ok { os.exit(123i32) }
    if port7_error != ok { os.exit(123i32) }
    let r7 = download(port7.port, 0u16, out[0usize..600usize])
    // the client aborts with ERROR(3, "Disk full"), which ends the server's wait for an ACK
    let j7 = thread.join(th7)
    if r7.failure != tftp.TooLong || s7.failed != 6u32 { os.exit(124i32) }
    // bad block sizes are refused up front
    var t: tftp.Transfer = zero
    var req: [64]u8 = zero
    let (_, small) = tftp.read_start(&t, "x", "octet", 4u16, out[0usize..16usize], req[0usize..64usize])
    if small != tftp.Protocol { os.exit(125i32) }
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("net tftp ok")
    ret ok
}
'''

src = ('// e.net.tftp: every packet tftpy encodes comes out of the codec byte for byte and decodes back; damaged\n'
       '// packets are refused; the sans-IO client transfers run over real loopback UDP against a scripted server\n'
       '// thread (D2802). Q/W request, D data, A ack, E error, O oack, X must be refused. Generated by\n'
       '// scripts/gen_tftp_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.net\nuse e.thread\nuse e.net.tftp\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + fc.run_all(fnames, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
