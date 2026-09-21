// `e.ui.app`'s notifications (D889, widget plan P4-03): the permission is asked
// first, a notice with no body is refused, and where the host has notices one is
// published, updated in place and -- where the host can -- removed; buttons are
// what no host offers here, and the record says so.

use e.io
use e.mem
use e.os
use e.os.shell
use e.ui.app

fn main(a: *mem.Arena, args: []str) -> err {
    if app.notification_actions_supported() { os.exit(1i32) }
    var tray: app.Tray = zero
    var pixels: [256]u32 = zero
    var i = 0usize
    while i < 256usize {
        pixels[i] = 4281624268u32
        i += 1usize
    }
    if app.tray_supported() {
        let (opened, open_error) = app.tray_open(a, 5u32, shell.Icon { width: 16u32, height: 16u32, pixels: pixels[..] }, "neper")
        if open_error != ok { os.exit(2i32) }
        tray = opened
    }
    let permission = app.notification_permission(a)
    let empty = app.Notification { title: "neper", body: "", silent: true }
    let (no_id, empty_error) = app.notify(a, &tray, empty)
    if empty_error != shell.Invalid { os.exit(3i32) }
    let first = app.Notification { title: "neper", body: "The fixture published this notice.", silent: true }
    let (id, publish_error) = app.notify(a, &tray, first)
    if permission == .Granted && app.notification_supported() {
        if publish_error != ok { os.exit(4i32) }
        if app.tray_supported() && id != 5u32 { os.exit(5i32) }
        if !app.tray_supported() && id == 0u32 { os.exit(6i32) }
        let second = app.Notification { title: "neper", body: "The fixture updated this notice.", silent: true }
        if app.notification_update(a, &tray, id, second) != ok { os.exit(7i32) }
        let removed = app.notification_remove(a, &tray, id)
        if app.shell_capabilities().notice_remove {
            if removed != ok { os.exit(8i32) }
        } else {
            if removed != shell.Unsupported { os.exit(9i32) }
        }
    } else {
        if publish_error == ok { os.exit(10i32) }
    }
    if app.tray_supported() {
        let (activation, any, poll_error) = app.tray_poll(a, &tray)
        if poll_error != ok { os.exit(11i32) }
        if app.tray_close(a, &tray) != ok { os.exit(12i32) }
        let (late_id, late_error) = app.notify(a, &tray, first)
        if late_error != shell.NotFound { os.exit(13i32) }
    }
    try io.print("ui notification ok\n")
    ret ok
}
