// `e.ui.app`'s shell file operations (D888, widget plan P4-09): the three verbs are
// the shell's own answers -- an empty argument refused, a missing item not found --
// and where the runner points the trash home at scratch (Linux) a file the app
// moves to the trash is gone from where it was.

use e.fs
use e.io
use e.mem
use e.os
use e.os.shell
use e.ui.app

fn joined(a: *mem.Arena, x: str, y: str) -> str {
    let (bytes, allocation_error) = mem.alloc[u8](a, x.len + y.len)
    if allocation_error != ok { os.exit(20i32) }
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

fn main(a: *mem.Arena, args: []str) -> err {
    let caps = app.shell_capabilities()
    if !caps.open_uri || !caps.reveal || !caps.trash { os.exit(1i32) }
    if app.open_uri(a, "") != shell.Invalid || app.reveal_in_file_manager(a, "") != shell.Invalid || app.move_to_trash(a, "") != shell.Invalid { os.exit(2i32) }
    if app.reveal_in_file_manager(a, "no/such/neper-app-item") != shell.NotFound || app.move_to_trash(a, "no/such/neper-app-item") != shell.NotFound { os.exit(3i32) }
    let (scratch, has_scratch) = fs.env_directory(a, "NEPER_SHELL_TRASH_HOME")
    if has_scratch {
        let victim = joined(a, scratch, "/app-victim.txt")
        if fs.write_file(a, victim, "gone") != ok { os.exit(4i32) }
        if app.move_to_trash(a, victim) != ok { os.exit(5i32) }
        let (still, exists_error) = fs.exists(a, victim)
        if exists_error != ok || still { os.exit(6i32) }
        let (kept, kept_error) = fs.exists(a, joined(a, scratch, "/Trash/files/app-victim.txt"))
        if kept_error != ok || !kept { os.exit(7i32) }
    }
    try io.print("ui shell ops ok\n")
    ret ok
}
