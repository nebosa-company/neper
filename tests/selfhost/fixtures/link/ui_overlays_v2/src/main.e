// The v2 menus and tooltips (D975, widget plan P5-11, docs/ux/components/Menu,
// ContextMenu, Tooltip) under the light theme: a pointer menu 4 below its
// button on `surface-container`, 4 above and below its 32 rows, a group head and
// a separator between them, a checked and a disabled command, and a 48-tall
// radio command with a supporting line; a context command opens one cascading
// submenu by Right and closes it by Left, while touch replaces the parent with
// a titled Back row; Down, Up, Home and End move the focus
// (skipping the disabled one, wrapping), Enter runs, Escape dismisses, a focused
// row has its ring inset 3 and a hovered row takes the `on-surface` layer; touch
// supporting rows are 56 tall under an
// 8 rim; a context menu at the pointer flipped to its start and
// above it at the window's corner, and one opened from the keyboard below its
// target; a plain tooltip on `inverse-surface` centred 4 above its anchor, 24
// tall, flipping below at the top of the window; a rich tooltip on
// `surface-container` 4 below its anchor's end with an action.

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
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

type Counter = struct { count: usize }

// The counters: 0 New, 1 the other commands, 2 dismiss, 3 Learn more, 4 anchors,
// 5 submenu toggle, 6 submenu leaf, 7 touch submenu toggle, 8 context toggle.
type Store = struct { counters: [9]Counter, subs: [9]widget.Submit, commands: [5]overlay.MenuCommand, touch_subs: [2]overlay.MenuCommand, pops: [2]overlay.MenuCommand, pop_subs: [2]overlay.MenuCommand, tips: [1]overlay.MenuItem }

type Which = enum u8 { Menu, Touch, Pointed, Keyboard, ContextTouch, Rich }

fn on_count(ctx: *void) -> err {
    let c = mem.cast[*Counter](ctx)
    c.count += 1usize
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

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store, which: Which) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 8usize)
    if items_error != ok { ret (zero, items_error) }
    let (file, e1) = control.button(a, 1u64, t, "File", &s.subs[4usize], control.button_options())
    let (save, e2) = control.button(a, 2u64, t, "Save", &s.subs[4usize], control.button_options())
    var info_options = control.button_options()
    info_options.variant = .Plain
    let (info_button, info_button_error) = control.button(a, 30u64, t, "Info", &s.subs[4usize], info_options)
    let context_open = which == .Pointed || which == .Keyboard || (which == .ContextTouch && s.counters[8usize].count % 2usize == 1usize)
    let (info, e3) = overlay.context_target(a, 3u64, t, .Group, "Actions for Info", 400u64, context_open, &s.subs[8usize], info_button)
    s.commands[0usize].submenu = s.touch_subs[0usize..0usize]
    s.commands[0usize].submenu_open = false
    if which == .Touch {
        s.commands[0usize].submenu = s.touch_subs[..]
        s.commands[0usize].submenu_open = s.counters[7usize].count % 2usize == 1usize
        s.commands[0usize].submenu_toggle = s.subs[7usize]
    }
    let (menu, e4) = overlay.menu_of(a, 100u64, t, 1u64, "File", s.commands[0usize..5usize], which == .Menu || which == .Touch, &s.subs[2usize])
    let (tip, e5) = overlay.tooltip_of(a, 200u64, t, 2u64, "Save file", "Ctrl+S", true)
    let (high, e6) = overlay.tooltip(a, 210u64, t, 1u64, "File menu", true)
    var rich_shown = true
    if which == .Rich { rich_shown = overlay.rich_tooltip_wanted(t, 3u64, 300u64) }
    let (rich, e7) = overlay.rich_tooltip(a, 300u64, t, 3u64, "Incremental builds", "Only changed modules are rebuilt.", s.tips[0usize..1usize], rich_shown)
    s.pops[0usize].submenu_open = s.counters[5usize].count % 2usize == 1usize
    let pointer = geometry.Point { x: 600.0, y: 460.0 }
    var context: widget.Node = zero
    var e8: err = ok
    if which == .ContextTouch {
        let (made, made_error) = overlay.context_menu_touch_of(a, 400u64, t, 3u64, "Actions for Info", s.pops[0usize..2usize], context_open, &s.subs[8usize])
        context = made
        e8 = made_error
    } else {
        let (made, made_error) = overlay.context_menu_of(a, 400u64, t, 3u64, "Actions for Info", s.pops[0usize..2usize], context_open, &s.subs[2usize], pointer, which == .Pointed)
        context = made
        e8 = made_error
    }
    if e1 != ok || e2 != ok || info_button_error != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (zero, e1) }
    let (anchors, anchors_error) = mem.alloc[widget.Node](a, 3usize)
    if anchors_error != ok { ret (zero, anchors_error) }
    anchors[0usize] = file
    anchors[1usize] = save
    anchors[2usize] = info
    var column = style.defaults()
    column.width = style.Length { Px: 620.0 }
    items[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: 150.0 }, column, anchors[0usize..3usize])
    items[1usize] = widget.box(0u64, style.defaults(), zero)
    items[2usize] = widget.box(0u64, style.defaults(), zero)
    items[3usize] = menu
    items[4usize] = tip
    items[5usize] = high
    items[6usize] = rich
    items[7usize] = context
    var page_style = style.defaults()
    page_style.width = style.Length { Px: 640.0 }
    page_style.height = style.Length { Px: 480.0 }
    page_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 10.0 }
    page_style.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, page_style, items[0usize..8usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 640usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn lifted(h: *testing.Harness, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = testing.overlay_of(h, testing.by_key(h, key).element)
    ret (b, found)
}

fn focus_is(h: *testing.Harness, key: widget.Key) -> bool {
    let (now, has) = testing.focused(h)
    ret has && now.slot == testing.by_key(h, key).element.slot
}

fn same_element(a: widget.ElementId, b: widget.ElementId) -> bool {
    ret a.slot == b.slot && a.generation == b.generation
}

fn has_action(node: accessibility.Node, wanted: accessibility.Action) -> bool {
    var i = 0usize
    while i < node.actions.len {
        if node.actions[i] == wanted { ret true }
        i += 1usize
    }
    ret false
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
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
    let touch_tokens = style.adapt(&tokens, style.Adaptation { size: .Expanded, capabilities: style.Capabilities { hover: false, fine_pointer: false, keyboard: false, touch: true, pen: false, resizable: false, multi_window: false, insets: zero }, profile: .Touch })
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 800usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 40u16, max_commands: 8192usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let touch_theme = control.Theme { tokens: &touch_tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 640u32, 480u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    var i = 0usize
    while i < 9usize {
        s.subs[i] = widget.Submit { ctx: mem.cast[*void](&s.counters[i]), invoke: on_count }
        i += 1usize
    }
    s.commands[0usize] = overlay.menu_command("New", s.subs[0usize])
    s.commands[0usize].shortcut = "Ctrl+N"
    s.commands[0usize].pictured = true
    s.commands[0usize].glyph = .Picture
    s.commands[1usize] = overlay.menu_command("Word wrap", s.subs[1usize])
    s.commands[1usize].checkable = true
    s.commands[1usize].checked = true
    s.commands[2usize] = overlay.menu_command("Minimap", s.subs[1usize])
    s.commands[2usize].head = "View"
    s.commands[2usize].supporting = "Always visible"
    s.commands[2usize].radio = true
    s.commands[2usize].checked = true
    s.commands[3usize] = overlay.menu_command("Quit", s.subs[1usize])
    s.commands[3usize].enabled = false
    s.commands[4usize] = overlay.menu_command("Delete", s.subs[1usize])
    s.commands[4usize].separated = true
    s.commands[4usize].destructive = true
    s.touch_subs[0usize] = overlay.menu_command("From template", s.subs[6usize])
    s.touch_subs[1usize] = overlay.menu_command("Blank file", s.subs[6usize])
    s.pop_subs[0usize] = overlay.menu_command("Code", s.subs[6usize])
    s.pop_subs[1usize] = overlay.menu_command("Text", s.subs[6usize])
    s.pops[0usize] = overlay.menu_command("Open with", s.subs[1usize])
    s.pops[0usize].submenu = s.pop_subs[0usize..2usize]
    s.pops[0usize].submenu_toggle = s.subs[5usize]
    s.pops[1usize] = overlay.menu_command("Rename", s.subs[1usize])
    s.tips[0usize] = overlay.MenuItem { label: "Learn more", action: s.subs[3usize], enabled: true }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, s, .Menu)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 101u64).element) != ok || testing.pump(&harness, root, time.Instant { nanos: 1000000001i64 }) != ok { os.exit(86i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    // The pointer menu: 4 below File at its start, 200 wide at least, on
    // `surface-container` with a 4 rim; its first row 32 tall, edge to edge.
    let (file, has_file) = bounds(&harness, &runtime, 1u64)
    let (menu, has_menu) = lifted(&harness, 100u64)
    if !has_file || !has_menu || !near(menu.x, file.x) || !near(menu.y, file.y + file.height + 4.0) || menu.width < 200.0 { os.exit(13i32) }
    if !is_color(shot, at(menu.x + 100.0, menu.y + 2.0), style.color(&tokens, .SurfaceContainer)) { os.exit(14i32) }
    let (new_row, has_new) = bounds(&harness, &runtime, 101u64)
    if !has_new || !near(new_row.y, menu.y + 4.0) || !near(new_row.height, 32.0) || !near(new_row.x, menu.x) || !near(new_row.width, menu.width) { os.exit(15i32) }
    let ring_at_4 = is_color(shot, at(new_row.x + 4.0, new_row.y + 16.0), style.color(&tokens, .FocusRing))
    let ring_at_5 = is_color(shot, at(new_row.x + 5.0, new_row.y + 16.0), style.color(&tokens, .FocusRing))
    if (!ring_at_4 && !ring_at_5) || is_color(shot, at(new_row.x + 1.0, new_row.y + 16.0), style.color(&tokens, .FocusRing)) { os.exit(85i32) }
    // The group head (8 above, 4 below its line) before Minimap; the separator
    // (4, 1, 4) before Delete, a 1px `outline-variant` line.
    let (wrap_row, has_wrap) = bounds(&harness, &runtime, 102u64)
    let (mini_row, has_mini) = bounds(&harness, &runtime, 103u64)
    let (quit_row, has_quit) = bounds(&harness, &runtime, 104u64)
    let (delete_row, has_delete) = bounds(&harness, &runtime, 105u64)
    if !has_wrap || !has_mini || !has_quit || !has_delete || !near(wrap_row.y, new_row.y + 32.0) || !near(mini_row.y, wrap_row.y + 44.0) || !near(mini_row.height, 48.0) || !near(delete_row.y, quit_row.y + 41.0) { os.exit(16i32) }
    if !is_color(shot, at(menu.x + 100.0, quit_row.y + 36.0), style.color(&tokens, .OutlineVariant)) || !is_color(shot, at(menu.x + 100.0, quit_row.y + 34.0), style.color(&tokens, .SurfaceContainer)) { os.exit(17i32) }
    if !near(menu.height, 4.0 + 32.0 * 4.0 + 48.0 + 12.0 + 9.0 + 4.0) { os.exit(18i32) }
    // The tree: a menu named File, checked checkbox and radio commands, its group
    // break a Separator, and Quit disabled.
    let (menu_node, has_menu_node) = find(tree, .Menu, "File")
    let (wrap_node, has_wrap_node) = find(tree, .MenuItemCheckbox, "Word wrap")
    let (mini_node, has_mini_node) = find(tree, .MenuItemRadio, "Minimap")
    let (quit_node, has_quit_node) = find(tree, .MenuItem, "Quit")
    if !has_menu_node { os.exit(19i32) }
    if !has_wrap_node || !wrap_node.state.checked { os.exit(54i32) }
    if !has_mini_node || !mini_node.state.checked { os.exit(54i32) }
    if !has_quit_node || !quit_node.state.disabled { os.exit(55i32) }
    if testing.by_role(&harness, .MenuItem).count != 3usize { os.exit(52i32) }
    if testing.by_role(&harness, .Separator).count != 1usize { os.exit(53i32) }
    // The keys: the focus starts on New; Down walks, skipping Quit, and wraps; Up
    // wraps back; End and Home jump; Enter runs New; Escape dismisses.
    if !focus_is(&harness, 101u64) { os.exit(20i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !focus_is(&harness, 102u64) { os.exit(21i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || testing.press_key(&harness, 40u32, zero) != ok || !focus_is(&harness, 105u64) { os.exit(22i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !focus_is(&harness, 101u64) { os.exit(23i32) }
    if testing.press_key(&harness, 38u32, zero) != ok || !focus_is(&harness, 105u64) { os.exit(24i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !focus_is(&harness, 101u64) { os.exit(25i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !focus_is(&harness, 105u64) { os.exit(26i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || testing.press_key(&harness, 13u32, zero) != ok || s.counters[0usize].count != 1usize || s.counters[2usize].count != 1usize { os.exit(27i32) }
    s.counters[2usize].count = 0usize
    if testing.press_key(&harness, 27u32, zero) != ok || s.counters[2usize].count != 1usize { os.exit(28i32) }
    // The plain tooltip: `inverse-surface`, 24 tall, centred 4 above Save.
    let (save, has_save) = bounds(&harness, &runtime, 2u64)
    let (tip, has_tip) = lifted(&harness, 200u64)
    if !has_save || !has_tip || !near(tip.y + tip.height, save.y - 4.0) || !near(tip.height, 24.0) || !near(tip.x + tip.width * 0.5, save.x + save.width * 0.5) { os.exit(29i32) }
    if !is_color(shot, at(tip.x + tip.width * 0.5, tip.y + 12.0), style.color(&tokens, .InverseSurface)) { os.exit(30i32) }
    let (tip_node, has_tip_node) = find(tree, .Tooltip, "Save file")
    if !has_tip_node { os.exit(31i32) }
    // At the top of the window it flips below File.
    let (high, has_high) = lifted(&harness, 210u64)
    if !has_high || !near(high.y, file.y + file.height + 4.0) { os.exit(32i32) }
    // The rich tooltip: 4 below Info, its end on Info's, at least 48 tall on
    // `surface-container`, named by its subhead; Learn more runs.
    let (info, has_info) = bounds(&harness, &runtime, 3u64)
    let (rich, has_rich) = lifted(&harness, 300u64)
    if !has_info || !has_rich || !near(rich.x + rich.width, info.x + info.width) || rich.height < 48.0 { os.exit(33i32) }
    if !near(rich.y, info.y + info.height + 4.0) && !near(rich.y + rich.height, info.y - 4.0) { os.exit(34i32) }
    if !is_color(shot, at(rich.x + rich.width * 0.5, rich.y + 6.0), style.color(&tokens, .SurfaceContainer)) { os.exit(35i32) }
    let (rich_node, has_rich_node) = find(tree, .Tooltip, "Incremental builds")
    let (learn, has_learn) = bounds(&harness, &runtime, 301u64)
    if !has_rich_node || !has_learn { os.exit(36i32) }
    // A hovered row takes the `on-surface` layer at `state-hover`.
    if testing.hover(&harness, wrap_row.x + 100.0, wrap_row.y + 16.0) != ok { os.exit(37i32) }
    let (root_2, build_2_error) = build(&f, &theme, s, .Menu)
    if build_2_error != ok || testing.pump(&harness, root_2, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(38i32) }
    let (shot_2, shot_2_error) = testing.snapshot(&harness, a)
    if shot_2_error != ok { os.exit(39i32) }
    let hovered = style.layer(style.color(&tokens, .SurfaceContainer), style.color(&tokens, .OnSurface), tokens.states.hover)
    if !is_color(shot_2, at(wrap_row.x + 150.0, wrap_row.y + 16.0), hovered) || !is_color(shot_2, at(mini_row.x + 150.0, mini_row.y + 16.0), style.color(&tokens, .SurfaceContainer)) { os.exit(40i32) }
    // Touch density: 48 rows under an 8 rim, 112 wide at least. Right replaces
    // the parent page with Back, a separator and the child rows; tapping Back or
    // pressing Escape restores the parent row and its focus.
    let (root_3, build_3_error) = build(&f, &touch_theme, s, .Touch)
    if build_3_error != ok || testing.pump(&harness, root_3, time.Instant { nanos: 1200000000i64 }) != ok { os.exit(41i32) }
    let (touch_menu, has_touch_menu) = lifted(&harness, 100u64)
    let (touch_row, has_touch_row) = bounds(&harness, &runtime, 101u64)
    let (touch_support, has_touch_support) = bounds(&harness, &runtime, 103u64)
    if !has_touch_menu || !has_touch_row || !has_touch_support || !near(touch_row.height, 48.0) || !near(touch_support.height, 56.0) || !near(touch_row.y, touch_menu.y + 8.0) || touch_menu.width < 112.0 { os.exit(42i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || s.counters[7usize].count != 1usize { os.exit(87i32) }
    let (root_touch_sub, root_touch_sub_error) = build(&f, &touch_theme, s, .Touch)
    if root_touch_sub_error != ok || testing.pump(&harness, root_touch_sub, time.Instant { nanos: 1210000000i64 }) != ok { os.exit(88i32) }
    let (touch_replaced, has_touch_replaced) = lifted(&harness, 100u64)
    let (touch_back, has_touch_back) = bounds(&harness, &runtime, 1124u64)
    let (touch_child, has_touch_child) = bounds(&harness, &runtime, 1125u64)
    if !has_touch_replaced || !has_touch_back || !has_touch_child || testing.by_key(&harness, 101u64).count != 0usize { os.exit(89i32) }
    if !near(touch_back.y, touch_replaced.y + 8.0) || !near(touch_child.y, touch_back.y + 57.0) || !near(touch_replaced.height, 169.0) || !focus_is(&harness, 1125u64) { os.exit(90i32) }
    let (tree_touch, tree_touch_error) = testing.semantics(&harness)
    if tree_touch_error != ok { os.exit(91i32) }
    let (back_node, has_back_node) = find(tree_touch, .MenuItem, "Back")
    let (child_menu, has_child_menu) = find(tree_touch, .Menu, "New")
    if !has_back_node || !has_action(back_node, .Collapse) || !has_child_menu { os.exit(92i32) }
    if testing.tap(&harness, touch_back.x + 20.0, touch_back.y + 24.0) != ok || s.counters[7usize].count != 2usize { os.exit(93i32) }
    let (root_touch_back, root_touch_back_error) = build(&f, &touch_theme, s, .Touch)
    if root_touch_back_error != ok || testing.pump(&harness, root_touch_back, time.Instant { nanos: 1220000000i64 }) != ok || !focus_is(&harness, 101u64) { os.exit(94i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || s.counters[7usize].count != 3usize { os.exit(95i32) }
    let (root_touch_again, root_touch_again_error) = build(&f, &touch_theme, s, .Touch)
    if root_touch_again_error != ok || testing.pump(&harness, root_touch_again, time.Instant { nanos: 1230000000i64 }) != ok || !focus_is(&harness, 1125u64) { os.exit(96i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || s.counters[7usize].count != 4usize { os.exit(97i32) }
    let (root_touch_escape, root_touch_escape_error) = build(&f, &touch_theme, s, .Touch)
    if root_touch_escape_error != ok || testing.pump(&harness, root_touch_escape, time.Instant { nanos: 1240000000i64 }) != ok || !focus_is(&harness, 101u64) { os.exit(98i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || s.counters[7usize].count != 5usize { os.exit(99i32) }
    let (root_touch_leaf, root_touch_leaf_error) = build(&f, &touch_theme, s, .Touch)
    if root_touch_leaf_error != ok || testing.pump(&harness, root_touch_leaf, time.Instant { nanos: 1250000000i64 }) != ok || !focus_is(&harness, 1125u64) { os.exit(100i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || s.counters[6usize].count != 1usize || s.counters[7usize].count != 6usize || s.counters[2usize].count != 2usize { os.exit(101i32) }
    s.counters[6usize].count = 0usize
    s.counters[2usize].count = 1usize
    // The context menu at the pointer (600, 460): no room at the end or below, so
    // it stands to the pointer's start and above it; 8 above its first row.
    let (root_4, build_4_error) = build(&f, &theme, s, .Pointed)
    if build_4_error != ok || testing.pump(&harness, root_4, time.Instant { nanos: 1300000000i64 }) != ok { os.exit(43i32) }
    let (pop, has_pop) = lifted(&harness, 400u64)
    let (open_row, has_open_row) = bounds(&harness, &runtime, 401u64)
    if !has_pop || !has_open_row || !near(pop.x + pop.width, 602.0) || !near(pop.y + pop.height, 462.0) || !near(open_row.y, pop.y + 8.0) || !near(pop.height, 80.0) { os.exit(44i32) }
    let (tree_4, tree_4_error) = testing.semantics(&harness)
    if tree_4_error != ok { os.exit(45i32) }
    let (pop_node, has_pop_node) = find(tree_4, .Menu, "Actions for Info")
    if !has_pop_node || !focus_is(&harness, 401u64) { os.exit(46i32) }
    // Right opens the general-menu submenu. Its first row aligns with its parent
    // and it remains in the window when neither full side fits; the parent exposes
    // Show menu / Expanded / Controls, and Left closes only that level.
    if testing.press_key(&harness, 39u32, zero) != ok || s.counters[5usize].count != 1usize { os.exit(56i32) }
    let (root_sub, root_sub_error) = build(&f, &theme, s, .Pointed)
    if root_sub_error != ok || testing.pump(&harness, root_sub, time.Instant { nanos: 1350000000i64 }) != ok { os.exit(57i32) }
    let (sub, has_sub) = lifted(&harness, 1424u64)
    let (sub_first, has_sub_first) = bounds(&harness, &runtime, 1425u64)
    if !has_sub { os.exit(80i32) }
    if !has_sub_first { os.exit(81i32) }
    if sub.x < 0.0 || sub.x + sub.width > 640.0 { os.exit(82i32) }
    if !near(sub_first.y, open_row.y) { os.exit(83i32) }
    if !focus_is(&harness, 1425u64) { os.exit(84i32) }
    let (tree_sub, tree_sub_error) = testing.semantics(&harness)
    if tree_sub_error != ok { os.exit(59i32) }
    let (open_with, has_open_with) = find(tree_sub, .MenuItem, "Open with")
    if !has_open_with || !open_with.state.expanded || !has_action(open_with, .ShowMenu) || !same_element(open_with.relations.controls, testing.by_key(&harness, 1424u64).element) { os.exit(60i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || s.counters[5usize].count != 2usize { os.exit(61i32) }
    s.counters[5usize].count = 0usize
    let (root_closed, root_closed_error) = build(&f, &theme, s, .Pointed)
    if root_closed_error != ok || testing.pump(&harness, root_closed, time.Instant { nanos: 1375000000i64 }) != ok { os.exit(62i32) }
    // A press outside dismisses and does not reach Save.
    if testing.tap(&harness, save.x + 4.0, save.y + 4.0) != ok || s.counters[2usize].count != 2usize || s.counters[4usize].count != 0usize { os.exit(47i32) }
    // From the keyboard: below Info at its start edge.
    let (root_5, build_5_error) = build(&f, &theme, s, .Keyboard)
    if build_5_error != ok || testing.pump(&harness, root_5, time.Instant { nanos: 1400000000i64 }) != ok { os.exit(48i32) }
    let (below, has_below) = lifted(&harness, 400u64)
    if !has_below || !near(below.x, info.x) { os.exit(49i32) }
    if !near(below.y, info.y + info.height) && !near(below.y + below.height, info.y) { os.exit(50i32) }
    // Touch: holding the target for 500 ms opens once, consumes its release,
    // leaves the lifted target out of the 32% scrim, and places the menu 8 away.
    let touch_start = time.Instant { nanos: 1500000000i64 }
    if testing.begin(&harness, touch_start) != ok { os.exit(102i32) }
    let (touch_context_closed, touch_context_closed_error) = build(&f, &touch_theme, s, .ContextTouch)
    if touch_context_closed_error != ok || testing.pump(&harness, touch_context_closed, touch_start) != ok { os.exit(103i32) }
    let (touch_info, has_touch_info) = bounds(&harness, &runtime, 3u64)
    if !has_touch_info { os.exit(104i32) }
    let touch_point = geometry.Point { x: touch_info.x + touch_info.width * 0.5, y: touch_info.y + touch_info.height * 0.5 }
    if testing.send(&harness, input.Event { PointerDown: testing.pointer_at(touch_point.x, touch_point.y) }) != ok { os.exit(105i32) }
    let held_at = time.Instant { nanos: 1510000000i64 }
    if testing.begin(&harness, held_at) != ok { os.exit(106i32) }
    let (touch_held, touch_held_error) = build(&f, &touch_theme, s, .ContextTouch)
    if touch_held_error != ok || testing.pump(&harness, touch_held, held_at) != ok || !widget.animation_frame_requested(&runtime) { os.exit(107i32) }
    let almost = time.Instant { nanos: 2009999999i64 }
    if testing.begin(&harness, almost) != ok { os.exit(108i32) }
    let (touch_almost, touch_almost_error) = build(&f, &touch_theme, s, .ContextTouch)
    if touch_almost_error != ok || testing.pump(&harness, touch_almost, almost) != ok || s.counters[8usize].count != 0usize { os.exit(109i32) }
    let due = time.Instant { nanos: 2010000000i64 }
    if testing.begin(&harness, due) != ok { os.exit(110i32) }
    let (touch_due, touch_due_error) = build(&f, &touch_theme, s, .ContextTouch)
    if touch_due_error != ok || testing.pump(&harness, touch_due, due) != ok || s.counters[8usize].count != 1usize || !widget.animation_frame_requested(&runtime) { os.exit(111i32) }
    let open_at = time.Instant { nanos: 2010000001i64 }
    if testing.begin(&harness, open_at) != ok { os.exit(112i32) }
    let (touch_context, touch_context_error) = build(&f, &touch_theme, s, .ContextTouch)
    if touch_context_error != ok || testing.pump(&harness, touch_context, open_at) != ok { os.exit(113i32) }
    let (touch_pop, has_touch_pop) = lifted(&harness, 400u64)
    if !has_touch_pop || (!near(touch_pop.y, touch_info.y + touch_info.height + 8.0) && !near(touch_pop.y + touch_pop.height, touch_info.y - 8.0)) { os.exit(114i32) }
    let (touch_tree, touch_tree_error) = testing.semantics(&harness)
    if touch_tree_error != ok { os.exit(115i32) }
    let (touch_target, has_touch_target) = find(touch_tree, .Group, "Actions for Info")
    if !has_touch_target || !touch_target.state.selected || !touch_target.state.expanded || !has_action(touch_target, .ShowMenu) || !same_element(touch_target.relations.controls, testing.by_key(&harness, 400u64).element) { os.exit(116i32) }
    let (touch_shot, touch_shot_error) = testing.snapshot(&harness, a)
    if touch_shot_error != ok { os.exit(117i32) }
    let dimmed = style.layer(style.color(&touch_tokens, .Background), style.color(&touch_tokens, .Scrim), touch_tokens.states.scrim)
    if !is_color(touch_shot, at(5.0, 5.0), dimmed) || is_color(touch_shot, at(touch_info.x + 2.0, touch_info.y + 2.0), dimmed) { os.exit(118i32) }
    if testing.send(&harness, input.Event { PointerUp: testing.pointer_at(touch_point.x, touch_point.y) }) != ok || s.counters[4usize].count != 0usize { os.exit(119i32) }
    if testing.tap(&harness, 5.0, 5.0) != ok || s.counters[8usize].count != 2usize { os.exit(120i32) }
    let (touch_context_done, touch_context_done_error) = build(&f, &touch_theme, s, .ContextTouch)
    if touch_context_done_error != ok || testing.pump(&harness, touch_context_done, time.Instant { nanos: 2020000000i64 }) != ok || testing.by_key(&harness, 400u64).count != 0usize { os.exit(121i32) }
    let (touch_done_tree, touch_done_tree_error) = testing.semantics(&harness)
    if touch_done_tree_error != ok { os.exit(122i32) }
    let (touch_done_target, has_touch_done_target) = find(touch_done_tree, .Group, "Actions for Info")
    if !has_touch_done_target || accessibility.perform(&runtime, touch_done_target.id, .ShowMenu, "") != ok || s.counters[8usize].count != 3usize { os.exit(123i32) }
    if accessibility.perform(&runtime, touch_done_target.id, .ShowMenu, "") != ok || s.counters[8usize].count != 4usize { os.exit(124i32) }
    // A second hold followed by a drag onto Rename arms that row; release runs
    // the leaf, closes the menu and still does not press the original target.
    if testing.send(&harness, input.Event { PointerDown: testing.pointer_at(touch_point.x, touch_point.y) }) != ok { os.exit(125i32) }
    let drag_held = time.Instant { nanos: 2030000000i64 }
    if testing.begin(&harness, drag_held) != ok { os.exit(126i32) }
    let (drag_wait, drag_wait_error) = build(&f, &touch_theme, s, .ContextTouch)
    if drag_wait_error != ok || testing.pump(&harness, drag_wait, drag_held) != ok { os.exit(127i32) }
    let drag_due = time.Instant { nanos: 2530000000i64 }
    if testing.begin(&harness, drag_due) != ok { os.exit(128i32) }
    let (drag_due_root, drag_due_error) = build(&f, &touch_theme, s, .ContextTouch)
    if drag_due_error != ok || testing.pump(&harness, drag_due_root, drag_due) != ok || s.counters[8usize].count != 5usize { os.exit(129i32) }
    let drag_open = time.Instant { nanos: 2530000001i64 }
    if testing.begin(&harness, drag_open) != ok { os.exit(130i32) }
    let (drag_open_root, drag_open_error) = build(&f, &touch_theme, s, .ContextTouch)
    if drag_open_error != ok || testing.pump(&harness, drag_open_root, drag_open) != ok { os.exit(131i32) }
    let (rename_row, has_rename_row) = bounds(&harness, &runtime, 402u64)
    if !has_rename_row { os.exit(132i32) }
    let rename_at = geometry.Point { x: rename_row.x + rename_row.width * 0.5, y: rename_row.y + rename_row.height * 0.5 }
    if testing.send(&harness, input.Event { PointerMove: testing.pointer_at(rename_at.x, rename_at.y) }) != ok || !widget.interaction(&runtime, 402u64).pressed { os.exit(133i32) }
    let leaf_before = s.counters[1usize].count
    if testing.send(&harness, input.Event { PointerUp: testing.pointer_at(rename_at.x, rename_at.y) }) != ok || s.counters[1usize].count != leaf_before + 1usize || s.counters[8usize].count != 6usize || s.counters[4usize].count != 0usize { os.exit(134i32) }
    let (drag_done, drag_done_error) = build(&f, &touch_theme, s, .ContextTouch)
    if drag_done_error != ok || testing.pump(&harness, drag_done, time.Instant { nanos: 2540000000i64 }) != ok || testing.by_key(&harness, 400u64).count != 0usize { os.exit(135i32) }
    // Rich tooltips wait 500 ms, bridge the pointer's 4px crossing for 300 ms,
    // remain for focus inside either surface, and dismiss on Escape.
    let rich_start = time.Instant { nanos: 3000000000i64 }
    if testing.hover(&harness, 5.0, 470.0) != ok || testing.begin(&harness, rich_start) != ok { os.exit(136i32) }
    let (rich_closed, rich_closed_error) = build(&f, &theme, s, .Rich)
    if rich_closed_error != ok || testing.pump(&harness, rich_closed, rich_start) != ok || testing.by_key(&harness, 300u64).count != 0usize { os.exit(137i32) }
    let (rich_info, has_rich_info) = bounds(&harness, &runtime, 3u64)
    if !has_rich_info || testing.hover(&harness, rich_info.x + rich_info.width * 0.5, rich_info.y + rich_info.height * 0.5) != ok { os.exit(138i32) }
    if testing.begin(&harness, rich_start) != ok { os.exit(139i32) }
    let (rich_wait, rich_wait_error) = build(&f, &theme, s, .Rich)
    if rich_wait_error != ok || testing.pump(&harness, rich_wait, rich_start) != ok || testing.by_key(&harness, 300u64).count != 0usize || !widget.animation_frame_requested(&runtime) { os.exit(140i32) }
    let rich_almost = time.Instant { nanos: 3499999999i64 }
    if testing.begin(&harness, rich_almost) != ok { os.exit(141i32) }
    let (rich_almost_root, rich_almost_error) = build(&f, &theme, s, .Rich)
    if rich_almost_error != ok || testing.pump(&harness, rich_almost_root, rich_almost) != ok || testing.by_key(&harness, 300u64).count != 0usize { os.exit(142i32) }
    let rich_due = time.Instant { nanos: 3500000000i64 }
    if testing.begin(&harness, rich_due) != ok { os.exit(143i32) }
    let (rich_open, rich_open_error) = build(&f, &theme, s, .Rich)
    if rich_open_error != ok || testing.pump(&harness, rich_open, rich_due) != ok { os.exit(144i32) }
    let (rich_bounds, has_rich_bounds) = lifted(&harness, 300u64)
    let (rich_action, has_rich_action) = bounds(&harness, &runtime, 301u64)
    if !has_rich_bounds || !has_rich_action || !near(rich_action.height, 40.0) { os.exit(145i32) }
    if testing.hover(&harness, rich_bounds.x + 8.0, rich_bounds.y + 20.0) != ok { os.exit(146i32) }
    let rich_cross = time.Instant { nanos: 3500000001i64 }
    if testing.begin(&harness, rich_cross) != ok { os.exit(147i32) }
    let (rich_cross_root, rich_cross_error) = build(&f, &theme, s, .Rich)
    if rich_cross_error != ok || testing.pump(&harness, rich_cross_root, rich_cross) != ok || testing.by_key(&harness, 300u64).count != 1usize { os.exit(148i32) }
    if testing.hover(&harness, 5.0, 470.0) != ok { os.exit(149i32) }
    let rich_leave = time.Instant { nanos: 3500000002i64 }
    if testing.begin(&harness, rich_leave) != ok { os.exit(150i32) }
    let (rich_grace, rich_grace_error) = build(&f, &theme, s, .Rich)
    if rich_grace_error != ok || testing.pump(&harness, rich_grace, rich_leave) != ok || testing.by_key(&harness, 300u64).count != 1usize || !widget.animation_frame_requested(&runtime) { os.exit(151i32) }
    let rich_grace_almost = time.Instant { nanos: 3800000001i64 }
    if testing.begin(&harness, rich_grace_almost) != ok { os.exit(152i32) }
    let (rich_grace_almost_root, rich_grace_almost_error) = build(&f, &theme, s, .Rich)
    if rich_grace_almost_error != ok || testing.pump(&harness, rich_grace_almost_root, rich_grace_almost) != ok || testing.by_key(&harness, 300u64).count != 1usize { os.exit(153i32) }
    let rich_gone_at = time.Instant { nanos: 3800000002i64 }
    if testing.begin(&harness, rich_gone_at) != ok { os.exit(154i32) }
    let (rich_gone, rich_gone_error) = build(&f, &theme, s, .Rich)
    if rich_gone_error != ok || testing.pump(&harness, rich_gone, rich_gone_at) != ok || testing.by_key(&harness, 300u64).count != 0usize { os.exit(155i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 30u64).element) != ok { os.exit(156i32) }
    let rich_focus_at = time.Instant { nanos: 3900000000i64 }
    if testing.begin(&harness, rich_focus_at) != ok { os.exit(157i32) }
    let (rich_focused, rich_focused_error) = build(&f, &theme, s, .Rich)
    if rich_focused_error != ok || testing.pump(&harness, rich_focused, rich_focus_at) != ok || testing.by_key(&harness, 300u64).count != 1usize { os.exit(158i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 301u64).element) != ok || testing.hover(&harness, 5.0, 470.0) != ok { os.exit(159i32) }
    let rich_action_focus_at = time.Instant { nanos: 4300000000i64 }
    if testing.begin(&harness, rich_action_focus_at) != ok { os.exit(160i32) }
    let (rich_action_focused, rich_action_focused_error) = build(&f, &theme, s, .Rich)
    if rich_action_focused_error != ok || testing.pump(&harness, rich_action_focused, rich_action_focus_at) != ok || testing.by_key(&harness, 300u64).count != 1usize { os.exit(161i32) }
    if testing.press_key(&harness, 27u32, zero) != ok { os.exit(162i32) }
    let rich_escape_at = time.Instant { nanos: 4300000001i64 }
    if testing.begin(&harness, rich_escape_at) != ok { os.exit(163i32) }
    let (rich_escaped, rich_escaped_error) = build(&f, &theme, s, .Rich)
    if rich_escaped_error != ok || testing.pump(&harness, rich_escaped, rich_escape_at) != ok || testing.by_key(&harness, 300u64).count != 0usize { os.exit(164i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(51i32) }
    try io.print("ui overlays v2 ok\n")
    ret ok
}
