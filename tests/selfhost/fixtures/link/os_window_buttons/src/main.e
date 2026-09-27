// The X button codes `e.os` turns into pointer events on Linux: 1, 2, 3 primary,
// middle, secondary; 8, 9 back, forward; 4, 5 a wheel notch up and down, a
// synthetic one (XSendEvent's high bit) as well. 6 and 7, the wheel's horizontal
// steps, and 10 on are nothing: they were each a primary press and release, so a
// sideways trackpad nudge clicked whatever was under the pointer. Raw ButtonPress
// and ButtonRelease units go straight to the event translation for a hidden
// window; a host without windows answers `Unsupported`, and the fixture says so.

use e.io
use e.mem
use e.os

fn put16(unit: []u8, at: usize, v: u32) {
    unit[at] = u8(v & 255u32)
    unit[at + 1usize] = u8((v >> 8u32) & 255u32)
}

// A press (kind 4) or release (kind 5) of `detail` at (40, 30) in `w`.
fn feed(w: os.Window, kind: u8, detail: u8) {
    var unit: [32]u8 = zero
    unit[0usize] = kind
    unit[1usize] = detail
    let id = u32(w.raw)
    put16(unit[..], 12usize, id & 65535u32)
    put16(unit[..], 14usize, id >> 16u32)
    put16(unit[..], 24usize, 40u32)
    put16(unit[..], 26usize, 30u32)
    os.x_event(unit[..])
}

// The next pointer or scroll event, skipping the window's own paint, focus and
// resize; `false` when none is queued.
fn next_pointer() -> (os.WindowEvent, bool) {
    while true {
        let (event, any, poll_error) = os.window_poll(0i64)
        if poll_error != ok || !any { ret (event, false) }
        if event.kind == .PointerDown || event.kind == .PointerUp || event.kind == .PointerMove || event.kind == .Scroll { ret (event, true) }
    }
    var none: os.WindowEvent = zero
    ret (none, false)
}

// A click of `detail` is a press then a release of `button` at (40, 30).
fn clicked(w: os.Window, detail: u8, button: u8) -> bool {
    feed(w, 4u8, detail)
    feed(w, 5u8, detail)
    let (down, has_down) = next_pointer()
    let (up, has_up) = next_pointer()
    ret has_down && has_up && down.kind == .PointerDown && up.kind == .PointerUp && down.button == button && up.button == button && down.x == 40i32 && down.y == 30i32
}

// A notch of `detail` (with `kind` carrying the synthetic bit or not) is one
// Scroll of `delta`, its release nothing.
fn scrolled(w: os.Window, kind: u8, detail: u8, delta: i32) -> bool {
    feed(w, kind, detail)
    feed(w, kind + 1u8, detail)
    let (notch, has_notch) = next_pointer()
    let (_, more) = next_pointer()
    ret has_notch && !more && notch.kind == .Scroll && notch.delta == delta && notch.x == 40i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (w, open_error) = os.window_open(a, os.WindowOptions { title: "neper os_window_buttons", width: 160u32, height: 120u32, resizable: false, visible: false, mode: .Windowed })
    if open_error == os.Unsupported {
        try io.print("os window unsupported\n")
        ret ok
    }
    if open_error != ok { os.exit(1i32) }
    // Whatever the host queued at open is drained first.
    let (_, early) = next_pointer()
    if early { os.exit(2i32) }
    if !clicked(w, 1u8, 0u8) { os.exit(3i32) }
    if !clicked(w, 3u8, 1u8) { os.exit(4i32) }
    if !clicked(w, 2u8, 2u8) { os.exit(5i32) }
    if !clicked(w, 8u8, 3u8) { os.exit(6i32) }
    if !clicked(w, 9u8, 4u8) { os.exit(7i32) }
    if !scrolled(w, 4u8, 4u8, 120i32) { os.exit(8i32) }
    if !scrolled(w, 4u8, 5u8, -120i32) { os.exit(9i32) }
    if !scrolled(w, 132u8, 5u8, -120i32) { os.exit(10i32) }
    // Horizontal steps and unnamed buttons: no event at all.
    var detail = 6u8
    while detail <= 12u8 {
        if detail == 8u8 { detail = 10u8 }
        feed(w, 4u8, detail)
        feed(w, 5u8, detail)
        let (_, stray) = next_pointer()
        if stray { os.exit(11i32) }
        detail += 1u8
    }
    if os.window_close(w) != ok { os.exit(12i32) }
    try io.print("os window buttons ok\n")
    ret ok
}
