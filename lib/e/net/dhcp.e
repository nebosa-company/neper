// DHCP messages (RFC 2131, options RFC 2132) as bytes: `encode` writes a BOOTP message with the magic cookie
// and the options a client and a server of a plain lease use; `decode` reads one back. The client's side
// of the exchange is `discover` and `request` (each a `Message` ready to encode); the lease a server
// offers or acknowledges is in the decoded message's `yiaddr` and options. Options understood: 1 subnet
// mask, 3 routers (the first), 6 DNS servers (up to four), 12 host name, 50 requested address, 51 lease
// time, 53 message type, 54 server identifier, 55 parameter request list and 61 client identifier on the
// way out; any other option is skipped by its length. A message is padded to 300 bytes, the BOOTP
// minimum some relays insist on. No socket here: the caller sends the bytes over UDP 68 to 67.

error Truncated
error BadMagic
error BadOption
error TooSmall

const OP_REQUEST: u8 = 1u8
const OP_REPLY: u8 = 2u8
const DISCOVER: u8 = 1u8
const OFFER: u8 = 2u8
const REQUEST: u8 = 3u8
const DECLINE: u8 = 4u8
const ACK: u8 = 5u8
const NAK: u8 = 6u8
const RELEASE: u8 = 7u8
const INFORM: u8 = 8u8
const FIXED: usize = 236usize
const MIN_SIZE: usize = 300usize

type Message = struct {
    op: u8,
    htype: u8,
    hlen: u8,
    hops: u8,
    xid: u32,
    secs: u16,
    flags: u16,
    ciaddr: [4]u8,
    yiaddr: [4]u8,
    siaddr: [4]u8,
    giaddr: [4]u8,
    chaddr: [16]u8,
    message_type: u8,
    server_id: [4]u8,
    has_server_id: bool,
    requested_ip: [4]u8,
    has_requested_ip: bool,
    lease_seconds: u32,
    has_lease: bool,
    subnet_mask: [4]u8,
    has_subnet: bool,
    router: [4]u8,
    has_router: bool,
    dns: [16]u8,
    dns_count: usize,
    hostname: [64]u8,
    hostname_len: usize,
    client_id: [17]u8,
    client_id_len: usize,
}

fn put32(out: []u8, at: usize, value: u32) {
    out[at] = u8((value >> 24u32) & 255u32)
    out[at + 1usize] = u8((value >> 16u32) & 255u32)
    out[at + 2usize] = u8((value >> 8u32) & 255u32)
    out[at + 3usize] = u8(value & 255u32)
}

fn get32(data: []const u8, at: usize) -> u32 {
    ret (u32(data[at]) << 24u32) | (u32(data[at + 1usize]) << 16u32) | (u32(data[at + 2usize]) << 8u32) | u32(data[at + 3usize])
}

fn copy4(from: []const u8, at: usize, to: []u8) {
    var i = 0usize
    while i < 4usize {
        to[i] = from[at + i]
        i += 1usize
    }
}

// A client message of `kind` from hardware address `mac` with transaction `xid`.
fn client_message(mac: [6]u8, xid: u32, kind: u8) -> Message {
    var m: Message = zero
    m.op = OP_REQUEST
    m.htype = 1u8
    m.hlen = 6u8
    m.xid = xid
    m.flags = 32768u16
    var i = 0usize
    while i < 6usize {
        m.chaddr[i] = mac[i]
        i += 1usize
    }
    m.message_type = kind
    m.client_id[0usize] = 1u8
    i = 0usize
    while i < 6usize {
        m.client_id[1usize + i] = mac[i]
        i += 1usize
    }
    m.client_id_len = 7usize
    ret m
}

fn discover(mac: [6]u8, xid: u32) -> Message {
    ret client_message(mac, xid, DISCOVER)
}

// A REQUEST selecting `requested` offered by `server`.
fn request(mac: [6]u8, xid: u32, requested: [4]u8, server: [4]u8) -> Message {
    var m = client_message(mac, xid, REQUEST)
    m.requested_ip = requested
    m.has_requested_ip = true
    m.server_id = server
    m.has_server_id = true
    ret m
}

fn put_option(out: []u8, at: usize, code: u8, body: []const u8) -> usize {
    out[at] = code
    out[at + 1usize] = u8(body.len)
    var i = 0usize
    while i < body.len {
        out[at + 2usize + i] = body[i]
        i += 1usize
    }
    ret at + 2usize + body.len
}

// The message as bytes into `out` (at least 300): the length, or TooSmall.
fn encode(m: *Message, out: []u8) -> (usize, err) {
    if out.len < MIN_SIZE { ret (0usize, TooSmall) }
    var i = 0usize
    while i < MIN_SIZE {
        out[i] = 0u8
        i += 1usize
    }
    out[0usize] = m.op
    out[1usize] = m.htype
    out[2usize] = m.hlen
    out[3usize] = m.hops
    put32(out, 4usize, m.xid)
    out[8usize] = u8(m.secs >> 8u16)
    out[9usize] = u8(m.secs & 255u16)
    out[10usize] = u8(m.flags >> 8u16)
    out[11usize] = u8(m.flags & 255u16)
    i = 0usize
    while i < 4usize {
        out[12usize + i] = m.ciaddr[i]
        out[16usize + i] = m.yiaddr[i]
        out[20usize + i] = m.siaddr[i]
        out[24usize + i] = m.giaddr[i]
        i += 1usize
    }
    i = 0usize
    while i < 16usize {
        out[28usize + i] = m.chaddr[i]
        i += 1usize
    }
    out[FIXED] = 99u8
    out[FIXED + 1usize] = 130u8
    out[FIXED + 2usize] = 83u8
    out[FIXED + 3usize] = 99u8
    var at = FIXED + 4usize
    if m.message_type != 0u8 {
        let kind: [1]u8 = [1]u8{ m.message_type }
        at = put_option(out, at, 53u8, kind[0..])
    }
    if m.client_id_len > 0usize { at = put_option(out, at, 61u8, m.client_id[0usize..m.client_id_len]) }
    if m.has_requested_ip { at = put_option(out, at, 50u8, m.requested_ip[0..]) }
    if m.has_server_id { at = put_option(out, at, 54u8, m.server_id[0..]) }
    if m.hostname_len > 0usize { at = put_option(out, at, 12u8, m.hostname[0usize..m.hostname_len]) }
    if m.has_lease {
        var lease: [4]u8 = zero
        put32(lease[0..], 0usize, m.lease_seconds)
        at = put_option(out, at, 51u8, lease[0..])
    }
    if m.has_subnet { at = put_option(out, at, 1u8, m.subnet_mask[0..]) }
    if m.has_router { at = put_option(out, at, 3u8, m.router[0..]) }
    if m.dns_count > 0usize { at = put_option(out, at, 6u8, m.dns[0usize..m.dns_count * 4usize]) }
    if m.op == OP_REQUEST && (m.message_type == DISCOVER || m.message_type == REQUEST) {
        let wanted: [4]u8 = [4]u8{ 1u8, 3u8, 6u8, 51u8 }
        at = put_option(out, at, 55u8, wanted[0..])
    }
    out[at] = 255u8
    at += 1usize
    if at < MIN_SIZE { at = MIN_SIZE }
    ret (at, ok)
}

// Read a message from `data`: Truncated when it is shorter than the fixed header, BadMagic without the cookie,
// BadOption when an option's length runs past the end.
fn decode(data: []const u8) -> (Message, err) {
    var m: Message = zero
    if data.len < FIXED + 4usize { ret (m, Truncated) }
    if data[FIXED] != 99u8 || data[FIXED + 1usize] != 130u8 || data[FIXED + 2usize] != 83u8 || data[FIXED + 3usize] != 99u8 { ret (m, BadMagic) }
    m.op = data[0usize]
    m.htype = data[1usize]
    m.hlen = data[2usize]
    m.hops = data[3usize]
    m.xid = get32(data, 4usize)
    m.secs = (u16(data[8usize]) << 8u16) | u16(data[9usize])
    m.flags = (u16(data[10usize]) << 8u16) | u16(data[11usize])
    copy4(data, 12usize, m.ciaddr[0..])
    copy4(data, 16usize, m.yiaddr[0..])
    copy4(data, 20usize, m.siaddr[0..])
    copy4(data, 24usize, m.giaddr[0..])
    var i = 0usize
    while i < 16usize {
        m.chaddr[i] = data[28usize + i]
        i += 1usize
    }
    var at = FIXED + 4usize
    var done = false
    while at < data.len && !done {
        let code = data[at]
        if code == 255u8 {
            done = true
        } else if code == 0u8 {
            at += 1usize
        } else {
            if at + 1usize >= data.len { ret (m, BadOption) }
            let length = usize(data[at + 1usize])
            if at + 2usize + length > data.len { ret (m, BadOption) }
            let body = at + 2usize
            if code == 53u8 && length == 1usize { m.message_type = data[body] }
            if code == 54u8 && length == 4usize {
                copy4(data, body, m.server_id[0..])
                m.has_server_id = true
            }
            if code == 50u8 && length == 4usize {
                copy4(data, body, m.requested_ip[0..])
                m.has_requested_ip = true
            }
            if code == 51u8 && length == 4usize {
                m.lease_seconds = get32(data, body)
                m.has_lease = true
            }
            if code == 1u8 && length == 4usize {
                copy4(data, body, m.subnet_mask[0..])
                m.has_subnet = true
            }
            if code == 3u8 && length >= 4usize {
                copy4(data, body, m.router[0..])
                m.has_router = true
            }
            if code == 6u8 && length >= 4usize {
                var count = length / 4usize
                if count > 4usize { count = 4usize }
                var k = 0usize
                while k < count * 4usize {
                    m.dns[k] = data[body + k]
                    k += 1usize
                }
                m.dns_count = count
            }
            if code == 12u8 {
                var n = length
                if n > 64usize { n = 64usize }
                var k = 0usize
                while k < n {
                    m.hostname[k] = data[body + k]
                    k += 1usize
                }
                m.hostname_len = n
            }
            if code == 61u8 && length <= 17usize {
                var k = 0usize
                while k < length {
                    m.client_id[k] = data[body + k]
                    k += 1usize
                }
                m.client_id_len = length
            }
            at = body + length
        }
    }
    ret (m, ok)
}

// The lease a decoded message grants as seconds, 0 when it carries none.
fn lease_time(m: Message) -> u32 {
    if m.has_lease { ret m.lease_seconds }
    ret 0u32
}
