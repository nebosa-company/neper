// `e.ui.app`'s file and document access (D895, widget plan P4-07): a grant is the
// path on a desktop host, a dialog with too many filters is refused before the
// host is asked, and the recent list takes an existing file and refuses a missing
// one where the host keeps one. No dialog is shown in the suite -- a dialog waits
// for a person -- and a host without them says so through the predicates.

use e.fs
use e.io
use e.mem
use e.os
use e.os.shell
use e.ui.app

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let grant = app.grant_of("D:/neper/document.txt")
    if !same(app.grant_path(grant), "D:/neper/document.txt") { os.exit(1i32) }
    var too_many: [17]shell.FileFilter = zero
    var at = 0usize
    while at < 17usize {
        too_many[at] = shell.FileFilter { label: "Everything", pattern: "*.*" }
        at += 1usize
    }
    var nobody: *app.App = zero
    let crowded = app.FileDialogOptions { title: "neper", filters: too_many[..], initial: "", default_extension: "" }
    let (no_grants, crowded_error) = app.open_file(a, nobody, crowded, false)
    if crowded_error != shell.Invalid { os.exit(2i32) }
    let (no_grant, crowded_save_error) = app.save_file(a, nobody, crowded)
    if crowded_save_error != shell.Invalid { os.exit(3i32) }
    let plain = app.FileDialogOptions { title: "neper", filters: zero, initial: "", default_extension: "" }
    if !app.file_dialogs_supported() {
        let (none, open_error) = app.open_file(a, nobody, plain, true)
        if open_error != shell.Unsupported { os.exit(4i32) }
        let (no_folder, folder_error) = app.pick_folder(a, nobody, plain)
        if folder_error != shell.Unsupported { os.exit(5i32) }
    }
    let (exe, exe_error) = fs.executable_path(a)
    if exe_error != ok { os.exit(6i32) }
    if app.recent_documents_supported() {
        if app.recent_add(a, app.grant_of("no/such/neper-document")) != shell.NotFound { os.exit(7i32) }
        if app.recent_add(a, app.grant_of("")) != shell.Invalid { os.exit(8i32) }
    } else {
        if app.recent_add(a, app.grant_of(exe)) != shell.Unsupported { os.exit(9i32) }
        if app.recent_add(a, app.grant_of("")) != shell.Invalid { os.exit(10i32) }
    }
    try io.print("ui file access ok\n")
    ret ok
}
