// The v2 action controls (D944, widget plan P5-03, docs/ux/components) under the
// light theme at pointer density: an icon button is a circle the control height
// across with its 18px icon centred; a toggle button on takes the fill and squarer
// corners; a hovered link lays the primary wash behind its label; a FAB is 56 on
// the primary container with its 16px corners and shadow, an extended one at least
// 80 wide; the action row puts 8 between its buttons, the toolbar 4 on its
// container; the speed dial's items are 56-tall pills over the primary close circle.

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
use e.ui.layout as ui_layout
use e.ui.navigation
use e.ui.style
use e.ui.testing
use e.ui.widget

type Store = struct { press: widget.Submit, items: [2]navigation.Action, dial: [2]widget.Submit, labels: [2]str, texture: scene.TextureId }


fn on_press(ctx: *void) -> err {
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 3.0 && e - v < 3.0
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *const Store, open: bool) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 9usize)
    if items_error != ok { ret (zero, items_error) }
    var plain = control.button_options()
    plain.variant = .Plain
    let (icon, e1) = control.icon_button(a, 1u64, t, s.texture, "Settings", &s.press, plain)
    let (toggled, e2) = control.toggle_button(a, 2u64, t, "", true, &s.press, control.button_options())
    let (link, e3) = control.link(a, 3u64, t, "Docs", &s.press)
    let (fab, e4) = control.fab(a, 4u64, t, s.texture, "New", &s.press, .Default)
    let (wide, e5) = control.fab(a, 5u64, t, s.texture, "", &s.press, .Extended)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (zero, e1) }
    let (row, e6) = navigation.action_row(a, 10u64, t, s.items[0usize..2usize], .Filled)
    let (bar, e7) = navigation.toolbar(a, 20u64, t, "Format", s.items[0usize..2usize])
    let (dial, e8) = control.speed_dial(a, 30u64, t, "", s.labels[0usize..2usize], s.dial[0usize..2usize], open, &s.press)
    if e6 != ok || e7 != ok || e8 != ok { ret (zero, e6) }
    items[0usize] = icon
    items[1usize] = toggled
    items[2usize] = link
    items[3usize] = fab
    items[4usize] = wide
    items[5usize] = row
    items[6usize] = bar
    items[7usize] = dial
    let (split, e9) = control.split_button(a, 40u64, t, "", &s.press, false, &s.press)
    if e9 != ok { ret (zero, e9) }
    items[8usize] = split
    var page = style.defaults()
    page.width = style.Length { Px: 240.0 }
    page.height = style.Length { Px: 760.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 12.0 }
    page.padding = style.EdgeLengths { left: pad, top: style.Length { Px: 140.0 }, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..9usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 240usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn over(page: paint.Color, ink: paint.Color, o: f32) -> paint.Color {
    ret paint.rgba(page.red + (ink.red - page.red) * o, page.green + (ink.green - page.green) * o, page.blue + (ink.blue - page.blue) * o, 1.0)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn frame(h: *testing.Harness, a: *mem.Arena, f: *mem.Arena, t: *const control.Theme, s: *const Store, open: bool) -> (image.Image, err) {
    let (root, build_error) = build(f, t, s, open)
    if build_error != ok { ret (zero, build_error) }
    let pumped = testing.pump(h, root, time.Instant { nanos: 1000000000i64 })
    if pumped != ok { ret (zero, pumped) }
    let (shot, shot_error) = testing.snapshot(h, a)
    ret (shot, shot_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 160usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 12u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 240u32, 760u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    var pixels: [16]u8 = zero
    let (view, view_error) = image.make_const(pixels[..], 2u32, 2u32, 8usize, .Rgba8, .Premultiplied)
    if view_error != ok { os.exit(7i32) }
    let (texture, upload_error) = scene.upload_image(&renderer, view)
    if upload_error != ok { os.exit(8i32) }
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(9i32) }
    var store: Store = zero
    stores[0usize] = store
    let ctx = mem.cast[*void](&stores[0usize])
    let press = widget.Submit { ctx: ctx, invoke: on_press }
    stores[0usize].press = press
    stores[0usize].items[0usize] = navigation.Action { label: "", action: press, icon: zero, enabled: true }
    stores[0usize].items[1usize] = navigation.Action { label: "", action: press, icon: zero, enabled: true }
    stores[0usize].dial[0usize] = press
    stores[0usize].dial[1usize] = press
    stores[0usize].labels[0usize] = ""
    stores[0usize].labels[1usize] = ""
    stores[0usize].texture = texture
    let (frame_storage, storage_error) = mem.alloc[u8](a, 524288usize)
    if storage_error != ok { os.exit(10i32) }
    var f = mem.arena_from(frame_storage)
    let (shot, shot_error) = frame(&harness, a, &f, &theme, &stores[0usize], false)
    if shot_error != ok { os.exit(11i32) }
    let page = style.color(&tokens, .Background)
    let h32 = tokens.metrics.control_height
    // The icon button: a circle the control height across, the icon centred.
    let (icon, has_icon) = bounds(&harness, &runtime, 1u64)
    if !has_icon || !near(icon.width, h32) || !near(icon.height, h32) { os.exit(12i32) }
    // The toggle button on: the primary fill with `radius-sm` corners, so the point
    // 3px in from the corner is filled where a full rounding would leave the page.
    let (toggled, has_toggled) = bounds(&harness, &runtime, 2u64)
    if !has_toggled || !is_color(shot, at(toggled.x + 3.0, toggled.y + 3.0), style.color(&tokens, .Primary)) { os.exit(13i32) }
    // The FAB: 56 across on the primary container, its 16px corner leaving the page,
    // its shadow darker than the page below it.
    let (fab, has_fab) = bounds(&harness, &runtime, 4u64)
    if !has_fab || !near(fab.width, tokens.sizes.control_xl) || !near(fab.height, tokens.sizes.control_xl) { os.exit(14i32) }
    if !is_color(shot, at(fab.x + fab.width * 0.5, fab.y + 6.0), style.color(&tokens, .PrimaryContainer)) || !is_color(shot, at(fab.x + 1.0, fab.y + 1.0), page) { os.exit(15i32) }
    if !(shot.pixels[at(fab.x + fab.width * 0.5, fab.y + fab.height + 1.0) + 1usize] < shot.pixels[at(fab.x + fab.width * 0.5, fab.y + fab.height + 8.0) + 1usize]) { os.exit(16i32) }
    let (wide, has_wide) = bounds(&harness, &runtime, 5u64)
    if !has_wide || wide.width < 80.0 || !near(wide.height, tokens.sizes.control_xl) { os.exit(17i32) }
    // The action row: 8 between its buttons.
    let (first, has_first) = bounds(&harness, &runtime, 10u64)
    let (second, has_second) = bounds(&harness, &runtime, 11u64)
    if !has_first || !has_second || !near(second.x - (first.x + first.width), 8.0) { os.exit(18i32) }
    // The toolbar: its container role, 4 between its items and 4 in.
    let (tool_a, has_tool_a) = bounds(&harness, &runtime, 21u64)
    let (tool_b, has_tool_b) = bounds(&harness, &runtime, 22u64)
    if !has_tool_a || !has_tool_b || !near(tool_b.x - (tool_a.x + tool_a.width), 4.0) { os.exit(19i32) }
    if !is_color(shot, at(tool_a.x - 2.0, tool_a.y + tool_a.height * 0.5), style.color(&tokens, .SurfaceContainer)) { os.exit(20i32) }
    // The speed dial closed: the FAB-shaped head on the primary container.
    let (head, has_head) = bounds(&harness, &runtime, 30u64)
    if !has_head || !near(head.height, tokens.sizes.control_xl) || !is_color(shot, at(head.x + head.width * 0.5, head.y + 6.0), style.color(&tokens, .PrimaryContainer)) { os.exit(21i32) }
    // The split button: 2 between its halves, the trailing one 36 wide; each half
    // round at its outer end (the corner pixel is the page) and nearly square at
    // the inner one (the pixel 2 in from the corner is filled).
    let (lead, has_lead) = bounds(&harness, &runtime, 40u64)
    let (trail, has_trail) = bounds(&harness, &runtime, 41u64)
    if !has_lead || !has_trail || !near(trail.x - (lead.x + lead.width), 2.0) || !near(trail.width, 36.0) { os.exit(29i32) }
    let primary = style.color(&tokens, .Primary)
    if !is_color(shot, at(lead.x + 1.0, lead.y + 1.0), page) || !is_color(shot, at(lead.x + lead.width - 2.0, lead.y + 2.0), primary) { os.exit(30i32) }
    if !is_color(shot, at(trail.x + 2.0, trail.y + 2.0), primary) || !is_color(shot, at(trail.x + trail.width - 1.0, trail.y + 1.0), page) { os.exit(31i32) }
    // The link, hovered: the primary wash at the hover opacity behind it.
    let (link, has_link) = bounds(&harness, &runtime, 3u64)
    if !has_link { os.exit(22i32) }
    if testing.hover(&harness, link.x + link.width * 0.5, link.y + link.height * 0.5) != ok { os.exit(23i32) }
    let (hovered, hovered_error) = frame(&harness, a, &f, &theme, &stores[0usize], false)
    if hovered_error != ok { os.exit(24i32) }
    if !is_color(hovered, at(link.x + 2.0, link.y + 2.0), over(page, style.color(&tokens, .Primary), tokens.states.hover)) { os.exit(25i32) }
    // The speed dial open: its items are 56-tall pills, the head the primary circle.
    let (opened, opened_error) = frame(&harness, a, &f, &theme, &stores[0usize], true)
    if opened_error != ok { os.exit(26i32) }
    let (item, has_item) = bounds(&harness, &runtime, 32u64)
    if !has_item || !near(item.height, tokens.sizes.control_xl) || !(item.y + item.height < head.y) { os.exit(27i32) }
    if !is_color(opened, at(head.x + head.width * 0.5, head.y + head.height * 0.5), style.color(&tokens, .Primary)) { os.exit(28i32) }
    try io.print("ui actions v2 ok\n")
    ret ok
}
