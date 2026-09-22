// `e.ui.app`'s cross-application drag and drop (D892, widget plan P4-05): where the
// host has OLE the app's window becomes a drop target once and not twice, takes
// nothing while nothing was dropped, and stops being one; a drag of an empty offer
// is refused before the shell is asked, and a promised file is one representation.
// Where the host has neither, every call is `shell.Unsupported` and the predicates
// say so first. A real drag needs a pointer, so none is started here.

use e.fs
use e.gpu
use e.io
use e.mem
use e.os
use e.os.shell
use e.time
use e.ui.app
use e.ui.style
use e.ui.widget
use e.ui.window

type Model = struct { builds: usize }

fn build(model: *Model, ctx: *widget.BuildContext) -> (widget.Node, err) {
    model.builds += 1usize
    var s = style.defaults()
    s.width = style.Length { Px: 200.0 }
    s.height = style.Length { Px: 120.0 }
    ret (widget.box(1u64, s, zero), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let promise = app.promised_file("notes.txt", "promised")
    if promise.kind != .Promise || promise.text.len != 9usize || promise.bytes.len != 8usize { os.exit(1i32) }
    var nothing: [1]shell.Content = zero
    let empty = app.DataOffer { types: zero, provider: zero }
    let (no_result, empty_error) = app.drag_offer(a, empty, app.DragOperation { allow_move: false })
    if empty_error != shell.Invalid { os.exit(2i32) }
    if app.drag_source_supported() != app.drop_target_supported() { os.exit(3i32) }
    if !app.drop_target_supported() {
        var no_window: os.Window = zero
        if shell.drop_target_register(a, no_window, a) != shell.Unsupported { os.exit(4i32) }
        var one: [1]shell.Content = zero
        one[0usize] = promise
        let (held, held_error) = app.offer_of(a, one[..])
        if held_error != ok { os.exit(5i32) }
        let (no_drag, drag_error) = app.drag_offer(a, held, app.DragOperation { allow_move: true })
        if drag_error != shell.Unsupported { os.exit(6i32) }
        try io.print("ui drag drop ok\n")
        ret ok
    }
    var model = Model { builds: 0usize }
    let options = app.Options {
        window: window.Options { title: "neper ui_drag_drop", width: 200u32, height: 120u32, min_width: 0u32, min_height: 0u32, resizable: true, transparent: false, mode: .Windowed },
        widget_limits: widget.Limits { max_elements: 16usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 32usize },
        frame_arena_bytes: 1048576usize,
        event_capacity: 64usize,
        backend: .Cpu,
    }
    let (application, init_error) = app.init[Model](a, options, app.Builder[Model] { ctx: &model, build: build })
    if init_error != ok { os.exit(7i32) }
    var running = application
    let (more, step_error) = app.step(&running, time.Duration { nanos: 0i64 })
    if step_error != ok || !more { os.exit(8i32) }
    let (storage_bytes, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(9i32) }
    var storage = mem.arena_from(storage_bytes)
    if app.drop_target_open(a, &running, &storage) != ok { os.exit(10i32) }
    if app.drop_target_open(a, &running, &storage) != shell.Invalid { os.exit(11i32) }
    let (landed, any) = app.drop_take()
    if any { os.exit(12i32) }
    if app.drop_target_close(a, &running) != ok { os.exit(13i32) }
    if app.drop_target_close(a, &running) != shell.NotFound { os.exit(14i32) }
    if app.close(&running) != ok { os.exit(15i32) }
    if app.drop_target_open(a, &running, &storage) != app.Closed { os.exit(16i32) }
    try io.print("ui drag drop ok\n")
    ret ok
}
