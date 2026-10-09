// The app-drawn caption (D2281, L088; e.ui.window geometry, e.ui.navigation.title_bar): where the title, the drag
// region and the caption buttons go on Windows, macOS and Linux (left to right and mirrored), at 800 wide; which part
// of a window a point belongs to (resize ring, buttons, caption, client) and what a press or a double press asks of the
// host; the maximised state (Restore, no ring), fullscreen (no bar), a bar over host chrome (title only, no drag); and the
// drawn bar -- every rectangle the layout's, the buttons named and firing, a drag fires `move`, a double press `toggle`,
// the close button red under the pointer, the disabled button inert and dimmed.

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
use e.ui.window as win

type Counter = struct { count: usize }
type Store = struct { counters: [5]Counter, subs: [5]widget.Submit, mode: win.Mode, platform: win.Platform, frameless: bool, minimizable: bool, rtl: bool }

fn on_count(ctx: *void) -> err {
    let c = mem.cast[*Counter](ctx)
    c.count += 1usize
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn rect_is(r: geometry.Rect, x: f32, y: f32, w: f32, h: f32) -> bool {
    ret near(r.x, x) && near(r.y, y) && near(r.width, w) && near(r.height, h)
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

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 1000usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn options_for(platform: win.Platform, mode: win.Mode, frameless: bool, rtl: bool) -> win.CaptionOptions {
    var o = win.caption_options(platform)
    o.mode = mode
    o.frameless = frameless
    o.rtl = rtl
    ret o
}

fn pure_checks() -> i32 {
    // Windows, left to right: 46 by 32 buttons flush at the end, close outermost; the icon 10 in; the rest is title and drag.
    let w = win.caption_layout(800.0, options_for(.Windows, .Windowed, true, false), 100.0)
    if w.count != 3usize || !rect_is(w.bar, 0.0, 0.0, 800.0, 32.0) || w.leading || w.centred || !w.draggable { ret 1i32 }
    if w.slots[0usize].kind != .Minimize || !rect_is(w.slots[0usize].rect, 662.0, 0.0, 46.0, 32.0) { ret 2i32 }
    if w.slots[1usize].kind != .Maximize || !rect_is(w.slots[1usize].rect, 708.0, 0.0, 46.0, 32.0) || w.slots[1usize].restore { ret 3i32 }
    if w.slots[2usize].kind != .Close || !rect_is(w.slots[2usize].rect, 754.0, 0.0, 46.0, 32.0) { ret 4i32 }
    if !rect_is(w.icon, 10.0, 8.0, 16.0, 16.0) || !rect_is(w.drag, 32.0, 0.0, 630.0, 32.0) || !rect_is(w.title, 32.0, 0.0, 630.0, 32.0) { ret 5i32 }
    // Windows, right to left: mirrored, close outermost at the left, the icon at the right.
    let r = win.caption_layout(800.0, options_for(.Windows, .Windowed, true, true), 100.0)
    if !r.leading || r.slots[0usize].kind != .Close || !rect_is(r.slots[0usize].rect, 0.0, 0.0, 46.0, 32.0) || r.slots[2usize].kind != .Minimize || !rect_is(r.slots[2usize].rect, 92.0, 0.0, 46.0, 32.0) { ret 6i32 }
    if !rect_is(r.icon, 774.0, 8.0, 16.0, 16.0) || !rect_is(r.drag, 138.0, 0.0, 630.0, 32.0) { ret 7i32 }
    // macOS: 28 tall, 12 round traffic lights 10 in and 8 apart at the start in the order close, minimise, zoom, no icon,
    // the title centred in what is left.
    let m = win.caption_layout(800.0, options_for(.Mac, .Windowed, true, false), 100.0)
    if !rect_is(m.bar, 0.0, 0.0, 800.0, 28.0) || !m.leading || !m.centred || m.icon.width != 0.0 { ret 8i32 }
    if m.slots[0usize].kind != .Close || !rect_is(m.slots[0usize].rect, 10.0, 8.0, 12.0, 12.0) { ret 9i32 }
    if m.slots[1usize].kind != .Minimize || !rect_is(m.slots[1usize].rect, 30.0, 8.0, 12.0, 12.0) { ret 10i32 }
    if m.slots[2usize].kind != .Maximize || !rect_is(m.slots[2usize].rect, 50.0, 8.0, 12.0, 12.0) { ret 11i32 }
    if !rect_is(m.drag, 72.0, 0.0, 728.0, 28.0) || !rect_is(m.title, 386.0, 0.0, 100.0, 28.0) { ret 12i32 }
    // Linux: 36 tall, 28 round buttons 8 apart with 10 at the end.
    let l = win.caption_layout(800.0, options_for(.Linux, .Windowed, true, false), 100.0)
    if !rect_is(l.bar, 0.0, 0.0, 800.0, 36.0) || !rect_is(l.slots[0usize].rect, 690.0, 4.0, 28.0, 28.0) || !rect_is(l.slots[1usize].rect, 726.0, 4.0, 28.0, 28.0) || !rect_is(l.slots[2usize].rect, 762.0, 4.0, 28.0, 28.0) { ret 13i32 }
    if !rect_is(l.drag, 32.0, 0.0, 648.0, 36.0) { ret 14i32 }
    // Maximised: the maximise button is restore; fullscreen has no bar at all; over host chrome only the title stands.
    let big = win.caption_layout(800.0, options_for(.Windows, .Maximized, true, false), 100.0)
    if !big.slots[1usize].restore || big.slots[0usize].restore { ret 15i32 }
    let full = win.caption_layout(800.0, options_for(.Windows, .Fullscreen, true, false), 100.0)
    if full.count != 0usize || full.bar.height != 0.0 || full.draggable { ret 16i32 }
    let host = win.caption_layout(800.0, options_for(.Windows, .Windowed, false, false), 100.0)
    if host.count != 0usize || host.draggable || !rect_is(host.bar, 0.0, 0.0, 800.0, 32.0) || !rect_is(host.drag, 32.0, 0.0, 768.0, 32.0) { ret 17i32 }
    // Unavailable buttons stay but are disabled; a window that cannot resize cannot maximise.
    var fixed = options_for(.Windows, .Windowed, true, false)
    fixed.resizable = false
    fixed.minimizable = false
    let locked = win.caption_layout(800.0, fixed, 100.0)
    if locked.slots[0usize].enabled || locked.slots[1usize].enabled || !locked.slots[2usize].enabled { ret 18i32 }
    // Hit regions in a 800 by 600 window with a 6 wide ring.
    let o = options_for(.Windows, .Windowed, true, false)
    if win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: 3.0, y: 3.0 }) != .TopLeft { ret 19i32 }
    if win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: 400.0, y: 3.0 }) != .Top { ret 20i32 }
    if win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: 400.0, y: 10.0 }) != .Caption { ret 21i32 }
    if win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: 700.0, y: 10.0 }) != .Minimize { ret 22i32 }
    if win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: 720.0, y: 10.0 }) != .Maximize { ret 23i32 }
    if win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: 780.0, y: 10.0 }) != .Close { ret 24i32 }
    if win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: 400.0, y: 300.0 }) != .Client { ret 25i32 }
    if win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: 799.0, y: 300.0 }) != .Right { ret 26i32 }
    if win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: 400.0, y: 599.0 }) != .Bottom { ret 27i32 }
    if win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: 796.0, y: 596.0 }) != .BottomRight { ret 28i32 }
    if win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: 2.0, y: 590.0 }) != .BottomLeft { ret 29i32 }
    if win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: 796.0, y: 8.0 }) != .TopRight { ret 30i32 }
    if win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: -1.0, y: 3.0 }) != .Client || win.hit_region(800.0, 600.0, o, 100.0, 6.0, geometry.Point { x: 800.0, y: 3.0 }) != .Client { ret 31i32 }
    // Maximised, fullscreen and host-chrome windows have no ring; the last has no buttons either.
    let max_o = options_for(.Windows, .Maximized, true, false)
    if win.hit_region(800.0, 600.0, max_o, 100.0, 6.0, geometry.Point { x: 400.0, y: 3.0 }) != .Caption || win.hit_region(800.0, 600.0, max_o, 100.0, 6.0, geometry.Point { x: 799.0, y: 300.0 }) != .Client { ret 32i32 }
    let full_o = options_for(.Windows, .Fullscreen, true, false)
    if win.hit_region(800.0, 600.0, full_o, 100.0, 6.0, geometry.Point { x: 400.0, y: 10.0 }) != .Client { ret 33i32 }
    let host_o = options_for(.Windows, .Windowed, false, false)
    if win.hit_region(800.0, 600.0, host_o, 100.0, 6.0, geometry.Point { x: 780.0, y: 10.0 }) != .Caption || win.hit_region(800.0, 600.0, host_o, 100.0, 6.0, geometry.Point { x: 2.0, y: 2.0 }) != .Caption { ret 34i32 }
    // Intents.
    if win.caption_intent(.Caption, o, false) != .Move || win.caption_intent(.Caption, o, true) != .Maximize || win.caption_intent(.Caption, max_o, true) != .Restore { ret 35i32 }
    if win.caption_intent(.Close, o, false) != .Close || win.caption_intent(.Minimize, o, false) != .Minimize || win.caption_intent(.Maximize, o, false) != .Maximize || win.caption_intent(.Maximize, max_o, false) != .Restore { ret 36i32 }
    if win.caption_intent(.Left, o, false) != .ResizeLeft || win.caption_intent(.BottomRight, o, false) != .ResizeBottomRight || win.caption_intent(.TopLeft, o, false) != .ResizeTopLeft || win.caption_intent(.Top, o, false) != .ResizeTop { ret 37i32 }
    if win.caption_intent(.Client, o, false) != .None || win.caption_intent(.Caption, host_o, false) != .None || win.caption_intent(.Caption, full_o, false) != .None { ret 38i32 }
    if win.caption_intent(.Minimize, fixed, false) != .None || win.caption_intent(.Maximize, fixed, false) != .None || win.caption_intent(.Caption, fixed, true) != .None { ret 39i32 }
    // Per-platform order.
    let order_w = win.caption_order(.Windows)
    let order_m = win.caption_order(.Mac)
    if order_w[0usize] != .Minimize || order_w[2usize] != .Close || order_m[0usize] != .Close || order_m[2usize] != .Maximize { ret 40i32 }
    ret 0i32
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    var o = navigation.title_bar_options(s.platform)
    o.mode = s.mode
    o.frameless = s.frameless
    o.minimizable = s.minimizable
    o.rtl = s.rtl
    o.minimize = s.subs[0usize]
    o.maximize = s.subs[1usize]
    o.close = s.subs[2usize]
    o.move = s.subs[3usize]
    o.toggle = s.subs[4usize]
    let (bar, bar_error) = navigation.title_bar(a, 3000u64, t, "main.e - Neper", o, 1000.0)
    if bar_error != ok { ret (zero, bar_error) }
    var page = style.defaults()
    page.width = style.Length { Px: 1000.0 }
    page.height = style.Length { Px: 600.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let (items, items_error) = mem.alloc[widget.Node](a, 1usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = bar
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, page, items[0usize..1usize]), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let pure = pure_checks()
    if pure != 0i32 { os.exit(pure) }
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(61i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(62i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(63i32) }
    var renderer = r
    let tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(64i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 400usize, max_states: 64usize, state_bytes: 4096usize, state_classes: 32u16, max_depth: 32u16, max_commands: 2048usize })
    if runtime_error != ok { os.exit(65i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 1000u32, 600u32, 1.0)
    if harness_error != ok { os.exit(66i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(67i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    var i = 0usize
    while i < 5usize {
        s.subs[i] = widget.Submit { ctx: mem.cast[*void](&s.counters[i]), invoke: on_count }
        i += 1usize
    }
    s.platform = .Windows
    s.mode = .Windowed
    s.frameless = true
    s.minimizable = true
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(68i32) }
    var f = mem.arena_from(frame_storage)
    var clock = 1000000000i64
    let (root, build_error) = build(&f, &theme, s)
    if build_error != ok { os.exit(69i32) }
    if testing.pump(&harness, root, time.Instant { nanos: clock }) != ok { os.exit(70i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(71i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(72i32) }
    // The drawn bar is the layout's: the buttons at 1000 wide, the drag region from the icon's end to the first button.
    let layout = win.caption_layout(1000.0, options_for(.Windows, .Windowed, true, false), 100.0)
    let (minimize, has_minimize) = bounds(&harness, &runtime, 3002u64)
    let (maximize, has_maximize) = bounds(&harness, &runtime, 3003u64)
    let (close, has_close) = bounds(&harness, &runtime, 3004u64)
    let (drag, has_drag) = bounds(&harness, &runtime, 3001u64)
    if !has_minimize || !has_maximize || !has_close || !has_drag { os.exit(73i32) }
    if !rect_is(minimize, layout.slots[0usize].rect.x, 0.0, 46.0, 32.0) || !rect_is(maximize, layout.slots[1usize].rect.x, 0.0, 46.0, 32.0) || !rect_is(close, layout.slots[2usize].rect.x, 0.0, 46.0, 32.0) { os.exit(74i32) }
    if !near(drag.x, layout.drag.x) || !near(drag.width, layout.drag.width) || !near(drag.height, 32.0) { os.exit(75i32) }
    if !is_color(shot, at(500.0, 16.0), style.color(&tokens, .SurfaceContainer)) { os.exit(76i32) }
    // The tree: a group named "Title bar" with three named buttons.
    let (group, has_group) = find(tree, .Group, "Title bar")
    let (b_min, has_b_min) = find(tree, .Button, "Minimize")
    let (b_max, has_b_max) = find(tree, .Button, "Maximize")
    let (b_close, has_b_close) = find(tree, .Button, "Close")
    if !has_group || !has_b_min || !has_b_max || !has_b_close || b_min.state.disabled { os.exit(77i32) }
    // Presses fire; a drag begun on the bar fires `move`; a double press fires `toggle`.
    if testing.tap(&harness, minimize.x + 20.0, 16.0) != ok || s.counters[0usize].count != 1usize { os.exit(78i32) }
    if testing.tap(&harness, maximize.x + 20.0, 16.0) != ok || s.counters[1usize].count != 1usize { os.exit(79i32) }
    if testing.tap(&harness, close.x + 20.0, 16.0) != ok || s.counters[2usize].count != 1usize { os.exit(80i32) }
    if testing.drag(&harness, geometry.Point { x: 400.0, y: 16.0 }, geometry.Point { x: 420.0, y: 40.0 }, 4usize) != ok || s.counters[3usize].count != 1usize { os.exit(81i32) }
    if testing.tap(&harness, 400.0, 16.0) != ok || testing.tap(&harness, 400.0, 16.0) != ok || s.counters[4usize].count != 1usize { os.exit(82i32) }
    // The close button is red under the pointer.
    if testing.hover(&harness, close.x + 20.0, 16.0) != ok { os.exit(83i32) }
    clock += 100000000i64
    let (hovered, hovered_error) = build(&f, &theme, s)
    if hovered_error != ok || testing.pump(&harness, hovered, time.Instant { nanos: clock }) != ok { os.exit(84i32) }
    let (hover_shot, hover_shot_error) = testing.snapshot(&harness, a)
    if hover_shot_error != ok || !is_color(hover_shot, at(close.x + 3.0, 3.0), style.color(&tokens, .Error)) { os.exit(85i32) }
    // Maximised: the same button reads Restore; the layout loses its ring.
    s.mode = .Maximized
    clock += 100000000i64
    let (maxed, maxed_error) = build(&f, &theme, s)
    if maxed_error != ok || testing.pump(&harness, maxed, time.Instant { nanos: clock }) != ok { os.exit(86i32) }
    let (maxed_tree, maxed_tree_error) = testing.semantics(&harness)
    let (restore, has_restore) = find(maxed_tree, .Button, "Restore")
    let (no_maximize, has_no_maximize) = find(maxed_tree, .Button, "Maximize")
    if maxed_tree_error != ok || !has_restore || has_no_maximize { os.exit(87i32) }
    // Fullscreen: no bar at all.
    s.mode = .Fullscreen
    clock += 100000000i64
    let (full, full_error) = build(&f, &theme, s)
    if full_error != ok || testing.pump(&harness, full, time.Instant { nanos: clock }) != ok { os.exit(88i32) }
    let (full_tree, full_tree_error) = testing.semantics(&harness)
    let (no_close, has_no_close) = find(full_tree, .Button, "Close")
    if full_tree_error != ok || has_no_close || testing.by_key(&harness, 3004u64).count != 0usize { os.exit(89i32) }
    // Over host chrome: the title only, no buttons, no drag.
    s.mode = .Windowed
    s.frameless = false
    clock += 100000000i64
    let (hosted, hosted_error) = build(&f, &theme, s)
    if hosted_error != ok || testing.pump(&harness, hosted, time.Instant { nanos: clock }) != ok { os.exit(90i32) }
    let (hosted_tree, hosted_tree_error) = testing.semantics(&harness)
    let (no_buttons, has_no_buttons) = find(hosted_tree, .Button, "Minimize")
    if hosted_tree_error != ok || has_no_buttons || testing.by_key(&harness, 3002u64).count != 0usize { os.exit(91i32) }
    let before = s.counters[3usize].count
    if testing.drag(&harness, geometry.Point { x: 400.0, y: 16.0 }, geometry.Point { x: 420.0, y: 40.0 }, 4usize) != ok || s.counters[3usize].count != before { os.exit(92i32) }
    // A disabled minimise is dimmed and inert.
    s.frameless = true
    s.minimizable = false
    clock += 100000000i64
    let (locked, locked_error) = build(&f, &theme, s)
    if locked_error != ok || testing.pump(&harness, locked, time.Instant { nanos: clock }) != ok { os.exit(93i32) }
    let (locked_tree, locked_tree_error) = testing.semantics(&harness)
    let (disabled_min, has_disabled_min) = find(locked_tree, .Button, "Minimize")
    let count_before = s.counters[0usize].count
    if locked_tree_error != ok || !has_disabled_min || !disabled_min.state.disabled || testing.tap(&harness, minimize.x + 20.0, 16.0) != ok || s.counters[0usize].count != count_before { os.exit(94i32) }
    // macOS: lights at the start, in the order close, minimise, zoom, and the title in the middle.
    s.platform = .Mac
    s.minimizable = true
    clock += 100000000i64
    let (mac, mac_error) = build(&f, &theme, s)
    if mac_error != ok || testing.pump(&harness, mac, time.Instant { nanos: clock }) != ok { os.exit(95i32) }
    let (mac_close, has_mac_close) = bounds(&harness, &runtime, 3004u64)
    let (mac_min, has_mac_min) = bounds(&harness, &runtime, 3002u64)
    let (mac_max, has_mac_max) = bounds(&harness, &runtime, 3003u64)
    if !has_mac_close || !has_mac_min || !has_mac_max || !rect_is(mac_close, 10.0, 8.0, 12.0, 12.0) || !rect_is(mac_min, 30.0, 8.0, 12.0, 12.0) || !rect_is(mac_max, 50.0, 8.0, 12.0, 12.0) { os.exit(96i32) }
    let (mac_shot, mac_shot_error) = testing.snapshot(&harness, a)
    if mac_shot_error != ok || !is_color(mac_shot, at(mac_close.x + 6.0, mac_close.y + 6.0), style.color(&tokens, .Error)) || !is_color(mac_shot, at(mac_min.x + 6.0, mac_min.y + 6.0), style.color(&tokens, .Warning)) || !is_color(mac_shot, at(mac_max.x + 6.0, mac_max.y + 6.0), style.color(&tokens, .Success)) { os.exit(97i32) }
    try io.print("ui title bar ok\n")
    ret ok
}
