// `e.os.shell` (D885, widget plan native-shell-api): the capability record is honest
// per host, an empty or missing argument is refused before the host is asked, a host
// with a tray adds, updates and removes one and answers a zero menu id `Invalid`, a
// host without one answers `Unsupported` for both, and where the runner points the
// trash home at scratch (Linux, `NEPER_SHELL_TRASH_HOME`) a file goes to the trash
// with its info file beside it and a second of the same name gets a counter.

use e.fs
use e.io
use e.mem
use e.os
use e.os.shell

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn contains(haystack: str, needle: str) -> bool {
    if needle.len > haystack.len { ret false }
    var at = 0usize
    while at + needle.len <= haystack.len {
        if same(haystack[at..at + needle.len], needle) { ret true }
        at += 1usize
    }
    ret false
}

fn joined(a: *mem.Arena, x: str, y: str) -> str {
    let (bytes, allocation_error) = mem.alloc[u8](a, x.len + y.len)
    if allocation_error != ok { os.exit(30i32) }
    var at = 0usize
    while at < x.len {
        bytes[at] = x[at]
        at += 1usize
    }
    var i = 0usize
    while i < y.len {
        bytes[at + i] = y[i]
        i += 1usize
    }
    ret bytes[0usize..x.len + y.len]
}

fn present(a: *mem.Arena, path: str) -> bool {
    let (found, exists_error) = fs.exists(a, path)
    if exists_error != ok { os.exit(31i32) }
    ret found
}

fn main(a: *mem.Arena, args: []str) -> err {
    let caps = shell.capabilities()
    if !caps.open_uri || !caps.reveal || !caps.trash || caps.tray != caps.popup_menu { os.exit(1i32) }
    if shell.open_uri(a, "") != shell.Invalid || shell.reveal(a, "") != shell.Invalid || shell.trash(a, "") != shell.Invalid { os.exit(2i32) }
    if shell.reveal(a, "no/such/neper-shell-item") != shell.NotFound || shell.trash(a, "no/such/neper-shell-item") != shell.NotFound { os.exit(3i32) }
    var items: [2]shell.MenuItem = zero
    items[0usize] = shell.MenuItem { id: 0u32, label: "Nameless", enabled: true, checked: false, separator: false }
    items[1usize] = shell.MenuItem { id: 0u32, label: "", enabled: true, checked: false, separator: true }
    var pixels: [256]u32 = zero
    var i = 0usize
    while i < 256usize {
        pixels[i] = 4281624268u32
        i += 1usize
    }
    let icon = shell.Icon { width: 16u32, height: 16u32, pixels: pixels[..] }
    let empty = shell.Icon { width: 0u32, height: 0u32, pixels: pixels[..] }
    if caps.tray {
        let (chosen, has_chosen, menu_error) = shell.popup_menu(a, items[..], 0i32, 0i32)
        if menu_error != shell.Invalid || has_chosen { os.exit(4i32) }
        if shell.tray_add(a, 7u32, icon, "neper") != ok { os.exit(5i32) }
        let (event, has_event) = shell.tray_poll()
        if has_event { os.exit(6i32) }
        if shell.tray_update(a, 7u32, icon, "neper, still") != ok { os.exit(7i32) }
        if shell.tray_add(a, 7u32, icon, "twice") != shell.Invalid { os.exit(8i32) }
        if shell.tray_add(a, 8u32, empty, "empty") != shell.Invalid { os.exit(9i32) }
        if shell.tray_remove(a, 7u32) != ok { os.exit(10i32) }
        if shell.tray_remove(a, 7u32) != shell.NotFound { os.exit(11i32) }
    } else {
        let (chosen, has_chosen, menu_error) = shell.popup_menu(a, items[..], 0i32, 0i32)
        if menu_error != shell.Unsupported || has_chosen { os.exit(4i32) }
        if shell.tray_add(a, 7u32, icon, "neper") != shell.Unsupported { os.exit(5i32) }
        let (event, has_event) = shell.tray_poll()
        if has_event { os.exit(6i32) }
        if shell.tray_update(a, 7u32, icon, "neper") != shell.Unsupported || shell.tray_remove(a, 7u32) != shell.Unsupported { os.exit(7i32) }
    }
    let (scratch, has_scratch) = fs.env_directory(a, "NEPER_SHELL_TRASH_HOME")
    if has_scratch {
        let victim = joined(a, scratch, "/victim.txt")
        if fs.write_file(a, victim, "gone") != ok { os.exit(12i32) }
        if shell.trash(a, victim) != ok { os.exit(13i32) }
        if present(a, victim) || !present(a, joined(a, scratch, "/Trash/files/victim.txt")) { os.exit(14i32) }
        let (info, read_error) = fs.read_file(a, joined(a, scratch, "/Trash/info/victim.txt.trashinfo"), 4096usize)
        if read_error != ok { os.exit(15i32) }
        if !contains(info, "[Trash Info]\nPath=") || !contains(info, "/victim.txt\nDeletionDate=") || !contains(info, "T") { os.exit(16i32) }
        if fs.write_file(a, victim, "gone again") != ok { os.exit(17i32) }
        if shell.trash(a, victim) != ok { os.exit(18i32) }
        if !present(a, joined(a, scratch, "/Trash/files/victim.txt.1")) || !present(a, joined(a, scratch, "/Trash/info/victim.txt.1.trashinfo")) { os.exit(19i32) }
    }
    try io.print("os shell ok\n")
    ret ok
}
