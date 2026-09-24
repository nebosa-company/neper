// The v2 selectable text (D963, widget plan P5-07,
// docs/ux/components/SelectableText) under the light theme with the square-glyph
// font. The inline value is no Tab stop: Tab passes it for the block, which is
// `surface-container-high` with 8 corners and 12 by 16 padding and wears the focus
// ring. Pressed, the inline value takes focus, and Shift+End selects it: the
// selection fills `primary-container`, the selected glyphs are repainted
// `on-primary-container`, and the caret is 2px `primary`.

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
use e.ui.control
use e.ui.input
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

// The square-glyph font of the scene fixture, with a cmap mapping `a` to glyph 1.
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
    // cmap at 300: one encoding record (3, 1) to a format 4 subtable with one
    // segment, `a` (0x61) to glyph 1, and the 0xFFFF terminator.
    record(d, 4usize, 1668112752u32, 300usize, 44usize)
    w16(d, 300usize, 0u32)
    w16(d, 302usize, 1u32)
    w16(d, 304usize, 3u32)
    w16(d, 306usize, 1u32)
    w32(d, 308usize, 12u32)
    let sub = 312usize
    w16(d, sub, 4u32)
    w16(d, sub + 2usize, 32u32)
    w16(d, sub + 4usize, 0u32)
    w16(d, sub + 6usize, 4u32)
    w16(d, sub + 8usize, 4u32)
    w16(d, sub + 10usize, 1u32)
    w16(d, sub + 12usize, 0u32)
    w16(d, sub + 14usize, 97u32)
    w16(d, sub + 16usize, 65535u32)
    w16(d, sub + 18usize, 0u32)
    w16(d, sub + 20usize, 97u32)
    w16(d, sub + 22usize, 65535u32)
    w16(d, sub + 24usize, 65440u32)
    w16(d, sub + 26usize, 1u32)
    w16(d, sub + 28usize, 0u32)
    w16(d, sub + 30usize, 0u32)
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

type Page = struct { inline_value: [16]u8, block_value: [16]u8 }

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

// How many pixels of a colour lie in a box.
fn count(shot: image.Image, box_area: geometry.Rect, c: paint.Color) -> usize {
    var n = 0usize
    var y = box_area.y
    while y < box_area.y + box_area.height {
        var x = box_area.x
        while x < box_area.x + box_area.width {
            if is_color(shot, px(x, y), c) { n += 1usize }
            x += 1.0
        }
        y += 1.0
    }
    ret n
}

fn build(a: *mem.Arena, t: *const control.Theme, page: *Page) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 2usize)
    if items_error != ok { ret (zero, items_error) }
    let (one, one_error) = control.selectable_text(a, 1u64, page.inline_value[..], 3usize, t, control.text_options())
    if one_error != ok { ret (zero, one_error) }
    items[0usize] = one
    let (two, two_error) = control.selectable_block(a, 2u64, page.block_value[..], 4usize, t, control.text_options())
    if two_error != ok { ret (zero, two_error) }
    items[1usize] = two
    var column = style.defaults()
    column.width = style.Length { Px: 300.0 }
    column.height = style.Length { Px: 200.0 }
    column.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 24.0 }
    column.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 24.0 }, column, items[0usize..2usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 64usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 512usize })
    if runtime_error != ok { os.exit(7i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts[0usize..1usize], language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 300u32, 200u32, 1.0)
    if harness_error != ok { os.exit(8i32) }
    var harness = h
    let (pages, pages_error) = mem.alloc[Page](a, 1usize)
    if pages_error != ok { os.exit(9i32) }
    var page: Page = zero
    var i = 0usize
    while i < 16usize {
        page.inline_value[i] = 97u8
        page.block_value[i] = 97u8
        i += 1usize
    }
    pages[0usize] = page
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(10i32) }
    var frame = mem.arena_from(frame_storage)
    let (root, build_error) = build(&frame, &theme, &pages[0usize])
    if build_error != ok { os.exit(11i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(12i32) }
    let inline_found = testing.by_key(&harness, 1u64)
    let block_found = testing.by_key(&harness, 2u64)
    let (inline_bounds, has_inline) = widget.bounds_of(&runtime, inline_found.element)
    let (block_bounds, has_block) = widget.bounds_of(&runtime, block_found.element)
    if !has_inline || !has_block { os.exit(13i32) }
    // The block: one line of the code role inside 12 by 16 padding.
    let code = style.text_style(&tokens, .Code)
    if !near(block_bounds.height, code.line_height + 24.0) { os.exit(14i32) }
    // Tab passes the inline value and focuses the block, which wears the ring.
    var none: input.Modifiers = zero
    if testing.press_key(&harness, 9u32, none) != ok { os.exit(15i32) }
    let (first, has_first) = testing.focused(&harness)
    if !has_first || first.slot != block_found.element.slot { os.exit(16i32) }
    // The next frame draws the ring.
    frame = mem.arena_from(frame_storage)
    let (root_2, build_2_error) = build(&frame, &theme, &pages[0usize])
    if build_2_error != ok { os.exit(29i32) }
    if testing.pump(&harness, root_2, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(30i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(17i32) }
    if !is_color(shot, px(block_bounds.x + 2.0, block_bounds.y + block_bounds.height * 0.5), style.color(&tokens, .SurfaceContainerHigh)) { os.exit(18i32) }
    if !is_color(shot, px(block_bounds.x - 4.0, block_bounds.y + block_bounds.height * 0.5), style.color(&tokens, .FocusRing)) { os.exit(19i32) }
    // A press focuses the inline value; Shift+End selects its three glyphs.
    if testing.tap(&harness, inline_bounds.x + 1.0, inline_bounds.y + inline_bounds.height * 0.5) != ok { os.exit(20i32) }
    var shift: input.Modifiers = zero
    shift.shift = true
    if testing.press_key(&harness, 35u32, shift) != ok { os.exit(21i32) }
    let (sel_start, sel_end, has_selection) = widget.edit_selection(&runtime, inline_found.element)
    if !has_selection || sel_start != 0usize || sel_end != 3usize { os.exit(22i32) }
    frame = mem.arena_from(frame_storage)
    let (root_3, build_3_error) = build(&frame, &theme, &pages[0usize])
    if build_3_error != ok { os.exit(31i32) }
    if testing.pump(&harness, root_3, time.Instant { nanos: 1200000000i64 }) != ok { os.exit(32i32) }
    let (lit, lit_error) = testing.snapshot(&harness, a)
    if lit_error != ok { os.exit(23i32) }
    // Inside the selection: the fill and the repainted glyphs, never the plain
    // text colour; the caret after the third glyph is 2px `primary`.
    let body = style.text_style(&tokens, .Body)
    let advance = 0.6 * body.size
    let band = geometry.Rect { x: inline_bounds.x, y: inline_bounds.y, width: 3.0 * advance - 1.0, height: body.line_height }
    if count(lit, band, style.color(&tokens, .PrimaryContainer)) == 0usize { os.exit(24i32) }
    if count(lit, band, style.color(&tokens, .OnPrimaryContainer)) == 0usize { os.exit(25i32) }
    if count(lit, band, style.color(&tokens, .Text)) != 0usize { os.exit(26i32) }
    let caret_x = inline_bounds.x + 3.0 * advance + 1.0
    if !is_color(lit, px(caret_x, inline_bounds.y + body.line_height * 0.5), style.color(&tokens, .Primary)) { os.exit(27i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(28i32) }
    try io.print("ui content2 v2 ok\n")
    ret ok
}
