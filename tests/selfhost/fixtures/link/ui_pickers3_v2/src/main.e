// The v2 colour field and font panel (D961, widget plan P5-06, docs/ux/components)
// under the light theme at pointer density. The colour field is the 40 read-only
// box; open, its panel stands 4 below on `surface-container-high`, 296 wide with 16
// padding and 16 between blocks: the 150 saturation and brightness area painted as
// the colour model says with its 20 ringed thumb at the colour, the 12 hue strip,
// the 12 opacity strip over the 5px checkerboard, the 32 hex field and 72 opacity
// readout 8 apart, and 32 swatches 8 apart, the chosen one ringed 2 outside, a
// transparent one checkered; presses on the area, the strip and a swatch reach the
// change. The font panel is `surface-container-low` with 16 padding: the 260
// family list on `surface`, its chosen row `secondary-container`, the dense 40
// style picker and the 104 x 40 size spin box, and the preview at least 88 tall in
// its 1px `outline-variant` edge on `surface`; a 40 search field with its mark
// stands 16 above the family list. The hex forms read and write.

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
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

type Store = struct { press: widget.Submit, open: bool, colour: paint.Color, colours: u32, family: usize, families: u32, swatches: [6]paint.Color, names: [4]str, faces: [3]str, hex: [16]u8, size: [8]u8, query: [16]u8 }

fn on_press(ctx: *void) -> err {
    ret ok
}

fn on_colour(ctx: *void, value: paint.Color) -> err {
    let s = mem.cast[*Store](ctx)
    s.colour = value
    s.colours += 1u32
    ret ok
}

fn on_family(ctx: *void, value: usize) -> err {
    let s = mem.cast[*Store](ctx)
    s.family = value
    s.families += 1u32
    ret ok
}

fn on_index(ctx: *void, value: usize) -> err {
    ret ok
}

fn on_size(ctx: *void, value: i64) -> err {
    ret ok
}

fn on_text(ctx: *void, value: str) -> err {
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

fn copper() -> paint.Color {
    ret paint.rgba(0.58, 0.29, 0.14, 1.0)
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let pick = widget.Change[paint.Color] { ctx: mem.cast[*void](s), invoke: on_colour }
    let typed = widget.Change[str] { ctx: mem.cast[*void](s), invoke: on_text }
    let (tint, e1) = overlay.color_field(a, 500u64, t, "Accent colour", copper(), true, pick, s.open, &s.press, s.swatches[0usize..6usize], s.hex[0usize..16usize], 7usize, typed, 296.0)
    if e1 != ok { ret (zero, e1) }
    let (font, e2) = control.font_panel(a, 600u64, t, "Editor font", s.names[0usize..4usize], 1usize, s.faces[0usize..3usize], 0usize, false, &s.press, 13i64, s.size[0usize..8usize], "fn main() {}", widget.Change[usize] { ctx: mem.cast[*void](s), invoke: on_family }, widget.Change[usize] { ctx: mem.cast[*void](s), invoke: on_index }, widget.Change[i64] { ctx: mem.cast[*void](s), invoke: on_size }, typed, s.query[0usize..16usize], 0usize, typed, 5u32, 520.0)
    if e2 != ok { ret (zero, e2) }
    let (columns, columns_error) = mem.alloc[widget.Node](a, 3usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[2usize] = tint
    columns[0usize] = widget.box(0u64, control.sized_style(296.0, 40.0), columns[2usize..3usize])
    columns[1usize] = font
    var page = style.defaults()
    page.width = style.Length { Px: 900.0 }
    page.height = style.Length { Px: 480.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 24.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 24.0 }, page, columns[0usize..2usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 900usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

// An antialiased or interpolated colour: within 12.
fn roughly(shot: image.Image, i: usize, c: paint.Color) -> bool {
    var k = 0usize
    while k < 3usize {
        var e = c.red
        if k == 1usize { e = c.green }
        if k == 2usize { e = c.blue }
        let d = f32(shot.pixels[i + k]) - e * 255.0
        if d > 12.0 || d < -12.0 { ret false }
        k += 1usize
    }
    ret true
}

fn mix(from: paint.Color, to: paint.Color, f: f32) -> paint.Color {
    ret paint.rgba(from.red + (to.red - from.red) * f, from.green + (to.green - from.green) * f, from.blue + (to.blue - from.blue) * f, 1.0)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn same(a: []const u8, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn near_color(x: paint.Color, y: paint.Color) -> bool {
    let d: f32 = 0.02
    ret x.red - y.red < d && y.red - x.red < d && x.green - y.green < d && y.green - x.green < d && x.blue - y.blue < d && y.blue - x.blue < d && x.alpha - y.alpha < d && y.alpha - x.alpha < d
}

fn main(a: *mem.Arena, args: []str) -> err {
    // The hex forms: written upper case with "#", read from 3, 6 or 8 digits.
    var written: [16]u8 = zero
    let n1 = overlay.write_hex(written[0usize..16usize], paint.rgba(148.0 / 255.0, 74.0 / 255.0, 35.0 / 255.0, 1.0))
    if !same(written[0usize..n1], "#944A23") { os.exit(40i32) }
    let n2 = overlay.write_hex(written[0usize..16usize], paint.rgba(1.0, 1.0, 1.0, 0.0))
    if !same(written[0usize..n2], "#FFFFFF00") { os.exit(41i32) }
    let (short, short_ok) = overlay.read_hex("f80")
    let (long, long_ok) = overlay.read_hex("#944a23")
    let (clear, clear_ok) = overlay.read_hex("00000080")
    let (bad, bad_ok) = overlay.read_hex("#94A2")
    if !short_ok || !long_ok || !clear_ok || bad_ok { os.exit(42i32) }
    if !near_color(short, paint.rgba(1.0, 0.533, 0.0, 1.0)) || !near_color(long, paint.rgba(0.580, 0.290, 0.137, 1.0)) || !near_color(clear, paint.rgba(0.0, 0.0, 0.0, 0.502)) { os.exit(43i32) }
    let (hue, saturation, bright) = overlay.hsv_of(copper())
    if !near_color(overlay.hsv_color(hue, saturation, bright, 1.0), copper()) || !near_color(overlay.hsv_color(180.0, 1.0, 1.0, 1.0), paint.rgba(0.0, 1.0, 1.0, 1.0)) { os.exit(44i32) }
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 1024usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 24u16, max_commands: 8192usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 900u32, 480u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    s.press = widget.Submit { ctx: mem.cast[*void](s), invoke: on_press }
    s.open = true
    s.swatches[0usize] = paint.rgba(0.95, 0.95, 0.9, 1.0)
    s.swatches[1usize] = copper()
    s.swatches[2usize] = paint.rgba(0.2, 0.4, 0.6, 1.0)
    s.swatches[3usize] = paint.rgba(0.1, 0.5, 0.3, 1.0)
    s.swatches[4usize] = paint.rgba(0.6, 0.2, 0.5, 1.0)
    s.swatches[5usize] = paint.rgba(0.0, 0.0, 0.0, 0.0)
    s.names[0usize] = "Cascadia Code"
    s.names[1usize] = "Consolas"
    s.names[2usize] = "Fira Code"
    s.names[3usize] = "JetBrains Mono"
    s.faces[0usize] = "Regular"
    s.faces[1usize] = "Italic"
    s.faces[2usize] = "Bold"
    let (frame_storage, storage_error) = mem.alloc[u8](a, 4194304usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, s)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let outline = style.color(&tokens, .Outline)
    let lowest = style.color(&tokens, .SurfaceContainerLowest)
    let ink = style.color(&tokens, .OnSurface)
    let high = style.color(&tokens, .SurfaceContainerHigh)
    // The trigger 40 tall; the panel 4 below it, 296 wide on the high container.
    let (head, has_head) = bounds(&harness, &runtime, 500u64)
    let (panel, has_panel) = bounds(&harness, &runtime, 507u64)
    if !has_head || !has_panel || !near(head.height, 40.0) || !near(panel.width, 296.0) || !near(panel.x, head.x) || !near(panel.y, head.y + 44.0) { os.exit(12i32) }
    if !is_color(shot, at(panel.x + 148.0, panel.y + 6.0), high) { os.exit(13i32) }
    // The area: 16 in, 264 by 150, painted as the colour model says away from the
    // thumb; the thumb at the colour, a disc of it inside the lowest ring.
    let (area, has_area) = bounds(&harness, &runtime, 502u64)
    if !has_area || !near(area.x, panel.x + 16.0) || !near(area.y, panel.y + 16.0) || !near(area.width, 264.0) || !near(area.height, 150.0) { os.exit(14i32) }
    if !roughly(shot, at(area.x + 60.0, area.y + 120.0), overlay.hsv_color(hue, 60.5 / 264.0, 1.0 - 120.5 / 150.0, 1.0)) || !roughly(shot, at(area.x + 240.0, area.y + 20.0), overlay.hsv_color(hue, 240.5 / 264.0, 1.0 - 20.5 / 150.0, 1.0)) || !roughly(shot, at(area.x + 132.0, area.y + 2.0), overlay.hsv_color(hue, 132.5 / 264.0, 1.0 - 2.5 / 150.0, 1.0)) { os.exit(15i32) }
    let tx = area.x + saturation * 264.0
    let ty = area.y + (1.0 - bright) * 150.0
    if !roughly(shot, at(tx, ty), copper()) || !roughly(shot, at(tx + 8.0, ty), lowest) { os.exit(16i32) }
    // The hue strip: 12 tall, 16 below, cyan at the middle, its hollow thumb's lowest ring.
    let (hues, has_hues) = bounds(&harness, &runtime, 503u64)
    if !has_hues || !near(hues.height, 12.0) || !near(hues.width, 264.0) || !near(hues.y, area.y + 166.0) { os.exit(17i32) }
    if !roughly(shot, at(hues.x + 132.0, hues.y + 6.0), overlay.hsv_color(132.5 / 264.0 * 360.0, 1.0, 1.0, 1.0)) || !roughly(shot, at(hues.x + hue / 360.0 * 264.0 - 8.0, hues.y + 6.0), lowest) { os.exit(18i32) }
    // The opacity strip: 16 below, the colour fading in over the checkerboard.
    let (fades, has_fades) = bounds(&harness, &runtime, 504u64)
    if !has_fades || !near(fades.height, 12.0) || !near(fades.y, hues.y + 28.0) { os.exit(19i32) }
    let dark = style.color(&tokens, .OutlineVariant)
    if !roughly(shot, at(fades.x + 7.0, fades.y + 6.0), mix(dark, copper(), 7.5 / 264.0)) || !roughly(shot, at(fades.x + 12.0, fades.y + 6.0), mix(lowest, copper(), 12.5 / 264.0)) || !roughly(shot, at(fades.x + 132.0, fades.y + 6.0), mix(lowest, copper(), 132.5 / 264.0)) { os.exit(20i32) }
    // (D1232) Keys on the focused spectrum and strips: Right is 1% more
    // saturation, Shift+Up 10% more brightness; on the hue strip Page Up is 10
    // degrees and End the last; on the opacity strip Home is clear and Left 1% less.
    var shift_held: input.Modifiers = zero
    shift_held.shift = true
    let colours_before = s.colours
    if widget.focus(&runtime, testing.by_key(&harness, 502u64).element) != ok || testing.press_key(&harness, 39u32, zero) != ok { os.exit(49i32) }
    let (right_hue, right_saturation, right_bright) = overlay.hsv_of(s.colour)
    if s.colours != colours_before + 1u32 || !(right_saturation > saturation + 0.005 && right_saturation < saturation + 0.015) || !(right_bright > bright - 0.005 && right_bright < bright + 0.005) { os.exit(50i32) }
    if testing.press_key(&harness, 38u32, shift_held) != ok { os.exit(51i32) }
    let (_, _, up_bright) = overlay.hsv_of(s.colour)
    if !(up_bright > bright + 0.095 && up_bright < bright + 0.105) { os.exit(52i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 503u64).element) != ok || testing.press_key(&harness, 33u32, zero) != ok { os.exit(53i32) }
    let (paged_hue, _, _) = overlay.hsv_of(s.colour)
    if !(paged_hue > hue + 9.5 && paged_hue < hue + 10.5) { os.exit(54i32) }
    if testing.press_key(&harness, 35u32, zero) != ok { os.exit(55i32) }
    let (end_hue, _, _) = overlay.hsv_of(s.colour)
    if !(end_hue > 358.0) { os.exit(56i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 504u64).element) != ok || testing.press_key(&harness, 36u32, zero) != ok || s.colour.alpha > 0.001 { os.exit(57i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || !(s.colour.alpha > 0.985 && s.colour.alpha < 0.995) { os.exit(58i32) }
    if right_hue < 0.0 { os.exit(59i32) }
    s.colours = colours_before
    s.colour = copper()
    // The channel row: the 184 x 32 hex field (its editor 16 in) and the 72
    // readout 8 after it, 16 below.
    let (hexed, has_hexed) = bounds(&harness, &runtime, 505u64)
    let (readout, has_readout) = bounds(&harness, &runtime, 506u64)
    if !has_hexed || !has_readout || !near(hexed.x, area.x + 16.0) || !near(hexed.width, 152.0) || !near(readout.width, 72.0) || !near(readout.height, 32.0) || !near(readout.x, area.x + 192.0) || !near(readout.y, fades.y + 28.0) || !near(hexed.y + hexed.height * 0.5, readout.y + 16.0) { os.exit(21i32) }
    if !roughly(shot, at(area.x + 0.5, readout.y + 16.0), outline) || !roughly(shot, at(area.x + 183.5, readout.y + 16.0), outline) { os.exit(47i32) }
    if !roughly(shot, at(readout.x + 0.5, readout.y + 16.0), outline) { os.exit(22i32) }
    // The swatches: 32, 8 apart; the chosen copper ringed 2 outside in on-surface,
    // the light one's hairline, the transparent one checkered.
    let (first, has_first) = bounds(&harness, &runtime, 508u64)
    let (second, has_second) = bounds(&harness, &runtime, 509u64)
    let (none_swatch, has_none) = bounds(&harness, &runtime, 513u64)
    if !has_first || !has_second || !has_none || !near(first.width, 32.0) || !near(first.height, 32.0) || !near(second.x - first.x, 40.0) || !near(first.x, panel.x + 16.0) { os.exit(23i32) }
    if !roughly(shot, at(second.x + 16.0 + 18.0, second.y + 16.0), ink) || !is_color(shot, at(first.x + 16.0 + 18.0, first.y + 16.0), high) || !roughly(shot, at(second.x + 16.0, second.y + 16.0), copper()) { os.exit(24i32) }
    if !roughly(shot, at(first.x + 16.0 + 15.0, first.y + 16.0), mix(s.swatches[0usize], ink, 0.16)) || !roughly(shot, at(first.x + 16.0 + 10.0, first.y + 16.0), s.swatches[0usize]) { os.exit(25i32) }
    if !roughly(shot, at(none_swatch.x + 16.0, none_swatch.y + 16.0), dark) || !roughly(shot, at(none_swatch.x + 21.0, none_swatch.y + 16.0), lowest) { os.exit(26i32) }
    // A press on the area, the hue strip and a swatch each reach the change.
    if testing.tap(&harness, area.x + 132.0, area.y + 75.0) != ok { os.exit(27i32) }
    if s.colours != 1u32 || !near_color(s.colour, overlay.hsv_color(hue, 0.5, 0.5, 1.0)) { os.exit(28i32) }
    if testing.tap(&harness, hues.x + 132.0, hues.y + 6.0) != ok { os.exit(29i32) }
    if s.colours != 2u32 || !near_color(s.colour, overlay.hsv_color(180.0, saturation, bright, 1.0)) { os.exit(30i32) }
    if testing.tap(&harness, second.x + 56.0, second.y + 16.0) != ok { os.exit(31i32) }
    if s.colours != 3u32 || !near_color(s.colour, s.swatches[2usize]) { os.exit(32i32) }
    // The font panel: the low container; the 40 x 260 search field 16 in, its query
    // 42 in after the mark; the family list 16 + 4 under it on surface with its 40
    // rows, the chosen one secondary-container.
    let low = style.color(&tokens, .SurfaceContainerLow)
    let page_color = style.color(&tokens, .Background)
    let (fonts_box, has_fonts) = bounds(&harness, &runtime, 600u64)
    let (list, has_list) = bounds(&harness, &runtime, 601u64)
    let (row0, has_row0) = bounds(&harness, &runtime, 602u64)
    let (row1, has_row1) = bounds(&harness, &runtime, 603u64)
    let (query, has_query) = bounds(&harness, &runtime, 685u64)
    if !has_query || !near(query.x, fonts_box.x + 16.0 + 42.0) || !roughly(shot, at(fonts_box.x + 16.5, fonts_box.y + 36.0), outline) || !roughly(shot, at(fonts_box.x + 275.5, fonts_box.y + 36.0), outline) { os.exit(48i32) }
    if !has_fonts || !has_list || !near(list.y, fonts_box.y + 16.0 + 40.0 + 16.0 + 4.0) || !has_row0 || !has_row1 || !near(fonts_box.width, 520.0) || !near(list.width, 260.0) || !near(list.x, fonts_box.x + 16.0) || !near(list.height, 208.0) || !near(row0.height, 40.0) || !near(row1.y, row0.y + 40.0) { os.exit(33i32) }
    if !is_color(shot, at(fonts_box.x + 284.0, fonts_box.y + 100.0), low) || !is_color(shot, at(row0.x + 8.0, row0.y + 20.0), page_color) || !is_color(shot, at(row1.x + 8.0, row1.y + 20.0), style.color(&tokens, .SecondaryContainer)) { os.exit(34i32) }
    // The style picker 40 tall and the size spin box 104 x 40 (its 36 arrow pair
    // centred 8 from the end), in the right column.
    let (faces, has_faces) = bounds(&harness, &runtime, 664u64)
    let (sized, has_sized) = bounds(&harness, &runtime, 683u64)
    let (up, has_up) = bounds(&harness, &runtime, 682u64)
    if !has_faces || !has_sized || !near(faces.height, 40.0) || !near(faces.x, fonts_box.x + 292.0) || !near(sized.width, 104.0) || !has_up || !near(up.x, sized.x + 104.0 - 32.0) || !near(up.y, sized.y + 2.0) || !roughly(shot, at(sized.x + 0.5, sized.y + 20.0), outline) { os.exit(35i32) }
    // The preview: 212 wide, at least 88 tall, the 1px outline-variant edge on surface.
    let (preview, has_preview) = bounds(&harness, &runtime, 684u64)
    if !has_preview || !near(preview.width, 212.0) || preview.height < 87.99 || !near(preview.x, faces.x) { os.exit(36i32) }
    if !roughly(shot, at(preview.x + 0.5, preview.y + 44.0), dark) || !is_color(shot, at(preview.x + 4.0, preview.y + 44.0), page_color) { os.exit(37i32) }
    // Closed, a press on the third family picks it.
    s.open = false
    f = mem.arena_from(frame_storage)
    let (closed_root, closed_error) = build(&f, &theme, s)
    if closed_error != ok { os.exit(45i32) }
    if testing.pump(&harness, closed_root, time.Instant { nanos: 2000000000i64 }) != ok { os.exit(46i32) }
    if testing.tap(&harness, row1.x + 100.0, row1.y + 60.0) != ok { os.exit(38i32) }
    if s.families != 1u32 || s.family != 2usize { os.exit(39i32) }
    try io.print("ui pickers3 v2 ok\n")
    ret ok
}
