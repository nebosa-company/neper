// `e.ui.app`'s global input and lifecycle (D899, widget plan P4-10): where the
// host has them a global shortcut is registered and removed, a power inhibitor
// is acquired and released once, a restart is registered and withdrawn, and the
// lifecycle and shortcut queues are empty while nothing happened; the background
// permission is answered; a host without a service says so through the predicates.

use e.io
use e.mem
use e.os
use e.os.shell
use e.ui.app

fn main(a: *mem.Arena, args: []str) -> err {
    if app.background_permission(a) == .Denied { os.exit(1i32) }
    let (no_press, pressed) = app.global_shortcut_poll()
    if pressed { os.exit(2i32) }
    let (no_event, happened) = app.lifecycle_poll()
    if happened { os.exit(3i32) }
    var session = app.global_shortcut_session()
    let combination = shell.Hotkey { control: true, alt: true, shift: true, super: false, key: 123u32 }
    if app.global_shortcut_add(a, &session, 0u32, combination) != shell.Invalid { os.exit(4i32) }
    if app.global_shortcuts_supported() {
        // Ctrl+Alt+Shift+F12, then gone again; a second removal finds nothing.
        if app.global_shortcut_add(a, &session, 7u32, combination) != ok || session.registered != 1u32 { os.exit(5i32) }
        if app.global_shortcut_remove(a, &session, 7u32) != ok || session.registered != 0u32 { os.exit(6i32) }
        if app.global_shortcut_remove(a, &session, 7u32) != shell.NotFound { os.exit(7i32) }
    } else {
        if app.global_shortcut_add(a, &session, 7u32, combination) != shell.Unsupported { os.exit(8i32) }
    }
    var released: app.PowerInhibitor = zero
    if app.power_inhibitor_release(a, &released) != shell.NotFound { os.exit(9i32) }
    let (inhibitor, inhibit_error) = app.power_inhibitor_acquire(a, false)
    if app.power_inhibit_supported() {
        // A host that has the service but no session behind it may still refuse.
        if inhibit_error == ok {
            var holding = inhibitor
            if !holding.held || app.power_inhibitor_release(a, &holding) != ok || holding.held { os.exit(10i32) }
            if app.power_inhibitor_release(a, &holding) != shell.NotFound { os.exit(11i32) }
        } else {
            if inhibit_error != shell.Failed { os.exit(12i32) }
        }
    } else {
        if inhibit_error != shell.Unsupported { os.exit(13i32) }
    }
    var long: [1025]u8 = zero
    if app.session_restore_register(a, long[..]) != shell.Invalid { os.exit(14i32) }
    if app.session_restore_supported() {
        if app.session_restore_register(a, "--restored") != ok { os.exit(15i32) }
        if app.session_restore_unregister(a) != ok { os.exit(16i32) }
    } else {
        if app.session_restore_register(a, "--restored") != shell.Unsupported { os.exit(17i32) }
    }
    try io.print("ui lifecycle ok\n")
    ret ok
}
