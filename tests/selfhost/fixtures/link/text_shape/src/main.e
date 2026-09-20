// Shaping over a synthetic OpenType font built here byte by byte: cmap format 4, a GSUB
// ligature and a single substitution behind a feature, GPOS pair kerning, and the same
// font with a legacy `kern` table in place of GPOS.

use e.io
use e.mem
use e.os
use e.text.shape

type Builder = struct { bytes: []u8, at: usize }

fn w8(b: *Builder, v: u32) {
    b.bytes[b.at] = u8(v & 255u32)
    b.at += 1usize
}

fn w16(b: *Builder, v: u32) {
    w8(b, v >> 8u32)
    w8(b, v)
}

fn w32(b: *Builder, v: u32) {
    w16(b, v >> 16u32)
    w16(b, v & 65535u32)
}

fn patch16(b: *Builder, at: usize, v: u32) {
    b.bytes[at] = u8((v >> 8u32) & 255u32)
    b.bytes[at + 1usize] = u8(v & 255u32)
}

fn patch32(b: *Builder, at: usize, v: u32) {
    patch16(b, at, v >> 16u32)
    patch16(b, at + 2usize, v & 65535u32)
}

fn zeros(b: *Builder, count: usize) {
    var i = 0usize
    while i < count {
        w8(b, 0u32)
        i += 1usize
    }
}

// Records a table in directory slot `slot`: tag, checksum 0, offset, length.
fn table(b: *Builder, slot: usize, tag: u32, start: usize) {
    while b.at % 4usize != 0usize { w8(b, 0u32) }
    let record = 12usize + 16usize * slot
    patch32(b, record, tag)
    patch32(b, record + 8usize, u32(start))
    patch32(b, record + 12usize, u32(b.at - start))
}

// The advances: 0 .notdef 500, 1 a 500, 2 f 300, 3 i 200, 4 fi 450, 5 A 600, 6 V 600,
// 7 b 520, 8 a.sc 480.
fn metrics(b: *Builder) {
    let start = b.at
    w16(b, 500u32)
    w16(b, 0u32)
    w16(b, 500u32)
    w16(b, 0u32)
    w16(b, 300u32)
    w16(b, 0u32)
    w16(b, 200u32)
    w16(b, 0u32)
    w16(b, 450u32)
    w16(b, 0u32)
    w16(b, 600u32)
    w16(b, 0u32)
    w16(b, 600u32)
    w16(b, 0u32)
    w16(b, 520u32)
    w16(b, 0u32)
    w16(b, 480u32)
    w16(b, 0u32)
    table(b, 2usize, 1752003704u32, start)
}

// Format 4, one segment per mapped character: A 5, V 6, a 1, b 7, f 2, i 3.
fn cmap(b: *Builder) {
    let start = b.at
    w16(b, 0u32)
    w16(b, 1u32)
    w16(b, 3u32)
    w16(b, 1u32)
    w32(b, 12u32)
    w16(b, 4u32)
    w16(b, 72u32)
    w16(b, 0u32)
    w16(b, 14u32)
    w16(b, 0u32)
    w16(b, 0u32)
    w16(b, 0u32)
    w16(b, 65u32)
    w16(b, 86u32)
    w16(b, 97u32)
    w16(b, 98u32)
    w16(b, 102u32)
    w16(b, 105u32)
    w16(b, 65535u32)
    w16(b, 0u32)
    w16(b, 65u32)
    w16(b, 86u32)
    w16(b, 97u32)
    w16(b, 98u32)
    w16(b, 102u32)
    w16(b, 105u32)
    w16(b, 65535u32)
    w16(b, 65476u32)
    w16(b, 65456u32)
    w16(b, 65440u32)
    w16(b, 65445u32)
    w16(b, 65436u32)
    w16(b, 65434u32)
    w16(b, 1u32)
    zeros(b, 14usize)
    table(b, 4usize, 1668112752u32, start)
}

// `liga`: f + i -> fi (lookup 0, type 4); `smcp`: a -> a.sc by delta 7 (lookup 1, type 1).
fn gsub(b: *Builder) {
    let start = b.at
    w32(b, 65536u32)
    w16(b, 10u32)
    w16(b, 32u32)
    w16(b, 58u32)
    w16(b, 1u32)
    w32(b, 1145457748u32)
    w16(b, 8u32)
    w16(b, 4u32)
    w16(b, 0u32)
    w16(b, 0u32)
    w16(b, 65535u32)
    w16(b, 2u32)
    w16(b, 0u32)
    w16(b, 1u32)
    w16(b, 2u32)
    w32(b, 1818847073u32)
    w16(b, 14u32)
    w32(b, 1936548720u32)
    w16(b, 20u32)
    w16(b, 0u32)
    w16(b, 1u32)
    w16(b, 0u32)
    w16(b, 0u32)
    w16(b, 1u32)
    w16(b, 1u32)
    w16(b, 2u32)
    w16(b, 6u32)
    w16(b, 38u32)
    w16(b, 4u32)
    w16(b, 0u32)
    w16(b, 1u32)
    w16(b, 8u32)
    w16(b, 1u32)
    w16(b, 8u32)
    w16(b, 1u32)
    w16(b, 14u32)
    w16(b, 1u32)
    w16(b, 1u32)
    w16(b, 2u32)
    w16(b, 1u32)
    w16(b, 4u32)
    w16(b, 4u32)
    w16(b, 2u32)
    w16(b, 3u32)
    w16(b, 1u32)
    w16(b, 0u32)
    w16(b, 1u32)
    w16(b, 8u32)
    w16(b, 1u32)
    w16(b, 6u32)
    w16(b, 7u32)
    w16(b, 1u32)
    w16(b, 1u32)
    w16(b, 1u32)
    table(b, 5usize, 1196643650u32, start)
}

// `kern`: A followed by V loses 100 units of advance (pair adjustment format 1).
fn gpos(b: *Builder) {
    let start = b.at
    w32(b, 65536u32)
    w16(b, 10u32)
    w16(b, 30u32)
    w16(b, 44u32)
    w16(b, 1u32)
    w32(b, 1145457748u32)
    w16(b, 8u32)
    w16(b, 4u32)
    w16(b, 0u32)
    w16(b, 0u32)
    w16(b, 65535u32)
    w16(b, 1u32)
    w16(b, 0u32)
    w16(b, 1u32)
    w32(b, 1801810542u32)
    w16(b, 8u32)
    w16(b, 0u32)
    w16(b, 1u32)
    w16(b, 0u32)
    w16(b, 1u32)
    w16(b, 4u32)
    w16(b, 2u32)
    w16(b, 0u32)
    w16(b, 1u32)
    w16(b, 8u32)
    w16(b, 1u32)
    w16(b, 12u32)
    w16(b, 4u32)
    w16(b, 0u32)
    w16(b, 1u32)
    w16(b, 18u32)
    w16(b, 1u32)
    w16(b, 1u32)
    w16(b, 5u32)
    w16(b, 1u32)
    w16(b, 6u32)
    w16(b, 65436u32)
    table(b, 6usize, 1196445523u32, start)
}

// The same pair in a format 0 `kern` subtable.
fn kern(b: *Builder) {
    let start = b.at
    w16(b, 0u32)
    w16(b, 1u32)
    w16(b, 0u32)
    w16(b, 20u32)
    w16(b, 1u32)
    w16(b, 1u32)
    w16(b, 0u32)
    w16(b, 0u32)
    w16(b, 0u32)
    w16(b, 5u32)
    w16(b, 6u32)
    w16(b, 65436u32)
    table(b, 6usize, 1801810542u32, start)
}

fn build(bytes: []u8, legacy: bool) -> usize {
    var b = Builder { bytes: bytes, at: 0usize }
    w32(&b, 65536u32)
    w16(&b, 7u32)
    zeros(&b, 6usize + 16usize * 7usize)
    let head = b.at
    zeros(&b, 18usize)
    w16(&b, 1000u32)
    zeros(&b, 34usize)
    table(&b, 0usize, 1751474532u32, head)
    let hhea = b.at
    zeros(&b, 34usize)
    w16(&b, 9u32)
    table(&b, 1usize, 1751672161u32, hhea)
    metrics(&b)
    let maxp = b.at
    w32(&b, 20480u32)
    w16(&b, 9u32)
    table(&b, 3usize, 1835104368u32, maxp)
    cmap(&b)
    gsub(&b)
    if legacy { kern(&b) } else { gpos(&b) }
    ret b.at
}

fn near(x: f32, y: f32) -> bool {
    let d = x - y
    ret d < 0.0001 && d > -0.0001
}

fn main(a: *mem.Arena, args: []str) -> err {
    var full_bytes: [640]u8 = zero
    let full_len = build(full_bytes[0..], false)
    let font = shape.Font { id: 7u32, data: full_bytes[0..full_len], face_index: 0u32 }
    if shape.validate_font(font) != ok { os.exit(1i32) }
    var plain: shape.Options = zero

    // Ligature, clusters and advances in em units.
    let (fia, fia_error) = shape.shape(a, font, "fia", plain)
    if fia_error != ok || fia.font != 7u32 || fia.glyphs.len != 2usize { os.exit(2i32) }
    if fia.glyphs[0].id != 4u32 || fia.glyphs[0].cluster != 0usize || fia.glyphs[1].id != 1u32 || fia.glyphs[1].cluster != 2usize { os.exit(3i32) }
    if !near(fia.glyphs[0].advance_x, 0.45) || !near(fia.glyphs[1].advance_x, 0.5) || !near(fia.glyphs[0].advance_y, 0.0) { os.exit(4i32) }

    // Pair kerning through GPOS.
    let (av, av_error) = shape.shape(a, font, "AV", plain)
    if av_error != ok || av.glyphs.len != 2usize || av.glyphs[0].id != 5u32 || av.glyphs[1].id != 6u32 { os.exit(5i32) }
    if !near(av.glyphs[0].advance_x, 0.5) || !near(av.glyphs[1].advance_x, 0.6) { os.exit(6i32) }
    let (va, va_error) = shape.shape(a, font, "VA", plain)
    if va_error != ok || !near(va.glyphs[0].advance_x, 0.6) { os.exit(7i32) }

    // A feature enabled over a byte range, and the default ligature turned off.
    var requests: [1]shape.Feature = [1]shape.Feature{ shape.Feature { tag: 1936548720u32, value: 1u32, start: 0usize, end: 1usize } }
    let ranged = shape.Options { direction: .LeftToRight, script: 0u32, language: "", features: requests[0..] }
    let (small, small_error) = shape.shape(a, font, "aa", ranged)
    if small_error != ok || small.glyphs.len != 2usize || small.glyphs[0].id != 8u32 || small.glyphs[1].id != 1u32 || !near(small.glyphs[0].advance_x, 0.48) { os.exit(8i32) }
    requests[0].end = 2usize
    let (both, both_error) = shape.shape(a, font, "aa", ranged)
    if both_error != ok || both.glyphs[0].id != 8u32 || both.glyphs[1].id != 8u32 { os.exit(9i32) }
    var off: [1]shape.Feature = [1]shape.Feature{ shape.Feature { tag: 1818847073u32, value: 0u32, start: 0usize, end: 0usize } }
    let no_liga = shape.Options { direction: .LeftToRight, script: 1818326388u32, language: "ENG ", features: off[0..] }
    let (apart, apart_error) = shape.shape(a, font, "fi", no_liga)
    if apart_error != ok || apart.glyphs.len != 2usize || apart.glyphs[0].id != 2u32 || apart.glyphs[1].id != 3u32 || apart.script != 1818326388u32 { os.exit(10i32) }

    // Right to left reverses the visual order; a missing character is glyph 0; a
    // multi-byte character keeps byte clusters.
    let rtl = shape.Options { direction: .RightToLeft, script: 0u32, language: "", features: zero }
    let (backwards, backwards_error) = shape.shape(a, font, "AV", rtl)
    if backwards_error != ok || backwards.direction != .RightToLeft || backwards.glyphs[0].id != 6u32 || backwards.glyphs[0].cluster != 1usize || backwards.glyphs[1].id != 5u32 { os.exit(11i32) }
    let (missing, missing_error) = shape.shape(a, font, "zé", plain)
    if missing_error != ok || missing.glyphs.len != 2usize || missing.glyphs[0].id != 0u32 || !near(missing.glyphs[0].advance_x, 0.5) || missing.glyphs[1].id != 0u32 || missing.glyphs[1].cluster != 1usize { os.exit(12i32) }
    let (empty, empty_error) = shape.shape(a, font, "", plain)
    if empty_error != ok || empty.glyphs.len != 0usize { os.exit(13i32) }

    // The legacy font kerns the same pair through `kern`.
    var legacy_bytes: [640]u8 = zero
    let legacy_len = build(legacy_bytes[0..], true)
    let legacy = shape.Font { id: 8u32, data: legacy_bytes[0..legacy_len], face_index: 0u32 }
    let (kerned, kerned_error) = shape.shape(a, legacy, "AVfi", plain)
    if kerned_error != ok || kerned.glyphs.len != 3usize || !near(kerned.glyphs[0].advance_x, 0.5) || kerned.glyphs[2].id != 4u32 { os.exit(14i32) }

    // Refusals: bad text, a face the file does not have, a truncated file, a cmap with
    // no usable subtable.
    var bad_text: [2]u8 = [2]u8{ 255, 65 }
    let (_, text_error) = shape.shape(a, font, bad_text[0..], plain)
    if text_error != shape.InvalidText { os.exit(15i32) }
    let second = shape.Font { id: 7u32, data: full_bytes[0..full_len], face_index: 1u32 }
    if shape.validate_font(second) != shape.InvalidFont { os.exit(16i32) }
    let cut = shape.Font { id: 7u32, data: full_bytes[0..200usize], face_index: 0u32 }
    let (_, cut_error) = shape.shape(a, cut, "a", plain)
    if shape.validate_font(cut) != shape.InvalidFont || cut_error != shape.InvalidFont { os.exit(17i32) }
    var odd_bytes: [640]u8 = zero
    let odd_len = build(odd_bytes[0..], false)
    var at = 12usize
    var cmap_at = 0usize
    while at < 12usize + 16usize * 7usize {
        if u32(odd_bytes[at]) == 99u32 && u32(odd_bytes[at + 1usize]) == 109u32 && u32(odd_bytes[at + 2usize]) == 97u32 && u32(odd_bytes[at + 3usize]) == 112u32 {
            cmap_at = usize(odd_bytes[at + 8usize]) * 16777216usize + usize(odd_bytes[at + 9usize]) * 65536usize + usize(odd_bytes[at + 10usize]) * 256usize + usize(odd_bytes[at + 11usize])
        }
        at += 16usize
    }
    odd_bytes[cmap_at + 5usize] = 1u8
    let odd = shape.Font { id: 9u32, data: odd_bytes[0..odd_len], face_index: 0u32 }
    let (_, odd_error) = shape.shape(a, odd, "a", plain)
    if odd_error != shape.Unsupported { os.exit(18i32) }

    try io.print("text shape ok\n")
    ret ok
}
