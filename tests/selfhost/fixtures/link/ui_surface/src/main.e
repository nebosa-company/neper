// `e.ui.control`'s surfaces (D814, widget plan P1-02) under the light theme: a card
// pads its content, rounds its corners, is bordered and casts a shadow below; a
// panel is the variant surface; a group box labels a bordered surface as a group;
// a divider is a hairline the tree leaves out; a badge is a status with its value;
// an avatar clips its image to a circle, its corners the page and its centre the
// image; a placeholder is busy. The frame's pixels say what was painted.

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

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn channel(shot: *const image.Image, x: usize, y: usize, c: usize) -> u8 {
    ret shot.pixels[(y * usize(shot.width) + x) * 4usize + c]
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 3.0 && e - v < 3.0
}

fn sized(width: f32, height: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: height }
    ret s
}

fn build(a: *mem.Arena, t: *const control.Theme, texture: scene.TextureId) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 3usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = widget.box(11u64, sized(20.0, 10.0), zero)
    inner[1usize] = widget.box(12u64, sized(20.0, 10.0), zero)
    inner[2usize] = widget.box(13u64, sized(20.0, 10.0), zero)
    let (items, items_error) = mem.alloc[widget.Node](a, 7usize)
    if items_error != ok { ret (zero, items_error) }
    let (a_card, card_error) = control.card(a, 1u64, t, inner[0usize..1usize])
    if card_error != ok { ret (zero, card_error) }
    items[0usize] = a_card
    let (a_panel, panel_error) = control.panel(a, 2u64, t, inner[1usize..2usize])
    if panel_error != ok { ret (zero, panel_error) }
    items[1usize] = a_panel
    let (a_group, group_error) = control.group_box(a, 3u64, t, "Set", inner[2usize..3usize])
    if group_error != ok { ret (zero, group_error) }
    items[2usize] = a_group
    let (a_divider, divider_error) = control.divider(a, 4u64, t, .Horizontal, 40.0)
    if divider_error != ok { ret (zero, divider_error) }
    items[3usize] = a_divider
    let (a_badge, badge_error) = control.badge(a, 5u64, t, "3")
    if badge_error != ok { ret (zero, badge_error) }
    items[4usize] = a_badge
    let (an_avatar, avatar_error) = control.avatar(a, 6u64, t, texture, 16.0, "me")
    if avatar_error != ok { ret (zero, avatar_error) }
    items[5usize] = an_avatar
    let (a_placeholder, placeholder_error) = control.placeholder(a, 7u64, t, 30.0, 10.0)
    if placeholder_error != ok { ret (zero, placeholder_error) }
    items[6usize] = a_placeholder
    var column = style.defaults()
    column.width = style.Length { Px: 100.0 }
    column.height = style.Length { Px: 200.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 6.0 }, column, items[0usize..7usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 64usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 100u32, 200u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    var pixels: [16]u8 = zero
    var i = 0usize
    while i < 4usize {
        pixels[i * 4usize + 1usize] = 255u8
        pixels[i * 4usize + 3usize] = 255u8
        i += 1usize
    }
    let (view, view_error) = image.make_const(pixels[..], 2u32, 2u32, 8usize, .Rgba8, .Premultiplied)
    if view_error != ok { os.exit(7i32) }
    let (texture, upload_error) = scene.upload_image(&renderer, view)
    if upload_error != ok { os.exit(8i32) }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(9i32) }
    var frame = mem.arena_from(frame_storage)
    let (root, build_error) = build(&frame, &theme, texture)
    if build_error != ok { os.exit(10i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(11i32) }
    // The card pads its 20 x 10 content by the medium spacing on each side.
    let (card_bounds, has_card) = widget.bounds_of(&runtime, testing.by_key(&harness, 1u64).element)
    if !has_card || !near(card_bounds.width, 20.0 + 2.0 * tokens.spacing.md) || !near(card_bounds.height, 10.0 + 2.0 * tokens.spacing.md) { os.exit(12i32) }
    let (panel_bounds, has_panel) = widget.bounds_of(&runtime, testing.by_key(&harness, 2u64).element)
    if !has_panel || !near(panel_bounds.width, card_bounds.width) { os.exit(13i32) }
    // The group box is a labelled group; the divider is not in the tree; the badge
    // is a status with its value; the avatar is an image; the placeholder is busy.
    if testing.by_label(&harness, "Set").count == 0usize { os.exit(14i32) }
    let divider = testing.by_key(&harness, 4u64)
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(15i32) }
    var busy_seen = false
    i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].id.slot == divider.element.slot { os.exit(16i32) }
        if tree.nodes[i].state.busy { busy_seen = true }
        i += 1usize
    }
    if !busy_seen { os.exit(17i32) }
    let (divider_bounds, has_divider) = widget.bounds_of(&runtime, divider.element)
    if !has_divider || !near(divider_bounds.width, 40.0) || !near(divider_bounds.height, tokens.borders.hairline) { os.exit(18i32) }
    let badge = testing.by_role(&harness, .Status)
    if badge.count != 1usize || testing.by_label(&harness, "3").count == 0usize { os.exit(19i32) }
    if testing.by_label(&harness, "me").count != 1usize { os.exit(20i32) }
    // The pixels: the card's inside is the surface colour and its shadow lies two
    // pixels below it; the panel is the variant surface; the avatar's corner is the
    // page and its centre the image.
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(21i32) }
    let surface_color = style.color(&tokens, .Surface)
    let variant_color = style.color(&tokens, .SurfaceVariant)
    let cx = usize(card_bounds.x + card_bounds.width * 0.5)
    let cy = usize(card_bounds.y + card_bounds.height * 0.5)
    if !close_to(channel(&shot, cx, cy, 0usize), surface_color.red) || !close_to(channel(&shot, cx, cy, 3usize), 1.0) { os.exit(22i32) }
    let below = usize(card_bounds.y + card_bounds.height) + 1usize
    if channel(&shot, cx, below, 3usize) == 0u8 || channel(&shot, cx, below, 3usize) == 255u8 { os.exit(23i32) }
    if channel(&shot, cx, below + 4usize, 3usize) != 0u8 { os.exit(24i32) }
    let px = usize(panel_bounds.x + 2.0)
    let py = usize(panel_bounds.y + panel_bounds.height * 0.5)
    if !close_to(channel(&shot, px, py, 0usize), variant_color.red) { os.exit(25i32) }
    let (avatar_bounds, has_avatar) = widget.bounds_of(&runtime, testing.by_key(&harness, 6u64).element)
    if !has_avatar || !near(avatar_bounds.width, 16.0) { os.exit(26i32) }
    let ax = usize(avatar_bounds.x)
    let ay = usize(avatar_bounds.y)
    if channel(&shot, ax, ay, 3usize) != 0u8 { os.exit(27i32) }
    if channel(&shot, ax + 8usize, ay + 8usize, 1usize) != 255u8 || channel(&shot, ax + 8usize, ay + 8usize, 0usize) != 0u8 { os.exit(28i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(29i32) }
    try io.print("ui surface ok\n")
    ret ok
}
