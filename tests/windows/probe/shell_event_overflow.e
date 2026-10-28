// Full native event rings must disclose lost callbacks instead of silently
// pretending that every tray, hotkey and lifecycle event was delivered.
use e.mem
use e.os
use e.os.shell

fn main(a: *mem.Arena) -> err {
    if shell.ensure_window() != ok { os.exit(1i32) }

    var at = 0usize
    while at < 65usize {
        let handled = shell.shell_procedure(shell.shell_window, 32769u32, 9usize, 514isize)
        at += 1usize
    }
    at = 0usize
    while at < 64usize {
        let (event, has_event) = shell.tray_poll()
        if !has_event || event.kind != .Select { os.exit(2i32) }
        at += 1usize
    }
    let (tray_overflow, has_tray_overflow) = shell.tray_poll()
    if !has_tray_overflow || tray_overflow.kind != .Overflow { os.exit(3i32) }

    at = 0usize
    while at < 33usize {
        let (was_hotkey, answer) = shell.session_message(786u32, at + 1usize)
        if !was_hotkey { os.exit(4i32) }
        at += 1usize
    }
    at = 0usize
    while at < 32usize {
        let (id, has_id) = shell.hotkey_poll()
        if !has_id || id != u32(at + 1usize) { os.exit(5i32) }
        at += 1usize
    }
    let (hotkey_overflow, has_hotkey_overflow) = shell.hotkey_poll()
    if !has_hotkey_overflow || hotkey_overflow != 0u32 { os.exit(6i32) }

    at = 0usize
    while at < 9usize {
        shell.push_lifecycle(.Resume)
        at += 1usize
    }
    at = 0usize
    while at < 8usize {
        let (event, has_event) = shell.lifecycle_poll()
        if !has_event || event != .Resume { os.exit(7i32) }
        at += 1usize
    }
    let (lifecycle_overflow, has_lifecycle_overflow) = shell.lifecycle_poll()
    if !has_lifecycle_overflow || lifecycle_overflow != .Overflow { os.exit(8i32) }
    ret ok
}
