// `e.ui.app` (D802): the whole chain in one `init` -- device, window, renderer,
// widget runtime, input queue, the application's builder behind its context -- a
// first `step` building and presenting a frame, later steps presenting only when a
// frame is due, `stop` ending the loop, `close` closing everything. Publication
// of the window's semantic tree answers `Unsupported` until a host bridge exists.
// A host without windows fails at `init`, and the fixture says so.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.paint
use e.ui.accessibility
use e.ui.app
use e.ui.style
use e.ui.widget
use e.ui.window

type Model = struct { builds: usize, taps: usize }
type PostMessage = fn(usize, u32, usize, isize) -> i32

fn on_gesture(ctx: *void, gesture: widget.Gesture) -> err {
    if gesture.tag == .Tap { mem.cast[*Model](ctx).taps += 1usize }
    ret ok
}

fn build(model: *Model, ctx: *widget.BuildContext) -> (widget.Node, err) {
    model.builds += 1usize
    if model.builds < 3usize { widget.request_animation_frame(ctx.runtime) }
    var s = style.defaults()
    s.width = style.Length { Px: 200.0 }
    s.height = style.Length { Px: 120.0 }
    s.background = paint.Brush { Solid: paint.rgba(0.2, 0.4, 0.8, 1.0) }
    ret (widget.region(1u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](model), invoke: on_gesture }, gestures: 1u8, enabled: true, focusable: false }, s, zero), ok)
}

fn settle(first: *app.App, second: *app.App) -> err {
    var round = 0usize
    while round < 8usize {
        let (first_more, first_error) = app.step(first, time.Duration { nanos: 0i64 })
        if first_error != ok || !first_more { ret mem.Exhausted }
        let (second_more, second_error) = app.step(second, time.Duration { nanos: 0i64 })
        if second_error != ok || !second_more { ret mem.Exhausted }
        round += 1usize
    }
    ret ok
}

fn packed_point(x: u16, y: u16) -> isize { ret isize(usize(x) | (usize(y) << 16usize)) }

fn main(a: *mem.Arena, args: []str) -> err {
    var model = Model { builds: 0usize, taps: 0usize }
    let options = app.Options {
        window: window.Options { title: "neper ui_app", width: 200u32, height: 120u32, min_width: 0u32, min_height: 0u32, resizable: true, transparent: false, mode: .Windowed },
        widget_limits: widget.Limits { max_elements: 16usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 32usize },
        frame_arena_bytes: 1048576usize,
        event_capacity: 64usize,
        backend: .Cpu,
    }
    let app_mark = mem.mark(a)
    let (application, init_error) = app.init[Model](a, options, app.Builder[Model] { ctx: &model, build: build })
    if init_error == app.Failed {
        try io.print("ui app unsupported\n")
        ret ok
    }
    if init_error != ok { os.exit(1i32) }
    var running = application
    // The first step builds and presents; a quiet step presents nothing new.
    let (more, step_error) = app.step(&running, time.Duration { nanos: 0i64 })
    if step_error != ok || !more || model.builds != 1usize || app.frames_of(&running) != 1u64 { os.exit(2i32) }
    var rounds = 0usize
    while rounds < 10usize {
        let (again, again_error) = app.step(&running, time.millis(10i64))
        if again_error != ok || !again { os.exit(3i32) }
        rounds += 1usize
    }
    if model.builds < 3usize || app.frames_of(&running) < 3u64 { os.exit(4i32) }
    app.stop(&running)
    let (after_stop, stop_error) = app.step(&running, time.Duration { nanos: 0i64 })
    if stop_error != ok || after_stop { os.exit(5i32) }
    if app.close(&running) != ok || app.close(&running) != app.Closed { os.exit(6i32) }
    let (_, closed_error) = app.step(&running, time.Duration { nanos: 0i64 })
    if closed_error != app.Closed { os.exit(7i32) }
    // App close releases its routing owner before callers reclaim its arena.
    mem.reset(a, app_mark)

    // Two Apps use separate runtimes, but the host exposes one event stream. On
    // Windows, post B's pointer and close messages, step A first, then prove the
    // pointer tap and close are delivered only to B.  The two-event capacity also
    // forces a backlog: A must leave later B messages upstream until B drains.
    var first_model: Model = zero
    var second_model: Model = zero
    var routed_options = options
    routed_options.event_capacity = 2usize
    let (first_opened, first_open_error) = app.init[Model](a, routed_options, app.Builder[Model] { ctx: &first_model, build: build })
    if first_open_error != ok { os.exit(8i32) }
    var first_app = first_opened
    let (second_opened, second_open_error) = app.init[Model](a, routed_options, app.Builder[Model] { ctx: &second_model, build: build })
    if second_open_error != ok { os.exit(9i32) }
    var second_app = second_opened
    if settle(&first_app, &second_app) != ok { os.exit(10i32) }
    let (user32, user32_error) = os.dlopen(a, "user32.dll")
    if user32_error == ok {
        let (post, post_error) = os.dlsym[PostMessage](a, user32, "PostMessageW")
        if post_error != ok { os.exit(11i32) }
        let (second_host, host_error) = app.host_window(&second_app)
        if host_error != ok { os.exit(12i32) }
        let (native, _, native_error) = os.window_native(second_host)
        if native_error != ok { os.exit(13i32) }
        if post(native, 513u32, 1usize, packed_point(10u16, 10u16)) == 0i32 { os.exit(14i32) }
        if post(native, 514u32, 0usize, packed_point(10u16, 10u16)) == 0i32 { os.exit(15i32) }
        let (first_more, first_error) = app.step(&first_app, time.millis(20i64))
        if first_error != ok || !first_more || first_model.taps != 0usize { os.exit(16i32) }
        let (second_more, second_error) = app.step(&second_app, time.millis(20i64))
        if second_error != ok || !second_more || second_model.taps != 1usize || first_model.taps != 0usize { os.exit(17i32) }

        // B now receives six raw pointer records while its configured queue holds
        // only two.  Stepping A fills B's queue and pauses the broker; B then
        // drains all three taps in order without losing any to a global cap.
        var tap = 0usize
        while tap < 3usize {
            if post(native, 513u32, 1usize, packed_point(10u16, 10u16)) == 0i32 { os.exit(18i32) }
            if post(native, 514u32, 0usize, packed_point(10u16, 10u16)) == 0i32 { os.exit(19i32) }
            tap += 1usize
        }
        let (first_backlog, first_backlog_error) = app.step(&first_app, time.millis(20i64))
        if first_backlog_error != ok || !first_backlog || first_model.taps != 0usize || second_model.taps != 1usize { os.exit(20i32) }
        let (second_backlog, second_backlog_error) = app.step(&second_app, time.millis(20i64))
        if second_backlog_error != ok || !second_backlog || second_model.taps != 4usize || first_model.taps != 0usize { os.exit(21i32) }

        if post(native, 16u32, 0usize, 0isize) == 0i32 { os.exit(22i32) }
        let (still_running, first_close_error) = app.step(&first_app, time.millis(20i64))
        if first_close_error != ok || !still_running { os.exit(23i32) }
        let (second_running, second_close_error) = app.step(&second_app, time.millis(20i64))
        if second_close_error != ok || second_running { os.exit(24i32) }
        let _ = os.dlclose(user32)
    }
    if app.close(&first_app) != ok || app.close(&second_app) != ok { os.exit(25i32) }
    try io.print("ui app ok\n")
    ret ok
}
