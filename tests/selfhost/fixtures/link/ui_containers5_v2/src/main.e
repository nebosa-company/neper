// The v2 document workspace over editor groups (D969, widget plan P5-08,
// docs/ux/components/MultiDocumentWorkspace) under the light theme at pointer
// density: two groups side by side split by a 1px `outline-variant` line, the
// active group's current tab with a 2px `primary` top line and the other's not; a
// location bar of 24-tall crumbs whose press is a Crumb event; a group actions
// button; in the active group Ctrl+Tab picks the most recently used document,
// Ctrl+Shift+Tab the least, Alt+1 the first, Ctrl+PageDown wraps, Ctrl+Shift+T
// reopens, Ctrl+\ splits and Ctrl+W closes; compact, a 32 count button opens
// the switcher; with no documents, a tonal Open recent button.

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
use e.ui.style
use e.ui.testing
use e.ui.widget

type Store = struct { events: usize, last: navigation.WorkspaceEvent, first: [2]navigation.Document, second: [3]navigation.Document, recent: [3]usize, crumbs: [3]str, groups: [2]navigation.EditorGroup, lone: [1]navigation.EditorGroup, bare: [1]navigation.EditorGroup }

fn on_event(ctx: *void, e: navigation.WorkspaceEvent) -> err {
    let s = mem.cast[*Store](ctx)
    s.events += 1usize
    s.last = e
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

fn blank(w: f32, h: f32) -> widget.Node {
    ret widget.box(0u64, control.sized_style(w, h), zero)
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let change = widget.Change[navigation.WorkspaceEvent] { ctx: mem.cast[*void](s), invoke: on_event }
    let (views, views_error) = mem.alloc[widget.Node](a, 2usize)
    if views_error != ok { ret (zero, views_error) }
    views[0usize] = blank(10.0, 10.0)
    views[1usize] = blank(10.0, 10.0)
    var split = navigation.workspace_options()
    split.active = 1usize
    let (one, e1) = navigation.multi_document_workspace_of(a, 1000u64, t, "Editors", s.groups[0usize..2usize], views[0usize..2usize], split, change, 601.0, 200.0)
    var compact = navigation.workspace_options()
    compact.compact = true
    let (two, e2) = navigation.multi_document_workspace_of(a, 2000u64, t, "Compact", s.lone[0usize..1usize], views[0usize..1usize], compact, change, 300.0, 200.0)
    let (three, e3) = navigation.multi_document_workspace_of(a, 3000u64, t, "Empty", s.bare[0usize..1usize], views[0usize..1usize], navigation.workspace_options(), change, 300.0, 200.0)
    if e1 != ok || e2 != ok || e3 != ok { ret (zero, e1) }
    let (items, items_error) = mem.alloc[widget.Node](a, 3usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = one
    items[1usize] = two
    items[2usize] = three
    var page = style.defaults()
    page.width = style.Length { Px: 640.0 }
    page.height = style.Length { Px: 660.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainer) }
    let pad = style.Length { Px: 10.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..3usize]), ok)
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

fn saw(s: *Store, kind: navigation.WorkspaceEventKind, group: usize, index: usize) -> bool {
    ret s.last.kind == kind && s.last.group == group && s.last.index == index
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
    let (h, harness_error) = testing.harness(a, &runtime, 640u32, 660u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    s.first[0usize] = navigation.Document { key: 1u64, title: "a.e", dirty: false, pinned: false }
    s.first[1usize] = navigation.Document { key: 2u64, title: "b.e", dirty: false, pinned: false }
    s.second[0usize] = navigation.Document { key: 3u64, title: "c.e", dirty: false, pinned: false }
    s.second[1usize] = navigation.Document { key: 4u64, title: "d.e", dirty: false, pinned: false }
    s.second[2usize] = navigation.Document { key: 5u64, title: "e.e", dirty: false, pinned: false }
    s.recent[0usize] = 2usize
    s.recent[1usize] = 0usize
    s.recent[2usize] = 1usize
    s.crumbs[0usize] = "src"
    s.crumbs[1usize] = "ui"
    s.crumbs[2usize] = "a.e"
    var none: []const usize = zero
    var no_crumbs: []const str = zero
    var no_documents: []const navigation.Document = zero
    s.groups[0usize] = navigation.EditorGroup { documents: s.first[0usize..2usize], current: 0usize, recent: none, crumbs: s.crumbs[0usize..3usize] }
    s.groups[1usize] = navigation.EditorGroup { documents: s.second[0usize..3usize], current: 2usize, recent: s.recent[0usize..3usize], crumbs: no_crumbs }
    s.lone[0usize] = navigation.EditorGroup { documents: s.second[0usize..1usize], current: 0usize, recent: none, crumbs: no_crumbs }
    s.bare[0usize] = navigation.EditorGroup { documents: no_documents, current: 0usize, recent: none, crumbs: no_crumbs }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, s)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let primary = style.color(&tokens, .Primary)
    // Two groups side by side with a 1px line between them.
    let (left, has_left) = bounds(&harness, &runtime, 1001u64)
    let (right, has_right) = bounds(&harness, &runtime, 1201u64)
    if !has_left || !has_right || !near(left.width, 300.0) || !near(right.x - left.x, 301.0) { os.exit(12i32) }
    if !is_color(shot, at(right.x - 0.5, right.y + 150.0), style.color(&tokens, .OutlineVariant)) || !is_color(shot, at(right.x + 100.0, right.y + 150.0), style.color(&tokens, .Background)) { os.exit(13i32) }
    // The active group's current tab carries the primary line along its top edge
    // (D974, docs/ux/components/DocumentTabs); the other group's current tab does
    // not.
    let (marked, has_marked) = bounds(&harness, &runtime, 1207u64)
    let (plain, has_plain) = bounds(&harness, &runtime, 1003u64)
    if !has_marked || !has_plain { os.exit(14i32) }
    if !is_color(shot, at(marked.x + 12.0, marked.y + 1.0), primary) || is_color(shot, at(plain.x + 12.0, plain.y + 1.0), primary) { os.exit(15i32) }
    // The location bar: 24-tall crumbs; a press is a Crumb event.
    let (crumb, has_crumb) = bounds(&harness, &runtime, 1153u64)
    if !has_crumb || !near(crumb.height, 24.0) || testing.by_label(&harness, "Group actions").count != 2usize { os.exit(16i32) }
    if !tap_key(&harness, &runtime, 1151u64) || !saw(s, .Crumb, 0usize, 0usize) { os.exit(17i32) }
    if !tap_key(&harness, &runtime, 1391u64) || !saw(s, .GroupMenu, 1usize, 0usize) { os.exit(18i32) }
    // The active group's keys, focus inside it by a tap on its current tab.
    if testing.tap(&harness, marked.x + 3.0, marked.y + marked.height * 0.5) != ok || !saw(s, .Pick, 1usize, 2usize) { os.exit(19i32) }
    var ctrl: input.Modifiers = zero
    ctrl.control = true
    var ctrl_shift = ctrl
    ctrl_shift.shift = true
    var alt: input.Modifiers = zero
    alt.alt = true
    if testing.press_key(&harness, 9u32, ctrl) != ok || !saw(s, .Pick, 1usize, 0usize) { os.exit(20i32) }
    if testing.press_key(&harness, 9u32, ctrl_shift) != ok || !saw(s, .Pick, 1usize, 1usize) { os.exit(21i32) }
    if testing.press_key(&harness, 49u32, alt) != ok || !saw(s, .Pick, 1usize, 0usize) { os.exit(22i32) }
    if testing.press_key(&harness, 34u32, ctrl) != ok || !saw(s, .Pick, 1usize, 0usize) { os.exit(23i32) }
    if testing.press_key(&harness, 84u32, ctrl_shift) != ok || s.last.kind != .Reopen { os.exit(24i32) }
    if testing.press_key(&harness, 220u32, ctrl) != ok || s.last.kind != .Split { os.exit(25i32) }
    if testing.press_key(&harness, 87u32, ctrl) != ok || !saw(s, .Close, 1usize, 2usize) { os.exit(26i32) }
    // Compact: a 32 count button opening the switcher.
    let (count_button, has_count) = bounds(&harness, &runtime, 2901u64)
    if !has_count || !near(count_button.width, 32.0) || !near(count_button.height, 32.0) { os.exit(27i32) }
    if !tap_key(&harness, &runtime, 2901u64) || s.last.kind != .Switcher { os.exit(28i32) }
    // Empty: the Open recent button.
    if testing.by_label(&harness, "Open recent").count == 0usize || !tap_key(&harness, &runtime, 3900u64) || s.last.kind != .OpenRecent { os.exit(29i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(30i32) }
    try io.print("ui containers5 v2 ok\n")
    ret ok
}
