use e.mem
use e.os

const FIRST: usize = 1usize

// A comptime lower-bound slice maps index zero to the owner's shifted slot.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [2]os.File = zero
    files[1usize] = try os.dup(os.stdout())
    let tail = files[FIRST..]
    let again = tail
    ret os.close(again[0usize])
}
