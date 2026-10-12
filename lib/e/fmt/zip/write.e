// ZIP writing (L100): a package of named parts stored as-is (method 0), each local header
// followed by its bytes, then the central directory and the end record -- the layout
// `e.fmt.zip` reads back and Python's zipfile writes for `ZIP_STORED`. The DOS date is
// 1980-01-01 00:00 so the same parts always give the same bytes, which is what a
// package that is diffed, signed or checked in wants. Nothing is compressed: Office
// readers accept stored parts, and the DEFLATE encoder belongs to a later slice.
//
// Limits are the classic (non-ZIP64) ones: 65535 parts, 4 GiB - 1 in total, a 65535-byte
// name. A name `e.fmt.zip` would refuse (absolute, `..`, backslash, drive) is `BadName`.
//
// Memory: the whole package is one allocation from the arena passed in.
use e.mem
use e.fmt.zip as zip
use e.algo.hash as hash

error BadName
error TooLarge

type Part = struct { name: str, data: []const u8 }

const MAX_PARTS: usize = 65535usize
const MAX_TOTAL: usize = 4294967295usize

fn put16(out: []u8, at: usize, v: u32) {
    out[at] = u8(v & 255u32)
    out[at + 1usize] = u8((v >> 8u32) & 255u32)
}

fn put32(out: []u8, at: usize, v: u32) {
    put16(out, at, v & 65535u32)
    put16(out, at + 2usize, v >> 16u32)
}

fn put_bytes(out: []u8, at: usize, src: []const u8) {
    var i = 0usize
    while i < src.len {
        out[at + i] = src[i]
        i += 1usize
    }
}

// The package holding `parts` in order, every one stored.
fn store(a: *mem.Arena, parts: []const Part) -> ([]u8, err) {
    if parts.len == 0usize || parts.len > MAX_PARTS { ret (zero, TooLarge) }
    var total = 22usize
    var i = 0usize
    while i < parts.len {
        let p = parts[i]
        if !zip.name_legal(p.name) || p.name.len > 65535usize { ret (zero, BadName) }
        if p.data.len > MAX_TOTAL { ret (zero, TooLarge) }
        total += 30usize + p.name.len + p.data.len + 46usize + p.name.len
        if total > MAX_TOTAL { ret (zero, TooLarge) }
        i += 1usize
    }
    let (out, out_error) = mem.alloc[u8](a, total)
    if out_error != ok { ret (zero, out_error) }
    let (offsets, offsets_error) = mem.alloc[u32](a, parts.len)
    if offsets_error != ok { ret (zero, offsets_error) }
    var at = 0usize
    i = 0usize
    while i < parts.len {
        let p = parts[i]
        offsets[i] = u32(at)
        put32(out, at, 67324752u32)
        put16(out, at + 4usize, 20u32)
        put16(out, at + 6usize, 0u32)
        put16(out, at + 8usize, 0u32)
        put16(out, at + 10usize, 0u32)
        put16(out, at + 12usize, 33u32)
        put32(out, at + 14usize, hash.crc32(p.data))
        put32(out, at + 18usize, u32(p.data.len))
        put32(out, at + 22usize, u32(p.data.len))
        put16(out, at + 26usize, u32(p.name.len))
        put16(out, at + 28usize, 0u32)
        put_bytes(out, at + 30usize, p.name)
        put_bytes(out, at + 30usize + p.name.len, p.data)
        at += 30usize + p.name.len + p.data.len
        i += 1usize
    }
    let directory = at
    i = 0usize
    while i < parts.len {
        let p = parts[i]
        put32(out, at, 33639248u32)
        put16(out, at + 4usize, 20u32)
        put16(out, at + 6usize, 20u32)
        put16(out, at + 8usize, 0u32)
        put16(out, at + 10usize, 0u32)
        put16(out, at + 12usize, 0u32)
        put16(out, at + 14usize, 33u32)
        put32(out, at + 16usize, hash.crc32(p.data))
        put32(out, at + 20usize, u32(p.data.len))
        put32(out, at + 24usize, u32(p.data.len))
        put16(out, at + 28usize, u32(p.name.len))
        put16(out, at + 30usize, 0u32)
        put16(out, at + 32usize, 0u32)
        put16(out, at + 34usize, 0u32)
        put16(out, at + 36usize, 0u32)
        // 0600 in the high half, as Python's zipfile writes for a plain file.
        put32(out, at + 38usize, 25165824u32)
        put32(out, at + 42usize, offsets[i])
        put_bytes(out, at + 46usize, p.name)
        at += 46usize + p.name.len
        i += 1usize
    }
    put32(out, at, 101010256u32)
    put16(out, at + 4usize, 0u32)
    put16(out, at + 6usize, 0u32)
    put16(out, at + 8usize, u32(parts.len))
    put16(out, at + 10usize, u32(parts.len))
    put32(out, at + 12usize, u32(at - directory))
    put32(out, at + 16usize, u32(directory))
    put16(out, at + 20usize, 0u32)
    ret (out, ok)
}
