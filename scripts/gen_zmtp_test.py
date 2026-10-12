"""Generate tests/selfhost/fixtures/link/net_zmtp/src/main.e (L156, D2805).

Reference: libzmq 4.3.5 through pyzmq. Real socket pairs (PUSH/PULL, PUB/SUB, REQ/REP,
REQ/ROUTER, DEALER/ROUTER, DEALER/DEALER, PAIR/PAIR, XSUB/XPUB, ROUTER/DEALER) talk
through a recording TCP proxy, and each direction's byte stream is embedded with a
structured description (socket type, identity, messages and subscription commands).
The fixture decodes every stream into that description and rebuilds the stream from it,
which must reproduce the libzmq bytes exactly; scripted libzmq peers (a thread that
replays a recorded server stream and checks what the client sends against the recorded
client stream) check the connection layer; loopback runs between two `e.net.zmtp`
connections check the pattern semantics (prefix subscriptions, REQ/REP envelopes,
identity routing, incompatible peers).

    PYTHONPATH=<pyzmq install dir> python scripts/gen_zmtp_test.py
"""
import socket
import sys
import threading
import time
from pathlib import Path

import zmq

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'net_zmtp' / 'src' / 'main.e'
TYPES = ['PAIR', 'PUB', 'SUB', 'REQ', 'REP', 'DEALER', 'ROUTER', 'PULL', 'PUSH', 'XPUB', 'XSUB']
ZMQ = {'PAIR': zmq.PAIR, 'PUB': zmq.PUB, 'SUB': zmq.SUB, 'REQ': zmq.REQ, 'REP': zmq.REP, 'DEALER': zmq.DEALER,
       'ROUTER': zmq.ROUTER, 'PULL': zmq.PULL, 'PUSH': zmq.PUSH, 'XPUB': zmq.XPUB, 'XSUB': zmq.XSUB}


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


def run(ctype, stype, setup_client, act, setup_server=lambda s: None):
    ctx = zmq.Context()
    server = ctx.socket(ZMQ[stype])
    setup_server(server)
    sport = free_port()
    server.bind('tcp://127.0.0.1:%d' % sport)
    pport = free_port()
    log = []
    threading.Thread(target=proxy, args=(pport, sport, log), daemon=True).start()
    time.sleep(0.1)
    client = ctx.socket(ZMQ[ctype])
    setup_client(client)
    client.connect('tcp://127.0.0.1:%d' % pport)
    time.sleep(0.4)
    act(client, server)
    time.sleep(0.4)
    c = b''.join(d for t, d in log if t == 'C')
    s = b''.join(d for t, d in log if t == 'S')
    client.close(0)
    server.close(0)
    ctx.term()
    return c, s


def parse_stream(data):
    """An independent stream parser: (type, identity, items); item is ('M', [parts]) | ('B', p) | ('X', p)."""
    assert data[0] == 0xFF and data[9] == 0x7F and data[10] >= 3
    at = 64
    items = []
    stype = None
    ident = b''
    msg = []
    while at < len(data):
        flags = data[at]
        if flags & 2:
            n = int.from_bytes(data[at + 1:at + 9], 'big')
            at += 9
        else:
            n = data[at + 1]
            at += 2
        body = data[at:at + n]
        at += n
        if flags & 4:
            nl = body[0]
            name = body[1:1 + nl]
            rest = body[1 + nl:]
            if name == b'READY':
                p = 0
                while p < len(rest):
                    kl = rest[p]
                    k = rest[p + 1:p + 1 + kl]
                    p += 1 + kl
                    vl = int.from_bytes(rest[p:p + 4], 'big')
                    v = rest[p + 4:p + 4 + vl]
                    p += 4 + vl
                    if k == b'Socket-Type':
                        stype = v.decode()
                    if k == b'Identity':
                        ident = v
            elif name == b'SUBSCRIBE':
                items.append(('B', rest))
            elif name == b'CANCEL':
                items.append(('X', rest))
            else:
                raise ValueError(name)
        else:
            msg.append(body)
            if not flags & 1:
                items.append(('M', msg))
                msg = []
    assert not msg
    return stype, ident, items


def hx(b):
    return b.hex() or '-'


def describe(stype, ident, items):
    out = ['T%d' % TYPES.index(stype), 'I' + hx(ident)]
    for kind, v in items:
        if kind == 'M':
            out.append('M' + '/'.join(hx(p) for p in v))
        else:
            out.append(kind + hx(v))
    return ' '.join(out)


lines = []
captures = {}


def capture(name, ctype, stype, setup_client, act, setup_server=lambda s: None):
    c, s = run(ctype, stype, setup_client, act, setup_server)
    captures[name] = (ctype, stype, c, s)
    for tag, stream in (('C', c), ('S', s)):
        t, ident, items = parse_stream(stream)
        lines.append('D %s %s %s => %s' % (name, tag, hx(stream), describe(t, ident, items)))


def nothing(client, server):
    pass


big = bytes((i * 7 + 3) & 255 for i in range(3000))
capture('push', 'PUSH', 'PULL', lambda c: None, lambda c, s: (c.send_multipart([b'hello', b'world']), c.send(b'x' * 300), c.send(b''), c.send(big)))
capture('sub', 'SUB', 'PUB', lambda c: (c.setsockopt(zmq.SUBSCRIBE, b'a'), c.setsockopt(zmq.SUBSCRIBE, b'topic/')), nothing)
capture('pub', 'PUB', 'SUB', lambda c: None, nothing, lambda s: s.setsockopt(zmq.SUBSCRIBE, b''))
capture('req', 'REQ', 'REP', lambda c: None, lambda c, s: (c.send_multipart([b'ping', b'2']), s.recv_multipart(), s.send(b'pong')))
capture('req_router', 'REQ', 'ROUTER', lambda c: None, lambda c, s: (c.send(b'q'), s.recv_multipart()))
capture('dealer_id', 'DEALER', 'ROUTER', lambda c: c.setsockopt(zmq.IDENTITY, b'id1'), lambda c, s: (c.send_multipart([b'a', b'b']), s.recv_multipart(), s.send_multipart([b'id1', b'reply'])))
capture('dealer_dealer', 'DEALER', 'DEALER', lambda c: c.setsockopt(zmq.IDENTITY, b'left'), lambda c, s: (c.send(b'x'), s.recv(), s.send_multipart([b'y', b'z'])))
capture('pair', 'PAIR', 'PAIR', lambda c: None, lambda c, s: (c.send(b'one'), s.recv(), s.send(b'two')))
capture('xsub', 'XSUB', 'XPUB', lambda c: None, lambda c, s: (c.send(b'\x01news'), c.send(b'\x00news'), time.sleep(0.2)))
capture('router_dealer', 'ROUTER', 'DEALER', lambda c: None, nothing, lambda s: s.setsockopt(zmq.IDENTITY, b'srvid'))

peer_lines = []
for name in ('push', 'sub', 'req', 'dealer_id'):
    ctype, stype, c, s = captures[name]
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

// A recorded stream into its description text.
fn describe(stream: []const u8, out: []u8) -> (usize, err) {
    let (g, ge) = zmtp.decode_greeting(stream)
    if ge != ok { ret (0usize, ge) }
    var at = 64usize
    var n = 0usize
    let (rf, used, re) = zmtp.decode_frame(stream[at..stream.len])
    if re != ok || !rf.command { ret (0usize, zmtp.Malformed) }
    let (ready, ready_error) = zmtp.decode_ready(rf.body)
    if ready_error != ok { ret (0usize, ready_error) }
    at += used
    out[0usize] = 84u8
    n = 1usize
    let ti = zmtp.type_index(ready.socket_type)
    if ti >= 10u8 {
        out[n] = 49u8
        out[n + 1usize] = 48u8 + (ti - 10u8)
        n += 2usize
    } else {
        out[n] = 48u8 + ti
        n += 1usize
    }
    out[n] = 32u8
    out[n + 1usize] = 73u8
    n += 2usize
    n = put_hex(out, n, ready.identity)
    while at < stream.len {
        let (f, u, e) = zmtp.decode_frame(stream[at..stream.len])
        if e != ok { ret (0usize, e) }
        at += u
        out[n] = 32u8
        n += 1usize
        if f.command {
            let (is_sub, subscribe, prefix) = zmtp.decode_subscription(f.body)
            if !is_sub { ret (0usize, zmtp.Malformed) }
            if subscribe {
                out[n] = 66u8
            } else {
                out[n] = 88u8
            }
            n += 1usize
            n = put_hex(out, n, prefix)
        } else {
            out[n] = 77u8
            n += 1usize
            n = put_hex(out, n, f.body)
            var more = f.more
            while more {
                let (g2, u2, e2) = zmtp.decode_frame(stream[at..stream.len])
                if e2 != ok { ret (0usize, e2) }
                at += u2
                out[n] = 47u8
                n += 1usize
                n = put_hex(out, n, g2.body)
                more = g2.more
            }
        }
    }
    ret (n, ok)
}

// A description back into the stream: greeting, READY, then the items.
fn rebuild(desc: str, out: []u8) -> (usize, err) {
    let (t_tok, p1) = tok(desc, 0usize)
    let (i_tok, p2) = tok(desc, p1)
    var ti = 0u8
    var d = 1usize
    while d < t_tok.len {
        ti = ti * 10u8 + (t_tok[d] - 48u8)
        d += 1usize
    }
    var ident: [260]u8 = zero
    let id_len = unhex(i_tok[1usize..i_tok.len], ident[0usize..260usize])
    let (gn, ge) = zmtp.encode_greeting(out[0usize..out.len], false, id_len)
    if ge != ok { ret (0usize, ge) }
    var n = gn
    let (rn, re) = zmtp.encode_ready(out[n..out.len], zmtp.socket_type_at(ti), ident[0usize..id_len])
    if re != ok { ret (0usize, re) }
    n += rn
    var p = p2
    while p < desc.len {
        let (item, next) = tok(desc, p)
        p = next
        if item.len == 0usize { break }
        let kind = item[0usize]
        if kind == 66u8 || kind == 88u8 {
            var prefix: [300]u8 = zero
            let pn = unhex(item[1usize..item.len], prefix[0usize..300usize])
            let (sn, se) = zmtp.encode_subscription(out[n..out.len], kind == 66u8, prefix[0usize..pn])
            if se != ok { ret (0usize, se) }
            n += sn
        } else {
            var start = 1usize
            var i = 1usize
            while i <= item.len {
                if i == item.len || item[i] == 47u8 {
                    var body: [4096]u8 = zero
                    let bn = unhex(item[start..i], body[0usize..4096usize])
                    let (frame_n, fe) = zmtp.encode_frame(out[n..out.len], i < item.len, false, body[0usize..bn])
                    if fe != ok { ret (0usize, fe) }
                    n += frame_n
                    start = i + 1usize
                }
                i += 1usize
            }
        }
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

// ---- scripted libzmq peer: replays the recorded server stream, checks the client's ----

type Peer = struct { port: Atomic[u32], server_bytes: []const u8, expect: []const u8, ok_flag: Atomic[u32] }

fn serve_peer(p: *Peer) {
    let (listener, port, le) = listen_local()
    if le != ok {
        let flag_set = atomic.add(&p.ok_flag, 2u32, .Release)
        let p0 = atomic.add(&p.port, 1u32, .Release)
        ret
    }
    defer let _ = net.close(listener)
    let published = atomic.add(&p.port, u32(port), .Release)
    let (sock, from, e) = net.tcp_accept(listener)
    if e != ok {
        let flag_set = atomic.add(&p.ok_flag, 2u32, .Release)
        ret
    }
    defer let _ = net.close(sock)
    if send_all(sock, p.server_bytes) != ok {
        let flag_set = atomic.add(&p.ok_flag, 3u32, .Release)
        ret
    }
    var got: [16384]u8 = zero
    var have = 0usize
    while have < p.expect.len {
        let (n, re) = net.receive(sock, got[have..16384usize])
        if re != ok || n == 0usize {
            let flag_set = atomic.add(&p.ok_flag, 4u32, .Release)
            ret
        }
        have += n
    }
    if same_bytes(got[0usize..have], p.expect) {
        let flag_set = atomic.add(&p.ok_flag, 1u32, .Release)
    } else {
        let flag_set = atomic.add(&p.ok_flag, 5u32, .Release)
    }
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

fn check_peer(a: *mem.Arena, line: str) -> u8 {
    var client_bytes: [16384]u8 = zero
    var server_bytes: [16384]u8 = zero
    var desc_text: [16384]u8 = zero
    var parts_store: [8192]u8 = zero
    var parts: [8][]const u8 = zero
    var sub_set_store: [4]str = zero
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
    // wait for the peer to publish its port
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
    // the client side: describe what the recorded client stream says it is and replay it through the library
    let (cdn, cde) = describe(client_bytes[0usize..cn], desc_text[0usize..16384usize])
    if cde != ok { ret 4u8 }
    let desc: str = desc_text[0usize..cdn]
    let (t_tok, q1) = tok(desc, 0usize)
    let (i_tok, q2) = tok(desc, q1)
    var ti = 0u8
    var d = 1usize
    while d < t_tok.len {
        ti = ti * 10u8 + (t_tok[d] - 48u8)
        d += 1usize
    }
    var ident: [260]u8 = zero
    let id_len = unhex(i_tok[1usize..i_tok.len], ident[0usize..260usize])
    var buf: [16384]u8 = zero
    var c = zmtp.conn(sock, buf[0usize..16384usize], zmtp.socket_type_at(ti), ident[0usize..id_len])
    if zmtp.handshake(&c, false) != ok { ret 5u8 }
    // client items, in order
    var q = q2
    var used = 0usize
    while q < desc.len {
        let (item, next) = tok(desc, q)
        q = next
        if item.len == 0usize { break }
        let kind_byte = item[0usize]
        if kind_byte == 66u8 || kind_byte == 88u8 {
            var prefix: [300]u8 = zero
            let pn = unhex(item[1usize..item.len], prefix[0usize..300usize])
            var frame: [320]u8 = zero
            let (fn_, fe) = zmtp.encode_subscription(frame[0usize..320usize], kind_byte == 66u8, prefix[0usize..pn])
            if fe != ok { ret 6u8 }
            if zmtp.send_command(&c, frame[0usize..fn_]) != ok { ret 7u8 }
        } else {
            var count = 0usize
            var start = 1usize
            var i = 1usize
            while i <= item.len {
                if i == item.len || item[i] == 47u8 {
                    let bn = unhex(item[start..i], parts_store[used..8192usize])
                    parts[count] = parts_store[used..used + bn]
                    used += bn
                    count += 1usize
                    start = i + 1usize
                }
                i += 1usize
            }
            if zmtp.send_message(&c, parts[0usize..count]) != ok { ret 8u8 }
        }
    }
    // then the messages the recorded server stream carries come back through recv_message
    var server_text: [16384]u8 = zero
    let (sdn, sde) = describe(server_bytes[0usize..sn], server_text[0usize..16384usize])
    if sde != ok { ret 9u8 }
    let sdesc: str = server_text[0usize..sdn]
    var subs: zmtp.Subscriptions = zero
    var got_parts: [8][]const u8 = zero
    var r = 0usize
    let (s_t, sp1) = tok(sdesc, 0usize)
    let (s_i, sp2) = tok(sdesc, sp1)
    var sp = sp2
    while sp < sdesc.len {
        let (item, next) = tok(sdesc, sp)
        sp = next
        if item.len == 0usize { break }
        if item[0usize] == 77u8 {
            // expect this message from the peer
            let (n, re) = zmtp.recv_message(&c, got_parts[0usize..8usize], &subs)
            if re != ok { ret 11u8 }
            var start = 1usize
            var i = 1usize
            var idx = 0usize
            while i <= item.len {
                if i == item.len || item[i] == 47u8 {
                    var want: [4096]u8 = zero
                    let wn = unhex(item[start..i], want[0usize..4096usize])
                    if idx >= n || !same_bytes(got_parts[idx], want[0usize..wn]) { ret 12u8 }
                    idx += 1usize
                    start = i + 1usize
                }
                i += 1usize
            }
            if idx != n { ret 13u8 }
        }
    }
    var settle = sync.semaphore(0u32)
    var spins = 0usize
    while atomic.load(&peer.ok_flag, .Acquire) == 0u32 && spins < 2000usize {
        let woke2 = sync.semaphore_wait_for(&settle, time.millis(5i64))
        spins += 1usize
    }
    if atomic.load(&peer.ok_flag, .Acquire) != 1u32 { ret 14u8 }
    ret 0u8
}

fn run_peer_chunk(a: *mem.Arena, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let code = check_peer(a, text[start..i])
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

'''

DECODE_CALLS = '\n'.join('    let rd_%s = run_decode_chunk(%s())\n    if rd_%s != 0u8 { os.exit(i32(rd_%s)) }' % (n, n, n, n) for n in names)
PEER_CALLS = '\n'.join('    let rp_%s = run_peer_chunk(a, %s())\n    if rp_%s != 0u8 { os.exit(i32(rp_%s) + 20i32) }' % (n, n, n, n) for n in peer_names)

PATTERNS = '''
// ---- pattern semantics between two library connections ----

type Pair = struct { server: net.Socket, client: net.Socket, port: u16 }

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
    p.port = port
    ret (p, ok)
}

type Shake = struct { c: *zmtp.Conn, as_server: bool, result: u32 }

fn shake(s: *Shake) {
    if zmtp.handshake(s.c, s.as_server) != ok {
        s.result = 2u32
        ret
    }
    s.result = 1u32
}

// Handshakes both ends at once (each side sends its greeting before it reads, but two threads keep it safe).
fn handshake_pair(left: *zmtp.Conn, right: *zmtp.Conn) -> u32 {
    var a: Shake = Shake { c: left, as_server: false, result: 0u32 }
    let (th, e) = thread.spawn[Shake](shake, &a, 0usize)
    if e != ok { ret 100u32 }
    let r = zmtp.handshake(right, true)
    let joined = thread.join(th)
    if r != ok { ret 101u32 }
    ret a.result
}

fn patterns(a: *mem.Arena) -> u32 {
    var lb: [8192]u8 = zero
    var rb: [8192]u8 = zero
    var parts: [4][]const u8 = zero
    var got: [4][]const u8 = zero
    var set_storage: [4]str = zero
    var empty_subs: zmtp.Subscriptions = zero
    // PUSH -> PULL, a multipart message, a long frame, an empty message
    if true {
        let (pair, pe) = connect_pair()
        if pe != ok { ret 110u32 }
        defer let _ = net.close(pair.server)
        defer let _ = net.close(pair.client)
        var push = zmtp.conn(pair.client, lb[0usize..8192usize], .Push, "")
        var pull = zmtp.conn(pair.server, rb[0usize..8192usize], .Pull, "")
        if handshake_pair(&push, &pull) != 1u32 { ret 111u32 }
        if push.remote != .Pull || pull.remote != .Push { ret 112u32 }
        var big: [1000]u8 = zero
        var i = 0usize
        while i < 1000usize {
            big[i] = u8(i % 251usize)
            i += 1usize
        }
        parts[0usize] = "alpha"
        parts[1usize] = big[0usize..1000usize]
        if zmtp.send_message(&push, parts[0usize..2usize]) != ok { ret 113u32 }
        parts[0usize] = ""
        if zmtp.send_message(&push, parts[0usize..1usize]) != ok { ret 114u32 }
        let (n1, e1) = zmtp.recv_message(&pull, got[0usize..4usize], &empty_subs)
        if e1 != ok || n1 != 2usize || !same_bytes(got[0usize], "alpha") || !same_bytes(got[1usize], big[0usize..1000usize]) { ret 115u32 }
        let (n2, e2) = zmtp.recv_message(&pull, got[0usize..4usize], &empty_subs)
        if e2 != ok || n2 != 1usize || got[0usize].len != 0usize { ret 116u32 }
    }
    // PUB / SUB: the PUB filters by the prefixes its SUB announced and cancelled
    if true {
        let (pair, pe) = connect_pair()
        if pe != ok { ret 120u32 }
        defer let _ = net.close(pair.server)
        defer let _ = net.close(pair.client)
        var sub = zmtp.conn(pair.client, lb[0usize..8192usize], .Sub, "")
        var pub = zmtp.conn(pair.server, rb[0usize..8192usize], .Pub, "")
        if handshake_pair(&sub, &pub) != 1u32 { ret 121u32 }
        var frame: [64]u8 = zero
        let (n_a, e_a) = zmtp.encode_subscription(frame[0usize..64usize], true, "a")
        if zmtp.send_command(&sub, frame[0usize..n_a]) != ok { ret 122u32 }
        let (n_b, e_b) = zmtp.encode_subscription(frame[0usize..64usize], true, "b")
        if zmtp.send_command(&sub, frame[0usize..n_b]) != ok { ret 123u32 }
        let (n_c, e_c) = zmtp.encode_subscription(frame[0usize..64usize], false, "b")
        if zmtp.send_command(&sub, frame[0usize..n_c]) != ok { ret 124u32 }
        var subs: zmtp.Subscriptions = zero
        subs.prefixes = set_storage[0usize..4usize]
        // the PUB reads the three commands (recv_message applies them and then needs a message to stop on)
        var seen = 0usize
        while seen < 3usize {
            let (f, fe) = zmtp.recv_frame(&pub)
            if fe != ok || !f.command { ret 125u32 }
            let (is_sub, subscribe, prefix) = zmtp.decode_subscription(f.body)
            if subscribe {
                let ae = zmtp.add_prefix(&subs, prefix)
            } else {
                zmtp.remove_prefix(&subs, prefix)
            }
            seen += 1usize
        }
        if subs.count != 1usize || !zmtp.wants(&subs, "apple") || zmtp.wants(&subs, "banana") || !zmtp.wants(&subs, "a") || zmtp.wants(&subs, "") { ret 126u32 }
        // publish three; only the matching ones are sent
        var words: [3]str = zero
        words[0usize] = "apple"
        words[1usize] = "banana"
        words[2usize] = "avocado"
        var w = 0usize
        while w < 3usize {
            parts[0usize] = words[w]
            if zmtp.wants(&subs, parts[0usize]) {
                if zmtp.send_message(&pub, parts[0usize..1usize]) != ok { ret 127u32 }
            }
            w += 1usize
        }
        let (n1, e1) = zmtp.recv_message(&sub, got[0usize..4usize], &empty_subs)
        if e1 != ok || n1 != 1usize || !same_bytes(got[0usize], "apple") { ret 128u32 }
        let (n2, e2) = zmtp.recv_message(&sub, got[0usize..4usize], &empty_subs)
        if e2 != ok || n2 != 1usize || !same_bytes(got[0usize], "avocado") { ret 129u32 }
    }
    // REQ / REP envelopes
    if true {
        let (pair, pe) = connect_pair()
        if pe != ok { ret 130u32 }
        defer let _ = net.close(pair.server)
        defer let _ = net.close(pair.client)
        var req = zmtp.conn(pair.client, lb[0usize..8192usize], .Req, "")
        var rep = zmtp.conn(pair.server, rb[0usize..8192usize], .Rep, "")
        if handshake_pair(&req, &rep) != 1u32 { ret 131u32 }
        var body: [3][]const u8 = zero
        body[0usize] = "ping"
        body[1usize] = "2"
        var wire: [4][]const u8 = zero
        let (wn, we) = zmtp.req_envelope(body[0usize..2usize], wire[0usize..4usize])
        if we != ok || wn != 3usize || wire[0usize].len != 0usize { ret 132u32 }
        if zmtp.send_message(&req, wire[0usize..wn]) != ok { ret 133u32 }
        let (n1, e1) = zmtp.recv_message(&rep, got[0usize..4usize], &empty_subs)
        if e1 != ok || n1 != 3usize { ret 134u32 }
        let (start, se) = zmtp.envelope_body_start(got[0usize..n1])
        if se != ok || start != 1usize || !same_bytes(got[start], "ping") || !same_bytes(got[start + 1usize], "2") { ret 135u32 }
        // the REP answers inside the same envelope
        var reply: [3][]const u8 = zero
        reply[0usize] = ""
        reply[1usize] = "pong"
        if zmtp.send_message(&rep, reply[0usize..2usize]) != ok { ret 136u32 }
        let (n2, e2) = zmtp.recv_message(&req, got[0usize..4usize], &empty_subs)
        let (start2, se2) = zmtp.envelope_body_start(got[0usize..n2])
        if e2 != ok || se2 != ok || !same_bytes(got[start2], "pong") { ret 137u32 }
    }
    // DEALER (identity) / ROUTER: the ROUTER sees the identity first and the auto id when none
    if true {
        let (pair, pe) = connect_pair()
        if pe != ok { ret 140u32 }
        defer let _ = net.close(pair.server)
        defer let _ = net.close(pair.client)
        var dealer = zmtp.conn(pair.client, lb[0usize..8192usize], .Dealer, "worker-1")
        var router = zmtp.conn(pair.server, rb[0usize..8192usize], .Router, "")
        if handshake_pair(&dealer, &router) != 1u32 { ret 141u32 }
        parts[0usize] = "job"
        parts[1usize] = "42"
        if zmtp.send_message(&dealer, parts[0usize..2usize]) != ok { ret 142u32 }
        let (n1, e1) = zmtp.recv_message(&router, got[0usize..4usize], &empty_subs)
        if e1 != ok || n1 != 2usize { ret 143u32 }
        var auto: [5]u8 = zero
        var routed: [4][]const u8 = zero
        let (rn, re) = zmtp.router_prefix(&router, 7u32, auto[0usize..5usize], got[0usize..n1], routed[0usize..4usize])
        if re != ok || rn != 3usize || !same_bytes(routed[0usize], "worker-1") || !same_bytes(routed[1usize], "job") { ret 144u32 }
        // an anonymous peer is given the five-byte id: zero byte then the big-endian counter
        var anon_l: [8192]u8 = zero
        var anon_r: [8192]u8 = zero
        let (pair2, pe2) = connect_pair()
        if pe2 != ok { ret 145u32 }
        defer let _ = net.close(pair2.server)
        defer let _ = net.close(pair2.client)
        var dealer2 = zmtp.conn(pair2.client, anon_l[0usize..8192usize], .Dealer, "")
        var router2 = zmtp.conn(pair2.server, anon_r[0usize..8192usize], .Router, "")
        if handshake_pair(&dealer2, &router2) != 1u32 { ret 146u32 }
        let (an, ae) = zmtp.router_prefix(&router2, 258u32, auto[0usize..5usize], got[0usize..1usize], routed[0usize..4usize])
        if ae != ok || routed[0usize].len != 5usize || routed[0usize][0usize] != 0u8 || routed[0usize][3usize] != 1u8 || routed[0usize][4usize] != 2u8 { ret 147u32 }
        // the router answers: dealer receives only the data frames
        parts[0usize] = "done"
        if zmtp.send_message(&router, parts[0usize..1usize]) != ok { ret 148u32 }
        let (n3, e3) = zmtp.recv_message(&dealer, got[0usize..4usize], &empty_subs)
        if e3 != ok || n3 != 1usize || !same_bytes(got[0usize], "done") { ret 149u32 }
    }
    // incompatible socket types are refused at the handshake
    if true {
        let (pair, pe) = connect_pair()
        if pe != ok { ret 150u32 }
        defer let _ = net.close(pair.server)
        defer let _ = net.close(pair.client)
        var push = zmtp.conn(pair.client, lb[0usize..8192usize], .Push, "")
        var pub = zmtp.conn(pair.server, rb[0usize..8192usize], .Pub, "")
        let r = handshake_pair(&push, &pub)
        if r == 1u32 { ret 151u32 }
    }
    ret 0u32
}
'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
''' + DECODE_CALLS + '''
''' + PEER_CALLS + '''
    let pr = patterns(a)
    if pr != 0u32 { os.exit(i32(pr)) }
    try io.print("net zmtp ok")
    ret ok
}
'''

src = ('// e.net.zmtp against libzmq 4.3.5: recorded byte streams of ten socket pairs decode to their description\n'
       '// and rebuild byte for byte; scripted libzmq peers over real TCP check the connection layer (what a\n'
       '// client writes, what it reads back); pattern semantics run between two library connections (D2805).\n'
       '// D stream vectors, P scripted peers. Generated by scripts/gen_zmtp_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.net\nuse e.thread\nuse e.atomic\nuse e.sync\nuse e.time\nuse e.net.zmtp\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + peer_src + '\n' + PATTERNS + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'stream vectors,', len(peer_lines), 'scripted peers')
