// The v2 breadcrumbs, tabs and menu bar (D972, widget plan P5-10,
// docs/ux/components/Breadcrumbs, Tabs, MenuBar) under the light theme at pointer
// density: 32 tall crumbs 16 apart across the `chevron-right`, the middle levels
// in a "Show 2 hidden levels" crumb opening a menu of them, the current place
// marked Current; the compact trail the parent link alone, 48 tall; a primary
// tab bar of 40 tall tabs 8 in, the 3px `primary` indicator under the active tab
// over the 1px `outline-variant` line, Home and End picking the ends; a
// secondary fixed bar sharing its width with a 2px line across the active tab;
// a 32 tall menu bar on `surface` whose open 24 tall title is
// `secondary-container`, its menu 2 below on `surface-container`, 32 tall
// commands, a separator, a checked command and Escape closing.

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
use e.ui.navigation
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

type Counter = struct { count: usize }

// The counters: 0-4 crumbs, 5 overflow toggle, 6-8 tabs, 9 menu toggles, 10
// commands.
type Store = struct { counters: [12]Counter, subs: [12]widget.Submit, crumbs: [5]widget.Submit, tabs: [3]widget.Submit, toggles: [2]widget.Submit, file: [4]navigation.BarCommand, edit: [1]navigation.BarCommand, menus: [2]navigation.BarMenu }

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

fn same_element(a: widget.ElementId, b: widget.ElementId) -> bool {
    ret a.slot == b.slot && a.generation == b.generation
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store, open_trail: bool, open_menu: usize) -> (widget.Node, err) {
    var names: [5]str = zero
    names[0usize] = "Workspace"
    names[1usize] = "lib"
    names[2usize] = "e"
    names[3usize] = "ui"
    names[4usize] = "navigation.e"
    var folded = navigation.breadcrumbs_options()
    folded.hidden = 2usize
    folded.open = open_trail
    folded.toggle = s.subs[5usize]
    let (trail, e1) = navigation.breadcrumbs_of(a, 2000u64, t, "Location", names[..], s.crumbs[0usize..5usize], folded)
    var narrow = navigation.breadcrumbs_options()
    narrow.compact = true
    let (parent, e2) = navigation.breadcrumbs_of(a, 2100u64, t, "Up", names[0usize..3usize], s.crumbs[0usize..3usize], narrow)
    var labels: [3]str = zero
    labels[0usize] = "Overview"
    labels[1usize] = "Builds"
    labels[2usize] = "Settings"
    let (primary, e3) = control.tabs(a, 2200u64, t, labels[..], 1usize, s.tabs[0usize..3usize])
    var fixed = control.tabs_options()
    fixed.secondary = true
    fixed.fixed = true
    fixed.width = 300.0
    let (secondary, e4) = control.tabs_of(a, 2300u64, t, labels[0usize..2usize], 0usize, s.tabs[0usize..2usize], fixed)
    let (menus, e5) = navigation.menu_bar_of(a, 2400u64, t, "Menu bar", s.menus[0usize..2usize], open_menu, s.toggles[0usize..2usize])
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (zero, e1) }
    let (items, items_error) = mem.alloc[widget.Node](a, 5usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = trail
    items[1usize] = parent
    items[2usize] = primary
    items[3usize] = secondary
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = menus
    items[4usize] = widget.box(0u64, control.sized_style(600.0, 32.0), held[0usize..1usize])
    var page_style = style.defaults()
    page_style.width = style.Length { Px: 640.0 }
    page_style.height = style.Length { Px: 520.0 }
    page_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHighest) }
    let pad = style.Length { Px: 10.0 }
    page_style.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page_style, items[0usize..5usize]), ok)
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

fn tap_key(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> bool {
    let (b, found) = bounds(h, runtime, key)
    if !found { ret false }
    ret testing.tap(h, b.x + b.width * 0.5, b.y + b.height * 0.5) == ok
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn current_count(tree: accessibility.Tree) -> usize {
    var n = 0usize
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].state.current { n += 1usize }
        i += 1usize
    }
    ret n
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 600usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 32u16, max_commands: 2048usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 640u32, 520u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    var i = 0usize
    while i < 12usize {
        s.subs[i] = widget.Submit { ctx: mem.cast[*void](&s.counters[i]), invoke: on_count }
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        s.crumbs[i] = s.subs[i]
        i += 1usize
    }
    s.tabs[0usize] = s.subs[6usize]
    s.tabs[1usize] = s.subs[7usize]
    s.tabs[2usize] = s.subs[8usize]
    s.toggles[0usize] = s.subs[9usize]
    s.toggles[1usize] = s.subs[9usize]
    var command: navigation.BarCommand = zero
    command.action = s.subs[10usize]
    command.enabled = true
    s.file[0usize] = command
    s.file[0usize].label = "New"
    s.file[0usize].shortcut = "Ctrl+N"
    s.file[1usize] = command
    s.file[1usize].label = "Open"
    s.file[2usize] = command
    s.file[2usize].label = "Autosave"
    s.file[2usize].checked = true
    s.file[2usize].separated = true
    s.file[3usize] = command
    s.file[3usize].label = "Delete"
    s.file[3usize].destructive = true
    s.file[3usize].enabled = false
    s.edit[0usize] = command
    s.edit[0usize].label = "Undo"
    s.menus[0usize] = navigation.BarMenu { label: "File", commands: s.file[0usize..4usize] }
    s.menus[1usize] = navigation.BarMenu { label: "Edit", commands: s.edit[0usize..1usize] }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, s, false, 9usize)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    // The trail: Workspace, the overflow crumb over lib and e, ui, and the
    // current place; crumbs 32 tall, 16 apart across the chevron.
    let (root_crumb, has_root) = bounds(&harness, &runtime, 2001u64)
    let (more, has_more) = bounds(&harness, &runtime, 2040u64)
    let (ui_crumb, has_ui) = bounds(&harness, &runtime, 2004u64)
    if !has_root || !has_more || !has_ui || !near(root_crumb.height, 32.0) || !near(more.x, root_crumb.x + root_crumb.width + 16.0) || !near(ui_crumb.x, more.x + more.width + 16.0) { os.exit(13i32) }
    if testing.by_key(&harness, 2002u64).count != 0usize || testing.by_key(&harness, 2003u64).count != 0usize { os.exit(14i32) }
    let (folded, has_folded) = find(tree, .Button, "Show 2 hidden levels")
    let (trail, has_trail) = find(tree, .Group, "Location")
    if !has_folded || folded.state.expanded || !has_trail || current_count(tree) != 1usize { os.exit(15i32) }
    if !tap_key(&harness, &runtime, 2001u64) || s.counters[0usize].count != 1usize || !tap_key(&harness, &runtime, 2040u64) || s.counters[5usize].count != 1usize { os.exit(16i32) }
    // Compact: the parent link alone, 48 tall.
    let (up, has_up) = bounds(&harness, &runtime, 2102u64)
    if !has_up || !near(up.height, 48.0) || testing.by_key(&harness, 2101u64).count != 0usize || !tap_key(&harness, &runtime, 2102u64) || s.counters[1usize].count != 1usize { os.exit(17i32) }
    // The primary bar: 40 tall tabs 8 in; the indicator under Builds only; the
    // line below.
    let (bar, has_bar) = bounds(&harness, &runtime, 2200u64)
    let (overview, has_overview) = bounds(&harness, &runtime, 2201u64)
    let (builds, has_builds) = bounds(&harness, &runtime, 2202u64)
    if !has_bar || !has_overview || !has_builds || !near(builds.height, 40.0) || !near(overview.x, bar.x + 8.0) || !near(bar.height, 41.0) { os.exit(18i32) }
    let mid = builds.x + builds.width * 0.5
    if !is_color(shot, at(mid, builds.y + 38.5), style.color(&tokens, .Primary)) || !is_color(shot, at(overview.x + overview.width * 0.5, overview.y + 38.5), style.color(&tokens, .Background)) { os.exit(19i32) }
    if !is_color(shot, at(mid - 20.0, builds.y + 38.5), style.color(&tokens, .Background)) || !is_color(shot, at(mid, bar.y + 40.5), style.color(&tokens, .OutlineVariant)) { os.exit(20i32) }
    // The keys: from the focused bar, End picks Settings and Home Overview.
    if !tap_key(&harness, &runtime, 2202u64) || s.counters[7usize].count != 1usize { os.exit(21i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || s.counters[8usize].count != 1usize || testing.press_key(&harness, 36u32, zero) != ok || s.counters[6usize].count != 1usize { os.exit(22i32) }
    // The secondary fixed bar: two tabs sharing 300, a 2px line across the first.
    let (first, has_first) = bounds(&harness, &runtime, 2301u64)
    let (second, has_second) = bounds(&harness, &runtime, 2302u64)
    if !has_first || !has_second || !near(first.width, 150.0) || !near(second.x, first.x + 150.0) { os.exit(23i32) }
    if !is_color(shot, at(first.x + 4.0, first.y + 38.5), style.color(&tokens, .Primary)) || !is_color(shot, at(second.x + 4.0, second.y + 38.5), style.color(&tokens, .Background)) || !is_color(shot, at(first.x + 4.0, first.y + 37.5), style.color(&tokens, .Background)) { os.exit(24i32) }
    // The menu bar: 32 tall on `surface`, its titles 24 tall 4 in; File opened
    // is `secondary-container` and Expanded, Edit closed.
    let (menus, has_menus) = bounds(&harness, &runtime, 2400u64)
    let (file, has_file) = bounds(&harness, &runtime, 2401u64)
    if !has_menus || !has_file || !near(menus.height, 32.0) || !near(file.height, 24.0) || !near(file.x, menus.x + 4.0) || !is_color(shot, at(menus.x + 300.0, menus.y + 16.0), style.color(&tokens, .Background)) { os.exit(25i32) }
    if testing.by_role(&harness, .MenuBar).count != 1usize { os.exit(36i32) }
    let original = testing.by_key(&harness, 2301u64).element
    if widget.focus(&runtime, original) != ok || testing.press_key(&harness, 65479u32, zero) != ok { os.exit(37i32) }
    let (on_file, has_on_file) = testing.focused(&harness)
    if !has_on_file || !same_element(on_file, testing.by_key(&harness, 2401u64).element) { os.exit(38i32) }
    if testing.press_key(&harness, 39u32, zero) != ok { os.exit(39i32) }
    let (on_edit, has_on_edit) = testing.focused(&harness)
    if !has_on_edit || !same_element(on_edit, testing.by_key(&harness, 2417u64).element) { os.exit(40i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || testing.press_key(&harness, 40u32, zero) != ok || s.counters[9usize].count != 1usize { os.exit(41i32) }
    s.counters[9usize].count = 0usize
    if testing.press_key(&harness, 27u32, zero) != ok { os.exit(42i32) }
    let (restored, has_restored) = testing.focused(&harness)
    if !has_restored || !same_element(restored, original) { os.exit(43i32) }
    // Releasing Alt alone enters the same mode on Windows and X; using Alt
    // with another key leaves focus alone.
    if testing.press_key(&harness, 18u32, zero) != ok { os.exit(45i32) }
    let (windows_alt, has_windows_alt) = testing.focused(&harness)
    if !has_windows_alt || !same_element(windows_alt, testing.by_key(&harness, 2401u64).element) || testing.press_key(&harness, 27u32, zero) != ok { os.exit(46i32) }
    if testing.press_key(&harness, 65513u32, zero) != ok { os.exit(47i32) }
    let (x_alt, has_x_alt) = testing.focused(&harness)
    if !has_x_alt || !same_element(x_alt, testing.by_key(&harness, 2401u64).element) || testing.press_key(&harness, 27u32, zero) != ok { os.exit(48i32) }
    var alt: input.Modifiers = zero
    alt.alt = true
    if testing.send(&harness, input.Event { KeyDown: input.KeyEvent { window: zero, key: input.Key { physical: 18u32, logical: 18u32 }, modifiers: alt, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyDown: input.KeyEvent { window: zero, key: input.Key { physical: 70u32, logical: 70u32 }, modifiers: alt, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyUp: input.KeyEvent { window: zero, key: input.Key { physical: 70u32, logical: 70u32 }, modifiers: alt, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyUp: input.KeyEvent { window: zero, key: input.Key { physical: 18u32, logical: 18u32 }, modifiers: zero, repeat: false } }) != ok { os.exit(49i32) }
    let (after_chord, has_after_chord) = testing.focused(&harness)
    if !has_after_chord || !same_element(after_chord, original) { os.exit(50i32) }
    let (root_3, build_3_error) = build(&f, &theme, s, false, 0usize)
    if build_3_error != ok || testing.pump(&harness, root_3, time.Instant { nanos: 1050000000i64 }) != ok { os.exit(26i32) }
    let (shot_3, shot_3_error) = testing.snapshot(&harness, a)
    let (tree_3, tree_3_error) = testing.semantics(&harness)
    if shot_3_error != ok || tree_3_error != ok || !is_color(shot_3, at(file.x + 8.0, file.y + 12.0), style.color(&tokens, .SecondaryContainer)) { os.exit(26i32) }
    let (file_node, has_file_node) = find(tree_3, .Button, "File")
    let (edit_node, has_edit_node) = find(tree_3, .Button, "Edit")
    if !has_file_node || !file_node.state.expanded || !has_edit_node || edit_node.state.expanded { os.exit(27i32) }
    // Right follows an open menu to its neighbour and fires that title.
    if testing.press_key(&harness, 39u32, zero) != ok || s.counters[9usize].count != 1usize { os.exit(44i32) }
    let (followed, has_followed) = testing.focused(&harness)
    if !has_followed || !same_element(followed, testing.by_key(&harness, 2417u64).element) { os.exit(44i32) }
    s.counters[9usize].count = 0usize
    // Its menu 2 below on `surface-container`, at least 200 wide; four commands
    // 32 tall, a separator line before Autosave, Autosave checked, Delete
    // disabled.
    let (menu, has_menu) = testing.overlay_of(&harness, testing.by_key(&harness, 2402u64).element)
    if !has_menu || !near(menu.y, file.y + 26.0) || menu.width < 200.0 || !is_color(shot_3, at(menu.x + 100.0, menu.y + 4.0), style.color(&tokens, .SurfaceContainer)) { os.exit(28i32) }
    let (open_row, has_open_row) = bounds(&harness, &runtime, 2404u64)
    let (auto_row, has_auto_row) = bounds(&harness, &runtime, 2405u64)
    if !has_open_row || !has_auto_row || !near(open_row.height, 32.0) || !near(auto_row.y, open_row.y + 49.0) || !is_color(shot_3, at(menu.x + 100.0, open_row.y + 40.5), style.color(&tokens, .OutlineVariant)) { os.exit(29i32) }
    let (auto_node, has_auto_node) = find(tree_3, .MenuItem, "Autosave")
    let (delete_node, has_delete_node) = find(tree_3, .MenuItem, "Delete")
    if testing.by_role(&harness, .MenuItem).count != 4usize || !has_auto_node || !auto_node.state.checked || !has_delete_node || !delete_node.state.disabled { os.exit(30i32) }
    if !tap_key(&harness, &runtime, 2403u64) || s.counters[10usize].count != 1usize || testing.press_key(&harness, 27u32, zero) != ok || s.counters[9usize].count != 1usize { os.exit(31i32) }
    // The overflow crumb open: Expanded, its menu holding lib and e in order.
    let (root_2, build_2_error) = build(&f, &theme, s, true, 9usize)
    if build_2_error != ok || testing.pump(&harness, root_2, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(32i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(33i32) }
    let (folded_2, has_folded_2) = find(tree_2, .Button, "Show 2 hidden levels")
    let (lib_item, has_lib) = find(tree_2, .MenuItem, "lib")
    let (e_item, has_e) = find(tree_2, .MenuItem, "e")
    if !has_folded_2 || !folded_2.state.expanded || !has_lib || !has_e || e_item.bounds.y <= lib_item.bounds.y { os.exit(34i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(35i32) }
    try io.print("ui navigation2 v2 ok\n")
    ret ok
}
