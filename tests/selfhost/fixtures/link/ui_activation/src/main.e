// `e.ui.app`'s activation and associations (D897, widget plan P4-08): a command
// line reads as a launch, a file or a URL on every host; where the host keeps
// associations a file type and a protocol are registered and removed for this
// user; startup registration is set, seen and cleared; a single instance is the
// first of its id. A host without a service says so through the predicates.

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
    let (exe, exe_error) = fs.executable_path(a)
    if exe_error != ok { os.exit(1i32) }
    // The command line, three ways.
    var launch: [1]str = zero
    launch[0usize] = exe
    if app.activation(a, launch[..]).kind != .Launch { os.exit(2i32) }
    var by_url: [2]str = zero
    by_url[0usize] = exe
    by_url[1usize] = "neper-test:open/1"
    let url = app.activation(a, by_url[..])
    if url.kind != .Url || !same(url.payload, "neper-test:open/1") || url.args.len != 2usize { os.exit(3i32) }
    var by_file: [2]str = zero
    by_file[0usize] = exe
    by_file[1usize] = exe
    if app.activation(a, by_file[..]).kind != .File { os.exit(4i32) }
    var by_word: [2]str = zero
    by_word[0usize] = exe
    by_word[1usize] = "--verbose"
    if app.activation(a, by_word[..]).kind != .Launch { os.exit(5i32) }
    // Associations, for this user, and gone again.
    if app.register_file_type(a, "neper-test", "neper.Test", "Neper test") != shell.Invalid || app.register_protocol(a, "bad/scheme", "") != shell.Invalid { os.exit(6i32) }
    if app.associations_supported() {
        if app.register_file_type(a, ".neper-test", "neper.Test", "Neper test document") != ok { os.exit(7i32) }
        if app.unregister_file_type(a, ".neper-test", "neper.Test") != ok { os.exit(8i32) }
        if app.unregister_file_type(a, ".neper-test", "neper.Test") != shell.NotFound { os.exit(9i32) }
        if app.register_protocol(a, "neper-test", "Neper test links") != ok { os.exit(10i32) }
        if app.unregister_protocol(a, "neper-test") != ok { os.exit(11i32) }
        if app.unregister_protocol(a, "neper-test") != shell.NotFound { os.exit(12i32) }
    } else {
        if app.register_file_type(a, ".neper-test", "neper.Test", "Neper test document") != shell.Unsupported || app.register_protocol(a, "neper-test", "") != shell.Unsupported { os.exit(13i32) }
    }
    // Startup, set and cleared.
    if app.startup_supported() {
        if app.startup_registration(a, "neper-test-fixture", true) != ok { os.exit(14i32) }
        let (registered, registered_error) = app.startup_registered(a, "neper-test-fixture")
        if registered_error != ok || !registered { os.exit(15i32) }
        if app.startup_registration(a, "neper-test-fixture", false) != ok { os.exit(16i32) }
        let (still, still_error) = app.startup_registered(a, "neper-test-fixture")
        if still_error != ok || still { os.exit(17i32) }
        if app.startup_registration(a, "neper-test-fixture", false) != ok { os.exit(18i32) }
    } else {
        if app.startup_registration(a, "neper-test-fixture", true) != shell.Unsupported { os.exit(19i32) }
    }
    // A single instance: this process is the first of its id.
    let (storage_bytes, storage_error) = mem.alloc[u8](a, 65536usize)
    if storage_error != ok { os.exit(20i32) }
    var storage = mem.arena_from(storage_bytes)
    let (first, instance_error) = app.single_instance(a, "neper-test-fixture", launch[..], &storage)
    if app.single_instance_supported() {
        if instance_error != ok || !first { os.exit(21i32) }
        let (again, again_error) = app.single_instance(a, "neper-test-fixture", launch[..], &storage)
        if again_error != ok || !again { os.exit(22i32) }
    } else {
        if instance_error != shell.Unsupported { os.exit(23i32) }
    }
    let (none, any) = app.activation_poll()
    if any { os.exit(24i32) }
    try io.print("ui activation ok\n")
    ret ok
}
