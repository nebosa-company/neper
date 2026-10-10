// Packet header codecs (L051): Ethernet II with 802.1Q/802.1ad tags, ARP (IPv4 over Ethernet), IPv4 with options,
// IPv6 with its extension-header chain (hop-by-hop, routing, fragment, destination options, authentication), TCP with
// options, UDP, ICMP and ICMPv6, and the Internet checksum (RFC 1071) with the IPv4/IPv6 pseudo-headers (RFC 793,
// RFC 8200). Every parser works over a caller's bytes, borrows its payload from them, and fails closed: a header or
// length the data does not hold is `Truncated`, a version, header length or value that cannot be is `Invalid`; nothing
// is read past the declared total length and no allocation happens. Builders write into a caller's buffer and compute
// the checksums, so a built packet parses back with `checksum_ok` true. Raw-socket send stays platform code.
//
// Memory: parsers allocate nothing; builders write into the buffer given.

error Truncated
error Invalid

type Ethernet = struct { dst: [6]u8, src: [6]u8, ethertype: u16, vlan_count: u8, vlan_id: u16, vlan_pcp: u8, payload: []const u8 }

type Arp = struct { operation: u16, sender_mac: [6]u8, sender_ip: [4]u8, target_mac: [6]u8, target_ip: [4]u8 }

type Ipv4 = struct { ihl: u8, dscp: u8, ecn: u8, total_length: u16, id: u16, flags: u8, fragment_offset: u16, ttl: u8, protocol: u8, checksum: u16, checksum_ok: bool, src: [4]u8, dst: [4]u8, options: []const u8, payload: []const u8 }

type Ipv6 = struct { traffic_class: u8, flow_label: u32, payload_length: u16, next_header: u8, hop_limit: u8, src: [16]u8, dst: [16]u8, protocol: u8, fragment: bool, fragment_offset: u16, more_fragments: bool, payload: []const u8 }

type Tcp = struct { src_port: u16, dst_port: u16, seq: u32, ack: u32, data_offset: u8, flags: u16, window: u16, checksum: u16, urgent: u16, options: []const u8, payload: []const u8 }

type Udp = struct { src_port: u16, dst_port: u16, length: u16, checksum: u16, payload: []const u8 }

type Icmp = struct { kind: u8, code: u8, checksum: u16, rest: u32, payload: []const u8 }

fn be16(b: []const u8, at: usize) -> u16 { ret (u16(b[at]) << 8u16) | u16(b[at + 1usize]) }

fn be32(b: []const u8, at: usize) -> u32 { ret (u32(b[at]) << 24u32) | (u32(b[at + 1usize]) << 16u32) | (u32(b[at + 2usize]) << 8u32) | u32(b[at + 3usize]) }

fn put16(b: []u8, at: usize, v: u16) {
    b[at] = u8(v >> 8u16)
    b[at + 1usize] = u8(v & 255u16)
}

fn put32(b: []u8, at: usize, v: u32) {
    b[at] = u8(v >> 24u32)
    b[at + 1usize] = u8((v >> 16u32) & 255u32)
    b[at + 2usize] = u8((v >> 8u32) & 255u32)
    b[at + 3usize] = u8(v & 255u32)
}

// --- checksums -------------------------------------------------------------------------------------------------

// The sum of 16-bit big-endian words (an odd last byte as the high half), not yet folded or complemented.
fn sum_words(data: []const u8, seed: u32) -> u32 {
    var sum = seed
    var i = 0usize
    while i + 1usize < data.len {
        sum += (u32(data[i]) << 8u32) | u32(data[i + 1usize])
        i += 2usize
    }
    if i < data.len { sum += u32(data[i]) << 8u32 }
    ret sum
}

fn fold(sum: u32) -> u16 {
    var s = sum
    while (s >> 16u32) != 0u32 { s = (s & 65535u32) + (s >> 16u32) }
    ret u16(s)
}

// The Internet checksum of `data` (RFC 1071): the folded one's-complement sum, complemented.
fn internet_checksum(data: []const u8) -> u16 {
    ret ~fold(sum_words(data, 0u32))
}

// The IPv4 pseudo-header's contribution (source, destination, zero, protocol, upper-layer length).
fn pseudo_sum_v4(src: [4]u8, dst: [4]u8, protocol: u8, length: usize) -> u32 {
    var sum = 0u32
    sum += (u32(src[0]) << 8u32) | u32(src[1])
    sum += (u32(src[2]) << 8u32) | u32(src[3])
    sum += (u32(dst[0]) << 8u32) | u32(dst[1])
    sum += (u32(dst[2]) << 8u32) | u32(dst[3])
    sum += u32(protocol)
    sum += u32(length)
    ret sum
}

fn pseudo_sum_v6(src: [16]u8, dst: [16]u8, protocol: u8, length: usize) -> u32 {
    var sum = 0u32
    var i = 0usize
    while i < 16usize {
        sum += (u32(src[i]) << 8u32) | u32(src[i + 1usize])
        sum += (u32(dst[i]) << 8u32) | u32(dst[i + 1usize])
        i += 2usize
    }
    sum += u32(length >> 16usize)
    sum += u32(length & 65535usize)
    sum += u32(protocol)
    ret sum
}

// The TCP/UDP/ICMP checksum field value for a segment whose checksum field holds zero.
fn transport_checksum_v4(src: [4]u8, dst: [4]u8, protocol: u8, segment: []const u8) -> u16 {
    ret ~fold(sum_words(segment, pseudo_sum_v4(src, dst, protocol, segment.len)))
}

fn transport_checksum_v6(src: [16]u8, dst: [16]u8, protocol: u8, segment: []const u8) -> u16 {
    ret ~fold(sum_words(segment, pseudo_sum_v6(src, dst, protocol, segment.len)))
}

// Whether a received segment's checksum verifies: the sum with the pseudo-header folds to 0xFFFF.
fn transport_ok_v4(src: [4]u8, dst: [4]u8, protocol: u8, segment: []const u8) -> bool {
    ret fold(sum_words(segment, pseudo_sum_v4(src, dst, protocol, segment.len))) == 65535u16
}

fn transport_ok_v6(src: [16]u8, dst: [16]u8, protocol: u8, segment: []const u8) -> bool {
    ret fold(sum_words(segment, pseudo_sum_v6(src, dst, protocol, segment.len))) == 65535u16
}

// --- Ethernet and ARP ------------------------------------------------------------------------------------------

fn copy6(b: []const u8, at: usize) -> [6]u8 {
    var out: [6]u8 = zero
    var i = 0usize
    while i < 6usize {
        out[i] = b[at + i]
        i += 1usize
    }
    ret out
}

fn copy4(b: []const u8, at: usize) -> [4]u8 {
    var out: [4]u8 = zero
    var i = 0usize
    while i < 4usize {
        out[i] = b[at + i]
        i += 1usize
    }
    ret out
}

fn copy16(b: []const u8, at: usize) -> [16]u8 {
    var out: [16]u8 = zero
    var i = 0usize
    while i < 16usize {
        out[i] = b[at + i]
        i += 1usize
    }
    ret out
}

// An Ethernet II frame with up to two VLAN tags (0x8100 and 0x88A8); the innermost tag's id and priority are reported.
fn parse_ethernet(frame: []const u8) -> (Ethernet, err) {
    var out: Ethernet = zero
    if frame.len < 14usize { ret (out, Truncated) }
    out.dst = copy6(frame, 0usize)
    out.src = copy6(frame, 6usize)
    var at = 12usize
    var ethertype = be16(frame, at)
    var tags = 0u8
    while (ethertype == 33024u16 || ethertype == 34984u16) && tags < 2u8 {
        if frame.len < at + 6usize { ret (out, Truncated) }
        let tci = be16(frame, at + 2usize)
        out.vlan_id = tci & 4095u16
        out.vlan_pcp = u8(tci >> 13u16)
        tags += 1u8
        at += 4usize
        ethertype = be16(frame, at)
    }
    out.vlan_count = tags
    out.ethertype = ethertype
    out.payload = frame[at + 2usize..]
    ret (out, ok)
}

// An ARP request or reply for IPv4 over Ethernet (hardware 1, protocol 0x0800, lengths 6 and 4).
fn parse_arp(data: []const u8) -> (Arp, err) {
    var out: Arp = zero
    if data.len < 28usize { ret (out, Truncated) }
    if be16(data, 0usize) != 1u16 || be16(data, 2usize) != 2048u16 || data[4] != 6u8 || data[5] != 4u8 { ret (out, Invalid) }
    out.operation = be16(data, 6usize)
    out.sender_mac = copy6(data, 8usize)
    out.sender_ip = copy4(data, 14usize)
    out.target_mac = copy6(data, 18usize)
    out.target_ip = copy4(data, 24usize)
    ret (out, ok)
}

// --- IPv4 ------------------------------------------------------------------------------------------------------

// An IPv4 packet: version 4, header length of at least 20 bytes within the data, a total length the data holds
// (trailing link padding beyond it is ignored); `checksum_ok` is the header checksum verifying.
fn parse_ipv4(data: []const u8) -> (Ipv4, err) {
    var out: Ipv4 = zero
    if data.len < 20usize { ret (out, Truncated) }
    if (data[0] >> 4u8) != 4u8 { ret (out, Invalid) }
    let ihl = usize(data[0] & 15u8)
    if ihl < 5usize { ret (out, Invalid) }
    let header = ihl * 4usize
    if data.len < header { ret (out, Truncated) }
    let total = usize(be16(data, 2usize))
    if total < header { ret (out, Invalid) }
    if data.len < total { ret (out, Truncated) }
    out.ihl = u8(ihl)
    out.dscp = data[1] >> 2u8
    out.ecn = data[1] & 3u8
    out.total_length = u16(total)
    out.id = be16(data, 4usize)
    let ff = be16(data, 6usize)
    out.flags = u8(ff >> 13u16)
    out.fragment_offset = ff & 8191u16
    out.ttl = data[8]
    out.protocol = data[9]
    out.checksum = be16(data, 10usize)
    out.checksum_ok = fold(sum_words(data[0usize..header], 0u32)) == 65535u16
    out.src = copy4(data, 12usize)
    out.dst = copy4(data, 16usize)
    out.options = data[20usize..header]
    out.payload = data[header..total]
    ret (out, ok)
}

// --- IPv6 ------------------------------------------------------------------------------------------------------

fn is_extension(next: u8) -> bool { ret next == 0u8 || next == 43u8 || next == 44u8 || next == 60u8 || next == 51u8 }

// An IPv6 packet with its extension headers walked to the upper-layer protocol; a fragment header sets `fragment`,
// the offset (in 8-byte units) and `more_fragments`, and the payload is then the fragment's data.
fn parse_ipv6(data: []const u8) -> (Ipv6, err) {
    var out: Ipv6 = zero
    if data.len < 40usize { ret (out, Truncated) }
    if (data[0] >> 4u8) != 6u8 { ret (out, Invalid) }
    out.traffic_class = ((data[0] & 15u8) << 4u8) | (data[1] >> 4u8)
    out.flow_label = ((u32(data[1]) & 15u32) << 16u32) | (u32(data[2]) << 8u32) | u32(data[3])
    let plen = usize(be16(data, 4usize))
    out.payload_length = u16(plen)
    out.next_header = data[6]
    out.hop_limit = data[7]
    out.src = copy16(data, 8usize)
    out.dst = copy16(data, 24usize)
    if data.len < 40usize + plen { ret (out, Truncated) }
    let end = 40usize + plen
    var next = out.next_header
    var at = 40usize
    var hops = 0usize
    while is_extension(next) {
        hops += 1usize
        if hops > 16usize { ret (out, Invalid) }
        if at + 8usize > end { ret (out, Truncated) }
        if next == 44u8 {
            out.fragment = true
            let fo = be16(data, at + 2usize)
            out.fragment_offset = fo >> 3u16
            out.more_fragments = (fo & 1u16) != 0u16
            next = data[at]
            at += 8usize
            continue
        }
        var length = (usize(data[at + 1usize]) + 1usize) * 8usize
        if next == 51u8 { length = (usize(data[at + 1usize]) + 2usize) * 4usize }
        if at + length > end { ret (out, Truncated) }
        next = data[at]
        at += length
    }
    out.protocol = next
    out.payload = data[at..end]
    ret (out, ok)
}

// --- TCP, UDP, ICMP --------------------------------------------------------------------------------------------

fn parse_tcp(segment: []const u8) -> (Tcp, err) {
    var out: Tcp = zero
    if segment.len < 20usize { ret (out, Truncated) }
    let offset = usize(segment[12] >> 4u8)
    if offset < 5usize { ret (out, Invalid) }
    let header = offset * 4usize
    if segment.len < header { ret (out, Truncated) }
    out.src_port = be16(segment, 0usize)
    out.dst_port = be16(segment, 2usize)
    out.seq = be32(segment, 4usize)
    out.ack = be32(segment, 8usize)
    out.data_offset = u8(offset)
    out.flags = be16(segment, 12usize) & 511u16
    out.window = be16(segment, 14usize)
    out.checksum = be16(segment, 16usize)
    out.urgent = be16(segment, 18usize)
    out.options = segment[20usize..header]
    out.payload = segment[header..]
    ret (out, ok)
}

fn parse_udp(segment: []const u8) -> (Udp, err) {
    var out: Udp = zero
    if segment.len < 8usize { ret (out, Truncated) }
    let length = usize(be16(segment, 4usize))
    if length < 8usize { ret (out, Invalid) }
    if segment.len < length { ret (out, Truncated) }
    out.src_port = be16(segment, 0usize)
    out.dst_port = be16(segment, 2usize)
    out.length = u16(length)
    out.checksum = be16(segment, 6usize)
    out.payload = segment[8usize..length]
    ret (out, ok)
}

// An ICMP or ICMPv6 message: type, code, checksum, the four-byte rest-of-header and the body.
fn parse_icmp(message: []const u8) -> (Icmp, err) {
    var out: Icmp = zero
    if message.len < 8usize { ret (out, Truncated) }
    out.kind = message[0]
    out.code = message[1]
    out.checksum = be16(message, 2usize)
    out.rest = be32(message, 4usize)
    out.payload = message[8usize..]
    ret (out, ok)
}

// --- builders --------------------------------------------------------------------------------------------------

// An Ethernet II header (no tag) at the start of `buf`; the number of bytes written.
fn build_ethernet(buf: []u8, dst: [6]u8, src: [6]u8, ethertype: u16) -> usize {
    var i = 0usize
    while i < 6usize {
        buf[i] = dst[i]
        buf[6usize + i] = src[i]
        i += 1usize
    }
    put16(buf, 12usize, ethertype)
    ret 14usize
}

// An IPv4 header without options, checksum computed; `payload_length` is what follows. Returns 20.
fn build_ipv4(buf: []u8, tos: u8, id: u16, flags: u8, fragment_offset: u16, ttl: u8, protocol: u8, src: [4]u8, dst: [4]u8, payload_length: usize) -> usize {
    buf[0] = 69u8
    buf[1] = tos
    put16(buf, 2usize, u16(20usize + payload_length))
    put16(buf, 4usize, id)
    put16(buf, 6usize, (u16(flags) << 13u16) | (fragment_offset & 8191u16))
    buf[8] = ttl
    buf[9] = protocol
    put16(buf, 10usize, 0u16)
    var i = 0usize
    while i < 4usize {
        buf[12usize + i] = src[i]
        buf[16usize + i] = dst[i]
        i += 1usize
    }
    put16(buf, 10usize, internet_checksum(buf[0usize..20usize]))
    ret 20usize
}

// A fixed IPv6 header; returns 40.
fn build_ipv6(buf: []u8, traffic_class: u8, flow_label: u32, next_header: u8, hop_limit: u8, src: [16]u8, dst: [16]u8, payload_length: usize) -> usize {
    buf[0] = 96u8 | (traffic_class >> 4u8)
    buf[1] = ((traffic_class & 15u8) << 4u8) | u8((flow_label >> 16u32) & 15u32)
    buf[2] = u8((flow_label >> 8u32) & 255u32)
    buf[3] = u8(flow_label & 255u32)
    put16(buf, 4usize, u16(payload_length))
    buf[6] = next_header
    buf[7] = hop_limit
    var i = 0usize
    while i < 16usize {
        buf[8usize + i] = src[i]
        buf[24usize + i] = dst[i]
        i += 1usize
    }
    ret 40usize
}

// A UDP datagram (header then `payload`) with the checksum computed over an IPv4 pseudo-header; returns its length.
fn build_udp_v4(buf: []u8, src_port: u16, dst_port: u16, payload: []const u8, src: [4]u8, dst: [4]u8) -> usize {
    let length = 8usize + payload.len
    put16(buf, 0usize, src_port)
    put16(buf, 2usize, dst_port)
    put16(buf, 4usize, u16(length))
    put16(buf, 6usize, 0u16)
    var i = 0usize
    while i < payload.len {
        buf[8usize + i] = payload[i]
        i += 1usize
    }
    var sum = transport_checksum_v4(src, dst, 17u8, buf[0usize..length])
    if sum == 0u16 { sum = 65535u16 }
    put16(buf, 6usize, sum)
    ret length
}

// A TCP segment with `options` (a multiple of four bytes) and `payload`, checksum over an IPv4 pseudo-header.
fn build_tcp_v4(buf: []u8, src_port: u16, dst_port: u16, seq: u32, ack: u32, flags: u16, window: u16, urgent: u16, options: []const u8, payload: []const u8, src: [4]u8, dst: [4]u8) -> usize {
    let header = 20usize + options.len
    put16(buf, 0usize, src_port)
    put16(buf, 2usize, dst_port)
    put32(buf, 4usize, seq)
    put32(buf, 8usize, ack)
    put16(buf, 12usize, (u16(header / 4usize) << 12u16) | (flags & 511u16))
    put16(buf, 14usize, window)
    put16(buf, 16usize, 0u16)
    put16(buf, 18usize, urgent)
    var i = 0usize
    while i < options.len {
        buf[20usize + i] = options[i]
        i += 1usize
    }
    i = 0usize
    while i < payload.len {
        buf[header + i] = payload[i]
        i += 1usize
    }
    let length = header + payload.len
    put16(buf, 16usize, transport_checksum_v4(src, dst, 6u8, buf[0usize..length]))
    ret length
}

// An ICMP (IPv4) message: type, code, rest-of-header and body, checksum computed over the message alone.
fn build_icmp(buf: []u8, kind: u8, code: u8, rest: u32, payload: []const u8) -> usize {
    buf[0] = kind
    buf[1] = code
    put16(buf, 2usize, 0u16)
    put32(buf, 4usize, rest)
    var i = 0usize
    while i < payload.len {
        buf[8usize + i] = payload[i]
        i += 1usize
    }
    let length = 8usize + payload.len
    put16(buf, 2usize, internet_checksum(buf[0usize..length]))
    ret length
}

// An ICMPv6 message: the checksum covers the IPv6 pseudo-header (next header 58).
fn build_icmp_v6(buf: []u8, kind: u8, code: u8, rest: u32, payload: []const u8, src: [16]u8, dst: [16]u8) -> usize {
    buf[0] = kind
    buf[1] = code
    put16(buf, 2usize, 0u16)
    put32(buf, 4usize, rest)
    var i = 0usize
    while i < payload.len {
        buf[8usize + i] = payload[i]
        i += 1usize
    }
    let length = 8usize + payload.len
    put16(buf, 2usize, transport_checksum_v6(src, dst, 58u8, buf[0usize..length]))
    ret length
}
