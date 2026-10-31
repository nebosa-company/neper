// A threaded wasm32-wasi regression for thread-stack reservation arithmetic (D5673).
// Run it with NEPER_WASM_MAX_PAGES=initial: reservations do not grow memory, but a
// fresh 64 KiB stack cannot grow it. A failed create must leave the next reservation
// at the same address, and a near-4 GiB stack must answer Failed before it rounds.
use e.mem
use e.os
use e.thread

error Failed

type State = struct {}

fn nothing(state: *State) {}

fn must_fail(state: *State, stack: usize) -> err {
    let (created, create_error) = thread.spawn[State](nothing, state, stack)
    if create_error != ok {
        if create_error == os.Failed { ret ok }
        ret Failed
    }
    let join_error = thread.join(created)
    if join_error != ok { ret Failed }
    ret Failed
}

fn main(a: *mem.Arena) -> err {
    when target.os != .Wasi { ret ok }
    var state: State = zero
    // `MEMORY_END` used to pass the pre-check then overflow while adding the record and alignment.
    try must_fail(&state, 4294901760usize)

    let (before, before_error) = os.reserve(65536usize)
    if before_error != ok { ret before_error }
    try os.release(before, 65536usize)

    try must_fail(&state, 65536usize)
    let (after, after_error) = os.reserve(65536usize)
    if after_error != ok { ret after_error }
    let release_error = os.release(after, 65536usize)
    if release_error != ok { ret release_error }
    if mem.address_of(before) != mem.address_of(after) { ret Failed }
    ret ok
}
