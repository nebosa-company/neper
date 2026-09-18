use e.mem
use e.os

// A full-slice alias reaches the fixed array's ownership slot.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [1]os.File = zero
    files[0usize] = try os.dup(os.stdout())
    let view = files[..]
    let again = view
    ret os.close(again[0usize])
}
