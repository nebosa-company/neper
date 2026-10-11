// SOCKS5 client (RFC 1928, username/password RFC 1929) over any `io.Reader` / `io.Writer`
// pair. `negotiate` offers "no authentication" and, when a user is given, "username/
// password" and runs the sub-negotiation; `connect_domain` and `connect_address` send
// CONNECT, `bind_address` BIND (the second reply is `read_reply` again) and
// `udp_associate` UDP ASSOCIATE, each answering the server's `Reply` -- a non-zero reply
// code is `Rejected` with the reply (code and bound address) still returned. `dial` and
// `udp_open` do the connecting over e.net sockets. UDP datagrams to and from the relay
// carry the RFC 1928 section 7 header, built by `udp_encode` and read by `udp_decode`.
// A domain name is a length byte then at most 255 bytes, so a longer host is `Invalid`
// before anything is written; user and password are 255 bytes at most. Reads are exact
// and sized by the protocol (no read-ahead), so a transport carries on past the reply
// untouched. No GSSAPI (method 1), no fragment reassembly (a datagram with a non-zero
// FRAG is reported, not joined), no server side.

use e.io
use e.net

type Reply = struct { code: u8, atyp: u8, address: net.Address, name: [255]u8, name_len: usize, port: u16 }
type Datagram = struct { fragment: u8, atyp: u8, address: net.Address, name: [255]u8, name_len: usize, port: u16, payload: usize }

error Protocol
error Rejected
error Unsupported
error AuthFailed
error Invalid
error Closed
error TooSmall

const VERSION: u8 = 5u8
const CMD_CONNECT: u8 = 1u8
const CMD_BIND: u8 = 2u8
const CMD_UDP_ASSOCIATE: u8 = 3u8
const ATYP_IPV4: u8 = 1u8
const ATYP_DOMAIN: u8 = 3u8
const ATYP_IPV6: u8 = 4u8
const METHOD_NONE: u8 = 0u8
const METHOD_PASSWORD: u8 = 2u8
const METHOD_REFUSED: u8 = 255u8

fn no_address() -> net.Address { ret net.Address{ Ip4: net.Ip4{ bytes: [4]u8{ 0u8, 0u8, 0u8, 0u8 } } } }

fn empty_reply() -> Reply {
    var r: Reply = zero
    r.address = no_address()
    ret r
}

// RFC 1928 section 6, by reply code.
fn reply_text(code: u8) -> str {
    if code == 0u8 { ret "succeeded" }
    if code == 1u8 { ret "general SOCKS server failure" }
    if code == 2u8 { ret "connection not allowed by ruleset" }
    if code == 3u8 { ret "network unreachable" }
    if code == 4u8 { ret "host unreachable" }
    if code == 5u8 { ret "connection refused" }
    if code == 6u8 { ret "TTL expired" }
    if code == 7u8 { ret "command not supported" }
    if code == 8u8 { ret "address type not supported" }
    ret "unassigned"
}

fn read_bytes(source: *io.Reader, dst: []u8) -> err {
    let failure = io.read_exact(source, dst)
    if failure == io.End { ret Closed }
    ret failure
}

// Offers the methods and, for method 2, runs RFC 1929; `user` empty means no credentials.
fn negotiate(source: *io.Reader, sink: *io.Writer, user: str, password: str) -> err {
    if user.len > 255usize || password.len > 255usize { ret Invalid }
    var greeting: [4]u8 = zero
    greeting[0] = VERSION
    var length = 3usize
    if user.len == 0usize {
        greeting[1] = 1u8
        greeting[2] = METHOD_NONE
    } else {
        greeting[1] = 2u8
        greeting[2] = METHOD_NONE
        greeting[3] = METHOD_PASSWORD
        length = 4usize
    }
    let sent = io.write_all(sink, greeting[..length])
    if sent != ok { ret sent }
    var choice: [2]u8 = zero
    let got = read_bytes(source, choice[0..])
    if got != ok { ret got }
    if choice[0] != VERSION { ret Protocol }
    if choice[1] == METHOD_REFUSED { ret Unsupported }
    if choice[1] == METHOD_NONE { ret ok }
    if choice[1] != METHOD_PASSWORD { ret Protocol }
    if user.len == 0usize { ret AuthFailed }
    var request: [515]u8 = zero
    request[0] = 1u8
    request[1] = u8(user.len)
    var at = 2usize
    var i = 0usize
    while i < user.len {
        request[at] = user[i]
        at += 1usize
        i += 1usize
    }
    request[at] = u8(password.len)
    at += 1usize
    i = 0usize
    while i < password.len {
        request[at] = password[i]
        at += 1usize
        i += 1usize
    }
    let sent_credentials = io.write_all(sink, request[..at])
    if sent_credentials != ok { ret sent_credentials }
    let status_read = read_bytes(source, choice[0..])
    if status_read != ok { ret status_read }
    if choice[0] != 1u8 { ret Protocol }
    if choice[1] != 0u8 { ret AuthFailed }
    ret ok
}

fn put_port(buf: []u8, at: usize, port: u16) {
    buf[at] = u8(port >> 8u32)
    buf[at + 1usize] = u8(port & 255u16)
}

fn send_request(sink: *io.Writer, cmd: u8, atyp: u8, host: []const u8, port: u16) -> err {
    var request: [262]u8 = zero
    request[0] = VERSION
    request[1] = cmd
    request[2] = 0u8
    request[3] = atyp
    var at = 4usize
    if atyp == ATYP_DOMAIN {
        request[at] = u8(host.len)
        at += 1usize
    }
    var i = 0usize
    while i < host.len {
        request[at] = host[i]
        at += 1usize
        i += 1usize
    }
    put_port(request[0..], at, port)
    at += 2usize
    ret io.write_all(sink, request[..at])
}

fn address_atyp(address: net.Address, bytes: []u8) -> (u8, usize) {
    let n = net.address_bytes(address, bytes)
    if n == 4usize { ret (ATYP_IPV4, n) }
    ret (ATYP_IPV6, n)
}

// One reply: VER REP RSV ATYP BND.ADDR BND.PORT. A non-zero REP is `Rejected` at once with
// `code` set (the proxy closes after a refusal, so the rest is not read).
fn read_reply(source: *io.Reader) -> (Reply, err) {
    var reply = empty_reply()
    var head: [4]u8 = zero
    let head_read = read_bytes(source, head[0..])
    if head_read != ok { ret (reply, head_read) }
    if head[0] != VERSION { ret (reply, Protocol) }
    reply.code = head[1]
    reply.atyp = head[3]
    if head[1] != 0u8 { ret (reply, Rejected) }
    if head[3] == ATYP_IPV4 {
        var four: [4]u8 = zero
        let got = read_bytes(source, four[0..])
        if got != ok { ret (reply, got) }
        reply.address = net.Address{ Ip4: net.Ip4{ bytes: four } }
    } else if head[3] == ATYP_IPV6 {
        var six: [16]u8 = zero
        let got = read_bytes(source, six[0..])
        if got != ok { ret (reply, got) }
        reply.address = net.Address{ Ip6: net.Ip6{ bytes: six, scope: 0u32 } }
    } else if head[3] == ATYP_DOMAIN {
        var count: [1]u8 = zero
        let count_read = read_bytes(source, count[0..])
        if count_read != ok { ret (reply, count_read) }
        reply.name_len = usize(count[0])
        let name_read = read_bytes(source, reply.name[..reply.name_len])
        if name_read != ok { ret (reply, name_read) }
    } else {
        ret (reply, Protocol)
    }
    var port: [2]u8 = zero
    let port_read = read_bytes(source, port[0..])
    if port_read != ok { ret (reply, port_read) }
    reply.port = (u16(port[0]) << 8u32) | u16(port[1])
    ret (reply, ok)
}

fn command_domain(source: *io.Reader, sink: *io.Writer, cmd: u8, host: str, port: u16) -> (Reply, err) {
    if host.len == 0usize || host.len > 255usize { ret (empty_reply(), Invalid) }
    let sent = send_request(sink, cmd, ATYP_DOMAIN, host, port)
    if sent != ok { ret (empty_reply(), sent) }
    let (reply, failure) = read_reply(source)
    ret (reply, failure)
}

fn command_address(source: *io.Reader, sink: *io.Writer, cmd: u8, address: net.Address, port: u16) -> (Reply, err) {
    var bytes: [16]u8 = zero
    let (atyp, n) = address_atyp(address, bytes[0..])
    let sent = send_request(sink, cmd, atyp, bytes[..n], port)
    if sent != ok { ret (empty_reply(), sent) }
    let (reply, failure) = read_reply(source)
    ret (reply, failure)
}

// CONNECT to a name the proxy resolves.
fn connect_domain(source: *io.Reader, sink: *io.Writer, host: str, port: u16) -> (Reply, err) {
    let (reply, failure) = command_domain(source, sink, CMD_CONNECT, host, port)
    ret (reply, failure)
}

fn connect_address(source: *io.Reader, sink: *io.Writer, address: net.Address, port: u16) -> (Reply, err) {
    let (reply, failure) = command_address(source, sink, CMD_CONNECT, address, port)
    ret (reply, failure)
}

// BIND: the first reply names the proxy's listening endpoint, the second (`read_reply`)
// the peer that connected to it.
fn bind_address(source: *io.Reader, sink: *io.Writer, address: net.Address, port: u16) -> (Reply, err) {
    let (reply, failure) = command_address(source, sink, CMD_BIND, address, port)
    ret (reply, failure)
}

// UDP ASSOCIATE; `address` and `port` are where the client will send from (all zeros when
// unknown). The reply names the relay's UDP endpoint; the association lasts as long as
// this TCP connection.
fn udp_associate(source: *io.Reader, sink: *io.Writer, address: net.Address, port: u16) -> (Reply, err) {
    let (reply, failure) = command_address(source, sink, CMD_UDP_ASSOCIATE, address, port)
    ret (reply, failure)
}

// The relay endpoint of a UDP ASSOCIATE reply; a relay that answers 0.0.0.0 or :: is the
// proxy's own address, which the caller substitutes (`proxy`).
fn relay_endpoint(reply: Reply, proxy: net.Address) -> (net.Endpoint, bool) {
    if reply.atyp == ATYP_DOMAIN { ret (net.Endpoint { address: proxy, port: reply.port }, false) }
    var bytes: [16]u8 = zero
    let n = net.address_bytes(reply.address, bytes[0..])
    var zeros = true
    var i = 0usize
    while i < n {
        if bytes[i] != 0u8 { zeros = false }
        i += 1usize
    }
    if zeros { ret (net.Endpoint { address: proxy, port: reply.port }, true) }
    ret (net.Endpoint { address: reply.address, port: reply.port }, true)
}

fn establish(connection: *net.Socket, user: str, password: str, host: str, port: u16, udp: bool) -> (Reply, err) {
    var source = net.reader(connection)
    var sink = net.writer(connection)
    let negotiated = negotiate(&source, &sink, user, password)
    if negotiated != ok { ret (empty_reply(), negotiated) }
    if udp {
        let (reply, failure) = udp_associate(&source, &sink, no_address(), 0u16)
        ret (reply, failure)
    }
    let (reply, failure) = connect_domain(&source, &sink, host, port)
    ret (reply, failure)
}

// Connects to the proxy, negotiates and CONNECTs to `host:port`; the returned socket is
// the tunnel. A failure closes the socket.
fn dial(proxy: net.Endpoint, user: str, password: str, host: str, port: u16) -> (net.Socket, Reply, err) {
    let (opened, connect_error) = net.tcp_connect(proxy)
    if connect_error != ok { ret (opened, empty_reply(), connect_error) }
    var connection = opened
    let (reply, failure) = establish(&connection, user, password, host, port, false)
    if failure != ok {
        let _ = net.close(connection)
        var none: net.Socket = zero
        ret (none, reply, failure)
    }
    ret (connection, reply, ok)
}

// Connects to the proxy, negotiates and asks for a UDP association from an unspecified
// client address; the returned TCP socket must stay open for the association's life and
// `relay_endpoint` of the reply says where datagrams go.
fn dial_udp(proxy: net.Endpoint, user: str, password: str) -> (net.Socket, Reply, err) {
    let (opened, connect_error) = net.tcp_connect(proxy)
    if connect_error != ok { ret (opened, empty_reply(), connect_error) }
    var connection = opened
    let (reply, failure) = establish(&connection, user, password, "", 0u16, true)
    if failure != ok {
        let _ = net.close(connection)
        var none: net.Socket = zero
        ret (none, reply, failure)
    }
    ret (connection, reply, ok)
}

// The datagram header (RSV RSV FRAG ATYP DST.ADDR DST.PORT) and `payload`, for a name.
fn udp_encode_domain(out: []u8, host: str, port: u16, payload: []const u8) -> (usize, err) {
    if host.len == 0usize || host.len > 255usize { ret (0usize, Invalid) }
    let need = 7usize + host.len + payload.len
    if out.len < need { ret (0usize, TooSmall) }
    out[0] = 0u8
    out[1] = 0u8
    out[2] = 0u8
    out[3] = ATYP_DOMAIN
    out[4] = u8(host.len)
    var at = 5usize
    var i = 0usize
    while i < host.len {
        out[at] = host[i]
        at += 1usize
        i += 1usize
    }
    put_port(out, at, port)
    at += 2usize
    i = 0usize
    while i < payload.len {
        out[at] = payload[i]
        at += 1usize
        i += 1usize
    }
    ret (at, ok)
}

fn udp_encode(out: []u8, address: net.Address, port: u16, payload: []const u8) -> (usize, err) {
    var bytes: [16]u8 = zero
    let (atyp, n) = address_atyp(address, bytes[0..])
    let need = 6usize + n + payload.len
    if out.len < need { ret (0usize, TooSmall) }
    out[0] = 0u8
    out[1] = 0u8
    out[2] = 0u8
    out[3] = atyp
    var at = 4usize
    var i = 0usize
    while i < n {
        out[at] = bytes[i]
        at += 1usize
        i += 1usize
    }
    put_port(out, at, port)
    at += 2usize
    i = 0usize
    while i < payload.len {
        out[at] = payload[i]
        at += 1usize
        i += 1usize
    }
    ret (at, ok)
}

fn empty_datagram() -> Datagram {
    var d: Datagram = zero
    d.address = no_address()
    ret d
}

// Reads the header of a relayed datagram; `payload` is the offset of the user data.
// `Protocol` for a reserved field that is not zero, an unknown address type or a header
// that runs past the datagram.
fn udp_decode(datagram: []const u8) -> (Datagram, err) {
    var d = empty_datagram()
    if datagram.len < 4usize { ret (d, Protocol) }
    if datagram[0] != 0u8 || datagram[1] != 0u8 { ret (d, Protocol) }
    d.fragment = datagram[2]
    d.atyp = datagram[3]
    var at = 4usize
    if d.atyp == ATYP_IPV4 {
        if datagram.len < at + 6usize { ret (d, Protocol) }
        var four: [4]u8 = zero
        var i = 0usize
        while i < 4usize {
            four[i] = datagram[at + i]
            i += 1usize
        }
        d.address = net.Address{ Ip4: net.Ip4{ bytes: four } }
        at += 4usize
    } else if d.atyp == ATYP_IPV6 {
        if datagram.len < at + 18usize { ret (d, Protocol) }
        var six: [16]u8 = zero
        var i = 0usize
        while i < 16usize {
            six[i] = datagram[at + i]
            i += 1usize
        }
        d.address = net.Address{ Ip6: net.Ip6{ bytes: six, scope: 0u32 } }
        at += 16usize
    } else if d.atyp == ATYP_DOMAIN {
        if datagram.len < at + 1usize { ret (d, Protocol) }
        let n = usize(datagram[at])
        at += 1usize
        if datagram.len < at + n + 2usize { ret (d, Protocol) }
        var i = 0usize
        while i < n {
            d.name[i] = datagram[at + i]
            i += 1usize
        }
        d.name_len = n
        at += n
    } else {
        ret (d, Protocol)
    }
    d.port = (u16(datagram[at]) << 8u32) | u16(datagram[at + 1usize])
    d.payload = at + 2usize
    ret (d, ok)
}
