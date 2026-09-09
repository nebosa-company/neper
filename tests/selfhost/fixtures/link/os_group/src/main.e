// `e.os`'s `spawn_with_options` and its process groups.
//
// Every check needs a second program, and the only one this fixture can be sure exists is
// itself: it spawns its own image with a marker argument and each mode answers by its exit
// code. The blocking mode has a timeout so that a group terminate which failed leaves nothing
// behind -- a test that leaks a running child is worse than one that fails.
//
// What a group promises is containment of descendants, which cannot be checked from outside
// without a grandchild whose identity the parent has no way to learn. What is checked here is
// that the group exists before the spawn returns and that terminating it ends the child.

use e.mem
use e.os
use e.atomic

// Long enough that the parent has terminated it well before, short enough that nothing is left
// running if the parent never does.
const CHILD_PATIENCE: i64 = 30000000000i64

// `Atomic[T]` stands as a field rather than as a bare local, which is the shape
// `link/os_futex` already uses.
type Blocker = struct { flag: Atomic[u32] }

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn has_argument(a: *mem.Arena, marker: str) -> bool {
    let (arguments, arguments_error) = os.args(a)
    if arguments_error != ok { ret false }
    var at = 0usize
    while at < arguments.len {
        if same(arguments[at], marker) { ret true }
        at += 1usize
    }
    ret false
}

fn ends_with(text: str, tail: str) -> bool {
    if text.len < tail.len { ret false }
    ret same(text[text.len - tail.len..text.len], tail)
}

fn child_argv(a: *mem.Arena, image: str, marker: str) -> ([]str, err) {
    let (argv, argv_error) = mem.alloc[str](a, 2usize)
    if argv_error != ok { ret (argv, argv_error) }
    argv[0usize] = image
    argv[1usize] = marker
    ret (argv, ok)
}

// The three streams a child is given, which here are this process's own.
fn child_streams() -> os.Stdio {
    var streams: os.Stdio = zero
    streams.stdin = os.stdin()
    streams.stdout = os.stdout()
    streams.stderr = os.stderr()
    ret streams
}

fn run_child(a: *mem.Arena) -> bool {
    // --- Inheriting with an addition: the marker is there and the parent's `PATH` survived.
    if has_argument(a, "np-overlay-child") {
        let (mark, mark_error) = os.env(a, "NP_SPAWN_MARK")
        if mark_error != ok { os.exit(60i32) }
        if !same(mark, "set") { os.exit(61i32) }
        let (inherited, inherited_error) = os.env(a, "PATH")
        if inherited_error != ok { os.exit(62i32) }
        if inherited.len == 0usize { os.exit(63i32) }
        os.exit(0i32)
    }
    // --- An addition that names an inherited record replaces it rather than joining it. If the
    // parent's record were still in the block the host would answer with that one.
    if has_argument(a, "np-replace-child") {
        let (replaced, replaced_error) = os.env(a, "PATH")
        if replaced_error != ok { os.exit(64i32) }
        if !same(replaced, "np-replaced") { os.exit(65i32) }
        os.exit(0i32)
    }
    // --- Not inheriting: the entries given are the whole environment, so nothing else is there.
    if has_argument(a, "np-bare-child") {
        let (mark, mark_error) = os.env(a, "NP_SPAWN_MARK")
        if mark_error != ok { os.exit(66i32) }
        if !same(mark, "set") { os.exit(67i32) }
        let (absent, absent_error) = os.env(a, "PATH")
        if absent_error != os.NotFound { os.exit(68i32) }
        os.exit(0i32)
    }
    // --- `cwd` is where the child starts, which it can only confirm by asking.
    if has_argument(a, "np-cwd-child") {
        let (here, here_error) = os.current_dir(a)
        if here_error != ok { os.exit(69i32) }
        if !ends_with(here, "np-group-cwd") { os.exit(70i32) }
        os.exit(0i32)
    }
    // --- Still running when the group is terminated. Waiting on a flag nothing will ever set
    // is how it blocks without a sleep of its own.
    if has_argument(a, "np-block-child") {
        var blocker: Blocker = zero
        let ignored = os.wait_u32(&blocker.flag, 0u32, CHILD_PATIENCE)
        os.exit(0i32)
    }
    ret false
}

fn main(a: *mem.Arena) -> err {
    if run_child(a) { ret ok }

    let (image, image_error) = os.executable_path(a)
    if image_error != ok { os.exit(10i32) }

    // --- `spawn_with_options`, inheriting with one entry laid over the parent's environment.
    let (overlay_argv, overlay_argv_error) = child_argv(a, image, "np-overlay-child")
    if overlay_argv_error != ok { os.exit(11i32) }
    var overlay_env: [1]str = zero
    overlay_env[0usize] = "NP_SPAWN_MARK=set"
    var overlay: os.SpawnOptions = zero
    overlay.argv = overlay_argv
    overlay.env = overlay_env[..]
    overlay.inherit_env = true
    overlay.stdio = child_streams()
    let (overlay_child, overlay_error) = os.spawn_with_options(a, overlay)
    if overlay_error != ok { os.exit(12i32) }
    let (overlay_status, overlay_wait_error) = os.wait(overlay_child)
    if overlay_wait_error != ok { os.exit(13i32) }
    if overlay_status != 0i32 { os.exit(14i32 + overlay_status) }

    // --- The same, with the entry naming something the parent already sets.
    let (replace_argv, replace_argv_error) = child_argv(a, image, "np-replace-child")
    if replace_argv_error != ok { os.exit(15i32) }
    var replace_env: [1]str = zero
    replace_env[0usize] = "PATH=np-replaced"
    var replace: os.SpawnOptions = zero
    replace.argv = replace_argv
    replace.env = replace_env[..]
    replace.inherit_env = true
    replace.stdio = child_streams()
    let (replace_child, replace_error) = os.spawn_with_options(a, replace)
    if replace_error != ok { os.exit(16i32) }
    let (replace_status, replace_wait_error) = os.wait(replace_child)
    if replace_wait_error != ok { os.exit(17i32) }
    if replace_status != 0i32 { os.exit(18i32 + replace_status) }

    // --- Not inheriting.
    let (bare_argv, bare_argv_error) = child_argv(a, image, "np-bare-child")
    if bare_argv_error != ok { os.exit(19i32) }
    var bare_env: [1]str = zero
    bare_env[0usize] = "NP_SPAWN_MARK=set"
    var bare: os.SpawnOptions = zero
    bare.argv = bare_argv
    bare.env = bare_env[..]
    bare.inherit_env = false
    bare.stdio = child_streams()
    let (bare_child, bare_error) = os.spawn_with_options(a, bare)
    if bare_error != ok { os.exit(20i32) }
    let (bare_status, bare_wait_error) = os.wait(bare_child)
    if bare_wait_error != ok { os.exit(21i32) }
    if bare_status != 0i32 { os.exit(22i32 + bare_status) }

    // --- A working directory the child confirms from the inside.
    let stale = os.remove_dir(a, "np-group-cwd")
    if os.mkdir(a, "np-group-cwd") != ok { os.exit(23i32) }
    let (cwd_argv, cwd_argv_error) = child_argv(a, image, "np-cwd-child")
    if cwd_argv_error != ok { os.exit(24i32) }
    var moved: os.SpawnOptions = zero
    moved.argv = cwd_argv
    moved.inherit_env = true
    moved.cwd = "np-group-cwd"
    moved.stdio = child_streams()
    let (moved_child, moved_error) = os.spawn_with_options(a, moved)
    if moved_error != ok { os.exit(25i32) }
    let (moved_status, moved_wait_error) = os.wait(moved_child)
    if moved_wait_error != ok { os.exit(26i32) }
    if moved_status != 0i32 { os.exit(27i32 + moved_status) }
    if os.remove_dir(a, "np-group-cwd") != ok { os.exit(28i32) }

    // --- A group, and the child in it ended by terminating the group rather than the child.
    let (group_argv, group_argv_error) = child_argv(a, image, "np-block-child")
    if group_argv_error != ok { os.exit(30i32) }
    var contained: os.SpawnOptions = zero
    contained.argv = group_argv
    contained.inherit_env = true
    contained.stdio = child_streams()
    let (group, group_child, group_error) = os.proc_group_spawn(a, contained)
    if group_error != ok { os.exit(31i32) }
    if os.proc_group_terminate(group, false) != ok { os.exit(32i32) }
    // The status is a failure on both hosts but not the same number: one reports the signal it
    // died of and the other the code the terminate was given, so only "not zero" is portable.
    let (group_status, group_wait_error) = os.wait(group_child)
    if group_wait_error != ok { os.exit(33i32) }
    if group_status == 0i32 { os.exit(34i32) }
    if os.proc_group_close(group) != ok { os.exit(35i32) }
    ret ok
}
