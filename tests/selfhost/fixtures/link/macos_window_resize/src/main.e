// `window_on_resize` (D5856): AppKit calls the window delegate's `windowDidResize:` from inside its own resize loop, where the poll
// model gets no turn while an edge is dragged. Resizing the window from code takes the same path, so the handler is called at once with
// the new client size in physical pixels, which `window_metrics` then agrees with; a window with no handler is untouched. macOS only.
use e.mem
use e.os

var calls: u32 = zero
var last_width: u32 = zero
var last_height: u32 = zero

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
    let (handle, view, native_error) = os.window_native(window)
    if native_error != ok { os.exit(3i32) }
    if os.window_on_resize(window, on_resize) != ok { os.exit(4i32) }
    let before = calls
    let sized = os.msg_size(handle, os.cocoa_sel("setContentSize:\x00"), os.CgSize { w: 480.0f64, h: 300.0f64 })
    if calls <= before { os.exit(5i32) }
    let (metrics, metrics_error) = os.window_metrics(window)
    if metrics_error != ok { os.exit(6i32) }
    if last_width != metrics.width || last_height != metrics.height { os.exit(7i32) }
    if last_width <= 320u32 { os.exit(8i32) }
    // A second size, the other way: the handler hears every one.
    let again = calls
    let smaller = os.msg_size(handle, os.cocoa_sel("setContentSize:\x00"), os.CgSize { w: 360.0f64, h: 240.0f64 })
    if calls <= again { os.exit(9i32) }
    if last_width >= metrics.width { os.exit(10i32) }
    // A window that was never given a handler: no call, no trouble.
    var plain_options: os.WindowOptions = zero
    plain_options.title = "Neper: no handler"
    plain_options.width = 200u32
    plain_options.height = 120u32
    plain_options.visible = true
    let (plain, plain_error) = os.window_open(a, plain_options)
    if plain_error != ok { os.exit(11i32) }
    let (plain_handle, plain_view, plain_native_error) = os.window_native(plain)
    if plain_native_error != ok { os.exit(12i32) }
    let fixed = calls
    let moved = os.msg_size(plain_handle, os.cocoa_sel("setContentSize:\x00"), os.CgSize { w: 260.0f64, h: 160.0f64 })
    if calls != fixed { os.exit(13i32) }
    if os.window_close(plain) != ok { os.exit(14i32) }
    if os.window_close(window) != ok { os.exit(15i32) }
    ret ok
}
