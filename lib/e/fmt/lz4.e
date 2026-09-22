// LZ4 over caller storage: the block format (a token of two nibbles, 255-extension
// bytes, a two-byte little-endian offset, match length + 4, the last five bytes
// literals and no match starting within twelve bytes of the end) with a greedy
// single-entry hash encoder over a caller-supplied `[]u32` table and a strict
// decoder; and the frame format (magic 0x184D2204, FLG/BD descriptor with its
// xxHash32 header byte, independent or dependent blocks, optional block checksums,
// content size and content checksum, skippable frames stepped over). `xxh32` is
// here because `e.algo.hash` only has the 64-bit form.
//
// ponytail: the encoder is one hash probe per position and forward extension only
// (no backward extension, no lazy matching, no hash chains); `table_required` is the
// 4096-entry table, and the frame writer emits 64 KiB independent blocks with a
// content checksum only. A dictionary ID in a frame is `Invalid`.

error Invalid
error TooSmall

const TABLE: usize = 4096usize
const MIN_MATCH: usize = 4usize
const LAST_LITERALS: usize = 5usize
const MATCH_LIMIT: usize = 12usize
const MAX_OFFSET: usize = 65535usize
const BLOCK: usize = 65536usize

// Entries the encoder's `table` must hold.
fn table_required() -> usize { ret TABLE }

// Worst-case block size for `n` input bytes.
fn bound(n: usize) -> usize { ret n + n / 255usize + 16usize }

fn read32(src: []const u8, at: usize) -> u32 {
    ret u32(src[at]) | (u32(src[at + 1usize]) << 8u32) | (u32(src[at + 2usize]) << 16u32) | (u32(src[at + 3usize]) << 24u32)
}

fn hash_of(v: u32) -> usize { ret usize((v *% 2654435761u32) >> 20u32) }

// The length prefix beyond the nibble: 255-bytes then the remainder.
fn put_length(dst: []u8, at: usize, n: usize) -> usize {
    var rest = n
    var o = at
    while rest >= 255usize {
        dst[o] = 255u8
        o += 1usize
        rest -= 255usize
    }
    dst[o] = u8(rest & 255usize)
    ret o + 1usize
}

// One sequence: `lit` literals from `src[anchor..]`, then (if `mlen` > 0) a match
// of `mlen` bytes at `offset`; answers the new output position.
fn put_sequence(src: []const u8, anchor: usize, lit: usize, offset: usize, mlen: usize, dst: []u8, at: usize) -> (usize, err) {
    let need = 1usize + lit + lit / 255usize + 1usize + 2usize + mlen / 255usize + 1usize
    if at + need > dst.len { ret (at, TooSmall) }
    let token_at = at
    var o = at + 1usize
    var token = 0u32
    if lit >= 15usize {
        token = 240u32
        o = put_length(dst, o, lit - 15usize)
    } else {
        token = u32(lit) << 4u32
    }
    var i = 0usize
    while i < lit {
        dst[o + i] = src[anchor + i]
        i += 1usize
    }
    o += lit
    if mlen > 0usize {
        dst[o] = u8(offset & 255usize)
        dst[o + 1usize] = u8((offset >> 8u32) & 255usize)
        o += 2usize
        let ml = mlen - MIN_MATCH
        if ml >= 15usize {
            token |= 15u32
            o = put_length(dst, o, ml - 15usize)
        } else {
            token |= u32(ml)
        }
    }
    dst[token_at] = u8(token & 255u32)
    ret (o, ok)
}

// Compress `src` as one LZ4 block into `dst`; `table` holds `table_required()`
// entries and is cleared here. Answers the block length.
fn encode(src: []const u8, dst: []u8, table: []u32) -> (usize, err) {
    if table.len < TABLE { ret (0usize, TooSmall) }
    var t = 0usize
    while t < TABLE {
        table[t] = 0u32
        t += 1usize
    }
    var out = 0usize
    var anchor = 0usize
    var ip = 0usize
    if src.len >= MATCH_LIMIT + 1usize {
        let match_end = src.len - LAST_LITERALS
        let last_start = src.len - MATCH_LIMIT
        while ip <= last_start {
            let seq = read32(src, ip)
            let h = hash_of(seq)
            let cand = usize(table[h])
            table[h] = u32(ip)
            if cand < ip && ip - cand <= MAX_OFFSET && read32(src, cand) == seq {
                var mlen = MIN_MATCH
                while ip + mlen < match_end && src[cand + mlen] == src[ip + mlen] { mlen += 1usize }
                let (next_out, e) = put_sequence(src, anchor, ip - anchor, ip - cand, mlen, dst, out)
                if e != ok { ret (0usize, e) }
                out = next_out
                ip += mlen
                anchor = ip
            } else {
                ip += 1usize
            }
        }
    }
    let (end, e) = put_sequence(src, anchor, src.len - anchor, 0usize, 0usize, dst, out)
    if e != ok { ret (0usize, e) }
    ret (end, ok)
}

// A length nibble's extension bytes; answers (length, input position).
fn get_length(src: []const u8, at: usize, base: usize) -> (usize, usize, err) {
    var n = base
    var i = at
    var more = true
    while more {
        if i >= src.len { ret (0usize, i, Invalid) }
        let b = usize(src[i])
        i += 1usize
        n += b
        more = b == 255usize
    }
    ret (n, i, ok)
}

// Decode one block into `dst[start..]`; a match may reach back into `dst[..start]`
// (dependent frame blocks). Answers the position after the last byte written.
fn decode_into(src: []const u8, dst: []u8, start: usize) -> (usize, err) {
    var ip = 0usize
    var op = start
    while true {
        if ip >= src.len { ret (op, Invalid) }
        let token = usize(src[ip])
        ip += 1usize
        var lit = token >> 4u32
        if lit == 15usize {
            let (n, next_ip, e) = get_length(src, ip, lit)
            if e != ok { ret (op, e) }
            lit = n
            ip = next_ip
        }
        if ip + lit > src.len { ret (op, Invalid) }
        if op + lit > dst.len { ret (op, TooSmall) }
        var i = 0usize
        while i < lit {
            dst[op + i] = src[ip + i]
            i += 1usize
        }
        ip += lit
        op += lit
        if ip == src.len { ret (op, ok) }
        if ip + 2usize > src.len { ret (op, Invalid) }
        let offset = usize(src[ip]) | (usize(src[ip + 1usize]) << 8u32)
        ip += 2usize
        if offset == 0usize || offset > op { ret (op, Invalid) }
        var mlen = (token & 15usize) + MIN_MATCH
        if (token & 15usize) == 15usize {
            let (n, next_ip, e) = get_length(src, ip, mlen)
            if e != ok { ret (op, e) }
            mlen = n
            ip = next_ip
        }
        if op + mlen > dst.len { ret (op, TooSmall) }
        var m = 0usize
        while m < mlen {
            dst[op + m] = dst[op + m - offset]
            m += 1usize
        }
        op += mlen
    }
    ret (op, Invalid)
}

// Decode one LZ4 block into `dst`; malformed input is `Invalid`, a short `dst` is
// `TooSmall`. Answers the decoded length.
fn decode(src: []const u8, dst: []u8) -> (usize, err) {
    let (n, e) = decode_into(src, dst, 0usize)
    ret (n, e)
}

fn rotl32(x: u32, r: u32) -> u32 { ret (x << r) | (x >> (32u32 - r)) }

fn xxh32_round(acc: u32, w: u32) -> u32 { ret rotl32(acc +% w *% 2246822519u32, 13u32) *% 2654435761u32 }

// xxHash32 of `data` with `seed`.
fn xxh32(data: []const u8, seed: u32) -> u32 {
    let p1 = 2654435761u32
    let p2 = 2246822519u32
    let p3 = 3266489917u32
    let p4 = 668265263u32
    let p5 = 374761393u32
    var h = 0u32
    var at = 0usize
    if data.len >= 16usize {
        var v1 = seed +% p1 +% p2
        var v2 = seed +% p2
        var v3 = seed
        var v4 = seed -% p1
        while at + 16usize <= data.len {
            v1 = xxh32_round(v1, read32(data, at))
            v2 = xxh32_round(v2, read32(data, at + 4usize))
            v3 = xxh32_round(v3, read32(data, at + 8usize))
            v4 = xxh32_round(v4, read32(data, at + 12usize))
            at += 16usize
        }
        h = rotl32(v1, 1u32) +% rotl32(v2, 7u32) +% rotl32(v3, 12u32) +% rotl32(v4, 18u32)
    } else {
        h = seed +% p5
    }
    h = h +% u32(data.len & 4294967295usize)
    while at + 4usize <= data.len {
        h = rotl32(h +% read32(data, at) *% p3, 17u32) *% p4
        at += 4usize
    }
    while at < data.len {
        h = rotl32(h +% u32(data[at]) *% p5, 11u32) *% p1
        at += 1usize
    }
    h ^= h >> 15u32
    h = h *% p2
    h ^= h >> 13u32
    h = h *% p3
    h ^= h >> 16u32
    ret h
}

fn put32(dst: []u8, at: usize, v: u32) {
    dst[at] = u8(v & 255u32)
    dst[at + 1usize] = u8((v >> 8u32) & 255u32)
    dst[at + 2usize] = u8((v >> 16u32) & 255u32)
    dst[at + 3usize] = u8((v >> 24u32) & 255u32)
}

// Worst-case frame size for `n` input bytes: header, one size word per 64 KiB
// block (each stored raw at worst), end mark and content checksum.
fn frame_bound(n: usize) -> usize { ret 7usize + n + 4usize * (n / BLOCK + 1usize) + 8usize }

// Write an LZ4 frame of `src`: version 1, independent 64 KiB blocks, content
// checksum, no content size. `table` is as for `encode`. Answers the frame length.
fn encode_frame(src: []const u8, dst: []u8, table: []u32) -> (usize, err) {
    if dst.len < 7usize { ret (0usize, TooSmall) }
    put32(dst, 0usize, 407708164u32)
    dst[4] = 100u8
    dst[5] = 64u8
    dst[6] = u8((xxh32(dst[4..6], 0u32) >> 8u32) & 255u32)
    var out = 7usize
    var at = 0usize
    while at < src.len {
        var n = src.len - at
        if n > BLOCK { n = BLOCK }
        if out + 4usize + n > dst.len { ret (0usize, TooSmall) }
        let (packed, e) = encode(src[at..at + n], dst[out + 4usize..out + 4usize + n], table)
        if e == ok && packed < n {
            put32(dst, out, u32(packed))
            out += 4usize + packed
        } else if e == ok || e == TooSmall {
            put32(dst, out, u32(n) | 2147483648u32)
            var i = 0usize
            while i < n {
                dst[out + 4usize + i] = src[at + i]
                i += 1usize
            }
            out += 4usize + n
        } else {
            ret (0usize, e)
        }
        at += n
    }
    if out + 8usize > dst.len { ret (0usize, TooSmall) }
    put32(dst, out, 0u32)
    put32(dst, out + 4usize, xxh32(src, 0u32))
    ret (out + 8usize, ok)
}

// Read one LZ4 frame (skippable frames before it are stepped over) into `dst`,
// verifying the header byte, any block checksums, the content checksum and the
// content size. Answers the decoded length.
fn decode_frame(src: []const u8, dst: []u8) -> (usize, err) {
    var ip = 0usize
    while true {
        if ip + 4usize > src.len { ret (0usize, Invalid) }
        let magic = read32(src, ip)
        if magic == 407708164u32 {
            ip += 4usize
            let (n, e) = decode_body(src, ip, dst)
            ret (n, e)
        }
        if (magic & 4294967280u32) != 407710288u32 { ret (0usize, Invalid) }
        if ip + 8usize > src.len { ret (0usize, Invalid) }
        ip += 8usize + usize(read32(src, ip + 4usize))
    }
    ret (0usize, Invalid)
}

fn decode_body(src: []const u8, start: usize, dst: []u8) -> (usize, err) {
    var ip = start
    if ip + 3usize > src.len { ret (0usize, Invalid) }
    let flg = u32(src[ip])
    if (flg & 192u32) != 64u32 || (flg & 3u32) != 0u32 { ret (0usize, Invalid) }
    let block_checksum = (flg & 16u32) != 0u32
    let has_size = (flg & 8u32) != 0u32
    let content_checksum = (flg & 4u32) != 0u32
    let bd = u32(src[ip + 1usize])
    let size_code = (bd >> 4u32) & 7u32
    if size_code < 4u32 || (bd & 143u32) != 0u32 { ret (0usize, Invalid) }
    var header_len = 2usize
    if has_size { header_len += 8usize }
    if ip + header_len + 1usize > src.len { ret (0usize, Invalid) }
    if src[ip + header_len] != u8((xxh32(src[ip..ip + header_len], 0u32) >> 8u32) & 255u32) { ret (0usize, Invalid) }
    var content_size = 0u64
    if has_size {
        var k = 0usize
        while k < 8usize {
            content_size |= u64(src[ip + 2usize + k]) << u32(8usize * k)
            k += 1usize
        }
    }
    ip += header_len + 1usize
    var op = 0usize
    while true {
        if ip + 4usize > src.len { ret (op, Invalid) }
        let word = read32(src, ip)
        ip += 4usize
        if word == 0u32 {
            if content_checksum {
                if ip + 4usize > src.len { ret (op, Invalid) }
                if read32(src, ip) != xxh32(dst[..op], 0u32) { ret (op, Invalid) }
            }
            if has_size && u64(op) != content_size { ret (op, Invalid) }
            ret (op, ok)
        }
        let n = usize(word & 2147483647u32)
        if ip + n > src.len { ret (op, Invalid) }
        let block = src[ip..ip + n]
        ip += n
        if block_checksum {
            if ip + 4usize > src.len { ret (op, Invalid) }
            if read32(src, ip) != xxh32(block, 0u32) { ret (op, Invalid) }
            ip += 4usize
        }
        if (word & 2147483648u32) != 0u32 {
            if op + n > dst.len { ret (op, TooSmall) }
            var i = 0usize
            while i < n {
                dst[op + i] = block[i]
                i += 1usize
            }
            op += n
        } else {
            let (next_op, e) = decode_into(block, dst, op)
            if e != ok { ret (op, e) }
            op = next_op
        }
    }
    ret (op, Invalid)
}
