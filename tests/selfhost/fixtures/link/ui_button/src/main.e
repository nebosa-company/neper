// `e.ui.control`'s button family (D818, widget plan P1-06) under the light theme: a
// filled button fires its action on a tap, on Enter and on Space when focused, and
// paints the primary colour at rest and a hovered look under the pointer; a disabled
// button neither fires nor takes the focus and is disabled in the tree; a toggle
// button shows its selection; an icon button is a button with a picture; a link is a
// link. Buttons stand at the theme's control height.

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
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { presses: usize, toggles: usize, icons: usize, links: usize, disabled: usize, selected: bool }

fn on_press(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.presses += 1usize
    ret ok
}

fn on_toggle(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.toggles += 1usize
    log.selected = !log.selected
    ret ok
}

fn on_icon(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.icons += 1usize
    ret ok
}

fn on_link(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.links += 1usize
    ret ok
}

fn on_disabled(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.disabled += 1usize
    ret ok
}

type Actions = struct { press: widget.Submit, toggle: widget.Submit, icon: widget.Submit, link: widget.Submit, disabled: widget.Submit }

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 3.0 && e - v < 3.0
}

fn build(a: *mem.Arena, t: *const control.Theme, actions: *const Actions, selected: bool, texture: scene.TextureId) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 5usize)
    if items_error != ok { ret (zero, items_error) }
    let (save, save_error) = control.button(a, 1u64, t, "Save", &actions.press, control.button_options())
    if save_error != ok { ret (zero, save_error) }
    items[0usize] = save
    var off = control.button_options()
    off.enabled = false
    let (never, never_error) = control.button(a, 2u64, t, "Never", &actions.disabled, off)
    if never_error != ok { ret (zero, never_error) }
    items[1usize] = never
    var outlined = control.button_options()
    outlined.variant = .Outlined
    let (bold, bold_error) = control.toggle_button(a, 3u64, t, "Bold", selected, &actions.toggle, outlined)
    if bold_error != ok { ret (zero, bold_error) }
    items[2usize] = bold
    let (star, star_error) = control.icon_button(a, 4u64, t, texture, "star", &actions.icon, control.button_options())
    if star_error != ok { ret (zero, star_error) }
    items[3usize] = star
    let (more, more_error) = control.link(a, 5u64, t, "more", &actions.link)
    if more_error != ok { ret (zero, more_error) }
    items[4usize] = more
    var column = style.defaults()
    column.width = style.Length { Px: 120.0 }
    column.height = style.Length { Px: 240.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, column, items[0usize..5usize]), ok)
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
    let (h, harness_error) = testing.harness(a, &runtime, 120u32, 240u32, 1.0)
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
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(9i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (actions, actions_error) = mem.alloc[Actions](a, 1usize)
    if actions_error != ok { os.exit(10i32) }
    actions[0usize] = Actions { press: widget.Submit { ctx: ctx, invoke: on_press }, toggle: widget.Submit { ctx: ctx, invoke: on_toggle }, icon: widget.Submit { ctx: ctx, invoke: on_icon }, link: widget.Submit { ctx: ctx, invoke: on_link }, disabled: widget.Submit { ctx: ctx, invoke: on_disabled } }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(11i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, &actions[0usize], logs[0usize].selected, texture)
    if build_error != ok { os.exit(12i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(13i32) }
    // Three buttons and a link in the tree; the disabled one says so.
    if testing.by_role(&harness, .Button).count != 4usize || testing.by_role(&harness, .Link).count != 1usize { os.exit(14i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(15i32) }
    var disabled_seen = false
    i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .Button && tree.nodes[i].state.disabled { disabled_seen = true }
        i += 1usize
    }
    if !disabled_seen { os.exit(16i32) }
    // The button stands at the control height and paints the primary colour.
    let (save_bounds, has_save) = widget.bounds_of(&runtime, testing.by_key(&harness, 1u64).element)
    if !has_save || !near(save_bounds.height, tokens.metrics.control_height) { os.exit(17i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(18i32) }
    let sx = usize(save_bounds.x + save_bounds.width * 0.5)
    let sy = usize(save_bounds.y + save_bounds.height * 0.5)
    let primary = style.color(&tokens, .Primary)
    if !close_to(shot.pixels[(sy * 120usize + sx) * 4usize], primary.red) || !close_to(shot.pixels[(sy * 120usize + sx) * 4usize + 2usize], primary.blue) { os.exit(19i32) }
    // A tap presses it and focuses it; Enter and Space press it again.
    if testing.tap(&harness, f32(sx), f32(sy)) != ok || logs[0usize].presses != 1usize { os.exit(20i32) }
    let (focus_now, has_focus) = testing.focused(&harness)
    if !has_focus || focus_now.slot != testing.by_key(&harness, 1u64).element.slot { os.exit(21i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].presses != 2usize { os.exit(22i32) }
    if testing.press_key(&harness, 32u32, zero) != ok || logs[0usize].presses != 3usize { os.exit(23i32) }
    // Hovered, the next frame paints the hovered look: the white label over the
    // primary fill at the hover opacity, lighter than at rest (D940).
    if testing.hover(&harness, f32(sx), f32(sy)) != ok { os.exit(24i32) }
    let (root_2, build_2_error) = build(&frame, &theme, &actions[0usize], logs[0usize].selected, texture)
    if build_2_error != ok { os.exit(25i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(26i32) }
    let (hovered_shot, hovered_error) = testing.snapshot(&harness, a)
    if hovered_error != ok { os.exit(27i32) }
    if !(hovered_shot.pixels[(sy * 120usize + sx) * 4usize + 2usize] > shot.pixels[(sy * 120usize + sx) * 4usize + 2usize]) { os.exit(28i32) }
    // The disabled button neither fires nor takes the focus.
    let (never_bounds, has_never) = widget.bounds_of(&runtime, testing.by_key(&harness, 2u64).element)
    if !has_never { os.exit(29i32) }
    if testing.tap(&harness, never_bounds.x + 5.0, never_bounds.y + 5.0) != ok || logs[0usize].disabled != 0usize { os.exit(30i32) }
    let (focus_after, has_focus_after) = testing.focused(&harness)
    if has_focus_after && focus_after.slot == testing.by_key(&harness, 2u64).element.slot { os.exit(31i32) }
    // The toggle: a tap selects it, the tree shows it selected on the next frame.
    let (bold_bounds, has_bold) = widget.bounds_of(&runtime, testing.by_key(&harness, 3u64).element)
    if !has_bold { os.exit(32i32) }
    if testing.tap(&harness, bold_bounds.x + 5.0, bold_bounds.y + 5.0) != ok || logs[0usize].toggles != 1usize || !logs[0usize].selected { os.exit(33i32) }
    let (root_3, build_3_error) = build(&frame, &theme, &actions[0usize], logs[0usize].selected, texture)
    if build_3_error != ok { os.exit(34i32) }
    if testing.pump(&harness, root_3, now) != ok { os.exit(35i32) }
    let (tree_3, tree_3_error) = testing.semantics(&harness)
    if tree_3_error != ok { os.exit(36i32) }
    var selected_seen = false
    i = 0usize
    while i < tree_3.nodes.len {
        if tree_3.nodes[i].role == .Button && tree_3.nodes[i].state.selected { selected_seen = true }
        i += 1usize
    }
    if !selected_seen { os.exit(37i32) }
    // The icon button and the link fire their actions.
    let (star_bounds, has_star) = widget.bounds_of(&runtime, testing.by_key(&harness, 4u64).element)
    if !has_star || testing.tap(&harness, star_bounds.x + 5.0, star_bounds.y + 5.0) != ok || logs[0usize].icons != 1usize { os.exit(38i32) }
    let (more_bounds, has_more) = widget.bounds_of(&runtime, testing.by_key(&harness, 5u64).element)
    if !has_more || testing.tap(&harness, more_bounds.x + 1.0, more_bounds.y + 1.0) != ok || logs[0usize].links != 1usize { os.exit(39i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(40i32) }
    try io.print("ui button ok\n")
    ret ok
}
