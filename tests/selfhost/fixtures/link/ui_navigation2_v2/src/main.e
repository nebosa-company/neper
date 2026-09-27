// The v2 breadcrumbs, tabs and menu bar (D972, widget plan P5-10,
// docs/ux/components/Breadcrumbs, Tabs, MenuBar) under the light theme at pointer
// density: 32 tall crumbs 16 apart across a direction-mirrored chevron, the middle levels
// in a "Show 2 hidden levels" crumb opening a menu of them, the current place
// marked Current; the compact trail the parent link alone, 48 tall; a primary
// tab bar of 40 tall tabs 8 in, the 3px `primary` indicator under the active tab
// over the 1px `outline-variant` line, Home and End picking the ends; a
// secondary fixed bar sharing its width with a 2px line across the active tab;
// a 32 tall menu bar on `surface` whose open 24 tall title is
// `secondary-container`, its menu 2 below on `surface-container`, 32 tall
// commands with aligned icon/check/radio slots, a separator, and one right-side
// submenu opened by keyboard or 200 ms hover with a safe diagonal path into it.

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
// commands, 11-12 submenu toggles, 13 the deep command.
type Store = struct { counters: [14]Counter, subs: [14]widget.Submit, crumbs: [5]widget.Submit, tabs: [3]widget.Submit, toggles: [2]widget.Submit, file: [5]navigation.BarCommand, submenu: [2]navigation.BarCommand, deep: [1]navigation.BarCommand, edit: [1]navigation.BarCommand, menus: [2]navigation.BarMenu }

fn on_count(ctx: *void) -> err {
    let c = mem.cast[*Counter](ctx)
    c.count += 1usize
    ret ok
}

// (D1361) A drag source: its drag carries payload 77; and a crumb drop, kept as
// the index plus one and the payload.
fn start_carry(ctx: *void, g: widget.Gesture) -> err {
    switch g {
    case .DragStart as began:
        ret widget.begin_drag(mem.cast[*widget.Runtime](ctx), 77u64)
    default:
        ret ok
    }
}

type CrumbLog = struct { index: u64, payload: u64 }

fn on_crumb_drop(ctx: *void, value: navigation.CrumbDrop) -> err {
    let kept = mem.cast[*CrumbLog](ctx)
    kept.index = u64(value.index) + 1u64
    kept.payload = value.payload
    ret ok
}

// (D1326) A sibling chevron's report, kept as the index plus one.
fn on_sibling(ctx: *void, value: usize) -> err {
    let seen = mem.cast[*usize](ctx)
    *seen = value + 1usize
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

fn has_action(node: accessibility.Node, wanted: accessibility.Action) -> bool {
    var i = 0usize
    while i < node.actions.len {
        if node.actions[i] == wanted { ret true }
        i += 1usize
    }
    ret false
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
    while i < 14usize {
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
    s.file[0usize].pictured = true
    s.file[0usize].glyph = .Picture
    s.file[1usize] = command
    s.file[1usize].label = "Open"
    s.file[2usize] = command
    s.file[2usize].label = "Other"
    s.file[3usize] = command
    s.file[3usize].label = "Autosave"
    s.file[3usize].checkable = true
    s.file[3usize].checked = true
    s.file[3usize].separated = true
    s.file[4usize] = command
    s.file[4usize].label = "Delete"
    s.file[4usize].destructive = true
    s.file[4usize].enabled = false
    s.submenu[0usize] = command
    s.submenu[0usize].label = "Recent"
    s.submenu[0usize].radio = true
    s.submenu[0usize].checked = true
    s.submenu[1usize] = command
    s.submenu[1usize].label = "Workspace"
    s.submenu[1usize].radio = true
    s.deep[0usize] = command
    s.deep[0usize].label = "Pinned"
    s.deep[0usize].action = s.subs[13usize]
    s.submenu[1usize].submenu = s.deep[..]
    s.submenu[1usize].submenu_toggle = s.subs[12usize]
    s.file[2usize].submenu = s.submenu[..]
    s.file[2usize].submenu_toggle = s.subs[11usize]
    s.edit[0usize] = command
    s.edit[0usize].label = "Undo"
    s.menus[0usize] = navigation.BarMenu { label: "File", commands: s.file[0usize..5usize] }
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
    var alt_held: input.Modifiers = zero
    alt_held.alt = true
    if testing.send(&harness, input.Event { KeyDown: input.KeyEvent { window: zero, key: input.Key { physical: 18u32, logical: 18u32 }, modifiers: alt_held, repeat: false } }) != ok || !widget.menu_access_keys_visible(&runtime) { os.exit(63i32) }
    let (root_alt, root_alt_error) = build(&f, &theme, s, false, 9usize)
    if root_alt_error != ok || testing.pump(&harness, root_alt, time.Instant { nanos: 1010000000i64 }) != ok { os.exit(63i32) }
    let (shot_alt, shot_alt_error) = testing.snapshot(&harness, a)
    if shot_alt_error != ok { os.exit(64i32) }
    if testing.send(&harness, input.Event { KeyDown: input.KeyEvent { window: zero, key: input.Key { physical: 90u32, logical: 90u32 }, modifiers: alt_held, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyUp: input.KeyEvent { window: zero, key: input.Key { physical: 90u32, logical: 90u32 }, modifiers: alt_held, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyUp: input.KeyEvent { window: zero, key: input.Key { physical: 18u32, logical: 18u32 }, modifiers: zero, repeat: false } }) != ok || widget.menu_access_keys_visible(&runtime) { os.exit(65i32) }
    let original = testing.by_key(&harness, 2301u64).element
    if widget.focus(&runtime, original) != ok || testing.press_key(&harness, 65479u32, zero) != ok { os.exit(37i32) }
    let (on_file, has_on_file) = testing.focused(&harness)
    if !has_on_file || !same_element(on_file, testing.by_key(&harness, 2401u64).element) { os.exit(38i32) }
    if testing.press_key(&harness, 39u32, zero) != ok { os.exit(39i32) }
    let (on_edit, has_on_edit) = testing.focused(&harness)
    if !has_on_edit || !same_element(on_edit, testing.by_key(&harness, 2657u64).element) { os.exit(40i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || testing.press_key(&harness, 40u32, zero) != ok || s.counters[9usize].count != 1usize { os.exit(41i32) }
    s.counters[9usize].count = 0usize
    if testing.press_key(&harness, 27u32, zero) != ok { os.exit(42i32) }
    let (restored, has_restored) = testing.focused(&harness)
    if !has_restored || !same_element(restored, original) { os.exit(43i32) }
    // Releasing Alt alone enters the same mode on Windows and X; Alt+F opens
    // File, while an unmatched Alt chord leaves focus alone.
    if testing.press_key(&harness, 18u32, zero) != ok { os.exit(45i32) }
    let (windows_alt, has_windows_alt) = testing.focused(&harness)
    if !has_windows_alt || !same_element(windows_alt, testing.by_key(&harness, 2401u64).element) || testing.press_key(&harness, 27u32, zero) != ok { os.exit(46i32) }
    if testing.press_key(&harness, 65513u32, zero) != ok { os.exit(47i32) }
    let (x_alt, has_x_alt) = testing.focused(&harness)
    if !has_x_alt || !same_element(x_alt, testing.by_key(&harness, 2401u64).element) || testing.press_key(&harness, 27u32, zero) != ok { os.exit(48i32) }
    var alt: input.Modifiers = zero
    alt.alt = true
    if testing.send(&harness, input.Event { KeyDown: input.KeyEvent { window: zero, key: input.Key { physical: 18u32, logical: 18u32 }, modifiers: alt, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyDown: input.KeyEvent { window: zero, key: input.Key { physical: 70u32, logical: 70u32 }, modifiers: alt, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyUp: input.KeyEvent { window: zero, key: input.Key { physical: 70u32, logical: 70u32 }, modifiers: alt, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyUp: input.KeyEvent { window: zero, key: input.Key { physical: 18u32, logical: 18u32 }, modifiers: zero, repeat: false } }) != ok { os.exit(49i32) }
    let (accessed, has_accessed) = testing.focused(&harness)
    if !has_accessed || !same_element(accessed, testing.by_key(&harness, 2401u64).element) || s.counters[9usize].count != 1usize || testing.press_key(&harness, 27u32, zero) != ok { os.exit(58i32) }
    s.counters[9usize].count = 0usize
    if testing.send(&harness, input.Event { KeyDown: input.KeyEvent { window: zero, key: input.Key { physical: 18u32, logical: 18u32 }, modifiers: alt, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyDown: input.KeyEvent { window: zero, key: input.Key { physical: 90u32, logical: 90u32 }, modifiers: alt, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyUp: input.KeyEvent { window: zero, key: input.Key { physical: 90u32, logical: 90u32 }, modifiers: alt, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyUp: input.KeyEvent { window: zero, key: input.Key { physical: 18u32, logical: 18u32 }, modifiers: zero, repeat: false } }) != ok { os.exit(49i32) }
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
    s.counters[9usize].count = 0usize
    if widget.focus(&runtime, original) != ok || testing.press_key(&harness, 65479u32, zero) != ok || testing.press_key(&harness, 40u32, zero) != ok || s.counters[9usize].count != 1usize || widget.focus(&runtime, testing.by_key(&harness, 2403u64).element) != ok { os.exit(54i32) }
    s.counters[9usize].count = 0usize
    if testing.send(&harness, input.Event { KeyDown: input.KeyEvent { window: zero, key: input.Key { physical: 18u32, logical: 18u32 }, modifiers: alt, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyDown: input.KeyEvent { window: zero, key: input.Key { physical: 78u32, logical: 78u32 }, modifiers: alt, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyUp: input.KeyEvent { window: zero, key: input.Key { physical: 78u32, logical: 78u32 }, modifiers: alt, repeat: false } }) != ok || testing.send(&harness, input.Event { KeyUp: input.KeyEvent { window: zero, key: input.Key { physical: 18u32, logical: 18u32 }, modifiers: zero, repeat: false } }) != ok { os.exit(59i32) }
    let (item_returned, has_item_returned) = testing.focused(&harness)
    if !has_item_returned || !same_element(item_returned, original) || s.counters[10usize].count != 1usize || s.counters[9usize].count != 1usize { os.exit(60i32) }
    s.counters[9usize].count = 0usize
    s.counters[10usize].count = 0usize
    if testing.press_key(&harness, 65479u32, zero) != ok || testing.press_key(&harness, 40u32, zero) != ok || widget.focus(&runtime, testing.by_key(&harness, 2403u64).element) != ok { os.exit(61i32) }
    s.counters[9usize].count = 0usize
    // Prefix typeahead expires after 500 ms: delayed T does not extend O, while
    // immediate O,T selects Other.
    if testing.press_key(&harness, 79u32, zero) != ok || testing.pump(&harness, root_3, time.Instant { nanos: 1600000000i64 }) != ok || testing.press_key(&harness, 84u32, zero) != ok { os.exit(52i32) }
    let (typed, has_typed) = testing.focused(&harness)
    if !has_typed || !same_element(typed, testing.by_key(&harness, 2404u64).element) || testing.pump(&harness, root_3, time.Instant { nanos: 2200000000i64 }) != ok || widget.focus(&runtime, testing.by_key(&harness, 2403u64).element) != ok || testing.press_key(&harness, 79u32, zero) != ok || testing.press_key(&harness, 84u32, zero) != ok { os.exit(53i32) }
    let (prefixed, has_prefixed) = testing.focused(&harness)
    if !has_prefixed || !same_element(prefixed, testing.by_key(&harness, 2405u64).element) { os.exit(62i32) }
    let (other_row, has_other_row) = bounds(&harness, &runtime, 2405u64)
    s.counters[11usize].count = 0usize
    if !has_other_row || testing.hover(&harness, other_row.x + other_row.width * 0.5, other_row.y + other_row.height * 0.5) != ok || s.counters[11usize].count != 0usize || !widget.animation_frame_requested(&runtime) { os.exit(63i32) }
    if testing.pump(&harness, root_3, time.Instant { nanos: 2399000000i64 }) != ok || s.counters[11usize].count != 0usize || !widget.animation_frame_requested(&runtime) { os.exit(64i32) }
    if testing.pump(&harness, root_3, time.Instant { nanos: 2400000000i64 }) != ok || s.counters[11usize].count != 1usize { os.exit(65i32) }
    s.counters[9usize].count = 0usize
    s.counters[10usize].count = 0usize
    s.counters[11usize].count = 0usize
    // Right opens the focused submenu; Left closes that level. Right on a leaf
    // still follows the top-level menu to its neighbour.
    if testing.press_key(&harness, 39u32, zero) != ok || s.counters[11usize].count != 1usize { os.exit(44i32) }
    s.file[2usize].submenu_open = true
    let (root_sub, root_sub_error) = build(&f, &theme, s, false, 0usize)
    if root_sub_error != ok || testing.pump(&harness, root_sub, time.Instant { nanos: 2210000000i64 }) != ok { os.exit(66i32) }
    let (tree_sub, tree_sub_error) = testing.semantics(&harness)
    if tree_sub_error != ok { os.exit(66i32) }
    let radio_count = testing.by_role(&harness, .MenuItemRadio).count
    let (other_node, has_other_node) = find(tree_sub, .MenuItem, "Other")
    let (recent_node, has_recent_node) = find(tree_sub, .MenuItemRadio, "Recent")
    if !has_other_node || !other_node.state.expanded || !has_action(other_node, .ShowMenu) || !same_element(other_node.relations.controls, testing.by_key(&harness, 2449u64).element) { os.exit(73i32) }
    if !has_recent_node || !recent_node.state.checked { os.exit(74i32) }
    if radio_count != 2usize { os.exit(75i32) }
    let (submenu_bounds, has_submenu_bounds) = testing.overlay_of(&harness, testing.by_key(&harness, 2449u64).element)
    let (auto_safe, has_auto_safe) = bounds(&harness, &runtime, 2406u64)
    if !has_submenu_bounds || !has_auto_safe || testing.hover(&harness, other_row.x + other_row.width * 0.5, other_row.y + other_row.height * 0.5) != ok || testing.hover(&harness, submenu_bounds.x - 1.0, auto_safe.y + auto_safe.height * 0.5) != ok || !widget.interaction(&runtime, 2406u64).hovered { os.exit(70i32) }
    if testing.pump(&harness, root_sub, time.Instant { nanos: 2410000000i64 }) != ok || s.counters[11usize].count != 1usize { os.exit(71i32) }
    if testing.hover(&harness, auto_safe.x + 8.0, auto_safe.y + auto_safe.height * 0.5) != ok || testing.pump(&harness, root_sub, time.Instant { nanos: 2610000000i64 }) != ok || s.counters[11usize].count != 2usize { os.exit(72i32) }
    s.counters[11usize].count = 1usize
    let (on_recent, has_on_recent) = testing.focused(&harness)
    if !has_on_recent || !same_element(on_recent, testing.by_key(&harness, 2450u64).element) { os.exit(67i32) }
    if testing.press_key(&harness, 13u32, zero) != ok { os.exit(67i32) }
    if s.counters[10usize].count != 1usize || s.counters[11usize].count != 2usize || s.counters[9usize].count != 1usize { os.exit(67i32) }
    let (sub_returned, has_sub_returned) = testing.focused(&harness)
    if !has_sub_returned || !same_element(sub_returned, original) { os.exit(67i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 2450u64).element) != ok || testing.press_key(&harness, 37u32, zero) != ok || s.counters[11usize].count != 3usize { os.exit(67i32) }
    // A second cascade level reuses the same menu behavior and closes the full
    // chain after its leaf runs.
    if widget.focus(&runtime, testing.by_key(&harness, 2451u64).element) != ok || testing.press_key(&harness, 39u32, zero) != ok || s.counters[12usize].count != 1usize { os.exit(76i32) }
    s.submenu[1usize].submenu_open = true
    let (root_deep, root_deep_error) = build(&f, &theme, s, false, 0usize)
    if root_deep_error != ok || testing.pump(&harness, root_deep, time.Instant { nanos: 2215000000i64 }) != ok { os.exit(77i32) }
    let (tree_deep, tree_deep_error) = testing.semantics(&harness)
    let (workspace_node, has_workspace_node) = find(tree_deep, .MenuItemRadio, "Workspace")
    if tree_deep_error != ok { os.exit(78i32) }
    if !has_workspace_node { os.exit(80i32) }
    if !workspace_node.state.expanded { os.exit(81i32) }
    if !has_action(workspace_node, .ShowMenu) { os.exit(82i32) }
    if !same_element(workspace_node.relations.controls, testing.by_key(&harness, 78385u64).element) { os.exit(83i32) }
    if testing.by_key(&harness, 78386u64).count != 1usize { os.exit(84i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 78386u64).element) != ok || testing.press_key(&harness, 13u32, zero) != ok || s.counters[13usize].count != 1usize || s.counters[12usize].count != 2usize || s.counters[11usize].count != 4usize || s.counters[9usize].count != 2usize { os.exit(79i32) }
    s.submenu[1usize].submenu_open = false
    s.counters[9usize].count = 0usize
    s.counters[10usize].count = 0usize
    s.file[2usize].submenu_open = false
    let (root_leaf, root_leaf_error) = build(&f, &theme, s, false, 0usize)
    if root_leaf_error != ok || testing.pump(&harness, root_leaf, time.Instant { nanos: 2220000000i64 }) != ok || widget.focus(&runtime, testing.by_key(&harness, 2406u64).element) != ok || testing.press_key(&harness, 39u32, zero) != ok || s.counters[9usize].count != 1usize { os.exit(68i32) }
    let (followed, has_followed) = testing.focused(&harness)
    if !has_followed || !same_element(followed, testing.by_key(&harness, 2657u64).element) { os.exit(44i32) }
    s.counters[9usize].count = 0usize
    let (edit_title, has_edit_title) = bounds(&harness, &runtime, 2657u64)
    if !has_edit_title || testing.hover(&harness, edit_title.x + edit_title.width * 0.5, edit_title.y + edit_title.height * 0.5) != ok || s.counters[9usize].count != 1usize { os.exit(51i32) }
    s.counters[9usize].count = 0usize
    // Its menu 2 below on `surface-container`, at least 200 wide; five commands
    // 32 tall, a separator line before Autosave, Autosave checked, Delete
    // disabled.
    // (D1432) The menu fades and slides 4 down over `duration-short-4` from its
    // first builds; look once it has arrived.
    var arrive_step = 0usize
    while arrive_step < 2usize {
        let arrive_at = time.Instant { nanos: 3000000000i64 + i64(arrive_step) * 500000000i64 }
        if testing.begin(&harness, arrive_at) != ok { os.exit(28i32) }
        let (root_menu_in, root_menu_in_error) = build(&f, &theme, s, false, 0usize)
        if root_menu_in_error != ok || testing.pump(&harness, root_menu_in, arrive_at) != ok { os.exit(28i32) }
        arrive_step += 1usize
    }
    let (shot_menu, shot_menu_error) = testing.snapshot(&harness, a)
    if shot_menu_error != ok { os.exit(28i32) }
    let (menu, has_menu) = testing.overlay_of(&harness, testing.by_key(&harness, 2402u64).element)
    if !has_menu || !near(menu.y, file.y + 26.0) || menu.width < 200.0 || !is_color(shot_menu, at(menu.x + 100.0, menu.y + 4.0), style.color(&tokens, .SurfaceContainer)) { os.exit(28i32) }
    let (open_row, has_open_row) = bounds(&harness, &runtime, 2404u64)
    let (auto_row, has_auto_row) = bounds(&harness, &runtime, 2406u64)
    if !has_open_row || !has_auto_row || !near(open_row.height, 32.0) || !near(auto_row.y, open_row.y + 81.0) || !is_color(shot_menu, at(menu.x + 100.0, open_row.y + 72.5), style.color(&tokens, .OutlineVariant)) { os.exit(29i32) }
    // The open menu's tree, taken now: `tree_3` predates the menu, and its storage
    // is the harness's, which every later query rebuilds (D1598 made the trees
    // smaller, and the menu's rows fell past `tree_3`'s old length).
    let (tree_menu, tree_menu_error) = testing.semantics(&harness)
    if tree_menu_error != ok { os.exit(30i32) }
    let (auto_node, has_auto_node) = find(tree_menu, .MenuItem, "Autosave")
    let (delete_node, has_delete_node) = find(tree_menu, .MenuItem, "Delete")
    let (auto_check, has_auto_check) = find(tree_menu, .MenuItemCheckbox, "Autosave")
    if testing.by_role(&harness, .MenuItem).count != 4usize || !has_auto_check || !auto_check.state.checked || has_auto_node || !has_delete_node || !delete_node.state.disabled { os.exit(30i32) }
    if widget.focus(&runtime, original) != ok || testing.press_key(&harness, 65479u32, zero) != ok || testing.press_key(&harness, 40u32, zero) != ok || widget.focus(&runtime, testing.by_key(&harness, 2403u64).element) != ok { os.exit(69i32) }
    s.counters[9usize].count = 0usize
    if !tap_key(&harness, &runtime, 2403u64) || s.counters[10usize].count != 1usize || s.counters[9usize].count != 1usize { os.exit(31i32) }
    let (returned, has_returned) = testing.focused(&harness)
    if !has_returned || !same_element(returned, original) { os.exit(55i32) }
    // The overflow crumb open: Expanded, its menu holding lib and e in order.
    let (root_2, build_2_error) = build(&f, &theme, s, true, 9usize)
    if build_2_error != ok || testing.pump(&harness, root_2, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(32i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(33i32) }
    let (folded_2, has_folded_2) = find(tree_2, .Button, "Show 2 hidden levels")
    let (lib_item, has_lib) = find(tree_2, .MenuItem, "lib")
    let (e_item, has_e) = find(tree_2, .MenuItem, "e")
    if !has_folded_2 || !folded_2.state.expanded || !has_lib || !has_e || e_item.bounds.y <= lib_item.bounds.y { os.exit(34i32) }
    // Right-to-left breadcrumbs keep their logical order but mirror both the
    // trail separators and the compact parent chevron.
    var rtl_tokens = style.reference(.Light)
    rtl_tokens.direction = .RightToLeft
    let rtl_theme = control.Theme { tokens: &rtl_tokens, fonts: fonts, language: "", runtime: &runtime }
    let (root_rtl, root_rtl_error) = build(&f, &rtl_theme, s, false, 9usize)
    if root_rtl_error != ok || testing.pump(&harness, root_rtl, time.Instant { nanos: 1200000000i64 }) != ok { os.exit(85i32) }
    let (rtl_shot, rtl_shot_error) = testing.snapshot(&harness, a)
    let (rtl_root, has_rtl_root) = bounds(&harness, &runtime, 2001u64)
    let (rtl_parent, has_rtl_parent) = bounds(&harness, &runtime, 2102u64)
    let rtl_muted = style.color(&rtl_tokens, .OnSurfaceVariant)
    let separator_x = rtl_root.x + rtl_root.width
    if rtl_shot_error != ok || !has_rtl_root || !has_rtl_parent || !is_color(rtl_shot, at(separator_x + 9.0, rtl_root.y + 13.0), rtl_muted) || is_color(rtl_shot, at(separator_x + 6.0, rtl_root.y + 13.0), rtl_muted) || !is_color(rtl_shot, at(rtl_parent.x + 15.0, rtl_parent.y + 21.0), rtl_muted) || is_color(rtl_shot, at(rtl_parent.x + 18.0, rtl_parent.y + 21.0), rtl_muted) { os.exit(86i32) }
    // (D1234) The collapsed menu bar: shut, one 32 Menu button and no menu; open
    // with File's row open, a menu of the titles with File's commands cascading
    // beside it; with no row open, a press on the Edit row fires its own toggle.
    var folded_toggles: [2]widget.Submit = zero
    folded_toggles[0usize] = s.subs[12usize]
    folded_toggles[1usize] = s.subs[13usize]
    var fold_step = 0usize
    while fold_step < 3usize {
        f = mem.arena_from(frame_storage)
        var opened_row = 9usize
        if fold_step == 1usize { opened_row = 0usize }
        let (folded_bar, folded_bar_error) = navigation.menu_bar_collapsed(&f, 9000u64, &theme, "Menu", s.menus[0usize..2usize], fold_step > 0usize, &s.subs[11usize], opened_row, folded_toggles[..])
        if folded_bar_error != ok { os.exit(87i32) }
        let (fold_page, fold_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if fold_page_error != ok { os.exit(87i32) }
        fold_page[0usize] = folded_bar
        if testing.pump(&harness, widget.box(0u64, control.sized_style(640.0, 520.0), fold_page[0usize..1usize]), time.Instant { nanos: 1500000000i64 + i64(fold_step) }) != ok { os.exit(94i32) }
        let (fold_button, has_fold_button) = bounds(&harness, &runtime, 9001u64)
        if !has_fold_button || !near(fold_button.width, 32.0) { os.exit(88i32) }
        let (fold_tree, fold_tree_error) = testing.semantics(&harness)
        if fold_tree_error != ok { os.exit(89i32) }
        let (_, has_fold_named) = find(fold_tree, .Button, "Menu")
        if !has_fold_named { os.exit(90i32) }
        if fold_step == 0usize && testing.by_role(&harness, .Menu).count != 0usize { os.exit(91i32) }
        if fold_step == 1usize {
            let (file_row, has_file_row) = find(fold_tree, .MenuItem, "File")
            let (edit_row, has_edit_row) = find(fold_tree, .MenuItem, "Edit")
            let (_, has_new) = find(fold_tree, .MenuItem, "New")
            if !has_file_row || !has_edit_row || !has_new || !file_row.state.expanded || testing.by_role(&harness, .Menu).count != 2usize { os.exit(92i32) }
        }
        if fold_step == 2usize {
            let (edit_row, has_edit_row) = find(fold_tree, .MenuItem, "Edit")
            if !has_edit_row || testing.by_role(&harness, .Menu).count != 1usize { os.exit(95i32) }
            let edit_before = s.counters[13usize].count
            if testing.tap(&harness, edit_row.bounds.x + 20.0, edit_row.bounds.y + edit_row.bounds.height * 0.5) != ok || s.counters[13usize].count != edit_before + 1usize { os.exit(93i32) }
        }
        fold_step += 1usize
    }
    // (D1308) The root crumb leads with its icon; Ctrl+L and a press on the empty
    // space ask to edit; editing, the path field stands alone, Enter goes and
    // Escape cancels.
    var path_names: [3]str = zero
    path_names[0usize] = "Workspace"
    path_names[1usize] = "lib"
    path_names[2usize] = "ui"
    let (path_bytes, path_bytes_error) = mem.alloc[u8](a, 32usize)
    if path_bytes_error != ok { os.exit(96i32) }
    let path_len = control.copy_text(path_bytes, "lib/ui")
    var path_step = 0usize
    while path_step < 2usize {
        var pathed = navigation.breadcrumbs_options()
        pathed.root_icon = true
        pathed.root_glyph = .Picture
        pathed.width = 500.0
        pathed.edit = s.subs[6usize]
        pathed.go = s.subs[7usize]
        pathed.cancel = s.subs[8usize]
        pathed.complete = s.subs[12usize]
        pathed.editing = path_step == 1usize
        pathed.path = path_bytes
        pathed.path_len = path_len
        f = mem.arena_from(frame_storage)
        let (path_trail, path_trail_error) = navigation.breadcrumbs_of(&f, 2300u64, &theme, "Path", path_names[..], s.crumbs[0usize..3usize], pathed)
        let (path_page, path_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if path_trail_error != ok || path_page_error != ok { os.exit(97i32) }
        path_page[0usize] = path_trail
        if testing.pump(&harness, widget.box(0u64, control.sized_style(640.0, 400.0), path_page[0usize..1usize]), time.Instant { nanos: 7000000000i64 + i64(path_step) }) != ok { os.exit(98i32) }
        if path_step == 0usize {
            let (icon_crumb, has_icon_crumb) = bounds(&harness, &runtime, 2301u64)
            if !has_icon_crumb || icon_crumb.width < 38.0 || testing.by_key(&harness, 2360u64).count != 0usize { os.exit(99i32) }
            var held_control: input.Modifiers = zero
            held_control.control = true
            let edits_before = s.counters[6usize].count
            if widget.focus(&runtime, testing.by_key(&harness, 2302u64).element) != ok || testing.press_key(&harness, 76u32, held_control) != ok || s.counters[6usize].count != edits_before + 1usize { os.exit(100i32) }
            if !tap_key(&harness, &runtime, 2361u64) || s.counters[6usize].count != edits_before + 2usize { os.exit(101i32) }
        }
        if path_step == 1usize {
            if testing.by_key(&harness, 2360u64).count != 1usize || testing.by_key(&harness, 2301u64).count != 0usize { os.exit(102i32) }
            let goes_before = s.counters[7usize].count
            let cancels_before = s.counters[8usize].count
            if widget.focus(&runtime, testing.by_key(&harness, 2360u64).element) != ok || testing.press_key(&harness, 13u32, zero) != ok || s.counters[7usize].count != goes_before + 1usize { os.exit(103i32) }
            if testing.press_key(&harness, 27u32, zero) != ok || s.counters[8usize].count != cancels_before + 1usize { os.exit(104i32) }
            // (D1396) Tab asks to complete the folder name, and the field keeps the focus.
            let completes_before = s.counters[12usize].count
            if widget.focus(&runtime, testing.by_key(&harness, 2360u64).element) != ok || testing.press_key(&harness, 9u32, zero) != ok || s.counters[12usize].count != completes_before + 1usize { os.exit(127i32) }
            let (still_there, has_still) = testing.focused(&harness)
            if !has_still || still_there.slot != testing.by_key(&harness, 2360u64).element.slot { os.exit(128i32) }
        }
        path_step += 1usize
    }
    // (D1443) Switched to editing, the path field fades in over
    // `duration-short-3`: on the switch's frame it stands part way in, a second
    // on whole.
    var fade_step = 0usize
    while fade_step < 4usize {
        var fade_at = 7100000000i64
        if fade_step == 1usize { fade_at = 7100000001i64 }
        if fade_step == 2usize { fade_at = 7200000000i64 }
        if fade_step == 3usize { fade_at = 8200000000i64 }
        if testing.begin(&harness, time.Instant { nanos: fade_at }) != ok { os.exit(129i32) }
        var fading_path = navigation.breadcrumbs_options()
        fading_path.width = 500.0
        fading_path.edit = s.subs[6usize]
        fading_path.go = s.subs[7usize]
        fading_path.cancel = s.subs[8usize]
        fading_path.editing = fade_step >= 2usize
        fading_path.path = path_bytes
        fading_path.path_len = path_len
        f = mem.arena_from(frame_storage)
        let (fading_trail, fading_trail_error) = navigation.breadcrumbs_of(&f, 2900u64, &theme, "Fading", path_names[..], s.crumbs[0usize..3usize], fading_path)
        let (fading_page, fading_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if fading_trail_error != ok || fading_page_error != ok { os.exit(129i32) }
        fading_page[0usize] = fading_trail
        if testing.pump(&harness, widget.box(0u64, control.sized_style(640.0, 400.0), fading_page[0usize..1usize]), time.Instant { nanos: fade_at }) != ok { os.exit(129i32) }
        if fade_step >= 2usize {
            let shown_share = control.eased_on(&theme, 2900u64, 2900u64 + 1048602u64, 1.0, false, tokens.durations.short3)
            if fade_step == 2usize && !(shown_share < 1.0) { os.exit(130i32) }
            if fade_step == 3usize && shown_share != 1.0 { os.exit(131i32) }
        }
        fade_step += 1usize
    }
    // (D1326) Sibling menus: a resting crumb has no chevron; hovered, "lib" shows
    // one that reports index 1; open, its menu lists the siblings and a pick fires.
    var sibling_log: [1]usize = zero
    var sibling_items: [2]overlay.MenuItem = zero
    sibling_items[0usize] = overlay.MenuItem { label: "docs", action: s.subs[9usize], enabled: true }
    sibling_items[1usize] = overlay.MenuItem { label: "tests", action: s.subs[10usize], enabled: true }
    if testing.hover(&harness, 1.0, 399.0) != ok { os.exit(105i32) }
    var sibling_step = 0usize
    while sibling_step < 3usize {
        var sibled = navigation.breadcrumbs_options()
        sibled.sibling_toggle = widget.Change[usize] { ctx: mem.cast[*void](&sibling_log[0usize]), invoke: on_sibling }
        sibled.siblings = sibling_items[..]
        if sibling_step == 2usize { sibled.sibling_open = 2usize }
        f = mem.arena_from(frame_storage)
        let (sib_trail, sib_trail_error) = navigation.breadcrumbs_of(&f, 2400u64, &theme, "Path", path_names[..], s.crumbs[0usize..3usize], sibled)
        let (sib_page, sib_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if sib_trail_error != ok || sib_page_error != ok { os.exit(106i32) }
        sib_page[0usize] = sib_trail
        if testing.pump(&harness, widget.box(0u64, control.sized_style(640.0, 400.0), sib_page[0usize..1usize]), time.Instant { nanos: 7100000000i64 + i64(sibling_step) }) != ok { os.exit(107i32) }
        if sibling_step == 0usize {
            let (lib_crumb, has_lib_crumb) = bounds(&harness, &runtime, 2402u64)
            if !has_lib_crumb || testing.by_key(&harness, 2501u64).count != 0usize || testing.hover(&harness, lib_crumb.x + 5.0, lib_crumb.y + lib_crumb.height * 0.5) != ok { os.exit(108i32) }
        }
        if sibling_step == 1usize {
            if !tap_key(&harness, &runtime, 2501u64) || sibling_log[0usize] != 2usize { os.exit(109i32) }
        }
        if sibling_step == 2usize {
            let tests_before = s.counters[10usize].count
            if testing.by_text(&harness, "docs").count == 0usize { os.exit(110i32) }
            let (sib_tree, sib_tree_error) = testing.semantics(&harness)
            let (tests_row, has_tests_row) = find(sib_tree, .MenuItem, "tests")
            if sib_tree_error != ok || !has_tests_row || testing.tap(&harness, tests_row.bounds.x + 10.0, tests_row.bounds.y + tests_row.bounds.height * 0.5) != ok || s.counters[10usize].count != tests_before + 1usize { os.exit(111i32) }
        }
        sibling_step += 1usize
    }
    // (D1361) A drag from the source over "lib" fills it `primary-container`;
    // dropped there, the trail reports crumb 1 and the payload.
    var drop_log: CrumbLog = zero
    var carry_step = 0usize
    let lib_visits = s.counters[1usize].count
    while carry_step < 3usize {
        var dropping = navigation.breadcrumbs_options()
        dropping.drop = widget.Change[navigation.CrumbDrop] { ctx: mem.cast[*void](&drop_log), invoke: on_crumb_drop }
        f = mem.arena_from(frame_storage)
        let (drop_trail, drop_trail_error) = navigation.breadcrumbs_of(&f, 2700u64, &theme, "Path", path_names[..], s.crumbs[0usize..3usize], dropping)
        let (carry_parts, carry_parts_error) = mem.alloc[widget.Node](&f, 2usize)
        if drop_trail_error != ok || carry_parts_error != ok { os.exit(112i32) }
        carry_parts[0usize] = drop_trail
        carry_parts[1usize] = widget.region(2690u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&runtime), invoke: start_carry }, gestures: 2u8 | 4u8, enabled: true, focusable: false }, control.sized_style(80.0, 80.0), zero)
        let (carry_page, carry_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if carry_page_error != ok { os.exit(113i32) }
        carry_page[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 40.0 }, control.sized_style(640.0, 400.0), carry_parts[0usize..2usize])
        if testing.pump(&harness, carry_page[0usize], time.Instant { nanos: 7200000000i64 + i64(carry_step) * 1000000000i64 }) != ok { os.exit(114i32) }
        let (lib_target, has_lib_target) = bounds(&harness, &runtime, 2901u64)
        let (source, has_source) = bounds(&harness, &runtime, 2690u64)
        if !has_lib_target || !has_source { os.exit(115i32) }
        let over = geometry.Point { x: lib_target.x + 6.0, y: lib_target.y + lib_target.height * 0.5 }
        if carry_step == 0usize {
            if testing.send(&harness, input.Event { PointerDown: testing.pointer_at(source.x + 40.0, source.y + 40.0) }) != ok || testing.send(&harness, input.Event { PointerMove: testing.pointer_at(source.x + 40.0, source.y + 20.0) }) != ok || testing.send(&harness, input.Event { PointerMove: testing.pointer_at(over.x, over.y) }) != ok { os.exit(116i32) }
        }
        // (D1374) Held over "lib" a second, the trail goes there.
        if carry_step == 2usize && s.counters[1usize].count == lib_visits { os.exit(119i32) }
        if carry_step == 2usize {
            let (carry_shot, carry_shot_error) = testing.snapshot(&harness, a)
            let fill = style.color(&tokens, .PrimaryContainer)
            if carry_shot_error != ok || !is_color(carry_shot, at(lib_target.x + 2.0, lib_target.y + lib_target.height * 0.5), fill) { os.exit(117i32) }
            if testing.send(&harness, input.Event { PointerUp: testing.pointer_at(over.x, over.y) }) != ok || drop_log.index != 2u64 || drop_log.payload != 77u64 { os.exit(118i32) }
        }
        carry_step += 1usize
    }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(35i32) }
    try io.print("ui navigation2 v2 ok\n")
    ret ok
}
