// The close button is a request: `performClose:` (what the button sends) answers the program with a Close event and leaves the window
// where it is, and only `window_close` takes it away. macOS only; the corpus runs it on a Mac.
use e.mem
use e.os

fn next(code: i32) -> os.WindowEvent {
    var tries = 0usize
    while tries < 40usize {
        let (event, got, poll_error) = os.window_poll(50000000i64)
        if poll_error != ok { os.exit(code) }
        if got { ret event }
        tries += 1usize
    }
    os.exit(code)
    var none: os.WindowEvent = zero
    ret none
}

fn main(a: *mem.Arena) -> err {
    var options: os.WindowOptions = zero
    options.title = "Neper: close request"
    options.width = 320u32
    options.height = 200u32
    options.visible = true
    let (window, open_error) = os.window_open(a, options)
    if open_error != ok { os.exit(2i32) }
    let (handle, view, native_error) = os.window_native(window)
    if native_error != ok { os.exit(3i32) }
    // What opening says first, then quiet.
    var seen_paint = false
    var polls = 0usize
    while polls < 6usize && !seen_paint {
        let first = next(10i32)
        if first.kind == .Paint { seen_paint = true }
        polls += 1usize
    }
    let asked = os.msg1(handle, os.cocoa_sel("performClose:\x00"), 0usize)
    var closing = false
    polls = 0usize
    while polls < 8usize && !closing {
        let event = next(20i32)
        if event.kind == .Close { closing = true }
        polls += 1usize
    }
    if !closing { os.exit(21i32) }
    let (metrics, metrics_error) = os.window_metrics(window)
    if metrics_error != ok { os.exit(22i32) }
    if !metrics.visible { os.exit(23i32) }
    if os.window_close(window) != ok { os.exit(24i32) }
    let (gone, gone_error) = os.window_metrics(window)
    if gone_error == ok { os.exit(25i32) }
    ret ok
}
