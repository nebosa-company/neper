// `e.os`'s file locks, with the contention real rather than described.
//
// Two separate opens of one path are two separate claims on both hosts -- a lock belongs to the
// open, not to the process -- so one process is enough to make a lock actually block, which is
// what makes this testable without a second program.
//
// Every path is relative, so the runner's working directory decides where this lands.

use e.mem
use e.os

fn open_shared(a: *mem.Arena, path: str) -> (os.File, err) {
    var flags: os.OpenFlags = zero
    flags.read = true
    flags.write = true
    let (file, open_error) = os.open(a, path, flags)
    ret (file, open_error)
}

fn main(a: *mem.Arena) -> err {
    let stale = os.remove_file(a, "np-lock.bin")
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    let (made, made_error) = os.open(a, "np-lock.bin", flags)
    if made_error != ok { os.exit(10i32) }
    var payload: [4]u8 = zero
    let (written, write_error) = os.write(made, payload[..])
    if write_error != ok { os.exit(11i32) }
    if os.close(made) != ok { os.exit(12i32) }

    let (first, first_error) = open_shared(a, "np-lock.bin")
    if first_error != ok { os.exit(13i32) }
    let (second, second_error) = open_shared(a, "np-lock.bin")
    if second_error != ok { os.exit(14i32) }

    // --- Exclusive, and the contention that proves it is one.
    let (held, held_error) = os.file_lock(first, true, 0i64)
    if held_error != ok { os.exit(20i32) }

    // A zero timeout asked for one attempt, so it says `WouldBlock` rather than waiting.
    let (blocked, blocked_error) = os.file_lock(second, true, 0i64)
    if blocked_error != os.WouldBlock { os.exit(21i32) }

    // A deadline that runs out is a different answer from one attempt failing, and it must
    // actually have waited: the clock is what says the poll ran rather than returning at once.
    let (before, before_error) = os.clock(.Monotonic)
    if before_error != ok { os.exit(22i32) }
    let (timed, timed_error) = os.file_lock(second, true, 60000000i64)
    if timed_error != os.Timeout { os.exit(23i32) }
    let (after, after_error) = os.clock(.Monotonic)
    if after_error != ok { os.exit(24i32) }
    if after - before < 40000000i64 { os.exit(25i32) }

    // Released, and now the other claim can have it -- which is what says the unlock did
    // something rather than the lock never having been held.
    if os.file_unlock(held) != ok { os.exit(26i32) }
    let (taken, taken_error) = os.file_lock(second, true, 0i64)
    if taken_error != ok { os.exit(27i32) }
    if os.file_unlock(taken) != ok { os.exit(28i32) }

    // --- Shared locks do not exclude each other, which is the whole difference.
    let (shared_first, shared_first_error) = os.file_lock(first, false, 0i64)
    if shared_first_error != ok { os.exit(30i32) }
    let (shared_second, shared_second_error) = os.file_lock(second, false, 0i64)
    if shared_second_error != ok { os.exit(31i32) }
    if os.file_unlock(shared_first) != ok { os.exit(32i32) }
    if os.file_unlock(shared_second) != ok { os.exit(33i32) }

    // And an exclusive claim is refused while a shared one stands.
    let (reader, reader_error) = os.file_lock(first, false, 0i64)
    if reader_error != ok { os.exit(40i32) }
    let (writer, writer_error) = os.file_lock(second, true, 0i64)
    if writer_error != os.WouldBlock { os.exit(41i32) }
    if os.file_unlock(reader) != ok { os.exit(42i32) }

    if os.close(second) != ok { os.exit(50i32) }
    if os.close(first) != ok { os.exit(51i32) }
    if os.remove_file(a, "np-lock.bin") != ok { os.exit(52i32) }
    ret ok
}
