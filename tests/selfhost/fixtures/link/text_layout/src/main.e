// Layout over two synthetic fonts built here: a Latin one (space, a, b, c, hyphen,
// full stop; ascender 800, descender -200 over 1000 units) and a fallback one with
// two Hebrew letters and `x`. Pins a single line's runs, bounds and baseline; word
// and character wrapping with hanging spaces; end, centre and justified alignment;
// font fallback and bidi reordering in both paragraph directions; newlines and
// blank lines; the line budget with an ellipsis; hit testing, carets and
// selections; and the refusals for a missing glyph, no fonts, bad UTF-8 and a
// negative width.

use e.gfx.geometry
use e.io
use e.mem
use e.os
use e.text.layout
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

fn table(b: *Builder, slot: usize, tag: u32, start: usize) {
    while b.at % 4usize != 0usize { w8(b, 0u32) }
    let record = 12usize + 16usize * slot
    patch32(b, record, tag)
    patch32(b, record + 8usize, u32(start))
    patch32(b, record + 12usize, u32(b.at - start))
}

// A font mapping `chars[i]` to glyph i + 1 with advance `advances[i]`; glyph 0 is
// .notdef with advance 500. `chars` ascend.
fn build(bytes: []u8, chars: []const u32, advances: []const u32, ascender: u32, descender: u32) -> usize {
    var b = Builder { bytes: bytes, at: 0usize }
    w32(&b, 65536u32)
    w16(&b, 5u32)
    zeros(&b, 6usize + 16usize * 5usize)
    let head = b.at
    zeros(&b, 18usize)
    w16(&b, 1000u32)
    zeros(&b, 34usize)
    table(&b, 0usize, 1751474532u32, head)
    let hhea = b.at
    w32(&b, 65536u32)
    w16(&b, ascender)
    w16(&b, descender)
    zeros(&b, 26usize)
    w16(&b, u32(chars.len) + 1u32)
    table(&b, 1usize, 1751672161u32, hhea)
    let hmtx = b.at
    w16(&b, 500u32)
    w16(&b, 0u32)
    var i = 0usize
    while i < chars.len {
        w16(&b, advances[i])
        w16(&b, 0u32)
        i += 1usize
    }
    table(&b, 2usize, 1752003704u32, hmtx)
    let maxp = b.at
    w32(&b, 20480u32)
    w16(&b, u32(chars.len) + 1u32)
    table(&b, 3usize, 1835104368u32, maxp)
    let cmap = b.at
    w16(&b, 0u32)
    w16(&b, 1u32)
    w16(&b, 3u32)
    w16(&b, 1u32)
    w32(&b, 12u32)
    let segments = chars.len + 1usize
    w16(&b, 4u32)
    w16(&b, u32(16usize + 8usize * segments))
    w16(&b, 0u32)
    w16(&b, u32(segments * 2usize))
    w16(&b, 0u32)
    w16(&b, 0u32)
    w16(&b, 0u32)
    i = 0usize
    while i < chars.len {
        w16(&b, chars[i])
        i += 1usize
    }
    w16(&b, 65535u32)
    w16(&b, 0u32)
    i = 0usize
    while i < chars.len {
        w16(&b, chars[i])
        i += 1usize
    }
    w16(&b, 65535u32)
    i = 0usize
    while i < chars.len {
        w16(&b, (u32(i) + 1u32 + 65536u32 - chars[i]) & 65535u32)
        i += 1usize
    }
    w16(&b, 1u32)
    zeros(&b, 2usize * segments)
    table(&b, 4usize, 1668112752u32, cmap)
    ret b.at
}

fn near(x: f32, y: f32) -> bool {
    let d = x - y
    ret d < 0.001 && d > -0.001
}

fn options(width: f32, align: layout.Align, wrap: layout.Wrap) -> layout.Options {
    ret layout.Options { width: width, max_lines: 0u32, align: align, wrap: wrap, ellipsis: "" }
}

fn glyph_count(line: layout.Line) -> usize {
    var n = 0usize
    var r = 0usize
    while r < line.runs.len {
        n += line.runs[r].run.glyphs.len
        r += 1usize
    }
    ret n
}

fn main(a: *mem.Arena, args: []str) -> err {
    var latin_bytes: [512]u8 = zero
    let latin_chars: [6]u32 = [6]u32{ 32u32, 45u32, 46u32, 97u32, 98u32, 99u32 }
    let latin_advances: [6]u32 = [6]u32{ 250u32, 300u32, 250u32, 500u32, 500u32, 500u32 }
    let latin_len = build(latin_bytes[0..], latin_chars[0..], latin_advances[0..], 800u32, 65336u32)
    var hebrew_bytes: [512]u8 = zero
    let hebrew_chars: [3]u32 = [3]u32{ 120u32, 1488u32, 1489u32 }
    let hebrew_advances: [3]u32 = [3]u32{ 400u32, 600u32, 600u32 }
    let hebrew_len = build(hebrew_bytes[0..], hebrew_chars[0..], hebrew_advances[0..], 0u32, 0u32)
    let latin = shape.Font { id: 1u32, data: latin_bytes[0..latin_len], face_index: 0u32 }
    let hebrew = shape.Font { id: 2u32, data: hebrew_bytes[0..hebrew_len], face_index: 0u32 }
    if shape.validate_font(latin) != ok || shape.validate_font(hebrew) != ok { os.exit(1i32) }
    let fonts: [2]layout.FontChoice = [2]layout.FontChoice{ layout.FontChoice { font: latin, size: 10.0 }, layout.FontChoice { font: hebrew, size: 10.0 } }
    let style = layout.Style { fonts: fonts[0..], language: "", line_height: 0.0 }

    // One line: a(5) b(5) space(2.5) a b = 22.5 wide, 10 high, baseline 8.
    let (one, one_error) = layout.layout(a, "ab ab", style, options(0.0, .Start, .Word))
    if one_error != ok || one.lines.len != 1usize { os.exit(2i32) }
    let l0 = one.lines[0]
    if l0.runs.len != 1usize || l0.runs[0].run.glyphs.len != 5usize || l0.runs[0].run.font != 1u32 { os.exit(3i32) }
    if !near(l0.bounds.width, 22.5) || !near(l0.bounds.height, 10.0) || !near(l0.baseline, 8.0) || l0.start != 0usize || l0.end != 5usize { os.exit(4i32) }
    if !near(l0.runs[0].origin.x, 0.0) || !near(l0.runs[0].origin.y, 8.0) || !near(l0.runs[0].size, 10.0) { os.exit(5i32) }
    if l0.runs[0].run.glyphs[3].cluster != 3usize || !near(one.bounds.width, 22.5) || !near(one.bounds.height, 10.0) { os.exit(6i32) }

    // Word wrap at 15: "ab " hangs its space, then "ab"; the second line sits at y 10.
    let (wrapped, wrapped_error) = layout.layout(a, "ab ab", style, options(15.0, .Start, .Word))
    if wrapped_error != ok || wrapped.lines.len != 2usize { os.exit(7i32) }
    if wrapped.lines[0].start != 0usize || wrapped.lines[0].end != 3usize || wrapped.lines[1].start != 3usize || wrapped.lines[1].end != 5usize { os.exit(8i32) }
    if !near(wrapped.lines[0].bounds.width, 10.0) || glyph_count(wrapped.lines[0]) != 3usize || !near(wrapped.lines[1].bounds.y, 10.0) || !near(wrapped.lines[1].baseline, 18.0) { os.exit(9i32) }
    if !near(wrapped.bounds.height, 20.0) { os.exit(10i32) }

    // Character wrap at 12: "ab" | "c"; a word wider than the line breaks by character.
    let (chars, chars_error) = layout.layout(a, "abc", style, options(12.0, .Start, .Character))
    if chars_error != ok || chars.lines.len != 2usize || chars.lines[0].end != 2usize || chars.lines[1].start != 2usize { os.exit(11i32) }
    let (long, long_error) = layout.layout(a, "abcabc", style, options(12.0, .Start, .Word))
    if long_error != ok || long.lines.len != 3usize || long.lines[0].end != 2usize { os.exit(12i32) }
    // No wrap: one line whatever the width.
    let (none, none_error) = layout.layout(a, "ab ab ab", style, options(12.0, .Start, .None))
    if none_error != ok || none.lines.len != 1usize { os.exit(13i32) }

    // Alignment: end and centre move the line; justify stretches the spaces of a
    // wrapped line and leaves the paragraph's last line alone.
    let (ended, ended_error) = layout.layout(a, "ab", style, options(30.0, .End, .Word))
    if ended_error != ok || !near(ended.lines[0].bounds.x, 20.0) || !near(ended.lines[0].runs[0].origin.x, 20.0) { os.exit(14i32) }
    let (centred, centred_error) = layout.layout(a, "ab", style, options(30.0, .Center, .Word))
    if centred_error != ok || !near(centred.lines[0].bounds.x, 10.0) { os.exit(15i32) }
    let (justified, justified_error) = layout.layout(a, "ab ab ab", style, options(26.0, .Justify, .Word))
    if justified_error != ok || justified.lines.len != 2usize { os.exit(16i32) }
    let j0 = justified.lines[0]
    if !near(j0.bounds.width, 26.0) || !near(j0.runs[0].run.glyphs[2].advance_x, 0.6) || !near(justified.lines[1].bounds.width, 10.0) { os.exit(17i32) }

    // Fallback and bidi in a left-to-right paragraph: a, alef, b -> three runs in
    // visual order a | alef | b, the Hebrew one from font 2 running right to left.
    let (mixed, mixed_error) = layout.layout(a, "a\xd7\x90b", style, options(0.0, .Start, .Word))
    if mixed_error != ok || mixed.lines.len != 1usize || mixed.lines[0].runs.len != 3usize { os.exit(18i32) }
    let m = mixed.lines[0]
    if m.runs[0].run.font != 1u32 || m.runs[1].run.font != 2u32 || m.runs[2].run.font != 1u32 { os.exit(19i32) }
    if m.runs[1].run.direction != .RightToLeft || m.runs[1].run.glyphs[0].cluster != 1usize || !near(m.runs[1].origin.x, 5.0) || !near(m.runs[2].origin.x, 11.0) { os.exit(20i32) }
    if !near(m.bounds.width, 16.0) { os.exit(21i32) }
    // A right-to-left paragraph: alef bet, space, a -> visually a | space | bet alef,
    // the Latin run leftmost and the Hebrew glyphs reversed.
    let (rtl, rtl_error) = layout.layout(a, "\xd7\x90\xd7\x91 a", style, options(0.0, .Start, .Word))
    if rtl_error != ok || rtl.lines.len != 1usize { os.exit(22i32) }
    let r = rtl.lines[0]
    if r.runs.len != 3usize || r.runs[0].run.font != 1u32 || r.runs[0].run.glyphs[0].cluster != 5usize || !near(r.runs[0].origin.x, 0.0) { os.exit(23i32) }
    if r.runs[2].run.direction != .RightToLeft || r.runs[2].run.glyphs[0].cluster != 2usize || r.runs[2].run.glyphs[1].cluster != 0usize { os.exit(24i32) }
    // Start alignment in a right-to-left paragraph is the right edge.
    let (rtl_start, rtl_start_error) = layout.layout(a, "\xd7\x90", style, options(30.0, .Start, .Word))
    if rtl_start_error != ok || !near(rtl_start.lines[0].bounds.x, 24.0) { os.exit(25i32) }

    // Newlines: three paragraphs, the middle one blank, each its own line.
    let (paragraphs, paragraphs_error) = layout.layout(a, "ab\n\r\nc", style, options(0.0, .Start, .Word))
    if paragraphs_error != ok || paragraphs.lines.len != 3usize { os.exit(26i32) }
    if paragraphs.lines[1].runs.len != 0usize || !near(paragraphs.lines[1].bounds.height, 10.0) || paragraphs.lines[2].start != 5usize || !near(paragraphs.lines[2].bounds.y, 20.0) { os.exit(27i32) }
    // A taller line height centres the baseline.
    let tall = layout.Style { fonts: fonts[0..], language: "", line_height: 14.0 }
    let (spaced, spaced_error) = layout.layout(a, "ab", tall, options(0.0, .Start, .Word))
    if spaced_error != ok || !near(spaced.lines[0].bounds.height, 14.0) || !near(spaced.lines[0].baseline, 10.0) { os.exit(28i32) }

    // The line budget: two lines of "ab ab ab" at width 15 would be three; the last
    // keeps "ab " and the ellipsis (2.5) after it, its clusters naming the line's end.
    var budget = options(15.0, .Start, .Word)
    budget.max_lines = 2u32
    budget.ellipsis = "."
    let (cut, cut_error) = layout.layout(a, "ab ab ab", style, budget)
    if cut_error != ok || cut.lines.len != 2usize { os.exit(29i32) }
    let c1 = cut.lines[1]
    if c1.start != 3usize || c1.end != 6usize || c1.runs.len != 2usize || c1.runs[1].run.glyphs.len != 1usize || c1.runs[1].run.glyphs[0].cluster != 6usize { os.exit(30i32) }
    if !near(c1.bounds.width, 12.5) || !near(c1.runs[1].origin.x, 12.5) { os.exit(31i32) }

    // Hit testing on "ab ab": x 12 is in the space, nearer its end; past the end is 5;
    // above the first line and below the last clamp.
    if layout.hit_test(&one, geometry.Point { x: 12.0, y: 5.0 }) != 3usize { os.exit(32i32) }
    if layout.hit_test(&one, geometry.Point { x: 11.0, y: 5.0 }) != 2usize { os.exit(33i32) }
    if layout.hit_test(&one, geometry.Point { x: 40.0, y: 5.0 }) != 5usize { os.exit(34i32) }
    if layout.hit_test(&one, geometry.Point { x: -3.0, y: -3.0 }) != 0usize { os.exit(35i32) }
    if layout.hit_test(&wrapped, geometry.Point { x: 1.0, y: 50.0 }) != 3usize { os.exit(36i32) }
    // In the mixed line the Hebrew glyph's left half is its logical end.
    if layout.hit_test(&mixed, geometry.Point { x: 6.0, y: 5.0 }) != 3usize || layout.hit_test(&mixed, geometry.Point { x: 10.0, y: 5.0 }) != 1usize { os.exit(37i32) }

    // Carets: 3 sits at x 12.5, 5 at the end, a wrapped offset at the next line's start.
    let k3 = layout.caret(&one, 3usize)
    if !near(k3.x, 12.5) || !near(k3.y, 0.0) || !near(k3.height, 10.0) || !near(k3.width, 0.0) { os.exit(38i32) }
    if !near(layout.caret(&one, 5usize).x, 22.5) || !near(layout.caret(&wrapped, 3usize).y, 10.0) || !near(layout.caret(&wrapped, 3usize).x, 0.0) { os.exit(39i32) }
    // The Hebrew glyph's caret is its right edge; a continuation byte snaps back.
    if !near(layout.caret(&mixed, 1usize).x, 11.0) || !near(layout.caret(&mixed, 2usize).x, 11.0) || !near(layout.caret(&mixed, 3usize).x, 11.0) { os.exit(40i32) }

    // Selections: one rect on one line; two across a wrap; none when empty.
    let (single, single_error) = layout.selection(a, &one, 1usize, 4usize)
    if single_error != ok || single.len != 1usize || !near(single[0].x, 5.0) || !near(single[0].width, 12.5) || !near(single[0].height, 10.0) { os.exit(41i32) }
    let (two, two_error) = layout.selection(a, &wrapped, 1usize, 4usize)
    if two_error != ok || two.len != 2usize || !near(two[0].x, 5.0) || !near(two[0].width, 7.5) || !near(two[1].y, 10.0) || !near(two[1].width, 5.0) { os.exit(42i32) }
    let (empty, empty_error) = layout.selection(a, &one, 2usize, 2usize)
    if empty_error != ok || empty.len != 0usize { os.exit(43i32) }
    let (_, backwards_error) = layout.selection(a, &one, 4usize, 1usize)
    if backwards_error != layout.Invalid { os.exit(44i32) }

    // Refusals.
    let (_, missing_error) = layout.layout(a, "abz", style, options(0.0, .Start, .Word))
    if missing_error != layout.MissingGlyph { os.exit(45i32) }
    let (_, no_fonts_error) = layout.layout(a, "ab", layout.Style { fonts: fonts[0usize..0usize], language: "", line_height: 0.0 }, options(0.0, .Start, .Word))
    if no_fonts_error != layout.Invalid { os.exit(46i32) }
    let (_, utf8_error) = layout.layout(a, "a\xff", style, options(0.0, .Start, .Word))
    if utf8_error != layout.Invalid { os.exit(47i32) }
    let (_, width_error) = layout.layout(a, "ab", style, options(-1.0, .Start, .Word))
    if width_error != layout.Invalid { os.exit(48i32) }
    let (_, ellipsis_error) = layout.layout(a, "ab ab ab", style, layout.Options { width: 15.0, max_lines: 1u32, align: .Start, wrap: .Word, ellipsis: "z" })
    if ellipsis_error != layout.MissingGlyph { os.exit(49i32) }

    try io.print("text layout ok\n")
    ret ok
}
