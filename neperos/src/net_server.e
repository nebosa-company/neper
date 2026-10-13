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
    test: bool,
    // (C171) Plaintext the secure stream gave up that the app has not taken yet: a poll reads a whole TLS record into
    // `hold` (the stream cannot say how much it still has buffered, so every read takes all of a record) and hands it
    // out in pieces of the size asked for.
    hold: [16384]u8,
    hold_at: usize,
    hold_len: usize,
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
    s.hold_at = 0usize
    s.hold_len = 0usize
}

fn connect(s: *Session, a: *mem.Arena, host: str, port: u16, secure: bool) -> usize {
    if s.connected { ret netproto.R_BUSY }
    if !radio_on { ret netproto.R_NO_NETWORK }
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
    var dial_port = port
    if s.test && port == 443u16 { dial_port = 8443u16 }
    let (conn, connect_error) = tcp.connect(&s.st, address, dial_port, s.ring)
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

// (C126) What the machine hears. There is no radio on this machine's network device: it has one wired link, which
// is listed as "Ethernet" and is always the connection to fall back on. The test boots add a recorded air, the way
// they record DNS and the API hosts, so the Settings app's scan, password sheet and join can be exercised: three
// networks, two of them secured. A real radio driver would put its scan results in this list.
fn air_name(index: usize) -> str {
    if index == 1usize { ret "Neper-Lab" }
    if index == 2usize { ret "Cafe-Free" }
    if index == 3usize { ret "Neighbour-5G" }
    ret "Ethernet"
}

fn air_secured(index: usize) -> usize {
    if index == 1usize || index == 3usize { ret 1usize }
    ret 0usize
}

fn air_signal(index: usize) -> usize {
    if index == 1usize { ret 82usize }
    if index == 2usize { ret 61usize }
    if index == 3usize { ret 34usize }
    ret 100usize
}

fn air_password(index: usize) -> str {
    if index == 1usize { ret "neperlab1" }
    ret "wallhugger"
}

// Whether the radios may carry traffic (the settings server's word: Airplane mode and the Wi-Fi and Mobile switches).
var radio_on: bool = true

// (C176) The Bluetooth and Hotspot links, as the settings server last asked (its word is already gated by Airplane
// mode). Bluetooth needs no uplink; a hotspot shares one, so it is up only while the radios may carry traffic.
var bt_wanted: bool = true
var hotspot_wanted: bool = false

fn bt_up() -> bool {
    ret bt_wanted
}

fn hotspot_up() -> bool {
    ret hotspot_wanted && radio_on
}

// The hotspot: 0 down, 1 asked for and waiting for an uplink, 2 up.
fn hotspot_state() -> usize {
    if !hotspot_wanted { ret 0usize }
    if radio_on { ret 2usize }
    ret 1usize
}

// Say what changed in the links since `was_bt` and the hotspot state `was_hotspot`.
fn link_report(was_bt: bool, was_hotspot: usize) {
    if bt_up() != was_bt {
        if bt_up() { say("net server bluetooth up\n") } else { say("net server bluetooth down\n") }
    }
    let now = hotspot_state()
    if now != was_hotspot {
        if now == 2usize { say("net server hotspot up\n") } else if now == 1usize { say("net server hotspot waiting\n") } else { say("net server hotspot down\n") }
    }
}

fn air_count(s: *Session) -> usize {
    if !radio_on { ret 0usize }
    if s.test { ret 4usize }
    if s.present { ret 1usize }
    ret 0usize
}

// The network joined since boot ("" none: the wired link is the connection), in a buffer of its own.
var joined_text: [32]u8 = zero
var joined_len: usize = 0usize

fn named(text: str, bytes: []u8) -> bool {
    if text.len != bytes.len { ret false }
    var i = 0usize
    while i < text.len {
        if text[i] != bytes[i] { ret false }
        i += 1usize
    }
    ret true
}

fn joined_is(index: usize) -> bool {
    if joined_len == 0usize { ret index == 0usize }
    ret named(air_name(index), joined_text[0usize..joined_len])
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
    if os.load64(AUX + 56usize) == 1u64 {
        // The test boots: the fixture root in place of the Mozilla set, the host's DNS responder (10.0.2.2:5300) as the
        // default resolver, and port 443 dialled as 8443, so a fixture can serve recorded API replies unprivileged.
        s.test = true
        s.dns_ip = 167772674u32
        s.dns_port = 5300u16
        if args.len > 2usize { s.trust = args[2usize] }
    }
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
        } else if op == netproto.OP_RADIO {
            let flag = os.recv(REQ, netproto.NO_SLOT)
            let was_hotspot_state = hotspot_state()
            radio_on = flag != 0usize
            if radio_on { say("net server radio on\n") } else { say("net server radio off\n") }
            link_report(bt_up(), was_hotspot_state)
            reply(netproto.R_OK)
        } else if op == netproto.OP_LINKS {
            let mask = os.recv(REQ, netproto.NO_SLOT)
            let was_bt = bt_up()
            let was_state = hotspot_state()
            bt_wanted = (mask & 1usize) != 0usize
            hotspot_wanted = (mask & 2usize) != 0usize
            link_report(was_bt, was_state)
            reply(netproto.R_OK)
        } else if op == netproto.OP_LINK_STATE {
            reply(netproto.R_OK)
            var state = 0usize
            if radio_on { state = state | 1usize }
            if bt_up() { state = state | 2usize }
            if hotspot_state() == 2usize { state = state | 4usize }
            if hotspot_state() == 1usize { state = state | 8usize }
            let state_sent = os.send(REP, state, netproto.NO_SLOT)
            // (The test boots record one station on the hotspot and two bonded devices; a real link layer counts.)
            var stations = 0usize
            if s.test && hotspot_state() == 2usize { stations = 1usize }
            let stations_sent = os.send(REP, stations, netproto.NO_SLOT)
            var bonded = 0usize
            if s.test && bt_up() { bonded = 2usize }
            let bonded_sent = os.send(REP, bonded, netproto.NO_SLOT)
        } else if op == netproto.OP_BT_SCAN {
            reply(netproto.R_OK)
            var heard = 0usize
            if s.test && bt_up() { heard = 2usize }
            let heard_sent = os.send(REP, heard, netproto.NO_SLOT)
            var d = 0usize
            while d < heard {
                var device_name = "Neper Buds"
                var strength = 71usize
                if d != 0usize {
                    device_name = "Lab Car Kit"
                    strength = 48usize
                }
                netproto.send_text(REP, device_name)
                let strength_sent = os.send(REP, strength, netproto.NO_SLOT)
                d += 1usize
            }
        } else if op == netproto.OP_SCAN {
            reply(netproto.R_OK)
            let count = air_count(&s)
            let count_sent = os.send(REP, count, netproto.NO_SLOT)
            var i = 0usize
            while i < count {
                netproto.send_text(REP, air_name(i))
                let secured_sent = os.send(REP, air_secured(i), netproto.NO_SLOT)
                let signal_sent = os.send(REP, air_signal(i), netproto.NO_SLOT)
                var flags = 0usize
                if joined_is(i) { flags = 3usize }
                if i == 0usize && joined_len != 0usize { flags = 0usize }
                let flags_sent = os.send(REP, flags, netproto.NO_SLOT)
                i += 1usize
            }
        } else if op == netproto.OP_JOIN {
            let name_len = netproto.recv_bytes(REQ, host_addr, 255usize)
            let password_len = netproto.recv_bytes(REQ, chunk_addr, 64usize)
            var found = 99usize
            var i = 0usize
            while i < air_count(&s) {
                if named(air_name(i), hostbuf[0usize..name_len]) { found = i }
                i += 1usize
            }
            if found == 99usize {
                reply(netproto.R_NO_NETWORK)
            } else if found == 0usize {
                joined_len = 0usize
                reply(netproto.R_OK)
            } else if air_secured(found) != 0usize && !named(air_password(found), chunk[0usize..password_len]) {
                reply(netproto.R_AUTH)
            } else {
                var k = 0usize
                while k < name_len && k < 32usize {
                    joined_text[k] = hostbuf[k]
                    k += 1usize
                }
                joined_len = k
                reply(netproto.R_OK)
            }
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
                    } else if op == netproto.OP_POLL {
                        var want = os.recv(REQ, netproto.NO_SLOT)
                        if want > 2048usize { want = 2048usize }
                        if !s.connected {
                            reply(netproto.R_NOT_CONNECTED)
                        } else if s.secure {
                            // (C171) A poll of a TLS stream: what the last record left, else wait a moment for the
                            // transport and read one whole record; nothing yet is R_EMPTY, the peer's close is an
                            // empty answer, like a recv's.
                            var failed = false
                            var closed = false
                            if s.hold_at == s.hold_len {
                                s.hold_at = 0usize
                                s.hold_len = 0usize
                                var spins = 0usize
                                while s.conn.count == 0usize && !s.conn.peer_fin && !s.conn.reset && spins < 20000usize {
                                    tcp.pump(&s.conn)
                                    spins += 1usize
                                }
                                if s.conn.count > 0usize || s.conn.peer_fin || s.conn.reset {
                                    var source = tls.reader(&s.stream)
                                    let (n, read_error) = io.read(&source, s.hold[0usize..16384usize])
                                    if read_error == ok {
                                        s.hold_len = n
                                    } else if read_error == io.End {
                                        closed = true
                                    } else {
                                        failed = true
                                    }
                                }
                            }
                            if failed {
                                reply(netproto.R_IO)
                            } else if s.hold_at < s.hold_len {
                                var n = s.hold_len - s.hold_at
                                if n > want { n = want }
                                reply(netproto.R_OK)
                                netproto.send_bytes(REP, mem.address_of(&s.hold[s.hold_at]), n)
                                s.hold_at += n
                            } else if closed {
                                reply(netproto.R_OK)
                                netproto.send_bytes(REP, chunk_addr, 0usize)
                            } else {
                                reply(netproto.R_EMPTY)
                            }
                        } else {
                            let (n, read_error) = tcp.read_for(&s.conn, chunk_addr, want, 20000usize)
                            if read_error == ok {
                                reply(netproto.R_OK)
                                netproto.send_bytes(REP, chunk_addr, n)
                            } else if s.conn.reset {
                                reply(netproto.R_IO)
                            } else {
                                reply(netproto.R_EMPTY)
                            }
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
                                if s.secure && s.hold_at < s.hold_len {
                                    // (C171) What a poll read and the app has not taken.
                                    got = s.hold_len - s.hold_at
                                    if got > want { got = want }
                                    var k = 0usize
                                    while k < got {
                                        chunk[k] = s.hold[s.hold_at + k]
                                        k += 1usize
                                    }
                                    s.hold_at += got
                                } else if s.secure {
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
