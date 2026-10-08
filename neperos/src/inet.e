// The NeperOS IPv4 stack (D2244, C117): Ethernet, ARP, IPv4, ICMP echo, UDP, DHCP and a DNS
// resolver over the virtio-net driver. Everything is polled: a request sends one frame and spins,
// bounded, on the receive ring until the answer arrives, so there is no interrupt to mis-route and
// a silent network ends in an error, never a hang. Every unicast frame goes to the gateway's MAC
// (QEMU user-mode networking answers for 10.0.2.2, .3 and the outside world through it), so ARP
// only ever resolves the gateway. Frames are built in place in the driver's transmit buffer, which
// is why the layers hand out the address where the next layer's payload begins.
use e.os
use virtio

error NoLease
error NoReply
error NoName
error Malformed

const ETH_HDR: usize = 14usize
const IP_HDR: usize = 20usize
const UDP_HDR: usize = 8usize

const ETYPE_IP: u16 = 2048u16
const ETYPE_ARP: u16 = 2054u16

const PROTO_ICMP: u8 = 1u8
const PROTO_TCP: u8 = 6u8
const PROTO_UDP: u8 = 17u8

const BROADCAST: u64 = 281474976710655u64

// How many empty polls of the receive ring make one wait; a wait is tens of milliseconds of
// emulated time, and every exchange retries a few waits.
const POLLS: usize = 4000000usize

type Stack = struct { net: virtio.Net, mac: u64, ip: u32, mask: u32, gw: u32, dns: u32, gw_mac: u64, ident: u16 }

fn put16(at: usize, value: u16) {
    os.store8(at, u8(value >> 8u16))
    os.store8(at + 1usize, u8(value & 255u16))
}

fn put32(at: usize, value: u32) {
    put16(at, u16(value >> 16u32))
    put16(at + 2usize, u16(value & 65535u32))
}

fn get16(at: usize) -> u16 {
    ret (u16(os.load8(at)) << 8u16) | u16(os.load8(at + 1usize))
}

fn get32(at: usize) -> u32 {
    ret (u32(get16(at)) << 16u32) | u32(get16(at + 2usize))
}

fn put_mac(at: usize, mac: u64) {
    var i = 0usize
    while i < 6usize {
        os.store8(at + i, u8((mac >> u64(8usize * (5usize - i))) & 255u64))
        i += 1usize
    }
}

fn get_mac(at: usize) -> u64 {
    var mac = 0u64
    var i = 0usize
    while i < 6usize {
        mac = (mac << 8u64) | u64(os.load8(at + i))
        i += 1usize
    }
    ret mac
}

fn copy(dst: usize, src: usize, len: usize) {
    var i = 0usize
    while i < len {
        os.store8(dst + i, os.load8(src + i))
        i += 1usize
    }
}

// The Internet checksum of [at, at+len) added to `seed` (a pseudo-header's partial sum): 16-bit
// words summed with the carries folded back, then complemented.
fn checksum(at: usize, len: usize, seed: u32) -> u16 {
    var sum = seed
    var i = 0usize
    while i + 1usize < len {
        sum += u32(get16(at + i))
        i += 2usize
    }
    if i < len { sum += u32(os.load8(at + i)) << 8u32 }
    while (sum >> 16u32) != 0u32 { sum = (sum & 65535u32) + (sum >> 16u32) }
    ret u16(~sum & 65535u32)
}

// Write `ip` as dotted decimal to the console.
fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn say_num(value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var open = true
    while open {
        at -= 1usize
        digits[at] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    say(digits[at..20usize])
}

fn say_ip(ip: u32) {
    say_num(usize(ip >> 24u32))
    say(".")
    say_num(usize((ip >> 16u32) & 255u32))
    say(".")
    say_num(usize((ip >> 8u32) & 255u32))
    say(".")
    say_num(usize(ip & 255u32))
}

// Bring the interface up: the driver opened, no address yet.
fn attach(device: virtio.Device) -> (Stack, err) {
    let (net, net_error) = virtio.net_open(device)
    if net_error != ok { ret (zero, net_error) }
    ret (Stack { net: net, mac: net.mac, ip: 0u32, mask: 0u32, gw: 0u32, dns: 0u32, gw_mac: BROADCAST, ident: 1u16 }, ok)
}

// ---- Ethernet and ARP ----

// Where the payload of the frame under construction begins.
fn eth_payload(st: *Stack) -> usize {
    ret st.net.tx_buf + virtio.NET_HDR + ETH_HDR
}

// Fill the Ethernet header of the frame in the transmit buffer and send it with `len` payload bytes.
fn eth_send(st: *Stack, dst: u64, ethertype: u16, len: usize) -> err {
    let frame = st.net.tx_buf + virtio.NET_HDR
    put_mac(frame, dst)
    put_mac(frame + 6usize, st.mac)
    put16(frame + 12usize, ethertype)
    var total = ETH_HDR + len
    // A frame shorter than the Ethernet minimum is padded with zeros.
    while total < 60usize {
        os.store8(frame + total, 0u8)
        total += 1usize
    }
    ret virtio.net_send(&st.net, total)
}

fn arp_send(st: *Stack, op: u16, target_mac: u64, target_ip: u32) -> err {
    let at = eth_payload(st)
    put16(at, 1u16)
    put16(at + 2usize, ETYPE_IP)
    os.store8(at + 4usize, 6u8)
    os.store8(at + 5usize, 4u8)
    put16(at + 6usize, op)
    put_mac(at + 8usize, st.mac)
    put32(at + 14usize, st.ip)
    put_mac(at + 18usize, target_mac)
    put32(at + 24usize, target_ip)
    var dst = BROADCAST
    if op == 2u16 { dst = target_mac }
    ret eth_send(st, dst, ETYPE_ARP, 28usize)
}

// Look at one received frame. ARP requests for our address are answered and the gateway's MAC is
// learnt from any ARP reply from it. An IPv4 packet addressed to us (or broadcast) comes back as
// (protocol, source address, payload address, payload length); everything else is (0, 0, 0, 0).
// ICMP echo requests are answered here, so callers only ever see replies.
fn poll(st: *Stack) -> (u8, u32, usize, usize) {
    let (frame, len, got) = virtio.net_recv(&st.net)
    if !got || len < ETH_HDR { ret (0u8, 0u32, 0usize, 0usize) }
    let ethertype = get16(frame + 12usize)
    if ethertype == ETYPE_ARP && len >= ETH_HDR + 28usize {
        let at = frame + ETH_HDR
        let op = get16(at + 6usize)
        let sender_mac = get_mac(at + 8usize)
        let sender_ip = get32(at + 14usize)
        let target_ip = get32(at + 24usize)
        if op == 2u16 && sender_ip == st.gw { st.gw_mac = sender_mac }
        if op == 1u16 && target_ip == st.ip && st.ip != 0u32 {
            let reply_error = arp_send(st, 2u16, sender_mac, sender_ip)
        }
        ret (0u8, 0u32, 0usize, 0usize)
    }
    if ethertype != ETYPE_IP || len < ETH_HDR + IP_HDR { ret (0u8, 0u32, 0usize, 0usize) }
    let ip = frame + ETH_HDR
    if (os.load8(ip) >> 4u8) != 4u8 { ret (0u8, 0u32, 0usize, 0usize) }
    let header_len = usize(os.load8(ip) & 15u8) * 4usize
    let total = usize(get16(ip + 2usize))
    if header_len < IP_HDR || total < header_len || ETH_HDR + total > len { ret (0u8, 0u32, 0usize, 0usize) }
    let dst = get32(ip + 16usize)
    // Before a lease the only packet that matters is the DHCP reply, addressed to our MAC.
    if st.ip != 0u32 && dst != st.ip && dst != 4294967295u32 { ret (0u8, 0u32, 0usize, 0usize) }
    let proto = os.load8(ip + 9usize)
    let src = get32(ip + 12usize)
    let payload = ip + header_len
    let payload_len = total - header_len
    if proto == PROTO_ICMP && payload_len >= 8usize && os.load8(payload) == 8u8 {
        let reply = eth_payload(st) + IP_HDR
        copy(reply, payload, payload_len)
        os.store8(reply, 0u8)
        put16(reply + 2usize, 0u16)
        put16(reply + 2usize, checksum(reply, payload_len, 0u32))
        let reply_error = ip_finish(st, PROTO_ICMP, src, st.gw_mac, payload_len)
        ret (0u8, 0u32, 0usize, 0usize)
    }
    ret (proto, src, payload, payload_len)
}

// Resolve the gateway's MAC with an ARP request, retrying a few times.
fn arp_gateway(st: *Stack) -> err {
    var attempt = 0usize
    while attempt < 5usize {
        let send_error = arp_send(st, 1u16, 0u64, st.gw)
        if send_error != ok { ret send_error }
        var spins = 0usize
        while spins < POLLS {
            let (proto, src, payload, len) = poll(st)
            if st.gw_mac != BROADCAST { ret ok }
            spins += 1usize
        }
        attempt += 1usize
    }
    ret NoReply
}

// ---- IPv4 ----

// Where the payload of the IPv4 packet under construction begins.
fn ip_payload(st: *Stack) -> usize {
    ret eth_payload(st) + IP_HDR
}

// Complete the IPv4 header around a payload of `len` bytes already at ip_payload, and send it to
// the link-layer address `dst_mac`.
fn ip_finish(st: *Stack, proto: u8, dst: u32, dst_mac: u64, len: usize) -> err {
    let ip = eth_payload(st)
    os.store8(ip, 69u8)
    os.store8(ip + 1usize, 0u8)
    put16(ip + 2usize, u16(IP_HDR + len))
    put16(ip + 4usize, st.ident)
    st.ident += 1u16
    put16(ip + 6usize, 16384u16)
    os.store8(ip + 8usize, 64u8)
    os.store8(ip + 9usize, proto)
    put16(ip + 10usize, 0u16)
    put32(ip + 12usize, st.ip)
    put32(ip + 16usize, dst)
    put16(ip + 10usize, checksum(ip, IP_HDR, 0u32))
    ret eth_send(st, dst_mac, ETYPE_IP, IP_HDR + len)
}

// Send the packet to `dst`: broadcast stays broadcast, everything else goes through the gateway.
fn ip_send(st: *Stack, proto: u8, dst: u32, len: usize) -> err {
    var mac = st.gw_mac
    if dst == 4294967295u32 { mac = BROADCAST }
    ret ip_finish(st, proto, dst, mac, len)
}

// ---- ICMP ----

// One echo request to `dst` and the wait for its reply: ok, or NoReply.
fn ping(st: *Stack, dst: u32, seq: u16) -> err {
    let at = ip_payload(st)
    os.store8(at, 8u8)
    os.store8(at + 1usize, 0u8)
    put16(at + 2usize, 0u16)
    put16(at + 4usize, 48879u16)
    put16(at + 6usize, seq)
    var i = 0usize
    while i < 32usize {
        os.store8(at + 8usize + i, u8(97usize + (i % 23usize)))
        i += 1usize
    }
    put16(at + 2usize, checksum(at, 40usize, 0u32))
    var attempt = 0usize
    while attempt < 3usize {
        let send_error = ip_send(st, PROTO_ICMP, dst, 40usize)
        if send_error != ok { ret send_error }
        var spins = 0usize
        while spins < POLLS {
            let (proto, src, payload, len) = poll(st)
            if proto == PROTO_ICMP && src == dst && len >= 8usize && os.load8(payload) == 0u8 && get16(payload + 6usize) == seq { ret ok }
            spins += 1usize
        }
        attempt += 1usize
    }
    ret NoReply
}

// ---- UDP ----

// Where the payload of the UDP datagram under construction begins.
fn udp_payload(st: *Stack) -> usize {
    ret ip_payload(st) + UDP_HDR
}

// The pseudo-header sum a UDP or TCP checksum starts from.
fn pseudo(src: u32, dst: u32, proto: u8, len: usize) -> u32 {
    ret (src >> 16u32) + (src & 65535u32) + (dst >> 16u32) + (dst & 65535u32) + u32(proto) + u32(len)
}

// Send the `len`-byte datagram at udp_payload from `sport` to `dst`:`dport`.
fn udp_send(st: *Stack, sport: u16, dst: u32, dport: u16, len: usize) -> err {
    let at = ip_payload(st)
    put16(at, sport)
    put16(at + 2usize, dport)
    put16(at + 4usize, u16(UDP_HDR + len))
    put16(at + 6usize, 0u16)
    var sum = checksum(at, UDP_HDR + len, pseudo(st.ip, dst, PROTO_UDP, UDP_HDR + len))
    if sum == 0u16 { sum = 65535u16 }
    put16(at + 6usize, sum)
    ret ip_send(st, PROTO_UDP, dst, UDP_HDR + len)
}

// ---- DHCP (RFC 2131) ----

const DHCP_DISCOVER: u8 = 1u8
const DHCP_OFFER: u8 = 2u8
const DHCP_REQUEST: u8 = 3u8
const DHCP_ACK: u8 = 5u8

// Build and send one DHCP client message of `kind`; `want` and `server` go in as options when set.
fn dhcp_send(st: *Stack, kind: u8, want: u32, server: u32) -> err {
    let at = udp_payload(st)
    var i = 0usize
    while i < 300usize {
        os.store8(at + i, 0u8)
        i += 1usize
    }
    os.store8(at, 1u8)
    os.store8(at + 1usize, 1u8)
    os.store8(at + 2usize, 6u8)
    put32(at + 4usize, 1397965394u32)
    put16(at + 10usize, 32768u16)
    put_mac(at + 28usize, st.mac)
    put32(at + 236usize, 1669485411u32)
    var o = at + 240usize
    os.store8(o, 53u8)
    os.store8(o + 1usize, 1u8)
    os.store8(o + 2usize, kind)
    o += 3usize
    os.store8(o, 55u8)
    os.store8(o + 1usize, 3u8)
    os.store8(o + 2usize, 1u8)
    os.store8(o + 3usize, 3u8)
    os.store8(o + 4usize, 6u8)
    o += 5usize
    if want != 0u32 {
        os.store8(o, 50u8)
        os.store8(o + 1usize, 4u8)
        put32(o + 2usize, want)
        o += 6usize
        os.store8(o, 54u8)
        os.store8(o + 1usize, 4u8)
        put32(o + 2usize, server)
        o += 6usize
    }
    os.store8(o, 255u8)
    o += 1usize
    ret udp_send(st, 68u16, 4294967295u32, 67u16, o - at)
}

// Wait for a DHCP reply of `kind` and take its offered address and options into `st` (the
// address only on an offer, where it is returned too). Returns (yiaddr, server id, ok).
fn dhcp_wait(st: *Stack, kind: u8) -> (u32, u32, err) {
    var spins = 0usize
    while spins < POLLS {
        let (proto, src, payload, len) = poll(st)
        if proto == PROTO_UDP && len >= UDP_HDR + 240usize && get16(payload) == 67u16 && get16(payload + 2usize) == 68u16 {
            let msg = payload + UDP_HDR
            if os.load8(msg) == 2u8 && get32(msg + 4usize) == 1397965394u32 && get32(msg + 236usize) == 1669485411u32 {
                let yiaddr = get32(msg + 16usize)
                var found = 0u8
                var server = src
                var o = msg + 240usize
                let limit = payload + len
                while o + 2usize <= limit && os.load8(o) != 255u8 {
                    let code = os.load8(o)
                    if code == 0u8 {
                        o += 1usize
                    } else {
                        let size = usize(os.load8(o + 1usize))
                        let value = o + 2usize
                        if code == 53u8 { found = os.load8(value) }
                        if code == 1u8 && size >= 4usize { st.mask = get32(value) }
                        if code == 3u8 && size >= 4usize { st.gw = get32(value) }
                        if code == 6u8 && size >= 4usize { st.dns = get32(value) }
                        if code == 54u8 && size >= 4usize { server = get32(value) }
                        o += 2usize + size
                    }
                }
                if found == kind { ret (yiaddr, server, ok) }
            }
        }
        spins += 1usize
    }
    ret (0u32, 0u32, NoReply)
}

// The whole exchange: discover, offer, request, acknowledgement. On success the stack holds its
// address, mask, gateway and resolver, and the gateway's MAC is resolved.
fn dhcp(st: *Stack) -> err {
    var attempt = 0usize
    while attempt < 4usize {
        let discover_error = dhcp_send(st, DHCP_DISCOVER, 0u32, 0u32)
        if discover_error != ok { ret discover_error }
        let (offered, server, offer_error) = dhcp_wait(st, DHCP_OFFER)
        if offer_error == ok {
            let request_error = dhcp_send(st, DHCP_REQUEST, offered, server)
            if request_error != ok { ret request_error }
            let (leased, leased_server, ack_error) = dhcp_wait(st, DHCP_ACK)
            if ack_error == ok {
                st.ip = leased
                ret arp_gateway(st)
            }
        }
        attempt += 1usize
    }
    ret NoLease
}

// ---- DNS (RFC 1035) ----

// Resolve `name` to an IPv4 address with one A query to the resolver DHCP named. Retries a few
// times; NoName when the resolver answers with no address, NoReply when it does not answer.
fn resolve(st: *Stack, name: str) -> (u32, err) {
    var attempt = 0usize
    while attempt < 3usize {
        let at = udp_payload(st)
        let id = 4660u16 + u16(attempt)
        put16(at, id)
        put16(at + 2usize, 256u16)
        put16(at + 4usize, 1u16)
        put16(at + 6usize, 0u16)
        put16(at + 8usize, 0u16)
        put16(at + 10usize, 0u16)
        var o = at + 12usize
        var label_start = o
        o += 1usize
        var i = 0usize
        while i < name.len {
            let c = name[i]
            if c == 46u8 {
                os.store8(label_start, u8(o - label_start - 1usize))
                label_start = o
            } else {
                os.store8(o, c)
            }
            o += 1usize
            i += 1usize
        }
        os.store8(label_start, u8(o - label_start - 1usize))
        os.store8(o, 0u8)
        put16(o + 1usize, 1u16)
        put16(o + 3usize, 1u16)
        o += 5usize
        let send_error = udp_send(st, 53000u16, st.dns, 53u16, o - at)
        if send_error != ok { ret (0u32, send_error) }
        var spins = 0usize
        while spins < POLLS {
            let (proto, src, payload, len) = poll(st)
            if proto == PROTO_UDP && len >= UDP_HDR + 12usize && get16(payload) == 53u16 && get16(payload + 2usize) == 53000u16 {
                let msg = payload + UDP_HDR
                let msg_len = len - UDP_HDR
                if get16(msg) == id {
                    let answers = usize(get16(msg + 6usize))
                    if (get16(msg + 2usize) & 15u16) != 0u16 || answers == 0usize { ret (0u32, NoName) }
                    // Skip the echoed question, then walk the answers for the first A record.
                    var p = 12usize
                    while p < msg_len && os.load8(msg + p) != 0u8 { p += usize(os.load8(msg + p)) + 1usize }
                    p += 5usize
                    var n = 0usize
                    while n < answers && p + 12usize <= msg_len {
                        // A name is a pointer (two bytes) or a label run ending in zero.
                        if (os.load8(msg + p) & 192u8) == 192u8 {
                            p += 2usize
                        } else {
                            while p < msg_len && os.load8(msg + p) != 0u8 { p += usize(os.load8(msg + p)) + 1usize }
                            p += 1usize
                        }
                        let rtype = get16(msg + p)
                        let rdlen = usize(get16(msg + p + 8usize))
                        if rtype == 1u16 && rdlen == 4usize && p + 14usize <= msg_len { ret (get32(msg + p + 10usize), ok) }
                        p += 10usize + rdlen
                        n += 1usize
                    }
                    ret (0u32, NoName)
                }
            }
            spins += 1usize
        }
        attempt += 1usize
    }
    ret (0u32, NoReply)
}
