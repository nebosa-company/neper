// `e.ui.testing`'s widget harness and gallery (D812, widget plan P0-09): the
// reference gallery pumped under the light theme; elements found by role and by
// label; a tap on the button by its bounds; Tab travelling button, field, checkbox;
// text typed and a composition committed into the field through the fake IME; the
// checkbox toggled by a tap and by its platform action; the wheel over the list
// viewport with rows visible and hidden; the tooltip overlay found below the
// button; a faked touch host with insets; and two frames the same pixel for pixel.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.scene
use e.text.layout
use e.ui.accessibility
use e.ui.style
use e.ui.testing
use e.ui.widget

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn centre(r: geometry.Rect) -> geometry.Point {
    ret geometry.Point { x: r.x + r.width * 0.5, y: r.y + r.height * 0.5 }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 64usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(4i32) }
    var runtime = rt
    let (h, harness_error) = testing.harness(a, &runtime, 200u32, 300u32, 1.0)
    if harness_error != ok { os.exit(5i32) }
    var harness = h
    let theme = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[layout.FontChoice](a, 0usize)
    if fonts_error != ok { os.exit(6i32) }
    let text_style = layout.Style { fonts: fonts, language: "", line_height: 16.0 }
    let (states, states_error) = mem.alloc[testing.Gallery](a, 1usize)
    if states_error != ok { os.exit(7i32) }
    var gallery_state: testing.Gallery = zero
    states[0usize] = gallery_state
    let now = time.Instant { nanos: 1000000000i64 }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(8i32) }
    var frame = mem.arena_from(frame_storage)
    let (page, page_error) = testing.gallery(&frame, &theme, text_style, &states[0usize])
    if page_error != ok { os.exit(9i32) }
    if testing.pump(&harness, page, now) != ok { os.exit(10i32) }
    // Semantic queries: one heading, the button by its label (the semantics first,
    // its text child after), six list items.
    if testing.by_role(&harness, .Heading).count != 1usize { os.exit(11i32) }
    let save = testing.by_label(&harness, "Save")
    if save.count != 2usize || save.element.slot != testing.by_key(&harness, 2u64).element.slot { os.exit(12i32) }
    if testing.by_role(&harness, .ListItem).count != 6usize || testing.by_role(&harness, .TextField).count != 1usize { os.exit(13i32) }
    // A tap on the button by its bounds presses it and focuses it.
    let button = testing.by_key(&harness, 3u64)
    let (button_bounds, has_button) = widget.bounds_of(&runtime, button.element)
    if button.count != 1usize || !has_button { os.exit(14i32) }
    let at = centre(button_bounds)
    if testing.tap(&harness, at.x, at.y) != ok || states[0usize].presses != 1usize { os.exit(15i32) }
    let (focus_1, has_focus_1) = testing.focused(&harness)
    if !has_focus_1 || focus_1.slot != button.element.slot { os.exit(16i32) }
    // Tab: the field, then the checkbox; Shift+Tab back to the field.
    let field = testing.by_key(&harness, 4u64)
    let check = testing.by_key(&harness, 6u64)
    if testing.tab(&harness, false) != ok { os.exit(17i32) }
    let (focus_2, _) = testing.focused(&harness)
    if focus_2.slot != field.element.slot { os.exit(18i32) }
    if testing.tab(&harness, false) != ok { os.exit(19i32) }
    let (focus_3, _) = testing.focused(&harness)
    if focus_3.slot != check.element.slot { os.exit(20i32) }
    if testing.tab(&harness, true) != ok { os.exit(21i32) }
    let (focus_4, _) = testing.focused(&harness)
    if focus_4.slot != field.element.slot { os.exit(22i32) }
    // The fake IME into the focused field: typed text, a composition, its commit.
    if testing.type_text(&harness, "hi") != ok { os.exit(23i32) }
    let (typed, has_typed) = widget.edit_value(&runtime, field.element)
    if !has_typed || !same(typed, "hi") || states[0usize].field_len != 2usize { os.exit(24i32) }
    if testing.compose(&harness, "x") != ok || testing.commit(&harness, "x") != ok { os.exit(25i32) }
    let (committed, _) = widget.edit_value(&runtime, field.element)
    if !same(committed, "hix") { os.exit(26i32) }
    // The checkbox: a tap toggles it, the platform action toggles it back; the
    // tree says so after the next frame.
    let (check_bounds, has_check) = widget.bounds_of(&runtime, check.element)
    if !has_check { os.exit(27i32) }
    let check_at = centre(check_bounds)
    if testing.tap(&harness, check_at.x, check_at.y) != ok || !states[0usize].checked { os.exit(28i32) }
    let (page_2, page_2_error) = testing.gallery(&frame, &theme, text_style, &states[0usize])
    if page_2_error != ok { os.exit(29i32) }
    if testing.pump(&harness, page_2, now) != ok { os.exit(30i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(31i32) }
    var checked_seen = false
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .Checkbox && tree.nodes[i].state.checked { checked_seen = true }
        i += 1usize
    }
    if !checked_seen { os.exit(32i32) }
    let box_node = testing.by_role(&harness, .Checkbox)
    if accessibility.perform(&runtime, box_node.element, .Press, "") != ok || states[0usize].checked { os.exit(33i32) }
    // The list viewport: two rows show; a notch of the wheel hides the first.
    let viewport = testing.by_key(&harness, 7u64)
    let (viewport_bounds, has_viewport) = widget.bounds_of(&runtime, viewport.element)
    if viewport.count != 1usize || !has_viewport { os.exit(34i32) }
    let row_0 = testing.by_key(&harness, 20u64)
    let row_1 = testing.by_key(&harness, 21u64)
    let row_5 = testing.by_key(&harness, 25u64)
    if !testing.visible(&harness, row_0.element) || testing.visible(&harness, row_5.element) { os.exit(35i32) }
    let list_at = centre(viewport_bounds)
    if testing.wheel(&harness, list_at.x, list_at.y, -1i32) != ok || !near(states[0usize].scrolled, 40.0) { os.exit(36i32) }
    let (page_3, page_3_error) = testing.gallery(&frame, &theme, text_style, &states[0usize])
    if page_3_error != ok { os.exit(37i32) }
    if testing.pump(&harness, page_3, now) != ok { os.exit(38i32) }
    if testing.visible(&harness, row_0.element) || !testing.visible(&harness, row_1.element) { os.exit(39i32) }
    // The tooltip overlay sits just below the button.
    let tip = testing.by_key(&harness, 8u64)
    let (tip_bounds, has_tip) = testing.overlay_of(&harness, tip.element)
    if tip.count != 1usize || !has_tip || !near(tip_bounds.y, button_bounds.y + button_bounds.height + theme.spacing.xs) || !near(tip_bounds.x, button_bounds.x) { os.exit(40i32) }
    // A faked touch host with insets, seen by the harness and sent to the widgets.
    let touch = style.Capabilities { hover: false, fine_pointer: false, keyboard: false, touch: true, pen: false, resizable: false, multi_window: false, insets: zero }
    let safe = geometry.Insets { left: 0.0, top: 24.0, right: 0.0, bottom: 34.0 }
    let keyboard = geometry.Insets { left: 0.0, top: 0.0, right: 0.0, bottom: 120.0 }
    if testing.fake_host(&harness, touch, safe, keyboard) != ok { os.exit(41i32) }
    let host = testing.capabilities(&harness)
    let (safe_now, keyboard_now) = testing.insets(&harness)
    if !host.touch || host.hover || !near(host.insets.top, 24.0) || !near(safe_now.bottom, 34.0) || !near(keyboard_now.bottom, 120.0) { os.exit(42i32) }
    // Two frames of the same tree are the same pixels.
    let (shot_a, shot_a_error) = testing.snapshot(&harness, a)
    if shot_a_error != ok { os.exit(43i32) }
    let (page_4, page_4_error) = testing.gallery(&frame, &theme, text_style, &states[0usize])
    if page_4_error != ok { os.exit(44i32) }
    if testing.pump(&harness, page_4, now) != ok { os.exit(45i32) }
    let (shot_b, shot_b_error) = testing.snapshot(&harness, a)
    if shot_b_error != ok { os.exit(46i32) }
    let (view_a, view_a_error) = image.make_const(shot_a.pixels, shot_a.width, shot_a.height, shot_a.stride, shot_a.format, shot_a.alpha)
    let (view_b, view_b_error) = image.make_const(shot_b.pixels, shot_b.width, shot_b.height, shot_b.stride, shot_b.format, shot_b.alpha)
    if view_a_error != ok || view_b_error != ok || testing.compare(view_a, view_b, 0u8) != ok { os.exit(47i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(48i32) }
    try io.print("ui gallery ok\n")
    ret ok
}
