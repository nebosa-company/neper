// WOFF 1.0 to sfnt (L043), after Vaper's `woffToSfnt`: the 44-byte header (`wOFF`, the sfnt flavor, the table count) and the
// 20-byte directory entries (tag, offset, compressed length, original length, checksum), each table zlib-inflated when its
// compressed length is below its original length and stored otherwise; the sfnt is rebuilt with the offset table, a
// tag-sorted 16-byte directory entry per table and the tables padded to four bytes. Any short, inconsistent or
// uncompressible input is `Invalid`; WOFF2 is `e.fmt.woff2`.
//
// ponytail: an inflated table is held to 64 MiB, where the reference allocates whatever the header claims.
//
// Memory: the arena is retained; the sfnt lives in it.

use e.mem
use e.algo.deflate as deflate
use e.algo.hash as hash

error Invalid

const LIMIT: usize = 67108864usize

type Entry = struct { tag: u32, checksum: u32, data: []const u8 }

fn be32(b: []const u8, at: usize) -> u32 {
    ret (u32(b[at]) << 24u32) | (u32(b[at + 1usize]) << 16u32) | (u32(b[at + 2usize]) << 8u32) | u32(b[at + 3usize])
}

fn put32(b: []u8, at: usize, v: u32) {
    b[at] = u8(v >> 24u32)
    b[at + 1usize] = u8((v >> 16u32) & 255u32)
    b[at + 2usize] = u8((v >> 8u32) & 255u32)
    b[at + 3usize] = u8(v & 255u32)
}

fn put16(b: []u8, at: usize, v: u32) {
    b[at] = u8((v >> 8u32) & 255u32)
    b[at + 1usize] = u8(v & 255u32)
}

// `raw` (a zlib stream: header, deflate data, big-endian Adler-32) inflated into exactly `want` bytes, or `Invalid`.
fn inflate(a: *mem.Arena, window: []u8, raw: []const u8, want: usize) -> ([]u8, err) {
    if want > LIMIT || raw.len < 6usize { ret (zero, Invalid) }
    let cmf = u32(raw[0])
    let flg = u32(raw[1])
    if (cmf & 15u32) != 8u32 || (cmf >> 4u32) > 7u32 { ret (zero, Invalid) }
    if (cmf * 256u32 + flg) % 31u32 != 0u32 || (flg & 32u32) != 0u32 { ret (zero, Invalid) }
    let (out, ae) = mem.alloc[u8](a, want + 1usize)
    if ae != ok { ret (zero, ae) }
    let (made, de) = deflate.decoder(window, 32768usize)
    if de != ok { ret (zero, Invalid) }
    var d = made
    let body = raw[2..]
    let (used, written, status, ie) = deflate.decode(&d, body, out, true)
    if ie != ok || status != .Finished || written != want { ret (zero, Invalid) }
    var trailer: [8]u8 = zero
    let held = deflate.leftover(&d, trailer[0..])
    var have = held
    var at = used
    while have < 4usize {
        if at >= body.len { ret (zero, Invalid) }
        trailer[have] = body[at]
        have += 1usize
        at += 1usize
    }
    let expected = (u32(trailer[0]) << 24u32) | (u32(trailer[1]) << 16u32) | (u32(trailer[2]) << 8u32) | u32(trailer[3])
    if expected != hash.adler32(out[..want]) { ret (zero, Invalid) }
    ret (out[..want], ok)
}

// The sfnt bytes for a WOFF font.
fn to_sfnt(a: *mem.Arena, bytes: []const u8) -> ([]u8, err) {
    if bytes.len < 44usize { ret (zero, Invalid) }
    if be32(bytes, 0usize) != 0x774F4646u32 { ret (zero, Invalid) }
    let flavor = be32(bytes, 4usize)
    let count = usize((u32(bytes[12]) << 8u32) | u32(bytes[13]))
    if count == 0usize { ret (zero, Invalid) }
    let (entries, ee) = mem.alloc[Entry](a, count)
    if ee != ok { ret (zero, ee) }
    let (window_size, we) = deflate.decoder_storage(32768usize)
    if we != ok { ret (zero, we) }
    let (storage, se) = mem.alloc[u8](a, window_size)
    if se != ok { ret (zero, se) }
    var p = 44usize
    var i = 0usize
    while i < count {
        if p + 20usize > bytes.len { ret (zero, Invalid) }
        let offset = usize(be32(bytes, p + 4usize))
        let comp = usize(be32(bytes, p + 8usize))
        let orig = usize(be32(bytes, p + 12usize))
        if offset + comp > bytes.len { ret (zero, Invalid) }
        let raw = bytes[offset..offset + comp]
        var data: []const u8 = raw
        if comp < orig {
            let (inflated, ie) = inflate(a, storage, raw, orig)
            if ie != ok { ret (zero, Invalid) }
            data = inflated
        }
        entries[i] = Entry { tag: be32(bytes, p), checksum: be32(bytes, p + 16usize), data: data }
        p += 20usize
        i += 1usize
    }
    // Insertion sort by tag: the sfnt directory is ordered.
    i = 1usize
    while i < count {
        let cur = entries[i]
        var j = i
        while j > 0usize && entries[j - 1usize].tag > cur.tag {
            entries[j] = entries[j - 1usize]
            j -= 1usize
        }
        entries[j] = cur
        i += 1usize
    }
    var search = 16usize
    var selector = 0usize
    while search * 2usize <= count * 16usize {
        search *= 2usize
        selector += 1usize
    }
    var total = 12usize + count * 16usize
    i = 0usize
    while i < count {
        total += entries[i].data.len
        total += (4usize - (entries[i].data.len & 3usize)) & 3usize
        i += 1usize
    }
    let (out, oe) = mem.alloc[u8](a, total)
    if oe != ok { ret (zero, oe) }
    var z = 0usize
    while z < total {
        out[z] = 0u8
        z += 1usize
    }
    put32(out, 0usize, flavor)
    put16(out, 4usize, u32(count))
    put16(out, 6usize, u32(search))
    put16(out, 8usize, u32(selector))
    put16(out, 10usize, u32(count * 16usize - search))
    var dir = 12usize
    var at = 12usize + count * 16usize
    i = 0usize
    while i < count {
        let e = entries[i]
        put32(out, dir, e.tag)
        put32(out, dir + 4usize, e.checksum)
        put32(out, dir + 8usize, u32(at))
        put32(out, dir + 12usize, u32(e.data.len))
        var k = 0usize
        while k < e.data.len {
            out[at + k] = e.data[k]
            k += 1usize
        }
        at += e.data.len + ((4usize - (e.data.len & 3usize)) & 3usize)
        dir += 16usize
        i += 1usize
    }
    ret (out, ok)
}
