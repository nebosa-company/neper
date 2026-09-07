// A flushing builder over a stack arena, which is the shape `printf` expands to: the
// buffer is a local, the sink drains it, and output longer than the buffer works.
// The drain is on arena exhaustion, not on filling the initial reservation -- the
// reservation grows by doubling while the arena has room -- so the arena is the
// buffer, and this pushes several times its size through it.

use e.mem
use e.os
use e.str

error Failed

type Counter = struct {
    total: usize,
    calls: usize,
}

fn count_bytes(ctx: *void, bytes: []const u8) -> err {
    var counter = mem.cast[*Counter](ctx)
    counter.total += bytes.len
    counter.calls += 1usize
    ret ok
}

fn main(a: *mem.Arena) -> err {
    var counter: Counter = zero
    var buf: [4096]u8 = zero
    var scratch = mem.arena_from(buf[..])
    let sink = str.Sink { ctx: mem.cast[*void](&counter), write: count_bytes }
    let (b, builder_error) = str.builder_to(&scratch, 64usize, sink)
    if builder_error != ok { ret builder_error }
    var b2 = b
    var at = 0usize
    while at < 1000usize {
        let push_error = str.push(&b2, "0123456789")
        if push_error != ok { ret push_error }
        at += 1usize
    }
    let tail = str.done(&b2)
    // What `done` leaves is only the unflushed remainder, so it is shorter than
    // everything pushed -- which is what says the drain happened during the pushes
    // and not in one buffered write at the end.
    if tail.len >= 10000usize { ret Failed }
    let drains = counter.calls
    if drains == 0usize { ret Failed }
    let sink_error = count_bytes(mem.cast[*void](&counter), tail)
    if sink_error != ok { ret sink_error }
    // 10000 bytes through a 4096-byte arena: every byte arrives exactly once.
    if counter.total != 10000usize { ret Failed }
    ret ok
}
