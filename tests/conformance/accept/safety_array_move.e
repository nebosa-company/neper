use e.mem
use e.os

// A whole-array move carries every slot's state and diagnostic provenance.
fn main(a: *mem.Arena, args: []str) -> err {
    var source: [2]os.File = zero
    source[1usize] = try os.dup(os.stdout())
    let destination = source
    ret os.close(destination[1usize])
}
