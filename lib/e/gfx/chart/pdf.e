// PDF adapter for the renderer-neutral chart layouts: one PDF 1.4 page of
// vector marks, in points (one layout pixel is one point, so a 360x240 chart
// is a 5x3.33 inch page). Text uses the built-in Helvetica in WinAnsi
// encoding, so nothing is embedded; text outside WinAnsi is refused. The
// content stream goes into caller-owned storage and `finish` writes the whole
// file, cross-reference table included, to any writer.
// ponytail: an uncompressed content stream and Helvetica only; FlateDecode
// and embedded TrueType text belong here when a report needs them.
use e.gfx.chart
use e.gfx.geometry
use e.gfx.paint
use e.io
use e.math
use e.text.layout as text_layout

error Invalid
error TooLarge

// Opacity needs a named graphics state per distinct alpha; 16 is plenty for
// a chart and keeps the page dictionary fixed-size.
type Document = struct { storage: []u8, len: usize, width: f32, height: f32, title: str, alphas: [16]f32, alpha_count: usize }

fn begin(storage: []u8, width: f32, height: f32, title: str) -> (Document, err) {
    if !chart.finite(width) || !chart.finite(height) || width <= 0.0 || height <= 0.0 || width > 14400.0 || height > 14400.0 { ret (zero, Invalid) }
    if title.len > 256usize || !text_layout.valid_utf8(title) { ret (zero, Invalid) }
    ret (Document { storage: storage, len: 0usize, width: width, height: height, title: title, alphas: zero, alpha_count: 0usize }, ok)
}

fn put(doc: *Document, text: []const u8) -> err {
    if text.len > doc.storage.len - doc.len { ret TooLarge }
    var i = 0usize
    while i < text.len {
        doc.storage[doc.len + i] = text[i]
        i += 1usize
    }
    doc.len += text.len
    ret ok
}

// A PDF real: fixed point, no exponent, trailing zeros trimmed.
fn real_text(value: f32, decimals: u32, out: []u8) -> ([]u8, err) {
    if !chart.finite(value) { ret (zero, Invalid) }
    var scale = 1.0f64
    var d = 0u32
    while d < decimals {
        scale *= 10.0f64
        d += 1u32
    }
    let scaled = math.round[f64](f64(value) * scale)
    if scaled > 1000000000000.0f64 || scaled < -1000000000000.0f64 { ret (zero, Invalid) }
    var n = i64(scaled)
    var at = out.len
    let negative = n < 0i64
    if negative { n = 0i64 - n }
    let divisor = i64(scale)
    var fraction = n % divisor
    var whole = n / divisor
    if fraction > 0i64 {
        var digits = decimals
        while fraction % 10i64 == 0i64 {
            fraction /= 10i64
            digits -= 1u32
        }
        while digits > 0u32 {
            at -= 1usize
            out[at] = 48u8 + u8(fraction % 10i64)
            fraction /= 10i64
            digits -= 1u32
        }
        at -= 1usize
        out[at] = 46u8
    }
    while true {
        at -= 1usize
        out[at] = 48u8 + u8(whole % 10i64)
        whole /= 10i64
        if whole == 0i64 { break }
    }
    if negative && (at < out.len - 1usize || out[at] != 48u8) {
        at -= 1usize
        out[at] = 45u8
    }
    ret (out[at..], ok)
}

fn real(doc: *Document, value: f32, decimals: u32) -> err {
    var buffer: [32]u8 = zero
    let (text, text_error) = real_text(value, decimals, buffer[..])
    if text_error != ok { ret text_error }
    try put(doc, text)
    ret put(doc, " ")
}

fn point(doc: *Document, x: f32, y: f32) -> err {
    try real(doc, x, 3u32)
    ret real(doc, doc.height - y, 3u32)
}

fn channel(c: f32) -> f32 { ret f32(u32(c * 255.0 + 0.5)) / 255.0 }

// Colour as the other adapters round it, plus a graphics state for alpha;
// the caller wraps the shape in q ... Q.
fn color(doc: *Document, ink: paint.Color, stroke: bool) -> err {
    if !paint.color_ok(ink) { ret Invalid }
    if ink.alpha < 1.0 {
        var index = 0usize
        while index < doc.alpha_count && doc.alphas[index] != ink.alpha { index += 1usize }
        if index == doc.alpha_count {
            if doc.alpha_count == doc.alphas.len { ret TooLarge }
            doc.alphas[index] = ink.alpha
            doc.alpha_count += 1usize
        }
        try put(doc, "/G")
        let digits = [2]u8{ 48u8 + u8(index / 10usize), 48u8 + u8(index % 10usize) }
        if index < 10usize { try put(doc, digits[1usize..]) } else { try put(doc, digits[..]) }
        try put(doc, " gs ")
    }
    try real(doc, channel(ink.red), 4u32)
    try real(doc, channel(ink.green), 4u32)
    try real(doc, channel(ink.blue), 4u32)
    if stroke { ret put(doc, "RG\n") }
    ret put(doc, "rg\n")
}

fn rect(doc: *Document, r: geometry.Rect, ink: paint.Color, outline: bool) -> err {
    if !chart.finite(r.x) || !chart.finite(r.y) || !chart.finite(r.width) || !chart.finite(r.height) || r.width <= 0.0 || r.height <= 0.0 { ret Invalid }
    try put(doc, "q ")
    try color(doc, ink, outline)
    if outline { try put(doc, "2 w ") }
    try point(doc, r.x, r.y + r.height)
    try real(doc, r.width, 3u32)
    try real(doc, r.height, 3u32)
    if outline { ret put(doc, "re S Q\n") }
    ret put(doc, "re f Q\n")
}

fn rule(doc: *Document, from: chart.Coord, to: chart.Coord, ink: paint.Color, width: f32) -> err {
    if !chart.finite(width) || width <= 0.0 { ret Invalid }
    try put(doc, "q ")
    try color(doc, ink, true)
    try real(doc, width, 3u32)
    try put(doc, "w 1 J ")
    try point(doc, from.x, from.y)
    try put(doc, "m ")
    try point(doc, to.x, to.y)
    ret put(doc, "l S Q\n")
}

fn path(doc: *Document, points: []const chart.Coord, ink: paint.Color, filled: bool) -> err {
    if points.len == 0usize { ret ok }
    try put(doc, "q ")
    try color(doc, ink, !filled)
    if !filled { try put(doc, "2 w 1 j 1 J ") }
    var i = 0usize
    while i < points.len {
        try point(doc, points[i].x, points[i].y)
        if i == 0usize { try put(doc, "m ") } else { try put(doc, "l ") }
        i += 1usize
    }
    if filled { ret put(doc, "h f Q\n") }
    ret put(doc, "S Q\n")
}

// A circle as four cubic Beziers (k = 0.5523, under 0.03% radial error).
fn circle(doc: *Document, cx: f32, cy: f32, r: f32, ink: paint.Color) -> err {
    if !chart.finite(cx) || !chart.finite(cy) || !chart.finite(r) || r <= 0.0 { ret Invalid }
    let k = r * 0.5523
    try put(doc, "q ")
    try color(doc, ink, false)
    try point(doc, cx + r, cy)
    try put(doc, "m ")
    let xs = [12]f32{ cx + r, cx + k, cx, cx - k, cx - r, cx - r, cx - r, cx - k, cx, cx + k, cx + r, cx + r }
    let ys = [12]f32{ cy - k, cy - r, cy - r, cy - r, cy - k, cy, cy + k, cy + r, cy + r, cy + r, cy + k, cy }
    var i = 0usize
    while i < 12usize {
        try point(doc, xs[i], ys[i])
        if i % 3usize == 2usize { try put(doc, "c ") }
        i += 1usize
    }
    ret put(doc, "f Q\n")
}

fn dot(doc: *Document, p: chart.Coord, ink: paint.Color) -> err {
    ret rect(doc, geometry.rect(p.x - 3.0, p.y - 3.0, 6.0, 6.0), ink, false)
}

// The same mark kinds, shapes and widths as chart.svg.append.
fn append(doc: *Document, marks: *const chart.Layout, ink: paint.Color) -> err {
    if !paint.color_ok(ink) { ret Invalid }
    if marks.kind == .PointLine {
        var line_marks = *marks
        line_marks.kind = .Line
        try append(doc, &line_marks, ink)
        var points = *marks
        points.kind = .Scatter
        ret append(doc, &points, ink)
    }
    if marks.kind == .Scatter || marks.kind == .Strip || marks.kind == .Beeswarm || marks.kind == .DotPlot {
        var i = 0usize
        while i < marks.coords.len {
            try dot(doc, marks.coords[i], ink)
            i += 1usize
        }
    } else if marks.kind == .Line || marks.kind == .Step || marks.kind == .Ecdf || marks.kind == .Density || marks.kind == .FrequencyPolygon {
        if marks.segments.len == 0usize { ret ok }
        try put(doc, "q ")
        try color(doc, ink, true)
        try put(doc, "2 w 1 j 1 J ")
        try point(doc, marks.segments[0usize].from.x, marks.segments[0usize].from.y)
        try put(doc, "m ")
        var i = 0usize
        while i < marks.segments.len {
            try point(doc, marks.segments[i].to.x, marks.segments[i].to.y)
            try put(doc, "l ")
            i += 1usize
        }
        try put(doc, "S Q\n")
    } else if marks.kind == .Area || marks.kind == .Violin || marks.kind == .Band {
        if marks.coords.len < 4usize { ret Invalid }
        try path(doc, marks.coords, ink, true)
    } else if marks.kind == .Box || marks.kind == .Lollipop || marks.kind == .ErrorBar || marks.kind == .Qq || marks.kind == .Pp || marks.kind == .Dumbbell || marks.kind == .SlopeGraph || marks.kind == .Rug {
        var i = 0usize
        while i < marks.bars.len {
            if marks.bars[i].width > 0.0 && marks.bars[i].height > 0.0 { try rect(doc, marks.bars[i], ink, true) }
            i += 1usize
        }
        i = 0usize
        while i < marks.segments.len {
            try rule(doc, marks.segments[i].from, marks.segments[i].to, ink, 2.0)
            i += 1usize
        }
        i = 0usize
        while i < marks.coords.len {
            try dot(doc, marks.coords[i], ink)
            i += 1usize
        }
    } else if marks.kind == .Bubble {
        var i = 0usize
        while i < marks.bars.len {
            let box = marks.bars[i]
            if box.width > 0.0 && box.height > 0.0 { try circle(doc, box.x + box.width * 0.5, box.y + box.height * 0.5, box.width * 0.5, ink) }
            i += 1usize
        }
    } else if marks.kind == .Bar || marks.kind == .Histogram || marks.kind == .Waterfall {
        var i = 0usize
        while i < marks.bars.len {
            if marks.bars[i].width > 0.0 && marks.bars[i].height > 0.0 { try rect(doc, marks.bars[i], ink, false) }
            i += 1usize
        }
        if marks.kind == .Waterfall {
            i = 0usize
            while i < marks.segments.len {
                try rule(doc, marks.segments[i].from, marks.segments[i].to, ink, 2.0)
                i += 1usize
            }
        }
    } else {
        ret Invalid
    }
    ret ok
}

fn append_matrix(doc: *Document, marks: *const chart.MatrixLayout, low: paint.Color, middle: paint.Color, high: paint.Color) -> err {
    if marks.kind != .Heatmap && marks.kind != .Correlation && marks.kind != .Mosaic && marks.kind != .Association { ret Invalid }
    if marks.columns == 0usize || marks.rows == 0usize || (marks.cells.len == 0usize && marks.kind != .Association) { ret Invalid }
    if !paint.color_ok(low) || !paint.color_ok(middle) || !paint.color_ok(high) { ret Invalid }
    var i = 0usize
    while i < marks.cells.len {
        let cell = marks.cells[i]
        if !chart.finite(cell.value) { ret Invalid }
        var ink = middle
        if marks.kind == .Correlation || marks.kind == .Mosaic || marks.kind == .Association {
            let value = cell.value / marks.value_max
            if value < 0.0 { ink = paint.mix(low, middle, value + 1.0) }
            if value > 0.0 { ink = paint.mix(middle, high, value) }
        } else if marks.value_max > marks.value_min {
            ink = paint.mix(low, high, (cell.value - marks.value_min) / (marks.value_max - marks.value_min))
        }
        try rect(doc, cell.rect, ink, false)
        i += 1usize
    }
    ret ok
}

fn append_guides(doc: *Document, bounds: geometry.Rect, x_ticks: []const chart.Tick, y_ticks: []const chart.Tick, grid: paint.Color, axis: paint.Color) -> err {
    if !chart.valid_bounds(bounds) || !paint.color_ok(grid) || !paint.color_ok(axis) { ret Invalid }
    var i = 0usize
    while i < x_ticks.len {
        let t = x_ticks[i].fraction
        if !(t >= 0.0 && t <= 1.0) { ret Invalid }
        let x = bounds.x + bounds.width * t
        try rule(doc, chart.Coord { x: x, y: bounds.y }, chart.Coord { x: x, y: bounds.y + bounds.height }, grid, 1.0)
        try rule(doc, chart.Coord { x: x, y: bounds.y + bounds.height }, chart.Coord { x: x, y: bounds.y + bounds.height + 5.0 }, axis, 1.0)
        i += 1usize
    }
    i = 0usize
    while i < y_ticks.len {
        let t = y_ticks[i].fraction
        if !(t >= 0.0 && t <= 1.0) { ret Invalid }
        let y = bounds.y + bounds.height * (1.0 - t)
        try rule(doc, chart.Coord { x: bounds.x, y: y }, chart.Coord { x: bounds.x + bounds.width, y: y }, grid, 1.0)
        try rule(doc, chart.Coord { x: bounds.x - 5.0, y: y }, chart.Coord { x: bounds.x, y: y }, axis, 1.0)
        i += 1usize
    }
    try rule(doc, chart.Coord { x: bounds.x, y: bounds.y }, chart.Coord { x: bounds.x, y: bounds.y + bounds.height }, axis, 1.0)
    ret rule(doc, chart.Coord { x: bounds.x, y: bounds.y + bounds.height }, chart.Coord { x: bounds.x + bounds.width, y: bounds.y + bounds.height }, axis, 1.0)
}

// The WinAnsi byte for one code point, or 0 when the encoding has none.
// Bytes 128-159 carry the typographic marks Windows-1252 put there
// (generated by scripts/chart_pdf_metrics.py).
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

// The next code point of valid UTF-8 at `at`, and its length.
fn decode(text: str, at: usize) -> (u32, usize) {
    let b = u32(text[at])
    if b < 128u32 { ret (b, 1usize) }
    if b < 224u32 { ret ((b & 31u32) << 6u32 | (u32(text[at + 1usize]) & 63u32), 2usize) }
    if b < 240u32 { ret ((b & 15u32) << 12u32 | (u32(text[at + 1usize]) & 63u32) << 6u32 | (u32(text[at + 2usize]) & 63u32), 3usize) }
    ret ((b & 7u32) << 18u32 | (u32(text[at + 1usize]) & 63u32) << 12u32 | (u32(text[at + 2usize]) & 63u32) << 6u32 | (u32(text[at + 3usize]) & 63u32), 4usize)
}

// Advance width of `text` in Helvetica, in thousandths of the font size.
fn winansi_width(text: str) -> (u32, err) {
    if !text_layout.valid_utf8(text) { ret (0u32, Invalid) }
    // Adobe's Helvetica AFM, bytes 32..255 (scripts/chart_pdf_metrics.py).
    let widths = [224]u16{
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
    var total = 0u32
    var at = 0usize
    while at < text.len {
        let (code, length) = decode(text, at)
        let byte = winansi(code)
        if byte == 0u8 { ret (0u32, Invalid) }
        total += u32(widths[usize(byte) - 32usize])
        at += length
    }
    ret (total, ok)
}

fn text_width(text: str, size: f32) -> (f32, err) {
    if !chart.finite(size) || size <= 0.0 { ret (0.0, Invalid) }
    let (units, units_error) = winansi_width(text)
    if units_error != ok { ret (0.0, units_error) }
    ret (f32(units) * size / 1000.0, ok)
}

// A PDF literal string: WinAnsi bytes, with ( ) \ escaped and bytes past 126
// written as octal so the file stays ASCII.
fn literal(doc: *Document, text: str) -> err {
    try put(doc, "(")
    var at = 0usize
    while at < text.len {
        let (code, length) = decode(text, at)
        let byte = winansi(code)
        if byte == 0u8 { ret Invalid }
        if byte == 40u8 || byte == 41u8 || byte == 92u8 {
            let pair = [2]u8{ 92u8, byte }
            try put(doc, pair[..])
        } else if byte > 126u8 {
            let octal = [4]u8{ 92u8, 48u8 + byte / 64u8, 48u8 + byte / 8u8 % 8u8, 48u8 + byte % 8u8 }
            try put(doc, octal[..])
        } else {
            let one = [1]u8{ byte }
            try put(doc, one[..])
        }
        at += length
    }
    ret put(doc, ")")
}

// Document-information text is PDFDocEncoding, not WinAnsi, so it is written
// as a UTF-16BE hex string with a byte-order mark: any title survives.
fn utf16_hex(doc: *Document, text: str) -> err {
    let hex = "0123456789ABCDEF"
    try put(doc, "<FEFF")
    var at = 0usize
    while at < text.len {
        let (code, length) = decode(text, at)
        var units = [2]u32{ code, 0u32 }
        var count = 1usize
        if code > 65535u32 {
            units[0usize] = 55296u32 + ((code - 65536u32) >> 10u32)
            units[1usize] = 56320u32 + ((code - 65536u32) & 1023u32)
            count = 2usize
        }
        var u = 0usize
        while u < count {
            let digits = [4]u8{ hex[usize(units[u] >> 12u32 & 15u32)], hex[usize(units[u] >> 8u32 & 15u32)], hex[usize(units[u] >> 4u32 & 15u32)], hex[usize(units[u] & 15u32)] }
            try put(doc, digits[..])
            u += 1usize
        }
        at += length
    }
    ret put(doc, ">")
}

// Labels with the SVG adapter's anchors: baseline at anchor.y, aligned on
// anchor.x by Helvetica's advance widths.
fn append_labels(doc: *Document, labels: []const chart.Label, ink: paint.Color, size: f32) -> err {
    if !paint.color_ok(ink) || !chart.finite(size) || size <= 0.0 { ret Invalid }
    var i = 0usize
    while i < labels.len {
        let label = labels[i]
        if !chart.valid_label(&label) { ret Invalid }
        let (width, width_error) = text_width(label.text, size)
        if width_error != ok { ret width_error }
        var x = label.anchor.x
        if label.align == .Center { x -= width / 2.0 }
        if label.align == .Right { x -= width }
        try put(doc, "q ")
        try color(doc, ink, false)
        try put(doc, "BT /F1 ")
        try real(doc, size, 3u32)
        try put(doc, "Tf ")
        try point(doc, x, label.anchor.y)
        try put(doc, "Td ")
        try literal(doc, label.text)
        try put(doc, " Tj ET Q\n")
        i += 1usize
    }
    ret ok
}

// The output writer with the running byte count the cross-reference needs.
type Sink = struct { w: *io.Writer, offset: usize }

fn emit(s: *Sink, text: []const u8) -> err {
    try io.write_all(s.w, text)
    s.offset += text.len
    ret ok
}

fn emit_number(s: *Sink, value: usize) -> err {
    var buffer: [24]u8 = zero
    var at = buffer.len
    var rest = value
    while true {
        at -= 1usize
        buffer[at] = 48u8 + u8(rest % 10usize)
        rest /= 10usize
        if rest == 0usize { break }
    }
    ret emit(s, buffer[at..])
}

// An xref entry: ten-digit offset, generation, in-use flag, two-byte EOL.
fn emit_xref(s: *Sink, offset: usize) -> err {
    var entry: [20]u8 = zero
    var value = offset
    var i = 10usize
    while i > 0usize {
        i -= 1usize
        entry[i] = 48u8 + u8(value % 10usize)
        value /= 10usize
    }
    let tail = " 00000 n \n"
    var j = 0usize
    while j < tail.len {
        entry[10usize + j] = tail[j]
        j += 1usize
    }
    ret emit(s, entry[..])
}

// Writes the document: catalog, page tree, page, font, content stream,
// opacity states, info, then the cross-reference table and trailer.
fn finish(doc: *Document, w: *io.Writer) -> err {
    let objects = 6usize + doc.alpha_count + 1usize
    var offsets: [24]usize = zero
    var s = Sink { w: w, offset: 0usize }
    let header = [15]u8{ 37u8, 80u8, 68u8, 70u8, 45u8, 49u8, 46u8, 52u8, 10u8, 37u8, 226u8, 227u8, 207u8, 211u8, 10u8 }
    try emit(&s, header[..])
    offsets[1usize] = s.offset
    try emit(&s, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
    offsets[2usize] = s.offset
    try emit(&s, "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n")
    offsets[3usize] = s.offset
    var size_doc = Document { storage: zero, len: 0usize, width: doc.width, height: doc.height, title: "", alphas: zero, alpha_count: 0usize }
    var box: [64]u8 = zero
    size_doc.storage = box[..]
    try real(&size_doc, doc.width, 3u32)
    try real(&size_doc, doc.height, 3u32)
    try emit(&s, "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ")
    try emit(&s, box[..size_doc.len])
    try emit(&s, "] /Resources << /Font << /F1 4 0 R >>")
    if doc.alpha_count > 0usize {
        try emit(&s, " /ExtGState <<")
        var g = 0usize
        while g < doc.alpha_count {
            try emit(&s, " /G")
            try emit_number(&s, g)
            try emit(&s, " ")
            try emit_number(&s, 6usize + g)
            try emit(&s, " 0 R")
            g += 1usize
        }
        try emit(&s, " >>")
    }
    try emit(&s, " >> /Contents 5 0 R >>\nendobj\n")
    offsets[4usize] = s.offset
    try emit(&s, "4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\nendobj\n")
    offsets[5usize] = s.offset
    try emit(&s, "5 0 obj\n<< /Length ")
    try emit_number(&s, doc.len)
    try emit(&s, " >>\nstream\n")
    try emit(&s, doc.storage[..doc.len])
    try emit(&s, "\nendstream\nendobj\n")
    var g = 0usize
    while g < doc.alpha_count {
        offsets[6usize + g] = s.offset
        var alpha_doc = Document { storage: zero, len: 0usize, width: doc.width, height: doc.height, title: "", alphas: zero, alpha_count: 0usize }
        var alpha_text: [32]u8 = zero
        alpha_doc.storage = alpha_text[..]
        try real(&alpha_doc, doc.alphas[g], 4u32)
        try emit_number(&s, 6usize + g)
        try emit(&s, " 0 obj\n<< /Type /ExtGState /ca ")
        try emit(&s, alpha_text[..alpha_doc.len])
        try emit(&s, "/CA ")
        try emit(&s, alpha_text[..alpha_doc.len])
        try emit(&s, ">>\nendobj\n")
        g += 1usize
    }
    let info = 6usize + doc.alpha_count
    offsets[info] = s.offset
    var title_doc = Document { storage: zero, len: 0usize, width: doc.width, height: doc.height, title: "", alphas: zero, alpha_count: 0usize }
    var title_text: [2048]u8 = zero
    title_doc.storage = title_text[..]
    try utf16_hex(&title_doc, doc.title)
    try emit_number(&s, info)
    try emit(&s, " 0 obj\n<< /Title ")
    try emit(&s, title_text[..title_doc.len])
    try emit(&s, " /Producer (Neper e.gfx.chart.pdf) >>\nendobj\n")
    let xref = s.offset
    try emit(&s, "xref\n0 ")
    try emit_number(&s, objects)
    try emit(&s, "\n0000000000 65535 f \n")
    var o = 1usize
    while o < objects {
        try emit_xref(&s, offsets[o])
        o += 1usize
    }
    try emit(&s, "trailer\n<< /Size ")
    try emit_number(&s, objects)
    try emit(&s, " /Root 1 0 R /Info ")
    try emit_number(&s, info)
    try emit(&s, " 0 R >>\nstartxref\n")
    try emit_number(&s, xref)
    ret emit(&s, "\n%%EOF\n")
}
