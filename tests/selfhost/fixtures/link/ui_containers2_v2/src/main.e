// The v2 resizable pane, split view, dock panel, dock layout and document
// workspace (D966, widget plan P5-08, docs/ux/components) under the light theme
// at pointer density: a pane's sash is an 8 hit strip around a 1px
// `outline-variant` line with no grip at rest and a 4 x 48 `outline` grip once
// hovered, a slider named "Resize " and the label with the size as its value,
// moved 48 by Shift+Right and to its limits by Home and End; a split view's sash
// is named by the caller; a focused dock panel is `surface-container-low` under a
// 2px `primary` line with a 32 Close button named for the panel; a dock layout's
// sash turns a 4px `primary` bar on hover over a `surface` centre; a workspace
// with no documents shows its empty state and Ctrl+PageDown wraps to the first.

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

type Store = struct { size: f32, sizes: usize, picked: usize, picks: usize, closes: usize, press: widget.Submit, documents: [3]navigation.Document }

fn on_size(ctx: *void, value: f32) -> err {
    let s = mem.cast[*Store](ctx)
    s.size = value
    s.sizes += 1usize
    ret ok
}

fn on_sizes(ctx: *void, value: navigation.DockSizes) -> err {
    ret ok
}

fn on_pick(ctx: *void, value: usize) -> err {
    let s = mem.cast[*Store](ctx)
    s.picked = value
    s.picks += 1usize
    ret ok
}

fn on_close(ctx: *void, value: usize) -> err {
    ret ok
}

fn on_move(ctx: *void, value: navigation.DocumentMove) -> err {
    ret ok
}

fn on_press(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.closes += 1usize
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

fn focused_panel() -> navigation.DockPanelOptions {
    var out = navigation.dock_panel_options()
    out.focused = true
    ret out
}

fn sized_row(a: *mem.Arena, w: f32, h: f32, child: widget.Node) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = child
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, control.sized_style(w, h), held[0usize..1usize]), ok)
}

fn press_at(h: *testing.Harness, x: f32, y: f32) -> bool {
    ret testing.send(h, input.Event { PointerDown: testing.pointer_at(x, y) }) == ok
}

fn move_at(h: *testing.Harness, x: f32, y: f32) -> bool {
    ret testing.send(h, input.Event { PointerMove: testing.pointer_at(x, y) }) == ok
}

fn release_at(h: *testing.Harness, x: f32, y: f32) -> bool {
    ret testing.send(h, input.Event { PointerUp: testing.pointer_at(x, y) }) == ok
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 6usize)
    if items_error != ok { ret (zero, items_error) }
    let ctx = mem.cast[*void](s)
    let (pane, e1) = control.resizable_pane(a, 10u64, t, "Files", .Horizontal, 100.0, 60.0, 200.0, widget.Change[f32] { ctx: ctx, invoke: on_size }, blank(20.0, 20.0))
    if e1 != ok { ret (zero, e1) }
    let (pane_row, e1b) = sized_row(a, 300.0, 100.0, pane)
    let (split, e2) = control.split_view_named(a, 30u64, t, "Builds", .Horizontal, blank(10.0, 10.0), blank(10.0, 10.0), 100.0, 60.0, 60.0, widget.Change[f32] { ctx: ctx, invoke: on_size }, 300.0, 60.0)
    let (panel, e3) = navigation.dock_panel_of(a, 50u64, t, "Explorer", blank(10.0, 10.0), &s.press, focused_panel())
    if e3 != ok { ret (zero, e3) }
    let (panel_row, e3b) = sized_row(a, 200.0, 120.0, panel)
    let (dock, e4) = navigation.dock_layout(a, 70u64, t, blank(10.0, 10.0), blank(10.0, 10.0), blank(10.0, 10.0), blank(10.0, 10.0), navigation.DockSizes { left: 200.0, right: 200.0, bottom: 100.0 }, widget.Change[navigation.DockSizes] { ctx: ctx, invoke: on_sizes }, 800.0, 300.0)
    let (bare, e5) = navigation.multi_document_workspace(a, 90u64, t, "Empty", s.documents[0usize..0usize], 0usize, blank(10.0, 10.0), widget.Change[usize] { ctx: ctx, invoke: on_pick }, widget.Change[usize] { ctx: ctx, invoke: on_close }, widget.Change[navigation.DocumentMove] { ctx: ctx, invoke: on_move }, 300.0, 150.0)
    let (full, e6) = navigation.multi_document_workspace(a, 100u64, t, "Documents", s.documents[0usize..3usize], 2usize, blank(10.0, 10.0), widget.Change[usize] { ctx: ctx, invoke: on_pick }, widget.Change[usize] { ctx: ctx, invoke: on_close }, widget.Change[navigation.DocumentMove] { ctx: ctx, invoke: on_move }, 300.0, 100.0)
    if e1b != ok || e2 != ok || e3b != ok || e4 != ok || e5 != ok || e6 != ok { ret (zero, e2) }
    items[0usize] = pane_row
    items[1usize] = split
    items[2usize] = panel_row
    items[3usize] = dock
    items[4usize] = bare
    items[5usize] = full
    var page = style.defaults()
    page.width = style.Length { Px: 820.0 }
    page.height = style.Length { Px: 1000.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainer) }
    let pad = style.Length { Px: 10.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..6usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 820usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
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
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 400usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 24u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 820u32, 1000u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    stores[0usize].press = widget.Submit { ctx: mem.cast[*void](&stores[0usize]), invoke: on_press }
    stores[0usize].documents[0usize] = navigation.Document { key: 1001u64, title: "main.e", dirty: false, pinned: false }
    stores[0usize].documents[1usize] = navigation.Document { key: 1002u64, title: "notes", dirty: false, pinned: false }
    stores[0usize].documents[2usize] = navigation.Document { key: 1003u64, title: "todo", dirty: false, pinned: false }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&f, &theme, &stores[0usize])
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let ground = style.color(&tokens, .SurfaceContainer)
    let edge = style.color(&tokens, .OutlineVariant)
    let primary = style.color(&tokens, .Primary)
    // The pane's sash: 8 wide after the 100 pane, its 1px outline-variant line 3
    // in, no grip at rest.
    let (sash, has_sash) = bounds(&harness, &runtime, 12u64)
    let (inner, has_inner) = bounds(&harness, &runtime, 11u64)
    if !has_sash || !has_inner || !near(sash.width, 8.0) || !near(inner.width, 100.0) || !near(sash.x, inner.x + 100.0) { os.exit(12i32) }
    let mid = sash.y + sash.height * 0.5
    if !is_color(shot, at(sash.x + 3.5, mid), edge) || !is_color(shot, at(sash.x + 5.5, mid), ground) { os.exit(13i32) }
    // A slider named for the pane, its value the size.
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(14i32) }
    let (named, has_named) = find(tree, .Separator, "Resize Files")
    if !has_named || !same(named.value, "100 px") { os.exit(15i32) }
    let (builds, has_builds) = find(tree, .Separator, "Builds")
    if !has_builds { os.exit(16i32) }
    // Hovered, the 4 x 48 grip shows in outline on the next frame.
    if testing.hover(&harness, sash.x + 4.0, mid) != ok { os.exit(17i32) }
    let (root_2, build_2_error) = build(&f, &theme, &stores[0usize])
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(18i32) }
    let (shot_2, shot_2_error) = testing.snapshot(&harness, a)
    if shot_2_error != ok { os.exit(19i32) }
    if !is_color(shot_2, at(sash.x + 5.5, mid), style.color(&tokens, .Outline)) || !is_color(shot_2, at(sash.x + 5.5, mid - 30.0), ground) { os.exit(20i32) }
    // Keys on the focused sash: Shift+Right 48 more, End to the limit, Home to
    // the least.
    if testing.drag(&harness, geometry.Point { x: sash.x + 4.0, y: mid }, geometry.Point { x: sash.x + 24.0, y: mid }, 4usize) != ok || stores[0usize].sizes == 0usize { os.exit(21i32) }
    var shifted: input.Modifiers = zero
    shifted.shift = true
    if testing.press_key(&harness, 39u32, shifted) != ok || !near(stores[0usize].size, 148.0) { os.exit(22i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !near(stores[0usize].size, 200.0) { os.exit(23i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !near(stores[0usize].size, 60.0) { os.exit(24i32) }
    // (D1212) Escape during a drag restores the size the drag began at and the
    // rest of that drag is ignored; a double-click restores the first size.
    if !press_at(&harness, sash.x + 4.0, mid) || !move_at(&harness, sash.x + 20.0, mid) || !move_at(&harness, sash.x + 40.0, mid) || near(stores[0usize].size, 100.0) { os.exit(40i32) }
    let (root_drag, root_drag_error) = build(&f, &theme, &stores[0usize])
    if root_drag_error != ok || testing.pump(&harness, root_drag, now) != ok { os.exit(41i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || !near(stores[0usize].size, 100.0) { os.exit(42i32) }
    let sizes_cancelled = stores[0usize].sizes
    if !move_at(&harness, sash.x + 60.0, mid) || !release_at(&harness, sash.x + 60.0, mid) || stores[0usize].sizes != sizes_cancelled { os.exit(43i32) }
    let (root_rest, root_rest_error) = build(&f, &theme, &stores[0usize])
    if root_rest_error != ok || testing.pump(&harness, root_rest, now) != ok { os.exit(44i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !near(stores[0usize].size, 60.0) { os.exit(45i32) }
    if testing.tap(&harness, sash.x + 4.0, mid) != ok || testing.tap(&harness, sash.x + 4.0, mid) != ok || !near(stores[0usize].size, 100.0) { os.exit(46i32) }
    // The focused dock panel: surface-container-low under a 2px primary line, a
    // 32 Close button named for the panel that fires.
    let (panel, has_panel) = bounds(&harness, &runtime, 50u64)
    let (closer, has_closer) = bounds(&harness, &runtime, 51u64)
    if !has_panel || !has_closer || !near(closer.width, 32.0) || !near(closer.height, 32.0) || !near(panel.width, 200.0) { os.exit(25i32) }
    if !is_color(shot, at(panel.x + 100.0, panel.y + 1.0), primary) || !is_color(shot, at(panel.x + 100.0, panel.y + 80.0), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot, at(panel.x + 100.0, panel.y + 16.0), style.color(&tokens, .SurfaceContainerLow)) { os.exit(26i32) }
    if testing.by_label(&harness, "Close Explorer panel").count != 1usize { os.exit(27i32) }
    if testing.tap(&harness, closer.x + 16.0, closer.y + 16.0) != ok || stores[0usize].closes != 1usize { os.exit(28i32) }
    // The dock layout: the left sash's hairline over a surface centre; hovered,
    // a 4px primary bar.
    let (left_sash, has_left) = bounds(&harness, &runtime, 73u64)
    if !has_left || !near(left_sash.width, 8.0) { os.exit(29i32) }
    let dock_mid = left_sash.y + 40.0
    if !is_color(shot, at(left_sash.x + 3.5, dock_mid), edge) || !is_color(shot, at(left_sash.x + 1.5, dock_mid), ground) || !is_color(shot, at(left_sash.x + 30.0, dock_mid), style.color(&tokens, .Background)) { os.exit(30i32) }
    if testing.hover(&harness, left_sash.x + 4.0, dock_mid) != ok { os.exit(31i32) }
    let (root_3, build_3_error) = build(&f, &theme, &stores[0usize])
    if build_3_error != ok || testing.pump(&harness, root_3, now) != ok { os.exit(32i32) }
    let (shot_3, shot_3_error) = testing.snapshot(&harness, a)
    if shot_3_error != ok { os.exit(33i32) }
    if !is_color(shot_3, at(left_sash.x + 2.5, dock_mid), primary) || !is_color(shot_3, at(left_sash.x + 5.5, dock_mid), primary) || !is_color(shot_3, at(left_sash.x + 6.5, dock_mid), ground) { os.exit(34i32) }
    // The empty workspace: its view 300 x 150 on surface, no tab list; the full
    // one's Ctrl+PageDown from the last document wraps to the first.
    let (bare, has_bare) = bounds(&harness, &runtime, 90u64)
    if !has_bare || !near(bare.width, 300.0) || !near(bare.height, 150.0) || testing.by_key(&harness, 91u64).count != 0usize { os.exit(35i32) }
    if !is_color(shot, at(bare.x + 20.0, bare.y + 20.0), style.color(&tokens, .Background)) { os.exit(36i32) }
    let (last, has_last) = bounds(&harness, &runtime, 106u64)
    if !has_last || testing.tap(&harness, last.x + 6.0, last.y + last.height * 0.5) != ok || stores[0usize].picked != 2usize { os.exit(37i32) }
    var held: input.Modifiers = zero
    held.control = true
    if testing.press_key(&harness, 34u32, held) != ok || stores[0usize].picks != 2usize || stores[0usize].picked != 0usize { os.exit(38i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(39i32) }
    try io.print("ui containers2 v2 ok\n")
    ret ok
}
