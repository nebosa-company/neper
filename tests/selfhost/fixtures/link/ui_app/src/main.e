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

type Model = struct { builds: usize }

fn build(model: *Model, ctx: *widget.BuildContext) -> (widget.Node, err) {
    model.builds += 1usize
    if model.builds < 3usize { widget.request_animation_frame(ctx.runtime) }
    var s = style.defaults()
    s.width = style.Length { Px: 200.0 }
    s.height = style.Length { Px: 120.0 }
    s.background = paint.Brush { Solid: paint.rgba(0.2, 0.4, 0.8, 1.0) }
    ret (widget.box(1u64, s, zero), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var model = Model { builds: 0usize }
    let options = app.Options {
        window: window.Options { title: "neper ui_app", width: 200u32, height: 120u32, min_width: 0u32, min_height: 0u32, resizable: true, transparent: false, mode: .Windowed },
        widget_limits: widget.Limits { max_elements: 16usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 32usize },
        frame_arena_bytes: 1048576usize,
        event_capacity: 64usize,
        backend: .Cpu,
    }
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
    try io.print("ui app ok\n")
    ret ok
}
