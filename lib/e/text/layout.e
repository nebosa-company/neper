// Paragraph layout over `e.text.shape`: the source is split at newlines, each
// paragraph's characters are given a direction and a font, maximal spans of one
// (direction, font) are shaped into items, lines are cut at word or character
// opportunities against `options.width`, and each line's items are sliced to it,
// reordered for bidi and placed against the alignment. Every offset is a byte
// offset into `source` at a UTF-8 boundary; a glyph's `cluster` is the byte its
// character starts at.
//
// Direction: a character is strong right-to-left in the Hebrew, Arabic, Syriac,
// Thaana, NKo, Samaritan and Mandaic blocks and their presentation forms; digits
// and everything else with a glyph are left-to-right; whitespace and punctuation
// take the direction of matching strong neighbours or else the paragraph's, which
// is that of its first strong character. Reordering is the two-level case: runs
// against the paragraph direction are reversed as a group. ponytail: this is the
// part of UAX #9 a two-level text needs -- explicit embeddings, isolates and
// nested levels are the upgrade, behind the same `Line.runs`.
//
// Fonts: a character is shaped in the first `Style.fonts` entry whose `cmap` maps
// it; a character no font maps is `MissingGlyph`. Every font is asked one
// character at a time and shaping answers with `cmap` alone at that size, so a
// ligature or kern only forms within one span; a span is shaped once more as a
// whole. ponytail: one shaping per character per font is quadratic in fonts;
// a cmap lookup on the fence would make it a table read.
//
// Metrics: a font's `hhea` ascender and descender (or 0.8 and 0.2 of the size
// when the font carries none) give a line's natural height and baseline;
// `Style.line_height` above zero replaces the height and centres the baseline
// within it. Trailing whitespace hangs: it is shaped and placed but does not
// count against the width or the alignment. `Justify` spreads the shortfall
// over the spaces of every line but a paragraph's last. With `max_lines` set,
// the last line drops characters until `ellipsis` fits after it and carries
// its glyphs as a final run whose clusters all name the line's end.

use e.mem
use e.gfx.geometry
use e.text.shape
use e.text.unicode

type Align = enum u8 { Start, End, Center, Justify }
type Wrap = enum u8 { None, Word, Character }
type FontChoice = struct { font: shape.Font, size: f32 }
type Style = struct { fonts: []const FontChoice, language: str, line_height: f32 }
type GlyphRun = struct { run: shape.Run, origin: geometry.Point, size: f32 }
type Line = struct { runs: []const GlyphRun, bounds: geometry.Rect, baseline: f32, start: usize, end: usize }
type Layout = struct { source: str, lines: []const Line, bounds: geometry.Rect }
type Options = struct { width: f32, max_lines: u32, align: Align, wrap: Wrap, ellipsis: str }
error MissingGlyph
error Invalid
error TooLarge

const MAX_SOURCE: usize = 16777216usize
const MAX_ITEMS: usize = 65536usize
const NONE: usize = 18446744073709551615usize

// A shaped span of one direction and one font: the run, its byte range, and the
// advance of every byte's cluster at the font's size (on the cluster's first byte).
type Item = struct { run: shape.Run, start: usize, end: usize, font: usize, rtl: bool }

type Metrics = struct { ascent: f32, descent: f32 }

fn is_rtl(scalar: u32) -> bool {
    if scalar >= 1424u32 && scalar <= 2303u32 { ret true }
    if scalar >= 64285u32 && scalar <= 65023u32 { ret true }
    if scalar >= 65136u32 && scalar <= 65279u32 { ret true }
    if scalar >= 67584u32 && scalar <= 69631u32 { ret true }
    ret scalar >= 124928u32 && scalar <= 126975u32
}

fn is_neutral(scalar: u32) -> bool {
    if unicode.is_whitespace(scalar) { ret true }
    let c = unicode.category(scalar)
    ret c == .Pc || c == .Pd || c == .Ps || c == .Pe || c == .Pi || c == .Pf || c == .Po || c == .Sm || c == .Sc || c == .Sk || c == .So
}

fn read16(d: []const u8, at: usize) -> i32 {
    if at + 2usize > d.len { ret 0i32 }
    var v = (i32(d[at]) << 8u32) | i32(d[at + 1usize])
    if v >= 32768i32 { v -= 65536i32 }
    ret v
}

fn read32(d: []const u8, at: usize) -> u32 {
    if at + 4usize > d.len { ret 0u32 }
    ret (u32(d[at]) << 24u32) | (u32(d[at + 1usize]) << 16u32) | (u32(d[at + 2usize]) << 8u32) | u32(d[at + 3usize])
}

// The ascent and descent of a font choice, from `hhea` over `head`'s unitsPerEm.
fn metrics_of(choice: FontChoice) -> Metrics {
    let d = choice.font.data
    var em = 0i32
    var ascent = 0i32
    var descent = 0i32
    let count = usize(read16(d, 4usize))
    var i = 0usize
    while i < count {
        let record = 12usize + 16usize * i
        let tag = read32(d, record)
        let at = usize(read32(d, record + 8usize))
        if tag == 1751474532u32 { em = read16(d, at + 18usize) }
        if tag == 1751672161u32 {
            ascent = read16(d, at + 4usize)
            descent = read16(d, at + 6usize)
        }
        i += 1usize
    }
    if em <= 0i32 || ascent - descent <= 0i32 { ret Metrics { ascent: 0.8 * choice.size, descent: 0.2 * choice.size } }
    var down = 0i32 - descent
    if down < 0i32 { down = 0i32 }
    ret Metrics { ascent: f32(ascent) * choice.size / f32(em), descent: f32(down) * choice.size / f32(em) }
}

fn shape_options(rtl: bool, language: str) -> shape.Options {
    var o: shape.Options = zero
    if rtl { o.direction = .RightToLeft }
    o.language = language
    ret o
}

fn valid_utf8(s: str) -> bool {
    var at = 0usize
    while at < s.len {
        let (scalar, width) = unicode.read_utf8(s, at)
        if scalar == 65533u32 && width == 1usize { ret false }
        at += width
    }
    ret true
}

// The first font that maps `scalar`, or NONE.
fn font_for(a: *mem.Arena, style: Style, scalar: u32) -> (usize, err) {
    var buffer: [4]u8 = zero
    let width = unicode.write_utf8(scalar, buffer[0..], 0usize)
    var i = 0usize
    while i < style.fonts.len {
        let (run, shape_error) = shape.shape(a, style.fonts[i].font, buffer[..width], shape_options(false, style.language))
        if shape_error != ok { ret (NONE, shape_error) }
        if run.glyphs.len > 0usize && run.glyphs[0].id != 0u32 { ret (i, ok) }
        i += 1usize
    }
    ret (NONE, ok)
}

fn shape_span(a: *mem.Arena, style: Style, source: str, start: usize, end: usize, font: usize, rtl: bool) -> (Item, err) {
    let (run, shape_error) = shape.shape(a, style.fonts[font].font, source[start..end], shape_options(rtl, style.language))
    if shape_error != ok { ret (zero, shape_error) }
    // Clusters are relative to the span; make them source offsets.
    let (glyphs, glyphs_error) = mem.alloc[shape.Glyph](a, run.glyphs.len)
    if glyphs_error != ok { ret (zero, glyphs_error) }
    var i = 0usize
    while i < glyphs.len {
        glyphs[i] = run.glyphs[i]
        glyphs[i].cluster += start
        i += 1usize
    }
    var item: Item = zero
    item.run = shape.Run { font: run.font, direction: run.direction, script: run.script, language: run.language, glyphs: glyphs }
    item.start = start
    item.end = end
    item.font = font
    item.rtl = rtl
    ret (item, ok)
}

// The items of one paragraph `[start, end)`, in logical order.
fn shape_paragraph(a: *mem.Arena, style: Style, source: str, start: usize, end: usize, items: []Item, count: *usize, rtl_paragraph: *bool) -> err {
    let length = end - start
    let (scalars, scalars_error) = mem.alloc[u32](a, length + 1usize)
    if scalars_error != ok { ret scalars_error }
    let (fonts, fonts_error) = mem.alloc[usize](a, length + 1usize)
    if fonts_error != ok { ret fonts_error }
    let (dirs, dirs_error) = mem.alloc[u8](a, length + 1usize)
    if dirs_error != ok { ret dirs_error }
    // Per character: scalar, font, and a direction class (0 L, 1 R, 2 neutral).
    var at = start
    var chars = 0usize
    var paragraph_rtl = false
    var seen_strong = false
    while at < end {
        let (scalar, width) = unicode.read_utf8(source, at)
        scalars[chars] = scalar
        let (font, font_error) = font_for(a, style, scalar)
        if font_error != ok { ret font_error }
        if font == NONE { ret MissingGlyph }
        fonts[chars] = font
        if is_neutral(scalar) {
            dirs[chars] = 2u8
        } else if is_rtl(scalar) {
            dirs[chars] = 1u8
            if !seen_strong { paragraph_rtl = true }
            seen_strong = true
        } else {
            dirs[chars] = 0u8
            seen_strong = true
        }
        chars += 1usize
        at += width
    }
    *rtl_paragraph = paragraph_rtl
    var paragraph_dir = 0u8
    if paragraph_rtl { paragraph_dir = 1u8 }
    // Neutrals: matching strong neighbours, else the paragraph.
    var i = 0usize
    while i < chars {
        if dirs[i] == 2u8 {
            var j = i
            while j < chars && dirs[j] == 2u8 { j += 1usize }
            var before = paragraph_dir
            if i > 0usize { before = dirs[i - 1usize] }
            var after = paragraph_dir
            if j < chars { after = dirs[j] }
            var resolved = paragraph_dir
            if before == after { resolved = before }
            while i < j {
                dirs[i] = resolved
                i += 1usize
            }
        } else {
            i += 1usize
        }
    }
    // Spans of one (direction, font).
    at = start
    i = 0usize
    while i < chars {
        var j = i
        var span_end = at
        while j < chars && dirs[j] == dirs[i] && fonts[j] == fonts[i] {
            span_end += unicode.utf8_length(scalars[j])
            j += 1usize
        }
        if *count >= items.len { ret TooLarge }
        let (item, item_error) = shape_span(a, style, source, at, span_end, fonts[i], dirs[i] == 1u8)
        if item_error != ok { ret item_error }
        items[*count] = item
        *count += 1usize
        at = span_end
        i = j
    }
    ret ok
}

// The advance at `size` of every glyph whose cluster is `byte`, over the items.
fn cluster_advance(items: []const Item, from: usize, to: usize, style: Style, byte: usize) -> f32 {
    var total: f32 = 0.0
    var i = from
    while i < to {
        if byte >= items[i].start && byte < items[i].end {
            let size = style.fonts[items[i].font].size
            var g = 0usize
            while g < items[i].run.glyphs.len {
                if items[i].run.glyphs[g].cluster == byte { total += items[i].run.glyphs[g].advance_x * size }
                g += 1usize
            }
        }
        i += 1usize
    }
    ret total
}

fn scalar_at(source: str, at: usize) -> u32 {
    let (scalar, _) = unicode.read_utf8(source, at)
    ret scalar
}

fn next_char(source: str, at: usize) -> usize {
    let (_, width) = unicode.read_utf8(source, at)
    ret at + width
}

// Whether a line may end before `at` (a cluster start) under `wrap`.
fn can_break(source: str, at: usize, wrap: Wrap, cluster_start: bool) -> bool {
    if wrap == .None || !cluster_start { ret false }
    if wrap == .Character { ret true }
    let (_, width) = unicode.read_utf8(source, at)
    if at < width { ret false }
    // Word: after whitespace and before a non-space.
    var previous = at - 1usize
    while previous > 0usize && (u32(source[previous]) & 192u32) == 128u32 { previous -= 1usize }
    ret unicode.is_whitespace(scalar_at(source, previous)) && !unicode.is_whitespace(scalar_at(source, at))
}

fn is_cluster_start(items: []const Item, from: usize, to: usize, byte: usize) -> bool {
    var i = from
    while i < to {
        var g = 0usize
        while g < items[i].run.glyphs.len {
            if items[i].run.glyphs[g].cluster == byte { ret true }
            g += 1usize
        }
        i += 1usize
    }
    ret false
}

type Cut = struct { start: usize, end: usize, paragraph_end: bool, rtl: bool, item_from: usize, item_to: usize }

// The width of `[start, end)` without its trailing whitespace.
fn measure(items: []const Item, from: usize, to: usize, style: Style, source: str, start: usize, end: usize) -> f32 {
    var last = end
    while last > start {
        var previous = last - 1usize
        while previous > start && (u32(source[previous]) & 192u32) == 128u32 { previous -= 1usize }
        if !unicode.is_whitespace(scalar_at(source, previous)) { break }
        last = previous
    }
    var total: f32 = 0.0
    var at = start
    while at < last {
        total += cluster_advance(items, from, to, style, at)
        at += 1usize
    }
    ret total
}

// Cuts a paragraph's `[start, end)` into lines under the width and wrap.
fn cut_paragraph(items: []const Item, from: usize, to: usize, style: Style, source: str, start: usize, end: usize, options: Options, rtl: bool, cuts: []Cut, count: *usize) -> err {
    var line_start = start
    while true {
        var at = line_start
        var last_opportunity = NONE
        var width: f32 = 0.0
        var line_end = end
        while at < end {
            let cluster_start = is_cluster_start(items, from, to, at)
            if at > line_start && can_break(source, at, options.wrap, cluster_start) { last_opportunity = at }
            let adv = cluster_advance(items, from, to, style, at)
            // Whitespace never overflows a line: it hangs past the end.
            if options.width > 0.0 && options.wrap != .None && at > line_start && !unicode.is_whitespace(scalar_at(source, at)) && width + adv > options.width {
                if last_opportunity != NONE {
                    line_end = last_opportunity
                } else if cluster_start {
                    // Character wrap, or a word longer than the line: cut it here.
                    line_end = at
                } else {
                    line_end = cluster_start_before(items, from, to, at)
                }
                break
            }
            width += adv
            at = next_char(source, at)
        }
        if *count >= cuts.len { ret TooLarge }
        if line_end <= line_start && line_start < end { line_end = next_char(source, line_start) }
        cuts[*count] = Cut { start: line_start, end: line_end, paragraph_end: line_end >= end, rtl: rtl, item_from: from, item_to: to }
        *count += 1usize
        if line_end >= end { break }
        line_start = line_end
    }
    ret ok
}

fn cluster_start_before(items: []const Item, from: usize, to: usize, at: usize) -> usize {
    var byte = at
    while byte > 0usize {
        byte -= 1usize
        if is_cluster_start(items, from, to, byte) { ret byte }
    }
    ret 0usize
}

// The glyphs of `item` whose clusters fall in `[start, end)`, as a run; a
// whitespace glyph before `last_content` is widened by `extra` (justification).
fn slice_item(a: *mem.Arena, item: Item, start: usize, end: usize, source: str, last_content: usize, extra: f32, size: f32) -> (shape.Run, usize, err) {
    var count = 0usize
    var g = 0usize
    while g < item.run.glyphs.len {
        let c = item.run.glyphs[g].cluster
        if c >= start && c < end { count += 1usize }
        g += 1usize
    }
    let (glyphs, glyphs_error) = mem.alloc[shape.Glyph](a, count)
    if glyphs_error != ok { ret (zero, 0usize, glyphs_error) }
    var n = 0usize
    g = 0usize
    while g < item.run.glyphs.len {
        let c = item.run.glyphs[g].cluster
        if c >= start && c < end {
            glyphs[n] = item.run.glyphs[g]
            if extra > 0.0 && c < last_content && unicode.is_whitespace(scalar_at(source, c)) { glyphs[n].advance_x += extra / size }
            n += 1usize
        }
        g += 1usize
    }
    let run = shape.Run { font: item.run.font, direction: item.run.direction, script: item.run.script, language: item.run.language, glyphs: glyphs }
    ret (run, count, ok)
}

fn run_width(run: GlyphRun) -> f32 {
    var total: f32 = 0.0
    var g = 0usize
    while g < run.run.glyphs.len {
        total += run.run.glyphs[g].advance_x * run.size
        g += 1usize
    }
    ret total
}

fn reverse_runs(runs: []GlyphRun, from: usize, to: usize) {
    var i = from
    var j = to
    while i + 1usize < j {
        j -= 1usize
        let t = runs[i]
        runs[i] = runs[j]
        runs[j] = t
        i += 1usize
    }
}

// Two-level reordering: runs against the paragraph direction reverse as groups;
// a right-to-left paragraph reverses the whole line first.
fn reorder(runs: []GlyphRun, paragraph_rtl: bool) {
    if paragraph_rtl { reverse_runs(runs, 0usize, runs.len) }
    var i = 0usize
    while i < runs.len {
        let against = (runs[i].run.direction == .RightToLeft) != paragraph_rtl
        if against {
            var j = i
            while j < runs.len && ((runs[j].run.direction == .RightToLeft) != paragraph_rtl) { j += 1usize }
            reverse_runs(runs, i, j)
            i = j
        } else {
            i += 1usize
        }
    }
}

// The whitespace characters of `[start, last_content)`, the ones justification widens.
fn count_spaces(source: str, start: usize, last_content: usize) -> usize {
    var count = 0usize
    var at = start
    while at < last_content {
        if unicode.is_whitespace(scalar_at(source, at)) { count += 1usize }
        at = next_char(source, at)
    }
    ret count
}

fn content_end(source: str, start: usize, end: usize) -> usize {
    var last = end
    while last > start {
        var previous = last - 1usize
        while previous > start && (u32(source[previous]) & 192u32) == 128u32 { previous -= 1usize }
        if !unicode.is_whitespace(scalar_at(source, previous)) { break }
        last = previous
    }
    ret last
}

// Shapes the ellipsis in the first font that maps all of it; clusters name `at`.
fn ellipsis_run(a: *mem.Arena, style: Style, text: str, at: usize, rtl: bool) -> (GlyphRun, err) {
    var f = 0usize
    while f < style.fonts.len {
        let (run, shape_error) = shape.shape(a, style.fonts[f].font, text, shape_options(rtl, style.language))
        if shape_error != ok { ret (zero, shape_error) }
        var complete = true
        var g = 0usize
        while g < run.glyphs.len {
            if run.glyphs[g].id == 0u32 { complete = false }
            g += 1usize
        }
        if complete {
            let (glyphs, glyphs_error) = mem.alloc[shape.Glyph](a, run.glyphs.len)
            if glyphs_error != ok { ret (zero, glyphs_error) }
            g = 0usize
            while g < glyphs.len {
                glyphs[g] = run.glyphs[g]
                glyphs[g].cluster = at
                g += 1usize
            }
            let own = shape.Run { font: run.font, direction: run.direction, script: run.script, language: run.language, glyphs: glyphs }
            ret (GlyphRun { run: own, origin: geometry.Point { x: 0.0, y: 0.0 }, size: style.fonts[f].size }, ok)
        }
        f += 1usize
    }
    ret (zero, MissingGlyph)
}

// Builds one line from its cut: sliced runs in visual order, placed and aligned.
fn build_line(a: *mem.Arena, items: []const Item, style: Style, source: str, cut: Cut, options: Options, top: f32, tail: GlyphRun, has_tail: bool) -> (Line, err) {
    var count = 0usize
    var i = cut.item_from
    while i < cut.item_to {
        if items[i].end > cut.start && items[i].start < cut.end { count += 1usize }
        i += 1usize
    }
    var total = count
    if has_tail { total += 1usize }
    let (runs, runs_error) = mem.alloc[GlyphRun](a, total)
    if runs_error != ok { ret (zero, runs_error) }
    // The width before alignment: the content without trailing whitespace, plus the tail.
    let last_content = content_end(source, cut.start, cut.end)
    var width = measure(items, cut.item_from, cut.item_to, style, source, cut.start, cut.end)
    if has_tail { width += run_width(tail) }
    var extra: f32 = 0.0
    if options.align == .Justify && options.width > width && !cut.paragraph_end {
        let spaces = count_spaces(source, cut.start, last_content)
        if spaces > 0usize {
            extra = (options.width - width) / f32(spaces)
            width = options.width
        }
    }
    var n = 0usize
    var ascent: f32 = 0.0
    var descent: f32 = 0.0
    i = cut.item_from
    while i < cut.item_to {
        if items[i].end > cut.start && items[i].start < cut.end {
            let size = style.fonts[items[i].font].size
            let (run, _, slice_error) = slice_item(a, items[i], cut.start, cut.end, source, last_content, extra, size)
            if slice_error != ok { ret (zero, slice_error) }
            runs[n] = GlyphRun { run: run, origin: geometry.Point { x: 0.0, y: 0.0 }, size: size }
            let m = metrics_of(style.fonts[items[i].font])
            if m.ascent > ascent { ascent = m.ascent }
            if m.descent > descent { descent = m.descent }
            n += 1usize
        }
        i += 1usize
    }
    if n == 0usize {
        let m = metrics_of(style.fonts[0usize])
        ascent = m.ascent
        descent = m.descent
    }
    reorder(runs[..n], cut.rtl)
    if has_tail {
        let m = metrics_of(style.fonts[0usize])
        if m.ascent > ascent { ascent = m.ascent }
        if m.descent > descent { descent = m.descent }
        if cut.rtl {
            // The visual end of a right-to-left line is its left: the tail goes first.
            var k = n
            while k > 0usize {
                runs[k] = runs[k - 1usize]
                k -= 1usize
            }
            runs[0usize] = tail
        } else {
            runs[n] = tail
        }
    }
    let natural = ascent + descent
    var height = natural
    if style.line_height > 0.0 { height = style.line_height }
    let baseline = top + ascent + (height - natural) / 2.0
    var x: f32 = 0.0
    if options.width > 0.0 {
        var align = options.align
        if align == .Justify { align = .Start }
        if cut.rtl {
            if align == .Start { align = .End } else if align == .End { align = .Start }
        }
        if align == .End { x = options.width - width } else if align == .Center { x = (options.width - width) / 2.0 }
    }
    var pen = x
    var r = 0usize
    while r < total {
        runs[r].origin = geometry.Point { x: pen, y: baseline }
        pen += run_width(runs[r])
        r += 1usize
    }
    ret (Line { runs: runs, bounds: geometry.rect(x, top, width, height), baseline: baseline, start: cut.start, end: cut.end }, ok)
}

fn layout(a: *mem.Arena, source: str, style: Style, options: Options) -> (Layout, err) {
    if style.fonts.len == 0usize || options.width < 0.0 || style.line_height < 0.0 { ret (zero, Invalid) }
    if source.len > MAX_SOURCE { ret (zero, TooLarge) }
    if !valid_utf8(source) || !valid_utf8(options.ellipsis) { ret (zero, Invalid) }
    var f = 0usize
    while f < style.fonts.len {
        if shape.validate_font(style.fonts[f].font) != ok || style.fonts[f].size <= 0.0 { ret (zero, Invalid) }
        f += 1usize
    }
    // Paragraphs at newlines; items per paragraph; then cuts. An item and a cut
    // each begin at a byte of the source, so a short text needs few of either
    // (D799): the tables are sized by the source, up to the ceiling.
    var table = source.len + 2usize
    if table > MAX_ITEMS { table = MAX_ITEMS }
    let (items, items_error) = mem.alloc[Item](a, table)
    if items_error != ok { ret (zero, items_error) }
    let (cuts, cuts_error) = mem.alloc[Cut](a, table)
    if cuts_error != ok { ret (zero, cuts_error) }
    var item_count = 0usize
    var cut_count = 0usize
    var at = 0usize
    while true {
        var end = at
        while end < source.len && source[end] != 10u8 { end += 1usize }
        var text_end = end
        if text_end > at && source[text_end - 1usize] == 13u8 { text_end -= 1usize }
        let from = item_count
        var rtl = false
        let shape_error = shape_paragraph(a, style, source, at, text_end, items, &item_count, &rtl)
        if shape_error != ok { ret (zero, shape_error) }
        let cut_error = cut_paragraph(items, from, item_count, style, source, at, text_end, options, rtl, cuts, &cut_count)
        if cut_error != ok { ret (zero, cut_error) }
        if end >= source.len { break }
        at = end + 1usize
    }
    // The line budget and the ellipsis.
    var line_count = cut_count
    var has_tail = false
    var tail: GlyphRun = zero
    if options.max_lines > 0u32 && cut_count > usize(options.max_lines) {
        line_count = usize(options.max_lines)
        if options.ellipsis.len > 0usize {
            let last = line_count - 1usize
            let (made, tail_error) = ellipsis_run(a, style, options.ellipsis, cuts[last].end, cuts[last].rtl)
            if tail_error != ok { ret (zero, tail_error) }
            tail = made
            has_tail = true
            // Drop characters until the tail fits after the content.
            if options.width > 0.0 {
                let tail_width = run_width(tail)
                let c = cuts[last]
                var end = c.end
                while end > c.start && measure(items, c.item_from, c.item_to, style, source, c.start, end) + tail_width > options.width {
                    end = cluster_start_before(items, c.item_from, c.item_to, end)
                }
                cuts[last].end = end
            }
            cuts[last].paragraph_end = true
        }
    }
    let (lines, lines_error) = mem.alloc[Line](a, line_count)
    if lines_error != ok { ret (zero, lines_error) }
    var top: f32 = 0.0
    var bounds = geometry.rect(0.0, 0.0, 0.0, 0.0)
    var i = 0usize
    while i < line_count {
        let is_last = has_tail && i + 1usize == line_count
        var line_tail: GlyphRun = zero
        if is_last { line_tail = tail }
        let (line, line_error) = build_line(a, items, style, source, cuts[i], options, top, line_tail, is_last)
        if line_error != ok { ret (zero, line_error) }
        lines[i] = line
        if i == 0usize { bounds = line.bounds } else { bounds = geometry.union_rect(bounds, line.bounds) }
        top += line.bounds.height
        i += 1usize
    }
    ret (Layout { source: source, lines: lines, bounds: bounds }, ok)
}

// The line a point lands on: by y, clamped to the first and last.
fn line_at(value: *const Layout, y: f32) -> usize {
    if value.lines.len == 0usize { ret NONE }
    var i = 0usize
    while i < value.lines.len {
        let b = value.lines[i].bounds
        if y < b.y + b.height { ret i }
        i += 1usize
    }
    ret value.lines.len - 1usize
}

// The logical end of a glyph's cluster: the next cluster start in the line, or its end.
fn cluster_end(line: *const Line, cluster: usize) -> usize {
    var best = line.end
    var r = 0usize
    while r < line.runs.len {
        var g = 0usize
        while g < line.runs[r].run.glyphs.len {
            let c = line.runs[r].run.glyphs[g].cluster
            if c > cluster && c < best { best = c }
            g += 1usize
        }
        r += 1usize
    }
    ret best
}

fn hit_test(value: *const Layout, point: geometry.Point) -> usize {
    let li = line_at(value, point.y)
    if li == NONE { ret 0usize }
    let line = &value.lines[li]
    if line.runs.len == 0usize { ret line.start }
    let rtl = line.runs[0usize].run.direction == .RightToLeft && line.runs[line.runs.len - 1usize].run.direction == .RightToLeft
    if point.x < line.runs[0usize].origin.x {
        if line.runs[0usize].run.direction == .RightToLeft { ret cluster_end_of_run(line, 0usize) }
        if line.runs[0usize].run.glyphs.len > 0usize { ret line.runs[0usize].run.glyphs[0usize].cluster }
        ret line.start
    }
    var r = 0usize
    while r < line.runs.len {
        let run = &line.runs[r]
        var x = run.origin.x
        var g = 0usize
        while g < run.run.glyphs.len {
            let adv = run.run.glyphs[g].advance_x * run.size
            let c = run.run.glyphs[g].cluster
            if point.x < x + adv {
                let leading = point.x - x < adv / 2.0
                if run.run.direction == .RightToLeft {
                    if leading { ret cluster_end(line, c) }
                    ret c
                }
                if leading { ret c }
                ret cluster_end(line, c)
            }
            x += adv
            g += 1usize
        }
        r += 1usize
    }
    // Past the last run.
    let last = &line.runs[line.runs.len - 1usize]
    if last.run.direction == .RightToLeft && last.run.glyphs.len > 0usize { ret last.run.glyphs[last.run.glyphs.len - 1usize].cluster }
    if rtl { ret line.start }
    ret line.end
}

fn cluster_end_of_run(line: *const Line, r: usize) -> usize {
    let run = &line.runs[r]
    if run.run.glyphs.len == 0usize { ret line.end }
    // The visually first glyph of a right-to-left run is its logical last.
    ret cluster_end(line, run.run.glyphs[0usize].cluster)
}

// The caret x on a line for a byte offset within it.
fn caret_x(line: *const Line, offset: usize) -> f32 {
    var r = 0usize
    var end_x: f32 = 0.0
    var start_x: f32 = 0.0
    if line.runs.len > 0usize {
        start_x = line.runs[0usize].origin.x
        let last = line.runs[line.runs.len - 1usize]
        end_x = last.origin.x + run_width(last)
    }
    while r < line.runs.len {
        let run = &line.runs[r]
        var x = run.origin.x
        var g = 0usize
        while g < run.run.glyphs.len {
            let adv = run.run.glyphs[g].advance_x * run.size
            let c = run.run.glyphs[g].cluster
            if c == offset {
                if run.run.direction == .RightToLeft { ret x + adv }
                ret x
            }
            // Inside a cluster (a ligature or a continuation byte): its trailing edge.
            if c < offset && cluster_end(line, c) > offset {
                if run.run.direction == .RightToLeft { ret x }
                ret x + adv
            }
            x += adv
            g += 1usize
        }
        r += 1usize
    }
    // The line's end: after the logically last glyph.
    let paragraph_rtl = line.runs.len > 0usize && line.runs[line.runs.len - 1usize].run.direction == .RightToLeft && line.runs[0usize].run.direction == .RightToLeft
    if paragraph_rtl { ret start_x }
    ret end_x
}

fn line_of_offset(value: *const Layout, byte_offset: usize) -> usize {
    if value.lines.len == 0usize { ret NONE }
    var i = 0usize
    while i < value.lines.len {
        let line = &value.lines[i]
        if byte_offset < line.end { ret i }
        if byte_offset == line.end && i + 1usize < value.lines.len && value.lines[i + 1usize].start > byte_offset { ret i }
        i += 1usize
    }
    ret value.lines.len - 1usize
}

fn caret(value: *const Layout, byte_offset: usize) -> geometry.Rect {
    var offset = byte_offset
    if offset > value.source.len { offset = value.source.len }
    while offset > 0usize && offset < value.source.len && (u32(value.source[offset]) & 192u32) == 128u32 { offset -= 1usize }
    let li = line_of_offset(value, offset)
    if li == NONE { ret geometry.rect(0.0, 0.0, 0.0, 0.0) }
    let line = &value.lines[li]
    ret geometry.rect(caret_x(line, offset), line.bounds.y, 0.0, line.bounds.height)
}

fn selection(a: *mem.Arena, value: *const Layout, start: usize, end: usize) -> ([]geometry.Rect, err) {
    if start > end || end > value.source.len { ret (zero, Invalid) }
    var count = 0usize
    var i = 0usize
    while i < value.lines.len {
        let line = &value.lines[i]
        if line.start < end && line.end > start && start < end { count += 1usize }
        i += 1usize
    }
    if count == 0usize { ret (zero, ok) }
    let (rects, rects_error) = mem.alloc[geometry.Rect](a, count)
    if rects_error != ok { ret (zero, rects_error) }
    var n = 0usize
    i = 0usize
    while i < value.lines.len {
        let line = &value.lines[i]
        if line.start < end && line.end > start && start < end {
            var from = start
            if from < line.start { from = line.start }
            var to = end
            if to > line.end { to = line.end }
            let x1 = caret_x(line, from)
            let x2 = caret_x(line, to)
            var left = x1
            var right = x2
            if right < left {
                left = x2
                right = x1
            }
            rects[n] = geometry.rect(left, line.bounds.y, right - left, line.bounds.height)
            n += 1usize
        }
        i += 1usize
    }
    ret (rects, ok)
}
