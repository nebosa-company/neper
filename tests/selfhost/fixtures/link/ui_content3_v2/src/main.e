// The v2 rich text (D964, widget plan P5-07, docs/ux/components/RichText) under
// the light theme with the square-glyph font, whose space is a square too. A
// body-medium paragraph 120 wide wraps at word boundaries across spans: plain
// words, inline code on `surface-container-high`, and a link that moves whole to
// the second line, where a mention follows. The code glyphs share the body
// baseline; the link is `primary` over a 1px underline, its target 32 tall
// reserved 6 above and below the lines, and it fires on a tap; hovered, its
// underline and an 8% `primary` wash show on the next frame. A paragraph cut to
// one line ends with the ellipsis after the last word that fits it. A key is on
// `surface-container-lowest` in a 1px `outline-variant` edge, and a visited link
// is `link-visited`.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

fn w16(d: []u8, at: usize, v: u32) {
    d[at] = u8((v >> 8u32) & 255u32)
    d[at + 1usize] = u8(v & 255u32)
}
fn w32(d: []u8, at: usize, v: u32) {
    w16(d, at, v >> 16u32)
    w16(d, at + 2usize, v & 65535u32)
}
fn record(d: []u8, slot: usize, tag: u32, at: usize, len: usize) {
    let r = 12usize + 16usize * slot
    w32(d, r, tag)
    w32(d, r + 8usize, u32(at))
    w32(d, r + 12usize, u32(len))
}

// The square-glyph font of the content fixture, whose cmap maps both the space
// and `a` to the square glyph 1.
fn synthetic_font(a: *mem.Arena) -> ([]u8, err) {
    let (d, d_error) = mem.alloc[u8](a, 512usize)
    if d_error != ok { ret (d, d_error) }
    var i = 0usize
    while i < 512usize {
        d[i] = 0u8
        i += 1usize
    }
    w32(d, 0usize, 65536u32)
    w16(d, 4usize, 7u32)
    record(d, 0usize, 1751474532u32, 128usize, 54usize)
    w16(d, 128usize + 18usize, 1000u32)
    record(d, 1usize, 1751672161u32, 192usize, 36usize)
    w16(d, 192usize + 4usize, 800u32)
    w16(d, 192usize + 34usize, 2u32)
    record(d, 2usize, 1752003704u32, 228usize, 8usize)
    w16(d, 228usize + 4usize, 600u32)
    record(d, 3usize, 1835104368u32, 236usize, 6usize)
    w16(d, 236usize + 4usize, 2u32)
    // cmap at 300: one encoding record (3, 1) to a format 4 subtable with three
    // segments, the space and `a` to glyph 1, and the 0xFFFF terminator.
    record(d, 4usize, 1668112752u32, 300usize, 52usize)
    w16(d, 300usize, 0u32)
    w16(d, 302usize, 1u32)
    w16(d, 304usize, 3u32)
    w16(d, 306usize, 1u32)
    w32(d, 308usize, 12u32)
    let sub = 312usize
    w16(d, sub, 4u32)
    w16(d, sub + 2usize, 40u32)
    w16(d, sub + 4usize, 0u32)
    w16(d, sub + 6usize, 6u32)
    w16(d, sub + 8usize, 4u32)
    w16(d, sub + 10usize, 1u32)
    w16(d, sub + 12usize, 2u32)
    w16(d, sub + 14usize, 32u32)
    w16(d, sub + 16usize, 97u32)
    w16(d, sub + 18usize, 65535u32)
    w16(d, sub + 20usize, 0u32)
    w16(d, sub + 22usize, 32u32)
    w16(d, sub + 24usize, 97u32)
    w16(d, sub + 26usize, 65535u32)
    w16(d, sub + 28usize, 65505u32)
    w16(d, sub + 30usize, 65440u32)
    w16(d, sub + 32usize, 1u32)
    w16(d, sub + 34usize, 0u32)
    w16(d, sub + 36usize, 0u32)
    w16(d, sub + 38usize, 0u32)
    record(d, 5usize, 1819239265u32, 252usize, 6usize)
    record(d, 6usize, 1735162214u32, 260usize, 40usize)
    let g = 260usize
    w16(d, g, 1u32)
    w16(d, g + 2usize, 100u32)
    w16(d, g + 4usize, 100u32)
    w16(d, g + 6usize, 900u32)
    w16(d, g + 8usize, 900u32)
    w16(d, g + 10usize, 3u32)
    w16(d, g + 12usize, 0u32)
    var at = g + 14usize
    d[at] = 55u8
    d[at + 1usize] = 33u8
    d[at + 2usize] = 17u8
    d[at + 3usize] = 33u8
    at += 4usize
    d[at] = 100u8
    d[at + 1usize] = 3u8
    d[at + 2usize] = 32u8
    d[at + 3usize] = 252u8
    d[at + 4usize] = 224u8
    at += 5usize
    d[at] = 100u8
    d[at + 1usize] = 3u8
    d[at + 2usize] = 32u8
    at += 3usize
    w16(d, 252usize + 2usize, 0u32)
    w16(d, 252usize + 4usize, u32((at - g) / 2usize))
    ret (d, ok)
}

type Page = struct { first: [5]control.RichSpan, cut: [1]control.RichSpan, keyed: [3]control.RichSpan, links: u32 }

fn on_link(ctx: *void) -> err {
    let page = mem.cast[*Page](ctx)
    page.links += 1u32
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 4.0 && e - v < 4.0
}

fn px(x: f32, y: f32) -> usize {
    ret (usize(y) * 300usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn over(top: paint.Color, alpha: f32, under: paint.Color) -> paint.Color {
    ret paint.rgba(top.red * alpha + under.red * (1.0 - alpha), top.green * alpha + under.green * (1.0 - alpha), top.blue * alpha + under.blue * (1.0 - alpha), 1.0)
}

// The lowest row in a column, from `y0` for `rows`, whose pixel is dark.
fn lowest_dark(shot: image.Image, x: f32, y0: f32, rows: f32) -> f32 {
    var found: f32 = -1.0
    var y = y0
    while y < y0 + rows {
        if shot.pixels[px(x, y)] < 128u8 { found = y }
        y += 1.0
    }
    ret found
}

// How many runs of a colour a column holds, from `y0` for `rows`.
fn runs(shot: image.Image, x: f32, y0: f32, rows: f32, c: paint.Color) -> usize {
    var n = 0usize
    var inside = false
    var y = y0
    while y < y0 + rows {
        let hit = is_color(shot, px(x, y), c)
        if hit && !inside { n += 1usize }
        inside = hit
        y += 1.0
    }
    ret n
}

fn build(a: *mem.Arena, t: *const control.Theme, page: *Page) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 3usize)
    if items_error != ok { ret (zero, items_error) }
    var wide = control.rich_options(t)
    wide.width = 120.0
    let (one, one_error) = control.paragraph(a, 10u64, t, page.first[..], wide)
    if one_error != ok { ret (zero, one_error) }
    items[0usize] = one
    var cut = control.rich_options(t)
    cut.width = 60.0
    cut.max_lines = 1u32
    cut.ellipsis = "a"
    let (two, two_error) = control.paragraph(a, 20u64, t, page.cut[..], cut)
    if two_error != ok { ret (zero, two_error) }
    items[1usize] = two
    let (three, three_error) = control.paragraph(a, 30u64, t, page.keyed[..], control.rich_options(t))
    if three_error != ok { ret (zero, three_error) }
    items[2usize] = three
    var column = style.defaults()
    column.width = style.Length { Px: 300.0 }
    column.height = style.Length { Px: 240.0 }
    column.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 24.0 }
    column.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 24.0 }, column, items[0usize..3usize]), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let (font_bytes, font_error) = synthetic_font(a)
    if font_error != ok { os.exit(4i32) }
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 1usize)
    if fonts_error != ok { os.exit(5i32) }
    fonts[0usize] = shape.Font { id: 7u32, data: font_bytes, face_index: 0u32 }
    if scene.register_font(&renderer, fonts[0usize]) != ok { os.exit(6i32) }
    let tokens = style.reference(.Light)
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 256usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 2048usize })
    if runtime_error != ok { os.exit(7i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts[0usize..1usize], language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 300u32, 240u32, 1.0)
    if harness_error != ok { os.exit(8i32) }
    var harness = h
    let (pages, pages_error) = mem.alloc[Page](a, 1usize)
    if pages_error != ok { os.exit(9i32) }
    var blank: Page = zero
    pages[0usize] = blank
    let page = &pages[0usize]
    page.first[0usize] = control.rich_span("aa aa ", .Plain)
    page.first[1usize] = control.rich_span("aaa", .Code)
    page.first[2usize] = control.rich_span(" aa", .Plain)
    page.first[3usize] = control.rich_span("aaaa", .Link)
    page.first[3usize].action = widget.Submit { ctx: mem.cast[*void](page), invoke: on_link }
    page.first[4usize] = control.rich_span("aa", .Mention)
    page.cut[0usize] = control.rich_span("aa aa aa aa", .Plain)
    page.keyed[0usize] = control.rich_span("aa", .Key)
    page.keyed[1usize] = control.rich_span(" a", .Plain)
    page.keyed[2usize] = control.rich_span("aa", .Link)
    page.keyed[2usize].visited = true
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(10i32) }
    var frame = mem.arena_from(frame_storage)
    let (root, build_error) = build(&frame, &theme, page)
    if build_error != ok { os.exit(11i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(12i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(13i32) }
    let ground = style.color(&tokens, .Background)
    let primary = style.color(&tokens, .Primary)
    let body = style.text_style(&tokens, .BodyMedium)
    let code = style.text_style(&tokens, .Code)
    let step = 0.6 * body.size
    let code_step = 0.6 * code.size
    // The paragraph: two 20 lines inside the 6 the link target reaches past them.
    let (p1, has_p1) = widget.bounds_of(&runtime, testing.by_key(&harness, 10u64).element)
    if !has_p1 || !near(p1.width, 120.0) || !near(p1.height, 2.0 * body.line_height + 12.0) { os.exit(14i32) }
    let line1 = p1.y + 6.0
    let line2 = line1 + body.line_height
    // The first words are the body colour; the code piece starts on its fill.
    if !is_color(shot, px(p1.x + 4.0, line1 + 8.0), style.color(&tokens, .OnSurface)) { os.exit(15i32) }
    let code_x = p1.x + 6.0 * step
    if !is_color(shot, px(code_x + 1.0, line1 + 10.0), style.color(&tokens, .SurfaceContainerHigh)) { os.exit(16i32) }
    // The code glyphs stand on the body baseline.
    let body_foot = lowest_dark(shot, p1.x + 4.0, line1, body.line_height)
    let code_foot = lowest_dark(shot, code_x + 4.0 + 5.0, line1, body.line_height)
    if body_foot < 0.0 || code_foot < 0.0 || body_foot - code_foot > 1.0 || code_foot - body_foot > 1.0 { os.exit(17i32) }
    // The link moved whole to the second line: its target is 32 tall and 6 above
    // the line, its column holds the glyph and the underline, and a tap fires it.
    let (link_bounds, has_link) = widget.bounds_of(&runtime, testing.by_key(&harness, 10u64 + 1u64 + 3u64).element)
    if !has_link || !near(link_bounds.x, p1.x) || !near(link_bounds.y, line2 - 6.0) || !near(link_bounds.height, 32.0) || !near(link_bounds.width, 4.0 * step) { os.exit(18i32) }
    if runs(shot, p1.x + 5.0, line2, body.line_height, primary) != 2usize { os.exit(19i32) }
    // The mention after it: `primary`, no underline.
    if runs(shot, p1.x + 4.0 * step + 5.0, line2, body.line_height, primary) != 1usize { os.exit(20i32) }
    if testing.by_role(&harness, .Link).count != 1usize { os.exit(21i32) }
    if testing.tap(&harness, link_bounds.x + 8.0, link_bounds.y + 16.0) != ok || page.links != 1u32 { os.exit(22i32) }
    // The cut paragraph: one line, the second word then the ellipsis, the width
    // it was given.
    let (p2, has_p2) = widget.bounds_of(&runtime, testing.by_key(&harness, 20u64).element)
    if !has_p2 || !near(p2.width, 60.0) || !near(p2.height, body.line_height) { os.exit(23i32) }
    if !is_color(shot, px(p2.x + 6.0 * step + 4.0, p2.y + 8.0), style.color(&tokens, .OnSurface)) { os.exit(24i32) }
    if !is_color(shot, px(p2.x + 7.0 * step + 5.0, p2.y + 8.0), ground) { os.exit(25i32) }
    if testing.by_label(&harness, "aa aa aa aa").count == 0usize { os.exit(26i32) }
    // The key's edge and fill; the visited link's colour.
    let (p3, has_p3) = widget.bounds_of(&runtime, testing.by_key(&harness, 30u64).element)
    if !has_p3 { os.exit(27i32) }
    if !is_color(shot, px(p3.x, p3.y + 10.0), style.color(&tokens, .OutlineVariant)) || !is_color(shot, px(p3.x + 2.0, p3.y + 10.0), style.color(&tokens, .SurfaceContainerLowest)) { os.exit(28i32) }
    let visited_x = p3.x + 2.0 * code_step + 8.0 + 2.0 * step
    if !is_color(shot, px(visited_x + 5.0, p3.y + 8.0), style.color(&tokens, .LinkVisited)) { os.exit(29i32) }
    // Hovered, the next frame washes the link and thickens its underline.
    if testing.hover(&harness, link_bounds.x + 8.0, link_bounds.y + 16.0) != ok { os.exit(30i32) }
    frame = mem.arena_from(frame_storage)
    let (root_2, build_2_error) = build(&frame, &theme, page)
    if build_2_error != ok { os.exit(31i32) }
    if testing.pump(&harness, root_2, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(32i32) }
    let (hovered, hovered_error) = testing.snapshot(&harness, a)
    if hovered_error != ok { os.exit(33i32) }
    if !is_color(hovered, px(p1.x + 0.5, line2 + 1.0), over(primary, tokens.states.hover, ground)) { os.exit(34i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(35i32) }
    try io.print("ui content3 v2 ok\n")
    ret ok
}
