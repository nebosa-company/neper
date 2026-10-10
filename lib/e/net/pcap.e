// Capture files (L051): the classic pcap format in both byte orders and both timestamp resolutions (microsecond
// `a1b2c3d4`, nanosecond `a1b23c4d`) and pcapng (section header, interface description with `if_tsresol`, enhanced and
// simple packet blocks; other blocks skipped), read over a caller's bytes with every length checked before it is used --
// a record or block that runs past the data is `Truncated`, a header, length or magic that cannot be is `Invalid`; the
// record data borrows from the input. A writer produces classic little-endian microsecond files. Link types are the
// registry's numbers (1 Ethernet, 101 raw IP, 113 Linux cooked).
//
// Memory: the reader allocates nothing; the writer fills the buffer given.

error Truncated
error Invalid

type Reader = struct { data: []const u8, at: usize, big_endian: bool, nanos: bool, pcapng: bool, linktype: u32, snaplen: u32, if_count: usize, if_linktypes: [16]u32, if_resolution: [16]u32 }

// One captured packet: seconds and nanoseconds since the epoch, captured and original lengths, the interface's link type.
type Record = struct { ts_sec: u64, ts_nsec: u32, caplen: u32, origlen: u32, linktype: u32, data: []const u8 }

fn u16_at(b: []const u8, at: usize, big: bool) -> u32 {
    if big { ret (u32(b[at]) << 8u32) | u32(b[at + 1usize]) }
    ret (u32(b[at + 1usize]) << 8u32) | u32(b[at])
}

fn u32_at(b: []const u8, at: usize, big: bool) -> u32 {
    if big { ret (u32(b[at]) << 24u32) | (u32(b[at + 1usize]) << 16u32) | (u32(b[at + 2usize]) << 8u32) | u32(b[at + 3usize]) }
    ret (u32(b[at + 3usize]) << 24u32) | (u32(b[at + 2usize]) << 16u32) | (u32(b[at + 1usize]) << 8u32) | u32(b[at])
}

// Starts reading a capture: classic pcap or a pcapng section.
fn open(data: []const u8) -> (Reader, err) {
    var r: Reader = zero
    r.data = data
    if data.len < 4usize { ret (r, Truncated) }
    let magic_be = u32_at(data, 0usize, true)
    if magic_be == 0x0A0D0D0Au32 {
        // 0x0A0D0D0A: pcapng section header block
        if data.len < 12usize { ret (r, Truncated) }
        let order = u32_at(data, 8usize, true)
        if order == 0x1A2B3C4Du32 {
            r.big_endian = true
        } else if order == u32_at(data, 8usize, false) && u32_at(data, 8usize, false) == 0x1A2B3C4Du32 {
            r.big_endian = false
        } else {
            let le = u32_at(data, 8usize, false)
            if le != 0x1A2B3C4Du32 { ret (r, Invalid) }
            r.big_endian = false
        }
        r.pcapng = true
        r.at = 0usize
        ret (r, ok)
    }
    if data.len < 24usize { ret (r, Truncated) }
    if magic_be == 0xA1B2C3D4u32 {
        r.big_endian = true
        r.nanos = false
    } else if magic_be == 0xA1B23C4Du32 {
        r.big_endian = true
        r.nanos = true
    } else {
        let magic_le = u32_at(data, 0usize, false)
        if magic_le == 0xA1B2C3D4u32 {
            r.big_endian = false
            r.nanos = false
        } else if magic_le == 0xA1B23C4Du32 {
            r.big_endian = false
            r.nanos = true
        } else {
            ret (r, Invalid)
        }
    }
    r.snaplen = u32_at(data, 16usize, r.big_endian)
    r.linktype = u32_at(data, 20usize, r.big_endian) & 65535u32
    r.at = 24usize
    ret (r, ok)
}

fn pow10(n: u32) -> u64 {
    var v = 1u64
    var i = 0u32
    while i < n && i < 19u32 {
        v *= 10u64
        i += 1u32
    }
    ret v
}

// The next packet, or false at the end of the file. A damaged tail is an error, never a short record.
fn next(r: *Reader) -> (Record, bool, err) {
    var rec: Record = zero
    if !r.pcapng {
        if r.at == r.data.len { ret (rec, false, ok) }
        if r.data.len - r.at < 16usize { ret (rec, false, Truncated) }
        let sec = u32_at(r.data, r.at, r.big_endian)
        let frac = u32_at(r.data, r.at + 4usize, r.big_endian)
        let caplen = u32_at(r.data, r.at + 8usize, r.big_endian)
        let origlen = u32_at(r.data, r.at + 12usize, r.big_endian)
        if caplen > origlen && origlen != 0u32 && caplen > r.snaplen { ret (rec, false, Invalid) }
        let start = r.at + 16usize
        if usize(caplen) > r.data.len - start { ret (rec, false, Truncated) }
        if r.nanos {
            if frac >= 1000000000u32 { ret (rec, false, Invalid) }
            rec.ts_nsec = frac
        } else {
            if frac >= 1000000u32 { ret (rec, false, Invalid) }
            rec.ts_nsec = frac * 1000u32
        }
        rec.ts_sec = u64(sec)
        rec.caplen = caplen
        rec.origlen = origlen
        rec.linktype = r.linktype
        rec.data = r.data[start..start + usize(caplen)]
        r.at = start + usize(caplen)
        ret (rec, true, ok)
    }
    while true {
        if r.at == r.data.len { ret (rec, false, ok) }
        if r.data.len - r.at < 12usize { ret (rec, false, Truncated) }
        let kind = u32_at(r.data, r.at, r.big_endian)
        var big = r.big_endian
        let total = usize(u32_at(r.data, r.at + 4usize, big))
        if total < 12usize || (total & 3usize) != 0usize { ret (rec, false, Invalid) }
        if total > r.data.len - r.at { ret (rec, false, Truncated) }
        if u32_at(r.data, r.at + total - 4usize, big) != u32(total) { ret (rec, false, Invalid) }
        let body = r.at + 8usize
        let end = r.at + total - 4usize
        if kind == 1u32 {
            if end - body < 8usize { ret (rec, false, Invalid) }
            if r.if_count < 16usize {
                r.if_linktypes[r.if_count] = u16_at(r.data, body, big)
                var resolution = 6u32
                // options: code u16, length u16, value padded to 4, ending with code 0
                var o = body + 8usize
                while o + 4usize <= end {
                    let code = u16_at(r.data, o, big)
                    let length = usize(u16_at(r.data, o + 2usize, big))
                    if code == 0u32 { break }
                    if o + 4usize + length > end { ret (rec, false, Invalid) }
                    if code == 9u32 && length >= 1usize {
                        let v = u32(r.data[o + 4usize])
                        if (v & 128u32) == 0u32 { resolution = v }
                    }
                    o += 4usize + ((length + 3usize) & ~3usize)
                }
                r.if_resolution[r.if_count] = resolution
                r.if_count += 1usize
            }
        } else if kind == 6u32 {
            if end - body < 20usize { ret (rec, false, Invalid) }
            let iface = usize(u32_at(r.data, body, big))
            let high = u64(u32_at(r.data, body + 4usize, big))
            let low = u64(u32_at(r.data, body + 8usize, big))
            let caplen = u32_at(r.data, body + 12usize, big)
            let origlen = u32_at(r.data, body + 16usize, big)
            if usize(caplen) > end - (body + 20usize) { ret (rec, false, Truncated) }
            var resolution = 6u32
            var linktype = 0u32
            if iface < r.if_count {
                resolution = r.if_resolution[iface]
                linktype = r.if_linktypes[iface]
            }
            let ticks = (high << 32u64) | low
            let unit = pow10(resolution)
            rec.ts_sec = ticks / unit
            let rem = ticks % unit
            if resolution <= 9u32 {
                rec.ts_nsec = u32(rem * (1000000000u64 / unit))
            } else {
                rec.ts_nsec = u32(rem / (unit / 1000000000u64))
            }
            rec.caplen = caplen
            rec.origlen = origlen
            rec.linktype = linktype
            rec.data = r.data[body + 20usize..body + 20usize + usize(caplen)]
            r.at += total
            ret (rec, true, ok)
        } else if kind == 3u32 {
            if end - body < 4usize { ret (rec, false, Invalid) }
            let origlen = u32_at(r.data, body, big)
            var caplen = origlen
            if usize(caplen) > end - (body + 4usize) { caplen = u32(end - (body + 4usize)) }
            rec.caplen = caplen
            rec.origlen = origlen
            if r.if_count > 0usize { rec.linktype = r.if_linktypes[0] }
            rec.data = r.data[body + 4usize..body + 4usize + usize(caplen)]
            r.at += total
            ret (rec, true, ok)
        } else if kind == 0x0A0D0D0Au32 {
            // a new section: its own byte order
            if end - body < 4usize { ret (rec, false, Invalid) }
            if u32_at(r.data, body, true) == 0x1A2B3C4Du32 {
                r.big_endian = true
            } else if u32_at(r.data, body, false) == 0x1A2B3C4Du32 {
                r.big_endian = false
            } else {
                ret (rec, false, Invalid)
            }
            r.if_count = 0usize
        }
        r.at += total
    }
    ret (rec, false, ok)
}

fn put16(b: []u8, at: usize, v: u32) {
    b[at] = u8(v & 255u32)
    b[at + 1usize] = u8((v >> 8u32) & 255u32)
}

fn put32(b: []u8, at: usize, v: u32) {
    b[at] = u8(v & 255u32)
    b[at + 1usize] = u8((v >> 8u32) & 255u32)
    b[at + 2usize] = u8((v >> 16u32) & 255u32)
    b[at + 3usize] = u8((v >> 24u32) & 255u32)
}

// The 24-byte global header of a little-endian microsecond classic file; returns 24.
fn write_header(buf: []u8, linktype: u32, snaplen: u32) -> usize {
    put32(buf, 0usize, 0xA1B2C3D4u32)
    put16(buf, 4usize, 2u32)
    put16(buf, 6usize, 4u32)
    put32(buf, 8usize, 0u32)
    put32(buf, 12usize, 0u32)
    put32(buf, 16usize, snaplen)
    put32(buf, 20usize, linktype)
    ret 24usize
}

// One record (16-byte header then the data); `usec` below a million; returns the bytes written.
fn write_record(buf: []u8, ts_sec: u32, usec: u32, data: []const u8, origlen: u32) -> usize {
    put32(buf, 0usize, ts_sec)
    put32(buf, 4usize, usec)
    put32(buf, 8usize, u32(data.len))
    put32(buf, 12usize, origlen)
    var i = 0usize
    while i < data.len {
        buf[16usize + i] = data[i]
        i += 1usize
    }
    ret 16usize + data.len
}
