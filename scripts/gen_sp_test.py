"""Generate tests/selfhost/fixtures/link/net_sp/src/main.e (L156, D2805).

Reference: NNG 1.x through pynng 0.9. Socket pairs (SURVEYOR/RESPONDENT, REQ/REP,
PUSH/PULL, SUB/PUB, PAIR, BUS) talk through a recording TCP proxy; each direction's byte
stream is embedded with its description (protocol, messages with their survey/request id).
The fixture decodes each stream to the description and rebuilds the bytes from it; scripted
NNG peers (a thread replaying the recorded server stream and checking the client's bytes)
exercise the connection layer; loopback runs between library connections check the survey,
request and publish patterns including stale-id skipping and large messages.

    PYTHONPATH=<pynng install dir> python scripts/gen_sp_test.py
"""
import socket
import sys
import threading
import time
from pathlib import Path

import pynng

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'net_sp' / 'src' / 'main.e'
ID_PROTOS = {0x30, 0x31, 0x62, 0x63}


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    return p


def proxy(listen_port, target_port, log):
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('127.0.0.1', listen_port))
    srv.listen(1)
    conn, _ = srv.accept()
    up = socket.create_connection(('127.0.0.1', target_port))

    def pump(a, b, tag):
        try:
            while True:
                d = a.recv(65536)
                if not d:
                    break
                log.append((tag, d))
                b.sendall(d)
        except OSError:
            pass
    threading.Thread(target=pump, args=(conn, up, 'C'), daemon=True).start()
    threading.Thread(target=pump, args=(up, conn, 'S'), daemon=True).start()


def run(client_cls, server_cls, act, setup=lambda c, s: None):
    sport = free_port()
    server = server_cls()
    server.listen('tcp://127.0.0.1:%d' % sport)
    pport = free_port()
    log = []
    threading.Thread(target=proxy, args=(pport, sport, log), daemon=True).start()
    time.sleep(0.1)
    client = client_cls()
    setup(client, server)
    client.dial('tcp://127.0.0.1:%d' % pport, block=True)
    time.sleep(0.4)
    act(client, server)
    time.sleep(0.4)
    c = b''.join(d for t, d in log if t == 'C')
    s = b''.join(d for t, d in log if t == 'S')
    client.close()
    server.close()
    return c, s


def parse(stream):
    assert stream[:4] == b'\x00SP\x00' and stream[6:8] == b'\x00\x00'
    proto = int.from_bytes(stream[4:6], 'big')
    at = 8
    msgs = []
    while at < len(stream):
        n = int.from_bytes(stream[at:at + 8], 'big')
        body = stream[at + 8:at + 8 + n]
        at += 8 + n
        if proto in ID_PROTOS:
            assert body[0] & 0x80
            msgs.append((body[:4], body[4:]))
        else:
            msgs.append((None, body))
    return proto, msgs


def hx(b):
    return b.hex() or '-'


def describe(proto, msgs):
    out = ['H%02x' % proto]
    for ident, payload in msgs:
        out.append('M%s:%s' % (hx(ident) if ident is not None else '.', hx(payload)))
    return ' '.join(out)


lines = []
captures = {}


def capture(name, client_cls, server_cls, act, setup=lambda c, s: None):
    c, s = run(client_cls, server_cls, act, setup)
    captures[name] = (c, s)
    for tag, stream in (('C', c), ('S', s)):
        proto, msgs = parse(stream)
        lines.append('D %s %s %s => %s' % (name, tag, hx(stream), describe(proto, msgs)))


def surv(client, server):
    server.recv_timeout = 3000
    client.survey_time = 500
    client.send(b'who?')
    m = server.recv()
    server.send(b'me:' + m)
    time.sleep(0.1)


def surv2(client, server):
    server.recv_timeout = 3000
    client.survey_time = 500
    client.send(b'first')
    m = server.recv()
    server.send(b'a1')
    client.recv()
    client.send(b'second')
    m = server.recv()
    server.send(b'a2')
    time.sleep(0.2)


def req(client, server):
    client.send(b'ask')
    server.recv()
    server.send(b'answer')


def push(client, server):
    client.send(b'hello')
    client.send(b'')
    client.send(bytes(range(256)) * 8)


def sub(client, server):
    time.sleep(0.2)
    server.send(b'apple')
    server.send(b'banana')
    server.send(b'avocado')


def pair(client, server):
    client.send(b'one')
    server.recv()
    server.send(b'two')


def bus(client, server):
    client.send(b'bus-msg')
    time.sleep(0.1)


capture('survey', pynng.Surveyor0, pynng.Respondent0, surv)
capture('survey2', pynng.Surveyor0, pynng.Respondent0, surv2)
capture('req', pynng.Req0, pynng.Rep0, req)
capture('push', pynng.Push0, pynng.Pull0, push)
capture('sub', pynng.Sub0, pynng.Pub0, sub, lambda c, s: c.subscribe(b'a'))
capture('pair', pynng.Pair0, pynng.Pair0, pair)
capture('bus', pynng.Bus0, pynng.Bus0, bus)

peer_lines = []
for name in ('survey', 'req', 'push', 'sub', 'pair'):
    c, s = captures[name]
    peer_lines.append('P %s %s %s' % (name, hx(c), hx(s)))

vec, names = fc.vector_functions('v', lines)
peer_src, peer_names = fc.vector_functions('p', peer_lines)

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

fn hex_digit(v: u8) -> u8 {
    if v < 10u8 { ret 48u8 + v }
    ret 87u8 + v
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

fn put_hex(out: []u8, at: usize, s: []const u8) -> usize {
    if s.len == 0usize {
        out[at] = 45u8
        ret at + 1usize
    }
    var i = 0usize
    var p = at
    while i < s.len {
        out[p] = hex_digit(s[i] / 16u8)
        out[p + 1usize] = hex_digit(s[i] % 16u8)
        p += 2usize
        i += 1usize
    }
    ret p
}

fn proto_has_id(p: sp.Protocol) -> bool { ret sp.carries_id(p) }

// A recorded stream into its description.
fn describe(stream: []const u8, out: []u8) -> (usize, err) {
    let (p, pe) = sp.decode_handshake(stream)
    if pe != ok { ret (0usize, pe) }
    let number = sp.number_of(p)
    out[0usize] = 72u8
    out[1usize] = hex_digit(u8(number >> 4u32))
    out[2usize] = hex_digit(u8(number & 15u16))
    var n = 3usize
    var at = 8usize
    while at < stream.len {
        let (body, used, e) = sp.decode_message(stream[at..stream.len])
        if e != ok { ret (0usize, e) }
        at += used
        out[n] = 32u8
        out[n + 1usize] = 77u8
        n += 2usize
        if proto_has_id(p) {
            let (id, payload, ie) = sp.split_id(body)
            if ie != ok { ret (0usize, ie) }
            n = put_hex(out, n, body[0usize..4usize])
            out[n] = 58u8
            n += 1usize
            n = put_hex(out, n, payload)
        } else {
            out[n] = 46u8
            out[n + 1usize] = 58u8
            n += 2usize
            n = put_hex(out, n, body)
        }
    }
    ret (n, ok)
}

fn rebuild(desc: str, out: []u8) -> (usize, err) {
    let (h, p1) = tok(desc, 0usize)
    var number = u16(hexval(h[1usize])) * 16u16 + u16(hexval(h[2usize]))
    let (p, known) = sp.protocol_of(number)
    if !known { ret (0usize, sp.Malformed) }
    let (hn, he) = sp.encode_handshake(out[0usize..out.len], p)
    if he != ok { ret (0usize, he) }
    var n = hn
    var q = p1
    while q < desc.len {
        let (item, next) = tok(desc, q)
        q = next
        if item.len == 0usize { break }
        // M<id|.>:<payload>
        var colon = 1usize
        while colon < item.len && item[colon] != 58u8 { colon += 1usize }
        var id_bytes: [4]u8 = zero
        var has_id = false
        var id = 0u32
        if item[1usize] != 46u8 {
            let idn = unhex(item[1usize..colon], id_bytes[0usize..4usize])
            id = ((u32(id_bytes[0usize]) * 256u32 + u32(id_bytes[1usize])) * 256u32 + u32(id_bytes[2usize])) * 256u32 + u32(id_bytes[3usize])
            has_id = true
        }
        var payload: [4096]u8 = zero
        let pn = unhex(item[colon + 1usize..item.len], payload[0usize..4096usize])
        let (mn, me) = sp.encode_message(out[n..out.len], has_id, id, payload[0usize..pn])
        if me != ok { ret (0usize, me) }
        n += mn
    }
    ret (n, ok)
}

fn check_decode(line: str) -> u8 {
    var stream: [16384]u8 = zero
    var text: [16384]u8 = zero
    var out: [16384]u8 = zero
    let (kind, p0) = tok(line, 0usize)
    let (name, p1) = tok(line, p0)
    let (dir, p2) = tok(line, p1)
    let (stream_hex, p3) = tok(line, p2)
    let (arrow, p4) = tok(line, p3)
    let desc = line[p4 + 1usize..line.len]
    let sn = unhex(stream_hex, stream[0usize..16384usize])
    let (dn, de) = describe(stream[0usize..sn], text[0usize..16384usize])
    if de != ok { ret 1u8 }
    if !text_is(text[0usize..dn], desc) {
        let seen = io.print(text[0usize..dn])
        ret 2u8
    }
    let (n, e) = rebuild(desc, out[0usize..16384usize])
    if e != ok { ret 3u8 }
    if !same_bytes(out[0usize..n], stream[0usize..sn]) { ret 4u8 }
    ret 0u8
}

fn run_decode_chunk(text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let code = check_decode(text[start..i])
            if code != 0u8 {
                let shown = io.print(text[start..start + 24usize])
                ret code
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

// ---- loopback helpers ----

fn loopback(port: u16) -> net.Endpoint {
    let (ip, ip_error) = net.parse_ip("127.0.0.1")
    ret net.Endpoint { address: ip, port: port }
}

fn listen_local() -> (net.Socket, u16, err) {
    let (listener, e) = net.tcp_listen(loopback(0u16), 4u32)
    if e != ok { ret (listener, 0u16, e) }
    let (bound, be) = os.socket_local_address(listener)
    if be != ok { ret (listener, 0u16, be) }
    ret (listener, bound.port, ok)
}

fn send_all(sock: net.Socket, data: []const u8) -> err {
    var sent = 0usize
    while sent < data.len {
        let (n, e) = net.send(sock, data[sent..data.len])
        if e != ok { ret e }
        if n == 0usize { ret net.Failed }
        sent += n
    }
    ret ok
}

type Peer = struct { port: Atomic[u32], server_bytes: []const u8, expect: []const u8, ok_flag: Atomic[u32] }

fn serve_peer(p: *Peer) {
    let (listener, port, le) = listen_local()
    if le != ok {
        let f0 = atomic.add(&p.ok_flag, 2u32, .Release)
        let p0 = atomic.add(&p.port, 1u32, .Release)
        ret
    }
    defer let _ = net.close(listener)
    let published = atomic.add(&p.port, u32(port), .Release)
    let (sock, from, e) = net.tcp_accept(listener)
    if e != ok {
        let f1 = atomic.add(&p.ok_flag, 2u32, .Release)
        ret
    }
    defer let _ = net.close(sock)
    if send_all(sock, p.server_bytes) != ok {
        let f2 = atomic.add(&p.ok_flag, 3u32, .Release)
        ret
    }
    var got: [16384]u8 = zero
    var have = 0usize
    while have < p.expect.len {
        let (n, re) = net.receive(sock, got[have..16384usize])
        if re != ok || n == 0usize {
            let f3 = atomic.add(&p.ok_flag, 4u32, .Release)
            ret
        }
        have += n
    }
    if same_bytes(got[0usize..have], p.expect) {
        let f4 = atomic.add(&p.ok_flag, 1u32, .Release)
    } else {
        let f5 = atomic.add(&p.ok_flag, 5u32, .Release)
    }
}

// The scripted peer replays the recorded server stream; our client (protocol taken from the recorded
// client stream, the messages it sent replayed through the library) must write exactly the recorded bytes.
fn check_peer(line: str) -> u8 {
    var client_bytes: [16384]u8 = zero
    var server_bytes: [16384]u8 = zero
    var desc_text: [16384]u8 = zero
    var server_text: [16384]u8 = zero
    var payload_store: [8192]u8 = zero
    let (kind, p0) = tok(line, 0usize)
    let (name, p1) = tok(line, p0)
    let (c_hex, p2) = tok(line, p1)
    let (s_hex, p3) = tok(line, p2)
    let cn = unhex(c_hex, client_bytes[0usize..16384usize])
    let sn = unhex(s_hex, server_bytes[0usize..16384usize])
    var peer: Peer = zero
    peer.server_bytes = server_bytes[0usize..sn]
    peer.expect = client_bytes[0usize..cn]
    let (th, spawn_error) = thread.spawn[Peer](serve_peer, &peer, 0usize)
    if spawn_error != ok { ret 2u8 }
    defer let _ = thread.join(th)
    var nap = sync.semaphore(0u32)
    var waited = 0usize
    while atomic.load(&peer.port, .Acquire) == 0u32 && waited < 2000usize {
        let woke = sync.semaphore_wait_for(&nap, time.millis(5i64))
        waited += 1usize
    }
    let port = u16(atomic.load(&peer.port, .Acquire))
    if port == 0u16 { ret 1u8 }
    let (sock, ce) = net.tcp_connect(loopback(port))
    if ce != ok { ret 3u8 }
    defer let _ = net.close(sock)
    let (cdn, cde) = describe(client_bytes[0usize..cn], desc_text[0usize..16384usize])
    if cde != ok { ret 4u8 }
    let desc: str = desc_text[0usize..cdn]
    let (h, q1) = tok(desc, 0usize)
    let (proto, known) = sp.protocol_of(u16(hexval(h[1usize])) * 16u16 + u16(hexval(h[2usize])))
    if !known { ret 5u8 }
    var buf: [16384]u8 = zero
    var c = sp.conn(sock, buf[0usize..16384usize], proto, 0u32)
    if sp.handshake(&c) != ok { ret 6u8 }
    var used = 0usize
    var q = q1
    while q < desc.len {
        let (item, next) = tok(desc, q)
        q = next
        if item.len == 0usize { break }
        var colon = 1usize
        while colon < item.len && item[colon] != 58u8 { colon += 1usize }
        var id_bytes: [4]u8 = zero
        var id = 0u32
        if item[1usize] != 46u8 {
            let idn = unhex(item[1usize..colon], id_bytes[0usize..4usize])
            id = ((u32(id_bytes[0usize]) * 256u32 + u32(id_bytes[1usize])) * 256u32 + u32(id_bytes[2usize])) * 256u32 + u32(id_bytes[3usize])
        }
        let pn = unhex(item[colon + 1usize..item.len], payload_store[used..8192usize])
        if sp.send(&c, id, payload_store[used..used + pn]) != ok { ret 7u8 }
        used += pn
    }
    // read back every message the recorded server stream carries and compare payloads
    let (sdn, sde) = describe(server_bytes[0usize..sn], server_text[0usize..16384usize])
    if sde != ok { ret 8u8 }
    let sdesc: str = server_text[0usize..sdn]
    let (sh, sq1) = tok(sdesc, 0usize)
    var sq = sq1
    while sq < sdesc.len {
        let (item, next) = tok(sdesc, sq)
        sq = next
        if item.len == 0usize { break }
        var colon = 1usize
        while colon < item.len && item[colon] != 58u8 { colon += 1usize }
        var want: [4096]u8 = zero
        let wn = unhex(item[colon + 1usize..item.len], want[0usize..4096usize])
        let (body, re) = sp.recv(&c)
        if re != ok { ret 9u8 }
        var payload = body
        if sp.carries_id(sp.peer_of(proto)) {
            let (rid, rpayload, ie) = sp.split_id(body)
            if ie != ok { ret 10u8 }
            payload = rpayload
        }
        if !same_bytes(payload, want[0usize..wn]) { ret 11u8 }
    }
    var settle = sync.semaphore(0u32)
    var spins = 0usize
    while atomic.load(&peer.ok_flag, .Acquire) == 0u32 && spins < 2000usize {
        let woke2 = sync.semaphore_wait_for(&settle, time.millis(5i64))
        spins += 1usize
    }
    if atomic.load(&peer.ok_flag, .Acquire) != 1u32 { ret 12u8 }
    ret 0u8
}

fn run_peer_chunk(text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let code = check_peer(text[start..i])
            if code != 0u8 {
                let shown = io.print(text[start..start + 12usize])
                ret code
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

// ---- patterns between two library connections ----

type Pair = struct { server: net.Socket, client: net.Socket }

fn connect_pair() -> (Pair, err) {
    var p: Pair = zero
    let (listener, port, le) = listen_local()
    if le != ok { ret (p, le) }
    defer let _ = net.close(listener)
    let (client, ce) = net.tcp_connect(loopback(port))
    if ce != ok { ret (p, ce) }
    let (server, from, ae) = net.tcp_accept(listener)
    if ae != ok {
        let cc = net.close(client)
        ret (p, ae)
    }
    p.server = server
    p.client = client
    ret (p, ok)
}

type Shake = struct { c: *sp.Conn, result: u32 }

fn shake(s: *Shake) {
    if sp.handshake(s.c) != ok {
        s.result = 2u32
        ret
    }
    s.result = 1u32
}

fn handshake_pair(left: *sp.Conn, right: *sp.Conn) -> u32 {
    var a: Shake = Shake { c: left, result: 0u32 }
    let (th, e) = thread.spawn[Shake](shake, &a, 0usize)
    if e != ok { ret 100u32 }
    let r = sp.handshake(right)
    let joined = thread.join(th)
    if r != ok { ret 101u32 }
    ret a.result
}

fn patterns() -> u32 {
    var lb: [8192]u8 = zero
    var rb: [8192]u8 = zero
    var rb2: [8192]u8 = zero
    var lb2: [8192]u8 = zero
    // SURVEYOR with two RESPONDENTS: both answer; a stale answer (previous survey id) is skipped
    if true {
        let (p1, e1) = connect_pair()
        if e1 != ok { ret 110u32 }
        defer let _ = net.close(p1.server)
        defer let _ = net.close(p1.client)
        let (p2, e2) = connect_pair()
        if e2 != ok { ret 111u32 }
        defer let _ = net.close(p2.server)
        defer let _ = net.close(p2.client)
        var s1 = sp.conn(p1.client, lb[0usize..8192usize], .Surveyor, 41u32)
        var r1 = sp.conn(p1.server, rb[0usize..8192usize], .Respondent, 0u32)
        var s2 = sp.conn(p2.client, lb2[0usize..8192usize], .Surveyor, 41u32)
        var r2 = sp.conn(p2.server, rb2[0usize..8192usize], .Respondent, 0u32)
        if handshake_pair(&s1, &r1) != 1u32 { ret 112u32 }
        if handshake_pair(&s2, &r2) != 1u32 { ret 113u32 }
        let id = sp.next_question_id(&s1)
        if id != 2147483689u32 { ret 114u32 }
        let id_b = sp.next_question_id(&s2)
        if sp.send(&s1, id, "who is there?") != ok { ret 115u32 }
        if sp.send(&s2, id_b, "who is there?") != ok { ret 116u32 }
        let (qid1, q1, qe1) = sp.recv_question(&r1)
        let (qid2, q2, qe2) = sp.recv_question(&r2)
        if qe1 != ok || qe2 != ok || qid1 != id || qid2 != id_b { ret 117u32 }
        // respondent 1 first sends a stale answer (older id), then the right one
        if sp.send(&r1, qid1 - 1u32, "stale") != ok { ret 118u32 }
        if sp.send(&r1, qid1, "one") != ok { ret 119u32 }
        if sp.send(&r2, qid2, "two") != ok { ret 120u32 }
        let (a1, ae1) = sp.recv_answer(&s1, id)
        let (a2, ae2) = sp.recv_answer(&s2, id_b)
        if ae1 != ok || ae2 != ok || !same_bytes(a1, "one") || !same_bytes(a2, "two") { ret 121u32 }
    }
    // REQ / REP with a payload larger than the small-buffer path
    if true {
        let (p, pe) = connect_pair()
        if pe != ok { ret 130u32 }
        defer let _ = net.close(p.server)
        defer let _ = net.close(p.client)
        var req = sp.conn(p.client, lb[0usize..8192usize], .Req, 7u32)
        var rep = sp.conn(p.server, rb[0usize..8192usize], .Rep, 0u32)
        if handshake_pair(&req, &rep) != 1u32 { ret 131u32 }
        var big: [3000]u8 = zero
        var i = 0usize
        while i < 3000usize {
            big[i] = u8(i % 253usize)
            i += 1usize
        }
        let id = sp.next_question_id(&req)
        if sp.send(&req, id, big[0usize..3000usize]) != ok { ret 132u32 }
        let (qid, q, qe) = sp.recv_question(&rep)
        if qe != ok || qid != id || !same_bytes(q, big[0usize..3000usize]) { ret 133u32 }
        if sp.send(&rep, qid, "ok") != ok { ret 134u32 }
        let (a, ae) = sp.recv_answer(&req, id)
        if ae != ok || !same_bytes(a, "ok") { ret 135u32 }
    }
    // PUB / SUB: the subscriber filters by prefix on receipt
    if true {
        let (p, pe) = connect_pair()
        if pe != ok { ret 140u32 }
        defer let _ = net.close(p.server)
        defer let _ = net.close(p.client)
        var sub = sp.conn(p.client, lb[0usize..8192usize], .Sub, 0u32)
        var pub = sp.conn(p.server, rb[0usize..8192usize], .Pub, 0u32)
        if handshake_pair(&sub, &pub) != 1u32 { ret 141u32 }
        var words: [3]str = zero
        words[0usize] = "apple"
        words[1usize] = "banana"
        words[2usize] = "avocado"
        var w = 0usize
        while w < 3usize {
            if sp.send(&pub, 0u32, words[w]) != ok { ret 142u32 }
            w += 1usize
        }
        var kept = 0usize
        var seen = 0usize
        while seen < 3usize {
            let (body, re) = sp.recv(&sub)
            if re != ok { ret 143u32 }
            if sp.topic_matches("a", body) { kept += 1usize }
            seen += 1usize
        }
        if kept != 2usize { ret 144u32 }
    }
    // incompatible protocols are refused
    if true {
        let (p, pe) = connect_pair()
        if pe != ok { ret 150u32 }
        defer let _ = net.close(p.server)
        defer let _ = net.close(p.client)
        var push = sp.conn(p.client, lb[0usize..8192usize], .Push, 0u32)
        var rep = sp.conn(p.server, rb[0usize..8192usize], .Rep, 0u32)
        if handshake_pair(&push, &rep) == 1u32 { ret 151u32 }
    }
    ret 0u32
}
'''

DECODE_CALLS = '\n'.join('    let rd_%s = run_decode_chunk(%s())\n    if rd_%s != 0u8 { os.exit(i32(rd_%s)) }' % (n, n, n, n) for n in names)
PEER_CALLS = '\n'.join('    let rp_%s = run_peer_chunk(%s())\n    if rp_%s != 0u8 { os.exit(i32(rp_%s) + 20i32) }' % (n, n, n, n) for n in peer_names)

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
''' + DECODE_CALLS + '''
''' + PEER_CALLS + '''
    let pr = patterns()
    if pr != 0u32 { os.exit(i32(pr)) }
    try io.print("net sp ok")
    ret ok
}
'''

src = ('// e.net.sp against NNG 1.x (pynng): recorded streams of six socket pairs decode to their description and\n'
       '// rebuild byte for byte, scripted NNG peers over TCP check the connection layer, and survey, request and\n'
       '// publish patterns run between library connections (D2805). D stream vectors, P scripted peers.\n'
       '// Generated by scripts/gen_sp_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.net\nuse e.thread\nuse e.atomic\nuse e.sync\nuse e.time\nuse e.net.sp\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + peer_src + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'stream vectors,', len(peer_lines), 'scripted peers')
