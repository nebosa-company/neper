// Portable network values. This first slice is deliberately pure: parse and format IP
// literals without consulting host DNS, interfaces or socket state. Socket operations
// build on the already-delivered e.os fence in the next slice.

use e.os

type Socket = os.Socket
type Ip4 = struct { bytes: [4]u8 }
type Ip6 = struct { bytes: [16]u8, scope: u32 }
type Address = union enum u8 { Ip4: Ip4, Ip6: Ip6 }
type Endpoint = struct { address: Address, port: u16 }
type Family = enum u8 { Any, Ip4, Ip6 }
type Shutdown = enum u8 { Read, Write, Both }

error NotFound
error Refused
error Reset
error Timeout
error AddressInUse
error Unreachable
error Failed

fn hex_value(byte: u8) -> (usize, bool) {
    if byte >= 48u8 && byte <= 57u8 { ret (usize(byte - 48u8), true) }
    if byte >= 97u8 && byte <= 102u8 { ret (usize(byte - 97u8) + 10usize, true) }
    if byte >= 65u8 && byte <= 70u8 { ret (usize(byte - 65u8) + 10usize, true) }
    ret (0usize, false)
}

fn parse_ip4(text: str) -> (Ip4, bool) {
    var address: Ip4 = zero
    var at = 0usize
    var part = 0usize
    while part < 4usize {
        let first = at
        var value = 0usize
        while at < text.len && text[at] >= 48u8 && text[at] <= 57u8 {
            if at - first == 3usize { ret (address, false) }
            value = value * 10usize + usize(text[at] - 48u8)
            if value > 255usize { ret (address, false) }
            at += 1usize
        }
        let digits = at - first
        if digits == 0usize || digits > 3usize || value > 255usize { ret (address, false) }
        // Leading zeroes have historically meant octal to some APIs. Refuse the
        // ambiguity instead of letting two spellings denote different addresses.
        if digits > 1usize && text[first] == 48u8 { ret (address, false) }
        address.bytes[part] = u8(value)
        part += 1usize
        if part < 4usize {
            if at >= text.len || text[at] != 46u8 { ret (address, false) }
            at += 1usize
        }
    }
    if at != text.len { ret (address, false) }
    ret (address, true)
}

fn parse_scope(text: str) -> (str, u32, bool) {
    var percent = text.len
    var at = 0usize
    while at < text.len {
        if text[at] == 37u8 {
            if percent != text.len { ret ("", 0u32, false) }
            percent = at
        }
        at += 1usize
    }
    if percent == text.len { ret (text, 0u32, true) }
    if percent == 0usize || percent + 1usize == text.len { ret ("", 0u32, false) }
    var scope = 0u64
    at = percent + 1usize
    while at < text.len {
        let byte = text[at]
        if byte < 48u8 || byte > 57u8 { ret ("", 0u32, false) }
        let digit = u64(byte - 48u8)
        if scope > 429496729u64 || (scope == 429496729u64 && digit > 5u64) { ret ("", 0u32, false) }
        scope = scope * 10u64 + digit
        at += 1usize
    }
    ret (text[..percent], u32(scope), true)
}

fn parse_ip6(source: str) -> (Ip6, bool) {
    var address: Ip6 = zero
    let (text, scope, scope_ok) = parse_scope(source)
    if !scope_ok { ret (address, false) }
    address.scope = scope
    var head: [16]u8 = zero
    var tail: [16]u8 = zero
    var head_len = 0usize
    var tail_len = 0usize
    var compressed = false
    var at = 0usize
    if text.len < 2usize { ret (address, false) }
    if text[0usize] == 58u8 {
        if text[1usize] != 58u8 { ret (address, false) }
        compressed = true
        at = 2usize
        if at == text.len { ret (address, true) }
    }
    while at < text.len {
        var value = 0usize
        var digits = 0usize
        var scan = at
        while scan < text.len {
            let (nibble, is_hex) = hex_value(text[scan])
            if !is_hex { break }
            if digits == 4usize { ret (address, false) }
            value = value * 16usize + nibble
            digits += 1usize
            scan += 1usize
        }
        if digits == 0usize || digits > 4usize { ret (address, false) }
        if scan < text.len && text[scan] == 46u8 {
            let (embedded, embedded_ok) = parse_ip4(text[at..])
            if !embedded_ok { ret (address, false) }
            var quad = 0usize
            while quad < 4usize {
                if compressed {
                    if tail_len == 16usize { ret (address, false) }
                    tail[tail_len] = embedded.bytes[quad]
                    tail_len += 1usize
                } else {
                    if head_len == 16usize { ret (address, false) }
                    head[head_len] = embedded.bytes[quad]
                    head_len += 1usize
                }
                quad += 1usize
            }
            at = text.len
            break
        }
        at = scan
        if compressed {
            if tail_len + 2usize > 16usize { ret (address, false) }
            tail[tail_len] = u8(value / 256usize)
            tail[tail_len + 1usize] = u8(value % 256usize)
            tail_len += 2usize
        } else {
            if head_len + 2usize > 16usize { ret (address, false) }
            head[head_len] = u8(value / 256usize)
            head[head_len + 1usize] = u8(value % 256usize)
            head_len += 2usize
        }
        if at == text.len { break }
        if text[at] != 58u8 { ret (address, false) }
        at += 1usize
        if at < text.len && text[at] == 58u8 {
            if compressed { ret (address, false) }
            compressed = true
            at += 1usize
            if at == text.len { break }
        } else {
            if at == text.len { ret (address, false) }
        }
    }
    if !compressed && head_len != 16usize { ret (address, false) }
    // `::` must replace at least one complete group.
    if compressed && head_len + tail_len >= 16usize { ret (address, false) }
    var index = 0usize
    while index < head_len {
        address.bytes[index] = head[index]
        index += 1usize
    }
    index = 0usize
    while index < tail_len {
        address.bytes[16usize - tail_len + index] = tail[index]
        index += 1usize
    }
    ret (address, true)
}

fn parse_ip(s: str) -> (Address, err) {
    var out: Address = zero
    let (four, is_four) = parse_ip4(s)
    if is_four { ret (Address{ Ip4: four }, ok) }
    let (six, is_six) = parse_ip6(s)
    if is_six { ret (Address{ Ip6: six }, ok) }
    ret (out, Failed)
}

fn put(dst: []u8, at: usize, byte: u8) -> (usize, bool) {
    if at == dst.len { ret (at, false) }
    dst[at] = byte
    ret (at + 1usize, true)
}

fn put_decimal(dst: []u8, at: usize, value: u32) -> (usize, bool) {
    var digits: [10]u8 = zero
    var first = digits.len
    var rest = value
    while true {
        first -= 1usize
        digits[first] = u8(rest % 10u32) + 48u8
        rest /= 10u32
        if rest == 0u32 { break }
    }
    var out = at
    var index = first
    while index < digits.len {
        let (next, wrote) = put(dst, out, digits[index])
        if !wrote { ret (at, false) }
        out = next
        index += 1usize
    }
    ret (out, true)
}

fn put_hex(dst: []u8, at: usize, value: u16) -> (usize, bool) {
    var digits: [4]u8 = zero
    var first = digits.len
    var rest = value
    while true {
        first -= 1usize
        let nibble = u8(rest % 16u16)
        if nibble < 10u8 { digits[first] = nibble + 48u8 } else { digits[first] = nibble - 10u8 + 97u8 }
        rest /= 16u16
        if rest == 0u16 { break }
    }
    var out = at
    var index = first
    while index < digits.len {
        let (next, wrote) = put(dst, out, digits[index])
        if !wrote { ret (at, false) }
        out = next
        index += 1usize
    }
    ret (out, true)
}

fn format_ip4(address: Ip4, dst: []u8) -> (str, err) {
    var at = 0usize
    var part = 0usize
    while part < 4usize {
        if part != 0usize {
            let (next, wrote) = put(dst, at, 46u8)
            if !wrote { ret ("", Failed) }
            at = next
        }
        let (next, wrote) = put_decimal(dst, at, u32(address.bytes[part]))
        if !wrote { ret ("", Failed) }
        at = next
        part += 1usize
    }
    ret (dst[..at], ok)
}

fn format_ip6(address: Ip6, dst: []u8) -> (str, err) {
    var groups: [8]u16 = zero
    var index = 0usize
    while index < 8usize {
        groups[index] = u16(address.bytes[index * 2usize]) * 256u16 + u16(address.bytes[index * 2usize + 1usize])
        index += 1usize
    }
    // RFC 5952: compress the first longest zero run, but never a single group.
    var best_at = 8usize
    var best_len = 0usize
    index = 0usize
    while index < 8usize {
        if groups[index] != 0u16 {
            index += 1usize
        } else {
            let start = index
            while index < 8usize && groups[index] == 0u16 { index += 1usize }
            let length = index - start
            if length > best_len && length >= 2usize {
                best_at = start
                best_len = length
            }
        }
    }
    var at = 0usize
    index = 0usize
    while index < 8usize {
        if index == best_at {
            let (first_colon, first_ok) = put(dst, at, 58u8)
            if !first_ok { ret ("", Failed) }
            let (second_colon, second_ok) = put(dst, first_colon, 58u8)
            if !second_ok { ret ("", Failed) }
            at = second_colon
            index += best_len
        } else {
            if index != 0usize && index != best_at + best_len {
                let (colon, colon_ok) = put(dst, at, 58u8)
                if !colon_ok { ret ("", Failed) }
                at = colon
            }
            let (next, wrote) = put_hex(dst, at, groups[index])
            if !wrote { ret ("", Failed) }
            at = next
            index += 1usize
        }
    }
    if address.scope != 0u32 {
        let (percent, percent_ok) = put(dst, at, 37u8)
        if !percent_ok { ret ("", Failed) }
        let (next, scope_ok) = put_decimal(dst, percent, address.scope)
        if !scope_ok { ret ("", Failed) }
        at = next
    }
    ret (dst[..at], ok)
}

fn format_ip(address: Address, dst: []u8) -> (str, err) {
    switch address {
    case .Ip4 as four:
        let (text, format_error) = format_ip4(four, dst)
        ret (text, format_error)
    case .Ip6 as six:
        let (text, format_error) = format_ip6(six, dst)
        ret (text, format_error)
    default:
        ret ("", Failed)
    }
}
