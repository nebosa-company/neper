// Newest frame only (C212): presents 200 solid frames back to back, frame k with red = k and green = 255 - k, the last
// one pure blue, then waits for a click or key. The page's counters (window.neperDebug.stats) say how many were drawn.
//
//   neper emit-executable tests/wasm/browser/ui_burst/src/main.e . wasm32 wasi ui_burst.wasm

use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let options = os.WindowOptions { title: "ui_burst", width: 320u32, height: 200u32, resizable: true, visible: true, mode: .Windowed }
    let (w, open_error) = os.window_open(a, options)
    if open_error != ok { os.exit(1i32) }
    var pixels: [64000]u32 = zero
    try io.print("ready\n")
    var k = 0u32
    while k < 200u32 {
        var colour = 0xff000000u32 | (k << 16u32) | ((255u32 - k) << 8u32)
        if k == 199u32 { colour = 0xff0000ffu32 }
        var i = 0usize
        while i < 64000usize {
            pixels[i] = colour
            i += 1usize
        }
        if os.window_present(w, pixels[0..], 320u32, 200u32) != ok { os.exit(2i32) }
        k += 1u32
    }
    try io.print("burst done\n")
    while true {
        let (event, any, poll_error) = os.window_poll(50000000i64)
        if poll_error != ok { os.exit(3i32) }
        if any && (event.kind == .PointerDown || event.kind == .KeyDown) { break }
    }
    ret ok
}
