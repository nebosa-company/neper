// `e.ui.testing` and `e.ui.animation` (D800): a harness over a widget runtime with
// no window -- a frame pumped at a supplied instant, elements found by key and by
// text, a press sent, the frame snapshotted and compared against itself and against
// a golden that differs by one channel; and a controller's value along each curve,
// repeating and reversing, finished or not, restarted.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.text.shape
use e.ui.animation
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget
use e.ui.window

type Counter = struct { presses: usize }

fn on_press(ctx: *void, event: input.Event) -> err {
    let counter = mem.cast[*Counter](ctx)
    if event.tag == .PointerDown { counter.presses += 1usize }
    ret ok
}

fn px(v: f32) -> style.Length {
    ret style.Length { Px: v }
}

fn sized(width: f32, height: f32, r: f32, g: f32, b: f32) -> style.Style {
    var s = style.defaults()
    s.width = px(width)
    s.height = px(height)
    s.background = paint.Brush { Solid: paint.rgba(r, g, b, 1.0) }
    ret s
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    // The animation controller: linear, eased, repeating, reversing.
    let start = time.Instant { nanos: 1000000000i64 }
    var linear = animation.controller(start, time.millis(100i64), .Linear)
    if !near(animation.value(&linear, start), 0.0) || !near(animation.value(&linear, time.instant_add(start, time.millis(25i64))), 0.25) { os.exit(1i32) }
    if !near(animation.value(&linear, time.instant_add(start, time.millis(250i64))), 1.0) || !animation.finished(&linear, time.instant_add(start, time.millis(100i64))) { os.exit(2i32) }
    if animation.finished(&linear, time.instant_add(start, time.millis(99i64))) { os.exit(3i32) }
    let ease_in = animation.controller(start, time.millis(100i64), .EaseIn)
    let ease_out = animation.controller(start, time.millis(100i64), .EaseOut)
    let ease_in_out = animation.controller(start, time.millis(100i64), .EaseInOut)
    let half = time.instant_add(start, time.millis(50i64))
    if !near(animation.value(&ease_in, half), 0.25) || !near(animation.value(&ease_out, half), 0.75) || !near(animation.value(&ease_in_out, half), 0.5) { os.exit(4i32) }
    var repeating = animation.controller(start, time.millis(100i64), .Linear)
    repeating.repeating = true
    if !near(animation.value(&repeating, time.instant_add(start, time.millis(125i64))), 0.25) || animation.finished(&repeating, time.instant_add(start, time.seconds(9i64))) { os.exit(5i32) }
    var reversing = animation.controller(start, time.millis(100i64), .Linear)
    reversing.reverse = true
    if !near(animation.value(&reversing, time.instant_add(start, time.millis(150i64))), 0.5) || animation.finished(&reversing, time.instant_add(start, time.millis(150i64))) || !animation.finished(&reversing, time.instant_add(start, time.millis(200i64))) { os.exit(6i32) }
    animation.restart(&linear, time.instant_add(start, time.seconds(5i64)))
    if !near(animation.value(&linear, time.instant_add(start, time.seconds(5i64))), 0.0) { os.exit(7i32) }

    // The harness: a runtime over a renderer, a 40x30 surface at scale 1.
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(8i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(9i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(10i32) }
    var renderer = r
    let limits = widget.Limits { max_elements: 16usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 32usize }
    let (rt, runtime_error) = widget.runtime(a, &renderer, limits)
    if runtime_error != ok { os.exit(11i32) }
    var runtime = rt
    let (h, harness_error) = testing.harness(a, &runtime, 40u32, 30u32, 1.0)
    if harness_error != ok { os.exit(12i32) }
    var harness = h
    widget.begin_frame(&runtime, start)
    if animation.frame_time(&runtime).nanos != start.nanos || !near(animation.cycle(&runtime, time.millis(100i64)), 0.0) || !widget.animation_frame_requested(&runtime) { os.exit(30i32) }
    let quarter = time.instant_add(start, time.millis(25i64))
    widget.begin_frame(&runtime, quarter)
    if widget.animation_frame_requested(&runtime) || !near(animation.cycle(&runtime, time.millis(100i64)), 0.25) || !near(animation.pulse(&runtime, time.millis(100i64), 0.4, 1.0), 0.7) { os.exit(31i32) }
    var counter = Counter { presses: 0usize }
    let (children, children_error) = mem.alloc[widget.Node](a, 2usize)
    if children_error != ok { os.exit(13i32) }
    children[0usize] = widget.box(1u64, sized(20.0, 10.0, 1.0, 0.0, 0.0), zero)
    children[1usize] = widget.button(2u64, widget.Button { action: widget.Action { ctx: mem.cast[*void](&counter), invoke: on_press }, enabled: true }, sized(20.0, 10.0, 0.0, 0.0, 1.0), zero)
    var column = style.defaults()
    column.width = px(40.0)
    column.height = px(30.0)
    let root = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, children[0usize..2usize])
    if testing.pump(&harness, root, start) != ok { os.exit(14i32) }
    let found = testing.by_key(&harness, 2u64)
    if found.count != 1usize { os.exit(15i32) }
    let (bounds, has_bounds) = widget.bounds_of(&runtime, found.element)
    if !has_bounds || bounds.y != 10.0 || bounds.height != 10.0 { os.exit(16i32) }
    if testing.by_key(&harness, 9u64).count != 0usize { os.exit(17i32) }
    if testing.by_text(&harness, "nothing").count != 0usize { os.exit(18i32) }
    // A press at the button's centre reaches its action.
    let down = input.Event { PointerDown: input.Pointer { window: window.Id { slot: 0u32, generation: 0u32 }, device: 0u32, pointer: 0u32, kind: .Mouse, position: geometry.Point { x: 10.0, y: 15.0 }, buttons: 1u32, changed: .Primary } }
    if testing.send(&harness, down) != ok || counter.presses != 1usize { os.exit(19i32) }
    // The snapshot: red above, blue below, empty to the right; it compares against
    // itself and not against a copy with one channel moved past the tolerance.
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok || shot.width != 40u32 || shot.height != 30u32 { os.exit(20i32) }
    if shot.pixels[(5usize * 40usize + 5usize) * 4usize] != 255u8 || shot.pixels[(15usize * 40usize + 5usize) * 4usize + 2usize] != 255u8 || shot.pixels[(5usize * 40usize + 30usize) * 4usize + 3usize] != 0u8 { os.exit(21i32) }
    let (view, view_error) = image.make_const(shot.pixels, shot.width, shot.height, shot.stride, shot.format, shot.alpha)
    if view_error != ok { os.exit(22i32) }
    if testing.compare(view, view, 0u8) != ok { os.exit(23i32) }
    let (golden, golden_error) = mem.alloc[u8](a, shot.pixels.len)
    if golden_error != ok { os.exit(24i32) }
    mem.copy[u8](golden, shot.pixels)
    golden[(5usize * 40usize + 5usize) * 4usize + 1usize] = 9u8
    let (golden_view, golden_view_error) = image.make_const(golden, shot.width, shot.height, shot.stride, shot.format, shot.alpha)
    if golden_view_error != ok { os.exit(25i32) }
    if testing.compare(view, golden_view, 8u8) != testing.GoldenMismatch || testing.compare(view, golden_view, 9u8) != ok { os.exit(26i32) }
    if testing.close(&harness) != ok || testing.close(&harness) != testing.NotFound { os.exit(27i32) }
    if widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(28i32) }
    try io.print("ui testing ok\n")
    ret ok
}
