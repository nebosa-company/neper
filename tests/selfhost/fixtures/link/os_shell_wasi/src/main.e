// #627: shell.wasi validates arguments before answering Unsupported. Run on wasm32-wasi;
// on a host the checks are skipped so the suite can still build it natively.

use e.io
use e.mem
use e.os
use e.os.ident
use e.os.shell as shell
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let (host, _) = ident.hostname(a)
    if str.eq(host, "wasi") {
        var no_pixels: [0]u32 = zero
        var one_pixel: [1]u32 = zero
        one_pixel[0usize] = 4294967295u32
        let bad_icon = shell.Icon { width: 0u32, height: 0u32, pixels: no_pixels[0..] }
        let good_icon = shell.Icon { width: 1u32, height: 1u32, pixels: one_pixel[0..] }
        // 1: a zero-sized icon is Invalid, a well-formed one is Unsupported.
        if shell.tray_add(a, 1u32, bad_icon, "") != shell.Invalid { os.exit(1i32) }
        if shell.tray_update(a, 1u32, bad_icon, "") != shell.Invalid { os.exit(2i32) }
        if shell.tray_add(a, 1u32, good_icon, "") != shell.Unsupported { os.exit(3i32) }
        if shell.taskbar_overlay(a, os.Window { raw: 1usize }, bad_icon, "") != shell.Invalid { os.exit(4i32) }
        // 2: a non-separator menu item with id 0 is Invalid; a separator may use id 0.
        var items: [2]shell.MenuItem = zero
        items[0usize] = shell.MenuItem { id: 0u32, label: "a", enabled: true, checked: false, separator: false }
        let (_, _, menu_error) = shell.popup_menu(a, items[0usize..1usize], 0i32, 0i32)
        if menu_error != shell.Invalid { os.exit(5i32) }
        items[0usize].separator = true
        let (_, _, separator_error) = shell.popup_menu(a, items[0usize..1usize], 0i32, 0i32)
        if separator_error != shell.Unsupported { os.exit(6i32) }
        // 3: determinate progress needs total > 0 and completed <= total.
        if shell.taskbar_progress(a, os.Window { raw: 1usize }, .Normal, 0u64, 0u64) != shell.Invalid { os.exit(7i32) }
        if shell.taskbar_progress(a, os.Window { raw: 1usize }, .Indeterminate, 0u64, 0u64) != shell.Unsupported { os.exit(8i32) }
        // 4: jump-list tasks need a title and a program.
        var task: [1]shell.JumpTask = zero
        task[0usize].title = ""
        task[0usize].program = "app"
        if shell.jump_list(a, task[0..]) != shell.Invalid { os.exit(9i32) }
        // 5: a notice removal names both ids, and zero ids are Invalid.
        if shell.notice_remove(a, 1u32, 0u32) != shell.Invalid { os.exit(10i32) }
        if shell.notice_remove(a, 0u32, 1u32) != shell.Invalid { os.exit(11i32) }
        if shell.notice_remove(a, 1u32, 1u32) != shell.Unsupported { os.exit(12i32) }
    }
    try io.print("os shell wasi ok\n")
    ret ok
}

