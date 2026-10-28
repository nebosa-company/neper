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

// A presenter-shaped fake pool proves that `window.close` releases the callback's slot even on
// hosts without GL: the seventeenth sequential attachment only fits if every prior close ran it.
const FAKE_MAX_PRESENTERS: usize = 16usize
const PRESENTER_CYCLES: usize = 17usize
type PostMessage = fn(usize, u32, usize, isize) -> i32

var fake_slots: [16]bool = zero
var fake_releases: usize = 0usize
var fake_present_fails: bool = false

fn fake_present(index: usize, host: os.Window, pixels: []const u32, width: u32, height: u32, changed: window.Changed) -> err {
    if fake_present_fails { ret window.Invalid }
    ret ok
}

fn fake_release(index: usize) -> err {
    if index >= FAKE_MAX_PRESENTERS || !fake_slots[index] { ret window.Invalid }
    fake_slots[index] = false
    fake_releases += 1usize
    ret ok
}

fn fake_slots_clear() -> bool {
    var index = 0usize
    while index < FAKE_MAX_PRESENTERS {
        if fake_slots[index] { ret false }
        index += 1usize
    }
    ret true
}

fn fake_attach(a: *mem.Arena, w: *window.Window) -> err {
    var index = 0usize
    while index < FAKE_MAX_PRESENTERS && fake_slots[index] { index += 1usize }
    if index == FAKE_MAX_PRESENTERS { ret window.Unsupported }
    fake_slots[index] = true
    let installed = window.set_presenter(w, window.Presenter { context: index, present: fake_present, release: fake_release })
    if installed != ok {
        fake_slots[index] = false
        ret installed
    }
    ret ok
}

// A factory that reports failure after taking a slot checks the defensive error-path release in
// `window.open`; a real presenter must itself also make its partially-open path safe.
fn fake_attach_and_fail(a: *mem.Arena, w: *window.Window) -> err {
    let attached = fake_attach(a, w)
    if attached != ok { ret attached }
    ret window.Invalid
}

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
    // Pointer buttons belong to their window's input queue. A held button in the
    // second window must not become a held button on a move in the first (#1216).
    let (other_opened, other_open_error) = window.open(a, device, options)
    if other_open_error != ok { os.exit(61i32) }
    var other = other_opened
    let (first_queue, first_queue_error) = input.queue_for(a, win.id, 8usize)
    if first_queue_error != ok { os.exit(62i32) }
    var first_events = first_queue
    let (second_queue, second_queue_error) = input.queue_for(a, other.id, 8usize)
    if second_queue_error != ok { os.exit(63i32) }
    var second_events = second_queue
    let (user32, user32_error) = os.dlopen(a, "user32.dll")
    if user32_error == ok {
        let (post, post_error) = os.dlsym[PostMessage](a, user32, "PostMessageW")
        if post_error != ok { os.exit(64i32) }
        let (first_host, first_host_error) = window.host_window(&win)
        let (second_host, second_host_error) = window.host_window(&other)
        if first_host_error != ok || second_host_error != ok { os.exit(65i32) }
        let (first_native, _, first_native_error) = os.window_native(first_host)
        let (second_native, _, second_native_error) = os.window_native(second_host)
        if first_native_error != ok || second_native_error != ok { os.exit(66i32) }
        if post(second_native, 513u32, 1usize, isize(10usize | (10usize << 16usize))) == 0i32 { os.exit(67i32) }
        var saw_down = false
        var route_round = 0usize
        while route_round < 8usize && !saw_down {
            let (first_event, first_any, first_poll_error) = input.poll_for(&first_events, win.id, time.millis(5i64))
            if first_poll_error != ok { os.exit(68i32) }
            if first_any && first_event.tag == .PointerDown { os.exit(69i32) }
            let (second_event, second_any, second_poll_error) = input.poll_for(&second_events, other.id, time.millis(5i64))
            if second_poll_error != ok { os.exit(70i32) }
            if second_any && second_event.tag == .PointerDown {
                if second_event.PointerDown.buttons != 1u32 { os.exit(71i32) }
                saw_down = true
            }
            route_round += 1usize
        }
        if !saw_down { os.exit(72i32) }
        if post(first_native, 512u32, 0usize, isize(12usize | (12usize << 16usize))) == 0i32 { os.exit(73i32) }
        var saw_move = false
        route_round = 0usize
        while route_round < 8usize && !saw_move {
            let (first_event, first_any, first_poll_error) = input.poll_for(&first_events, win.id, time.millis(5i64))
            if first_poll_error != ok { os.exit(74i32) }
            if first_any && first_event.tag == .PointerMove {
                if first_event.PointerMove.buttons != 0u32 { os.exit(75i32) }
                saw_move = true
            }
            route_round += 1usize
        }
        if !saw_move { os.exit(76i32) }
        if post(second_native, 514u32, 0usize, isize(10usize | (10usize << 16usize))) == 0i32 { os.exit(77i32) }
        let _ = os.dlclose(user32)
    }
    if input.close(&first_events) != ok || input.close(&second_events) != ok { os.exit(78i32) }
    if window.close(&other) != ok { os.exit(79i32) }
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
    window.set_default_presenter(window.PresenterFactory { attach: fake_attach })
    let (failure_opened, failure_open_error) = window.open(a, device, options)
    if failure_open_error != ok { os.exit(31i32) }
    var failure = failure_opened
    let (failure_canvas, failure_canvas_error) = window.draw_target(&failure)
    if failure_canvas_error != ok || scene.render(&renderer, compiled, failure_canvas, geometry.Size { width: 320.0, height: 200.0 }) != ok { os.exit(32i32) }
    fake_present_fails = true
    if window.request_frame(&failure) != ok { os.exit(33i32) }
    fake_present_fails = false
    if window.presenting(&failure) || fake_releases != 1usize || !fake_slots_clear() { os.exit(34i32) }
    if window.close(&failure) != ok || fake_releases != 1usize { os.exit(35i32) }
    var cycle = 0usize
    while cycle < PRESENTER_CYCLES {
        let (opened, opened_error) = window.open(a, device, options)
        if opened_error != ok { os.exit(36i32) }
        var attached = opened
        if !window.presenting(&attached) { os.exit(37i32) }
        if window.close(&attached) != ok { os.exit(38i32) }
        if fake_releases != cycle + 2usize || !fake_slots_clear() { os.exit(39i32) }
        cycle += 1usize
    }
    window.set_default_presenter(window.PresenterFactory { attach: fake_attach_and_fail })
    let (partially_attached, partial_error) = window.open(a, device, options)
    if partial_error != ok { os.exit(40i32) }
    var fallback = partially_attached
    if window.presenting(&fallback) { os.exit(41i32) }
    if fake_releases != PRESENTER_CYCLES + 2usize || !fake_slots_clear() { os.exit(42i32) }
    if window.close(&fallback) != ok { os.exit(43i32) }
    if fake_releases != PRESENTER_CYCLES + 2usize { os.exit(44i32) }
    if scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(30i32) }
    try io.print("ui window ok\n")
    ret ok
}
