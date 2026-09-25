// `e.ui.control`'s advanced actions (D829, widget plan P2-01) under the light
// theme: a rating's stars set the value by a tap and the arrow keys step it from
// the focused row; a split button's primary fires and its second toggles the menu
// the caller places; a speed dial expands into its actions above itself and a
// press outside closes it; a filter chip is checked, an input chip removes.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { ratings: usize, rating: u32, primaries: usize, toggles: usize, dials: usize, dial_actions: usize, chips: usize, removes: usize }

fn on_rating(ctx: *void, value: u32) -> err {
    let log = mem.cast[*Log](ctx)
    log.ratings += 1usize
    log.rating = value
    ret ok
}

fn on_primary(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.primaries += 1usize
    ret ok
}

fn on_toggle(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.toggles += 1usize
    ret ok
}

fn on_dial(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.dials += 1usize
    ret ok
}

fn on_dial_action(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.dial_actions += 1usize
    ret ok
}

fn on_chip(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.chips += 1usize
    ret ok
}

fn on_remove(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.removes += 1usize
    ret ok
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

type Handlers = struct { primary: widget.Submit, toggle: widget.Submit, dial: widget.Submit, chip: widget.Submit, remove: widget.Submit }

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, h: *const Handlers, dial_actions: []const widget.Submit, menu_items: []const overlay.MenuItem, rating: u32, menu_open: bool, dial_open: bool, filtered: bool) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 6usize)
    if parts_error != ok { ret (zero, parts_error) }
    let (stars, stars_error) = control.rating(a, 1u64, t, "Quality", rating, 5u32, widget.Change[u32] { ctx: ctx, invoke: on_rating })
    if stars_error != ok { ret (zero, stars_error) }
    parts[0usize] = stars
    let (split, split_error) = control.split_button(a, 10u64, t, "Save", &h.primary, menu_open, &h.toggle)
    if split_error != ok { ret (zero, split_error) }
    parts[1usize] = split
    let (popup, popup_error) = overlay.menu(a, 12u64, t, 11u64, "Save as", menu_items, menu_open, &h.toggle)
    if popup_error != ok { ret (zero, popup_error) }
    parts[2usize] = popup
    var labels: [2]str = zero
    labels[0usize] = "Photo"
    labels[1usize] = "Note"
    let (dial, dial_error) = control.speed_dial(a, 20u64, t, "Add", labels[..], dial_actions, dial_open, &h.dial)
    if dial_error != ok { ret (zero, dial_error) }
    parts[3usize] = dial
    let (filter, filter_error) = control.chip(a, 30u64, t, "Unread", .Filter, filtered, &h.chip, &h.remove)
    if filter_error != ok { ret (zero, filter_error) }
    parts[4usize] = filter
    let (token, token_error) = control.chip(a, 40u64, t, "alice@example.com", .Input, false, &h.chip, &h.remove)
    if token_error != ok { ret (zero, token_error) }
    parts[5usize] = token
    var column = style.defaults()
    column.width = style.Length { Px: 320.0 }
    column.height = style.Length { Px: 400.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 24.0 }, column, parts[0usize..6usize]), ok)
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn centre_of(h: *testing.Harness, runtime: *const widget.Runtime, key: widget.Key) -> (geometry.Point, bool) {
    let found = testing.by_key(h, key)
    if found.count != 1usize { ret (zero, false) }
    let (area, has_area) = widget.bounds_of(runtime, found.element)
    if !has_area { ret (zero, false) }
    ret (geometry.Point { x: area.x + area.width * 0.5, y: area.y + area.height * 0.5 }, true)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    var tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 128usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 12u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 320u32, 400u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (handlers, handlers_error) = mem.alloc[Handlers](a, 1usize)
    if handlers_error != ok { os.exit(8i32) }
    handlers[0usize] = Handlers { primary: widget.Submit { ctx: ctx, invoke: on_primary }, toggle: widget.Submit { ctx: ctx, invoke: on_toggle }, dial: widget.Submit { ctx: ctx, invoke: on_dial }, chip: widget.Submit { ctx: ctx, invoke: on_chip }, remove: widget.Submit { ctx: ctx, invoke: on_remove } }
    let (dial_actions, dial_actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if dial_actions_error != ok { os.exit(9i32) }
    dial_actions[0usize] = widget.Submit { ctx: ctx, invoke: on_dial_action }
    dial_actions[1usize] = widget.Submit { ctx: ctx, invoke: on_dial_action }
    let (menu_items, menu_items_error) = mem.alloc[overlay.MenuItem](a, 1usize)
    if menu_items_error != ok { os.exit(10i32) }
    menu_items[0usize] = overlay.MenuItem { label: "Save as copy", action: widget.Submit { ctx: ctx, invoke: on_primary }, enabled: true }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 524288usize)
    if storage_error != ok { os.exit(11i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, ctx, &handlers[0usize], dial_actions[0usize..2usize], menu_items[0usize..1usize], 2u32, false, false, false)
    if build_error != ok { os.exit(12i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(13i32) }
    // The rating: a slider valued "2"; a tap on the fourth star sets 4; Tab reaches
    // the row and Right steps to 3 from the caller's 2, Left to 1.
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(14i32) }
    let (slider, has_slider) = find(tree, .Slider, "Quality")
    if !has_slider || !same(slider.value, "2") { os.exit(15i32) }
    let (fourth_at, has_fourth) = centre_of(&harness, &runtime, 5u64)
    if !has_fourth || testing.tap(&harness, fourth_at.x, fourth_at.y) != ok || logs[0usize].ratings != 1usize || logs[0usize].rating != 4u32 { os.exit(16i32) }
    if testing.tab(&harness, false) != ok { os.exit(17i32) }
    let (focused, has_focus) = testing.focused(&harness)
    let rating_row = testing.by_key(&harness, 1u64).element
    if !has_focus || focused.slot != rating_row.slot { os.exit(18i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || logs[0usize].rating != 3u32 { os.exit(19i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || logs[0usize].rating != 1u32 { os.exit(20i32) }
    // RTL mirrors Left/Right only; Down/Up and Home/End remain logical.
    tokens.direction = .RightToLeft
    let (root_rtl, build_rtl_error) = build(&frame, &theme, ctx, &handlers[0usize], dial_actions[0usize..2usize], menu_items[0usize..1usize], 2u32, false, false, false)
    if build_rtl_error != ok || testing.pump(&harness, root_rtl, time.Instant { nanos: 2000000000i64 }) != ok { os.exit(47i32) }
    let (rtl_first, has_rtl_first) = centre_of(&harness, &runtime, 2u64)
    let (rtl_last, has_rtl_last) = centre_of(&harness, &runtime, 6u64)
    if !has_rtl_first || !has_rtl_last || !(rtl_first.x > rtl_last.x) { os.exit(54i32) }
    if testing.tap(&harness, rtl_last.x, rtl_last.y) != ok || logs[0usize].rating != 5u32 { os.exit(55i32) }
    if testing.tap(&harness, rtl_first.x, rtl_first.y) != ok || logs[0usize].rating != 1u32 { os.exit(56i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || logs[0usize].rating != 3u32 { os.exit(48i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || logs[0usize].rating != 1u32 { os.exit(49i32) }
    if testing.press_key(&harness, 38u32, zero) != ok || logs[0usize].rating != 3u32 { os.exit(50i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || logs[0usize].rating != 1u32 { os.exit(51i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || logs[0usize].rating != 0u32 { os.exit(52i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || logs[0usize].rating != 5u32 { os.exit(53i32) }
    tokens.direction = .LeftToRight
    // The split button: the primary fires; the second toggles; open, the menu the
    // caller anchors to it lies below it and the second says expanded.
    let (save_at, has_save) = centre_of(&harness, &runtime, 10u64)
    if !has_save || testing.tap(&harness, save_at.x, save_at.y) != ok || logs[0usize].primaries != 1usize { os.exit(21i32) }
    let (more_at, has_more) = centre_of(&harness, &runtime, 11u64)
    if !has_more || testing.tap(&harness, more_at.x, more_at.y) != ok || logs[0usize].toggles != 1usize { os.exit(22i32) }
    let (root_2, build_2_error) = build(&frame, &theme, ctx, &handlers[0usize], dial_actions[0usize..2usize], menu_items[0usize..1usize], 1u32, true, false, false)
    if build_2_error != ok { os.exit(23i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(24i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(25i32) }
    let (more_node, has_more_node) = find(tree_2, .Button, "More")
    if !has_more_node || !more_node.state.expanded || testing.by_role(&harness, .MenuItem).count != 1usize { os.exit(26i32) }
    let (more_bounds, has_more_bounds) = widget.bounds_of(&runtime, testing.by_key(&harness, 11u64).element)
    let (menu_bounds, has_menu_bounds) = testing.overlay_of(&harness, testing.by_key(&harness, 12u64).element)
    if !has_more_bounds || !has_menu_bounds || menu_bounds.y < more_bounds.y + more_bounds.height { os.exit(27i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].toggles != 2usize { os.exit(28i32) }
    // The speed dial: closed, its button alone; a tap fires the toggle; open, two
    // actions stand above it, one fires on a tap, and a press outside closes.
    let (root_3, build_3_error) = build(&frame, &theme, ctx, &handlers[0usize], dial_actions[0usize..2usize], menu_items[0usize..1usize], 1u32, false, false, false)
    if build_3_error != ok { os.exit(29i32) }
    if testing.pump(&harness, root_3, now) != ok { os.exit(30i32) }
    if testing.by_label(&harness, "Photo").count != 0usize { os.exit(31i32) }
    let (add_at, has_add) = centre_of(&harness, &runtime, 20u64)
    if !has_add || testing.tap(&harness, add_at.x, add_at.y) != ok || logs[0usize].dials != 1usize { os.exit(32i32) }
    let (root_4, build_4_error) = build(&frame, &theme, ctx, &handlers[0usize], dial_actions[0usize..2usize], menu_items[0usize..1usize], 1u32, false, true, false)
    if build_4_error != ok { os.exit(33i32) }
    if testing.pump(&harness, root_4, now) != ok { os.exit(34i32) }
    if testing.by_label(&harness, "Photo").count == 0usize || testing.by_label(&harness, "Note").count == 0usize { os.exit(35i32) }
    let (add_bounds, has_add_bounds) = widget.bounds_of(&runtime, testing.by_key(&harness, 20u64).element)
    let (list_bounds, has_list_bounds) = testing.overlay_of(&harness, testing.by_key(&harness, 21u64).element)
    if !has_add_bounds || !has_list_bounds || list_bounds.y + list_bounds.height > add_bounds.y { os.exit(36i32) }
    let (photo_at, has_photo) = centre_of(&harness, &runtime, 22u64)
    if !has_photo || testing.tap(&harness, photo_at.x, photo_at.y) != ok || logs[0usize].dial_actions != 1usize { os.exit(37i32) }
    if testing.tap(&harness, 2.0, 398.0) != ok || logs[0usize].dials != 2usize { os.exit(38i32) }
    // The chips: the filter chip is a checkbox, checked when selected; a tap fires
    // its action; the input chip's remove button fires the remove alone.
    let (root_5, build_5_error) = build(&frame, &theme, ctx, &handlers[0usize], dial_actions[0usize..2usize], menu_items[0usize..1usize], 1u32, false, false, true)
    if build_5_error != ok { os.exit(39i32) }
    if testing.pump(&harness, root_5, now) != ok { os.exit(40i32) }
    let (tree_5, tree_5_error) = testing.semantics(&harness)
    if tree_5_error != ok { os.exit(41i32) }
    let (filter_node, has_filter) = find(tree_5, .Checkbox, "Unread")
    if !has_filter || !filter_node.state.checked { os.exit(42i32) }
    let (filter_at, has_filter_at) = centre_of(&harness, &runtime, 30u64)
    if !has_filter_at || testing.tap(&harness, filter_at.x, filter_at.y) != ok || logs[0usize].chips != 1usize { os.exit(43i32) }
    let (remove_node, has_remove) = find(tree_5, .Button, "Remove")
    if !has_remove { os.exit(44i32) }
    let (remove_at, has_remove_at) = centre_of(&harness, &runtime, 41u64)
    if !has_remove_at || testing.tap(&harness, remove_at.x, remove_at.y) != ok || logs[0usize].removes != 1usize || logs[0usize].chips != 1usize { os.exit(45i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(46i32) }
    try io.print("ui actions ok\n")
    ret ok
}
