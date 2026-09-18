use e.mem
use e.os

const SLOT: usize = 1usize + 0usize

// A comptime expression names the same independently tracked slot on store and move.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [2]os.File = zero
    files[SLOT] = try os.dup(os.stdout())
    ret os.close(files[SLOT])
}
