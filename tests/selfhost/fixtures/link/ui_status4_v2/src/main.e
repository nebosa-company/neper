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
    // (D1278) A text-only snackbar dismisses itself once it has shown 4 s, counted
    // from its first frame after appearing: not at 3 s, once by 4.1 s, not again.
    if testing.hover(&harness, 590.0, 5.0) != ok { os.exit(26i32) }
    var timed_step = 0usize
    var dismissed_at = s.presses
    while timed_step < 5usize {
        var at_nanos = 10000000000i64
        if timed_step == 1usize { at_nanos = 10016000000i64 }
        if timed_step == 2usize { at_nanos = 13000000000i64 }
        if timed_step == 3usize { at_nanos = 14100000000i64 }
        if timed_step == 4usize { at_nanos = 16000000000i64 }
        if testing.begin(&harness, time.Instant { nanos: at_nanos }) != ok { os.exit(27i32) }
        f = mem.arena_from(frame_storage)
        let (timed, timed_error) = control.snackbar(&f, 750u64, &theme, s.notices[1usize..2usize], 320.0)
        let (timed_page, timed_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if timed_error != ok || timed_page_error != ok { os.exit(22i32) }
        timed_page[0usize] = timed
        if testing.pump(&harness, widget.box(0u64, control.sized_style(600.0, 400.0), timed_page[0usize..1usize]), time.Instant { nanos: at_nanos }) != ok { os.exit(23i32) }
        if timed_step == 0usize { dismissed_at = s.presses }
        if timed_step >= 1usize && timed_step <= 2usize && s.presses != dismissed_at { os.exit(24i32) }
        if timed_step >= 3usize && s.presses != dismissed_at + 1usize { os.exit(25i32) }
        timed_step += 1usize
    }
    // (D1287) A snackbar enters fading in: half way its surface is not yet the
    // full `inverse-surface`; settled, it is.
    let full_ink = style.color(&tokens, .InverseSurface)
    var enter_step = 0usize
    while enter_step < 5usize {
        var enter_at = 40000000000i64
        var enter_count = 0usize
        if enter_step == 1usize { enter_at = 40016000000i64 }
        if enter_step == 2usize {
            enter_at = 40100000000i64
            enter_count = 1usize
        }
        if enter_step == 3usize {
            enter_at = 40225000000i64
            enter_count = 1usize
        }
        if enter_step == 4usize {
            enter_at = 40500000000i64
            enter_count = 1usize
        }
        if testing.begin(&harness, time.Instant { nanos: enter_at }) != ok { os.exit(28i32) }
        f = mem.arena_from(frame_storage)
        let (entering, entering_error) = control.snackbar(&f, 770u64, &theme, s.notices[0usize..enter_count], 320.0)
        let (enter_page, enter_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if entering_error != ok || enter_page_error != ok { os.exit(29i32) }
        enter_page[0usize] = entering
        var enter_ground = control.sized_style(640.0, 400.0)
        enter_ground.background = paint.Brush { Solid: style.color(&tokens, .Background) }
        if testing.pump(&harness, widget.box(0u64, enter_ground, enter_page[0usize..1usize]), time.Instant { nanos: enter_at }) != ok { os.exit(30i32) }
        if enter_step >= 3usize {
            let (enter_box, has_enter_box) = widget.bounds_of(&runtime, testing.by_key(&harness, 771u64).element)
            let (enter_shot, enter_shot_error) = testing.snapshot(&harness, a)
            if !has_enter_box || enter_shot_error != ok { os.exit(31i32) }
            let solid = is_color(enter_shot, at(enter_box.x - 20.0, enter_box.y + enter_box.height * 0.5), full_ink)
            if enter_step == 3usize && solid { os.exit(32i32) }
            if enter_step == 4usize && !solid { os.exit(33i32) }
        }
        enter_step += 1usize
    }
    // (D1394) In a compact window, 360 wide, the snackbar spans it less 16 a
    // side: its surface at 20 and at 340 across, the ground at 8.
    let (compact_rt, compact_runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 600usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 32u16, max_commands: 2048usize })
    if compact_runtime_error != ok { os.exit(34i32) }
    var compact_runtime = compact_rt
    let compact_theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &compact_runtime }
    let (compact_h, compact_harness_error) = testing.harness(a, &compact_runtime, 360u32, 400u32, 1.0)
    if compact_harness_error != ok { os.exit(35i32) }
    var compact_harness = compact_h
    f = mem.arena_from(frame_storage)
    let (compact_snack, compact_snack_error) = control.snackbar(&f, 790u64, &compact_theme, s.notices[0usize..1usize], 320.0)
    let (compact_page, compact_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if compact_snack_error != ok || compact_page_error != ok { os.exit(36i32) }
    compact_page[0usize] = compact_snack
    var compact_ground = control.sized_style(360.0, 400.0)
    compact_ground.background = paint.Brush { Solid: style.color(&tokens, .Background) }
    if testing.pump(&compact_harness, widget.box(0u64, compact_ground, compact_page[0usize..1usize]), time.Instant { nanos: 41000000000i64 }) != ok { os.exit(37i32) }
    // A second frame: the first build could not yet see the window's width.
    f = mem.arena_from(frame_storage)
    let (compact_again, compact_again_error) = control.snackbar(&f, 790u64, &compact_theme, s.notices[0usize..1usize], 320.0)
    let (again_page, again_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if compact_again_error != ok || again_page_error != ok { os.exit(36i32) }
    again_page[0usize] = compact_again
    if testing.pump(&compact_harness, widget.box(0u64, compact_ground, again_page[0usize..1usize]), time.Instant { nanos: 41016000000i64 }) != ok { os.exit(37i32) }
    let (compact_shot, compact_shot_error) = testing.snapshot(&compact_harness, a)
    if compact_shot_error != ok { os.exit(38i32) }
    let surface_ink = style.color(&tokens, .InverseSurface)
    let compact_row: f32 = 364.0
    let compact_at_start = (usize(compact_row) * 360usize + 20usize) * 4usize
    let compact_at_end = (usize(compact_row) * 360usize + 340usize) * 4usize
    let compact_outside = (usize(compact_row) * 360usize + 8usize) * 4usize
    if !is_color(compact_shot, compact_at_start, surface_ink) || !is_color(compact_shot, compact_at_end, surface_ink) || is_color(compact_shot, compact_outside, surface_ink) { os.exit(39i32) }
    if testing.close(&compact_harness) != ok || widget.close(&compact_runtime) != ok { os.exit(40i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(21i32) }
    try io.print("ui status4 v2 ok\n")
    ret ok
}
