// IPv4 CIDR prefix arithmetic with Terraform's semantics (`cidrsubnet`, `cidrhost`, `cidrnetmask`,
// `cidrsubnets`), after petcow's interpreter. `parse` reads `a.b.c.d/n`; `subnet` extends a prefix by
// `newbits` and picks number `netnum` of the 2^newbits subnets; `host` is the address `hostnum` into a prefix;
// `netmask` is the mask; `subnets` packs a list of subnets of different sizes into a prefix, each placed at
// the next offset aligned to its own size. Each has a text form (`subnet_text`, ...) that takes and gives
// strings, which is what a template engine calls.
//
// The host bits of the written prefix are ignored: `10.0.0.5/24` is the network `10.0.0.0/24`, as in Terraform
// (Go's `net.ParseCIDR` masks it). An octet is plain decimal, 0 to 255, with no leading zero (`010` is
// ambiguous between decimal and octal and is refused). `newbits` and `netnum` and `hostnum` are `i64` so that a
// negative input is refused as `Negative` rather than wrapping. IPv6 prefixes are not handled: they answer
// `NotIpv4`.

use e.mem

error BadPrefix
error BadLength
error LengthTooLong
error NotIpv4
error BadAddress
error Negative
error NewbitsTooBig
error NetnumRange
error HostRange
error DoesNotFit

type Ipv4Prefix = struct { addr: u32, len: u32 }

// A decimal number from `text`, or false for empty, non-digit or more than 10 digits (a u32 never takes more).
fn decimal(text: str) -> (u64, bool) {
    if text.len == 0usize || text.len > 10usize { ret (0u64, false) }
    var v = 0u64
    var i = 0usize
    while i < text.len {
        if text[i] < 48u8 || text[i] > 57u8 { ret (0u64, false) }
        v = v * 10u64 + u64(text[i] - 48u8)
        i += 1usize
    }
    ret (v, true)
}

// Read `a.b.c.d/n`. The host bits stay as written in `addr`; `network` clears them.
fn parse(prefix: str) -> (Ipv4Prefix, err) {
    var empty: Ipv4Prefix = zero
    var slash = prefix.len
    var i = 0usize
    while i < prefix.len {
        if prefix[i] == 47u8 {
            slash = i
            i = prefix.len
        } else {
            i += 1usize
        }
    }
    if slash == prefix.len { ret (empty, BadPrefix) }
    let (length, length_ok) = decimal(prefix[slash + 1usize..prefix.len])
    if !length_ok { ret (empty, BadLength) }
    if length > 32u64 { ret (empty, LengthTooLong) }
    let address_text = prefix[0usize..slash]
    // Four dot-separated octets; a field that is not digits at all means this is not a dotted IPv4 address.
    var value = 0u64
    var count = 0usize
    var start = 0usize
    var bad_address = false
    i = 0usize
    while i <= address_text.len {
        if i == address_text.len || address_text[i] == 46u8 {
            let field = address_text[start..i]
            let (octet, octet_ok) = decimal(field)
            if !octet_ok { ret (empty, NotIpv4) }
            if octet > 255u64 || (field.len > 1usize && field[0usize] == 48u8) { bad_address = true }
            if count < 4usize { value = value * 256u64 + octet }
            count += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    if count != 4usize || bad_address { ret (empty, BadAddress) }
    ret (Ipv4Prefix { addr: u32(value), len: u32(length) }, ok)
}

// The mask of a prefix length as an address.
fn mask_of(length: u32) -> u32 {
    if length == 0u32 { ret 0u32 }
    ret u32((4294967295u64 << u64(32u32 - length)) & 4294967295u64)
}

// The network address (host bits cleared).
fn network(p: Ipv4Prefix) -> u32 {
    ret p.addr & mask_of(p.len)
}

// `cidrnetmask`: the mask of the prefix as an address.
fn netmask(p: Ipv4Prefix) -> u32 {
    ret mask_of(p.len)
}

// `cidrsubnet`: the prefix `newbits` longer whose number among the 2^newbits subnets is `netnum`.
fn subnet(p: Ipv4Prefix, newbits: i64, netnum: i64) -> (Ipv4Prefix, err) {
    var empty: Ipv4Prefix = zero
    if newbits < 0i64 || netnum < 0i64 { ret (empty, Negative) }
    if newbits > 32i64 || u64(p.len) + u64(newbits) > 32u64 { ret (empty, NewbitsTooBig) }
    if u64(netnum) >= (1u64 << u64(newbits)) { ret (empty, NetnumRange) }
    let new_length = p.len + u32(newbits)
    let shift = 32u32 - new_length
    var offset = 0u64
    if shift < 32u32 { offset = u64(netnum) << u64(shift) }
    ret (Ipv4Prefix { addr: u32((u64(network(p)) | offset) & 4294967295u64), len: new_length }, ok)
}

// `cidrhost`: the address `hostnum` into the prefix (0 is the network address).
fn host(p: Ipv4Prefix, hostnum: i64) -> (u32, err) {
    if hostnum < 0i64 { ret (0u32, Negative) }
    let capacity = 1u64 << u64(32u32 - p.len)
    if u64(hostnum) >= capacity { ret (0u32, HostRange) }
    ret (u32(u64(network(p)) + u64(hostnum)), ok)
}

// `cidrsubnets`: one subnet per entry of `newbits`, in order, each at the next offset aligned to its size.
// `out` must hold `newbits.len` prefixes; the count is answered.
fn subnets(p: Ipv4Prefix, newbits: []const i64, out: []Ipv4Prefix) -> (usize, err) {
    if out.len < newbits.len { ret (0usize, DoesNotFit) }
    let parent_size = 1u64 << u64(32u32 - p.len)
    var position = 0u64
    var i = 0usize
    while i < newbits.len {
        if newbits[i] < 0i64 { ret (0usize, Negative) }
        if newbits[i] > 32i64 || u64(p.len) + u64(newbits[i]) > 32u64 { ret (0usize, NewbitsTooBig) }
        let new_length = p.len + u32(newbits[i])
        let size = 1u64 << u64(32u32 - new_length)
        position = (position + size - 1u64) / size * size
        if position + size > parent_size { ret (0usize, DoesNotFit) }
        out[i] = Ipv4Prefix { addr: u32(u64(network(p)) + position), len: new_length }
        position += size
        i += 1usize
    }
    ret (newbits.len, ok)
}

// ---------------------------------------------------------------------------
// Text forms.

// "10.1.2.3" from an address.
fn format_addr(a: *mem.Arena, addr: u32) -> (str, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, 15usize)
    if buffer_error != ok { ret ("", buffer_error) }
    var n = 0usize
    var shift = 24u32
    var octet_index = 0usize
    while octet_index < 4usize {
        let octet = (addr >> shift) & 255u32
        if octet >= 100u32 {
            buffer[n] = u8(48u32 + octet / 100u32)
            n += 1usize
        }
        if octet >= 10u32 {
            buffer[n] = u8(48u32 + (octet / 10u32) % 10u32)
            n += 1usize
        }
        buffer[n] = u8(48u32 + octet % 10u32)
        n += 1usize
        if octet_index < 3usize {
            buffer[n] = 46u8
            n += 1usize
            shift -= 8u32
        }
        octet_index += 1usize
    }
    ret (buffer[0usize..n], ok)
}

// "10.1.2.0/24" from a prefix (the address as stored).
fn format(a: *mem.Arena, p: Ipv4Prefix) -> (str, err) {
    let (address, address_error) = format_addr(a, p.addr)
    if address_error != ok { ret ("", address_error) }
    let (buffer, buffer_error) = mem.alloc[u8](a, address.len + 3usize)
    if buffer_error != ok { ret ("", buffer_error) }
    var n = 0usize
    while n < address.len {
        buffer[n] = address[n]
        n += 1usize
    }
    buffer[n] = 47u8
    n += 1usize
    if p.len >= 10u32 {
        buffer[n] = u8(48u32 + p.len / 10u32)
        n += 1usize
    }
    buffer[n] = u8(48u32 + p.len % 10u32)
    n += 1usize
    ret (buffer[0usize..n], ok)
}

// `cidrsubnet("10.1.2.0/24", 4, 15)` is "10.1.2.240/28".
fn subnet_text(a: *mem.Arena, prefix: str, newbits: i64, netnum: i64) -> (str, err) {
    let (p, parse_error) = parse(prefix)
    if parse_error != ok { ret ("", parse_error) }
    let (s, subnet_error) = subnet(p, newbits, netnum)
    if subnet_error != ok { ret ("", subnet_error) }
    let (text, format_error) = format(a, s)
    ret (text, format_error)
}

// `cidrhost("10.12.127.0/20", 268)` is "10.12.113.12".
fn host_text(a: *mem.Arena, prefix: str, hostnum: i64) -> (str, err) {
    let (p, parse_error) = parse(prefix)
    if parse_error != ok { ret ("", parse_error) }
    let (address, host_error) = host(p, hostnum)
    if host_error != ok { ret ("", host_error) }
    let (text, format_error) = format_addr(a, address)
    ret (text, format_error)
}

// `cidrnetmask("172.16.0.0/12")` is "255.240.0.0".
fn netmask_text(a: *mem.Arena, prefix: str) -> (str, err) {
    let (p, parse_error) = parse(prefix)
    if parse_error != ok { ret ("", parse_error) }
    let (text, format_error) = format_addr(a, netmask(p))
    ret (text, format_error)
}

// `cidrsubnets("10.1.0.0/16", 4, 4, 8, 4)` is "10.1.0.0/20", "10.1.16.0/20", "10.1.32.0/24", "10.1.48.0/20".
fn subnets_text(a: *mem.Arena, prefix: str, newbits: []const i64) -> ([]str, err) {
    var none: []str = zero
    let (p, parse_error) = parse(prefix)
    if parse_error != ok { ret (none, parse_error) }
    if newbits.len == 0usize { ret (none, ok) }
    let (found, found_error) = mem.alloc[Ipv4Prefix](a, newbits.len)
    if found_error != ok { ret (none, found_error) }
    let (count, subnets_error) = subnets(p, newbits, found)
    if subnets_error != ok { ret (none, subnets_error) }
    let (texts, texts_error) = mem.alloc[str](a, count)
    if texts_error != ok { ret (none, texts_error) }
    var i = 0usize
    while i < count {
        let (line, line_error) = format(a, found[i])
        if line_error != ok { ret (none, line_error) }
        texts[i] = line
        i += 1usize
    }
    ret (texts, ok)
}
