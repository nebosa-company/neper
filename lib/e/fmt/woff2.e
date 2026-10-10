// WOFF2 to sfnt (L043), after Vaper's `woff2ToSfnt`, a port of Google's reference decoder: the container header and table
// directory (known-tag indexes, UIntBase128 lengths, transform versions), the table data Brotli-decompressed through
// `e.fmt.brotli`, the `glyf`/`loca` transform reversed (the seven glyph streams, triplet-coded points, composite glyphs,
// bounding boxes, the overlap bitmap) and the `hmtx` transform reversed, then the sfnt rebuilt with tag-sorted directory
// entries, recomputed table checksums and `head.checkSumAdjustment`. A font collection (`ttcf`), a malformed container or
// stream, or an unsupported transform is `Invalid`.
//
// ponytail: the Brotli output may exceed the directory's total by at most 4096 bytes (the buffer is sized from the
// directory, the reference measures what the stream produced); a table section over 256 MiB is `Invalid`.
//
// Memory: the arena is retained; the sfnt and the working buffers live in it.

use e.mem
use e.fmt.brotli as brotli

error Invalid

const SPARE: usize = 4096usize
const LIMIT: usize = 268435456usize

// A big-endian reading cursor; a read past `end` sets `bad` and answers zero.
type Buf = struct { data: []const u8, pos: usize, end: usize, bad: bool }

// A table directory entry and, once sliced, its content.
type Table = struct { tag: u32, flags: u32, dst_len: usize, xform_len: usize, src_off: usize, content: []const u8 }

fn tag_of(s: str) -> u32 {
    ret (u32(s[0]) << 24u32) | (u32(s[1]) << 16u32) | (u32(s[2]) << 8u32) | u32(s[3])
}

// The 63 known table tags, by the low six flag bits.
fn known_tag(i: u32) -> u32 {
    if i == 0u32 { ret tag_of("cmap") }
    if i == 1u32 { ret tag_of("head") }
    if i == 2u32 { ret tag_of("hhea") }
    if i == 3u32 { ret tag_of("hmtx") }
    if i == 4u32 { ret tag_of("maxp") }
    if i == 5u32 { ret tag_of("name") }
    if i == 6u32 { ret tag_of("OS/2") }
    if i == 7u32 { ret tag_of("post") }
    if i == 8u32 { ret tag_of("cvt ") }
    if i == 9u32 { ret tag_of("fpgm") }
    if i == 10u32 { ret tag_of("glyf") }
    if i == 11u32 { ret tag_of("loca") }
    if i == 12u32 { ret tag_of("prep") }
    if i == 13u32 { ret tag_of("CFF ") }
    if i == 14u32 { ret tag_of("VORG") }
    if i == 15u32 { ret tag_of("EBDT") }
    if i == 16u32 { ret tag_of("EBLC") }
    if i == 17u32 { ret tag_of("gasp") }
    if i == 18u32 { ret tag_of("hdmx") }
    if i == 19u32 { ret tag_of("kern") }
    if i == 20u32 { ret tag_of("LTSH") }
    if i == 21u32 { ret tag_of("PCLT") }
    if i == 22u32 { ret tag_of("VDMX") }
    if i == 23u32 { ret tag_of("vhea") }
    if i == 24u32 { ret tag_of("vmtx") }
    if i == 25u32 { ret tag_of("BASE") }
    if i == 26u32 { ret tag_of("GDEF") }
    if i == 27u32 { ret tag_of("GPOS") }
    if i == 28u32 { ret tag_of("GSUB") }
    if i == 29u32 { ret tag_of("EBSC") }
    if i == 30u32 { ret tag_of("JSTF") }
    if i == 31u32 { ret tag_of("MATH") }
    if i == 32u32 { ret tag_of("CBDT") }
    if i == 33u32 { ret tag_of("CBLC") }
    if i == 34u32 { ret tag_of("COLR") }
    if i == 35u32 { ret tag_of("CPAL") }
    if i == 36u32 { ret tag_of("SVG ") }
    if i == 37u32 { ret tag_of("sbix") }
    if i == 38u32 { ret tag_of("acnt") }
    if i == 39u32 { ret tag_of("avar") }
    if i == 40u32 { ret tag_of("bdat") }
    if i == 41u32 { ret tag_of("bloc") }
    if i == 42u32 { ret tag_of("bsln") }
    if i == 43u32 { ret tag_of("cvar") }
    if i == 44u32 { ret tag_of("fdsc") }
    if i == 45u32 { ret tag_of("feat") }
    if i == 46u32 { ret tag_of("fmtx") }
    if i == 47u32 { ret tag_of("fvar") }
    if i == 48u32 { ret tag_of("gvar") }
    if i == 49u32 { ret tag_of("hsty") }
    if i == 50u32 { ret tag_of("just") }
    if i == 51u32 { ret tag_of("lcar") }
    if i == 52u32 { ret tag_of("mort") }
    if i == 53u32 { ret tag_of("morx") }
    if i == 54u32 { ret tag_of("opbd") }
    if i == 55u32 { ret tag_of("prop") }
    if i == 56u32 { ret tag_of("trak") }
    if i == 57u32 { ret tag_of("Zapf") }
    if i == 58u32 { ret tag_of("Silf") }
    if i == 59u32 { ret tag_of("Glat") }
    if i == 60u32 { ret tag_of("Gloc") }
    if i == 61u32 { ret tag_of("Feat") }
    ret tag_of("Sill")
}

fn get8(b: *Buf) -> u32 {
    if b.pos + 1usize > b.end {
        b.bad = true
        ret 0u32
    }
    let v = b.data[b.pos]
    b.pos += 1usize
    ret u32(v)
}

fn get16(b: *Buf) -> u32 {
    if b.pos + 2usize > b.end {
        b.bad = true
        ret 0u32
    }
    let v = (u32(b.data[b.pos]) << 8u32) | u32(b.data[b.pos + 1usize])
    b.pos += 2usize
    ret v
}

fn get32(b: *Buf) -> u32 {
    if b.pos + 4usize > b.end {
        b.bad = true
        ret 0u32
    }
    let v = (u32(b.data[b.pos]) << 24u32) | (u32(b.data[b.pos + 1usize]) << 16u32) | (u32(b.data[b.pos + 2usize]) << 8u32) | u32(b.data[b.pos + 3usize])
    b.pos += 4usize
    ret v
}

fn skip(b: *Buf, n: usize) {
    if b.pos + n > b.end {
        b.bad = true
        ret
    }
    b.pos += n
}

// The next `n` bytes, or an empty slice with `bad` set.
fn take(b: *Buf, n: usize) -> []const u8 {
    if b.pos + n > b.end {
        b.bad = true
        ret b.data[0..0]
    }
    let v = b.data[b.pos..b.pos + n]
    b.pos += n
    ret v
}

// 255UInt16 (WOFF2 6.1.1).
fn read255(b: *Buf) -> u32 {
    let code = get8(b)
    if code == 253u32 { ret get16(b) }
    if code == 255u32 { ret get8(b) + 253u32 }
    if code == 254u32 { ret get8(b) + 506u32 }
    ret code
}

// UIntBase128 (WOFF2 6.1.2).
fn read_base128(b: *Buf) -> u32 {
    var result = 0u32
    var i = 0u32
    while i < 5u32 {
        let code = get8(b)
        if b.bad { ret 0u32 }
        if i == 0u32 && code == 128u32 {
            b.bad = true
            ret 0u32
        }
        if (result & 4261412864u32) != 0u32 {
            b.bad = true
            ret 0u32
        }
        result = (result << 7u32) | (code & 127u32)
        if (code & 128u32) == 0u32 { ret result }
        i += 1u32
    }
    b.bad = true
    ret 0u32
}

fn with_sign(flag: u32, base: i64) -> i64 {
    if (flag & 1u32) != 0u32 { ret base }
    ret 0i64 - base
}

// The low sixteen bits of a possibly negative value.
fn low16(v: i64) -> u32 {
    var m = v % 65536i64
    if m < 0i64 { m += 65536i64 }
    ret u32(m)
}

fn store16(dst: []u8, at: usize, v: u32) {
    dst[at] = u8((v >> 8u32) & 255u32)
    dst[at + 1usize] = u8(v & 255u32)
}

fn store32(dst: []u8, at: usize, v: u32) {
    dst[at] = u8((v >> 24u32) & 255u32)
    dst[at + 1usize] = u8((v >> 16u32) & 255u32)
    dst[at + 2usize] = u8((v >> 8u32) & 255u32)
    dst[at + 3usize] = u8(v & 255u32)
}

fn at_byte(g: *Buf, o: usize) -> u32 {
    if o >= g.end {
        g.bad = true
        ret 0u32
    }
    ret u32(g.data[o])
}

// Decodes `n` coordinate triplets (WOFF2 5.2); the glyph stream is not advanced, the bytes used are answered.
fn triplets(flags: []const u8, g: *Buf, n: usize, xs: []i64, ys: []i64, on: []u8) -> usize {
    var x = 0i64
    var y = 0i64
    let base = g.pos
    var ti = g.pos
    var i = 0usize
    while i < n {
        let flag = u32(flags[i])
        on[i] = 0u8
        if (flag >> 7u32) == 0u32 { on[i] = 1u8 }
        let f = flag & 127u32
        var nbytes = 4usize
        if f < 84u32 {
            nbytes = 1usize
        } else if f < 120u32 {
            nbytes = 2usize
        } else if f < 124u32 {
            nbytes = 3usize
        }
        var dx = 0i64
        var dy = 0i64
        if f < 10u32 {
            dy = with_sign(f, i64(((f & 14u32) << 7u32) + at_byte(g, ti)))
        } else if f < 20u32 {
            dx = with_sign(f, i64((((f - 10u32) & 14u32) << 7u32) + at_byte(g, ti)))
        } else if f < 84u32 {
            let b0 = f - 20u32
            let b1 = at_byte(g, ti)
            dx = with_sign(f, i64(1u32 + (b0 & 48u32) + (b1 >> 4u32)))
            dy = with_sign(f >> 1u32, i64(1u32 + ((b0 & 12u32) << 2u32) + (b1 & 15u32)))
        } else if f < 120u32 {
            let b0 = f - 84u32
            dx = with_sign(f, i64(1u32 + ((b0 / 12u32) << 8u32) + at_byte(g, ti)))
            dy = with_sign(f >> 1u32, i64(1u32 + (((b0 % 12u32) >> 2u32) << 8u32) + at_byte(g, ti + 1usize)))
        } else if f < 124u32 {
            let b2 = at_byte(g, ti + 1usize)
            dx = with_sign(f, i64((at_byte(g, ti) << 4u32) + (b2 >> 4u32)))
            dy = with_sign(f >> 1u32, i64(((b2 & 15u32) << 8u32) + at_byte(g, ti + 2usize)))
        } else {
            dx = with_sign(f, i64((at_byte(g, ti) << 8u32) + at_byte(g, ti + 1usize)))
            dy = with_sign(f >> 1u32, i64((at_byte(g, ti + 2usize) << 8u32) + at_byte(g, ti + 3usize)))
        }
        if g.bad { ret 0usize }
        ti += nbytes
        x += dx
        y += dy
        xs[i] = x
        ys[i] = y
        i += 1usize
    }
    ret ti - base
}

// The TrueType flags and coordinates of a simple glyph (the reference's StorePoints); the glyph's size.
fn store_points(xs: []const i64, ys: []const i64, on: []const u8, n: usize, contours: usize, instr: usize, overlap: bool, dst: []u8) -> usize {
    var flag_at = 10usize + 2usize * contours + 2usize + instr
    var last_flag = 65536u32
    var repeat = 0u32
    var last_x = 0i64
    var last_y = 0i64
    var x_bytes = 0usize
    var i = 0usize
    while i < n {
        var flag = 0u32
        if on[i] != 0u8 { flag = 1u32 }
        if overlap && i == 0usize { flag = flag | 64u32 }
        let dx = xs[i] - last_x
        let dy = ys[i] - last_y
        if dx == 0i64 {
            flag = flag | 16u32
        } else if dx > -256i64 && dx < 256i64 {
            flag = flag | 2u32
            if dx > 0i64 { flag = flag | 16u32 }
            x_bytes += 1usize
        } else {
            x_bytes += 2usize
        }
        if dy == 0i64 {
            flag = flag | 32u32
        } else if dy > -256i64 && dy < 256i64 {
            flag = flag | 4u32
            if dy > 0i64 { flag = flag | 32u32 }
        }
        if flag == last_flag && repeat != 255u32 {
            dst[flag_at - 1usize] = dst[flag_at - 1usize] | 8u8
            repeat += 1u32
        } else {
            if repeat != 0u32 {
                dst[flag_at] = u8(repeat)
                flag_at += 1usize
            }
            dst[flag_at] = u8(flag)
            flag_at += 1usize
            repeat = 0u32
        }
        last_x = xs[i]
        last_y = ys[i]
        last_flag = flag
        i += 1usize
    }
    if repeat != 0u32 {
        dst[flag_at] = u8(repeat)
        flag_at += 1usize
    }
    var x_at = flag_at
    var y_at = flag_at + x_bytes
    last_x = 0i64
    last_y = 0i64
    i = 0usize
    while i < n {
        let dx = xs[i] - last_x
        if dx != 0i64 && dx > -256i64 && dx < 256i64 {
            var m = dx
            if m < 0i64 { m = 0i64 - m }
            dst[x_at] = u8(m)
            x_at += 1usize
        } else if dx != 0i64 {
            store16(dst, x_at, low16(dx))
            x_at += 2usize
        }
        last_x += dx
        let dy = ys[i] - last_y
        if dy != 0i64 && dy > -256i64 && dy < 256i64 {
            var m = dy
            if m < 0i64 { m = 0i64 - m }
            dst[y_at] = u8(m)
            y_at += 1usize
        } else if dy != 0i64 {
            store16(dst, y_at, low16(dy))
            y_at += 2usize
        }
        last_y += dy
        i += 1usize
    }
    ret y_at
}

fn compute_bbox(xs: []const i64, ys: []const i64, n: usize, dst: []u8) {
    var x_min = 0i64
    var y_min = 0i64
    var x_max = 0i64
    var y_max = 0i64
    if n > 0usize {
        x_min = xs[0]
        x_max = xs[0]
        y_min = ys[0]
        y_max = ys[0]
    }
    var i = 0usize
    while i < n {
        if xs[i] < x_min { x_min = xs[i] }
        if xs[i] > x_max { x_max = xs[i] }
        if ys[i] < y_min { y_min = ys[i] }
        if ys[i] > y_max { y_max = ys[i] }
        i += 1usize
    }
    store16(dst, 2usize, low16(x_min))
    store16(dst, 4usize, low16(y_min))
    store16(dst, 6usize, low16(x_max))
    store16(dst, 8usize, low16(y_max))
}

// A composite glyph's component bytes (not consumed: `s` is a copy) and whether it carries instructions.
type Composite = struct { size: usize, instr: bool }

fn size_of_composite(s: *Buf) -> Composite {
    let start = s.pos
    var have = false
    var flags = 32u32
    while (flags & 32u32) != 0u32 {
        flags = get16(s)
        if s.bad { break }
        if (flags & 256u32) != 0u32 { have = true }
        var arg = 2usize
        if (flags & 1u32) != 0u32 {
            arg += 4usize
        } else {
            arg += 2usize
        }
        if (flags & 8u32) != 0u32 {
            arg += 2usize
        } else if (flags & 64u32) != 0u32 {
            arg += 4usize
        } else if (flags & 128u32) != 0u32 {
            arg += 8usize
        }
        skip(s, arg)
        if s.bad { break }
    }
    ret Composite { size: s.pos - start, instr: have }
}

type Glyphs = struct { glyf: []u8, loca: []u8, x_mins: []u32 }

fn zero_bytes(b: []u8) {
    var i = 0usize
    while i < b.len {
        b[i] = 0u8
        i += 1usize
    }
}

// The `glyf` and `loca` tables from a transformed glyf blob.
fn reconstruct_glyf(a: *mem.Arena, data: []const u8, loca_len: usize) -> (Glyphs, err) {
    var file = Buf { data: data, pos: 0usize, end: data.len, bad: false }
    let version = get16(&file)
    let option = get16(&file)
    let glyph_count = usize(get16(&file))
    let index_format = get16(&file)
    if file.bad { ret (zero, Invalid) }
    var loca_unit = 2usize
    if index_format != 0u32 { loca_unit = 4usize }
    if loca_len != loca_unit * (glyph_count + 1usize) { ret (zero, Invalid) }
    var sizes: [7]usize = zero
    var k = 0usize
    while k < 7usize {
        sizes[k] = usize(get32(&file))
        k += 1usize
    }
    if file.bad { ret (zero, Invalid) }
    var off = file.pos
    var subs: [7]Buf = zero
    k = 0usize
    while k < 7usize {
        if off + sizes[k] > data.len { ret (zero, Invalid) }
        subs[k] = Buf { data: data, pos: off, end: off + sizes[k], bad: false }
        off += sizes[k]
        k += 1usize
    }
    let has_overlap_map = (option & 1u32) != 0u32
    var overlap_map: []const u8 = data[0..0]
    if has_overlap_map {
        let len = (glyph_count + 7usize) >> 3usize
        if off + len > data.len { ret (zero, Invalid) }
        overlap_map = data[off..off + len]
    }
    let bbox_map_len = ((glyph_count + 31usize) >> 5usize) << 2usize
    let bbox_map = take(&subs[5], bbox_map_len)
    if subs[5].bad { ret (zero, Invalid) }
    let cap = 15usize * glyph_count + 2usize * subs[1].end - 2usize * subs[1].pos + 5usize * (subs[2].end - subs[2].pos) + (subs[4].end - subs[4].pos) + (subs[6].end - subs[6].pos) + 16usize
    let (glyf, ge) = mem.alloc[u8](a, cap)
    if ge != ok { ret (zero, ge) }
    let (loca_values, le) = mem.alloc[usize](a, glyph_count + 1usize)
    if le != ok { ret (zero, le) }
    let (x_mins, xe) = mem.alloc[u32](a, glyph_count)
    if xe != ok { ret (zero, xe) }
    var glyf_len = 0usize
    var g = 0usize
    while g < glyph_count {
        x_mins[g] = 0u32
        g += 1usize
    }
    g = 0usize
    while g < glyph_count {
        let have_bbox = (u32(bbox_map[g >> 3usize]) & (128u32 >> u32(g & 7usize))) != 0u32
        let contours = get16(&subs[0])
        if subs[0].bad { ret (zero, Invalid) }
        loca_values[g] = glyf_len
        var size = 0usize
        var buf: []u8 = glyf[0..0]
        if contours == 65535u32 {
            if !have_bbox { ret (zero, Invalid) }
            var snap = subs[4]
            let comp = size_of_composite(&snap)
            if snap.bad { ret (zero, Invalid) }
            var instr = 0usize
            if comp.instr { instr = usize(read255(&subs[3])) }
            if subs[3].bad { ret (zero, Invalid) }
            let (made, me) = mem.alloc[u8](a, 12usize + comp.size + instr)
            if me != ok { ret (zero, me) }
            buf = made
            zero_bytes(buf)
            store16(buf, 0usize, contours)
            let box = take(&subs[5], 8usize)
            let parts = take(&subs[4], comp.size)
            if subs[5].bad || subs[4].bad { ret (zero, Invalid) }
            var q = 0usize
            while q < 8usize {
                buf[2usize + q] = box[q]
                q += 1usize
            }
            q = 0usize
            while q < comp.size {
                buf[10usize + q] = parts[q]
                q += 1usize
            }
            size = 10usize + comp.size
            if comp.instr {
                store16(buf, size, u32(instr))
                size += 2usize
                let code = take(&subs[6], instr)
                if subs[6].bad { ret (zero, Invalid) }
                q = 0usize
                while q < instr {
                    buf[size + q] = code[q]
                    q += 1usize
                }
                size += instr
            }
        } else if contours > 0u32 {
            let nc = usize(contours)
            let (counts, ce) = mem.alloc[usize](a, nc)
            if ce != ok { ret (zero, ce) }
            var total = 0usize
            var j = 0usize
            while j < nc {
                let n = usize(read255(&subs[1]))
                if subs[1].bad { ret (zero, Invalid) }
                counts[j] = n
                total += n
                j += 1usize
            }
            if total > subs[2].end - subs[2].pos { ret (zero, Invalid) }
            let flags = take(&subs[2], total)
            let (xs, xe2) = mem.alloc[i64](a, total + 1usize)
            if xe2 != ok { ret (zero, xe2) }
            let (ys, ye) = mem.alloc[i64](a, total + 1usize)
            if ye != ok { ret (zero, ye) }
            let (on, oe) = mem.alloc[u8](a, total + 1usize)
            if oe != ok { ret (zero, oe) }
            let used = triplets(flags, &subs[3], total, xs, ys, on)
            if subs[3].bad { ret (zero, Invalid) }
            skip(&subs[3], used)
            let instr = usize(read255(&subs[3]))
            if subs[3].bad { ret (zero, Invalid) }
            let (made, me) = mem.alloc[u8](a, 12usize + 2usize * nc + 5usize * total + instr)
            if me != ok { ret (zero, me) }
            buf = made
            zero_bytes(buf)
            store16(buf, 0usize, contours)
            if have_bbox {
                let box = take(&subs[5], 8usize)
                if subs[5].bad { ret (zero, Invalid) }
                var q = 0usize
                while q < 8usize {
                    buf[2usize + q] = box[q]
                    q += 1usize
                }
            } else {
                compute_bbox(xs, ys, total, buf)
            }
            var gs = 10usize
            var end_point = -1i64
            j = 0usize
            while j < nc {
                end_point += i64(counts[j])
                if end_point >= 65536i64 { ret (zero, Invalid) }
                store16(buf, gs, low16(end_point))
                gs += 2usize
                j += 1usize
            }
            store16(buf, gs, u32(instr))
            gs += 2usize
            let code = take(&subs[6], instr)
            if subs[6].bad { ret (zero, Invalid) }
            var q = 0usize
            while q < instr {
                buf[gs + q] = code[q]
                q += 1usize
            }
            var overlap = false
            if has_overlap_map {
                overlap = (u32(overlap_map[g >> 3usize]) & (128u32 >> u32(g & 7usize))) != 0u32
            }
            size = store_points(xs, ys, on, total, nc, instr, overlap, buf)
            x_mins[g] = (u32(buf[2]) << 8u32) | u32(buf[3])
        }
        // nContours of zero is an empty glyph: nothing is written.
        if size > 0usize {
            if glyf_len + size + 3usize > glyf.len { ret (zero, Invalid) }
            var q = 0usize
            while q < size {
                glyf[glyf_len + q] = buf[q]
                q += 1usize
            }
            glyf_len += size
            while (glyf_len & 3usize) != 0usize {
                glyf[glyf_len] = 0u8
                glyf_len += 1usize
            }
        }
        g += 1usize
    }
    loca_values[glyph_count] = glyf_len
    let (loca, lce) = mem.alloc[u8](a, loca_len)
    if lce != ok { ret (zero, lce) }
    g = 0usize
    while g <= glyph_count {
        let v = loca_values[g]
        if index_format != 0u32 {
            store32(loca, g * 4usize, u32(v & 4294967295usize))
        } else {
            store16(loca, g * 2usize, u32((v >> 1usize) & 65535usize))
        }
        g += 1usize
    }
    ret (Glyphs { glyf: glyf[..glyf_len], loca: loca, x_mins: x_mins }, ok)
}

// A transformed `hmtx` table (WOFF2 5.3).
fn reconstruct_hmtx(a: *mem.Arena, data: []const u8, glyph_count: i64, metrics: usize, x_mins: []const u32) -> ([]u8, err) {
    var b = Buf { data: data, pos: 0usize, end: data.len, bad: false }
    let flags = get8(&b)
    if b.bad || (flags & 252u32) != 0u32 { ret (zero, Invalid) }
    let has_prop = (flags & 1u32) == 0u32
    let has_mono = (flags & 2u32) == 0u32
    if has_prop && has_mono { ret (zero, Invalid) }
    if i64(metrics) > glyph_count || metrics < 1usize { ret (zero, Invalid) }
    let count = usize(glyph_count)
    if count > x_mins.len + data.len { ret (zero, Invalid) }
    let (out, oe) = mem.alloc[u8](a, 2usize * metrics + 2usize * count)
    if oe != ok { ret (zero, oe) }
    let (widths, we) = mem.alloc[u32](a, metrics)
    if we != ok { ret (zero, we) }
    var i = 0usize
    while i < metrics {
        widths[i] = get16(&b)
        if b.bad { ret (zero, Invalid) }
        i += 1usize
    }
    let (lsbs, le) = mem.alloc[u32](a, count)
    if le != ok { ret (zero, le) }
    i = 0usize
    while i < count {
        var v = 0u32
        var from_stream = has_mono
        if i < metrics { from_stream = has_prop }
        if from_stream {
            v = get16(&b)
            if b.bad { ret (zero, Invalid) }
        } else {
            if i >= x_mins.len { ret (zero, Invalid) }
            v = x_mins[i]
        }
        lsbs[i] = v
        i += 1usize
    }
    var p = 0usize
    i = 0usize
    while i < count {
        if i < metrics {
            store16(out, p, widths[i])
            p += 2usize
        }
        store16(out, p, lsbs[i])
        p += 2usize
        i += 1usize
    }
    ret (out[..p], ok)
}

fn checksum(d: []const u8, len: usize) -> u32 {
    var sum = 0u32
    var i = 0usize
    while i < len {
        var word = 0u32
        var j = 0usize
        while j < 4usize {
            var byte = 0u32
            if i + j < len { byte = u32(d[i + j]) }
            word = (word << 8u32) | byte
            j += 1usize
        }
        sum = sum +% word
        i += 4usize
    }
    ret sum
}

// The sfnt bytes for a WOFF2 font.
fn to_sfnt(a: *mem.Arena, bytes: []const u8) -> ([]u8, err) {
    var file = Buf { data: bytes, pos: 0usize, end: bytes.len, bad: false }
    if get32(&file) != 0x774F4632u32 { ret (zero, Invalid) }
    let flavor = get32(&file)
    if file.bad || flavor == 0x74746366u32 { ret (zero, Invalid) }
    let whole_length = get32(&file)
    let count = usize(get16(&file))
    if file.bad || count == 0usize { ret (zero, Invalid) }
    let reserved = get16(&file)
    let sfnt_size = get32(&file)
    let compressed_size = usize(get32(&file))
    skip(&file, 4usize)
    skip(&file, 20usize)
    if file.bad { ret (zero, Invalid) }
    let (tables, te) = mem.alloc[Table](a, count)
    if te != ok { ret (zero, te) }
    var src_offset = 0usize
    var i = 0usize
    while i < count {
        let flag_byte = get8(&file)
        var tag = 0u32
        if (flag_byte & 63u32) == 63u32 {
            tag = get32(&file)
        } else {
            tag = known_tag(flag_byte & 63u32)
        }
        let version = (flag_byte >> 6u32) & 3u32
        var flags = 0u32
        if tag == 0x676C7966u32 || tag == 0x6C6F6361u32 {
            if version == 0u32 { flags = flags | 256u32 }
        } else if version != 0u32 {
            flags = flags | 256u32
        }
        flags = flags | version
        let dst_len = usize(read_base128(&file))
        var xform_len = dst_len
        if (flags & 256u32) != 0u32 {
            xform_len = usize(read_base128(&file))
            if tag == 0x6C6F6361u32 && xform_len != 0usize { ret (zero, Invalid) }
        }
        if file.bad { ret (zero, Invalid) }
        tables[i] = Table { tag: tag, flags: flags, dst_len: dst_len, xform_len: xform_len, src_off: src_offset, content: bytes[0..0] }
        src_offset += xform_len
        i += 1usize
    }
    let packed = take(&file, compressed_size)
    if file.bad || src_offset > LIMIT { ret (zero, Invalid) }
    let (scratch, se) = mem.alloc[u8](a, brotli.decode_scratch_required())
    if se != ok { ret (zero, se) }
    let (transformed_buf, de) = mem.alloc[u8](a, src_offset + SPARE)
    if de != ok { ret (zero, de) }
    let (got, be) = brotli.decode(packed, transformed_buf, scratch)
    if be != ok { ret (zero, Invalid) }
    if src_offset > got { ret (zero, Invalid) }
    i = 0usize
    while i < count {
        if tables[i].src_off + tables[i].xform_len > got { ret (zero, Invalid) }
        tables[i].content = transformed_buf[tables[i].src_off..tables[i].src_off + tables[i].xform_len]
        i += 1usize
    }
    // The last table of a tag is the one the maps below answer.
    var glyf_at = count
    var loca_at = count
    var hhea_at = count
    var head_at = count
    i = 0usize
    while i < count {
        let t = tables[i].tag
        if t == 0x676C7966u32 { glyf_at = i }
        if t == 0x6C6F6361u32 { loca_at = i }
        if t == 0x68686561u32 { hhea_at = i }
        if t == 0x68656164u32 { head_at = i }
        i += 1usize
    }
    if (glyf_at == count) != (loca_at == count) { ret (zero, Invalid) }
    var metrics = 0usize
    if hhea_at != count && tables[hhea_at].content.len >= 36usize {
        metrics = (usize(tables[hhea_at].content[34]) << 8usize) | usize(tables[hhea_at].content[35])
    }
    var x_mins: []const u32 = zero
    if glyf_at != count && (tables[glyf_at].flags & 256u32) != 0u32 {
        let (r, re) = reconstruct_glyf(a, tables[glyf_at].content, tables[loca_at].dst_len)
        if re != ok { ret (zero, re) }
        tables[glyf_at].content = r.glyf
        tables[loca_at].content = r.loca
        x_mins = r.x_mins
    }
    // Tag-sorted directory order (a stable insertion sort of indexes).
    let (order, oe) = mem.alloc[usize](a, count)
    if oe != ok { ret (zero, oe) }
    i = 0usize
    while i < count {
        order[i] = i
        i += 1usize
    }
    i = 1usize
    while i < count {
        let cur = order[i]
        var j = i
        while j > 0usize && tables[order[j - 1usize]].tag > tables[cur].tag {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[j] = cur
        i += 1usize
    }
    var pow2 = 0u32
    while (1usize << usize(pow2 + 1u32)) <= count {
        pow2 += 1u32
    }
    let search = (1usize << usize(pow2)) << 4usize
    // Table contents in directory order, with the reversed hmtx and the zeroed head adjustment.
    var total = 12usize + 16usize * count
    i = 0usize
    while i < count {
        let t = order[i]
        if tables[t].tag == 0x686D7478u32 && (tables[t].flags & 256u32) != 0u32 {
            var glyph_count = 0i64
            if loca_at != count {
                var unit = 2usize
                if (tables[loca_at].flags & 1u32) != 0u32 { unit = 4usize }
                glyph_count = i64(tables[loca_at].dst_len / unit) - 1i64
            }
            let (h, he) = reconstruct_hmtx(a, tables[t].content, glyph_count, metrics, x_mins)
            if he != ok { ret (zero, he) }
            tables[t].content = h
        }
        if tables[t].tag == 0x68656164u32 && tables[t].content.len >= 12usize {
            let (copy, ce) = mem.alloc[u8](a, tables[t].content.len)
            if ce != ok { ret (zero, ce) }
            var q = 0usize
            while q < copy.len {
                copy[q] = tables[t].content[q]
                q += 1usize
            }
            copy[8] = 0u8
            copy[9] = 0u8
            copy[10] = 0u8
            copy[11] = 0u8
            tables[t].content = copy
        }
        let len = tables[t].content.len
        total += len + ((4usize - (len & 3usize)) & 3usize)
        i += 1usize
    }
    let (font, fe) = mem.alloc[u8](a, total)
    if fe != ok { ret (zero, fe) }
    zero_bytes(font)
    store16(font, 0usize, flavor >> 16u32)
    store16(font, 2usize, flavor & 65535u32)
    store16(font, 4usize, u32(count))
    store16(font, 6usize, u32(search))
    store16(font, 8usize, pow2)
    store16(font, 10usize, u32((count << 4usize) - search))
    var offset = 12usize + 16usize * count
    i = 0usize
    while i < count {
        let t = tables[order[i]]
        let dir = 12usize + 16usize * i
        store32(font, dir, t.tag)
        store32(font, dir + 4usize, checksum(t.content, t.content.len))
        store32(font, dir + 8usize, u32(offset))
        store32(font, dir + 12usize, u32(t.content.len))
        var q = 0usize
        while q < t.content.len {
            font[offset + q] = t.content[q]
            q += 1usize
        }
        offset += t.content.len + ((4usize - (t.content.len & 3usize)) & 3usize)
        i += 1usize
    }
    if head_at != count {
        i = 0usize
        while i < count {
            let dir = 12usize + 16usize * i
            let tag = (u32(font[dir]) << 24u32) | (u32(font[dir + 1usize]) << 16u32) | (u32(font[dir + 2usize]) << 8u32) | u32(font[dir + 3usize])
            if tag == 0x68656164u32 {
                let head_off = (usize(font[dir + 8usize]) << 24usize) | (usize(font[dir + 9usize]) << 16usize) | (usize(font[dir + 10usize]) << 8usize) | usize(font[dir + 11usize])
                if head_off + 12usize > font.len { ret (zero, Invalid) }
                let adj = 0xB1B0AFBAu32 -% checksum(font, font.len)
                store32(font, head_off + 8usize, adj)
                break
            }
            i += 1usize
        }
    }
    ret (font, ok)
}
