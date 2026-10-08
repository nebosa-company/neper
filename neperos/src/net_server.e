// The NeperOS network server (D2247, C117): an EL0 user-mode server that alone holds the virtio-net
// device. Apps never see a frame, a socket address of their own, a key or a certificate: they hold
// two endpoint capabilities (slots 2 and 3 here) and ask for a connection by host name; the server
// resolves it, opens TCP, and for a secure connection runs TLS 1.3 against the bundled trust roots
// with the host name as the name to match, then relays bytes. Entropy for the handshake is fetched
// from the random server over slots 4 (requests out) and 5 (words back). The protocol is netproto.e.
// The lease is taken on the first CONNECT, so a phone with the network off costs nothing to boot.
use e.io
use e.mem
use e.os
use e.net.tls
use virtio
use inet
use tcp
use https
use netproto

const AUX: usize = 548684165120usize
const REQ: usize = 2usize
const REP: usize = 3usize
const RNG_REQ: usize = 4usize
const RNG_REP: usize = 5usize

type Session = struct {
    st: inet.Stack,
    conn: tcp.Conn,
    stream: tls.Stream,
    present: bool,
    leased: bool,
    connected: bool,
    secure: bool,
    mark: usize,
    ring: usize,
    dns_ip: u32,
    dns_port: u16,
    trust: str,
}

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn read_device() -> virtio.Device {
    var device: virtio.Device = zero
    device.common = usize(os.load64(AUX))
    device.notify = usize(os.load64(AUX + 8usize))
    device.notify_multiplier = u32(os.load64(AUX + 16usize))
    virtio.pool_set(usize(os.load64(AUX + 24usize)), usize(os.load64(AUX + 32usize)))
    device.config = usize(os.load64(AUX + 40usize))
    ret device
}

fn reply(result: usize) {
    let sent = os.send(REP, result, netproto.NO_SLOT)
}

// 64 random bytes into `dst`, from the random server.
fn fetch_entropy(dst: usize) {
    let ask = os.send(RNG_REQ, 1usize, netproto.NO_SLOT)
    let count = os.send(RNG_REQ, 8usize, netproto.NO_SLOT)
    var i = 0usize
    while i < 8usize {
        os.store64(dst + i * 8usize, u64(os.recv(RNG_REP, netproto.NO_SLOT)))
        i += 1usize
    }
}

// A dotted-quad address, if `text` is one.
fn parse_ip(text: str) -> (u32, bool) {
    var value = 0u32
    var part = 0u32
    var digits = 0usize
    var parts = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if c >= 48u8 && c <= 57u8 {
            part = part * 10u32 + u32(c - 48u8)
            digits += 1usize
            if part > 255u32 { ret (0u32, false) }
        } else {
            if c != 46u8 || digits == 0usize { ret (0u32, false) }
            value = (value << 8u32) | part
            part = 0u32
            digits = 0usize
            parts += 1usize
        }
        i += 1usize
    }
    if digits == 0usize || parts != 3usize { ret (0u32, false) }
    ret ((value << 8u32) | part, true)
}

// Take the lease on first use.
fn ensure_lease(s: *Session) -> bool {
    if !s.present { ret false }
    if s.leased { ret true }
    if inet.dhcp(&s.st) != ok { ret false }
    s.leased = true
    if s.dns_ip != 0u32 {
        s.st.dns = s.dns_ip
        s.st.dns_port = s.dns_port
    }
    ret true
}

fn teardown(s: *Session, a: *mem.Arena) {
    if s.connected {
        if s.secure {
            let closed = tls.close(&s.stream)
        }
        let tcp_closed = tcp.close(&s.conn)
        mem.reset(a, s.mark)
    }
    s.connected = false
    s.secure = false
}

fn connect(s: *Session, a: *mem.Arena, host: str, port: u16, secure: bool) -> usize {
    if s.connected { ret netproto.R_BUSY }
    if !ensure_lease(s) { ret netproto.R_NO_NETWORK }
    var address = 0u32
    let (literal, is_literal) = parse_ip(host)
    if is_literal {
        address = literal
    } else {
        let (found, resolve_error) = inet.resolve(&s.st, host)
        if resolve_error != ok { ret netproto.R_RESOLVE }
        address = found
    }
    s.mark = mem.mark(a)
    let (conn, connect_error) = tcp.connect(&s.st, address, port, s.ring)
    if connect_error != ok {
        mem.reset(a, s.mark)
        ret netproto.R_CONNECT
    }
    s.conn = conn
    s.connected = true
    if secure {
        var entropy: [64]u8 = zero
        fetch_entropy(mem.address_of(&entropy[0usize]))
        let (stream, tls_error) = https.connect(a, &s.conn, host, s.trust, entropy[0usize..64usize])
        if tls_error != ok {
            let tcp_closed = tcp.close(&s.conn)
            mem.reset(a, s.mark)
            s.connected = false
            ret netproto.R_TLS
        }
        s.stream = stream
        s.secure = true
    }
    ret netproto.R_OK
}

fn main(a: *mem.Arena, args: []str) -> err {
    let device = read_device()
    var s: Session = zero
    let (st, open_error) = inet.attach(device)
    if open_error == ok {
        s.st = st
        s.present = true
    } else {
        say("net server: no network device\n")
    }
    // The trust roots arrive as a mapped archive entry: args[1] the Mozilla set, and args[2], only in the test boots, the fixture root.
    if args.len > 1usize { s.trust = args[1usize] }
    if os.load64(AUX + 56usize) == 1u64 && args.len > 2usize { s.trust = args[2usize] }
    var ring_storage: [65536]u8 = zero
    s.ring = mem.address_of(&ring_storage[0usize])
    var chunk: [2048]u8 = zero
    let chunk_addr = mem.address_of(&chunk[0usize])
    var hostbuf: [256]u8 = zero
    let host_addr = mem.address_of(&hostbuf[0usize])
    say("net server up\n")
    var running = true
    while running {
        let op = os.recv(REQ, netproto.NO_SLOT)
        if op == netproto.OP_QUIT {
            running = false
        } else {
            if op == netproto.OP_SET_DNS {
                let ip_word = os.recv(REQ, netproto.NO_SLOT)
                let port_word = os.recv(REQ, netproto.NO_SLOT)
                s.dns_ip = u32(ip_word)
                s.dns_port = u16(port_word)
                if s.leased {
                    s.st.dns = s.dns_ip
                    s.st.dns_port = s.dns_port
                }
                reply(netproto.R_OK)
            } else {
                if op == netproto.OP_CONNECT {
                    let host_len = netproto.recv_bytes(REQ, host_addr, 255usize)
                    let port_word = os.recv(REQ, netproto.NO_SLOT)
                    let secure_word = os.recv(REQ, netproto.NO_SLOT)
                    reply(connect(&s, a, hostbuf[0usize..host_len], u16(port_word), secure_word != 0usize))
                } else {
                    if op == netproto.OP_SEND {
                        let got = netproto.recv_bytes(REQ, chunk_addr, 2048usize)
                        if !s.connected {
                            reply(netproto.R_NOT_CONNECTED)
                        } else {
                            var failed = false
                            if s.secure {
                                var sink = tls.writer(&s.stream)
                                if io.write_all(&sink, chunk[0usize..got]) != ok { failed = true }
                            } else {
                                if tcp.write(&s.conn, chunk_addr, got) != ok { failed = true }
                            }
                            if failed { reply(netproto.R_IO) } else { reply(netproto.R_OK) }
                        }
                    } else {
                        if op == netproto.OP_RECV {
                            var want = os.recv(REQ, netproto.NO_SLOT)
                            if want > 2048usize { want = 2048usize }
                            if !s.connected {
                                reply(netproto.R_NOT_CONNECTED)
                            } else {
                                var got = 0usize
                                var failed = false
                                if s.secure {
                                    var source = tls.reader(&s.stream)
                                    let (n, read_error) = io.read(&source, chunk[0usize..want])
                                    if read_error == ok { got = n } else { if read_error != io.End { failed = true } }
                                } else {
                                    let (n, read_error) = tcp.read(&s.conn, chunk_addr, want)
                                    if read_error == ok { got = n } else { failed = true }
                                }
                                if failed {
                                    reply(netproto.R_IO)
                                } else {
                                    reply(netproto.R_OK)
                                    netproto.send_bytes(REP, chunk_addr, got)
                                }
                            }
                        } else {
                            if op == netproto.OP_CLOSE {
                                teardown(&s, a)
                                reply(netproto.R_OK)
                            } else {
                                reply(netproto.R_BAD)
                            }
                        }
                    }
                }
            }
        }
    }
    teardown(&s, a)
    // The random server has nothing left to serve either.
    let rng_quit = os.send(RNG_REQ, 0usize, netproto.NO_SLOT)
    ret ok
}
