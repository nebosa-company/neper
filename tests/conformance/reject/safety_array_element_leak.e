use e.mem
use e.os

// A resource stored in a literal-indexed array slot is still owed at scope exit.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [1]os.File = zero
    files[0usize] = try os.dup(os.stdout())
    ret ok
}
