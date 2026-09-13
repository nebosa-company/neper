// UUIDs as 16 bytes in RFC 9562's field order, which is the order they are written
// and compared in. Entropy and time come from the caller: this module reads no clock
// and no random source, so a UUID built here is reproducible from its inputs and the
// module has no dependency on `e.os` at all.

use e.algo.hash
use e.str

type Uuid = struct {
    bytes: [16]u8,
}

error Invalid

// Version 4 is entropy everywhere except the six bits the version and variant
// fields take.
fn v4(random: [16]u8) -> Uuid {
    var u: Uuid = zero
    var at = 0usize
    while at < 16usize {
        u.bytes[at] = random[at]
        at += 1usize
    }
    u.bytes[6usize] = (u.bytes[6usize] & 15u8) | 64u8
    u.bytes[8usize] = (u.bytes[8usize] & 63u8) | 128u8
    ret u
}

// Version 7 puts a 48-bit big-endian Unix millisecond count in front, so sorting the
// bytes sorts by time. A count that does not fit in 48 bits is `Invalid` rather than
// silently truncated -- it would produce a UUID that sorts before ones made earlier.
fn v7(unix_millis: u64, random: [10]u8) -> (Uuid, err) {
    var u: Uuid = zero
    if unix_millis >= 281474976710656u64 { ret (u, Invalid) }
    var shift = 40u64
    var at = 0usize
    while at < 6usize {
        u.bytes[at] = u8((unix_millis >> shift) & 255u64)
        shift = shift -% 8u64
        at += 1usize
    }
    at = 0usize
    while at < 10usize {
        u.bytes[at + 6usize] = random[at]
        at += 1usize
    }
    u.bytes[6usize] = (u.bytes[6usize] & 15u8) | 112u8
    u.bytes[8usize] = (u.bytes[8usize] & 63u8) | 128u8
    ret (u, ok)
}

// The 36-byte hyphenated form, in either case. Anything else -- a wrong length, a
// hyphen out of place, a brace, a URN prefix -- is `Invalid`: this accepts exactly
// what `format` writes, modulo case.
fn parse(s: str) -> (Uuid, err) {
    var u: Uuid = zero
    if s.len != 36usize { ret (u, Invalid) }
    var at = 0usize
    var written = 0usize
    var high = 0u8
    var have_high = false
    while at < 36usize {
        let byte = s[at]
        if at == 8usize || at == 13usize || at == 18usize || at == 23usize {
            if byte != 45u8 { ret (u, Invalid) }
            at += 1usize
            continue
        }
        var digit = 16u8
        if byte >= 48u8 && byte <= 57u8 { digit = byte - 48u8 }
        if byte >= 97u8 && byte <= 102u8 { digit = byte - 87u8 }
        if byte >= 65u8 && byte <= 70u8 { digit = byte - 55u8 }
        if digit == 16u8 { ret (u, Invalid) }
        if have_high {
            u.bytes[written] = high * 16u8 + digit
            written += 1usize
            have_high = false
        } else {
            high = digit
            have_high = true
        }
        at += 1usize
    }
    if written != 16usize || have_high { ret (u, Invalid) }
    ret (u, ok)
}

// Writes the 36-byte lowercase hyphenated form into `dst` and returns the bytes it
// wrote, so the caller owns the storage and no arena is involved.
fn format(uuid: Uuid, dst: []u8) -> (str, err) {
    if dst.len < 36usize { ret ("", Invalid) }
    var at = 0usize
    var written = 0usize
    while at < 16usize {
        if at == 4usize || at == 6usize || at == 8usize || at == 10usize {
            dst[written] = 45u8
            written += 1usize
        }
        let byte = uuid.bytes[at]
        var high = byte / 16u8
        var low = byte % 16u8
        if high < 10u8 { high = high + 48u8 } else { high = high + 87u8 }
        if low < 10u8 { low = low + 48u8 } else { low = low + 87u8 }
        dst[written] = high
        written += 1usize
        dst[written] = low
        written += 1usize
        at += 1usize
    }
    ret (dst[0usize..36usize], ok)
}

fn version(uuid: Uuid) -> u8 {
    ret uuid.bytes[6usize] >> 4u8
}

// RFC 9562 section 4.1: the variant is read from however many leading bits of octet 8
// are set, so it is 0 for the Apollo NCS layout, 1 for this one, 2 for Microsoft's
// and 3 for the reserved range.
fn variant(uuid: Uuid) -> u8 {
    let octet = uuid.bytes[8usize]
    if octet < 128u8 { ret 0u8 }
    if octet < 192u8 { ret 1u8 }
    if octet < 224u8 { ret 2u8 }
    ret 3u8
}

// Section 9 rule 4's protocol set for `Uuid`. Ordering is over the bytes in field
// order, which for version 7 is time order.
fn uuid_eq(a: Uuid, b: Uuid) -> bool {
    var at = 0usize
    while at < 16usize {
        if a.bytes[at] != b.bytes[at] { ret false }
        at += 1usize
    }
    ret true
}

fn uuid_cmp(a: Uuid, b: Uuid) -> i32 {
    var at = 0usize
    while at < 16usize {
        if a.bytes[at] != b.bytes[at] {
            if a.bytes[at] < b.bytes[at] { ret -1i32 }
            ret 1i32
        }
        at += 1usize
    }
    ret 0i32
}

fn uuid_hash(uuid: Uuid) -> u64 {
    ret hash.xxhash64(uuid.bytes[0usize..16usize], 0u64)
}

fn uuid_format(uuid: Uuid, b: *str.Builder) -> err {
    var text: [36]u8 = zero
    let (written, format_error) = format(uuid, text[0usize..36usize])
    if format_error != ok { ret format_error }
    ret str.push(b, written)
}
