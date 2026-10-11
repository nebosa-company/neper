// EXIF reader (L124): the TIFF structure inside a JPEG APP1 segment, a PNG eXIf chunk, a
// WebP EXIF chunk or a TIFF file. `block_of_jpeg`, `block_of_png`, `block_of_webp` find the
// bytes; `open` validates the TIFF header and byte order; `tags` walks IFD0, the chained
// IFD1 (thumbnail) and the Exif (0x8769), GPS (0x8825) and Interoperability (0xA005)
// sub-IFDs into a flat list, each IFD visited once, to a depth of four and to the caller's
// tag limit, with every entry's value range checked against the block. `value_u32`,
// `value_rational` and `value_text` read one value of an entry; `find` looks a tag up and
// `orientation` is the common question. Read only; a MakerNote is not interpreted.

use e.mem

type Exif = struct { data: []const u8, big: bool, ifd0: usize }
type Tag = struct { ifd: u8, tag: u16, kind: u16, count: u32, at: usize }
error Invalid
error TooLarge
error NotFound

const IFD_MAIN: u8 = 0u8
const IFD_THUMBNAIL: u8 = 1u8
const IFD_EXIF: u8 = 2u8
const IFD_GPS: u8 = 3u8
const IFD_INTEROP: u8 = 4u8

fn rd16(e: *const Exif, at: usize) -> u32 {
    if e.big { ret (u32(e.data[at]) << 8u32) | u32(e.data[at + 1usize]) }
    ret u32(e.data[at]) | (u32(e.data[at + 1usize]) << 8u32)
}

fn rd32(e: *const Exif, at: usize) -> u32 {
    if e.big {
        ret (u32(e.data[at]) << 24u32) | (u32(e.data[at + 1usize]) << 16u32) | (u32(e.data[at + 2usize]) << 8u32) | u32(e.data[at + 3usize])
    }
    ret u32(e.data[at]) | (u32(e.data[at + 1usize]) << 8u32) | (u32(e.data[at + 2usize]) << 16u32) | (u32(e.data[at + 3usize]) << 24u32)
}

fn begins(d: []const u8, at: usize, lit: str) -> bool {
    if at + lit.len > d.len { ret false }
    var i = 0usize
    while i < lit.len {
        if d[at + i] != lit[i] { ret false }
        i += 1usize
    }
    ret true
}

// The Exif TIFF block of a JPEG: the payload of the first APP1 segment that starts "Exif\0\0".
fn block_of_jpeg(d: []const u8) -> ([]const u8, err) {
    var nothing: []const u8 = zero
    if d.len < 4usize || d[0] != 255u8 || d[1] != 216u8 { ret (nothing, Invalid) }
    var at = 2usize
    while at + 4usize <= d.len {
        if d[at] != 255u8 { ret (nothing, Invalid) }
        let marker = d[at + 1usize]
        if marker == 255u8 {
            at += 1usize
            continue
        }
        if marker == 217u8 || marker == 218u8 { break }
        if marker >= 208u8 && marker <= 215u8 || marker == 1u8 {
            at += 2usize
            continue
        }
        let length = (usize(d[at + 2usize]) << 8u32) | usize(d[at + 3usize])
        if length < 2usize || at + 2usize + length > d.len { ret (nothing, Invalid) }
        if marker == 225u8 && begins(d, at + 4usize, "Exif\x00\x00") {
            ret (d[at + 10usize..at + 2usize + length], ok)
        }
        at += 2usize + length
    }
    ret (nothing, NotFound)
}

fn block_of_png(d: []const u8) -> ([]const u8, err) {
    var nothing: []const u8 = zero
    if !begins(d, 0usize, "\x89PNG\r\n\x1a\n") { ret (nothing, Invalid) }
    var at = 8usize
    while at + 12usize <= d.len {
        let length = (usize(d[at]) << 24u32) | (usize(d[at + 1usize]) << 16u32) | (usize(d[at + 2usize]) << 8u32) | usize(d[at + 3usize])
        if length > d.len - at - 12usize { ret (nothing, Invalid) }
        if begins(d, at + 4usize, "eXIf") { ret (d[at + 8usize..at + 8usize + length], ok) }
        if begins(d, at + 4usize, "IEND") { break }
        at += 12usize + length
    }
    ret (nothing, NotFound)
}

fn block_of_webp(d: []const u8) -> ([]const u8, err) {
    var nothing: []const u8 = zero
    if d.len < 12usize || !begins(d, 0usize, "RIFF") || !begins(d, 8usize, "WEBP") { ret (nothing, Invalid) }
    var at = 12usize
    while at + 8usize <= d.len {
        let length = usize(d[at + 4usize]) | (usize(d[at + 5usize]) << 8u32) | (usize(d[at + 6usize]) << 16u32) | (usize(d[at + 7usize]) << 24u32)
        if length > d.len - at - 8usize { ret (nothing, Invalid) }
        if begins(d, at, "EXIF") {
            var start = at + 8usize
            // some writers keep the "Exif\0\0" prefix of the JPEG form
            if begins(d, start, "Exif\x00\x00") { start += 6usize }
            ret (d[start..at + 8usize + length], ok)
        }
        at += 8usize + length + (length & 1usize)
    }
    ret (nothing, NotFound)
}

fn open(block: []const u8) -> (Exif, err) {
    var e: Exif = zero
    if block.len < 8usize { ret (e, Invalid) }
    if block[0] == 73u8 && block[1] == 73u8 {
        e.big = false
    } else if block[0] == 77u8 && block[1] == 77u8 {
        e.big = true
    } else {
        ret (e, Invalid)
    }
    e.data = block
    if rd16(&e, 2usize) != 42u32 { ret (e, Invalid) }
    let first = usize(rd32(&e, 4usize))
    if first < 8usize || first + 2usize > block.len { ret (e, Invalid) }
    e.ifd0 = first
    ret (e, ok)
}

fn kind_size(kind: u32) -> usize {
    if kind == 1u32 || kind == 2u32 || kind == 6u32 || kind == 7u32 { ret 1usize }
    if kind == 3u32 || kind == 8u32 { ret 2usize }
    if kind == 4u32 || kind == 9u32 || kind == 11u32 || kind == 13u32 { ret 4usize }
    if kind == 5u32 || kind == 10u32 || kind == 12u32 { ret 8usize }
    ret 0usize
}

fn walk(e: *Exif, at: usize, ifd: u8, depth: usize, out: []Tag, used: *usize, seen: []usize, seen_count: *usize) -> err {
    if depth > 4usize { ret Invalid }
    var cur = at
    var which = ifd
    while cur != 0usize {
        var k = 0usize
        while k < *seen_count {
            if seen[k] == cur { ret Invalid }
            k += 1usize
        }
        if *seen_count >= seen.len { ret TooLarge }
        seen[*seen_count] = cur
        *seen_count = *seen_count + 1usize
        if cur + 2usize > e.data.len { ret Invalid }
        let n = usize(rd16(e, cur))
        if cur + 2usize + n * 12usize + 4usize > e.data.len { ret Invalid }
        var i = 0usize
        while i < n {
            let entry = cur + 2usize + i * 12usize
            let tag = rd16(e, entry)
            let kind = rd16(e, entry + 2usize)
            let count = rd32(e, entry + 4usize)
            let size = kind_size(kind)
            if size != 0usize {
                let total = u64(size) * u64(count)
                var value_at = entry + 8usize
                if total > 4u64 {
                    let off = u64(rd32(e, entry + 8usize))
                    if off > u64(e.data.len) || total > u64(e.data.len) - off { ret Invalid }
                    value_at = usize(off)
                }
                if *used >= out.len { ret TooLarge }
                out[*used].ifd = which
                out[*used].tag = u16(tag)
                out[*used].kind = u16(kind)
                out[*used].count = count
                out[*used].at = value_at
                *used = *used + 1usize
                if (tag == 34665u32 || tag == 34853u32 || tag == 40965u32) && kind == 4u32 && count == 1u32 {
                    var sub = IFD_EXIF
                    if tag == 34853u32 { sub = IFD_GPS }
                    if tag == 40965u32 { sub = IFD_INTEROP }
                    let sub_at = usize(rd32(e, entry + 8usize))
                    let nested = walk(e, sub_at, sub, depth + 1usize, out, used, seen, seen_count)
                    if nested != ok { ret nested }
                }
            }
            i += 1usize
        }
        // IFD0 chains to the thumbnail's IFD1; a sub-IFD's chain is not followed
        if depth == 0usize && which == IFD_MAIN {
            cur = usize(rd32(e, cur + 2usize + n * 12usize))
            which = IFD_THUMBNAIL
        } else {
            cur = 0usize
        }
    }
    ret ok
}

// Every tag of the block's IFDs in file order (a sub-IFD right after the entry that points
// to it); `limit` bounds the count and so the allocation.
fn tags(a: *mem.Arena, e: *Exif, limit: usize) -> ([]Tag, err) {
    var nothing: []Tag = zero
    let (out, out_error) = mem.alloc[Tag](a, limit + 1usize)
    if out_error != ok { ret (nothing, out_error) }
    let (seen, seen_error) = mem.alloc[usize](a, 64usize)
    if seen_error != ok { ret (nothing, seen_error) }
    var used = 0usize
    var seen_count = 0usize
    let failure = walk(e, e.ifd0, IFD_MAIN, 0usize, out[..limit], &used, seen, &seen_count)
    if failure != ok { ret (nothing, failure) }
    ret (out[..used], ok)
}

fn find(all: []const Tag, ifd: u8, tag: u16) -> (Tag, bool) {
    var i = 0usize
    while i < all.len {
        if all[i].ifd == ifd && all[i].tag == tag { ret (all[i], true) }
        i += 1usize
    }
    var none: Tag = zero
    ret (none, false)
}

// One BYTE, SHORT or LONG value (signed kinds are returned as their bit pattern).
fn value_u32(e: *const Exif, t: Tag, index: usize) -> (u32, err) {
    if u32(index) >= t.count { ret (0u32, Invalid) }
    let kind = u32(t.kind)
    if kind == 1u32 || kind == 7u32 || kind == 6u32 { ret (u32(e.data[t.at + index]), ok) }
    if kind == 3u32 || kind == 8u32 { ret (rd16(e, t.at + index * 2usize), ok) }
    if kind == 4u32 || kind == 9u32 { ret (rd32(e, t.at + index * 4usize), ok) }
    ret (0u32, Invalid)
}

// One RATIONAL or SRATIONAL: numerator and denominator as read (an SRATIONAL's are two's
// complement bit patterns).
fn value_rational(e: *const Exif, t: Tag, index: usize) -> (u32, u32, err) {
    if u32(index) >= t.count { ret (0u32, 0u32, Invalid) }
    if t.kind != 5u16 && t.kind != 10u16 { ret (0u32, 0u32, Invalid) }
    let p = t.at + index * 8usize
    ret (rd32(e, p), rd32(e, p + 4usize), ok)
}

// An ASCII value up to its first NUL, borrowed from the block.
fn value_text(e: *const Exif, t: Tag) -> (str, err) {
    if t.kind != 2u16 { ret ("", Invalid) }
    var n = usize(t.count)
    var i = 0usize
    while i < n {
        if e.data[t.at + i] == 0u8 {
            n = i
            break
        }
        i += 1usize
    }
    ret (e.data[t.at..t.at + n], ok)
}

// The orientation tag (1 to 8), or 1 when the block has none or an out-of-range one.
fn orientation(a: *mem.Arena, block: []const u8) -> u32 {
    let (e, open_error) = open(block)
    if open_error != ok { ret 1u32 }
    var x = e
    let (all, tags_error) = tags(a, &x, 256usize)
    if tags_error != ok { ret 1u32 }
    let (t, found) = find(all, IFD_MAIN, 274u16)
    if !found { ret 1u32 }
    let (v, v_error) = value_u32(&x, t, 0usize)
    if v_error != ok || v < 1u32 || v > 8u32 { ret 1u32 }
    ret v
}
