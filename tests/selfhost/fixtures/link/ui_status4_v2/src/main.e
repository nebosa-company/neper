// The v2 snackbar and toast (D971, widget plan P5-09, docs/ux/components/Snackbar)
// under the light theme: the snackbar on `inverse-surface` at least 48 tall, 24
// from the bottom start of the window (the margin survives the window clamp), its
// action and a Dismiss close pressing; the toast 340 wide on
// `surface-container-high`, 12 in from the top end, with a 32 info well; both a
// polite status named by the text.

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
use e.ui.style
use e.ui.testing
use e.ui.widget

type Store = struct { presses: usize, press: widget.Submit, notices: [2]control.Notice }

fn on_press(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.presses += 1usize
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

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let (snack, e1) = control.snackbar(a, 700u64, t, s.notices[0usize..1usize], 320.0)
    let (pop, e2) = control.toast(a, 800u64, t, s.notices[1usize..2usize], 320.0)
    if e1 != ok || e2 != ok { ret (zero, e1) }
    let (items, items_error) = mem.alloc[widget.Node](a, 2usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = snack
    items[1usize] = pop
    var page = style.defaults()
    page.width = style.Length { Px: 640.0 }
    page.height = style.Length { Px: 400.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, page, items[0usize..2usize]), ok)
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
    let (h, harness_error) = testing.harness(a, &runtime, 640u32, 400u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    s.press = widget.Submit { ctx: mem.cast[*void](s), invoke: on_press }
    s.notices[0usize] = control.Notice { text: "3 files moved", action_label: "Undo", action: s.press, dismiss: s.press }
    s.notices[1usize] = control.Notice { text: "Build 4128 finished", action_label: "", action: s.press, dismiss: s.press }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, s)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    let ground = style.color(&tokens, .Background)
    // The snackbar: 24 from the bottom start, at least 48 tall, `inverse-surface`.
    if !is_color(shot, at(30.0, 350.0), style.color(&tokens, .InverseSurface)) || !is_color(shot, at(30.0, 330.0), style.color(&tokens, .InverseSurface)) { os.exit(13i32) }
    if !is_color(shot, at(10.0, 350.0), ground) || !is_color(shot, at(30.0, 390.0), ground) { os.exit(14i32) }
    let (moved, has_moved) = find(tree, .Status, "3 files moved")
    if !has_moved || moved.live != .Polite { os.exit(15i32) }
    let (close, has_close) = bounds(&harness, &runtime, 702u64)
    if !has_close || !near(close.width, 40.0) || close.x + close.width > 24.0 + 312.0 || close.y + close.height > 376.0 { os.exit(16i32) }
    if !tap_key(&harness, &runtime, 701u64) || !tap_key(&harness, &runtime, 702u64) || s.presses != 2usize { os.exit(17i32) }
    // The toast: 340 wide on `surface-container-high`, 12 in from the top end, the
    // 32 info well in `primary-container`.
    if !is_color(shot, at(458.0, 22.0), style.color(&tokens, .SurfaceContainerHigh)) || !is_color(shot, at(634.0, 30.0), ground) || !is_color(shot, at(458.0, 6.0), ground) { os.exit(18i32) }
    if !is_color(shot, at(308.0, 40.0), style.color(&tokens, .PrimaryContainer)) { os.exit(19i32) }
    let (finished, has_finished) = find(tree, .Status, "Build 4128 finished")
    if !has_finished || testing.by_key(&harness, 801u64).count != 0usize || testing.by_label(&harness, "Dismiss").count != 2usize { os.exit(20i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(21i32) }
    try io.print("ui status4 v2 ok\n")
    ret ok
}
