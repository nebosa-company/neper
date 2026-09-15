// `e.os`'s pipe, page size, reservation release, the standard streams, `file_handle`
// and `kill`.
//
// `kill` needs a child, and the only program this fixture can be sure exists is itself: it
// spawns its own image with an argument, and the child blocks until it is killed. The block
// has a timeout so that a `kill` which failed leaves no process behind -- a test that leaks a
// running child is worse than one that fails.

use e.mem
use e.os
use e.atomic

// Long enough that the parent has killed it well before, short enough that nothing is left
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

fn is_child(a: *mem.Arena) -> bool {
    let (arguments, arguments_error) = os.args(a)
    if arguments_error != ok { ret false }
    var at = 0usize
    while at < arguments.len {
        if same(arguments[at], "np-child") { ret true }
        at += 1usize
    }
    ret false
}

fn says(a: *mem.Arena) -> bool {
    let (arguments, arguments_error) = os.args(a)
    if arguments_error != ok { ret false }
    var at = 0usize
    while at < arguments.len {
        if same(arguments[at], "np-say") { ret true }
        at += 1usize
    }
    ret false
}

fn main(a: *mem.Arena) -> err {
    // The other child: it says one word on its stdout and leaves, which is how the parent can
    // tell whether a stream it handed over arrived.
    if says(a) {
        let (_, said_error) = os.write(os.stdout(), "said")
        os.exit(0i32)
    }
    // The child's whole job is to still be running when the parent kills it. Waiting on a flag
    // nothing will ever set is how it blocks without a sleep of its own.
    if is_child(a) {
        var blocker: Blocker = zero
        let ignored = os.wait_u32(&blocker.flag, 0u32, CHILD_PATIENCE)
        os.exit(0i32)
    }

    // --- The page size, which every other answer here is measured in.
    let size = os.page_size()
    if size == 0usize { os.exit(10i32) }
    if size < 4096usize { os.exit(11i32) }
    // A power of two: anything else is not a page size, and a zeroed struct read at the wrong
    // offset would not be one.
    if size & (size - 1usize) != 0usize { os.exit(12i32) }

    // --- A reservation, given back. What says the release did something is that the range
    // can no longer be committed: releasing twice would not, because one host lets an unmapped
    // range be unmapped again and reports success.
    let (reserved, reserve_error) = os.reserve(size * 4usize)
    if reserve_error != ok { os.exit(20i32) }
    if os.commit(reserved, size) != ok { os.exit(21i32) }
    if os.release(reserved, size * 4usize) != ok { os.exit(22i32) }
    if os.commit(reserved, size) == ok { os.exit(23i32) }

    // --- The three standard streams, which are three different things. Comparing them is what
    // catches a wrong constant: `stdin` asked for with `stdout`'s number answers with `stdout`,
    // and every read from it would then be a read of the wrong stream.
    if os.file_handle(os.stdin()).raw == os.file_handle(os.stdout()).raw { os.exit(25i32) }
    if os.file_handle(os.stdin()).raw == os.file_handle(os.stderr()).raw { os.exit(26i32) }

    // --- A pipe, written at one end and read at the other.
    let (reading, writing, pipe_error) = os.pipe()
    if pipe_error != ok { os.exit(30i32) }
    var message: [5]u8 = zero
    message[0usize] = 112u8
    message[1usize] = 105u8
    message[2usize] = 112u8
    message[3usize] = 101u8
    message[4usize] = 100u8
    let (sent, send_error) = os.write(writing, message[..])
    if send_error != ok { os.exit(31i32) }
    if sent != 5usize { os.exit(32i32) }
    var received: [16]u8 = zero
    let (taken, take_error) = os.read(reading, received[..])
    if take_error != ok { os.exit(33i32) }
    if taken != 5usize { os.exit(34i32) }
    var at = 0usize
    while at < 5usize {
        if received[at] != message[at] { os.exit(35i32) }
        at += 1usize
    }
    // A `File` and a `Socket` reach a poller as a `Handle`, which is the only reason the
    // conversion exists. Two ends of one pipe are two handles, which is what says this answers
    // with the file's own rather than with something constant.
    if os.file_handle(reading).raw == 0usize { os.exit(45i32) }
    if os.file_handle(writing).raw == 0usize { os.exit(46i32) }
    if os.file_handle(reading).raw == os.file_handle(writing).raw { os.exit(47i32) }
    // Closing the writing end is what turns a further read into end of stream rather than a
    // wait -- the property a pipe is used for.
    if os.close(writing) != ok { os.exit(36i32) }
    let (finished, finish_error) = os.read(reading, received[..])
    if finish_error != ok { os.exit(37i32) }
    if finished != 0usize { os.exit(38i32) }
    if os.close(reading) != ok { os.exit(39i32) }

    // --- `kill`, on a child that is this program again.
    let (image, image_error) = os.executable_path(a)
    if image_error != ok { os.exit(40i32) }
    var argv: [2]str = zero
    argv[0usize] = image
    argv[1usize] = "np-child"
    var streams: os.Stdio = zero
    streams.stdin = os.stdin()
    streams.stdout = os.stdout()
    streams.stderr = os.stderr()
    let (child, spawn_error) = os.spawn(a, argv[..], streams)
    if spawn_error != ok { os.exit(41i32) }
    if os.kill(child) != ok { os.exit(42i32) }
    // The status is a failure on both hosts, but not the same number: one reports 128 plus the
    // signal and the other the code the terminate call was given, so only "not zero" is
    // portable.
    let (status, wait_error) = os.wait(child)
    if wait_error != ok { os.exit(43i32) }
    if status == 0i32 { os.exit(44i32) }

    // --- A pipe handed to `spawn_with_options` reaches the child. The `spawn` intrinsic marks
    // its handles inheritable before creating the process and this path did not, so on Windows
    // a pipe given here arrived in the child as nothing and its first write failed.
    let (said_read, said_write, said_pipe_error) = os.pipe()
    if said_pipe_error != ok { os.exit(50i32) }
    var options: os.SpawnOptions = zero
    var said_argv: [2]str = zero
    said_argv[0usize] = image
    said_argv[1usize] = "np-say"
    options.argv = said_argv[..]
    options.inherit_env = true
    options.stdio.stdout = said_write
    let (speaker, speaker_error) = os.spawn_with_options(a, options)
    if speaker_error != ok { os.exit(51i32) }
    if os.close(said_write) != ok { os.exit(52i32) }
    var said: [8]u8 = zero
    var said_len = 0usize
    while said_len < said.len {
        let (count, said_error) = os.read(said_read, said[said_len..])
        if said_error != ok { os.exit(53i32) }
        if count == 0usize { break }
        said_len += count
    }
    if !same(said[0usize..said_len], "said") { os.exit(54i32) }
    if os.close(said_read) != ok { os.exit(55i32) }
    // --- `wait_usage` is `wait` with the child's peak beside the code (D311), and
    // `peak_memory` is this process's own. The child's peak is not checked: Linux counts
    // resident pages lazily and a process as small as `np-say` can read as zero. This one
    // touches a megabyte first, which is past that.
    let (said_usage, said_wait) = os.wait_usage(speaker)
    if said_wait != ok { os.exit(56i32) }
    if said_usage.exit_code != 0i32 { os.exit(57i32) }
    let (touched, touched_error) = mem.alloc[u8](a, 1048576usize)
    if touched_error != ok { os.exit(58i32) }
    var touch_at = 0usize
    while touch_at < touched.len {
        touched[touch_at] = 1u8
        touch_at += size
    }
    let (own_peak, own_peak_error) = os.peak_memory()
    if own_peak_error != ok { os.exit(59i32) }
    if own_peak < touched.len { os.exit(60i32) }
    ret ok
}
