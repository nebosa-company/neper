// The v2 button (D942, widget plan P5-03, docs/ux/components/Button) under the
// light theme: each variant paints its container role -- filled `primary`, tonal
// `secondary-container`, elevated `surface-container-low` with a shadow under it,
// outlined its `outline` over the page, text nothing, danger `error` -- fully
// rounded at the control height; a disabled button's container is the surface's
// content colour at the disabled-container opacity; a button with an icon is the
// icon, the gap and 16px each side.

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

type Actions = struct { press: widget.Submit }

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

fn variant(a: *mem.Arena, t: *const control.Theme, actions: *const Actions, key: widget.Key, v: style.ControlVariant, enabled: bool) -> (widget.Node, err) {
    var options = control.button_options()
    options.variant = v
    options.enabled = enabled
    let (node, node_error) = control.button(a, key, t, "", &actions.press, options)
    ret (node, node_error)
}

fn build(a: *mem.Arena, t: *const control.Theme, actions: *const Actions, texture: scene.TextureId) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 9usize)
    if items_error != ok { ret (zero, items_error) }
    let (filled, e1) = variant(a, t, actions, 1u64, .Filled, true)
    let (tonal, e2) = variant(a, t, actions, 2u64, .Tonal, true)
    let (elevated, e3) = variant(a, t, actions, 3u64, .Elevated, true)
    let (outlined, e4) = variant(a, t, actions, 4u64, .Outlined, true)
    let (plain, e5) = variant(a, t, actions, 5u64, .Plain, true)
    let (danger, e6) = variant(a, t, actions, 6u64, .Danger, true)
    let (off, e7) = variant(a, t, actions, 7u64, .Filled, false)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (zero, e1) }
    let (icon, e8) = control.button_with_icon(a, 8u64, t, texture, "", &actions.press, control.button_options())
    if e8 != ok { ret (zero, e8) }
    items[0usize] = filled
    items[1usize] = tonal
    items[2usize] = elevated
    items[3usize] = outlined
    items[4usize] = plain
    items[5usize] = danger
    items[6usize] = off
    items[7usize] = icon
    var busy = control.button_options()
    busy.loading = true
    let (loading, e9) = control.button(a, 9u64, t, "", &actions.press, busy)
    if e9 != ok { ret (zero, e9) }
    items[8usize] = loading
    var page = style.defaults()
    page.width = style.Length { Px: 200.0 }
    page.height = style.Length { Px: 640.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 12.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..9usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 200usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn center_is(h: *testing.Harness, runtime: *widget.Runtime, shot: image.Image, key: widget.Key, c: paint.Color) -> bool {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    if !found { ret false }
    ret is_color(shot, at(b.x + b.width * 0.5, b.y + b.height * 0.5), c)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 96usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 512usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 200u32, 640u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    var pixels: [16]u8 = zero
    let (view, view_error) = image.make_const(pixels[..], 2u32, 2u32, 8usize, .Rgba8, .Premultiplied)
    if view_error != ok { os.exit(7i32) }
    let (texture, upload_error) = scene.upload_image(&renderer, view)
    if upload_error != ok { os.exit(8i32) }
    let (actions, actions_error) = mem.alloc[Actions](a, 1usize)
    if actions_error != ok { os.exit(9i32) }
    actions[0usize] = Actions { press: widget.Submit { ctx: mem.cast[*void](&actions[0usize]), invoke: on_press } }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(10i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, &actions[0usize], texture)
    if build_error != ok { os.exit(11i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(12i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(13i32) }
    let page = style.color(&tokens, .Background)
    // Every variant paints its container role.
    if !center_is(&harness, &runtime, shot, 1u64, style.color(&tokens, .Primary)) { os.exit(14i32) }
    if !center_is(&harness, &runtime, shot, 2u64, style.color(&tokens, .SecondaryContainer)) { os.exit(15i32) }
    if !center_is(&harness, &runtime, shot, 3u64, style.color(&tokens, .SurfaceContainerLow)) { os.exit(16i32) }
    if !center_is(&harness, &runtime, shot, 4u64, page) || !center_is(&harness, &runtime, shot, 5u64, page) { os.exit(17i32) }
    if !center_is(&harness, &runtime, shot, 6u64, style.color(&tokens, .Error)) { os.exit(18i32) }
    // Fully rounded at the control height: the corner is the page, the middle of
    // the left edge the fill.
    let (filled, has_filled) = widget.bounds_of(&runtime, testing.by_key(&harness, 1u64).element)
    if !has_filled { os.exit(47i32) }
    if !near(filled.height, tokens.metrics.control_height) { os.exit(19i32) }
    if !is_color(shot, at(filled.x + 1.0, filled.y + 1.0), page) || !is_color(shot, at(filled.x + 2.0, filled.y + filled.height * 0.5), style.color(&tokens, .Primary)) { os.exit(20i32) }
    // The elevated button casts its shadow below it; the outlined one draws its outline.
    let (raised, has_raised) = widget.bounds_of(&runtime, testing.by_key(&harness, 3u64).element)
    if !has_raised || !(shot.pixels[at(raised.x + raised.width * 0.5, raised.y + raised.height) + 1usize] < shot.pixels[at(raised.x + raised.width * 0.5, raised.y + raised.height + 4.0) + 1usize]) { os.exit(21i32) }
    let (lined, has_lined) = widget.bounds_of(&runtime, testing.by_key(&harness, 4u64).element)
    // (the outline is 1px on a circle here, so antialiased: darker than the page)
    if !has_lined || !(f32(shot.pixels[at(lined.x + lined.width * 0.5, lined.y) + 1usize]) < page.green * 255.0 - 40.0) { os.exit(22i32) }
    // Disabled: on-surface at the disabled-container opacity over the page.
    let ink = style.color(&tokens, .OnSurface)
    let o = tokens.states.disabled_container
    let dimmed = paint.rgba(page.red + (ink.red - page.red) * o, page.green + (ink.green - page.green) * o, page.blue + (ink.blue - page.blue) * o, 1.0)
    if !center_is(&harness, &runtime, shot, 7u64, dimmed) { os.exit(23i32) }
    // With no label: the 16px sides; with an icon, 16 + icon + gap + 16.
    if !near(filled.width, 2.0 * tokens.spacing.lg) { os.exit(24i32) }
    let (icon, has_icon) = widget.bounds_of(&runtime, testing.by_key(&harness, 8u64).element)
    if !has_icon || !near(icon.width, 2.0 * tokens.spacing.lg + tokens.sizes.icon_sm + tokens.spacing.sm) { os.exit(25i32) }
    // A loading button is busy in the tree and shows the ring's arc over its fill.
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(30i32) }
    var busy_seen = false
    var n = 0usize
    while n < tree.nodes.len {
        if tree.nodes[n].role == .Button && tree.nodes[n].state.busy { busy_seen = true }
        n += 1usize
    }
    if !busy_seen { os.exit(31i32) }
    let (spinning, has_spinning) = widget.bounds_of(&runtime, testing.by_key(&harness, 9u64).element)
    if !has_spinning || !near(spinning.height, tokens.metrics.control_height) { os.exit(32i32) }
    // At touch density the sides are 24, not the touch spacing.
    let touch = style.adapt(&tokens, style.Adaptation { size: .Expanded, capabilities: style.Capabilities { hover: false, fine_pointer: false, keyboard: false, touch: true, pen: false, resizable: false, multi_window: false, insets: zero }, profile: .Touch })
    let touch_theme = control.Theme { tokens: &touch, fonts: fonts, language: "", runtime: &runtime }
    let (root_2, build_2_error) = build(&frame, &touch_theme, &actions[0usize], texture)
    if build_2_error != ok { os.exit(26i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(27i32) }
    let (wide, has_wide) = widget.bounds_of(&runtime, testing.by_key(&harness, 1u64).element)
    if !has_wide || !near(wide.width, 48.0) || !near(wide.height, touch.metrics.control_height) { os.exit(28i32) }
    try io.print("ui button v2 ok\n")
    ret ok
}
