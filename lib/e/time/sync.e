// Clock agreement over caller storage: `marzullo` finds the interval covered
// by the most sources (a sweep over the sorted endpoints) and
// `marzullo_estimate` its midpoint; `berkeley` is the master's step, an
// average of the reported offsets with outliers beyond a tolerance from the
// median dropped, answering every node's adjustment; `cristian` is the
// client's step, the server time plus half the round trip with the bound the
// other half leaves after the minimum one-way delay.

error TooSmall
error Invalid

// The interval [lo, hi] intersected by the most of the `n` source intervals
// `[lows[i], highs[i]]`; `scratch` needs `4 * n` slots. Touching intervals
// count as overlapping. Answers the interval and how many sources cover it.
fn marzullo(lows: []const i64, highs: []const i64, n: usize, scratch: []i64) -> (i64, i64, usize, err) {
    if n == 0usize || n > lows.len || n > highs.len { ret (0i64, 0i64, 0usize, Invalid) }
    if scratch.len < 4usize * n { ret (0i64, 0i64, 0usize, TooSmall) }
    let m = 2usize * n
    let offsets = scratch[..m]
    let kinds = scratch[m..2usize * m]
    var i = 0usize
    while i < n {
        if lows[i] > highs[i] { ret (0i64, 0i64, 0usize, Invalid) }
        offsets[2usize * i] = lows[i]
        kinds[2usize * i] = -1i64
        offsets[2usize * i + 1usize] = highs[i]
        kinds[2usize * i + 1usize] = 1i64
        i += 1usize
    }
    // ponytail: insertion sort, O(n^2) over 2n endpoints; sources are few.
    i = 1usize
    while i < m {
        let o = offsets[i]
        let k = kinds[i]
        var j = i
        while j > 0usize && (offsets[j - 1usize] > o || (offsets[j - 1usize] == o && kinds[j - 1usize] > k)) {
            offsets[j] = offsets[j - 1usize]
            kinds[j] = kinds[j - 1usize]
            j -= 1usize
        }
        offsets[j] = o
        kinds[j] = k
        i += 1usize
    }
    var count = 0i64
    var best = 0i64
    var lo = 0i64
    var hi = 0i64
    i = 0usize
    while i < m {
        count -= kinds[i]
        if count > best {
            best = count
            lo = offsets[i]
            hi = offsets[i + 1usize]
        }
        i += 1usize
    }
    ret (lo, hi, usize(best), ok)
}

// The midpoint of the `marzullo` interval.
fn marzullo_estimate(lows: []const i64, highs: []const i64, n: usize, scratch: []i64) -> (i64, err) {
    let (lo, hi, _, e) = marzullo(lows, highs, n, scratch)
    if e != ok { ret (0i64, e) }
    ret (lo + (hi - lo) / 2i64, ok)
}

// The master's step: `offsets[i]` is node i's clock minus the master's (the
// master itself reports 0 if it takes part). Offsets more than `tolerance`
// from the median are left out of the average; `out[i]` is what node i adds
// to its clock. Division truncates toward zero.
fn berkeley(offsets: []const i64, n: usize, tolerance: i64, out: []i64) -> err {
    if n == 0usize || n > offsets.len || tolerance < 0i64 { ret Invalid }
    if out.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        out[i] = offsets[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let o = out[i]
        var j = i
        while j > 0usize && out[j - 1usize] > o {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = o
        i += 1usize
    }
    let median = out[n / 2usize]
    var sum = 0i64
    var kept = 0i64
    i = 0usize
    while i < n {
        var gap = offsets[i] - median
        if gap < 0i64 { gap = 0i64 - gap }
        if gap <= tolerance {
            sum += offsets[i]
            kept += 1i64
        }
        i += 1usize
    }
    let average = sum / kept
    i = 0usize
    while i < n {
        out[i] = average - offsets[i]
        i += 1usize
    }
    ret ok
}

// The client's step: `t_server` was read while the request was in flight
// between `t0_send` and `t1_receive` on the client's clock. Answers the
// client's estimate of the server's clock at `t1_receive` and the error
// bound, half the round trip less `min_one_way`, the least the network takes.
fn cristian(t0_send: i64, t_server: i64, t1_receive: i64, min_one_way: i64) -> (i64, i64) {
    let rtt = t1_receive - t0_send
    let half = rtt / 2i64
    var bound = half - min_one_way
    if bound < 0i64 { bound = 0i64 }
    ret (t_server + half, bound)
}

// ---- NTP / SNTP wire format (RFC 5905) ----
//
// The 48-byte packet as fields, with no sockets or clock: the caller drives UDP port 123 and
// reads its own clock. A timestamp is the 64-bit NTP fixed point (32 bits of seconds since
// 1900-01-01, 32 of fraction); with the usual pivot (seconds with the top bit set are era 0,
// the rest era 1) it covers 1968-01-20 03:14:08 to 2104-02-26 06:28:16 UTC, and conversions
// outside that are refused. 16.16 "short" values (root delay and dispersion) are nanoseconds
// in and out. Extension fields and the MAC after byte 48 are ignored on decode and never
// written. `offset_delay` is RFC 5905 section 8's clock offset and round-trip delay.

error KissOfDeath
error Unsynchronized
error BadReply
error Mismatch

const NTP_UNIX_DELTA: u64 = 2208988800u64
const NTP_MODE_CLIENT: u8 = 3u8
const NTP_MODE_SERVER: u8 = 4u8

type NtpPacket = struct {
    leap: u8, version: u8, mode: u8, stratum: u8, poll: i32, precision: i32,
    root_delay: u32, root_dispersion: u32, reference_id: u32,
    reference: u64, origin: u64, receive: u64, transmit: u64,
}

fn read_u32(bytes: []const u8, at: usize) -> u32 {
    ret (u32(bytes[at]) << 24u32) | (u32(bytes[at + 1usize]) << 16u32) | (u32(bytes[at + 2usize]) << 8u32) | u32(bytes[at + 3usize])
}

fn read_u64(bytes: []const u8, at: usize) -> u64 {
    ret (u64(read_u32(bytes, at)) << 32u64) | u64(read_u32(bytes, at + 4usize))
}

fn write_u32(out: []u8, at: usize, value: u32) {
    out[at] = u8(value >> 24u32)
    out[at + 1usize] = u8((value >> 16u32) & 255u32)
    out[at + 2usize] = u8((value >> 8u32) & 255u32)
    out[at + 3usize] = u8(value & 255u32)
}

fn write_u64(out: []u8, at: usize, value: u64) {
    write_u32(out, at, u32(value >> 32u64))
    write_u32(out, at + 4usize, u32(value & 4294967295u64))
}

fn signed_byte(b: u8) -> i32 {
    if b >= 128u8 { ret i32(b) - 256i32 }
    ret i32(b)
}

// Parse the first 48 bytes. Fewer is refused.
fn ntp_decode(bytes: []const u8) -> (NtpPacket, err) {
    if bytes.len < 48usize { ret (zero, Invalid) }
    let first = bytes[0usize]
    ret (NtpPacket {
        leap: first >> 6u8, version: (first >> 3u8) & 7u8, mode: first & 7u8, stratum: bytes[1usize],
        poll: signed_byte(bytes[2usize]), precision: signed_byte(bytes[3usize]),
        root_delay: read_u32(bytes, 4usize), root_dispersion: read_u32(bytes, 8usize), reference_id: read_u32(bytes, 12usize),
        reference: read_u64(bytes, 16usize), origin: read_u64(bytes, 24usize), receive: read_u64(bytes, 32usize), transmit: read_u64(bytes, 40usize),
    }, ok)
}

// Write 48 bytes. Refused: leap above 3, version or mode above 7, poll or precision outside -128..127.
fn ntp_encode(p: NtpPacket, out: []u8) -> err {
    if out.len < 48usize { ret TooSmall }
    if p.leap > 3u8 || p.version > 7u8 || p.mode > 7u8 || p.poll < -128i32 || p.poll > 127i32 || p.precision < -128i32 || p.precision > 127i32 { ret Invalid }
    out[0usize] = (p.leap << 6u8) | (p.version << 3u8) | p.mode
    out[1usize] = p.stratum
    out[2usize] = u8((p.poll + 256i32) & 255i32)
    out[3usize] = u8((p.precision + 256i32) & 255i32)
    write_u32(out, 4usize, p.root_delay)
    write_u32(out, 8usize, p.root_dispersion)
    write_u32(out, 12usize, p.reference_id)
    write_u64(out, 16usize, p.reference)
    write_u64(out, 24usize, p.origin)
    write_u64(out, 32usize, p.receive)
    write_u64(out, 40usize, p.transmit)
    ret ok
}

// A client request (mode 3) carrying the client's transmit timestamp. Version 1 to 4.
fn ntp_request(version: u8, transmit: u64) -> (NtpPacket, err) {
    if version < 1u8 || version > 4u8 { ret (zero, Invalid) }
    var p: NtpPacket = zero
    p.version = version
    p.mode = NTP_MODE_CLIENT
    p.transmit = transmit
    ret (p, ok)
}

// A timestamp as Unix nanoseconds (era chosen by the pivot above); the fraction rounds to the nearest nanosecond.
fn ntp_to_unix_nanos(ts: u64) -> i64 {
    var seconds = ts >> 32u64
    var nanos = (((ts & 4294967295u64) * 1000000000u64) + 2147483648u64) >> 32u64
    if nanos >= 1000000000u64 {
        nanos -= 1000000000u64
        seconds += 1u64
    }
    var unix = i64(seconds) - i64(NTP_UNIX_DELTA)
    if (ts >> 32u64) < 2147483648u64 { unix += 4294967296i64 }
    ret unix * 1000000000i64 + i64(nanos)
}

// The timestamp of Unix nanoseconds, the fraction rounded to the nearest 2^-32 s. Instants outside
// 1968-01-20 03:14:08 .. 2104-02-26 06:28:16 UTC are refused.
fn unix_nanos_to_ntp(nanos: i64) -> (u64, err) {
    var seconds = nanos / 1000000000i64
    var rest = nanos % 1000000000i64
    if rest < 0i64 {
        rest += 1000000000i64
        seconds -= 1i64
    }
    var ntp_seconds = seconds + i64(NTP_UNIX_DELTA)
    var fraction = ((u64(rest) << 32u64) + 500000000u64) / 1000000000u64
    if fraction >= 4294967296u64 {
        fraction -= 4294967296u64
        ntp_seconds += 1i64
    }
    if ntp_seconds < 2147483648i64 || ntp_seconds >= 2147483648i64 + 4294967296i64 { ret (0u64, Invalid) }
    ret ((u64(ntp_seconds) & 4294967295u64) << 32u64 | fraction, ok)
}

// A 16.16 value (root delay, root dispersion) as nanoseconds, and back (refused above 65535.99 s or below 0).
fn ntp_short_to_nanos(v: u32) -> i64 {
    ret i64(v >> 16u32) * 1000000000i64 + ((i64(v & 65535u32) * 1000000000i64 + 32768i64) / 65536i64)
}

fn nanos_to_ntp_short(nanos: i64) -> (u32, err) {
    if nanos < 0i64 { ret (0u32, Invalid) }
    let whole = nanos / 1000000000i64
    let rest = nanos % 1000000000i64
    if whole > 65535i64 { ret (0u32, Invalid) }
    var fraction = (rest * 65536i64 + 500000000i64) / 1000000000i64
    var seconds = whole
    if fraction >= 65536i64 {
        fraction -= 65536i64
        seconds += 1i64
        if seconds > 65535i64 { ret (0u32, Invalid) }
    }
    ret (u32(seconds) << 16u32 | u32(fraction), ok)
}

// RFC 5905 section 8 from the four timestamps (client send, server receive, server send, client
// receive), in nanoseconds on any common scale: the offset of the server's clock from the client's
// (positive when the server is ahead) and the round-trip delay. The offset halves toward zero.
fn offset_delay(t1: i64, t2: i64, t3: i64, t4: i64) -> (i64, i64) {
    ret (((t2 - t1) + (t3 - t4)) / 2i64, (t4 - t1) - (t3 - t2))
}

// Whether `reply` is an acceptable answer to a request whose transmit timestamp was `sent`: a server
// (mode 4) of version 3 or 4, echoing `sent` as its origin (`Mismatch` otherwise, the defence against
// spoofed or stale replies), not a kiss-o'-death (stratum 0, `KissOfDeath`), synchronised (leap 3 is
// `Unsynchronized`), a stratum of at most 15 and a transmit time that is set (`BadReply`).
fn ntp_check_reply(sent: u64, reply: NtpPacket) -> err {
    if reply.mode != NTP_MODE_SERVER || reply.version < 3u8 || reply.version > 4u8 { ret BadReply }
    if sent == 0u64 || reply.origin != sent { ret Mismatch }
    if reply.stratum == 0u8 { ret KissOfDeath }
    if reply.leap == 3u8 { ret Unsynchronized }
    if reply.stratum > 15u8 || reply.transmit == 0u64 { ret BadReply }
    ret ok
}
