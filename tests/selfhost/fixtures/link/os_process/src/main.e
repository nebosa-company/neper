// `e.os`'s pipe, page size, reservation release, `file_handle` and `kill`.
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

fn main(a: *mem.Arena) -> err {
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
    // `os.stdin` is in the fence and is not seeded, so it cannot be named here. The child
    // never reads, so its input is left as it comes.
    var streams: os.Stdio = zero
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
    ret ok
}
