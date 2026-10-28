// A failed `e.async.init` has no result that can own its allocations, so the
// caller's arena must be at its entry mark. Sixteen bytes fit the private loop
// state but leave insufficient room for the platform poller setup.
use e.async
use e.mem
use e.os

const TINY_CAPACITY: usize = 16usize

fn main(a: *mem.Arena) -> err {
    var storage: [TINY_CAPACITY]u8 = zero
    var tiny = mem.arena_from(storage[..])
    let entry = mem.mark(&tiny)
    let (loop, init_error) = async.init(&tiny)
    if init_error == ok {
        // The capacity is deliberately too small. Keep this branch leak-free
        // if a future platform changes its poller representation.
        var opened = loop
        if async.close(&opened) != ok { os.exit(12i32) }
        os.exit(10i32)
    }
    if mem.mark(&tiny) != entry { os.exit(11i32) }

    // A rollback on the failed constructor must not poison the ordinary open/close path.
    let (normal_loop, normal_error) = async.init(a)
    if normal_error == async.Unsupported { ret ok }
    if normal_error != ok { os.exit(20i32) }
    var normal = normal_loop
    if async.close(&normal) != ok { os.exit(21i32) }
    ret ok
}
