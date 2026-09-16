use e.mem
use e.os

// Every `e.os` handle is a resource owed to its closer (D350): a directory opened
// and not closed at an exit is E-SAFETY-0002, as a file is.
fn main(a: *mem.Arena, args: []str) -> err {
    let dir = try os.dir_open(a, ".")
    try os.remove_at(a, dir, "np-absent", false)
    ret os.dir_close(dir)
}
