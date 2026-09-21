// `e.ui.window` and `e.ui.input` (D797): a window over the host's primitives with a
// scene target, a frame rendered and shown through `request_frame`, the `Frame`
// event it queues delivered first, the host's own events mapped to the window's
// id, cursor, title and visibility, and a closed window stale. A host without
// windows answers `Unsupported` at `open`, and the fixture says so.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.ui.input
use e.ui.window

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let options = window.Options { title: "neper ui_window", width: 320u32, height: 200u32, min_width: 0u32, min_height: 0u32, resizable: true, transparent: false, mode: .Windowed }
    let (w, window_error) = window.open(a, device, options)
    if window_error == window.Unsupported {
        try io.print("ui window unsupported\n")
        ret ok
    }
    if window_error != ok { os.exit(2i32) }
    var win = w
    let (metrics, metrics_error) = window.metrics(&win)
    if metrics_error != ok || metrics.framebuffer_width != 320u32 || metrics.framebuffer_height != 200u32 || !(metrics.scale >= 1.0) { os.exit(3i32) }
    if !(metrics.logical_size.width > 0.0) || metrics.logical_size.width > 320.0 { os.exit(4i32) }
    let (canvas, target_error) = window.draw_target(&win)
    if target_error != ok { os.exit(5i32) }
    // A frame: a red fill, rendered into the window's target and shown.
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(6i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 2u32, 2u32)
    if renderer_error != ok { os.exit(7i32) }
    var renderer = r
    let (b, builder_error) = scene.builder(a, 4usize)
    if builder_error != ok { os.exit(8i32) }
    var builder = b
    if scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 320.0, 200.0), brush: paint.Brush { Solid: paint.rgba(0.8, 0.1, 0.1, 1.0) } } }) != ok { os.exit(9i32) }
    let (compiled, compile_error) = scene.compile(&renderer, scene.finish(&builder))
    if compile_error != ok { os.exit(10i32) }
    if scene.render(&renderer, compiled, canvas, geometry.Size { width: 320.0, height: 200.0 }) != ok { os.exit(11i32) }
    if window.request_frame(&win) != ok { os.exit(12i32) }
    // The input queue: the requested frame comes first, then whatever the host has.
    let (iq, iq_error) = input.queue(a, 64usize)
    if iq_error != ok { os.exit(13i32) }
    var events = iq
    let (first, has_first, first_error) = input.poll(&events, time.Duration { nanos: 0i64 })
    if first_error != ok || !has_first || first.tag != .Frame { os.exit(14i32) }
    if first.Frame.slot != win.id.slot || first.Frame.generation != win.id.generation { os.exit(15i32) }
    var rounds = 0usize
    var seen = 0usize
    while rounds < 25usize {
        let (event, any, poll_error) = input.poll(&events, time.Duration { nanos: 20000000i64 })
        if poll_error != ok { os.exit(16i32) }
        if any {
            seen += 1usize
            if event.tag == .Close { os.exit(17i32) }
        }
        rounds += 1usize
    }
    if window.title(&win, "neper ui_window: titled") != ok { os.exit(18i32) }
    if window.cursor(&win, .Hand) != ok { os.exit(19i32) }
    if window.visible(&win, false) != ok { os.exit(20i32) }
    let (hidden, hidden_error) = window.metrics(&win)
    if hidden_error != ok || hidden.visible { os.exit(21i32) }
    if input.capture(&events, win.id, 0u32) != ok || input.release_capture(&events, win.id, 0u32) != ok { os.exit(22i32) }
    if input.composition_rect(&events, win.id, geometry.rect(0.0, 0.0, 1.0, 1.0)) != input.TooLarge { os.exit(23i32) }
    // The clipboard is the desktop's; a session without one answers, and that is fine.
    let (_, clip_error) = window.clipboard_get(a, &win)
    if clip_error != ok && clip_error != window.Invalid && clip_error != window.Unsupported { os.exit(24i32) }
    // Closed: stale afterwards, unknown to the input queue.
    if window.close(&win) != ok { os.exit(25i32) }
    if window.close(&win) != window.Closed { os.exit(26i32) }
    let (_, stale_error) = window.metrics(&win)
    if stale_error != window.Closed { os.exit(27i32) }
    if input.capture(&events, win.id, 0u32) != input.Closed { os.exit(28i32) }
    if input.close(&events) != ok || input.close(&events) != input.Closed { os.exit(29i32) }
    if scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(30i32) }
    try io.print("ui window ok\n")
    ret ok
}
