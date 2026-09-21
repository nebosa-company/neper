// `e.ui.app`'s taskbar and jump list controllers (D887, widget plan P4-02): on a
// host with a taskbar the app's window shows a determinate, an indeterminate and
// no progress, wears and drops an overlay, refuses a progress past its total, and
// publishes then removes a jump list of two tasks; on a host without one every
// call is `shell.Unsupported` and the capability record says so first.

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
    var pixels: [256]u32 = zero
    var i = 0usize
    while i < 256usize {
        pixels[i] = 4293281869u32
        i += 1usize
    }
    let icon = shell.Icon { width: 16u32, height: 16u32, pixels: pixels[..] }
    let none = shell.Icon { width: 0u32, height: 0u32, pixels: pixels[..] }
    let (exe, exe_error) = fs.executable_path(a)
    if exe_error != ok { os.exit(1i32) }
    var tasks: [2]shell.JumpTask = zero
    tasks[0usize] = shell.JumpTask { title: "Open a fresh window", program: exe, arguments: "--fresh", description: "A second window of the fixture" }
    tasks[1usize] = shell.JumpTask { title: "Show the log", program: exe, arguments: "--log", description: "" }
    var nameless: [1]shell.JumpTask = zero
    nameless[0usize] = shell.JumpTask { title: "", program: exe, arguments: "", description: "" }
    if !app.taskbar_supported() || !app.jump_list_supported() {
        if app.taskbar_supported() != app.jump_list_supported() { os.exit(2i32) }
        var nowhere: os.Window = zero
        if shell.taskbar_progress(a, nowhere, .Normal, 1u64, 2u64) != shell.Unsupported || shell.taskbar_overlay(a, nowhere, icon, "one") != shell.Unsupported { os.exit(3i32) }
        if app.jump_list(a, tasks[..]) != shell.Unsupported || app.jump_list_clear(a) != shell.Unsupported { os.exit(4i32) }
        try io.print("ui taskbar ok\n")
        ret ok
    }
    var model = Model { builds: 0usize }
    let options = app.Options {
        window: window.Options { title: "neper ui_taskbar", width: 200u32, height: 120u32, min_width: 0u32, min_height: 0u32, resizable: true, transparent: false, mode: .Windowed },
        widget_limits: widget.Limits { max_elements: 16usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 32usize },
        frame_arena_bytes: 1048576usize,
        event_capacity: 64usize,
        backend: .Cpu,
    }
    let (application, init_error) = app.init[Model](a, options, app.Builder[Model] { ctx: &model, build: build })
    if init_error != ok { os.exit(5i32) }
    var running = application
    let (more, step_error) = app.step(&running, time.Duration { nanos: 0i64 })
    if step_error != ok || !more { os.exit(6i32) }
    if app.taskbar_progress(a, &running, .Normal, 1u64, 2u64) != ok { os.exit(7i32) }
    if app.taskbar_progress(a, &running, .Indeterminate, 0u64, 0u64) != ok { os.exit(8i32) }
    if app.taskbar_progress(a, &running, .Normal, 3u64, 2u64) != shell.Invalid || app.taskbar_progress(a, &running, .Paused, 1u64, 0u64) != shell.Invalid { os.exit(9i32) }
    if app.taskbar_progress(a, &running, .None, 0u64, 0u64) != ok { os.exit(10i32) }
    if app.taskbar_overlay(a, &running, icon, "one unread") != ok { os.exit(11i32) }
    if app.taskbar_overlay(a, &running, none, "") != ok { os.exit(12i32) }
    if app.jump_list(a, nameless[..]) != shell.Invalid { os.exit(13i32) }
    if app.jump_list(a, tasks[..]) != ok { os.exit(14i32) }
    if app.jump_list_clear(a) != ok { os.exit(15i32) }
    // A window that is closed has no taskbar button to speak of.
    if app.close(&running) != ok { os.exit(16i32) }
    if app.taskbar_progress(a, &running, .None, 0u64, 0u64) != app.Closed { os.exit(17i32) }
    try io.print("ui taskbar ok\n")
    ret ok
}
