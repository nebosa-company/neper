// A placement reads before it writes (D919, H03): the cast makes a `*State` of bytes
// that were never a `State`, and its first mention reads `ready` -- whatever byte
// the storage held -- before `*placed = written` chooses every one. Only a whole
// write as the next mention makes the bytes the program's.
use e.mem

type State = struct { ready: bool, count: u32 }

fn main() -> i32 {
    var storage: [8]u8 = zero
    let placed = mem.cast[*State](&storage[0])
    if placed.ready { ret 1i32 }
    let written = State { ready: true, count: 2u32 }
    *placed = written
    ret 0i32
}
