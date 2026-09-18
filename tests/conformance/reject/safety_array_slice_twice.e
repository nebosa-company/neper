use e.mem
use e.os

// A full-slice alias and its array owner cannot consume the same slot twice.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [1]os.File = zero
    files[0usize] = try os.dup(os.stdout())
    let view = files[..]
    try os.close(view[0usize])
    ret os.close(files[0usize])
}
