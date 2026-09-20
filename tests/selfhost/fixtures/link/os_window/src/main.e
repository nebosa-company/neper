// The native window primitives of `e.os` (D795): a window opens hidden at the client
// size asked for, reports its metrics, takes a title, a cursor and a present, shows
// and hides, delivers its events through `window_poll`, and is stale once closed; the
// primary monitor and the clipboard's text answer. A host without them answers
// `Unsupported` at `window_open`, and the fixture says so.

use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let options = os.WindowOptions { title: "neper os_window", width: 320u32, height: 200u32, resizable: true, visible: false }
    let (w, open_error) = os.window_open(a, options)
    if open_error == os.Unsupported {
        try io.print("os window unsupported\n")
        ret ok
    }
    if open_error != ok { os.exit(1i32) }
    let (metrics, metrics_error) = os.window_metrics(w)
    if metrics_error != ok || metrics.width != 320u32 || metrics.height != 200u32 || metrics.visible || metrics.scale_percent < 100u32 { os.exit(2i32) }
    if os.window_title(w, "neper os_window: titled") != ok { os.exit(3i32) }
    if os.window_cursor(w, .Hand) != ok { os.exit(4i32) }
    // A frame of solid colour, presented to the hidden window.
    var pixels: [64000]u32 = zero
    var i = 0usize
    while i < 64000usize {
        pixels[i] = 4278255360u32
        i += 1usize
    }
    if os.window_present(w, pixels[0..], 320u32, 200u32) != ok { os.exit(5i32) }
    let (handle, context, native_error) = os.window_native(w)
    if native_error != ok || handle != w.raw || context == 0usize { os.exit(6i32) }
    // Shown: a resize or a paint or a focus arrives within a second.
    if os.window_visible(w, true) != ok { os.exit(7i32) }
    var seen = 0usize
    var rounds = 0usize
    while rounds < 50usize {
        let (event, any, poll_error) = os.window_poll(20000000i64)
        if poll_error != ok { os.exit(8i32) }
        if any {
            if event.window.raw != w.raw { os.exit(9i32) }
            if event.kind == .Paint || event.kind == .Resize || event.kind == .Focus { seen += 1usize }
        }
        rounds += 1usize
    }
    if seen == 0usize { os.exit(10i32) }
    let (shown, shown_error) = os.window_metrics(w)
    if shown_error != ok || !shown.visible { os.exit(11i32) }
    if os.window_visible(w, false) != ok { os.exit(12i32) }
    if os.window_capture(w, true) != ok || os.window_capture(w, false) != ok { os.exit(13i32) }
    // The primary monitor, and the clipboard's text, whatever it holds.
    let (screens, monitors_error) = os.monitors(a, 4usize)
    if monitors_error != ok || screens.len == 0usize || !screens[0].primary || screens[0].width == 0u32 || screens[0].scale_percent < 100u32 { os.exit(14i32) }
    let (_, limit_error) = os.monitors(a, 0usize)
    if limit_error != os.Unsupported { os.exit(15i32) }
    // The clipboard is the desktop's: a session without an interactive station --
    // a service, a sandboxed runner -- refuses `OpenClipboard` with `Denied`, and
    // that is the answer here, not a wrong one.
    let (_, clipboard_error) = os.clipboard_text(a)
    if clipboard_error != ok && clipboard_error != os.Denied { os.exit(16i32) }
    // Closed: stale afterwards, and its events gone.
    if os.window_close(w) != ok { os.exit(17i32) }
    if os.window_close(w) != os.NotFound { os.exit(18i32) }
    let (_, stale_error) = os.window_metrics(w)
    if stale_error != os.NotFound { os.exit(19i32) }
    if os.window_present(w, pixels[0..], 320u32, 200u32) != os.NotFound { os.exit(20i32) }
    let (_, none_error) = os.window_open(a, os.WindowOptions { title: "", width: 0u32, height: 10u32, resizable: false, visible: false })
    if none_error != os.Unsupported { os.exit(21i32) }
    try io.print("os window ok\n")
    ret ok
}
