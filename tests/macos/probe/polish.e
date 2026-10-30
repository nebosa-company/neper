// The Dock tile with an overlay drawn over the lower right of the program's icon (screenshot at 3 s), then a drag of two files
// and an image out of a window, ended by a posted mouse up: it must answer Cancelled.
use e.mem
use e.os
use e.os.shell

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena) -> err {
    if os.cocoa_start() != ok { os.exit(2i32) }
    var pixels: [1024]u32 = zero
    var i = 0usize
    while i < 1024usize {
        pixels[i] = 4294901760u32
        if i / 32usize > 8usize && i / 32usize < 24usize && i % 32usize > 8usize && i % 32usize < 24usize { pixels[i] = 4294967295u32 }
        i += 1usize
    }
    let icon = shell.Icon { width: 32u32, height: 32u32, pixels: pixels[..] }
    var nowhere: os.Window = zero
    if shell.taskbar_overlay(a, nowhere, icon, "overlay") != ok { os.exit(3i32) }
    var spins = 0usize
    while spins < 45usize {
        os.cocoa_pump(100000000i64)
        spins += 1usize
    }
    say("overlay shown\n")
    // A second overlay replaces the first, then the system's icon is back.
    if shell.taskbar_overlay(a, nowhere, icon, "again") != ok { os.exit(4i32) }
    let none = shell.Icon { width: 0u32, height: 0u32, pixels: pixels[..] }
    if shell.taskbar_overlay(a, nowhere, none, "") != ok { os.exit(5i32) }
    say("overlay cleared\n")
    var options: os.WindowOptions = zero
    options.title = "Neper: drag out"
    options.width = 300u32
    options.height = 200u32
    options.visible = true
    let (window, open_error) = os.window_open(a, options)
    if open_error != ok { os.exit(6i32) }
    var paths: [2]str = zero
    paths[0usize] = "/tmp"
    paths[1usize] = "/etc/hosts"
    var items: [2]shell.Content = zero
    items[0usize] = shell.Content { kind: .Files, mime: "", text: "", paths: paths[..], image: zero, bytes: zero }
    items[1usize] = shell.Content { kind: .Image, mime: "", text: "", paths: zero, image: icon, bytes: zero }
    if shell.drag_cancel_after(2.0f64) != ok { os.exit(7i32) }
    let (result, drag_error) = shell.drag_start(a, items[..], false)
    if drag_error != ok { os.exit(8i32) }
    if result != .Cancelled { os.exit(9i32) }
    say("drag out ok\n")
    ret ok
}
