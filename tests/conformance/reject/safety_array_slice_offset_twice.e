use e.mem
use e.os

const FIRST: usize = 1usize

// The shifted slice and array spelling still name one ownership slot.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [2]os.File = zero
    files[1usize] = try os.dup(os.stdout())
    let tail = files[FIRST..]
    try os.close(tail[0usize])
    ret os.close(files[1usize])
}
