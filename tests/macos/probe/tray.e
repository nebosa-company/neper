// A status item with a 22x22 red-and-white icon in the menu bar for the screenshot, and a popup menu whose tracking the
// run loop cancels after six seconds, then the item is removed. macos-probe screenshots after `shot_after` seconds.
use e.mem
use e.os
use e.os.shell


fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena) -> err {
    var pixels: [484]u32 = zero
    var i = 0usize
    while i < 484usize {
        pixels[i] = 4294901760u32
        if (i / 22usize + i % 22usize) % 4usize == 0usize { pixels[i] = 4294967295u32 }
        i += 1usize
    }
    let icon = shell.Icon { width: 22u32, height: 22u32, pixels: pixels[..] }
    if shell.tray_add(a, 7u32, icon, "Neper tray") != ok { os.exit(2i32) }
    say("tray added\n")
    var started = 0usize
    while started < 50usize {
        let (event, has_event) = shell.tray_poll()
        started += 1usize
    }
    var items: [3]shell.MenuItem = zero
    items[0usize] = shell.MenuItem { id: 1u32, label: "First", enabled: true, checked: true, separator: false }
    items[1usize] = shell.MenuItem { id: 0u32, label: "", enabled: true, checked: false, separator: true }
    items[2usize] = shell.MenuItem { id: 2u32, label: "Second", enabled: true, checked: false, separator: false }
    if shell.popup_cancel_after(6.0f64) != ok { os.exit(5i32) }
    let (chosen, has_chosen, menu_error) = shell.popup_menu(a, items[..], 400i32, 300i32)
    if menu_error != ok { os.exit(3i32) }
    if has_chosen { say("chosen\n") } else { say("menu dismissed\n") }
    if shell.tray_remove(a, 7u32) != ok { os.exit(4i32) }
    say("tray removed\n")
    ret ok
}
