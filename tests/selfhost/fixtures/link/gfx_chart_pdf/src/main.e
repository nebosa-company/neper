use e.gfx.chart
use e.gfx.chart.pdf as chart_pdf
use e.gfx.geometry
use e.gfx.paint
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool { ret a - b < 0.001 && b - a < 0.001 }

fn real_is(value: f32, decimals: u32, want: str) -> bool {
    var buffer: [32]u8 = zero
    let (text, text_error) = chart_pdf.real_text(value, decimals, buffer[..])
    ret text_error == ok && str.eq(text, want)
}

// The decimal number written right after `key` at or past `from`.
fn number_after(text: str, key: str, from: usize) -> (usize, bool) {
    let (at, found) = str.find(text[from..], key)
    if !found { ret (0usize, false) }
    var i = from + at + key.len
    var value = 0usize
    var digits = 0usize
    while i < text.len && text[i] >= 48u8 && text[i] <= 57u8 {
        value = value * 10usize + usize(text[i] - 48u8)
        i += 1usize
        digits += 1usize
    }
    ret (value, digits > 0usize)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // PDF reals: fixed point, trimmed, never an exponent or a negative zero.
    if !real_is(2.0, 3u32, "2") || !real_is(0.125, 3u32, "0.125") || !real_is(-1.5, 3u32, "-1.5") || !real_is(-0.0004, 3u32, "0") || !real_is(240.0, 3u32, "240") || !real_is(0.0000001, 3u32, "0") || !real_is(0.4470588, 4u32, "0.4471") { ret chart.Invalid }
    // Helvetica advance widths: H e l l o = 722 + 556 + 222 + 222 + 556.
    let (hello, hello_error) = chart_pdf.text_width("Hello", 10.0)
    let (dash, dash_error) = chart_pdf.text_width("\xe2\x80\x93\xe2\x82\xac", 1000.0)
    let (_, greek_error) = chart_pdf.text_width("\xce\xa9", 10.0)
    if hello_error != ok || !near(hello, 22.78) || dash_error != ok || !near(dash, 1112.0) || greek_error != chart_pdf.Invalid { ret chart.Invalid }
    let x = [4]f32{ 1.0, 2.0, 3.0, 4.0 }
    let y = [4]f32{ 2.0, 6.0, 4.0, 8.0 }
    var bar_storage: [4]geometry.Rect = zero
    var point_storage: [4]chart.Coord = zero
    var line_storage: [3]chart.Segment = zero
    let plot = geometry.rect(40.0, 30.0, 280.0, 160.0)
    let bar_spec = chart.spec(.Bar, plot, x[..], y[..])
    let (bars, bars_error) = chart.layout(&bar_spec, zero, zero, bar_storage[..])
    let line_spec = chart.spec(.PointLine, plot, x[..], y[..])
    let (trend, trend_error) = chart.layout(&line_spec, point_storage[..], line_storage[..], zero)
    if bars_error != ok || trend_error != ok { ret chart.Invalid }
    var storage: [16384]u8 = zero
    let (made, begin_error) = chart_pdf.begin(storage[..], 360.0, 240.0, "Quarterly (est.) \xe2\x80\x93 \xe2\x82\xac")
    if begin_error != ok { ret begin_error }
    var doc = made
    let ticks = [3]chart.Tick{ chart.Tick { value: 0.0, fraction: 0.0 }, chart.Tick { value: 4.0, fraction: 0.5 }, chart.Tick { value: 8.0, fraction: 1.0 } }
    try chart_pdf.append_guides(&doc, plot, zero, ticks[..], paint.rgba(0.8, 0.84, 0.89, 1.0), paint.rgba(0.5, 0.5, 0.5, 1.0))
    try chart_pdf.append(&doc, &bars, paint.rgba(0.0, 114.0 / 255.0, 178.0 / 255.0, 0.5))
    try chart_pdf.append(&doc, &trend, paint.rgba(0.8, 0.3, 0.1, 1.0))
    let labels = [3]chart.Label{
        chart.Label { text: "Q1 (a)\\b", anchor: chart.Coord { x: 100.0, y: 220.0 }, align: .Left },
        chart.Label { text: "Hello", anchor: chart.Coord { x: 180.0, y: 20.0 }, align: .Center },
        chart.Label { text: "\xe2\x80\x93 \xe2\x82\xac5", anchor: chart.Coord { x: 320.0, y: 220.0 }, align: .Right },
    }
    try chart_pdf.append_labels(&doc, labels[..], paint.rgba(0.1, 0.1, 0.1, 1.0), 10.0)
    let content: str = storage[..doc.len]
    // Bars at half opacity share one graphics state; the bars fill, the line strokes.
    if doc.alpha_count != 1usize || !str.contains(content, "/G0 gs 0 0.4471 0.698 rg") || !str.contains(content, "0.8 0.302 0.102 RG") { ret chart.Invalid }
    // y flips to PDF's bottom-left origin: the first bar's top-left (x, 190 - h) becomes (x, 50).
    if !str.contains(content, " re f Q") || !str.contains(content, "2 w 1 j 1 J ") { ret chart.Invalid }
    // Centred text starts half its width left of the anchor; y = 240 - 20.
    if !str.contains(content, "BT /F1 10 Tf 168.61 220 Td (Hello) Tj ET") || !str.contains(content, "(Q1 \\(a\\)\\\\b)") || !str.contains(content, "(\\226 \\2005)") { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_pdf.finish(&doc, &writer)
    let file: str = io.memory_bytes(&held)
    if !str.starts_with(file, "%PDF-1.4\n") || !str.ends_with(file, "%%EOF\n") || !str.contains(file, "/Title <FEFF0051007500610072007400650072006C007900200028006500730074002E002900202013002020AC>") || !str.contains(file, "/ExtGState << /G0 6 0 R >>") || !str.contains(file, "/ca 0.5 /CA 0.5 >>") { ret chart.Invalid }
    // startxref names the xref table; every in-use entry points at its object.
    let (xref, has_xref) = number_after(file, "startxref\n", 0usize)
    if !has_xref || !str.starts_with(file[xref..], "xref\n0 8\n0000000000 65535 f \n") { ret chart.Invalid }
    var object = 1usize
    while object < 8usize {
        let entry = xref + 29usize + (object - 1usize) * 20usize
        let (offset, has_offset) = number_after(file, "", entry)
        var label: [8]u8 = zero
        label[0usize] = 48u8 + u8(object)
        let tail = " 0 obj\n"
        var i = 0usize
        while i < tail.len {
            label[1usize + i] = tail[i]
            i += 1usize
        }
        if !has_offset || !str.starts_with(file[offset..], label[..8usize]) { ret chart.Invalid }
        object += 1usize
    }
    // The stream holds exactly /Length bytes.
    let (length, has_length) = number_after(file, "/Length ", 0usize)
    let (stream_at, has_stream) = str.find(file, "stream\n")
    if !has_length || !has_stream || length != doc.len || !str.starts_with(file[stream_at + 7usize + length..], "\nendstream") { ret chart.Invalid }
    // Refusals: no room, a code point WinAnsi lacks, a bad page, a 17th opacity.
    var tiny: [8]u8 = zero
    let (small, small_error) = chart_pdf.begin(tiny[..], 100.0, 100.0, "t")
    var small_doc = small
    let room_error = chart_pdf.append(&small_doc, &bars, paint.rgba(0.0, 0.0, 0.0, 1.0))
    let greek_labels = [1]chart.Label{ chart.Label { text: "\xce\xa9", anchor: chart.Coord { x: 1.0, y: 1.0 }, align: .Left } }
    let label_error = chart_pdf.append_labels(&doc, greek_labels[..], paint.rgba(0.0, 0.0, 0.0, 1.0), 10.0)
    let (_, page_error) = chart_pdf.begin(storage[..], 0.0, 100.0, "t")
    var alpha = 1usize
    var alpha_error = ok
    while alpha < 18usize && alpha_error == ok {
        alpha_error = chart_pdf.rect(&doc, geometry.rect(1.0, 1.0, 2.0, 2.0), paint.rgba(0.0, 0.0, 0.0, f32(alpha) / 20.0), false)
        alpha += 1usize
    }
    if small_error != ok || room_error != chart_pdf.TooLarge || label_error != chart_pdf.Invalid || page_error != chart_pdf.Invalid || alpha_error != chart_pdf.TooLarge { ret chart.Invalid }
    try io.print("gfx chart pdf ok\n")
    ret ok
}
