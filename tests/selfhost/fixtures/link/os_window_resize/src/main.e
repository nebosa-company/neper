// `window_on_resize` on Windows (D5856): the handler is called from the window procedure, which is where the system's sizing loop
// delivers WM_SIZE while an edge is dragged. Resizing from code (SetWindowPos) takes the same path, so the handler runs at once with
// the new client size in physical pixels, agreeing with `window_metrics`; a window with no handler is silent.
use e.mem
use e.os

var calls: u32 = zero
var last_width: u32 = zero
var last_height: u32 = zero

@import("user32.dll", "SetWindowPos")
extern fn set_window_pos(window: usize, after: usize, x: i32, y: i32, width: i32, height: i32, flags: u32) -> i32

fn on_resize(w: os.Window, width: u32, height: u32) {
    calls += 1u32
    last_width = width
    last_height = height
}

fn main(a: *mem.Arena) -> err {
    var options: os.WindowOptions = zero
    options.title = "Neper: live resize"
    options.width = 320u32
    options.height = 200u32
    options.visible = true
    let (window, open_error) = os.window_open(a, options)
    if open_error != ok { os.exit(2i32) }
    if os.window_on_resize(window, on_resize) != ok { os.exit(3i32) }
    let before = calls
    // SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE: the outer size, so the client area changes by about the same.
    if set_window_pos(window.raw, 0usize, 0i32, 0i32, 640i32, 480i32, 22u32) == 0i32 { os.exit(4i32) }
    if calls <= before { os.exit(5i32) }
    let (metrics, metrics_error) = os.window_metrics(window)
    if metrics_error != ok { os.exit(6i32) }
    if last_width != metrics.width || last_height != metrics.height { os.exit(7i32) }
    if last_width <= 320u32 { os.exit(8i32) }
    let again = calls
    if set_window_pos(window.raw, 0usize, 0i32, 0i32, 500i32, 400i32, 22u32) == 0i32 { os.exit(9i32) }
    if calls <= again { os.exit(10i32) }
    if last_width >= metrics.width { os.exit(11i32) }
    var plain_options: os.WindowOptions = zero
    plain_options.title = "Neper: no handler"
    plain_options.width = 200u32
    plain_options.height = 120u32
    plain_options.visible = true
    let (plain, plain_error) = os.window_open(a, plain_options)
    if plain_error != ok { os.exit(12i32) }
    let fixed = calls
    if set_window_pos(plain.raw, 0usize, 0i32, 0i32, 300i32, 240i32, 22u32) == 0i32 { os.exit(13i32) }
    if calls != fixed { os.exit(14i32) }
    if os.window_close(plain) != ok { os.exit(15i32) }
    if os.window_close(window) != ok { os.exit(16i32) }
    ret ok
}
