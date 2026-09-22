// UUIDs as 16 bytes in RFC 9562's field order, which is the order they are written
// and compared in. Entropy and time come from the caller: this module reads no clock
// and no random source, so a UUID built here is reproducible from its inputs and the
// module has no dependency on `e.os` at all.

use e.algo.hash
use e.algo.rand
use e.crypto.hash as crypto_hash
use e.str

type Uuid = struct { bytes: [16]u8 }

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

// The identifiers below are D885. A ULID is 16 bytes in the same layout as a
// UUID (a 48-bit big-endian millisecond count, then 80 bits of entropy), so it
// shares `Uuid`, its comparison and its byte-order sorting; the text form is
// `ulid_format`'s Crockford base32. Entropy still comes from the caller, as a
// `rand.Pcg64`, so every identifier here reproduces from its inputs.

// A Snowflake generator: 41 bits of milliseconds since `epoch_ms`, 10 of
// `worker`, 12 of sequence within the millisecond.
type Snowflake = struct { epoch_ms: u64, worker: u64, last_ms: u64, sequence: u64 }

// Version 5 (RFC 9562 section 5.5): SHA-1 over the namespace bytes followed by
// `name`, with the version and variant bits set; `scratch.len >= 16 + name.len`
// holds the concatenation `legacy_sha1` hashes in one piece.
fn v5(namespace: Uuid, name: []const u8, scratch: []u8) -> (Uuid, err) {
    var u: Uuid = zero
    if scratch.len < 16usize + name.len { ret (u, Invalid) }
    var at = 0usize
    while at < 16usize {
        scratch[at] = namespace.bytes[at]
        at += 1usize
    }
    at = 0usize
    while at < name.len {
        scratch[16usize + at] = name[at]
        at += 1usize
    }
    let digest = crypto_hash.legacy_sha1(scratch[..16usize + name.len])
    at = 0usize
    while at < 16usize {
        u.bytes[at] = digest[at]
        at += 1usize
    }
    u.bytes[6usize] = (u.bytes[6usize] & 15u8) | 80u8
    u.bytes[8usize] = (u.bytes[8usize] & 63u8) | 128u8
    ret (u, ok)
}

// The RFC's DNS and URL name spaces.
fn namespace_dns() -> Uuid {
    let (u, _) = parse("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
    ret u
}

fn namespace_url() -> Uuid {
    let (u, _) = parse("6ba7b811-9dad-11d1-80b4-00c04fd430c8")
    ret u
}

// A ULID: the 48-bit millisecond count, then 80 bits from the caller's PCG (one
// whole draw big-endian, then the low 16 bits of a second). A count past 48
// bits is `Invalid`, as for `v7`.
fn ulid(unix_millis: u64, r: *rand.Pcg64) -> (Uuid, err) {
    var u: Uuid = zero
    if unix_millis >= 281474976710656u64 { ret (u, Invalid) }
    var shift = 40u64
    var at = 0usize
    while at < 6usize {
        u.bytes[at] = u8((unix_millis >> shift) & 255u64)
        shift = shift -% 8u64
        at += 1usize
    }
    let high = rand.pcg64_next(r)
    shift = 56u64
    at = 0usize
    while at < 8usize {
        u.bytes[6usize + at] = u8((high >> shift) & 255u64)
        shift = shift -% 8u64
        at += 1usize
    }
    let low = rand.pcg64_next(r)
    u.bytes[14usize] = u8((low >> 8u64) & 255u64)
    u.bytes[15usize] = u8(low & 255u64)
    ret (u, ok)
}

// The monotonic variant: within the millisecond of `previous` (or with a clock
// that went backwards) the entropy is incremented instead of redrawn, so the
// ULIDs of one millisecond still sort by creation; an entropy overflow is
// `Invalid`. A later millisecond draws afresh.
fn ulid_monotonic(previous: Uuid, unix_millis: u64, r: *rand.Pcg64) -> (Uuid, err) {
    var stamp = 0u64
    var at = 0usize
    while at < 6usize {
        stamp = (stamp << 8u64) | u64(previous.bytes[at])
        at += 1usize
    }
    if unix_millis > stamp {
        let (fresh, fresh_error) = ulid(unix_millis, r)
        ret (fresh, fresh_error)
    }
    var u = previous
    at = 16usize
    while at > 6usize {
        at -= 1usize
        if u.bytes[at] != 255u8 {
            u.bytes[at] = u.bytes[at] + 1u8
            ret (u, ok)
        }
        u.bytes[at] = 0u8
    }
    ret (previous, Invalid)
}

// Five bits of the 128-bit big-endian value from bit `low` up (bit 0 the last
// byte's lowest); bits past the top read as zero.
fn ulid_bits(u: Uuid, low: usize) -> usize {
    var v = 0usize
    var i = 0usize
    while i < 5usize {
        let b = low + i
        if b < 128usize {
            let bit = (u.bytes[15usize - b / 8usize] >> u8(b % 8usize)) & 1u8
            v = v | (usize(bit) << u32(i))
        }
        i += 1usize
    }
    ret v
}

// The 26-character Crockford base32 form (the first character carries the top
// three bits, so the largest is `7ZZZ...`) into `dst`, answering what it wrote.
fn ulid_format(u: Uuid, dst: []u8) -> (str, err) {
    if dst.len < 26usize { ret ("", Invalid) }
    let alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    var k = 0usize
    while k < 26usize {
        dst[k] = alphabet[ulid_bits(u, 125usize - 5usize * k)]
        k += 1usize
    }
    ret (dst[0usize..26usize], ok)
}

// A Snowflake generator for `worker` (below 1024) counting from `epoch_ms`.
fn snowflake(epoch_ms: u64, worker: u64) -> (Snowflake, err) {
    if worker >= 1024u64 { ret (zero, Invalid) }
    ret (Snowflake { epoch_ms: epoch_ms, worker: worker, last_ms: 0u64, sequence: 0u64 }, ok)
}

// The next id at the caller's clock `now_ms`. The 12-bit sequence counts the
// ids of one millisecond and rolls over into the next one, so ids stay
// strictly increasing until the clock catches up; a clock behind the last id,
// or before the epoch, or a stamp past 41 bits, is `Invalid`.
fn snowflake_next(g: *Snowflake, now_ms: u64) -> (u64, err) {
    if now_ms < g.last_ms || now_ms < g.epoch_ms { ret (0u64, Invalid) }
    if now_ms == g.last_ms {
        g.sequence = (g.sequence + 1u64) & 4095u64
        if g.sequence == 0u64 { g.last_ms += 1u64 }
    } else {
        g.last_ms = now_ms
        g.sequence = 0u64
    }
    let elapsed = g.last_ms - g.epoch_ms
    if elapsed >= 2199023255552u64 { ret (0u64, Invalid) }
    ret ((elapsed << 22u64) | (g.worker << 12u64) | g.sequence, ok)
}

// Nano ID over the 64-symbol URL alphabet `_-0-9a-zA-Z`: every byte of the
// caller's PCG (low byte first) masks to one symbol, the reference algorithm's
// mask step, which for a 64-symbol alphabet rejects nothing. Fills all of
// `dst`: 21 slots for the standard length.
fn nanoid(r: *rand.Pcg64, dst: []u8) -> str {
    let alphabet = "_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    var at = 0usize
    while at < dst.len {
        let draw = rand.pcg64_next(r)
        var k = 0u64
        while k < 8u64 && at < dst.len {
            dst[at] = alphabet[usize((draw >> (8u64 * k)) & 63u64)]
            at += 1usize
            k += 1u64
        }
    }
    ret dst
}
