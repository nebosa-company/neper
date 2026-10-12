// PDF document generation (L145): a page model in points over the built-in Helvetica and
// Helvetica-Bold (WinAnsi, nothing embedded), so a report is a handful of calls and the
// file is a plain PDF 1.4 that any viewer opens. Coordinates are points from the top left
// of the page, y growing down; a text's `y` is its baseline.
//
//   var d = document(a, max_pages, capacity, 595.0, 842.0, "Title")
//   begin_page(&d); put_text(...); put_paragraph(...); put_table(...); end_page(&d)
//   let (bytes, e) = finish(a, &d)
//
// What is drawn: single-line text, word-wrapped paragraphs (greedy, at spaces and at `\n`;
// a word wider than the line stands alone), tables (column widths, wrapped cells, a ruled
// grid, a shaded bold header row; the row height follows the tallest cell), rectangles,
// lines, polylines, polygons and circles in RGB. Text measures with the Adobe Helvetica
// metrics, so a line that fits here fits in the viewer.
//
// Not here: embedded fonts (a character outside WinAnsi is `Unsupported`; no CJK, no
// emoji), images, links, outlines, compression of the content (streams are plain text,
// which is also what the byte-level fixtures compare), page breaking (the caller decides
// where a page ends; `put_table` reports where it stopped), tagged or accessible PDF, and
// e.text.layout shaping -- which needs a font file this writer does not carry.
//
// Memory: each page's content is built in a private region of `capacity` bytes taken from
// the arena at `document`, so the caller may allocate from the arena between drawing
// calls; `finish` writes the file into the arena as one allocation.
use e.mem
use e.str

error Invalid
error Unsupported
error TooLarge
error NoPage
error PageOpen

type Font = enum u8 { Regular, Bold }
type Color = struct { red: u8, green: u8, blue: u8 }
type Document = struct { store: mem.Arena, pages: []str, count: usize, open: bool, content: str.Builder, width: f64, height: f64, title: str }

fn black() -> Color {
    ret Color { red: 0u8, green: 0u8, blue: 0u8 }
}

fn rgb(red: u8, green: u8, blue: u8) -> Color {
    ret Color { red: red, green: green, blue: blue }
}

// The WinAnsi byte for one code point, or 0 when the encoding has none (the typographic
// marks Windows-1252 keeps in 128-159).
fn winansi(code: u32) -> u8 {
    if (code >= 32u32 && code <= 126u32) || (code >= 160u32 && code <= 255u32) { ret u8(code) }
    let codes = [27]u32{ 8364u32, 8218u32, 402u32, 8222u32, 8230u32, 8224u32, 8225u32, 710u32, 8240u32, 352u32, 8249u32, 338u32, 381u32, 8216u32, 8217u32, 8220u32, 8221u32, 8226u32, 8211u32, 8212u32, 732u32, 8482u32, 353u32, 8250u32, 339u32, 382u32, 376u32 }
    let bytes = [27]u8{ 128u8, 130u8, 131u8, 132u8, 133u8, 134u8, 135u8, 136u8, 137u8, 138u8, 139u8, 140u8, 142u8, 145u8, 146u8, 147u8, 148u8, 149u8, 150u8, 151u8, 152u8, 153u8, 154u8, 155u8, 156u8, 158u8, 159u8 }
    var i = 0usize
    while i < codes.len {
        if codes[i] == code { ret bytes[i] }
        i += 1usize
    }
    ret 0u8
}

// The code point of the UTF-8 sequence at `at` and its length; length 0 when malformed.
fn decode_at(s: str, at: usize) -> (u32, usize) {
    let b = u32(s[at])
    if b < 128u32 { ret (b, 1usize) }
    var need = 0usize
    var code = 0u32
    if b >= 194u32 && b < 224u32 {
        need = 2usize
        code = b & 31u32
    } else if b >= 224u32 && b < 240u32 {
        need = 3usize
        code = b & 15u32
    } else if b >= 240u32 && b < 245u32 {
        need = 4usize
        code = b & 7u32
    } else {
        ret (0u32, 0usize)
    }
    if at + need > s.len { ret (0u32, 0usize) }
    var k = 1usize
    while k < need {
        let c = u32(s[at + k])
        if (c & 192u32) != 128u32 { ret (0u32, 0usize) }
        code = (code << 6u32) | (c & 63u32)
        k += 1usize
    }
    ret (code, need)
}

// Advance widths in thousandths of the font size for WinAnsi bytes 32..255, generated from
// the Adobe Helvetica and Helvetica-Bold metrics (scripts/gen_pdf_write_test.py --metrics).
fn width_units(font: Font, byte: u8) -> u32 {
    let regular = [224]u16{
        278u16, 278u16, 355u16, 556u16, 556u16, 889u16, 667u16, 191u16, 333u16, 333u16, 389u16, 584u16, 278u16, 333u16, 278u16, 278u16,
        556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 278u16, 278u16, 584u16, 584u16, 584u16, 556u16,
        1015u16, 667u16, 667u16, 722u16, 722u16, 667u16, 611u16, 778u16, 722u16, 278u16, 500u16, 667u16, 556u16, 833u16, 722u16, 778u16,
        667u16, 778u16, 722u16, 667u16, 611u16, 722u16, 667u16, 944u16, 667u16, 667u16, 611u16, 278u16, 278u16, 278u16, 469u16, 556u16,
        333u16, 556u16, 556u16, 500u16, 556u16, 556u16, 278u16, 556u16, 556u16, 222u16, 222u16, 500u16, 222u16, 833u16, 556u16, 556u16,
        556u16, 556u16, 333u16, 500u16, 278u16, 556u16, 500u16, 722u16, 500u16, 500u16, 500u16, 334u16, 260u16, 334u16, 584u16, 761u16,
        556u16, 0u16, 222u16, 556u16, 333u16, 1000u16, 556u16, 556u16, 333u16, 1000u16, 667u16, 333u16, 1000u16, 0u16, 611u16, 0u16,
        0u16, 222u16, 222u16, 333u16, 333u16, 350u16, 556u16, 1000u16, 333u16, 1000u16, 500u16, 333u16, 944u16, 0u16, 500u16, 667u16,
        278u16, 333u16, 556u16, 556u16, 556u16, 556u16, 260u16, 556u16, 333u16, 737u16, 370u16, 556u16, 584u16, 333u16, 737u16, 333u16,
        400u16, 584u16, 333u16, 333u16, 333u16, 556u16, 537u16, 278u16, 333u16, 333u16, 365u16, 556u16, 834u16, 834u16, 834u16, 611u16,
        667u16, 667u16, 667u16, 667u16, 667u16, 667u16, 1000u16, 722u16, 667u16, 667u16, 667u16, 667u16, 278u16, 278u16, 278u16, 278u16,
        722u16, 722u16, 778u16, 778u16, 778u16, 778u16, 778u16, 584u16, 778u16, 722u16, 722u16, 722u16, 722u16, 667u16, 667u16, 611u16,
        556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 889u16, 500u16, 556u16, 556u16, 556u16, 556u16, 278u16, 278u16, 278u16, 278u16,
        556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 584u16, 611u16, 556u16, 556u16, 556u16, 556u16, 500u16, 556u16, 500u16,
    }
    let bold = [224]u16{
        278u16, 333u16, 474u16, 556u16, 556u16, 889u16, 722u16, 238u16, 333u16, 333u16, 389u16, 584u16, 278u16, 333u16, 278u16, 278u16,
        556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 333u16, 333u16, 584u16, 584u16, 584u16, 611u16,
        975u16, 722u16, 722u16, 722u16, 722u16, 667u16, 611u16, 778u16, 722u16, 278u16, 556u16, 722u16, 611u16, 833u16, 722u16, 778u16,
        667u16, 778u16, 722u16, 667u16, 611u16, 722u16, 667u16, 944u16, 667u16, 667u16, 611u16, 333u16, 278u16, 333u16, 584u16, 556u16,
        333u16, 556u16, 611u16, 556u16, 611u16, 556u16, 333u16, 611u16, 611u16, 278u16, 278u16, 556u16, 278u16, 889u16, 611u16, 611u16,
        611u16, 611u16, 389u16, 556u16, 333u16, 611u16, 556u16, 778u16, 556u16, 556u16, 500u16, 389u16, 280u16, 389u16, 584u16, 761u16,
        556u16, 0u16, 278u16, 556u16, 500u16, 1000u16, 556u16, 556u16, 333u16, 1000u16, 667u16, 333u16, 1000u16, 0u16, 611u16, 0u16,
        0u16, 278u16, 278u16, 500u16, 500u16, 350u16, 556u16, 1000u16, 333u16, 1000u16, 556u16, 333u16, 944u16, 0u16, 500u16, 667u16,
        278u16, 333u16, 556u16, 556u16, 556u16, 556u16, 280u16, 556u16, 333u16, 737u16, 370u16, 556u16, 584u16, 333u16, 737u16, 333u16,
        400u16, 584u16, 333u16, 333u16, 333u16, 611u16, 556u16, 278u16, 333u16, 333u16, 365u16, 556u16, 834u16, 834u16, 834u16, 611u16,
        722u16, 722u16, 722u16, 722u16, 722u16, 722u16, 1000u16, 722u16, 667u16, 667u16, 667u16, 667u16, 278u16, 278u16, 278u16, 278u16,
        722u16, 722u16, 778u16, 778u16, 778u16, 778u16, 778u16, 584u16, 778u16, 722u16, 722u16, 722u16, 722u16, 667u16, 667u16, 611u16,
        556u16, 556u16, 556u16, 556u16, 556u16, 556u16, 889u16, 556u16, 556u16, 556u16, 556u16, 556u16, 278u16, 278u16, 278u16, 278u16,
        611u16, 611u16, 611u16, 611u16, 611u16, 611u16, 611u16, 584u16, 611u16, 611u16, 611u16, 611u16, 611u16, 556u16, 611u16, 556u16,
    }
    if byte < 32u8 { ret 0u32 }
    if font == .Bold { ret u32(bold[usize(byte) - 32usize]) }
    ret u32(regular[usize(byte) - 32usize])
}

// Whether every character of `s` is in WinAnsi and none is a control character other than
// the newline `put_paragraph` and `put_table` break on.
fn supported(s: str) -> bool {
    var at = 0usize
    while at < s.len {
        let (code, length) = decode_at(s, at)
        if length == 0usize { ret false }
        if code == 10u32 {
            at += 1usize
            continue
        }
        if winansi(code) == 0u8 { ret false }
        at += length
    }
    ret true
}

// Width in thousandths of the font size of s[from..to], which must be `supported`.
fn span_units(s: str, from: usize, to: usize, font: Font) -> u64 {
    var total = 0u64
    var at = from
    while at < to {
        let (code, length) = decode_at(s, at)
        total += u64(width_units(font, winansi(code)))
        at += length
    }
    ret total
}

fn text_width(s: str, size: f64, font: Font) -> (f64, err) {
    if !(size > 0.0 && size < 1000.0) { ret (0.0, Invalid) }
    if !supported(s) { ret (0.0, Unsupported) }
    ret (f64(span_units(s, 0usize, s.len, font)) * size / 1000.0, ok)
}

// ---- output primitives -------------------------------------------------------------------

// A PDF real: fixed point with `decimals` places, trailing zeros trimmed, no exponent.
fn push_real(b: *str.Builder, v: f64, decimals: u32) -> err {
    var scale = 1.0f64
    var d = 0u32
    while d < decimals {
        scale *= 10.0
        d += 1u32
    }
    var m = v
    if v < 0.0 { m = 0.0 - v }
    let n = u64(m * scale + 0.5)
    let divisor = u64(scale)
    var whole = n / divisor
    var frac = n % divisor
    if v < 0.0 && n != 0u64 { try str.push(b, "-") }
    try str.push_u64(b, whole)
    if frac > 0u64 {
        var digits = decimals
        while frac % 10u64 == 0u64 {
            frac /= 10u64
            digits -= 1u32
        }
        var buffer: [12]u8 = zero
        var i = usize(digits)
        while i > 0usize {
            buffer[i - 1usize] = 48u8 + u8(frac % 10u64)
            frac /= 10u64
            i -= 1usize
        }
        try str.push(b, ".")
        try str.push(b, buffer[0usize..usize(digits)])
    }
    ret ok
}

fn real(b: *str.Builder, v: f64) -> err {
    try push_real(b, v, 2u32)
    ret str.push(b, " ")
}

fn finite(v: f64) -> bool {
    ret v == v && v < 1.0e12 && v > -1.0e12
}

fn color_op(b: *str.Builder, c: Color, stroke: bool) -> err {
    try push_real(b, f64(c.red) / 255.0, 4u32)
    try str.push(b, " ")
    try push_real(b, f64(c.green) / 255.0, 4u32)
    try str.push(b, " ")
    try push_real(b, f64(c.blue) / 255.0, 4u32)
    if stroke { ret str.push(b, " RG ") }
    ret str.push(b, " rg ")
}

// A literal string for s[from..to]: WinAnsi bytes, `( ) \` escaped, bytes past 126 octal.
fn literal(b: *str.Builder, s: str, from: usize, to: usize) -> err {
    try str.push(b, "(")
    var at = from
    while at < to {
        let (code, length) = decode_at(s, at)
        let byte = winansi(code)
        if byte == 40u8 || byte == 41u8 || byte == 92u8 {
            let pair = [2]u8{ 92u8, byte }
            try str.push(b, pair[0usize..2usize])
        } else if byte > 126u8 {
            let octal = [4]u8{ 92u8, 48u8 + byte / 64u8, 48u8 + byte / 8u8 % 8u8, 48u8 + byte % 8u8 }
            try str.push(b, octal[0usize..4usize])
        } else {
            let one = [1]u8{ byte }
            try str.push(b, one[0usize..1usize])
        }
        at += length
    }
    ret str.push(b, ")")
}

fn font_name(font: Font) -> str {
    if font == .Bold { ret "/F2 " }
    ret "/F1 "
}

// ---- document ----------------------------------------------------------------------------

// A document of at most `max_pages` pages whose page content will fit `capacity` bytes in all.
fn document(a: *mem.Arena, max_pages: usize, capacity: usize, width: f64, height: f64, title: str) -> (Document, err) {
    if max_pages == 0usize || max_pages > 4096usize || capacity == 0usize { ret (zero, Invalid) }
    if !(width >= 1.0 && width <= 14400.0 && height >= 1.0 && height <= 14400.0) { ret (zero, Invalid) }
    if title.len > 256usize || !supported(title) { ret (zero, Invalid) }
    let (region, region_error) = mem.alloc[u8](a, capacity)
    if region_error != ok { ret (zero, region_error) }
    let (pages, pages_error) = mem.alloc[str](a, max_pages)
    if pages_error != ok { ret (zero, pages_error) }
    var d: Document = zero
    d.store = mem.arena_from(region)
    d.pages = pages
    d.count = 0usize
    d.open = false
    d.width = width
    d.height = height
    d.title = title
    ret (d, ok)
}

fn begin_page(d: *Document) -> err {
    if d.open { ret PageOpen }
    if d.count == d.pages.len { ret TooLarge }
    let (b, b_error) = str.builder(&d.store, 0usize)
    if b_error != ok { ret TooLarge }
    d.content = b
    d.open = true
    ret ok
}

fn end_page(d: *Document) -> err {
    if !d.open { ret NoPage }
    d.pages[d.count] = str.done(&d.content)
    d.count += 1usize
    d.open = false
    ret ok
}

// One drawing call's emission: a failed push means the page region is full.
fn full(e: err) -> err {
    if e == ok { ret ok }
    ret TooLarge
}

// A line of text with its baseline at `y`, starting at `x`.
fn put_text(d: *Document, x: f64, y: f64, size: f64, font: Font, ink: Color, s: str) -> err {
    if !d.open { ret NoPage }
    if !finite(x) || !finite(y) || !(size > 0.0 && size < 1000.0) { ret Invalid }
    if !supported(s) { ret Unsupported }
    var i = 0usize
    while i < s.len {
        if s[i] == 10u8 { ret Invalid }
        i += 1usize
    }
    let b = &d.content
    try full(str.push(b, "q "))
    try full(color_op(b, ink, false))
    try full(str.push(b, "BT "))
    try full(str.push(b, font_name(font)))
    try full(push_real(b, size, 2u32))
    try full(str.push(b, " Tf "))
    try full(real(b, x))
    try full(real(b, d.height - y))
    try full(str.push(b, "Td "))
    try full(literal(b, s, 0usize, s.len))
    ret full(str.push(b, " Tj ET Q\n"))
}

// The end of the next line of `s` starting at `from`, where the following line starts, and
// the line's width in thousandths. A line breaks at a space once a further word would pass
// `limit`, or at a newline; the spaces at a soft break are dropped.
fn next_line(s: str, from: usize, limit: f64, size: f64, font: Font) -> (usize, usize, u64) {
    var i = from
    var line_end = from
    var units = 0u64
    var empty = true
    while true {
        if i >= s.len { ret (line_end, s.len, units) }
        if s[i] == 10u8 { ret (line_end, i + 1usize, units) }
        var k = i
        while k < s.len && s[k] == 32u8 { k += 1usize }
        var j = k
        while j < s.len && s[j] != 32u8 && s[j] != 10u8 { j += 1usize }
        let token = span_units(s, i, j, font)
        if !empty && f64(units + token) * size / 1000.0 > limit {
            // Break here; the next line starts at the word, the spaces are dropped.
            ret (line_end, k, units)
        }
        units += token
        line_end = j
        empty = false
        i = j
    }
    ret (line_end, s.len, units)
}

// How many lines `s` takes at `limit` points wide.
fn count_lines(s: str, limit: f64, size: f64, font: Font) -> usize {
    var lines = 0usize
    var at = 0usize
    while true {
        let (end, next, units) = next_line(s, at, limit, size, font)
        lines += 1usize
        if next >= s.len { break }
        at = next
    }
    ret lines
}

// Word-wrapped text in a column `width` wide, first baseline at `y`, lines `leading` apart.
// Returns the baseline the next line would take and the number of lines drawn.
fn put_paragraph(d: *Document, x: f64, y: f64, width: f64, size: f64, leading: f64, font: Font, ink: Color, s: str) -> (f64, usize, err) {
    if !d.open { ret (0.0, 0usize, NoPage) }
    if !finite(x) || !finite(y) || !(size > 0.0 && size < 1000.0) || !(width > 0.0 && width < 100000.0) || !(leading > 0.0 && leading < 10000.0) { ret (0.0, 0usize, Invalid) }
    if !supported(s) { ret (0.0, 0usize, Unsupported) }
    let b = &d.content
    var lines = 0usize
    var at = 0usize
    var baseline = y
    while true {
        let (end, next, units) = next_line(s, at, width, size, font)
        let e1 = full(str.push(b, "q "))
        if e1 != ok { ret (0.0, 0usize, e1) }
        let e2 = full(color_op(b, ink, false))
        if e2 != ok { ret (0.0, 0usize, e2) }
        let e3 = full(str.push(b, "BT "))
        if e3 != ok { ret (0.0, 0usize, e3) }
        let e4 = full(str.push(b, font_name(font)))
        if e4 != ok { ret (0.0, 0usize, e4) }
        let e5 = full(push_real(b, size, 2u32))
        if e5 != ok { ret (0.0, 0usize, e5) }
        let e6 = full(str.push(b, " Tf "))
        if e6 != ok { ret (0.0, 0usize, e6) }
        let e7 = full(real(b, x))
        if e7 != ok { ret (0.0, 0usize, e7) }
        let e8 = full(real(b, d.height - baseline))
        if e8 != ok { ret (0.0, 0usize, e8) }
        let e9 = full(str.push(b, "Td "))
        if e9 != ok { ret (0.0, 0usize, e9) }
        let e10 = full(literal(b, s, at, end))
        if e10 != ok { ret (0.0, 0usize, e10) }
        let e11 = full(str.push(b, " Tj ET Q\n"))
        if e11 != ok { ret (0.0, 0usize, e11) }
        lines += 1usize
        baseline += leading
        if next >= s.len { break }
        at = next
    }
    ret (baseline, lines, ok)
}

fn fill_rect(d: *Document, x: f64, y: f64, w: f64, h: f64, ink: Color) -> err {
    if !d.open { ret NoPage }
    if !finite(x) || !finite(y) || !finite(w) || !finite(h) || w <= 0.0 || h <= 0.0 { ret Invalid }
    let b = &d.content
    try full(str.push(b, "q "))
    try full(color_op(b, ink, false))
    try full(real(b, x))
    try full(real(b, d.height - y - h))
    try full(real(b, w))
    try full(real(b, h))
    ret full(str.push(b, "re f Q\n"))
}

fn stroke_rect(d: *Document, x: f64, y: f64, w: f64, h: f64, line_width: f64, ink: Color) -> err {
    if !d.open { ret NoPage }
    if !finite(x) || !finite(y) || !finite(w) || !finite(h) || w <= 0.0 || h <= 0.0 || !(line_width > 0.0 && line_width < 1000.0) { ret Invalid }
    let b = &d.content
    try full(str.push(b, "q "))
    try full(color_op(b, ink, true))
    try full(real(b, line_width))
    try full(str.push(b, "w "))
    try full(real(b, x))
    try full(real(b, d.height - y - h))
    try full(real(b, w))
    try full(real(b, h))
    ret full(str.push(b, "re S Q\n"))
}

fn draw_line(d: *Document, x1: f64, y1: f64, x2: f64, y2: f64, line_width: f64, ink: Color) -> err {
    if !d.open { ret NoPage }
    if !finite(x1) || !finite(y1) || !finite(x2) || !finite(y2) || !(line_width > 0.0 && line_width < 1000.0) { ret Invalid }
    let b = &d.content
    try full(str.push(b, "q "))
    try full(color_op(b, ink, true))
    try full(real(b, line_width))
    try full(str.push(b, "w "))
    try full(real(b, x1))
    try full(real(b, d.height - y1))
    try full(str.push(b, "m "))
    try full(real(b, x2))
    try full(real(b, d.height - y2))
    ret full(str.push(b, "l S Q\n"))
}

// A path through the points: filled and closed, or stroked open.
fn draw_path(d: *Document, xs: []const f64, ys: []const f64, filled: bool, line_width: f64, ink: Color) -> err {
    if !d.open { ret NoPage }
    if xs.len != ys.len || xs.len < 2usize || (filled && xs.len < 3usize) { ret Invalid }
    if !(line_width > 0.0 && line_width < 1000.0) { ret Invalid }
    let b = &d.content
    try full(str.push(b, "q "))
    try full(color_op(b, ink, !filled))
    if !filled {
        try full(real(b, line_width))
        try full(str.push(b, "w "))
    }
    var i = 0usize
    while i < xs.len {
        if !finite(xs[i]) || !finite(ys[i]) { ret Invalid }
        try full(real(b, xs[i]))
        try full(real(b, d.height - ys[i]))
        if i == 0usize {
            try full(str.push(b, "m "))
        } else {
            try full(str.push(b, "l "))
        }
        i += 1usize
    }
    if filled { ret full(str.push(b, "h f Q\n")) }
    ret full(str.push(b, "S Q\n"))
}

// A filled circle as four cubic Beziers (control distance 0.5523 r).
fn fill_circle(d: *Document, cx: f64, cy: f64, r: f64, ink: Color) -> err {
    if !d.open { ret NoPage }
    if !finite(cx) || !finite(cy) || !(r > 0.0 && r < 100000.0) { ret Invalid }
    let k = r * 0.5523
    let xs = [12]f64{ cx + r, cx + r, cx + k, cx, cx - k, cx - r, cx - r, cx - r, cx - k, cx, cx + k, cx + r }
    let ys = [12]f64{ cy, cy - k, cy - r, cy - r, cy - r, cy - k, cy, cy + k, cy + r, cy + r, cy + r, cy + k }
    let b = &d.content
    try full(str.push(b, "q "))
    try full(color_op(b, ink, false))
    try full(real(b, xs[0usize]))
    try full(real(b, d.height - ys[0usize]))
    try full(str.push(b, "m "))
    var i = 1usize
    while i < 12usize {
        try full(real(b, xs[i]))
        try full(real(b, d.height - ys[i]))
        if i % 3usize == 0usize { try full(str.push(b, "c ")) }
        i += 1usize
    }
    // The last segment closes on the start point.
    try full(real(b, xs[0usize]))
    try full(real(b, d.height - ys[0usize]))
    ret full(str.push(b, "c f Q\n"))
}

// A table: `widths` are the column widths, each row a slice of cell texts (fewer than
// `widths.len` leaves the rest empty), the first row a shaded bold header when `header` is
// set. Cell text is wrapped inside `pad` points of its cell; the row height is the tallest
// cell's lines at `leading` plus 2 * pad. Returns the y of the table's bottom edge.
fn put_table(d: *Document, x: f64, y: f64, widths: []const f64, rows: []const []const str, size: f64, leading: f64, pad: f64, header: bool, ink: Color, rule: Color) -> (f64, err) {
    if !d.open { ret (0.0, NoPage) }
    if widths.len == 0usize || !finite(x) || !finite(y) || !(size > 0.0 && size < 1000.0) || !(leading > 0.0 && leading < 10000.0) || !(pad >= 0.0 && pad < 1000.0) { ret (0.0, Invalid) }
    var c = 0usize
    while c < widths.len {
        if !(widths[c] > 2.0 * pad && widths[c] < 100000.0) { ret (0.0, Invalid) }
        c += 1usize
    }
    var top = y
    var r = 0usize
    while r < rows.len {
        let row = rows[r]
        if row.len > widths.len { ret (0.0, Invalid) }
        let head = header && r == 0usize
        var font: Font = .Regular
        if head { font = .Bold }
        var tallest = 1usize
        c = 0usize
        while c < row.len {
            if !supported(row[c]) { ret (0.0, Unsupported) }
            let n = count_lines(row[c], widths[c] - 2.0 * pad, size, font)
            if n > tallest { tallest = n }
            c += 1usize
        }
        let height = f64(tallest) * leading + 2.0 * pad
        var left = x
        c = 0usize
        while c < widths.len {
            if head {
                let shade_error = fill_rect(d, left, top, widths[c], height, rgb(238u8, 238u8, 238u8))
                if shade_error != ok { ret (0.0, shade_error) }
            }
            let box_error = stroke_rect(d, left, top, widths[c], height, 0.5, rule)
            if box_error != ok { ret (0.0, box_error) }
            if c < row.len && row[c].len > 0usize {
                let (next_baseline, drawn, text_error) = put_paragraph(d, left + pad, top + pad + size, widths[c] - 2.0 * pad, size, leading, font, ink, row[c])
                if text_error != ok { ret (0.0, text_error) }
            }
            left += widths[c]
            c += 1usize
        }
        top += height
        r += 1usize
    }
    ret (top, ok)
}

// ---- the file ----------------------------------------------------------------------------

fn push_padded(b: *str.Builder, v: usize, digits: usize) -> err {
    var buffer: [10]u8 = zero
    var n = v
    var i = digits
    while i > 0usize {
        buffer[i - 1usize] = 48u8 + u8(n % 10usize)
        n /= 10usize
        i -= 1usize
    }
    ret str.push(b, buffer[0usize..digits])
}

fn push_utf16_hex(b: *str.Builder, s: str) -> err {
    let hex = "0123456789ABCDEF"
    try str.push(b, "<FEFF")
    var at = 0usize
    while at < s.len {
        let (code, length) = decode_at(s, at)
        var units = [2]u32{ code, 0u32 }
        var count = 1usize
        if code > 65535u32 {
            units[0usize] = 55296u32 + ((code - 65536u32) >> 10u32)
            units[1usize] = 56320u32 + ((code - 65536u32) & 1023u32)
            count = 2usize
        }
        var u = 0usize
        while u < count {
            let digits = [4]u8{ hex[usize((units[u] >> 12u32) & 15u32)], hex[usize((units[u] >> 8u32) & 15u32)], hex[usize((units[u] >> 4u32) & 15u32)], hex[usize(units[u] & 15u32)] }
            try str.push(b, digits[0usize..4usize])
            u += 1usize
        }
        at += length
    }
    ret str.push(b, ">")
}

// The file: catalog, page tree, the two fonts, the information dictionary, then a page and
// its content stream per page, the cross-reference table and the trailer.
fn finish(a: *mem.Arena, d: *Document) -> (str, err) {
    if d.open { ret (zero, PageOpen) }
    if d.count == 0usize { ret (zero, NoPage) }
    let objects = 5usize + 2usize * d.count
    let (offsets, offsets_error) = mem.alloc[usize](a, objects + 1usize)
    if offsets_error != ok { ret (zero, offsets_error) }
    var (b, b_error) = str.builder(a, 0usize)
    if b_error != ok { ret (zero, b_error) }
    try str.push(&b, "%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets[1usize] = b.len
    try str.push(&b, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
    offsets[2usize] = b.len
    try str.push(&b, "2 0 obj\n<< /Type /Pages /Count ")
    try str.push_usize(&b, d.count)
    try str.push(&b, " /Kids [")
    var p = 0usize
    while p < d.count {
        if p > 0usize { try str.push(&b, " ") }
        try str.push_usize(&b, 6usize + 2usize * p)
        try str.push(&b, " 0 R")
        p += 1usize
    }
    try str.push(&b, "] >>\nendobj\n")
    offsets[3usize] = b.len
    try str.push(&b, "3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\nendobj\n")
    offsets[4usize] = b.len
    try str.push(&b, "4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>\nendobj\n")
    offsets[5usize] = b.len
    try str.push(&b, "5 0 obj\n<< ")
    if d.title.len > 0usize {
        try str.push(&b, "/Title ")
        try push_utf16_hex(&b, d.title)
        try str.push(&b, " ")
    }
    try str.push(&b, "/Producer (Neper e.fmt.pdf.write) >>\nendobj\n")
    p = 0usize
    while p < d.count {
        let page_number = 6usize + 2usize * p
        offsets[page_number] = b.len
        try str.push_usize(&b, page_number)
        try str.push(&b, " 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ")
        try real(&b, d.width)
        try real(&b, d.height)
        try str.push(&b, "] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ")
        try str.push_usize(&b, page_number + 1usize)
        try str.push(&b, " 0 R >>\nendobj\n")
        offsets[page_number + 1usize] = b.len
        try str.push_usize(&b, page_number + 1usize)
        try str.push(&b, " 0 obj\n<< /Length ")
        try str.push_usize(&b, d.pages[p].len)
        try str.push(&b, " >>\nstream\n")
        try str.push(&b, d.pages[p])
        try str.push(&b, "endstream\nendobj\n")
        p += 1usize
    }
    let xref = b.len
    try str.push(&b, "xref\n0 ")
    try str.push_usize(&b, objects + 1usize)
    try str.push(&b, "\n0000000000 65535 f \n")
    var n = 1usize
    while n <= objects {
        try push_padded(&b, offsets[n], 10usize)
        try str.push(&b, " 00000 n \n")
        n += 1usize
    }
    try str.push(&b, "trailer\n<< /Size ")
    try str.push_usize(&b, objects + 1usize)
    try str.push(&b, " /Root 1 0 R /Info 5 0 R >>\nstartxref\n")
    try str.push_usize(&b, xref)
    try str.push(&b, "\n%%EOF\n")
    let out = str.done(&b)
    ret (out, ok)
}
