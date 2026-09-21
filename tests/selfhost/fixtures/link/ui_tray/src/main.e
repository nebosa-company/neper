// `e.ui.app`'s tray controller (D886, widget plan P4-01): where the host has a tray
// one opens, wears a badge composed into its pixels, takes a menu, polls nothing
// while nothing was clicked, and closes once; where it has none, every call is
// `shell.Unsupported`.

use e.io
use e.mem
use e.os
use e.os.shell
use e.ui.app

const BLUE: u32 = 4281624268u32
const BADGE: u32 = 4293281869u32

fn main(a: *mem.Arena, args: []str) -> err {
    var pixels: [256]u32 = zero
    var i = 0usize
    while i < 256usize {
        pixels[i] = BLUE
        i += 1usize
    }
    let icon = shell.Icon { width: 16u32, height: 16u32, pixels: pixels[..] }
    if !app.tray_supported() {
        let (missing, open_error) = app.tray_open(a, 3u32, icon, "neper")
        if open_error != shell.Unsupported { os.exit(1i32) }
        try io.print("ui tray ok\n")
        ret ok
    }
    let (opened, open_error) = app.tray_open(a, 3u32, icon, "neper")
    if open_error != ok { os.exit(2i32) }
    var tray = opened
    let (bad, bad_error) = app.tray_open(a, 4u32, shell.Icon { width: 0u32, height: 0u32, pixels: pixels[..] }, "empty")
    if bad_error != shell.Invalid { os.exit(3i32) }
    // A badge of five: the top right wears the disc, the bottom left does not.
    if app.tray_set_badge(a, &tray, 5u32) != ok || tray.composed[4usize * 16usize + 15usize] != BADGE || tray.composed[15usize * 16usize] != BLUE { os.exit(4i32) }
    if app.tray_set_badge(a, &tray, 0u32) != ok || tray.composed[4usize * 16usize + 15usize] != BLUE { os.exit(5i32) }
    var small: [64]u32 = zero
    if app.tray_set_icon(a, &tray, shell.Icon { width: 8u32, height: 8u32, pixels: small[..] }) != shell.Invalid { os.exit(6i32) }
    if app.tray_set_tooltip(a, &tray, "neper, badged") != ok { os.exit(7i32) }
    var items: [2]shell.MenuItem = zero
    items[0usize] = shell.MenuItem { id: 1u32, label: "Show", enabled: true, checked: false, separator: false }
    items[1usize] = shell.MenuItem { id: 2u32, label: "Quit", enabled: true, checked: false, separator: false }
    app.tray_set_menu(&tray, items[..])
    let (activation, any, poll_error) = app.tray_poll(a, &tray)
    if poll_error != ok || any { os.exit(8i32) }
    if app.tray_close(a, &tray) != ok { os.exit(9i32) }
    if app.tray_close(a, &tray) != shell.NotFound { os.exit(10i32) }
    let (late, late_any, late_error) = app.tray_poll(a, &tray)
    if late_error != shell.NotFound { os.exit(11i32) }
    try io.print("ui tray ok\n")
    ret ok
}
