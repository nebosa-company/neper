// The v2 dock layout over its slot model (D968, widget plan P5-08,
// docs/ux/components/DockLayout) under the light theme at pointer density: a 40
// activity strip on `surface-container` leads with a round button per side-slot
// panel, the open one tonal; the left slot's two panels share it as tabs; a
// floating panel stands at its rectangle. Presses reach the caller as events
// that dock_apply folds into the model: a strip button shows its panel, then
// collapses the slot; Maximise fills the area with the bottom slot's panel and
// Restore undoes it; Close hides a panel and the slot shows the next; Dock
// returns a floating panel to its home slot as a tab; a sash drag resizes; a
// Move the caller sends puts a panel in another slot.

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
use e.ui.navigation
use e.ui.style
use e.ui.testing
use e.ui.widget

type Store = struct { model: navigation.DockModel, placements: [6]navigation.DockPlacement, events: usize }

fn on_event(ctx: *void, e: navigation.DockEvent) -> err {
    let s = mem.cast[*Store](ctx)
    s.events += 1usize
    navigation.dock_apply(&s.model, s.placements[0usize..6usize], e)
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

fn place(name: str, icon: control.GlyphKind, slot: navigation.DockSlot, home: navigation.DockSlot) -> navigation.DockPlacement {
    ret navigation.DockPlacement { name: name, icon: icon, slot: slot, home: home, x: 0.0, y: 0.0, width: 0.0, height: 0.0 }
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let (contents, contents_error) = mem.alloc[widget.Node](a, 6usize)
    if contents_error != ok { ret (zero, contents_error) }
    var i = 0usize
    while i < 6usize {
        contents[i] = blank(10.0, 10.0)
        i += 1usize
    }
    let (made, made_error) = navigation.dock_layout_of(a, 200u64, t, s.model, s.placements[0usize..6usize], contents[0usize..6usize], blank(10.0, 10.0), widget.Change[navigation.DockEvent] { ctx: mem.cast[*void](s), invoke: on_event }, 800.0, 400.0)
    ret (made, made_error)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 800usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn frame(h: *testing.Harness, f: *mem.Arena, t: *const control.Theme, s: *Store) -> bool {
    let (root, build_error) = build(f, t, s)
    if build_error != ok { ret false }
    ret testing.pump(h, root, time.Instant { nanos: 1000000000i64 }) == ok
}

fn tap_key(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> bool {
    let (b, found) = bounds(h, runtime, key)
    if !found { ret false }
    ret testing.tap(h, b.x + b.width * 0.5, b.y + b.height * 0.5) == ok
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
    let (h, harness_error) = testing.harness(a, &runtime, 800u32, 400u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    s.placements[0usize] = place("Explorer", .Search, .Left, .Left)
    s.placements[1usize] = place("Outline", .Picture, .Left, .Left)
    s.placements[2usize] = place("Inspector", .Person, .Right, .Right)
    s.placements[3usize] = place("Problems", .Alert, .Bottom, .Bottom)
    s.placements[4usize] = place("Terminal", .Clock, .Bottom, .Bottom)
    s.placements[5usize] = navigation.DockPlacement { name: "Palette", icon: .Dash, slot: .Floating, home: .Right, x: 500.0, y: 60.0, width: 260.0, height: 160.0 }
    s.model.sizes = navigation.DockSizes { left: 200.0, right: 200.0, bottom: 100.0 }
    s.model.current[0usize] = 0usize
    s.model.current[1usize] = 2usize
    s.model.current[2usize] = 3usize
    let (frame_storage, storage_error) = mem.alloc[u8](a, 4194304usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    if !frame(&harness, &f, &theme, s) { os.exit(9i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(10i32) }
    let strip = style.color(&tokens, .SurfaceContainer)
    // The strip: 40 on surface-container, a button per side-slot panel (not the
    // bottom's), the open one tonal.
    let (explorer, has_explorer) = bounds(&harness, &runtime, 220u64)
    let (outline, has_outline) = bounds(&harness, &runtime, 221u64)
    if !has_explorer || !has_outline || !near(explorer.width, 32.0) || !near(explorer.x, 4.0) || !near(outline.y - explorer.y, 36.0) || testing.by_key(&harness, 223u64).count != 0usize || testing.by_key(&harness, 225u64).count != 1usize { os.exit(11i32) }
    if !is_color(shot, at(20.0, 390.0), strip) || !is_color(shot, at(explorer.x + 16.0, explorer.y + 4.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(outline.x + 16.0, outline.y + 4.0), strip) { os.exit(12i32) }
    // The slots: the left panel 200 wide after the strip, tabbed with its
    // neighbour, as is the bottom; the floating panel at its rectangle.
    let (left, has_left) = bounds(&harness, &runtime, 240u64)
    let (floated, has_floated) = bounds(&harness, &runtime, 380u64)
    if !has_left || !near(left.x, 40.0) || !near(left.width, 200.0) || testing.by_role(&harness, .Tab).count != 4usize { os.exit(13i32) }
    if !has_floated || !near(floated.x, 500.0) || !near(floated.y, 60.0) || !near(floated.width, 260.0) { os.exit(14i32) }
    // A strip button shows its panel; pressed again, it collapses the slot.
    if !tap_key(&harness, &runtime, 221u64) || s.model.current[0usize] != 1usize || s.model.collapsed[0usize] { os.exit(15i32) }
    if !frame(&harness, &f, &theme, s) || !tap_key(&harness, &runtime, 221u64) || !s.model.collapsed[0usize] { os.exit(16i32) }
    if !frame(&harness, &f, &theme, s) || testing.by_key(&harness, 240u64).count != 0usize || testing.by_key(&harness, 203u64).count != 0usize { os.exit(17i32) }
    // Maximise fills the area with the bottom slot's panel; Restore undoes it.
    if !tap_key(&harness, &runtime, 274u64) || s.model.maximised != 3u8 { os.exit(18i32) }
    if !frame(&harness, &f, &theme, s) { os.exit(19i32) }
    let (whole, has_whole) = bounds(&harness, &runtime, 272u64)
    if !has_whole || !near(whole.width, 760.0) || !near(whole.height, 400.0) || testing.by_label(&harness, "Restore panel").count != 1usize { os.exit(20i32) }
    if !tap_key(&harness, &runtime, 274u64) || s.model.maximised != 0u8 || !frame(&harness, &f, &theme, s) { os.exit(21i32) }
    // Close hides Problems; the bottom slot shows Terminal alone.
    if !tap_key(&harness, &runtime, 273u64) || s.placements[3usize].slot != .Hidden || !frame(&harness, &f, &theme, s) { os.exit(22i32) }
    if testing.by_label(&harness, "Close Terminal panel").count != 1usize || testing.by_label(&harness, "Close Problems panel").count != 0usize { os.exit(23i32) }
    // Dock returns the palette to the right slot, where it is the current tab.
    if !tap_key(&harness, &runtime, 383u64) || s.placements[5usize].slot != .Right || s.model.current[1usize] != 5usize || !frame(&harness, &f, &theme, s) { os.exit(24i32) }
    if testing.by_key(&harness, 380u64).count != 0usize || testing.by_label(&harness, "Close Palette panel").count != 1usize { os.exit(25i32) }
    // Explorer's button reopens the left slot; its sash dragged 20 resizes it.
    if !tap_key(&harness, &runtime, 220u64) || s.model.collapsed[0usize] || s.model.current[0usize] != 0usize || !frame(&harness, &f, &theme, s) { os.exit(26i32) }
    let (sash, has_sash) = bounds(&harness, &runtime, 203u64)
    if !has_sash { os.exit(27i32) }
    let grip = geometry.Point { x: sash.x + 4.0, y: sash.y + 200.0 }
    if testing.drag(&harness, grip, geometry.Point { x: grip.x + 20.0, y: grip.y }, 4usize) != ok || !near(s.model.sizes.left, 220.0) { os.exit(28i32) }
    // A Move the caller sends puts Inspector in the bottom slot.
    navigation.dock_apply(&s.model, s.placements[0usize..6usize], navigation.DockEvent { kind: .Move, panel: 2usize, slot: .Bottom, sizes: zero })
    if !frame(&harness, &f, &theme, s) || testing.by_label(&harness, "Close Inspector panel").count != 1usize || s.placements[2usize].home != .Bottom { os.exit(29i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(30i32) }
    try io.print("ui containers4 v2 ok\n")
    ret ok
}
