// The v2 menus and tooltips (D975, widget plan P5-11, docs/ux/components/Menu,
// ContextMenu, Tooltip) under the light theme: a pointer menu 4 below its
// button on `surface-container`, 4 above and below its 32 rows, a group head and
// a separator between them, a checked and a disabled command; Down, Up, Home and
// End move the focus (skipping the disabled one, wrapping), Enter runs, Escape
// dismisses, a hovered row takes the `on-surface` layer; the touch menu's rows
// 48 tall under an 8 rim; a context menu at the pointer flipped to its start and
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
use e.ui.layout as ui_layout
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

type Counter = struct { count: usize }

// The counters: 0 New, 1 the other commands, 2 dismiss, 3 Learn more, 4 anchors.
type Store = struct { counters: [8]Counter, subs: [8]widget.Submit, commands: [5]overlay.MenuCommand, pops: [2]overlay.MenuCommand, tips: [1]overlay.MenuItem }

type Which = enum u8 { Menu, Touch, Pointed, Keyboard }

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
    let (info, e3) = control.button(a, 3u64, t, "Info", &s.subs[4usize], control.button_options())
    let (menu, e4) = overlay.menu_of(a, 100u64, t, 1u64, "File", s.commands[0usize..5usize], which == .Menu || which == .Touch, &s.subs[2usize])
    let (tip, e5) = overlay.tooltip_of(a, 200u64, t, 2u64, "Save file", "Ctrl+S", true)
    let (high, e6) = overlay.tooltip(a, 210u64, t, 1u64, "File menu", true)
    let (rich, e7) = overlay.rich_tooltip(a, 300u64, t, 3u64, "Incremental builds", "Only changed modules are rebuilt.", s.tips[0usize..1usize], true)
    let pointer = geometry.Point { x: 600.0, y: 460.0 }
    let (context, e8) = overlay.context_menu_of(a, 400u64, t, 3u64, "Actions for Info", s.pops[0usize..2usize], which == .Pointed || which == .Keyboard, &s.subs[2usize], pointer, which == .Pointed)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (zero, e1) }
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
    while i < 8usize {
        s.subs[i] = widget.Submit { ctx: mem.cast[*void](&s.counters[i]), invoke: on_count }
        i += 1usize
    }
    s.commands[0usize] = overlay.menu_command("New", s.subs[0usize])
    s.commands[0usize].shortcut = "Ctrl+N"
    s.commands[1usize] = overlay.menu_command("Word wrap", s.subs[1usize])
    s.commands[1usize].checked = true
    s.commands[2usize] = overlay.menu_command("Minimap", s.subs[1usize])
    s.commands[2usize].head = "View"
    s.commands[3usize] = overlay.menu_command("Quit", s.subs[1usize])
    s.commands[3usize].enabled = false
    s.commands[4usize] = overlay.menu_command("Delete", s.subs[1usize])
    s.commands[4usize].separated = true
    s.commands[4usize].destructive = true
    s.pops[0usize] = overlay.menu_command("Open", s.subs[1usize])
    s.pops[1usize] = overlay.menu_command("Rename", s.subs[1usize])
    s.tips[0usize] = overlay.MenuItem { label: "Learn more", action: s.subs[3usize], enabled: true }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, s, .Menu)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
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
    // The group head (8 above, 4 below its line) before Minimap; the separator
    // (4, 1, 4) before Delete, a 1px `outline-variant` line.
    let (wrap_row, has_wrap) = bounds(&harness, &runtime, 102u64)
    let (mini_row, has_mini) = bounds(&harness, &runtime, 103u64)
    let (quit_row, has_quit) = bounds(&harness, &runtime, 104u64)
    let (delete_row, has_delete) = bounds(&harness, &runtime, 105u64)
    if !has_wrap || !has_mini || !has_quit || !has_delete || !near(wrap_row.y, new_row.y + 32.0) || !near(mini_row.y, wrap_row.y + 44.0) || !near(delete_row.y, quit_row.y + 41.0) { os.exit(16i32) }
    if !is_color(shot, at(menu.x + 100.0, quit_row.y + 36.0), style.color(&tokens, .OutlineVariant)) || !is_color(shot, at(menu.x + 100.0, quit_row.y + 34.0), style.color(&tokens, .SurfaceContainer)) { os.exit(17i32) }
    if !near(menu.height, 4.0 + 32.0 * 5.0 + 12.0 + 9.0 + 4.0) { os.exit(18i32) }
    // The tree: a menu named File, its commands MenuItems, Word wrap checked and
    // Quit disabled.
    let (menu_node, has_menu_node) = find(tree, .Menu, "File")
    let (wrap_node, has_wrap_node) = find(tree, .MenuItem, "Word wrap")
    let (quit_node, has_quit_node) = find(tree, .MenuItem, "Quit")
    if !has_menu_node || !has_wrap_node || !wrap_node.state.checked || !has_quit_node || !quit_node.state.disabled || testing.by_role(&harness, .MenuItem).count != 5usize { os.exit(19i32) }
    // The keys: the focus starts on New; Down walks, skipping Quit, and wraps; Up
    // wraps back; End and Home jump; Enter runs New; Escape dismisses.
    if !focus_is(&harness, 101u64) { os.exit(20i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !focus_is(&harness, 102u64) { os.exit(21i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || testing.press_key(&harness, 40u32, zero) != ok || !focus_is(&harness, 105u64) { os.exit(22i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !focus_is(&harness, 101u64) { os.exit(23i32) }
    if testing.press_key(&harness, 38u32, zero) != ok || !focus_is(&harness, 105u64) { os.exit(24i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !focus_is(&harness, 101u64) { os.exit(25i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !focus_is(&harness, 105u64) { os.exit(26i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || testing.press_key(&harness, 13u32, zero) != ok || s.counters[0usize].count != 1usize { os.exit(27i32) }
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
    // Touch density: 48 rows under an 8 rim, 112 wide at least.
    let (root_3, build_3_error) = build(&f, &touch_theme, s, .Touch)
    if build_3_error != ok || testing.pump(&harness, root_3, time.Instant { nanos: 1200000000i64 }) != ok { os.exit(41i32) }
    let (touch_menu, has_touch_menu) = lifted(&harness, 100u64)
    let (touch_row, has_touch_row) = bounds(&harness, &runtime, 101u64)
    if !has_touch_menu || !has_touch_row || !near(touch_row.height, 48.0) || !near(touch_row.y, touch_menu.y + 8.0) || touch_menu.width < 112.0 { os.exit(42i32) }
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
    // A press outside dismisses and does not reach Save.
    if testing.tap(&harness, save.x + 4.0, save.y + 4.0) != ok || s.counters[2usize].count != 2usize || s.counters[4usize].count != 0usize { os.exit(47i32) }
    // From the keyboard: below Info at its start edge.
    let (root_5, build_5_error) = build(&f, &theme, s, .Keyboard)
    if build_5_error != ok || testing.pump(&harness, root_5, time.Instant { nanos: 1400000000i64 }) != ok { os.exit(48i32) }
    let (below, has_below) = lifted(&harness, 400u64)
    if !has_below || !near(below.x, info.x) { os.exit(49i32) }
    if !near(below.y, info.y + info.height) && !near(below.y + below.height, info.y) { os.exit(50i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(51i32) }
    try io.print("ui overlays v2 ok\n")
    ret ok
}
